class_name JourneyModel
extends RefCounted

const TRANSFER_WALK_MINUTES := 3.0
const MAX_ACCESS_METERS := 800.0
const ServiceScheduleScript = preload("res://scripts/service_schedule.gd")
static var _network_cache_key := ""
static var _network_cache: Dictionary = {}

static func invalidate_network_cache() -> void:
	_network_cache_key = ""
	_network_cache.clear()

static func build_network(state: Dictionary, ref_lat: float) -> Dictionary:
	var cache_key := _network_fingerprint(state, ref_lat)
	if cache_key == _network_cache_key and not _network_cache.is_empty():
		var cached := _network_cache.duplicate(false)
		# Search results depend on a particular origin and are mutable memoized data.
		# Keep the reusable topology, but give each caller an isolated memo table.
		cached["searchCache"] = {}
		return cached
	var adjacency: Dictionary = {}
	var station_routes: Dictionary = {}
	var paths: Dictionary = {}
	for route in state.get("routes", []):
		if not bool(route.get("open", false)): continue
		var route_id := str(route.get("id", ""))
		var path := RoutePath.for_route(route, state, ref_lat)
		paths[route_id] = path
		if not bool(path.get("valid", false)): continue
		for direction in path.get("directions", []):
			var segments: Array = direction.get("segments", [])
			for segment_index in range(segments.size()):
				var segment: Dictionary = segments[segment_index]
				var from_id := str(segment.get("fromStationId", ""))
				var to_id := str(segment.get("toStationId", ""))
				var from_key := _state_key(from_id, route_id)
				var to_key := _state_key(to_id, route_id)
				if not adjacency.has(from_key): adjacency[from_key] = []
				if not adjacency.has(to_key): adjacency[to_key] = []
				adjacency[from_key].append({"to": to_key, "type": "rail", "routeId": route_id, "directionId": str(direction.get("id", segment.get("directionId", "forward"))), "fromStopIndex": segment_index, "toStopIndex": segment_index + 1, "stationOffsetMinutes": float(segment.get("stationOffsetMinutes", 0.0)), "fromStationId": from_id, "toStationId": to_id, "linkId": str(segment.get("linkId", "")), "linkIds": segment.get("linkIds", [str(segment.get("linkId", ""))]), "linkDirections": segment.get("linkDirections", []), "distanceM": float(segment.get("distanceM", 0.0)), "minutes": float(segment.get("travelMinutes", 0.0)), "movingMinutes": float(segment.get("movingMinutes", segment.get("travelMinutes", 0.0))), "dwellMinutes": float(segment.get("dwellMinutes", 0.0))})
				if not station_routes.has(from_id): station_routes[from_id] = []
				if not station_routes.has(to_id): station_routes[to_id] = []
				if not station_routes[from_id].has(route_id): station_routes[from_id].append(route_id)
				if not station_routes[to_id].has(route_id): station_routes[to_id].append(route_id)
	for station_id in station_routes:
		var route_ids: Array = station_routes[station_id]
		for from_route in route_ids:
			var from_key := _state_key(str(station_id), str(from_route))
			for to_route in route_ids:
				if from_route == to_route: continue
				var to_key := _state_key(str(station_id), str(to_route))
				var next_route := WorldData.find_route(state, str(to_route))
				var current_seconds := int(state.get("simulation", {}).get("elapsedSeconds", int(state.get("simulation", {}).get("elapsedMinutes", 420)) * 60))
				var half_headway := maxf(0.0, float(ServiceScheduleScript.headway_minutes(next_route, current_seconds)) * 0.5)
				adjacency[from_key].append({"to": to_key, "type": "transfer", "routeId": str(to_route), "fromRouteId": str(from_route), "stationId": str(station_id), "minutes": TRANSFER_WALK_MINUTES + half_headway, "transferMinutes": TRANSFER_WALK_MINUTES, "waitMinutes": half_headway})
	var result := {"adjacency": adjacency, "stationRoutes": station_routes, "routePaths": paths, "searchCache": {}}
	_network_cache_key = cache_key
	_network_cache = result.duplicate(false)
	return result

static func _network_fingerprint(state: Dictionary, ref_lat: float) -> String:
	# Include the data that affects route geometry, access, and transfer wait time.
	# The simulation revision alone is insufficient because headway controls can
	# update a route without changing the geometry revision.
	var track_edges: Array = TrackNetwork.all_physical_edges(state)
	var fingerprint := [
		str(state.get("cityId", "")),
		"%.6f" % ref_lat,
		int(state.get("revision", 0)),
		state.get("routes", []),
		state.get("stations", []),
		state.get("trackNodes", []),
		track_edges,
		state.get("trackLinks", [])
	]
	return JSON.stringify(fingerprint)

static func find_journey(origin: Dictionary, destination: Dictionary, state: Dictionary, network: Dictionary, ref_lat: float) -> Dictionary:
	var origin_ll: Array = origin.get("latlng", [])
	var destination_ll: Array = destination.get("latlng", [])
	if origin_ll.size() < 2 or destination_ll.size() < 2:
		return {"valid": false, "reason": "需求地点坐标缺失", "steps": []}
	var station_routes: Dictionary = network.get("stationRoutes", {})
	var adjacency: Dictionary = network.get("adjacency", {})
	var starts: Array[Dictionary] = []
	var ends: Array[Dictionary] = []
	for station in state.get("stations", []):
		var station_id := str(station.get("id", ""))
		var routes: Array = station_routes.get(station_id, [])
		if routes.is_empty(): continue
		var from_distance := _distance(origin_ll, station.get("latlng", []), ref_lat)
		if from_distance <= MAX_ACCESS_METERS:
			for route_id in routes:
				var route := WorldData.find_route(state, str(route_id))
				var current_seconds := int(state.get("simulation", {}).get("elapsedSeconds", int(state.get("simulation", {}).get("elapsedMinutes", 420)) * 60))
				starts.append({"key": _state_key(station_id, str(route_id)), "stationId": station_id, "routeId": str(route_id), "distanceM": from_distance, "walkMinutes": TravelModel.walk_minutes(from_distance), "waitMinutes": maxf(0.0, float(ServiceScheduleScript.headway_minutes(route, current_seconds)) * 0.5)})
		var to_distance := _distance(destination_ll, station.get("latlng", []), ref_lat)
		if to_distance <= MAX_ACCESS_METERS:
			for route_id in routes:
				ends.append({"key": _state_key(station_id, str(route_id)), "stationId": station_id, "routeId": str(route_id), "distanceM": to_distance, "walkMinutes": TravelModel.walk_minutes(to_distance)})
	if starts.is_empty(): return {"valid": false, "reason": "800 米估算接驳范围内没有可运营车站", "steps": []}
	if ends.is_empty(): return {"valid": false, "reason": "目的地 800 米估算接驳范围内没有可运营车站", "steps": []}
	var search_cache: Dictionary = network.get("searchCache", {})
	var search_key := str(origin.get("id", JSON.stringify(origin_ll)))
	var distances: Dictionary = {}
	var previous: Dictionary = {}
	if search_cache.has(search_key):
		var cached: Dictionary = search_cache[search_key]
		distances = cached.get("distances", {})
		previous = cached.get("previous", {})
	else:
		var heap: Array = []
		for start in starts:
			var key := str(start.key)
			var initial := float(start.walkMinutes) + float(start.waitMinutes)
			if distances.has(key) and float(distances[key]) <= initial: continue
			distances[key] = initial
			previous[key] = {"from": "", "edge": {"type": "access", "stationId": str(start.stationId), "routeId": str(start.routeId), "distanceM": float(start.distanceM), "walkMinutes": float(start.walkMinutes), "waitMinutes": float(start.waitMinutes), "minutes": initial}}
			_heap_push(heap, {"key": key, "distance": initial})
		while not heap.is_empty():
			var item := _heap_pop(heap)
			var current_key := str(item.key)
			var current_distance := float(item.distance)
			if current_distance > float(distances.get(current_key, INF)) + 0.0001: continue
			for edge in adjacency.get(current_key, []):
				var next_key := str(edge.get("to", ""))
				var candidate := current_distance + float(edge.get("minutes", 0.0))
				if candidate + 0.0001 >= float(distances.get(next_key, INF)): continue
				distances[next_key] = candidate
				previous[next_key] = {"from": current_key, "edge": edge}
				_heap_push(heap, {"key": next_key, "distance": candidate})
		search_cache[search_key] = {"distances": distances, "previous": previous}
		network["searchCache"] = search_cache
	var best: Dictionary = {}
	var best_total := INF
	for finish in ends:
		var key := str(finish.key)
		if not distances.has(key): continue
		var total := float(distances[key]) + float(finish.walkMinutes)
		if total < best_total:
			best_total = total
			best = finish
	if best.is_empty(): return {"valid": false, "reason": "当前轨网没有连续可达路径", "steps": []}
	var edges: Array[Dictionary] = []
	var cursor := str(best.key)
	while not cursor.is_empty():
		var previous_record: Dictionary = previous.get(cursor, {})
		if previous_record.is_empty(): break
		edges.push_front(previous_record.edge)
		cursor = str(previous_record.from)
	var steps: Array[Dictionary] = []
	var first_route := ""
	for edge in edges:
		var type := str(edge.get("type", ""))
		if type == "access":
			steps.append({"type": "walk", "place": "起点接驳", "stationId": edge.get("stationId", ""), "distanceM": edge.get("distanceM", 0.0), "minutes": edge.get("walkMinutes", 0.0), "estimated": true})
			steps.append({"type": "wait", "stationId": edge.get("stationId", ""), "routeId": edge.get("routeId", ""), "minutes": edge.get("waitMinutes", 0.0), "estimated": true})
			first_route = str(edge.get("routeId", ""))
		elif type == "rail":
			if not first_route.is_empty():
				if steps.is_empty() or str(steps.back().get("type", "")) != "rail" or str(steps.back().get("routeId", "")) != str(edge.get("routeId", "")) or str(steps.back().get("directionId", "")) != str(edge.get("directionId", "")):
					steps.append({"type": "rail", "routeId": edge.get("routeId", ""), "directionId": edge.get("directionId", "forward"), "fromStopIndex": int(edge.get("fromStopIndex", -1)), "toStopIndex": int(edge.get("toStopIndex", -1)), "stationOffsetMinutes": float(edge.get("stationOffsetMinutes", 0.0)), "fromStationId": edge.get("fromStationId", ""), "toStationId": edge.get("toStationId", ""), "linkIds": edge.get("linkIds", [edge.get("linkId", "")]).duplicate(), "linkDirections": edge.get("linkDirections", []).duplicate(true), "segments": [_journey_segment(edge)], "distanceM": float(edge.get("distanceM", 0.0)), "minutes": float(edge.get("minutes", 0.0))})
				else:
					var last_rail: Dictionary = steps.back()
					if int(last_rail.get("toStopIndex", -1)) != int(edge.get("fromStopIndex", -2)):
						steps.append({"type": "rail", "routeId": edge.get("routeId", ""), "directionId": edge.get("directionId", "forward"), "fromStopIndex": int(edge.get("fromStopIndex", -1)), "toStopIndex": int(edge.get("toStopIndex", -1)), "stationOffsetMinutes": float(edge.get("stationOffsetMinutes", 0.0)), "fromStationId": edge.get("fromStationId", ""), "toStationId": edge.get("toStationId", ""), "linkIds": edge.get("linkIds", [edge.get("linkId", "")]).duplicate(), "linkDirections": edge.get("linkDirections", []).duplicate(true), "segments": [_journey_segment(edge)], "distanceM": float(edge.get("distanceM", 0.0)), "minutes": float(edge.get("minutes", 0.0))})
						continue
					last_rail.toStationId = edge.get("toStationId", "")
					last_rail.toStopIndex = int(edge.get("toStopIndex", -1))
					for link_id in edge.get("linkIds", [edge.get("linkId", "")]):
						if not last_rail.linkIds.has(link_id): last_rail.linkIds.append(link_id)
					last_rail.linkDirections.append_array(edge.get("linkDirections", []))
					last_rail.segments.append(_journey_segment(edge))
					last_rail.distanceM = float(last_rail.distanceM) + float(edge.get("distanceM", 0.0))
					last_rail.minutes = float(last_rail.minutes) + float(edge.get("minutes", 0.0))
		elif type == "transfer":
			steps.append({"type": "transfer", "stationId": edge.get("stationId", ""), "fromRouteId": edge.get("fromRouteId", ""), "toRouteId": edge.get("routeId", ""), "minutes": edge.get("transferMinutes", TRANSFER_WALK_MINUTES), "waitMinutes": edge.get("waitMinutes", 0.0), "estimated": true})
			steps.append({"type": "wait", "stationId": edge.get("stationId", ""), "routeId": edge.get("routeId", ""), "minutes": edge.get("waitMinutes", 0.0), "estimated": true})
	var last_station_id := str(best.stationId)
	var end_station := WorldData.find_station(state, last_station_id)
	steps.append({"type": "walk", "place": "终点接驳", "stationId": last_station_id, "distanceM": float(best.distanceM), "minutes": float(best.walkMinutes), "estimated": true})
	var origin_walk := float(steps[0].get("minutes", 0.0)) if not steps.is_empty() else 0.0
	var destination_walk := float(best.walkMinutes)
	var result_route := first_route
	var route_ids: Array[String] = []
	for step in steps:
		var step_route := str(step.get("routeId", ""))
		if step.get("type", "") == "rail" and not route_ids.has(step_route): route_ids.append(step_route)
	if route_ids.is_empty(): return {"valid": false, "reason": "步行比搭乘地铁更直接；当前出行不计作地铁路径", "steps": []}
	var total_minutes := 0.0
	for step in steps:
		total_minutes += float(step.get("minutes", 0.0))
	var origin_station_id := str(steps[0].get("stationId", "")) if not steps.is_empty() else ""
	return {"valid": true, "reason": "", "originStationId": origin_station_id, "destinationStationId": last_station_id, "routeId": result_route, "routeIds": route_ids, "steps": steps, "totalMinutes": total_minutes, "walkMinutes": origin_walk + destination_walk, "destinationStation": end_station}

static func _distance(a: Array, b: Array, ref_lat: float) -> float:
	if a.size() < 2 or b.size() < 2: return INF
	return Geo.local_m(a, ref_lat).distance_to(Geo.local_m(b, ref_lat))

static func _journey_segment(edge: Dictionary) -> Dictionary:
	return {"fromStopIndex": int(edge.get("fromStopIndex", -1)), "toStopIndex": int(edge.get("toStopIndex", -1)), "fromStationId": str(edge.get("fromStationId", "")), "toStationId": str(edge.get("toStationId", "")), "linkIds": edge.get("linkIds", []).duplicate(), "linkDirections": edge.get("linkDirections", []).duplicate(true), "distanceM": float(edge.get("distanceM", 0.0)), "minutes": float(edge.get("minutes", 0.0))}

static func _state_key(station_id: String, route_id: String) -> String:
	return station_id + "\u001f" + route_id

static func _heap_push(heap: Array, item: Dictionary) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if float(heap[parent].distance) <= float(heap[index].distance): break
		var temp: Variant = heap[parent]
		heap[parent] = heap[index]
		heap[index] = temp
		index = parent

static func _heap_pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Variant = heap.pop_back()
	if heap.is_empty(): return result
	heap[0] = tail
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if left < heap.size() and float(heap[left].distance) < float(heap[smallest].distance): smallest = left
		if right < heap.size() and float(heap[right].distance) < float(heap[smallest].distance): smallest = right
		if smallest == index: break
		var temp: Variant = heap[smallest]
		heap[smallest] = heap[index]
		heap[index] = temp
		index = smallest
	return result
