#!/usr/bin/env python3
"""Add one audited project chapter from an explicit JSON spec.

The spec is the review artifact: station order, station-area points, transfer
identities and the cited source all live in it. This tool only materializes the
spec into the campaign city data and marks the project playable; it does not
invent stations, coordinates or transfers.

Spec keys:
  city, projectIds, stations, lineGroups (or the legacy single lineGroup),
  transfers, plan

stations[]   : {name, id, latlng?, existing?, coordinateNote?, coordinateSource?, source?}
lineGroups[] : {key?, mapRouteId, name, historicalLineId, color?, stationIds,
                toleranceM?, alignmentPrecision?, precisionNote,
                stationOrderSource?, stationInstances?}

Run:
  python tools/add_project_plan.py tools/project_specs/<name>.json --check
  python tools/add_project_plan.py tools/project_specs/<name>.json --dry-run
  python tools/add_project_plan.py tools/project_specs/<name>.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN_PATH = ROOT / "data/campaigns.json"
CITY_PATH = ROOT / "data/cities.json"
BASELINE_PATH = ROOT / "data/network_baselines_2026-10-01.json"

COORDINATE_SOURCES = {
    "existing_station",
    "official_chainage",
    "official_site_description",
    "local_road_geometry",
    "local_osm_station_node",
    "official_project_statement_and_local_road_geometry",
}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def fail(message: str) -> None:
    raise SystemExit("spec error: " + message)


def normalize_groups(spec: dict) -> list[dict]:
    groups = spec.get("lineGroups")
    if groups is None:
        legacy = spec.get("lineGroup")
        if not isinstance(legacy, dict):
            fail("spec needs lineGroups[] or lineGroup")
        merged = dict(legacy, key="main")
        if spec.get("stationInstances") and not merged.get("stationInstances"):
            merged["stationInstances"] = spec["stationInstances"]
        if not merged.get("stationIds"):
            merged["stationIds"] = [str(entry.get("id") or entry["name"]) for entry in spec.get("stations", [])]
        groups = [merged]
    if not isinstance(groups, list) or not groups:
        fail("lineGroups must be a non-empty list")
    # Backward compatibility: an older spec kept one shared stationInstances
    # map at the top level. Only a single-group spec can use that form.
    top_level_instances = spec.get("stationInstances")
    if top_level_instances and len(groups) == 1 and not groups[0].get("stationInstances"):
        groups[0] = dict(groups[0], stationInstances=top_level_instances)
    return groups


def build_station_catalog(city: dict, spec: dict) -> tuple[dict[str, dict], dict[str, str], int]:
    station_rows = city.setdefault("stations", [])
    by_id = {str(row.get("id", "")): row for row in station_rows}
    by_name: dict[str, str] = {}
    for row in station_rows:
        by_name.setdefault(str(row.get("name", "")), str(row.get("id", "")))

    catalog: dict[str, dict] = {}
    new_count = 0
    plan_source = spec["plan"]["source"]
    for entry in spec["stations"]:
        name = str(entry["name"])
        station_id = str(entry.get("id") or by_name.get(name) or "")
        if not station_id:
            fail(f"station {name}: no id and no existing mapped station")
        if not station_id.startswith(str(city["id"]) + "-"):
            fail(f"station {name}: id {station_id} must start with {city['id']}-")
        if station_id in catalog:
            fail(f"station {name}: duplicate station id {station_id}")
        existing = bool(entry.get("existing"))
        if existing:
            if station_id not in by_id:
                fail(f"station {name}: existing station {station_id} is not in city data")
            record = {
                "id": station_id,
                "name": name,
                "latlng": [float(by_id[station_id]["latlng"][0]), float(by_id[station_id]["latlng"][1])],
                "existing": True,
            }
        else:
            latlng = entry.get("latlng")
            if not isinstance(latlng, list) or len(latlng) != 2:
                fail(f"station {name}: new station needs [lat, lon]")
            coordinate_source = str(entry.get("coordinateSource", "official_site_description"))
            if coordinate_source not in COORDINATE_SOURCES:
                fail(f"station {name}: unknown coordinateSource {coordinate_source}")
            record = {
                "id": station_id,
                "name": name,
                "latlng": [float(latlng[0]), float(latlng[1])],
                "existing": False,
                "coordinateSource": coordinate_source,
                "coordinateNote": str(entry.get("coordinateNote", "")),
                "source": str(entry.get("source", plan_source)),
                "coordinateAccuracyM": entry.get("coordinateAccuracyM"),
            }
            if not record["coordinateNote"]:
                fail(f"station {name}: new station needs a coordinateNote")
            if station_id in by_id:
                new_count += 0
            else:
                new_count += 1
        catalog[station_id] = record
    if len(catalog) < 2:
        fail("a project chapter needs at least two stations")
    return catalog, by_name, new_count


def resolve_group_station(value: str, catalog: dict[str, dict], by_name: dict[str, str]) -> str:
    if value in catalog:
        return value
    if value in by_name and by_name[value] in catalog:
        return by_name[value]
    fail(f"group references unknown station {value}")


def existing_line_ids(campaign: dict) -> set[str]:
    ids: set[str] = set()
    for chapter in campaign.get("chapters", []):
        for group in chapter.get("lineGroups", []):
            line_id = str(group.get("historicalLineId", ""))
            if line_id:
                ids.add(line_id)
    for plan in campaign.get("futurePlans", []):
        for group in plan.get("lineGroups", []):
            line_id = str(group.get("historicalLineId", ""))
            if line_id:
                ids.add(line_id)
    return ids


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("spec")
    parser.add_argument("--check", action="store_true", help="validate only, never write")
    parser.add_argument("--dry-run", action="store_true", help="print the plan summary and write nothing")
    args = parser.parse_args()

    spec = read(Path(args.spec))
    city_id = str(spec["city"])
    campaigns = read(CAMPAIGN_PATH)
    cities = read(CITY_PATH)
    baseline = read(BASELINE_PATH)
    campaign = campaigns["cities"][city_id]
    city = next(row for row in cities["cities"] if row["id"] == city_id)
    baseline_city = baseline["cities"][city_id]
    plan_spec = spec["plan"]

    catalog, by_name, new_station_count = build_station_catalog(city, spec)
    groups_spec = normalize_groups(spec)
    known_lines = existing_line_ids(campaign) | {str(g["historicalLineId"]) for g in groups_spec}

    task_ids: set[str] = set()
    groups: list[dict] = []
    multi = len(groups_spec) > 1
    for index, group_spec in enumerate(groups_spec):
        key = str(group_spec.get("key") or f"g{index + 1}")
        resolved_ids = [resolve_group_station(str(value), catalog, by_name) for value in group_spec["stationIds"]]
        if len(resolved_ids) < 2:
            fail(f"group {key}: needs at least two stations")
        if len(set(resolved_ids)) != len(resolved_ids):
            fail(f"group {key}: duplicate station in station order")
        default_task_id = f"project:{plan_spec['id']}" if not multi else f"project:{plan_spec['id']}:{key}"
        task_id = str(group_spec.get("taskId") or default_task_id)
        task_prefix = f"project:{plan_spec['id']}"
        if task_id != task_prefix and not task_id.startswith(task_prefix + ":"):
            fail(f"group {key}: taskId must belong to this project")
        if task_id in task_ids:
            fail(f"group {key}: duplicate taskId {task_id}")
        task_ids.add(task_id)
        instances = {str(k): str(v) for k, v in (group_spec.get("stationInstances") or {}).items()}
        for station_id in instances:
            if station_id not in resolved_ids:
                fail(f"group {key}: stationInstances key {station_id} is not in this group")
        if not str(group_spec.get("precisionNote", "")).strip():
            fail(f"group {key}: precisionNote is required")
        group = {
            "taskId": task_id,
            "mapRouteId": str(group_spec["mapRouteId"]),
            "name": str(group_spec["name"]),
            "historicalLineId": str(group_spec["historicalLineId"]),
            "color": str(group_spec.get("color", "#808080")),
            "stationIds": resolved_ids,
            "stationNames": {station_id: catalog[station_id]["name"] for station_id in resolved_ids},
            "toleranceM": float(group_spec.get("toleranceM", 500)),
            "alignmentPrecision": str(group_spec.get("alignmentPrecision", "corridor_only")),
            "precisionNote": str(group_spec["precisionNote"]),
            "stationOrderSource": str(group_spec.get("stationOrderSource", plan_spec["source"])),
            "requireOpen": False,
        }
        if instances:
            group["stationInstances"] = instances
        if group_spec.get('stationReferenceIds'):
            references = group_spec['stationReferenceIds']
            for identity, reference in references.items():
                if identity not in resolved_ids or reference not in catalog:
                    fail(f'group {key}: invalid line-specific station reference {identity}: {reference}')
            group['stationReferenceIds'] = references
        for field in ('loop', 'officialLengthM', 'officialCenterSpanM', 'coverageGroupId', 'servicePathRevision', 'constructionVariant', 'stationNamingSource', 'stationNamingSources', 'requiredPlanningCorridorId', 'planningCorridorToleranceM'):
            if field in group_spec:
                group[field] = group_spec[field]
        if float(group["toleranceM"]) <= 0:
            fail(f"group {key}: toleranceM must be positive")
        if not str(group["mapRouteId"]).startswith(city_id + "-future-"):
            fail(f"group {key}: mapRouteId must start with {city_id}-future-")
        groups.append(group)

    transfers = []
    transfer_ids: set[str] = set()
    for entry in spec.get("transfers", []):
        transfer_id = str(entry["id"])
        if transfer_id in transfer_ids:
            fail(f"duplicate transfer id {transfer_id}")
        transfer_ids.add(transfer_id)
        complex_id = str(entry["complexId"])
        if complex_id not in catalog:
            fail(f"transfer {transfer_id}: complexId {complex_id} is not one of this plan's stations")
        instance_ids = [str(value) for value in entry["stationInstanceIds"]]
        line_ids = [str(value) for value in entry["lineIds"]]
        if len(instance_ids) < 2 or len(instance_ids) != len(line_ids):
            fail(f"transfer {transfer_id}: needs matching bodies and line ids (at least two)")
        project_lines = sum(1 for line_id in line_ids if line_id in {str(g["historicalLineId"]) for g in groups_spec})
        if project_lines < 1 or len(set(line_ids)) != len(line_ids) or len(set(instance_ids)) != len(instance_ids):
            fail(f"transfer {transfer_id}: distinct lines and physical bodies, including a project line, are required")
        for line_id in line_ids:
            if line_id not in known_lines:
                fail(f"transfer {transfer_id}: unknown line {line_id}")
        # A multi-line project may construct both sides of an interchange.
        # Each project-side body must still belong to that explicit line group.
        for body, line_id in zip(instance_ids, line_ids):
            matching = [g for g in groups if g['historicalLineId'] == line_id]
            aliases = campaign.get('stationComplexAliases', {})
            canonical = lambda station_id: aliases.get(station_id, station_id)
            if matching and not any(canonical(station_id) == canonical(complex_id)
                    and g.get('stationInstances', {}).get(station_id, station_id) == body
                    for g in matching for station_id in g['stationIds']):
                fail(f"transfer {transfer_id}: body {body} is not a bound project-side platform")
        if not str(entry.get("sourceNote", "")).strip():
            fail(f"transfer {transfer_id}: sourceNote is required")
        transfers.append({
            "id": transfer_id,
            "name": str(entry["name"]),
            "complexId": complex_id,
            "stationInstanceIds": instance_ids,
            "lineIds": line_ids,
            "precision": "schematic",
            "source": str(entry.get("source", plan_spec["source"])),
            "sourceNote": str(entry["sourceNote"]),
        })

    if "sourcePublicationDate" not in plan_spec:
        fail("plan.sourcePublicationDate is required (use null with publicationDateNote when unknown)")
    if plan_spec.get("sourcePublicationDate") is None and not str(plan_spec.get("publicationDateNote", "")).strip():
        fail("plan with a null sourcePublicationDate needs publicationDateNote")

    plan = {
        "id": str(plan_spec["id"]),
        "projectIds": [str(value) for value in spec["projectIds"]],
        "title": str(plan_spec["title"]),
        "date": str(plan_spec.get("date", "2026-10-01")),
        "status": str(plan_spec["status"]),
        "sourceType": str(plan_spec["sourceType"]),
        "projectType": str(plan_spec["projectType"]),
        "required": bool(plan_spec.get("required", True)),
        "requireOpen": False,
        "serviceStatusSchema": 2,
        "dataStatus": "blueprint_ready",
        "exactAlignment": str(plan_spec.get("exactAlignment", "corridor_only")),
        "source": str(plan_spec["source"]),
        "sourceTitle": str(plan_spec["sourceTitle"]),
        "sourceCheckedAt": str(plan_spec["sourceCheckedAt"]),
        "description": str(plan_spec["description"]),
        "sourcePublicationDate": plan_spec["sourcePublicationDate"],
        "lineGroups": groups,
        "requiredTransfers": transfers,
        "scopeRevision": str(plan_spec.get("contentRevision", "")),
        "requiresScopeRecheck": bool(plan_spec.get("requiresScopeRecheck", False)),
        "scopeCorrections": plan_spec.get("scopeCorrections", []),
    }
    if plan["sourcePublicationDate"] is None:
        plan["publicationDateNote"] = str(plan_spec["publicationDateNote"])
    for field in ('requiresLineReorganization', 'constructionProfile', 'stationProfiles', 'operationType', 'operationGuide', 'additionalSources', 'sourceArchive'):
        if field in plan_spec:
            plan[field] = plan_spec[field]

    summary = {
        "plan": plan["id"],
        "groups": [{"taskId": group["taskId"], "stations": len(group["stationIds"]), "route": group["mapRouteId"]} for group in groups],
        "newStations": new_station_count,
        "existingStations": sum(1 for record in catalog.values() if record["existing"]),
        "transfers": len(transfers),
    }
    if args.check:
        print(json.dumps(summary, ensure_ascii=False, indent=1))
        print("CHECK OK: no files written")
        return 0
    if args.dry_run:
        print(json.dumps(summary, ensure_ascii=False, indent=1))
        print("DRY RUN: no files written")
        return 0

    plans = campaign.setdefault("futurePlans", [])
    for index, old in enumerate(plans):
        if str(old.get("id", "")) == plan["id"]:
            plans[index] = plan
            break
    else:
        plans.append(plan)

    station_rows = city.setdefault("stations", [])
    by_id = {str(row.get("id", "")): row for row in station_rows}
    for station_id, record in catalog.items():
        if record["existing"]:
            continue
        value = {
            "id": station_id,
            "name": record["name"],
            "latlng": record["latlng"],
            "schematic": True,
            "coordinateSource": record["coordinateSource"],
            "coordinateNote": record["coordinateNote"],
            "source": record["source"],
            "sourceCheckedAt": str(plan_spec["sourceCheckedAt"]),
        }
        if record.get("coordinateAccuracyM") is not None:
            value["coordinateAccuracyM"] = record["coordinateAccuracyM"]
        if station_id in by_id:
            by_id[station_id].update(value)
        else:
            station_rows.append(value)

    for project in baseline_city.get("projectsAtCutoff", []):
        if project.get("id") in plan["projectIds"]:
            project["playabilityStatus"] = "playable_build_task"
            project.pop("playabilityNote", None)

    if plan_spec.get("contentRevision"):
        incoming = str(plan_spec["contentRevision"])
        current = str(campaigns.get("contentRevision", ""))
        # Re-materializing an older reviewed project must not roll back the
        # content package version used by save scope reconciliation.
        revision_key = lambda value: tuple(int(part) for part in value.split("."))
        if not current or revision_key(incoming) >= revision_key(current):
            campaigns["contentRevision"] = incoming
            campaigns["contentRevisionNote"] = str(plan_spec.get("contentRevisionNote", ""))
        baseline_revision = str(baseline.get("contentRevision", ""))
        if not baseline_revision or revision_key(incoming) >= revision_key(baseline_revision):
            baseline["contentRevision"] = incoming

    write(CITY_PATH, cities)
    write(CAMPAIGN_PATH, campaigns)
    write(BASELINE_PATH, baseline)
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
