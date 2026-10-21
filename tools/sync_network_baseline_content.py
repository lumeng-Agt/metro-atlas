#!/usr/bin/env python3
"""Synchronize the cutoff inventory and dated event snapshots with authored campaigns.

This deliberately preserves the independently curated project inventory and
milestone ledger, while updating route membership and any authored event/task
rows that changed. It never rewrites campaigns.json.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from build_network_baseline import build


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> dict[str, Any]:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def write(path: str, value: dict[str, Any]) -> None:
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    cities_doc = read("data/cities.json")
    campaigns_doc = read("data/campaigns.json")
    baseline = read("data/network_baselines_2026-10-01.json")
    generated = build(cities_doc, campaigns_doc)
    map_city_by_id = {str(city["id"]): city for city in cities_doc["cities"]}

    for city_id, expected in generated["cities"].items():
        row = baseline["cities"][city_id]
        for field in ("routes", "mapRouteEntryCount", "mapRouteStopOccurrenceCount", "mapUniqueStationCount"):
            row[field] = expected[field]

        config = campaigns_doc["cities"][city_id]
        chapters = config.get("chapters", [])
        chapters_by_id = {str(chapter.get("id", "")): chapter for chapter in chapters}
        chapters_by_date: dict[str, list[dict[str, Any]]] = {}
        for chapter in chapters:
            chapters_by_date.setdefault(str(chapter.get("date", "")), []).append(chapter)

        old_events = row.get("documentedMilestones", [])
        event_by_id = {str(event.get("id", "")): event for event in old_events}
        for authored in config.get("historicalEvents", []):
            event_id = str(authored.get("id", ""))
            event = event_by_id.get(event_id)
            if event is None:
                event = {"id": event_id}
                old_events.append(event)
                event_by_id[event_id] = event
            for field in ("date", "title", "status", "source", "sourceTitle", "sourceType", "sourceCheckedAt", "routeIds", "chapterId", "scope"):
                if field in authored:
                    event[field] = authored[field]
            chapter_id = str(authored.get("chapterId", event.get("chapterId", "")))
            if not chapter_id:
                date_chapters = chapters_by_date.get(str(authored.get("date", event.get("date", ""))), [])
                if date_chapters:
                    chapter_id = str(date_chapters[0].get("id", ""))
            chapter = chapters_by_id.get(chapter_id)
            if chapter is not None:
                event["chapterId"] = chapter_id
                event["targetLineGroups"] = chapter.get("lineGroups", [])

        # Keep all existing generated event IDs, but refresh their target data
        # from the chapter that players actually see and build in.
        for event in old_events:
            chapter_id = str(event.get("chapterId", ""))
            if not chapter_id:
                date_chapters = chapters_by_date.get(str(event.get("date", "")), [])
                if date_chapters:
                    chapter_id = str(date_chapters[0].get("id", ""))
                    event["chapterId"] = chapter_id
            chapter = chapters_by_id.get(chapter_id)
            if chapter is not None and chapter.get("lineGroups"):
                event["targetLineGroups"] = chapter["lineGroups"]
        old_events.sort(key=lambda event: (str(event.get("date", "")), str(event.get("id", ""))))
        row["documentedMilestones"] = old_events
        row["documentedMilestoneCount"] = len(old_events)

        # Insert an interval for any newly-authored dated opening so it cannot
        # be hidden inside the following milestone's period.
        schedule = row.get("milestoneChapters", [])
        known_ends = {str(interval.get("periodEndInclusive", "")) for interval in schedule}
        cutoff = str(baseline.get("cutoffDate", "2026-10-01"))
        authored_dates = sorted({str(ch.get("date", "")) for ch in chapters if ch.get("date") and str(ch.get("date")) < cutoff})
        for date in authored_dates:
            if date in known_ends:
                continue
            if not any(str(event.get("date", "")) == date and str(event.get("chapterId", "")) for event in old_events):
                continue
            previous = max((end for end in known_ends if end < date), default="")
            following = min((end for end in known_ends if end > date), default=cutoff)
            containing = next((interval for interval in schedule if str(interval.get("periodStartExclusive", "")) == previous and str(interval.get("periodEndInclusive", "")) == following), None)
            if containing is None:
                continue
            old_start = str(containing.get("periodStartExclusive", ""))
            containing["periodStartExclusive"] = date
            same_date_chapters = chapters_by_date.get(date, [])
            first = same_date_chapters[0]
            inserted = {
                "id": f"{city_id}-milestone-{date}",
                "periodStartExclusive": old_start,
                "periodEndInclusive": date,
                "title": " / ".join(str(ch.get("title", "历史节点")) for ch in same_date_chapters),
                "eventIds": [], "events": [],
                "chapterIds": [str(ch.get("id", "")) for ch in same_date_chapters],
                "playableChapterId": str(first.get("id", "")),
                "contentStatus": "playable_milestone",
                "routeIds": [], "chapterTargetGroups": [group for ch in same_date_chapters for group in ch.get("lineGroups", [])],
                "chapterTargetStationIds": [], "sources": [],
            }
            known_ends.add(date)
            schedule.append(inserted)

        schedule.sort(key=lambda interval: str(interval.get("periodEndInclusive", "")))
        previous = ""
        event_dates = {str(event.get("id", "")): str(event.get("date", "")) for event in old_events}
        for interval in schedule:
            end = str(interval.get("periodEndInclusive", ""))
            interval["periodStartExclusive"] = previous
            previous = end
            event_rows = [event for event in old_events if str(interval.get("periodStartExclusive", "")) < str(event.get("date", "")) <= end]
            interval["eventIds"] = [str(event.get("id", "")) for event in event_rows]
            interval["events"] = [{field: event.get(field) for field in ("id", "date", "title", "status", "source", "routeIds", "targetLineGroups")} for event in event_rows]
            interval["routeIds"] = sorted({str(route_id) for event in event_rows for route_id in event.get("routeIds", [])})
            matching_chapters = chapters_by_date.get(end, [])
            if matching_chapters:
                interval["chapterIds"] = [str(ch.get("id", "")) for ch in matching_chapters]
                interval["playableChapterId"] = str(matching_chapters[0].get("id", ""))
                interval["title"] = " / ".join(str(ch.get("title", "历史节点")) for ch in matching_chapters)
                groups = [group for chapter in matching_chapters for group in chapter.get("lineGroups", [])]
                interval["chapterTargetGroups"] = groups
                interval["chapterTargetStationIds"] = sorted({str(station_id) for group in groups for station_id in group.get("stationIds", [])})
                interval["sources"] = [{"title": str(ch.get("sourceTitle", "")), "url": str(ch.get("source", ""))} for ch in matching_chapters if ch.get("source")]
                interval["contentStatus"] = "network_reconciliation_complete" if end == cutoff else "playable_milestone"
            elif end == cutoff:
                interval["chapterIds"] = []
                interval["playableChapterId"] = ""
                interval["contentStatus"] = "network_reconciliation_missing"

        row["milestoneChapters"] = schedule
        row["milestoneChapterCount"] = len(schedule)

    baseline["compiledAt"] = "2026-10-21"
    write("data/network_baselines_2026-10-01.json", baseline)
    print("Synchronized route inventories and campaign-linked event snapshots without rewriting campaign content.")


if __name__ == "__main__":
    main()
