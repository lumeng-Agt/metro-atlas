extends SceneTree

const MapViewScript = preload("res://scripts/map_view.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	root.size = Vector2i(1600, 980)
	var map := MapViewScript.new()
	map.size = Vector2(1600, 980)
	root.add_child(map)
	var world := WorldData.new_world("shenzhen", "blank")
	world.view.zoom = 15
	map.set_context(WorldData.city("shenzhen"), world)
	var short_road := {"id":"short-main-road", "kind":"road_major", "points":[[22.545, 114.054], [22.5451, 114.054]]}
	_check(MapViewScript._prepare_base_features_for([short_road], 12, 10.0, 22.545).size() == 1, "短主路片段不会因长度阈值从城市骨架中消失")
	var primary_road := {"id":"city-primary-road", "kind":"road_primary", "points":[[22.545, 114.054], [22.546, 114.054]]}
	_check(MapViewScript._prepare_base_features_for([primary_road], 12, 10.0, 22.545).is_empty(), "城市总览暂不绘制过密的城市主路")
	_check(MapViewScript._prepare_base_features_for([primary_road], 13, 10.0, 22.545).size() == 1, "放大至城区尺度后显示城市主路")
	var timeout:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<timeout:
		await process_frame
		if not map._base_map_thread_busy and map._base_map_pending_request.is_empty(): break
	var roads := 0
	for feature in map.base_map_features:
		if str(feature.get("kind", "")).begins_with("road_"): roads += 1
	_check(roads > 0, "可见的本地地图道路在后台加载后显示")
	_check(not map._base_map_thread_busy, "关闭地图视图前后台加载任务已完成")
	map.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: %d asynchronous basemap checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
