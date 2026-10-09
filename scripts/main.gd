extends Control

const MapViewScript = preload("res://scripts/map_view.gd")
const UiPreferencesScript = preload("res://scripts/ui_preferences.gd")
const MenuArtScript = preload("res://scripts/menu_art.gd")
const OnboardingScript = preload("res://scripts/onboarding.gd")
const TravelModelScript = preload("res://scripts/travel_model.gd")
const APP_BG := Color("#101b25")
const PANEL := Color("#162532")
const PANEL_LIGHT := Color("#1c3040")
const BORDER := Color("#2b4352")
const TEXT := Color("#e7edf0")
const MUTED := Color("#9db0bb")
const TEAL := Color("#4ad1ae")

var map_view: MapView
var world: Dictionary = {}
var active_city_id := "shanghai"
var active_route_id := ""
var selected_type := ""
var selected_id := ""
var current_tool := "select"
var history := CommandHistory.new()
var sim_accumulator := 0.0
var save_dirty := false
var tutorial_completed := false
var active_saves_page := 0
var city_picker: OptionButton
var speed_picker: OptionButton
var pause_button: Button
var undo_button: Button
var redo_button: Button
var save_badge: Label
var route_list: VBoxContainer
var right_content: VBoxContainer
var left_content: VBoxContainer
var tool_panel: HFlowContainer
var tool_instruction_label: Label
var toast_label: Label
var time_label: Label
var stats_label: Label
var demand_toggle: CheckButton
var hall_toggle: CheckButton
var menu_layer: Control
var menu_city_picker: OptionButton
var menu_continue_button: Button
var draft_route_id := ""
var _flow_cache_revision := -1
var _flow_cache: Array[Dictionary] = []
var _ui_scale := 1.0
var _theme: Theme
var _base_font: Font
var _bold_font: Font
var _left_panel: Control
var _right_panel: Control
var _footer_panel: Control
var _top_panel: Control
var attribution_label: Label
var _attribution_panel: PanelContainer
var _left_panel_button: Button
var _right_panel_button: Button
var _layer_panel: PanelContainer
var _top_content: VBoxContainer
var _top_primary_row: HBoxContainer
var _top_actions: HBoxContainer
var _top_spacer: Control
var _left_requested := true
var _right_requested := true
var _layout_narrow := false
var onboarding_panel: PanelContainer
var _more_tools_expanded := false

func _ready() -> void:
	WorldData.load_assets()
	name = "MetroAtlasDesktop"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderingServer.set_default_clear_color(APP_BG)
	_build_application()
	_show_main_menu()

func _process(delta: float) -> void:
	if world.is_empty(): return
	var sim: Dictionary = world.get("simulation", {})
	if not bool(sim.get("paused", true)):
		sim_accumulator += delta * float(sim.get("speed", 1))
		while sim_accumulator >= 1.0:
			sim_accumulator -= 1.0
			_simulate_one_minute()
			map_view.requested_redraw()
			if int(sim.get("minute", 420)) % 15 == 0:
				_autosave()
				_update_sim_labels()
			if bool(world.simulation.get("paused", true)):
				sim_accumulator = 0.0
				break

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not world.is_empty():
			world.simulation.paused = true
			_autosave()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not world.is_empty() and not bool(world.simulation.paused):
			world.simulation.paused = true
			_autosave()
			_update_topbar()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo: return
	var text_field := get_viewport().gui_get_focus_owner()
	if text_field is LineEdit or text_field is TextEdit: return
	if event.keycode == KEY_ESCAPE:
		_cancel_tool_step()
		get_viewport().set_input_as_handled()
		return
	var primary: bool = event.ctrl_pressed or event.meta_pressed
	if primary and event.keycode == KEY_Z:
		if event.shift_pressed: _do_redo()
		else: _do_undo()
		get_viewport().set_input_as_handled()
	elif primary and event.keycode == KEY_Y:
		_do_redo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R:
		if current_tool == "station" and not map_view.draft_station.is_empty():
			map_view.draft_station.heading = fposmod(float(map_view.draft_station.get("heading", 90.0)) + 15.0, 360.0)
			_on_draft_station_changed()
		elif selected_type == "station":
			_rotate_station(selected_id)
	elif event.keycode == KEY_SPACE and not world.is_empty():
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _build_application() -> void:
	_ui_scale = UiPreferencesScript.load_scale()
	_base_font = load("res://fonts/NotoSansSC.ttf")
	_base_font = _font_weight(_base_font, 500)
	_bold_font = _font_weight(load("res://fonts/NotoSansSC.ttf"), 700)
	_theme = Theme.new()
	_theme.default_font = _base_font
	_theme.default_font_size = roundi(18.0 * _ui_scale)
	theme = _theme
	var background := ColorRect.new()
	background.name = "Background"
	background.color = APP_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	map_view = MapViewScript.new()
	map_view.name = "CityMap"
	map_view.bold_font = _bold_font
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_view.offset_left = 280
	map_view.offset_top = 68
	map_view.offset_right = -310
	map_view.offset_bottom = -92
	add_child(map_view)
	map_view.map_clicked.connect(_on_map_clicked)
	map_view.station_dragged.connect(_on_station_drag_preview)
	map_view.station_drag_finished.connect(_on_station_drag_finished)
	map_view.curve_control_finished.connect(_on_curve_control_finished)
	map_view.camera_changed.connect(_on_camera_changed)
	map_view.cancel_requested.connect(_cancel_tool_step)
	map_view.draft_station_changed.connect(_on_draft_station_changed)
	get_viewport().size_changed.connect(_update_responsive_layout)

func _font_weight(base: Font, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	var text_server := TextServerManager.get_primary_interface()
	variation.variation_opentype = {text_server.name_to_tag("wght"): weight}
	return variation

func _apply_ui_scale(value: float) -> void:
	var previous_scale := _ui_scale
	_ui_scale = value if UiPreferencesScript.SCALE_OPTIONS.has(value) else 1.0
	if is_instance_valid(_theme): _theme.default_font_size = roundi(18.0 * _ui_scale)
	if is_instance_valid(map_view): map_view.ui_scale = _ui_scale
	var ratio := _ui_scale / maxf(0.01, previous_scale)
	_apply_ui_scale_to_node(self, ratio)
	_update_responsive_layout()

func _apply_ui_scale_to_node(node: Node, ratio: float) -> void:
	if node is Control:
		if node.has_meta("ui_base_font_size"):
			var base_size := int(node.get_meta("ui_base_font_size"))
			node.add_theme_font_size_override("font_size", roundi(float(base_size) * _ui_scale))
		node.custom_minimum_size *= ratio
		node.offset_left *= ratio; node.offset_top *= ratio; node.offset_right *= ratio; node.offset_bottom *= ratio
	for child in node.get_children():
		_apply_ui_scale_to_node(child, ratio)

func _update_responsive_layout() -> void:
	if not is_instance_valid(map_view) or not is_instance_valid(_left_panel) or not is_instance_valid(_right_panel): return
	var logical_width := get_viewport_rect().size.x / maxf(1.0, _ui_scale)
	var should_collapse := logical_width < 1440.0 or _ui_scale >= 1.5
	var use_two_top_rows := logical_width < 1760.0 or _ui_scale >= 1.25
	if is_instance_valid(_top_content) and is_instance_valid(_top_primary_row) and is_instance_valid(_top_actions):
		if use_two_top_rows and _top_actions.get_parent() == _top_primary_row:
			_top_primary_row.remove_child(_top_actions)
			_top_content.add_child(_top_actions)
		elif not use_two_top_rows and _top_actions.get_parent() == _top_content:
			_top_content.remove_child(_top_actions)
			_top_primary_row.add_child(_top_actions)
	if should_collapse != _layout_narrow:
		_layout_narrow = should_collapse
		_left_requested = not _layout_narrow
		_right_requested = not _layout_narrow
	_left_panel.visible = _left_requested
	_right_panel.visible = _right_requested
	var top_height := roundi((104.0 if use_two_top_rows else 76.0) * _ui_scale)
	var footer_height := roundi((158.0 if _ui_scale >= 1.25 else 144.0) * _ui_scale)
	if is_instance_valid(_top_panel): _top_panel.offset_bottom = top_height
	_left_panel.offset_top = top_height
	_left_panel.offset_bottom = -footer_height
	_left_panel.offset_right = 330.0 * _ui_scale
	_right_panel.offset_top = top_height
	_right_panel.offset_bottom = -footer_height
	_right_panel.offset_left = -350.0 * _ui_scale
	map_view.offset_left = 330.0 * _ui_scale if _left_panel.visible and not _layout_narrow else 0.0
	map_view.offset_top = top_height
	map_view.offset_right = -350.0 * _ui_scale if _right_panel.visible and not _layout_narrow else 0.0
	map_view.offset_bottom = -footer_height
	if is_instance_valid(_footer_panel): _footer_panel.offset_top = -footer_height
	if is_instance_valid(left_content): left_content.custom_minimum_size.x = 300.0 * _ui_scale
	if is_instance_valid(right_content): right_content.custom_minimum_size.x = 330.0 * _ui_scale
	if is_instance_valid(_left_panel_button): _left_panel_button.text = "线路 ▾" if _left_panel.visible else "线路 ▸"
	if is_instance_valid(_right_panel_button): _right_panel_button.text = "详情 ▾" if _right_panel.visible else "详情 ▸"
	if is_instance_valid(_layer_panel):
		_layer_panel.offset_left = -378.0 * _ui_scale if _right_panel.visible and not _layout_narrow else -362.0 * _ui_scale
		_layer_panel.offset_right = -12.0
	if is_instance_valid(_attribution_panel):
		_attribution_panel.offset_left = 12.0 if not _left_panel.visible or _layout_narrow else 308.0 * _ui_scale
		_attribution_panel.offset_right = 1120.0 * _ui_scale
		_attribution_panel.offset_top = -footer_height - roundi(34.0 * _ui_scale)
		_attribution_panel.offset_bottom = -footer_height - roundi(5.0 * _ui_scale)
	if is_instance_valid(attribution_label): attribution_label.add_theme_font_size_override("font_size", roundi(12.0 * _ui_scale))

func _show_main_menu() -> void:
	map_view.visible = false
	if is_instance_valid(menu_layer): menu_layer.queue_free()
	menu_layer = Control.new()
	menu_layer.name = "MainMenu"
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu_layer)
	var shade := ColorRect.new()
	shade.color = Color("#09131b")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "MenuCard"
	var card_style := _style(Color("#14232e"), Color("#315261"), 22, 1)
	card_style.content_margin_left = 30.0 * _ui_scale
	card_style.content_margin_right = 30.0 * _ui_scale
	card_style.content_margin_top = 28.0 * _ui_scale
	card_style.content_margin_bottom = 28.0 * _ui_scale
	card_style.shadow_color = Color(0, 0, 0, 0.42)
	card_style.shadow_size = roundi(28.0 * _ui_scale)
	card_style.shadow_offset = Vector2(0, 12.0 * _ui_scale)
	panel.add_theme_stylebox_override("panel", card_style)
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	var viewport_size := get_viewport_rect().size
	var compact_layout := viewport_size.y < 820.0 * _ui_scale
	var menu_width := minf(1260.0 * _ui_scale, viewport_size.x - 40.0)
	var menu_height := minf(820.0 * _ui_scale, viewport_size.y - 40.0)
	panel.offset_left = -menu_width * 0.5; panel.offset_right = menu_width * 0.5
	panel.offset_top = -menu_height * 0.5; panel.offset_bottom = menu_height * 0.5
	menu_layer.add_child(panel)
	var body_scroll := ScrollContainer.new()
	body_scroll.name = "MenuBodyScroll"
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(body_scroll)
	var wide_layout := viewport_size.x >= 1040.0 * _ui_scale
	var body: BoxContainer = HBoxContainer.new() if wide_layout else VBoxContainer.new()
	body.name = "MenuContent"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", roundi(36.0 * _ui_scale) if wide_layout else roundi(16.0 * _ui_scale))
	body_scroll.add_child(body)
	var left_column := VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", roundi((8.0 if compact_layout else 12.0) * _ui_scale))
	if wide_layout: left_column.custom_minimum_size.x = 500.0 * _ui_scale
	body.add_child(left_column)
	var eyebrow := _menu_label("METRO ATLAS     •     城市交通规划模拟", 14, TEAL, true)
	left_column.add_child(eyebrow)
	var title := _menu_label("造一座地铁", 48 if compact_layout else 52, TEXT, true)
	title.custom_minimum_size.y = (64.0 if compact_layout else 72.0) * _ui_scale
	left_column.add_child(title)
	var subtitle := _menu_label("在真实地图上规划线路，让每一站都服务有需求的人。" if compact_layout else "在真实城市地图上规划线路。\n让每一站，都有它要服务的人。", 18 if compact_layout else 19, MUTED)
	left_column.add_child(subtitle)
	var divider := HSeparator.new(); divider.add_theme_color_override("separator", BORDER); left_column.add_child(divider)
	var city_row := HBoxContainer.new()
	city_row.add_theme_constant_override("separation", 10)
	city_row.add_child(_menu_label("选择规划城市", 16, TEXT, true))
	left_column.add_child(city_row)
	menu_city_picker = OptionButton.new()
	menu_city_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_city_picker.custom_minimum_size.y = 50.0 * _ui_scale
	_set_control_base_font(menu_city_picker, 16)
	for item in WorldData.cities(): menu_city_picker.add_item(str(item.get("name", "城市")))
	menu_city_picker.item_selected.connect(func(index: int): active_city_id = str(WorldData.cities()[index].get("id", "shanghai")))
	menu_city_picker.select(0)
	left_column.add_child(menu_city_picker)
	var blank := _button("从零规划新城市     →", TEAL, Color("#123b35"), 21)
	blank.custom_minimum_size.y = (58.0 if compact_layout else 62.0) * _ui_scale
	blank.pressed.connect(func(): _start_new_game(active_city_id, "blank"))
	left_column.add_child(blank)
	if not compact_layout: left_column.add_child(_menu_label("从空白地图起步，自由规划第一条线路。", 15, MUTED))
	var expand := _button("扩建现实路网     →", Color("#91cbf2"), Color("#173044"), 20)
	expand.custom_minimum_size.y = (54.0 if compact_layout else 58.0) * _ui_scale
	expand.pressed.connect(func(): _start_new_game(active_city_id, "expand"))
	left_column.add_child(expand)
	if not compact_layout: left_column.add_child(_menu_label("从已运营路网继续，寻找新的服务缺口。", 15, MUTED))
	menu_continue_button = _button("继续上次游戏", TEXT, Color("#233744"), 18)
	menu_continue_button.custom_minimum_size.y = 54.0 * _ui_scale
	menu_continue_button.disabled = true
	menu_continue_button.pressed.connect(_continue_last_game)
	left_column.add_child(menu_continue_button)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var import_button := _button("导入存档", MUTED, PANEL_LIGHT, 16)
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.pressed.connect(func(): SaveManager.import_world(func(loaded: Dictionary): _load_world(loaded)))
	row.add_child(import_button)
	var settings_button := _button("设置", MUTED, PANEL_LIGHT, 16)
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.pressed.connect(_show_settings)
	row.add_child(settings_button)
	var quit_button := _button("退出", MUTED, PANEL_LIGHT, 16)
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_button.pressed.connect(func(): get_tree().quit())
	row.add_child(quit_button)
	left_column.add_child(row)
	var saves_button := _button("选择其他本地存档…", Color("#b4c5ce"), PANEL_LIGHT, 16)
	saves_button.custom_minimum_size.y = (44.0 if compact_layout else 48.0) * _ui_scale
	saves_button.pressed.connect(_show_load_menu)
	left_column.add_child(saves_button)
	left_column.add_child(_menu_label("底图 © OpenStreetMap · 需求与客流为游戏模拟。" if compact_layout else "OpenStreetMap © 贡献者 · 路网快照 2026-10-05\n需求与客流为游戏模拟数据。", 13, MUTED))
	if wide_layout:
		var showcase := PanelContainer.new()
		showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
		showcase.custom_minimum_size = Vector2(520.0 * _ui_scale, 0)
		showcase.add_theme_stylebox_override("panel", _style(Color("#0e1b25"), Color("#294553"), 18, 1))
		body.add_child(showcase)
		var showcase_body := VBoxContainer.new()
		showcase_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		showcase_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		showcase_body.add_theme_constant_override("separation", 14)
		showcase_body.add_theme_constant_override("margin_left", 20)
		showcase_body.add_theme_constant_override("margin_right", 20)
		showcase_body.add_theme_constant_override("margin_top", 20)
		showcase_body.add_theme_constant_override("margin_bottom", 20)
		showcase.add_child(showcase_body)
		var showcase_header := HBoxContainer.new()
		showcase_header.add_child(_menu_label("规划工作台", 19, TEXT, true))
		var header_spacer := Control.new(); header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; showcase_header.add_child(header_spacer)
		showcase_header.add_child(_menu_label("城市 · 需求 · 线路", 14, MUTED))
		showcase_body.add_child(showcase_header)
		var art := MenuArtScript.new()
		art.name = "MetroNetworkIllustration"
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.custom_minimum_size.y = 390.0 * _ui_scale
		showcase_body.add_child(art)
		showcase_body.add_child(_menu_label("从需求出发，连接城市里真正要去的地方。", 17, TEXT, true))
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 10)
		for pair in [["05", "座真实城市"], ["自由", "绘制轨道"], ["本地", "自动存档"]]:
			var stat := PanelContainer.new()
			stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stat.add_theme_stylebox_override("panel", _style(Color("#172b37"), Color("#2a4351"), 10, 1))
			stats.add_child(stat)
			var stat_body := VBoxContainer.new()
			stat_body.add_theme_constant_override("separation", 2)
			stat.add_child(stat_body)
			stat_body.add_child(_label(str(pair[0]), 20, TEAL, true))
			stat_body.add_child(_label(str(pair[1]), 13, MUTED))
			if pair[0] == "自由": stat_body.get_child(0).add_theme_color_override("font_color", Color("#59a8ee"))
			if pair[0] == "本地": stat_body.get_child(0).add_theme_color_override("font_color", Color("#f0b657"))
		showcase_body.add_child(stats)
	_update_continue_button()

func _show_settings() -> void:
	if not is_instance_valid(menu_layer): return
	var dialog := AcceptDialog.new()
	dialog.title = "显示与游戏设置"
	dialog.dialog_text = ""
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.add_child(_label("界面文字大小", 18, TEXT, true))
	content.add_child(_label("地图镜头缩放与界面缩放分开保存。", 14, MUTED))
	var scale_picker := OptionButton.new()
	for percentage in [100, 125, 150, 175]: scale_picker.add_item("%d%%" % percentage)
	scale_picker.select([1.0, 1.25, 1.5, 1.75].find(_ui_scale))
	scale_picker.custom_minimum_size.y = roundi(44.0 * _ui_scale)
	scale_picker.add_theme_font_size_override("font_size", roundi(16.0 * _ui_scale))
	content.add_child(scale_picker)
	scale_picker.item_selected.connect(func(index: int):
		var value: float = [1.0, 1.25, 1.5, 1.75][index]
		var save_error: Error = UiPreferencesScript.save_scale(value)
		if save_error != OK:
			_show_toast("界面设置保存失败；本次缩放仍已生效")
		_apply_ui_scale(value)
		dialog.popup_centered(Vector2i(roundi(490.0 * _ui_scale), roundi(310.0 * _ui_scale)))
	)
	content.add_child(_label("地图：OpenStreetMap 标准瓦片，按视野加载并遵循缓存规则。\n模拟速度使用固定游戏时间步长。", 14, MUTED))
	dialog.add_child(content)
	menu_layer.add_child(dialog)
	dialog.popup_centered(Vector2i(roundi(490.0 * _ui_scale), roundi(310.0 * _ui_scale)))

func _start_new_game(city_id: String, mode: String) -> void:
	if SaveManager.save_exists(city_id, mode):
		var confirm := ConfirmationDialog.new()
		confirm.title = "替换本地进度？"
		confirm.dialog_text = "这个城市与开局已有存档。继续会先将旧文件保存在 .bak。"
		add_child(confirm)
		confirm.confirmed.connect(func():
			confirm.queue_free()
			_load_world(_prepared_new_world(city_id, mode))
		)
		confirm.canceled.connect(func(): confirm.queue_free())
		confirm.popup_centered()
		return
	_load_world(_prepared_new_world(city_id, mode))

func _prepared_new_world(city_id: String, mode: String) -> Dictionary:
	var state := WorldData.new_world(city_id, mode)
	state["onboarding"] = OnboardingScript.create_state(city_id, mode, UiPreferencesScript.load_onboarding_completed())
	# The previous tutorial is retained only for old saves; new games use the location-based guide.
	state["tutorialDone"] = true
	state["tutorialStep"] = 0
	return state

func _continue_last_game() -> void:
	var path := SaveManager.last_game_path()
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary: _load_world(SaveManager.migrate(data))

func _update_continue_button() -> void:
	var exists := FileAccess.file_exists(SaveManager.last_game_path())
	if is_instance_valid(menu_continue_button): menu_continue_button.disabled = not exists

func _load_world(state: Dictionary) -> void:
	world = state
	if not world.has("onboarding"):
		# Existing version-8 saves should not unexpectedly start a new lesson.
		world["onboarding"] = OnboardingScript.create_state(str(world.get("cityId", "shanghai")), str(world.get("mode", "blank")), true)
		world["tutorialDone"] = true
	_flow_cache_revision = -1
	active_city_id = str(world.get("cityId", "shanghai"))
	if not world.has("simulation"): world.simulation = {"minute": 420, "speed": 1, "paused": true, "seed": 45281, "completed": 0, "attempted": 0, "served": 0}
	world.simulation.paused = true
	if world.get("stations", []).is_empty() and world.get("routes", []).is_empty(): WorldData.add_route(world, "1号线", "#e23f56")
	active_route_id = str(world.get("selectedRoute", world.get("activeRouteId", world.get("routes", [{}])[0].get("id", "")))) if not world.get("routes", []).is_empty() else ""
	if WorldData.find_route(world, active_route_id).is_empty() and not world.get("routes", []).is_empty(): active_route_id = str(world.routes[0].get("id", ""))
	selected_type = ""; selected_id = ""; current_tool = "select"
	_more_tools_expanded = false
	_left_requested = not bool(world.get("onboarding", {}).get("active", false))
	_right_requested = not bool(world.get("onboarding", {}).get("active", false))
	history.attach(world)
	if history.changed.is_connected(_on_history_changed): history.changed.disconnect(_on_history_changed)
	history.changed.connect(_on_history_changed)
	map_view.set_context(WorldData.city(active_city_id), world)
	map_view.clean_map_style = UiPreferencesScript.load_clean_map()
	map_view.selected_id = ""; map_view.selected_type = ""; map_view.tool = "select"
	map_view.visible = true
	_build_game_ui()
	_sync_onboarding_map(true)
	_refresh_onboarding_card()
	if is_instance_valid(menu_layer): menu_layer.queue_free()
	menu_layer = null
	_autosave()
	_update_tutorial()
	_refresh_ui()
	var migration_notice := str(world.get("migrationNotice", ""))
	_show_toast(migration_notice if not migration_notice.is_empty() else "已载入 %s · %s；游戏已暂停" % [world.get("cityName", "城市"), _mode_name(str(world.get("mode", "blank")))])

func _build_game_ui() -> void:
	for child in get_children():
		if child != map_view and child.get_name() != "Background": child.queue_free()
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 68
	top.add_theme_stylebox_override("panel", _style(Color("#101b26"), BORDER, 0, 0))
	add_child(top)
	_top_panel = top
	_top_content = VBoxContainer.new()
	_top_content.add_theme_constant_override("separation", 2)
	top.add_child(_top_content)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.add_theme_constant_override("margin_left", 14); top_row.add_theme_constant_override("margin_right", 14)
	_top_content.add_child(top_row)
	_top_primary_row = top_row
	_top_actions = HBoxContainer.new()
	_top_actions.add_theme_constant_override("separation", 10)
	_top_actions.add_theme_constant_override("margin_left", 14); _top_actions.add_theme_constant_override("margin_right", 14)
	_top_content.add_child(_top_actions)
	var logo := _label("M  造一座地铁", 18, TEAL, true); logo.custom_minimum_size.x = 188.0 * _ui_scale; top_row.add_child(logo)
	_left_panel_button = _button("线路 ▾", MUTED, PANEL_LIGHT, 14)
	_left_panel_button.pressed.connect(func(): _left_requested = not _left_requested; _update_responsive_layout())
	top_row.add_child(_left_panel_button)
	city_picker = OptionButton.new(); city_picker.custom_minimum_size = Vector2(120, 38)
	_set_control_base_font(city_picker, 15)
	for item in WorldData.cities(): city_picker.add_item(str(item.name))
	for i in range(WorldData.cities().size()):
		if WorldData.cities()[i].id == active_city_id: city_picker.select(i)
	city_picker.item_selected.connect(_on_city_change_requested)
	top_row.add_child(city_picker)
	_right_panel_button = _button("详情 ▾", MUTED, PANEL_LIGHT, 14)
	_right_panel_button.pressed.connect(func(): _right_requested = not _right_requested; _update_responsive_layout())
	top_row.add_child(_right_panel_button)
	var mode_badge := _label(_mode_name(str(world.get("mode", "blank"))), 12, MUTED); mode_badge.custom_minimum_size.x = 82; top_row.add_child(mode_badge)
	_top_spacer = Control.new(); _top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top_row.add_child(_top_spacer)
	time_label = _label("第 1 天 · 07:00", 13, TEXT, true); time_label.custom_minimum_size.x = 112; _top_actions.add_child(time_label)
	pause_button = _button("▶", TEAL, Color("#142e2c"), 18); pause_button.custom_minimum_size = Vector2(42, 40); pause_button.pressed.connect(_toggle_pause); _top_actions.add_child(pause_button)
	speed_picker = OptionButton.new(); speed_picker.custom_minimum_size = Vector2(82, 38)
	for speed in [1,3,10]: speed_picker.add_item("%d×" % speed)
	speed_picker.item_selected.connect(func(index: int): world.simulation.speed = [1,3,10][index]; _autosave())
	_top_actions.add_child(speed_picker)
	undo_button = _button("↶", TEXT, PANEL_LIGHT, 20); undo_button.tooltip_text = "撤销 Ctrl+Z"; undo_button.pressed.connect(_do_undo); _top_actions.add_child(undo_button)
	redo_button = _button("↷", TEXT, PANEL_LIGHT, 20); redo_button.tooltip_text = "重做 Ctrl+Y"; redo_button.pressed.connect(_do_redo); _top_actions.add_child(redo_button)
	var saves := _button("存档 ▾", MUTED, PANEL_LIGHT, 13); saves.pressed.connect(_show_save_menu); _top_actions.add_child(saves)
	save_badge = _label("已保存", 12, TEAL); save_badge.custom_minimum_size.x = 70; _top_actions.add_child(save_badge)
	var menu_button := _button("菜单", MUTED, PANEL_LIGHT, 13); menu_button.pressed.connect(_leave_to_menu); _top_actions.add_child(menu_button)

	var left := PanelContainer.new()
	left.anchor_left = 0; left.anchor_right = 0; left.anchor_top = 0; left.anchor_bottom = 1
	left.offset_top = 68; left.offset_bottom = -35; left.offset_left = 0; left.offset_right = 280
	left.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 0, 0)); add_child(left)
	_left_panel = left
	var left_scroll := ScrollContainer.new(); left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(left_scroll)
	left_content = VBoxContainer.new(); left_content.custom_minimum_size.x = 250; left_content.add_theme_constant_override("separation", 8); left_content.add_theme_constant_override("margin_left", 14); left_content.add_theme_constant_override("margin_right", 14); left_content.add_theme_constant_override("margin_top", 12); left_content.add_theme_constant_override("margin_bottom", 12); left_scroll.add_child(left_content)

	var right := PanelContainer.new()
	right.anchor_left = 1; right.anchor_right = 1; right.anchor_top = 0; right.anchor_bottom = 1
	right.offset_top = 68; right.offset_bottom = -35; right.offset_left = -310; right.offset_right = 0
	right.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 0, 0)); add_child(right)
	_right_panel = right
	var right_scroll := ScrollContainer.new(); right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; right.add_child(right_scroll)
	right_content = VBoxContainer.new(); right_content.custom_minimum_size.x = 280; right_content.add_theme_constant_override("separation", 9); right_content.add_theme_constant_override("margin_left", 14); right_content.add_theme_constant_override("margin_right", 14); right_content.add_theme_constant_override("margin_top", 14); right_content.add_theme_constant_override("margin_bottom", 14); right_scroll.add_child(right_content)

	var footer := PanelContainer.new()
	footer.anchor_left = 0; footer.anchor_right = 1; footer.anchor_top = 1; footer.anchor_bottom = 1
	footer.offset_top = -132; footer.offset_bottom = 0
	footer.add_theme_stylebox_override("panel", _style(Color("#111d27"), BORDER, 0, 0)); add_child(footer)
	_footer_panel = footer
	var footer_body := VBoxContainer.new(); footer_body.add_theme_constant_override("separation", 4); footer_body.add_theme_constant_override("margin_left", 10); footer_body.add_theme_constant_override("margin_right", 10); footer_body.add_theme_constant_override("margin_top", 6); footer_body.add_theme_constant_override("margin_bottom", 5); footer.add_child(footer_body)
	tool_panel = HFlowContainer.new(); tool_panel.add_theme_constant_override("h_separation", 7); tool_panel.add_theme_constant_override("v_separation", 5); footer_body.add_child(tool_panel)
	tool_instruction_label = _label("", 14, TEAL)
	tool_instruction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_body.add_child(tool_instruction_label)
	var footer_row := HFlowContainer.new(); footer_row.add_theme_constant_override("h_separation", 12); footer_row.add_theme_constant_override("v_separation", 4); footer_body.add_child(footer_row)
	stats_label = _label("需求服务率 —   平均出行 —   已完成 0 趟", 14, MUTED); stats_label.custom_minimum_size.x = 440.0 * _ui_scale; footer_row.add_child(stats_label)
	save_badge = _label("本地存档", 14, TEAL); save_badge.custom_minimum_size.x = 110.0 * _ui_scale; footer_row.add_child(save_badge)
	toast_label = _label("", 14, TEXT); toast_label.custom_minimum_size.x = 300.0 * _ui_scale; footer_row.add_child(toast_label)
	_layer_panel = PanelContainer.new()
	_layer_panel.anchor_left = 1.0; _layer_panel.anchor_right = 1.0
	_layer_panel.anchor_top = 0.0; _layer_panel.anchor_bottom = 0.0
	_layer_panel.offset_left = -456.0 * _ui_scale; _layer_panel.offset_right = -12.0
	_layer_panel.offset_top = 12.0; _layer_panel.offset_bottom = 60.0 * _ui_scale
	_layer_panel.custom_minimum_size = Vector2(430.0 * _ui_scale, 48.0 * _ui_scale)
	_layer_panel.add_theme_stylebox_override("panel", _style(Color("#172836"), BORDER, 10, 1))
	var layers := HBoxContainer.new(); layers.add_theme_constant_override("separation", 8); _layer_panel.add_child(layers)
	var halls_toggle := CheckButton.new(); halls_toggle.text = "站体"; halls_toggle.button_pressed = map_view.show_halls; _set_control_base_font(halls_toggle, 14); halls_toggle.toggled.connect(func(on: bool): map_view.show_halls = on; map_view.requested_redraw()); layers.add_child(halls_toggle)
	var demand_toggle := CheckButton.new(); demand_toggle.text = "需求"; demand_toggle.button_pressed = map_view.show_demand; _set_control_base_font(demand_toggle, 14); demand_toggle.toggled.connect(func(on: bool): map_view.show_demand = on; map_view.requested_redraw()); layers.add_child(demand_toggle)
	var network_toggle := CheckButton.new(); network_toggle.text = "线路"; network_toggle.button_pressed = map_view.show_network; _set_control_base_font(network_toggle, 14); network_toggle.toggled.connect(func(on: bool): map_view.show_network = on; map_view.requested_redraw()); layers.add_child(network_toggle)
	var style_toggle := _button("清爽规划" if map_view.clean_map_style else "详细街道", TEXT, PANEL_LIGHT, 13)
	style_toggle.tooltip_text = "切换底图对比度；道路文字属于地图图片，不能单独隐藏"
	style_toggle.pressed.connect(func():
		map_view.clean_map_style = not map_view.clean_map_style
		style_toggle.text = "清爽规划" if map_view.clean_map_style else "详细街道"
		var result := UiPreferencesScript.save_clean_map(map_view.clean_map_style)
		if result != OK: _show_toast("地图风格已切换，但设置保存失败")
		map_view.requested_redraw()
	)
	layers.add_child(style_toggle)
	map_view.add_child(_layer_panel)
	onboarding_panel = PanelContainer.new()
	onboarding_panel.anchor_left = 0.0; onboarding_panel.anchor_right = 0.0
	onboarding_panel.anchor_top = 0.0; onboarding_panel.anchor_bottom = 0.0
	onboarding_panel.offset_left = 18.0 * _ui_scale; onboarding_panel.offset_top = 14.0 * _ui_scale
	onboarding_panel.custom_minimum_size = Vector2(370.0 * _ui_scale, 0)
	onboarding_panel.add_theme_stylebox_override("panel", _style(Color("#12232d"), Color("#358f79"), 14, 2))
	onboarding_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	map_view.add_child(onboarding_panel)
	_attribution_panel = PanelContainer.new()
	_attribution_panel.anchor_left = 0; _attribution_panel.anchor_right = 0
	_attribution_panel.anchor_top = 1; _attribution_panel.anchor_bottom = 1
	_attribution_panel.add_theme_stylebox_override("panel", _style(Color("#eef2f1"), Color("#8798a0"), 5, 1))
	attribution_label = _label("© OpenStreetMap contributors · 地图资料快照 2026-10-05 · 既有线虚线表示站间示意，非实测轨道几何", 12, Color("#354956"))
	attribution_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attribution_panel.add_child(attribution_label)
	add_child(_attribution_panel)
	_update_responsive_layout()
	_refresh_ui()

func _refresh_ui() -> void:
	if world.is_empty() or not is_instance_valid(left_content): return
	_sync_onboarding_map()
	_refresh_left_panel()
	_refresh_right_panel()
	_refresh_tools()
	_refresh_onboarding_card()
	_update_topbar()
	_update_sim_labels()
	map_view.active_route_id = active_route_id
	map_view.selected_type = selected_type
	map_view.selected_id = selected_id
	map_view.set_world(world)

func _refresh_left_panel() -> void:
	for c in left_content.get_children(): c.queue_free()
	left_content.add_child(_label("线路与车站", 18, TEXT, true))
	var active_route := WorldData.find_route(world, active_route_id)
	var active_name := str(active_route.get("name", "未选线路"))
	left_content.add_child(_label("当前线路 · %s" % active_name, 12, MUTED))
	var add_route := _button("＋ 新建线路", TEAL, Color("#15362f"), 13)
	add_route.pressed.connect(_new_route)
	left_content.add_child(add_route)
	route_list = VBoxContainer.new(); route_list.add_theme_constant_override("separation", 5); left_content.add_child(route_list)
	for route in world.get("routes", []):
		var row := HBoxContainer.new()
		var color := Color.from_string(str(route.get("color", "#4a91e8")), Color("#4a91e8"))
		var route_button := _button("●  %s" % route.get("name", "线路"), TEXT, PANEL_LIGHT, 12)
		route_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		route_button.add_theme_color_override("font_color", color)
		route_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		route_button.pressed.connect(func(): active_route_id = str(route.get("id", "")); selected_type = "route"; selected_id = active_route_id; _refresh_ui())
		row.add_child(route_button)
		var count := _label("%d站" % route.get("stationOrder", []).size(), 11, MUTED); row.add_child(count)
		route_list.add_child(row)
	var line_order := _label("线路结构", 13, TEXT, true); left_content.add_child(line_order)
	if active_route.is_empty(): left_content.add_child(_label("请新建或选择一条线路。", 11, MUTED))
	else:
		var order: Array = active_route.get("stationOrder", [])
		if order.is_empty(): left_content.add_child(_label("还没有车站。先放置两个站，再连接两端节点。", 11, MUTED))
		for index in range(order.size()):
			var st := WorldData.find_station(world, str(order[index]))
			if st.is_empty(): continue
			var station_button := _button("%02d  %s" % [index + 1, st.get("name", "车站")], TEXT, PANEL_LIGHT, 11)
			station_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			station_button.pressed.connect(func(): _select_object("station", str(st.get("id", ""))); map_view.center_on(st.get("latlng", [0,0]), maxi(map_view.current_zoom, 14)))
			left_content.add_child(station_button)
	left_content.add_child(HSeparator.new())
	left_content.add_child(_label("新手任务", 16, TEXT, true))
	var onboarding: Dictionary = world.get("onboarding", {})
	var tutorial_card := PanelContainer.new(); tutorial_card.add_theme_stylebox_override("panel", _style(Color("#1a3533"), Color("#2f6258"), 9, 1)); left_content.add_child(tutorial_card)
	var tutorial_box := VBoxContainer.new(); tutorial_box.add_theme_constant_override("separation", 6); tutorial_box.add_theme_constant_override("margin_left", 10); tutorial_box.add_theme_constant_override("margin_right", 10); tutorial_box.add_theme_constant_override("margin_top", 9); tutorial_box.add_theme_constant_override("margin_bottom", 9); tutorial_card.add_child(tutorial_box)
	if bool(onboarding.get("active", false)):
		tutorial_box.add_child(_label("街区规划引导 · 第 %d / 6 步" % mini(int(onboarding.get("step", 0)) + 1, 6), 13, TEAL, true))
		tutorial_box.add_child(_label("%s → %s" % [_find_demand(str(onboarding.get("originId", ""))).get("name", "起点"), _find_demand(str(onboarding.get("destinationId", ""))).get("name", "目的地")], 13, TEXT, true))
		var locate := _button("返回任务位置", TEXT, PANEL_LIGHT, 13); locate.pressed.connect(_return_to_onboarding_mission); tutorial_box.add_child(locate)
	elif str(world.get("mode", "blank")) == "expand":
		tutorial_box.add_child(_label("现实路网开局：先查看一条已运营线路，再决定从哪里扩建。", 13, MUTED))
		var browse := _button("定位既有线路", TEXT, PANEL_LIGHT, 13); browse.pressed.connect(_locate_existing_network); tutorial_box.add_child(browse)
	else:
		tutorial_box.add_child(_label("从真实街区的一组出行需求开始。自由选址，不要求照着需求虚线铺轨。", 13, MUTED))
		var replay := _button("重玩街区规划引导", TEXT, PANEL_LIGHT, 13); replay.pressed.connect(_restart_onboarding); tutorial_box.add_child(replay)
	if _flow_cache_revision != int(world.get("revision", 0)): _rebuild_flow_cache()
	left_content.add_child(_label("优先补足的出行", 15, TEXT, true))
	var gaps: Array[Dictionary] = []
	for flow in _flow_cache:
		if not bool(flow.get("valid", false)): gaps.append(flow)
	gaps.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("peoplePerDay", 0)) > float(b.get("peoplePerDay", 0)))
	if gaps.is_empty():
		left_content.add_child(_label("当前需求已有可达线路；继续运行，观察实际服务表现。", 11, MUTED))
	else:
		for i in range(mini(3, gaps.size())):
			var flow: Dictionary = gaps[i]
			var card := PanelContainer.new(); card.add_theme_stylebox_override("panel", _style(Color("#1b2a35"), BORDER, 7, 1)); left_content.add_child(card)
			var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 4); content.add_theme_constant_override("margin_left", 8); content.add_theme_constant_override("margin_right", 8); content.add_theme_constant_override("margin_top", 6); content.add_theme_constant_override("margin_bottom", 6); card.add_child(content)
			var pair := _label("%s → %s" % [flow.get("from", "起点"), flow.get("to", "目的地")], 11, TEXT, true); pair.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; content.add_child(pair)
			var flow_total := _number(int(round(float(flow.get("peoplePerDay", 0)))))
			content.add_child(_label("约 %s 人次/日 · 当前未形成完整可达路径" % flow_total, 10, MUTED))
			var locate := _button("查看起终点", Color("#8fc9ed"), PANEL_LIGHT, 10)
			locate.pressed.connect(func(): _focus_flow(flow))
			content.add_child(locate)
	var source := str(world.get("source", {}).get("snapshot", ""))
	left_content.add_child(_label("站点与线路：OSM 快照 %s\n线路几何为站间示意；需求量为游戏设定。" % source.left(10), 10, MUTED))
	if not str(world.get("migrationNotice", "")).is_empty():
		var migration_label := _label(str(world.get("migrationNotice", "")), 10, Color("#e1b975"))
		migration_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_content.add_child(migration_label)
	left_content.add_child(_label("城市出行需求", 15, TEXT, true))
	for demand in WorldData.city(active_city_id).get("demand", []):
		var demand_button := _button("●  %s · %s" % [demand.get("name", "需求点"), _type_name(str(demand.get("type", "")))], TEXT, Color("#1b2934"), 11)
		demand_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		demand_button.add_theme_color_override("font_color", _type_color(str(demand.get("type", ""))))
		demand_button.pressed.connect(func(): _select_object("demand", str(demand.get("id", ""))); map_view.center_on(demand.get("latlng", [0,0]), maxi(map_view.current_zoom, 14)))
		left_content.add_child(demand_button)

func _tutorial_detail(step: int) -> String:
	match step:
		0: return "点击下方「建车站」，在地图选两个位置后确认。按 R 可转向。"
		1: return "点击「连接轨道」，先选起点，再点另一站的端点。站间距不会卡住开通。"
		2: return "点击右侧「检查并开通」。默认自动保障车辆，不必先造车辆段。"
		3: return "按播放，首批乘客会按站点覆盖与线路连通情况计入模拟。"
	return "基础教学可以跳过，也可以从菜单重开。"

func _refresh_right_panel() -> void:
	for c in right_content.get_children(): c.queue_free()
	if selected_type == "station":
		var station := WorldData.find_station(world, selected_id)
		if station.is_empty(): selected_type = ""
		else: _station_details(station)
	elif selected_type == "route":
		var route := WorldData.find_route(world, selected_id)
		if route.is_empty(): selected_type = ""
		else: _route_details(route)
	elif selected_type == "demand":
		var demand := _find_demand(selected_id)
		if demand.is_empty(): selected_type = ""
		else: _demand_details(demand)
	elif selected_type == "link":
		var link := _find_link(selected_id)
		if link.is_empty(): selected_type = ""
		else: _link_details(link)
	if selected_type == "":
		right_content.add_child(_label("规划检查", 17, TEXT, true))
		right_content.add_child(_label("选择一座车站、线路或需求点查看信息。\n\n建议流程：选线路 → 建站 → 接轨 → 检查 → 开通。\n\n默认采用自动配车；运行状态与历史记录保存在本机。", 12, MUTED))
		var summary := _network_summary()
		right_content.add_child(HSeparator.new())
		right_content.add_child(_label("当前方案", 14, TEXT, true))
		right_content.add_child(_label("车站 %d 座\n实体区间 %d 段\n运营线路 %d 条\n车辆保障：自动\n站间距：只影响运行时间，不作开通门槛" % [summary.stations, summary.links, summary.routes], 12, MUTED))
		var check := _button("检查并开通线路", TEAL, Color("#15372f"), 14)
		if not bool(world.get("tutorialDone", false)) and int(world.get("tutorialStep", 0)) == 2:
			check.add_theme_stylebox_override("normal", _style(Color("#246a52"), Color("#78edc4"), 8, 2))
		check.pressed.connect(_open_route)
		right_content.add_child(check)
		var note := _label("阻断：断连、零长度、站体重叠\n建议：站间距、覆盖、曲线\n资料未知：现实路网为站间示意", 11, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right_content.add_child(note)

func _station_details(station: Dictionary) -> void:
	right_content.add_child(_label("车站详情", 20, TEXT, true))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	right_content.add_child(_label("站名", 14, MUTED))
	var name_edit := LineEdit.new(); name_edit.text = str(station.get("name", "")); name_edit.placeholder_text = "输入车站名称"; name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _set_control_base_font(name_edit, 16)
	name_edit.text_submitted.connect(func(value: String): _rename_station(str(station.id), value))
	name_edit.focus_exited.connect(func(): _rename_station(str(station.id), name_edit.text))
	name_row.add_child(name_edit)
	var save_name := _button("保存", TEAL, Color("#15372f"), 14)
	save_name.pressed.connect(func(): _rename_station(str(station.id), name_edit.text))
	name_row.add_child(save_name)
	right_content.add_child(name_row)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 5)
	var move := _button("移动车站", TEXT, PANEL_LIGHT, 14)
	move.pressed.connect(func(): _set_tool("select"); _show_toast("拖动车站移动；按 R 旋转"))
	actions.add_child(move)
	var rotate := _button("旋转 15°  (R)", TEXT, PANEL_LIGHT, 14)
	rotate.pressed.connect(func(): _rotate_station(str(station.id)))
	actions.add_child(rotate)
	var connect_a := _button("从 A 端接轨", TEAL, Color("#15372f"), 14)
	connect_a.pressed.connect(func(): _begin_station_connection(str(station.id), "start"))
	actions.add_child(connect_a)
	var connect_b := _button("从 B 端接轨", TEAL, Color("#15372f"), 14)
	connect_b.pressed.connect(func(): _begin_station_connection(str(station.id), "end"))
	actions.add_child(connect_b)
	right_content.add_child(actions)
	var locate := _button("定位到地图", TEXT, PANEL_LIGHT, 14)
	locate.pressed.connect(func(): map_view.center_on(station.get("latlng", [0,0]), maxi(map_view.current_zoom, 14)))
	right_content.add_child(locate)
	right_content.add_child(HSeparator.new())
	right_content.add_child(_label("车型与站体", 16, TEXT, true))
	var vehicle_picker := OptionButton.new()
	_set_control_base_font(vehicle_picker, 15)
	for profile in WorldData.vehicles():
		vehicle_picker.add_item(str(profile.get("name", profile.get("id", "车型"))))
		vehicle_picker.set_item_metadata(vehicle_picker.item_count - 1, str(profile.get("id", "")))
	for i in range(vehicle_picker.item_count):
		if vehicle_picker.get_item_metadata(i) == str(station.get("vehicleId", "B-6")): vehicle_picker.select(i)
	vehicle_picker.item_selected.connect(func(index: int): _change_station_vehicle(str(station.id), str(vehicle_picker.get_item_metadata(index))))
	right_content.add_child(vehicle_picker)
	var profile := WorldData.vehicle(str(station.get("vehicleId", "B-6")))
	right_content.add_child(_label("%d 节 · 列车总长 %.1f 米 · 站厅宽 %.0f 米\n中心 %.5f, %.5f\n%s" % [profile.get("cars", 6), station.get("lengthM", 118.8), station.get("widthM", 20.0), station.get("latlng", [0,0])[0], station.get("latlng", [0,0])[1], "既有站体：游戏简化" if station.get("existing", false) else "游戏简化站体，尺寸随编组",], 11, MUTED))
	right_content.add_child(HSeparator.new())
	if station.get("schematic", false):
		var schematic := _label("既有站点坐标来自 OSM 快照。站厅位置与尺寸是游戏简化示意，不代表实测建筑。", 10, Color("#d4af6b")); schematic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; right_content.add_child(schematic)
	var del := _button("拆除车站", Color("#ef8b8b"), Color("#41272d"), 14)
	del.pressed.connect(func(): _delete_station(str(station.id)))
	right_content.add_child(del)

func _begin_station_connection(station_id: String, side: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	current_tool = "connect"
	map_view.tool = current_tool
	map_view.draft_station = {}
	map_view.link_start = {"stationId": station_id, "side": side}
	selected_type = "station"
	selected_id = station_id
	map_view.selected_type = selected_type
	map_view.selected_id = selected_id
	map_view.requested_redraw()
	_refresh_ui()
	_show_toast("已选 %s · %s 端，请点另一座车站的端点" % [station.get("name", "车站"), "A" if side == "start" else "B"])

func _route_details(route: Dictionary) -> void:
	right_content.add_child(_label("线路详情", 17, TEXT, true))
	right_content.add_child(_label("线路名称", 11, MUTED))
	var name_edit := LineEdit.new(); name_edit.text = str(route.get("name", "")); name_edit.text_submitted.connect(func(value: String): _rename_route(str(route.id), value)); name_edit.focus_exited.connect(func(): _rename_route(str(route.id), name_edit.text)); right_content.add_child(name_edit)
	right_content.add_child(_label("车辆与发车间隔", 12, MUTED))
	var vehicle_picker := OptionButton.new()
	for profile in WorldData.vehicles():
		vehicle_picker.add_item(str(profile.get("name", profile.get("id", "车型"))))
		vehicle_picker.set_item_metadata(vehicle_picker.item_count - 1, str(profile.get("id", "")))
	for i in range(vehicle_picker.item_count):
		if vehicle_picker.get_item_metadata(i) == str(route.get("vehicleId", "B-6")): vehicle_picker.select(i)
	vehicle_picker.item_selected.connect(func(index: int): _change_route_vehicle(str(route.id), str(vehicle_picker.get_item_metadata(index))))
	right_content.add_child(vehicle_picker)
	var headway := SpinBox.new(); headway.min_value = 1; headway.max_value = 20; headway.step = 1; headway.value = int(route.get("headway", 3)); headway.suffix = " 分钟"
	headway.value_changed.connect(func(value: float): _change_headway(str(route.id), int(value)))
	right_content.add_child(headway)
	right_content.add_child(_label("停站序列 · %d 站" % route.get("stationOrder", []).size(), 12, MUTED))
	for i in range(route.get("stationOrder", []).size()):
		var station := WorldData.find_station(world, str(route.stationOrder[i]))
		if not station.is_empty(): right_content.add_child(_label("%02d  %s" % [i+1, station.get("name", "车站")], 11, TEXT))
	right_content.add_child(_label("状态：%s\n配车：自动保障\n线路长度约 %.1f 千米\n最大单向运能：约 %d 人/小时\n区间几何：%s" % ["已开通" if route.get("open", false) else "草案", _route_length_km(route), int(WorldData.vehicle(str(route.get("vehicleId", "B-6"))).get("capacity", 1800)) * 60 / maxi(1, int(route.get("headway", 3))), "既有线路站间示意" if route.get("schematic", false) else "由站端连接生成"], 11, MUTED))
	var check := _button("检查并开通此线路", TEAL, Color("#15372f"), 14)
	if not bool(world.get("tutorialDone", false)) and int(world.get("tutorialStep", 0)) == 2:
		check.add_theme_stylebox_override("normal", _style(Color("#246a52"), Color("#78edc4"), 8, 2))
	check.pressed.connect(_open_route); right_content.add_child(check)
	var del := _button("删除线路", Color("#ef8b8b"), Color("#41272d"), 12); del.pressed.connect(func(): _delete_route(str(route.id))); right_content.add_child(del)

func _link_details(link: Dictionary) -> void:
	var a := WorldData.find_station(world, str(link.get("a", {}).get("stationId", "")))
	var b := WorldData.find_station(world, str(link.get("b", {}).get("stationId", "")))
	if a.is_empty() or b.is_empty():
		right_content.add_child(_label("轨道区间", 20, TEXT, true))
		right_content.add_child(_label("连接端点资料不完整。", 14, MUTED))
		return
	right_content.add_child(_label("轨道区间", 20, TEXT, true))
	var length := WorldData.track_length_m(link, world, float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0]))
	var route_id := str(link.get("routeIds", [""])[0]) if not link.get("routeIds", []).is_empty() else ""
	var route := WorldData.find_route(world, route_id)
	var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
	var minutes := length / maxf(1.0, float(profile.get("maxSpeedKmh", 80.0)) * 1000.0 / 60.0) + 0.5
	right_content.add_child(_label("%s · %s\n%s → %s\n长度 %.0f 米 · 估算运行 %.1f 分钟\n%s" % [route.get("name", "未编入线路"), "站间示意" if link.get("schematic", false) else "规划轨道", a.get("name", "车站"), b.get("name", "车站"), length, minutes, "现实快照示意，几何待核验" if link.get("schematic", false) else "按当前车型最高速度估算"], 15, MUTED))
	var curve := _button("调整曲线", TEXT, PANEL_LIGHT, 14)
	curve.pressed.connect(func(): active_route_id = route_id; selected_type = "link"; selected_id = str(link.get("id", "")); _set_tool("curve"))
	right_content.add_child(curve)
	var del := _button("删除此区间", Color("#ef8b8b"), Color("#41272d"), 14)
	del.pressed.connect(func(): _delete_link(str(link.get("id", ""))))
	right_content.add_child(del)

func _demand_details(demand: Dictionary) -> void:
	right_content.add_child(_label("出行需求", 17, TEXT, true))
	right_content.add_child(_label(str(demand.get("name", "需求地点")), 16, _type_color(str(demand.get("type", ""))), true))
	right_content.add_child(_label("类型：%s\n游戏设定需求：约 %s 人/日\n资料日期：%s" % [_type_name(str(demand.get("type", ""))), _number(int(demand.get("gameDemand", {}).get("base", 0))), str(world.get("source", {}).get("snapshot", "")).left(10)], 12, MUTED))
	_ensure_flow_cache()
	var related: Array[Dictionary] = []
	for flow in _flow_cache:
		if str(flow.get("fromId", "")) == str(demand.get("id", "")): related.append(flow)
	related.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("peoplePerDay", 0)) > float(b.get("peoplePerDay", 0)))
	if not related.is_empty():
		right_content.add_child(_label("主要出行方向（游戏设定）", 12, TEXT, true))
		for i in range(mini(3, related.size())):
			var flow: Dictionary = related[i]
			var status := "已接入 %s" % WorldData.find_route(world, str(flow.get("routeId", ""))).get("name", "线路") if flow.get("valid", false) else "未满足：接驳、站点覆盖或线路未连通"
			right_content.add_child(_label("→ %s · 约 %s 人次/日\n%s" % [flow.get("to", "目的地"), _number(int(round(float(flow.get("peoplePerDay", 0))))), status], 11, MUTED))
	var nearest := _nearest_station(demand.get("latlng", [0,0]))
	if nearest.is_empty():
		right_content.add_child(_label("当前没有可达车站。\n此处为估算直线距离；未取得连续步行网络数据。", 12, Color("#d5aa66")))
	else:
		var distance := _distance_m(demand.get("latlng", [0,0]), nearest.get("latlng", [0,0]))
		right_content.add_child(_label("最近站：%s\n估算直线距离：%.0f 米\n%s" % [nearest.get("name", "车站"), distance, "800 米游戏覆盖范围内" if distance <= 800 else "超出 800 米估算覆盖范围"], 12, MUTED))
	right_content.add_child(_label("游戏客流是规划对比用的模拟数，不是实际运营统计或出行调查。", 10, MUTED))
	var locate := _button("定位需求点", TEXT, PANEL_LIGHT, 12); locate.pressed.connect(func(): map_view.center_on(demand.get("latlng", [0,0]), maxi(map_view.current_zoom, 14))); right_content.add_child(locate)

func _refresh_tools() -> void:
	if not is_instance_valid(tool_panel): return
	for c in tool_panel.get_children(): c.queue_free()
	var footer_instruction := _tool_instruction()
	if is_instance_valid(tool_instruction_label):
		tool_instruction_label.text = footer_instruction
		tool_instruction_label.add_theme_color_override("font_color", TEAL if current_tool in ["station", "connect"] else MUTED)
	var onboarding: Dictionary = world.get("onboarding", {})
	var guide_active := bool(onboarding.get("active", false)) and not _more_tools_expanded
	var tutorial_step := int(onboarding.get("step", 0)) if guide_active else int(world.get("tutorialStep", 0))
	var tools: Array = [["select", "选择"], ["station", "建车站"], ["connect", "连接轨道"], ["curve", "调曲线"], ["delete", "拆除"]]
	if guide_active:
		if tutorial_step in [1, 2]: tools = [["select", "选择"], ["station", "建车站"]]
		elif tutorial_step == 3: tools = [["select", "选择"], ["connect", "连接轨道"]]
		else: tools = [["select", "选择"]]
	for item in tools:
		var active: bool = current_tool == item[0]
		var coached := false
		var button := _button(item[1], TEAL if active or coached else TEXT, Color("#174037") if active else Color("#1c4039") if coached else PANEL_LIGHT, 14)
		button.custom_minimum_size = Vector2(96.0 * _ui_scale, 42.0 * _ui_scale)
		if coached: button.tooltip_text = "新手教学下一步"
		button.pressed.connect(func(): _set_tool(str(item[0])))
		tool_panel.add_child(button)
	if bool(onboarding.get("active", false)) and not _more_tools_expanded:
		var more := _button("更多工具 ▸", MUTED, PANEL_LIGHT, 13)
		more.pressed.connect(func(): _more_tools_expanded = true; _refresh_tools())
		tool_panel.add_child(more)
	elif bool(onboarding.get("active", false)):
		var less := _button("收起工具 ▾", MUTED, PANEL_LIGHT, 13)
		less.pressed.connect(func(): _more_tools_expanded = false; _refresh_tools())
		tool_panel.add_child(less)
	if current_tool == "station" and not map_view.draft_station.is_empty():
		var confirm := _button("确认任务车站" if bool(onboarding.get("active", false)) else "确认站点", TEAL, Color("#164034"), 14); confirm.disabled = map_view.draft_conflict; confirm.pressed.connect(_confirm_station); tool_panel.add_child(confirm)
		var cancel := _button("取消本步", MUTED, PANEL_LIGHT, 14); cancel.pressed.connect(_cancel_tool_step); tool_panel.add_child(cancel)
		var finish_station := _button("退出建站", MUTED, PANEL_LIGHT, 14); finish_station.pressed.connect(_finish_tool); tool_panel.add_child(finish_station)
		if is_instance_valid(tool_instruction_label):
			tool_instruction_label.text += "   ·   预览 %.1f × %.0f 米；可拖动或点空地重定位，按 R 转向" % [map_view.draft_station.get("lengthM", 118.8), map_view.draft_station.get("widthM", 20)]
	elif current_tool == "connect":
		var end := _button("结束操作", MUTED, PANEL_LIGHT, 14); end.pressed.connect(_finish_tool); tool_panel.add_child(end)
	else:
		var finish := _button("结束操作 / Esc", MUTED, PANEL_LIGHT, 14); finish.pressed.connect(_finish_tool); tool_panel.add_child(finish)
	if current_tool == "connect" and is_instance_valid(tool_instruction_label):
		tool_instruction_label.text = _connection_instruction()

func _connection_instruction() -> String:
	if map_view.link_start.is_empty(): return "连接轨道：先选择一站的 A／B 端点，再点另一站端点。"
	var source := WorldData.find_station(world, str(map_view.link_start.get("stationId", "")))
	var side := "A" if str(map_view.link_start.get("side", "start")) == "start" else "B"
	return "已选：%s · %s端 → 请点另一座车站的端点。" % [source.get("name", "车站"), side]

func _tool_instruction() -> String:
	match current_tool:
		"station":
			if map_view.draft_conflict: return "位置冲突：站体与现有车站重叠，请移动或旋转。"
			return "建站：点空地放置预览，可拖动、按 R 转向，再确认。" if map_view.draft_station.is_empty() else "站址预览有效：确认后加入规划。"
		"connect": return _connection_instruction()
		"curve": return "调曲线：点蓝色控制点拖动，里程和运行时间同步变化。"
		"delete": return "拆除：点站体或轨道区间；确认后可撤销。"
		_: return "选择：点车站、轨道或需求查看详情；拖空地图移动镜头。"

func _finish_tool() -> void:
	map_view.draft_station = {}
	map_view.draft_conflict = false
	map_view.link_start = {}
	current_tool = "select"
	map_view.tool = current_tool
	map_view.requested_redraw()
	_refresh_ui()

func _on_map_clicked(latlng: Array, hit_type: String, hit_id: String, side: String) -> void:
	if current_tool == "station":
		if not map_view.draft_station.is_empty():
			if hit_type == "station":
				_show_toast("点击了现有车站；请在空地重新选址，或直接拖动预览")
				return
			map_view.draft_station["latlng"] = latlng.duplicate()
			_on_draft_station_changed()
			_refresh_tools()
			return
		var route := WorldData.find_route(world, active_route_id)
		if route.is_empty(): route = _new_route(false)
		var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
		var guide_heading := _onboarding_station_heading()
		var heading := guide_heading if guide_heading >= 0.0 else 90.0
		map_view.draft_station = {"id": "draft", "name": "新建车站", "latlng": latlng, "heading": heading, "lengthM": float(profile.get("trainLengthM", 118.788)), "widthM": 20.0, "vehicleId": str(profile.get("id", "B-6")), "routeIds": [active_route_id]}
		_on_draft_station_changed()
		map_view.requested_redraw(); _refresh_tools(); _show_toast("站体预览已放置；按 R 调方向，再确认")
		return
	if current_tool == "connect":
		var station_id := hit_id
		var endpoint_side := side
		if hit_type == "station":
			var station := WorldData.find_station(world, hit_id)
			if not station.is_empty():
				var start_pos := Geo.project(WorldData.station_endpoint(station, "start"), map_view.current_zoom)
				var end_pos := Geo.project(WorldData.station_endpoint(station, "end"), map_view.current_zoom)
				var click_pos := Geo.project(latlng, map_view.current_zoom)
				endpoint_side = "start" if click_pos.distance_to(start_pos) < click_pos.distance_to(end_pos) else "end"
		if hit_type not in ["station", "endpoint"]:
			_show_toast("请点车站旁的绿色／橙色端点")
			return
		if map_view.link_start.is_empty():
			map_view.link_start = {"stationId": station_id, "side": endpoint_side}
			selected_type = "station"; selected_id = station_id
			map_view.requested_redraw(); _refresh_ui(); _show_toast("已选择轨道起点，请点另一座站的端点")
		else:
			var a_ref: Dictionary = map_view.link_start
			if str(a_ref.stationId) == station_id:
				_show_toast("一段轨道需要连接两座不同的车站")
				return
			var a_station := WorldData.find_station(world, str(a_ref.stationId))
			var b_station := WorldData.find_station(world, station_id)
			var a_ll := WorldData.station_endpoint(a_station, str(a_ref.side))
			var b_ll := WorldData.station_endpoint(b_station, endpoint_side)
			if _distance_m(a_ll, b_ll) < 1.0:
				_show_toast("端点重合，无法创建零长度区间")
				return
			var route_id := active_route_id
			var route := WorldData.find_route(world, route_id)
			if route.is_empty(): route = _new_route(false); route_id = active_route_id
			var curve := WorldData.default_curve_vectors(a_station, str(a_ref.side), b_station, endpoint_side, float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0]))
			var link := {"id": "trk_%d" % Time.get_ticks_msec(), "a": a_ref.duplicate(true), "b": {"stationId": station_id, "side": endpoint_side}, "curveA": curve.a, "curveB": curve.b, "routeIds": [route_id], "schematic": false}
			var changed := history.execute("连接轨道", func(state: Dictionary):
				state.trackLinks.append(link)
				var r := WorldData.find_route(state, route_id)
				for sid in [str(a_ref.stationId), station_id]:
					if not r.stationOrder.has(sid): r.stationOrder.append(sid)
					var st := WorldData.find_station(state, sid)
					if not st.routeIds.has(route_id): st.routeIds.append(route_id)
			)
			map_view.link_start = {}
			current_tool = "select"
			map_view.tool = current_tool
			selected_type = "route"; selected_id = route_id
			map_view.requested_redraw(); _refresh_ui()
			if changed: _after_planning_change("已接轨；检查线路后可开通")
		return
	if current_tool == "delete":
		if hit_type == "station": _delete_station(hit_id)
		elif hit_type == "link": _delete_link(hit_id)
		elif hit_type == "demand": _show_toast("需求地点是城市资料，不能拆除")
		return
	if hit_type == "station": _select_object("station", hit_id)
	elif hit_type == "link": _select_object("link", hit_id)
	elif hit_type == "demand": _select_object("demand", hit_id)
	else:
		selected_type = ""; selected_id = ""; _refresh_ui()

func _confirm_station() -> void:
	if map_view.draft_station.is_empty(): return
	var draft: Dictionary = map_view.draft_station.duplicate(true)
	if _station_overlaps(draft):
		map_view.draft_conflict = true
		map_view.requested_redraw(); _refresh_tools()
		_show_toast("站体与另一座站重叠；移到空位或转向后再确认")
		return
	var route_id := str(draft.get("routeIds", [""])[0])
	var created: Dictionary = {}
	var station_count_before: int = world.get("stations", []).size()
	var success := history.execute("新建%s站" % draft.get("name", "车站"), func(state: Dictionary):
		created = WorldData.create_station(state, draft.latlng, float(draft.heading), route_id)
	)
	if not success: return
	if created.is_empty() and world.get("stations", []).size() > station_count_before:
		created = world.stations.back()
	map_view.draft_station = {}
	map_view.draft_conflict = false
	current_tool = "select"; map_view.tool = current_tool
	selected_type = "station"; selected_id = str(created.get("id", ""))
	_onboarding_note_station(created)
	map_view.requested_redraw(); _update_tutorial(); _refresh_ui(); _after_planning_change("已新建车站；端点随列车长度放置")

func _on_draft_station_changed() -> void:
	map_view.draft_conflict = not map_view.draft_station.is_empty() and _station_overlaps(map_view.draft_station)
	map_view.requested_redraw()
	_refresh_tools()

func _cancel_tool_step() -> void:
	if world.is_empty(): return
	if not map_view.draft_station.is_empty(): map_view.draft_station = {}; map_view.draft_conflict = false
	elif not map_view.link_start.is_empty(): map_view.link_start = {}
	else:
		current_tool = "select"
	map_view.tool = current_tool
	map_view.requested_redraw(); _refresh_tools()

func _set_tool(new_tool: String) -> void:
	if new_tool == current_tool:
		_cancel_tool_step(); return
	map_view.draft_station = {}; map_view.link_start = {}
	current_tool = new_tool
	map_view.tool = current_tool
	if current_tool == "station" and active_route_id.is_empty(): _new_route()
	map_view.requested_redraw(); _refresh_tools()
	match current_tool:
		"station": _show_toast("点击地图选站址；R 转向；点底栏「确认站点」完成")
		"connect": _show_toast("点击车站端点 A，再点击车站端点 B")
		"curve": _show_toast("拖动线路上的蓝色控制点调整弯曲；里程和时间将同步重算")
		"delete": _show_toast("点击车站拆除；线路和相邻区间一并调整")
		_: _show_toast("选择模式：点击对象查看，拖动车站调整位置")

func _station_overlaps(candidate: Dictionary) -> bool:
	var ref_lat := float(candidate.latlng[0])
	var center := Geo.local_m(candidate.latlng, ref_lat)
	var ang := deg_to_rad(float(candidate.heading))
	var along := Vector2(sin(ang), cos(ang))
	var across := Vector2(along.y, -along.x)
	var poly := _rect_points(center, along, across, float(candidate.lengthM)*.5, float(candidate.widthM)*.5)
	for station in world.get("stations", []):
		if str(station.get("id", "")) == str(candidate.get("id", "")): continue
		var other_center := Geo.local_m(station.latlng, ref_lat)
		var a := deg_to_rad(float(station.get("heading", 90)))
		var other_along := Vector2(sin(a), cos(a))
		var other_across := Vector2(other_along.y, -other_along.x)
		var other_poly := _rect_points(other_center, other_along, other_across, float(station.get("lengthM", 118.8))*.5, float(station.get("widthM", 20.0))*.5)
		if _polygons_intersect(poly, other_poly): return true
	return false

func _rect_points(c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float) -> Array[Vector2]:
	return [c-u*hu-v*hv,c+u*hu-v*hv,c+u*hu+v*hv,c-u*hu+v*hv]

func _polygons_intersect(a: Array[Vector2], b: Array[Vector2]) -> bool:
	for poly in [a,b]:
		for i in range(poly.size()):
			var edge: Vector2 = poly[(i+1)%poly.size()] - poly[i]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
			for p in a: amin = minf(amin,p.dot(axis)); amax = maxf(amax,p.dot(axis))
			for p in b: bmin = minf(bmin,p.dot(axis)); bmax = maxf(bmax,p.dot(axis))
			if amax <= bmin or bmax <= amin: return false
	return true

func _open_route() -> void:
	var route := WorldData.find_route(world, active_route_id if selected_type != "route" else selected_id)
	if selected_type == "route": active_route_id = selected_id
	if route.is_empty():
		_show_toast("先建立或选择一条线路")
		return
	var onboarding: Dictionary = world.get("onboarding", {})
	if bool(onboarding.get("active", false)) and int(onboarding.get("step", 0)) == 4:
		var target_route := _onboarding_route_for_pair(false)
		if target_route.is_empty() or str(target_route.get("id", "")) != str(route.get("id", "")):
			onboarding.lastError = "当前线路没有通过任务里的两座车站形成连续轨道。"
			world["onboarding"] = onboarding
			_refresh_onboarding_card()
			_show_issue("任务线路尚未连通；开通其他线路不能完成这一步。")
			return
	var order: Array = route.get("stationOrder", [])
	var links: Array = []
	for link in world.get("trackLinks", []):
		if link.get("routeIds", []).has(route.id): links.append(link)
	if order.size() < 2 or links.is_empty():
		_show_issue("阻断：至少需要两站和一段已连接轨道。距离不作为开通门槛。")
		return
	var reached: Dictionary = {str(order[0]): true}
	var changed := true
	while changed:
		changed = false
		for link in links:
			var a := str(link.a.stationId); var b := str(link.b.stationId)
			if reached.has(a) and not reached.has(b): reached[b] = true; changed = true
			elif reached.has(b) and not reached.has(a): reached[a] = true; changed = true
	for sid in order:
		if not reached.has(str(sid)):
			_show_issue("阻断：线路停站序列中有车站尚未接入轨网。请先连接端点。")
			return
	history.execute("开通%s" % route.get("name", "线路"), func(state: Dictionary):
		var r := WorldData.find_route(state, str(route.id))
		r.open = true
	)
	_update_tutorial(); _refresh_ui(); _after_planning_change("线路已开通；站距只影響行车时间")

func _new_route(refresh: bool = true) -> Dictionary:
	var colors := ["#e25263", "#478fdf", "#34a67f", "#db9638", "#9b69ce", "#36aeb4"]
	var route_name := "%d号线" % (world.get("routes", []).size() + 1)
	var route: Dictionary = {}
	var index: int = world.get("routes", []).size()
	var changed := history.execute("新建线路%s" % route_name, func(state: Dictionary): route = WorldData.add_route(state, route_name, colors[index % colors.size()]))
	if not changed: route = WorldData.add_route(world, route_name, colors[index % colors.size()])
	active_route_id = str(route.id)
	selected_type = "route"; selected_id = active_route_id
	if refresh: _refresh_ui(); _after_planning_change("已新建线路")
	return route

func _delete_station(station_id: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var station_name := str(station.get("name", "车站"))
	history.execute("删除%s" % station_name, func(state: Dictionary):
		state.stations = state.stations.filter(func(st: Dictionary): return str(st.get("id", "")) != station_id)
		state.trackLinks = state.trackLinks.filter(func(link: Dictionary): return str(link.get("a", {}).get("stationId", "")) != station_id and str(link.get("b", {}).get("stationId", "")) != station_id)
		for route in state.routes:
			route.stationOrder = route.get("stationOrder", []).filter(func(id: String): return id != station_id)
		for id in station.get("routeIds", []):
			var route := WorldData.find_route(state, str(id))
			if not route.is_empty(): route.open = false
	)
	selected_id = ""; selected_type = ""; _after_planning_change("车站与相邻区间已一并移除")

func _delete_route(route_id: String) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	history.execute("删除线路%s" % route.get("name", ""), func(state: Dictionary):
		state.trackLinks = state.trackLinks.filter(func(link: Dictionary): return not link.get("routeIds", []).has(route_id))
		state.routes = state.routes.filter(func(item: Dictionary): return str(item.get("id", "")) != route_id)
		for st in state.stations:
			st.routeIds = st.get("routeIds", []).filter(func(id: String): return id != route_id)
	)
	active_route_id = str(world.get("routes", [{}])[0].get("id", "")) if not world.get("routes", []).is_empty() else ""
	selected_id = ""; selected_type = ""; _after_planning_change("线路已删除；无关联线路的车站保留")

func _rename_station(station_id: String, value: String) -> void:
	var name := value.strip_edges()
	var station := WorldData.find_station(world, station_id)
	if station.is_empty() or name.is_empty() or station.get("name", "") == name: return
	history.execute("重命名%s" % station.get("name", "车站"), func(state: Dictionary): WorldData.find_station(state, station_id).name = name)
	_after_planning_change("车站名称已更新")

func _rename_route(route_id: String, value: String) -> void:
	var name := value.strip_edges(); var route := WorldData.find_route(world, route_id)
	if route.is_empty() or name.is_empty() or route.get("name", "") == name: return
	history.execute("重命名线路", func(state: Dictionary): WorldData.find_route(state, route_id).name = name)
	_after_planning_change("线路名称已更新")

func _change_station_vehicle(station_id: String, vehicle_id: String) -> void:
	var station := WorldData.find_station(world, station_id); var profile := WorldData.vehicle(vehicle_id)
	if station.is_empty() or profile.is_empty() or station.get("vehicleId", "") == vehicle_id: return
	var conflict := false
	var old_length := float(station.get("lengthM", 118.8))
	var new_length := float(profile.get("trainLengthM", 118.8))
	for other in world.stations:
		if str(other.id) != station_id and _distance_m(station.latlng, other.latlng) < (new_length + float(other.get("lengthM", 118.8))) * 0.5:
			conflict = true
	if conflict:
		_show_toast("车型替换预览：站台将增长 %.0f 米，请先移开附近站体。" % (new_length-old_length))
		return
	history.execute("更换车站车型", func(state: Dictionary):
		var st := WorldData.find_station(state, station_id)
		st.vehicleId = vehicle_id; st.lengthM = new_length
	)
	_after_planning_change("列车与站体长度已联动更新")

func _change_route_vehicle(route_id: String, vehicle_id: String) -> void:
	var profile := WorldData.vehicle(vehicle_id); var route := WorldData.find_route(world, route_id)
	if profile.is_empty() or route.is_empty(): return
	var conflict := false
	for station_id in route.get("stationOrder", []):
		var st := WorldData.find_station(world, str(station_id))
		if not st.is_empty() and _station_vehicle_conflict(st, vehicle_id): conflict = true
	if conflict:
		_show_toast("有站体无法容纳该编组长度；请逐站迁移，避免静默缩短")
		return
	history.execute("更换线路车型", func(state: Dictionary):
		var r := WorldData.find_route(state, route_id); r.vehicleId = vehicle_id
		for sid in r.stationOrder:
			var st := WorldData.find_station(state, str(sid)); if not st.is_empty(): st.vehicleId = vehicle_id; st.lengthM = float(profile.trainLengthM)
	)
	_after_planning_change("线路车型已更换；相连站体尺寸一并更新")

func _station_vehicle_conflict(station: Dictionary, vehicle_id: String) -> bool:
	var profile := WorldData.vehicle(vehicle_id)
	var required := float(profile.get("trainLengthM", 118.8))
	for other in world.stations:
		if str(other.id) == str(station.id): continue
		if _distance_m(station.latlng, other.latlng) < (required + float(other.get("lengthM", 118.8))) * .5: return true
	return false

func _change_headway(route_id: String, value: int) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty() or int(route.get("headway", 3)) == value: return
	history.execute("调整发车间隔", func(state: Dictionary): WorldData.find_route(state, route_id).headway = value)
	_after_planning_change("发车间隔已更新")

func _rotate_station(station_id: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var draft := station.duplicate(true)
	draft.heading = fposmod(float(draft.get("heading", 90.0)) + 15.0, 360.0)
	if _station_overlaps(draft):
		_show_toast("旋转后会与相邻站体重叠；已保留原方向")
		return
	history.execute("旋转%s" % station.get("name", "车站"), func(state: Dictionary):
		var st := WorldData.find_station(state, station_id)
		st.heading = draft.heading
	)
	_after_planning_change("车站方向已调整")

func _on_station_drag_preview(station_id: String, latlng: Array) -> void:
	map_view._station_drag_preview_update(station_id, latlng)

func _on_station_drag_finished(station_id: String, latlng: Array) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var draft := station.duplicate(true); draft.latlng = latlng
	if _station_overlaps(draft):
		_show_toast("位置冲突：站体会与另一座站重叠，已恢复原位")
		map_view.requested_redraw(); return
	var changed := history.execute("移动%s" % station.get("name", "车站"), func(state: Dictionary): WorldData.find_station(state, station_id).latlng = latlng)
	if changed: _after_planning_change("站点已移动；相邻区间将按站端重新绘制")

func _on_curve_control_finished(link_id: String, control_name: String, offset_m: Array) -> void:
	var key := "curveA" if control_name == "curveA" else "curveB"
	var link: Dictionary = {}
	for item in world.get("trackLinks", []):
		if str(item.get("id", "")) == link_id:
			link = item
			break
	if link.is_empty() or JSON.stringify(link.get(key, [])) == JSON.stringify(offset_m): return
	history.execute("调整轨道曲线", func(state: Dictionary):
		for item in state.trackLinks:
			if str(item.get("id", "")) == link_id:
				item[key] = offset_m
				break
	)
	_after_planning_change("轨道曲线已更新；线路里程与乘客时间随之重算")

func _select_object(kind: String, object_id: String) -> void:
	selected_type = kind; selected_id = object_id
	if kind == "route": active_route_id = object_id
	map_view.active_route_id = active_route_id
	map_view.selected_type = kind; map_view.selected_id = object_id; map_view.requested_redraw()
	_refresh_ui()

func _find_link(link_id: String) -> Dictionary:
	for link in world.get("trackLinks", []):
		if str(link.get("id", "")) == link_id: return link
	return {}

func _delete_link(link_id: String) -> void:
	var link := _find_link(link_id)
	if link.is_empty(): return
	var affected_names: Array[String] = []
	for route_id in link.get("routeIds", []):
		var route := WorldData.find_route(world, str(route_id))
		if not route.is_empty(): affected_names.append(str(route.get("name", "线路")))
	history.execute("删除轨道区间", func(state: Dictionary):
		state.trackLinks = state.get("trackLinks", []).filter(func(item: Dictionary): return str(item.get("id", "")) != link_id)
		for route_id in link.get("routeIds", []):
			var route := WorldData.find_route(state, str(route_id))
			if not route.is_empty(): route.open = false
	)
	selected_type = ""
	selected_id = ""
	_after_planning_change("区间已删除%s；受影响线路已暂停，操作可撤销" % (" · " + "、".join(affected_names) if not affected_names.is_empty() else ""))

func _do_undo() -> void:
	if world.is_empty(): return
	world.simulation.paused = true
	var label := history.undo()
	if label.is_empty(): _show_toast("没有可撤销的规划操作"); return
	selected_type = ""; selected_id = ""; map_view.set_world(world); _update_tutorial(); _autosave(); _refresh_ui(); _show_toast("已撤销：%s · 游戏时钟保持不变" % label)

func _do_redo() -> void:
	if world.is_empty(): return
	world.simulation.paused = true
	var label := history.redo()
	if label.is_empty(): _show_toast("没有可重做的操作"); return
	selected_type = ""; selected_id = ""; map_view.set_world(world); _update_tutorial(); _autosave(); _refresh_ui(); _show_toast("已重做：%s" % label)

func _toggle_pause() -> void:
	world.simulation.paused = not bool(world.simulation.get("paused", true))
	if world.simulation.paused: _autosave()
	_update_topbar()

func _simulate_one_minute() -> void:
	if world.is_empty(): return
	var sim: Dictionary = world.simulation
	sim.minute = int(sim.get("minute", 420)) + 1
	if sim.minute >= 1440: sim.minute = 0
	if _flow_cache_revision != int(world.get("revision", 0)):
		_rebuild_flow_cache()
	var minute_of_day := int(sim.minute) % 1440
	var hour := minute_of_day / 60
	var peak := 0.55
	if hour >= 7 and hour < 10: peak = 2.1
	elif hour >= 16 and hour < 19: peak = 1.8
	elif hour >= 11 and hour < 14: peak = 1.1
	var remainders: Dictionary = sim.get("flowRemainders", {})
	var route_flow: Dictionary = {}
	var arrivals_by_flow: Dictionary = {}
	var attempted := 0
	var onboarding: Dictionary = world.get("onboarding", {})
	var observe_target := bool(onboarding.get("active", false)) and bool(onboarding.get("observationStarted", false))
	var target_flow_id := "%s>%s" % [str(onboarding.get("originId", "")), str(onboarding.get("destinationId", ""))]
	var target_flow := _onboarding_flow() if observe_target else {}
	var target_route_id := str(target_flow.get("routeId", "")) if bool(target_flow.get("valid", false)) else ""
	var target_arrivals_this_minute := 0
	for flow in _flow_cache:
		var expected := float(flow.get("peoplePerDay", 0.0)) / (16.0 * 60.0) * peak
		var accumulated := float(remainders.get(str(flow.id), 0.0)) + expected
		var arrivals := int(floor(accumulated))
		remainders[str(flow.id)] = accumulated - arrivals
		attempted += arrivals
		arrivals_by_flow[str(flow.id)] = arrivals
		if str(flow.get("id", "")) == target_flow_id and bool(flow.get("valid", false)) and str(flow.get("routeId", "")) == target_route_id:
			target_arrivals_this_minute = arrivals
		if bool(flow.get("valid", false)) and arrivals > 0:
			var route_id := str(flow.get("routeId", ""))
			route_flow[route_id] = int(route_flow.get(route_id, 0)) + arrivals
	var served := 0
	var weighted_minutes := 0.0
	var worst_crowding := 0.0
	var target_served_this_minute := 0
	for route_id in route_flow:
		var route := WorldData.find_route(world, str(route_id))
		var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
		var capacity_per_minute := float(profile.get("capacity", 1800)) / maxf(1.0, float(route.get("headway", 3)))
		var route_arrivals := int(route_flow[route_id])
		var route_served := mini(route_arrivals, int(floor(capacity_per_minute)))
		worst_crowding = maxf(worst_crowding, float(route_arrivals) / maxf(1.0, capacity_per_minute))
		if route_arrivals > 0:
			for flow in _flow_cache:
				if str(flow.get("routeId", "")) == str(route_id):
					var flow_arrivals := int(arrivals_by_flow.get(str(flow.id), 0))
					var served_share := float(route_served) * float(flow_arrivals) / float(route_arrivals)
					weighted_minutes += served_share * float(flow.get("tripMinutes", 0.0))
					if str(flow.get("id", "")) == target_flow_id and str(route_id) == target_route_id:
						var fractional_service := float(onboarding.get("targetServiceRemainder", 0.0)) + served_share
						target_served_this_minute = mini(target_arrivals_this_minute, int(floor(fractional_service)))
						onboarding.targetServiceRemainder = fractional_service - floor(fractional_service)
		served += route_served
	sim["flowRemainders"] = remainders
	sim["attempted"] = int(sim.get("attempted", 0)) + attempted
	sim["served"] = int(sim.get("served", 0)) + served
	sim["completed"] = int(sim.get("completed", 0)) + served
	sim["tripMinutesTotal"] = float(sim.get("tripMinutesTotal", 0.0)) + weighted_minutes
	sim["peakCrowding"] = worst_crowding
	world.simulation = sim
	if observe_target and not target_route_id.is_empty():
		onboarding.observedTargetArrivals = int(onboarding.get("observedTargetArrivals", 0)) + target_arrivals_this_minute
		onboarding.observedTargetServed = int(onboarding.get("observedTargetServed", 0)) + target_served_this_minute
		world["onboarding"] = onboarding
	_update_tutorial()

func _network_summary() -> Dictionary:
	return {"stations": world.get("stations", []).size(), "links": world.get("trackLinks", []).size(), "routes": world.get("routes", []).size()}

func _nearest_station(latlng: Array) -> Dictionary:
	var best: Dictionary = {}; var best_distance := INF
	for station in world.get("stations", []):
		var dist := _distance_m(latlng, station.get("latlng", [0,0]))
		if dist < best_distance: best_distance = dist; best = station
	return best

func _nearest_connected_station(latlng: Array) -> bool:
	var station := _nearest_station(latlng)
	if station.is_empty() or _distance_m(latlng, station.latlng) > 800.0: return false
	for route in world.get("routes", []):
		if not route.get("open", false): continue
		if route.get("stationOrder", []).has(str(station.id)): return true
	return false

func _rebuild_flow_cache() -> void:
	_flow_cache.clear()
	var demands: Array = WorldData.city(active_city_id).get("demand", [])
	var housing: Array = demands.filter(func(point: Dictionary): return str(point.get("type", "")) == "housing")
	var destinations := {"employment": 0.17, "education": 0.055, "health": 0.04, "commerce": 0.035, "hub": 0.04, "culture": 0.025}
	var open_routes: Array[Dictionary] = []
	for route in world.get("routes", []):
		if not route.get("open", false): continue
		var adjacency: Dictionary = {}
		for link in world.get("trackLinks", []):
			if not link.get("routeIds", []).has(str(route.id)): continue
			var a := str(link.get("a", {}).get("stationId", "")); var b := str(link.get("b", {}).get("stationId", ""))
			if not adjacency.has(a): adjacency[a] = []
			if not adjacency.has(b): adjacency[b] = []
			adjacency[a].append({"to": b, "link": link}); adjacency[b].append({"to": a, "link": link})
		open_routes.append({"route": route, "adjacency": adjacency})
	for origin in housing:
		for destination in demands:
			var target_type := str(destination.get("type", ""))
			if not destinations.has(target_type): continue
			if str(origin.get("id", "")) == str(destination.get("id", "")): continue
			var distance := _distance_m(origin.get("latlng", [0,0]), destination.get("latlng", [0,0]))
			if distance > 40000.0: continue
			var daily := minf(float(origin.get("gameDemand", {}).get("base", 0)), float(destination.get("gameDemand", {}).get("base", 0))) * float(destinations[target_type])
			_append_flow_pair(origin, destination, daily, open_routes)
			_append_flow_pair(destination, origin, daily * 0.85, open_routes)
	_flow_cache_revision = int(world.get("revision", 0))

func _append_flow_pair(origin: Dictionary, destination: Dictionary, people_per_day: float, routes: Array[Dictionary]) -> void:
	var origin_station := _nearest_station(origin.get("latlng", [0,0]))
	var destination_station := _nearest_station(destination.get("latlng", [0,0]))
	var valid := false
	var route_id := ""
	var trip_minutes := 0.0
	var origin_walk := _distance_m(origin.get("latlng", [0,0]), origin_station.get("latlng", [0,0])) if not origin_station.is_empty() else INF
	var destination_walk := _distance_m(destination.get("latlng", [0,0]), destination_station.get("latlng", [0,0])) if not destination_station.is_empty() else INF
	if origin_walk <= 800.0 and destination_walk <= 800.0 and str(origin_station.get("id", "")) != str(destination_station.get("id", "")):
		for record in routes:
			var route: Dictionary = record.route
			var adjacency: Dictionary = record.adjacency
			var start_id := str(origin_station.id); var end_id := str(destination_station.id)
			var path := _route_link_path(adjacency, start_id, end_id)
			if not path.is_empty():
				valid = true; route_id = str(route.id)
				var distance_m := 0.0
				for link in path:
					distance_m += WorldData.track_length_m(link, world, float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0]))
				var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
				var rail_mins := TravelModelScript.rail_minutes(distance_m, float(profile.get("maxSpeedKmh", 80)))
				var dwell := maxf(0.0, float(path.size() - 1)) * 0.5
				var walking := TravelModelScript.walk_minutes(origin_walk + destination_walk)
				trip_minutes = rail_mins + dwell + float(route.get("headway", 3)) * 0.5 + walking
				break
	_flow_cache.append({"id": "%s>%s" % [origin.get("id", ""), destination.get("id", "")], "fromId": origin.get("id", ""), "toId": destination.get("id", ""), "from": origin.get("name", ""), "to": destination.get("name", ""), "peoplePerDay": people_per_day, "valid": valid, "routeId": route_id, "tripMinutes": trip_minutes})

func _route_link_path(adjacency: Dictionary, start_id: String, end_id: String) -> Array:
	if start_id == end_id: return []
	var queue: Array[String] = [start_id]
	var seen := {start_id: true}
	var previous: Dictionary = {}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for edge in adjacency.get(current, []):
			var next := str(edge.get("to", ""))
			if seen.has(next): continue
			seen[next] = true; previous[next] = {"station": current, "link": edge.get("link", {})}
			if next == end_id:
				var path: Array = []; var cursor := end_id
				while cursor != start_id:
					var record: Dictionary = previous[cursor]; path.push_front(record.link); cursor = str(record.station)
				return path
			queue.append(next)
	return []

func _ensure_flow_cache() -> void:
	if _flow_cache_revision != int(world.get("revision", 0)): _rebuild_flow_cache()

func _focus_flow(flow: Dictionary) -> void:
	var origin := _find_demand(str(flow.get("fromId", "")))
	var destination := _find_demand(str(flow.get("toId", "")))
	if origin.is_empty() or destination.is_empty(): return
	map_view.task_origin = origin.get("latlng", []).duplicate()
	map_view.task_destination = destination.get("latlng", []).duplicate()
	map_view.task_origin_name = str(origin.get("name", "起点"))
	map_view.task_destination_name = str(destination.get("name", "目的地"))
	var center := [(float(origin.latlng[0])+float(destination.latlng[0]))*.5, (float(origin.latlng[1])+float(destination.latlng[1]))*.5]
	var distance := _distance_m(origin.latlng, destination.latlng)
	var target_zoom := 11
	if distance < 30000: target_zoom = 12
	if distance < 15000: target_zoom = 13
	if distance < 8000: target_zoom = 14
	if distance < 4000: target_zoom = 15
	map_view.center_on(center, target_zoom)
	map_view.requested_redraw()
	_show_toast("已定位需求方向；虚线是规划提示，不代表现有道路或客流路径")

func _find_demand(demand_id: String) -> Dictionary:
	for demand in WorldData.city(active_city_id).get("demand", []):
		if str(demand.get("id", "")) == demand_id: return demand
	return {}

func _sync_onboarding_map(focus_task: bool = false) -> void:
	if world.is_empty() or not is_instance_valid(map_view): return
	var onboarding: Dictionary = world.get("onboarding", {})
	var active := bool(onboarding.get("active", false))
	var origin := _find_demand(str(onboarding.get("originId", "")))
	var destination := _find_demand(str(onboarding.get("destinationId", "")))
	map_view.clean_map_style = UiPreferencesScript.load_clean_map()
	map_view.filter_demand_to_task = active and not bool(onboarding.get("viewingCity", false))
	map_view.focus_demand_ids = [str(onboarding.get("originId", "")), str(onboarding.get("destinationId", ""))]
	map_view.task_coverage_visible = active and int(onboarding.get("step", 0)) in [1, 2]
	map_view.task_origin_id = str(onboarding.get("originId", ""))
	map_view.task_destination_id = str(onboarding.get("destinationId", ""))
	map_view.task_origin = origin.get("latlng", []).duplicate() if not origin.is_empty() else []
	map_view.task_destination = destination.get("latlng", []).duplicate() if not destination.is_empty() else []
	map_view.task_origin_name = str(origin.get("name", "起点"))
	map_view.task_destination_name = str(destination.get("name", "目的地"))
	map_view.task_recommended_latlng = []
	if active and not origin.is_empty() and not destination.is_empty() and int(onboarding.get("step", 0)) in [1, 2]:
		var amount := 0.18 if int(onboarding.get("step", 0)) == 1 else 0.82
		map_view.task_recommended_latlng = [
			lerpf(float(origin.latlng[0]), float(destination.latlng[0]), amount),
			lerpf(float(origin.latlng[1]), float(destination.latlng[1]), amount)
		]
	if focus_task and not origin.is_empty() and not destination.is_empty():
		var center := [(float(origin.latlng[0]) + float(destination.latlng[0])) * 0.5, (float(origin.latlng[1]) + float(destination.latlng[1])) * 0.5]
		var distance := _distance_m(origin.latlng, destination.latlng)
		var zoom := 15 if distance < 1500.0 else 14 if distance < 4500.0 else 13 if distance < 9000.0 else 12
		map_view.center_on(center, zoom)
	map_view.requested_redraw()

func _refresh_onboarding_card() -> void:
	if not is_instance_valid(onboarding_panel): return
	for child in onboarding_panel.get_children(): child.queue_free()
	var onboarding: Dictionary = world.get("onboarding", {}) if not world.is_empty() else {}
	var active := bool(onboarding.get("active", false))
	onboarding_panel.visible = active
	if not active: return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_theme_constant_override("margin_left", 14); box.add_theme_constant_override("margin_right", 14)
	box.add_theme_constant_override("margin_top", 12); box.add_theme_constant_override("margin_bottom", 12)
	onboarding_panel.add_child(box)
	var step := int(onboarding.get("step", 0))
	var mission := OnboardingScript.mission(active_city_id)
	var headings := ["先看懂这组出行", "第一站：覆盖 A 起点", "第二站：覆盖 B 终点", "把两站接起来", "检查并开通这条线", "运行一小段时间", "这一组街区需求已接入"]
	box.add_child(_label("街区规划引导   %s" % ("已完成" if step >= 6 else "第 %d / 6 步" % (step + 1)), 13, TEAL, true))
	box.add_child(_label(headings[clampi(step, 0, headings.size() - 1)], 19, TEXT, true))
	var description := ""
	var condition := ""
	match step:
		0:
			description = str(mission.get("theme", "观察一组城市出行需求")) + "。橙色箭头表示人们的出行方向，不是让你照着铺的轨道。"
			condition = "先决定你想怎样服务这两处地点。"
		1:
			description = "在 A 起点附近选一个站址。绿色圆圈表示 800 米游戏接驳估算范围；圆心只是推荐区域，不会自动建站。"
			condition = "站体中心需在 A 起点 800 米内，确认后才算完成。"
		2:
			description = "现在为 B 终点安排另一座车站。可以沿绿色建议点选址，也可以自由调整位置和朝向。"
			condition = "需要一座不同的车站覆盖 B 终点。"
		3:
			description = "选择“连接轨道”，点击第一座站的 A／B 端，再点击另一座站的端点。必须连接任务里的两站。"
			condition = "连接后会自动检查端点间的连续轨道。"
		4:
			description = "线路检查只针对服务 A、B 的这条实际连续路径。只有孤立站或其他线路不会替代这项任务。"
			condition = "建议项不阻止开通；先解决断连等阻断问题。"
		5:
			var flow := _onboarding_flow()
			var arrived := int(onboarding.get("observedTargetArrivals", 0))
			var served := int(onboarding.get("observedTargetServed", 0))
			description = "按播放，让模拟推进并观察这组需求。" if not bool(onboarding.get("observationStarted", false)) else "模拟正在运行。目标需求已到达 %d 人、估算获得服务 %d 人；暂停不会重置结果。" % [arrived, served]
			condition = "出行量与时间来自游戏模拟；不会把聚合统计画成逐人行走动画。"
			if bool(flow.get("valid", false)):
				condition += " 当前估算：约 %s 人次/日，出行 %.1f 分钟。" % [_number(int(round(float(flow.get("peoplePerDay", 0.0))))), float(flow.get("tripMinutes", 0.0))]
		6:
			var complete_flow := _onboarding_flow()
			description = "这组需求已通过你规划的两座站和连续线路接入。模型估算约 %s 人次/日，出行 %.1f 分钟。" % [_number(int(round(float(complete_flow.get("peoplePerDay", 0.0))))), float(complete_flow.get("tripMinutes", 0.0))]
			condition = "这是聚合模拟估算，不是逐人完成行程的动画。你可以继续扩建，也可以查看全城。"
	box.add_child(_label(str(mission.get("reason", "")), 13, MUTED))
	var body := _label(description, 15, TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	var detail := _label(condition, 13, Color("#b9c8ce"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	var error_text := str(onboarding.get("lastError", ""))
	if not error_text.is_empty():
		var error_label := _label("需要处理：" + error_text, 13, Color("#ffad91"), true)
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(error_label)
	var primary_label := "开始规划" if step == 0 else "开始建第一站" if step == 1 else "开始建第二站" if step == 2 else "启用连接轨道工具" if step == 3 and current_tool != "connect" else "在地图上连接两站端点" if step == 3 else "检查并开通任务线路" if step == 4 else "播放并观察" if step == 5 and not bool(onboarding.get("observationStarted", false)) else "继续扩建这个街区" if step == 6 else "正在运行 · 等待这组需求的模拟结果"
	var primary := _button(primary_label, Color("#eafff8"), Color("#17644f"), 16)
	primary.custom_minimum_size.y = 44.0 * _ui_scale
	primary.disabled = step == 3 and current_tool == "connect" or step == 5 and bool(onboarding.get("observationStarted", false))
	primary.pressed.connect(_onboarding_primary_action)
	box.add_child(primary)
	var secondary_row := HFlowContainer.new()
	secondary_row.add_theme_constant_override("h_separation", 6)
	secondary_row.add_theme_constant_override("v_separation", 4)
	var skip := _button("跳过引导", MUTED, PANEL_LIGHT, 13)
	skip.pressed.connect(func(): _end_onboarding(true))
	secondary_row.add_child(skip)
	var all_city := _button("查看全城", TEXT, PANEL_LIGHT, 13)
	all_city.pressed.connect(_show_onboarding_city)
	secondary_row.add_child(all_city)
	var return_task := _button("返回任务位置", TEXT, PANEL_LIGHT, 13)
	return_task.disabled = not bool(onboarding.get("viewingCity", false))
	return_task.pressed.connect(_return_to_onboarding_mission)
	secondary_row.add_child(return_task)
	box.add_child(secondary_row)

func _onboarding_primary_action() -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	var step := int(onboarding.get("step", 0))
	match step:
		0:
			_set_onboarding_step(1)
			_sync_onboarding_map(true)
		1, 2:
			var demand := _find_demand(str(onboarding.get("originId" if step == 1 else "destinationId", "")))
			if current_tool != "station": _set_tool("station")
			if not demand.is_empty(): map_view.center_on(demand.latlng, 15)
			_show_toast("在绿色建议区域附近点击地图放置预览，再确认站点")
		3:
			if current_tool != "connect": _set_tool("connect")
			else: _show_toast(_connection_instruction())
		4:
			var route := _onboarding_route_for_pair(false)
			if route.is_empty():
				onboarding.lastError = "任务两站之间还没有连续轨道。"
				_refresh_onboarding_card()
				return
			active_route_id = str(route.get("id", ""))
			selected_type = "route"; selected_id = active_route_id
			_open_route()
		5:
			if bool(onboarding.get("observationStarted", false)):
				_show_toast("继续运行；模拟累计到这组需求实际到达并获得服务后会显示结果")
				return
			onboarding.observationStarted = true
			onboarding.observationStartMinute = int(world.get("simulation", {}).get("minute", 420))
			onboarding.observedTargetArrivals = 0
			onboarding.observedTargetServed = 0
			onboarding.targetServiceRemainder = 0.0
			world.simulation.paused = false
			_update_topbar()
			_autosave()
			_refresh_onboarding_card()
			_show_toast("模拟已开始；会等这组出行产生可观察的服务结果")
		6:
			_end_onboarding(false)

func _set_onboarding_step(step: int) -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	onboarding.step = clampi(step, 0, 6)
	onboarding.lastError = ""
	world["onboarding"] = onboarding
	_sync_onboarding_map()
	_refresh_onboarding_card()
	_refresh_tools()
	_autosave()

func _onboarding_note_station(station: Dictionary) -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	if not bool(onboarding.get("active", false)): return
	var step := int(onboarding.get("step", 0))
	if step not in [1, 2]: return
	var demand_id := str(onboarding.get("originId" if step == 1 else "destinationId", ""))
	var demand := _find_demand(demand_id)
	if demand.is_empty() or station.get("latlng", []).size() < 2:
		onboarding.lastError = "无法读取车站或任务地点坐标，请重试这一步。"
		world["onboarding"] = onboarding
		_refresh_onboarding_card()
		return
	if _distance_m(station.get("latlng", []), demand.get("latlng", [])) > 800.0:
		onboarding.lastError = "车站离任务地点超过 800 米游戏估算范围。可以撤销并重新选址。"
		world["onboarding"] = onboarding
		_refresh_onboarding_card()
		return
	if step == 2 and str(station.get("id", "")) == str(onboarding.get("originStationId", "")):
		onboarding.lastError = "B 终点必须由另一座车站覆盖。"
		world["onboarding"] = onboarding
		_refresh_onboarding_card()
		return
	if step == 1:
		onboarding.originStationId = str(station.get("id", ""))
		_set_onboarding_step(2)
	else:
		onboarding.destinationStationId = str(station.get("id", ""))
		_set_onboarding_step(3)
		_show_toast("A、B 各有一座车站；下一步把两站端点接起来")

func _onboarding_station_ids_valid() -> bool:
	var onboarding: Dictionary = world.get("onboarding", {})
	var a := WorldData.find_station(world, str(onboarding.get("originStationId", "")))
	var b := WorldData.find_station(world, str(onboarding.get("destinationStationId", "")))
	var origin := _find_demand(str(onboarding.get("originId", "")))
	var destination := _find_demand(str(onboarding.get("destinationId", "")))
	if a.is_empty() or b.is_empty() or origin.is_empty() or destination.is_empty() or str(a.id) == str(b.id): return false
	return _distance_m(a.latlng, origin.latlng) <= 800.0 and _distance_m(b.latlng, destination.latlng) <= 800.0

func _onboarding_route_for_pair(require_open: bool) -> Dictionary:
	var onboarding: Dictionary = world.get("onboarding", {})
	if not _onboarding_station_ids_valid(): return {}
	var start_id := str(onboarding.get("originStationId", ""))
	var end_id := str(onboarding.get("destinationStationId", ""))
	var routes: Array = world.get("routes", []).duplicate()
	routes.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("id", "")) == active_route_id and str(b.get("id", "")) != active_route_id)
	for route in routes:
		if require_open and not bool(route.get("open", false)): continue
		if not route.get("stationOrder", []).has(start_id) or not route.get("stationOrder", []).has(end_id): continue
		var adjacency: Dictionary = {}
		for link in world.get("trackLinks", []):
			if not link.get("routeIds", []).has(str(route.get("id", ""))): continue
			var a_id := str(link.get("a", {}).get("stationId", ""))
			var b_id := str(link.get("b", {}).get("stationId", ""))
			if not adjacency.has(a_id): adjacency[a_id] = []
			if not adjacency.has(b_id): adjacency[b_id] = []
			adjacency[a_id].append({"to": b_id, "link": link})
			adjacency[b_id].append({"to": a_id, "link": link})
		if not _route_link_path(adjacency, start_id, end_id).is_empty(): return route
	return {}

func _onboarding_flow() -> Dictionary:
	var onboarding: Dictionary = world.get("onboarding", {})
	_ensure_flow_cache()
	var target_id := "%s>%s" % [str(onboarding.get("originId", "")), str(onboarding.get("destinationId", ""))]
	for flow in _flow_cache:
		if str(flow.get("id", "")) == target_id: return flow
	return {}

func _onboarding_city_center() -> void:
	var city := WorldData.city(active_city_id)
	map_view.center_on(city.get("center", [31.23, 121.47]), int(city.get("zoom", 12)))

func _show_onboarding_city() -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	onboarding.viewingCity = true
	world["onboarding"] = onboarding
	map_view.filter_demand_to_task = false
	map_view.requested_redraw()
	_onboarding_city_center()
	_refresh_onboarding_card()

func _return_to_onboarding_mission() -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	onboarding.viewingCity = false
	world["onboarding"] = onboarding
	_sync_onboarding_map(true)
	_refresh_onboarding_card()

func _end_onboarding(skipped: bool) -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	onboarding.active = false
	onboarding.skipped = skipped
	onboarding.viewingCity = false
	world["onboarding"] = onboarding
	map_view.filter_demand_to_task = false
	map_view.task_coverage_visible = false
	map_view.task_recommended_latlng = []
	map_view.task_origin = []; map_view.task_destination = []
	map_view.task_origin_id = ""; map_view.task_destination_id = ""
	map_view.task_origin_name = ""; map_view.task_destination_name = ""
	map_view.requested_redraw()
	var preference_saved := UiPreferencesScript.save_onboarding_completed(true) == OK
	current_tool = "select"; map_view.tool = "select"
	map_view.draft_station = {}; map_view.link_start = {}
	_refresh_onboarding_card(); _refresh_ui(); _autosave()
	var message := "引导已结束；之后可从左侧新手任务重玩。" if skipped else "街区规划引导完成；规划已保存在正式城市存档。"
	if not preference_saved: message += " 本机未能保存已看过标记。"
	_show_toast(message)

func _restart_onboarding() -> void:
	if str(world.get("mode", "blank")) != "blank":
		_locate_existing_network()
		return
	var state := OnboardingScript.create_state(active_city_id, str(world.get("mode", "blank")), false)
	state.active = true
	world["onboarding"] = state
	world.simulation.paused = true
	_left_requested = false; _right_requested = false
	_update_responsive_layout()
	_sync_onboarding_map(true)
	_refresh_ui(); _refresh_onboarding_card(); _autosave()
	_show_toast("街区引导已重开；既有规划保留，教学任务从头判断。")

func _locate_existing_network() -> void:
	for station in world.get("stations", []):
		if not bool(station.get("existing", false)): continue
		_select_object("station", str(station.get("id", "")))
		map_view.center_on(station.get("latlng", [0, 0]), 15)
		_show_toast("已定位既有车站；点击线路可查看站序和运营信息")
		return
	_show_toast("当前还没有既有车站；可以使用建站工具从空白处扩建")

func _route_length_km(route: Dictionary) -> float:
	var total := 0.0
	for link in world.get("trackLinks", []):
		if not link.get("routeIds", []).has(str(route.get("id", ""))): continue
		var a := WorldData.find_station(world, str(link.get("a", {}).get("stationId", "")))
		var b := WorldData.find_station(world, str(link.get("b", {}).get("stationId", "")))
		if not a.is_empty() and not b.is_empty():
			total += WorldData.track_length_m(link, world, float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0]))
	return total / 1000.0

func _distance_m(a: Array, b: Array) -> float:
	var ref_lat := (float(a[0]) + float(b[0])) * .5
	return Geo.local_m(a, ref_lat).distance_to(Geo.local_m(b, ref_lat))

func _onboarding_station_heading() -> float:
	var onboarding: Dictionary = world.get("onboarding", {})
	if not bool(onboarding.get("active", false)) or int(onboarding.get("step", 0)) not in [1, 2]: return -1.0
	var origin := _find_demand(str(onboarding.get("originId", "")))
	var destination := _find_demand(str(onboarding.get("destinationId", "")))
	if origin.is_empty() or destination.is_empty(): return -1.0
	var ref_lat := deg_to_rad((float(origin.latlng[0]) + float(destination.latlng[0])) * 0.5)
	var north := (float(destination.latlng[0]) - float(origin.latlng[0])) * 111320.0
	var east := (float(destination.latlng[1]) - float(origin.latlng[1])) * 111320.0 * cos(ref_lat)
	return fposmod(rad_to_deg(atan2(east, north)), 360.0)

func _update_tutorial() -> void:
	if world.is_empty(): return
	if world.has("onboarding"):
		_update_onboarding()
		return
	if world.get("tutorialDone", false): return
	var step := int(world.get("tutorialStep", 0))
	var next := step
	if step == 0 and world.get("stations", []).size() >= 2: next = 1
	if next == 1 and world.get("trackLinks", []).size() >= 1: next = 2
	var connected_open := false
	for route in world.get("routes", []):
		if route.get("open", false): connected_open = true
	if next == 2 and connected_open: next = 3
	if next == 3 and int(world.get("simulation", {}).get("completed", 0)) > 0:
		next = 4; world.tutorialDone = true
	if next != step: world.tutorialStep = next; _refresh_left_panel(); _show_toast("教学步骤更新：%s" % ["","连接两个端点","检查并开通线路","播放观察乘客","基础规划教学已完成"][next])

func _update_onboarding() -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	if not bool(onboarding.get("active", false)): return
	var old_step := int(onboarding.get("step", 0))
	var old_error := str(onboarding.get("lastError", ""))
	var step := old_step
	var origin := _find_demand(str(onboarding.get("originId", "")))
	var destination := _find_demand(str(onboarding.get("destinationId", "")))
	var origin_station := WorldData.find_station(world, str(onboarding.get("originStationId", "")))
	var destination_station := WorldData.find_station(world, str(onboarding.get("destinationStationId", "")))
	if step >= 2 and (origin.is_empty() or origin_station.is_empty() or _distance_m(origin_station.get("latlng", []), origin.get("latlng", [])) > 800.0):
		onboarding.originStationId = ""
		onboarding.destinationStationId = ""
		onboarding.taskRouteId = ""
		onboarding.observationStarted = false
		step = 1
		onboarding.lastError = "起点站已删除或移出覆盖范围。请重新选址。"
	elif step >= 3 and (destination.is_empty() or destination_station.is_empty() or _distance_m(destination_station.get("latlng", []), destination.get("latlng", [])) > 800.0 or str(onboarding.get("originStationId", "")) == str(onboarding.get("destinationStationId", ""))):
		onboarding.destinationStationId = ""
		onboarding.taskRouteId = ""
		onboarding.observationStarted = false
		step = 2
		onboarding.lastError = "终点站已删除、移位或与起点站相同。请重新安排另一座站。"
	if step >= 3:
		var connected_route := _onboarding_route_for_pair(false)
		if connected_route.is_empty():
			if step >= 4: onboarding.lastError = "任务两站之间的轨道已断开；请重新连接端点。"
			step = 3
			onboarding.taskRouteId = ""
			onboarding.observationStarted = false
		else:
			onboarding.taskRouteId = str(connected_route.get("id", ""))
			if step == 3: step = 4
			if bool(connected_route.get("open", false)):
				if step == 4: step = 5
			elif step >= 5:
				step = 4
				onboarding.observationStarted = false
				onboarding.observedTargetArrivals = 0
				onboarding.observedTargetServed = 0
				onboarding.lastError = "任务线路已停止运营；重新开通后再观察。"
	if step >= 5:
		var flow := _onboarding_flow()
		if flow.is_empty() or not bool(flow.get("valid", false)) or str(flow.get("routeId", "")) != str(onboarding.get("taskRouteId", "")):
			if step >= 6: step = 4 if not _onboarding_route_for_pair(true).is_empty() else 3
			if bool(onboarding.get("observationStarted", false)):
				onboarding.lastError = "模拟路径当前不再由这条任务线路服务；请检查站点覆盖和开通状态。"
				onboarding.observationStarted = false
		else:
			if step == 5 and bool(onboarding.get("observationStarted", false)) and int(onboarding.get("observedTargetServed", 0)) > 0:
				step = 6
				onboarding.completed = true
				world.simulation.paused = true
				if UiPreferencesScript.save_onboarding_completed(true) != OK:
					_show_toast("引导已完成，但全局完成标记未能保存")
	if step != old_step:
		onboarding.step = step
		if step in [2, 3, 4, 5, 6] and old_step < step: onboarding.lastError = ""
	world["onboarding"] = onboarding
	if step != old_step or str(onboarding.get("lastError", "")) != old_error:
		_sync_onboarding_map()
		_refresh_onboarding_card()
		_refresh_tools()
		if step != old_step:
			_autosave()
			if step == 6: _show_toast("任务需求已在模拟中实际产生服务；结果采用模型估算")
	elif step == 5:
		_refresh_onboarding_card()

func _on_city_change_requested(index: int) -> void:
	var new_id := str(WorldData.cities()[index].get("id", "shanghai"))
	if new_id == active_city_id: return
	world.simulation.paused = true; _autosave()
	active_city_id = new_id
	var mode := str(world.get("mode", "blank"))
	var loaded := SaveManager.load_world(new_id, mode)
	if loaded.ok: _load_world(loaded.world)
	else: _load_world(_prepared_new_world(new_id, mode))

func _on_camera_changed(center: Array, zoom: int) -> void:
	if not world.is_empty():
		world.view = {"center": center.duplicate(), "zoom": zoom}
		if is_instance_valid(save_badge): save_badge.text = "视图未保存"

func _after_planning_change(message: String) -> void:
	if not world.is_empty():
		world.simulation.paused = true
		map_view.set_world(world)
		_autosave()
		_update_topbar()
		_update_tutorial()
		_refresh_ui()
		_show_toast(message)

func _on_history_changed() -> void:
	if is_instance_valid(undo_button): undo_button.tooltip_text = "撤销：%s" % history.undo_label() if not history.undo_label().is_empty() else "撤销 Ctrl+Z"
	if is_instance_valid(redo_button): redo_button.tooltip_text = "重做：%s" % history.redo_label() if not history.redo_label().is_empty() else "重做 Ctrl+Y"

func _update_topbar() -> void:
	if world.is_empty(): return
	var sim: Dictionary = world.simulation
	if is_instance_valid(time_label):
		var minute := int(sim.get("minute", 420)); time_label.text = "第 %d 天 · %02d:%02d" % [minute / 1440 + 1, (minute % 1440) / 60, minute % 60]
	if is_instance_valid(pause_button):
		pause_button.text = "▶" if bool(sim.get("paused", true)) else "Ⅱ"
		var coach_play := not bool(world.get("tutorialDone", false)) and int(world.get("tutorialStep", 0)) == 3
		pause_button.tooltip_text = "教学下一步：播放并观察乘客" if coach_play else "暂停／继续 · 空格"
		pause_button.add_theme_stylebox_override("normal", _style(Color("#236548"), Color("#8cf0c6"), 8, 2) if coach_play else _style(Color("#142e2c"), BORDER, 8, 1))
	if is_instance_valid(speed_picker): speed_picker.select([1,3,10].find(int(sim.get("speed", 1))))
	if is_instance_valid(undo_button): undo_button.disabled = history.undo_label().is_empty()
	if is_instance_valid(redo_button): redo_button.disabled = history.redo_label().is_empty()
	if is_instance_valid(save_badge): save_badge.text = "正在保存…" if save_dirty else "已保存"

func _update_sim_labels() -> void:
	if not is_instance_valid(stats_label) or world.is_empty(): return
	var sim: Dictionary = world.simulation
	var completed := int(sim.get("completed", 0)); var attempted := int(sim.get("attempted", 0))
	if completed <= 0:
		stats_label.text = "需求服务率 —   平均出行 —   已完成 0 趟 · 暂无有效运行数据"
	else:
		var rate := 100.0 * float(sim.get("served", 0)) / maxf(1.0, float(attempted))
		var average := float(sim.get("tripMinutesTotal", 0.0)) / maxf(1.0, float(completed))
		var crowd := 100.0 * float(sim.get("peakCrowding", 0.0))
		stats_label.text = "需求服务率 %.0f%%   平均出行 %.1f 分钟   高峰运能占用 %.0f%%   已完成 %s 趟 · 游戏估算" % [rate, average, crowd, _number(completed)]

func _autosave() -> void:
	if world.is_empty(): return
	save_dirty = true; _update_topbar()
	var result := SaveManager.save_world(world)
	if result.ok:
		var last := FileAccess.open(SaveManager.last_game_path(), FileAccess.WRITE)
		if last: last.store_string(JSON.stringify(world))
		save_dirty = false
		if is_instance_valid(save_badge): save_badge.text = "已保存"
	else:
		save_dirty = true
		if is_instance_valid(save_badge): save_badge.text = "未保存！"
		_show_issue(str(result.get("error", "本地存档失败")))

func _show_save_menu() -> void:
	var popup := PopupMenu.new()
	popup.add_item("立即保存", 1)
	popup.add_item("另存为 JSON…", 2)
	popup.add_item("导入 JSON…", 3)
	popup.add_item("打开存档目录", 4)
	popup.id_pressed.connect(func(id: int):
		match id:
			1: _autosave(); _show_toast("本地存档已写入")
			2: SaveManager.export_world(world)
			3: SaveManager.import_world(func(loaded: Dictionary): _load_world(loaded))
			4: OS.shell_open(SaveManager.saves_root_path())
	)
	add_child(popup); popup.popup(Rect2i(get_viewport().get_mouse_position(), Vector2i(190, 150)))

func _show_load_menu() -> void:
	var popup := PopupMenu.new()
	var choices: Dictionary = {}
	var item_id := 1
	for city in WorldData.cities():
		for mode in ["blank", "expand"]:
			var city_id := str(city.get("id", ""))
			var exists := SaveManager.save_exists(city_id, mode)
			popup.add_item("%s · %s%s" % [city.get("name", "城市"), _mode_name(mode), "" if exists else "（无存档）"], item_id)
			popup.set_item_disabled(popup.item_count - 1, not exists)
			choices[item_id] = [city_id, mode]
			item_id += 1
	popup.id_pressed.connect(func(id: int):
		var choice: Array = choices.get(id, [])
		if choice.is_empty(): return
		var result := SaveManager.load_world(str(choice[0]), str(choice[1]))
		if result.ok: _load_world(result.world)
		else: _show_issue(str(result.get("error", "载入存档失败")))
	)
	if is_instance_valid(menu_layer): menu_layer.add_child(popup)
	else: add_child(popup)
	popup.popup_centered(Vector2i(350, 330))

func _leave_to_menu() -> void:
	world.simulation.paused = true; _autosave()
	for child in get_children():
		if child != map_view and child.get_name() != "Background": child.queue_free()
	world = {}; _show_main_menu()

func _show_issue(text: String) -> void:
	var dialog := AcceptDialog.new(); dialog.title = "规划检查"; dialog.dialog_text = text; add_child(dialog); dialog.confirmed.connect(func(): dialog.queue_free()); dialog.canceled.connect(func(): dialog.queue_free()); dialog.popup_centered()

func _show_toast(text: String) -> void:
	if is_instance_valid(toast_label): toast_label.text = text

func _type_name(kind: String) -> String:
	return {"housing":"居住", "employment":"就业", "education":"教育", "health":"医疗", "hub":"枢纽", "commerce":"商业", "culture":"文化休闲", "service":"生活服务"}.get(kind, "需求")

func _type_color(kind: String) -> Color:
	return {"housing":Color("#e57272"),"employment":Color("#55a4ed"),"education":Color("#b585e8"),"health":Color("#ed8b9b"),"hub":Color("#3dbba7"),"commerce":Color("#edaf57"),"culture":Color("#4abc91"),"service":Color("#edaf57")}.get(kind, MUTED)

func _mode_name(mode: String) -> String:
	return "从零规划" if mode == "blank" else "扩建既有路网"

func _number(value: int) -> String:
	if value >= 10000: return "%.1f万" % (float(value) / 10000.0)
	if value >= 1000: return "%.1f千" % (float(value) / 1000.0)
	return str(value)

func _label(text: String, font_size: int = 13, color: Color = TEXT, bold: bool = false) -> Label:
	var readable_size := maxi(15, font_size)
	var item := Label.new(); item.text = text; item.set_meta("ui_base_font_size", readable_size); item.add_theme_font_size_override("font_size", roundi(float(readable_size) * _ui_scale)); item.add_theme_color_override("font_color", color)
	if bold: item.add_theme_font_override("font", _bold_font)
	if bold: item.add_theme_color_override("font_outline_color", Color(0,0,0,0))
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item

func _menu_label(text: String, font_size: int, color: Color = TEXT, bold: bool = false) -> Label:
	var item := _label(text, font_size, color, bold)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item

func _button(text: String, font_color: Color, background: Color, font_size: int = 13) -> Button:
	var item := Button.new()
	item.text = text
	var readable_size := maxi(16, font_size)
	item.set_meta("ui_base_font_size", readable_size)
	item.add_theme_font_size_override("font_size", roundi(float(readable_size) * _ui_scale))
	item.add_theme_color_override("font_color", font_color)
	item.add_theme_color_override("font_hover_color", Color.WHITE)
	item.add_theme_stylebox_override("normal", _style(background, BORDER, 8, 1))
	item.add_theme_stylebox_override("hover", _style(background.lightened(.1), Color("#42677c"), 8, 1))
	item.add_theme_stylebox_override("pressed", _style(background.darkened(.1), Color("#42677c"), 8, 1))
	item.add_theme_stylebox_override("disabled", _style(background.darkened(.2), BORDER, 8, 1))
	item.add_theme_stylebox_override("focus", _style(background, TEAL, 8, 2))
	item.custom_minimum_size.y = roundi(46.0 * _ui_scale)
	if font_color == TEAL or text in ["检查并开通线路", "检查并开通此线路", "确认站点"]:
		item.add_theme_font_override("font", _bold_font)
	return item

func _set_control_base_font(control: Control, font_size: int) -> void:
	var readable_size := maxi(16, font_size)
	control.set_meta("ui_base_font_size", readable_size)
	control.add_theme_font_size_override("font_size", roundi(float(readable_size) * _ui_scale))

func _style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color = background; box.border_color = border; box.set_border_width_all(border_width); box.set_corner_radius_all(radius); box.content_margin_left = 10; box.content_margin_right = 10; box.content_margin_top = 4; box.content_margin_bottom = 4; return box
