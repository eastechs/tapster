#!/usr/bin/env python3
"""Validate existing Textend provisioning; never create credentials or contact Apple."""
import argparse
import datetime
import hashlib
import pathlib
import plistlib
import re
import shutil
import subprocess
import uuid

TEAM = "VK288Z42NG"
BUNDLE = "chat.eastechs.tapster"
CONTAINER = "iCloud.chat.eastechs.tapster"
NAMES = {"development": "Textend CloudKit Development", "release": "Textend CloudKit Developer ID"}


def profile_folders():
    return [pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
            pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles"]


def read_profile(path):
    decoded = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True, check=True)
    return plistlib.loads(decoded.stdout)


def install_profile(source, kind, folders=None):
    """Install an approved profile and retain superseded copies outside Xcode's search path."""
    folders = folders or profile_folders()
    profile = read_profile(source)
    validate_profile(profile, kind)
    if profile.get("Name") != NAMES[kind]:
        raise RuntimeError(f"Expected the '{NAMES[kind]}' profile.")
    identifier = str(uuid.UUID(profile["UUID"]))
    target = folders[0] / (identifier + ".provisionprofile")
    retired = []
    for folder in folders:
        for path in folder.glob("*provision*"):
            if not path.is_file() or path == target or (target.exists() and path.samefile(target)):
                continue
            try:
                existing = read_profile(path)
            except (subprocess.CalledProcessError, ValueError):
                continue
            if existing.get("Name") == NAMES[kind] and existing.get("TeamIdentifier") == [TEAM]:
                retired.append(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".installing")
    try:
        shutil.copyfile(source, temporary)
        temporary.chmod(0o600)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    for old in retired:
        archive = old.parent.parent / "TextendRetiredProfiles"
        archive.mkdir(exist_ok=True)
        old.replace(archive / (str(uuid.uuid4()) + "-" + old.name))
    return target


def validate_profile(profile, kind, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    expiry = profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
    entitlements = profile.get("Entitlements", {})
    expected_environment = "Development" if kind == "development" else "Production"
    environments = entitlements.get("com.apple.developer.icloud-container-environment", [])
    if isinstance(environments, str):
        environments = [environments]
    services = entitlements.get("com.apple.developer.icloud-services", [])
    if (profile.get("TeamIdentifier") != [TEAM]
            or entitlements.get("com.apple.application-identifier") != f"{TEAM}.{BUNDLE}"
            or CONTAINER not in entitlements.get("com.apple.developer.icloud-container-identifiers", [])
            or (services != "*" and "CloudKit" not in services)
            or expected_environment not in environments
            or entitlements.get("com.apple.developer.aps-environment") != ("development" if kind == "development" else "production")
            or expiry <= now):
        raise RuntimeError("Textend provisioning has expired or does not match its team, app, CloudKit container, and environment.")
    if kind == "release" and not profile.get("ProvisionsAllDevices"):
        raise RuntimeError("Release requires a Developer ID profile valid for all devices.")


def resolve_profile(kind):
    folders = profile_folders()
    candidates = {}
    for folder in folders:
        for path in folder.glob("*provision*"):
            decoded = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True)
            if decoded.returncode:
                continue
            profile = plistlib.loads(decoded.stdout)
            if profile.get("Name") == NAMES[kind]:
                candidates[profile["UUID"]] = profile
    if len(candidates) != 1:
        raise RuntimeError(f"Install exactly one current '{NAMES[kind]}' profile from Apple Developer. See docs/icloud-sync.md.")
    profile = next(iter(candidates.values()))
    validate_profile(profile, kind)
    identities = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                                check=True, capture_output=True, text=True).stdout
    prefix = "Apple Development:" if kind == "development" else "Developer ID Application:"
    available = re.findall(r'\) ([A-F0-9]{40}) "(' + re.escape(prefix) + r'[^\"]+)"', identities)
    allowed = {hashlib.sha1(certificate).hexdigest().upper() for certificate in profile["DeveloperCertificates"]}
    matches = [fingerprint for fingerprint, _ in available if fingerprint in allowed]
    if len(matches) != 1:
        raise RuntimeError("Expected one usable local signing identity included in the Textend profile.")
    return profile, matches[0]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=NAMES)
    parser.add_argument("--install", type=pathlib.Path, help="Install a downloaded Textend profile, retaining superseded copies.")
    args = parser.parse_args()
    try:
        if args.install:
            install_profile(args.install, args.kind)
        profile, identity = resolve_profile(args.kind)
        print(f"{profile['UUID']}\t{identity}\t{TEAM}")
    except (RuntimeError, subprocess.CalledProcessError, ValueError, KeyError, OSError) as error:
        parser.exit(1, f"Provisioning: {error}\n")
