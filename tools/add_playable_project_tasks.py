#!/usr/bin/env python3
"""Add audited, source-backed construction plans for cutoff projects.

This first content increment turns the fully published Shanghai Line 23 Phase 1
approval into a buildable project chapter. Station-area points are taken from
the official station-site descriptions; the bundled OSM basemap is used only to
locate those described street junctions. Inter-station geometry remains an
explicit corridor approximation, not a surveyed tunnel alignment.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN_PATH = ROOT / "data/campaigns.json"
CITY_PATH = ROOT / "data/cities.json"
BASELINE_PATH = ROOT / "data/network_baselines_2026-10-01.json"

SOURCE = "https://www.shanghai.gov.cn/gwk/search/content/2d9b25a3bed24964a3739c117926ed58"
SOURCE_TITLE = "关于上海市轨道交通23号线一期工程可行性研究报告的批复"
CHECKED = "2026-10-21"

# Existing city station IDs retain their shared complex identity, while this
# project's stationInstances create its own physical station bodies.
EXISTING = {
    "闵行开发区": ("shanghai-s210", [31.002676, 121.3654379]),
    "文井路": ("shanghai-s211", [31.0056477, 121.3765305]),
    "华宁路": ("shanghai-s212", [31.0094993, 121.3909794]),
    "金平路": ("shanghai-s213", [31.0132667, 121.405889]),
    "东川路": ("shanghai-s214", [31.0205267, 121.4151396]),
    "紫竹高新区": ("shanghai-s411", [31.0264916, 121.4460335]),
    "龙漕路": ("shanghai-s353", [31.1720906, 121.4389396]),
    "上海体育场": ("shanghai-s72", [31.1874075, 121.4391017]),
}

# Official approval lists 22 stops and locates them by road/site. For new
# station areas, coordinates use the corresponding named street junction from
# the bundled contemporary OSM road vectors. Where the public description
# gives a parcel/site rather than a junction, a nearby station-area point is
# explicitly tagged as approximate.
NEW = [
    ("沪金高速", "shanghai-f23-hujin", [31.0206023, 121.4307337], "东川路与沪金高速交叉处；站区参考"),
    ("江川东路", "shanghai-f23-jiangchuan-east", [31.028302, 121.455987], "东川路与江川东路交叉处"),
    ("紫龙路", "shanghai-f23-zilong", [31.035754, 121.465012], "龙吴路与紫龙路交叉处"),
    ("放鹤路", "shanghai-f23-fanghe", [31.051382, 121.461565], "龙吴路与放鹤路交叉处"),
    ("吴泾北", "shanghai-f23-wujing-north", [31.066601, 121.457014], "龙吴路与元江路交叉处"),
    ("墨江路", "shanghai-f23-mojiang", [31.0746732, 121.455512], "龙吴路与墨江路交叉处"),
    ("澄江路", "shanghai-f23-chengjiang", [31.086355, 121.454956], "龙吴路与澄江路交叉处"),
    ("龙吴路", "shanghai-f23-longwu", [31.093457, 121.453], "龙吴路与双柏路交叉口西南侧站区参考"),
    ("景联路", "shanghai-f23-jinglian", [31.103095, 121.449933], "龙吴路与景联路交叉处"),
    ("华泾路", "shanghai-f23-huajing", [31.121923, 121.452232], "龙吴路与华泾路交叉处"),
    ("徐浦大桥", "shanghai-f23-xupu-bridge", [31.129086, 121.45146], "龙吴路与华发路交叉处北侧站区参考"),
    ("龙瑞路", "shanghai-f23-longrui", [31.14119, 121.447162], "龙吴路与罗秀路附近站区参考"),
    ("上海植物园", "shanghai-f23-botanical-garden", [31.155349, 121.445497], "上海植物园东门附近站区参考"),
    ("龙启路", "shanghai-f23-longqi", [31.160471, 121.444605], "龙吴路与石龙路交叉处附近站区参考"),
]

ORDER = [
    "闵行开发区", "文井路", "华宁路", "金平路", "东川路", "沪金高速",
    "紫竹高新区", "江川东路", "紫龙路", "放鹤路", "吴泾北", "墨江路",
    "澄江路", "龙吴路", "景联路", "华泾路", "徐浦大桥", "龙瑞路",
    "上海植物园", "龙启路", "龙漕路", "上海体育场",
]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    campaigns = load(CAMPAIGN_PATH)
    cities = load(CITY_PATH)
    baseline = load(BASELINE_PATH)
    campaign = campaigns["cities"]["shanghai"]
    city = next(row for row in cities["cities"] if row["id"] == "shanghai")
    project = next(row for row in baseline["cities"]["shanghai"]["projectsAtCutoff"] if row["id"] == "sh-line23-phase1")

    by_name = {name: (station_id, latlng) for name, (station_id, latlng) in EXISTING.items()}
    for name, station_id, latlng, site_note in NEW:
        by_name[name] = (station_id, latlng)
        if not any(row.get("id") == station_id for row in city["stations"]):
            city["stations"].append({
                "id": station_id,
                "name": name,
                "latlng": latlng,
                "schematic": True,
                "coordinateSource": "official_station_site_description_and_local_OSM_road_junction",
                "coordinateNote": site_note,
                "source": SOURCE,
                "sourceCheckedAt": CHECKED,
            })

    existing_ids = {row["id"] for row in city["stations"]}
    ids = [by_name[name][0] for name in ORDER]
    missing = [station_id for station_id in ids if station_id not in existing_ids]
    if missing:
        raise SystemExit(f"station target references missing map entries: {missing}")

    plan_id = "sh-line23-phase1-build"
    group = {
        "taskId": "project:sh-line23-phase1-build",
        "mapRouteId": "shanghai-future-line23-phase1",
        "name": "23号线一期",
        "historicalLineId": "shanghai-line23-23",
        "color": "#A92C59",
        "stationIds": ids,
        "stationNames": {station_id: name for name, (station_id, _latlng) in by_name.items() if name in ORDER},
        "stationInstances": {station_id: f"{station_id}__line23-23" for station_id in ids},
        "stationReferenceIds": {station_id: station_id for station_id in ids},
        "toleranceM": 250,
        "alignmentPrecision": "corridor_only",
        "precisionNote": "22座车站及站序依据上海市政府可研批复；新增站区按批复中的道路、地块位置与现代开放地图路口定位。区间仅表示走廊近似，不是隧道测绘线位。",
        "stationOrderSource": SOURCE,
        "requireOpen": False,
    }
    transfer_specs = [
        ("dongchuan", "东川路", "shanghai-s214", "shanghai-s214__line23-23", "shanghai-line5-5"),
        ("zizhu", "紫竹高新区", "shanghai-s411", "shanghai-s411__line23-23", "shanghai-line15-15"),
        ("longcao", "龙漕路", "shanghai-s353", "shanghai-s353__line23-23", "shanghai-line12-12"),
        ("stadium", "上海体育场", "shanghai-s72", "shanghai-s72__line23-23", "shanghai-line4-4"),
    ]
    required_transfers = [{
        "id": f"sh-future-transfer-line23-{slug}",
        "name": name,
        "complexId": station_id,
        "stationInstanceIds": [base_instance, project_instance],
        "lineIds": [base_line, "shanghai-line23-23"],
        "precision": "schematic",
        "source": SOURCE,
        "sourceNote": "官方批复明确该站与既有线路换乘；站内通道和层次仅作示意。",
    } for slug, name, station_id, project_instance, base_line in transfer_specs for base_instance in [station_id]]

    plan = {
        "id": plan_id,
        "projectIds": [project["id"]],
        "title": "上海23号线一期建设篇",
        "date": "2026-10-01",
        "status": "under_construction",
        "sourceType": "municipal_initial_design_approval",
        "projectType": project["projectType"],
        "required": True,
        "dataStatus": "blueprint_ready",
        "exactAlignment": "corridor_only",
        "source": SOURCE,
        "sourceTitle": SOURCE_TITLE,
        "sourceCheckedAt": CHECKED,
        "description": "按可研批复的22站站序，复现闵行开发区至上海体育场的一期建设范围。项目在截止日仍在建；完成本篇只记录为规划建设完成，不计作真实开通。站区可核对，区间是近似走廊。",
        "sourcePublicationDate": "2022-09-27",
        "lineGroups": [group],
        "requiredTransfers": required_transfers,
    }
    plans = campaign.setdefault("futurePlans", [])
    found = False
    for index, row in enumerate(plans):
        if str(row.get("id", "")) == plan_id:
            plans[index] = plan
            found = True
            break
    if not found:
        plans.append(plan)
    project["playabilityStatus"] = "playable_build_task"
    campaigns["contentRevision"] = "2026.10.21.1"
    campaigns["contentRevisionNote"] = "增加上海23号线一期官方批复站序及走廊级规划建设任务；其余项目按独立台账继续补齐。"

    write(CITY_PATH, cities)
    write(CAMPAIGN_PATH, campaigns)
    write(BASELINE_PATH, baseline)
    print(f"added {plan_id}: {len(ids)} stations, {len(required_transfers)} transfers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

