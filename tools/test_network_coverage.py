#!/usr/bin/env python3
"""Regression checks for cutoff-aware playable coverage reporting."""
from __future__ import annotations

from pathlib import Path

from audit_network_coverage import build_report, read_json


def main() -> None:
    cities = read_json(Path("data/cities.json"))
    campaigns = read_json(Path("data/campaigns.json"))
    baseline = read_json(Path("data/network_baselines_2026-10-01.json"))
    report = build_report(cities, campaigns, baseline, "2026-10-01")
    rows = {row["cityId"]: row for row in report["cities"]}
    failures: list[str] = []
    if len(rows) != 5:
        failures.append("coverage report must contain five cities")
    for city_id, baseline_city in baseline["cities"].items():
        city = rows[city_id]
        by_route = {route["mapRouteId"]: route for route in city["mapRoutes"]}
        for cutoff_route in baseline_city["routes"]:
            route_id = cutoff_route["mapRouteId"]
            if by_route[route_id]["stationCount"] != len(cutoff_route["cutoffStationIds"]):
                failures.append(f"{city_id}/{route_id}: report did not use cutoff station membership")
            if set(by_route[route_id]["stationIds"]) & {item["stationId"] for item in cutoff_route.get("excludedStations", [])}:
                failures.append(f"{city_id}/{route_id}: excluded station leaked into cutoff target coverage")
        if city["playableChapterCount"] != len(campaigns["cities"][city_id]["chapters"]):
            failures.append(f"{city_id}: playable chapter count mismatch")
        if city["projectInventoryCount"] != len(baseline_city.get("projectsAtCutoff", [])):
            failures.append(f"{city_id}: project inventory count mismatch")
        if city["playableProjectCount"] + city["pendingPlayableProjectCount"] != city["projectInventoryCount"]:
            failures.append(f"{city_id}: project status counts do not add up")
        project_ids = {str(project.get("id", "")) for project in baseline_city.get("projectsAtCutoff", [])}
        if not set(city["playableProjectIds"]).issubset(project_ids):
            failures.append(f"{city_id}: playable project task points outside the cutoff project inventory")
        declared_playable = {
            str(project.get("id", ""))
            for project in baseline_city.get("projectsAtCutoff", [])
            if str(project.get("playabilityStatus", "")) == "playable_build_task"
        }
        if declared_playable != set(city["playableProjectIds"]):
            failures.append(f"{city_id}: project inventory and validated construction-task coverage disagree")
        for project in city["projectsAtCutoff"]:
            if project["playableTaskStatus"] == "playable" and project["id"] not in city["playableProjectIds"]:
                failures.append(f"{city_id}/{project['id']}: project marked playable without a linked build plan")
    if failures:
        raise SystemExit("\n".join(f"FAIL: {message}" for message in failures))
    print("PASS: cutoff-aware five-city route coverage", {key: {"playableChapters": value["playableChapterCount"], "cutoffStations": value["mapUniqueRouteStationCount"], "uncoveredStations": len(value["currentMapStationsNeverTargetedByAnyPlayableChapter"])} for key, value in rows.items()})


if __name__ == "__main__":
    main()
