#!/usr/bin/env python3
"""Turn official project station lists into selectable construction chapters.

Coordinates are station-area references, not tunnel survey data. Every custom
point records the source and whether it is an intersection or a broader site
estimate. Existing station IDs are reused where the project joins the current
network, while stationInstances keep the physical bodies line-specific.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN_PATH = ROOT / "data/campaigns.json"
CITY_PATH = ROOT / "data/cities.json"
BASELINE_PATH = ROOT / "data/network_baselines_2026-10-01.json"
CHECKED = "2026-10-21"

SHENZHEN_SOURCE = "https://www.szmc.net/SMARTC/upload/file/20250506/1746516250192036661.pdf"
SHENZHEN_SOURCE_TITLE = "深圳市城市轨道交通17号线一期工程环境影响报告书（报批前公示稿）"
CHENGDU_SOURCE = "https://www.chengdurail.com/info/1261/55632.htm"
CHENGDU_SOURCE_TITLE = "成都轨道交通18号线三期工程建设进展"


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def city_row(cities: dict, city_id: str) -> dict:
    return next(row for row in cities["cities"] if row["id"] == city_id)


def add_station(city: dict, station_id: str, name: str, point: list[float], source: str, note: str) -> None:
    rows = city.setdefault("stations", [])
    existing = next((row for row in rows if row.get("id") == station_id), None)
    value = {
        "id": station_id,
        "name": name,
        "latlng": point,
        "schematic": True,
        "coordinateSource": "official_station_site_description_and_local_OSM_reference",
        "coordinateNote": note,
        "source": source,
        "sourceCheckedAt": CHECKED,
    }
    if existing is None:
        rows.append(value)
    else:
        existing.update(value)


def add_plan(campaign: dict, baseline_city: dict, plan: dict) -> None:
    plans = campaign.setdefault("futurePlans", [])
    for index, old in enumerate(plans):
        if str(old.get("id", "")) == str(plan["id"]):
            plans[index] = plan
            break
    else:
        plans.append(plan)
    project_ids = set(plan.get("projectIds", []))
    for project in baseline_city.get("projectsAtCutoff", []):
        if project.get("id") in project_ids:
            project["playabilityStatus"] = "playable_build_task"


def transfer(name: str, complex_id: str, project_body_id: str, existing_body_id: str,
             existing_line_id: str, project_line_id: str, source: str, suffix: str) -> dict:
    return {
        "id": f"future-transfer-{suffix}",
        "name": name,
        "complexId": complex_id,
        "stationInstanceIds": [existing_body_id, project_body_id],
        "lineIds": [existing_line_id, project_line_id],
        "precision": "schematic",
        "source": source,
        "sourceNote": "两线站体分别建造；站内换乘联系按已公布的换乘站身份确认，具体通道和层次不作推断。",
    }


def add_shenzhen17(campaigns: dict, cities: dict, baseline: dict) -> None:
    campaign = campaigns["cities"]["shenzhen"]
    city = city_row(cities, "shenzhen")
    baseline_city = baseline["cities"]["shenzhen"]
    custom = [
        ("侨社", "shenzhen-f17-qiaoshe", [22.53334, 114.111009], "和平路南端、罗湖口岸高架桥下站区参考点。"),
        ("嘉宾", "shenzhen-f17-jiabin", [22.541795, 114.110349], "和平路与嘉宾路交叉口南侧；按现代道路数据定位。"),
        ("大塘龙", "shenzhen-f17-datanglong", [22.5587218, 114.107603], "笋岗东路与宝岗路附近站区参考；公开站位为交叉口以北。"),
        ("笋岗北", "shenzhen-f17-sungang-north", [22.5762, 114.1065], "清水河三路与泥岗东路以南站区参考；该路口在本地矢量中缺少完整命名几何，位置为走廊近似。"),
        ("德兴", "shenzhen-f17-dexing", [22.592637, 114.107582], "粤宝路、西环路、红岗路附近站区参考。"),
        ("罗岗", "shenzhen-f17-luogang", [22.596501, 114.119633], "荣华路与百鸽路交叉口。"),
        ("求水山", "shenzhen-f17-qiushuishan", [22.6002, 114.1346], "求水山公园西侧湖东路站区参考；未取得工程坐标，按公开位置和现代底图近似。"),
        ("南岭", "shenzhen-f17-nanling", [22.6098221, 114.14531], "布沙路与开放路交叉口北侧。"),
        ("南岭北", "shenzhen-f17-nanling-north", [22.6170, 114.1410], "华盛玩具厂地块内；采用现代地理参考的地块级近似点。"),
        ("下李朗", "shenzhen-f17-xialilang", [22.636647, 114.126046], "布澜路与三联东路交叉口北侧。"),
        ("深朗", "shenzhen-f17-shenlang", [22.64484, 114.12365], "布澜路与甘李二路交叉口附近。"),
    ]
    for name, station_id, point, note in custom:
        add_station(city, station_id, name, point, SHENZHEN_SOURCE, note)

    ids = [
        "shenzhen-f17-qiaoshe", "shenzhen-f17-jiabin", "shenzhen-s3",
        "shenzhen-f17-datanglong", "shenzhen-s222", "shenzhen-f17-sungang-north",
        "shenzhen-s310", "shenzhen-f17-dexing", "shenzhen-f17-luogang",
        "shenzhen-s137", "shenzhen-f17-qiushuishan", "shenzhen-f17-nanling",
        "shenzhen-f17-nanling-north", "shenzhen-s49", "shenzhen-s311",
        "shenzhen-f17-xialilang", "shenzhen-f17-shenlang", "shenzhen-s284",
    ]
    names = [
        "侨社", "嘉宾", "老街", "大塘龙", "笋岗", "笋岗北", "罗湖北", "德兴",
        "罗岗", "百鸽笼", "求水山", "南岭", "南岭北", "丹竹头", "石芽岭",
        "下李朗", "深朗", "上李朗",
    ]
    existing = {row["id"] for row in city["stations"]}
    if any(station_id not in existing for station_id in ids):
        raise ValueError("深圳17号线目标站位未全部写入地图城市数据")
    project_body = {station_id: f"{station_id}__line17-17" for station_id in ids}
    group = {
        "taskId": "project:sz-line17-phase1-build",
        "mapRouteId": "shenzhen-future-line17-phase1",
        "name": "17号线一期",
        "historicalLineId": "shenzhen-line17-17",
        "color": "#D96C98",
        "stationIds": ids,
        "stationNames": dict(zip(ids, names)),
        "stationInstances": project_body,
        "stationReferenceIds": {station_id: station_id for station_id in ids},
        "toleranceM": 500,
        "alignmentPrecision": "corridor_only",
        "precisionNote": "官方环评给出18站顺序和多处道路/地块站位；点位以站区参考表示，区间是走廊近似而非工程测绘线。笋岗北、求水山、南岭北为地块级近似。",
        "stationOrderSource": SHENZHEN_SOURCE,
        "requireOpen": False,
    }
    transfers = []
    for suffix, name, station_id, existing_line_id in [
        ("laojie-line1", "老街", "shenzhen-s3", "shenzhen-line1"),
        ("laojie-line3", "老街", "shenzhen-s3", "shenzhen-line3-3"),
        ("sungang-line7", "笋岗", "shenzhen-s222", "shenzhen-line7-8"),
        ("luohubei-line14", "罗湖北", "shenzhen-s310", "shenzhen-line14-15"),
        ("baigelong-line5", "百鸽笼", "shenzhen-s137", "shenzhen-line5-5"),
        ("dantou-line3", "丹竹头", "shenzhen-s49", "shenzhen-line3-3"),
        ("shiyaling-line14", "石芽岭", "shenzhen-s311", "shenzhen-line14-15"),
        ("shanglilang-line10", "上李朗", "shenzhen-s284", "shenzhen-line10-11"),
    ]:
        transfers.append(transfer(name, station_id, project_body[station_id], station_id,
                                  existing_line_id, "shenzhen-line17-17", SHENZHEN_SOURCE, suffix))
    add_plan(campaign, baseline_city, {
        "id": "sz-line17-phase1-build",
        "projectIds": ["sz-line17-phase1"],
        "title": "深圳17号线一期建设篇",
        "date": "2026-10-01",
        "status": "under_construction",
        "sourceType": "operator_environmental_impact_report",
        "projectType": "under_construction",
        "required": True,
        "dataStatus": "blueprint_ready",
        "exactAlignment": "corridor_only",
        "source": SHENZHEN_SOURCE,
        "sourceTitle": SHENZHEN_SOURCE_TITLE,
        "sourceCheckedAt": CHECKED,
        "description": "按报批前环评修订后的18站站序，复现侨社至上李朗一期。罗湖西、梨园、南岭中心已分别更名为侨社、笋岗北、南岭北。项目在截止日仍在建；本章完成只表示规划建设完成。",
        "sourcePublicationDate": "2025-05-06",
        "lineGroups": [group],
        "requiredTransfers": transfers,
    })


def add_chengdu18_phase3(campaigns: dict, cities: dict, baseline: dict) -> None:
    campaign = campaigns["cities"]["chengdu"]
    city = city_row(cities, "chengdu")
    baseline_city = baseline["cities"]["chengdu"]
    ids = ["chengdu-s22", "chengdu-s19", "chengdu-s15", "chengdu-s14", "chengdu-s303"]
    names = ["火车北站", "骡马市", "省体育馆", "倪家桥", "火车南站"]
    by_id = {row["id"]: row for row in city["stations"]}
    if any(station_id not in by_id for station_id in ids):
        raise ValueError("成都18号线三期目标站位未全部写入地图城市数据")
    project_body = {station_id: f"{station_id}__line18-18" for station_id in ids[:-1]}
    # 火车南站 is the existing Line 18 endpoint and is reused as the actual
    # junction. The new northern station bodies are separate at transfer sites.
    group = {
        "taskId": "project:cd-line18-phase3-build",
        "mapRouteId": "chengdu-future-line18-phase3",
        "name": "18号线三期北延段",
        "historicalLineId": "chengdu-line18-13",
        "color": "#A6CE39",
        "stationIds": ids,
        "stationNames": dict(zip(ids, names)),
        "stationInstances": project_body,
        "stationReferenceIds": {station_id: station_id for station_id in ids},
        "toleranceM": 250,
        "alignmentPrecision": "corridor_only",
        "precisionNote": "官方资料确认北延段火车北站至火车南站范围及经人民北路、人民中路、人民南路走向；站点采用现有地铁站区地理位置，区间为走廊近似。",
        "stationOrderSource": "成都轨道集团工程资料与官方线路站点资料；本章只复现已公布的火车北站—骡马市—省体育馆—倪家桥—火车南站站序。",
        "requireOpen": False,
    }
    transfers = []
    for suffix, name, station_id, existing_body, existing_line in [
        ("north-line1", "火车北站", "chengdu-s22", "chengdu-s22", "chengdu-line1"),
        ("north-line7", "火车北站", "chengdu-s22", "chengdu-s22__line7-7", "chengdu-line7-7"),
        ("luomashi-line1", "骡马市", "chengdu-s19", "chengdu-s19", "chengdu-line1"),
        ("luomashi-line4", "骡马市", "chengdu-s19", "chengdu-s19__line4-4", "chengdu-line4-4"),
        ("stadium-line1", "省体育馆", "chengdu-s15", "chengdu-s15", "chengdu-line1"),
        ("stadium-line3", "省体育馆", "chengdu-s15", "chengdu-s15__line3-3", "chengdu-line3-3"),
        ("nijiaqiao-line1", "倪家桥", "chengdu-s14", "chengdu-s14__line1", "chengdu-line1"),
        ("nijiaqiao-line8", "倪家桥", "chengdu-s14", "chengdu-s274", "chengdu-line8-8"),
    ]:
        transfers.append(transfer(name, station_id, project_body[station_id], existing_body,
                                  existing_line, "chengdu-line18-13", CHENGDU_SOURCE, suffix))
    add_plan(campaign, baseline_city, {
        "id": "cd-line18-phase3-build",
        "projectIds": ["cd-line18-phase3"],
        "title": "成都18号线三期北延建设篇",
        "date": "2026-10-01",
        "status": "under_construction",
        "sourceType": "metro_operator_construction_update",
        "projectType": "under_construction",
        "required": True,
        "dataStatus": "blueprint_ready",
        "exactAlignment": "corridor_only",
        "source": CHENGDU_SOURCE,
        "sourceTitle": CHENGDU_SOURCE_TITLE,
        "sourceCheckedAt": CHECKED,
        "description": "沿既有18号线火车南站向北接入火车北站，形成串联成都铁路枢纽的市区段。项目在截止日仍在建；完成建设篇不视为已经开通。四个中间站区与换乘点按公开范围和现状地图对应，区间线位为近似走廊。",
        "sourcePublicationDate": "2024-07-01",
        "lineGroups": [group],
        "requiredTransfers": transfers,
    })


def main() -> None:
    campaigns = read(CAMPAIGN_PATH)
    cities = read(CITY_PATH)
    baseline = read(BASELINE_PATH)
    add_shenzhen17(campaigns, cities, baseline)
    add_chengdu18_phase3(campaigns, cities, baseline)
    campaigns["contentRevision"] = "2026.10.21.2"
    campaigns["contentRevisionNote"] = "补入上海23号线一期、深圳17号线一期、成都18号线三期三条官方项目建设章；其余项目继续逐条数字化。"
    write(CITY_PATH, cities)
    write(CAMPAIGN_PATH, campaigns)
    write(BASELINE_PATH, baseline)
    print("added Shenzhen Line 17 Phase 1 (18 stations, 8 interchange tasks) and Chengdu Line 18 Phase 3 (5 stations, 8 interchange tasks)")


if __name__ == "__main__":
    main()
