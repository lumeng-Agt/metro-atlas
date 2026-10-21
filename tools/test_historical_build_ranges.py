#!/usr/bin/env python3
"""Verify incremental construction tasks are contiguous and reuse earlier stops."""
from __future__ import annotations

import json
import copy
from pathlib import Path

from expand_historical_event_chapters import incrementalize_build_groups


def group(task_id: str, ids: list[str]) -> dict:
    return {"taskId": task_id, "historicalLineId": "line-a", "name": "Line A", "stationIds": ids}


def main() -> None:
    failures: list[str] = []

    demo = [
        {"id": "a", "date": "2000-01-01", "lineGroups": [group("initial", ["A", "B", "C"])]},
        {"id": "b", "date": "2005-01-01", "lineGroups": [group("extension", ["A", "B", "C", "D", "E"])]},
        {"id": "c", "date": "2010-01-01", "lineGroups": [group("extension-2", ["A", "B", "C", "D", "E", "F"])]},
        {"id": "audit", "date": "2026-10-01", "chapterScope": "cutoff_reconciliation", "lineGroups": [group("cutoff", ["A", "B", "C", "D", "E", "F"])]},
    ]
    result = incrementalize_build_groups(demo, "2026-10-01")
    expected = [["C", "D", "E"], ["E", "F"]]
    actual = [chapter["lineGroups"][0]["stationIds"] for chapter in demo[1:3]]
    if actual != expected:
        failures.append(f"later extensions should keep only the new run and its existing terminal anchor: {actual}")
    if demo[-1]["lineGroups"][0]["stationIds"] != ["A", "B", "C", "D", "E", "F"]:
        failures.append("final network audit must retain the full reference route")
    if result["groupsReducedToNewRanges"] != 2:
        failures.append(f"expected two route snapshots to be reduced, got {result}")
    first_pass = copy.deepcopy(demo)
    incrementalize_build_groups(demo, "2026-10-01")
    if demo != first_pass:
        failures.append("running the incremental range generator twice must produce identical targets and task IDs")

    transitioned = [
        {
            "id": "transition",
            "date": "2020-01-01",
            "serviceTransitions": [{"id": "open-west", "stationIds": ["B", "C"]}],
            "lineGroups": [
                {
                    **group("route:line-a:range-2:range-1", ["B", "C"]),
                    "constructionScope": "new_contiguous_range",
                    "constructionScopeNote": "generated range",
                    "sourceStationIds": ["A", "B", "C", "D"],
                }
            ],
        }
    ]
    incrementalize_build_groups(transitioned, "2026-10-01")
    transitioned_once = copy.deepcopy(transitioned)
    incrementalize_build_groups(transitioned, "2026-10-01")
    transition_group = transitioned[0]["lineGroups"][0]
    if transitioned != transitioned_once:
        failures.append("service-transition ranges must be stable across generator runs")
    if transition_group["stationIds"] != ["B", "C"] or transition_group["taskId"] != "route:line-a" or "constructionScope" in transition_group:
        failures.append("service-transition target order must stay exact while nested range IDs are normalized")

    split = [
        {"id": "a", "date": "2000-01-01", "lineGroups": [group("west", ["A", "B"]), group("east", ["E", "F"])]},
        {"id": "b", "date": "2005-01-01", "lineGroups": [group("infill", ["A", "B", "C", "D", "E", "F", "G"])]},
    ]
    incrementalize_build_groups(split, "2026-10-01")
    split_groups = split[1]["lineGroups"]
    split_ids = [item["stationIds"] for item in split_groups]
    if split_ids != [["B", "C", "D", "E"], ["F", "G"]]:
        failures.append(f"multiple new runs must stay separate and attach to previous built terminals: {split_ids}")

    campaigns = json.loads(Path("data/campaigns.json").read_text(encoding="utf-8"))
    for city_id, city in campaigns.get("cities", {}).items():
        built_by_line: dict[str, set[str]] = {}
        incremental_count = 0
        for chapter in sorted(city.get("chapters", []), key=lambda row: (str(row.get("date", "")), str(row.get("id", "")))):
            if str(chapter.get("date", "")) >= "2026-10-01":
                continue
            for item in chapter.get("lineGroups", []):
                line_id = str(item.get("historicalLineId", ""))
                ids = [str(value) for value in item.get("stationIds", [])]
                if item.get("constructionScope") == "new_contiguous_range":
                    incremental_count += 1
                    source_ids = [str(value) for value in item.get("sourceStationIds", [])]
                    start = -1
                    for index in range(max(0, len(source_ids) - len(ids) + 1)):
                        if source_ids[index:index + len(ids)] == ids:
                            start = index
                            break
                    if start < 0:
                        failures.append(f"{city_id}/{chapter.get('id')}: incremental target is not a contiguous slice of its source order")
                    new_positions = [index for index, station_id in enumerate(ids) if station_id not in built_by_line.get(line_id, set())]
                    if not new_positions:
                        failures.append(f"{city_id}/{chapter.get('id')}: incremental range adds no new station target")
                    elif new_positions != list(range(new_positions[0], new_positions[-1] + 1)):
                        failures.append(f"{city_id}/{chapter.get('id')}: new station targets are not contiguous")
                built_by_line.setdefault(line_id, set()).update(ids)
        if incremental_count == 0:
            failures.append(f"{city_id}: no later construction ranges were reduced to incremental targets")

    if failures:
        raise SystemExit("\n".join("FAIL: " + item for item in failures))
    print("PASS: incremental historical construction ranges", result)


if __name__ == "__main__":
    main()
