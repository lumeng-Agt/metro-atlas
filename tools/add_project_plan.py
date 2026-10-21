#!/usr/bin/env python3
"""Add one audited project chapter from an explicit JSON spec.

The spec is the review artifact: station order, station-area points, transfer
identities and the cited source all live in it. This tool only materializes the
spec into the campaign city data and marks the project playable; it does not
invent stations, coordinates or transfers.

Spec keys:
  city, projectIds, stations, transfers, plan, lineGroup

stations[]  : {name, id, latlng?, existing?, coordinateNote?, source?}
              existing=true reuses an already mapped station area.
transfers[] : {id, name, complexId, stationInstanceIds, lineIds, sourceNote?}

Run: python tools/add_project_plan.py tools/project_specs/<name>.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN_PATH = ROOT / "data/campaigns.json"
CITY_PATH = ROOT / "data/cities.json"
BASELINE_PATH = ROOT / "data/network_baselines_2026-10-01.json"


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    spec = read(Path(sys.argv[1]))
    city_id = str(spec["city"])
    campaigns = read(CAMPAIGN_PATH)
    cities = read(CITY_PATH)
    baseline = read(BASELINE_PATH)
    campaign = campaigns["cities"][city_id]
    city = next(row for row in cities["cities"] if row["id"] == city_id)
    baseline_city = baseline["cities"][city_id]
    plan_spec = spec["plan"]
    group_spec = spec["lineGroup"]

    station_rows = city.setdefault("stations", [])
    by_id = {str(row.get("id", "")): row for row in station_rows}
    by_name: dict[str, str] = {}
    for row in station_rows:
        by_name.setdefault(str(row.get("name", "")), str(row.get("id", "")))

    station_ids: list[str] = []
    station_names: dict[str, str] = {}
    new_station_count = 0
    for entry in spec["stations"]:
        name = str(entry["name"])
        station_id = str(entry.get("id") or by_name.get(name) or "")
        if not station_id:
            raise SystemExit(f"station {name}: no id and no existing mapped station")
        if bool(entry.get("existing")):
            if station_id not in by_id:
                raise SystemExit(f"station {name}: existing station {station_id} is not in city data")
        else:
            value = {
                "id": station_id,
                "name": name,
                "latlng": [float(entry["latlng"][0]), float(entry["latlng"][1])],
                "schematic": True,
                "coordinateSource": str(entry.get("coordinateSource", "official_project_document_and_local_map_reference")),
                "coordinateNote": str(entry.get("coordinateNote", "")),
                "source": str(entry.get("source", plan_spec["source"])),
                "sourceCheckedAt": str(plan_spec["sourceCheckedAt"]),
            }
            if station_id in by_id:
                by_id[station_id].update(value)
            else:
                station_rows.append(value)
                by_id[station_id] = value
                new_station_count += 1
        if station_id in station_ids:
            raise SystemExit(f"station {name}: duplicate station in spec")
        station_ids.append(station_id)
        station_names[station_id] = name

    if len(station_ids) < 2:
        raise SystemExit("a project chapter needs at least two stations")

    shared_bodies = spec.get("stationInstances", {})
    for station_id in shared_bodies:
        if station_id not in station_ids:
            raise SystemExit(f"stationInstances key {station_id} is not part of this chapter")

    group = {
        "taskId": f"project:{plan_spec['id']}",
        "mapRouteId": str(group_spec["mapRouteId"]),
        "name": str(group_spec["name"]),
        "historicalLineId": str(group_spec["historicalLineId"]),
        "color": str(group_spec.get("color", "#808080")),
        "stationIds": station_ids,
        "stationNames": station_names,
        "toleranceM": float(group_spec.get("toleranceM", 500)),
        "alignmentPrecision": str(group_spec.get("alignmentPrecision", "corridor_only")),
        "precisionNote": str(group_spec["precisionNote"]),
        "stationOrderSource": str(group_spec.get("stationOrderSource", plan_spec["source"])),
        "requireOpen": False,
    }
    if shared_bodies:
        group["stationInstances"] = {str(key): str(value) for key, value in shared_bodies.items()}

    transfers = []
    for entry in spec.get("transfers", []):
        transfers.append({
            "id": str(entry["id"]),
            "name": str(entry["name"]),
            "complexId": str(entry["complexId"]),
            "stationInstanceIds": [str(value) for value in entry["stationInstanceIds"]],
            "lineIds": [str(value) for value in entry["lineIds"]],
            "precision": "schematic",
            "source": str(entry.get("source", plan_spec["source"])),
            "sourceNote": str(entry.get("sourceNote", "换乘身份按官方项目资料确认；站内通道和层次仅作示意。")),
        })

    plan = {
        "id": str(plan_spec["id"]),
        "projectIds": [str(value) for value in spec["projectIds"]],
        "title": str(plan_spec["title"]),
        "date": str(plan_spec.get("date", "2026-10-01")),
        "status": str(plan_spec["status"]),
        "sourceType": str(plan_spec["sourceType"]),
        "projectType": str(plan_spec["projectType"]),
        "required": bool(plan_spec.get("required", True)),
        "dataStatus": "blueprint_ready",
        "exactAlignment": str(plan_spec.get("exactAlignment", "corridor_only")),
        "source": str(plan_spec["source"]),
        "sourceTitle": str(plan_spec["sourceTitle"]),
        "sourceCheckedAt": str(plan_spec["sourceCheckedAt"]),
        "description": str(plan_spec["description"]),
        "sourcePublicationDate": str(plan_spec["sourcePublicationDate"]),
        "lineGroups": [group],
        "requiredTransfers": transfers,
    }

    plans = campaign.setdefault("futurePlans", [])
    for index, old in enumerate(plans):
        if str(old.get("id", "")) == plan["id"]:
            plans[index] = plan
            break
    else:
        plans.append(plan)

    for project in baseline_city.get("projectsAtCutoff", []):
        if project.get("id") in plan["projectIds"]:
            project["playabilityStatus"] = "playable_build_task"

    if plan_spec.get("contentRevision"):
        campaigns["contentRevision"] = str(plan_spec["contentRevision"])
        campaigns["contentRevisionNote"] = str(plan_spec.get("contentRevisionNote", ""))

    write(CITY_PATH, cities)
    write(CAMPAIGN_PATH, campaigns)
    write(BASELINE_PATH, baseline)
    print(f"plan {plan['id']}: {len(station_ids)} stations ({new_station_count} new), {len(transfers)} transfers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
