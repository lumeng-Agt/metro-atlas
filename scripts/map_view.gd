class_name MapView
extends Control

signal map_clicked(latlng: Array, hit_type: String, hit_id: String, side: String)
signal station_dragged(station_id: String, latlng: Array)
signal station_drag_finished(station_id: String, latlng: Array)
signal curve_control_finished(link_id: String, control_name: String, offset_m: Array)
signal camera_changed(center: Array, zoom: int)
signal cancel_requested
signal draft_station_changed

const OSM_URL := "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
const TILE_CACHE := "user://tile_cache"
const OSM_BLOCKED_TILE_SHA256 := "b02c44252dac5a5e820ecef1e9bf9200e9407c042df668a466a1aa81a9ecca7a"
const MAX_CONCURRENT := 4
const PALETTE := {"housing": Color("#e57272"), "employment": Color("#55a4ed"), "education": Color("#b585e8"), "health": Color("#ed8b9b"), "hub": Color("#3dbba7"), "commerce": Color("#edaf57"), "culture": Color("#4abc91"), "service": Color("#edaf57")}

var city_data: Dictionary = {}
var world: Dictionary = {}
var selected_id := ""
var selected_type := ""
var active_route_id := ""
var task_origin: Array = []
var task_destination: Array = []
var task_origin_name := ""
var task_destination_name := ""
var task_origin_id := ""
var task_destination_id := ""
var task_recommended_latlng: Array = []
var task_coverage_visible := false
var focus_demand_ids: Array[String] = []
var filter_demand_to_task := false
var clean_map_style := true
var bold_font: Font
var ui_scale := 1.0
var tool := "select"
var hover_latlng: Array = []
var draft_station: Dictionary = {}
var link_start: Dictionary = {}
var show_demand := true
var show_network := true
var show_stations := true
var show_halls := true
var allow_network_tiles := true
var current_center: Array = [31.2304, 121.4737]
var current_zoom := 13
var _tile_textures: Dictionary = {}
var _tile_expiry: Dictionary = {}
var _tile_queue: Array[Dictionary] = []
var _queued_tiles: Dictionary = {}
var _requests: Array[HTTPRequest] = []
var _active_request_by_key: Dictionary = {}
var _requested: Dictionary = {}
var _mouse_down := false
var _pan_active := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _drag_station_id := ""
var _drag_preview: Array = []
var _drag_curve: Array = []
var _curve_preview: Dictionary = {}
var _tile_redraw_pending := false
var _network_unavailable := false
var _network_blocked := false
var draft_conflict := false
var _drag_draft_station := false
var _label_rects: Array[Rect2] = []
var _tile_valid_count := 0
var _tile_placeholder_rejections := 0
var _https_proxy_host := ""
var _https_proxy_port := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(false)
	var proxy := _detect_system_https_proxy()
	_https_proxy_host = str(proxy.get("host", ""))
	_https_proxy_port = int(proxy.get("port", 0))

func set_context(city: Dictionary, state: Dictionary) -> void:
	city_data = city
	world = state
	current_center = state.get("view", {}).get("center", city.get("center", [31.2304, 121.4737])).duplicate()
	current_zoom = int(state.get("view", {}).get("zoom", city.get("zoom", 12)))
	requested_redraw()

func set_world(state: Dictionary) -> void:
	world = state
	requested_redraw()

func center_on(latlng: Array, zoom_level: int = -1) -> void:
	current_center = [float(latlng[0]), float(latlng[1])]
	if zoom_level >= 0: current_zoom = clampi(zoom_level, 3, 19)
	_store_view()
	requested_redraw()
	camera_changed.emit(current_center, current_zoom)

func requested_redraw() -> void:
	queue_redraw()
	if not _tile_redraw_pending:
		_tile_redraw_pending = true
		call_deferred("_queue_visible_tiles")

func _draw() -> void:
	_label_rects.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#e8e5dd"))
	_draw_tiles()
	_draw_built_links()
	_draw_trains()
	_draw_demand()
	_draw_stations()
	_draw_task_pair()
	_draw_draft()
	_draw_view_hints()

func _draw_tiles() -> void:
	var bounds := _visible_tile_bounds()
	for y in range(bounds.top, bounds.bottom + 1):
		for x in range(bounds.left, bounds.right + 1):
			var key := "%d/%d/%d" % [current_zoom, x, y]
			if _tile_textures.has(key):
				var pos := _tile_screen_pos(x, y)
				var tile_rect := Rect2(pos, Vector2(256, 256))
				draw_texture_rect(_tile_textures[key], tile_rect, false)
				if clean_map_style:
					# Map labels are baked into raster tiles; soften the whole tile while keeping streets readable.
					draw_rect(tile_rect, Color(0.98, 0.97, 0.93, 0.40))
			else:
				var pos := _tile_screen_pos(x, y)
				draw_rect(Rect2(pos, Vector2(256, 256)), Color("#eeece7"))
				draw_rect(Rect2(pos, Vector2(256, 256)), Color("#ddd9d0"), false, 1.0)
	if _tile_textures.is_empty():
		_draw_fallback_grid()

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
	var stations: Dictionary = {}
	var routes: Dictionary = {}
	for station in world.get("stations", []): stations[str(station.get("id", ""))] = station
	for route in world.get("routes", []): routes[str(route.get("id", ""))] = route
	for link in world.get("trackLinks", []):
		var a_ref: Dictionary = link.get("a", {})
		var b_ref: Dictionary = link.get("b", {})
		var a: Dictionary = stations.get(str(a_ref.get("stationId", "")), {})
		var b: Dictionary = stations.get(str(b_ref.get("stationId", "")), {})
		if a.is_empty() or b.is_empty(): continue
		var draw_link: Dictionary = link
		if not _curve_preview.is_empty() and str(_curve_preview.get("linkId", "")) == str(link.get("id", "")):
			draw_link = link.duplicate(true)
			draw_link[str(_curve_preview.get("controlName", "curveA"))] = _curve_preview.get("offset", [])
		var ref_lat := float(city_data.get("center", [31.23,121.47])[0])
		var geo_points: Array = WorldData.track_points(draw_link, world, ref_lat, 24)
		if link.get("schematic", false): geo_points = [a.get("latlng", [0,0]), b.get("latlng", [0,0])]
		if geo_points.size() < 2: continue
		var points := PackedVector2Array()
		for geo_point in geo_points: points.append(_to_screen(geo_point))
		var p0: Vector2 = points[0]
		var p3: Vector2 = points[-1]
		if not _segment_visible(p0, p3): continue
		var route_ids: Array = link.get("routeIds", [])
		var route: Dictionary = routes.get(str(route_ids[0]) if not route_ids.is_empty() else "", {})
		var color := Color.from_string(str(route.get("color", "#4a91e8")), Color("#4a91e8"))
		var selected_link := selected_type == "link" and str(selected_id) == str(link.get("id", ""))
		if link.get("schematic", false):
			for i in range(0, points.size() - 1, 2):
				draw_line(points[i], points[i + 1], Color("#f2bd58") if selected_link else color.darkened(0.12), 5.0 if selected_link else 2.8, true)
		else:
			draw_polyline(points, Color("#ffffff"), 10.0 if selected_link else 8.0, true)
			draw_polyline(points, Color("#f2bd58") if selected_link else color, 6.0 if selected_link else 4.0, true)
			if tool == "curve" and link.get("routeIds", []).has(active_route_id):
				var controls := WorldData.link_control_points(draw_link, world, ref_lat)
				if controls.size() == 4:
					var ca := _to_screen(Geo.from_local(controls[1], ref_lat)); var cb := _to_screen(Geo.from_local(controls[2], ref_lat))
					draw_line(p0, ca, Color(0.08, 0.35, 0.53, 0.65), 1.5, true)
					draw_line(p3, cb, Color(0.08, 0.35, 0.53, 0.65), 1.5, true)
					draw_circle(ca, 10.0, Color("#ffffff")); draw_circle(ca, 7.0, Color("#297ab7"))
					draw_circle(cb, 10.0, Color("#ffffff")); draw_circle(cb, 7.0, Color("#297ab7"))

func _draw_trains() -> void:
	if current_zoom < 11 or not show_network: return
	var minute := float(world.get("simulation", {}).get("minute", 420))
	var ref_lat := float(city_data.get("center", [31.23,121.47])[0])
	var total_trains := 0
	for route in world.get("routes", []):
		if not route.get("open", false): continue
		var stop_ids: Array = route.get("stationOrder", [])
		var directions: Array = route.get("directions", [])
		if not directions.is_empty():
			var first_direction: Array = directions[0].get("stationIds", [])
			if first_direction.size() >= 2: stop_ids = first_direction
		if stop_ids.size() < 2: continue
		var path: Array[Dictionary] = []
		var route_length := 0.0
		for i in range(stop_ids.size() - 1):
			var from_id := str(stop_ids[i]); var to_id := str(stop_ids[i+1])
			var link: Dictionary = {}
			for candidate in world.get("trackLinks", []):
				if not candidate.get("routeIds", []).has(str(route.get("id", ""))): continue
				var a_id := str(candidate.get("a", {}).get("stationId", "")); var b_id := str(candidate.get("b", {}).get("stationId", ""))
				if (a_id == from_id and b_id == to_id) or (a_id == to_id and b_id == from_id): link = candidate; break
			if link.is_empty(): continue
			var length := WorldData.track_length_m(link, world, ref_lat)
			if length <= 0.0: continue
			path.append({"link": link, "from": from_id, "to": to_id, "length": length})
			route_length += length
		if path.is_empty() or route_length <= 0.0: continue
		var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
		var trip_minutes := route_length / maxf(1.0, float(profile.get("maxSpeedKmh", 80))) * 60.0 * 1.18 + float(stop_ids.size()) * 0.5
		var train_count := mini(8, maxi(1, int(ceil(trip_minutes / maxf(1.0, float(route.get("headway", 3)))))))
		var color := Color.from_string(str(route.get("color", "#397fc5")), Color("#397fc5"))
		for train_index in range(train_count):
			if total_trains >= 160: return
			var traveled := fposmod(minute / maxf(1.0, trip_minutes) + float(train_index) / float(train_count), 1.0) * route_length
			var train_pos := Vector2.ZERO
			var train_direction := Vector2.RIGHT
			for step in path:
				var step_length := float(step.length)
				if traveled > step_length:
					traveled -= step_length
					continue
				var points: Array = []
				if step.link.get("schematic", false):
					var from_station := WorldData.find_station(world, str(step.from))
					var to_station := WorldData.find_station(world, str(step.to))
					if not from_station.is_empty() and not to_station.is_empty(): points = [from_station.get("latlng", [0,0]), to_station.get("latlng", [0,0])]
				else:
					points = WorldData.track_points(step.link, world, ref_lat, 24)
					var link_a_id := str(step.link.get("a", {}).get("stationId", ""))
					if link_a_id != str(step.from): points.reverse()
				if points.size() < 2: break
				var segment_lengths: Array[float] = []
				var poly_length := 0.0
				for pindex in range(points.size() - 1):
					var local_a := Geo.local_m(points[pindex], ref_lat); var local_b := Geo.local_m(points[pindex+1], ref_lat)
					var piece := local_a.distance_to(local_b)
					segment_lengths.append(piece); poly_length += piece
				var curve_target := traveled / maxf(1.0, step_length) * poly_length
				for pindex in range(segment_lengths.size()):
					if curve_target > segment_lengths[pindex]:
						curve_target -= segment_lengths[pindex]
						continue
					var from_screen := _to_screen(points[pindex]); var to_screen := _to_screen(points[pindex+1])
					var fraction := curve_target / maxf(0.01, segment_lengths[pindex])
					train_pos = from_screen.lerp(to_screen, fraction)
					train_direction = (to_screen - from_screen).normalized()
					break
				break
			var half := train_direction * 7.0
			draw_line(train_pos - half, train_pos + half, Color("#ffffff"), 8.0, true)
			draw_line(train_pos - half, train_pos + half, color.lightened(0.18), 5.0, true)
			draw_circle(train_pos, 2.0, Color("#fff5d5"))
			total_trains += 1

func _draw_demand() -> void:
	if not show_demand: return
	var font := get_theme_default_font()
	for demand in city_data.get("demand", []):
		var demand_id := str(demand.get("id", ""))
		var selected := demand_id == selected_id and selected_type == "demand"
		if filter_demand_to_task and focus_demand_ids.has(demand_id): continue
		if filter_demand_to_task and not focus_demand_ids.has(demand_id) and not selected: continue
		var pos := _to_screen(demand.get("latlng", [0, 0]))
		if not Rect2(Vector2(-25, -25), size + Vector2(50, 50)).has_point(pos): continue
		var d_type := str(demand.get("type", "commerce"))
		var color: Color = PALETTE.get(d_type, PALETTE.get("service"))
		var radius := 5.0 if current_zoom < 14 else 7.0
		_draw_demand_symbol(pos, radius, d_type, color)
		if current_zoom >= 14 or selected:
			_draw_label(pos + Vector2(9, 3), str(demand.get("name", "需求点")), Color("#263746"), font, 14 if selected else 12, selected, selected)

func _draw_demand_symbol(pos: Vector2, radius: float, kind: String, color: Color) -> void:
	draw_circle(pos, radius + 3.0, Color(1, 1, 1, 0.96))
	match kind:
		"housing": draw_circle(pos, radius, color)
		"employment": draw_rect(Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), color)
		"education": draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -radius-1), pos + Vector2(radius+1,0), pos+Vector2(0,radius+1), pos+Vector2(-radius-1,0)]), color)
		"health":
			draw_circle(pos, radius + 1.0, color)
			draw_line(pos - Vector2(radius * .55, 0), pos + Vector2(radius * .55, 0), Color.WHITE, 2.4, true)
			draw_line(pos - Vector2(0, radius * .55), pos + Vector2(0, radius * .55), Color.WHITE, 2.4, true)
		"hub":
			draw_circle(pos, radius + 1.0, color)
			draw_arc(pos, radius * .58, 0.0, TAU, 16, Color.WHITE, 1.5, true)
		"commerce":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0,-radius-1), pos + Vector2(radius+1,radius), pos + Vector2(-radius-1,radius)]), color)
		_:
			var points := PackedVector2Array()
			for index in range(6): points.append(pos + Vector2.from_angle(TAU * float(index) / 6.0) * (radius + 1.0))
			draw_colored_polygon(points, color)

func _draw_stations() -> void:
	if not show_stations: return
	for station in world.get("stations", []):
		var pos := _station_screen(station)
		if not Rect2(Vector2(-80, -80), size + Vector2(160, 160)).has_point(pos): continue
		var bearing := deg_to_rad(float(station.get("heading", 90.0)) - 90.0)
		var axis := Vector2(cos(bearing), sin(bearing))
		var normal := Vector2(-axis.y, axis.x)
		var mpp := Geo.meters_per_pixel(float(station.get("latlng", [0,0])[0]), current_zoom)
		var half_len := float(station.get("lengthM", 118.788)) / mpp * 0.5
		var half_w := float(station.get("widthM", 20.0)) / mpp * 0.5
		var footprint := PackedVector2Array([pos - axis * half_len - normal * half_w, pos + axis * half_len - normal * half_w, pos + axis * half_len + normal * half_w, pos - axis * half_len + normal * half_w])
		if show_halls and current_zoom >= 13:
			draw_colored_polygon(footprint, Color(0.12, 0.3, 0.48, 0.42))
			draw_polyline(PackedVector2Array([footprint[0], footprint[1], footprint[2], footprint[3], footprint[0]]), Color("#176d92"), 2.0, true)
			var rail_delta := normal * maxf(2.0, half_w * 0.3)
			draw_line(pos - axis * half_len + rail_delta, pos + axis * half_len + rail_delta, Color("#344654"), 2.0)
			draw_line(pos - axis * half_len - rail_delta, pos + axis * half_len - rail_delta, Color("#344654"), 2.0)
		var selected := str(station.get("id", "")) == selected_id and selected_type == "station"
		var marker_color := Color("#213342")
		for route_id in station.get("routeIds", []):
			var route := WorldData.find_route(world, str(route_id))
			if not route.is_empty(): marker_color = Color.from_string(str(route.get("color", "#4a91e8")), marker_color); break
		draw_circle(pos, 10.5 if selected else 8.0, Color("#ffffff"))
		draw_circle(pos, 7.5 if selected else 5.5, marker_color)
		if current_zoom >= 14 or selected or station.get("existing", false) == false:
			_draw_label(pos + Vector2(10, -9), str(station.get("name", "车站")), Color("#1b2d3b"), get_theme_default_font(), 14 if selected else 12, selected, selected)
		if tool == "connect" or selected:
			var start_pos := _to_screen(WorldData.station_endpoint(station, "start"))
			var end_pos := _to_screen(WorldData.station_endpoint(station, "end"))
			draw_circle(start_pos, 9.0 if tool == "connect" else 7.0, Color("#2b9e77"))
			draw_circle(end_pos, 9.0 if tool == "connect" else 7.0, Color("#e38d3a"))
			var endpoint_hover := false
			if not hover_latlng.is_empty():
				endpoint_hover = _to_screen(hover_latlng).distance_to(start_pos) <= 44.0 or _to_screen(hover_latlng).distance_to(end_pos) <= 44.0
			var show_endpoint_names := tool == "connect" and (selected or str(link_start.get("stationId", "")) == str(station.get("id", "")) or endpoint_hover)
			if show_endpoint_names:
				_draw_label(start_pos + Vector2(8, -6), "A端", Color("#145c46"), get_theme_default_font(), 12, true)
				_draw_label(end_pos + Vector2(8, -6), "B端", Color("#8c4d17"), get_theme_default_font(), 12, true)

func _draw_task_pair() -> void:
	if task_origin.is_empty() or task_destination.is_empty(): return
	var a := _to_screen(task_origin)
	var b := _to_screen(task_destination)
	if task_coverage_visible:
		for anchor in [a, b]:
			var anchor_latlng: Array = task_origin if anchor == a else task_destination
			var radius := 800.0 / maxf(0.1, Geo.meters_per_pixel(float(anchor_latlng[0]), current_zoom))
			draw_circle(anchor, radius, Color(0.19, 0.70, 0.56, 0.045))
			draw_arc(anchor, radius, 0.0, TAU, 64, Color(0.20, 0.75, 0.59, 0.34), 1.4, true)
	if not task_recommended_latlng.is_empty():
		var recommendation := _to_screen(task_recommended_latlng)
		draw_circle(recommendation, 15.0, Color(0.20, 0.75, 0.59, 0.20))
		draw_arc(recommendation, 15.0, 0.0, TAU, 32, Color("#217e68"), 2.0, true)
		draw_circle(recommendation, 4.0, Color("#217e68"))
	draw_dashed_line(a, b, Color("#e28b43"), 3.0, 9.0, true)
	var direction := (b-a).normalized()
	var tip := a.lerp(b, 0.58)
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([tip + direction*9.0, tip - direction*5.0 + normal*6.0, tip - direction*5.0 - normal*6.0]), Color("#e28b43"))
	_draw_label((a + b) * 0.5 + Vector2(0, -13), "出行方向 · 不是轨道建议", Color("#71481e"), get_theme_default_font(), 11, true)
	for data in [[a, "A 起点", task_origin_name, Color("#e16b5f")], [b, "B 终点", task_destination_name, Color("#437fd6")]]:
		var pos: Vector2 = data[0]
		draw_circle(pos, 18, Color(1,1,1,0.9))
		draw_circle(pos, 13, data[3])
		draw_circle(pos, 4, Color.WHITE)
		_draw_label(pos + Vector2(20, -8), "%s · %s" % [data[1], data[2]], Color("#192837"), get_theme_default_font(), 14, true, true)

func _draw_draft() -> void:
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
	if not _drag_preview.is_empty():
		var id := str(_drag_preview[0])
		var pos_ll: Array = _drag_preview[1]
		var station := WorldData.find_station(world, id)
		if not station.is_empty(): draw_circle(_to_screen(pos_ll), 18, Color(0.05, 0.45, 0.72, 0.3))

func _draw_view_hints() -> void:
	if _tile_textures.is_empty():
		var status := "地图瓦片加载中…"
		if _network_blocked:
			status = "底图服务拒绝请求 · 仍可继续规划和保存"
		elif _network_unavailable:
			status = "底图暂不可用 · 仍可继续规划和保存"
		var font := get_theme_default_font()
		var pos := Vector2(16, 34)
		var rect := Rect2(pos - Vector2(8, 23), Vector2(font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18, 32))
		draw_rect(rect, Color("#182936"))
		draw_string(font, pos, status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e7edf0"))
	if not hover_latlng.is_empty() and tool == "station":
		var p := _to_screen(hover_latlng)
		draw_circle(p, 18, Color(0.04, 0.55, 0.63, 0.22))
		draw_circle(p, 4, Color("#087b8d"))
	if draft_conflict and not draft_station.is_empty():
		var warning := "站体与现有车站冲突 · 移动或旋转后再确认"
		var font := get_theme_default_font()
		var pos := Vector2(16, 66)
		draw_rect(Rect2(pos - Vector2(8, 24), Vector2(font.get_string_size(warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18, 38)), Color("#55252a"))
		draw_string(bold_font if is_instance_valid(bold_font) else font, pos, warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

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
					elif tool == "select" and str(hit.get("type", "")) == "station" and str(hit.get("id", "")) == selected_id:
						_drag_station_id = selected_id
				accept_event()
			else:
				if _mouse_down:
					if _drag_station_id != "" and not _drag_preview.is_empty():
						station_drag_finished.emit(_drag_station_id, _drag_preview[1])
					elif not _drag_curve.is_empty() and not _curve_preview.is_empty():
						curve_control_finished.emit(str(_drag_curve[0]), str(_drag_curve[1]), _curve_preview.offset)
					elif _drag_draft_station and _press_pos.distance_to(event.position) >= 6.0:
						pass
					elif not _pan_active and _press_pos.distance_to(event.position) < 6.0 and event.button_index == MOUSE_BUTTON_LEFT:
						var click_ll := _screen_to_geo(event.position)
						var hit := _pick(event.position)
						map_clicked.emit(click_ll, str(hit.get("type", "")), str(hit.get("id", "")), str(hit.get("side", "")))
				_mouse_down = false
				_pan_active = false
				_drag_station_id = ""
				_drag_curve = []
				_drag_draft_station = false
				_curve_preview = {}
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
					var controls := WorldData.link_control_points(link, world, float(city_data.get("center", [31.23,121.47])[0]))
					var is_a := str(_drag_curve[1]) == "curveA"
					var endpoint_geo := WorldData.station_endpoint(WorldData.find_station(world, str(link.get("a" if is_a else "b", {}).get("stationId", ""))), str(link.get("a" if is_a else "b", {}).get("side", "end")))
					var endpoint_local := Geo.local_m(endpoint_geo, float(city_data.get("center", [31.23,121.47])[0]))
					var cursor_local := Geo.local_m(hover_latlng, float(city_data.get("center", [31.23,121.47])[0]))
					var offset := cursor_local - endpoint_local
					_curve_preview = {"linkId": str(_drag_curve[0]), "controlName": str(_drag_curve[1]), "offset": [offset.x, offset.y]}
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
	return Geo.project(latlng, current_zoom) - Geo.project(current_center, current_zoom) + size * .5

func _station_screen(station: Dictionary) -> Vector2:
	if station.get("id", "") == selected_id and station_drag_preview_active(): return _to_screen(_drag_preview[1])
	return _to_screen(station.get("latlng", [0, 0]))

func station_drag_preview_active() -> bool:
	return not _drag_preview.is_empty() and str(_drag_preview[0]) == selected_id

func _pick(point: Vector2) -> Dictionary:
	if tool == "connect":
		var endpoint: Dictionary = {}
		var endpoint_distance := 20.0
		for station in world.get("stations", []):
			if str(station.get("id", "")) == str(link_start.get("stationId", "")): continue
			for side in ["start", "end"]:
				var distance := point.distance_to(_to_screen(WorldData.station_endpoint(station, side)))
				if distance <= endpoint_distance:
					endpoint_distance = distance
					endpoint = {"type": "endpoint", "id": str(station.get("id", "")), "side": side}
		if not endpoint.is_empty(): return endpoint
	for station in world.get("stations", []):
		if point.distance_to(_station_screen(station)) <= 20.0:
			return {"type": "station", "id": str(station.get("id", "")), "side": ""}
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
	if tool in ["select", "delete", "curve"]:
		var ref_lat := float(city_data.get("center", [31.23,121.47])[0])
		var nearest_link: Dictionary = {}
		var nearest_distance := 12.0
		for link in world.get("trackLinks", []):
			var points: Array = WorldData.track_points(link, world, ref_lat, 24)
			if points.size() < 2: continue
			var previous := _to_screen(points[0])
			for index in range(1, points.size()):
				var current := _to_screen(points[index])
				var closest := Geometry2D.get_closest_point_to_segment(point, previous, current)
				var distance := point.distance_to(closest)
				if distance <= nearest_distance:
					nearest_distance = distance
					nearest_link = {"type": "link", "id": str(link.get("id", "")), "side": ""}
				previous = current
		if not nearest_link.is_empty(): return nearest_link
	if show_demand and tool in ["select", "delete", "station"]:
		var nearest_demand: Dictionary = {}
		var demand_distance := 15.0
		for demand in city_data.get("demand", []):
			var demand_id := str(demand.get("id", ""))
			if filter_demand_to_task and not focus_demand_ids.has(demand_id): continue
			var distance := point.distance_to(_to_screen(demand.get("latlng", [0, 0])))
			if distance <= demand_distance:
				demand_distance = distance
				nearest_demand = {"type": "demand", "id": str(demand.get("id", "")), "side": ""}
		return nearest_demand
	return {}

func _find_link(link_id: String) -> Dictionary:
	for link in world.get("trackLinks", []):
		if str(link.get("id", "")) == link_id: return link
	return {}

func _station_drag_preview_update(station_id: String, latlng: Array) -> void:
	_drag_preview = [station_id, latlng]

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

func _draw_label(position: Vector2, text: String, color: Color, font: Font, font_size: int, force: bool = false, bold: bool = false) -> void:
	var display_font: Font = bold_font if bold and is_instance_valid(bold_font) else font
	var size := maxi(14, roundi(float(font_size) * ui_scale))
	var measured := display_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var rect := Rect2(position + Vector2(-5, -size - 4), Vector2(measured.x + 10, size + 9))
	if not force:
		for occupied in _label_rects:
			if rect.intersects(occupied): return
	_label_rects.append(rect)
	draw_rect(rect, Color(1, 1, 1, 0.94 if force else 0.88))
	draw_string(display_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _visible_tile_bounds() -> Dictionary:
	var center := Geo.project(current_center, current_zoom)
	var min_x := int(floor((center.x - size.x * .5) / 256.0))
	var max_x := int(floor((center.x + size.x * .5) / 256.0))
	var min_y := int(floor((center.y - size.y * .5) / 256.0))
	var max_y := int(floor((center.y + size.y * .5) / 256.0))
	var n := int(pow(2.0, current_zoom))
	return {"left": min_x, "right": max_x, "top": clampi(min_y, 0, n - 1), "bottom": clampi(max_y, 0, n - 1), "world_n": n}

func _tile_screen_pos(x: int, y: int) -> Vector2:
	var center := Geo.project(current_center, current_zoom)
	return Vector2(float(x) * 256.0, float(y) * 256.0) - center + size * .5

func _queue_visible_tiles() -> void:
	_tile_redraw_pending = false
	if not is_inside_tree() or city_data.is_empty() or not allow_network_tiles: return
	var loaded_cached_tile := false
	var b := _visible_tile_bounds()
	var visible_keys: Dictionary = {}
	for y in range(b.top, b.bottom + 1):
		for x in range(b.left, b.right + 1):
			var normalized_x := posmod(x, int(b.world_n))
			var key := "%d/%d/%d" % [current_zoom, normalized_x, y]
			visible_keys[key] = true
	var kept_queue: Array[Dictionary] = []
	for item in _tile_queue:
		var queued_key := str(item.get("key", ""))
		if visible_keys.has(queued_key): kept_queue.append(item)
		else: _queued_tiles.erase(queued_key)
	_tile_queue = kept_queue
	for active_key in _active_request_by_key.keys():
		if visible_keys.has(str(active_key)): continue
		var stale_request: HTTPRequest = _active_request_by_key[active_key]
		stale_request.cancel_request()
		_active_request_by_key.erase(active_key)
		_requested.erase(active_key)
		_requests.erase(stale_request)
	for raw_key in visible_keys:
		var key: String = str(raw_key)
		var expired := _tile_expiry.has(key) and int(_tile_expiry[key]) < int(Time.get_unix_time_from_system())
		if _tile_textures.has(key) and not expired: continue
		if _requested.has(key) or _queued_tiles.has(key): continue
		var loaded_count := _tile_textures.size()
		if _load_cached_tile(key):
			loaded_cached_tile = loaded_cached_tile or _tile_textures.size() > loaded_count
			continue
		loaded_cached_tile = loaded_cached_tile or _tile_textures.size() > loaded_count
		if _network_blocked: continue
		var parts: PackedStringArray = key.split("/")
		_tile_queue.append({"z": int(parts[0]), "x": int(parts[1]), "y": int(parts[2]), "key": key})
		_queued_tiles[key] = true
	# Cache hits do not receive an HTTP callback to schedule a redraw. Without
	# this, first launch can display the fallback grid until the camera moves.
	if loaded_cached_tile: queue_redraw()
	_pump_tile_requests()

func _load_cached_tile(key: String) -> bool:
	var parts := key.split("/")
	var path := "%s/%s/%s/%s.png" % [TILE_CACHE, parts[0], parts[1], parts[2]]
	var meta_path := path + ".json"
	if not FileAccess.file_exists(path): return false
	var bytes := FileAccess.get_file_as_bytes(path)
	if _is_osm_blocked_tile(bytes):
		_tile_placeholder_rejections += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(meta_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(meta_path))
		_tile_textures.erase(key)
		_tile_expiry.erase(key)
		return false
	var expiry := 0
	if FileAccess.file_exists(meta_path):
		var meta := FileAccess.open(meta_path, FileAccess.READ)
		if meta:
			var parsed: Variant = JSON.parse_string(meta.get_as_text())
			if parsed is Dictionary: expiry = int(parsed.get("expires", 0))
	else:
		expiry = int(FileAccess.get_modified_time(path)) + 604800
	var fresh := expiry >= int(Time.get_unix_time_from_system())
	var img := Image.new()
	if img.load(path) != OK: return false
	_tile_textures[key] = ImageTexture.create_from_image(img)
	_tile_valid_count += 1
	_tile_expiry[key] = expiry
	return fresh

func _is_osm_blocked_tile(bytes: PackedByteArray) -> bool:
	if bytes.is_empty(): return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode() == OSM_BLOCKED_TILE_SHA256

func _pump_tile_requests() -> void:
	while _requests.size() < MAX_CONCURRENT and not _tile_queue.is_empty():
		var item: Dictionary = _tile_queue.pop_front()
		var key := str(item.key)
		_queued_tiles.erase(key)
		if _requested.has(key): continue
		var req := HTTPRequest.new()
		req.timeout = 12.0
		req.max_redirects = 3
		req.accept_gzip = true
		req.use_threads = true
		if not _https_proxy_host.is_empty() and _https_proxy_port > 0:
			req.set_https_proxy(_https_proxy_host, _https_proxy_port)
		add_child(req)
		_requests.append(req)
		_requested[key] = true
		_active_request_by_key[key] = req
		req.request_completed.connect(_on_tile_completed.bind(key, req, item))
		var url := OSM_URL.replace("{z}", str(item.z)).replace("{x}", str(item.x)).replace("{y}", str(item.y))
		var error := req.request(url, ["User-Agent: MetroAtlasDesktop/0.1", "Accept: image/png"])
		if error != OK:
			_requests.erase(req)
			_requested.erase(key)
			_active_request_by_key.erase(key)
			req.queue_free()

func _on_tile_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, key: String, req: HTTPRequest, item: Dictionary) -> void:
	_requests.erase(req)
	_requested.erase(key)
	_active_request_by_key.erase(key)
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		if _is_osm_blocked_tile(body):
			_tile_placeholder_rejections += 1
			_network_unavailable = true
			_network_blocked = true
			_tile_queue.clear()
			_queued_tiles.clear()
			push_warning("地图服务返回了访问提示图，已停止后续请求；仍可继续规划和保存。")
			requested_redraw()
			if is_instance_valid(req): req.queue_free()
			_pump_tile_requests()
			return
		var image := Image.new()
		if image.load_png_from_buffer(body) == OK:
			_network_unavailable = false
			_tile_textures[key] = ImageTexture.create_from_image(image)
			_tile_valid_count += 1
			var max_age := 604800
			var cache_allowed := true
			for header in headers:
				var h := str(header).to_lower()
				if h.begins_with("cache-control:"):
					if h.contains("no-store"): cache_allowed = false
					if h.contains("no-cache"): max_age = 0
					var cache_regex := RegEx.new()
					cache_regex.compile("max-age=(\\d+)")
					var found := cache_regex.search(h)
					if found: max_age = int(found.get_string(1))
			var expiry := int(Time.get_unix_time_from_system()) + maxi(0, max_age)
			_tile_expiry[key] = expiry if cache_allowed and max_age > 0 else 9223372036854775807
			if cache_allowed:
				var parts := key.split("/")
				var base := "%s/%s/%s" % [TILE_CACHE, parts[0], parts[1]]
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
				var png_path := "%s/%s.png" % [base, parts[2]]
				var image_file := FileAccess.open(png_path, FileAccess.WRITE)
				if image_file: image_file.store_buffer(body)
				var meta_file := FileAccess.open(png_path + ".json", FileAccess.WRITE)
				if meta_file: meta_file.store_string(JSON.stringify({"expires": expiry}))
			requested_redraw()
	else:
		_network_unavailable = true
		requested_redraw()
		if response_code == 403 or response_code == 429:
			push_warning("OpenStreetMap 瓦片服务暂时拒绝请求；仍可离线规划和保存。")
	if is_instance_valid(req): req.queue_free()
	_pump_tile_requests()

func _detect_system_https_proxy() -> Dictionary:
	if OS.get_name() == "Windows":
		const INTERNET_SETTINGS := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings"
		var enable_output: Array = []
		var enable_code := OS.execute("reg.exe", ["query", INTERNET_SETTINGS, "/v", "ProxyEnable"], enable_output, true)
		if enable_code == 0:
			var enable_regex := RegEx.new()
			enable_regex.compile("ProxyEnable\\s+REG_DWORD\\s+(0x[0-9a-fA-F]+|\\d+)")
			var enable_match := enable_regex.search("\n".join(enable_output))
			if enable_match and enable_match.get_string(1).to_lower() in ["0x1", "0x00000001", "1"]:
				var server_output: Array = []
				if OS.execute("reg.exe", ["query", INTERNET_SETTINGS, "/v", "ProxyServer"], server_output, true) == 0:
					var server_regex := RegEx.new()
					server_regex.compile("ProxyServer\\s+REG_SZ\\s+(.+)")
					var server_match := server_regex.search("\n".join(server_output))
					if server_match:
						var setting := server_match.get_string(1).strip_edges()
						var https_setting := ""
						var simple_setting := setting
						for entry in setting.split(";"):
							var parts := str(entry).split("=", false, 1)
							if parts.size() == 2 and str(parts[0]).strip_edges().to_lower() == "https":
								https_setting = str(parts[1]).strip_edges()
							elif parts.size() == 1:
								simple_setting = str(parts[0]).strip_edges()
						var proxy_text := https_setting if not https_setting.is_empty() else simple_setting
						if not proxy_text.is_empty():
							var proxy := _parse_proxy(proxy_text)
							if not proxy.is_empty() and not _proxy_bypasses_osm(INTERNET_SETTINGS): return proxy
		var env_proxy := OS.get_environment("HTTPS_PROXY")
		if env_proxy.is_empty(): env_proxy = OS.get_environment("https_proxy")
		return _parse_proxy(env_proxy)
	return {}

func _parse_proxy(value: String) -> Dictionary:
	var text := value.strip_edges().trim_prefix("http://").trim_prefix("https://").trim_suffix("/")
	if text.contains("@"): text = text.get_slice("@", text.get_slice_count("@") - 1)
	if text.begins_with("[") and text.contains("]:"):
		var closing := text.find("]")
		return {"host": text.substr(1, closing - 1), "port": int(text.substr(closing + 2))}
	var colon := text.rfind(":")
	if colon <= 0: return {}
	var port := int(text.substr(colon + 1))
	if port <= 0 or port > 65535: return {}
	return {"host": text.left(colon), "port": port}

func _proxy_bypasses_osm(registry_path: String) -> bool:
	var bypass_output: Array = []
	if OS.execute("reg.exe", ["query", registry_path, "/v", "ProxyOverride"], bypass_output, true) != 0: return false
	var bypass_regex := RegEx.new()
	bypass_regex.compile("ProxyOverride\\s+REG_SZ\\s+(.+)")
	var bypass_match := bypass_regex.search("\n".join(bypass_output))
	if not bypass_match: return false
	for pattern in bypass_match.get_string(1).split(";"):
		var clean := str(pattern).strip_edges().to_lower()
		if clean == "<local>": continue
		if "tile.openstreetmap.org".matchn(clean) or clean == "openstreetmap.org" or clean == "*.openstreetmap.org": return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: requested_redraw()
