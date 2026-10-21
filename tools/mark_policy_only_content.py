#!/usr/bin/env python3
"""Keep policy-only catalogue entries out of the blocking project path.

A plan that only states a policy direction ("十五五建设方向", 规划研究, 五期项目库)
has no published station order, so it can never become a buildable chapter. Such
entries stay in the catalogue with their sources, but they stop blocking the
free-creation unlock: their future plan is marked optional and the matching
project row is labelled policy-only instead of "geometry pending".

Only entries listed here are touched, so the change stays auditable.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN_PATH = ROOT / "data/campaigns.json"
BASELINE_PATH = ROOT / "data/network_baselines_2026-10-01.json"

POLICY_PLANS = {
    "sh-2026-2030": "上海市2026—2030年规划实施项目方向，未发布逐站工程蓝图。",
    "sh-2025-2035": "上海市轨道交通线网规划（2025—2035年）原则获批，属线网层面规划。",
    "bj-2020-2035": "北京市轨道交通线网规划（2020—2035年），属线网层面规划。",
    "gz-2023-2035": "广州市综合交通体系规划（2023—2035年），属线网层面规划。",
    "sz-2016-2035": "深圳市轨道交通线网规划（2016—2035年），属线网层面规划。",
    "sz-2024-2035": "深圳市综合立体交通网规划（2024—2035年），属线网层面规划。",
    "cd-fifth-phase-preliminary-2024-2029": "成都市第五期建设规划（2024—2029年）初步方案，尚未形成逐站工程蓝图。",
    "cd-fifteenth-five-year-policy-2026": "“十五五”交通发展政策方向，未发布逐站工程蓝图。",
}

ENGINEERING_PROJECTS = {
    "bj-yizhuang-connector": "亦庄线至5号线、10号线的联络工程，不新增运营车站，按工程条目单列。",
}

POLICY_PROJECTS = {
    "sh-line20-east": "十五五建设方向，仅有规划层面表述，未发布逐站工程蓝图。",
    "sh-line12-west": "规划建设方向，未发布逐站工程蓝图。",
    "sz-fifth-phase-plan": "五期建设规划项目库，属规划集合而非单一工程。",
    "cd-fifth-phase-consultation": "第五期建设规划初步方案征求意见，尚未进入工程实施。",
}


def main() -> None:
    campaigns = json.loads(CAMPAIGN_PATH.read_text(encoding="utf-8"))
    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    changed_plans = []
    for city in campaigns["cities"].values():
        for plan in city.get("futurePlans", []):
            plan_id = str(plan.get("id", ""))
            if plan_id not in POLICY_PLANS:
                continue
            plan["required"] = False
            plan["requiredNote"] = "政策与线网规划条目，仅作资料呈现，不阻塞自由创作；" + POLICY_PLANS[plan_id]
            changed_plans.append(plan_id)
    changed_projects = []
    engineering_projects = []
    for city in baseline["cities"].values():
        for project in city.get("projectsAtCutoff", []):
            project_id = str(project.get("id", ""))
            if project_id in ENGINEERING_PROJECTS:
                project["playabilityStatus"] = "engineering_works_only"
                project["playabilityNote"] = ENGINEERING_PROJECTS[project_id]
                engineering_projects.append(project_id)
                continue
            if project_id not in POLICY_PROJECTS:
                continue
            project["playabilityStatus"] = "policy_only_not_playable"
            project["playabilityNote"] = POLICY_PROJECTS[project_id]
            changed_projects.append(project_id)
    CAMPAIGN_PATH.write_text(json.dumps(campaigns, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    BASELINE_PATH.write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("optional plans:", len(changed_plans), changed_plans)
    print("policy-only projects:", len(changed_projects), changed_projects)
    print("engineering projects:", len(engineering_projects), engineering_projects)


if __name__ == "__main__":
    main()
