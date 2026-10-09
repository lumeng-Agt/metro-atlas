extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1600, 980)
	var main_scene := load("res://scenes/main.tscn")
	var main: Variant = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var menu_card: Control = main.menu_layer.get_node("MenuCard")
	var menu_content: Control = menu_card.get_node("MenuBodyScroll/MenuContent")
	var menu_center: Vector2 = menu_card.global_position + menu_card.size * 0.5
	_assert(absf(menu_center.x - main.get_viewport_rect().size.x * 0.5) < 2.0 and absf(menu_center.y - main.get_viewport_rect().size.y * 0.5) < 2.0, "主菜单卡片在不同窗口尺寸下保持视口居中")
	_assert(menu_content.size.x >= menu_card.size.x * 0.82, "主菜单内容横向铺满卡片，不再挤在左侧")
	_assert(menu_content.get_child(0).get_child(1).get_theme_font_size("font_size") >= 48, "主菜单标题使用清楚的展示字号")
	main.map_view.allow_network_tiles = false
	main._load_world(WorldData.new_world("shanghai", "blank"))
	await process_frame
	var initial_zoom: int = main.map_view.current_zoom
	var scaled_label: Label = main._label("可读性检查", 14, Color.WHITE)
	main.add_child(scaled_label)
	for scale in [1.0, 1.25, 1.5, 1.75]:
		main._apply_ui_scale(scale)
		_assert(main.map_view.ui_scale == scale and main._theme.default_font_size == roundi(18.0 * scale), "界面缩放 %d%% 会同步调整正文与控件" % roundi(scale * 100.0))
		_assert(scaled_label.get_theme_font_size("font_size") == roundi(15.0 * scale), "界面缩放 %d%% 会同步调整辅助文字" % roundi(scale * 100.0))
		_assert(main.map_view.current_zoom == initial_zoom, "界面缩放与地图镜头级别相互独立")
		var logical_width: float = main.get_viewport_rect().size.x / scale
		_assert(main._layout_narrow == (logical_width < 1440.0 or scale >= 1.5), "窄窗口或放大界面后侧栏按空间自动收起")
		var wants_two_rows: bool = logical_width < 1760.0 or scale >= 1.25
		_assert((main._top_actions.get_parent() == main._top_content) == wants_two_rows, "顶部运行栏按宽度自动换行为一行或两行")
	var preferences_script = load("res://scripts/ui_preferences.gd")
	_assert(preferences_script.save_scale(1.75) == OK and preferences_script.load_scale() == 1.75, "界面缩放设置可保存并恢复")
	preferences_script.save_scale(1.0)
	scaled_label.queue_free()
	await process_frame
	main._apply_ui_scale(1.0)
	main.map_view.draft_station = {"latlng": [31.2304, 121.4737], "heading": 90.0, "lengthM": 118.788, "widthM": 20.0, "vehicleId": "B-6", "routeIds": [main.active_route_id], "name": "人民广场"}
	main._confirm_station()
	var first_id := str(main.world.stations[0].id)
	main.map_view.draft_station = {"latlng": [31.2304, 121.4752], "heading": 90.0, "lengthM": 118.788, "widthM": 20.0, "vehicleId": "B-6", "routeIds": [main.active_route_id], "name": "世纪大道"}
	main._confirm_station()
	var second_id := str(main.world.stations[1].id)
	_assert(not main._station_overlaps(main.world.stations[0]), "拖动或旋转检查不会把车站自身视为重叠")
	main.current_tool = "connect"; main.map_view.tool = "connect"
	main.map_view.current_zoom = 17
	main.map_view.current_center = [31.2304, 121.4745]
	var target_endpoint: Array = WorldData.station_endpoint(main.world.stations[1], "start")
	var test_demand := {"id": "smoke-overlap-demand", "latlng": target_endpoint, "type": "housing", "name": "命中优先级测试"}
	main.map_view.city_data["demand"].append(test_demand)
	main.map_view.link_start = {"stationId": first_id, "side": "end"}
	var endpoint_hit: Dictionary = main.map_view._pick(main.map_view._to_screen(target_endpoint))
	_assert(endpoint_hit.get("type", "") == "endpoint" and endpoint_hit.get("id", "") == second_id, "接轨点击优先命中端点，不被重叠需求点截走")
	main.map_view.city_data["demand"].erase(test_demand)
	main.map_view.link_start = {}
	main._on_map_clicked([31.2304,121.4737], "endpoint", first_id, "end")
	main._on_map_clicked([31.2304,121.4752], "endpoint", second_id, "start")
	_assert(main.world.trackLinks.size() == 1, "两座站端点可以接轨")
	var endpoint_distance: float = main._distance_m(WorldData.station_endpoint(main.world.stations[0], "end"), WorldData.station_endpoint(main.world.stations[1], "start"))
	_assert(endpoint_distance < 40.0, "短于旧版 40 米阈值的区间也允许连接")
	var route := WorldData.find_route(main.world, main.active_route_id)
	var straight_length: float = main._route_length_km(route)
	var link_id := str(main.world.trackLinks[0].id)
	main._on_curve_control_finished(link_id, "curveA", [0.0, 100.0])
	var curved_length: float = main._route_length_km(WorldData.find_route(main.world, main.active_route_id))
	_assert(curved_length > straight_length, "拖动曲线控制点会增加实际区间长度")
	main.selected_type = "route"; main.selected_id = main.active_route_id
	main._open_route()
	_assert(bool(WorldData.find_route(main.world, main.active_route_id).open), "近距离线路无距离门槛且可开通")
	main._simulate_one_minute()
	_assert(main.world.simulation.minute == 421, "模拟固定推进一分钟")
	main._do_undo()
	_assert(not bool(WorldData.find_route(main.world, main.active_route_id).open), "撤销开通恢复草案")
	main._do_undo()
	_assert(is_equal_approx(main._route_length_km(WorldData.find_route(main.world, main.active_route_id)), straight_length), "撤销曲线调整恢复区间几何")
	main._do_undo()
	_assert(main.world.trackLinks.is_empty(), "撤销接轨能恢复完整规划")
	_assert(main.world.simulation.minute == 421, "撤销不倒退模拟时间")
	main._do_redo()
	main._do_redo()
	main._do_redo()
	_assert(main.world.trackLinks.size() == 1, "重做能恢复接轨")
	print("PASS: native UI smoke flow")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
