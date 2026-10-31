"""Prepare the exact, checksummed, unmodified LGPL encoder helpers for packaging."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent
ARCHIVE_NAME = "ffmpeg-n8.1-latest-win64-lgpl-8.1.zip"
EXPECTED = "19cfdb89e80f4b0d9f608327d86487444c1fbc98e7703b3c025c292cec3ca070"


def prepare():
    archive = ROOT / ".tools/ffmpeg-lgpl.zip"
    if hashlib.sha256(archive.read_bytes()).hexdigest() != EXPECTED:
        raise RuntimeError("Encoder archive does not match the reviewed upstream checksum")
    target = ROOT / ".tools/media-runtime"
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        for name, suffix in (("ffmpeg.exe", "/bin/ffmpeg.exe"), ("ffprobe.exe", "/bin/ffprobe.exe"), ("LICENSE.txt", "/LICENSE.txt")):
            matches = [entry for entry in bundle.namelist() if entry.endswith(suffix)]
            if len(matches) != 1:
                raise RuntimeError(f"Ambiguous component {name}")
            (target / name).write_bytes(bundle.read(matches[0]))
    version = subprocess.check_output([str(target / "ffmpeg.exe"), "-version"], text=True)
    encoders = subprocess.check_output([str(target / "ffmpeg.exe"), "-hide_banner", "-encoders"], text=True)
    if "--enable-gpl" in version or "libvpx-vp9" not in encoders:
        raise RuntimeError("Unexpected encoder license configuration or missing VP9 support")
    source = (f"Unmodified FFmpeg LGPL helpers from BtbN/FFmpeg-Builds\nArchive: {ARCHIVE_NAME}\n"
              f"Archive SHA-256: {EXPECTED}\nRetrieved: 2026-10-31\n"
              "Binary source and build instructions: https://github.com/BtbN/FFmpeg-Builds\n"
              "FFmpeg source: https://git.ffmpeg.org/ffmpeg.git\n"
              "License: LGPL-3.0-or-later; see LICENSE.txt. The helper is a separate process, not linked into the game.\n\n"
              + version)
    (target / "SOURCE.txt").write_text(source, encoding="utf-8")
    (target / "GPL-3.0.txt").write_bytes((ROOT / "licenses/GPL-3.0.txt").read_bytes())
    manifest = {"archive": ARCHIVE_NAME, "archiveSha256": EXPECTED, "version": version.splitlines()[0],
                "source": "https://github.com/BtbN/FFmpeg-Builds", "license": "LGPL-3.0-or-later",
                "files": {name: hashlib.sha256((target / name).read_bytes()).hexdigest()
                          for name in ("ffmpeg.exe", "ffprobe.exe", "LICENSE.txt", "GPL-3.0.txt", "SOURCE.txt")}}
    (ROOT / "data/media_runtime_manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(manifest["version"])


if __name__ == "__main__": prepare()
