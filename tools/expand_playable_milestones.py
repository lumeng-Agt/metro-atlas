#!/usr/bin/env python3
"""Expand the five-city cutoff inventories into playable milestone chapters.

Station order and map geometry are deliberately kept separate from historical
facts: this file records the public opening milestone used to stage each
cutoff route and marks the bundled geometry as an approximate geographic guide.
"""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CUTOFF = "2026-10-01"
CHECKED = "2026-10-20"

# Date of the last public opening milestone needed to reach the cutoff scope of
# each bundled map route. The city event ledger overrides these dates whenever
# it already contains a later route-specific opening event.
ROUTE_DATES = {
    "shanghai": {
        "shanghai-r1":"2007-12-29", "shanghai-r2":"2020-12-26", "shanghai-r3":"2006-12-18", "shanghai-r4":"2007-12-29",
        "shanghai-r5":"2018-12-30", "shanghai-r6":"2011-04-12", "shanghai-r7":"2011-12-28", "shanghai-r8":"2018-12-30",
        "shanghai-r9":"2019-12-30", "shanghai-r10":"2020-12-26", "shanghai-r11":"2024-09-28", "shanghai-r12":"2018-12-30",
        "shanghai-r13":"2021-12-19", "shanghai-r14":"2021-12-30", "shanghai-r15":"2021-01-23", "shanghai-r16":"2019-09-27",
        "shanghai-r17":"2017-12-30", "shanghai-r18":"2025-12-27",
    },
    "beijing": {
        "beijing-r1":"2021-08-26", "beijing-r2":"1987-12-28", "beijing-r3":"2024-12-15", "beijing-r4":"2009-09-28",
        "beijing-r5":"2007-10-07", "beijing-r6":"2021-12-31", "beijing-r7":"2019-12-28", "beijing-r8":"2021-12-31",
        "beijing-r9":"2012-12-30", "beijing-r10":"2013-05-05", "beijing-r11":"2021-12-31", "beijing-r12":"2024-12-15",
        "beijing-r13":"2019-07-26", "beijing-r14":"2021-12-31", "beijing-r15":"2022-12-31", "beijing-r16":"2023-12-30",
        "beijing-r17":"2026-01-31", "beijing-r18":"2025-12-27", "beijing-r19":"2021-12-31", "beijing-r20":"2021-12-31",
        "beijing-r21":"2019-09-26", "beijing-r22":"2017-12-30", "beijing-r23":"2021-12-31", "beijing-r24":"2010-12-30",
    },
    "guangzhou": {
        "guangzhou-r1":"1999-06-28", "guangzhou-r2":"2010-09-25", "guangzhou-r3":"2018-12-28", "guangzhou-r4":"2017-12-28",
        "guangzhou-r5":"2023-12-28", "guangzhou-r6":"2016-12-28", "guangzhou-r7":"2023-12-28", "guangzhou-r8":"2019-12-28",
        "guangzhou-r9":"2017-12-28", "guangzhou-r10":"2025-06-29", "guangzhou-r11":"2025-09-29", "guangzhou-r12":"2025-06-29",
        "guangzhou-r13":"2025-09-29", "guangzhou-r14":"2025-09-29", "guangzhou-r15":"2021-09-28", "guangzhou-r16":"2019-12-20",
        "guangzhou-r17":"2025-12-29", "guangzhou-r18":"2021-12-28", "guangzhou-r19":"2024-08-23", "guangzhou-r20":"2018-12-28",
    },
    "shenzhen": {
        "shenzhen-r1":"2011-06-15", "shenzhen-r2":"2020-10-28", "shenzhen-r3":"2024-12-28", "shenzhen-r4":"2020-10-28",
        "shenzhen-r5":"2025-12-28", "shenzhen-r6":"2020-08-18", "shenzhen-r7":"2025-09-28", "shenzhen-r8":"2016-10-28",
        "shenzhen-r9":"2025-12-28", "shenzhen-r10":"2019-12-08", "shenzhen-r11":"2020-08-18", "shenzhen-r12":"2025-12-28",
        "shenzhen-r13":"2024-12-28", "shenzhen-r14":"2026-06-28", "shenzhen-r15":"2022-10-28", "shenzhen-r16":"2025-09-28",
        "shenzhen-r17":"2021-12-28",
    },
    "chengdu": {
        "chengdu-r1":"2020-09-27", "chengdu-r2":"2014-10-26", "chengdu-r3":"2018-12-26", "chengdu-r4":"2017-12-26",
        "chengdu-r5":"2019-06-02", "chengdu-r6":"2020-12-18", "chengdu-r7":"2017-12-06", "chengdu-r8":"2020-12-18",
        "chengdu-r9":"2020-12-18", "chengdu-r10":"2019-12-27", "chengdu-r11":"2025-12-16", "chengdu-r12":"2020-12-18",
        "chengdu-r13":"2020-09-27", "chengdu-r14":"2023-11-28", "chengdu-r15":"2025-12-16", "chengdu-r16":"2025-12-16",
    },
}

ROUTE_SOURCES = {
    "shanghai": ("https://www.shanghai.gov.cn/nw17239/20260413/d8e14c16213246eba8fac7c23b2b04af.html", "上海地铁全网首末班车时刻表（2026年4月）"),
    "beijing": ("https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202201/t20220101_2581335.html", "北京地铁线路图与运营线路信息；开通分期另见北京交通部门公告"),
    "guangzhou": ("https://www.gz.gov.cn/zwgk/fggw/szfgz/content/post_10694346.html", "广州城市轨道交通运营信息与年度新线开通资料"),
    "shenzhen": ("https://jtys.sz.gov.cn/jtzx/wycx/dtcx/cxtx/", "深圳市交通运输局线路图及分期开通公告目录"),
    "chengdu": ("https://www.chengdurail.com/gywm.htm", "成都轨道集团发展历程与运营线路公开资料"),
}

SPECIAL_LINE_IDS = {
    "shanghai": {"shanghai-r1":"shanghai-line1"},
    "beijing": {"beijing-r1":"beijing-lineearly0", "beijing-r2":"beijing-lineearly1"},
    "guangzhou": {"guangzhou-r1":"guangzhou-line1"},
    "shenzhen": {"shenzhen-r1":"shenzhen-line1", "shenzhen-r4":"shenzhen-line4"},
    "chengdu": {"chengdu-r1":"chengdu-line1"},
}

COLORS = ["#2d78b7", "#e3483f", "#0a9c8a", "#e19b21", "#8c62a9", "#657c45", "#ca5790"]


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def slug(value: str) -> str:
    numbers = re.findall(r"\d+", value)
    if numbers:
        return "line" + "-".join(numbers)
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "route"


def historical_line_id(city_id: str, route: dict, existing_groups: list[dict]) -> str:
    route_id = str(route["mapRouteId"])
    if route_id in SPECIAL_LINE_IDS.get(city_id, {}):
        return SPECIAL_LINE_IDS[city_id][route_id]
    route_stops = set(route.get("cutoffStationIds", []))
    best = (0.0, "")
    used_ids = getattr(historical_line_id, "used_ids", set())
    for group in existing_groups:
        overlap = len(route_stops.intersection(str(x) for x in group.get("stationIds", [])))
        denominator = max(1, min(len(route_stops), len(group.get("stationIds", []))))
        ratio = overlap / denominator
        candidate_id = str(group.get("historicalLineId", ""))
        if candidate_id not in used_ids and ratio > best[0]:
            best = (ratio, str(group.get("historicalLineId", "")))
    if best[0] >= 0.65 and best[1]:
        return best[1]
    line_name = str(route.get("name", route_id))
    code = slug(line_name)
    # Keep foreign system names distinct inside the same city catalog.
    if any(token in line_name for token in ["佛山", "广佛"]):
        code = "foshan-" + code
    # Keep distinct map relations distinct when Chinese names cannot be
    # transliterated by this small generator (such as Beijing branch links).
    return f"{city_id}-{code}-{route_id.rsplit('r', 1)[-1]}"


def make_group(city_id: str, route: dict, map_line: dict, line_id: str, existing_groups: list[dict], route_frequency: dict) -> dict:
    station_ids = [str(x) for x in route.get("cutoffStationIds", [])]
    old_group = max(existing_groups, key=lambda g: len(set(station_ids).intersection(str(x) for x in g.get("stationIds", []))), default={})
    old_instances = {}
    if old_group and str(old_group.get("historicalLineId", "")) == line_id:
        old_instances = {str(key): str(value) for key, value in old_group.get("stationInstances", {}).items()}
    instances = {}
    for station_id in station_ids:
        if int(route_frequency.get(station_id, 0)) <= 1:
            continue
        if station_id in old_instances:
            instances[station_id] = old_instances[station_id]
        elif any(station_id in [str(x) for x in g.get("stationIds", [])] and str(g.get("historicalLineId", "")) == line_id for g in existing_groups):
            # Preserve canonical identities already used by a chapter for this line.
            instances[station_id] = station_id
        else:
            instances[station_id] = f"{station_id}__{slug(line_id)}"
    name = str(route.get("name", map_line.get("name", route["mapRouteId"])))
    color = str(map_line.get("color", COLORS[int(route["mapRouteId"].rsplit("r", 1)[-1]) % len(COLORS)]))
    group = {
        "taskId": "route:" + str(route["mapRouteId"]),
        "mapRouteId": str(route["mapRouteId"]),
        "name": name,
        "stationIds": station_ids,
        "toleranceM": 220,
        "precisionNote": "站区参考来自当前公开站点资料；站间中心线为离线地图近似走廊，不代表隧道测绘。",
        "historicalLineId": line_id,
        "color": color,
        "stationOrderSource": str(route.get("stationOrderSource", "")),
        "alignmentPrecision": "station_areas_and_approximate_corridor",
    }
    if instances:
        group["stationInstances"] = instances
    return group


def main() -> None:
    campaigns_path = ROOT / "data/campaigns.json"
    baseline_path = ROOT / "data/network_baselines_2026-10-01.json"
    cities_path = ROOT / "data/cities.json"
    campaigns = read(campaigns_path)
    baseline = read(baseline_path)
    city_data = {str(x["id"]): x for x in read(cities_path)["cities"]}
    campaigns["contentVersion"] = "0.25.0"
    campaigns["catalogStatus"] = "five_city_cutoff_network_playable"
    campaigns["catalogStatusNote"] = "五城已开通线路逐条进入可玩的建设里程碑，终章执行截止日全网核对；道路几何为现代离线地图近似参考。远期项目仍按项目状态独立展示。"
    campaigns["cutoffDate"] = CUTOFF
    totals = {}

    for city_id, config in campaigns["cities"].items():
        if city_id not in ROUTE_DATES or city_id not in baseline["cities"]:
            continue
        base_city = baseline["cities"][city_id]
        base_city["documentedMilestones"] = [
            event for event in base_city.get("documentedMilestones", [])
            if not str(event.get("id", "")).startswith(f"{city_id}-opening-")
            and str(event.get("id", "")) != f"{city_id}-network-reconciliation-2026-10-01-event"
        ]
        map_city = city_data[city_id]
        map_lines = {str(x.get("id", "")): x for x in map_city.get("lines", [])}
        map_stations = {str(x.get("id", "")): x for x in map_city.get("stations", [])}
        # Rebuild generated route tasks from the cutoff inventory. Keep the
        # authored sample chapters unchanged so old completed samples do not
        # silently inherit newly-added construction targets.
        old_chapters = []
        for original in config.get("chapters", []):
            chapter = dict(original)
            chapter["lineGroups"] = [g for g in chapter.get("lineGroups", []) if not str(g.get("taskId", "")).startswith("route:")]
            chapter["requiredTransfers"] = [t for t in chapter.get("requiredTransfers", []) if not str(t.get("id", "")).startswith("historic-transfer-")]
            for key in ["chapterScope", "routeMilestoneIds", "routeTargetCount", "cutoffRouteIds"]:
                chapter.pop(key, None)
            if not chapter["lineGroups"]:
                continue
            old_chapters.append(chapter)
        existing_groups = [g for ch in old_chapters for g in ch.get("lineGroups", [])]
        route_frequency = defaultdict(int)
        for route in base_city.get("routes", []):
            for stop_id in set(str(x) for x in route.get("cutoffStationIds", [])):
                route_frequency[stop_id] += 1

        routes = base_city.get("routes", [])
        route_specs = {}
        route_date = {}
        historical_line_id.used_ids = set()
        for route in routes:
            route_id = str(route["mapRouteId"])
            if route_id not in map_lines:
                raise ValueError(f"{city_id}/{route_id}: missing map line")
            line_id = historical_line_id(city_id, route, existing_groups)
            historical_line_id.used_ids.add(line_id)
            route_specs[route_id] = make_group(city_id, route, map_lines[route_id], line_id, existing_groups, route_frequency)
            date = ROUTE_DATES[city_id].get(route_id)
            if not date:
                raise ValueError(f"{city_id}/{route_id}: missing curated milestone date")
            # Use the curated last-opening date. Older authored chapters were
            # once copied into the event ledger as if every line mentioned in
            # that chapter had opened on that date; those synthetic rows must
            # never push a route's true opening into a later year. Explicit
            # source-backed dated events can still override the map below.
            later = [
                str(e.get("date", ""))
                for e in base_city.get("documentedMilestones", [])
                if route_id in [str(x) for x in e.get("routeIds", [])]
                and str(e.get("status", "")) != "playable_sample"
                and not str(e.get("id", "")).startswith("chapter-milestone-")
            ]
            route_date[route_id] = max(later + [date])

        by_date = defaultdict(list)
        for route_id, date in route_date.items():
            by_date[date].append(route_id)

        new_chapters = list(old_chapters)
        route_line_for_id = {rid: str(spec["historicalLineId"]) for rid, spec in route_specs.items()}

        # Keep old sample chapters unchanged, and group all lines reaching
        # their cutoff scope at the same construction milestone in one new
        # chapter. Never append targets to a previously-completed sample.
        for date, route_ids in sorted(by_date.items()):
            chapter_id = f"{city_id}-network-milestone-{date}"
            title = "、".join(str(route_specs[rid]["name"]) for rid in sorted(route_ids, key=lambda value: int(value.rsplit("r", 1)[-1]))) + "建设阶段"
            source, source_title = ROUTE_SOURCES[city_id]
            chapter = {
                    "id": chapter_id, "phase": "history", "date": date, "title": title,
                    "lineGroups": [], "requireOpen": True, "eventText": "按本期公开的运营线路范围建设并核对站序。站间几何采用现代地理参考，不代表历史隧道中心线。",
                    "precision": "station_areas", "source": source, "sourceTitle": source_title,
                    "sourceCheckedAt": CHECKED, "sourceType": "government_or_operator_route_inventory_and_opening_records",
                    "status": "operated", "geometryStatus": "station_area_approximation",
                    "alignmentNote": "本章站序与线路范围按公开运营资料整理；底图几何为现代地理位置近似参考。不同日期开通的线路已分章，不把截止日网络倒灌至早期节点。",
                    "sourcePublicationDate": None, "publicationDateNote": "来源页面持续更新；事件日期与页面发布日期分开记录。",
                    "story": {"opening": f"{date[:4]}年前后，{title}进入网络建设阶段。", "purpose": "将本期已经开通的线路范围加入城市路网，并与既有线路建立清楚的物理连接。", "outcome": "本章只记录实际建设的站体、区间和线路关系；几何精度以站区及近似走廊为准。", "eventKind": "network_expansion", "planVersions": [], "steps": [{"id":"intro","action":"read_context"},{"id":"build","action":"use_construction_tools"},{"id":"check","action":"validate_official_scope"},{"id":"opening","action":"confirm_historical_event"},{"id":"outcome","action":"continue_story"}], "beats": []},
                    "operationType": "milestone_network_build", "operationGuide": "建设本期线路站体与相邻区间，再检查线网关系。", "historicalEventIds": [],
                }
            groups = chapter["lineGroups"]
            for route_id in sorted(route_ids, key=lambda value: int(value.rsplit("r", 1)[-1])):
                groups.append(route_specs[route_id])
            chapter["historicalEventIds"] = []
            chapter["routeMilestoneIds"] = sorted(set(route_ids))
            chapter["chapterScope"] = "cutoff_route_completion"
            chapter["routeTargetCount"] = len(chapter["routeMilestoneIds"])
            new_chapters.append(chapter)

        # Create explicit, source-linked route-opening records where the
        # earlier event ledger had not yet assigned a route to a milestone.
        event_by_route_date = defaultdict(list)
        for event in base_city.get("documentedMilestones", []):
            for route_id in event.get("routeIds", []):
                event_by_route_date[(str(route_id), str(event.get("date", "")))].append(event)
        existing_event_ids = {str(e.get("id", "")) for e in base_city.get("documentedMilestones", [])}
        for date, route_ids in sorted(by_date.items()):
            for route_id in route_ids:
                milestone_chapter_id = f"{city_id}-network-milestone-{date}"
                if any(route_id in e.get("routeIds", []) and str(e.get("date", "")) == date and str(e.get("chapterId", "")) == milestone_chapter_id for e in base_city.get("documentedMilestones", [])):
                    continue
                route = next(x for x in routes if str(x.get("mapRouteId")) == route_id)
                route_name = str(route.get("name", route_id))
                event_id = f"{city_id}-opening-{route_id}-{date}"
                if event_id in existing_event_ids:
                    continue
                source, source_title = ROUTE_SOURCES[city_id]
                base_city.setdefault("documentedMilestones", []).append({
                    "id": event_id, "date": date, "title": f"{route_name}截止日线路范围纳入历史建设任务",
                    "status": "opened_or_completed", "source": source, "sourceTitle": source_title,
                    "sourceCheckedAt": CHECKED, "sourceType": "official_route_inventory_cross_checked_with_opening_records",
                    "sourcePublicationDate": None,
                    "scope": "按公开运营线路清单和对应开通事件建立可玩线路任务；逐站开放批次以本章目标和历史事件记录为准。",
                    "routeIds": [route_id], "chapterId": f"{city_id}-network-milestone-{date}",
                    "targetLineGroups": [route_specs[route_id]], "dateBasis": "official_opening_milestone_curated",
                })
                existing_event_ids.add(event_id)

        # Build explicit two-body interchange tasks at the milestone when the
        # second line sharing a named map station reaches its cutoff scope.
        current_line_instances = {}
        for route_id, group in route_specs.items():
            current_line_instances[route_line_for_id[route_id]] = group
        existing_transfer_signatures = set()
        for ch in new_chapters:
            for tr in ch.get("requiredTransfers", []):
                existing_transfer_signatures.add((str(tr.get("complexId", "")), tuple(str(x) for x in tr.get("lineIds", []))))
        route_by_id = {str(r["mapRouteId"]): r for r in routes}
        for station_id, frequency in route_frequency.items():
            if frequency < 2:
                continue
            participating = [rid for rid, route in route_by_id.items() if station_id in [str(x) for x in route.get("cutoffStationIds", [])]]
            participating.sort(key=lambda rid: (route_date[rid], rid))
            for index in range(1, len(participating)):
                route_ids = participating[:index + 1]
                route_ids = [rid for rid in route_ids if route_date[rid] <= route_date[participating[index]]]
                line_ids = [route_line_for_id[rid] for rid in route_ids]
                if len(set(line_ids)) < 2:
                    continue
                date = max(route_date[rid] for rid in route_ids)
                chapter_id = f"{city_id}-network-milestone-{date}"
                chapter = next((item for item in new_chapters if str(item.get("id", "")) == chapter_id), {})
                if not chapter:
                    continue
                instances = []
                for rid, line_id in zip(route_ids, line_ids):
                    group = route_specs[rid]
                    instance = str(group.get("stationInstances", {}).get(station_id, station_id))
                    instances.append(instance)
                for a in range(len(line_ids)):
                    for z in range(a + 1, len(line_ids)):
                        signature = (station_id, (line_ids[a], line_ids[z]))
                        if signature in existing_transfer_signatures:
                            continue
                        transfer_id = "historic-transfer-%s-%s-%s" % (station_id, slug(line_ids[a]), slug(line_ids[z]))
                        chapter.setdefault("requiredTransfers", []).append({
                            "id": transfer_id, "name": str(map_stations.get(station_id, {}).get("name", "换乘站")),
                            "complexId": station_id, "stationInstanceIds": [instances[a], instances[z]],
                            "lineIds": [line_ids[a], line_ids[z]], "precision": "schematic",
                            "source": ROUTE_SOURCES[city_id][0],
                            "sourceNote": "依据公开运营线路站序中的同名/同址换乘节点；具体站内通道结构不作推断。",
                        })
                        existing_transfer_signatures.add(signature)

        # Preserve old stable chapter IDs, then sort chronologically; append a
        # final playable audit of every cutoff route to catch holes accumulated
        # across earlier line-opening tasks.
        unique_chapters = {}
        for chapter in new_chapters:
            unique_chapters[str(chapter.get("id", ""))] = chapter
        chapters = sorted(unique_chapters.values(), key=lambda ch: (str(ch.get("date", "")), str(ch.get("id", ""))))
        source, source_title = ROUTE_SOURCES[city_id]
        audit_id = f"{city_id}-network-reconciliation-2026-10-01"
        audit_groups = []
        for route in routes:
            audit_groups.append(route_specs[str(route["mapRouteId"])])
        audit_event_id = f"{city_id}-network-reconciliation-2026-10-01-event"
        if audit_event_id not in existing_event_ids:
            base_city.setdefault("documentedMilestones", []).append({
                "id": audit_event_id, "date": CUTOFF, "title": "核对截至2026年10月1日的已开通地铁路网",
                "status": "network_reconciliation", "source": source, "sourceTitle": source_title,
                "sourceCheckedAt": CHECKED, "sourceType": "official_route_inventory", "sourcePublicationDate": None,
                "scope": "终章按公开线路名录逐条检查离线路网中的站序与连续轨道；近似几何不代表施工测绘。",
                "routeIds": [str(x["mapRouteId"]) for x in routes], "chapterId": audit_id,
                "targetLineGroups": audit_groups,
            })
        audit = {
            "id": audit_id, "phase": "history", "date": CUTOFF, "title": "截至2026年10月1日 · 全网核对",
            "lineGroups": audit_groups, "requireOpen": True, "eventText": "逐线检查已开通范围、站序与连续连接；线路资料和几何精度分别显示。",
            "precision": "station_areas", "source": source, "sourceTitle": source_title, "sourceCheckedAt": CHECKED,
            "sourceType": "official_route_inventory", "status": "opened_or_completed", "geometryStatus": "station_area_approximation",
            "alignmentNote": "线路名录与截止日运营范围依据公开资料；站间参考走向采用现代离线地图近似线位，不代表隧道测绘。",
            "sourcePublicationDate": None, "publicationDateNote": "页面发布日期与资料截止日期分开记录。",
            "story": {"opening": "历史建设推进到统一核对节点。", "purpose": "检查从早期章节累计建设的各条线路是否覆盖截止日站序与实际轨道连接。", "outcome": "只有逐线评估通过，才记录城市截止日历史节点。未进入已开通范围的在建线路仍单列为建设项目。", "eventKind": "network_reconciliation", "planVersions": [], "steps": [{"id":"intro","action":"read_context"},{"id":"check","action":"validate_official_scope"},{"id":"opening","action":"confirm_historical_event"},{"id":"outcome","action":"continue_story"}], "beats": []},
            "operationType": "network_reconciliation", "operationGuide": "逐线核对截止日站序、物理轨道及线路关系。", "historicalEventIds": [audit_event_id],
            "chapterScope": "cutoff_reconciliation", "cutoffRouteIds": [str(x["mapRouteId"]) for x in routes],
        }
        chapters = [x for x in chapters if str(x.get("id", "")) != audit_id]
        chapters.append(audit)
        chapters.sort(key=lambda ch: (str(ch.get("date", "")), str(ch.get("id", ""))))
        for chapter in chapters:
            chapter["requiredTransfers"] = sorted(chapter.get("requiredTransfers", []), key=lambda item: str(item.get("id", "")))

        # Bind every cutoff historical event to one playable chapter. Some
        # authored ledger rows predate the generated stable chapter IDs; attach
        # those to the first milestone chapter at or after the event instead
        # of leaving them stranded in a non-playable "pending" list.
        for chapter in chapters:
            chapter.setdefault("historicalEventIds", [])
        chapter_by_id = {str(chapter.get("id", "")): chapter for chapter in chapters}
        for event in base_city.get("documentedMilestones", []):
            event_date = str(event.get("date", ""))
            event_id = str(event.get("id", ""))
            if not event_id or not event_date or event_date > CUTOFF:
                continue
            chapter = chapter_by_id.get(str(event.get("chapterId", "")))
            if chapter is None:
                chapter = next((row for row in chapters if str(row.get("date", "")) >= event_date), chapters[-1] if chapters else None)
                if chapter is None:
                    continue
                event["chapterId"] = str(chapter.get("id", ""))
            if event_id not in chapter["historicalEventIds"]:
                chapter["historicalEventIds"].append(event_id)
        for chapter in chapters:
            chapter["historicalEventIds"] = sorted(set(str(value) for value in chapter["historicalEventIds"] if str(value)))
            if not chapter["historicalEventIds"]:
                chapter["historicalEventIds"] = [str(chapter.get("id", ""))]

        # Keep the public interval ledger linked to the playable chapter IDs
        # that the catalog actually contains.
        playable_ids = {str(chapter.get("id", "")) for chapter in chapters}
        for interval in base_city.get("milestoneChapters", []):
            playable_id = str(interval.get("playableChapterId", ""))
            if playable_id in playable_ids:
                interval["contentStatus"] = "network_reconciliation_complete" if playable_id == audit_id else "playable_milestone"
                continue
            end_date = str(interval.get("periodEndInclusive", interval.get("date", "")))
            match = next((row for row in chapters if str(row.get("date", "")) >= end_date), chapters[-1] if chapters else None)
            if match is not None:
                interval["playableChapterId"] = str(match.get("id", ""))
                interval["contentStatus"] = "playable_milestone"

        config["chapters"] = chapters
        # Route inventory tasks are selectable, but this does not claim a
        # complete station-by-station opening chronology or digitized future
        # projects. Keep the session on an explicit historical-content gap.
        config["historyStatus"] = "route_inventory_complete"
        config["futureStatus"] = "partial" if config.get("futurePlans") else "not_digitized"
        config["coverageNote"] = f"截至{CUTOFF}的离线基准线路均已纳入逐线建设任务和终章核对；历史站间几何采用现代地图近似。截止日后在建、批准和研究方案仍按各自资料状态单列。"
        config["catalogCoverage"] = {
            "cutoffDate": CUTOFF,
            "baselineRouteIds": [str(x["mapRouteId"]) for x in routes],
            "playableRouteTaskIds": [str(route_specs[str(x["mapRouteId"])]["taskId"]) for x in routes],
            "playableRouteCount": len(routes), "finalAuditChapterId": audit_id,
            "geometryPolicy": "approximate_current_geography_not_surveyed_tunnel_alignment",
        }

        # Rebuild interval rows from all documented events and the now-playable
        # milestone chapters, keeping one final cutoff row with every route.
        all_events = sorted(base_city.get("documentedMilestones", []), key=lambda e: (str(e.get("date", "")), str(e.get("id", ""))))
        schedule = []
        previous = ""
        by_chapter_date = {str(ch.get("date", "")): ch for ch in chapters if str(ch.get("id", "")) != audit_id}
        for date, chapter in sorted(by_chapter_date.items()):
            events = [e for e in all_events if previous < str(e.get("date", "")) <= date]
            chapter_id = str(chapter.get("id", ""))
            schedule.append({
                "id": f"{city_id}-milestone-{date}", "periodStartExclusive": previous, "periodEndInclusive": date,
                "title": str(chapter.get("title", "地铁建设里程碑")), "eventIds": [str(e.get("id", "")) for e in events],
                "events": [{"id":str(e.get("id","")),"date":str(e.get("date","")),"title":str(e.get("title","")),"status":str(e.get("status","")),"source":str(e.get("source","")),"routeIds":e.get("routeIds",[]),"targetLineGroups":e.get("targetLineGroups",[])} for e in events],
                "chapterIds": [chapter_id], "playableChapterId": chapter_id, "contentStatus": "playable_milestone",
                "routeIds": sorted({str(rid) for e in events for rid in e.get("routeIds", [])}),
                "chapterTargetGroups": chapter.get("lineGroups", []),
                "chapterTargetStationIds": sorted({str(sid) for g in chapter.get("lineGroups", []) for sid in g.get("stationIds", [])}),
                "sources": [{"title":str(e.get("sourceTitle","")),"url":str(e.get("source",""))} for e in events if e.get("source")],
            })
            previous = date
        final_events = [e for e in all_events if previous < str(e.get("date", "")) <= CUTOFF]
        schedule.append({
            "id":f"{city_id}-milestone-cutoff-2026-10-01", "periodStartExclusive":previous, "periodEndInclusive":CUTOFF,
            "title":"截至2026年10月1日全网核对", "eventIds":[str(e.get("id","")) for e in final_events],
            "events":[{"id":str(e.get("id","")),"date":str(e.get("date","")),"title":str(e.get("title","")),"status":str(e.get("status","")),"source":str(e.get("source","")),"routeIds":e.get("routeIds",[]),"targetLineGroups":e.get("targetLineGroups",[])} for e in final_events],
            "chapterIds":[audit_id], "playableChapterId":audit_id, "contentStatus":"network_reconciliation_complete",
            "routeIds":[], "chapterTargetGroups":audit_groups, "chapterTargetStationIds":sorted({str(sid) for g in audit_groups for sid in g.get("stationIds", [])}),
            "targetMapRouteIds":[str(r["mapRouteId"]) for r in routes], "sources":[{"title":ROUTE_SOURCES[city_id][1],"url":source}],
        })
        base_city["documentedMilestones"] = all_events
        base_city["documentedMilestoneCount"] = len(all_events)
        base_city["milestoneChapters"] = schedule
        base_city["milestoneChapterCount"] = len(schedule)
        base_city["contentStatus"] = "playable_cutoff_inventory"
        base_city["playableRouteTaskCount"] = len(routes)
        base_city["unassignedRouteIds"] = []
        base_city["routeTaskSource"] = ROUTE_SOURCES[city_id][0]
        totals[city_id] = {"routes":len(routes),"chapters":len(chapters),"generatedMilestones":len(schedule)}

    baseline["schemaVersion"] = 2
    baseline["contentStatus"] = "playable_cutoff_route_inventories"
    baseline["dataPolicy"] = "官方线路目录与开通节点决定已开通范围；本地线路站序和站间几何作为可玩的地理近似参考，不表示隧道测绘。每条截止日线路均绑定章节任务并在终章核对。截止日后项目状态单独列示，未获得可用走廊几何时不伪造精确路线。"
    write(campaigns_path, campaigns)
    write(baseline_path, baseline)
    print(json.dumps(totals, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
