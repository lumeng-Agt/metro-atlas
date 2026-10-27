#!/usr/bin/env python3
"""Guard route-sequence and station-body corrections found in city replays."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def main() -> int:
    cities = {city["id"]: city for city in read("data/cities.json")["cities"]}
    campaigns = read("data/campaigns.json")["cities"]
    alignments = read("data/reference_alignments.json")
    failures: list[str] = []

    shanghai = cities["shanghai"]
    sh_line14 = next(line for line in shanghai["lines"] if line["id"] == "shanghai-r14")
    if "shanghai-s410" in sh_line14["stationIds"] or any("shanghai-s410" in d.get("stationIds", []) for d in sh_line14["directions"]):
        failures.append("Shanghai Line 14 still includes the stale Dongchang Road anchor")
    if not all("shanghai-s394" in d.get("stationIds", []) for d in sh_line14["directions"]):
        failures.append("Shanghai Line 14 does not use the same Pudong South Road body in both directions")
    if "https://jtw.sh.gov.cn/xydt/20211229/921a5130a02e4d8b99e35a96125fbf73.html" not in str(sh_line14.get("stationOrderSource", "")):
        failures.append("Shanghai Line 14 correction has no official station-order provenance")

    beijing = cities["beijing"]
    bj_line4 = next(line for line in beijing["lines"] if line["id"] == "beijing-r4")
    # Line 4 and the Daxing Line run through as one service: 24 stations on
    # Line 4 proper plus the 11 Daxing stations. The duplicate anchor must
    # never come back, and neither half may silently lose or gain a station.
    daxing_ids = [sid for sid in bj_line4["stationIds"] if sid.startswith("beijing-daxing-")]
    line4_ids = [sid for sid in bj_line4["stationIds"] if not sid.startswith("beijing-daxing-")]
    if len(line4_ids) != 24:
        failures.append("Beijing Line 4 proper must keep its 24 official stations")
    if len(daxing_ids) != 11 or len(bj_line4["stationIds"]) != 35:
        failures.append("Beijing Line 4 through service must keep the 11 Daxing Line stations")
    if "beijing-s239" in bj_line4["stationIds"]:
        failures.append("Beijing Line 4 still contains the unnamed duplicate anchor")
    if len(bj_line4.get("directions", [])) >= 2 and bj_line4["directions"][1]["stationIds"] != list(reversed(bj_line4["directions"][0]["stationIds"])):
        failures.append("Beijing Line 4 directions are not reciprocal after deduplicating Taoranting")

    guangzhou_ref = alignments.get("stationReferences", {}).get("guangzhou-s342", {})
    if guangzhou_ref.get("latlng") != guangzhou_ref.get("rawLatlng") or guangzhou_ref.get("lineId") != "guangzhou-r11":
        failures.append("Guangzhou East Line 11 anchor still points at the Line 1 station")
    gz_stations = {station["id"]: station for station in cities["guangzhou"]["stations"]}
    if guangzhou_ref.get("latlng") == gz_stations.get("guangzhou-s177", {}).get("latlng"):
        failures.append("Guangzhou East Line 11 and Line 1 bodies still share an accidental coordinate")

    chengdu = campaigns["chengdu"]
    if chengdu.get("stationInstanceAliases", {}).get("chengdu-line1|chengdu-s12") != "chengdu-s12":
        failures.append("Chengdu Line 1 must reuse its original South Railway Station body identity")
    # A transfer requirement legitimately appears again in a later chapter
    # that re-checks the same interchange, but never twice inside one chapter.
    # Every occurrence must still point at the original Line 1 station body.
    transfer_rows = [
        (chapter.get("id"), transfer)
        for chapter in chengdu.get("chapters", [])
        for transfer in chapter.get("requiredTransfers", [])
        if transfer.get("id") == "historic-transfer-chengdu-s12-line7-7-line1"
    ]
    if not transfer_rows:
        failures.append("Chengdu Line 7/Line 1 transfer requirement is missing")
    for chapter_id, row in transfer_rows:
        if row.get("stationInstanceIds", [None, None])[1] != "chengdu-s12":
            failures.append(f"Chengdu Line 7/Line 1 transfer in {chapter_id} still references the duplicate Line 1 body")

    for city_id, city_config in campaigns.items():
        aliases = city_config.get("stationInstanceAliases", {})
        complex_aliases = city_config.get("stationComplexAliases", {})
        for chapter in city_config.get("chapters", []):
            seen_transfers: set[str] = set()
            for transfer in chapter.get("requiredTransfers", []):
                transfer_id = str(transfer.get("id", ""))
                if transfer_id in seen_transfers:
                    failures.append(f"{city_id} chapter {chapter.get('id')} lists transfer {transfer_id} twice")
                seen_transfers.add(transfer_id)
                complex_id = str(transfer.get("complexId", ""))
                if complex_aliases.get(complex_id, complex_id) != complex_id:
                    failures.append(f"{city_id} transfer {transfer.get('id')} does not use its canonical historical complex ID")
                for index, line_id in enumerate(transfer.get("lineIds", [])):
                    if index >= len(transfer.get("stationInstanceIds", [])):
                        failures.append(f"{city_id} transfer {transfer.get('id')} has fewer station bodies than lines")
                        continue
                    alias = aliases.get(f"{line_id}|{complex_id}")
                    if alias and transfer["stationInstanceIds"][index] != alias:
                        failures.append(f"{city_id} transfer {transfer.get('id')} does not use its line's canonical station body")

    if failures:
        raise SystemExit("\n".join(f"FAIL: {failure}" for failure in failures))
    print("PASS: city replay station identity repairs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
