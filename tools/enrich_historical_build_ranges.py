#!/usr/bin/env python3
"""Attach source-backed opening ranges to dated construction events.

The offline OSM station coordinates provide the map anchors.  The explicit
ordered station-name ranges below come from the cited official opening history
and Shenzhen transport pages; they are not inferred from the modern map's
line order.  Each range remains a station-area target, not a surveyed tunnel
centerline.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHENZHEN_HISTORY = "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"
SHENZHEN_2020_OPENINGS = "https://ka.sz.gov.cn/gkmlpt/content/5/5366/post_5366691.html"
SHENZHEN_2022_OPENINGS = SHENZHEN_HISTORY
SHENZHEN_2023_LINE8 = "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_11072547.html"
SHENZHEN_2024_OPENINGS = "https://www.sz.gov.cn/cn/xxgk/zfxxgj/gqdt/content/post_11930882.html"
SHENZHEN_2025_OPENINGS = "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_12576035.html"
SHANGHAI_NORTH = "https://www.shanghai.gov.cn/nw9822/20200906/0001-9822_97192.html"
SHANGHAI_LINE18_PHASE2 = "https://www.shanghai.gov.cn/nw15343/20251229/fcb5d15bff724f659dcc8aea717df2ba.html"

# Stable event id -> (historical line id, display name, exact ordered station names).
# Ranges are the construction scope for that dated opening. Existing stations
# in a range are reused, so extension tasks do not require rebuilding them.
RANGES: dict[str, list[tuple[str, str, list[str]]]] = {
    "shenzhen-2009-09-28-line1-extension": [
        ("shenzhen-line1", "1号线二期首通段", ["世界之窗", "白石洲", "高新园", "深大"]),
    ],
    "shenzhen-2010-12-28-lines2-3": [
        ("shenzhen-line2-2", "2号线一期", ["赤湾", "蛇口港", "海上世界", "水湾", "东角头", "湾厦", "海月", "登良", "后海", "科苑", "红树湾", "世界之窗"]),
        ("shenzhen-line3-3", "3号线一期", ["草埔", "布吉", "木棉湾", "大芬", "丹竹头", "六约", "塘坑", "横岗", "永湖", "荷坳", "大运", "爱联", "吉祥", "龙城广场", "南联", "双龙"]),
    ],
    "shenzhen-2011-06-16-line4-qinghu": [
        ("shenzhen-line4", "4号线北延伸", ["福田口岸", "福民", "会展中心", "市民中心", "少年宫", "莲花北", "上梅林", "民乐", "白石龙", "深圳北站", "红山", "上塘", "龙胜", "龙华", "清湖"]),
    ],
    "shenzhen-2011-06-22-line5": [
        ("shenzhen-line5-5", "5号线一期", ["前海湾", "临海", "宝华", "宝安中心", "翻身", "灵芝", "洪浪北", "兴东", "留仙洞", "西丽", "大学城", "塘朗", "长岭陂", "深圳北站", "民治", "五和", "坂田", "杨美", "上水径", "下水径", "长龙", "布吉", "百鸽笼", "布心", "太安", "怡景", "黄贝岭"]),
    ],
    "shenzhen-2011-06-28-lines2-3-extensions": [
        ("shenzhen-line2-2", "2号线二期", ["世界之窗", "侨城北", "深康", "安托山", "侨香", "香蜜", "香梅北", "景田", "莲花西", "福田", "市民中心", "岗厦北", "华强北", "燕南", "大剧院", "湖贝", "黄贝岭", "新秀"]),
        ("shenzhen-line3-3", "3号线二期", ["益田", "石厦", "购物公园", "福田", "少年宫", "莲花村", "华新", "通新岭", "红岭", "老街", "晒布", "翠竹", "田贝", "水贝", "草埔"]),
    ],
    # The bundled 2020 OSM route relations confuse the through-running Line 2/8
    # corridor and omit the newly opened Line 3 and Line 8 segments. Use the
    # official line-specific opening scope for that milestone.
    "shenzhen-2020-10-28-lines2-3-4-8": [
        ("shenzhen-line2-2", "2号线三期至莲塘", ["赤湾", "蛇口港", "海上世界", "水湾", "东角头", "湾厦", "海月", "登良", "后海", "科苑", "红树湾", "世界之窗", "侨城北", "深康", "安托山", "侨香", "香蜜", "香梅北", "景田", "莲花西", "福田", "市民中心", "岗厦北", "华强北", "燕南", "大剧院", "湖贝", "黄贝岭", "新秀", "莲塘口岸", "仙湖路", "莲塘"]),
        ("shenzhen-line3-3", "3号线南延至福保", ["福保", "益田", "石厦", "购物公园", "福田", "少年宫", "莲花村", "华新", "通新岭", "红岭", "老街", "晒布", "翠竹", "田贝", "水贝", "草埔", "布吉", "木棉湾", "大芬", "丹竹头", "六约", "塘坑", "横岗", "永湖", "荷坳", "大运", "爱联", "吉祥", "龙城广场", "南联", "双龙"]),
        ("shenzhen-line4", "4号线北延至牛湖", ["福田口岸", "福民", "会展中心", "市民中心", "少年宫", "莲花北", "上梅林", "民乐", "白石龙", "深圳北站", "红山", "上塘", "龙胜", "龙华", "清湖", "清湖北", "竹村", "茜坑", "长湖", "观澜", "松元厦", "观澜湖", "牛湖"]),
        ("shenzhen-line8-9", "8号线一期至盐田路", ["莲塘", "梧桐山南", "沙头角", "海山", "盐田港西", "深外高中", "盐田路"]),
    ],
    "shenzhen-2024-12-28-five-openings": [
        ("shenzhen-line3-3", "3号线四期东延至坪地六联", ["双龙", "梨园", "新生", "坪西", "低碳城", "白石塘", "富坪", "坪地六联"]),
        ("shenzhen-line7-8", "7号线二期至深大丽湖", ["西丽湖", "北大", "深大丽湖"]),
        ("shenzhen-line11-12", "11号线二期岗厦北至华强南段", ["岗厦北", "华强南"]),
        ("shenzhen-line12-13", "12号线二期至松岗", ["海上田园东", "蚝乡", "沙蚝", "沙井古墟", "步涌", "朗下", "松岗"]),
        ("shenzhen-line13-14", "13号线一期南段至高新中", ["深圳湾口岸", "人才公园", "后海", "科苑", "粤海门", "深大", "高新中"]),
    ],
    "shenzhen-2016-06-28-line11": [
        ("shenzhen-line11-12", "11号线一期", ["福田", "车公庙", "红树湾南", "后海", "南山", "前海湾", "宝安", "碧海湾", "机场", "机场北", "福永", "桥头", "塘尾", "马安山", "沙井", "后亭", "松岗", "碧头"]),
    ],
    "shenzhen-2016-10-28-lines7-9": [
        ("shenzhen-line7-8", "7号线一期", ["西丽湖", "西丽", "茶光", "珠光", "龙井", "桃源村", "深云", "安托山", "农林", "车公庙", "上沙", "沙尾", "石厦", "皇岗村", "福民", "皇岗口岸", "赤尾", "华强南", "华强北", "华新", "黄木岗", "八卦岭", "红岭北", "笋岗", "洪湖", "田贝", "太安"]),
        ("shenzhen-line9-10", "9号线一期", ["红树湾南", "深湾", "深圳湾公园", "下沙", "车公庙", "香梅", "景田", "梅景", "下梅林", "梅村", "上梅林", "孖岭", "银湖", "泥岗", "红岭北", "园岭", "红岭", "红岭南", "鹿丹村", "人民南", "向西村", "文锦"]),
    ],
    "shenzhen-2019-09-28-line5-phase2": [
        ("shenzhen-line5-5", "5号线西延段", ["赤湾", "荔湾", "铁路公园", "妈湾", "前湾公园", "前湾", "桂湾", "前海湾"]),
    ],
    "shenzhen-2022-10-28-lines11-14": [
        ("shenzhen-line11-12", "11号线东延至岗厦北", ["福田", "岗厦北"]),
    ],
    "shenzhen-2022-11-28-line6-branch-line12": [
        ("shenzhen-line6-7", "6号线支线一期", ["光明", "圳美", "中大", "深理工"]),
        ("shenzhen-line12-13", "12号线一期", ["左炮台东", "太子湾", "海上世界", "花果山", "四海", "南油", "南光", "南山", "桃园", "南头古城", "中山公园", "同乐南", "新安公园", "灵芝", "上川", "流塘", "宝安客运站", "平峦山", "西乡桃源", "钟屋南", "黄田", "兴围", "机场东", "福围", "怀德", "福永", "桥头西", "福海西", "国展", "国展北", "海上田园南", "海上田园东"]),
    ],
    "shenzhen-2022-12-28-line16": [
        ("shenzhen-line16-16", "16号线一期", ["田心", "技术大学", "石井", "燕子湖", "沙壆", "东纵纪念馆", "坪环", "坪山围", "六和", "新和", "坪山", "宝龙同乐", "龙东", "新塘围", "双龙", "龙园", "盛平", "尚景", "回龙埔", "愉园", "黄阁坑", "龙城公园", "大运中心", "大运"]),
    ],
    "shenzhen-2023-12-27-line8-phase2": [
        ("shenzhen-line8-9", "8号线二期至小梅沙", ["盐田路", "鸿安围", "盐田墟", "大梅沙", "小梅沙"]),
    ],
    "shenzhen-2025-12-28-lines5-8-11-13": [
        ("shenzhen-line5-5", "5号线西延至大剧院", ["黄贝岭", "湖贝", "东门", "大剧院"]),
        ("shenzhen-line8-9", "8号线三期至溪涌", ["小梅沙", "溪涌"]),
        ("shenzhen-line11-12", "11号线二期华强南至红岭南段", ["华强南", "福星", "红岭南"]),
        ("shenzhen-line13-14", "13号线一期北段贯通至上屋", ["高新中", "高新北", "石鼓", "留仙洞", "百旺", "应人石", "罗租", "石岩", "上屋"]),
    ],
    "shenzhen-opening-shenzhen-r13-2025-12-28": [
        ("shenzhen-line13-14", "13号线一期贯通至上屋", ["深圳湾口岸", "人才公园", "后海", "科苑", "粤海门", "深大", "高新中", "高新北", "石鼓", "留仙洞", "百旺", "应人石", "罗租", "石岩", "上屋"]),
    ],
    "shenzhen-2026-06-28-line13-north": [
        # The north extension starts at the 2025 terminal Shangwu. Keep that
        # shared terminal as an anchor and target only the 11 newly opened
        # station areas, rather than replaying the whole 26-stop line.
        ("shenzhen-line13-14", "13号线二期北延至李松蓢", ["上屋", "红坳公园", "光明城", "德雅路", "凤凰城", "月亮路", "将围", "新庄", "公明广场", "上村", "下村", "李松蓢"]),
    ],
    "shanghai-event-2004-12-28-line1-north-extension": [
        ("shanghai-line1", "1号线北延伸段", ["上海火车站", "中山北路", "延长路", "上海马戏城", "汶水路", "彭浦新村", "共康路", "通河新村", "呼兰路", "共富新村"]),
    ],
    "shanghai-2025-12-27-line18-phase2": [
        ("shanghai-line18-18", "18号线二期宝山段", ["长江南路", "通南路", "长江西路", "爱辉路", "呼兰路", "康文路"]),
    ],
    "chengdu-event-2018-03-18-03": [
        ("chengdu-line1", "1号线三期", ["广都", "四河", "华府大道", "天府五街", "天府三街", "世纪城", "锦城广场", "孵化园", "金融城", "高新", "火车南站", "桐梓林", "倪家桥", "省体育馆", "华西坝", "锦江宾馆", "天府广场", "骡马市", "文殊院", "人民北路", "火车北站", "升仙湖", "韦家碾"]),
    ],
}

RANGE_SOURCES = {
    "shenzhen-2020-10-28-lines2-3-4-8": SHENZHEN_2020_OPENINGS,
    "shenzhen-2022-10-28-lines11-14": SHENZHEN_2022_OPENINGS,
    "shenzhen-2024-12-28-five-openings": SHENZHEN_2024_OPENINGS,
    "shenzhen-2023-12-27-line8-phase2": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_11072547.html",
    "shenzhen-2025-12-28-lines5-8-11-13": SHENZHEN_2025_OPENINGS,
    "shenzhen-opening-shenzhen-r13-2025-12-28": SHENZHEN_2025_OPENINGS,
    "shenzhen-2026-06-28-line13-north": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_12866204.html",
    "shanghai-event-2004-12-28-line1-north-extension": SHANGHAI_NORTH,
    "shanghai-2025-12-27-line18-phase2": SHANGHAI_LINE18_PHASE2,
    "chengdu-event-2018-03-18-03": "https://www.chengdurail.com/gywm.htm",
}

REPLACED_LINE_IDS = {
    "shenzhen-2022-10-28-lines11-14": {"shenzhen-line11-12"},
    "shenzhen-2024-12-28-five-openings": {"shenzhen-line3-3", "shenzhen-line7-8", "shenzhen-line11-12", "shenzhen-line12-13", "shenzhen-line13-14"},
    "shenzhen-2023-12-27-line8-phase2": {"shenzhen-line8-9"},
    "shenzhen-2025-12-28-lines5-8-11-13": {"shenzhen-line5-5", "shenzhen-line8-9", "shenzhen-line11-12", "shenzhen-line12-13", "shenzhen-line13-14"},
    "shenzhen-opening-shenzhen-r13-2025-12-28": {"shenzhen-line12-13", "shenzhen-line13-14"},
    "shenzhen-2026-06-28-line13-north": {"shenzhen-line13-14"},
    "shanghai-2025-12-27-line18-phase2": {"shanghai-line18-18"},
}

# Authored historical names that differ from the current map label. Keep these
# overrides when dated ranges replace broad route snapshots.
HISTORICAL_STATION_NAMES = {
    "guangzhou-1997-06-28-03": {"guangzhou-s298": "西朗"},
    "shanghai-1995-04-10-03": {
        "shanghai-s118": "黄陂南路",
        "shanghai-s422": "新龙华",
    },
}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def display_name(station_id: str, city_name: str, groups: list[dict]) -> str:
    for group in groups:
        if station_id in group.get("stationNames", {}):
            return str(group["stationNames"][station_id])
    return city_name


def target_group(city_id: str, event_id: str, line_id: str, display: str, names: list[str], city: dict, route_templates: dict, all_groups: list[dict], source_url: str) -> dict:
    template = route_templates.get(line_id)
    if template is None:
        raise ValueError(f"{event_id}: missing route template for {line_id}")
    refs = {str(item["id"]): item for item in city["stations"]}
    template_ids = [str(value) for value in template.get("stationIds", [])]
    candidates_by_name: dict[str, list[str]] = {}
    for station_id, station in refs.items():
        name = display_name(station_id, str(station.get("name", "")), all_groups)
        candidates_by_name.setdefault(name, []).append(station_id)
    chosen_ids = []
    missing = []
    for name in names:
        choices = [station_id for station_id in template_ids if display_name(station_id, str(refs.get(station_id, {}).get("name", "")), all_groups) == name]
        if not choices:
            choices = candidates_by_name.get(name, [])
        if not choices:
            missing.append(name)
            continue
        # Prefer one station reference already attached to the line, then the
        # first stable city reference when an official interchange has aliases.
        station_id = choices[0]
        if station_id in chosen_ids:
            missing.append(name)
            continue
        chosen_ids.append(station_id)
    if missing:
        raise ValueError(f"{event_id}/{line_id}: station references not found: {', '.join(missing)}")
    if len(chosen_ids) < 2:
        raise ValueError(f"{event_id}/{line_id}: construction range needs at least two stations")
    old_instances = template.get("stationInstances", {})
    # Reuse the physical body identity already established by an earlier
    # segment of this same line. A station must not become a second target
    # merely because the later chapter uses a different target group.
    existing_instances: dict[str, str] = {}
    for existing_group in all_groups:
        if str(existing_group.get("historicalLineId", "")) != line_id:
            continue
        for historical_id in existing_group.get("stationIds", []):
            historical_id = str(historical_id)
            existing_instances.setdefault(
                historical_id,
                str(existing_group.get("stationInstances", {}).get(historical_id, historical_id)),
            )
    line_suffix = line_id.split("-", 1)[-1]
    station_instances = {}
    for station_id in chosen_ids:
        station_instances[station_id] = existing_instances.get(
            station_id,
            str(old_instances.get(station_id, f"{station_id}__{line_suffix}")),
        )
    result = copy.deepcopy(template)
    result.update({
        "taskId": f"dated:{event_id}:{line_id}",
        "name": display,
        "stationIds": chosen_ids,
        "stationInstances": station_instances,
        "toleranceM": min(float(template.get("toleranceM", 180)), 220),
        "precisionNote": "站序按官方开通历史资料；站点锚点取离线地图，隧道中心线未作为精测数据。",
        "stationOrderSource": f"官方逐站站序：{source_url}" if source_url else str(template.get("stationOrderSource", "")),
        "alignmentPrecision": "station_area_approximation",
        "source": source_url or str(template.get("source", "")),
    })
    result.pop("requiredTransfers", None)
    return result


def main() -> None:
    campaigns_path = ROOT / "data/campaigns.json"
    baseline_path = ROOT / "data/network_baselines_2026-10-01.json"
    campaigns = read(campaigns_path)
    baseline = read(baseline_path)
    map_cities = {str(city["id"]): city for city in read(ROOT / "data/cities.json")["cities"]}
    summary = {}
    for city_id, campaign in campaigns["cities"].items():
        chapters = campaign.get("chapters", [])
        cutoff = next((chapter for chapter in chapters if chapter.get("chapterScope") == "cutoff_reconciliation"), None)
        if cutoff is None:
            cutoff = next((chapter for chapter in chapters if str(chapter.get("date", "")) == "2026-10-01" and "reconciliation" in str(chapter.get("id", ""))), None)
        if cutoff is None:
            raise ValueError(f"{city_id}: missing cutoff template chapter")
        route_templates = {str(group.get("historicalLineId", "")): group for group in cutoff.get("lineGroups", [])}
        all_groups = [group for chapter in chapters for group in chapter.get("lineGroups", [])]
        city = map_cities[city_id]
        updated = 0
        for event in baseline["cities"][city_id].get("documentedMilestones", []):
            specs = RANGES.get(str(event.get("id", "")), [])
            if not specs:
                continue
            existing = event.setdefault("targetLineGroups", [])
            replaced = REPLACED_LINE_IDS.get(str(event.get("id", "")), set())
            if replaced:
                existing[:] = [group for group in existing if str(group.get("historicalLineId", "")) not in replaced]
            for line_id, display, names in specs:
                source_url = RANGE_SOURCES.get(str(event.get("id", "")), str(event.get("source", "")))
                candidate = target_group(city_id, str(event["id"]), line_id, display, names, city, route_templates, all_groups, source_url)
                historical_names = HISTORICAL_STATION_NAMES.get(str(event["id"]), {})
                candidate_names = {station_id: historical_names[station_id] for station_id in candidate["stationIds"] if station_id in historical_names}
                if candidate_names:
                    candidate["stationNames"] = candidate_names
                exact = next((group for group in existing if str(group.get("historicalLineId", "")) == line_id and [str(x) for x in group.get("stationIds", [])] == candidate["stationIds"]), None)
                if exact is None:
                    existing[:] = [group for group in existing if str(group.get("historicalLineId", "")) != line_id]
                    existing.append(candidate)
                    updated += 1
            if event.get("targetLineGroups"):
                event["chapterScope"] = "dated_opening_segment"
        summary[city_id] = {"newBuildRanges": updated, "buildEvents": sum(1 for event in baseline["cities"][city_id].get("documentedMilestones", []) if event.get("targetLineGroups"))}
    write(baseline_path, baseline)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
