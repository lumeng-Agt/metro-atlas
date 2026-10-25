class_name MapView
extends Control

class TrainOverlay extends Control:
	var map_view: MapView
	func _draw() -> void:
		if is_instance_valid(map_view): map_view._draw_trains_on(self)

const Style = preload("res://scripts/map_style.gd")
const RoutePathScript = preload("res://scripts/route_path.gd")
const BASEMAP_CACHE_BUDGET_BYTES := 256 * 1024 * 1024

signal map_clicked(latlng: Array, hit_type: String, hit_id: String, side: String, hit_t: float)
signal station_dragged(station_id: String, latlng: Array)
signal station_drag_finished(station_id: String, latlng: Array)
signal curve_control_previewed(link_id: String, control_name: String, offset_m: Array)
signal curve_control_finished(link_id: String, control_name: String, offset_m: Array)
signal camera_changed(center: Array, zoom: int)
signal cancel_requested
signal draft_station_changed


var city_data: Dictionary = {}
var world: Dictionary = {}
var route_path_cache: Dictionary = {}
var presentation_seconds := 0.0
var show_train_display := true
var draft_track_points: Array = []
var draft_track_segments: Array[Dictionary] = []
var highlight_path_points: Array = []
var assisted_preview: Dictionary = {}
var chapter_baseline_overlay: Dictionary = {}
var route_path_cache_revision := -1
var link_geometry_cache: Dictionary = {}
var station_local_cache: Dictionary = {}
var route_cache_by_id: Dictionary = {}
var geometry_ref_lat := 31.23
var _camera_cache_center: Array = []
var _camera_cache_size := Vector2.ZERO
var _camera_cache_zoom := -1
var _camera_center_pixel := Vector2.ZERO
var _camera_local_center := Vector2.ZERO
var _camera_mpp := 1.0
var selected_id := ""
var selected_type := ""
var active_route_id := ""
var campaign_blueprint: Dictionary = {}
var blueprint_choice_candidates: Array[Dictionary] = []
var station_choice_candidates: Array[Dictionary] = []
var endpoint_choice_candidates: Array[Dictionary] = []
var story_markers: Array = []
var _basemap_labels: Array[Dictionary] = []
var show_road_names := true
var base_map_features: Array[Dictionary] = []
var base_map_draw_batches: Dictionary = {}
var base_map_bounds := Rect2()
var base_map_snapshot := "未安装"
var base_map_available := false
var base_map_city_path := ""
var base_map_chunk_degrees := 0.05
var base_map_chunk_paths: Array = []
var base_map_chunk_available: Dictionary = {}
var base_map_chunk_cache: Dictionary = {}
var base_map_chunk_cache_order: Array[String] = []
var base_map_chunk_cache_bytes: Dictionary = {}
var base_map_cache_bytes := 0
var base_map_cache_over_budget_bytes := 0
var base_map_loaded_signature := ""
var _base_map_thread := Thread.new()
var _base_map_thread_busy := false
var _base_map_pending_request: Dictionary = {}
var bold_font: Font
var ui_scale := 1.0
var tool := "select"
var hover_latlng: Array = []
var draft_station: Dictionary = {}
var link_start: Dictionary = {}
var track_start_ref: Dictionary = {}
var track_end_ref: Dictionary = {}
var track_control_latlng: Array = []
var line_draft_points: Array[Array] = []
var track_preview_conflict := ""
var track_preview_notice := ""
var station_preview_edges: Dictionary = {}
var station_preview_issue := ""
var current_depth_m := -15.0
var show_all_depths := false
var continuous_track := true
var show_network := true
var show_stations := true
var show_halls := true
var current_center: Array = [31.2304, 121.4737]
var current_zoom := 13
var _mouse_down := false
var _pan_active := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _drag_station_id := ""
var _drag_preview: Array = []
var _drag_curve: Array = []
var _curve_preview: Dictionary = {}
var _curve_commit_pending := false
var curve_preview_issue := ""
var draft_conflict := false
var _drag_draft_station := false
var _label_rects: Array[Rect2] = []
var _train_overlay: TrainOverlay

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(false)
	_train_overlay = TrainOverlay.new()
	_train_overlay.name = "TrainOverlay"
	_train_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_train_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_train_overlay.map_view = self
	add_child(_train_overlay)

func _exit_tree() -> void:
	if _base_map_thread_busy:
		_base_map_thread.wait_to_finish()
		_base_map_thread_busy = false

func set_context(city: Dictionary, state: Dictionary) -> void:
	city_data = city
	world = state
	_rebuild_route_path_cache()
	current_center = state.get("view", {}).get("center", city.get("center", [31.2304, 121.4737])).duplicate()
	current_zoom = int(state.get("view", {}).get("zoom", city.get("zoom", 12)))
	_refresh_camera_cache()
	_load_local_basemap(str(city.get("id", "")))
	requested_redraw()

func set_world(state: Dictionary) -> void:
	world = state
	_rebuild_route_path_cache()
	requested_redraw()

func set_blueprint(value: Dictionary) -> void:
	campaign_blueprint = value.duplicate(true)
	requested_redraw()

func snap_blueprint_station(latlng: Array, radius_px: float = 20.0) -> Dictionary:
	if not bool(campaign_blueprint.get("visible", false)) or latlng.size() < 2: return {}
	var click := _to_screen(latlng)
	var closest: Dictionary = {}
	var closest_distance := radius_px
	for target in campaign_blueprint.get("stations", []):
		if bool(target.get("built", false)): continue
		var screen_distance := click.distance_to(_to_screen(target.get("latlng", [])))
		if screen_distance <= closest_distance:
			closest_distance = screen_distance
			closest = target
	return closest

func blueprint_heading_for(target_id: String) -> float:
	for target in campaign_blueprint.get("stations",[]):
		if str(target.get("id",""))==target_id and float(target.get("referenceHeading",-1))>=0:return float(target.referenceHeading)
	for corridor in campaign_blueprint.get("corridors", []):
		var points: Array = corridor.get("targets", [])
		for index in range(points.size()):
			if str(points[index].get("id", "")) != target_id: continue
			var neighbor_index := index + 1 if index + 1 < points.size() else index - 1
			if neighbor_index < 0 or neighbor_index >= points.size(): return -1.0
			var origin: Vector2 = Geo.local_m(points[index].get("latlng", [0.0, 0.0]), geometry_ref_lat)
			var neighbor: Vector2 = Geo.local_m(points[neighbor_index].get("latlng", [0.0, 0.0]), geometry_ref_lat)
			var direction := neighbor - origin
			if direction.length_squared() < 1.0: return -1.0
			return fposmod(90.0 - rad_to_deg(direction.angle()), 180.0)
	return -1.0

func _rebuild_route_path_cache() -> void:
	route_path_cache.clear()
	link_geometry_cache.clear()
	station_local_cache.clear()
	route_cache_by_id.clear()
	geometry_ref_lat = float(city_data.get("center", [31.23, 121.47])[0])
	var station_by_id: Dictionary = {}
	for station in world.get("stations", []):
		var station_id := str(station.get("id", ""))
		station_by_id[station_id] = station
		station_local_cache[station_id] = Geo.local_m(station.get("latlng", [0.0, 0.0]), geometry_ref_lat)
	for route in world.get("routes", []):
		route_cache_by_id[str(route.get("id", ""))] = route
		if not bool(route.get("open", false)): continue
		var canonical:=RoutePathScript.for_route(route,world,geometry_ref_lat)
		canonical["presentationDirections"]=RoutePathScript.presentation_directions(canonical,route)
		route_path_cache[str(route.get("id", ""))] = canonical
	for link in world.get("trackLinks", []):
		var a_ref: Dictionary = link.get("a", {})
		var b_ref: Dictionary = link.get("b", {})
		var a: Dictionary = station_by_id.get(str(a_ref.get("stationId", "")), {})
		var b: Dictionary = station_by_id.get(str(b_ref.get("stationId", "")), {})
		if a.is_empty() or b.is_empty(): continue
		var local_points: Array[Vector2] = []
		if bool(link.get("schematic", false)):
			local_points.append(station_local_cache[str(a.get("id", ""))])
			local_points.append(station_local_cache[str(b.get("id", ""))])
		else:
			var controls := _link_control_local(link, a, b)
			for index in range(25):
				local_points.append(_bezier(controls[0], controls[1], controls[2], controls[3], float(index) / 24.0))
		if local_points.size() < 2: continue
		var min_point := local_points[0]
		var max_point := local_points[0]
		for point in local_points:
			min_point.x = minf(min_point.x, point.x); min_point.y = minf(min_point.y, point.y)
			max_point.x = maxf(max_point.x, point.x); max_point.y = maxf(max_point.y, point.y)
		link_geometry_cache[str(link.get("id", ""))] = {"points": local_points, "bounds": Rect2(min_point, max_point - min_point).grow(1.0)}
	TrackNetwork.ensure_station_nodes(world)
	for edge in world.get("trackEdges", []):
		var geographic_points := TrackNetwork.edge_points(edge, world, geometry_ref_lat, 24)
		var local_points: Array[Vector2] = []
		for point in geographic_points: local_points.append(Geo.local_m(point, geometry_ref_lat))
		if local_points.size() < 2: continue
		var minimum := local_points[0]
		var maximum := local_points[0]
		for point in local_points:
			minimum.x = minf(minimum.x, point.x); minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x); maximum.y = maxf(maximum.y, point.y)
		link_geometry_cache[str(edge.get("id", ""))] = {"points": local_points, "bounds": Rect2(minimum, maximum - minimum).grow(1.0)}
	route_path_cache_revision = int(world.get("revision", 0))
	_camera_cache_zoom = -1

func _link_control_local(link: Dictionary, a: Dictionary, b: Dictionary) -> Array[Vector2]:
	var a_side := str(link.get("a", {}).get("side", "end"))
	var b_side := str(link.get("b", {}).get("side", "start"))
	var p0 := Geo.local_m(WorldData.station_endpoint(a, a_side), geometry_ref_lat)
	var p3 := Geo.local_m(WorldData.station_endpoint(b, b_side), geometry_ref_lat)
	var defaults := WorldData.default_curve_vectors(a, a_side, b, b_side, geometry_ref_lat)
	var va: Array = link.get("curveA", defaults.a)
	var vb: Array = link.get("curveB", defaults.b)
	return [p0, p0 + Vector2(float(va[0]), float(va[1])), p3 + Vector2(float(vb[0]), float(vb[1])), p3]

func center_on(latlng: Array, zoom_level: int = -1) -> void:
	current_center = [float(latlng[0]), float(latlng[1])]
	if zoom_level >= 0: current_zoom = clampi(zoom_level, 3, 19)
	_store_view()
	requested_redraw()
	camera_changed.emit(current_center, current_zoom)

func requested_redraw() -> void:
	queue_redraw()
	requested_train_redraw()

func requested_train_redraw() -> void:
	if is_instance_valid(_train_overlay): _train_overlay.queue_redraw()

func clear_curve_preview() -> void:
	_curve_preview.clear()
	_curve_commit_pending = false
	curve_preview_issue = ""
	requested_redraw()

func cancel_pointer_interaction() -> void:
	_mouse_down = false
	_pan_active = false
	_drag_station_id = ""
	_drag_curve = []
	_drag_draft_station = false
	_drag_preview.clear()
	clear_curve_preview()
	requested_redraw()

func _load_local_basemap(city_id: String) -> void:
	base_map_loaded_signature = ""
	_base_map_pending_request = {}
	base_map_chunk_cache.clear()
	base_map_chunk_cache_order.clear()
	base_map_chunk_cache_bytes.clear()
	base_map_cache_bytes = 0
	base_map_cache_over_budget_bytes = 0
	base_map_features.clear()
	base_map_bounds = Rect2()
	base_map_snapshot = "未安装"
	base_map_available = false
	base_map_city_path = ""
	base_map_chunk_paths.clear()
	base_map_chunk_available.clear()
	base_map_loaded_signature = ""
	var manifest_file := FileAccess.open("res://data/basemap/manifest.json", FileAccess.READ)
	if manifest_file == null: return
	var manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	if not manifest is Dictionary: return
	var city_package: Dictionary = manifest.get("cities", {}).get(city_id, {})
	if city_package.is_empty(): return
	var ref_lat := float(city_data.get("center", [31.23, 121.47])[0])
	var bbox: Array = city_package.get("bounds", [])
	if bbox.size() == 4:
		var southwest := Geo.local_m([float(bbox[0]), float(bbox[1])], ref_lat)
		var northeast := Geo.local_m([float(bbox[2]), float(bbox[3])], ref_lat)
		base_map_bounds = Rect2(southwest, northeast - southwest)
	base_map_city_path = str(city_package.get("path", city_id))
	base_map_chunk_degrees = float(city_package.get("chunkDegrees", 0.05))
	base_map_chunk_paths = city_package.get("chunks", [])
	for path in base_map_chunk_paths:
		base_map_chunk_available[str(path).trim_suffix(".json.gz")] = true
	base_map_snapshot = str(city_package.get("sourceModified", "未知日期"))
	base_map_available = not base_map_chunk_paths.is_empty()
	_load_visible_base_chunks()

func _load_visible_base_chunks() -> void:
	if base_map_city_path.is_empty() or base_map_chunk_paths.is_empty(): return
	var southwest := Geo.from_local(_camera_local_center - size * 0.5 * _camera_mpp, geometry_ref_lat)
	var northeast := Geo.from_local(_camera_local_center + size * 0.5 * _camera_mpp, geometry_ref_lat)
	# Chunk assignment duplicates long features into every cell crossed by their
	# bounds, so a full chunk of padding is unnecessary. Keep only enough margin
	# for the offscreen draw gutter; this avoids loading an entire ring of dense
	# city blocks around a neighborhood-scale view.
	var pad := 120.0 * _camera_mpp / (111_132.0 * cos(deg_to_rad(geometry_ref_lat)))
	var row_min := int(floor((float(southwest[0]) - pad) / base_map_chunk_degrees))
	var row_max := int(floor((float(northeast[0]) + pad) / base_map_chunk_degrees))
	var col_min := int(floor((float(southwest[1]) - pad) / base_map_chunk_degrees))
	var col_max := int(floor((float(northeast[1]) + pad) / base_map_chunk_degrees))
	var wanted: Array[String] = []
	for row in range(row_min, row_max + 1):
		for col in range(col_min, col_max + 1):
			var key := "%d_%d" % [row, col]
			if base_map_chunk_available.has(key): wanted.append(key)
	wanted.sort()
	var signature := "%s|%s" % [str(city_data.get("id", "")), ",".join(wanted)]
	# Feature preparation uses actual zoom and scale. Cache on that same level so
	# approaching a view from either direction cannot reuse a coarse filtered set.
	var detail_band := current_zoom
	signature += "|%d" % detail_band
	if signature == base_map_loaded_signature: return
	base_map_loaded_signature = signature
	var missing: Array[Dictionary] = []
	var cached_chunks: Dictionary = {}
	for key in wanted:
		var cache_key := "%s|%d" % [key, detail_band]
		if not base_map_chunk_cache.has(cache_key):
			missing.append({"key": cache_key, "path": "res://data/basemap/%s/%s.json.gz" % [base_map_city_path, key]})
		else:
			cached_chunks[cache_key] = base_map_chunk_cache[cache_key]
			base_map_chunk_cache_order.erase(cache_key)
			base_map_chunk_cache_order.append(cache_key)
	var request := {"signature": signature, "cityId": str(city_data.get("id", "")), "wanted": wanted, "detailBand": detail_band, "zoom": current_zoom, "mpp": _camera_mpp, "refLat": geometry_ref_lat, "chunks": missing, "cachedChunks": cached_chunks}
	if _base_map_thread_busy:
		_base_map_pending_request = request
	else:
		_start_base_map_worker(request)

func _rebuild_visible_base_features(wanted: Array[String], detail_band: int) -> void:
	base_map_features.clear()
	base_map_draw_batches.clear()
	var seen_feature_ids: Dictionary = {}
	for key in wanted:
		var prepared_features: Array = base_map_chunk_cache.get("%s|%d" % [key, detail_band], [])
		for feature in prepared_features:
			var feature_id := str(feature.get("id", ""))
			if feature_id.is_empty(): feature_id = "%s|%s|%s" % [feature.get("kind", ""), feature.get("name", ""), feature.get("bounds", Rect2())]
			if seen_feature_ids.has(feature_id): continue
			seen_feature_ids[feature_id] = true
			base_map_features.append(feature)
	_prepare_basemap_draw_batches()

func _prepare_basemap_draw_batches() -> void:
	base_map_draw_batches = _prepare_basemap_draw_batches_for(base_map_features, current_zoom, _camera_mpp)

static func _prepare_basemap_draw_batches_for(features: Array, zoom_level: int, meters_per_pixel: float) -> Dictionary:
	# Preparing line and polygon arrays while drawing made every pan rescan and
	# repack thousands of OSM ways. Build once when the visible tile set changes;
	# panning within those tiles now only submits a few cached draw batches.
	var batches := {
		"waterPoints": PackedVector2Array(), "waterIndices": PackedInt32Array(), "waterColors": PackedColorArray(), "waterOutline": PackedVector2Array(),
		"parkPoints": PackedVector2Array(), "parkIndices": PackedInt32Array(), "parkColors": PackedColorArray(), "parkOutline": PackedVector2Array(),
		"majorLines": PackedVector2Array(), "primaryLines": PackedVector2Array(), "secondaryLines": PackedVector2Array(), "localLines": PackedVector2Array(), "waterLines": PackedVector2Array(),
		"buildingPoints": PackedVector2Array(), "buildingIndices": PackedInt32Array(), "buildingColors": PackedColorArray(), "buildingOutline": PackedVector2Array(),
		"majorBuildingPoints": PackedVector2Array(), "majorBuildingIndices": PackedInt32Array(), "majorBuildingColors": PackedColorArray(), "majorBuildingOutline": PackedVector2Array(),
		"roadLabels": []
	}
	for feature in features:
		var kind := str(feature.get("kind", ""))
		var points: PackedVector2Array = feature.get("points", PackedVector2Array())
		var pairs: PackedVector2Array = feature.get("pairs", PackedVector2Array())
		if kind in ["water_area", "park"] and points.size() >= 3:
			var triangles: PackedInt32Array = feature.get("fillIndices", PackedInt32Array())
			var point_key := "waterPoints" if kind == "water_area" else "parkPoints"
			var index_key := "waterIndices" if kind == "water_area" else "parkIndices"
			var color_key := "waterColors" if kind == "water_area" else "parkColors"
			var outline_key := "waterOutline" if kind == "water_area" else "parkOutline"
			if not triangles.is_empty():
				var polygon_points: PackedVector2Array = batches[point_key]
				var polygon_indices: PackedInt32Array = batches[index_key]
				var polygon_colors: PackedColorArray = batches[color_key]
				var base := polygon_points.size()
				polygon_points.append_array(points)
				for index in triangles: polygon_indices.append(base + index)
				var fill := Style.WATER if kind == "water_area" else Style.PARK
				for _index in points.size(): polygon_colors.append(fill)
				batches[point_key] = polygon_points
				batches[index_key] = polygon_indices
				batches[color_key] = polygon_colors
			var polygon_outline: PackedVector2Array = batches[outline_key]
			polygon_outline.append_array(pairs)
			batches[outline_key] = polygon_outline
		elif kind in ["road_major", "road_primary", "road_secondary", "road_local", "water_line"]:
			var line_key: String = str({"road_major":"majorLines", "road_primary":"primaryLines", "road_secondary":"secondaryLines", "road_local":"localLines", "water_line":"waterLines"}.get(kind, ""))
			var line_batch: PackedVector2Array = batches[line_key]
			line_batch.append_array(pairs)
			batches[line_key] = line_batch
			if Style.label_visible(kind, zoom_level) and kind != "water_line" and not str(feature.get("name", "")).is_empty() and points.size() >= 2:
				batches.roadLabels.append({"position": points[points.size() / 2], "name": str(feature.name), "kind": kind, "priority": _road_label_priority(kind), "bounds": feature.get("bounds", Rect2()), "angle": _road_angle(points)})
		elif kind in ["building", "building_major"] and points.size() >= 3 and (zoom_level >= 17 if kind == "building" else zoom_level >= 14):
			var triangles: PackedInt32Array = feature.get("fillIndices", PackedInt32Array())
			var point_key := "buildingPoints" if kind == "building" else "majorBuildingPoints"
			var index_key := "buildingIndices" if kind == "building" else "majorBuildingIndices"
			var color_key := "buildingColors" if kind == "building" else "majorBuildingColors"
			var outline_key := "buildingOutline" if kind == "building" else "majorBuildingOutline"
			var fill_color := Style.BUILDING if kind == "building" else Style.LANDMARK
			if not triangles.is_empty():
				var building_points: PackedVector2Array = batches[point_key]
				var building_indices: PackedInt32Array = batches[index_key]
				var building_colors: PackedColorArray = batches[color_key]
				var base := building_points.size()
				building_points.append_array(points)
				for index in triangles: building_indices.append(base + index)
				for _index in points.size(): building_colors.append(fill_color)
				batches[point_key] = building_points
				batches[index_key] = building_indices
				batches[color_key] = building_colors
			var bounds: Rect2 = feature.get("bounds", Rect2())
			var projected_area: float = bounds.size.x * bounds.size.y / maxf(meters_per_pixel * meters_per_pixel, 0.001)
			if projected_area >= (400.0 if kind == "building" else 80.0):
				var building_outline: PackedVector2Array = batches[outline_key]
				building_outline.append_array(pairs)
				batches[outline_key] = building_outline
			if kind == "building_major" and Style.label_visible(kind,zoom_level) and not str(feature.get("name", "")).is_empty() and points.size() >= 2:
				batches.roadLabels.append({"position": bounds.get_center(), "name": str(feature.get("name", "")), "kind": kind, "priority": _road_label_priority(kind), "bounds": bounds})
	# Priority is invariant while a chunk batch is loaded. Sort in the worker,
	# rather than sorting every label again during each pan/render frame.
	batches.roadLabels.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.get("priority",0))>int(b.get("priority",0)))
	return batches

func _start_base_map_worker(request: Dictionary) -> void:
	if request.is_empty(): return
	var error := _base_map_thread.start(_load_and_prepare_base_chunks.bind(request), Thread.PRIORITY_LOW)
	if error != OK:
		_base_map_pending_request = request
		set_process(true)
		return
	_base_map_thread_busy = true
	set_process(true)

func _process(_delta: float) -> void:
	if _base_map_thread_busy:
		if _base_map_thread.is_alive(): return
		var result: Variant = _base_map_thread.wait_to_finish()
		_base_map_thread_busy = false
		if result is Dictionary and str(result.get("cityId", "")) == str(city_data.get("id", "")) and str(result.get("signature", "")) == base_map_loaded_signature:
			for cache_key in result.get("chunks", {}):
				var normalized_key := str(cache_key)
				if base_map_chunk_cache_bytes.has(normalized_key):
					base_map_cache_bytes -= int(base_map_chunk_cache_bytes[normalized_key])
				var chunk_features: Array = result.chunks[cache_key]
				var chunk_bytes := _estimate_prepared_chunk_bytes(chunk_features)
				base_map_chunk_cache[normalized_key] = chunk_features
				base_map_chunk_cache_bytes[normalized_key] = chunk_bytes
				base_map_cache_bytes += chunk_bytes
				base_map_chunk_cache_order.erase(normalized_key)
				base_map_chunk_cache_order.append(normalized_key)
			base_map_features.clear()
			for feature in result.get("features", []): base_map_features.append(feature)
			base_map_draw_batches = result.get("drawBatches", {})
			_trim_basemap_cache(result.get("wanted", []), int(result.get("detailBand", current_zoom)))
			requested_redraw()
	if not _base_map_pending_request.is_empty():
		var next_request := _base_map_pending_request
		_base_map_pending_request = {}
		_start_base_map_worker(next_request)
	else:
		set_process(false)

func _trim_basemap_cache(wanted: Array, detail_band: int) -> void:
	var protected: Dictionary = {}
	for key in wanted: protected["%s|%d" % [str(key), detail_band]] = true
	var attempts := base_map_chunk_cache_order.size()
	while base_map_cache_bytes > BASEMAP_CACHE_BUDGET_BYTES and attempts > 0:
		attempts -= 1
		var candidate: String = base_map_chunk_cache_order.pop_front()
		if protected.has(candidate):
			base_map_chunk_cache_order.append(candidate)
			continue
		base_map_cache_bytes -= int(base_map_chunk_cache_bytes.get(candidate, 0))
		base_map_chunk_cache_bytes.erase(candidate)
		base_map_chunk_cache.erase(candidate)
	base_map_cache_over_budget_bytes = maxi(0, base_map_cache_bytes - BASEMAP_CACHE_BUDGET_BYTES)

func _estimate_prepared_chunk_bytes(features: Array) -> int:
	var total := 0
	for feature in features:
		if not feature is Dictionary: continue
		total += 128
		total += str(feature.get("id", "")).length() * 2
		total += str(feature.get("name", "")).length() * 2
		total += feature.get("points", PackedVector2Array()).size() * 8
		total += feature.get("pairs", PackedVector2Array()).size() * 8
		total += feature.get("fillIndices", PackedInt32Array()).size() * 4
	return total

func _load_and_prepare_base_chunks(request: Dictionary) -> Dictionary:
	var prepared: Dictionary = {}
	for chunk in request.get("chunks", []):
		if not chunk is Dictionary: continue
		var compressed_bytes := FileAccess.get_file_as_bytes(str(chunk.get("path", "")))
		if compressed_bytes.is_empty(): continue
		var decoded_bytes := compressed_bytes.decompress_dynamic(32 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
		if decoded_bytes.is_empty(): continue
		var parsed: Variant = JSON.parse_string(decoded_bytes.get_string_from_utf8())
		if not parsed is Dictionary or str(parsed.get("cityId", "")) != str(request.get("cityId", "")): continue
		prepared[str(chunk.get("key", ""))] = _prepare_base_features_for(parsed.get("features", []), int(request.get("zoom", 12)), float(request.get("mpp", 1.0)), float(request.get("refLat", 31.23)))
	var all_chunks: Dictionary = request.get("cachedChunks", {}).duplicate()
	for cache_key in prepared: all_chunks[cache_key] = prepared[cache_key]
	var combined_features: Array[Dictionary] = []
	var seen_feature_ids: Dictionary = {}
	for key in request.get("wanted", []):
		var cache_key := "%s|%d" % [str(key), int(request.get("detailBand", 12))]
		for feature in all_chunks.get(cache_key, []):
			var feature_id := str(feature.get("id", ""))
			if feature_id.is_empty(): feature_id = "%s|%s|%s" % [feature.get("kind", ""), feature.get("name", ""), feature.get("bounds", Rect2())]
			if seen_feature_ids.has(feature_id): continue
			seen_feature_ids[feature_id] = true
			combined_features.append(feature)
	var draw_batches := _prepare_basemap_draw_batches_for(combined_features, int(request.get("zoom", 12)), float(request.get("mpp", 1.0)))
	return {"signature": request.get("signature", ""), "cityId": request.get("cityId", ""), "wanted": request.get("wanted", []), "detailBand": request.get("detailBand", 12), "chunks": prepared, "features": combined_features, "drawBatches": draw_batches}

func _prepare_base_features(raw_features: Array) -> Array[Dictionary]:
	return _prepare_base_features_for(raw_features, current_zoom, _camera_mpp, geometry_ref_lat)

static func _prepare_base_features_for(raw_features: Array, zoom_level: int, meters_per_pixel: float, ref_lat: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw in raw_features:
		if not raw is Dictionary: continue
		var kind := str(raw.get("kind", ""))
		if kind == "building" and zoom_level < 17: continue
		if kind == "building_major" and zoom_level < 14: continue
		if kind == "road_local" and zoom_level < 16: continue
		if kind == "road_secondary" and zoom_level < 15: continue
		if kind == "road_primary" and zoom_level < 13: continue
		if kind == "road_major" and zoom_level < 10: continue
		var points: Array[Vector2] = []
		for point in raw.get("points", []):
			if point is Array and point.size() >= 2: points.append(Geo.local_m([float(point[0]), float(point[1])], ref_lat))
		if points.size() < 2: continue
		var path_length := 0.0
		for point_index in range(1, points.size()):
			path_length += points[point_index - 1].distance_to(points[point_index])
		var maximum := points[0]
		var minimum := points[0]
		for point in points:
			minimum.x = minf(minimum.x, point.x); minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x); maximum.y = maxf(maximum.y, point.y)
		# OSM roads are commonly split into short ways at intersections. Filter
		# only lines that occupy less than a pixel; length-based city thresholds
		# caused visible holes in otherwise continuous streets.
		var screen_path_length := path_length / maxf(meters_per_pixel, 0.01)
		if kind == "water_line" and screen_path_length < 2.0: continue
		if kind in ["water_area", "park", "building", "building_major"]:
			var projected_area := (maximum.x - minimum.x) * (maximum.y - minimum.y) / maxf(meters_per_pixel * meters_per_pixel, 0.001)
			var area_threshold := 1800.0 if zoom_level < 14 and kind in ["water_area", "park"] else 160.0 if kind == "building" else 48.0 if kind == "building_major" else 32.0
			if projected_area < area_threshold: continue
		if zoom_level < 15: points = _simplify_local_points(points, maxf(4.0, 1.5 * meters_per_pixel))
		var packed_points := PackedVector2Array(points)
		var fill_indices := PackedInt32Array()
		if kind in ["water_area", "park", "building", "building_major"] and packed_points.size() >= 3:
			fill_indices = Geometry2D.triangulate_polygon(packed_points)
		for point in points:
			minimum.x = minf(minimum.x, point.x); minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x); maximum.y = maxf(maximum.y, point.y)
		var pairs := _polyline_pairs(packed_points, kind in ["water_area", "park", "building", "building_major"])
		result.append({"id": str(raw.get("id", "")), "kind": kind, "name": str(raw.get("name", "")), "points": packed_points, "pairs": pairs, "bounds": Rect2(minimum, maximum - minimum), "fillValid": not fill_indices.is_empty(), "fillIndices": fill_indices})
	return result

static func _simplify_local_points(points: Array[Vector2], tolerance_m: float) -> Array[Vector2]:
	if points.size() <= 3: return points
	var result: Array[Vector2] = [points[0]]
	var last_kept: Vector2 = points[0]
	var tolerance_sq := tolerance_m * tolerance_m
	for point_index in range(1, points.size() - 1):
		var point: Vector2 = points[point_index]
		if last_kept.distance_squared_to(point) >= tolerance_sq:
			result.append(point)
			last_kept = point
	result.append(points[points.size() - 1])
	return result

func _draw() -> void:
	_refresh_camera_cache()
	_label_rects.clear()
	_basemap_labels.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Style.CANVAS)
	_draw_local_basemap()
	_draw_campaign_corridors()
	_draw_built_links()
	if highlight_path_points.size()>=2:
		var highlight:=PackedVector2Array()
		for point in highlight_path_points:highlight.append(_to_screen(point))
		draw_polyline(highlight,Color("#cf9737"),6.0,true)
	_draw_station_preview_links()
	_draw_campaign_targets()
	_draw_stations()
	_draw_queued_basemap_labels()
	_draw_story_markers()
	_draw_draft()
	_draw_view_hints()

func _draw_campaign_corridors() -> void:
	if not bool(campaign_blueprint.get("visible", false)): return
	for scheme in campaign_blueprint.get("previous",[]):
		for index in range(scheme.size()-1):draw_dashed_line(_to_screen(scheme[index]),_to_screen(scheme[index+1]),Style.PREVIOUS_PLAN,5.0,10.0,true)
	for corridor in campaign_blueprint.get("corridors", []):
		var points: Array = corridor.get("points", [])
		if points.size() < 2: continue
		for index in range(1, points.size()):
			var a := _to_screen(points[index - 1])
			var b := _to_screen(points[index])
			var schematic:=str(corridor.get("precision","schematic"))=="schematic"
			if not schematic:draw_line(a,b,Color(0.22,0.39,0.66,0.10),11.0,true)
			draw_dashed_line(a,b,Color("#8a929c") if schematic else Style.BLUEPRINT,1.6 if schematic else 2.4,12.0 if schematic else 8.0,true)

func _draw_campaign_targets() -> void:
	if not bool(campaign_blueprint.get("visible", false)): return
	for marker in campaign_blueprint.get("engineeringMarkers",[]):
		var point:=_to_screen(marker.latlng)
		if not Rect2(Vector2(-60,-60),size+Vector2(120,120)).has_point(point):continue
		draw_rect(Rect2(point-Vector2(6,6),Vector2(12,12)),Color("#8a929c"),false,2.0)
		_draw_label(point+Vector2(11,-7),str(marker.name)+" · 轨道接口",Color("#42515c"),get_theme_default_font(),15,true)
	for target in campaign_blueprint.get("stations", []):
		var latlng: Array = target.get("latlng", [])
		if latlng.size() < 2: continue
		var point := _to_screen(latlng)
		if not Rect2(Vector2(-60, -60), size + Vector2(120, 120)).has_point(point): continue
		var radius := _blueprint_target_radius(target)
		var color := Color("#278568") if bool(target.get("built", false)) else Color("#b18032")
		draw_circle(point, radius, Color(color.r, color.g, color.b, 0.055))
		draw_arc(point, radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.62), 1.6, true)
		draw_circle(point, 4.5, Color("#fffdf7"))
		draw_circle(point, 3.0, color)
		var separate_instance:=str(target.get("stationInstanceId",""))!=str(target.get("stationComplexId",""))
		if current_zoom >= 14 and (not bool(target.get("built",false)) or separate_instance):
			var title:="目标站区 · %s" % str(target.get("name", ""))
			if separate_instance:title="%s线站体 · %s" % [str(target.get("historicalLineName",target.get("historicalLineId","本线"))),str(target.get("name","换乘站"))]
			var offset_y:=9.0
			if separate_instance:
				var siblings:Array=[];var complex_id:=str(target.get("stationComplexId",""))
				for sibling in campaign_blueprint.get("stations",[]):
					if str(sibling.get("stationComplexId",""))==complex_id:
						var sibling_id:=str(sibling.get("stationInstanceId",""))
						if not siblings.has(sibling_id):siblings.append(sibling_id)
				siblings.sort();offset_y+=float(siblings.find(str(target.get("stationInstanceId",""))))*27.0
			_draw_label(point + Vector2(9, offset_y), title, color.darkened(0.15), get_theme_default_font(), 15, false)

func _blueprint_target_radius(target: Dictionary) -> float:
	var latlng: Array = target.get("latlng", [])
	if latlng.size() < 2:return 20.0
	return maxf(20.0, float(target.get("toleranceM", 150.0)) / maxf(0.1, Geo.meters_per_pixel(float(latlng[0]), current_zoom)))

func _draw_local_basemap() -> void:
	if base_map_features.is_empty() and _base_map_thread_busy:
		_draw_fallback_grid()
		_draw_map_hint("正在读取本地道路与建筑 · 建设操作仍可使用")
	if not base_map_available:
		draw_rect(Rect2(Vector2.ZERO, size), Style.CANVAS)
		_draw_fallback_grid()
		return
	var view_half := size * 0.5 * _camera_mpp
	var visible := Rect2(_camera_local_center - view_half, view_half * 2.0).grow(80.0 * _camera_mpp)
	var inside_package := base_map_bounds.intersects(visible)
	if not base_map_draw_batches.is_empty():
		_draw_cached_local_basemap(visible, inside_package)
		return
	# The fallback uses exactly the same batching and style as async chunks.
	_prepare_basemap_draw_batches()
	_draw_cached_local_basemap(visible, inside_package)

func _draw_cached_local_basemap(visible: Rect2, inside_package: bool) -> void:
	var pixel_scale := 1.0 / _camera_mpp
	var origin := Vector2(size.x * 0.5 - _camera_local_center.x * pixel_scale, size.y * 0.5 + _camera_local_center.y * pixel_scale)
	draw_set_transform(origin, 0.0, Vector2(pixel_scale, -pixel_scale))
	var batches := base_map_draw_batches
	var water_indices: PackedInt32Array = batches.get("waterIndices", PackedInt32Array())
	var park_indices: PackedInt32Array = batches.get("parkIndices", PackedInt32Array())
	if not water_indices.is_empty(): RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), water_indices, batches.waterPoints, batches.waterColors)
	if not park_indices.is_empty(): RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), park_indices, batches.parkPoints, batches.parkColors)
	var water_outline: PackedVector2Array = batches.get("waterOutline", PackedVector2Array())
	var park_outline: PackedVector2Array = batches.get("parkOutline", PackedVector2Array())
	if not water_outline.is_empty(): draw_multiline(water_outline, Style.WATER_EDGE, _camera_mpp, false)
	if not park_outline.is_empty(): draw_multiline(park_outline, Style.PARK_EDGE, _camera_mpp, false)
	var water_lines: PackedVector2Array = batches.get("waterLines", PackedVector2Array())
	var major_lines: PackedVector2Array = batches.get("majorLines", PackedVector2Array())
	var primary_lines: PackedVector2Array = batches.get("primaryLines", PackedVector2Array())
	var secondary_lines: PackedVector2Array = batches.get("secondaryLines", PackedVector2Array())
	var local_lines: PackedVector2Array = batches.get("localLines", PackedVector2Array())
	if not water_lines.is_empty(): draw_multiline(water_lines, Style.WATER_EDGE, (0.8 if current_zoom < 14 else 1.6) * _camera_mpp, false)
	for road in [["road_local",local_lines],["road_secondary",secondary_lines],["road_primary",primary_lines],["road_major",major_lines]]:
		var kind: String = road[0]
		var lines: PackedVector2Array = road[1]
		if lines.is_empty() or not Style.road_visible(kind,current_zoom): continue
		var width: float = Style.road_width(kind,current_zoom)
		draw_multiline(lines,Style.ROAD_EDGE,(width+1.5)*_camera_mpp,false)
		draw_multiline(lines,Style.MAJOR_ROAD if kind=="road_major" else Style.ROAD,width*_camera_mpp,false)
	var building_indices: PackedInt32Array = batches.get("buildingIndices", PackedInt32Array())
	var building_outline: PackedVector2Array = batches.get("buildingOutline", PackedVector2Array())
	if not building_indices.is_empty(): RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), building_indices, batches.buildingPoints, batches.buildingColors)
	if not building_outline.is_empty(): draw_multiline(building_outline, Style.BUILDING_EDGE, 0.7 * _camera_mpp, false)
	var major_building_indices: PackedInt32Array = batches.get("majorBuildingIndices", PackedInt32Array())
	var major_building_outline: PackedVector2Array = batches.get("majorBuildingOutline", PackedVector2Array())
	if not major_building_indices.is_empty(): RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), major_building_indices, batches.majorBuildingPoints, batches.majorBuildingColors)
	if not major_building_outline.is_empty(): draw_multiline(major_building_outline, Style.LANDMARK_EDGE, 1.0 * _camera_mpp, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if current_zoom >= 13:
		var visible_road_labels: Array[Dictionary] = []
		for road_label in batches.get("roadLabels", []):
			if visible.intersects(road_label.get("bounds", Rect2())):
				var visible_label: Dictionary = road_label.duplicate()
				visible_label["screenPosition"] = _local_to_screen_cached(road_label.get("position", Vector2.ZERO))
				visible_road_labels.append(visible_label)
		_draw_road_labels(visible_road_labels, true)
	if not inside_package:
		_draw_map_hint("超出本地底图范围 · 规划仍可继续")

static func _polyline_pairs(points: PackedVector2Array, close_loop: bool = false) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.size() < 2: return result
	for index in range(points.size() - 1):
		result.append(points[index]); result.append(points[index + 1])
	if close_loop:
		result.append(points[-1]); result.append(points[0])
	return result

func _draw_fallback_grid() -> void:
	var step := 64.0
	for x in range(0, int(size.x) + 1, int(step)):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.7, 0.72, 0.72, 0.25), 1.0)
	for y in range(0, int(size.y) + 1, int(step)):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.7, 0.72, 0.72, 0.25), 1.0)

func _draw_schematic_network() -> void:
	if not show_network: return
	var station_by_id: Dictionary = {}
	var linked_route_ids: Dictionary = {}
	for station in world.get("stations", []): station_by_id[str(station.get("id", ""))] = station
	for link in world.get("trackLinks", []):
		for route_id in link.get("routeIds", []): linked_route_ids[str(route_id)] = true
	for route in world.get("routes", []):
		if linked_route_ids.has(str(route.get("id", ""))): continue
		var color := Color.from_string(str(route.get("color", "#e23f56")), Color("#e23f56"))
		if route.get("schematic", false):
			var directions: Array = route.get("directions", [])
			if not directions.is_empty():
				var ids: Array = directions[0].get("stationIds", [])
				for i in range(ids.size() - 1):
					var a: Dictionary = station_by_id.get(str(ids[i]), {})
					var b: Dictionary = station_by_id.get(str(ids[i + 1]), {})
					if a.is_empty() or b.is_empty(): continue
					var pa := _to_screen(a.get("latlng", [0, 0]))
					var pb := _to_screen(b.get("latlng", [0, 0]))
					if _segment_visible(pa, pb): draw_dashed_line(pa, pb, color, 3.0, 10.0, true)

func _draw_built_links() -> void:
	if not show_network: return
	var view_half := size * 0.5 * _camera_mpp
	var visible_local := Rect2(_camera_local_center - view_half, view_half * 2.0).grow(700.0)
	for link in world.get("trackLinks", []):
		var geometry: Dictionary = link_geometry_cache.get(str(link.get("id", "")), {})
		var local_points: Array[Vector2] = geometry.get("points", [])
		var is_preview_link := not _curve_preview.is_empty() and str(_curve_preview.get("linkId", "")) == str(link.get("id", ""))
		if is_preview_link:
			var a: Dictionary = WorldData.find_station(world, str(link.get("a", {}).get("stationId", "")))
			var b: Dictionary = WorldData.find_station(world, str(link.get("b", {}).get("stationId", "")))
			if a.is_empty() or b.is_empty(): continue
			var preview_link: Dictionary = link.duplicate(true)
			preview_link[str(_curve_preview.get("controlName", "curveA"))] = _curve_preview.get("offset", [])
			var controls := _link_control_local(preview_link, a, b)
			local_points = []
			for index in range(25): local_points.append(_bezier(controls[0], controls[1], controls[2], controls[3], float(index) / 24.0))
		if local_points.size() < 2: continue
		if not is_preview_link and not visible_local.intersects(geometry.get("bounds", Rect2())): continue
		var points := PackedVector2Array()
		for local_point in local_points: points.append(_local_to_screen(local_point))
		var p0: Vector2 = points[0]
		var p3: Vector2 = points[-1]
		if bool(link.get("schematic", false)) and not _segment_visible(p0, p3): continue
		var route_ids: Array = link.get("routeIds", [])
		var route: Dictionary = route_cache_by_id.get(str(route_ids[0]) if not route_ids.is_empty() else "", {})
		var color := Color.from_string(str(route.get("color", "#4a91e8")), Color("#4a91e8"))
		var selected_link := selected_type == "link" and str(selected_id) == str(link.get("id", ""))
		if link.get("schematic", false):
			for i in range(0, points.size() - 1, 2):
				draw_line(points[i], points[i + 1], Color("#f2bd58") if selected_link else color.darkened(0.12), 5.0 if selected_link else 2.8, true)
		else:
			var preview_tint := Color("#df5360") if is_preview_link and not curve_preview_issue.is_empty() else (Color("#f2bd58") if selected_link else color)
			draw_polyline(points, Color("#ffffff"), 10.0 if selected_link else 8.0, true)
			draw_polyline(points, preview_tint, 6.0 if selected_link or is_preview_link else 4.0, true)
			if tool == "curve" and link.get("routeIds", []).has(active_route_id):
				var a: Dictionary = WorldData.find_station(world, str(link.get("a", {}).get("stationId", "")))
				var b: Dictionary = WorldData.find_station(world, str(link.get("b", {}).get("stationId", "")))
				if not a.is_empty() and not b.is_empty():
					var controls := _link_control_local(link, a, b)
					var ca := _local_to_screen(controls[1]); var cb := _local_to_screen(controls[2])
					draw_line(p0, ca, Color(0.08, 0.35, 0.53, 0.65), 1.5, true)
					draw_line(p3, cb, Color(0.08, 0.35, 0.53, 0.65), 1.5, true)
					draw_circle(ca, 10.0, Color("#ffffff")); draw_circle(ca, 7.0, Color("#297ab7"))
					draw_circle(cb, 10.0, Color("#ffffff")); draw_circle(cb, 7.0, Color("#297ab7"))
	for edge in world.get("trackEdges", []):
		var geometry: Dictionary = link_geometry_cache.get(str(edge.get("id", "")), {})
		var local_points: Array[Vector2] = []
		for raw_point in geometry.get("points", []):
			if raw_point is Vector2: local_points.append(raw_point)
		if local_points.size() < 2 or not visible_local.intersects(geometry.get("bounds", Rect2())): continue
		var points := PackedVector2Array()
		for local_point in local_points: points.append(_local_to_screen(local_point))
		var depth := float(edge.get("depthM", -15.0))
		var faded := not show_all_depths and absf(depth - current_depth_m) > 2.5 and tool in ["track", "track_curve", "station"]
		var base_color := Color("#98a5ac") if faded else Color("#ffffff")
		var selected_link := selected_type == "link" and str(selected_id) == str(edge.get("id", ""))
		draw_polyline(points, base_color, 9.0 if selected_link else 7.0, true)
		var route_ids: Array = edge.get("routeIds", [])
		if route_ids.is_empty():
			var rail_color := Color("#7a8790") if faded else Color("#566b78")
			draw_polyline(_offset_screen_polyline(points, -2.3), rail_color, 2.2 if selected_link else 1.8, true)
			draw_polyline(_offset_screen_polyline(points, 2.3), rail_color, 2.2 if selected_link else 1.8, true)
		else:
			var lane_width := 2.2 if route_ids.size() > 1 else 3.2
			for lane_index in range(mini(3, route_ids.size())):
				var route: Dictionary = route_cache_by_id.get(str(route_ids[lane_index]), {})
				var color := Color.from_string(str(route.get("color", "#4a91e8")), Color("#4a91e8"))
				var lane_points := points
				if route_ids.size() > 1:
					lane_points = PackedVector2Array()
					var lane_offset := (float(lane_index) - float(mini(3, route_ids.size()) - 1) * 0.5) * 2.6
					for point_index in range(points.size()):
						var before: Vector2 = points[maxi(0, point_index - 1)]
						var after: Vector2 = points[mini(points.size() - 1, point_index + 1)]
						var direction := (after - before).normalized()
						lane_points.append(points[point_index] + Vector2(-direction.y, direction.x) * lane_offset)
				draw_polyline(lane_points, color.darkened(0.25) if faded else color, lane_width, true)
		var is_preview_edge := not _curve_preview.is_empty() and str(_curve_preview.get("linkId", "")) == str(edge.get("id", ""))
		if is_preview_edge:
			var preview_edge: Dictionary = edge.duplicate(true)
			preview_edge["controlA" if str(_curve_preview.get("controlName", "curveA")) == "curveA" else "controlB"] = _curve_preview.get("offset", [])
			var preview_points: PackedVector2Array = []
			for point in TrackNetwork.edge_points(preview_edge, world, geometry_ref_lat, 24): preview_points.append(_local_to_screen(Geo.local_m(point, geometry_ref_lat)))
			points = preview_points
			if points.size() >= 2:
				draw_polyline(points, Color("#ffffff"), 10.0, true)
				draw_polyline(points, Color("#df5360") if not curve_preview_issue.is_empty() else Color("#f2bd58"), 6.0, true)
		if tool == "curve" and str(edge.get("geometry", "straight")) == "bezier":
			var ends := TrackNetwork._edge_node_ids(edge, world)
			if ends.size() == 2:
				var node_a := TrackNetwork.find_node(world, ends[0]); var node_b := TrackNetwork.find_node(world, ends[1])
				if not node_a.is_empty() and not node_b.is_empty():
					var p0 := Geo.local_m(node_a.get("latlng", [0, 0]), geometry_ref_lat)
					var p3 := Geo.local_m(node_b.get("latlng", [0, 0]), geometry_ref_lat)
					var delta := p3 - p0
					var ca: Array = edge.get("controlA", [delta.x / 3.0, delta.y / 3.0]); var cb: Array = edge.get("controlB", [-delta.x / 3.0, -delta.y / 3.0])
					var ca_screen := _local_to_screen(p0 + Vector2(float(ca[0]), float(ca[1])))
					var cb_screen := _local_to_screen(p3 + Vector2(float(cb[0]), float(cb[1])))
					draw_line(_local_to_screen(p0), ca_screen, Color(0.08, 0.35, 0.53, 0.65), 1.5, true)
					draw_line(_local_to_screen(p3), cb_screen, Color(0.08, 0.35, 0.53, 0.65), 1.5, true)
					draw_circle(ca_screen, 10.0, Color("#ffffff")); draw_circle(ca_screen, 7.0, Color("#297ab7"))
					draw_circle(cb_screen, 10.0, Color("#ffffff")); draw_circle(cb_screen, 7.0, Color("#297ab7"))
		if selected_link: _draw_label(points[points.size() / 2] + Vector2(7, -8), "地下轨道 · %.0f 米" % TrackNetwork.edge_length_m(edge, world, geometry_ref_lat), Color("#243847"), get_theme_default_font(), 13, true, true)
		elif faded and current_zoom >= 14:
			_draw_label(points[points.size() / 2] + Vector2(4, -5), "深 %.0f m" % depth, Color("#52636d"), get_theme_default_font(), 10)

func _offset_screen_polyline(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size()):
		var before: Vector2 = points[maxi(0, index - 1)]
		var after: Vector2 = points[mini(points.size() - 1, index + 1)]
		var direction := (after - before).normalized()
		result.append(points[index] + Vector2(-direction.y, direction.x) * amount)
	return result

func _draw_trains_on(target: CanvasItem) -> void:
	if not show_train_display or not show_network:return
	for route_id in route_path_cache:
		var route:Dictionary=route_cache_by_id.get(str(route_id),{})
		var path:Dictionary=route_path_cache[route_id]
		for direction in path.get("presentationDirections",[]).slice(0,2):
			var geo_points:Array=[]
			for segment in direction.get("segments",[]):
				for point in segment.get("points",[]):geo_points.append(point)
			if geo_points.size()<2:continue
			var lengths:Array[float]=[];var total:=0.0
			for index in range(geo_points.size()-1):
				var piece:=Geo.local_m(geo_points[index],geometry_ref_lat).distance_to(Geo.local_m(geo_points[index+1],geometry_ref_lat));lengths.append(piece);total+=piece
			var remaining:=fposmod(presentation_seconds/maxf(18.0,total/120.0),1.0)*total
			for index in range(lengths.size()):
				if remaining>lengths[index]:remaining-=lengths[index];continue
				var a:=_to_screen(geo_points[index]);var b:=_to_screen(geo_points[index+1])
				var point:=a.lerp(b,remaining/maxf(0.01,lengths[index]));var axis:=(b-a).normalized()*8.0
				target.draw_line(point-axis,point+axis,Color.WHITE,9.0,true)
				target.draw_line(point-axis,point+axis,Color.from_string(str(route.get("color","#24745e")),Color("#24745e")),5.0,true)
				break

func _draw_station_preview_links() -> void:
	if station_preview_edges.is_empty(): return
	var tint := Color("#df5360") if not station_preview_issue.is_empty() else Color("#f2bd58")
	for local_points_variant in station_preview_edges.values():
		var local_points: Array = local_points_variant
		if local_points.size() < 2: continue
		var points := PackedVector2Array()
		for point in local_points: points.append(_local_to_screen(point))
		draw_polyline(points, Color(1.0, 1.0, 1.0, 0.92), 10.0, true)
		draw_polyline(points, tint, 6.0, true)

func _draw_stations() -> void:
	if not show_stations: return
	for station in world.get("stations", []):
		var display_station: Dictionary = station
		if not _drag_preview.is_empty() and str(_drag_preview[0]) == str(station.get("id", "")):
			display_station = station.duplicate(true)
			display_station["latlng"] = _drag_preview[1].duplicate()
		var pos := _to_screen(display_station.get("latlng", [0, 0]))
		if not Rect2(Vector2(-80, -80), size + Vector2(160, 160)).has_point(pos): continue
		var selected := str(station.get("id", "")) == selected_id and selected_type == "station"
		var bearing := deg_to_rad(float(display_station.get("heading", 90.0)) - 90.0)
		var axis := Vector2(cos(bearing), sin(bearing))
		var normal := Vector2(-axis.y, axis.x)
		var mpp := Geo.meters_per_pixel(float(display_station.get("latlng", [0,0])[0]), current_zoom)
		var half_len := float(display_station.get("lengthM", 118.788)) / mpp * 0.5
		var half_w := float(display_station.get("widthM", 20.0)) / mpp * 0.5
		var footprint := PackedVector2Array([pos - axis * half_len - normal * half_w, pos + axis * half_len - normal * half_w, pos + axis * half_len + normal * half_w, pos - axis * half_len + normal * half_w])
		if show_halls and (current_zoom >= 15 or selected):
			draw_colored_polygon(footprint, Color(0.12, 0.3, 0.48, 0.42))
			draw_polyline(PackedVector2Array([footprint[0], footprint[1], footprint[2], footprint[3], footprint[0]]), Color("#176d92"), 2.0, true)
			var rail_delta := normal * maxf(2.0, half_w * 0.3)
			draw_line(pos - axis * half_len + rail_delta, pos + axis * half_len + rail_delta, Color("#344654"), 2.0)
			draw_line(pos - axis * half_len - rail_delta, pos + axis * half_len - rail_delta, Color("#344654"), 2.0)
		var marker_color := Color("#213342")
		for route_id in station.get("routeIds", []):
			var route: Dictionary = route_cache_by_id.get(str(route_id), {})
			if not route.is_empty(): marker_color = Color.from_string(str(route.get("color", "#4a91e8")), marker_color); break
		if bool(station.get("plannedTransfer", false)):
			draw_arc(pos, 16.0, 0.0, TAU, 32, Color("#e2a747"), 2.0, true)
			draw_dashed_line(pos + Vector2(-12.0, 13.0), pos + Vector2(12.0, -13.0), Color("#e2a747"), 2.0, 3.0, true)
		draw_circle(pos, 10.5 if selected else 8.0, Color("#ffffff"))
		draw_circle(pos, 7.5 if selected else 5.5, marker_color)
		if station.get("routeIds",[]).size()>1:
			draw_circle(pos,4.0,Color.WHITE)
			draw_arc(pos,10.0,0,TAU,24,marker_color,2,true)
		if (current_zoom >= 14 or selected or station.get("existing", false) == false):
			var siblings:Array=[];var complex_id:=str(station.get("stationComplexId",""));var instance_id:=str(station.get("stationInstanceId",station.get("id","")))
			if not complex_id.is_empty():
				for sibling in world.get("stations",[]):
					if str(sibling.get("stationComplexId",""))!=complex_id:continue
					var sibling_instance:=str(sibling.get("stationInstanceId",sibling.get("id","")))
					if sibling_instance!=instance_id and not siblings.has(sibling_instance):siblings.append(sibling_instance)
			if siblings.size()>0 and current_zoom>=14:
				var ordered_instances:Array=[instance_id];ordered_instances.append_array(siblings);ordered_instances.sort()
				var body_index:=ordered_instances.find(instance_id)
				var body_offset:=Vector2(14.0,-19.0+float(body_index)*22.0)
				draw_line(pos+Vector2(4,0),pos+body_offset+Vector2(1,3),Color("#314b5a",0.72),1.2,true)
				_draw_label(pos+body_offset,"%s线 · %s站体" % [_station_line_label(station),str(station.get("name","车站"))],Color("#1b2d3b"),get_theme_default_font(),13,selected,selected)
			else:
				_draw_label(pos + Vector2(10, -9), str(station.get("name", "车站")), Color("#1b2d3b"), get_theme_default_font(), 14 if selected else 12, selected, selected)
		if bool(station.get("plannedTransfer", false)) and (selected or current_zoom >= 14):
			_draw_label(pos + Vector2(11, 13), "拟换乘", Color("#76561c"), get_theme_default_font(), 15, false)
		if tool in ["connect", "track", "track_curve"] or selected:
			var start_pos := _to_screen(WorldData.station_endpoint(display_station, "start"))
			var end_pos := _to_screen(WorldData.station_endpoint(display_station, "end"))
			draw_circle(start_pos, 9.0 if tool == "connect" else 7.0, Color("#2b9e77"))
			draw_circle(end_pos, 9.0 if tool == "connect" else 7.0, Color("#e38d3a"))
			var endpoint_hover := false
			if not hover_latlng.is_empty():
				endpoint_hover = _to_screen(hover_latlng).distance_to(start_pos) <= 44.0 or _to_screen(hover_latlng).distance_to(end_pos) <= 44.0
			var show_endpoint_names := tool in ["connect", "track", "track_curve"] and (selected or str(link_start.get("stationId", "")) == str(station.get("id", "")) or endpoint_hover)
			if show_endpoint_names:
				_draw_label(start_pos + Vector2(8, -6), "A端", Color("#145c46"), get_theme_default_font(), 12, true)
				_draw_label(end_pos + Vector2(8, -6), "B端", Color("#8c4d17"), get_theme_default_font(), 12, true)

func _station_line_label(station:Dictionary) -> String:
	var saved_name:=str(station.get("stationLineName",""))
	if not saved_name.is_empty():return saved_name
	var instance_id:=str(station.get("stationInstanceId",station.get("id","")))
	for target in campaign_blueprint.get("stations",[]):
		if str(target.get("stationInstanceId",""))==instance_id:return str(target.get("historicalLineName",target.get("historicalLineId","线路")))
	var line_id:=str(station.get("stationLineId",""))
	for route_variant in route_cache_by_id.values():
		var route:Dictionary=route_variant
		if str(route.get("historicalLineId",""))==line_id:return str(route.get("name",line_id))
	return line_id if not line_id.is_empty() else "线路未标记"
	if tool in ["track", "track_curve"]:
		for node in world.get("trackNodes", []):
			var point := _to_screen(node.get("latlng", [0, 0]))
			if not Rect2(Vector2(-16, -16), size + Vector2(32, 32)).has_point(point): continue
			draw_circle(point, 7.0, Color("#ffffff")); draw_circle(point, 4.0, Color("#2589ae"))

func _draw_draft() -> void:
	if not chapter_baseline_overlay.is_empty():
		for edge in TrackNetwork.all_physical_edges(chapter_baseline_overlay):
			var old_points := PackedVector2Array()
			for ll in TrackNetwork.edge_points(edge, chapter_baseline_overlay, geometry_ref_lat, 24): old_points.append(_to_screen(ll))
			if old_points.size() > 1:
				for index in range(old_points.size() - 1): draw_dashed_line(old_points[index], old_points[index + 1], Color(0.24, 0.31, 0.38, 0.78), 3.0, 7.0, true)
	if not assisted_preview.is_empty():
		for station in assisted_preview.get("stations",[]):
			if not WorldData.find_station(world,str(station.id)).is_empty():continue
			var point:=_to_screen(station.latlng);draw_circle(point,9,Color("#d3a351"));draw_arc(point,12,0,TAU,24,Color("#835e21"),2,true)
		for edge in assisted_preview.get("trackEdges",[]):
			if world.get("trackEdges",[]).any(func(item:Dictionary):return str(item.id)==str(edge.id)):continue
			var points:=PackedVector2Array()
			for ll in TrackNetwork.edge_points(edge,assisted_preview,geometry_ref_lat,32):points.append(_to_screen(ll))
			if points.size()>1:draw_polyline(points,Color("#c89034"),4,true)
	if not draft_station.is_empty():
		var copy: Dictionary = draft_station
		var pos := _station_screen(copy)
		var bearing := deg_to_rad(float(copy.get("heading", 90.0)) - 90.0)
		var axis := Vector2(cos(bearing), sin(bearing))
		var normal := Vector2(-axis.y, axis.x)
		var mpp := Geo.meters_per_pixel(float(copy.get("latlng", [0,0])[0]), current_zoom)
		var half_len := float(copy.get("lengthM", 118.788)) / mpp * .5
		var half_w := float(copy.get("widthM", 20.0)) / mpp * .5
		var poly := PackedVector2Array([pos-axis*half_len-normal*half_w,pos+axis*half_len-normal*half_w,pos+axis*half_len+normal*half_w,pos-axis*half_len+normal*half_w])
		var preview_color := Color(0.78, 0.2, 0.2, 0.42) if draft_conflict else Color(0.1, 0.63, 0.8, 0.35)
		draw_colored_polygon(poly, preview_color)
		draw_polyline(PackedVector2Array([poly[0],poly[1],poly[2],poly[3],poly[0]]), Color("#d33e4e") if draft_conflict else Color("#147ba0"), 3.0, true)
		draw_circle(_to_screen(WorldData.station_endpoint(copy,"start")), 6, Color("#2b9e77"))
		draw_circle(_to_screen(WorldData.station_endpoint(copy,"end")), 6, Color("#e38d3a"))
	if not link_start.is_empty() and not hover_latlng.is_empty():
		var station := WorldData.find_station(world, str(link_start.get("stationId", "")))
		if not station.is_empty():
			var start_point := _to_screen(WorldData.station_endpoint(station, str(link_start.get("side", "end"))))
			var hit := _pick(_to_screen(hover_latlng))
			if str(hit.get("type", "")) == "endpoint" and str(hit.get("id", "")) != str(link_start.get("stationId", "")):
				var target_station := WorldData.find_station(world, str(hit.get("id", "")))
				var target_geo := WorldData.station_endpoint(target_station, str(hit.get("side", "start")))
				var temp_link := {"a": link_start, "b": {"stationId": str(hit.id), "side": str(hit.side)}}
				var geo_points: Array = WorldData.track_points(temp_link, world, float(city_data.get("center", [31.23,121.47])[0]), 24)
				var points := PackedVector2Array(); for geo_point in geo_points: points.append(_to_screen(geo_point))
				if points.size() >= 2:
					draw_polyline(points, Color("#ffffff"), 9.0, true); draw_polyline(points, Color("#27aee8"), 5.0, true)
					draw_circle(_to_screen(target_geo), 12.0, Color(0.15,0.75,0.91,0.55))
			else:
				var end_point := _to_screen(hover_latlng)
				draw_dashed_line(start_point, end_point, Color("#37a6e8"), 3.0, 8.0, true)
	if draft_track_points.size()>=2:
		var points:=PackedVector2Array()
		for point in draft_track_points:points.append(_to_screen(point))
		draw_polyline(points,Color.WHITE,9.0,true)
		draw_polyline(points,Color("#c14b42") if not track_preview_conflict.is_empty() else Color("#27869d"),4.0,true)
		draw_circle(points[0],7.0,Color("#d2a24a"));draw_circle(points[-1],7.0,Color("#27869d"))
		if not track_preview_conflict.is_empty():_draw_map_hint(track_preview_conflict)
	for segment in draft_track_segments:
		var batch_points := PackedVector2Array()
		for ll in segment.get("points", []): batch_points.append(_to_screen(ll))
		if batch_points.size() > 1:
			var batch_color := Color("#c14b42") if not str(segment.get("issue", "")).is_empty() else Color("#d09b39") if bool(segment.get("reused", false)) else Color("#27869d")
			draw_polyline(batch_points, Color(1, 1, 1, 0.92), 9.0, true)
			draw_polyline(batch_points, batch_color, 5.0, true)
	if tool in ["line", "repair_route_segment"] and not _line_draft_stops().is_empty():
		var line_points := PackedVector2Array()
		for point in line_draft_points: line_points.append(_to_screen(point))
		for station_id in _line_draft_stops():
			var station := WorldData.find_station(world, station_id)
			if station.is_empty(): continue
			var point := _to_screen(station.get("latlng", [0, 0]))
			draw_circle(point, 12.0, Color("#f1bd54"))
			draw_circle(point, 7.0, Color("#254d61"))
		if line_points.size() >= 2: draw_polyline(line_points, Color("#f1bd54"), 3.0, true)
	if not _drag_preview.is_empty():
		var id := str(_drag_preview[0])
		var pos_ll: Array = _drag_preview[1]
		var station := WorldData.find_station(world, id)
		if not station.is_empty(): draw_circle(_to_screen(pos_ll), 18, Color(0.05, 0.45, 0.72, 0.3))

func _draw_view_hints() -> void:
	if not base_map_available:
		_draw_map_hint("本地城市底图未安装 · 仍可继续规划")
	if not hover_latlng.is_empty() and tool == "station":
		var p := _to_screen(hover_latlng)
		draw_circle(p, 18, Color(0.04, 0.55, 0.63, 0.22))
		draw_circle(p, 4, Color("#087b8d"))
	if tool in ["station", "track", "track_curve"]:
		_draw_map_hint("地下建设视图 · 当前深度 %.0f m · PageUp / PageDown 调整" % current_depth_m)
	if draft_conflict and not draft_station.is_empty():
		var warning := "站体与现有车站冲突 · 移动或旋转后再确认"
		var font := get_theme_default_font()
		var pos := Vector2(16, 66)
		var warning_rect := Rect2(pos - Vector2(8, 24), Vector2(font.get_string_size(warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18, 38))
		draw_rect(warning_rect, Color("#F5EEDC"))
		draw_rect(warning_rect, Color("#D9C79D"), false, 1.0, true)
		draw_string(bold_font if is_instance_valid(bold_font) else font, pos, warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#865C12"))
	if not station_preview_issue.is_empty() and not _drag_preview.is_empty():
		_draw_map_hint("移动预览无效：%s" % station_preview_issue)

func _draw_map_hint(status: String) -> void:
	var font := get_theme_default_font()
	var pos := Vector2(16, 34)
	var rect := Rect2(pos - Vector2(8, 23), Vector2(font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24, 36))
	draw_rect(rect, Color("#FFFEFA"))
	draw_rect(rect, Color("#DEDED7"), false, 1.0, true)
	draw_string(font, pos, status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#63706A"))

func _line_draft_stops() -> Array[String]:
	var controller := get_parent()
	if controller != null and controller.get("line_draft_stops") is Array:
		var values: Array[String] = []
		for id in controller.get("line_draft_stops"): values.append(str(id))
		return values
	return []

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_requested.emit()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1); accept_event(); return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, -1); accept_event(); return
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_mouse_down = true
				_press_pos = event.position
				_last_pos = event.position
				_pan_active = event.button_index != MOUSE_BUTTON_LEFT
				_drag_station_id = ""
				_drag_curve = []
				_drag_draft_station = event.button_index == MOUSE_BUTTON_LEFT and tool == "station" and not draft_station.is_empty()
				if event.button_index == MOUSE_BUTTON_LEFT:
					var hit := _pick(event.position)
					if tool == "curve" and str(hit.get("type", "")) == "curve_handle":
						_drag_curve = [str(hit.id), str(hit.side)]
					elif tool in ["select", "move_station"] and str(hit.get("type", "")) == "station" and str(hit.get("id", "")) == selected_id:
						_drag_station_id = selected_id
				accept_event()
			else:
				if _mouse_down:
					if _drag_station_id != "" and not _drag_preview.is_empty():
						station_drag_finished.emit(_drag_station_id, _drag_preview[1])
					elif not _drag_curve.is_empty() and not _curve_preview.is_empty():
						_curve_commit_pending = true
						curve_control_finished.emit(str(_drag_curve[0]), str(_drag_curve[1]), _curve_preview.offset)
					elif _drag_draft_station and _press_pos.distance_to(event.position) >= 6.0:
						pass
					elif not _pan_active and _press_pos.distance_to(event.position) < 6.0 and event.button_index == MOUSE_BUTTON_LEFT:
						var hit := _pick(event.position)
						var click_ll: Array = hit.get("latlng", _screen_to_geo(event.position))
						map_clicked.emit(click_ll, str(hit.get("type", "")), str(hit.get("id", "")), str(hit.get("side", "")), float(hit.get("t", -1.0)))
				_mouse_down = false
				_pan_active = false
				_drag_station_id = ""
				_drag_curve = []
				_drag_draft_station = false
				if not _curve_commit_pending: _curve_preview = {}
				_drag_preview.clear()
				requested_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		hover_latlng = _screen_to_geo(event.position)
		if _mouse_down:
			if _drag_draft_station and _press_pos.distance_to(event.position) > 6.0:
				draft_station["latlng"] = hover_latlng.duplicate()
				draft_station_changed.emit()
				requested_redraw()
			elif _drag_station_id != "" and _press_pos.distance_to(event.position) > 6.0:
				_drag_preview = [_drag_station_id, hover_latlng]
				station_dragged.emit(_drag_station_id, hover_latlng)
			elif not _drag_curve.is_empty() and _press_pos.distance_to(event.position) > 6.0:
				var link := _find_link(str(_drag_curve[0]))
				if not link.is_empty():
					var ref_lat := float(city_data.get("center", [31.23,121.47])[0])
					var is_a := str(_drag_curve[1]) == "curveA"
					var endpoint_geo: Array = []
					if link.has("aNodeId"):
						var ends := TrackNetwork._edge_node_ids(link, world)
						var node := TrackNetwork.find_node(world, ends[0] if is_a else ends[1]) if ends.size() == 2 else {}
						endpoint_geo = node.get("latlng", [])
					else:
						var endpoint_ref: Dictionary = link.get("a" if is_a else "b", {})
						var station := WorldData.find_station(world, str(endpoint_ref.get("stationId", "")))
						if not station.is_empty(): endpoint_geo = WorldData.station_endpoint(station, str(endpoint_ref.get("side", "end")))
					if endpoint_geo.size() < 2: return
					var endpoint_local := Geo.local_m(endpoint_geo, ref_lat)
					var cursor_local := Geo.local_m(hover_latlng, ref_lat)
					var offset := cursor_local - endpoint_local
					_curve_preview = {"linkId": str(_drag_curve[0]), "controlName": str(_drag_curve[1]), "offset": [offset.x, offset.y]}
					curve_control_previewed.emit(str(_drag_curve[0]), str(_drag_curve[1]), _curve_preview.offset)
					requested_redraw()
			elif _pan_active or _press_pos.distance_to(event.position) > 6.0 and tool == "select":
				var movement: Vector2 = event.position - _last_pos
				_pan_active = true
				var center_point: Vector2 = Geo.project(current_center, current_zoom) - movement
				current_center = Geo.unproject(center_point, current_zoom)
				_store_view()
				camera_changed.emit(current_center, current_zoom)
		_last_pos = event.position
		requested_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and tool == "station" and not draft_station.is_empty():
			draft_station["heading"] = fposmod(float(draft_station.get("heading", 90.0)) + 15.0, 360.0)
			draft_station_changed.emit()
			requested_redraw()
			accept_event()

func _zoom_at(pointer: Vector2, delta: int) -> void:
	var before := _screen_to_geo(pointer)
	current_zoom = clampi(current_zoom + delta, 3, 19)
	var after := _screen_to_geo(pointer)
	var shift := Geo.project(before, current_zoom) - Geo.project(after, current_zoom)
	current_center = Geo.unproject(Geo.project(current_center, current_zoom) + shift, current_zoom)
	_store_view()
	camera_changed.emit(current_center, current_zoom)
	requested_redraw()

func _screen_to_geo(position: Vector2) -> Array:
	var center_pixel := Geo.project(current_center, current_zoom)
	return Geo.unproject(center_pixel + position - size * .5, current_zoom)

func _to_screen(latlng: Array) -> Vector2:
	_refresh_camera_cache()
	return Geo.project(latlng, current_zoom) - _camera_center_pixel + size * .5

func _local_to_screen(position: Vector2) -> Vector2:
	_refresh_camera_cache()
	return _local_to_screen_cached(position)

func _local_to_screen_cached(position: Vector2) -> Vector2:
	return Vector2((position.x - _camera_local_center.x) / _camera_mpp + size.x * 0.5, (_camera_local_center.y - position.y) / _camera_mpp + size.y * 0.5)

func _refresh_camera_cache() -> void:
	if _camera_cache_zoom == current_zoom and _camera_cache_center == current_center and _camera_cache_size == size:
		return
	_camera_cache_zoom = current_zoom
	_camera_cache_center = current_center.duplicate()
	_camera_cache_size = size
	_camera_center_pixel = Geo.project(current_center, current_zoom)
	_camera_local_center = Geo.local_m(current_center, geometry_ref_lat)
	_camera_mpp = maxf(0.01, Geo.meters_per_pixel(float(current_center[0]), current_zoom))
	_load_visible_base_chunks()

func _station_screen(station: Dictionary) -> Vector2:
	if station.get("id", "") == selected_id and station_drag_preview_active(): return _to_screen(_drag_preview[1])
	var station_id := str(station.get("id", ""))
	if station_local_cache.has(station_id): return _local_to_screen(station_local_cache[station_id])
	return _to_screen(station.get("latlng", [0, 0]))

func station_drag_preview_active() -> bool:
	return not _drag_preview.is_empty() and str(_drag_preview[0]) == selected_id

func _pick(point: Vector2) -> Dictionary:
	if tool=="select":
		for marker in story_markers:
			if point.distance_to(_to_screen(marker.latlng)+Vector2(24,24))<=16*ui_scale:return {"type":"story_beat","id":str(marker.id),"latlng":marker.latlng,"side":""}
	endpoint_choice_candidates.clear();blueprint_choice_candidates.clear();station_choice_candidates.clear()
	# Keep the visible target ring and its click target identical. A ring click
	# selects the historical target; the construction preview still snaps to the
	# exact blueprint center, so this does not enlarge the historical tolerance.
	if tool in ["select", "station"] and bool(campaign_blueprint.get("visible", false)):
		for target in campaign_blueprint.get("stations", []):
			if bool(target.get("built", false)):continue
			# A tiny sub-pixel epsilon absorbs projection rounding at the visible rim.
			# It is far below the 20 px minimum hit target and does not change map tolerance.
			if point.distance_to(_to_screen(target.get("latlng", []))) <= _blueprint_target_radius(target) + 0.01:blueprint_choice_candidates.append(target.duplicate(true))
		if blueprint_choice_candidates.size()==1:
			var target:Dictionary=blueprint_choice_candidates[0]
			return {"type":"blueprint","id":str(target.get("id","")),"side":"","latlng":target.get("latlng",[])}
		if blueprint_choice_candidates.size()>1:return {"type":"blueprint_choice","id":"","side":""}
	endpoint_choice_candidates.clear()
	var snap_disabled := tool in ["track", "track_curve"] and Input.is_key_pressed(KEY_ALT)
	if tool in ["connect", "track", "track_curve"] and not snap_disabled:
		var snap_candidates: Array[Dictionary] = []
		for station in world.get("stations", []):
			if str(station.get("id", "")) == str(link_start.get("stationId", "")): continue
			for side in ["start", "end"]:
				var endpoint_ll := WorldData.station_endpoint(station, side)
				var endpoint_screen := _to_screen(endpoint_ll)
				var distance := point.distance_to(endpoint_screen)
				if distance <= 20.0:
					snap_candidates.append({"type": "endpoint", "id": str(station.get("id", "")), "side": side, "distance": distance, "screen": endpoint_screen, "latlng": endpoint_ll})
		if tool in ["track", "track_curve"]:
			for node in world.get("trackNodes", []):
				if not str(node.get("stationId", "")).is_empty(): continue
				var node_pos := _to_screen(node.get("latlng", [0, 0]))
				var distance := point.distance_to(node_pos)
				if distance <= 20.0:
					snap_candidates.append({"type": "track_node", "id": str(node.get("id", "")), "side": "", "distance": distance, "screen": node_pos, "latlng": node.get("latlng", []).duplicate()})
		snap_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("distance", INF)) < float(b.get("distance", INF)))
		if not snap_candidates.is_empty():
			if snap_candidates.size() > 1 and float(snap_candidates[1].distance) - float(snap_candidates[0].distance) <= 2.0 and (snap_candidates[0].screen as Vector2).distance_to(snap_candidates[1].screen as Vector2) <= 8.0:
				endpoint_choice_candidates = [snap_candidates[0].duplicate(true), snap_candidates[1].duplicate(true)]
				return {"type": "endpoint_choice", "id": "", "side": ""}
			var best_snap: Dictionary = snap_candidates[0].duplicate(true)
			best_snap.erase("distance"); best_snap.erase("screen")
			return best_snap
	for station in world.get("stations", []):
		var center := _station_screen(station)
		var angle := deg_to_rad(float(station.get("heading", 90.0)))
		var along := Vector2(sin(angle), -cos(angle))
		var across := Vector2(cos(angle), sin(angle))
		var local := point - center
		var longitudinal_limit := float(station.get("lengthM", 118.8)) * 0.5 / _camera_mpp + 10.0
		var lateral_limit := float(station.get("widthM", 20.0)) * 0.5 / _camera_mpp + 10.0
		if absf(local.dot(along)) <= longitudinal_limit and absf(local.dot(across)) <= lateral_limit:
			station_choice_candidates.append({"type":"station","id":str(station.get("id","")),"side":"","screen":center})
	if station_choice_candidates.size()==1:return station_choice_candidates[0]
	if station_choice_candidates.size()>1:return {"type":"station_choice","id":"","side":""}
	if tool == "curve":
		var ref_lat := float(city_data.get("center", [31.23,121.47])[0])
		var best_handle: Dictionary = {}
		var handle_distance := 13.0
		for link in world.get("trackLinks", []):
			if not link.get("routeIds", []).has(active_route_id) or link.get("schematic", false): continue
			var controls := WorldData.link_control_points(link, world, ref_lat)
			if controls.size() != 4: continue
			for control_name in ["curveA", "curveB"]:
				var control_point := controls[1] if control_name == "curveA" else controls[2]
				var distance := point.distance_to(_to_screen(Geo.from_local(control_point, ref_lat)))
				if distance <= handle_distance:
					handle_distance = distance
					best_handle = {"type": "curve_handle", "id": str(link.id), "side": control_name}
		if not best_handle.is_empty(): return best_handle
		for edge in world.get("trackEdges", []):
			if str(edge.get("geometry", "straight")) != "bezier": continue
			var ends := TrackNetwork._edge_node_ids(edge, world)
			if ends.size() != 2: continue
			var node_a := TrackNetwork.find_node(world, ends[0])
			var node_b := TrackNetwork.find_node(world, ends[1])
			if node_a.is_empty() or node_b.is_empty(): continue
			var p0 := Geo.local_m(node_a.get("latlng", [0, 0]), ref_lat)
			var p3 := Geo.local_m(node_b.get("latlng", [0, 0]), ref_lat)
			var delta := p3 - p0
			var ca: Array = edge.get("controlA", [delta.x / 3.0, delta.y / 3.0])
			var cb: Array = edge.get("controlB", [-delta.x / 3.0, -delta.y / 3.0])
			for control_name in ["curveA", "curveB"]:
				var cp := p0 + Vector2(float(ca[0]), float(ca[1])) if control_name == "curveA" else p3 + Vector2(float(cb[0]), float(cb[1]))
				var distance := point.distance_to(_to_screen(Geo.from_local(cp, ref_lat)))
				if distance <= handle_distance:
					handle_distance = distance
					best_handle = {"type": "curve_handle", "id": str(edge.get("id", "")), "side": control_name}
		if not best_handle.is_empty(): return best_handle
	var can_snap_edge := tool in ["select", "delete", "curve"] or tool == "track" and not snap_disabled or tool == "track_curve" and (track_start_ref.is_empty() or not track_control_latlng.is_empty()) and not snap_disabled
	if can_snap_edge:
		var nearest_link: Dictionary = {}
		var nearest_distance := 12.0
		for link in TrackNetwork.all_physical_edges(world):
			var geometry: Dictionary = link_geometry_cache.get(str(link.get("id", "")), {})
			var local_points: Array[Vector2] = geometry.get("points", [])
			if local_points.size() < 2: continue
			var previous := _local_to_screen(local_points[0])
			for index in range(1, local_points.size()):
				var current := _local_to_screen(local_points[index])
				var closest := Geometry2D.get_closest_point_to_segment(point, previous, current)
				var distance := point.distance_to(closest)
				if distance <= nearest_distance:
					nearest_distance = distance
					var segment_fraction := 0.0
					var segment := current - previous
					if segment.length_squared() > 0.001: segment_fraction = clampf((closest - previous).dot(segment) / segment.length_squared(), 0.0, 1.0)
					var snapped_t := (float(index - 1) + segment_fraction) / float(local_points.size() - 1)
					var edge_type := "track_edge" if tool in ["track", "track_curve"] else "link"
					nearest_link = {"type": edge_type, "id": str(link.get("id", "")), "side": "", "t": snapped_t, "latlng": _screen_to_geo(closest)}
				previous = current
		if not nearest_link.is_empty(): return nearest_link
	return {}

func _find_link(link_id: String) -> Dictionary:
	for link in TrackNetwork.all_physical_edges(world):
		if str(link.get("id", "")) == link_id: return link
	return {}

func _station_drag_preview_update(station_id: String, latlng: Array) -> void:
	_drag_preview = [station_id, latlng]
	requested_redraw()

func _store_view() -> void:
	if world.is_empty(): return
	if not world.has("view"): world.view = {}
	world.view["center"] = current_center.duplicate()
	world.view["zoom"] = current_zoom

func _segment_visible(a: Vector2, b: Vector2) -> bool:
	var bounds := Rect2(Vector2(-120, -120), size + Vector2(240, 240))
	return bounds.has_point(a) or bounds.has_point(b) or bounds.intersects(Rect2(a, b - a).abs())

func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t

static func _road_angle(points: PackedVector2Array) -> float:
	if points.size()<2: return 0.0
	var mid := points.size()/2
	var tangent := points[mini(mid+1,points.size()-1)]-points[maxi(mid-1,0)]
	var angle := Vector2(tangent.x,-tangent.y).angle()
	if angle>PI/2: angle-=PI
	if angle< -PI/2: angle+=PI
	return angle

func _draw_road_labels(labels: Array[Dictionary], positions_are_screen: bool = false) -> void:
	for road_label in labels:
		if not Style.label_visible(str(road_label.get("kind","")),current_zoom): continue
		if not show_road_names and str(road_label.get("kind",""))!="building_major": continue
		var candidate: Dictionary = road_label if positions_are_screen else road_label.duplicate()
		candidate["screenPosition"] = road_label.get("screenPosition",road_label.get("position",Vector2.ZERO)) if positions_are_screen else _local_to_screen_cached(road_label.get("position",Vector2.ZERO))
		_basemap_labels.append(candidate)

func _draw_queued_basemap_labels() -> void:
	if size.x<24 or size.y<24:return
	var landmark_positions:Array[Vector2]=[]
	# Roads have label priority without exhausting the whole label budget before
	# any hospital, school or public building gets a chance to appear.
	var roads:Array[Dictionary]=[];var landmarks:Array[Dictionary]=[]
	for entry in _basemap_labels:
		if str(entry.get("kind",""))=="building_major":landmarks.append(entry)
		else:roads.append(entry)
	var ordered:=deduplicate_road_labels(roads,220.0*ui_scale,48,true)
	ordered.append_array(deduplicate_road_labels(landmarks,220.0*ui_scale,36,true))
	for entry in ordered:
		var pos: Vector2=entry.screenPosition
		if not Rect2(Vector2(12,12),size-Vector2(24,24)).has_point(pos): continue
		var is_building := str(entry.get("kind",""))=="building_major"
		if is_building:
			var text:=str(entry.name)
			if not ["学校","小学","中学","大学","学院","医院","机场","火车站","博物馆","图书馆","体育馆","市政府"].any(func(word:String):return text.contains(word)):continue
			if landmark_positions.size()>=(20 if current_zoom>=17 else 12):continue
			if landmark_positions.any(func(other:Vector2):return other.distance_to(pos)<140*ui_scale):continue
			if _draw_label(pos,text,Style.LANDMARK_TEXT,get_theme_default_font(),12,false,false):landmark_positions.append(pos)
			continue
		var font := get_theme_default_font()
		var pixels := maxi(12,roundi(12*ui_scale))
		var text := str(entry.name)
		var measured := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels)
		var angle := float(entry.get("angle",0))
		var rect := Rect2(pos-Vector2(measured.x*absf(cos(angle))+pixels*absf(sin(angle)),measured.x*absf(sin(angle))+pixels*absf(cos(angle)))*0.5-Vector2(3,3),Vector2(measured.x*absf(cos(angle))+pixels*absf(sin(angle)),measured.x*absf(sin(angle))+pixels*absf(cos(angle)))+Vector2(6,6))
		if _label_rects.any(func(occupied:Rect2):return occupied.intersects(rect)): continue
		_label_rects.append(rect)
		draw_set_transform(pos,angle)
		var origin := Vector2(-measured.x/2,pixels*0.35)
		draw_string_outline(font,origin,text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,3,Color.WHITE)
		draw_string(font,origin,text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,Style.ROAD_TEXT)
		draw_set_transform(Vector2.ZERO)

func _draw_story_markers() -> void:
	if size.x<24 or size.y<24:return
	for marker in story_markers:
		var pos := _to_screen(marker.latlng)+Vector2(24,24)
		if not Rect2(Vector2(12,12),size-Vector2(24,24)).has_point(pos): continue
		draw_circle(pos,12*ui_scale,Color.WHITE)
		draw_arc(pos,12*ui_scale,0,TAU,24,Color("#81718f") if bool(marker.read) else Color("#925324"),2,true)
		draw_string(get_theme_default_font(),pos+Vector2(-7,5)*ui_scale,"史",HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(14*ui_scale),Color("#694925"))

static func deduplicate_road_labels(labels: Array[Dictionary], minimum_spacing_px: float = 220.0, maximum_labels: int = 72, already_ordered: bool = false) -> Array[Dictionary]:
	var ordered := labels if already_ordered else labels.duplicate()
	if not already_ordered:
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("priority", 0)) > int(b.get("priority", 0))
		)
	var accepted: Array[Dictionary] = []
	var accepted_positions_by_name: Dictionary = {}
	for road_label in ordered:
		var road_name := str(road_label.get("name", "")).strip_edges()
		if road_name.is_empty(): continue
		var position: Vector2 = road_label.get("screenPosition", road_label.get("position", Vector2.ZERO))
		var existing_positions: Array = accepted_positions_by_name.get(road_name, [])
		var too_close := false
		for existing_position in existing_positions:
			if (existing_position as Vector2).distance_to(position) < minimum_spacing_px:
				too_close = true
				break
		if too_close: continue
		accepted.append(road_label)
		existing_positions.append(position)
		accepted_positions_by_name[road_name] = existing_positions
		if accepted.size() >= maxi(1, maximum_labels): break
	return accepted

static func _road_label_priority(kind: String) -> int:
	match kind:
		"building_major": return 2
		"road_major": return 5
		"road_primary": return 4
		"road_secondary": return 3
		"road_local": return 1
	return 0

func _draw_label(position: Vector2, text: String, color: Color, font: Font, font_size: int, force: bool = false, bold: bool = false) -> bool:
	var display_font: Font = bold_font if bold and is_instance_valid(bold_font) else font
	var size := maxi(14, roundi(float(font_size) * ui_scale))
	var measured := display_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var rect := Rect2(position + Vector2(-5, -size - 4), Vector2(measured.x + 10, size + 9))
	if not force:
		for occupied in _label_rects:
			if rect.intersects(occupied): return false
	_label_rects.append(rect)
	draw_rect(rect, Color(1, 1, 1, 0.94 if force else 0.88))
	draw_string(display_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: requested_redraw()
