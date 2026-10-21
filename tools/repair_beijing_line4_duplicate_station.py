#!/usr/bin/env python3
"""Remove a duplicate OSM anchor from Beijing Line 4's station sequence.

The map snapshot contains an unnamed station anchor inside Taoranting's
station footprint. It appears only in one direction, while the official operator's
24-station sequence identifies Taoranting between Caishikou and Beijing South.
This repair keeps the real station identity and makes both map directions
reverses of the same sequence.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DUPLICATE_ID = "beijing-s239"
CANONICAL_ID = "beijing-s223"  # 陶然亭
SOURCE = "https://www.mtr.bj.cn/service/line/line-4.html"


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    cities_path = ROOT / "data/cities.json"
    campaigns_path = ROOT / "data/campaigns.json"
    cities_doc = read_json(cities_path)
    campaigns_doc = read_json(campaigns_path)

    beijing = next(city for city in cities_doc["cities"] if city["id"] == "beijing")
    canonical = next(station for station in beijing["stations"] if station["id"] == CANONICAL_ID)
    line4 = next(line for line in beijing["lines"] if line["id"] == "beijing-r4")
    duplicate = next((station for station in beijing["stations"] if station["id"] == DUPLICATE_ID), None)
    if duplicate is not None:
        lat1, lon1 = map(math.radians, duplicate["latlng"])
        lat2, lon2 = map(math.radians, canonical["latlng"])
        a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
        if 6_371_000 * 2 * math.asin(math.sqrt(a)) > 30.0:
            raise SystemExit("Duplicate candidate moved outside the canonical station footprint; review before applying.")
        if DUPLICATE_ID in line4["stationIds"]:
            line4["stationIds"] = [station_id for station_id in line4["stationIds"] if station_id != DUPLICATE_ID]
    for direction in line4.get("directions", []):
        if DUPLICATE_ID in direction.get("stationIds", []):
            direction["stationIds"] = [CANONICAL_ID if station_id == DUPLICATE_ID else station_id for station_id in direction["stationIds"]]
    forward = line4["directions"][0]["stationIds"]
    reverse = line4["directions"][1]["stationIds"]
    if reverse != list(reversed(forward)):
        raise SystemExit("Line 4 directions still disagree after targeted correction; review the source data.")
    beijing["stations"] = [station for station in beijing["stations"] if station["id"] != DUPLICATE_ID]
    line4["stationOrderSource"] = SOURCE
    line4["stationOrderCheckedAt"] = "2026-10-20"

    campaign_city = campaigns_doc["cities"]["beijing"]
    removed_from_chapters = 0
    for chapter in campaign_city.get("chapters", []):
        for group in chapter.get("lineGroups", []):
            if DUPLICATE_ID in group.get("stationIds", []):
                group["stationIds"] = [station_id for station_id in group["stationIds"] if station_id != DUPLICATE_ID]
                removed_from_chapters += 1
            for revision in group.get("story", {}).get("planVersions", []):
                for revision_group in revision.get("lineGroups", []):
                    if DUPLICATE_ID in revision_group.get("stationIds", []):
                        revision_group["stationIds"] = [station_id for station_id in revision_group["stationIds"] if station_id != DUPLICATE_ID]
                        removed_from_chapters += 1
    if removed_from_chapters < 2 and DUPLICATE_ID in json.dumps(campaign_city, ensure_ascii=False):
        raise SystemExit(f"Expected to repair at least two historical route snapshots; repaired {removed_from_chapters}.")

    write_json(cities_path, cities_doc)
    write_json(campaigns_path, campaigns_doc)
    print(f"Repaired Beijing Line 4 duplicate anchor {DUPLICATE_ID} -> {CANONICAL_ID}; campaign snapshots fixed: {removed_from_chapters}; source: {SOURCE}")


if __name__ == "__main__":
    main()
