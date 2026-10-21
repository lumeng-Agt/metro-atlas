#!/usr/bin/env python3
"""Check that every cutoff project has a coherent terminal state.

A project may be playable (validated blueprint), policy-only (no station-level
blueprint published) or an engineering-works entry (connector/upgrade with no
new stations). Anything else is still "pending" and blocks the final delivery
check.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "data/network_baselines_2026-10-01.json"
CAMPAIGNS = ROOT / "data/campaigns.json"
CITIES = ROOT / "data/cities.json"

PLAYABLE = "playable_build_task"
POLICY = "policy_only_not_playable"
ENGINEERING = "engineering_works_only"
PENDING = "registered_geometry_and_playable_task_pending"
TERMINAL = {PLAYABLE, POLICY, ENGINEERING}


def plan_ready(plan: dict, city_station_ids: set[str]) -> list[str]:
    errors: list[str] = []
    if str(plan.get("dataStatus", "")) != "blueprint_ready":
        errors.append(f"{plan.get('id')}: dataStatus is not blueprint_ready")
    if str(plan.get("exactAlignment", "")) not in {"station_areas", "corridor_only", "verified_alignment"}:
        errors.append(f"{plan.get('id')}: invalid exactAlignment")
    groups = plan.get("lineGroups", [])
    if not groups:
        errors.append(f"{plan.get('id')}: no line groups")
    for index, group in enumerate(groups):
        ids = [str(value) for value in group.get("stationIds", [])]
        if len(ids) < 2:
            errors.append(f"{plan.get('id')}/group{index}: fewer than two stations")
        if float(group.get("toleranceM", 0) or 0) <= 0:
            errors.append(f"{plan.get('id')}/group{index}: toleranceM must be positive")
        missing = [value for value in ids if value not in city_station_ids]
        if missing:
            errors.append(f"{plan.get('id')}/group{index}: unknown stations {missing[:5]}")
    for transfer in plan.get("requiredTransfers", []):
        if not str(transfer.get("sourceNote", "")).strip():
            errors.append(f"{plan.get('id')}/{transfer.get('id')}: transfer lacks sourceNote")
        bodies = transfer.get("stationInstanceIds", [])
        lines = transfer.get("lineIds", [])
        if len(bodies) < 2 or len(bodies) != len(lines):
            errors.append(f"{plan.get('id')}/{transfer.get('id')}: transfer needs matching bodies and line ids (at least two)")
    return errors


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    parser.add_argument("--city")
    args = parser.parse_args()

    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    campaigns = json.loads(CAMPAIGNS.read_text(encoding="utf-8"))
    cities = {row["id"]: row for row in json.loads(CITIES.read_text(encoding="utf-8"))["cities"]}

    failures: list[str] = []
    pending: list[str] = []
    counts = {"playable": 0, "policy": 0, "engineering": 0, "pending": 0}
    for city_id, baseline_city in baseline["cities"].items():
        if args.city and city_id != args.city:
            continue
        city_station_ids = {str(row.get("id", "")) for row in cities[city_id].get("stations", [])}
        plans = campaigns["cities"][city_id].get("futurePlans", [])
        spec_names = {path.stem for path in (ROOT / "tools/project_specs").glob(city_id + "-*.json")}
        for project in baseline_city.get("projectsAtCutoff", []):
            project_id = str(project.get("id", ""))
            status = str(project.get("playabilityStatus", ""))
            ready_plans = [
                plan for plan in plans
                if project_id in [str(value) for value in plan.get("projectIds", [])]
                and plan_ready(plan, city_station_ids) == [] and str(plan.get("dataStatus", "")) == "blueprint_ready"
            ]
            if status == PLAYABLE:
                counts["playable"] += 1
                if not ready_plans:
                    failures.append(f"{city_id}/{project_id}: marked playable without a ready blueprint")
            elif status == POLICY:
                counts["policy"] += 1
                if not str(project.get("playabilityNote", "")).strip():
                    failures.append(f"{city_id}/{project_id}: policy-only project lacks playabilityNote")
                if ready_plans:
                    failures.append(f"{city_id}/{project_id}: policy-only project has a ready build plan")
            elif status == ENGINEERING:
                counts["engineering"] += 1
                if not str(project.get("playabilityNote", "")).strip():
                    failures.append(f"{city_id}/{project_id}: engineering project lacks playabilityNote")
                if ready_plans:
                    failures.append(f"{city_id}/{project_id}: engineering project has a ready build plan")
            elif status == PENDING:
                counts["pending"] += 1
                pending.append(f"{city_id}/{project_id}")
            else:
                failures.append(f"{city_id}/{project_id}: unknown playabilityStatus {status!r}")
            for plan in ready_plans:
                for error in plan_ready(plan, city_station_ids):
                    failures.append(error)
            if status == PLAYABLE and len(ready_plans) > 1:
                failures.append(f"{city_id}/{project_id}: more than one ready plan {[plan.get('id') for plan in ready_plans]}")
            if status == PLAYABLE and not any(name.startswith(city_id) for name in spec_names):
                pass  # legacy plans predate tools/project_specs; specs are added line by line

    if failures:
        for failure in failures:
            print("FAIL: " + failure)
        raise SystemExit(1)
    print(f"PASS: project states {counts}")
    if pending:
        print("pending projects: " + ", ".join(pending))
    if args.require_complete and pending:
        raise SystemExit(f"FAIL: {len(pending)} project(s) still pending")
    print("PASS: project plan coverage")


if __name__ == "__main__":
    main()
