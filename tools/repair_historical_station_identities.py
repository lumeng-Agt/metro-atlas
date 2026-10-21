#!/usr/bin/env python3
"""Repair cross-city station identity/anchor errors found by replay.

The edits are narrowly scoped to independently sourced station anchors:
Shanghai Line 14 had two IDs for one station in opposite directions; the
Guangzhou East Line 11 target inherited Line 1's coordinate reference; and
Chengdu's Line 1 transfer alias pointed at a duplicate body instead of the
already-built historical station.
Beijing Line 2 must keep its own physical Yonghegong interchange body.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, data, *, compact: bool = False) -> None:
    if compact:
        payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    else:
        payload = json.dumps(data, ensure_ascii=False, indent=2)
    path.write_text(payload + "\n", encoding="utf-8")


def main() -> None:
    cities_path = ROOT / "data/cities.json"
    alignments_path = ROOT / "data/reference_alignments.json"
    campaigns_path = ROOT / "data/campaigns.json"
    cities = read(cities_path)
    alignments = read(alignments_path)
    campaigns = read(campaigns_path)

    # The OSM route's first direction uses the correct Line 14 Pudong South
    # Road anchor, while the reverse direction substitutes a nearby stale
    # Dongchang Road anchor. Keep Line 2's separate station anchor. A second
    # Wuning Road discrepancy is retained for separate source review.
    shanghai = next(city for city in cities["cities"] if city["id"] == "shanghai")
    line14 = next(line for line in shanghai["lines"] if line["id"] == "shanghai-r14")
    wrong_id, correct_id = "shanghai-s410", "shanghai-s394"
    line14["stationIds"] = [sid for sid in line14["stationIds"] if sid != wrong_id]
    for direction in line14.get("directions", []):
        direction["stationIds"] = [correct_id if sid == wrong_id else sid for sid in direction.get("stationIds", [])]
    if wrong_id in line14["stationIds"] or any(wrong_id in direction.get("stationIds", []) for direction in line14.get("directions", [])):
        raise SystemExit("Shanghai Line 14 still contains the duplicate East Chang Road anchor.")
    if not any(wrong_id in [sid for line in city["lines"] for sid in line.get("stationIds", [])] for city in cities["cities"]):
        shanghai["stations"] = [station for station in shanghai["stations"] if station["id"] != wrong_id]
    line14["stationOrderSource"] = "https://jtw.sh.gov.cn/xydt/20211229/921a5130a02e4d8b99e35a96125fbf73.html"
    line14["stationOrderCheckedAt"] = "2026-10-20"

    # A reference-building step accidentally snapped Line 11's Guangzhou East
    # target to the Line 1/3 body. Restore the target's own OSM station anchor.
    station_ref = alignments["stationReferences"].get("guangzhou-s342", {})
    raw = station_ref.get("rawLatlng", [])
    if len(raw) != 2:
        raise SystemExit("Guangzhou East Line 11 station is missing its own raw map anchor.")
    station_ref["latlng"] = raw[:]
    station_ref["sourceNodeId"] = 6898751631
    station_ref["lineId"] = "guangzhou-r11"
    station_ref["amapReview"] = "pending"
    station_ref["historicalReview"] = "modern_reference_only"
    station_ref["note"] = "修正误吸附到1号线广州东站站体的坐标引用，改用11号线站点自身的离线地图锚点；不表示站体测绘精度。"

    # Line 1 at Chengdu South Railway Station is one stable physical body. The
    # 2010 chapter created it as chengdu-s12; later snapshots must reuse that
    # identity rather than inventing chengdu-s12__line1 beside it.
    chengdu = campaigns["cities"]["chengdu"]
    instance_aliases = chengdu.setdefault("stationInstanceAliases", {})
    instance_aliases["chengdu-line1|chengdu-s12"] = "chengdu-s12"
    transfer_id = "historic-transfer-chengdu-s12-line7-7-line1"
    fixed_transfers = 0
    for chapter in chengdu.get("chapters", []):
        for transfer in chapter.get("requiredTransfers", []):
            if str(transfer.get("id", "")) != transfer_id:
                continue
            body_ids = transfer.get("stationInstanceIds", [])
            if len(body_ids) >= 2 and body_ids[1] == "chengdu-s12__line1":
                body_ids[1] = "chengdu-s12"
                fixed_transfers += 1
            elif len(body_ids) >= 2 and body_ids[1] == "chengdu-s12":
                fixed_transfers += 1
    if fixed_transfers != 1:
        raise SystemExit(f"Expected one Chengdu South Line 7/Line 1 transfer to repair; found {fixed_transfers}.")

    # An old alias collapsed the Beijing Line 2 Yonghegong body into a generic
    # station complex, while the 2007 Line 5 transfer explicitly requires two
    # physical station bodies. Keep the group-level Line 2 instance ID so the
    # historical build creates a separate, independently connectable body.
    beijing = campaigns["cities"]["beijing"]
    beijing_aliases = beijing.setdefault("stationInstanceAliases", {})
    beijing_aliases.pop("beijing-lineearly1|beijing-s73", None)

    # Transfer targets must resolve to the same physical body IDs used by the
    # corresponding line build groups. Some historical targets intentionally
    # reuse a different OSM anchor for the same complex (e.g. Changshu Road,
    # Xilang); leaving the synthetic ``complex__line`` ID here makes the map
    # look connected while the transfer transaction cannot find that body.
    for city_id, city_config in campaigns.get("cities", {}).items():
        aliases = city_config.get("stationInstanceAliases", {})
        complex_aliases = city_config.get("stationComplexAliases", {})
        for chapter in city_config.get("chapters", []):
            for transfer in chapter.get("requiredTransfers", []):
                complex_id = str(transfer.get("complexId", ""))
                transfer["complexId"] = str(complex_aliases.get(complex_id, complex_id))
                body_ids = transfer.get("stationInstanceIds", [])
                for index, line_id in enumerate(transfer.get("lineIds", [])):
                    if index >= len(body_ids):
                        continue
                    alias = str(aliases.get(f"{line_id}|{complex_id}", ""))
                    if alias:
                        body_ids[index] = alias

    write(cities_path, cities)
    write(alignments_path, alignments, compact=True)
    write(campaigns_path, campaigns)
    print("Repaired route anchors and synchronized historical interchange targets with each line's physical station-body identity.")


if __name__ == "__main__":
    main()
