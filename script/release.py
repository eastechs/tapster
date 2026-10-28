#!/usr/bin/env python3
"""Build signed Textend releases locally; explicitly publish them to Spaces."""

import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

from provisioning import resolve_profile, validate_profile, CONTAINER

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "build/SourcePackages/artifacts/sparkle/Sparkle/bin"
ACCOUNT = "chat.eastechs.textend"
BUNDLE_ID = "chat.eastechs.tapster"
FEED_URL = "https://cdn.usetextend.com/macos/appcast.xml"
DOWNLOAD_URL = FEED_URL.rsplit("/", 1)[0] + "/"
NS = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
SECRET_NAMES = ("AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "APPLE_APP_SPECIFIC_PASSWORD")


def run(*args, allow_failure=False):
    result = subprocess.run([str(x) for x in args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode and not allow_failure:
        detail = result.stderr or result.stdout
        for name in SECRET_NAMES:
            if value := os.environ.get(name):
                detail = detail.replace(value, "<redacted>")
        raise RuntimeError(f"{Path(str(args[0])).name} failed:\n{detail[-6000:]}")
    return result


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def public_key():
    text = (ROOT / "Config/Updates.xcconfig").read_text()
    key = re.search(r"^TEXTEND_SPARKLE_PUBLIC_KEY = (.+)$", text, re.M)[1].strip()
    if len(base64.b64decode(key, validate=True)) != 32:
        raise RuntimeError("Invalid Sparkle public key in Config/Updates.xcconfig.")
    return key


def check_key():
    if not (TOOLS / "generate_keys").is_file():
        raise RuntimeError("Resolve Sparkle first: ./script/build_and_run.sh --build-only")
    actual = run(TOOLS / "generate_keys", "--account", ACCOUNT, "-p").stdout.strip()
    if actual != public_key():
        raise RuntimeError("The Textend Sparkle key in this Mac's Keychain does not match the app.")


def load_config(path):
    if not path.is_file():
        raise RuntimeError("Copy Config/release.example.json to Config/release.local.json and configure it.")
    config = json.loads(path.read_text())
    for key in ("team_id", "notary_profile"):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise RuntimeError(f"Missing release configuration: {key}")
    if not re.fullmatch(r"[A-Z0-9]{10}", config["team_id"]):
        raise RuntimeError("Invalid Apple team ID.")
    return config


def check_version(version, build):
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise RuntimeError("Use a version such as 0.1.0.")
    if type(build) is not int or build < 1:
        raise RuntimeError("The build number must be a positive, increasing integer.")


def validate_bundle(app, version, build):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {
        "CFBundleIdentifier": BUNDLE_ID, "CFBundleName": "Textend",
        "CFBundleVersion": str(build), "CFBundleShortVersionString": version,
        "SUFeedURL": FEED_URL, "SUPublicEDKey": public_key(),
        "LSMinimumSystemVersion": "14.0",
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise RuntimeError(f"Unexpected {key} in the exported app.")
    for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
        if info.get(key) is not True:
            raise RuntimeError(f"{key} must be enabled in the exported app.")
    if not (app / "Contents/Frameworks/Sparkle.framework").is_dir():
        raise RuntimeError("Sparkle is missing from the exported app.")
    arches = run("lipo", "-archs", app / "Contents/MacOS/Textend").stdout.split()
    if set(arches) != {"arm64", "x86_64"}:
        raise RuntimeError("Release must include both Apple Silicon and Intel.")


def feed_item(feed):
    root = ET.parse(feed).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise RuntimeError("A prepared release must contain exactly one appcast item.")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise RuntimeError("Appcast is missing its download.")
    build = item.findtext("s:version", namespaces=NS) or enclosure.get(f"{{{NS['s']}}}version")
    if not build or not build.isdigit():
        raise RuntimeError("Appcast build number must be an integer.")
    return item, enclosure, int(build)


def check_newer(feed, build):
    for item in ET.parse(feed).getroot().findall("./channel/item"):
        enclosure = item.find("enclosure")
        value = item.findtext("s:version", namespaces=NS)
        if value is None and enclosure is not None:
            value = enclosure.get(f"{{{NS['s']}}}version")
        if not value or not value.isdigit():
            raise RuntimeError("Published feed contains an unsupported build number.")
        if int(value) >= build:
            raise RuntimeError(f"Build {build} is not newer than published build {value}.")


def build_release(args, config):
    check_version(args.version, args.build)
    check_key()
    if run("git", "status", "--porcelain").stdout.strip():
        raise RuntimeError("Commit source changes before creating a distributable release.")
    profile, signing_identity = resolve_profile("release")
    identities = run("security", "find-identity", "-v", "-p", "codesigning").stdout
    matches = re.findall(r'\) ([A-F0-9]{40}) "Developer ID Application: [^"]+ \(' + config["team_id"] + r'\)"', identities)
    if len(matches) != 1 or matches[0] != signing_identity:
        raise RuntimeError("Expected one Developer ID Application certificate for the configured team.")
    run("xcrun", "notarytool", "history", "--keychain-profile", config["notary_profile"], "--output-format", "json")
    if not args.notes.is_file():
        raise RuntimeError("Provide an existing Markdown release notes file with --notes.")
    output = ROOT / "dist" / f"{args.version}-{args.build}"
    if output.exists():
        raise RuntimeError(f"Release output already exists: {output}. Use a new build number.")
    work = ROOT / "build/releases.noindex" / f"{args.version}-{args.build}"
    work.mkdir(parents=True, exist_ok=True)
    archive = work / "Textend.xcarchive"
    exported = work / "export"
    print("Archiving Textend…", flush=True)
    run("xcodebuild", "-quiet", "-project", ROOT / "Textend.xcodeproj", "-scheme", "Textend",
        "-configuration", "Release", "-destination", "generic/platform=macOS",
        "-derivedDataPath", work / "DerivedData", "-clonedSourcePackagesDirPath", ROOT / "build/SourcePackages",
        "-disableAutomaticPackageResolution", "-archivePath", archive,
        f"MARKETING_VERSION={args.version}", f"CURRENT_PROJECT_VERSION={args.build}",
        f"DEVELOPMENT_TEAM={config['team_id']}", f"TEXTEND_SIGNING_IDENTITY={matches[0]}",
        f"TEXTEND_PROVISIONING_PROFILE={profile['UUID']}",
        "ONLY_ACTIVE_ARCH=NO", "ARCHS=arm64 x86_64", "archive")
    options = work / "ExportOptions.plist"
    options.write_bytes(plistlib.dumps({"method": "developer-id", "teamID": config["team_id"],
                                       "signingStyle": "manual", "signingCertificate": matches[0],
                                       "provisioningProfiles": {BUNDLE_ID: profile["UUID"]},
                                       "iCloudContainerEnvironment": "Production"}))
    print("Exporting and verifying nested signatures…", flush=True)
    run("xcodebuild", "-quiet", "-exportArchive", "-archivePath", archive,
        "-exportOptionsPlist", options, "-exportPath", exported)
    app = exported / "Textend.app"
    validate_bundle(app, args.version, args.build)
    embedded = plistlib.loads(run("security", "cms", "-D", "-i", app / "Contents/embedded.provisionprofile").stdout.encode())
    validate_profile(embedded, "release")
    entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", app).stdout.encode())
    if (entitlements.get("com.apple.developer.icloud-container-environment") != "Production"
            or entitlements.get("com.apple.developer.icloud-container-identifiers") != [CONTAINER]
            or entitlements.get("com.apple.developer.icloud-services") != ["CloudKit"]
            or entitlements.get("com.apple.developer.aps-environment") != "production"):
        raise RuntimeError("Exported app is missing production CloudKit entitlements.")
    run("codesign", "--verify", "--deep", "--strict", app)
    signature = run("codesign", "-dvv", app).stderr
    if f"TeamIdentifier={config['team_id']}" not in signature or "Timestamp=" not in signature:
        raise RuntimeError("Export does not have the expected timestamped release signature.")
    submission_zip = work / "notarization.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, submission_zip)
    print("Submitting to Apple for notarization…", flush=True)
    response = json.loads(run("xcrun", "notarytool", "submit", submission_zip,
                              "--keychain-profile", config["notary_profile"], "--wait",
                              "--output-format", "json").stdout)
    (work / "notarization.json").write_text(json.dumps(response, indent=2) + "\n")
    if response.get("status") != "Accepted":
        raise RuntimeError(f"Notarization was not accepted; see {work / 'notarization.json'}")
    run("xcrun", "stapler", "staple", app)
    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", app)
    # Nothing is advertised until Apple validation and Sparkle signing both succeed.
    stage = work / "publish"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    filename = f"Textend-{args.version}-{args.build}.zip"
    package = stage / filename
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, package)
    shutil.copy2(args.notes, package.with_suffix(".md"))
    run(TOOLS / "generate_appcast", "--account", ACCOUNT,
        "--download-url-prefix", DOWNLOAD_URL, "--embed-release-notes", "--maximum-deltas", "0", stage)
    feed = stage / "appcast.xml"
    run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", feed)
    _, enclosure, feed_build = feed_item(feed)
    if feed_build != args.build or enclosure.get("url") != DOWNLOAD_URL + filename:
        raise RuntimeError("Generated appcast has unexpected release metadata.")
    # Notes are embedded in the signed feed; only the ZIP and XML need publication.
    package.with_suffix(".md").unlink()
    manifest = {"version": args.version, "build": args.build, "archive": filename,
                "archive_sha256": sha256(package), "feed_sha256": sha256(feed),
                "source_revision": run("git", "rev-parse", "HEAD").stdout.strip(),
                "notarization_id": response["id"]}
    (stage / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    output.parent.mkdir(exist_ok=True)
    shutil.copytree(stage, output)
    print(f"Prepared {output}\nPublish explicitly: python3 script/release.py publish {output}")


def aws_command(config):
    endpoint = config.get("spaces_endpoint", "")
    bucket = config.get("spaces_bucket", "")
    if not re.fullmatch(r"https://[a-z]+[0-9]+\.digitaloceanspaces\.com", endpoint):
        raise RuntimeError("Set spaces_endpoint to the Spaces origin, such as https://atl1.digitaloceanspaces.com.")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket):
        raise RuntimeError("Set spaces_bucket to your Textend downloads bucket.")
    if config.get("spaces_prefix") != "macos":
        raise RuntimeError("spaces_prefix must be macos to match the app's feed URL.")
    executable = shutil.which("aws") or str(ROOT / ".build/release-tools/bin/aws")
    if not Path(executable).is_file():
        raise RuntimeError("Install the local upload tool: ./script/setup_release_tools.sh")
    command = [executable, "--endpoint-url", endpoint, "--region", "us-east-1"]
    if config.get("aws_profile"):
        command += ["--profile", config["aws_profile"]]
    return command


def object_missing(result):
    return result.returncode != 0 and bool(re.search(r"\((?:404|NoSuchKey|NotFound)\)", result.stderr))


def verify_public_feed(feed):
    with urllib.request.urlopen(FEED_URL, timeout=60) as response:
        actual = response.read()
    if hashlib.sha256(actual).hexdigest() != sha256(feed):
        raise RuntimeError("The origin feed was published, but the CDN is stale. Purge macos/appcast.xml in Spaces and retry publish.")


def publish_release(args, config):
    check_key()
    command = aws_command(config)
    directory = args.release.resolve()
    manifest = json.loads((directory / "release.json").read_text())
    check_version(manifest["version"], manifest["build"])
    filename = f"Textend-{manifest['version']}-{manifest['build']}.zip"
    if manifest["archive"] != filename:
        raise RuntimeError("Invalid release archive name.")
    package, feed = directory / filename, directory / "appcast.xml"
    if sha256(package) != manifest["archive_sha256"] or sha256(feed) != manifest["feed_sha256"]:
        raise RuntimeError("Release files changed after preparation; refusing to publish.")
    run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", feed)
    _, enclosure, build = feed_item(feed)
    if build != manifest["build"] or enclosure.get("url") != DOWNLOAD_URL + filename:
        raise RuntimeError("Release manifest and appcast do not match.")
    if enclosure.get("length") != str(package.stat().st_size):
        raise RuntimeError("Appcast download size does not match the archive.")
    run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", package,
        enclosure.get(f"{{{NS['s']}}}edSignature", ""))
    bucket, prefix = config["spaces_bucket"], config["spaces_prefix"]
    with tempfile.TemporaryDirectory(prefix="textend-publish-") as temporary:
        previous = Path(temporary) / "appcast.xml"
        # Spaces can return a missing-object body that the AWS CLI cannot decode.
        # HEAD distinguishes absence from access/network errors without reading it.
        result = run(*command, "s3api", "head-object", "--bucket", bucket,
                     "--key", f"{prefix}/appcast.xml", allow_failure=True)
        if result.returncode == 0:
            run(*command, "s3api", "get-object", "--bucket", bucket,
                "--key", f"{prefix}/appcast.xml", previous)
            run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", previous)
            if sha256(previous) == sha256(feed):
                verify_public_feed(feed)
                print(f"Build {build} is already published and verified.")
                return
            check_newer(previous, build)
        elif not object_missing(result):
            raise RuntimeError("Could not read the current feed from Spaces. Check credentials and bucket access.")
        existing = run(*command, "s3api", "head-object", "--bucket", bucket,
                       "--key", f"{prefix}/{filename}", allow_failure=True)
        if existing.returncode == 0:
            remote = json.loads(existing.stdout)
            if (remote.get("Metadata", {}).get("sha256") != manifest["archive_sha256"]
                    or remote.get("ContentLength") != package.stat().st_size):
                raise RuntimeError("An archive with this version already exists with different contents.")
        elif object_missing(existing):
            print("Uploading versioned archive…", flush=True)
            run(*command, "s3", "cp", package, f"s3://{bucket}/{prefix}/{filename}",
                "--acl", "public-read", "--content-type", "application/zip",
                "--cache-control", "public,max-age=31536000,immutable",
                "--metadata", f"sha256={manifest['archive_sha256']}", "--only-show-errors")
        else:
            raise RuntimeError("Could not check the versioned archive in Spaces.")
        # Verify the exact public download before advertising it to installed apps.
        print("Verifying public download through the CDN…", flush=True)
        downloaded = Path(temporary) / filename
        with urllib.request.urlopen(DOWNLOAD_URL + filename, timeout=60) as source, downloaded.open("wb") as target:
            shutil.copyfileobj(source, target)
        if sha256(downloaded) != manifest["archive_sha256"]:
            raise RuntimeError("Public download does not match the signed release; feed was not published.")
        print("Publishing update feed last…", flush=True)
        run(*command, "s3", "cp", feed, f"s3://{bucket}/{prefix}/appcast.xml", "--acl", "public-read",
            "--content-type", "application/xml", "--cache-control", "no-cache,max-age=0,must-revalidate",
            "--only-show-errors")
        verify_public_feed(feed)
        print(f"Published and verified build {build}: {FEED_URL}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "Config/release.local.json")
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="Archive, export, notarize, and sign a local release.")
    build.add_argument("--version", required=True)
    build.add_argument("--build", type=int, required=True)
    build.add_argument("--notes", type=Path, required=True)
    publish = commands.add_parser("publish", help="Upload a prepared release and publish the feed last.")
    publish.add_argument("release", type=Path)
    args = parser.parse_args()
    (ROOT / "build").mkdir(exist_ok=True)
    with (ROOT / "build/release.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another local release operation is running.")
        config = load_config(args.config)
        if args.command == "build":
            build_release(args, config)
        else:
            publish_release(args, config)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, ET.ParseError) as error:
        sys.exit(f"Release stopped: {error}")
