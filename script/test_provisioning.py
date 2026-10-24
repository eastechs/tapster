#!/usr/bin/env python3
"""Offline checks for CloudKit profile validation."""
import copy
import datetime
import unittest
import pathlib
import tempfile
from unittest.mock import patch
from provisioning import BUNDLE, CONTAINER, TEAM, NAMES, install_profile, validate_profile


class ProvisioningTests(unittest.TestCase):
    def test_install_keeps_other_apps_and_archives_superseded_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            destination = root / "profiles"
            destination.mkdir()
            source = root / "download.provisionprofile"
            source.write_bytes(b"new profile")
            old = destination / "old.provisionprofile"
            old.write_bytes(b"old profile")
            other = destination / "other.provisionprofile"
            other.write_bytes(b"other app")
            profile = self.profile("development")
            profile.update(Name=NAMES["development"], UUID="07992c51-7f23-4b20-9d76-3fe5a387ad8b")
            def decode(path):
                return {"Name": "Other", "TeamIdentifier": [TEAM]} if path == other else profile
            with patch("provisioning.read_profile", side_effect=decode):
                target = install_profile(source, "development", [destination])
                self.assertEqual(target.read_bytes(), b"new profile")
                self.assertEqual(other.read_bytes(), b"other app")
                self.assertFalse(old.exists())
                archived = list((destination.parent / "TextendRetiredProfiles").iterdir())
                self.assertEqual(len(archived), 1)
                self.assertEqual(archived[0].read_bytes(), b"old profile")
                install_profile(source, "development", [destination])
                self.assertTrue(target.exists(), "Reinstalling must retain the current profile")

    def test_install_rejects_wrong_profile_without_changing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "download.provisionprofile"
            source.write_bytes(b"download")
            profile = self.profile("development")
            profile.update(Name="Other App", UUID="07992c51-7f23-4b20-9d76-3fe5a387ad8b")
            with patch("provisioning.read_profile", return_value=profile), self.assertRaises(RuntimeError):
                install_profile(source, "development", [root / "profiles"])
            self.assertFalse((root / "profiles").exists())

    def profile(self, kind):
        return {
            "ExpirationDate": datetime.datetime(2099, 1, 1),
            "TeamIdentifier": [TEAM],
            "ProvisionsAllDevices": kind == "release",
            "Entitlements": {
                "com.apple.application-identifier": f"{TEAM}.{BUNDLE}",
                "com.apple.developer.icloud-container-identifiers": [CONTAINER],
                "com.apple.developer.icloud-services": "*",
                "com.apple.developer.icloud-container-environment": ["Development", "Production"],
                "com.apple.developer.aps-environment": "development" if kind == "development" else "production",
            },
        }

    def test_accepts_matching_profiles(self):
        for kind in ("development", "release"):
            validate_profile(self.profile(kind), kind)

    def test_rejects_mismatched_entitlements(self):
        for key, value in {
            "com.apple.application-identifier": "OTHER.app",
            "com.apple.developer.icloud-container-identifiers": ["iCloud.other"],
            "com.apple.developer.icloud-services": ["CloudDocuments"],
            "com.apple.developer.icloud-container-environment": "Development",
            "com.apple.developer.aps-environment": "development",
        }.items():
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                profile = copy.deepcopy(self.profile("release"))
                profile["Entitlements"][key] = value
                validate_profile(profile, "release")

    def test_rejects_expired_wrong_team_or_device_limited_release(self):
        for key, value in {
            "ExpirationDate": datetime.datetime(2000, 1, 1),
            "TeamIdentifier": ["OTHER"],
            "ProvisionsAllDevices": False,
        }.items():
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                profile = self.profile("release")
                profile[key] = value
                validate_profile(profile, "release")


if __name__ == "__main__":
    unittest.main()
