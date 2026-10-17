class_name StoryConstruction
extends RefCounted

var world: Dictionary = {}
var active_city_id := "shanghai"
var map_view: MapView

func track_preview(start: Dictionary, finish: Dictionary, control: Array = []) -> Dictionary:
	var lat := float(WorldData.city(active_city_id).get("center",[31.23])[0])
	var p0 := Geo.local_m(start.latlng,lat); var p3 := Geo.local_m(finish.latlng,lat)
	if p0.distance_to(p3)<0.1:return {"issue":"起点与终点重合。"}
	var chord:=p3-p0
	var length:=maxf(1.0,chord.length()*0.34)
	var ca:=_track_endpoint_tangent(start,true,chord,lat)*length
	var cb:=-_track_endpoint_tangent(finish,false,chord,lat)*length
	if not control.is_empty():
		var offset:=Geo.local_m(control,lat)-(p0+p3)*0.5
		if str(start.get("stationId","")).is_empty():ca=chord/3.0+offset
		if str(finish.get("stationId","")).is_empty():cb=-chord/3.0+offset
	var test:=world.duplicate(false)
	test["trackNodes"]=world.get("trackNodes",[]).duplicate()
	var a_id:=str(start.get("nodeId",""));var b_id:=str(finish.get("nodeId",""))
	if a_id.is_empty():a_id="preview_a";test.trackNodes.append({"id":a_id,"latlng":start.latlng,"depthM":start.get("depthM",-15)})
	if b_id.is_empty():b_id="preview_b";test.trackNodes.append({"id":b_id,"latlng":finish.latlng,"depthM":finish.get("depthM",-15)})
	var edge:={"id":"preview","aNodeId":a_id,"bNodeId":b_id,"geometry":"bezier","controlA":[ca.x,ca.y],"controlB":[cb.x,cb.y],"routeIds":[],"depthM":start.get("depthM",-15)}
	var points:=TrackNetwork.edge_points(edge,test,lat,32)
	var distance:=TrackNetwork.edge_length_m(edge,test,lat)
	var issue:=""
	if absf(float(start.get("depthM",-15))-float(finish.get("depthM",-15)))/maxf(0.1,distance)>0.035:issue="坡度超过35‰游戏预设；请调整深度或延长区间。"
	for i in range(points.size()-1):
		for j in range(i+2,points.size()-1):
			var intersection:=_segment_intersection_parameters(Geo.local_m(points[i],lat),Geo.local_m(points[i+1],lat),Geo.local_m(points[j],lat),Geo.local_m(points[j+1],lat))
			if intersection.x>=0:issue="轨道曲线自身交叉，请调整方向或分段连接。"
	var ignored:Array[String]=[]
	for endpoint in [start,finish]:
		if not str(endpoint.get("splitEdgeId","")).is_empty():ignored.append(str(endpoint.splitEdgeId))
	if issue.is_empty():issue=_track_crossing_conflict(points,edge,float(start.get("depthM",-15)),float(finish.get("depthM",-15)),lat,ignored,test)
	return {"edge":edge,"points":points,"lengthM":distance,"issue":issue,"revision":int(world.get("revision",0))}

func materialize(state: Dictionary, ref: Dictionary) -> String:
	if not str(ref.get("nodeId","")).is_empty():return str(ref.nodeId)
	if not str(ref.get("splitEdgeId","")).is_empty():return _split_track_edge(state,str(ref.splitEdgeId),float(ref.get("splitT",0.5)),float(WorldData.city(active_city_id).center[0]))
	return str(TrackNetwork.create_node(state,ref.latlng,float(ref.get("depthM",-15))).id)

func _edge_distance_fraction(edge: Dictionary, latlng: Array, ref_lat: float) -> float:
	var points := TrackNetwork.edge_points(edge, world, ref_lat, 128)
	if points.size() < 2: return 0.5
	var target := Geo.local_m(latlng, ref_lat)
	var lengths: Array[float] = []
	var total := 0.0
	for index in range(points.size() - 1):
		var length := Geo.local_m(points[index], ref_lat).distance_to(Geo.local_m(points[index + 1], ref_lat))
		lengths.append(length); total += length
	var best_distance := INF
	var best_along := total * 0.5
	var walked := 0.0
	for index in range(points.size() - 1):
		var a := Geo.local_m(points[index], ref_lat)
		var b := Geo.local_m(points[index + 1], ref_lat)
		var segment := b - a
		var fraction := clampf((target - a).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var distance_to_path := target.distance_to(a.lerp(b, fraction))
		if distance_to_path < best_distance:
			best_distance = distance_to_path
			best_along = walked + float(lengths[index]) * fraction
		walked += float(lengths[index])
	return clampf(best_along / maxf(total, 0.001), 0.02, 0.98)

func _track_endpoint_tangent(ref: Dictionary, is_start: bool, chord: Vector2, ref_lat: float) -> Vector2:
	var station_id := str(ref.get("stationId", ""))
	if not station_id.is_empty():
		var station := WorldData.find_station(world, station_id)
		if not station.is_empty():
			var outward := WorldData.station_outward(station, str(ref.get("side", "end")))
			return outward if is_start else -outward
	var node_id := str(ref.get("nodeId", ""))
	if node_id.is_empty(): node_id = str(ref.get("splitNodeId", ""))
	var split_edge_id := str(ref.get("splitEdgeId", ""))
	if node_id.is_empty() and not split_edge_id.is_empty():
		var split_edge := _find_link(split_edge_id)
		if not split_edge.is_empty():
			var split_points := TrackNetwork.edge_points(split_edge, world, ref_lat, 32)
			if split_points.size() >= 2:
				var split_index := clampi(roundi(clampf(float(ref.get("splitT", 0.5)), 0.0, 1.0) * float(split_points.size() - 1)), 0, split_points.size() - 2)
				var split_tangent := Geo.local_m(split_points[split_index + 1], ref_lat) - Geo.local_m(split_points[split_index], ref_lat)
				if split_tangent.length_squared() > 0.001:
					split_tangent = split_tangent.normalized()
					if split_tangent.dot(chord) < 0.0: split_tangent = -split_tangent
					return split_tangent
	for edge in TrackNetwork.all_physical_edges(world):
		var ends := TrackNetwork._edge_node_ids(edge, world)
		if ends.size() != 2 or not ends.has(node_id): continue
		var points := TrackNetwork.edge_points(edge, world, ref_lat, 8)
		if points.size() < 2: continue
		var local_points: Array[Vector2] = []
		for point in points: local_points.append(Geo.local_m(point, ref_lat))
		var tangent := local_points[1] - local_points[0] if ends[0] == node_id else local_points[-1] - local_points[-2]
		if tangent.length_squared() > 0.001:
			tangent = tangent.normalized()
			if tangent.dot(chord) < 0.0: tangent = -tangent
			return tangent
	return chord.normalized() if chord.length_squared() > 0.001 else Vector2.RIGHT

func _split_track_edge(state: Dictionary, edge_id: String, split_t: float, ref_lat: float) -> String:
	TrackNetwork.ensure_station_nodes(state)
	var edge: Dictionary = {}
	var is_legacy_link := false
	for candidate in state.get("trackEdges", []):
		if str(candidate.get("id", "")) == edge_id: edge = candidate; break
	if edge.is_empty():
		for legacy in state.get("trackLinks", []):
			if str(legacy.get("id", "")) != edge_id: continue
			var endpoints := TrackNetwork._edge_node_ids(legacy, state)
			if endpoints.size() != 2: return ""
			var converted := {"id": edge_id, "aNodeId": endpoints[0], "bNodeId": endpoints[1], "geometry": "straight" if legacy.get("schematic", false) else "bezier", "routeIds": legacy.get("routeIds", []).duplicate(), "speedLimitKmh": float(legacy.get("speedLimitKmh", -1.0)), "depthM": -15.0}
			if str(converted.geometry) == "bezier":
				var controls := WorldData.link_control_points(legacy, state, ref_lat)
				if controls.size() == 4:
					converted["controlA"] = [(controls[1] - controls[0]).x, (controls[1] - controls[0]).y]
					converted["controlB"] = [(controls[2] - controls[3]).x, (controls[2] - controls[3]).y]
			state.trackLinks = state.trackLinks.filter(func(item: Dictionary): return str(item.get("id", "")) != edge_id)
			state.trackEdges.append(converted)
			edge = converted
			is_legacy_link = true
			break
	if edge.is_empty(): return ""
	var ends := TrackNetwork._edge_node_ids(edge, state)
	if ends.size() != 2: return ""
	var node_a := TrackNetwork.find_node(state, ends[0]); var node_b := TrackNetwork.find_node(state, ends[1])
	if node_a.is_empty() or node_b.is_empty(): return ""
	var p0 := Geo.local_m(node_a.get("latlng", [0, 0]), ref_lat)
	var p3 := Geo.local_m(node_b.get("latlng", [0, 0]), ref_lat)
	var geometry := str(edge.get("geometry", "straight"))
	var p1 := p0.lerp(p3, 1.0 / 3.0)
	var p2 := p0.lerp(p3, 2.0 / 3.0)
	if geometry == "bezier":
		var delta := p3 - p0
		var ca: Array = edge.get("controlA", [delta.x / 3.0, delta.y / 3.0])
		var cb: Array = edge.get("controlB", [-delta.x / 3.0, -delta.y / 3.0])
		p1 = p0 + Vector2(float(ca[0]), float(ca[1]))
		p2 = p3 + Vector2(float(cb[0]), float(cb[1]))
	var distance_fraction := clampf(split_t, 0.02, 0.98)
	var t := _curve_t_at_distance(edge, state, ref_lat, distance_fraction)
	var q0 := p0.lerp(p1, t); var q1 := p1.lerp(p2, t); var q2 := p2.lerp(p3, t)
	var r0 := q0.lerp(q1, t); var r1 := q1.lerp(q2, t)
	var split_point := r0.lerp(r1, t)
	var split_latlng := Geo.from_local(split_point, ref_lat)
	var depth_a := float(node_a.get("depthM", edge.get("depthM", -15.0)))
	var depth_b := float(node_b.get("depthM", edge.get("depthM", -15.0)))
	var split_depth := lerpf(depth_a, depth_b, distance_fraction)
	var split_node := TrackNetwork.create_node(state, split_latlng, split_depth)
	var shared_routes: Array = edge.get("routeIds", []).duplicate()
	if is_legacy_link:
		for route_id in shared_routes:
			var route := WorldData.find_route(state, str(route_id))
			if not route.is_empty(): route.networkBased = true
	var base_id := "split_%d" % Time.get_ticks_usec()
	var phase_id := str(edge.get("planningPhaseId", ""))
	if phase_id.is_empty():
		for phase in state.get("planningPhases", []):
			if phase.get("edgeIds", []).has(edge_id): phase_id = str(phase.get("id", "")); break
	var left := {"id": base_id + "_a", "aNodeId": ends[0], "bNodeId": split_node.id, "geometry": geometry, "routeIds": shared_routes.duplicate(), "speedLimitKmh": edge.get("speedLimitKmh", -1.0), "depthM": (depth_a + split_depth) * 0.5, "planningPhaseId":phase_id}
	var right := {"id": base_id + "_b", "aNodeId": split_node.id, "bNodeId": ends[1], "geometry": geometry, "routeIds": shared_routes.duplicate(), "speedLimitKmh": edge.get("speedLimitKmh", -1.0), "depthM": (split_depth + depth_b) * 0.5, "planningPhaseId":phase_id}
	if geometry == "bezier":
		left["controlA"] = [(q0 - p0).x, (q0 - p0).y]
		left["controlB"] = [(r0 - split_point).x, (r0 - split_point).y]
		right["controlA"] = [(r1 - split_point).x, (r1 - split_point).y]
		right["controlB"] = [(q2 - p3).x, (q2 - p3).y]
	state.trackEdges = state.get("trackEdges", []).filter(func(item: Dictionary): return str(item.get("id", "")) != edge_id)
	state.trackEdges.append(left); state.trackEdges.append(right)
	if not phase_id.is_empty():
		for phase in state.get("planningPhases", []):
			if str(phase.get("id", "")) != phase_id: continue
			var phase_edge_ids: Array = phase.get("edgeIds", [])
			phase_edge_ids.erase(edge_id)
			if not phase_edge_ids.has(str(left.id)): phase_edge_ids.append(str(left.id))
			if not phase_edge_ids.has(str(right.id)): phase_edge_ids.append(str(right.id))
			phase["edgeIds"] = phase_edge_ids
			break
	if is_legacy_link: state.trackLinks = state.trackLinks.filter(func(item: Dictionary): return str(item.get("id", "")) != edge_id)
	_replace_split_edge_in_route_paths(state, edge_id, left, right)
	return str(split_node.get("id", ""))

func _curve_t_at_distance(edge: Dictionary, state: Dictionary, ref_lat: float, distance_fraction: float) -> float:
	if str(edge.get("geometry", "straight")) == "straight": return distance_fraction
	var samples := TrackNetwork.edge_points(edge, state, ref_lat, 256)
	var total := TrackNetwork.edge_length_m(edge, state, ref_lat)
	var target := total * distance_fraction
	var walked := 0.0
	for index in range(samples.size() - 1):
		var length := Geo.local_m(samples[index], ref_lat).distance_to(Geo.local_m(samples[index + 1], ref_lat))
		if walked + length >= target: return (float(index) + (target - walked) / maxf(length, 0.001)) / float(samples.size() - 1)
		walked += length
	return distance_fraction

func _replace_split_edge_in_route_paths(state: Dictionary, old_id: String, left: Dictionary, right: Dictionary) -> void:
	for route in state.get("routes", []):
		for direction in route.get("directions", []):
			if not direction is Dictionary: continue
			var paths: Array = direction.get("edgePathsBySegment", [])
			for segment_index in range(paths.size()):
				var segment: Array = paths[segment_index]
				var rewritten: Array = []
				for item in segment:
					if str(item.get("id", "")) != old_id:
						rewritten.append(item)
						continue
					if bool(item.get("forward", true)):
						rewritten.append({"id": str(left.id), "forward": true}); rewritten.append({"id": str(right.id), "forward": true})
					else:
						rewritten.append({"id": str(right.id), "forward": false}); rewritten.append({"id": str(left.id), "forward": false})
				paths[segment_index] = rewritten
			direction["edgePathsBySegment"] = paths

func _track_crossing_conflict(points_geo: Array, candidate: Dictionary, start_depth: float, end_depth: float, ref_lat: float, ignored_edges: Array[String] = [], check_state: Dictionary = {}) -> String:
	var state: Dictionary = check_state if not check_state.is_empty() else world
	var shared: Dictionary = {}
	for node_id in [str(candidate.get("aNodeId", "")), str(candidate.get("bNodeId", ""))]:
		if not node_id.is_empty(): shared[node_id] = true
	var candidate_local: Array[Vector2] = []
	for point in points_geo: candidate_local.append(Geo.local_m(point, ref_lat))
	var candidate_lengths := _polyline_segment_lengths(candidate_local)
	var candidate_total := _sum_lengths(candidate_lengths)
	for existing in TrackNetwork.all_physical_edges(state):
		if ignored_edges.has(str(existing.get("id", ""))): continue
		var ids := TrackNetwork._edge_node_ids(existing, state)
		if ids.size() != 2: continue
		var old_geo := TrackNetwork.edge_points(existing, state, ref_lat, 24)
		var old_local: Array[Vector2] = []
		for point in old_geo: old_local.append(Geo.local_m(point, ref_lat))
		var old_lengths := _polyline_segment_lengths(old_local)
		var old_total := _sum_lengths(old_lengths)
		var old_node_a := TrackNetwork.find_node(state, ids[0])
		var old_node_b := TrackNetwork.find_node(state, ids[1])
		var depth_a := float(old_node_a.get("depthM", existing.get("depthM", -15.0)))
		var depth_b := float(old_node_b.get("depthM", existing.get("depthM", -15.0)))
		var candidate_travelled := 0.0
		for i in range(candidate_local.size() - 1):
			var candidate_length := candidate_lengths[i] if i < candidate_lengths.size() else 0.0
			var old_travelled := 0.0
			for j in range(old_local.size() - 1):
				var old_length := old_lengths[j] if j < old_lengths.size() else 0.0
				var params := _segment_intersection_parameters(candidate_local[i], candidate_local[i + 1], old_local[j], old_local[j + 1])
				if params.x >= 0.0:
					var crossing := candidate_local[i].lerp(candidate_local[i + 1], float(params.x))
					var is_shared_endpoint := false
					for node_id in ids:
						if not shared.has(node_id): continue
						var shared_node := TrackNetwork.find_node(state, node_id)
						if shared_node.is_empty(): continue
						var shared_position := Geo.local_m(shared_node.get("latlng", [0, 0]), ref_lat)
						if crossing.distance_to(shared_position) <= 1.0: is_shared_endpoint = true; break
					if not is_shared_endpoint:
						var candidate_fraction := (candidate_travelled + candidate_length * float(params.x)) / maxf(candidate_total, 0.001)
						var old_fraction := (old_travelled + old_length * float(params.y)) / maxf(old_total, 0.001)
						var candidate_depth := lerpf(start_depth, end_depth, candidate_fraction)
						var existing_depth := lerpf(depth_a, depth_b, old_fraction)
						if absf(candidate_depth - existing_depth) < 5.0:
							return "交叉点深度差不足 5 米；调整纵断面或明确接轨"
				old_travelled += old_length
			candidate_travelled += candidate_length
	return ""

func _polyline_segment_lengths(points: Array[Vector2]) -> Array[float]:
	var lengths: Array[float] = []
	for index in range(points.size() - 1): lengths.append(points[index].distance_to(points[index + 1]))
	return lengths

func _sum_lengths(lengths: Array[float]) -> float:
	var total := 0.0
	for length in lengths: total += length
	return total

func _segment_intersection_parameters(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var ab := b - a; var cd := d - c
	var divisor := ab.cross(cd)
	if absf(divisor) < 0.001: return Vector2(-1, -1)
	var t := (c - a).cross(cd) / divisor
	var u := (c - a).cross(ab) / divisor
	return Vector2(t, u) if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0 else Vector2(-1, -1)

func _minimum_curve_radius(points_geo: Array, ref_lat: float) -> float:
	var minimum := INF
	for index in range(1, points_geo.size() - 1):
		var a := Geo.local_m(points_geo[index - 1], ref_lat)
		var b := Geo.local_m(points_geo[index], ref_lat)
		var c := Geo.local_m(points_geo[index + 1], ref_lat)
		var ab := a.distance_to(b); var bc := b.distance_to(c); var ac := a.distance_to(c)
		var twice_area := absf((b - a).cross(c - a))
		if twice_area > 0.01: minimum = minf(minimum, ab * bc * ac / (2.0 * twice_area))
	return minimum

func _station_overlaps_in(candidate: Dictionary, stations: Array) -> bool:
	var ref_lat := float(candidate.latlng[0])
	var center := Geo.local_m(candidate.latlng, ref_lat)
	var ang := deg_to_rad(float(candidate.heading))
	var along := Vector2(sin(ang), cos(ang))
	var across := Vector2(along.y, -along.x)
	var poly := _rect_points(center, along, across, float(candidate.lengthM)*.5, float(candidate.widthM)*.5)
	for station in stations:
		if str(station.get("id", "")) == str(candidate.get("id", "")): continue
		var other_center := Geo.local_m(station.latlng, ref_lat)
		var a := deg_to_rad(float(station.get("heading", 90)))
		var other_along := Vector2(sin(a), cos(a))
		var other_across := Vector2(other_along.y, -other_along.x)
		var other_poly := _rect_points(other_center, other_along, other_across, float(station.get("lengthM", 118.8))*.5, float(station.get("widthM", 20.0))*.5)
		if _polygons_intersect(poly, other_poly): return true
	return false

func _station_preview_analysis(candidate: Dictionary, source_state: Dictionary) -> Dictionary:
	# A station drag touches only the station, its endpoint nodes, and attached
	# edges. Unrelated planning arrays and story history remain read-only.
	var test_state: Dictionary = source_state.duplicate(false)
	var station_id := str(candidate.get("id", ""))
	var test_stations: Array = source_state.get("stations", []).duplicate()
	var test_station: Dictionary = {}
	var found_index := -1
	for index in range(test_stations.size()):
		if str(test_stations[index].get("id", "")) == station_id:
			found_index = index
			break
	test_station = candidate.duplicate(true)
	if found_index >= 0: test_stations[found_index] = test_station
	else: test_stations.append(test_station)
	test_state["stations"] = test_stations
	# Make only this station's endpoint nodes writable. Unrelated nodes and
	# stations remain shared read-only references during pointer-move previews.
	var test_nodes: Array = source_state.get("trackNodes", []).duplicate()
	test_state["trackNodes"] = test_nodes
	var endpoint_refs: Dictionary = test_station.get("endpointNodes", {}).duplicate(true)
	for side in ["start", "end"]:
		var key := "A" if side == "start" else "B"
		var node_id := str(endpoint_refs.get(key, "node_%s_%s" % [station_id, key.to_lower()]))
		var node_index := -1
		for index in range(test_nodes.size()):
			if str(test_nodes[index].get("id", "")) == node_id:
				node_index = index
				break
		var node_value := {"id": node_id, "latlng": WorldData.station_endpoint(test_station, side), "stationId": station_id, "side": side, "depthM": float(test_station.get("depthM", -15.0))}
		if node_index >= 0: test_nodes[node_index] = node_value
		else: test_nodes.append(node_value)
		endpoint_refs[key] = node_id
	test_station["endpointNodes"] = endpoint_refs
	test_state["trackEdges"] = source_state.get("trackEdges", []).duplicate()
	test_state["trackLinks"] = source_state.get("trackLinks", []).duplicate()
	var original_station := WorldData.find_station(source_state, station_id)
	var old_heading := float(original_station.get("heading", candidate.get("heading", 90.0)))
	var new_heading := float(candidate.get("heading", old_heading))
	var old_position: Array = original_station.get("latlng", [])
	var new_position: Array = candidate.get("latlng", old_position)
	var position_changed := old_position.size() >= 2 and new_position.size() >= 2 and _distance_m(old_position, new_position) > 0.05
	var length_changed := not is_equal_approx(float(original_station.get("lengthM", 0.0)), float(candidate.get("lengthM", original_station.get("lengthM", 0.0))))
	if position_changed or length_changed or not is_equal_approx(old_heading, new_heading):
		_align_station_edge_handles(test_state, station_id)
	var preview_edges: Dictionary = {}
	var issue := "站体与另一座车站重叠" if _station_overlaps_in(test_station, test_state.get("stations", [])) else ""
	var attached_nodes: Array = test_station.get("endpointNodes", {}).values()
	var ref_lat := float(WorldData.city(str(source_state.get("cityId", active_city_id))).get("center", [31.23, 121.47])[0])
	for edge in TrackNetwork.all_physical_edges(test_state):
		var ends := TrackNetwork._edge_node_ids(edge, test_state)
		if ends.size() != 2 or not (attached_nodes.has(ends[0]) or attached_nodes.has(ends[1])): continue
		var edge_issue := _physical_edge_geometry_issue(edge, test_state)
		if issue.is_empty() and not edge_issue.is_empty(): issue = edge_issue
		var points_geo := TrackNetwork.edge_points(edge, test_state, ref_lat, 32)
		var local_points: Array[Vector2] = []
		for point in points_geo: local_points.append(Geo.local_m(point, ref_lat))
		preview_edges[str(edge.get("id", ""))] = local_points
	return {"issue": issue, "state": test_state, "edges": preview_edges}

func _align_station_edge_handles(state: Dictionary, station_id: String) -> void:
	var station := WorldData.find_station(state, station_id)
	if station.is_empty(): return
	var ref_lat := float(WorldData.city(str(state.get("cityId", active_city_id))).get("center", [31.23, 121.47])[0])
	for collection_name in ["trackLinks", "trackEdges"]:
		var collection: Array = state.get(collection_name, [])
		for index in range(collection.size()):
			var source_edge: Dictionary = collection[index]
			var is_straight := str(source_edge.get("geometry", "straight")) == "straight"
			var endpoint_data: Array[Dictionary] = []
			if collection_name == "trackLinks" and source_edge.has("a") and not source_edge.has("aNodeId"):
				for side_key in ["a", "b"]:
					var endpoint: Dictionary = source_edge.get(side_key, {})
					if str(endpoint.get("stationId", "")) == station_id:
						endpoint_data.append({"which": side_key, "side": str(endpoint.get("side", "end")), "stationId": station_id})
				if not endpoint_data.is_empty() and is_straight:
					for side_key in ["a", "b"]:
						var endpoint: Dictionary = source_edge.get(side_key, {})
						if str(endpoint.get("stationId", "")).is_empty(): continue
						var already_added := false
						for item in endpoint_data:
							if str(item.which) == side_key: already_added = true
						if not already_added: endpoint_data.append({"which": side_key, "side": str(endpoint.get("side", "end")), "stationId": str(endpoint.get("stationId", ""))})
			else:
				var ends := TrackNetwork._edge_node_ids(source_edge, state)
				if ends.size() == 2:
					for position in range(2):
						var endpoint_node := TrackNetwork.find_node(state, ends[position])
						var side_name := str(endpoint_node.get("side", ""))
						var endpoint_station_id := str(endpoint_node.get("stationId", ""))
						if not side_name.is_empty() and endpoint_station_id == station_id:
							endpoint_data.append({"which": "a" if position == 0 else "b", "side": side_name, "stationId": endpoint_station_id})
					if not endpoint_data.is_empty() and is_straight:
						for position in range(2):
							var endpoint_node := TrackNetwork.find_node(state, ends[position])
							var side_name := str(endpoint_node.get("side", ""))
							var endpoint_station_id := str(endpoint_node.get("stationId", ""))
							var endpoint_key := "a" if position == 0 else "b"
							var already_added := false
							for item in endpoint_data:
								if str(item.which) == endpoint_key: already_added = true
							if not side_name.is_empty() and not endpoint_station_id.is_empty() and not already_added:
								endpoint_data.append({"which": endpoint_key, "side": side_name, "stationId": endpoint_station_id})
			if endpoint_data.is_empty() or bool(source_edge.get("schematic", false)): continue
			var edge: Dictionary = source_edge.duplicate(true)
			var endpoints := TrackNetwork._edge_node_ids(edge, state)
			var chord := Vector2.ZERO
			if endpoints.size() == 2:
				var first := TrackNetwork.find_node(state, endpoints[0])
				var last := TrackNetwork.find_node(state, endpoints[1])
				if not first.is_empty() and not last.is_empty(): chord = Geo.local_m(last.get("latlng", []), ref_lat) - Geo.local_m(first.get("latlng", []), ref_lat)
			for endpoint in endpoint_data:
				var at_a := str(endpoint.which) == "a"
				var key := ("controlA" if at_a else "controlB") if collection_name == "trackEdges" else ("curveA" if at_a else "curveB")
				var handle: Array = edge.get(key, [])
				var length := Vector2(float(handle[0]), float(handle[1])).length() if handle.size() >= 2 else 0.0
				if length < 1.0: length = maxf(20.0, chord.length() * 0.34)
				var endpoint_station := WorldData.find_station(state, str(endpoint.get("stationId", station_id)))
				if endpoint_station.is_empty(): endpoint_station = station
				var vector := WorldData.station_outward(endpoint_station, str(endpoint.side)) * length
				edge[key] = [vector.x, vector.y]
			if is_straight:
				edge["geometry"] = "bezier"
				if endpoint_data.size() == 1:
					var remote_key := ("controlB" if endpoint_data[0].which == "a" else "controlA") if collection_name == "trackEdges" else ("curveB" if endpoint_data[0].which == "a" else "curveA")
					var remote := -chord.normalized() * maxf(20.0, chord.length() * 0.34) if endpoint_data[0].which == "a" else chord.normalized() * maxf(20.0, chord.length() * 0.34)
					edge[remote_key] = [remote.x, remote.y]
			collection[index] = edge
		state[collection_name] = collection

func _physical_edge_geometry_issue(edge: Dictionary, check_state: Dictionary) -> String:
	var ends := TrackNetwork._edge_node_ids(edge, check_state)
	if ends.size() != 2: return "相邻轨道接点缺失"
	var node_a := TrackNetwork.find_node(check_state, ends[0])
	var node_b := TrackNetwork.find_node(check_state, ends[1])
	if node_a.is_empty() or node_b.is_empty(): return "相邻轨道接点缺失"
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var points := TrackNetwork.edge_points(edge, check_state, ref_lat, 40)
	var length := TrackNetwork.edge_length_m(edge, check_state, ref_lat)
	if length <= 0.1: return "相邻轨道长度为零"
	var depth_a := float(node_a.get("depthM", edge.get("depthM", -15.0)))
	var depth_b := float(node_b.get("depthM", edge.get("depthM", -15.0)))
	var grade := absf(depth_b - depth_a) / length
	if grade > 0.035: return "相邻区间纵坡 %.1f‰ 超过 35‰ 游戏预设" % (grade * 1000.0)
	var local_points: Array[Vector2] = []
	for point in points: local_points.append(Geo.local_m(point, ref_lat))
	if str(edge.get("geometry", "straight")) == "bezier":
		var endpoint_checks: Array[Dictionary] = []
		if edge.has("aNodeId"):
			for at_a in [true, false]:
				var node := TrackNetwork.find_node(check_state, str(edge.get("aNodeId" if at_a else "bNodeId", "")))
				if not node.is_empty() and not str(node.get("stationId", "")).is_empty():
					endpoint_checks.append({"station": WorldData.find_station(check_state, str(node.stationId)), "side": str(node.get("side", "")), "atA": at_a})
		else:
			for at_a in [true, false]:
				var ref: Dictionary = edge.get("a" if at_a else "b", {})
				var station := WorldData.find_station(check_state, str(ref.get("stationId", "")))
				if not station.is_empty(): endpoint_checks.append({"station": station, "side": str(ref.get("side", "")), "atA": at_a})
		for endpoint in endpoint_checks:
			var station: Dictionary = endpoint.station
			var side := str(endpoint.side)
			var is_a := bool(endpoint.atA)
			var key := ("controlA" if is_a else "controlB") if edge.has("aNodeId") else ("curveA" if is_a else "curveB")
			var handle: Array = edge.get(key, [])
			if handle.size() < 2: return "车站接头缺少顺接控制点"
			var tangent := Vector2(float(handle[0]), float(handle[1]))
			var outward := WorldData.station_outward(station, side)
			if tangent.length() < 1.0 or outward.length() < 0.5: return "车站接头方向无效"
			if absf(rad_to_deg(tangent.normalized().angle_to(outward.normalized()))) > 5.0:
				return "轨道与「%s」%s端方向不顺接" % [str(station.get("name", "车站")), "A" if side in ["start", "A"] else "B"]
	for first in range(local_points.size() - 1):
		for second in range(first + 2, local_points.size() - 1):
			if first == 0 and second == local_points.size() - 2: continue
			var params := _segment_intersection_parameters(local_points[first], local_points[first + 1], local_points[second], local_points[second + 1])
			if params.x >= 0.0: return "轨道曲线自身交叉"
	var crossing := _track_crossing_conflict(points, edge, depth_a, depth_b, ref_lat, [str(edge.get("id", ""))], check_state)
	return crossing

func _rect_points(c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float) -> Array[Vector2]:
	return [c-u*hu-v*hv,c+u*hu-v*hv,c+u*hu+v*hv,c-u*hu+v*hv]

func _polygons_intersect(a: Array[Vector2], b: Array[Vector2]) -> bool:
	for poly in [a,b]:
		for i in range(poly.size()):
			var edge: Vector2 = poly[(i+1)%poly.size()] - poly[i]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
			for p in a: amin = minf(amin,p.dot(axis)); amax = maxf(amax,p.dot(axis))
			for p in b: bmin = minf(bmin,p.dot(axis)); bmax = maxf(bmax,p.dot(axis))
			if amax <= bmin or bmax <= amin: return false
	return true

func _find_link(link_id: String) -> Dictionary:
	for link in TrackNetwork.all_physical_edges(world):
		if str(link.get("id", "")) == link_id: return link
	return {}

func _distance_m(a: Array, b: Array) -> float:
	var ref_lat := (float(a[0]) + float(b[0])) * .5
	return Geo.local_m(a, ref_lat).distance_to(Geo.local_m(b, ref_lat))

