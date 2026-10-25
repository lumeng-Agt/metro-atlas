#!/usr/bin/env python3
"""Validate project-chapter specs before they are written into game data.

Runs independently of add_project_plan.py so a spec can be reviewed in CI and
in pull requests. It checks geometry plausibility, source bookkeeping and the
station/transfer identity rules that the campaign loader also enforces.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CITY_PATH = ROOT / "data/cities.json"
CAMPAIGNS_PATH = ROOT / "data/campaigns.json"

MIN_SPACING_M = 300.0
MAX_SPACING_M = 8000.0
MAX_CITY_DISTANCE_M = 70000.0
MAX_LENGTH_DEVIATION = 0.20
FOLD_BACK_DEGREES = 120.0
COORDINATE_SOURCES = {
    "existing_station",
    "official_chainage",
    "official_site_description",
    "local_road_geometry",
    "local_osm_station_node",
    "official_project_statement_and_local_road_geometry",
}


def distance_m(a: list[float], b: list[float]) -> float:
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371000.0 * 2 * math.asin(min(1.0, math.sqrt(h)))


def bearing_delta(a: list[float], b: list[float], c: list[float]) -> float:
    scale = math.cos(math.radians(a[0]))
    first = math.atan2((b[1] - a[1]) * scale, b[0] - a[0])
    second = math.atan2((c[1] - b[1]) * scale, c[0] - b[0])
    delta = abs(math.degrees(second - first)) % 360.0
    return min(delta, 360.0 - delta)


def validate(spec: dict, city: dict, existing_lines: set[str]) -> list[str]:
    errors: list[str] = []
    city_id = str(spec.get("city", ""))
    if city_id != str(city.get("id", "")):
        errors.append(f"spec city {city_id} does not match city data {city.get('id')}")
        return errors
    plan = spec.get("plan", {})
    for field in ["id", "title", "status", "sourceType", "source", "sourceTitle", "sourceCheckedAt", "description"]:
        if not str(plan.get(field, "")).strip():
            errors.append(f"plan.{field} is required")
    if "sourcePublicationDate" not in plan:
        errors.append("plan.sourcePublicationDate is required (null with publicationDateNote when unknown)")
    if plan.get("sourcePublicationDate") is None and not str(plan.get("publicationDateNote", "")).strip():
        errors.append("null sourcePublicationDate needs publicationDateNote")

    stations = {str(entry.get("id") or entry.get("name", "")): entry for entry in spec.get("stations", [])}
    name_to_id = {str(entry.get("name", "")): str(entry.get("id") or entry.get("name", "")) for entry in spec.get("stations", [])}
    city_stations = {str(row.get("id", "")): row for row in city.get("stations", [])}

    for station_id, entry in stations.items():
        name = str(entry.get("name", ""))
        if not name:
            errors.append(f"station {station_id}: name is required")
        if not station_id.startswith(city_id + "-"):
            errors.append(f"station {name}: id must start with {city_id}-")
        if entry.get("existing"):
            if station_id not in city_stations:
                errors.append(f"station {name}: existing station {station_id} is missing from city data")
            continue
        latlng = entry.get("latlng")
        if not isinstance(latlng, list) or len(latlng) != 2:
            errors.append(f"station {name}: new station needs [lat, lon]")
            continue
        source = str(entry.get("coordinateSource", "official_site_description"))
        if source not in COORDINATE_SOURCES:
            errors.append(f"station {name}: coordinateSource {source} is not allowed")
        if not str(entry.get("coordinateNote", "")).strip():
            errors.append(f"station {name}: coordinateNote is required")

    groups = spec.get("lineGroups")
    if groups is None:
        legacy = spec.get("lineGroup")
        if not isinstance(legacy, dict):
            errors.append("spec needs lineGroups[] or lineGroup")
            return errors
        groups = [dict(legacy, stationIds=legacy.get("stationIds", [str(entry.get("id") or entry["name"]) for entry in spec.get("stations", [])]))]

    for index, group in enumerate(groups):
        key = str(group.get("key") or index + 1)
        values = [str(value) for value in group.get("stationIds", [])]
        ids = [name_to_id.get(value, value) for value in values]
        if len(ids) < 2:
            errors.append(f"group {key}: fewer than two stations")
            continue
        if len(set(ids)) != len(ids):
            errors.append(f"group {key}: duplicate station in order")
        if not str(group.get("precisionNote", "")).strip():
            errors.append(f"group {key}: precisionNote is required")
        if "stationNamingSource" in group:
            naming_source = group["stationNamingSource"]
            if not isinstance(naming_source, str) or not naming_source.startswith(("https://", "http://")):
                errors.append(f"group {key}: stationNamingSource needs a public source URL")
            if not group.get("constructionVariant"):
                errors.append(f"group {key}: planning names require a separate constructionVariant")
        points: list[list[float]] = []
        for station_id in ids:
            entry = stations.get(station_id)
            if entry is None:
                errors.append(f"group {key}: station {station_id} is not declared in stations[]")
                continue
            if entry.get("existing"):
                if station_id in city_stations:
                    points.append(city_stations[station_id]["latlng"])
            elif entry.get("latlng"):
                points.append(entry["latlng"])
        if len(points) != len(ids):
            continue
        center = [float(city.get("center", [0, 0])[0]), float(city.get("center", [0, 0])[1])]
        for station_id, point in zip(ids, points):
            if distance_m(point, center) > MAX_CITY_DISTANCE_M:
                errors.append(f"group {key}: {station_id} is more than {int(MAX_CITY_DISTANCE_M / 1000)} km from the city centre")
        loop = bool(group.get("loop"))
        max_spacing = float(group.get("maxSpacingM", MAX_SPACING_M) or MAX_SPACING_M)
        total = 0.0
        for pair in range(len(points) - 1):
            spacing = distance_m(points[pair], points[pair + 1])
            total += spacing
            if spacing < MIN_SPACING_M or spacing > max_spacing:
                errors.append(f"group {key}: spacing {int(spacing)} m between {ids[pair]} and {ids[pair + 1]} is outside {int(MIN_SPACING_M)}–{int(max_spacing)} m")
        if loop and len(points) > 2:
            total += distance_m(points[-1], points[0])
        if not loop:
            for pair in range(1, len(points) - 1):
                delta = bearing_delta(points[pair - 1], points[pair], points[pair + 1])
                if delta > FOLD_BACK_DEGREES:
                    errors.append(f"group {key}: {ids[pair]} folds back {int(delta)}° between its neighbours")
        # Siting points are station centers. An engineering route length may
        # include end tunnels, so compare a published center-to-center span
        # when the official station chainage table supplies one.
        official = float(group.get("officialCenterSpanM", group.get("officialLengthM", 0)) or 0)
        if official > 0:
            deviation = abs(total - official) / official
            if deviation > MAX_LENGTH_DEVIATION:
                errors.append(f"group {key}: corridor length {int(total)} m deviates {deviation:.0%} from the official {int(official)} m")
        station_ids = set(ids)
        for station_id in (group.get("stationInstances") or {}):
            if station_id not in station_ids:
                errors.append(f"group {key}: stationInstances key {station_id} is not in this group")

    task_ids: set[str] = set()
    for index, group in enumerate(groups):
        task_id = str(group.get("taskId", f"group-{index}"))
        if task_id in task_ids:
            errors.append(f"duplicate taskId {task_id}")
        task_ids.add(task_id)

    plan_lines = {str(group.get("historicalLineId", "")) for group in groups}
    for transfer in spec.get("transfers", []):
        transfer_id = str(transfer.get("id", "?"))
        if not str(transfer.get("sourceNote", "")).strip():
            errors.append(f"transfer {transfer_id}: sourceNote is required")
        line_ids = [str(value) for value in transfer.get("lineIds", [])]
        if len(line_ids) < 2:
            errors.append(f"transfer {transfer_id}: needs at least two line ids")
            continue
        if len(set(line_ids)) != len(line_ids):
            errors.append(f"transfer {transfer_id}: line ids must be distinct")
        if not any(line_id in plan_lines for line_id in line_ids):
            errors.append(f"transfer {transfer_id}: no line belongs to this plan")
        body_ids=transfer.get("stationInstanceIds",[])
        if len(body_ids)!=len(line_ids) or len(set(body_ids))!=len(body_ids):
            errors.append(f"transfer {transfer_id}: each distinct line needs its own physical body")
        # A single approved project can build two separate lines meeting at
        # the same complex (Guangzhou's Jiangfu is such a sourced case).
        for other_line in line_ids:
            if other_line not in plan_lines and other_line not in existing_lines and not other_line.endswith("-future-line"):
                errors.append(f"transfer {transfer_id}: unknown existing line {other_line}")
    return errors


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("specs", nargs="*")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()
    paths = [Path(value) for value in args.specs]
    if args.all or not paths:
        paths = sorted((ROOT / "tools/project_specs").glob("*.json"))
    cities = {row["id"]: row for row in json.loads(CITY_PATH.read_text(encoding="utf-8"))["cities"]}
    campaigns = json.loads(CAMPAIGNS_PATH.read_text(encoding="utf-8"))
    existing_lines: set[str] = set()
    for config in campaigns["cities"].values():
        for chapter in config.get("chapters", []):
            existing_lines.update(str(group.get("historicalLineId", "")) for group in chapter.get("lineGroups", []))
        for plan in config.get("futurePlans", []):
            existing_lines.update(str(group.get("historicalLineId", "")) for group in plan.get("lineGroups", []))
    failures = 0
    for path in paths:
        spec = json.loads(path.read_text(encoding="utf-8"))
        city = cities.get(str(spec.get("city", "")), {})
        errors = validate(spec, city, existing_lines)
        if errors:
            failures += 1
            print(f"FAIL {path.name}")
            for error in errors:
                print("  - " + error)
        else:
            print(f"PASS {path.name}")
    if failures:
        raise SystemExit(f"{failures} spec(s) failed validation")
    print(f"PASS: {len(paths)} project spec(s)")


if __name__ == "__main__":
    main()
