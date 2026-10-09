class_name WorldData
extends RefCounted

const SAVE_VERSION := 8
const CITIES_PATH := "res://data/cities.json"
const VEHICLES_PATH := "res://data/vehicles.json"

static var _dataset: Dictionary = {}
static var _vehicle_profiles: Array = []

static func load_assets() -> void:
	var city_file := FileAccess.open(CITIES_PATH, FileAccess.READ)
	if city_file:
		_dataset = JSON.parse_string(city_file.get_as_text())
	var vehicle_file := FileAccess.open(VEHICLES_PATH, FileAccess.READ)
	if vehicle_file:
		_vehicle_profiles = JSON.parse_string(vehicle_file.get_as_text())

static func cities() -> Array:
	return _dataset.get("cities", [])

static func vehicles() -> Array:
	return _vehicle_profiles

static func city(city_id: String) -> Dictionary:
	for item in cities():
		if item.get("id", "") == city_id:
			return item
	return {}

static func new_world(city_id: String, mode: String) -> Dictionary:
	var c := city(city_id)
	var state := {
		"schemaVersion": SAVE_VERSION,
		"cityId": city_id,
		"cityName": c.get("name", city_id),
		"mode": mode,
		"dataVersion": _dataset.get("generatedAt", "unknown"),
		"stations": [], "routes": [], "trackLinks": [], "depots": [],
		"simulation": {"minute": 420, "speed": 1, "paused": true, "seed": 45281, "completed": 0, "attempted": 0, "served": 0},
		"fleetMode": "automatic", "tutorialStep": 0, "tutorialDone": false,
		"randomSeed": 45281, "revision": 1,
		"view": {"center": c.get("center", [31.2304, 121.4737]), "zoom": int(c.get("zoom", 12))},
		"history": {"undo": [], "redo": []},
		"source": {"attribution": _dataset.get("osmAttribution", "© OpenStreetMap contributors"), "license": _dataset.get("license", "ODbL 1.0"), "snapshot": _dataset.get("generatedAt", "unknown")}
	}
	if mode == "expand":
		_import_existing_network(state, c)
	else:
		_add_route(state, "1号线", "#e23f56")
	return state

static func _import_existing_network(state: Dictionary, c: Dictionary) -> void:
	var station_lookup: Dictionary = {}
	for raw in c.get("stations", []):
		var station := {"id": str(raw.get("id", "")), "name": str(raw.get("name", "未命名站")), "latlng": raw.get("latlng", c.get("center", [0, 0])), "heading": 90.0, "lengthM": 118.788, "widthM": 20.0, "vehicleId": "B-6", "schematic": true, "existing": true, "routeIds": []}
		state["stations"].append(station)
		station_lookup[station.id] = station
	var link_lookup: Dictionary = {}
	for raw_route in c.get("lines", []):
		var route := {"id": str(raw_route.get("id", "route_%d" % state.routes.size())), "name": str(raw_route.get("name", "线路")), "color": str(raw_route.get("color", "#e23f56")), "vehicleId": "B-6", "headway": 4, "open": true, "schematic": true, "stationOrder": [], "directions": raw_route.get("directions", [])}
		var directions: Array = raw_route.get("directions", [])
		for direction in directions:
			var ids: Array = direction.get("stationIds", [])
			for sid in ids:
				if station_lookup.has(str(sid)):
					if not route.stationOrder.has(str(sid)): route.stationOrder.append(str(sid))
					var st: Dictionary = station_lookup[str(sid)]
					if not st.routeIds.has(route.id): st.routeIds.append(route.id)
			for index in range(maxi(0, ids.size() - 1)):
				if ids.size() < 2: continue
				var a: String = str(ids[index]); var b: String = str(ids[index + 1])
				if not station_lookup.has(a) or not station_lookup.has(b): continue
				var link_key := (a + "|" + b) if a < b else (b + "|" + a)
				if link_lookup.has(link_key):
					var existing_link: Dictionary = link_lookup[link_key]
					if not existing_link.routeIds.has(route.id): existing_link.routeIds.append(route.id)
				else:
					var link := {"id": "legacy_%s_%d" % [route.id, state.trackLinks.size()], "a": {"stationId": a, "side": "end"}, "b": {"stationId": b, "side": "start"}, "routeIds": [route.id], "schematic": true}
					state["trackLinks"].append(link)
					link_lookup[link_key] = link
		state["routes"].append(route)

static func _add_route(state: Dictionary, route_name: String, color: String) -> Dictionary:
	var route := {"id": "r_%d" % Time.get_ticks_msec(), "name": route_name, "color": color, "vehicleId": "B-6", "headway": 3, "open": false, "schematic": false, "stationOrder": [], "directions": []}
	state["routes"].append(route)
	return route

static func add_route(state: Dictionary, route_name: String, color: String) -> Dictionary:
	return _add_route(state, route_name, color)

static func find_station(state: Dictionary, station_id: String) -> Dictionary:
	for station in state.get("stations", []):
		if str(station.get("id", "")) == station_id: return station
	return {}

static func find_route(state: Dictionary, route_id: String) -> Dictionary:
	for route in state.get("routes", []):
		if str(route.get("id", "")) == route_id: return route
	return {}

static func vehicle(vehicle_id: String) -> Dictionary:
	for profile in vehicles():
		if str(profile.get("id", "")) == vehicle_id: return profile
	return {}

static func station_endpoint(station: Dictionary, side: String) -> Array:
	var bearing := float(station.get("heading", 90.0))
	if side == "start": bearing += 180.0
	return Geo.offset(station.get("latlng", [0.0, 0.0]), float(station.get("lengthM", 118.788)) * 0.5, bearing)

static func station_outward(station: Dictionary, side: String) -> Vector2:
	var bearing := float(station.get("heading", 90.0))
	if side == "start": bearing += 180.0
	var rad := deg_to_rad(bearing)
	return Vector2(sin(rad), cos(rad))

static func default_curve_vectors(a_station: Dictionary, a_side: String, b_station: Dictionary, b_side: String, ref_lat: float) -> Dictionary:
	var p0 := Geo.local_m(station_endpoint(a_station, a_side), ref_lat)
	var p3 := Geo.local_m(station_endpoint(b_station, b_side), ref_lat)
	var handle := minf(p0.distance_to(p3) * 0.34, 420.0)
	var a_vector := station_outward(a_station, a_side) * handle
	var b_vector := station_outward(b_station, b_side) * handle
	return {"a": [a_vector.x, a_vector.y], "b": [b_vector.x, b_vector.y]}

static func link_control_points(link: Dictionary, state: Dictionary, ref_lat: float) -> Array[Vector2]:
	var a_ref: Dictionary = link.get("a", {})
	var b_ref: Dictionary = link.get("b", {})
	var a_station := find_station(state, str(a_ref.get("stationId", "")))
	var b_station := find_station(state, str(b_ref.get("stationId", "")))
	if a_station.is_empty() or b_station.is_empty(): return []
	var p0 := Geo.local_m(station_endpoint(a_station, str(a_ref.get("side", "end"))), ref_lat)
	var p3 := Geo.local_m(station_endpoint(b_station, str(b_ref.get("side", "start"))), ref_lat)
	var defaults := default_curve_vectors(a_station, str(a_ref.get("side", "end")), b_station, str(b_ref.get("side", "start")), ref_lat)
	var va: Array = link.get("curveA", defaults.a)
	var vb: Array = link.get("curveB", defaults.b)
	var p1 := p0 + Vector2(float(va[0]), float(va[1]))
	var p2 := p3 + Vector2(float(vb[0]), float(vb[1]))
	return [p0, p1, p2, p3]

static func track_points(link: Dictionary, state: Dictionary, ref_lat: float, segments: int = 24) -> Array[Array]:
	var controls := link_control_points(link, state, ref_lat)
	var result: Array[Array] = []
	if controls.size() != 4: return result
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var u := 1.0 - t
		var point := controls[0] * u*u*u + controls[1] * 3.0*u*u*t + controls[2] * 3.0*u*t*t + controls[3] * t*t*t
		result.append(Geo.from_local(point, ref_lat))
	return result

static func track_length_m(link: Dictionary, state: Dictionary, ref_lat: float) -> float:
	if link.get("schematic", false):
		var a_station := find_station(state, str(link.get("a", {}).get("stationId", "")))
		var b_station := find_station(state, str(link.get("b", {}).get("stationId", "")))
		if a_station.is_empty() or b_station.is_empty(): return 0.0
		return Geo.local_m(a_station.get("latlng", [0,0]), ref_lat).distance_to(Geo.local_m(b_station.get("latlng", [0,0]), ref_lat))
	var controls := link_control_points(link, state, ref_lat)
	if controls.size() != 4: return 0.0
	var length := 0.0
	var previous := controls[0]
	for i in range(1, 33):
		var t := float(i) / 32.0
		var u := 1.0 - t
		var point := controls[0] * u*u*u + controls[1] * 3.0*u*u*t + controls[2] * 3.0*u*t*t + controls[3] * t*t*t
		length += previous.distance_to(point)
		previous = point
	return length

static func create_station(state: Dictionary, latlng: Array, heading: float, route_id: String) -> Dictionary:
	var vehicle_id := "B-6"
	var route := find_route(state, route_id)
	if not route.is_empty(): vehicle_id = str(route.get("vehicleId", "B-6"))
	var profile := vehicle(vehicle_id)
	var station := {"id": "st_%d" % Time.get_ticks_msec(), "name": "新建车站", "latlng": [float(latlng[0]), float(latlng[1])], "heading": heading, "lengthM": float(profile.get("trainLengthM", 118.788)), "widthM": 20.0, "vehicleId": vehicle_id, "schematic": false, "existing": false, "routeIds": [route_id] if not route_id.is_empty() else []}
	state["stations"].append(station)
	if not route.is_empty(): route["stationOrder"].append(station.id)
	return station
