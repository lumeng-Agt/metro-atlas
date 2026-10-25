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
		# Label grouping must follow the same independent bodies after a world
		# replacement (including undo/reload), without retaining stale siblings.
		map.world["cityId"]="shanghai"
		for station in map.world.stations:
			station["stationComplexId"]="fixture-complex"
			station["stationInstanceId"]=str(station.id)
		map.set_world(map.world)
		_check(map.station_complex_bodies.get("fixture-complex",[])==["body-a","body-b"],"formal independent bodies have stable label order")
		map.set_blueprint({"visible":true,"stations":[map.world.stations[1],map.world.stations[0]]})
		_check(map.blueprint_complex_bodies.get("fixture-complex",[])==["body-a","body-b"],"blueprint input order does not change interchange label positions")
		var reference:Dictionary={"visible":true,"stations":[],"corridors":[{"points":[[31.23,121.47],[31.24,121.48]],"precision":"schematic"}],"previous":[[[31.23,121.47],[31.25,121.49]]]}
		map.set_blueprint(reference);map._prepare_blueprint_corridors()
		_check(map._blueprint_corridor_paths.size()==2 and bool(map._blueprint_corridor_paths[0].previous) and bool(map._blueprint_corridor_paths[1].schematic),"corridor display retains old-plan and schematic line semantics")
		var local_before:PackedVector2Array=map._blueprint_corridor_paths[1].points.duplicate()
		map.current_zoom=16;map.current_center=[31.24,121.48];map._prepare_blueprint_corridors()
		_check(map._blueprint_corridor_paths[1].points==local_before and reference.corridors[0].points==[[31.23,121.47],[31.24,121.48]],"panning and zooming preserve cached exact reference coordinates")
		map.geometry_ref_lat=30;map._prepare_blueprint_corridors()
		_check(map._blueprint_corridor_paths[1].points!=local_before,"changing cities rebuilds geographic corridor projection")
		map.geometry_ref_lat=31.2304
		map._track_meshes[12]=ArrayMesh.new()
		map.world.stations.pop_back();map.set_world(map.world)
		_check(map.station_complex_bodies.get("fixture-complex",[])==["body-a"],"removing a body invalidates its cached sibling label")
		_check(map._track_meshes.is_empty(),"world replacement invalidates retained track drawing meshes")
		map.set_blueprint({"visible":false,"stations":[]})
		_check(map.blueprint_complex_bodies.is_empty(),"clearing a blueprint releases its old sibling label groups")
		map._prepare_blueprint_corridors()
		_check(map._blueprint_corridor_paths.is_empty(),"replacing a blueprint releases obsolete reference line geometry")
		var occupied:=Rect2(Vector2(-20,120),Vector2(300,20))
		map._reserve_label(occupied)
		_check(map._label_overlaps(Rect2(Vector2(270,125),Vector2(20,10))),"label index finds collisions beyond the origin cell")
		_check(map._label_overlaps(Rect2(Vector2(-25,125),Vector2(10,10))),"label index includes negative screen coordinates")
		_check(not map._label_overlaps(Rect2(Vector2(280,120),Vector2(10,20))),"touching label edges keep the original non-overlap rule")
		_check(not map._label_overlaps(Rect2(Vector2(0,150),Vector2(300,20))),"nearby cells do not create false collisions")
		var original:=PackedVector2Array([Vector2(0,0),Vector2(50,0.1),Vector2(100,0)])
		var geometry:Dictionary={"packedPoints":original}
		map.current_zoom=12
		var rendered:Dictionary=map._render_geometry(geometry)
		_check(geometry.packedPoints==original and rendered.packedPoints.size()==2,"display reduction preserves authoritative geometry")
		var screen_points:=PackedVector2Array()
		for point in rendered.packedPoints:screen_points.append(map._local_to_screen(point))
		var expected:PackedVector2Array=map._offset_screen_polyline(screen_points,2.6)
		var shifted:PackedVector2Array=map._offset_cached_local(rendered,2.6*map._camera_mpp)
		_check(map._local_to_screen(shifted[0]).distance_to(expected[0])<0.05,"renderer transform preserves the signed shared-track lane offset")
	if failures.is_empty():
		print("PASS: %d map hit checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		push_error("Map hit checks: %d checks, %d failures" % [checks, failures.size()])
		quit(1)
