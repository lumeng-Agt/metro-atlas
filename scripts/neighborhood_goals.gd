class_name NeighborhoodGoals
extends RefCounted

const MAX_ACTIVE := 3
const STABLE_MINUTES := 60

static func update(state: Dictionary, flows: Array[Dictionary], absolute_minute: int) -> bool:
	var board: Dictionary = state.get("goalBoard", {"active": [], "completed": []})
	var active: Array = board.get("active", [])
	var finished: Array = board.get("completed", [])
	var sim: Dictionary = state.get("simulation", {})
	var completed_by_flow: Dictionary = sim.get("completedByFlow", {})
	var attempted_by_flow: Dictionary = sim.get("attemptedByFlow", {})
	var trip_minutes_by_flow: Dictionary = sim.get("tripMinutesByFlow", {})
	var active_ids: Dictionary = {}
	var completed_ids: Dictionary = {}
	for goal in active: active_ids[str(goal.get("id", ""))] = true
	for goal in finished: completed_ids[str(goal.get("id", ""))] = true
	var changed := false
	var retained: Array = []
	for raw_goal in active:
		if not raw_goal is Dictionary: continue
		var goal: Dictionary = raw_goal
		var goal_type := str(goal.get("type", ""))
		var flow := _find_flow(flows, str(goal.get("flowId", "")))
		if goal_type in ["coverage", "transfer"]:
			var journey_valid := not flow.is_empty() and bool(flow.get("valid", false))
			if goal_type == "transfer": journey_valid = journey_valid and flow.get("routeIds", []).size() > 1
			if not journey_valid:
				if str(goal.get("status", "")) != "build" or int(goal.get("stableSince", -1)) >= 0:
					goal.status = "build"
					goal.stableSince = -1
					changed = true
			else:
				var current_completed := int(completed_by_flow.get(str(goal.flowId), 0))
				if int(goal.get("stableSince", -1)) < 0 and current_completed > int(goal.get("baselineCompleted", 0)):
					goal.stableSince = absolute_minute
					goal.baselineCompleted = current_completed
					goal.baselineAttempted = int(attempted_by_flow.get(str(goal.flowId), 0))
					goal.baselineTripMinutes = float(trip_minutes_by_flow.get(str(goal.flowId), 0.0))
					goal.beforeWindow = _flow_window(sim, str(goal.flowId), absolute_minute - 1, STABLE_MINUTES)
					goal.status = "observe"
					changed = true
				elif int(goal.get("stableSince", -1)) >= 0 and absolute_minute - int(goal.stableSince) >= STABLE_MINUTES:
					var completed_now := current_completed - int(goal.get("baselineCompleted", 0))
					var attempted_now := int(attempted_by_flow.get(str(goal.flowId), 0)) - int(goal.get("baselineAttempted", 0))
					var minutes_now := float(trip_minutes_by_flow.get(str(goal.flowId), 0.0)) - float(goal.get("baselineTripMinutes", 0.0))
					var after_window := _flow_window(sim, str(goal.flowId), absolute_minute, STABLE_MINUTES)
					if after_window.attempted <= 0:
						after_window = {"attempted": attempted_now, "completed": completed_now, "tripMinutes": minutes_now, "serviceRate": 100.0 * float(completed_now) / maxf(1.0, float(attempted_now)), "averageMinutes": minutes_now / maxf(1.0, float(completed_now))}
					var before_window: Dictionary = goal.get("beforeWindow", {"attempted": 0, "completed": 0, "tripMinutes": 0.0, "serviceRate": 0.0, "averageMinutes": 0.0})
					var result := {"id": goal.id, "type": goal_type, "title": goal.get("title", "街区目标"), "flowId": goal.get("flowId", ""), "stableMinutes": STABLE_MINUTES, "completed": int(after_window.get("completed", completed_now)), "attempted": int(after_window.get("attempted", attempted_now)), "serviceRate": float(after_window.get("serviceRate", 100.0 * float(completed_now) / maxf(1.0, float(attempted_now)))), "averageMinutes": float(after_window.get("averageMinutes", minutes_now / maxf(1.0, float(completed_now)))), "beforeWindow": before_window, "afterWindow": after_window, "recordedAt": absolute_minute}
					finished.append(result)
					completed_ids[str(goal.id)] = true
					changed = true
					continue
		elif goal_type == "operations":
			var current_wait := int(sim.get("waitingByRoute", {}).get(str(goal.get("routeId", "")), 0))
			var metric := str(goal.get("focusMetric", "waiting"))
			var baseline_wait := maxi(1, int(goal.get("baselineWaiting", current_wait)))
			var baseline_crowding := maxf(0.01, float(goal.get("baselineCrowding", sim.get("peakCrowding", 0.0))))
			var metric_improved := current_wait <= int(floor(float(baseline_wait) * 0.75)) if metric == "waiting" else float(sim.get("peakCrowding", 0.0)) <= baseline_crowding * 0.75
			var improved := metric_improved and int(goal.get("stableSince", -1)) >= 0
			if metric_improved and int(goal.get("stableSince", -1)) < 0:
				goal.stableSince = absolute_minute
				goal.status = "observe"
				changed = true
			elif not metric_improved and int(goal.get("stableSince", -1)) >= 0:
				goal.stableSince = -1
				goal.status = "improve"
				changed = true
			if improved and absolute_minute - int(goal.stableSince) >= STABLE_MINUTES:
				finished.append({"id": goal.id, "type": goal_type, "title": goal.get("title", "运营改善"), "focusMetric": metric, "beforeWaiting": baseline_wait, "afterWaiting": current_wait, "beforeCrowding": baseline_crowding, "afterCrowding": float(sim.get("peakCrowding", 0.0)), "stableMinutes": STABLE_MINUTES, "recordedAt": absolute_minute})
				completed_ids[str(goal.id)] = true
				changed = true
				continue
		retained.append(goal)
	active = retained
	active_ids.clear()
	for goal in active: active_ids[str(goal.get("id", ""))] = true
	var waiting_by_route: Dictionary = sim.get("waitingByRoute", {})
	var busiest_route := ""
	var busiest_wait := 0
	for route_id in waiting_by_route:
		if int(waiting_by_route[route_id]) > busiest_wait:
			busiest_wait = int(waiting_by_route[route_id])
			busiest_route = str(route_id)
	var operations_route_id := busiest_route
	var focus_metric := "waiting"
	var focus_link_id := ""
	var issue_value := busiest_wait
	if issue_value < 10 and float(sim.get("peakCrowding", 0.0)) >= 0.85:
		operations_route_id = str(sim.get("peakCrowdedRoute", ""))
		for crowded_key in sim.get("crowdedLinks", {}):
			var parts := str(crowded_key).split("|")
			if not parts.is_empty():
				operations_route_id = str(parts[0])
				if parts.size() > 1: focus_link_id = str(parts[1])
				focus_metric = "crowding"
				issue_value = 1
				break
		if not operations_route_id.is_empty():
			focus_metric = "crowding"
			issue_value = 1
	var has_operations_goal := false
	for goal in active:
		if str(goal.get("type", "")) == "operations" and str(goal.get("routeId", "")) == operations_route_id:
			has_operations_goal = true
			break
	if issue_value >= 10 or focus_metric == "crowding":
		if not operations_route_id.is_empty() and not has_operations_goal:
			if active.size() >= MAX_ACTIVE:
				for index in range(active.size() - 1, -1, -1):
					if str(active[index].get("type", "")) == "coverage":
						active_ids.erase(str(active[index].get("id", "")))
						active.remove_at(index)
						break
			if active.size() < MAX_ACTIVE:
				var route := WorldData.find_route(state, operations_route_id)
				var operations_id := "operations|%s|%d" % [operations_route_id, absolute_minute]
				active.append({"id": operations_id, "type": "operations", "routeId": operations_route_id, "linkId": focus_link_id, "title": "改善%s%s" % [str(route.get("name", "线路")), "候车" if focus_metric == "waiting" else "区间拥挤"], "status": "improve", "focusMetric": focus_metric, "baselineWaiting": busiest_wait, "baselineCrowding": float(sim.get("peakCrowding", 0.0)), "stableSince": -1, "createdAt": absolute_minute})
				active_ids[operations_id] = true
				changed = true
	var gaps: Array[Dictionary] = []
	for flow in flows:
		if not bool(flow.get("valid", false)): gaps.append(flow)
	gaps.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("peoplePerDay", 0.0)) > float(b.get("peoplePerDay", 0.0)))
	for flow in gaps:
		if active.size() >= MAX_ACTIVE: break
		var goal_id := "coverage|%s" % str(flow.get("id", ""))
		if active_ids.has(goal_id) or completed_ids.has(goal_id): continue
		active.append({"id": goal_id, "type": "coverage", "flowId": str(flow.get("id", "")), "title": "%s → %s" % [str(flow.get("from", "起点")), str(flow.get("to", "目的地"))], "status": "build", "baselineCompleted": int(completed_by_flow.get(str(flow.get("id", "")), 0)), "baselineAttempted": int(attempted_by_flow.get(str(flow.get("id", "")), 0)), "baselineTripMinutes": float(trip_minutes_by_flow.get(str(flow.get("id", "")), 0.0)), "stableSince": -1, "createdAt": absolute_minute})
		active_ids[goal_id] = true
		changed = true
	if active.size() < MAX_ACTIVE:
		for flow in flows:
			if not bool(flow.get("valid", false)) or flow.get("routeIds", []).size() < 2: continue
			var goal_id := "transfer|%s" % str(flow.get("id", ""))
			if active_ids.has(goal_id) or completed_ids.has(goal_id): continue
			active.append({"id": goal_id, "type": "transfer", "flowId": str(flow.get("id", "")), "title": "观察%s的换乘出行" % str(flow.get("from", "街区")), "status": "build", "baselineCompleted": int(completed_by_flow.get(str(flow.get("id", "")), 0)), "baselineAttempted": int(attempted_by_flow.get(str(flow.get("id", "")), 0)), "baselineTripMinutes": float(trip_minutes_by_flow.get(str(flow.get("id", "")), 0.0)), "stableSince": -1, "createdAt": absolute_minute})
			active_ids[goal_id] = true
			changed = true
			if active.size() >= MAX_ACTIVE: break
	while finished.size() > 20: finished.pop_front()
	board["active"] = active
	board["completed"] = finished
	state["goalBoard"] = board
	return changed

static func _find_flow(flows: Array[Dictionary], flow_id: String) -> Dictionary:
	for flow in flows:
		if str(flow.get("id", "")) == flow_id: return flow
	return {}

static func _flow_window(sim: Dictionary, flow_id: String, end_minute: int, duration: int) -> Dictionary:
	var totals := {"attempted": 0, "completed": 0, "tripMinutes": 0.0}
	var samples: Array = sim.get("flowSamples", {}).get(flow_id, [])
	for sample in samples:
		var minute := int(sample.get("minute", -1))
		if minute <= end_minute - duration or minute > end_minute: continue
		totals.attempted = int(totals.attempted) + int(sample.get("attempted", 0))
		totals.completed = int(totals.completed) + int(sample.get("completed", 0))
		totals.tripMinutes = float(totals.tripMinutes) + float(sample.get("tripMinutes", 0.0))
	var completed := int(totals.completed)
	totals["serviceRate"] = 100.0 * float(completed) / maxf(1.0, float(totals.attempted))
	totals["averageMinutes"] = float(totals.tripMinutes) / maxf(1.0, float(completed))
	return totals
