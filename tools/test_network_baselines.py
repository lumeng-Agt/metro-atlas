#!/usr/bin/env python3
"""Validate official cutoff inventory, map references, and milestone records."""
from __future__ import annotations

import json
import copy
import sys
from pathlib import Path

from build_network_baseline import build
from expand_playable_milestones import ROUTE_DATES


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def main() -> int:
    cities_doc = read("data/cities.json")
    campaigns_doc = read("data/campaigns.json")
    baseline = read("data/network_baselines_2026-10-01.json")
    expected = build(cities_doc, campaigns_doc)
    failures: list[str] = []

    # Route membership is generated from the same source map and must match
    # exactly. Playable milestone metadata is then enriched by
    # expand_playable_milestones.py, so the chapter schedule is validated
    # structurally below rather than compared to the pre-expansion draft.
    if int(baseline.get("schemaVersion", 0)) != 2:
        failures.append("cutoff baseline schema must be version 2")
    for city_id, expected_city in expected.get("cities", {}).items():
        actual_city = baseline.get("cities", {}).get(city_id, {})
        if actual_city.get("routes") != expected_city.get("routes"):
            failures.append(f"{city_id}: cutoff route inventory is stale; rerun the baseline builder")

    # Baseline event snapshots must preserve the source sequence and task
    # scope of incremental targets, otherwise repeated generation nests range
    # suffixes and gradually changes the playable campaign.
    metadata_campaigns = copy.deepcopy(campaigns_doc)
    metadata_group = {
        "taskId": "range:test:range-1",
        "historicalLineId": "test-line",
        "name": "Test extension",
        "stationIds": ["B", "C"],
        "stationInstances": {"B": "body-B", "C": "body-C"},
        "constructionScope": "new_contiguous_range",
        "constructionScopeNote": "build only this contiguous range",
        "sourceStationIds": ["A", "B", "C", "D"],
        "sourceStationInstances": {"A": "body-A", "B": "body-B", "C": "body-C", "D": "body-D"},
    }
    metadata_campaigns["cities"]["shanghai"]["chapters"].append({
        "id": "test-incremental-baseline-metadata",
        "date": "1900-01-01",
        "title": "Test",
        "lineGroups": [metadata_group],
    })
    metadata_output = build(cities_doc, metadata_campaigns)
    metadata_event = next((
        event
        for event in metadata_output["cities"]["shanghai"]["documentedMilestones"]
        if event.get("chapterId") == "test-incremental-baseline-metadata"
    ), {})
    metadata_copy = next((
        group
        for group in metadata_event.get("targetLineGroups", [])
        if group.get("taskId") == metadata_group["taskId"]
    ), {})
    for field in ["constructionScope", "constructionScopeNote", "sourceStationIds", "sourceStationInstances", "stationInstances"]:
        if metadata_copy.get(field) != metadata_group.get(field):
            failures.append(f"baseline event snapshot dropped construction metadata field {field}")
    if baseline.get("cutoffDate") != "2026-10-01":
        failures.append("cutoff date must remain 2026-10-01")

    map_cities = {str(city["id"]): city for city in cities_doc.get("cities", [])}
    if set(baseline.get("cities", {})) != set(map_cities):
        failures.append("baseline must contain exactly the five bundled cities")

    for city_id, row in baseline.get("cities", {}).items():
        city = map_cities.get(city_id, {})
        projects = row.get("projectsAtCutoff", [])
        project_ids = [str(project.get("id", "")) for project in projects]
        if len(project_ids) != len(set(project_ids)):
            failures.append(f"{city_id}: duplicate cutoff project identifier")
        if not projects:
            failures.append(f"{city_id}: no cutoff construction/approved-plan inventory")
        valid_project_types = {
            "under_construction", "under_construction_or_planned", "approved_and_under_construction",
            "approved_project", "approved_plan", "public_consultation",
        }
        campaign_city = campaigns_doc.get("cities", {}).get(city_id, {})
        city_station_ids = {str(station.get("id", "")) for station in city.get("stations", [])}
        playable_plan_ids: set[str] = set()
        for plan in campaign_city.get("futurePlans", []):
            if str(plan.get("dataStatus", "")) != "blueprint_ready":
                continue
            if str(plan.get("exactAlignment", "")) not in {"station_areas", "corridor_only", "verified_alignment"}:
                continue
            groups = plan.get("lineGroups", [])
            if not isinstance(groups, list) or not groups:
                continue
            groups_ready = True
            for group in groups:
                station_ids = [str(value) for value in group.get("stationIds", [])]
                if len(station_ids) < 2 or float(group.get("toleranceM", 0)) <= 0 or not set(station_ids).issubset(city_station_ids):
                    groups_ready = False
                    break
                if not group.get("stationOrderSource") and not group.get("source") and not plan.get("source"):
                    groups_ready = False
                    break
            if groups_ready:
                playable_plan_ids.update(str(value) for value in plan.get("projectIds", []))
        for project in projects:
            project_id = str(project.get("id", ""))
            for field in ["name", "status", "source", "sourceTitle", "note", "sourceCheckedAt", "playabilityStatus"]:
                if not str(project.get(field, "")).strip():
                    failures.append(f"{city_id}/{project_id}: cutoff project missing {field}")
            if str(project.get("projectType", "")) not in valid_project_types:
                failures.append(f"{city_id}/{project_id}: invalid project type")
            status = str(project.get("playabilityStatus", ""))
            if status not in {"registered_geometry_and_playable_task_pending", "playable_build_task", "policy_only_not_playable", "engineering_works_only"}:
                failures.append(f"{city_id}/{project_id}: invalid playable-task status")
            if status == "playable_build_task" and project_id not in playable_plan_ids:
                failures.append(f"{city_id}/{project_id}: marked playable without a ready, selectable construction plan")
            if status == "registered_geometry_and_playable_task_pending" and project_id in playable_plan_ids:
                failures.append(f"{city_id}/{project_id}: build plan is ready but project inventory still says pending")
        for plan in campaign_city.get("futurePlans", []):
            if str(plan.get("dataStatus", "")) == "blueprint_ready":
                continue
            if bool(plan.get("required", False)):
                failures.append(f"{city_id}/{plan.get('id')}: plan without a ready blueprint must not block the free stage")
            if plan.get("lineGroups"):
                failures.append(f"{city_id}/{plan.get('id')}: plan without a ready blueprint must not declare line groups")
        if city_id == "guangzhou" and "gz-line13-phase2-east" in project_ids:
            failures.append("guangzhou: Line 13 Phase II east segment opened in 2025 and must not be listed as an unbuilt cutoff project")
        map_lines = {str(line.get("id", "")): line for line in city.get("lines", [])}
        inventory = row.get("routes", [])
        ids = [str(item.get("mapRouteId", "")) for item in inventory]
        if len(ids) != len(set(ids)):
            failures.append(f"{city_id}: duplicate route identifier")
        if set(ids) != set(map_lines):
            failures.append(f"{city_id}: cutoff route rows do not match bundled map relation IDs")
        known_stations = {str(station.get("id", "")) for station in city.get("stations", [])}
        for route in inventory:
            if route.get("cutoffStatus") != "open_at_cutoff":
                failures.append(f"{city_id}/{route.get('mapRouteId')}: missing cutoff opening status")
            if not route.get("stationOrderSource") or not route.get("routeRelations"):
                failures.append(f"{city_id}/{route.get('mapRouteId')}: missing geometry provenance")
            for station_id in route.get("cutoffStationIds", []):
                if station_id not in known_stations:
                    failures.append(f"{city_id}/{route.get('mapRouteId')}: unknown station {station_id}")
        for milestone in row.get("documentedMilestones", []):
            if not milestone.get("id") or not milestone.get("date") or milestone.get("date", "") > baseline["cutoffDate"]:
                failures.append(f"{city_id}: invalid or post-cutoff milestone {milestone.get('id')}")
            if not milestone.get("source"):
                failures.append(f"{city_id}/{milestone.get('id')}: missing source")
            for route_id in milestone.get("routeIds", []):
                if route_id not in map_lines:
                    failures.append(f"{city_id}/{milestone.get('id')}: unknown route {route_id}")

        schedule = row.get("milestoneChapters", [])
        if not schedule or schedule[-1].get("contentStatus") != "network_reconciliation_complete":
            failures.append(f"{city_id}: missing playable 2026-10-01 network-reconciliation milestone")
        previous_date = ""
        scheduled_event_ids: list[str] = []
        for milestone_chapter in schedule:
            if milestone_chapter.get("periodStartExclusive", "") != previous_date:
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: interval is not contiguous")
            end_date = str(milestone_chapter.get("periodEndInclusive", ""))
            if not end_date or end_date < previous_date or end_date > baseline["cutoffDate"]:
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: invalid interval end")
            status = milestone_chapter.get("contentStatus")
            if status in {"playable_sample", "playable_milestone"} and not milestone_chapter.get("playableChapterId"):
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: playable interval lacks a stable chapter id")
            if status in {"playable_sample", "playable_milestone"} and not milestone_chapter.get("chapterTargetGroups") and not milestone_chapter.get("eventOnly"):
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: construction milestone lacks target groups and is not marked as a source-only node")
            if status == "content_missing" and milestone_chapter.get("playableChapterId"):
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: missing interval is incorrectly playable")
            for route_id in milestone_chapter.get("targetMapRouteIds", milestone_chapter.get("routeIds", [])):
                if route_id not in map_lines:
                    failures.append(f"{city_id}/{milestone_chapter.get('id')}: unknown route {route_id}")
            scheduled_event_ids.extend(str(event_id) for event_id in milestone_chapter.get("eventIds", []))
            if milestone_chapter is not schedule[-1] and milestone_chapter.get("contentStatus") not in {"playable_sample", "playable_milestone"}:
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: unexpected non-final interval status")
            if milestone_chapter is not schedule[-1] and not milestone_chapter.get("chapterIds") and not any(event.get("status") in {"opened_or_completed", "opened_or_operated", "trial_operation", "built_not_publicly_operated"} for event in milestone_chapter.get("events", [])):
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: interval is not bounded by a construction milestone")
            previous_date = end_date
        expected_event_ids = [str(event.get("id", "")) for event in row.get("documentedMilestones", [])]
        if sorted(scheduled_event_ids) != sorted(expected_event_ids):
            failures.append(f"{city_id}: milestone ledger events are missing or duplicated across chapter intervals")
        if schedule and set(schedule[-1].get("targetMapRouteIds", [])) != set(ids):
            failures.append(f"{city_id}: final cutoff milestone does not target every map route row")

        chapter_ids = {str(chapter.get("id", "")) for chapter in campaigns_doc.get("cities", {}).get(city_id, {}).get("chapters", [])}
        for event in row.get("documentedMilestones", []):
            if str(event.get("chapterId", "")) not in chapter_ids:
                failures.append(f"{city_id}/{event.get('id')}: dated source event is not attached to a timeline chapter")
        for milestone_chapter in schedule:
            chapter_rows = [
                chapter for chapter in campaigns_doc.get("cities", {}).get(city_id, {}).get("chapters", [])
                if str(chapter.get("id", "")) in milestone_chapter.get("chapterIds", [])
            ]
            if milestone_chapter.get("eventOnly") and any(chapter.get("lineGroups") for chapter in chapter_rows):
                failures.append(f"{city_id}/{milestone_chapter.get('id')}: source-only node hides a construction task")

    shenzhen = baseline["cities"]["shenzhen"]
    expected_shenzhen = {f"shenzhen-r{i}" for i in range(1, 15)} | {"shenzhen-r15", "shenzhen-r16", "shenzhen-r17"}
    if {str(route["mapRouteId"]) for route in shenzhen["routes"]} != expected_shenzhen:
        failures.append("Shenzhen official 1–14, 16, 20 and Line 6 branch inventory is incomplete")
    shenzhen_recent = {item["id"] for item in shenzhen["documentedMilestones"]}
    if "shenzhen-2026-06-28-line13-north" not in shenzhen_recent:
        failures.append("Shenzhen Line 13 north extension milestone is missing")

    # Every cutoff line must first become a real, selectable construction task
    # before the final whole-network reconciliation. A map inventory row or a
    # context-only chapter does not satisfy this requirement.
    for city_id, config in campaigns_doc.get("cities", {}).items():
        chapters = config.get("chapters", [])
        cutoff = next((row for row in chapters if row.get("chapterScope") == "cutoff_reconciliation"), None)
        if cutoff is None:
            failures.append(f"{city_id}: cutoff chapter missing")
            continue
        cutoff_lines = {str(group.get("historicalLineId", "")) for group in cutoff.get("lineGroups", [])}
        earlier_lines: set[str] = set()
        for chapter in chapters:
            if str(chapter.get("date", "")) >= "2026-10-01":
                continue
            groups = chapter.get("lineGroups", [])
            if not groups:
                if not chapter.get("eventOnly") or not chapter.get("source"):
                    failures.append(f"{city_id}/{chapter.get('id')}: empty chapter must be explicitly source-only")
                continue
            for group in groups:
                line_id = str(group.get("historicalLineId", ""))
                if len(group.get("stationIds", [])) < 2 or not line_id:
                    failures.append(f"{city_id}/{chapter.get('id')}: construction task lacks ordered station targets")
                if float(group.get("toleranceM", 0)) <= 0:
                    failures.append(f"{city_id}/{chapter.get('id')}/{line_id}: task missing a positive station-area tolerance")
                if not (group.get("source") or chapter.get("source")):
                    failures.append(f"{city_id}/{chapter.get('id')}/{line_id}: task has no source provenance")
                if not (group.get("stationOrderSource") or group.get("source") or chapter.get("source")):
                    failures.append(f"{city_id}/{chapter.get('id')}/{line_id}: station order has no provenance")
                earlier_lines.add(line_id)
            groups_by_line: dict[str, list[dict]] = {}
            for group in groups:
                groups_by_line.setdefault(str(group.get("historicalLineId", "")), []).append(group)
            for line_id, same_line_groups in groups_by_line.items():
                if len(same_line_groups) <= 1:
                    continue
                # A single milestone may add two disconnected ranges to the
                # same line (for example, both ends of an existing corridor).
                # Permit only explicitly split, individually identified ranges.
                task_ids = [str(group.get("taskId", "")) for group in same_line_groups]
                if any(group.get("constructionScope") != "new_contiguous_range" for group in same_line_groups) or len(task_ids) != len(set(task_ids)) or any(not task_id for task_id in task_ids):
                    failures.append(f"{city_id}/{chapter.get('id')}: duplicate construction task for {line_id} is not a set of explicit contiguous additions")
        missing_lines = sorted(cutoff_lines - earlier_lines)
        if missing_lines:
            failures.append(f"{city_id}: cutoff lines only appear in final reconciliation, missing earlier build tasks: {missing_lines}")

        # A complete current-map route may only be introduced at or after its
        # curated last-opening milestone. This catches modern line snapshots
        # accidentally copied into an unrelated earlier chapter.
        cutoff_groups = {str(group.get("mapRouteId", "")): group for group in cutoff.get("lineGroups", [])}
        for chapter_row in chapters:
            if str(chapter_row.get("date", "")) >= "2026-10-01":
                continue
            for group in chapter_row.get("lineGroups", []):
                route_id = str(group.get("mapRouteId", ""))
                target = cutoff_groups.get(route_id)
                if target is None:
                    continue
                if set(str(x) for x in group.get("stationIds", [])) == set(str(x) for x in target.get("stationIds", [])):
                    last_open = ROUTE_DATES.get(city_id, {}).get(route_id, "")
                    if last_open and str(chapter_row.get("date", "")) < last_open:
                        failures.append(f"{city_id}/{chapter_row.get('id')}/{route_id}: full cutoff route appears before its last-opening milestone {last_open}")

    # The recently mis-staged Shenzhen and Shanghai segments are deliberately
    # small deltas around the prior terminal, not full modern line snapshots.
    def chapter(city_id: str, date: str):
        return next((row for row in campaigns_doc["cities"][city_id]["chapters"] if str(row.get("date", "")) == date), {})

    def group_for(row, prefix: str):
        return next((group for group in row.get("lineGroups", []) if str(group.get("historicalLineId", "")).startswith(prefix)), None)

    expected_segment_sizes = {
        ("shenzhen", "2022-10-28", "shenzhen-line11"): 2,
        ("shenzhen", "2023-12-27", "shenzhen-line8"): 5,
        ("shenzhen", "2024-12-28", "shenzhen-line3"): 8,
        ("shenzhen", "2024-12-28", "shenzhen-line7"): 3,
        ("shenzhen", "2024-12-28", "shenzhen-line11"): 2,
        ("shenzhen", "2024-12-28", "shenzhen-line12"): 7,
        ("shenzhen", "2024-12-28", "shenzhen-line13"): 7,
        ("shenzhen", "2025-12-28", "shenzhen-line5"): 4,
        ("shenzhen", "2025-12-28", "shenzhen-line8"): 2,
        ("shenzhen", "2025-12-28", "shenzhen-line11"): 3,
        ("shenzhen", "2025-12-28", "shenzhen-line13"): 9,
        ("shenzhen", "2026-06-28", "shenzhen-line13"): 12,
        ("shanghai", "2025-12-27", "shanghai-line18"): 6,
    }
    for (city_id, date, line_prefix), expected_count in expected_segment_sizes.items():
        row = chapter(city_id, date)
        group = group_for(row, line_prefix)
        if group is None or len(group.get("stationIds", [])) != expected_count:
            actual = len(group.get("stationIds", [])) if group else 0
            failures.append(f"{city_id}/{date}/{line_prefix}: expected source-backed opening segment of {expected_count} station areas, got {actual}")
    sz_2025 = chapter("shenzhen", "2025-12-28")
    if any(str(group.get("historicalLineId", "")).startswith("shenzhen-line12") for group in sz_2025.get("lineGroups", [])):
        failures.append("Shenzhen Line 12 Phase II is incorrectly staged in the 2025 chapter")
    sz_2023 = chapter("shenzhen", "2023-12-27")
    if not sz_2023 or not sz_2023.get("historicalEventIds"):
        failures.append("Shenzhen's 2023 Line 8 phase-II opening is not attached to a playable chapter")

    beijing = baseline["cities"]["beijing"]
    if beijing.get("officialRouteCount") != 30 or beijing.get("mapRouteEntryCount") != 24:
        failures.append("Beijing must preserve the published 30-route count vs 24 local relations discrepancy")

    minimum_project_counts = {"shanghai": 8, "beijing": 8, "guangzhou": 3, "shenzhen": 9, "chengdu": 1}
    for city_id, expected_count in minimum_project_counts.items():
        actual_count = len(baseline.get("cities", {}).get(city_id, {}).get("projectsAtCutoff", []))
        if actual_count < expected_count:
            failures.append(f"{city_id}: project inventory has {actual_count} rows; expected at least {expected_count} sourced project records")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    totals = {city: {"officialRoutes": item.get("officialRouteCount"), "mapRelations": item["mapRouteEntryCount"], "mapStations": item["mapUniqueStationCount"], "milestones": item["documentedMilestoneCount"], "milestoneIntervals": item["milestoneChapterCount"]} for city, item in baseline["cities"].items()}
    print("PASS: cutoff network baseline", json.dumps(totals, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
