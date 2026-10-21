extends SceneTree

const MapViewScript = preload("res://scripts/map_view.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	var map: MapView = MapViewScript.new()
	root.add_child(map)
	map.size = Vector2(1200, 800)
	map.city_data = {"id":"shanghai","center":[31.2304,121.4737]}
	map.geometry_ref_lat = 31.2304
	map.current_center = [31.2304,121.4737]
	map.world = {"stations":[],"trackNodes":[],"trackEdges":[],"trackLinks":[],"view":{"center":[31.2304,121.4737],"zoom":14}}
	map.tool = "station"
	var target: Dictionary = {"id":"target-a","name":"目标站","latlng":[31.2304,121.4737],"toleranceM":120.0,"built":false}
	map.campaign_blueprint = {"visible":true,"stations":[target]}
	for zoom in [9, 13, 17]:
		map.current_zoom = zoom
		map._camera_cache_zoom = -1
		var center: Vector2 = map._to_screen(target.latlng)
		var radius: float = map._blueprint_target_radius(target)
		var hit: Dictionary = map._pick(center + Vector2(radius, 0.0))
		_check(str(hit.get("type",""))=="blueprint" and str(hit.get("id",""))=="target-a","visible target-ring edge is selectable at zoom %d" % zoom)
	var overlap := target.duplicate(true)
	overlap.id = "target-b"
	overlap.name = "重叠站区"
	map.campaign_blueprint.stations = [target, overlap]
	map.current_zoom = 14
	map._camera_cache_zoom = -1
	var overlap_hit: Dictionary = map._pick(map._to_screen(target.latlng))
	_check(str(overlap_hit.get("type",""))=="blueprint_choice","overlapping target areas request an explicit choice")
	map.campaign_blueprint.visible = false
	map.world.stations = [
		{"id":"body-a","latlng":[31.2304,121.4737],"heading":90.0,"lengthM":120.0,"widthM":22.0},
		{"id":"body-b","latlng":[31.2304,121.4737],"heading":0.0,"lengthM":120.0,"widthM":22.0}
	]
	var station_hit: Dictionary = map._pick(map._to_screen([31.2304,121.4737]))
	_check(str(station_hit.get("type",""))=="station_choice","overlapping physical station bodies request an explicit choice")
	if failures.is_empty():
		print("PASS: %d map hit checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		push_error("Map hit checks: %d checks, %d failures" % [checks, failures.size()])
		quit(1)
