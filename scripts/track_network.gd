class_name TrackNetwork
extends RefCounted

## Physical track geometry shared by construction, route previews and train rendering.

static func ensure_station_nodes(state: Dictionary) -> void:
	if not state.has("trackNodes") or not state.trackNodes is Array: state["trackNodes"] = []
	if not state.has("trackEdges") or not state.trackEdges is Array: state["trackEdges"] = []
	for station in state.get("stations", []):
		var refs: Dictionary = station.get("endpointNodes", {})
		for side in ["start", "end"]:
			var key := "A" if side == "start" else "B"
			var node_id := str(refs.get(key, "node_%s_%s" % [station.get("id", "station"), key.to_lower()]))
			var node := find_node(state, node_id)
			if node.is_empty():
				state.trackNodes.append({"id": node_id, "latlng": WorldData.station_endpoint(station, side), "stationId": str(station.get("id", "")), "side": side, "depthM": float(station.get("depthM", -15.0))})
			else:
				node["latlng"] = WorldData.station_endpoint(station, side)
				node["depthM"] = float(station.get("depthM", -15.0))
			refs[key] = node_id
		station["endpointNodes"] = refs

static func find_node(state: Dictionary, node_id: String) -> Dictionary:
	for node in state.get("trackNodes", []):
		if str(node.get("id", "")) == node_id: return node
	return {}

static func station_node_id(station: Dictionary, side: String) -> String:
	var key := "A" if side in ["start", "A"] else "B"
	return str(station.get("endpointNodes", {}).get(key, ""))

static func create_node(state: Dictionary, latlng: Array, depth_m: float = -15.0) -> Dictionary:
	var node := {"id": "tn_%d" % Time.get_ticks_usec(), "latlng": [float(latlng[0]), float(latlng[1])], "depthM": depth_m, "stationId": "", "side": ""}
	state.trackNodes.append(node)
	return node

static func edge_points(edge: Dictionary, state: Dictionary, ref_lat: float, segments: int = 24) -> Array[Array]:
	if edge.has("a") and edge.has("b") and not edge.has("aNodeId"):
		return WorldData.track_points(edge, state, ref_lat, segments)
	var node_a := find_node(state, str(edge.get("aNodeId", "")))
	var node_b := find_node(state, str(edge.get("bNodeId", "")))
	if node_a.is_empty() or node_b.is_empty(): return []
	if str(edge.get("geometry",""))=="reference_polyline":
		var copied:Array[Array]=[]
		for point in edge.get("referencePoints",[]):copied.append(point.duplicate())
		if copied.size()>=2:
			copied[0]=node_a.latlng.duplicate();copied[-1]=node_b.latlng.duplicate()
		return copied
	var p0 := Geo.local_m(node_a.get("latlng", [0, 0]), ref_lat)
	var p3 := Geo.local_m(node_b.get("latlng", [0, 0]), ref_lat)
	var result: Array[Array] = []
	if str(edge.get("geometry", "straight")) == "straight":
		result.append(Geo.from_local(p0, ref_lat)); result.append(Geo.from_local(p3, ref_lat))
		return result
	var delta := p3 - p0
	var ca: Array = edge.get("controlA", [delta.x / 3.0, delta.y / 3.0])
	var cb: Array = edge.get("controlB", [-delta.x / 3.0, -delta.y / 3.0])
	var p1 := p0 + Vector2(float(ca[0]), float(ca[1]))
	var p2 := p3 + Vector2(float(cb[0]), float(cb[1]))
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		var u := 1.0 - t
		var point := p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t
		result.append(Geo.from_local(point, ref_lat))
	return result

static func edge_length_m(edge: Dictionary, state: Dictionary, ref_lat: float) -> float:
	var points := edge_points(edge, state, ref_lat, 32)
	var total := 0.0
	for index in range(points.size() - 1): total += Geo.local_m(points[index], ref_lat).distance_to(Geo.local_m(points[index + 1], ref_lat))
	return total

static func all_physical_edges(state: Dictionary) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for edge in state.get("trackLinks", []):
		if edge is Dictionary: edges.append(edge)
	for edge in state.get("trackEdges", []):
		if edge is Dictionary: edges.append(edge)
	return edges

static func shortest_station_path(from_station_id: String, to_station_id: String, state: Dictionary, ref_lat: float, allowed_edge_ids: Array = [], banned_edge_ids: Array = []) -> Dictionary:
	if from_station_id == to_station_id: return {"valid": false, "error": "线路需要停靠在两座不同的车站", "edges": []}
	var from_station := WorldData.find_station(state, from_station_id)
	var to_station := WorldData.find_station(state, to_station_id)
	if from_station.is_empty() or to_station.is_empty(): return {"valid": false, "error": "停站车站不存在", "edges": []}
	ensure_station_nodes(state)
	var adjacency: Dictionary = {}
	var graph_edges := all_physical_edges(state)
	for station in state.get("stations", []):
		var a_id := station_node_id(station, "start")
		var b_id := station_node_id(station, "end")
		var platform := {"id": "platform:%s" % station.get("id", ""), "aNodeId": a_id, "bNodeId": b_id, "geometry": "straight", "pointsOverride": [WorldData.station_endpoint(station, "start"), WorldData.station_endpoint(station, "end")], "distanceM": float(station.get("lengthM", 0.0)), "platform": true}
		graph_edges.append(platform)
	for edge in graph_edges:
		# A saved operating route may lock this station pair to a chosen branch.
		# Platform edges join the two station ends for continuous historical paths.
		if not allowed_edge_ids.is_empty() and not bool(edge.get("platform", false)) and not allowed_edge_ids.has(str(edge.get("id", ""))): continue
		if banned_edge_ids.has(str(edge.get("id", ""))): continue
		var ends := _edge_node_ids(edge, state)
		if ends.size() != 2 or ends[0].is_empty() or ends[1].is_empty(): continue
		var length := edge_length_m(edge, state, ref_lat)
		if edge.has("distanceM"): length = float(edge.distanceM)
		if length <= 0.1: continue
		if not adjacency.has(ends[0]): adjacency[ends[0]] = []
		if not adjacency.has(ends[1]): adjacency[ends[1]] = []
		adjacency[ends[0]].append({"to": ends[1], "edge": edge, "lengthM": length, "forward": true})
		adjacency[ends[1]].append({"to": ends[0], "edge": edge, "lengthM": length, "forward": false})
	var start_ids := [station_node_id(from_station, "start"), station_node_id(from_station, "end")]
	var goal_ids := [station_node_id(to_station, "start"), station_node_id(to_station, "end")]
	var distances: Dictionary = {}
	var previous: Dictionary = {}
	var queue: Array[Dictionary] = []
	for start_id in start_ids:
		var cost := float(from_station.get("lengthM", 0.0)) * 0.5
		distances[start_id] = cost
		queue.append({"id": start_id, "cost": cost})
	var visited: Dictionary = {}
	var target_id := ""
	while not queue.is_empty():
		queue.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.cost) > float(b.cost))
		var item: Dictionary = queue.pop_back()
		var current_id := str(item.id)
		if visited.has(current_id): continue
		visited[current_id] = true
		if goal_ids.has(current_id): target_id = current_id; break
		for connection in adjacency.get(current_id, []):
			var next_id := str(connection.to)
			var candidate := float(item.cost) + float(connection.lengthM)
			if candidate >= float(distances.get(next_id, INF)): continue
			distances[next_id] = candidate
			previous[next_id] = {"from": current_id, "connection": connection}
			queue.append({"id": next_id, "cost": candidate})
	if target_id.is_empty(): return {"valid": false, "error": "两座车站之间没有连续接轨的物理轨道", "edges": []}
	var path: Array[Dictionary] = []
	var cursor := target_id
	while previous.has(cursor):
		var record: Dictionary = previous[cursor]
		var connection: Dictionary = record.connection.duplicate(true)
		connection["fromNodeId"] = str(record.from)
		connection["toNodeId"] = cursor
		path.push_front(connection)
		cursor = str(record.from)
	var points: Array[Array] = []
	var start_node := find_node(state, cursor)
	if not start_node.is_empty():
		points.append(from_station.get("latlng", [0, 0]).duplicate())
		points.append(start_node.get("latlng", [0, 0]).duplicate())
	for connection in path:
		var edge: Dictionary = connection.edge
		var piece := edge_points(edge, state, ref_lat, 24)
		if not bool(connection.forward): piece.reverse()
		for point in piece:
			if points.is_empty() or Geo.local_m(points[-1], ref_lat).distance_to(Geo.local_m(point, ref_lat)) > 0.1: points.append(point)
	var end_node := find_node(state, target_id)
	if not end_node.is_empty():
		if points.is_empty() or Geo.local_m(points[-1], ref_lat).distance_to(Geo.local_m(end_node.get("latlng", [0, 0]), ref_lat)) > 0.1: points.append(end_node.get("latlng", [0, 0]).duplicate())
		points.append(to_station.get("latlng", [0, 0]).duplicate())
	if points.size() < 2: return {"valid": false, "error": "路径几何无效", "edges": []}
	var link_ids: Array[String] = []
	var distance_m := 0.0
	for connection in path:
		var edge_id := str(connection.edge.get("id", ""))
		if not bool(connection.edge.get("platform", false)) and not link_ids.has(edge_id): link_ids.append(edge_id)
		distance_m += float(connection.lengthM)
	distance_m += float(from_station.get("lengthM", 0.0)) * 0.5 + float(to_station.get("lengthM", 0.0)) * 0.5
	return {"valid": true, "points": points, "distanceM": distance_m, "linkIds": link_ids, "edges": path, "fromNodeId": str(start_ids[0]), "toNodeId": target_id}

static func station_path_options(from_station_id: String, to_station_id: String, state: Dictionary, ref_lat: float, limit: int = 4) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var first := shortest_station_path(from_station_id, to_station_id, state, ref_lat)
	if not bool(first.get("valid", false)): return options
	options.append(first)
	var seen := {"|".join(first.get("linkIds", [])): true}
	for edge_id in first.get("linkIds", []):
		if options.size() >= maxi(1, limit): break
		var alternative := shortest_station_path(from_station_id, to_station_id, state, ref_lat, [], [str(edge_id)])
		if not bool(alternative.get("valid", false)): continue
		var signature := "|".join(alternative.get("linkIds", []))
		if seen.has(signature): continue
		seen[signature] = true
		options.append(alternative)
	return options

static func ordered_station_path(from_station_id: String, to_station_id: String, edge_path: Array, state: Dictionary, ref_lat: float) -> Dictionary:
	if from_station_id == to_station_id: return {"valid": false, "error": "线路需要停靠在两座不同的车站", "edges": []}
	var from_station := WorldData.find_station(state, from_station_id)
	var to_station := WorldData.find_station(state, to_station_id)
	if from_station.is_empty() or to_station.is_empty(): return {"valid": false, "error": "停站车站不存在", "edges": []}
	if edge_path.is_empty(): return {"valid": false, "error": "已确认线路缺少有序轨道区间", "edges": []}
	ensure_station_nodes(state)
	var by_id: Dictionary = {}
	for edge in all_physical_edges(state): by_id[str(edge.get("id", ""))] = edge
	var from_nodes := [station_node_id(from_station, "start"), station_node_id(from_station, "end")]
	var to_nodes := [station_node_id(to_station, "start"), station_node_id(to_station, "end")]
	var oriented: Array[Dictionary] = []
	var first_node := ""
	var cursor := ""
	var total_distance := 0.0
	var link_ids: Array[String] = []
	for record in edge_path:
		if not record is Dictionary: return {"valid": false, "error": "已确认线路区间缺少方向信息", "edges": []}
		var edge_id := str(record.get("id", ""))
		var edge: Dictionary = by_id.get(edge_id, {})
		if edge.is_empty(): return {"valid": false, "error": "已确认线路引用了不存在的轨道 %s" % edge_id, "edges": []}
		var endpoints := _edge_node_ids(edge, state)
		if endpoints.size() != 2: return {"valid": false, "error": "轨道 %s 的接点无效" % edge_id, "edges": []}
		var forward := bool(record.get("forward", true))
		var start_node := str(endpoints[0] if forward else endpoints[1])
		var end_node := str(endpoints[1] if forward else endpoints[0])
		if oriented.is_empty():
			if not from_nodes.has(start_node): return {"valid": false, "error": "已确认线路的起始轨道未接入车站 %s" % str(from_station.get("name", from_station_id)), "edges": []}
			first_node = start_node
		else:
			if start_node != cursor: return {"valid": false, "error": "已确认线路在轨道 %s 处不连续" % edge_id, "edges": []}
		var length := float(edge.get("distanceM", edge_length_m(edge, state, ref_lat)))
		if length <= 0.1: return {"valid": false, "error": "轨道 %s 长度为零" % edge_id, "edges": []}
		oriented.append({"edge": edge, "forward": forward, "fromNodeId": start_node, "toNodeId": end_node, "lengthM": length})
		total_distance += length
		if not bool(edge.get("platform", false)) and not link_ids.has(edge_id): link_ids.append(edge_id)
		cursor = end_node
	if not to_nodes.has(cursor): return {"valid": false, "error": "已确认线路的末端轨道未接入车站 %s" % str(to_station.get("name", to_station_id)), "edges": []}
	var start_node_data := find_node(state, first_node)
	var end_node_data := find_node(state, cursor)
	if start_node_data.is_empty() or end_node_data.is_empty(): return {"valid": false, "error": "已确认线路引用了不存在的接点", "edges": []}
	var points: Array[Array] = [from_station.get("latlng", [0.0, 0.0]).duplicate(), start_node_data.get("latlng", [0.0, 0.0]).duplicate()]
	for connection in oriented:
		var piece := edge_points(connection.edge, state, ref_lat, 24)
		if not bool(connection.forward): piece.reverse()
		for point in piece:
			if points.is_empty() or Geo.local_m(points[-1], ref_lat).distance_to(Geo.local_m(point, ref_lat)) > 0.1: points.append(point)
	points.append(to_station.get("latlng", [0.0, 0.0]).duplicate())
	total_distance += float(from_station.get("lengthM", 0.0)) * 0.5 + float(to_station.get("lengthM", 0.0)) * 0.5
	return {"valid": true, "points": points, "distanceM": total_distance, "linkIds": link_ids, "edges": oriented, "fromNodeId": first_node, "toNodeId": cursor}

static func _edge_node_ids(edge: Dictionary, state: Dictionary) -> Array[String]:
	if edge.has("aNodeId") and edge.has("bNodeId"):
		return [str(edge.get("aNodeId", "")), str(edge.get("bNodeId", ""))]
	var a: Dictionary = edge.get("a", {})
	var b: Dictionary = edge.get("b", {})
	var station_a := WorldData.find_station(state, str(a.get("stationId", "")))
	var station_b := WorldData.find_station(state, str(b.get("stationId", "")))
	return [station_node_id(station_a, str(a.get("side", "start"))), station_node_id(station_b, str(b.get("side", "end")))]
