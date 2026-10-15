extends SceneTree

const Journey = preload("res://scripts/journey_model.gd")
const Simulation = preload("res://scripts/simulation_engine.gd")
const Goals = preload("res://scripts/neighborhood_goals.gd")

const DESTINATION_WEIGHTS := {"employment": 0.17, "education": 0.055, "health": 0.04, "commerce": 0.035, "hub": 0.04, "culture": 0.025}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var state := WorldData.new_world("shanghai", "expand")
	var city := WorldData.city("shanghai")
	var ref_lat := float(city.get("center", [31.23, 121.47])[0])
	var network := Journey.build_network(state, ref_lat)
	var flows := _build_flows(city.get("demand", []), state, network, ref_lat)
	var valid_flows := 0
	var shortest_journey := INF
	var longest_journey := 0.0
	for flow in flows:
		if not bool(flow.get("valid", false)): continue
		valid_flows += 1
		var minutes := float(flow.get("journey", {}).get("totalMinutes", INF))
		shortest_journey = minf(shortest_journey, minutes)
		longest_journey = maxf(longest_journey, minutes)
	var elapsed := Time.get_ticks_usec()
	for _minute in range(60):
		var next_minute := posmod(int(state.simulation.get("elapsedMinutes", 420)) + 1, 1440)
		var hour := next_minute / 60
		var peak := 0.55
		if hour >= 7 and hour < 10: peak = 2.1
		elif hour >= 16 and hour < 19: peak = 1.8
		elif hour >= 11 and hour < 14: peak = 1.1
		var minute_flows: Array[Dictionary] = []
		for flow in flows:
			var item := flow.duplicate(false)
			item["peakMultiplier"] = _peak_multiplier(flow, hour, peak)
			minute_flows.append(item)
		Simulation.step_one_minute(state, minute_flows, 1.0)
		Goals.update(state, flows, int(state.simulation.elapsedMinutes))
	var elapsed_ms := float(Time.get_ticks_usec() - elapsed) / 1000.0
	var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var peak_memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576.0
	var station_count: int = state.get("stations", []).size()
	var route_count: int = state.get("routes", []).size()
	var link_count: int = state.get("trackLinks", []).size()
	var demand_count: int = city.get("demand", []).size()
	var simulated := int(state.simulation.get("elapsedMinutes", 0)) - 420
	if station_count < 400 or route_count < 15 or simulated != 60 or int(state.simulation.get("completed", 0)) <= 0:
		push_error("Expected the largest city network and 60 simulated minutes; got %d stations, %d routes, %d minutes." % [station_count, route_count, simulated])
		quit(1)
		return
	print("PASS: Shanghai max-network one-hour simulation; stations=%d routes=%d links=%d demand=%d flows=%d valid_flows=%d journey_minutes=%.1f–%.1f simulated_minutes=%d wall_ms=%.1f ms_per_game_minute=%.2f memory_mb=%.1f peak_memory_mb=%.1f completed=%d waiting=%d in_transit=%d abandoned=%d" % [station_count, route_count, link_count, demand_count, flows.size(), valid_flows, shortest_journey, longest_journey, simulated, elapsed_ms, elapsed_ms / 60.0, memory_mb, peak_memory_mb, int(state.simulation.completed), int(state.simulation.waiting), int(state.simulation.inTransit), int(state.simulation.abandoned)])
	quit(0)

func _build_flows(demands: Array, state: Dictionary, network: Dictionary, ref_lat: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for origin in demands:
		if str(origin.get("type", "")) != "housing": continue
		for destination in demands:
			var target_type := str(destination.get("type", ""))
			if not DESTINATION_WEIGHTS.has(target_type) or str(origin.get("id", "")) == str(destination.get("id", "")): continue
			if _distance_m(origin.get("latlng", []), destination.get("latlng", []), ref_lat) > 40000.0: continue
			var daily := minf(float(origin.get("gameDemand", {}).get("base", 0.0)), float(destination.get("gameDemand", {}).get("base", 0.0))) * float(DESTINATION_WEIGHTS[target_type])
			_append_pair(result, origin, destination, daily, state, network, ref_lat)
			_append_pair(result, destination, origin, daily * 0.85, state, network, ref_lat)
	return result

func _append_pair(result: Array[Dictionary], origin: Dictionary, destination: Dictionary, daily: float, state: Dictionary, network: Dictionary, ref_lat: float) -> void:
	var journey := Journey.find_journey(origin, destination, state, network, ref_lat)
	result.append({"id": "%s>%s" % [origin.get("id", ""), destination.get("id", "")], "fromType": str(origin.get("type", "")), "toType": str(destination.get("type", "")), "peoplePerDay": daily, "valid": bool(journey.get("valid", false)), "journey": journey})

func _peak_multiplier(flow: Dictionary, hour: int, fallback: float) -> float:
	var from_type := str(flow.get("fromType", ""))
	var to_type := str(flow.get("toType", ""))
	if from_type == "housing" and to_type in ["employment", "education"]:
		if hour >= 7 and hour < 10: return 2.1
		if hour >= 16 and hour < 19: return 0.55
		return 0.65
	if from_type in ["employment", "education"] and to_type == "housing":
		if hour >= 16 and hour < 19: return 2.0
		if hour >= 7 and hour < 10: return 0.45
		return 0.7
	if to_type == "commerce" or from_type == "commerce":
		if hour >= 11 and hour < 14: return 1.5
		if hour >= 17 and hour < 21: return 1.65
		return 0.8
	if to_type == "hub" or from_type == "hub":
		if hour >= 7 and hour < 10 or hour >= 16 and hour < 19: return 1.6
		return 0.75
	if to_type == "health" or from_type == "health": return 0.75
	return fallback

func _distance_m(a: Array, b: Array, ref_lat: float) -> float:
	if a.size() < 2 or b.size() < 2: return INF
	return Geo.local_m(a, ref_lat).distance_to(Geo.local_m(b, ref_lat))
