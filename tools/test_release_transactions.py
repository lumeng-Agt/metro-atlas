"""Check release replacement failures and the boundary of certified inputs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_packages as build


class ReleaseChecks(unittest.TestCase):
    def test_bundle_rollback_at_each_replace(self):
        for fresh in (False, True):
            # Existing media move + install + five file replacements.
            for fail_at in range(1, 7 if fresh else 8):
                with self.subTest(fresh=fresh, fail_at=fail_at), tempfile.TemporaryDirectory() as base:
                    release = Path(base).resolve()
                    stage = release / "stage"
                    stage.mkdir()
                    (stage / "media").mkdir()
                    (stage / "media/encoder.exe").write_bytes(b"new encoder")
                    names = ("game.exe", "game.zip", "README.txt", "build-info.txt", "SHA256SUMS.txt")
                    for name in names:
                        (stage / name).write_bytes(b"new " + name.encode())
                        if not fresh: (release / name).write_bytes(b"old " + name.encode())
                    if not fresh:
                        (release / "media").mkdir()
                        (release / "media/encoder.exe").write_bytes(b"old encoder")
                        (release / "media/extra-notice.txt").write_bytes(b"retain unknown old notice")
                    count = 0
                    replace = os.replace
                    def interrupted(source, target):
                        nonlocal count
                        count += 1
                        if count == fail_at: raise PermissionError("injected locked destination")
                        return replace(source, target)
                    with patch.object(build.os, "replace", interrupted), self.assertRaises(PermissionError):
                        build.install_bundle(stage, release, names, ("encoder.exe",))
                    for name in names:
                        self.assertEqual((release / name).exists(), not fresh)
                        if not fresh: self.assertEqual((release / name).read_bytes(), b"old " + name.encode())
                    self.assertEqual((release / "media").exists(), not fresh)
                    if not fresh:
                        self.assertEqual((release / "media/encoder.exe").read_bytes(), b"old encoder")
                        self.assertEqual((release / "media/extra-notice.txt").read_bytes(), b"retain unknown old notice")

    def test_manifest_tracks_runtime_and_tests_but_not_report_updates(self):
        with tempfile.TemporaryDirectory() as base:
            root = Path(base)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            for name in ("scripts/a.gd", "data/cities.json", "tests/check.gd", "docs/report.md", "licenses/LICENSE.txt"):
                path = root / name
                path.parent.mkdir(exist_ok=True)
                path.write_text("original")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            with patch.object(build, "ROOT", root):
                baseline = build.source_manifest_hash(gameplay_only=True)
                source = build.source_manifest_hash()
                (root / "docs/report.md").write_text("fresh measurements")
                self.assertEqual(baseline, build.source_manifest_hash(gameplay_only=True))
                self.assertNotEqual(source, build.source_manifest_hash())
                for name in ("scripts/a.gd", "data/cities.json", "tests/check.gd"):
                    (root / name).write_text("changed input")
                    self.assertNotEqual(baseline, build.source_manifest_hash(gameplay_only=True))
                    (root / name).write_text("original")


if __name__ == "__main__": unittest.main()
