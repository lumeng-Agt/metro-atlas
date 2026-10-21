"""Generate the project-chapter delivery report from campaign and baseline data.

Usage:
    python tools/report_project_chapters.py [--check]

Reads data/network_baselines_2026-10-01.json and data/campaigns.json, then writes
docs/project-chapters-2026-10.md. With --check it only verifies the committed
report matches the data (used by CI).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "data" / "network_baselines_2026-10-01.json"
CAMPAIGNS = ROOT / "data" / "campaigns.json"
REPORT = ROOT / "docs" / "project-chapters-2026-10.md"

CITY_ORDER = ["shanghai", "beijing", "guangzhou", "shenzhen", "chengdu"]
CITY_NAMES = {"shanghai": "上海", "beijing": "北京", "guangzhou": "广州", "shenzhen": "深圳", "chengdu": "成都"}
STATUS_LABELS = {
    "playable_build_task": "可玩建设章",
    "policy_only_not_playable": "政策条目",
    "engineering_works_only": "工程条目",
    "registered_geometry_and_playable_task_pending": "待制作",
}


def load() -> tuple[dict, dict]:
    return (
        json.loads(BASELINE.read_text(encoding="utf-8")),
        json.loads(CAMPAIGNS.read_text(encoding="utf-8")),
    )


def plans_by_project(city: dict) -> dict[str, list[dict]]:
    mapping: dict[str, list[dict]] = {}
    for plan in city.get("futurePlans", []):
        for pid in plan.get("projectIds") or []:
            mapping.setdefault(str(pid), []).append(plan)
    return mapping


def render(baseline: dict, campaigns: dict) -> str:
    lines: list[str] = []
    lines.append("# 五城在建／规划项目章交付台账（2026-10-01 截止日）")
    lines.append("")
    lines.append("由 `tools/report_project_chapters.py` 从 `data/network_baselines_2026-10-01.json` 与 `data/campaigns.json` 生成，随数据一起校验；请勿手工编辑。")
    lines.append("")
    totals = {"playable_build_task": 0, "policy_only_not_playable": 0, "engineering_works_only": 0, "registered_geometry_and_playable_task_pending": 0}
    for cid in CITY_ORDER:
        city_data = campaigns["cities"][cid]
        base = baseline["cities"][cid]
        plans = plans_by_project(city_data)
        lines.append(f"## {CITY_NAMES[cid]}")
        lines.append("")
        lines.append("| 项目 | 终态 | 章数 | 车站 | 精度 | 来源 |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for project in base.get("projectsAtCutoff", []):
            status = project.get("playabilityStatus") or "registered_geometry_and_playable_task_pending"
            totals[status] = totals.get(status, 0) + 1
            pid = str(project["id"])
            related = plans.get(pid, [])
            station_count = 0
            precisions: set[str] = set()
            for plan in related:
                for group in plan.get("lineGroups", []):
                    station_count += len(group.get("stationIds", []))
                    if group.get("alignmentPrecision"):
                        precisions.add(str(group["alignmentPrecision"]))
            precision = "、".join(sorted(precisions)) if precisions else "—"
            source = project.get("source", "")
            src = f"[{project.get('sourceTitle') or '来源'}]({source})" if source else "—"
            lines.append(
                f"| {project.get('name', pid)} | {STATUS_LABELS.get(status, status)} | {len(related)} | {station_count or '—'} | {precision} | {src} |"
            )
        lines.append("")
    lines.append("## 合计")
    lines.append("")
    lines.append(f"- 可玩建设章：{totals['playable_build_task']}")
    lines.append(f"- 政策条目：{totals['policy_only_not_playable']}")
    lines.append(f"- 工程条目：{totals['engineering_works_only']}")
    lines.append(f"- 待制作：{totals['registered_geometry_and_playable_task_pending']}")
    lines.append("")
    lines.append("走廊复现章（`corridor_only`）只表示按官方公开资料可核对的端点／换乘站与走廊，未公开的逐站站位不虚构坐标；判定依据见各章 `precisionNote`。")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    baseline, campaigns = load()
    text = render(baseline, campaigns)
    if args.check:
        current = REPORT.read_text(encoding="utf-8") if REPORT.exists() else ""
        if current != text:
            print("FAIL: docs/project-chapters-2026-10.md is stale; run tools/report_project_chapters.py", file=sys.stderr)
            return 1
        print("PASS: project chapter report is up to date")
        return 0
    REPORT.write_text(text, encoding="utf-8")
    print(f"wrote {REPORT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
