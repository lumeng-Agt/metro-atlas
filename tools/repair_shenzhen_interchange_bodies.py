#!/usr/bin/env python3
"""Correct duplicate Shenzhen map station IDs used by the historical route tasks.

The IDs remain separate physical station bodies. Explicit complex aliases only
group them for the transfer identity and overlap exception; they never connect
the railway track graph. The pairings are cross-checked against the Shenzhen
Transport Bureau's published system map and route list.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "https://jtys.sz.gov.cn/jtzx/wycx/dtcx/dtxl/content/post_12601089.html"


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    path = ROOT / "data/campaigns.json"
    catalog = read(path)
    city = catalog["cities"]["shenzhen"]
    # The 2004 Line 1 sample accidentally pointed at Line 6, Line 3 and Line
    # 7/9 copies of three stations. Use Line 1's own station bodies instead.
    line1 = next(ch for ch in city["chapters"] if ch["id"] == "sz-initial-cross-2004")
    group = next(g for g in line1["lineGroups"] if g.get("historicalLineId") == "shenzhen-line1")
    replacements = {"shenzhen-s270": "shenzhen-s5", "shenzhen-s34": "shenzhen-s9", "shenzhen-s212": "shenzhen-s11"}
    group["stationIds"] = [replacements.get(str(value), str(value)) for value in group["stationIds"]]
    for field in ["stationInstances", "stationNames", "stationReferenceIds"]:
        values = group.get(field)
        if not isinstance(values, dict):
            continue
        for old, new in replacements.items():
            if old in values:
                values[new] = values.pop(old)
    group.setdefault("stationInstances", {})["shenzhen-s11"] = "shenzhen-s11__line1"

    # Same named interchange complexes have distinct map anchors and keep
    # independent physical bodies. These aliases do not make lines share a
    # station body or create a transfer automatically.
    aliases = city.setdefault("stationComplexAliases", {})
    aliases.update({
        "shenzhen-s270": "shenzhen-s5",   # 科学馆：1号线 / 6号线
        "shenzhen-s34": "shenzhen-s9",    # 购物公园：1号线 / 3号线
        "shenzhen-s212": "shenzhen-s11",  # 车公庙：1/7/9/11号线
    })

    def add_transfer(chapter_id: str, transfer: dict) -> None:
        chapter = next(ch for ch in city["chapters"] if ch["id"] == chapter_id)
        transfers = chapter.setdefault("requiredTransfers", [])
        existing = next((item for item in transfers if item.get("id") == transfer["id"]), None)
        if existing is None:
            transfers.append(transfer)
        else:
            existing.update(transfer)

    common = {"precision": "schematic", "source": SOURCE,
              "sourceNote": "按深圳市交通运输局发布的现状线网图核对线路关系；站内通道和具体结构不作推断。"}
    add_transfer("shenzhen-network-milestone-2020-08-18", {
        **common, "id": "sz-transfer-science-museum-line1-line6", "name": "科学馆",
        "complexId": "shenzhen-s5", "stationInstanceIds": ["shenzhen-s5", "shenzhen-s270"],
        "lineIds": ["shenzhen-line1", "shenzhen-line6-6"],
    })
    add_transfer("shenzhen-historical-milestone-2011-06-28", {
        **common, "id": "sz-transfer-shopping-park-line1-line3", "name": "购物公园",
        "complexId": "shenzhen-s9", "stationInstanceIds": ["shenzhen-s9", "shenzhen-s34__line3-3"],
        "lineIds": ["shenzhen-line1", "shenzhen-line3-3"],
    })
    add_transfer("shenzhen-historical-milestone-2016-10-28", {
        **common, "id": "sz-transfer-chegongmiao-lines1-7-9-11", "name": "车公庙",
        "complexId": "shenzhen-s11",
        "stationInstanceIds": ["shenzhen-s11__line1", "shenzhen-s212__line7-8", "shenzhen-s212__line9-10", "shenzhen-s11__line11-12"],
        "lineIds": ["shenzhen-line1", "shenzhen-line7-8", "shenzhen-line9-10", "shenzhen-line11-12"],
    })
    write(path, catalog)
    print("Corrected Shenzhen station body identities and added 3 explicit transfer milestones.")


if __name__ == "__main__":
    main()
