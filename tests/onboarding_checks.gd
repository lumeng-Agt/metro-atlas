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
	Preferences.save_onboarding_completed(false)
	var stale_blank := WorldData.new_world("shanghai", "blank")
	stale_blank["onboarding"] = Onboarding.create_state("shanghai", "blank", true)
	stale_blank["tutorialDone"] = true
	main._load_world(stale_blank)
	_check(bool(main.world.onboarding.active), "旧版空白存档中未开始、未跳过的教学会在继续游戏时启动")
	_check(str(main._onboarding_focus_spec().get("message", "")).contains("A"), "恢复旧存档后直接指向第一项真实地图操作")
	var no_tutorial_field := WorldData.new_world("shanghai", "blank")
	no_tutorial_field.erase("onboarding")
	main._load_world(no_tutorial_field)
	_check(bool(main.world.onboarding.active), "没有教学字段的旧空白存档按本机完成状态补入教学")
	var completed_blank := WorldData.new_world("shanghai", "blank")
	completed_blank["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	completed_blank.onboarding.active = false
	completed_blank.onboarding.completed = true
	main._load_world(completed_blank)
	_check(not bool(main.world.onboarding.active), "已完成的存档不会因为修复逻辑重复启动教学")
	var skipped_blank := WorldData.new_world("shanghai", "blank")
	skipped_blank["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	skipped_blank.onboarding.active = false
	skipped_blank.onboarding.skipped = true
	main._load_world(skipped_blank)
	_check(not bool(main.world.onboarding.active), "主动跳过教学的存档不会因修复逻辑重新弹出")
	var guide := WorldData.new_world("shanghai", "blank")
	guide["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	guide.onboarding.active = true
	guide["tutorialDone"] = true
	main._load_world(guide)
	await process_frame
	for _frame in range(600):
		if not main.map_view.base_map_features.is_empty() and not main.map_view._base_map_thread_busy and main.map_view._base_map_pending_request.is_empty(): break
		await create_timer(0.02).timeout
	_check(bool(main.world.onboarding.active), "空白开局任务卡已经启用")
	_check(main.onboarding_panel.visible, "地图上显示独立的新手任务卡")
	_check(not main._left_panel.visible and not main._right_panel.visible, "教学开局默认收起两侧抽屉")
	_check(main.map_view.filter_demand_to_task, "教学只显示 A、B 需求点")
	_check(main.map_view.base_map_available and not main.map_view.base_map_features.is_empty(), "新手开局加载本地矢量底图")
	var has_unwanted_basemap_symbols := false
	for feature in main.map_view.base_map_features:
		if str(feature.get("kind", "")) not in ["road_major", "road_primary", "road_secondary", "road_local", "water_line", "water_area", "park", "building"]:
			has_unwanted_basemap_symbols = true
	_check(not has_unwanted_basemap_symbols, "地图底图只含道路、水系、绿地和建筑轮廓")
	_check(main.map_view.current_zoom >= 14, "镜头聚焦教学街区")

	var origin: Dictionary = main._find_demand(str(main.world.onboarding.originId))
	var destination: Dictionary = main._find_demand(str(main.world.onboarding.destinationId))
	var demand_focus: Dictionary = main._onboarding_focus_spec()
	_check(str(demand_focus.get("kind", "")) == "map" and str(demand_focus.get("message", "")).contains("A"), "引导先圈出地图上的 A 地点，并要求玩家点击实际需求点")
	_check(main.tutorial_spotlight.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.tutorial_spotlight.active, "聚焦层突出目标且不拦截目标按钮或地图点击")
	main.map_view.center_on([float(origin.latlng[0]) + 0.5, float(origin.latlng[1])], main.map_view.current_zoom)
	main._update_tutorial_spotlight()
	_check(is_equal_approx(float(main.map_view.current_center[0]), float(origin.latlng[0]) + 0.5) and str(main.tutorial_spotlight.message).contains("视野外"), "玩家自由平移后教程不反复拉回镜头，并指向返回任务位置选项")
	main._return_to_onboarding_mission()
	_check(not is_equal_approx(float(main.map_view.current_center[0]), float(origin.latlng[0]) + 0.5) and str(main.tutorial_spotlight.message).contains("A"), "点击返回任务位置后恢复当前地图目标聚焦")
	main._on_map_clicked(destination.latlng, "demand", str(destination.id), "")
	_check(int(main.world.onboarding.step) == 0 and not main.world.onboarding.get("visitedDemandIds", []).has(destination.id), "提前点击 B 不会跳过当前 A 目标")
	main._on_map_clicked(origin.latlng, "demand", str(origin.id), "")
	var second_demand_focus: Dictionary = main._onboarding_focus_spec()
	_check(int(main.world.onboarding.step) == 0 and str(second_demand_focus.get("message", "")).contains("B"), "点击 A 后焦点立即移到 B 地点")
	main._on_map_clicked(destination.latlng, "demand", str(destination.id), "")
	_check(int(main.world.onboarding.step) == 1, "玩家实际点选地图上的 A、B 需求后才进入建站")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "tool_station", "需求步骤完成后聚焦真实底栏车站工具")
	var heading: float = main._onboarding_station_heading()
	main._set_tool("station")
	_check(str(main._onboarding_focus_spec().get("kind", "")) == "map", "点击车站工具后焦点移到 A 附近地图推荐区域")
	main.map_view.draft_station = {"id":"draft-a", "name":"A站", "latlng":origin.latlng.duplicate(), "heading":heading, "lengthM":118.788, "widthM":20.0, "vehicleId":"B-6", "routeIds":[]}
	main._refresh_tools()
	_check(str(main._onboarding_focus_spec().get("key", "")) == "confirm_station" and is_instance_valid(main.tutorial_targets.get("confirm_station")), "放置预览后聚焦工具栏上的真实确认车站按钮")
	main._cancel_tool_step()
	_check(main.map_view.draft_station.is_empty() and str(main._onboarding_focus_spec().get("kind", "")) == "map", "取消预览后焦点退回地图选址，不误认为已建站")
	main.map_view.draft_station = {"id":"draft-a", "name":"A站", "latlng":origin.latlng.duplicate(), "heading":heading, "lengthM":118.788, "widthM":20.0, "vehicleId":"B-6", "routeIds":[]}
	main._refresh_tools()
	main._confirm_station()
	_check(int(main.world.onboarding.step) == 2 and not str(main.world.onboarding.originStationId).is_empty(), "只有确认且覆盖 A 的新站才完成第一站")
	main._do_undo()
	_check(int(main.world.onboarding.step) == 1 and str(main._onboarding_focus_spec().get("key", "")) == "tool_station", "撤销车站后教学回到缺少的起点建设工具")
	main._do_redo()
	_check(int(main.world.onboarding.step) == 2 and not str(main.world.onboarding.originStationId).is_empty(), "重做车站后教学识别已完成建设并继续下一项")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "tool_station", "确认第一站后引导重新指向车站工具")
	var source_id := str(main.world.onboarding.originStationId)
	await create_timer(0.01).timeout
	main._set_tool("station")
	main.map_view.draft_station = {"id":"draft-b", "name":"B站", "latlng":destination.latlng.duplicate(), "heading":heading, "lengthM":118.788, "widthM":20.0, "vehicleId":"B-6", "routeIds":[]}
	main._refresh_tools()
	_check(str(main._onboarding_focus_spec().get("key", "")) == "confirm_station", "第二座站同样必须由实际确认按钮提交")
	main._confirm_station()
	_check(int(main.world.onboarding.step) == 3 and str(main.world.onboarding.destinationStationId) != source_id, "第二座不同的确认车站覆盖 B 终点")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "tool_track", "确认第二站后引导切换到轨道工具")
	var destination_id := str(main.world.onboarding.destinationStationId)
	var source_station: Dictionary = WorldData.find_station(main.world, source_id)
	var destination_station: Dictionary = WorldData.find_station(main.world, destination_id)
	var task_endpoints := [
		main.map_view._to_screen(WorldData.station_endpoint(source_station, "start")),
		main.map_view._to_screen(WorldData.station_endpoint(source_station, "end")),
		main.map_view._to_screen(WorldData.station_endpoint(destination_station, "start")),
		main.map_view._to_screen(WorldData.station_endpoint(destination_station, "end"))
	]
	var endpoints_visible := true
	for endpoint in task_endpoints:
		if not Rect2(Vector2.ZERO, main.map_view.size).grow(-24.0).has_point(endpoint): endpoints_visible = false
	_check(endpoints_visible, "进入铺轨教学后镜头同时容纳两站的 A/B 接轨端点")
	main._set_tool("track")
	var first_endpoint_focus: Dictionary = main._onboarding_focus_spec()
	_check(str(first_endpoint_focus.get("kind", "")) == "map" and str(first_endpoint_focus.get("message", "")).contains("第一站"), "选择轨道工具后聚焦第一站真实接轨端点")
	main._on_map_clicked(WorldData.station_endpoint(WorldData.find_station(main.world, source_id), "end"), "endpoint", source_id, "end")
	_check(str(main._onboarding_focus_spec().get("message", "")).contains("另一座"), "选择第一端后聚焦另一座车站的接轨端点")
	main._on_map_clicked(WorldData.station_endpoint(WorldData.find_station(main.world, destination_id), "start"), "endpoint", destination_id, "start")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "confirm_track", "轨道预览完成后聚焦真实确认按钮")
	main._commit_track_preview()
	_check(int(main.world.onboarding.step) == 4, "只有任务两站连续接轨才进入开通检查")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "tool_line", "轨道接好后引导切换到运营线路工具")
	main._set_tool("line")
	_check(str(main._onboarding_focus_spec().get("message", "")).contains("第一座"), "选择运营线路后先聚焦第一座任务车站")
	main._on_map_clicked(origin.latlng, "station", source_id, "")
	_check(str(main._onboarding_focus_spec().get("message", "")).contains("第二座"), "选中第一站后焦点移到第二座车站")
	main._on_map_clicked(destination.latlng, "station", destination_id, "")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "confirm_line", "两座车站已选后聚焦真实线路确认按钮")
	main._confirm_operating_line()
	var route_id := str(main.active_route_id)
	_check(int(main.world.onboarding.step) == 5 and not route_id.is_empty(), "物理轨网接好后才创建任务运营线路")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "route_open", "创建线路后自动打开详情并聚焦实际开通按钮")
	main._open_route()
	_check(int(main.world.onboarding.step) == 6 and bool(WorldData.find_route(main.world, route_id).get("open", false)), "任务线路开通后进入观察")
	_check(str(main._onboarding_focus_spec().get("key", "")) == "play", "线路开通后聚焦顶部播放按钮")
	var flow: Dictionary = main._onboarding_flow()
	_check(bool(flow.get("valid", false)) and float(flow.get("tripMinutes", 0.0)) < 120.0, "教学展示有效且单位合理的模拟出行估算")
	main._toggle_pause()
	_check(not bool(main.world.simulation.get("paused", true)), "教学要求通过顶部播放控件开始观察")
	for minute in range(240):
		if int(main.world.onboarding.step) >= 7: break
		main._simulate_one_minute()
	_check(int(main.world.onboarding.observedTargetArrivals) > 0, "教学等待目标需求真实进入模拟批次")
	_check(int(main.world.onboarding.observedTargetServed) > 0, "教学等待目标需求真实获得线路服务")
	_check(int(main.world.onboarding.step) == 7 and bool(main.world.simulation.paused), "观察到目标服务后完成引导并自动暂停")
	await process_frame
	_check(str(main._onboarding_focus_spec().get("key", "")) == "tab_tasks", "目标乘客到达后聚焦左侧任务页，而非教学卡里的入口按钮")
	main._on_left_tab_pressed("tasks")
	await process_frame
	_check(str(main._onboarding_focus_spec().get("key", "")) == "campaign_next" and is_instance_valid(main.tutorial_targets.get("campaign_next")), "打开任务页后聚焦真实的下一项扩建目标")
	var next_goal: Control = main.tutorial_targets.get("campaign_next")
	if is_instance_valid(next_goal) and next_goal is Button: (next_goal as Button).pressed.emit()
	_check(not bool(main.world.onboarding.active) and bool(main.world.get("cityProgression", {}).get("started", false)), "进入城市议程后解锁持续扩建目标")
	Preferences.save_onboarding_completed(false)
	main.world["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	main.world.onboarding.active = true
	main._end_onboarding(true)
	_check(bool(main.world.onboarding.skipped) and Preferences.load_onboarding_completed(), "主动跳过会记为已看过，其他新城市不再重复弹出")
	_check(not Onboarding.create_state("beijing", "blank", Preferences.load_onboarding_completed()).active, "已跳过后其他城市仍可直接规划")
	var early_world := WorldData.new_world("shanghai", "blank")
	early_world["tutorialDone"] = true
	early_world["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	early_world.onboarding.active = true
	early_world.onboarding.step = 1
	var early_origin_station := WorldData.create_station(early_world, origin.latlng, heading, "", "B-6", -15.0)
	early_origin_station["name"] = "提前建好的起点站"
	main._load_world(early_world)
	_check(int(main.world.onboarding.step) == 2 and str(main.world.onboarding.originStationId) == str(early_origin_station.id), "进入教学前已覆盖 A 的车站会被识别并跳到缺少的 B 站操作")
	var early_destination_station := WorldData.create_station(main.world, destination.latlng, heading, "", "B-6", -15.0)
	early_destination_station["name"] = "提前建好的终点站"
	main._update_onboarding()
	_check(int(main.world.onboarding.step) == 3 and str(main.world.onboarding.destinationStationId) == str(early_destination_station.id), "玩家提前建好两站后教程跳到实际缺少的轨道操作")
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
