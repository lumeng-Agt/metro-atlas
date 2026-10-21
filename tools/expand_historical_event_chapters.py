#!/usr/bin/env python3
"""Turn every dated, source-indexed city milestone into a stable story chapter.

The line-inventory chapters remain the cutoff-network safety net. This pass
adds the dated historical events that were previously folded into a later
route chapter, preserving supplied station targets where the event has them.
Events without a build range are presented as source-backed history nodes and
are never dressed up as construction tasks.
"""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CUTOFF = "2026-10-01"
VERSION = "0.25.0"
AUTHORED_PERIOD_NAMES = {
    "gz-line1-1997": {"guangzhou-s298": "西朗"},
    "sh-line1-1993": {"shanghai-s422": "新龙华"},
    "sh-line1-1995": {
        "shanghai-s118": "黄陂南路",
        "shanghai-s422": "新龙华",
    },
}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def stable_date(value: str) -> str:
    value = value.strip()
    return re.sub(r"[^0-9-]", "", value) or "undated"


def make_event_chapter(city_id: str, date: str, events: list[dict], chapters: list[dict]) -> dict:
    by_date = [chapter for chapter in chapters if str(chapter.get("date", "")) == date]
    # Attach the event to an existing chapter on the same day when possible.
    # This keeps authored construction scenes and stable save IDs intact.
    chosen = None
    for event in events:
        event_chapter_id = str(event.get("chapterId", ""))
        chosen = next((chapter for chapter in by_date if str(chapter.get("id", "")) == event_chapter_id), None)
        if chosen is not None:
            break
    if chosen is None and by_date:
        chosen = next((chapter for chapter in by_date if "network-reconciliation" in str(chapter.get("id", ""))), None)
    if chosen is None and by_date:
        chosen = next((chapter for chapter in by_date if "network-milestone" in str(chapter.get("id", ""))), by_date[0])
    if chosen is not None:
        # A source event can carry a staged construction range even when its
        # date already has an authored chapter. Merge that range into the
        # playable chapter rather than leaving it stranded in the source ledger.
        line_groups = chosen.setdefault("lineGroups", [])
        for event in events:
            for raw_group in event.get("targetLineGroups", []):
                if not isinstance(raw_group, dict) or len(raw_group.get("stationIds", [])) < 2:
                    continue
                group = json.loads(json.dumps(raw_group, ensure_ascii=False))
                line_id = str(group.get("historicalLineId", ""))
                existing = next((item for item in line_groups if str(item.get("historicalLineId", "")) == line_id), None)
                if existing is None:
                    line_groups.append(group)
                    continue
                old_ids = [str(value) for value in existing.get("stationIds", [])]
                new_ids = [str(value) for value in group.get("stationIds", [])]
                if old_ids != new_ids:
                    # The dated source range is authoritative for this event.
                    # Do not union a later route snapshot into the event: that
                    # can silently introduce stations opened in another year.
                    old_names = dict(existing.get("stationNames", {}))
                    old_instances = dict(existing.get("stationInstances", {}))
                    existing.clear()
                    existing.update(group)
                    names = old_names
                    names.update(group.get("stationNames", {}))
                    instances = old_instances
                    instances.update(group.get("stationInstances", {}))
                    if names:
                        existing["stationNames"] = names
                    if instances:
                        existing["stationInstances"] = instances
                names = dict(existing.get("stationNames", {}))
                names.update(group.get("stationNames", {}))
                if names:
                    existing["stationNames"] = names
                instances = dict(existing.get("stationInstances", {}))
                instances.update(group.get("stationInstances", {}))
                if instances:
                    existing["stationInstances"] = instances
        if not line_groups:
            chosen["eventOnly"] = True
        else:
            chosen["eventOnly"] = False
        return chosen

    titles = [str(event.get("title", "歷史節點")).strip() for event in events if str(event.get("title", "")).strip()]
    title = "、".join(dict.fromkeys(titles)) or "地铁建设历史节点"
    source_event = next((event for event in events if str(event.get("source", ""))), {})
    source = str(source_event.get("source", ""))
    source_title = str(source_event.get("sourceTitle", "官方历史资料索引"))
    status = str(source_event.get("status", "historical_context"))
    has_build_scope = any(event.get("targetLineGroups") for event in events)
    groups: list[dict] = []
    for event in events:
        for raw_group in event.get("targetLineGroups", []):
            if not isinstance(raw_group, dict) or len(raw_group.get("stationIds", [])) < 2:
                continue
            group = json.loads(json.dumps(raw_group, ensure_ascii=False))
            group.setdefault("taskId", "event:%s:%s" % (str(event.get("id", "event")), str(group.get("historicalLineId", "line"))))
            # Do not create a second route task for a line already targeted on
            # this date; the existing group is authoritative for this chapter.
            existing = next((candidate for candidate in groups if str(candidate.get("historicalLineId", "")) == str(group.get("historicalLineId", ""))), None)
            if existing is None:
                groups.append(group)
            else:
                old_ids = [str(value) for value in existing.get("stationIds", [])]
                new_ids = [str(value) for value in group.get("stationIds", [])]
                if old_ids != new_ids:
                    # Dated source data wins over a current-map route snapshot.
                    # Combining disjoint sequences invents a station order.
                    old_names = dict(existing.get("stationNames", {}))
                    old_instances = dict(existing.get("stationInstances", {}))
                    existing.clear()
                    existing.update(group)
                    names = old_names
                    names.update(group.get("stationNames", {}))
                    instances = old_instances
                    instances.update(group.get("stationInstances", {}))
                    if names:
                        existing["stationNames"] = names
                    if instances:
                        existing["stationInstances"] = instances
                names = dict(existing.get("stationNames", {}))
                names.update(group.get("stationNames", {}))
                if names:
                    existing["stationNames"] = names
                instances = dict(existing.get("stationInstances", {}))
                instances.update(group.get("stationInstances", {}))
                if instances:
                    existing["stationInstances"] = instances

    if not groups:
        summary = "；".join(str(event.get("scope", "")) for event in events if str(event.get("scope", "")))
        opening = "%s：%s" % (date, title)
        purpose = summary or "本章记录已登记的历史资料节点。此节点没有足够的站段范围可要求玩家铺轨。"
        outcome = "完成本历史资料节点。它不新增线路，也不替代后续有建设范围的章节。"
        steps = [{"id": "intro", "action": "read_context"}, {"id": "record", "action": "confirm_historical_record"}, {"id": "outcome", "action": "continue_story"}]
    else:
        opening = "%s：%s" % (date, title)
        purpose = "按本期来源列出的站序与站段建设；已建目标可复用。未提供的隧道测绘不作精确线位要求。"
        outcome = "记录本期来源明确的站段与线路变化；后续分期仍按各自日期建设。"
        steps = [{"id": "intro", "action": "read_context"}, {"id": "build", "action": "use_construction_tools"}, {"id": "check", "action": "validate_official_scope"}, {"id": "opening", "action": "confirm_historical_event"}, {"id": "outcome", "action": "continue_story"}]
    return {
        "id": "%s-historical-milestone-%s" % (city_id, stable_date(date)),
        "phase": "history",
        "date": date,
        "title": title,
        "lineGroups": groups,
        "requireOpen": bool(groups) and status in ["opened_or_completed", "opened_or_operated", "trial_operation"],
        "eventText": opening,
        "precision": "station_areas" if groups else "schematic",
        "source": source,
        "sourceTitle": source_title,
        "sourceCheckedAt": str(source_event.get("sourceCheckedAt", "2026-10-20")),
        "sourceType": str(source_event.get("sourceType", "official_historical_event_index")),
        "status": status,
        "geometryStatus": "source_station_range" if groups else "no_build_geometry",
        "alignmentNote": "仅使用该事件明确列出的站区及站序；没有公布的工程中心线不作推断。" if groups else "资料节点；没有可核实建设站段，不要求玩家放站或铺轨。",
        "sourcePublicationDate": source_event.get("sourcePublicationDate"),
        "publicationDateNote": "来源页面发布日期与事件日期分别记录。",
        "chapterScope": "documented_historical_event" if not groups else "dated_opening_segment",
        "eventOnly": not groups,
        "historicalEventIds": [],
        "story": {"opening": opening, "purpose": purpose, "outcome": outcome, "eventKind": "historical_record" if not groups else "dated_network_change", "planVersions": [], "steps": steps, "beats": []},
        "operationType": "historical_record" if not groups else "dated_station_segment",
        "operationGuide": "查看来源资料并确认此历史节点。" if not groups else "建设本期明确列出的站段；检查后确认历史节点。",
    }


def refresh_schedule(city_id: str, city: dict, campaign: dict, cutoff: str) -> None:
    chapters = campaign.get("chapters", [])
    chapter_by_date: dict[str, list[dict]] = defaultdict(list)
    for chapter in chapters:
        chapter_by_date[str(chapter.get("date", ""))].append(chapter)
    events = city.get("documentedMilestones", [])
    all_dates = sorted({date for date in chapter_by_date if date and date <= cutoff} | {str(event.get("date", "")) for event in events if str(event.get("date", "")) and str(event.get("date", "")) <= cutoff})
    rows = []
    previous = ""
    for date in all_dates:
        dated_chapters = chapter_by_date.get(date, [])
        dated_events = [event for event in events if str(event.get("date", "")) == date]
        chapter_ids = [str(item.get("id", "")) for item in dated_chapters]
        route_ids = sorted({str(route_id) for event in dated_events for route_id in event.get("routeIds", [])})
        if not route_ids:
            route_ids = sorted({str(route_id) for item in dated_chapters for route_id in item.get("routeMilestoneIds", [])})
        groups = []
        for item in dated_chapters:
            groups.extend(json.loads(json.dumps(item.get("lineGroups", []), ensure_ascii=False)))
        target_ids = sorted({str(station_id) for group in groups for station_id in group.get("stationIds", [])})
        if date == cutoff:
            status = "network_reconciliation_complete"
            title = next((str(item.get("title", "截止日全网核对")) for item in dated_chapters if item.get("chapterScope") == "cutoff_reconciliation"), "截至2026年10月1日全网核对")
            route_ids = sorted({str(route.get("mapRouteId", "")) for route in city.get("routes", [])})
        else:
            status = "playable_milestone"
            title = str(dated_chapters[0].get("title", "历史建设里程碑")) if dated_chapters else "、".join(str(item.get("title", "历史节点")) for item in dated_events)
        rows.append({
            "id": "%s-milestone-%s" % (city_id, stable_date(date)),
            "periodStartExclusive": previous,
            "periodEndInclusive": date,
            "title": title,
            "eventIds": [str(event.get("id", "")) for event in dated_events],
            "events": json.loads(json.dumps(dated_events, ensure_ascii=False)),
            "chapterIds": chapter_ids,
            "playableChapterId": chapter_ids[0] if chapter_ids else "",
            "contentStatus": status,
            "eventOnly": bool(dated_chapters) and all(bool(item.get("eventOnly", False)) for item in dated_chapters),
            "routeIds": route_ids,
            "targetMapRouteIds": route_ids if date == cutoff else [],
            "chapterTargetGroups": groups,
            "chapterTargetStationIds": target_ids,
        })
        previous = date
    if not rows or rows[-1]["periodEndInclusive"] != cutoff:
        raise ValueError(f"{city_id}: no 2026-10-01 cutoff chapter")
    city["milestoneChapters"] = rows
    city["milestoneChapterCount"] = len(rows)


def incrementalize_build_groups(chapters: list[dict], cutoff: str) -> dict[str, int]:
    """Turn later whole-route snapshots into the newly added contiguous ranges.

    Existing stations remain in each range only as connection anchors. This
    keeps the map's route inventory useful for the final audit while avoiding
    asking the player to redraw every earlier station at each milestone.
    The source station sequence is retained for audit/rebuild diagnostics.
    """
    # Make generation idempotent: a second run must start from the retained
    # unsplit range, never from the already shortened player-facing target.
    for chapter in chapters:
        restored_groups: list[dict] = []
        restored_tasks: set[str] = set()
        has_service_ranges = bool(chapter.get("serviceTransitions", []))
        for group in chapter.get("lineGroups", []):
            if not isinstance(group, dict):
                continue
            if has_service_ranges:
                # Service-transition chapters carry the historically opened
                # station sequence, which may intentionally be narrower than
                # the current full route. Do not restore a route snapshot over
                # that authoritative range or split it again on each build.
                if group.get("constructionScope") in ["new_contiguous_range", "reuse_and_verify"]:
                    group["taskId"] = re.sub(r"(?::range-\d+)+$", "", str(group.get("taskId", "")))
                    for field in ["sourceStationIds", "sourceStationInstances", "sourceStationNames", "constructionScope", "constructionScopeNote"]:
                        group.pop(field, None)
                restored_groups.append(group)
                continue
            if group.get("constructionScope") == "new_contiguous_range":
                task_id = re.sub(r"(?::range-\d+)+$", "", str(group.get("taskId", "")))
                if task_id in restored_tasks:
                    continue
                restored_tasks.add(task_id)
                if isinstance(group.get("sourceStationIds"), list):
                    group["stationIds"] = list(group["sourceStationIds"])
                if isinstance(group.get("sourceStationInstances"), dict):
                    group["stationInstances"] = dict(group["sourceStationInstances"])
                if isinstance(group.get("sourceStationNames"), dict):
                    group["stationNames"] = dict(group["sourceStationNames"])
                group["taskId"] = task_id
                for field in ["sourceStationIds", "sourceStationInstances", "sourceStationNames", "constructionScope", "constructionScopeNote"]:
                    group.pop(field, None)
            elif group.get("constructionScope") == "reuse_and_verify":
                group.pop("constructionScope", None)
                group.pop("constructionScopeNote", None)
            restored_groups.append(group)
        chapter["lineGroups"] = restored_groups

    built_by_line: dict[str, set[str]] = defaultdict(set)
    changed_groups = 0
    removed_duplicate_groups = 0
    for chapter in sorted(chapters, key=lambda row: (str(row.get("date", "")), str(row.get("id", "")))):
        chapter_date = str(chapter.get("date", ""))
        is_final_audit = chapter_date >= cutoff or str(chapter.get("chapterScope", "")) == "cutoff_reconciliation"
        operation = str(chapter.get("operationType", ""))
        preserve_whole_group = is_final_audit or bool(chapter.get("requiresLineReorganization", False)) or bool(chapter.get("serviceTransitions", [])) or operation in {
            "line_reorganization", "station_rename", "network_reconciliation", "historical_record",
        }
        groups = chapter.get("lineGroups", [])
        if not isinstance(groups, list):
            continue
        next_groups: list[dict] = []
        current_chapter_added: dict[str, set[str]] = defaultdict(set)
        for group in groups:
            if not isinstance(group, dict):
                continue
            line_id = str(group.get("historicalLineId", ""))
            ids = [str(value) for value in group.get("stationIds", [])]
            if not line_id or len(ids) < 2 or preserve_whole_group:
                next_groups.append(group)
                current_chapter_added[line_id].update(ids)
                continue
            prior_ids = built_by_line[line_id] | current_chapter_added[line_id]
            if not prior_ids:
                next_groups.append(group)
                current_chapter_added[line_id].update(ids)
                continue
            new_positions = [index for index, station_id in enumerate(ids) if station_id not in prior_ids]
            if not new_positions:
                # Keep the verified target for network checks, but tell the UI
                # and audit this is reuse/verification rather than fresh build.
                group["constructionScope"] = "reuse_and_verify"
                group["constructionScopeNote"] = "本期没有新的站区目标；复用前期已建实体，只核对线路归属与连接。"
                next_groups.append(group)
                continue
            runs: list[tuple[int, int]] = []
            start = previous = new_positions[0]
            for index in new_positions[1:]:
                if index != previous + 1:
                    runs.append((start, previous))
                    start = index
                previous = index
            runs.append((start, previous))
            for run_number, (start, end) in enumerate(runs, start=1):
                left = start - 1 if start > 0 and ids[start - 1] in prior_ids else start
                right = end + 1 if end + 1 < len(ids) and ids[end + 1] in prior_ids else end
                segment = json.loads(json.dumps(group, ensure_ascii=False))
                segment["sourceStationIds"] = ids
                if isinstance(group.get("stationInstances"), dict) and group.get("stationInstances"):
                    segment["sourceStationInstances"] = dict(group["stationInstances"])
                if isinstance(group.get("stationNames"), dict) and group.get("stationNames"):
                    segment["sourceStationNames"] = dict(group["stationNames"])
                segment["stationIds"] = ids[left:right + 1]
                segment["constructionScope"] = "new_contiguous_range"
                segment["constructionScopeNote"] = "仅建设本期新增连续区段；与已建线路共用的端站作为接头复用。"
                original_task = str(group.get("taskId", "task"))
                segment["taskId"] = f"{original_task}:range-{run_number}"
                if len(runs) > 1:
                    segment["name"] = f"{str(group.get('name', line_id))} · 本期新增段{run_number}"
                station_instances = group.get("stationInstances", {})
                if isinstance(station_instances, dict):
                    segment["stationInstances"] = {key: value for key, value in station_instances.items() if key in segment["stationIds"]}
                station_names = group.get("stationNames", {})
                if isinstance(station_names, dict):
                    segment["stationNames"] = {key: value for key, value in station_names.items() if key in segment["stationIds"]}
                    if not segment["stationNames"]:
                        segment.pop("stationNames", None)
                next_groups.append(segment)
                current_chapter_added[line_id].update(segment["stationIds"])
                changed_groups += 1
            if len(new_positions) < len(ids):
                removed_duplicate_groups += 1
        lines_with_new_ranges = {
            str(group.get("historicalLineId", ""))
            for group in next_groups
            if group.get("constructionScope") == "new_contiguous_range"
        }
        # A generated full-route snapshot and a dated event may both target the
        # same line on the same day. Once the new ranges are present, discard
        # the redundant whole-line reuse check from that duplicate source row.
        chapter["lineGroups"] = [
            group for group in next_groups
            if not (str(group.get("historicalLineId", "")) in lines_with_new_ranges and group.get("constructionScope") == "reuse_and_verify")
        ]
        for line_id, station_ids in current_chapter_added.items():
            built_by_line[line_id].update(station_ids)
    return {"incrementalGroups": changed_groups, "groupsReducedToNewRanges": removed_duplicate_groups}


def main() -> None:
    campaigns_path = ROOT / "data/campaigns.json"
    baseline_path = ROOT / "data/network_baselines_2026-10-01.json"
    campaigns = read(campaigns_path)
    baseline = read(baseline_path)
    campaigns["contentVersion"] = VERSION
    campaigns["catalogStatus"] = "source_indexed_milestone_chapters"
    campaigns["catalogStatusNote"] = "按五城来源台账中每个明确日期建立稳定历史节点；有来源站段的节点可建设，无几何范围的史料节点明确为只读确认。现状线路范围章节保留为截止日核对目标。"
    campaigns["cutoffDate"] = CUTOFF
    summary = {}
    for city_id, config in campaigns["cities"].items():
        row = baseline["cities"][city_id]
        old = list(config.get("chapters", []))
        events_by_date: dict[str, list[dict]] = defaultdict(list)
        for event in row.get("documentedMilestones", []):
            date = str(event.get("date", ""))
            if date and date <= CUTOFF:
                events_by_date[date].append(event)
        chapters = list(old)
        for date, events in sorted(events_by_date.items()):
            chapter = make_event_chapter(city_id, date, events, chapters)
            if chapter not in chapters:
                chapters.append(chapter)
            # Keep event history exact by date. Old broad route milestones had
            # absorbed earlier dates; those associations are replaced here.
            chapter.setdefault("historicalEventIds", [])
            chapter["historicalEventIds"] = sorted(set(str(value) for value in chapter["historicalEventIds"] if str(value)) | {str(event.get("id", "")) for event in events if str(event.get("id", ""))})
            for event in events:
                event["chapterId"] = str(chapter.get("id", ""))
        # An interchange complex contains one physical body per line. Keep
        # those identities in the same groups used by construction and route
        # evaluation instead of collapsing them to the complex's shared ID.
        for chapter in chapters:
            groups_by_line = {
                str(group.get("historicalLineId", "")): group
                for group in chapter.get("lineGroups", [])
            }
            for transition in chapter.get("serviceTransitions", []):
                line_id = str(transition.get("historicalLineId", ""))
                group = groups_by_line.get(line_id)
                transition_ids = [str(value) for value in transition.get("stationIds", [])]
                group_ids = [str(value) for value in group.get("stationIds", [])] if group else []
                if group and len(transition_ids) >= 2:
                    start = next((index for index in range(max(0, len(group_ids) - len(transition_ids) + 1)) if group_ids[index:index + len(transition_ids)] == transition_ids), -1)
                    if start < 0:
                        # The historical service ledger is the source for the
                        # opened range. Keep its exact order in the construction
                        # target too; a shorter target makes the opening status
                        # impossible to validate or reproduce.
                        group["stationIds"] = transition_ids
                        group.pop("sourceStationIds", None)
                        group.pop("constructionScope", None)
                        group.pop("constructionScopeNote", None)
                        for field in ["stationInstances", "stationNames"]:
                            values = group.get(field, {})
                            if isinstance(values, dict):
                                group[field] = {key: value for key, value in values.items() if key in transition_ids}
            for transfer in chapter.get("requiredTransfers", []):
                line_ids = [str(value) for value in transfer.get("lineIds", [])]
                instance_ids = [str(value) for value in transfer.get("stationInstanceIds", [])]
                complex_id = str(transfer.get("complexId", ""))
                for transfer_index, line_id in enumerate(line_ids):
                    group = groups_by_line.get(line_id)
                    if group is None or complex_id not in [str(value) for value in group.get("stationIds", [])]:
                        continue
                    if transfer_index >= len(instance_ids):
                        continue
                    group.setdefault("stationInstances", {})[complex_id] = instance_ids[transfer_index]
            historic_names = AUTHORED_PERIOD_NAMES.get(str(chapter.get("id", "")), {})
            for group in chapter.get("lineGroups", []):
                group_names = group.setdefault("stationNames", {})
                for station_id, historical_name in historic_names.items():
                    if station_id in [str(value) for value in group.get("stationIds", [])]:
                        group_names[station_id] = historical_name
                if not group_names:
                    group.pop("stationNames", None)
        incremental_summary = incrementalize_build_groups(chapters, CUTOFF)
        # A date can contain multiple older authored chapters. Stable sorting
        # keeps those intact, and event chapters always sit at their true date.
        unique = {str(chapter.get("id", "")): chapter for chapter in chapters}
        for chapter in unique.values():
            for group in chapter.get("lineGroups", []):
                group.setdefault("toleranceM", 180.0)
        config["chapters"] = sorted(unique.values(), key=lambda chapter: (str(chapter.get("date", "")), str(chapter.get("id", ""))))
        config["historyStatus"] = "route_inventory_complete"
        config["coverageNote"] = "所有已登记来源日期均可在时间轴中逐项查看；有明确站段范围的节点可建设，缺少站段资料的节点不伪装成铺轨关卡。截止日现状线路另有全网核对。未覆盖的中间分期和截止日后工程继续列明。"
        refresh_schedule(city_id, row, config, CUTOFF)
        summary[city_id] = {"chapters": len(config["chapters"]), "datedSourceEvents": len(events_by_date), "eventOnlyChapters": sum(1 for chapter in config["chapters"] if chapter.get("eventOnly")), "buildChapters": sum(1 for chapter in config["chapters"] if chapter.get("lineGroups")), **incremental_summary}
    write(campaigns_path, campaigns)
    write(baseline_path, baseline)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
