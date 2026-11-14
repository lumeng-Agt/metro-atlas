#!/usr/bin/env python3
"""Audit cutoff-date route inventories and playable historical chapter coverage.

Official opening scope and OSM-derived map geometry are reported separately.
The report must never infer that current geometry is a playable history.
"""
from __future__ import annotations

import argparse
import json
import re
from engineering_scope import definition_errors as engineering_definition_errors
from transfer_scope import is_transfer_task
from collections import Counter
from pathlib import Path
from typing import Any


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def unique_route_stations(line: dict[str, Any]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for direction in line.get("directions", []):
        for station_id in direction.get("stationIds", []):
            station_id = str(station_id)
            if station_id not in seen:
                seen.add(station_id)
                result.append(station_id)
    return result


def playable_future_project_ids(campaign: dict[str, Any], city: dict[str, Any]) -> set[str]:
    """Return only projects backed by validated station or engineering scope."""
    known_stations = {str(station.get("id", "")) for station in city.get("stations", [])}
    playable: set[str] = set()
    for plan in campaign.get("futurePlans", []):
        if str(plan.get("dataStatus", "")) != "blueprint_ready":
            continue
        if str(plan.get("exactAlignment", "")) not in {"station_areas", "corridor_only", "verified_alignment"}:
            continue
        project_ids = plan.get("projectIds", [])
        groups = plan.get("lineGroups", [])
        if not isinstance(project_ids, list) or not project_ids or not isinstance(groups, list) or (not groups and not is_transfer_task(plan,str(city.get('id','')))):
            continue
        ready = True
        for group in groups:
            if not isinstance(group, dict):
                ready = False
                break
            if group.get('taskKind') == 'engineering_track':
                if engineering_definition_errors(group, known_stations):
                    ready = False
                    break
                continue
            station_ids = [str(value) for value in group.get("stationIds", [])]
            if len(station_ids) < 2 or float(group.get("toleranceM", 0)) <= 0 or not set(station_ids).issubset(known_stations):
                ready = False
                break
            if not (group.get("stationOrderSource") or group.get("source") or plan.get("source")):
                ready = False
                break
        if ready:
            playable.update(str(project_id) for project_id in project_ids)
    return playable


PUBLISHED_CITY_IDS = ["shenzhen"]


def published_city_ids() -> list[str]:
    """Read the release list from the game so the report cannot drift from it."""
    source = (Path(__file__).resolve().parent.parent / "scripts" / "world_data.gd").read_text(encoding="utf-8")
    match = re.search(r'PUBLISHED_CITY_IDS\s*:?=\s*\[([^\]]*)\]', source)
    if not match:
        raise RuntimeError("Cannot read PUBLISHED_CITY_IDS from scripts/world_data.gd")
    return re.findall(r'"([^"]+)"', match.group(1))


def build_report(cities_doc: dict[str, Any], campaigns_doc: dict[str, Any], baseline_doc: dict[str, Any], cutoff: str, only_cities: list[str] | None = None) -> dict[str, Any]:
    report: dict[str, Any] = {
        "cutoffDate": cutoff,
        "generatedAt": cities_doc.get("generatedAt", "unknown"),
        "mapDataSource": cities_doc.get("osmAttribution", "unknown"),
        "scopeNotice": (
            "Official route-status sources and the bundled OSM route geometry are separate evidence. "
            "A route may be officially open while its complete historical construction is not yet playable."
        ),
        "cities": [],
    }
    for city in cities_doc.get("cities", []):
        city_id = str(city.get("id", ""))
        # The report covers what this build offers. Other cities stay in the
        # data files for catalog validation and existing saves, but naming them
        # in a shipped document would describe a game the player cannot reach.
        if only_cities is not None and city_id not in only_cities:
            continue
        catalog = campaigns_doc.get("cities", {}).get(city_id, {})
        stations = {str(item.get("id", "")): item for item in city.get("stations", [])}
        chapters = catalog.get("chapters", [])
        baseline = baseline_doc.get("cities", {}).get(city_id, {})
        baseline_by_id = {str(row.get("mapRouteId", "")): row for row in baseline.get("routes", [])}
        chapter_groups: list[dict[str, Any]] = []
        all_targets: set[str] = set()
        build_chapters = 0
        event_only_chapters = 0
        route_snapshot_chapters = 0
        for chapter in chapters:
            groups_in_chapter = chapter.get("lineGroups", [])
            if groups_in_chapter:
                build_chapters += 1
                if any(str(group.get("taskId", "")).startswith("route:") and str(group.get("constructionScope", "")) != "new_contiguous_range" for group in groups_in_chapter):
                    route_snapshot_chapters += 1
            elif bool(chapter.get("eventOnly", False)):
                event_only_chapters += 1
            for group in chapter.get("lineGroups", []):
                ids = [str(value) for value in group.get("stationIds", [])]
                all_targets.update(ids)
                chapter_groups.append({
                    "chapterId": str(chapter.get("id", "")),
                    "chapterTitle": str(chapter.get("title", "")),
                    "chapterDate": str(chapter.get("date", "")),
                    "lineId": str(group.get("historicalLineId", "")),
                    "lineName": str(group.get("name", "")),
                    "targetStationCount": len(ids),
                    "targetStationIds": ids,
                    "targetIdsInMapPackage": [value for value in ids if value in stations],
                    "missingTargetIds": [value for value in ids if value not in stations],
                    "alignmentPrecision": str(group.get("alignmentPrecision", group.get("geometryStatus", chapter.get("geometryStatus", chapter.get("precision", "station_areas_or_unspecified"))))),
                    "hasSource": bool(group.get("source") or chapter.get("source") or chapter.get("sources")),
                })
        route_rows: list[dict[str, Any]] = []
        for line in city.get("lines", []):
            map_route_station_ids = unique_route_stations(line)
            cutoff_row = baseline_by_id.get(str(line.get("id", "")), {})
            route_station_ids = [str(value) for value in cutoff_row.get("cutoffStationIds", map_route_station_ids)]
            route_set = set(route_station_ids)
            candidates: list[dict[str, Any]] = []
            for group in chapter_groups:
                overlap = route_set.intersection(group["targetStationIds"])
                if overlap:
                    candidates.append({
                        "chapterId": group["chapterId"],
                        "historicalLineId": group["lineId"],
                        "targetLineName": group["lineName"],
                        "overlapStationCount": len(overlap),
                    })
            candidates.sort(key=lambda row: (-row["overlapStationCount"], row["chapterId"]))
            route_rows.append({
                "mapRouteId": str(line.get("id", "")),
                "name": str(line.get("name", line.get("ref", ""))),
                "ref": str(line.get("ref", "")),
                "routeRelationIds": line.get("osmRelationIds", []),
                "mapSnapshotStationCount": len(map_route_station_ids),
                "stationCount": len(route_station_ids),
                "stationIds": route_station_ids,
                "stationIdsMentionedByAnyPlayableChapter": [value for value in route_station_ids if value in all_targets],
                "stationTargetCoverageCount": len(route_set.intersection(all_targets)),
                "uncoveredStationIds": [value for value in route_station_ids if value not in all_targets],
                "chapterCandidatesByStationIdOverlap": candidates,
                "historicalLineMappingStatus": "map_route_id_crosschecked_against_cutoff_baseline" if str(line.get("id", "")) in baseline_by_id else "missing_from_cutoff_baseline",
                "cutoffOpeningStatus": str(baseline_by_id.get(str(line.get("id", "")), {}).get("cutoffStatus", "not_in_baseline")),
                "cutoffStationCount": len(route_station_ids),
                "fullyRepresentedByPlayableTargets": bool(route_set) and route_set.issubset(all_targets),
                "partiallyRepresentedByPlayableTargets": bool(route_set.intersection(all_targets)) and not route_set.issubset(all_targets),
            })
        all_route_stations = {
            str(station_id)
            for line in city.get("lines", [])
            for station_id in baseline_by_id.get(str(line.get("id", "")), {}).get("cutoffStationIds", unique_route_stations(line))
        }
        map_snapshot_stations = {station_id for line in city.get("lines", []) for station_id in unique_route_stations(line)}
        known_chapter_stations = all_targets.intersection(stations)
        route_frequency = Counter(station_id for line in city.get("lines", []) for station_id in unique_route_stations(line))
        shared_current_stations = sorted(station_id for station_id, count in route_frequency.items() if count > 1)
        fully_covered = [row for row in route_rows if row["fullyRepresentedByPlayableTargets"]]
        partially_covered = [row for row in route_rows if row["partiallyRepresentedByPlayableTargets"]]
        uncovered_routes = [row for row in route_rows if not row["fullyRepresentedByPlayableTargets"]]
        playable_chapter_ids = {str(ch.get("id", "")) for ch in chapters}
        milestones = baseline.get("documentedMilestones", [])
        missing_playable_milestones = [row for row in milestones if row.get("chapterId") not in playable_chapter_ids]
        project_plans = catalog.get("futurePlans", [])
        playable_project_ids = playable_future_project_ids(catalog, city)
        projects = baseline.get("projectsAtCutoff", [])
        project_rows = []
        for project in projects:
            item = dict(project)
            if str(project.get("id", "")) in playable_project_ids:
                item["playableTaskStatus"] = "playable"
            elif str(project.get("playabilityStatus", "")) == "policy_only_not_playable":
                item["playableTaskStatus"] = "policy_only"
            elif str(project.get("playabilityStatus", "")) == "engineering_works_only":
                item["playableTaskStatus"] = "engineering_works"
            else:
                item["playableTaskStatus"] = "not_playable"
            project_rows.append(item)
        playable_project_count = sum(1 for item in project_rows if item["playableTaskStatus"] == "playable")
        report["cities"].append({
            "cityId": city_id,
            "cityName": str(city.get("name", catalog.get("name", city_id))),
            "mapSnapshotGeneratedAt": cities_doc.get("generatedAt", "unknown"),
            "mapRouteEntryCount": len(city.get("lines", [])),
            "mapUniqueRouteStationCount": len(all_route_stations),
            "mapSnapshotUniqueRouteStationCount": len(map_snapshot_stations),
            "officialRouteCount": baseline.get("officialRouteCount"),
            "officialCountBasis": str(baseline.get("countBasis", "")),
            "officialSources": baseline.get("sources", []),
            "projectsAtCutoff": project_rows,
            "projectInventoryCount": len(project_rows),
            "playableProjectCount": playable_project_count,
            "pendingPlayableProjectCount": len(project_rows) - playable_project_count,
            "policyProjectCount": sum(1 for item in project_rows if item["playableTaskStatus"] == "policy_only"),
            "engineeringProjectCount": sum(1 for item in project_rows if item["playableTaskStatus"] == "engineering_works"),
            "playableProjectIds": sorted(playable_project_ids),
            "documentedMilestones": milestones,
            "documentedMilestoneCount": len(milestones),
            "milestoneChapters": baseline.get("milestoneChapters", []),
            "documentedMilestonesWithoutPlayableChapter": missing_playable_milestones,
            "playableChapterCount": len(chapters),
            "buildChapterCount": build_chapters,
            "eventOnlyChapterCount": event_only_chapters,
            "routeSnapshotChapterCount": route_snapshot_chapters,
            "playableChapterLineGroupCount": len(chapter_groups),
            "uniqueChapterTargetCount": len(all_targets),
            "chapterTargetsPresentInMapPackage": len(known_chapter_stations),
            "currentMapStationsNeverTargetedByAnyPlayableChapter": sorted(all_route_stations - all_targets),
            "sharedMapStationIdsAcrossRoutes": shared_current_stations,
            "fullyTargetedRouteEntryCount": len(fully_covered),
            "partiallyTargetedRouteEntryCount": len(partially_covered),
            "untargetedOrPartialRouteIds": [row["mapRouteId"] for row in uncovered_routes],
            "historyStatus": str(catalog.get("historyStatus", "unknown")),
            "futureStatus": str(catalog.get("futureStatus", "unknown")),
            "coverageNote": str(catalog.get("coverageNote", "")),
            "chapterGroups": chapter_groups,
            "mapRoutes": route_rows,
        })
    return report


def write_markdown(report: dict[str, Any], destination: Path) -> None:
    lines = [
        f"# 五城地铁线路历史覆盖核对（截止 {report['cutoffDate']}）",
        "",
        f"地图包快照日期：`{report['generatedAt']}`；来源标注：{report['mapDataSource']}。官方开通状态截止 `2026-10-01`。站点覆盖采用截止日剔除表，地图快照的原始站点数另存于 JSON。",
        "",
        "> 官方来源用于确认公开线路口径和已登记的开通节点；逐线逐站的开通范围及官方站序尚未全部对照。本地线路对象与几何来自 OSM 快照，只提供地图参照，不能单独证明历史建设过程。线路数统计口径按各城来源说明分别展示，不能简单横向比较。",
        "",
        "| 城市 | 官方线路数／口径 | 地图线路条目 | 地图包独立站点 | 章节数 | 有建设目标章节 | 项目资料条目 | 可玩项目章 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for city in report["cities"]:
        lines.append(
            f"| {city['cityName']} | {city['officialRouteCount'] if city['officialRouteCount'] is not None else '口径不等同'} | {city['mapRouteEntryCount']} | {city['mapUniqueRouteStationCount']} | "
            f"{city['playableChapterCount']} | {city['buildChapterCount']} | {city['projectInventoryCount']} | {city['playableProjectCount']} |"
        )
    lines.extend([
        "",
    ])
    lines.extend(["## 截止日线路目录与内容缺口", "", "这里把官方线路口径、历史节点、本地地图目标和项目建设任务分开核对。‘站点覆盖’只表示章节提到对应地图站点编号，不等于按历史分期逐段建设成功。‘有建设目标章节’也不代表城市历史全量通过。项目只有同时关联项目编号和至少一个实际站序建设组，才计为可玩项目章。", ""])
    for city in report["cities"]:
        sources = city.get("officialSources", [])
        if not sources:
            continue
        lines.extend([f"### {city['cityName']}", "", city.get("officialCountBasis", "")])
        if city.get("officialRouteCount") is not None and int(city["officialRouteCount"]) != int(city["mapRouteEntryCount"]):
            lines.append(f"官方统计为{city['officialRouteCount']}，当前离线包为{city['mapRouteEntryCount']}个路线关系条目，差值需要逐项补映射；不能用线路重叠推断已覆盖。")
        lines.append("")
        for source in sources:
            lines.append(f"- [{source['title']}]({source['url']})：{source['supports']}")
        lines.append("")
        if city.get("projectsAtCutoff"):
            policy_count = sum(1 for item in city["projectsAtCutoff"] if item["playableTaskStatus"] == "policy_only")
            engineering_count = sum(1 for item in city["projectsAtCutoff"] if item["playableTaskStatus"] == "engineering_works")
            lines.append(f"截止日建设／规划项目：登记 {city['projectInventoryCount']} 项，可玩建设章 {city['playableProjectCount']} 项，仍待制作 {city['pendingPlayableProjectCount'] - policy_count - engineering_count} 项，另有 {policy_count} 项政策／规划方向（可选）、{engineering_count} 项联络／扩能工程（不新增车站）。")
            lines.append("")
            for project in city["projectsAtCutoff"]:
                if project["playableTaskStatus"] == "playable":
                    task_state = "已有可玩建设任务"
                elif project["playableTaskStatus"] == "policy_only":
                    task_state = "政策／规划方向，未发布逐站蓝图，不阻塞解锁"
                elif project["playableTaskStatus"] == "engineering_works":
                    task_state = "联络／扩能工程，不新增运营车站，按工程条目单列"
                else:
                    task_state = "尚无可玩建设任务"
                lines.append(f"- [{project['name']}]({project['source']}) · `{project['status']}` · {task_state}：{project['note']}")
            lines.append("")
        milestone_chapters = city.get("milestoneChapters", [])
        if milestone_chapters:
            lines.extend(["里程碑区间目录（标为‘内容待制作’的区间不能当作可玩章节）：", "", "| 建设时期 | 里程碑 | 状态 | 地图线路对象／样章目标 |", "|---|---|---|---|"])
            for interval in milestone_chapters:
                start = str(interval.get("periodStartExclusive", "")) or "历史起点"
                end = str(interval.get("periodEndInclusive", ""))
                route_ids = interval.get("routeIds", [])
                target_map_routes = interval.get("targetMapRouteIds", [])
                target_names = [str(group.get("name", group.get("historicalLineId", "样章目标"))) for group in interval.get("chapterTargetGroups", [])]
                route_names = "；".join(part for part in [
                    "地图关系 " + ", ".join(str(route_id) for route_id in route_ids) if route_ids else "",
                    "样章目标 " + "、".join(target_names) if target_names else "",
                    "截止日目标 " + ", ".join(str(route_id) for route_id in target_map_routes) if not route_ids and not target_names and target_map_routes else "",
                ] if part) or "—"
                status = {"playable_sample": "已有可玩章节", "playable_milestone": "已有可玩章节", "content_missing": "内容待制作", "network_reconciliation_missing": "截止日现状核对待制作"}.get(str(interval.get("contentStatus", "")), str(interval.get("contentStatus", "未知")))
                lines.append(f"| {start}—{end} | {interval.get('title', '历史节点')} | {status} | {route_names} |")
            lines.append("")
        lines.append(f"历史事件索引 {city['documentedMilestoneCount']} 项；当前章节 {city['playableChapterCount']} 个，其中含铺轨目标 {city['buildChapterCount']} 个、纯历史节点 {city['eventOnlyChapterCount']} 个、使用整条地图路线目标的章节 {city['routeSnapshotChapterCount']} 个。未进入任何章节的事件 {len(city['documentedMilestonesWithoutPlayableChapter'])} 项。")
        if city["documentedMilestonesWithoutPlayableChapter"]:
            pending = "、".join(f"{item['date']} {item['title']}" for item in city["documentedMilestonesWithoutPlayableChapter"][:12])
            if len(city["documentedMilestonesWithoutPlayableChapter"]) > 12:
                pending += f"等{len(city['documentedMilestonesWithoutPlayableChapter'])}项"
            lines.append(f"未进入可玩章节的已登记历史节点：{pending}")
        lines.append("")
    lines.extend(["## 按城市与线路检查", "", "候选章节只按共享站点编号计算，可能只是换乘站重叠；必须人工核对线路身份、开通日期、站序和官方来源。", ""])
    for city in report["cities"]:
        lines.extend([f"### {city['cityName']}", "", city["coverageNote"], "", "| 地图线路 | 站点数 | 被任一章节目标提及 | 未覆盖站点 | 可能相关章节（仅编号交集） |", "|---|---:|---:|---:|---|"])
        for route in city["mapRoutes"]:
            candidates = ", ".join(f"{item['chapterId']} ({item['overlapStationCount']})" for item in route["chapterCandidatesByStationIdOverlap"][:3]) or "无"
            uncovered = "、".join(route["uncoveredStationIds"][:10]) or "无"
            if len(route["uncoveredStationIds"]) > 10:
                uncovered += f" 等{len(route['uncoveredStationIds'])}站"
            lines.append(f"| {route['name']} `{route['mapRouteId']}` | {route['stationCount']} | {route['stationTargetCoverageCount']} | {uncovered} | {candidates} |")
        lines.append("")
        lines.extend(["本城可玩章节目标与资料状态：", ""])
        for group in city["chapterGroups"]:
            source = "有章节／线路来源链接" if group["hasSource"] else "缺来源链接"
            missing = "；缺地图站点：" + "、".join(group["missingTargetIds"]) if group["missingTargetIds"] else ""
            lines.append(f"- `{group['chapterId']}` {group['chapterDate']} · {group['lineName']}：{group['targetStationCount']}个目标站，线位等级 `{group['alignmentPrecision']}`，{source}{missing}")
        lines.append("")
    lines.extend([
        "## 结论与使用边界",
        "",
        "- 当前可直接得到的是地图包条目数、章节目标数、站点编号覆盖和疑似重叠；这不能替代官方开通年表。",
        "- 站点覆盖使用截止日基准中排除的未开放车站；地图快照自身独立站点数另列。区间站序和几何来自可分发地图数据，不能替代逐线官方站序审查。官方运营线数量和 OSM 路线关系条目数量不是同一口径。",
        "- 已确认开通的线路不再因缺少隧道测绘中心线而排除；未进入章节的线路和历史节点在表中明确列出。线位可用近似走廊，但不能把当前完整路线套到早期开放年份。",
        "- 目前五城均有截至日的线路目标和历史章节目录，但章节数与地图站点覆盖不能证明逐期建设完整；仍需逐段核对开通日期、站序、线路归属和拓扑。",
        "- 当前项目目录的条目数不是可玩项目章数量。只有登记状态明确、包含实际站序和建设目标的项目才可进入项目章验收；未完成的项目不能解锁自由创作。",
        "- 本审计不把磁浮、市域线、机场线或其他轨道类别自动算作地铁主线；需要分类复核。",
        "",
    ])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cities", type=Path, default=Path("data/cities.json"))
    parser.add_argument("--campaigns", type=Path, default=Path("data/campaigns.json"))
    parser.add_argument("--baseline", type=Path, default=Path("data/network_baselines_2026-10-01.json"))
    parser.add_argument("--cutoff", default="2026-10-01")
    parser.add_argument("--json-out", type=Path, default=Path("docs/network-coverage-2026-10-01.json"))
    parser.add_argument("--markdown-out", type=Path, default=Path("docs/network-coverage-2026-10-01.md"))
    parser.add_argument("--all-cities", action="store_true", help="Include cities this build does not publish")
    args = parser.parse_args()
    only = None if args.all_cities else published_city_ids()
    report = build_report(read_json(args.cities), read_json(args.campaigns), read_json(args.baseline), args.cutoff, only)
    if str(read_json(args.baseline).get("cutoffDate", "")) != args.cutoff:
        raise SystemExit("Requested cutoff does not match the source-controlled network baseline")
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(report, args.markdown_out)
    totals = {
        "cities": len(report["cities"]),
        "mapRouteEntries": sum(city["mapRouteEntryCount"] for city in report["cities"]),
        "playableChapters": sum(city["playableChapterCount"] for city in report["cities"]),
        "unreferencedMapStations": sum(len(city["currentMapStationsNeverTargetedByAnyPlayableChapter"]) for city in report["cities"]),
        "fullyTargetedRouteEntries": sum(city["fullyTargetedRouteEntryCount"] for city in report["cities"]),
        "partiallyTargetedRouteEntries": sum(city["partiallyTargetedRouteEntryCount"] for city in report["cities"]),
    }
    print(json.dumps(totals, ensure_ascii=False))


if __name__ == "__main__":
    main()
