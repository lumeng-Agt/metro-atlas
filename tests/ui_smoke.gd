extends SceneTree

const RoutePathScript = preload("res://scripts/route_path.gd")
const OnboardingScript = preload("res://scripts/onboarding.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1600, 980)
	WorldData.load_assets()
	var main_scene := load("res://scenes/main.tscn")
	var main: Variant = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._show_issue("测试保存错误详情", "保存失败")
	var save_error_dialog: AcceptDialog
	for child in main.get_children():
		if child is AcceptDialog: save_error_dialog = child
	_assert(save_error_dialog != null and save_error_dialog.title == "保存失败" and save_error_dialog.dialog_text == "测试保存错误详情", "保存问题对话框使用准确标题和错误详情")
	if save_error_dialog != null: save_error_dialog.queue_free()
	await process_frame
	var train_layer: Control = main.map_view.get_node_or_null("TrainOverlay")
	_assert(train_layer != null and train_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "列车有独立鼠标穿透绘制层，不因动画要求整张地图重绘")
	var road_label_candidates: Array[Dictionary] = [
		{"name":"中山路", "kind":"road_local", "priority":1, "position":Vector2(0, 0)},
		{"name":"中山路", "kind":"road_major", "priority":4, "position":Vector2(80, 0)},
		{"name":"中山路", "kind":"road_local", "priority":1, "position":Vector2(310, 0)},
		{"name":"人民路", "kind":"road_primary", "priority":3, "position":Vector2(80, 0)}
	]
	var road_labels: Array[Dictionary] = MapView.deduplicate_road_labels(road_label_candidates, 220.0, 72)
	var zhongshan_labels := road_labels.filter(func(label: Dictionary) -> bool: return str(label.get("name", "")) == "中山路")
	_assert(zhongshan_labels.size() == 2 and str(zhongshan_labels[0].get("kind", "")) == "road_major", "街区地图合并近邻重复路名并优先保留主路标签")
	_assert(road_labels.size() == 3, "相距较远的同名道路仍能保留名称，标签数量受控")
	var menu_card: Control = main.menu_layer.get_node("MenuCard")
	var menu_content: Control = menu_card.get_node("MenuBodyScroll/MenuContent")
	_assert(_find_button(main.menu_layer, "存档中心") != null and _find_button(main.menu_layer, "命名存档") != null, "主菜单提供统一存档中心与命名存档入口")
	var menu_center: Vector2 = menu_card.global_position + menu_card.size * 0.5
	_assert(absf(menu_center.x - main.get_viewport_rect().size.x * 0.5) < 2.0 and absf(menu_center.y - main.get_viewport_rect().size.y * 0.5) < 2.0, "主菜单卡片在不同窗口尺寸下保持视口居中")
	_assert(menu_content.size.x >= menu_card.size.x * 0.82, "主菜单内容横向铺满卡片，不再挤在左侧")
	_assert(menu_content.get_child(0).get_child(1).get_theme_font_size("font_size") >= 48, "主菜单标题使用清楚的展示字号")
	main._ui_scale = 1.5
	main._show_settings()
	await process_frame
	await process_frame
	var settings_dialog: AcceptDialog
	for child in main.menu_layer.get_children():
		if child is AcceptDialog: settings_dialog = child
	_assert(settings_dialog != null, "设置窗口可以从主菜单打开")
	if settings_dialog != null:
		var settings_scroll: ScrollContainer = settings_dialog.get_child(0) as ScrollContainer
		_assert(settings_scroll != null and settings_scroll.custom_minimum_size.x >= 600.0, "高缩放设置窗口保留足够文字排版宽度")
		if settings_scroll != null and settings_scroll.get_child_count() > 0:
			var settings_content: Control = settings_scroll.get_child(0)
			_assert(settings_content.size.x >= settings_scroll.size.x - 2.0, "设置说明随窗口宽度展开，避免窄列逐字换行")
			_assert(_find_button(settings_content, "启用定时自动存档") != null, "设置页提供定时自动存档开关")
			_assert(_find_button(settings_content, "启用轻量界面淡入动效") != null, "设置页提供界面动效开关")
			_assert(_contains_label_text(settings_content, "现实时间") and _contains_label_text(settings_content, "手动存档会另存"), "自动存档设置明确说明计时方式与手动副本")
		settings_dialog.queue_free()
	await process_frame
	main._apply_ui_scale(1.75, true)
	await process_frame
	await process_frame
	var reopened_settings: AcceptDialog
	for child in main.menu_layer.get_children():
		if child is AcceptDialog: reopened_settings = child
	_assert(reopened_settings != null, "更改界面缩放并重排主菜单后设置窗口仍保持打开")
	if reopened_settings != null:
		var reopened_scroll: ScrollContainer = reopened_settings.get_child(0) as ScrollContainer
		var reopened_content: Control = reopened_scroll.get_child(0) as Control if reopened_scroll != null and reopened_scroll.get_child_count() > 0 else null
		var reopened_picker: OptionButton = reopened_content.get_child(2) as OptionButton if reopened_content != null and reopened_content.get_child_count() > 2 else null
		_assert(reopened_picker != null and reopened_picker.selected == 3, "设置重开后显示刚刚选择的 175% 缩放")
		reopened_settings.queue_free()
	await process_frame
	main._ui_scale = 1.0
	var state := WorldData.new_world("shanghai", "blank")
	state["onboarding"] = {"active": false, "step": 0, "completed": false}
	state.tutorialDone = true
	main._load_world(state)
	await process_frame
	var timer_interval_before: int = int(main.timed_autosave_interval_minutes)
	var timer_enabled_before: bool = bool(main.timed_autosave_enabled)
	var timer_elapsed_before := int(main.world.simulation.get("elapsedMinutes", 420))
	main.timed_autosave_enabled = true
	main.timed_autosave_interval_minutes = 2
	main.autosave_elapsed_seconds = 0.0
	main.save_dirty = true
	main._process(119.0)
	_assert(main.save_dirty and is_equal_approx(main.autosave_elapsed_seconds, 119.0), "定时自动存档在间隔到达前不会提前写入")
	main._process(2.0)
	var timed_saved := SaveManager.load_world("shanghai", "blank")
	_assert(not main.save_dirty and bool(timed_saved.get("ok", false)), "达到现实时间间隔后自动保存并清除未保存状态")
	_assert(int(main.world.simulation.get("elapsedMinutes", 420)) == timer_elapsed_before, "暂停期间定时保存不会推进游戏时间")
	main.timed_autosave_enabled = timer_enabled_before
	main.timed_autosave_interval_minutes = timer_interval_before
	main._show_save_menu()
	var save_center: AcceptDialog
	for child in main.get_children():
		if child is AcceptDialog and child.title == "存档中心": save_center = child
	var save_tabs: TabContainer = save_center.find_child("SaveCenterTabs", true, false) as TabContainer if save_center != null else null
	_assert(save_tabs != null and save_tabs.get_child_count() == 2 and _find_button(save_center, "当前进度另存为…") != null and _find_button(save_center, "删除自动进度") != null, "统一存档中心提供自动进度删除及当前进度另存入口")
	if save_center != null: save_center.queue_free()
	await process_frame
	main._prompt_manual_save()
	var manual_save_dialog: ConfirmationDialog
	for child in main.get_children():
		if child is ConfirmationDialog and child.title == "当前进度另存为": manual_save_dialog = child
	var manual_name_edit: LineEdit = _find_line_edit(manual_save_dialog) if manual_save_dialog != null else null
	_assert(manual_name_edit != null, "手动存档窗口提供可编辑名称")
	var ui_manual_path := ""
	if manual_save_dialog != null and manual_name_edit != null:
		manual_name_edit.text = "UI流程检查存档"
		manual_save_dialog.confirmed.emit()
		await process_frame
		for entry in SaveManager.list_manual_snapshots():
			if str(entry.get("name", "")) == "UI流程检查存档": ui_manual_path = str(entry.get("path", ""))
	_assert(not ui_manual_path.is_empty() and FileAccess.file_exists(ui_manual_path), "确认后创建独立命名的手动存档")
	main._show_manual_load_menu()
	await process_frame
	var manual_save_center: AcceptDialog
	for child in main.get_children():
		if child is AcceptDialog and child.title == "存档中心": manual_save_center = child
	var manual_tabs: TabContainer = manual_save_center.find_child("SaveCenterTabs", true, false) as TabContainer if manual_save_center != null else null
	var manual_page: Control = manual_save_center.find_child("ManualSaves", true, false) as Control if manual_save_center != null else null
	_assert(manual_tabs != null and manual_tabs.current_tab == 1 and manual_page != null and manual_page.size.y > 0.0 and _contains_label_text(manual_page, "UI流程检查存档"), "存档中心命名页可见并列出已保存的进度")
	var load_manual_button := _find_button(manual_page, "载入")
	if load_manual_button != null:
		load_manual_button.pressed.emit()
		await process_frame
	var manual_load_confirmation: ConfirmationDialog
	for child in main.get_children():
		if child is ConfirmationDialog and child.title == "载入手动存档？": manual_load_confirmation = child
	_assert(manual_load_confirmation != null and str(manual_load_confirmation.dialog_text).contains("UI流程检查存档"), "选择手动存档后显示载入确认及目标名称")
	if manual_load_confirmation != null:
		manual_load_confirmation.canceled.emit()
		manual_load_confirmation.queue_free()
	if not ui_manual_path.is_empty(): SaveManager.delete_manual_snapshot(ui_manual_path.get_file())
	main.left_tab = "tasks"
	main.world["challengeMode"] = "neighborhood"
	main._refresh_left_panel()
	await process_frame
	_assert(_find_button(main.left_content, "继续自由扩建") != null, "街区挑战提供退出目标层并继续自由扩建的入口")
	main.world["challengeMode"] = "free"
	main.left_tab = "routes"
	main._refresh_left_panel()
	var complexity_summary: Dictionary = main._network_complexity_summary()
	_assert(is_zero_approx(float(complexity_summary.get("lengthKm", -1.0))) and int(complexity_summary.get("curves", -1)) == 0 and int(complexity_summary.get("transfers", -1)) == 0, "空白方案复杂度指标可计算且不会生成虚假里程或换乘")
	main._complexity_expanded = true
	main._refresh_right_panel()
	await process_frame
	_assert(_contains_label_text(main.right_content, "不合成为工程评分"), "复杂度摘要明确说明是游戏比较信息而非工程评分")
	main._complexity_expanded = false
	main._refresh_right_panel()
	var original_onboarding: Dictionary = main.world.get("onboarding", {}).duplicate(true)
	var original_tool := str(main.current_tool)
	var guide := OnboardingScript.create_state("shanghai", "blank", false)
	guide.active = true
	guide.step = 1
	main.world["onboarding"] = guide
	main.current_tool = "station"
	main.map_view.tool = "station"
	main.map_view.draft_station.clear()
	main._refresh_onboarding_card()
	await process_frame
	var guide_focus: Dictionary = main._onboarding_focus_spec()
	_assert(str(guide_focus.get("kind", "")) == "map" and str(guide_focus.get("message", "")).contains("附近"), "教程直接聚焦推荐站址区域，而不是用教学卡按钮代替操作")
	_assert(main.tutorial_spotlight.active and main.tutorial_spotlight.mouse_filter == Control.MOUSE_FILTER_IGNORE, "教程聚焦层压暗其他界面且保持鼠标点击穿透")
	_assert(_find_button(main.onboarding_panel, "定位当前教学对象") == null, "教学卡不再显示大号定位按钮")
	main.map_view.draft_station = {"id":"tutorial-draft", "name":"教学预览站", "latlng":[31.2304, 121.4768], "heading":90.0, "lengthM":118.8, "widthM":20.0, "vehicleId":"B-6", "routeIds":[]}
	main._refresh_tools()
	guide_focus = main._onboarding_focus_spec()
	_assert(str(guide_focus.get("key", "")) == "confirm_station" and is_instance_valid(main.tutorial_targets.get("confirm_station")), "站体预览后焦点跟随到底栏真实确认按钮")
	guide.step = 3
	main.current_tool = "select"
	main.map_view.tool = "select"
	main.map_view.draft_station.clear()
	main._refresh_onboarding_card()
	main._refresh_tools()
	await process_frame
	guide_focus = main._onboarding_focus_spec()
	_assert(str(guide_focus.get("key", "")) == "tool_track", "铺轨教学聚焦真实底栏轨道工具")
	main.world["onboarding"] = original_onboarding
	main.current_tool = original_tool
	main.map_view.tool = original_tool
	main.map_view.draft_station.clear()
	main._refresh_onboarding_card()
	main._refresh_tools()
	await process_frame

	var initial_zoom: int = main.map_view.current_zoom
	var scaled_label: Label = main._label("可读性检查", 14, Color.WHITE)
	main.add_child(scaled_label)
	for scale in [1.0, 1.25, 1.5, 1.75]:
		main._apply_ui_scale(scale)
		_assert(main.map_view.ui_scale == scale and main._theme.default_font_size == roundi(16.0 * scale), "界面缩放 %d%% 会同步调整正文与控件" % roundi(scale * 100.0))
		_assert(scaled_label.get_theme_font_size("font_size") == roundi(14.0 * scale), "界面缩放 %d%% 会同步调整辅助文字" % roundi(scale * 100.0))
		_assert(main.map_view.current_zoom == initial_zoom, "界面缩放与地图镜头级别相互独立")
		var logical_width: float = main.get_viewport_rect().size.x / scale
		_assert(main._layout_narrow == (logical_width < 1100.0), "逻辑宽度不足 1100 时侧栏自动收起")
		var wants_two_rows: bool = logical_width < 1440.0
		_assert((main._top_actions.get_parent() == main._top_content) == wants_two_rows, "顶部运行栏按宽度自动换行为一行或两行")
		if scale == 1.75:
			var saved_onboarding: Dictionary = main.world.get("onboarding", {}).duplicate(true)
			var layout_onboarding := OnboardingScript.create_state("shanghai", "blank", false)
			layout_onboarding.active = true
			layout_onboarding.step = 1
			main.world["onboarding"] = layout_onboarding
			main.current_tool = "select"
			main.map_view.tool = "select"
			main._refresh_onboarding_card()
			await process_frame
			_assert(not main._mode_badge.visible, "窄屏高缩放时隐藏重复模式标签，避免顶部栏换行溢出")
			_assert(main.onboarding_panel.size.y <= main.map_view.size.y - 8.0, "175%缩放时教学卡完整留在地图区域，不被底栏遮挡")
			var focus_spec: Dictionary = main._onboarding_focus_spec()
			_assert(str(focus_spec.get("key", "")) == "tool_station" and main.tutorial_spotlight.active, "175%缩放时教程仍聚焦真实车站工具")
			var focus_button: Control = main.tutorial_targets.get("tool_station")
			_assert(is_instance_valid(focus_button) and Rect2(Vector2.ZERO, main.get_viewport_rect().size).intersects(focus_button.get_global_rect()), "缩放后教学焦点重新定位到可见工具")
			main.world["onboarding"] = saved_onboarding
			main.current_tool = original_tool
			main.map_view.tool = original_tool
			main._refresh_onboarding_card()
	var layout_original_onboarding: Dictionary = main.world.get("onboarding", {}).duplicate(true)
	var layout_guide := OnboardingScript.create_state("shanghai", "blank", false)
	layout_guide.active = true
	layout_guide.step = 1
	main.world["onboarding"] = layout_guide
	main.current_tool = "select"
	main.map_view.tool = "select"
	main._refresh_onboarding_card()
	main._refresh_tools()
	for window_size in [Vector2i(1366, 768), Vector2i(1600, 980), Vector2i(1920, 1080)]:
		root.size = window_size
		for scale in [1.0, 1.25, 1.5, 1.75]:
			main._apply_ui_scale(scale)
			await process_frame
			await process_frame
			main._update_tutorial_spotlight()
			var focus_button: Control = main.tutorial_targets.get("tool_station")
			var viewport_rect := Rect2(Vector2.ZERO, main.get_viewport_rect().size)
			_assert(main.tutorial_spotlight.active and is_instance_valid(focus_button) and viewport_rect.intersects(focus_button.get_global_rect()), "教程在 %d×%d、%d%% 下仍聚焦可见的真实车站工具" % [window_size.x, window_size.y, roundi(scale * 100.0)])
			_assert(viewport_rect.intersects(main.tutorial_spotlight.target_rect), "教程提示目标在 %d×%d、%d%% 下保持在窗口内" % [window_size.x, window_size.y, roundi(scale * 100.0)])
	main.world["onboarding"] = layout_original_onboarding
	main.current_tool = original_tool
	main.map_view.tool = original_tool
	main._refresh_onboarding_card()
	main._refresh_tools()
	root.size = Vector2i(1366, 768)
	main._apply_ui_scale(1.75)
	await process_frame
	await process_frame
	_assert(main.map_view.size.y >= 360.0, "1366×768 且 175% 界面缩放时地图仍保留至少 360 像素高度")
	var attribution_rect: Rect2 = main._attribution_panel.get_global_rect()
	var footer_rect: Rect2 = main._footer_panel.get_global_rect()
	_assert(not attribution_rect.intersects(footer_rect), "地图署名与底部建设工具保持分离")
	_assert(str(main.attribution_label.text).contains("2026-") and not str(main.attribution_label.text).contains("GMT"), "地图署名显示短日期，完整快照信息放入详情")
	root.size = Vector2i(1600, 980)
	main._apply_ui_scale(1.0)
	await process_frame
	var preferences_script = load("res://scripts/ui_preferences.gd")
	_assert(preferences_script.save_scale(1.75) == OK and preferences_script.load_scale() == 1.75, "界面缩放设置可保存并恢复")
	preferences_script.save_scale(1.0)
	scaled_label.queue_free()
	await process_frame
	main._apply_ui_scale(1.0)

	main.map_view.current_zoom = 16
	main.map_view.current_center = [31.2304, 121.4768]
	main.map_view.set_world(main.world)
	var first_ll: Array = [31.2304, 121.4737]
	var second_ll: Array = [31.2304, 121.4800]
	main.map_view.draft_station = {"name":"人民广场", "latlng":first_ll, "heading":90.0, "lengthM":118.8, "widthM":20.0, "depthM":-15.0, "vehicleId":"B-6", "routeIds":[]}
	main._confirm_station()
	var first_id := str(main.world.stations[0].id)
	main.map_view.draft_station = {"name":"世纪大道", "latlng":second_ll, "heading":90.0, "lengthM":118.8, "widthM":20.0, "depthM":-15.0, "vehicleId":"B-6", "routeIds":[]}
	main._confirm_station()
	var second_id := str(main.world.stations[1].id)
	var generated_station_name: String = main._next_station_name()
	_assert(generated_station_name.begins_with("新建车站 ") and generated_station_name != str(main.world.stations[0].get("name", "")) and generated_station_name != str(main.world.stations[1].get("name", "")), "默认新站名称带编号，避免连续放置时重名")
	main._select_object("station", first_id)
	_assert(main._right_requested and main.right_content.get_child_count() > 0, "点击车站会自动展开并刷新右侧详情")
	_assert(not main._station_overlaps(main.world.stations[0]), "拖动或旋转检查不会把车站自身视为重叠")
	root.size = Vector2i(1366, 768)
	main._update_responsive_layout()
	main._select_object("station", first_id)
	_assert(main._right_requested and main._left_requested and not main._layout_narrow, "1366逻辑宽度下详情抽屉覆盖地图，线路侧栏保持停靠")
	main._on_map_clicked([], "", "", "")
	_assert(not main._right_requested and main._left_requested, "1366逻辑宽度下点击地图空白会收起详情抽屉")
	root.size = Vector2i(1600, 980)
	main._update_responsive_layout()
	_assert(main.world.routes.is_empty(), "空白开局可以先建站，不会强制创建运营线路")
	_assert(main.world.trackEdges.is_empty() and main.world.trackLinks.is_empty(), "新站自带站内轨道，但尚未擅自连接站间轨道")

	var first_station: Dictionary = WorldData.find_station(main.world, first_id)
	var second_station: Dictionary = WorldData.find_station(main.world, second_id)
	main.map_view.tool = "select"
	main.map_view._refresh_camera_cache()
	var station_body_hit: Dictionary = main.map_view._pick(main.map_view._station_screen(first_station) + Vector2(18.0, 0.0))
	_assert(str(station_body_hit.get("type", "")) == "station" and str(station_body_hit.get("id", "")) == first_id, "点击站体内部即可选中，不必命中中心点")
	main.map_view.current_zoom = 10
	main.map_view._refresh_camera_cache()
	main.map_view.tool = "track"
	var ambiguous_endpoint: Dictionary = main.map_view._pick(main.map_view._station_screen(first_station))
	_assert(str(ambiguous_endpoint.get("type", "")) == "endpoint_choice" and main.map_view.endpoint_choice_candidates.size() == 2, "缩小地图时相邻的 A／B 端会提供明确选择")
	main.map_view.current_zoom = 16
	main.map_view._refresh_camera_cache()
	main.map_view.tool = "select"
	var first_end: Array = WorldData.station_endpoint(first_station, "end")
	var second_start: Array = WorldData.station_endpoint(second_station, "start")
	var ref_lat := float(WorldData.city("shanghai").center[0])
	TrackNetwork.ensure_station_nodes(main.world)
	var first_end_local := Geo.local_m(first_end, ref_lat)
	var free_node_location := Geo.from_local(first_end_local + Vector2(main.map_view._camera_mpp * 13.0, 0.0), ref_lat)
	main.world.trackNodes.append({"id":"near-free-node", "latlng":free_node_location, "depthM":-15.0, "stationId":"", "side":""})
	main.map_view.tool = "track"
	main.map_view.requested_redraw()
	var close_cursor: Vector2 = main.map_view._to_screen(first_end) + Vector2(10.0, 0.0)
	var nearest_snap: Dictionary = main.map_view._pick(close_cursor)
	_assert(str(nearest_snap.get("type", "")) == "track_node" and str(nearest_snap.get("id", "")) == "near-free-node", "较近的轨道自由节点优先于 20 像素内较远的站端")
	var test_snap_candidates: Array[Dictionary] = [
		{"type":"endpoint", "id":first_id, "side":"start", "latlng":WorldData.station_endpoint(first_station, "start")},
		{"type":"endpoint", "id":first_id, "side":"end", "latlng":WorldData.station_endpoint(first_station, "end")}
	]
	main._set_tool("track")
	main.endpoint_choice_candidates = test_snap_candidates.duplicate(true)
	main.map_view.endpoint_choice_candidates = test_snap_candidates.duplicate(true)
	main._on_map_clicked([], "endpoint_choice", "", "")
	_assert(main.interaction_state.phase == "choose_snap" and main.interaction_state.snap_candidates.size() == 2, "A／B 端选择列表与地图吸附候选共用同一交互状态")
	main._cancel_tool_step()
	_assert(main.interaction_state.snap_candidates.is_empty() and main.endpoint_choice_candidates.is_empty(), "取消吸附选择会同时清理地图与操作状态")
	main.world.trackNodes = main.world.trackNodes.filter(func(node: Dictionary): return str(node.get("id", "")) != "near-free-node")
	main.map_view.tool = "select"
	var control := Geo.from_local((Geo.local_m(first_end, ref_lat) + Geo.local_m(second_start, ref_lat)) * 0.5 + Vector2(0.0, 140.0), ref_lat)
	main._set_tool("track_curve")
	main._on_map_clicked(first_end, "endpoint", first_id, "end")
	main._on_map_clicked(control, "", "", "")
	main._on_map_clicked(second_start, "endpoint", second_id, "start")
	_assert(not main.map_view.track_end_ref.is_empty(), "曲线轨道先显示待确认预览")
	main._commit_track_preview()
	_assert(main.world.trackEdges.size() == 1 and main.world.trackLinks.is_empty(), "站端之间建立独立的物理轨道，不绑定运营线路")
	var edge_id := str(main.world.trackEdges[0].id)
	var original_edge_for_repair: Dictionary = main.world.trackEdges[0].duplicate(true)
	var rotated_candidate: Dictionary = WorldData.find_station(main.world, first_id).duplicate(true)
	rotated_candidate["heading"] = 73.0
	var rotated_preview: Dictionary = main._station_preview_analysis(rotated_candidate, main.world)
	_assert(str(rotated_preview.get("issue", "")).is_empty(), "车站旋转预览会统一检查相邻曲线")
	var rotated_preview_state: Dictionary = rotated_preview.get("state", {})
	var preview_edge: Dictionary = TrackNetwork.all_physical_edges(rotated_preview_state)[0]
	var preview_points := TrackNetwork.edge_points(preview_edge, rotated_preview_state, ref_lat, 8)
	var preview_tangent := Geo.local_m(preview_points[1], ref_lat) - Geo.local_m(preview_points[0], ref_lat)
	_assert(preview_tangent.normalized().dot(WorldData.station_outward(rotated_candidate, "end")) > 0.95, "旋转预览重算站端控制柄并保持曲线相切")
	var straight_state: Dictionary = main.world.duplicate(true)
	straight_state.trackLinks.clear(); straight_state.trackEdges.clear()
	TrackNetwork.ensure_station_nodes(straight_state)
	var straight_edge := {"id":"preview-straight", "aNodeId":WorldData.find_station(straight_state, first_id).endpointNodes.B, "bNodeId":WorldData.find_station(straight_state, second_id).endpointNodes.A, "geometry":"straight", "depthM":-15.0, "routeIds":[]}
	straight_state.trackEdges.append(straight_edge)
	var straight_candidate: Dictionary = WorldData.find_station(straight_state, first_id).duplicate(true)
	straight_candidate.latlng = Geo.from_local(Geo.local_m(straight_candidate.latlng, ref_lat) + Vector2(0, 200), ref_lat)
	var straight_preview: Dictionary = main._station_preview_analysis(straight_candidate, straight_state)
	var converted_edge: Dictionary = TrackNetwork.all_physical_edges(straight_preview.state)[0]
	_assert(str(straight_preview.get("issue", "")).is_empty() and str(converted_edge.get("geometry", "")) == "bezier", "横移直线接轨站点时预览自动转为两端顺接曲线")
	if str(converted_edge.get("geometry", "")) == "bezier":
		var converted_points := TrackNetwork.edge_points(converted_edge, straight_preview.state, ref_lat, 16)
		var start_tangent := Geo.local_m(converted_points[1], ref_lat) - Geo.local_m(converted_points[0], ref_lat)
		_assert(start_tangent.normalized().dot(WorldData.station_outward(straight_candidate, "end")) > 0.99, "横移后的站端预览切线与站体方向一致")
	var world_position_before_preview: Array = WorldData.find_station(main.world, first_id).get("latlng", []).duplicate()
	var overlapping_move := Geo.from_local(Geo.local_m(second_station.get("latlng", []), ref_lat), ref_lat)
	main._station_preview_last_usec = 0
	main._on_station_drag_preview(first_id, overlapping_move)
	_assert(main.map_view.station_preview_edges.has(edge_id) and not main.map_view.station_preview_issue.is_empty(), "移站时同步绘制关联轨道并提前标出站体冲突")
	_assert(WorldData.find_station(main.world, first_id).get("latlng", []) == world_position_before_preview, "移站草稿预览不会提前改写正式站址")
	main.current_tool = "move_station"
	main.map_view.tool = "move_station"
	main._cancel_tool_step()
	_assert(main.station_construction_draft.kind.is_empty() and main.map_view.station_preview_edges.is_empty() and main.interaction_state.error_message.is_empty(), "取消移站预览会清除临时几何和持续错误提示")
	main._clear_station_move_preview()
	_assert(str(main.world.trackEdges[0].geometry) == "bezier", "曲线铺轨保留预览使用的曲线几何")
	var curve_points := TrackNetwork.edge_points(main.world.trackEdges[0], main.world, ref_lat, 8)
	var curve_start_tangent := Geo.local_m(curve_points[1], ref_lat) - Geo.local_m(curve_points[0], ref_lat)
	_assert(curve_start_tangent.normalized().dot(WorldData.station_outward(first_station, "end")) > 0.95, "曲线从车站端点沿站体方向顺接")
	var edge_length: float = TrackNetwork.edge_length_m(main.world.trackEdges[0], main.world, ref_lat)
	_assert(edge_length > Geo.local_m(first_end, ref_lat).distance_to(Geo.local_m(second_start, ref_lat)), "弧线里程长于端点直线距离")
	var saved_nodes: Array = main.world.trackNodes.duplicate(true)
	var saved_edges: Array = main.world.trackEdges.duplicate(true)
	var saved_links: Array = main.world.trackLinks.duplicate(true)
	main.world.trackNodes.clear(); main.world.trackEdges.clear(); main.world.trackLinks.clear()
	var crossing_center := Geo.local_m([31.2304, 121.4737], ref_lat)
	main.world.trackNodes = [
		{"id":"cross-left", "latlng":Geo.from_local(crossing_center + Vector2(-100, 0), ref_lat), "depthM":-10.0},
		{"id":"cross-right", "latlng":Geo.from_local(crossing_center + Vector2(100, 0), ref_lat), "depthM":-30.0}
	]
	main.world.trackEdges = [{"id":"crossing-edge", "aNodeId":"cross-left", "bNodeId":"cross-right", "geometry":"straight", "depthM":-20.0}]
	var candidate_a := Geo.from_local(crossing_center + Vector2(-50, -100), ref_lat)
	var candidate_b := Geo.from_local(crossing_center + Vector2(-50, 300), ref_lat)
	var candidate_points: Array = [candidate_a, candidate_b]
	var crossing_candidate := {"aNodeId":"cross-candidate-a", "bNodeId":"cross-candidate-b", "depthM":-25.0}
	_assert(not main._track_crossing_conflict(candidate_points, crossing_candidate, -5.0, -45.0, ref_lat).is_empty(), "交叉检查使用交点深度，不使用两段平均深度")
	_assert(main._track_crossing_conflict(candidate_points, crossing_candidate, -30.0, 10.0, ref_lat).is_empty(), "交叉点高差达到五米后可通过")
	main.world.trackNodes = saved_nodes; main.world.trackEdges = saved_edges; main.world.trackLinks = saved_links
	_assert(main.map_view.current_depth_m == -15.0, "地下建设默认深度为 15 米")
	main._adjust_track_depth(-5.0)
	_assert(main.map_view.current_depth_m == -20.0, "深度控制按 5 米步进")
	main._adjust_track_depth(5.0)
	_assert(main.map_view.current_depth_m == -15.0, "深度可恢复至默认值")

	main._set_tool("line")
	main._on_map_clicked(first_ll, "station", first_id, "")
	main._on_map_clicked(second_ll, "station", second_id, "")
	_assert(main.line_draft_stops.size() == 2, "运营线路按玩家点击次序选择停站")
	main._confirm_operating_line()
	_assert(main.world.routes.size() == 1, "物理轨网完成后才创建运营线路")
	var route: Dictionary = WorldData.find_route(main.world, main.active_route_id)
	_assert(bool(route.get("networkBased", false)) and route.get("stationOrder", []).size() == 2, "运营线路引用连续轨网和停站顺序")
	var status_unoperated: Dictionary = main._station_service_status(first_station)
	_assert(str(status_unoperated.get("text", "")).begins_with("已接轨"), "车站详情明确区分已接轨与尚未运营")
	var route_path: Dictionary = RoutePathScript.for_route(route, main.world, ref_lat)
	_assert(bool(route_path.get("valid", false)), "线路路径与物理轨网共享同一几何结果")
	var curved_segment: Dictionary = route_path.directions[0].segments[0]
	_assert(float(curved_segment.get("minimumCurveRadiusM", INF)) < INF and float(curved_segment.get("curveSpeedLimitKmh", -1.0)) > 0.0, "曲线半径参与计算并生成标注为游戏估算的限速")
	var locked_path: Array = route.get("directions", [])[0].get("edgePathsBySegment", [])[0]
	_assert(locked_path.size() == 1 and str(locked_path[0].get("id", "")) == edge_id, "运营线路保存创建时确认的有序轨道走向")
	var extension_center := Geo.from_local(Geo.local_m(second_ll, ref_lat) + Vector2(720.0, 0.0), ref_lat)
	var extension_station := WorldData.create_station(main.world, extension_center, 90.0, "", "B-6", -15.0)
	TrackNetwork.ensure_station_nodes(main.world)
	var extension_edge_id := "extension-test-edge"
	main.world.trackEdges.append({"id":extension_edge_id, "aNodeId":TrackNetwork.station_node_id(second_station, "end"), "bNodeId":TrackNetwork.station_node_id(extension_station, "start"), "geometry":"straight", "depthM":-15.0, "routeIds":[]})
	main._begin_route_extension(str(route.get("id", "")), false)
	main.line_draft_stops.append(str(extension_station.get("id", "")))
	main._ensure_line_draft_path_options()
	main._update_line_draft_preview()
	main._confirm_operating_line()
	var extended_route: Dictionary = WorldData.find_route(main.world, str(route.get("id", "")))
	_assert(str(extended_route.get("id", "")) == str(route.get("id", "")) and extended_route.get("stationOrder", []).size() == 3, "从终点扩建会保留原线路身份并增加停站")
	_assert(not bool(extended_route.get("open", true)) and bool(RoutePathScript.for_route(extended_route, main.world, ref_lat).get("valid", false)), "线路扩建保存完整新走向并要求玩家检查后重新开通")
	main._do_undo()
	var undone_extension: Dictionary = WorldData.find_route(main.world, str(route.get("id", "")))
	_assert(undone_extension.get("stationOrder", []).size() == 2, "线路延伸作为一个完整撤销步骤")
	main._do_redo()
	var redone_extension: Dictionary = WorldData.find_route(main.world, str(route.get("id", "")))
	_assert(redone_extension.get("stationOrder", []).size() == 3, "线路延伸支持重做")
	main._do_undo()
	main.world.trackEdges = main.world.trackEdges.filter(func(edge: Dictionary): return str(edge.get("id", "")) != extension_edge_id)
	main.world.stations = main.world.stations.filter(func(station: Dictionary): return str(station.get("id", "")) != str(extension_station.get("id", "")))
	main.world.trackNodes = main.world.trackNodes.filter(func(node: Dictionary): return str(node.get("stationId", "")) != str(extension_station.get("id", "")))
	route = WorldData.find_route(main.world, str(route.get("id", "")))
	main._refresh_left_panel()
	var shortcut := {"id": "audit_shortcut", "aNodeId": WorldData.find_station(main.world, first_id).get("endpointNodes", {}).get("B", ""), "bNodeId": WorldData.find_station(main.world, second_id).get("endpointNodes", {}).get("A", ""), "geometry": "straight", "depthM": -15.0, "routeIds": []}
	main.world.trackEdges.append(shortcut)
	var route_path_after_shortcut: Dictionary = RoutePathScript.for_route(route, main.world, ref_lat)
	_assert(route_path_after_shortcut.get("directions", [])[0].get("segments", [])[0].get("linkIds", []) == [edge_id], "新增更短轨道不会悄悄改变已创建线路")
	main.world.trackEdges.erase(shortcut)
	main.history.execute("测试拆分轨道", func(state: Dictionary): main._split_track_edge(state, edge_id, 0.5, ref_lat))
	var split_path: Dictionary = RoutePathScript.for_route(route, main.world, ref_lat)
	_assert(bool(split_path.get("valid", false)) and split_path.directions[0].segments[0].linkIds.size() == 2, "拆分运营线路使用的轨道会同步更新有向路径")
	main._do_undo()
	route = WorldData.find_route(main.world, main.active_route_id)
	var restored_path: Dictionary = RoutePathScript.for_route(route, main.world, ref_lat)
	_assert(bool(restored_path.get("valid", false)) and restored_path.directions[0].segments[0].linkIds == [edge_id], "撤销轨道拆分同时恢复线路路径引用")
	var route_length_before: float = main._route_length_km(route)
	main._select_object("link", edge_id)
	_assert(main.selected_type == "link" and not main._find_link(edge_id).is_empty(), "物理轨道可以直接选中查看详情")
	main._on_curve_control_finished(edge_id, "curveA", [260.0, 0.0])
	var route_length_after: float = main._route_length_km(WorldData.find_route(main.world, main.active_route_id))
	_assert(route_length_after > route_length_before, "调整轨道曲线会更新真实里程")
	main.selected_type = "route"; main.selected_id = main.active_route_id
	main._open_route()
	_assert(bool(WorldData.find_route(main.world, main.active_route_id).open), "已接轨运营线路可开通")
	main._simulate_one_minute()
	_assert(main.world.simulation.minute == 421, "模拟固定推进一分钟")
	main._do_undo()
	_assert(not bool(WorldData.find_route(main.world, main.active_route_id).open), "撤销开通恢复线路草案")
	main._do_undo()
	route = WorldData.find_route(main.world, main.active_route_id)
	_assert(is_equal_approx(main._route_length_km(WorldData.find_route(main.world, main.active_route_id)), route_length_before), "撤销曲线调整恢复区间几何")
	main._do_undo()
	_assert(main.world.routes.is_empty() and main.world.trackEdges.size() == 1, "撤销运营线路不拆除其物理轨道")
	main._do_undo()
	_assert(main.world.trackEdges.is_empty(), "撤销铺轨恢复站点但移除连接轨道")
	_assert(main.world.simulation.minute == 421, "撤销规划不倒退模拟时间")
	main._do_redo()
	main._do_redo()
	main._do_redo()
	main._do_redo()
	_assert(main.world.trackEdges.size() == 1 and main.world.routes.size() == 1 and bool(WorldData.find_route(main.world, main.active_route_id).open), "连续重做能恢复轨道、运营线路和开通状态")
	main._apply_delete_link(edge_id)
	var deleted_route: Dictionary = WorldData.find_route(main.world, main.active_route_id)
	var deleted_route_path: Dictionary = RoutePathScript.for_route(deleted_route, main.world, ref_lat)
	_assert(main.world.trackEdges.is_empty() and not bool(deleted_route.get("open", true)) and not bool(deleted_route_path.get("valid", true)), "删除运营区间会暂停线路并明确留下待修复区间")
	_assert(SaveManager._validate_world(main.world).is_empty(), "含待修复空区间的规划仍可保存")
	main._do_undo()
	_assert(main.world.trackEdges.size() == 1 and bool(WorldData.find_route(main.world, main.active_route_id).get("open", false)), "撤销拆轨会一起恢复线路路径与运行状态")
	main._do_redo()
	_assert(main.world.trackEdges.is_empty() and SaveManager._validate_world(main.world).is_empty(), "重做拆轨后仍可保存修复中的线路")
	var broken_save := SaveManager.save_world(main.world)
	_assert(bool(broken_save.get("ok", false)), "删轨后的待修复线路可以保存")
	var replacement_edge: Dictionary = original_edge_for_repair.duplicate(true)
	replacement_edge["id"] = "repair_replacement_edge"
	main.world.trackEdges.append(replacement_edge)
	var repair_route_id := str(main.active_route_id)
	var repair_route: Dictionary = WorldData.find_route(main.world, repair_route_id)
	var repair_forward: Dictionary = repair_route.get("directions", [])[0]
	main._begin_route_segment_repair(repair_route_id, str(repair_forward.get("id", "")), 0)
	await process_frame
	await process_frame
	_assert(main.current_tool == "repair_route_segment" and not main.repair_path_options.is_empty(), "线路详情可为断开的相邻停站生成修复候选")
	_assert(main._footer_panel.size.y < 380.0 and main.tool_panel.get_children().all(func(child: Control): return child.size.y <= 64.0), "线路修复工具不会因旧控件或竖排文字撑满底栏")
	_assert(main.tool_instruction_label.text.contains("修复") and main.tool_instruction_label.text.contains("→"), "固定操作提示显示待修复的两个站名")
	_assert(main.map_view.line_draft_points.size() >= 2, "修复线路会在地图上高亮候选走向")
	main._confirm_route_segment_repair()
	await _confirm_impact(main)
	var repaired_route: Dictionary = WorldData.find_route(main.world, repair_route_id)
	var repaired_path: Dictionary = RoutePathScript.for_route(repaired_route, main.world, ref_lat)
	_assert(bool(repaired_path.get("valid", false)) and not bool(repaired_route.get("open", true)), "修复后正反向路径有效且线路保持暂停")
	_assert(str(repaired_route.get("directions", [])[0].get("edgePathsBySegment", [])[0][0].get("id", "")) == "repair_replacement_edge", "修复写入玩家确认的有向轨道编号")
	var repaired_save := SaveManager.save_world(main.world)
	var repaired_reload := SaveManager.load_world("shanghai", "blank")
	_assert(bool(repaired_save.get("ok", false)) and bool(repaired_reload.get("ok", false)) and bool(RoutePathScript.for_route(WorldData.find_route(repaired_reload.get("world", {}), repair_route_id), repaired_reload.get("world", {}), ref_lat).get("valid", false)), "修复走向保存并重新载入后保持一致")
	main._do_undo()
	_assert(not bool(RoutePathScript.for_route(WorldData.find_route(main.world, repair_route_id), main.world, ref_lat).get("valid", true)), "撤销修复会恢复待接通状态")
	main._do_redo()
	_assert(bool(RoutePathScript.for_route(WorldData.find_route(main.world, repair_route_id), main.world, ref_lat).get("valid", false)), "重做修复会恢复确认的线路走向")
	main._do_undo()
	main._do_undo()
	main.world.trackEdges = main.world.trackEdges.filter(func(edge: Dictionary): return str(edge.get("id", "")) != "repair_replacement_edge")
	var test_route_id: String = main.active_route_id
	var test_route_name: String = str(WorldData.find_route(main.world, test_route_id).get("name", "线路"))
	var history_before_delete: String = main.history.undo_label()
	for child in main.get_children():
		if child is AcceptDialog:
			_assert(str(child.dialog_text).contains("受影响列车"), "运行中撤销会说明列车与乘客的处理方式")
			child.queue_free()
	await process_frame
	main._delete_route(test_route_id)
	await process_frame
	var impact_dialog: ConfirmationDialog
	for child in main.get_children():
		if child is ConfirmationDialog: impact_dialog = child
	_assert(impact_dialog != null and impact_dialog.title == "确认影响运营", "删除运营线路前显示影响确认")
	if impact_dialog != null:
		_assert(impact_dialog.dialog_text.contains(test_route_name) and impact_dialog.dialog_text.contains("暂停模拟"), "运营影响提示列出线路与运行处理")
		impact_dialog.canceled.emit()
		await process_frame
	_assert(not WorldData.find_route(main.world, test_route_id).is_empty() and main.history.undo_label() == history_before_delete, "取消运营影响确认不会改规划或写入撤销历史")
	main._delete_route(test_route_id)
	await process_frame
	for child in main.get_children():
		if child is ConfirmationDialog: impact_dialog = child
	if impact_dialog != null:
		impact_dialog.confirmed.emit()
		await process_frame
	_assert(WorldData.find_route(main.world, test_route_id).is_empty(), "确认后才删除运营线路")
	main._do_undo()
	_assert(not WorldData.find_route(main.world, test_route_id).is_empty(), "运营影响操作可通过撤销恢复")
	var route_for_vehicle: Dictionary = WorldData.find_route(main.world, test_route_id)
	main._change_route_vehicle(test_route_id, "A-6")
	await _confirm_impact(main)
	_assert(str(WorldData.find_route(main.world, test_route_id).get("vehicleId", "")) == "A-6", "线路车型替换在所有站体通过旋转矩形与轨道检查后应用")
	for station_id in route_for_vehicle.get("stationOrder", []):
		var station := WorldData.find_station(main.world, str(station_id))
		_assert(float(station.get("lengthM", 0.0)) >= 140.0, "长编组线路的停站长度能容纳整列车辆")
	main._change_route_vehicle(test_route_id, "B-6")
	await _confirm_impact(main)
	for station_id in route_for_vehicle.get("stationOrder", []):
		var station := WorldData.find_station(main.world, str(station_id))
		_assert(float(station.get("lengthM", 0.0)) >= 140.0, "短编组线路不能缩短其他服务仍需要的共用站体")
	main._do_undo()
	_assert(str(WorldData.find_route(main.world, test_route_id).get("vehicleId", "")) == "A-6", "车型替换作为整体建设操作可撤销")
	var current_station := WorldData.find_station(main.world, first_id)
	var invalid_move := current_station.duplicate(true); invalid_move["latlng"] = second_station.get("latlng", []).duplicate()
	_assert(not main._station_geometry_issue(invalid_move).is_empty(), "移站预检会阻止与其他站体重叠并保留旧位置")
	var corrupt_city_path := SaveManager.save_path("beijing", "blank")
	var corrupt_file := FileAccess.open(corrupt_city_path, FileAccess.WRITE)
	if corrupt_file != null: corrupt_file.store_string("{broken"); corrupt_file.close()
	var beijing_index := -1
	for index in range(WorldData.cities().size()):
		if str(WorldData.cities()[index].get("id", "")) == "beijing": beijing_index = index
	main._on_city_change_requested(beijing_index)
	await process_frame
	_assert(main.active_city_id == "shanghai" and not main.world.is_empty(), "损坏的目标城市存档不会被空白世界覆盖")
	_assert(main.city_picker.selected == WorldData.cities().find_custom(func(city: Dictionary) -> bool: return str(city.get("id", "")) == "shanghai"), "载入损坏失败后城市选择恢复到当前城市")
	for child in main.get_children():
		if child is AcceptDialog: child.queue_free()
	if FileAccess.file_exists(corrupt_city_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_city_path))
	await process_frame
	var transition_calls: Array[bool] = []
	main.world["schemaVersion"] = 999
	main._request_world_transition(func(): transition_calls.append(true))
	await process_frame
	var save_choice: ConfirmationDialog = main.pending_transition_dialog
	_assert(main.save_failed and save_choice != null and save_choice.title == "保存未完成", "无法保存时提供明确的离开保护对话框")
	if save_choice != null:
		save_choice.canceled.emit(); save_choice.queue_free(); main.pending_transition_dialog = null
	await process_frame
	_assert(transition_calls.is_empty() and not main.world.is_empty(), "取消保存失败的离开操作会留在当前世界")
	main._request_world_transition(func(): transition_calls.append(true))
	await process_frame
	save_choice = main.pending_transition_dialog
	if save_choice != null:
		save_choice.custom_action.emit(&"discard"); save_choice.queue_free(); main.pending_transition_dialog = null
	await process_frame
	_assert(not transition_calls.is_empty(), "只有明确选择放弃未保存修改才继续离开")
	main.world["schemaVersion"] = WorldData.SAVE_VERSION
	main._autosave(false)
	if failures.is_empty():
		print("PASS: native UI workflow · station → independent track → operating line")
		quit(0)
	else:
		quit(1)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _confirm_impact(main: Node) -> void:
	for child in main.get_children():
		if child is ConfirmationDialog and child.title == "确认影响运营":
			child.confirmed.emit()
			child.queue_free()
			await process_frame
			return

func _find_button(root_node: Node, label: String) -> Button:
	if root_node is Button and str((root_node as Button).text) == label:
		return root_node as Button
	for child in root_node.get_children():
		var found := _find_button(child, label)
		if found != null: return found
	return null

func _find_line_edit(root_node: Node) -> LineEdit:
	if root_node is LineEdit: return root_node as LineEdit
	for child in root_node.get_children():
		var found := _find_line_edit(child)
		if found != null: return found
	return null

func _contains_label_text(root_node: Node, needle: String) -> bool:
	if root_node is Label and str((root_node as Label).text).contains(needle): return true
	for child in root_node.get_children():
		if _contains_label_text(child, needle): return true
	return false
