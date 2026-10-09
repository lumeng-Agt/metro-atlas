extends SceneTree

const Onboarding = preload("res://scripts/onboarding.gd")
const Preferences = preload("res://scripts/ui_preferences.gd")
const Travel = preload("res://scripts/travel_model.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var city_pairs := {
		"shanghai": ["shanghai-tutorial-jingui", "shanghai-d17"],
		"beijing": ["beijing-d5", "beijing-tutorial-cnu"],
		"guangzhou": ["guangzhou-tutorial-zhongshan-housing", "guangzhou-d14"],
		"shenzhen": ["shenzhen-tutorial-xililantian", "shenzhen-d4"],
		"chengdu": ["chengdu-tutorial-yulinmingju", "chengdu-d19"]
	}
	for city_id in city_pairs:
		var city := WorldData.city(str(city_id))
		var origin := _find_demand(city, str(city_pairs[city_id][0]))
		var destination := _find_demand(city, str(city_pairs[city_id][1]))
		_check(not origin.is_empty() and not destination.is_empty(), "%s 教学点存在于城市资料" % city_id)
		_check(bool(origin.get("verified", false)) and bool(destination.get("verified", false)), "%s 教学点有来源核验标记" % city_id)
		_check(str(origin.get("type", "")) == "housing" and not str(origin.get("sourceUrl", "")).is_empty(), "%s 起点是带 OSM 来源链接的具体居住地点" % city_id)
		var origin_tags: Dictionary = origin.get("tags", {})
		_check(origin_tags.get("landuse", "") == "residential" or origin_tags.get("building", "") == "apartments" or origin_tags.get("place", "") == "neighbourhood", "%s 起点的 OSM 要素标签与居住地点一致" % city_id)
		if not origin.is_empty() and not destination.is_empty():
			var ref_lat := deg_to_rad((float(origin.latlng[0]) + float(destination.latlng[0])) * 0.5)
			var north := (float(destination.latlng[0]) - float(origin.latlng[0])) * 111320.0
			var east := (float(destination.latlng[1]) - float(origin.latlng[1])) * 111320.0 * cos(ref_lat)
			var km := Vector2(east, north).length() / 1000.0
			_check(km >= 1.0 and km <= 3.0, "%s 教学出行控制在 1—3 公里" % city_id)
	_check(is_equal_approx(Travel.rail_minutes(1000.0, 60.0), 1.18), "千米与公里时速换算为正确的轨道分钟数")
	_check(is_equal_approx(Travel.walk_minutes(800.0, 4.8), 10.0), "步行耗时采用 4.8 千米/小时游戏参数")

	var previous_completion := Preferences.load_onboarding_completed()
	root.size = Vector2i(1600, 980)
	var main_scene := load("res://scenes/main.tscn")
	var main: Variant = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	main.map_view.allow_network_tiles = false
	var guide := WorldData.new_world("shanghai", "blank")
	guide["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	guide.onboarding.active = true
	guide["tutorialDone"] = true
	main._load_world(guide)
	await process_frame
	_check(bool(main.world.onboarding.active), "空白开局任务卡已经启用")
	_check(main.onboarding_panel.visible, "地图上显示独立的新手任务卡")
	_check(not main._left_panel.visible and not main._right_panel.visible, "教学开局默认收起两侧抽屉")
	_check(main.map_view.filter_demand_to_task, "教学只显示 A、B 需求点")
	_check(main.map_view.clean_map_style, "新手地图默认使用清爽底图")
	_check(main.map_view.current_zoom >= 14, "镜头聚焦教学街区")

	main._onboarding_primary_action()
	_check(int(main.world.onboarding.step) == 1, "查看需求后才进入第一站任务")
	var origin: Dictionary = main._find_demand(str(main.world.onboarding.originId))
	var destination: Dictionary = main._find_demand(str(main.world.onboarding.destinationId))
	var route_id := str(main.active_route_id)
	var heading: float = main._onboarding_station_heading()
	main.current_tool = "station"; main.map_view.tool = "station"
	main.map_view.draft_station = {"id":"draft-a", "name":"A站", "latlng":origin.latlng.duplicate(), "heading":heading, "lengthM":118.788, "widthM":20.0, "vehicleId":"B-6", "routeIds":[route_id]}
	main._confirm_station()
	_check(int(main.world.onboarding.step) == 2 and not str(main.world.onboarding.originStationId).is_empty(), "只有确认且覆盖 A 的新站才完成第一站")
	var source_id := str(main.world.onboarding.originStationId)
	await create_timer(0.01).timeout
	main.current_tool = "station"; main.map_view.tool = "station"
	main.map_view.draft_station = {"id":"draft-b", "name":"B站", "latlng":destination.latlng.duplicate(), "heading":heading, "lengthM":118.788, "widthM":20.0, "vehicleId":"B-6", "routeIds":[route_id]}
	main._confirm_station()
	_check(int(main.world.onboarding.step) == 3 and str(main.world.onboarding.destinationStationId) != source_id, "第二座不同的确认车站覆盖 B 终点")
	var destination_id := str(main.world.onboarding.destinationStationId)
	main.current_tool = "connect"; main.map_view.tool = "connect"
	main._on_map_clicked(WorldData.station_endpoint(WorldData.find_station(main.world, source_id), "end"), "endpoint", source_id, "end")
	main._on_map_clicked(WorldData.station_endpoint(WorldData.find_station(main.world, destination_id), "start"), "endpoint", destination_id, "start")
	_check(int(main.world.onboarding.step) == 4, "只有任务两站连续接轨才进入开通检查")
	main._onboarding_primary_action()
	_check(int(main.world.onboarding.step) == 5 and bool(WorldData.find_route(main.world, route_id).get("open", false)), "任务线路开通后进入观察")
	var flow: Dictionary = main._onboarding_flow()
	_check(bool(flow.get("valid", false)) and float(flow.get("tripMinutes", 0.0)) < 120.0, "教学展示有效且单位合理的模拟出行估算")
	main._onboarding_primary_action()
	for minute in range(240):
		if int(main.world.onboarding.step) >= 6: break
		main._simulate_one_minute()
	_check(int(main.world.onboarding.observedTargetArrivals) > 0, "教学等待目标需求真实进入模拟批次")
	_check(int(main.world.onboarding.observedTargetServed) > 0, "教学等待目标需求真实获得线路服务")
	_check(int(main.world.onboarding.step) == 6 and bool(main.world.simulation.paused), "观察到目标服务后完成引导并自动暂停")
	Preferences.save_onboarding_completed(false)
	main.world["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	main.world.onboarding.active = true
	main._end_onboarding(true)
	_check(bool(main.world.onboarding.skipped) and Preferences.load_onboarding_completed(), "主动跳过会记为已看过，其他新城市不再重复弹出")
	_check(not Onboarding.create_state("beijing", "blank", Preferences.load_onboarding_completed()).active, "已跳过后其他城市仍可直接规划")
	_check(previous_completion == Preferences.load_onboarding_completed() or Preferences.save_onboarding_completed(previous_completion) == OK, "测试结束恢复原有的教学完成偏好")
	if failures.is_empty():
		print("PASS: %d onboarding checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _find_demand(city: Dictionary, demand_id: String) -> Dictionary:
	for point in city.get("demand", []):
		if str(point.get("id", "")) == demand_id: return point
	return {}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
