"""Fail release checks on missing challenge/audio/runtime content, not UI counts."""
from __future__ import annotations

import json
from pathlib import Path


def issues(root: Path) -> list[str]:
    bank = json.loads((root / "data/challenges.json").read_text(encoding="utf-8"))
    missing = []
    for city in ("shanghai", "beijing", "guangzhou", "shenzhen", "chengdu"):
        eligible = [q for q in bank.get("locations", [])
                    if q.get("cityId") == city and q.get("reviewStatus") == "verified"
                    and isinstance(q.get("positionErrorM"), (int, float))
                    and 0 <= q["positionErrorM"] <= 25 and q.get("source")]
        if len(eligible) < 5:
            missing.append(f"{city}: only {len(eligible)}/5 independently reviewed location questions")
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
            if not path.is_relative_to(root.resolve()) or not path.is_file() or clip.get("pronunciationReview") != "verified":
                missing.append(f"missing/unreviewed announcement: {clip.get('id')}")
    runtime = root / ".tools/media-runtime"
    for name in ("ffmpeg.exe", "ffprobe.exe", "LICENSE.txt", "SOURCE.txt"):
        if not (runtime / name).is_file():
            missing.append(f"bundled encoder component missing: {name}")
    return missing


if __name__ == "__main__":
    problems = issues(Path(__file__).resolve().parent.parent)
    for problem in problems:
        print("FAIL:", problem)
    raise SystemExit(1 if problems else 0)
