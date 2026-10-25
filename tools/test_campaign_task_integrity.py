"""Check that campaign build targets belong to their declared city and route."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CAMPAIGNS = json.loads((ROOT / "data/campaigns.json").read_text(encoding="utf-8"))
CITIES = json.loads((ROOT / "data/cities.json").read_text(encoding="utf-8"))
city_data = {city["id"]: city for city in CITIES["cities"]}
station_ids_by_city = {
    str(city["id"]): {str(station.get("id", "")) for station in city.get("stations", [])}
    for city in CITIES["cities"]
}
errors: list[str] = []
checked_groups = 0


def check_group(city_id: str, chapter_id: str, group: dict, location: str) -> None:
    global checked_groups
    checked_groups += 1
    map_route_id = str(group.get("mapRouteId", ""))
    if not map_route_id:
        return
    city = city_data.get(city_id)
    if city is None:
        errors.append(f"{city_id}/{chapter_id}/{location}: city data missing")
        return
    known_station_ids = station_ids_by_city.get(city_id, set())
    for field in ("stationIds", "sourceStationIds"):
        unknown = [str(value) for value in group.get(field, []) if str(value) not in known_station_ids]
        if unknown:
            errors.append(f"{city_id}/{chapter_id}/{location}: {field} references unknown map stations {unknown[:8]}")
    route = next((line for line in city.get("lines", []) if line.get("id") == map_route_id), None)
    if route is None:
        # Future project alignments may use a project-local route ID. They
        # still must point at real bundled station areas; only cutoff routes
        # are required to match an OSM route relation.
        if not map_route_id.startswith(city_id + "-future-"):
            errors.append(f"{city_id}/{chapter_id}/{location}: map route {map_route_id} not found")
        return
    route_value = route.get("stationIds", [])
    if isinstance(route_value, str):
        route_ids = set(route_value.split())
    else:
        route_ids = set(str(value) for value in route_value)
    for extra_route_id, evidence in group.get('additionalMapRouteSources', {}).items():
        extra = next((line for line in city.get('lines', []) if line.get('id') == extra_route_id), None)
        if extra is None or not str(evidence).startswith('https://'):
            errors.append(f'{city_id}/{chapter_id}/{location}: extra geographic route needs a real city route and documented lineage')
            continue
        route_ids.update(extra.get('stationIds', []))
    aliases = CAMPAIGNS['cities'][city_id].get('stationComplexAliases', {})
    def canonical(value):
        seen = set()
        while value in aliases and value not in seen:
            seen.add(value); value = aliases[value]
        return value
    reference_complexes = {canonical(value) for value in route_ids}
    # A closed historical stop may legitimately be absent from the modern
    # OSM service relation. Require its separately sourced physical object,
    # matching historical line and identical opening evidence; a free-form
    # exception or an arbitrary extra station is not sufficient.
    for historical_id,evidence in group.get('historicalStationSources',{}).items():
        station=next((s for s in city.get('stations',[]) if s['id']==historical_id),{})
        if (station.get('historicalOnly') is True and station.get('historicalLineId')==group.get('historicalLineId')
                and isinstance(evidence,str) and evidence.startswith('https://')
                and evidence==station.get('historicalOpeningSource')):
            reference_complexes.add(canonical(historical_id))
        else:
            errors.append(f'{city_id}/{chapter_id}/{location}: historical station {historical_id} lacks matching line and opening evidence')
    for field in ("stationIds", "sourceStationIds"):
        values = [str(value) for value in group.get(field, [])]
        foreign = [value for value in values if not value.startswith(city_id + "-")]
        missing = [value for value in values if value.startswith(city_id + "-") and canonical(value) not in reference_complexes]
        if foreign:
            errors.append(f"{city_id}/{chapter_id}/{location}: {field} has foreign station IDs {foreign[:5]}")
        if missing:
            errors.append(f"{city_id}/{chapter_id}/{location}: {field} not on {map_route_id}: {missing[:8]}")
    for historical_id, instance_id in group.get("stationInstances", {}).items():
        if canonical(historical_id) not in reference_complexes:
            errors.append(f"{city_id}/{chapter_id}/{location}: station instance key {historical_id} not on {map_route_id}")


for city_id, config in CAMPAIGNS.get("cities", {}).items():
    for chapter in config.get("chapters", []):
        chapter_id = str(chapter.get("id", "?"))
        for index, group in enumerate(chapter.get("lineGroups", [])):
            check_group(city_id, chapter_id, group, f"lineGroups[{index}]")
        for version_index, version in enumerate(chapter.get("story", {}).get("planVersions", [])):
            for group_index, group in enumerate(version.get("lineGroups", [])):
                check_group(city_id, chapter_id, group, f"planVersions[{version_index}].lineGroups[{group_index}]")
    for plan in config.get("futurePlans", []):
        for index, group in enumerate(plan.get("lineGroups", [])):
            check_group(city_id, str(plan.get("id", "?")), group, f"lineGroups[{index}]")


def chapter(city_id: str, date: str) -> dict:
    return next((row for row in CAMPAIGNS["cities"][city_id]["chapters"] if str(row.get("date", "")) == date), {})


def target_ids(city_id: str, date: str, line_id: str) -> list[str]:
    row = chapter(city_id, date)
    group = next((item for item in row.get("lineGroups", []) if str(item.get("mapRouteId", "")) == line_id), {})
    return [str(value) for value in group.get("stationIds", [])]


# These date-specific segments are cross-checked against opening milestones.
# They prevent the bundled modern route snapshot from being copied wholesale
# into the wrong historical chapter.
expected_segments = {
    ("shanghai", "2000-12-26", "shanghai-r3"): [
        "shanghai-s58", "shanghai-s57", "shanghai-s56", "shanghai-s55", "shanghai-s54",
        "shanghai-s53", "shanghai-s52", "shanghai-s51", "shanghai-s50", "shanghai-s49",
        "shanghai-s48", "shanghai-s47", "shanghai-s46", "shanghai-s45", "shanghai-s44",
        "shanghai-s20", "shanghai-s43", "shanghai-s42", "shanghai-s41",
    ],
    ("shanghai", "2006-12-18", "shanghai-r3"): [
        "shanghai-s31", "shanghai-s32", "shanghai-s33", "shanghai-s34", "shanghai-s35",
        "shanghai-s36", "shanghai-s37", "shanghai-s38", "shanghai-s39", "shanghai-s40", "shanghai-s41",
    ],
    ("guangzhou", "2006-12-30", "guangzhou-r4"): [
        "guangzhou-s60", "guangzhou-s59", "guangzhou-s58", "guangzhou-s57",
        "guangzhou-s56", "guangzhou-s54", "guangzhou-s53",
    ],
    ("guangzhou", "2007-06-28", "guangzhou-r4"): ["guangzhou-s53", "guangzhou-s52", "guangzhou-s51"],
    ("guangzhou", "2009-12-28", "guangzhou-r4"): ["guangzhou-s64", "guangzhou-s65"],
    ("guangzhou", "2010-09-25", "guangzhou-r4"): ["guangzhou-s65", "guangzhou-s66", "guangzhou-s67"],
    ("guangzhou", "2017-12-28", "guangzhou-r4"): [
        "guangzhou-s51", "guangzhou-s50", "guangzhou-s49", "guangzhou-s48", "guangzhou-s47", "guangzhou-s46", "guangzhou-s45",
    ],
}
for (city_id, date, route_id), expected in expected_segments.items():
    actual = target_ids(city_id, date, route_id)
    if actual != expected:
        errors.append(f"{city_id}/{date}/{route_id}: expected dated build segment {expected}, got {actual}")

# Preserve physical station identities for historically shared Line 3 bodies.
def task_group(city_id: str, date: str, task_id: str) -> dict:
    row = chapter(city_id, date)
    return next((
        item
        for item in row.get("lineGroups", [])
        if str(item.get("taskId", "")) == task_id
    ), {})


shanghai_cutoff_r3 = task_group("shanghai", "2026-10-01", "route:shanghai-r3")
for date, task_id in [
    ("2000-12-26", "route:shanghai-r3-phase1-2000"),
    ("2006-12-18", "route:shanghai-r3-north-extension-2006"),
]:
    historical_group = task_group("shanghai", date, task_id)
    target_station_ids = set(str(value) for value in historical_group.get("stationIds", []))
    expected_instances = {station_id: str(shanghai_cutoff_r3.get('stationInstances', {}).get(station_id, station_id)) for station_id in target_station_ids}
    actual_instances = {station_id: str(historical_group.get('stationInstances', {}).get(station_id, station_id)) for station_id in target_station_ids}
    if actual_instances != expected_instances:
        errors.append(
            f"shanghai/{date}/{task_id}: historical phase must preserve cutoff Line 3 body identities"
        )

# The 2025 Guangzhou Line 14 extension joins the existing line at Jiahe Wanggang.
# Xinhe belongs to the northern branch and is not adjacent to Lejia Road.
gz_line14_extension = task_group("guangzhou", "2025-09-29", "route:guangzhou-r14:range-1")
expected_gz_line14_extension = [
    "guangzhou-s231", "guangzhou-s232", "guangzhou-s233", "guangzhou-s234",
    "guangzhou-s235", "guangzhou-s236", "guangzhou-s237", "guangzhou-s144",
]
if gz_line14_extension.get("stationIds", []) != expected_gz_line14_extension:
    errors.append(
        "guangzhou/2025-09-29/route:guangzhou-r14:range-1: "
        "must build Lejia Road→Jiahe Wanggang without the unrelated Xinhe branch"
    )

shenzhen = city_data.get("shenzhen", {})
route2 = next((line for line in shenzhen.get("lines", []) if line.get("id") == "shenzhen-r2"), {})
expected_line2_west = ["shenzhen-s112", "shenzhen-s305", "shenzhen-s304", "shenzhen-s303", "shenzhen-s302"]
if route2:
    route2_ids = [str(value) for value in route2.get("stationIds", [])]
    if route2_ids[:len(expected_line2_west)] != expected_line2_west:
        errors.append(f"shenzhen/shenzhen-r2: western section must begin Chiwan → Shekou Port → Sea World → Shuiwan → Dongjiaotou, got {route2_ids[:5]}")

if errors:
    print(f"FAIL: campaign task route integrity ({len(errors)} issues; {checked_groups} groups checked)")
    for error in errors:
        print(" - " + error)
    raise SystemExit(1)

print(f"PASS: campaign task route integrity ({checked_groups} groups checked)")
