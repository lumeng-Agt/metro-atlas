"""Fail release checks on missing challenge/audio/runtime content, not UI counts."""
from __future__ import annotations

import json
import hashlib
from pathlib import Path


def issues(root: Path) -> list[str]:
    bank = json.loads((root / "data/challenges.json").read_text(encoding="utf-8"))
    missing = []
    for city in ("shanghai", "beijing", "guangzhou", "shenzhen", "chengdu"):
        eligible = [q for q in bank.get("locations", [])
                    if q.get("cityId") == city and q.get("reviewStatus") == "reference_bound"
                    and q.get("referenceBasis") == "game_reference"
                    and q.get("referenceId") and len(q.get("latlng", [])) == 2 and q.get("source")]
        if len(eligible) < 5:
            missing.append(f"{city}: only {len(eligible)}/5 explicitly bound game-reference location questions")
    questions = {q["id"]: q for q in bank.get("questions", [])}
    types = {questions[day["questionId"]].get("type")
             for day in bank.get("days", {}).values() if day.get("questionId") in questions}
    if not {"location", "former_name", "order"}.issubset(types):
        missing.append("daily schedule does not cover location/former_name/order")
    if len(bank.get("days", {})) < 180:
        missing.append("fewer than 180 explicit daily dates")
    audio = root / "data/announcement_manifest.json"
    if not audio.is_file():
        missing.append("reviewed offline announcement assets and rights manifest are missing")
    else:
        manifest = json.loads(audio.read_text(encoding="utf-8"))
        if not manifest.get("license") or not manifest.get("clips"):
            missing.append("announcement manifest has no license or clips")
        for clip in manifest.get("clips", []):
            path = (root / clip.get("path", "")).resolve()
            if not path.is_relative_to(root.resolve()) or not path.is_file() or clip.get("pronunciationReview") not in {"dictionary_checked", "verified"}:
                missing.append(f"missing/unreviewed announcement: {clip.get('id')}")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != clip.get("sha256"):
                missing.append(f"announcement hash mismatch: {clip.get('id')}")
    runtime = root / ".tools/media-runtime"
    for name in ("ffmpeg.exe", "ffprobe.exe", "LICENSE.txt", "GPL-3.0.txt", "SOURCE.txt"):
        if not (runtime / name).is_file():
            missing.append(f"bundled encoder component missing: {name}")
    runtime_manifest = root / "data/media_runtime_manifest.json"
    if not runtime_manifest.is_file():
        missing.append("encoder version and checksum manifest missing")
    else:
        record = json.loads(runtime_manifest.read_text(encoding="utf-8"))
        for name, expected in record.get("files", {}).items():
            component = runtime / name
            if component.name != name or not component.is_file() or hashlib.sha256(component.read_bytes()).hexdigest() != expected:
                missing.append(f"encoder component changed: {name}")
    return missing


if __name__ == "__main__":
    problems = issues(Path(__file__).resolve().parent.parent)
    for problem in problems:
        print("FAIL:", problem)
    raise SystemExit(1 if problems else 0)
