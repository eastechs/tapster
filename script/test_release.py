#!/usr/bin/env python3
"""Offline release guard tests. No signing, Apple submission, or Spaces writes."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def feed(build=2, filename="Textend-0.1.0-2.zip", length=7):
    return f'''<rss xmlns:sparkle="{release.NS['s']}"><channel><item>
    <sparkle:version>{build}</sparkle:version><enclosure url="{release.DOWNLOAD_URL}{filename}"
    length="{length}" sparkle:edSignature="test-signature"/></item></channel></rss>'''


class ReleaseGuards(unittest.TestCase):
    def test_versions_reject_paths_and_noninteger_builds(self):
        for version, build in [("../0.1.0", 2), ("0.1.0", 0), ("0.1.0", True), ("0.1.0", "2")]:
            with self.subTest(version=version, build=build), self.assertRaises(RuntimeError):
                release.check_version(version, build)
        release.check_version("1.2.3", 123)

    def test_published_build_cannot_be_reused_or_downgraded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(feed(12))
            for number in (1, 12):
                with self.assertRaises(RuntimeError):
                    release.check_newer(path, number)
            release.check_newer(path, 13)

    def test_unknown_remote_version_stops_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(feed("1.2"))
            with self.assertRaises(RuntimeError):
                release.check_newer(path, 99)

    def test_only_missing_objects_allow_first_publication(self):
        for message in ["(403) Forbidden", "(AccessDenied)", "connection failed", "(NoSuchBucket)"]:
            self.assertFalse(release.object_missing(subprocess.CompletedProcess([], 1, "", message)))
        self.assertTrue(release.object_missing(subprocess.CompletedProcess([], 1, "", "(NoSuchKey)")))

    def test_upload_requires_spaces_origin_and_matching_prefix(self):
        config = dict(spaces_endpoint="https://evil.example.com", spaces_bucket="textend", spaces_prefix="macos")
        with self.assertRaises(RuntimeError):
            release.aws_command(config)
        config.update(spaces_endpoint="https://atl1.digitaloceanspaces.com", spaces_prefix="hella-pads")
        with self.assertRaises(RuntimeError):
            release.aws_command(config)


class PublishWorkflow(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name).resolve()
        self.addCleanup(self.temporary.cleanup)
        self.package = self.directory / "Textend-0.1.0-2.zip"
        self.package.write_bytes(b"archive")
        self.appcast = self.directory / "appcast.xml"
        self.appcast.write_text(feed())
        self.manifest = dict(version="0.1.0", build=2, archive=self.package.name,
                             archive_sha256=release.sha256(self.package), feed_sha256=release.sha256(self.appcast))
        (self.directory / "release.json").write_text(json.dumps(self.manifest))
        self.commands = []
        self.remote_feed = None
        self.remote_error = "(NoSuchKey)"
        self.remote_get_error = None
        self.remote_archive = None
        self.public_archive = b"archive"
        self.public_feed = self.appcast.read_bytes()
        self.config = dict(spaces_bucket="textend", spaces_prefix="macos")

    def run_command(self, *args, **kwargs):
        self.commands.append(tuple(str(x) for x in args))
        if "get-object" in args:
            if self.remote_get_error:
                raise RuntimeError(self.remote_get_error)
            if self.remote_feed is None:
                return subprocess.CompletedProcess(args, 1, "", self.remote_error)
            Path(args[-1]).write_text(self.remote_feed)
        if "head-object" in args:
            if "macos/appcast.xml" in args:
                if self.remote_feed is None:
                    return subprocess.CompletedProcess(args, 1, "", self.remote_error)
                return subprocess.CompletedProcess(args, 0, "{}", "")
            if self.remote_archive is None:
                return subprocess.CompletedProcess(args, 1, "", "(404)")
            return subprocess.CompletedProcess(args, 0, json.dumps(self.remote_archive), "")
        return subprocess.CompletedProcess(args, 0, "", "")

    def urlopen(self, url, **kwargs):
        return io.BytesIO(self.public_feed if url == release.FEED_URL else self.public_archive)

    def publish(self):
        with patch.object(release, "check_key"), patch.object(release, "aws_command", return_value=["aws"]), \
                patch.object(release, "run", side_effect=self.run_command), \
                patch.object(release.urllib.request, "urlopen", side_effect=self.urlopen), \
                contextlib.redirect_stdout(io.StringIO()):
            release.publish_release(SimpleNamespace(release=self.directory), self.config)

    def uploads(self):
        return [x for x in self.commands if "cp" in x]

    def test_archive_is_uploaded_before_feed(self):
        self.publish()
        uploads = self.uploads()
        self.assertEqual(len(uploads), 2)
        self.assertIn(str(self.package), uploads[0])
        self.assertIn(str(self.appcast), uploads[1])
        self.assertIn("no-cache,max-age=0,must-revalidate", uploads[1])

    def test_missing_feed_is_not_downloaded(self):
        self.remote_error = "(404) Not Found"
        self.remote_get_error = "argument of type 'NoneType' is not a container or iterable"
        self.publish()
        self.assertFalse(any("get-object" in command for command in self.commands))
        self.assertEqual(len(self.uploads()), 2)

    def test_existing_feed_download_failure_blocks_upload(self):
        self.remote_feed = feed(1)
        self.remote_get_error = "connection failed"
        with self.assertRaisesRegex(RuntimeError, "connection failed"):
            self.publish()
        self.assertEqual(self.uploads(), [])

    def test_feed_not_published_if_public_download_differs(self):
        self.public_archive = b"corrupt"
        with self.assertRaisesRegex(RuntimeError, "does not match"):
            self.publish()
        self.assertEqual(len(self.uploads()), 1)

    def test_changed_prepared_files_are_rejected_before_upload(self):
        self.package.write_bytes(b"tampered")
        with self.assertRaisesRegex(RuntimeError, "changed after"):
            self.publish()
        self.assertEqual(self.uploads(), [])

    def test_remote_permission_error_is_not_treated_as_first_release(self):
        self.remote_error = "(AccessDenied)"
        with self.assertRaisesRegex(RuntimeError, "Could not read"):
            self.publish()
        self.assertEqual(self.uploads(), [])

    def test_existing_version_cannot_be_overwritten(self):
        self.remote_archive = {"Metadata": {"sha256": "different"}, "ContentLength": 7}
        with self.assertRaisesRegex(RuntimeError, "different contents"):
            self.publish()
        self.assertEqual(self.uploads(), [])

    def test_newer_remote_feed_blocks_older_release(self):
        self.remote_feed = feed(3)
        with self.assertRaisesRegex(RuntimeError, "not newer"):
            self.publish()
        self.assertEqual(self.uploads(), [])

    def test_retry_after_partial_archive_upload_is_safe(self):
        self.remote_archive = {"Metadata": {"sha256": self.manifest["archive_sha256"]}, "ContentLength": 7}
        self.publish()
        self.assertEqual(len(self.uploads()), 1)
        self.assertIn(str(self.appcast), self.uploads()[0])

    def test_identical_completed_release_is_idempotent(self):
        self.remote_feed = self.appcast.read_text()
        self.publish()
        self.assertEqual(self.uploads(), [])

    def test_stale_cdn_is_reported_after_origin_publication(self):
        self.public_feed = b"old feed"
        with self.assertRaisesRegex(RuntimeError, "CDN is stale"):
            self.publish()
        self.assertEqual(len(self.uploads()), 2)


if __name__ == "__main__":
    unittest.main()
