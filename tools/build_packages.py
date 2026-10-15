from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "release"
STABLE_EXE = RELEASE / "造一座地铁.exe"
STABLE_ZIP = RELEASE / "造一座地铁-Windows-x86_64.zip"
CHECKSUM_FILE = RELEASE / "SHA256SUMS.txt"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def current_version() -> str:
    source = (ROOT / "scripts" / "main.gd").read_text(encoding="utf-8")
    match = re.search(r'BUILD_VERSION\s*:?=\s*"([0-9]+\.[0-9]+\.[0-9]+)', source)
    if not match:
        raise RuntimeError("Cannot read BUILD_VERSION from scripts/main.gd")
    return match.group(1)


def git_state() -> tuple[str, str, str]:
    try:
        commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
        status = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True)
    except (OSError, subprocess.CalledProcessError):
        return "unknown", "unknown", "unknown"
    return commit, "clean" if not status.strip() else "dirty (changes not committed)", source_manifest_hash()


def source_manifest_hash() -> str:
    digest = hashlib.sha256()
    excluded_dirs = {".git", ".godot", ".tools", "Godot", "release", "test-artifacts", "__pycache__"}
    for path in sorted(ROOT.rglob("*")):
        relative_parts = path.relative_to(ROOT).parts
        if not path.is_file() or any(part in excluded_dirs or part.startswith("test-") for part in relative_parts):
            continue
        if path.suffix in {".exe", ".zip", ".pck", ".tmp", ".bak"}:
            continue
        relative = path.relative_to(ROOT).as_posix().encode("utf-8")
        digest.update(relative + b"\0")
        digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def copy_verified(source: Path, target: Path) -> None:
    shutil.copy2(source, target)
    if sha256(source) != sha256(target):
        raise RuntimeError(f"Copy verification failed: {source.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the single stable Metro Atlas Windows package.")
    parser.add_argument("--exe", type=Path, help="Verified fresh Godot export; defaults to release/造一座地铁.exe")
    parser.add_argument("--version", default=current_version())
    args = parser.parse_args()

    source_exe = args.exe.resolve() if args.exe else STABLE_EXE
    if not source_exe.is_file():
        raise FileNotFoundError(f"Fresh exported executable not found: {source_exe}")
    if args.version != current_version():
        raise RuntimeError(f"Requested version {args.version} does not match source version {current_version()}")

    RELEASE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".metro-atlas-stage-", dir=RELEASE) as temp_name:
        stage = Path(temp_name)
        staged_exe = stage / "造一座地铁.exe"
        staged_zip = stage / STABLE_ZIP.name
        staged_readme = stage / "README.txt"
        staged_build_info = stage / "build-info.txt"
        staged_checksums = stage / CHECKSUM_FILE.name
        copy_verified(source_exe, staged_exe)

        readme_text = (RELEASE / "README.txt").read_text(encoding="utf-8")
        readme_text = re.sub(r"(?m)^造一座地铁 · Windows 免安装版 [^\r\n]+$", f"造一座地铁 · Windows 免安装版 {args.version}", readme_text)
        readme_text = re.sub(r"(?m)^更新内容：[^\r\n]+$", f"更新内容：压缩包内 update-notes-{args.version}.txt", readme_text)
        readme_text = re.sub(r"(?m)^测试记录：[^\r\n]+$", "测试记录：压缩包内 test-record.txt", readme_text)
        staged_readme.write_text(readme_text, encoding="utf-8")

        commit, tree_state, manifest = git_state()
        build_time = datetime.now().astimezone().isoformat(timespec="seconds")
        staged_build_info.write_text(
            f"游戏：造一座地铁\n版本：{args.version}\n构建日期：{build_time}\n"
            "Godot：4.7.2 stable / Compatibility\n"
            f"Git 提交：{commit}\n源码工作区：{tree_state}\n源码清单 SHA-256：{manifest}\n"
            f"游戏程序 SHA-256：{sha256(staged_exe)}\n",
            encoding="utf-8",
        )

        update_notes = ROOT / "docs" / f"update-notes-{args.version}.md"
        distribution_files = [
            (staged_exe, "造一座地铁.exe"),
            (staged_readme, "README.txt"),
            (RELEASE / "LICENSES.txt", "LICENSES.txt"),
            (ROOT / "THIRD_PARTY_NOTICES.txt", "THIRD_PARTY_NOTICES.txt"),
            (RELEASE / "OFL.txt", "OFL.txt"),
            (staged_build_info, "build-info.txt"),
            (update_notes, f"update-notes-{args.version}.txt"),
            (ROOT / "docs" / "test-record.md", "test-record.txt"),
            (ROOT / "data" / "basemap" / "manifest.json", "basemap-manifest.json"),
            (ROOT / "data" / "basemap" / "README.txt", "basemap-README.txt"),
        ]
        for source, _ in distribution_files:
            if not source.is_file():
                raise FileNotFoundError(f"Missing release content: {source}")

        previews = [
            "docs/route-repair-0.13.5.jpg",
            "docs/menu-preview-1366x768.png",
            "docs/menu-preview-1600x980.png",
            "docs/ui-preview-1366x768.png",
            "docs/ui-preview-1600x980.png",
            "docs/ui-preview-1920x1080.png",
            "docs/tutorial-preview-1366x768.png",
            "docs/tutorial-preview-1600x980.png",
        ]
        with ZipFile(staged_zip, "w", ZIP_DEFLATED, compresslevel=7) as archive:
            for source, archive_name in distribution_files:
                archive.write(source, archive_name)
            for relative in previews:
                source = ROOT / relative
                if source.is_file():
                    archive.write(source, relative)

        with ZipFile(staged_zip, "r") as archive:
            broken_member = archive.testzip()
            if broken_member:
                raise RuntimeError(f"ZIP verification failed at {broken_member}")
            packaged_exe_hash = hashlib.sha256(archive.read("造一座地铁.exe")).hexdigest()
            if packaged_exe_hash != sha256(staged_exe):
                raise RuntimeError("Packaged executable does not match the verified export")

        staged_checksums.write_text(
            f"{sha256(staged_exe)}  {STABLE_EXE.name}\n{sha256(staged_zip)}  {STABLE_ZIP.name}\n",
            encoding="utf-8",
        )

        # Keep a temporary rollback copy so the stable EXE and ZIP remain a matching pair
        # if either final rename fails. No versioned EXEs or ZIPs are produced.
        rollback_exe = stage / "previous.exe"
        rollback_zip = stage / "previous.zip"
        had_exe, had_zip = STABLE_EXE.is_file(), STABLE_ZIP.is_file()
        if had_exe:
            copy_verified(STABLE_EXE, rollback_exe)
        if had_zip:
            copy_verified(STABLE_ZIP, rollback_zip)
        try:
            os.replace(staged_exe, STABLE_EXE)
            os.replace(staged_zip, STABLE_ZIP)
        except OSError:
            if had_exe and rollback_exe.exists(): os.replace(rollback_exe, STABLE_EXE)
            if had_zip and rollback_zip.exists(): os.replace(rollback_zip, STABLE_ZIP)
            raise

        (RELEASE / "README.txt").write_text(readme_text, encoding="utf-8")
        os.replace(staged_build_info, RELEASE / "build-info.txt")
        os.replace(staged_checksums, CHECKSUM_FILE)

    print(f"Installed stable EXE: {STABLE_EXE} ({STABLE_EXE.stat().st_size:,} bytes)")
    print(f"Installed single Windows package: {STABLE_ZIP} ({STABLE_ZIP.stat().st_size:,} bytes)")
    print(f"Checksums: {CHECKSUM_FILE}")


if __name__ == "__main__":
    main()
