class_name RoutePath
extends RefCounted

## Canonical operational path for a route. Validation, passenger routing and train
## rendering consume the same ordered segments from this module.

static func for_route(route: Dictionary, state: Dictionary, ref_lat: float) -> Dictionary:
	var route_id := str(route.get("id", ""))
	if bool(route.get("networkBased", false)):
		return _for_network_route(route, state, ref_lat)
	var links: Array[Dictionary] = []
	for raw_link in state.get("trackLinks", []):
		if raw_link is Dictionary and raw_link.get("routeIds", []).has(route_id):
			links.append(raw_link)
	if links.is_empty():
		return {"routeId": route_id, "valid": false, "directions": [], "errors": ["没有分配给线路的轨道区间"]}
	var raw_directions: Array = route.get("directions", [])
	var directions: Array[Dictionary] = []
	var errors: Array[String] = []
	if raw_directions.is_empty():
		var order_result := _derive_order(route, links)
		if not bool(order_result.get("valid", false)):
			errors.append(str(order_result.get("error", "无法从轨道连接顺序确定停站路径")))
		else:
			var generated := _build_direction("forward", order_result.get("stationIds", []), links, route, state, ref_lat)
			if bool(generated.get("valid", false)):
				directions.append(generated)
				var reverse_ids: Array = order_result.get("stationIds", []).duplicate()
				reverse_ids.reverse()
				var reverse := _build_direction("reverse", reverse_ids, links, route, state, ref_lat)
				if bool(reverse.get("valid", false)):
					directions.append(reverse)
			else:
				errors.append_array(generated.get("errors", []))
	else:
		for index in range(raw_directions.size()):
			var raw: Variant = raw_directions[index]
			if not raw is Dictionary:
				errors.append("线路方向资料格式无效")
				continue
			var ids: Array = raw.get("stationIds", [])
			var built := _build_direction(str(raw.get("id", "direction_%d" % index)), ids, links, route, state, ref_lat)
			if bool(built.get("valid", false)):
				directions.append(built)
			else:
				errors.append_array(built.get("errors", []))
	var valid := not directions.is_empty() and errors.is_empty()
	return {"routeId": route_id, "valid": valid, "directions": directions, "errors": errors}

static func _for_network_route(route: Dictionary, state: Dictionary, ref_lat: float) -> Dictionary:
	var raw_directions: Array = route.get("directions", [])
	if raw_directions.is_empty():
		var order: Array = route.get("stationOrder", [])
		raw_directions = [{"id": "forward", "stationIds": order}]
		var reverse_order := order.duplicate(); reverse_order.reverse()
		raw_directions.append({"id": "reverse", "stationIds": reverse_order})
	var directions: Array[Dictionary] = []
	var errors: Array[String] = []
	for index in range(raw_directions.size()):
		var raw: Variant = raw_directions[index]
		if not raw is Dictionary:
			errors.append("运营线路方向资料无效")
			continue
		var locked_paths: Array = raw.get("edgePathsBySegment", [])
		if locked_paths.is_empty(): locked_paths = raw.get("edgeIdsBySegment", [])
		var direction := _build_network_direction(str(raw.get("id", "direction_%d" % index)), raw.get("stationIds", []), route, state, ref_lat, locked_paths)
		if bool(direction.get("valid", false)): directions.append(direction)
		else: errors.append_array(direction.get("errors", []))
	return {"routeId": str(route.get("id", "")), "valid": not directions.is_empty() and errors.is_empty(), "directions": directions, "errors": errors}

static func _build_network_direction(direction_id: String, station_ids: Array, route: Dictionary, state: Dictionary, ref_lat: float, edge_ids_by_segment: Array = []) -> Dictionary:
	var errors: Array[String] = []
	if station_ids.size() < 2:
		return {"valid": false, "errors": ["运营线路至少需要选择两座车站"]}
	var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
	if profile.is_empty(): profile = {"maxSpeedKmh": 80.0, "accelerationMps2": 1.0, "decelerationMps2": 1.1}
	var segments: Array[Dictionary] = []
	var total_distance := 0.0
	var total_minutes := 0.0
	for index in range(station_ids.size() - 1):
		var from_id := str(station_ids[index])
		var to_id := str(station_ids[index + 1])
		if not edge_ids_by_segment.is_empty() and index >= edge_ids_by_segment.size():
			errors.append("%s → %s：线路区间尚未确认走向" % [_station_name(state, from_id), _station_name(state, to_id)])
			continue
		var locked_path: Array = edge_ids_by_segment[index] if index < edge_ids_by_segment.size() and edge_ids_by_segment[index] is Array else []
		if not edge_ids_by_segment.is_empty() and locked_path.is_empty():
			errors.append("%s → %s：该区间已断开，请修复此区间后再开通" % [_station_name(state, from_id), _station_name(state, to_id)])
			continue
		var locked_edge_ids: Array = []
		var locked_directions: Array = []
		if not locked_path.is_empty():
			if locked_path[0] is Dictionary:
				for entry in locked_path:
					locked_edge_ids.append(str(entry.get("id", "")))
					locked_directions.append({"id": str(entry.get("id", "")), "forward": bool(entry.get("forward", true))})
			else:
				locked_edge_ids = locked_path
		var path := TrackNetwork.ordered_station_path(from_id, to_id, locked_directions, state, ref_lat) if not locked_directions.is_empty() else TrackNetwork.shortest_station_path(from_id, to_id, state, ref_lat, locked_edge_ids)
		if not bool(path.get("valid", false)):
			errors.append("%s → %s：%s" % [_station_name(state, from_id), _station_name(state, to_id), path.get("error", "没有连续轨道")])
			continue
		if not locked_directions.is_empty() and not _same_ordered_path(locked_directions, _link_directions(path)):
			errors.append("%s → %s：已保存的轨道顺序或方向发生变化，请重新确认线路走向" % [_station_name(state, from_id), _station_name(state, to_id)])
			continue
		var distance := float(path.get("distanceM", 0.0))
		var limit := float(route.get("speedLimitKmh", -1.0))
		for edge_record in path.get("edges", []):
			var edge: Dictionary = edge_record.get("edge", {})
			var edge_limit := float(edge.get("speedLimitKmh", -1.0))
			if edge_limit > 0.0: limit = edge_limit if limit <= 0.0 else minf(limit, edge_limit)
		var points: Array = path.get("points", [])
		var minimum_radius := _minimum_curve_radius_m(points, ref_lat)
		var curve_limit := TravelModel.curve_speed_limit_kmh(minimum_radius)
		if curve_limit > 0.0: limit = curve_limit if limit <= 0.0 else minf(limit, curve_limit)
		var moving_minutes := TravelModel.rail_segment_minutes(distance, profile, 0.0, limit)
		var dwell := 0.5 if index < station_ids.size() - 2 or str(station_ids.back()) == from_id else 0.0
		var link_ids: Array = path.get("linkIds", [])
		var capacity_ids: Array = link_ids.duplicate()
		if capacity_ids.is_empty(): capacity_ids.append("station:%s" % from_id)
		segments.append({"linkId": str(capacity_ids[0]), "linkIds": capacity_ids, "linkDirections": _link_directions(path), "points": points, "minimumCurveRadiusM": minimum_radius, "directionId": direction_id, "stationOffsetMinutes": total_minutes, "fromStationId": from_id, "toStationId": to_id, "distanceM": distance, "travelMinutes": moving_minutes + dwell, "movingMinutes": moving_minutes, "dwellMinutes": dwell, "speedLimitKmh": limit, "curveSpeedLimitKmh": curve_limit})
		total_distance += distance
		total_minutes += moving_minutes + dwell
	if not errors.is_empty(): return {"valid": false, "errors": errors}
	return {"id": direction_id, "stationIds": station_ids.duplicate(), "segments": segments, "distanceM": total_distance, "travelMinutes": total_minutes, "valid": true}

static func _link_directions(path: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for connection in path.get("edges", []):
		var edge: Dictionary = connection.get("edge", {})
		if bool(edge.get("platform", false)): continue
		result.append({"id": str(edge.get("id", "")), "forward": bool(connection.get("forward", true))})
	return result

static func _same_ordered_path(expected: Array, actual: Array) -> bool:
	if expected.size() != actual.size(): return false
	for index in range(expected.size()):
		if str(expected[index].get("id", "")) != str(actual[index].get("id", "")) or bool(expected[index].get("forward", true)) != bool(actual[index].get("forward", true)): return false
	return true

static func _station_name(state: Dictionary, station_id: String) -> String:
	var station := WorldData.find_station(state, station_id)
	return str(station.get("name", "车站"))

static func _minimum_curve_radius_m(points: Array, ref_lat: float) -> float:
	var minimum := INF
	for index in range(1, points.size() - 1):
		var a := Geo.local_m(points[index - 1], ref_lat)
		var b := Geo.local_m(points[index], ref_lat)
		var c := Geo.local_m(points[index + 1], ref_lat)
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		var ac := a.distance_to(c)
		var cross := absf((b - a).cross(c - a))
		if minf(ab, minf(bc, ac)) < 0.5 or cross < 0.01: continue
		minimum = minf(minimum, ab * bc * ac / (2.0 * cross))
	return minimum

static func _derive_order(route: Dictionary, links: Array[Dictionary]) -> Dictionary:
	var adjacency: Dictionary = {}
	var edge_keys: Dictionary = {}
	for link in links:
		var a := str(link.get("a", {}).get("stationId", ""))
		var b := str(link.get("b", {}).get("stationId", ""))
		if a.is_empty() or b.is_empty() or a == b:
			return {"valid": false, "error": "轨道端点无效或区间长度为零"}
		if not adjacency.has(a): adjacency[a] = []
		if not adjacency.has(b): adjacency[b] = []
		adjacency[a].append({"to": b, "link": link})
		adjacency[b].append({"to": a, "link": link})
		edge_keys[_edge_key(a, b)] = true
	if adjacency.size() < 2:
		return {"valid": false, "error": "至少需要两座已连接车站"}
	for station_id in adjacency:
		if adjacency[station_id].size() > 2:
			return {"valid": false, "error": "线路存在三岔或多条走向；请先明确停站顺序"}
	var endpoints: Array[String] = []
	for station_id in adjacency:
		if adjacency[station_id].size() == 1: endpoints.append(str(station_id))
	var start_id := ""
	if not endpoints.is_empty():
		start_id = endpoints[0]
	else:
		var order: Array = route.get("stationOrder", [])
		start_id = str(order[0]) if not order.is_empty() and adjacency.has(str(order[0])) else str(adjacency.keys()[0])
	var station_ids: Array[String] = [start_id]
	var used_edges: Dictionary = {}
	var previous := ""
	var current := start_id
	while true:
		var next_record: Dictionary = {}
		for record in adjacency.get(current, []):
			var next_id := str(record.get("to", ""))
			var key := _edge_key(current, next_id)
			if next_id == previous or used_edges.has(key): continue
			next_record = record
			break
		if next_record.is_empty(): break
		var next := str(next_record.get("to", ""))
		used_edges[_edge_key(current, next)] = true
		previous = current
		current = next
		station_ids.append(current)
		if current == start_id: break
	if used_edges.size() != edge_keys.size() or (not endpoints.is_empty() and station_ids.size() < 2):
		return {"valid": false, "error": "轨道没有形成一条连续且无分支的停站路径"}
	return {"valid": true, "id": "track_order", "stationIds": station_ids}

static func _build_direction(direction_id: String, station_ids: Array, links: Array[Dictionary], route: Dictionary, state: Dictionary, ref_lat: float) -> Dictionary:
	var errors: Array[String] = []
	if station_ids.size() < 2:
		return {"valid": false, "errors": ["停站方向至少需要两座车站"]}
	var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
	if profile.is_empty(): profile = {"maxSpeedKmh": 80.0, "accelerationMps2": 1.0, "decelerationMps2": 1.1}
	var segments: Array[Dictionary] = []
	var total_distance := 0.0
	var total_minutes := 0.0
	for index in range(station_ids.size() - 1):
		var from_id := str(station_ids[index])
		var to_id := str(station_ids[index + 1])
		if WorldData.find_station(state, from_id).is_empty() or WorldData.find_station(state, to_id).is_empty():
			errors.append("停站序列引用了不存在的车站")
			continue
		var candidates: Array[Dictionary] = []
		for link in links:
			var a := str(link.get("a", {}).get("stationId", ""))
			var b := str(link.get("b", {}).get("stationId", ""))
			if (a == from_id and b == to_id) or (a == to_id and b == from_id): candidates.append(link)
		if candidates.is_empty():
			errors.append("%s 与 %s 之间没有连续轨道" % [from_id, to_id])
			continue
		var selected := candidates[0]
		var distance := WorldData.track_length_m(selected, state, ref_lat)
		if distance <= 0.1:
			errors.append("%s 与 %s 之间存在零长度区间" % [from_id, to_id])
			continue
		var limit := float(selected.get("speedLimitKmh", -1.0))
		var points: Array = []
		if bool(selected.get("schematic", false)):
			points = [WorldData.find_station(state, from_id).get("latlng", [0, 0]), WorldData.find_station(state, to_id).get("latlng", [0, 0])]
		else:
			points = WorldData.track_points(selected, state, ref_lat, 24)
			if str(selected.get("a", {}).get("stationId", "")) != from_id: points.reverse()
		var minimum_radius := _minimum_curve_radius_m(points, ref_lat)
		var curve_limit := TravelModel.curve_speed_limit_kmh(minimum_radius)
		if curve_limit > 0.0: limit = curve_limit if limit <= 0.0 else minf(limit, curve_limit)
		var dwell := 0.5 if index < station_ids.size() - 2 or str(station_ids.back()) == from_id else 0.0
		var moving_minutes := TravelModel.rail_segment_minutes(distance, profile, 0.0, limit)
		var minutes := moving_minutes + dwell
		segments.append({"linkId": str(selected.get("id", "")), "link": selected, "points": points, "minimumCurveRadiusM": minimum_radius, "curveSpeedLimitKmh": curve_limit, "directionId": direction_id, "stationOffsetMinutes": total_minutes, "fromStationId": from_id, "toStationId": to_id, "distanceM": distance, "travelMinutes": minutes, "movingMinutes": moving_minutes, "dwellMinutes": dwell, "speedLimitKmh": limit})
		total_distance += distance
		total_minutes += minutes
	if not errors.is_empty(): return {"valid": false, "errors": errors}
	return {"id": direction_id, "stationIds": station_ids.duplicate(), "segments": segments, "distanceM": total_distance, "travelMinutes": total_minutes, "valid": true}

static func normalize_station_order(route: Dictionary, state: Dictionary) -> void:
	if not route.get("directions", []).is_empty(): return
	var links: Array[Dictionary] = []
	for link in state.get("trackLinks", []):
		if link.get("routeIds", []).has(str(route.get("id", ""))): links.append(link)
	var result := _derive_order(route, links)
	if bool(result.get("valid", false)):
		route["stationOrder"] = result.get("stationIds", [])

static func _edge_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a
