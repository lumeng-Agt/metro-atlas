extends Control

const MapViewScript = preload("res://scripts/map_view.gd")
const UiPreferencesScript = preload("res://scripts/ui_preferences.gd")
const MenuArtScript = preload("res://scripts/menu_art.gd")
const OnboardingScript = preload("res://scripts/onboarding.gd")
const TravelModelScript = preload("res://scripts/travel_model.gd")
const RoutePathScript = preload("res://scripts/route_path.gd")
const JourneyModelScript = preload("res://scripts/journey_model.gd")
const SimulationEngineScript = preload("res://scripts/simulation_engine.gd")
const NeighborhoodGoalsScript = preload("res://scripts/neighborhood_goals.gd")
const BUILD_VERSION := "0.13.5 · 2026.10.16"
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
var interaction_state := InteractionState.new()
var station_construction_draft := ConstructionDraft.new()
var sim_accumulator := 0.0
var save_dirty := false
var save_failed := false
var save_failure_reason := ""
var pending_transition_dialog: ConfirmationDialog
var tutorial_completed := false
var active_saves_page := 0
var city_picker: OptionButton
var speed_picker: OptionButton
var pause_button: Button
var undo_button: Button
var redo_button: Button
var save_badge: Button
var route_list: VBoxContainer
var right_content: VBoxContainer
var left_content: VBoxContainer
var left_tab_buttons: Dictionary = {}
var left_tab := "routes"
var tool_panel: HFlowContainer
var tool_action_panel: HFlowContainer
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
var line_draft_stops: Array[String] = []
var line_draft_path_options: Array = []
var line_draft_path_choices: Array[int] = []
var line_draft_segment_index := -1
var repair_route_id := ""
var repair_direction_id := ""
var repair_segment_index := -1
var repair_from_station_id := ""
var repair_to_station_id := ""
var repair_path_options: Array[Dictionary] = []
var repair_path_choice := 0
var repair_plan_revision := -1
var endpoint_choice_candidates: Array[Dictionary] = []
var station_vehicle_id := "B-6"
var confirming_track_preview := false
var _flow_cache_revision := -1
var _flow_cache: Array[Dictionary] = []
var _ui_scale := 1.0
var _theme: Theme
var _base_font: Font
var _bold_font: Font
var _left_panel: Control
var _right_panel: Control
var _right_pinned_header: VBoxContainer
var _right_pinned_footer: VBoxContainer
var _footer_panel: Control
var _top_panel: Control
var attribution_label: Button
var _attribution_panel: PanelContainer
var _left_panel_button: Button
var _right_panel_button: Button
var _layer_panel: PanelContainer
var _top_content: VBoxContainer
var _top_primary_row: HBoxContainer
var _top_actions: HBoxContainer
var _top_spacer: Control
var _mode_badge: Label
var _left_requested := true
var _right_requested := true
var _layout_narrow := false
var onboarding_panel: PanelContainer
var _more_tools_expanded := false
var _onboarding_reason_expanded := false
var _station_preview_last_usec := 0
var _curve_preview_last_usec := 0

func _ready() -> void:
	WorldData.load_assets()
	name = "MetroAtlasDesktop"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderingServer.set_default_clear_color(APP_BG)
	_build_application()
	interaction_state.set_tool(current_tool)
	_show_main_menu()

func _process(delta: float) -> void:
	if world.is_empty(): return
	var sim: Dictionary = world.get("simulation", {})
	var simulation_advanced := false
	if not bool(sim.get("paused", true)):
		sim_accumulator += delta * float(sim.get("speed", 1))
		while sim_accumulator >= 1.0:
			sim_accumulator -= 1.0
			_simulate_one_minute()
			simulation_advanced = true
			map_view.requested_train_redraw()
			if int(sim.get("elapsedMinutes", sim.get("minute", 420))) % 15 == 0:
				_autosave()
				map_view.requested_redraw()
			if bool(world.simulation.get("paused", true)):
				sim_accumulator = 0.0
				break
	map_view.simulation_fraction = sim_accumulator if not bool(world.simulation.get("paused", true)) else 0.0
	if simulation_advanced:
		_update_sim_labels()
		if left_tab == "stats": _refresh_left_panel()
	if not bool(world.simulation.get("paused", true)): map_view.requested_train_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if world.is_empty():
			get_tree().quit()
		else:
			_request_world_transition(func(): get_tree().quit())
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
	elif event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] and current_tool in ["track", "track_curve", "station"]:
		_adjust_track_depth(5.0 if event.keycode == KEY_PAGEUP else -5.0)
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
	map_view.curve_control_previewed.connect(_on_curve_control_previewed)
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

func _apply_ui_scale(value: float, reopen_settings: bool = false) -> void:
	_ui_scale = value if UiPreferencesScript.SCALE_OPTIONS.has(value) else 1.0
	if is_instance_valid(_theme): _theme.default_font_size = roundi(18.0 * _ui_scale)
	if is_instance_valid(map_view): map_view.ui_scale = _ui_scale
	_apply_ui_font_scale_to_node(self)
	if is_instance_valid(menu_layer):
		call_deferred("_show_main_menu")
		# Rebuilding the main menu updates its layout metrics; reopen the dialog
		# afterward so changing scale does not unexpectedly return to the menu.
		if reopen_settings: call_deferred("_show_settings")
	else: _update_responsive_layout()

func _apply_ui_font_scale_to_node(node: Node) -> void:
	if node is Control:
		if node.has_meta("ui_base_font_size"):
			var base_size := int(node.get_meta("ui_base_font_size"))
			node.add_theme_font_size_override("font_size", roundi(float(base_size) * _ui_scale))
	for child in node.get_children():
		_apply_ui_font_scale_to_node(child)

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
	var layout_scale := minf(_ui_scale, 1.25)
	var top_height := roundi((104.0 if use_two_top_rows else 76.0) * layout_scale)
	var footer_height := _calculate_footer_height(top_height, layout_scale)
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
	if is_instance_valid(_footer_panel):
		var footer_width := minf(1120.0 * layout_scale, get_viewport_rect().size.x - 24.0)
		_footer_panel.offset_left = -footer_width * 0.5
		_footer_panel.offset_right = footer_width * 0.5
		_footer_panel.offset_top = -footer_height - 10.0
		_footer_panel.offset_bottom = -10.0
	if is_instance_valid(left_content): left_content.custom_minimum_size.x = 300.0 * _ui_scale
	if is_instance_valid(right_content): right_content.custom_minimum_size.x = 330.0 * _ui_scale
	if is_instance_valid(_left_panel_button): _left_panel_button.text = "线路 ▾" if _left_panel.visible else "线路 ▸"
	if is_instance_valid(_right_panel_button): _right_panel_button.text = "详情 ▾" if _right_panel.visible else "详情 ▸"
	if is_instance_valid(_mode_badge): _mode_badge.visible = not _layout_narrow
	if is_instance_valid(_layer_panel):
		var layer_width := minf(430.0 * _ui_scale, maxf(220.0, get_viewport_rect().size.x - 24.0))
		var right_drawer_cover := 350.0 * _ui_scale if _layout_narrow and _right_panel.visible else 0.0
		_layer_panel.offset_left = -layer_width - right_drawer_cover
		_layer_panel.offset_right = -12.0 - right_drawer_cover
		_layer_panel.custom_minimum_size.x = layer_width
	if is_instance_valid(_attribution_panel):
		var map_origin_x := map_view.position.x
		var left_drawer_cover := 330.0 * _ui_scale if _layout_narrow and _left_panel.visible else 0.0
		var attribution_width := minf(250.0 * minf(_ui_scale, 1.25), maxf(120.0, map_view.size.x - left_drawer_cover - 24.0))
		_attribution_panel.offset_left = map_origin_x + left_drawer_cover + 12.0
		_attribution_panel.offset_right = map_origin_x + left_drawer_cover + 12.0 + attribution_width
		_attribution_panel.offset_top = -footer_height - roundi(48.0 * minf(_ui_scale, 1.25))
		_attribution_panel.offset_bottom = -footer_height - roundi(14.0 * minf(_ui_scale, 1.25))
	if is_instance_valid(attribution_label): attribution_label.add_theme_font_size_override("font_size", roundi(12.0 * _ui_scale))

func _short_basemap_date(raw_date: String) -> String:
	var iso := RegEx.new()
	iso.compile("(\\d{4}-\\d{2}-\\d{2})")
	var iso_match := iso.search(raw_date)
	if iso_match != null: return iso_match.get_string(1)
	var rfc := RegEx.new()
	rfc.compile("\\b(\\d{2}) ([A-Z][a-z]{2}) (\\d{4})\\b")
	var match_result := rfc.search(raw_date)
	if match_result == null: return raw_date.left(10)
	var months := {"Jan": "01", "Feb": "02", "Mar": "03", "Apr": "04", "May": "05", "Jun": "06", "Jul": "07", "Aug": "08", "Sep": "09", "Oct": "10", "Nov": "11", "Dec": "12"}
	return "%s-%s-%s" % [match_result.get_string(3), str(months.get(match_result.get_string(2), "01")), match_result.get_string(1)]

func _show_map_attribution_details() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "地图数据来源"
	dialog.dialog_text = "地图数据 © OpenStreetMap contributors\n许可：Open Database License（ODbL）\n本地快照：%s\n地图几何仅用于显示；不代表已取得步行道路、过街或建筑施工校核数据。" % map_view.base_map_snapshot
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(560, 260))

func _calculate_footer_height(top_height: int, layout_scale: float) -> int:
	var viewport_height := int(get_viewport_rect().size.y)
	var reserve_map := 360.0 * minf(_ui_scale, 1.25)
	var maximum := maxi(112, int(floor(float(viewport_height - top_height) - reserve_map)))
	var panel_rows := 1
	if is_instance_valid(tool_panel):
		var footer_width := minf(1120.0 * layout_scale, get_viewport_rect().size.x - 24.0)
		var available_width := maxf(240.0, footer_width - 32.0 * layout_scale)
		var row_width := 0.0
		panel_rows = 1
		for child in tool_panel.get_children():
			if not is_instance_valid(child) or not child.visible: continue
			var child_width := maxf(child.custom_minimum_size.x, child.get_combined_minimum_size().x)
			if row_width > 0.0 and row_width + child_width + 7.0 > available_width:
				panel_rows += 1
				row_width = child_width
			else:
				row_width += child_width + 7.0
	var action_rows := 0
	if is_instance_valid(tool_action_panel) and tool_action_panel.visible:
		var action_width := 0.0
		action_rows = 1
		for child in tool_action_panel.get_children():
			if not is_instance_valid(child) or not child.visible: continue
			var child_width := maxf(child.custom_minimum_size.x, child.get_combined_minimum_size().x)
			var footer_width := minf(1120.0 * layout_scale, get_viewport_rect().size.x - 24.0)
			if action_width > 0.0 and action_width + child_width + 7.0 > maxf(240.0, footer_width - 32.0 * layout_scale):
				action_rows += 1
				action_width = child_width
			else:
				action_width += child_width + 7.0
	var control_height := 48.0 * layout_scale
	var instruction_height := 34.0 * layout_scale
	var stats_height := 26.0 * layout_scale
	var desired := 18.0 * layout_scale + panel_rows * (control_height + 5.0) + action_rows * (control_height + 5.0) + instruction_height + stats_height
	return clampi(roundi(desired), mini(112, maximum), maximum)

func _show_main_menu() -> void:
	_render_planning_menu(false)

func _show_new_city_menu() -> void:
	_render_planning_menu(true)

func _render_planning_menu(new_city: bool) -> void:
	map_view.visible = false
	if is_instance_valid(menu_layer): menu_layer.queue_free()
	menu_layer = Control.new()
	menu_layer.name = "MainMenu"
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu_layer)
	var backdrop := ColorRect.new()
	backdrop.name = "Background"
	backdrop.color = Color("#dce5e5")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(backdrop)
	var card := PanelContainer.new()
	card.name = "MenuCard"
	card.anchor_left = 0.5; card.anchor_right = 0.5
	card.anchor_top = 0.5; card.anchor_bottom = 0.5
	var viewport_size := get_viewport_rect().size
	var card_width := minf(1080.0, viewport_size.x - 40.0)
	var card_height := minf(760.0, viewport_size.y - 36.0)
	card.offset_left = -card_width * 0.5; card.offset_right = card_width * 0.5
	card.offset_top = -card_height * 0.5; card.offset_bottom = card_height * 0.5
	var panel_style := _style(Color("#162632"), Color("#f5fbfb"), 22, 1)
	panel_style.shadow_color = Color(0.02, 0.09, 0.13, 0.26)
	panel_style.shadow_size = 24
	panel_style.shadow_offset = Vector2(0, 10)
	panel_style.content_margin_left = 24; panel_style.content_margin_right = 24
	panel_style.content_margin_top = 22; panel_style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", panel_style)
	menu_layer.add_child(card)
	var body_scroll := ScrollContainer.new()
	body_scroll.name = "MenuBodyScroll"
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(body_scroll)
	var wide := viewport_size.x >= 900.0
	var body: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	body.name = "MenuContent"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 26)
	body_scroll.add_child(body)
	var intro := VBoxContainer.new()
	intro.name = "MenuIntroduction"
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	intro.add_theme_constant_override("separation", 14)
	intro.custom_minimum_size.x = 360.0 if wide else 0.0
	body.add_child(intro)
	intro.add_child(_menu_label("METRO ATLAS  /  DESKTOP %s" % BUILD_VERSION, 14, TEAL, true))
	var title := _menu_label("造一座地铁", 48, TEXT, true)
	title.custom_minimum_size.y = 70
	intro.add_child(title)
	intro.add_child(_menu_label("从真实街区出发，连接人们每天要去的地方。", 18, Color("#b9c8d0")))
	var illustration_panel := PanelContainer.new()
	illustration_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	illustration_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	illustration_panel.custom_minimum_size.y = 250 if wide else 170
	illustration_panel.add_theme_stylebox_override("panel", _style(Color("#e5ecea"), Color("#45606b"), 14, 1))
	intro.add_child(illustration_panel)
	var illustration := MenuArtScript.new()
	illustration.name = "MetroNetworkIllustration"
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	illustration_panel.add_child(illustration)
	intro.add_child(_menu_label("需求 → 车站 → 轨道 → 运营", 16, Color("#e0ebed"), true))
	var actions := VBoxContainer.new()
	actions.name = "MenuActions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 10)
	actions.custom_minimum_size.x = 300.0 if wide else 0.0
	body.add_child(actions)
	if new_city:
		actions.add_child(_menu_label("开始一座新城市", 24, TEXT, true))
		actions.add_child(_menu_label("先选城市，再决定从空白地图起步或扩建既有路网。", 15, MUTED))
		menu_city_picker = OptionButton.new()
		menu_city_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu_city_picker.custom_minimum_size.y = 48
		_set_control_base_font(menu_city_picker, 16)
		for city in WorldData.cities(): menu_city_picker.add_item(str(city.get("name", "城市")))
		for index in range(WorldData.cities().size()):
			if str(WorldData.cities()[index].get("id", "")) == active_city_id: menu_city_picker.select(index); break
		menu_city_picker.item_selected.connect(func(index: int): active_city_id = str(WorldData.cities()[index].get("id", "shanghai")))
		actions.add_child(menu_city_picker)
		var blank := _button("从零规划", Color("#103b35"), Color("#74e0bd"), 19)
		blank.custom_minimum_size.y = 56
		blank.pressed.connect(func(): _start_new_game(active_city_id, "blank"))
		actions.add_child(blank)
		var expand := _button("扩建现实路网", Color("#123650"), Color("#a9d8fa"), 18)
		expand.custom_minimum_size.y = 54
		expand.pressed.connect(func(): _start_new_game(active_city_id, "expand"))
		actions.add_child(expand)
		var back := _button("返回主菜单", TEXT, PANEL_LIGHT, 16)
		back.pressed.connect(_show_main_menu)
		actions.add_child(back)
	else:
		actions.add_child(_menu_label("规划工作台", 20, TEAL, true))
		menu_continue_button = _button("继续上次游戏   →", Color("#103b35"), Color("#74e0bd"), 19)
		menu_continue_button.custom_minimum_size.y = 58
		menu_continue_button.disabled = true
		menu_continue_button.pressed.connect(_continue_last_game)
		actions.add_child(menu_continue_button)
		var new_button := _button("新建城市规划", Color("#e5edf0"), Color("#274657"), 18)
		new_button.custom_minimum_size.y = 54
		new_button.pressed.connect(_show_new_city_menu)
		actions.add_child(new_button)
		var saves_button := _button("本地存档", TEXT, PANEL_LIGHT, 16)
		saves_button.custom_minimum_size.y = 48
		saves_button.pressed.connect(_show_load_menu)
		actions.add_child(saves_button)
		var secondary := HBoxContainer.new()
		secondary.add_theme_constant_override("separation", 8)
		var settings := _button("设置", MUTED, PANEL_LIGHT, 16)
		settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		settings.pressed.connect(_show_settings)
		secondary.add_child(settings)
		var quit := _button("退出", MUTED, PANEL_LIGHT, 16)
		quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quit.pressed.connect(func(): get_tree().quit())
		secondary.add_child(quit)
		actions.add_child(secondary)
		actions.add_child(_menu_label("五座城市 · 本地存档 · 随时撤销", 14, MUTED))
	_update_continue_button()

func _show_main_menu_legacy() -> void:
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
	var wide_layout := viewport_size.x / maxf(1.0, _ui_scale) >= 1440.0
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
	var eyebrow := _menu_label("METRO ATLAS     •     DESKTOP %s" % BUILD_VERSION, 14, TEAL, true)
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
	for index in range(WorldData.cities().size()):
		if str(WorldData.cities()[index].get("id", "")) == active_city_id:
			menu_city_picker.select(index)
			break
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
	import_button.pressed.connect(func(): SaveManager.import_world(func(loaded: Dictionary): _load_world(loaded), func(error: String): _show_issue(error)))
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
	var content_scroll := ScrollContainer.new()
	content_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_scroll.offset_left = roundi(18.0 * _ui_scale)
	content_scroll.offset_top = roundi(42.0 * _ui_scale)
	content_scroll.offset_right = -roundi(18.0 * _ui_scale)
	content_scroll.offset_bottom = -roundi(54.0 * _ui_scale)
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var viewport_size := get_viewport_rect().size
	content_scroll.custom_minimum_size = Vector2(
		minf(440.0 * _ui_scale, maxf(240.0, viewport_size.x - 96.0)),
		minf(220.0 * _ui_scale, maxf(160.0, viewport_size.y - 96.0))
	)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	var settings_title := _label("界面文字大小", 18, TEXT, true)
	settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(settings_title)
	var settings_intro := _label("地图镜头缩放与界面缩放分开保存。", 14, MUTED)
	settings_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(settings_intro)
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
		_apply_ui_scale(value, true)
	)
	var settings_info := _label("地图：随游戏附带五城 OSM 矢量底图，断网也能规划。\n模拟速度使用固定游戏时间步长。", 14, MUTED)
	settings_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(settings_info)
	content_scroll.add_child(content)
	dialog.add_child(content_scroll)
	menu_layer.add_child(dialog)
	dialog.popup_centered(Vector2i(mini(roundi(520.0 * _ui_scale), int(viewport_size.x - 32.0)), mini(roundi(360.0 * _ui_scale), int(viewport_size.y - 32.0))))

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
	var indexed := SaveManager.load_last_game(true)
	if not bool(indexed.get("ok", false)):
		_show_issue(str(indexed.get("error", "无法读取继续游戏存档")), "载入失败")
		return
	if bool(indexed.get("pendingRecoveryConfirmation", false)):
		_confirm_recovery_before_load(indexed, Callable(self, "_continue_from_index"))
	else:
		_continue_from_index(indexed)

func _continue_from_index(indexed: Dictionary) -> void:
	var index_world: Dictionary = indexed.get("world", {})
	var city_id := str(index_world.get("cityId", "shanghai"))
	var mode := str(index_world.get("mode", "blank"))
	var loaded: Dictionary = {}
	if SaveManager.save_exists(city_id, mode):
		loaded = SaveManager.load_world(city_id, mode, true)
		if not bool(loaded.get("ok", false)):
			_show_issue(str(loaded.get("error", "城市存档载入失败；原文件已保留。")), "载入失败")
			return
	else:
		loaded = indexed
	if bool(loaded.get("pendingRecoveryConfirmation", false)):
		_confirm_recovery_before_load(loaded, func(confirmed: Dictionary): _finish_continue_load(confirmed, indexed))
		return
	_finish_continue_load(loaded, indexed)

func _finish_continue_load(loaded: Dictionary, indexed: Dictionary) -> void:
	var index_world: Dictionary = indexed.get("world", {})
	_load_world(loaded.get("world", index_world))
	if bool(indexed.get("recovered", false)) or bool(loaded.get("recovered", false)):
		_show_toast(str(loaded.get("error", indexed.get("notice", "已从最近备份恢复；原文件仍保留。"))))

func _confirm_recovery_before_load(result: Dictionary, continue_action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认从备份恢复"
	dialog.dialog_text = "发现可用恢复备份：\n%s\n\n原因：%s\n\n确认后会先保存一份独立恢复副本，再载入这份备份。取消不会更改当前进度或存档文件。" % [SaveManager.recovery_source_label(result), str(result.get("recoveryCause", "当前存档无法读取"))]
	dialog.get_ok_button().text = "保留副本并恢复"
	dialog.get_cancel_button().text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var confirmed := SaveManager.confirm_backup_recovery(result)
		dialog.queue_free()
		if not bool(confirmed.get("ok", false)):
			_show_issue(str(confirmed.get("error", "备份恢复失败；当前游戏仍保留")), "恢复失败")
			return
		if continue_action.is_valid(): continue_action.call(confirmed)
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(620, 330))

func _update_continue_button() -> void:
	var path := SaveManager.last_game_path()
	var exists := FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")
	if is_instance_valid(menu_continue_button): menu_continue_button.disabled = not exists

func _load_world(state: Dictionary) -> void:
	SimulationEngineScript.invalidate_route_cache()
	world = state
	if not world.has("onboarding"):
		# Existing version-8 saves should not unexpectedly start a new lesson.
		world["onboarding"] = OnboardingScript.create_state(str(world.get("cityId", "shanghai")), str(world.get("mode", "blank")), true)
		world["tutorialDone"] = true
	_flow_cache_revision = -1
	active_city_id = str(world.get("cityId", "shanghai"))
	if not world.has("simulation"): world.simulation = {"minute": 420, "elapsedMinutes": 420, "elapsedSeconds": 25200, "nextDepartureSeconds": {}, "trainTripsInitialized": false, "speed": 1, "paused": true, "seed": 45281, "completed": 0, "attempted": 0, "served": 0, "boarded": 0, "departed": 0, "waiting": 0, "inTransit": 0, "abandoned": 0, "unreachable": 0, "interrupted": 0, "tripMinutesTotal": 0.0, "flowRemainders": {}, "passengerBatches": [], "capacityLoads": {}, "capacitySlot": -1, "trainTrips": [], "flowSamples": {}}
	if not world.simulation.has("elapsedMinutes"): world.simulation.elapsedMinutes = int(world.simulation.get("minute", 420))
	for key in ["boarded", "departed", "waiting", "inTransit", "abandoned", "unreachable", "interrupted"]:
		if not world.simulation.has(key): world.simulation[key] = 0
	if not world.simulation.has("passengerBatches"): world.simulation.passengerBatches = []
	if not world.simulation.has("trainTrips"): world.simulation.trainTrips = []
	if not world.simulation.has("flowSamples"): world.simulation.flowSamples = {}
	if not world.has("goalBoard"): world["goalBoard"] = {"active": [], "completed": []}
	world.simulation.paused = true
	active_route_id = str(world.get("selectedRoute", world.get("activeRouteId", world.get("routes", [{}])[0].get("id", "")))) if not world.get("routes", []).is_empty() else ""
	if WorldData.find_route(world, active_route_id).is_empty() and not world.get("routes", []).is_empty(): active_route_id = str(world.routes[0].get("id", ""))
	selected_type = ""; selected_id = ""; current_tool = "select"
	interaction_state.set_tool("select")
	interaction_state.clear_selection()
	station_construction_draft.clear()
	_more_tools_expanded = false
	_left_requested = not bool(world.get("onboarding", {}).get("active", false))
	_right_requested = not bool(world.get("onboarding", {}).get("active", false))
	history.attach(world)
	if history.changed.is_connected(_on_history_changed): history.changed.disconnect(_on_history_changed)
	history.changed.connect(_on_history_changed)
	map_view.set_context(WorldData.city(active_city_id), world)
	map_view.show_road_names = UiPreferencesScript.load_road_names()
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
	for overlay in [_layer_panel, onboarding_panel]:
		if is_instance_valid(overlay) and overlay.get_parent() == map_view:
			map_view.remove_child(overlay)
			overlay.free()
	_layer_panel = null
	onboarding_panel = null
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
	_left_panel_button.pressed.connect(func():
		_left_requested = not _left_requested
		if _layout_narrow and _left_requested: _right_requested = false
		_update_responsive_layout()
	)
	top_row.add_child(_left_panel_button)
	city_picker = OptionButton.new(); city_picker.custom_minimum_size = Vector2(120, 38)
	_set_control_base_font(city_picker, 15)
	for item in WorldData.cities(): city_picker.add_item(str(item.name))
	for i in range(WorldData.cities().size()):
		if WorldData.cities()[i].id == active_city_id: city_picker.select(i)
	city_picker.item_selected.connect(_on_city_change_requested)
	top_row.add_child(city_picker)
	_right_panel_button = _button("详情 ▾", MUTED, PANEL_LIGHT, 14)
	_right_panel_button.pressed.connect(func():
		_right_requested = not _right_requested
		if _layout_narrow and _right_requested: _left_requested = false
		_update_responsive_layout()
	)
	top_row.add_child(_right_panel_button)
	_mode_badge = _label(_mode_name(str(world.get("mode", "blank"))), 12, MUTED); _mode_badge.custom_minimum_size.x = 82; top_row.add_child(_mode_badge)
	_top_spacer = Control.new(); _top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top_row.add_child(_top_spacer)
	time_label = _label("D1 · 07:00", 14, TEXT, true); time_label.custom_minimum_size.x = 92; _top_actions.add_child(time_label)
	pause_button = _button("▶", TEAL, Color("#142e2c"), 18); pause_button.custom_minimum_size = Vector2(42, 40); pause_button.pressed.connect(_toggle_pause); _top_actions.add_child(pause_button)
	speed_picker = OptionButton.new(); speed_picker.custom_minimum_size = Vector2(82, 38)
	for speed in [1,3,10]: speed_picker.add_item("%d×" % speed)
	speed_picker.item_selected.connect(func(index: int): world.simulation.speed = [1,3,10][index]; _autosave())
	_top_actions.add_child(speed_picker)
	undo_button = _button("↶", TEXT, PANEL_LIGHT, 20); undo_button.tooltip_text = "撤销 Ctrl+Z"; undo_button.pressed.connect(_do_undo); _top_actions.add_child(undo_button)
	redo_button = _button("↷", TEXT, PANEL_LIGHT, 20); redo_button.tooltip_text = "重做 Ctrl+Y"; redo_button.pressed.connect(_do_redo); _top_actions.add_child(redo_button)
	var saves := _button("存档 ▾", MUTED, PANEL_LIGHT, 13); saves.pressed.connect(_show_save_menu); _top_actions.add_child(saves)
	save_badge = _button("已保存", TEAL, Color("#142e2c"), 13)
	save_badge.custom_minimum_size = Vector2(96, 38)
	save_badge.pressed.connect(_retry_or_save)
	_top_actions.add_child(save_badge)
	var menu_button := _button("菜单", MUTED, PANEL_LIGHT, 13); menu_button.pressed.connect(_leave_to_menu); _top_actions.add_child(menu_button)

	var left := PanelContainer.new()
	left.anchor_left = 0; left.anchor_right = 0; left.anchor_top = 0; left.anchor_bottom = 1
	left.offset_top = 68; left.offset_bottom = -35; left.offset_left = 0; left.offset_right = 280
	left.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 0, 0)); add_child(left)
	_left_panel = left
	var left_body := VBoxContainer.new(); left_body.add_theme_constant_override("separation", 4); left_body.add_theme_constant_override("margin_left", 8); left_body.add_theme_constant_override("margin_right", 8); left_body.add_theme_constant_override("margin_top", 8); left_body.add_theme_constant_override("margin_bottom", 8); left.add_child(left_body)
	var left_tabs := HBoxContainer.new(); left_tabs.add_theme_constant_override("separation", 5); left_body.add_child(left_tabs)
	for tab_data in [["routes", "线路"], ["tasks", "任务"], ["stats", "统计"]]:
		var tab_button := _button(str(tab_data[1]), TEXT, PANEL_LIGHT, 14)
		tab_button.custom_minimum_size.y = 40.0 * _ui_scale
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.pressed.connect(_on_left_tab_pressed.bind(str(tab_data[0])))
		left_tabs.add_child(tab_button)
		left_tab_buttons[str(tab_data[0])] = tab_button
	var left_scroll := ScrollContainer.new(); left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; left_body.add_child(left_scroll)
	left_content = VBoxContainer.new(); left_content.custom_minimum_size.x = 250; left_content.add_theme_constant_override("separation", 8); left_content.add_theme_constant_override("margin_left", 6); left_content.add_theme_constant_override("margin_right", 6); left_content.add_theme_constant_override("margin_top", 10); left_content.add_theme_constant_override("margin_bottom", 12); left_scroll.add_child(left_content)

	var right := PanelContainer.new()
	right.anchor_left = 1; right.anchor_right = 1; right.anchor_top = 0; right.anchor_bottom = 1
	right.offset_top = 68; right.offset_bottom = -35; right.offset_left = -310; right.offset_right = 0
	right.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 0, 0)); add_child(right)
	_right_panel = right
	var right_body := VBoxContainer.new()
	right_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_body.add_theme_constant_override("separation", 4)
	right.add_child(right_body)
	_right_pinned_header = VBoxContainer.new()
	_right_pinned_header.add_theme_constant_override("separation", 7)
	_right_pinned_header.add_theme_constant_override("margin_left", 14)
	_right_pinned_header.add_theme_constant_override("margin_right", 14)
	_right_pinned_header.add_theme_constant_override("margin_top", 14)
	_right_pinned_header.add_theme_constant_override("margin_bottom", 8)
	right_body.add_child(_right_pinned_header)
	var right_scroll := ScrollContainer.new(); right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right_body.add_child(right_scroll)
	right_content = VBoxContainer.new(); right_content.custom_minimum_size.x = 280; right_content.add_theme_constant_override("separation", 9); right_content.add_theme_constant_override("margin_left", 14); right_content.add_theme_constant_override("margin_right", 14); right_content.add_theme_constant_override("margin_top", 14); right_content.add_theme_constant_override("margin_bottom", 14); right_scroll.add_child(right_content)
	_right_pinned_footer = VBoxContainer.new()
	_right_pinned_footer.add_theme_constant_override("margin_left", 14)
	_right_pinned_footer.add_theme_constant_override("margin_right", 14)
	_right_pinned_footer.add_theme_constant_override("margin_top", 8)
	_right_pinned_footer.add_theme_constant_override("margin_bottom", 14)
	right_body.add_child(_right_pinned_footer)

	var footer := PanelContainer.new()
	footer.anchor_left = 0.5; footer.anchor_right = 0.5; footer.anchor_top = 1; footer.anchor_bottom = 1
	footer.offset_left = -560; footer.offset_right = 560; footer.offset_top = -158; footer.offset_bottom = -12
	var footer_style := _style(Color("#172833"), Color("#46616d"), 16, 1)
	footer_style.shadow_color = Color(0.02, 0.08, 0.12, 0.24); footer_style.shadow_size = 12; footer_style.shadow_offset = Vector2(0, 4)
	footer.add_theme_stylebox_override("panel", footer_style); add_child(footer)
	_footer_panel = footer
	var footer_body := VBoxContainer.new(); footer_body.add_theme_constant_override("separation", 4); footer_body.add_theme_constant_override("margin_left", 10); footer_body.add_theme_constant_override("margin_right", 10); footer_body.add_theme_constant_override("margin_top", 6); footer_body.add_theme_constant_override("margin_bottom", 5); footer.add_child(footer_body)
	tool_panel = HFlowContainer.new(); tool_panel.add_theme_constant_override("h_separation", 7); tool_panel.add_theme_constant_override("v_separation", 5); footer_body.add_child(tool_panel)
	tool_action_panel = HFlowContainer.new(); tool_action_panel.add_theme_constant_override("h_separation", 7); tool_action_panel.add_theme_constant_override("v_separation", 5); footer_body.add_child(tool_action_panel)
	tool_instruction_label = _label("", 14, TEAL)
	tool_instruction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_instruction_label.custom_minimum_size.y = 20.0 * minf(_ui_scale, 1.25)
	footer_body.add_child(tool_instruction_label)
	var footer_row := HFlowContainer.new(); footer_row.add_theme_constant_override("h_separation", 12); footer_row.add_theme_constant_override("v_separation", 4); footer_body.add_child(footer_row)
	stats_label = _label("等候 0  ·  在途 0  ·  已完成 0", 15, MUTED); stats_label.custom_minimum_size.x = 430.0 * _ui_scale; footer_row.add_child(stats_label)
	toast_label = _label("", 14, TEXT); toast_label.custom_minimum_size.x = 300.0 * _ui_scale; footer_row.add_child(toast_label)
	_layer_panel = PanelContainer.new()
	_layer_panel.name = "MapLayerControls"
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
	var roads_toggle := CheckButton.new()
	roads_toggle.text = "路名"
	roads_toggle.button_pressed = map_view.show_road_names
	_set_control_base_font(roads_toggle, 14)
	roads_toggle.tooltip_text = "显示或隐藏简洁底图上的道路名称"
	roads_toggle.toggled.connect(func(on: bool):
		map_view.show_road_names = on
		if UiPreferencesScript.save_road_names(on) != OK: _show_toast("路名设置未能保存")
		map_view.requested_redraw()
	)
	layers.add_child(roads_toggle)
	map_view.add_child(_layer_panel)
	onboarding_panel = PanelContainer.new()
	onboarding_panel.name = "NeighborhoodGuide"
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
	_attribution_panel.add_theme_stylebox_override("panel", _style(Color("#f4f7f4"), Color("#aab7b8"), 7, 1))
	attribution_label = Button.new()
	attribution_label.text = "© OpenStreetMap · %s" % _short_basemap_date(map_view.base_map_snapshot)
	attribution_label.flat = true
	attribution_label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	attribution_label.add_theme_color_override("font_color", Color("#354956"))
	attribution_label.add_theme_color_override("font_hover_color", Color("#153b56"))
	attribution_label.add_theme_font_size_override("font_size", 12)
	attribution_label.pressed.connect(_show_map_attribution_details)
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
	if not is_instance_valid(left_content): return
	for child in left_content.get_children(): child.queue_free()
	if _flow_cache_revision != int(world.get("revision", 0)): _rebuild_flow_cache()
	var elapsed := int(world.get("simulation", {}).get("elapsedMinutes", world.get("simulation", {}).get("minute", 420)))
	NeighborhoodGoalsScript.update(world, _flow_cache, elapsed)
	for tab_id in left_tab_buttons:
		var button: Button = left_tab_buttons[tab_id]
		var active := str(tab_id) == left_tab
		button.add_theme_stylebox_override("normal", _style(Color("#174037") if active else PANEL_LIGHT, Color("#3b967f") if active else BORDER, 8, 1))
		button.add_theme_color_override("font_color", TEAL if active else TEXT)
	match left_tab:
		"tasks": _refresh_tasks_tab()
		"stats": _refresh_stats_tab()
		_: _refresh_routes_tab()

func _on_left_tab_pressed(tab_id: String) -> void:
	left_tab = tab_id
	_refresh_left_panel()

func _refresh_routes_tab() -> void:
	left_content.add_child(_label("线路与车站", 20, TEXT, true))
	var active_route := WorldData.find_route(world, active_route_id)
	left_content.add_child(_label("当前线路 · %s" % str(active_route.get("name", "未选线路")), 15, MUTED))
	var add_route := _button("＋ 创建运营线路", TEAL, Color("#15362f"), 16)
	add_route.custom_minimum_size.y = 44.0 * _ui_scale
	add_route.pressed.connect(func(): _set_tool("line"))
	left_content.add_child(add_route)
	route_list = VBoxContainer.new()
	route_list.add_theme_constant_override("separation", 6)
	left_content.add_child(route_list)
	for route in world.get("routes", []):
		var row := HBoxContainer.new()
		var color := Color.from_string(str(route.get("color", "#4a91e8")), Color("#4a91e8"))
		var route_button := _button("●  %s" % route.get("name", "线路"), TEXT, PANEL_LIGHT, 15)
		route_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		route_button.add_theme_color_override("font_color", color)
		route_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		route_button.custom_minimum_size.y = 42.0 * _ui_scale
		route_button.pressed.connect(func(): active_route_id = str(route.get("id", "")); _select_object("route", active_route_id))
		row.add_child(route_button)
		row.add_child(_label("%d站" % route.get("stationOrder", []).size(), 13, MUTED))
		route_list.add_child(row)
	left_content.add_child(_label("线路停站顺序", 16, TEXT, true))
	if active_route.is_empty():
		left_content.add_child(_label("先放车站，再铺设独立轨道，最后安排运营线路。", 14, MUTED))
	else:
		var order: Array = active_route.get("stationOrder", [])
		if order.is_empty(): left_content.add_child(_label("运营线路还没有停站。", 14, MUTED))
		for index in range(order.size()):
			var station := WorldData.find_station(world, str(order[index]))
			if station.is_empty(): continue
			var station_button := _button("%02d  %s" % [index + 1, station.get("name", "车站")], TEXT, PANEL_LIGHT, 14)
			station_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			station_button.custom_minimum_size.y = 40.0 * _ui_scale
			station_button.pressed.connect(func(): _select_object("station", str(station.get("id", ""))); map_view.center_on(station.get("latlng", [0, 0]), maxi(map_view.current_zoom, 14)))
			left_content.add_child(station_button)
	left_content.add_child(HSeparator.new())
	left_content.add_child(_label("城市出行需求", 17, TEXT, true))
	left_content.add_child(_label("点选地点可查看方向与当前接入情况。", 14, MUTED))
	for demand in WorldData.city(active_city_id).get("demand", []):
		var demand_button := _button("●  %s · %s" % [demand.get("name", "需求点"), _type_name(str(demand.get("type", "")))], TEXT, Color("#1b2934"), 14)
		demand_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		demand_button.custom_minimum_size.y = 40.0 * _ui_scale
		demand_button.add_theme_color_override("font_color", _type_color(str(demand.get("type", ""))))
		demand_button.pressed.connect(func(): _select_object("demand", str(demand.get("id", ""))); map_view.center_on(demand.get("latlng", [0, 0]), maxi(map_view.current_zoom, 14)))
		left_content.add_child(demand_button)
	var source := str(world.get("source", {}).get("snapshot", ""))
	left_content.add_child(_label("OSM 快照 %s · 客流为游戏设定。" % source.left(10), 12, MUTED))

func _refresh_tasks_tab() -> void:
	left_content.add_child(_label("任务与扩建", 20, TEXT, true))
	var onboarding: Dictionary = world.get("onboarding", {})
	var tutorial_card := PanelContainer.new()
	tutorial_card.add_theme_stylebox_override("panel", _style(Color("#1a3533"), Color("#2f6258"), 9, 1))
	left_content.add_child(tutorial_card)
	var tutorial_box := VBoxContainer.new()
	tutorial_box.add_theme_constant_override("separation", 8)
	tutorial_box.add_theme_constant_override("margin_left", 10)
	tutorial_box.add_theme_constant_override("margin_right", 10)
	tutorial_box.add_theme_constant_override("margin_top", 10)
	tutorial_box.add_theme_constant_override("margin_bottom", 10)
	tutorial_card.add_child(tutorial_box)
	if bool(onboarding.get("active", false)):
		tutorial_box.add_child(_label("新手引导 · 第 %d / 7 步" % mini(int(onboarding.get("step", 0)) + 1, 7), 16, TEAL, true))
		tutorial_box.add_child(_label("%s → %s" % [_find_demand(str(onboarding.get("originId", ""))).get("name", "起点"), _find_demand(str(onboarding.get("destinationId", ""))).get("name", "目的地")], 15, TEXT, true))
		tutorial_box.add_child(_label(_tutorial_detail(int(onboarding.get("step", 0))), 14, MUTED))
		var locate := _button("返回任务位置", TEXT, PANEL_LIGHT, 15)
		locate.custom_minimum_size.y = 44.0 * _ui_scale
		locate.pressed.connect(_return_to_onboarding_mission)
		tutorial_box.add_child(locate)
	elif str(world.get("mode", "blank")) == "expand":
		tutorial_box.add_child(_label("扩建现实路网：选一条既有线路，查看周边需求后再扩建。", 14, MUTED))
		var browse := _button("定位既有线路", TEXT, PANEL_LIGHT, 15)
		browse.pressed.connect(_locate_existing_network)
		tutorial_box.add_child(browse)
	else:
		tutorial_box.add_child(_label("基础教学已结束。你可以继续扩建，或随时重玩引导。", 14, MUTED))
		var replay := _button("重玩街区规划引导", TEXT, PANEL_LIGHT, 15)
		replay.pressed.connect(_restart_onboarding)
		tutorial_box.add_child(replay)
	if bool(onboarding.get("completed", false)) and not bool(onboarding.get("active", false)):
		var local_flow := _next_neighborhood_flow(onboarding)
		left_content.add_child(_label("下一步 · 附近扩建", 17, TEAL, true))
		if not local_flow.is_empty():
			var local_card := PanelContainer.new()
			local_card.add_theme_stylebox_override("panel", _style(Color("#1b2a35"), Color("#39705e"), 8, 1))
			left_content.add_child(local_card)
			var local_box := VBoxContainer.new()
			local_box.add_theme_constant_override("separation", 7)
			local_box.add_theme_constant_override("margin_left", 10); local_box.add_theme_constant_override("margin_right", 10)
			local_box.add_theme_constant_override("margin_top", 9); local_box.add_theme_constant_override("margin_bottom", 9)
			local_card.add_child(local_box)
			var local_title := _label("%s → %s" % [local_flow.get("from", "附近居住区"), local_flow.get("to", "附近目的地")], 16, TEXT, true)
			local_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			local_box.add_child(local_title)
			local_box.add_child(_label("这组附近出行目前没有完整地铁路径 · 游戏设定约 %s 人次/日" % _number(int(round(float(local_flow.get("peoplePerDay", 0.0))))), 14, MUTED))
			var locate_local := _button("查看这组需求", Color("#8fc9ed"), PANEL_LIGHT, 14)
			locate_local.pressed.connect(func(): _focus_flow(local_flow))
			local_box.add_child(locate_local)
		else:
			left_content.add_child(_label("当前教学街区附近没有未服务的出行目标；可从线路页查看其他需求。", 14, MUTED))
	var goal_board: Dictionary = world.get("goalBoard", {})
	var active_goals: Array = goal_board.get("active", [])
	left_content.add_child(_label("当前目标 · %d / 3" % active_goals.size(), 17, TEXT, true))
	if active_goals.is_empty():
		left_content.add_child(_label("暂时没有明显的待补需求或运营问题。你可以查看需求地点，继续扩建。", 14, MUTED))
	for goal in active_goals:
		var goal_flow := _find_cached_flow(str(goal.get("flowId", "")))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _style(Color("#1b2a35"), Color("#39705e") if str(goal.get("status", "")) == "observe" else BORDER, 8, 1))
		left_content.add_child(card)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 7)
		content.add_theme_constant_override("margin_left", 10)
		content.add_theme_constant_override("margin_right", 10)
		content.add_theme_constant_override("margin_top", 9)
		content.add_theme_constant_override("margin_bottom", 9)
		card.add_child(content)
		var title := _label(str(goal.get("title", "街区目标")), 16, TEXT, true)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(title)
		var description := ""
		var action_label := "查看位置"
		var route_id := str(goal.get("routeId", ""))
		match str(goal.get("type", "")):
			"coverage":
				description = "已有路径，等待实际到达并保持改善一游戏小时。" if bool(goal_flow.get("valid", false)) else "约 %s 人次/日尚无完整路径；需要覆盖两端并连通轨道。" % _number(int(round(float(goal_flow.get("peoplePerDay", 0)))))
			"operations":
				var route := WorldData.find_route(world, route_id)
				var waiting := int(world.get("simulation", {}).get("waitingByRoute", {}).get(route_id, 0))
				description = "当前约 %d 人等待 %s；可在线路详情调整班距。" % [waiting, str(route.get("name", "线路"))]
				action_label = "查看线路"
			"transfer":
				description = "这是需要换乘的出行目标；建立同站换乘后观察实际到达。"
		content.add_child(_label(description, 14, MUTED))
		var locate := _button(action_label, Color("#8fc9ed"), PANEL_LIGHT, 14)
		locate.custom_minimum_size.y = 42.0 * _ui_scale
		if str(goal.get("type", "")) == "operations":
			locate.pressed.connect(func(): _focus_route(route_id))
		else:
			locate.pressed.connect(func(): _focus_flow(goal_flow))
		content.add_child(locate)
	var completed_goals: Array = goal_board.get("completed", [])
	if not completed_goals.is_empty():
		left_content.add_child(_label("近期改善记录", 16, TEAL, true))
		for result in completed_goals.slice(maxi(0, completed_goals.size() - 3), completed_goals.size()):
			left_content.add_child(_label("%s · 稳定观察 1 小时" % str(result.get("title", "街区改善")), 14, MUTED))
	if not str(world.get("migrationNotice", "")).is_empty():
		var notice := _label(str(world.get("migrationNotice", "")), 13, Color("#e1b975"))
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_content.add_child(notice)

func _next_neighborhood_flow(onboarding: Dictionary) -> Dictionary:
	_ensure_flow_cache()
	var origin := _find_demand(str(onboarding.get("originId", "")))
	var destination := _find_demand(str(onboarding.get("destinationId", "")))
	if origin.is_empty() or destination.is_empty(): return {}
	var best: Dictionary = {}
	var best_score := INF
	for flow in _flow_cache:
		if bool(flow.get("valid", false)) or str(flow.get("fromType", "")) != "housing": continue
		var flow_id := str(flow.get("id", ""))
		if flow_id == "%s>%s" % [onboarding.get("originId", ""), onboarding.get("destinationId", "")]: continue
		var point: Array = flow.get("originLatLng", [])
		if point.size() < 2: continue
		var from_a := _distance_m(point, origin.get("latlng", []))
		var from_b := _distance_m(point, destination.get("latlng", []))
		var distance := minf(from_a, from_b)
		if distance > 8000.0: continue
		var score := distance - minf(float(flow.get("peoplePerDay", 0.0)), 500.0) * 0.5
		if score < best_score:
			best_score = score
			best = flow
	return best

func _refresh_stats_tab() -> void:
	left_content.add_child(_label("运营统计", 20, TEXT, true))
	var sim: Dictionary = world.get("simulation", {})
	var elapsed := int(sim.get("elapsedMinutes", sim.get("minute", 420)))
	left_content.add_child(_label("第 %d 天 · %02d:%02d" % [elapsed / 1440 + 1, posmod(elapsed, 1440) / 60, posmod(elapsed, 60)], 15, MUTED))
	var metrics := [
		["累计发起", int(sim.get("attempted", 0)), "按游戏需求产生的出行批次人数。"],
		["已到达", int(sim.get("completed", 0)), "只有抵达目的地才计入。"],
		["等候", int(sim.get("waiting", 0)), "正在站台等待符合线路与方向的列车。"],
		["在途", int(sim.get("inTransit", 0)), "步行、换乘或乘车中的人数。"],
		["已放弃", int(sim.get("abandoned", 0)), "等待超过 30 游戏分钟后离开。"],
		["中断记录", int(sim.get("interrupted", 0)), "线路失效时记录的历史中断人数。"],
		["无法接入", int(sim.get("unreachable", 0)), "当前没有可用完整旅程的出行人数。"]
	]
	for metric in metrics:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var metric_name := _label(str(metric[0]), 15, TEXT, true)
		metric_name.custom_minimum_size.x = 118.0 * _ui_scale
		metric_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var metric_value := _label(_number(int(metric[1])), 17, TEAL, true)
		metric_value.custom_minimum_size.x = 62.0 * _ui_scale
		metric_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(metric_name)
		row.add_child(metric_value)
		left_content.add_child(row)
		var explanation := _label(str(metric[2]), 13, MUTED)
		explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_content.add_child(explanation)
	left_content.add_child(HSeparator.new())
	var completed := int(sim.get("completed", 0))
	if completed > 0:
		var average := float(sim.get("tripMinutesTotal", 0.0)) / float(completed)
		left_content.add_child(_label("平均完整出行 · %.1f 分钟" % average, 17, TEXT, true))
	else:
		left_content.add_child(_label("尚无完成行程，暂不显示平均耗时或效率评分。", 14, MUTED))
	left_content.add_child(_label("高峰区间占用 · %.0f%%" % (float(sim.get("peakCrowding", 0.0)) * 100.0), 15, TEXT))
	var waiting_by_route: Dictionary = sim.get("waitingByRoute", {})
	left_content.add_child(_label("线路候车", 17, TEXT, true))
	for route in world.get("routes", []):
		var route_id := str(route.get("id", ""))
		var line_row := _button("%s   等待 %s 人 · 班距 %d 分钟" % [str(route.get("name", "线路")), _number(int(waiting_by_route.get(route_id, 0))), int(route.get("headway", 3))], TEXT, PANEL_LIGHT, 14)
		line_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		line_row.custom_minimum_size.y = 42.0 * _ui_scale
		line_row.pressed.connect(func(): _focus_route(route_id))
		left_content.add_child(line_row)
	left_content.add_child(_label("以上均为游戏模拟。地图上的示意线路与客流数字不是现实运营预测。", 13, MUTED))


func _tutorial_detail(step: int) -> String:
	match step:
		0: return "用「放置车站」在需求点附近建立站台；按 R 调整朝向。"
		1: return "使用「直线铺轨」或「曲线铺轨」连接站端；物理轨道不属于某条线路。"
		2: return "选择「创建运营线路」，按停站顺序点击车站并确认线路走向。"
		3: return "在线路详情检查并开通；车辆自动保障，站间距只影响运行时间。"
		4: return "按播放，批次乘客真正到达后才计入完成出行。"
	return "基础教学可以跳过，也可以从菜单重开。"

func _refresh_right_panel() -> void:
	for c in right_content.get_children(): c.queue_free()
	if is_instance_valid(_right_pinned_header):
		for c in _right_pinned_header.get_children(): c.queue_free()
	if is_instance_valid(_right_pinned_footer):
		for c in _right_pinned_footer.get_children(): c.queue_free()
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
		right_content.add_child(_label("选择一座车站、轨道、线路或需求点查看信息。\n\n建设顺序：放置车站 → 自由铺设物理轨道 → 创建运营线路 → 检查开通。\n\n默认自动配车；站间距离影响运行时间，不作为开通门槛。", 13, MUTED))
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
	var fixed_header: Control = _right_pinned_header if is_instance_valid(_right_pinned_header) else right_content
	var fixed_footer: Control = _right_pinned_footer if is_instance_valid(_right_pinned_footer) else right_content
	fixed_header.add_child(_label("车站详情", 20, TEXT, true))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	fixed_header.add_child(_label("站名", 14, MUTED))
	var name_edit := LineEdit.new(); name_edit.text = str(station.get("name", "")); name_edit.placeholder_text = "输入车站名称"; name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _set_control_base_font(name_edit, 16)
	name_edit.text_submitted.connect(func(value: String): _rename_station(str(station.id), value))
	name_edit.focus_exited.connect(func(): _rename_station(str(station.id), name_edit.text))
	name_row.add_child(name_edit)
	var save_name := _button("保存", TEAL, Color("#15372f"), 14)
	save_name.pressed.connect(func(): _rename_station(str(station.id), name_edit.text))
	name_row.add_child(save_name)
	fixed_header.add_child(name_row)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 5)
	var move := _button("移动车站", TEXT, PANEL_LIGHT, 14)
	move.pressed.connect(func():
		if current_tool == "move_station": _finish_tool()
		else:
			current_tool = "move_station"
			map_view.tool = current_tool
			map_view.requested_redraw()
			_refresh_tools()
			_show_toast("移动模式：拖动车站至新位置；放开后检查站体与接轨")
	)
	actions.add_child(move)
	var rotate := _button("旋转 15°  (R)", TEXT, PANEL_LIGHT, 14)
	rotate.pressed.connect(func(): _rotate_station(str(station.id)))
	actions.add_child(rotate)
	var connect_a := _button("从 A 端铺轨", TEAL, Color("#15372f"), 14)
	connect_a.pressed.connect(func(): _begin_station_track(str(station.id), "start"))
	actions.add_child(connect_a)
	var connect_b := _button("从 B 端铺轨", TEAL, Color("#15372f"), 14)
	connect_b.pressed.connect(func(): _begin_station_track(str(station.id), "end"))
	actions.add_child(connect_b)
	fixed_header.add_child(actions)
	var rotation_row := HBoxContainer.new()
	rotation_row.add_theme_constant_override("separation", 6)
	var rotation := SpinBox.new()
	rotation.min_value = 0
	rotation.max_value = 359.9
	rotation.step = 0.1
	rotation.value = fposmod(float(station.get("heading", 90.0)), 360.0)
	rotation.suffix = "°"
	_set_control_base_font(rotation, 15)
	rotation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var apply_rotation := _button("应用角度", TEXT, PANEL_LIGHT, 14)
	apply_rotation.pressed.connect(func(): _set_station_heading(str(station.id), rotation.value))
	rotation_row.add_child(rotation)
	rotation_row.add_child(apply_rotation)
	fixed_header.add_child(rotation_row)
	var locate := _button("定位到地图", TEXT, PANEL_LIGHT, 14)
	locate.pressed.connect(func(): map_view.center_on(station.get("latlng", [0,0]), maxi(map_view.current_zoom, 14)))
	fixed_header.add_child(locate)
	right_content.add_child(HSeparator.new())
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
	right_content.add_child(_label("%d 节 · 列车总长 %.1f 米 · 站厅宽 %.0f 米\n地下深度 %.0f 米 · 中心 %.5f, %.5f\n%s" % [profile.get("cars", 6), station.get("lengthM", 118.8), station.get("widthM", 20.0), station.get("depthM", -15.0), station.get("latlng", [0,0])[0], station.get("latlng", [0,0])[1], "既有站体：游戏简化" if station.get("existing", false) else "游戏简化站体，尺寸随编组",], 13, MUTED))
	var depth_row := HBoxContainer.new()
	var depth_down := _button("深度 −5 米", TEXT, PANEL_LIGHT, 13); depth_down.pressed.connect(func(): _change_station_depth(str(station.id), -5.0)); depth_row.add_child(depth_down)
	var depth_up := _button("深度 +5 米", TEXT, PANEL_LIGHT, 13); depth_up.pressed.connect(func(): _change_station_depth(str(station.id), 5.0)); depth_row.add_child(depth_up)
	right_content.add_child(depth_row)
	right_content.add_child(HSeparator.new())
	if station.get("schematic", false):
		var schematic := _label("既有站点坐标来自 OSM 快照。站厅位置与尺寸是游戏简化示意，不代表实测建筑。", 10, Color("#d4af6b")); schematic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; right_content.add_child(schematic)
	var del := _button("拆除车站", Color("#ef8b8b"), Color("#41272d"), 14)
	del.pressed.connect(func(): _delete_station(str(station.id)))
	del.custom_minimum_size.y = maxf(44.0, 40.0 * minf(_ui_scale, 1.25))
	fixed_footer.add_child(del)

func _begin_station_track(station_id: String, side: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	TrackNetwork.ensure_station_nodes(world)
	current_tool = "track"
	map_view.tool = current_tool
	map_view.draft_station = {}
	map_view.link_start = {}
	map_view.track_control_latlng = []
	map_view.track_preview_conflict = ""
	map_view.track_preview_notice = ""
	map_view.track_start_ref = {"nodeId": TrackNetwork.station_node_id(station, side), "latlng": WorldData.station_endpoint(station, side), "stationId": station_id, "side": side, "depthM": float(station.get("depthM", -15.0))}
	map_view.track_end_ref = {}
	selected_type = "station"
	selected_id = station_id
	map_view.selected_type = selected_type
	map_view.selected_id = selected_id
	map_view.requested_redraw()
	_refresh_ui()
	_show_toast("从 %s · %s 端开始铺设地下轨道；终点可接另一站端或轨道节点" % [station.get("name", "车站"), "A" if side == "start" else "B"])

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
	var repair_pairs: Dictionary = {}
	for direction in route.get("directions", []):
		if not direction is Dictionary: continue
		var stops: Array = direction.get("stationIds", [])
		var paths: Array = direction.get("edgePathsBySegment", [])
		for segment_index in range(maxi(0, stops.size() - 1)):
			var segment_path: Array = paths[segment_index] if segment_index < paths.size() and paths[segment_index] is Array else []
			if not segment_path.is_empty(): continue
			var from_id := str(stops[segment_index]); var to_id := str(stops[segment_index + 1])
			var pair_key := "%s|%s" % [from_id, to_id] if from_id < to_id else "%s|%s" % [to_id, from_id]
			if repair_pairs.has(pair_key): continue
			repair_pairs[pair_key] = true
			var from_station := WorldData.find_station(world, from_id); var to_station := WorldData.find_station(world, to_id)
			var repair := _button("修复：%s → %s" % [from_station.get("name", "车站"), to_station.get("name", "车站")], Color("#f2bd58"), PANEL_LIGHT, 14)
			repair.pressed.connect(_begin_route_segment_repair.bind(str(route.get("id", "")), str(direction.get("id", "")), segment_index))
			right_content.add_child(repair)
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var route_path := RoutePathScript.for_route(route, world, ref_lat)
	var directions: Array = route_path.get("directions", [])
	var route_errors: Array = route_path.get("errors", [])
	var path_summary: String = "有效路径：%d 个方向 · %.1f 分钟/方向" % [directions.size(), float(directions[0].get("travelMinutes", 0.0))] if bool(route_path.get("valid", false)) and not directions.is_empty() else "运营路径待整理：%s" % (str(route_errors[0]) if not route_errors.is_empty() else "没有可用停站路径")
	right_content.add_child(_label("状态：%s\n配车：自动保障\n线路长度约 %.1f 千米\n最大单向运能：约 %d 人/小时\n%s\n区间几何：%s" % ["已开通" if route.get("open", false) else "草案", _route_length_km(route), int(WorldData.vehicle(str(route.get("vehicleId", "B-6"))).get("capacity", 1800)) * 60 / maxi(1, int(route.get("headway", 3))), path_summary, "既有线路站间示意" if route.get("schematic", false) else "由站端连接生成"], 13, MUTED))
	var check := _button("检查并开通此线路", TEAL, Color("#15372f"), 14)
	if not bool(world.get("tutorialDone", false)) and int(world.get("tutorialStep", 0)) == 2:
		check.add_theme_stylebox_override("normal", _style(Color("#246a52"), Color("#78edc4"), 8, 2))
	check.pressed.connect(_open_route); right_content.add_child(check)
	var del := _button("删除线路", Color("#ef8b8b"), Color("#41272d"), 12); del.pressed.connect(func(): _delete_route(str(route.id))); right_content.add_child(del)

func _link_details(link: Dictionary) -> void:
	right_content.add_child(_label("轨道区间", 20, TEXT, true))
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var endpoints := TrackNetwork._edge_node_ids(link, world)
	var node_a := TrackNetwork.find_node(world, endpoints[0]) if endpoints.size() == 2 else {}
	var node_b := TrackNetwork.find_node(world, endpoints[1]) if endpoints.size() == 2 else {}
	var a_name := "自由接点"
	var b_name := "自由接点"
	if not node_a.is_empty():
		var station_a := WorldData.find_station(world, str(node_a.get("stationId", "")))
		if not station_a.is_empty(): a_name = "%s · %s端" % [station_a.get("name", "车站"), "A" if str(node_a.get("side", "")) == "start" else "B"]
	if not node_b.is_empty():
		var station_b := WorldData.find_station(world, str(node_b.get("stationId", "")))
		if not station_b.is_empty(): b_name = "%s · %s端" % [station_b.get("name", "车站"), "A" if str(node_b.get("side", "")) == "start" else "B"]
	if not link.has("aNodeId"):
		var station_a := WorldData.find_station(world, str(link.get("a", {}).get("stationId", "")))
		var station_b := WorldData.find_station(world, str(link.get("b", {}).get("stationId", "")))
		if not station_a.is_empty(): a_name = "%s · %s端" % [station_a.get("name", "车站"), "A" if str(link.get("a", {}).get("side", "")) in ["start", "A"] else "B"]
		if not station_b.is_empty(): b_name = "%s · %s端" % [station_b.get("name", "车站"), "A" if str(link.get("b", {}).get("side", "")) in ["start", "A"] else "B"]
	var length := TrackNetwork.edge_length_m(link, world, ref_lat) if link.has("aNodeId") else WorldData.track_length_m(link, world, ref_lat)
	var route_id := str(link.get("routeIds", [""])[0]) if not link.get("routeIds", []).is_empty() else ""
	var route := WorldData.find_route(world, route_id)
	var route_path := RoutePathScript.for_route(route, world, ref_lat) if not route.is_empty() else {"valid": false, "directions": []}
	var minutes := -1.0
	if bool(route_path.get("valid", false)):
		for direction in route_path.get("directions", []):
			for segment in direction.get("segments", []):
				if str(segment.get("linkId", "")) == str(link.get("id", "")) or segment.get("linkIds", []).has(str(link.get("id", ""))):
					minutes = float(segment.get("travelMinutes", 0.0))
					break
			if minutes >= 0.0: break
	var runtime_text := "估算运行 %.1f 分钟（与线路路径一致）" % minutes if minutes >= 0.0 else "未纳入有效运营路径"
	right_content.add_child(_label("%s · %s\n%s → %s\n长度 %.0f 米 · 深度 %.0f 米\n%s\n%s" % [route.get("name", "未编入运营线路"), "站间示意" if link.get("schematic", false) else "实体地下轨道", a_name, b_name, length, float(link.get("depthM", -15.0)), runtime_text, "现实快照几何待核验" if link.get("schematic", false) else "按实际曲线计算里程"], 15, MUTED))
	if not link.get("schematic", false) and str(link.get("geometry", "straight")) == "bezier":
		var curve := _button("调整曲线控制点", TEXT, PANEL_LIGHT, 14)
		curve.pressed.connect(func(): active_route_id = route_id; selected_type = "link"; selected_id = str(link.get("id", "")); map_view.selected_type = "link"; map_view.selected_id = selected_id; _set_tool("curve"))
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
	if not is_instance_valid(tool_panel) or not is_instance_valid(tool_action_panel): return
	for c in tool_panel.get_children():
		tool_panel.remove_child(c)
		c.queue_free()
	for c in tool_action_panel.get_children():
		tool_action_panel.remove_child(c)
		c.queue_free()
	tool_action_panel.visible = false
	var footer_instruction := _tool_instruction()
	if is_instance_valid(tool_instruction_label):
		tool_instruction_label.text = footer_instruction
		tool_instruction_label.add_theme_color_override("font_color", TEAL if current_tool == "station" else MUTED)
	var onboarding: Dictionary = world.get("onboarding", {})
	var guide_active := bool(onboarding.get("active", false)) and not _more_tools_expanded
	var tutorial_step := int(onboarding.get("step", 0)) if guide_active else int(world.get("tutorialStep", 0))
	var tools: Array = [["select", "选择"], ["station", "车站"], ["track", "轨道"], ["line", "运营线路"]]
	if guide_active:
		if tutorial_step in [1, 2]: tools = [["station", "放置车站"]]
		elif tutorial_step == 3: tools = [["track", "连续铺轨"]]
		elif tutorial_step == 4: tools = [["line", "创建运营线路"]]
		else: tools = [["select", "选择"]]
	for item in tools:
		var active: bool = current_tool == item[0] or (str(item[0]) == "track" and current_tool in ["track", "track_curve"])
		var coached := false
		var button := _button(item[1], TEAL if active or coached else TEXT, Color("#174037") if active else Color("#1c4039") if coached else PANEL_LIGHT, 14)
		button.custom_minimum_size = Vector2(118.0 * minf(_ui_scale, 1.25), 46.0 * minf(_ui_scale, 1.25))
		if coached: button.tooltip_text = "新手教学下一步"
		button.pressed.connect(func(): _set_tool(str(item[0])))
		tool_panel.add_child(button)
	if not guide_active and _more_tools_expanded:
		for item in [["track_curve", "曲线轨道"], ["curve", "调曲线"], ["delete", "拆除"]]:
			var button := _button(str(item[1]), TEAL if current_tool == item[0] else TEXT, PANEL_LIGHT, 14)
			button.custom_minimum_size = Vector2(108.0 * minf(_ui_scale, 1.25), 44.0 * minf(_ui_scale, 1.25))
			button.pressed.connect(func(): _set_tool(str(item[0])))
			tool_panel.add_child(button)
	var more := _button("收起更多 ▾" if _more_tools_expanded else "更多工具 ▸", MUTED, PANEL_LIGHT, 13)
	more.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
	more.pressed.connect(func(): _more_tools_expanded = not _more_tools_expanded; _refresh_tools())
	tool_panel.add_child(more)
	if current_tool == "station" and not map_view.draft_station.is_empty():
		var confirm := _button("确认任务车站" if bool(onboarding.get("active", false)) else "确认站点", TEAL, Color("#164034"), 14); confirm.disabled = map_view.draft_conflict; confirm.pressed.connect(_confirm_station); _add_tool_action(confirm)
		var cancel := _button("取消本步", MUTED, PANEL_LIGHT, 14); cancel.pressed.connect(_cancel_tool_step); _add_tool_action(cancel)
		var finish_station := _button("退出建站", MUTED, PANEL_LIGHT, 14); finish_station.pressed.connect(_finish_tool); _add_tool_action(finish_station)
		if is_instance_valid(tool_instruction_label):
			tool_instruction_label.text += "   ·   预览 %.1f × %.0f 米；可拖动或点空地重定位，按 R 转向" % [map_view.draft_station.get("lengthM", 118.8), map_view.draft_station.get("widthM", 20)]
		_refresh_onboarding_card()
	elif current_tool == "move_station":
		var moving_station := WorldData.find_station(world, selected_id)
		var moving_name := str(moving_station.get("name", "车站")) if not moving_station.is_empty() else "车站"
		var move_hint := _button("拖动车站「%s」或点击新位置" % moving_name, TEAL, PANEL_LIGHT, 14)
		move_hint.disabled = true
		tool_panel.add_child(move_hint)
		var finish_move := _button("结束移动", MUTED, PANEL_LIGHT, 14)
		finish_move.pressed.connect(_finish_tool)
		_add_tool_action(finish_move)
	elif current_tool in ["track", "track_curve"]:
		var geometry_mode := _button("当前：曲线" if current_tool == "track_curve" else "当前：直线", TEAL, PANEL_LIGHT, 13)
		geometry_mode.pressed.connect(func(): _set_tool("track" if current_tool == "track_curve" else "track_curve"))
		tool_panel.add_child(geometry_mode)
		var depth_down := _button("深度 −5 m", TEXT, PANEL_LIGHT, 13); depth_down.pressed.connect(func(): _adjust_track_depth(-5.0)); tool_panel.add_child(depth_down)
		var depth_label := _button("深度 %.0f m" % map_view.current_depth_m, TEAL, PANEL_LIGHT, 13); depth_label.disabled = true; tool_panel.add_child(depth_label)
		var depth_up := _button("深度 +5 m", TEXT, PANEL_LIGHT, 13); depth_up.pressed.connect(func(): _adjust_track_depth(5.0)); tool_panel.add_child(depth_up)
		var all_depths := CheckButton.new(); all_depths.text = "显示全部深度"; all_depths.button_pressed = map_view.show_all_depths; all_depths.toggled.connect(func(value: bool): map_view.show_all_depths = value; map_view.requested_redraw()); tool_panel.add_child(all_depths)
		var continuous := CheckButton.new(); continuous.text = "连续铺设"; continuous.button_pressed = map_view.continuous_track; continuous.toggled.connect(func(value: bool): map_view.continuous_track = value); tool_panel.add_child(continuous)
		if not map_view.track_end_ref.is_empty():
			var confirm_track := _button("确认轨道段", Color("#eafff8"), Color("#17644f"), 14); confirm_track.disabled = not map_view.track_preview_conflict.is_empty(); confirm_track.pressed.connect(_commit_track_preview); _add_tool_action(confirm_track)
			var cancel_segment := _button("取消本段", MUTED, PANEL_LIGHT, 13); cancel_segment.pressed.connect(func(): map_view.track_end_ref = {}; map_view.track_preview_conflict = ""; map_view.track_preview_notice = ""; map_view.requested_redraw(); _refresh_tools()); _add_tool_action(cancel_segment)
		var end := _button("结束铺轨", Color("#ffe8d0"), Color("#563725"), 14); end.pressed.connect(_finish_tool); _add_tool_action(end)
		for candidate in endpoint_choice_candidates:
			var station_id := str(candidate.get("id", candidate.get("stationId", "")))
			var endpoint_side := str(candidate.get("side", "start"))
			var endpoint_station := WorldData.find_station(world, station_id)
			var candidate_label := "%s · %s端" % [endpoint_station.get("name", "车站"), "A" if endpoint_side == "start" else "B"] if str(candidate.get("type", "endpoint")) == "endpoint" else "轨道自由节点 · %s" % station_id
			var choose_endpoint := _button(candidate_label, TEAL, Color("#15372f"), 14)
			choose_endpoint.pressed.connect(_choose_track_endpoint.bind(candidate.duplicate(true)))
			tool_panel.add_child(choose_endpoint)
		if not map_view.track_preview_conflict.is_empty(): tool_instruction_label.text = map_view.track_preview_conflict
		elif not map_view.track_preview_notice.is_empty(): tool_instruction_label.text = map_view.track_preview_notice
		_refresh_onboarding_card()
	elif current_tool == "line":
		var line_hint := _button("停站 %d 座" % line_draft_stops.size(), TEAL, PANEL_LIGHT, 13); line_hint.disabled = true; tool_panel.add_child(line_hint)
		_ensure_line_draft_path_options()
		if not line_draft_path_options.is_empty():
			var segment_index := clampi(line_draft_segment_index, 0, line_draft_path_options.size() - 1)
			var previous_segment := _button("‹ 上一区间", TEXT, PANEL_LIGHT, 13)
			previous_segment.disabled = segment_index <= 0
			previous_segment.pressed.connect(func(): line_draft_segment_index = maxi(0, segment_index - 1); _refresh_tools())
			tool_panel.add_child(previous_segment)
			var segment_label := _button("区间 %d → %d" % [segment_index + 1, segment_index + 2], TEAL, PANEL_LIGHT, 13)
			segment_label.disabled = true
			tool_panel.add_child(segment_label)
			var next_segment := _button("下一区间 ›", TEXT, PANEL_LIGHT, 13)
			next_segment.disabled = segment_index >= line_draft_path_options.size() - 1
			next_segment.pressed.connect(func(): line_draft_segment_index = mini(line_draft_path_options.size() - 1, segment_index + 1); _refresh_tools())
			tool_panel.add_child(next_segment)
			var choices: Array = line_draft_path_options[segment_index]
			if choices.size() > 1:
				var choice_index := int(line_draft_path_choices[segment_index])
				var choose_path := _button("经过走向 %d / %d" % [choice_index + 1, choices.size()], TEAL, PANEL_LIGHT, 13)
				choose_path.tooltip_text = "点击切换两座停站之间的物理轨道走向"
				choose_path.pressed.connect(func():
					line_draft_path_choices[segment_index] = (int(line_draft_path_choices[segment_index]) + 1) % choices.size()
					_update_line_draft_preview(); _refresh_tools()
				)
				tool_panel.add_child(choose_path)
		if line_draft_stops.size() >= 2:
			var confirm_line := _button("确认线路走向", Color("#eafff8"), Color("#17644f"), 14); confirm_line.pressed.connect(_confirm_operating_line); _add_tool_action(confirm_line)
		var undo_stop := _button("撤回上一站", MUTED, PANEL_LIGHT, 13); undo_stop.disabled = line_draft_stops.is_empty(); undo_stop.pressed.connect(func(): if not line_draft_stops.is_empty(): line_draft_stops.pop_back(); _update_line_draft_preview(); _refresh_tools()); _add_tool_action(undo_stop)
		var end_line := _button("结束线路设置", MUTED, PANEL_LIGHT, 14); end_line.pressed.connect(_finish_tool); _add_tool_action(end_line)
	elif current_tool == "repair_route_segment":
		var from_station := WorldData.find_station(world, repair_from_station_id)
		var to_station := WorldData.find_station(world, repair_to_station_id)
		var choice_label := _button("候选走向 %d / %d" % [repair_path_choice + 1, repair_path_options.size()], TEXT, PANEL_LIGHT, 13)
		choice_label.disabled = repair_path_options.size() < 2
		choice_label.pressed.connect(func(): repair_path_choice = (repair_path_choice + 1) % repair_path_options.size(); _update_repair_preview(); _refresh_tools())
		tool_panel.add_child(choice_label)
		var instruction := "点击高亮轨道选择走向。" if not repair_path_options.is_empty() else "还没有连续轨道；先铺轨，再回来修复。"
		instruction = "修复「%s → %s」：%s" % [from_station.get("name", "车站"), to_station.get("name", "车站"), instruction]
		tool_instruction_label.text = instruction
		var confirm_repair := _button("确认修复区间", Color("#eafff8"), Color("#17644f"), 14)
		confirm_repair.disabled = repair_path_options.is_empty()
		confirm_repair.pressed.connect(_confirm_route_segment_repair)
		_add_tool_action(confirm_repair)
		var cancel_repair := _button("取消修复", MUTED, PANEL_LIGHT, 14); cancel_repair.pressed.connect(_finish_tool); _add_tool_action(cancel_repair)
	else:
		var finish := _button("结束操作 / Esc", MUTED, PANEL_LIGHT, 14); finish.pressed.connect(_finish_tool); _add_tool_action(finish)
	interaction_state.set_tool(current_tool)
	interaction_state.phase = "choose_snap" if not endpoint_choice_candidates.is_empty() else "preview" if current_tool == "station" and not map_view.draft_station.is_empty() or current_tool in ["track", "track_curve"] and not map_view.track_end_ref.is_empty() else "active" if current_tool != "select" else "idle"
	interaction_state.select_object(selected_type, selected_id)
	call_deferred("_update_responsive_layout")

func _add_tool_action(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 44.0 * minf(_ui_scale, 1.25))
	tool_action_panel.visible = true
	tool_action_panel.add_child(button)
func _tool_instruction() -> String:
	match current_tool:
		"station":
			if map_view.draft_conflict: return "位置冲突：站体与现有车站重叠，请移动或旋转。"
			return "建站：点空地放置预览，可拖动、按 R 转向，再确认。" if map_view.draft_station.is_empty() else "站址预览有效：确认后加入规划。"
		"track": return "直线铺轨：点起点，再点终点预览，确认后写入轨网。"
		"track_curve": return "曲线铺轨：点起点、控制点和终点预览，再确认写入。"
		"line": return "创建运营线路：按停靠顺序点击已接轨车站；可再次点击首站闭合环线。"
		"repair_route_segment": return "修复运营线路：选择两站之间的实际轨道走向，确认后线路保持暂停。"
		"curve": return "调曲线：点蓝色控制点拖动，里程和运行时间同步变化。"
		"delete": return "拆除：点站体或轨道区间；确认后可撤销。"
		_: return "选择：点车站、轨道或需求查看详情；拖空地图移动镜头。"

func _finish_tool() -> void:
	map_view.cancel_pointer_interaction()
	map_view.clear_curve_preview()
	_clear_station_move_preview()
	map_view.draft_station = {}
	map_view.draft_conflict = false
	map_view.link_start = {}
	map_view.track_start_ref = {}; map_view.track_end_ref = {}; map_view.track_control_latlng = []; map_view.track_preview_conflict = ""; map_view.track_preview_notice = ""
	line_draft_stops.clear()
	line_draft_path_options.clear(); line_draft_path_choices.clear(); line_draft_segment_index = -1
	_clear_route_repair_draft()
	endpoint_choice_candidates.clear()
	interaction_state.snap_candidates.clear()
	map_view.line_draft_points.clear()
	current_tool = "select"
	map_view.tool = current_tool
	interaction_state.set_tool(current_tool)
	interaction_state.select_object(selected_type, selected_id)
	map_view.requested_redraw()
	_refresh_ui()

func _on_map_clicked(latlng: Array, hit_type: String, hit_id: String, side: String, hit_t: float = -1.0) -> void:
	if current_tool == "move_station":
		if hit_type == "station" and hit_id != selected_id:
			_select_object("station", hit_id)
			current_tool = "move_station"; map_view.tool = current_tool; _refresh_tools()
			return
		if hit_type == "station" and hit_id == selected_id:
			_show_toast("拖动车站，或点击地图上的新位置")
			return
		if hit_type != "station" and not selected_id.is_empty():
			_on_station_drag_finished(selected_id, latlng)
			return
		_show_toast("先选中一座车站，再移动它")
		return
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
		var vehicle_id := str(route.get("vehicleId", station_vehicle_id)) if not route.is_empty() else station_vehicle_id
		var profile := WorldData.vehicle(vehicle_id)
		var guide_heading := _onboarding_station_heading()
		var heading := guide_heading if guide_heading >= 0.0 else 90.0
		map_view.draft_station = {"id": "draft", "name": _next_station_name(), "latlng": latlng, "heading": heading, "lengthM": float(profile.get("trainLengthM", 118.788)), "widthM": 20.0, "depthM": map_view.current_depth_m, "vehicleId": str(profile.get("id", "B-6")), "routeIds": []}
		_on_draft_station_changed()
		map_view.requested_redraw(); _refresh_tools(); _show_toast("站体预览已放置；按 R 调方向，再确认")
		return
	if current_tool in ["track", "track_curve"]:
		if hit_type == "endpoint_choice":
			endpoint_choice_candidates = map_view.endpoint_choice_candidates.duplicate(true)
			interaction_state.snap_candidates = endpoint_choice_candidates.duplicate(true)
			interaction_state.phase = "choose_snap"
			_refresh_tools()
			return
		_handle_track_click(latlng, hit_type, hit_id, side, hit_t)
		return
	if current_tool == "line":
		if hit_type != "station":
			_show_toast("运营线路按顺序点击已接轨的车站；先完成物理轨道")
			return
		if not line_draft_stops.is_empty() and hit_id == line_draft_stops[0] and line_draft_stops.size() >= 3:
			line_draft_stops.append(hit_id)
		else:
			if not line_draft_stops.is_empty() and line_draft_stops.back() == hit_id:
				_show_toast("相邻停站不能重复；再次点击首站可闭合环线")
				return
			if not line_draft_stops.is_empty():
				var path_check := TrackNetwork.shortest_station_path(line_draft_stops.back(), hit_id, world, float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0]))
				if not bool(path_check.get("valid", false)):
					_show_toast(str(path_check.get("error", "这两站之间没有连续轨道")))
					return
		line_draft_stops.append(hit_id)
		_ensure_line_draft_path_options()
		line_draft_segment_index = maxi(0, line_draft_path_options.size() - 1)
		selected_type = "station"; selected_id = hit_id
		map_view.selected_type = selected_type; map_view.selected_id = selected_id; _update_line_draft_preview(); _refresh_tools(); _refresh_ui()
		return
	if current_tool == "repair_route_segment":
		if hit_type == "link":
			for index in range(repair_path_options.size()):
				if repair_path_options[index].get("linkIds", []).has(hit_id):
					repair_path_choice = index
					_update_repair_preview()
					_refresh_tools()
					_show_toast("已选择包含该轨道的候选走向")
					return
			_show_toast("这段轨道不在当前候选走向中")
		else:
			_show_toast("点击高亮区间内的轨道切换走向，或在底部循环候选")
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
		selected_type = ""; selected_id = ""
		interaction_state.clear_selection()
		if _layout_narrow:
			_left_requested = false
			_right_requested = false
		_update_responsive_layout()
		_refresh_ui()

func _choose_track_endpoint(candidate: Dictionary) -> void:
	endpoint_choice_candidates.clear()
	map_view.endpoint_choice_candidates.clear()
	interaction_state.snap_candidates.clear()
	interaction_state.phase = "active"
	_handle_track_click(candidate.get("latlng", []), str(candidate.get("type", "endpoint")), str(candidate.get("id", "")), str(candidate.get("side", "start")))
	_refresh_tools()

func _track_ref_from_hit(latlng: Array, hit_type: String, hit_id: String, side: String, hit_t: float = -1.0) -> Dictionary:
	if hit_type == "endpoint":
		var station := WorldData.find_station(world, hit_id)
		if not station.is_empty():
			var node_id := TrackNetwork.station_node_id(station, side)
			return {"nodeId": node_id, "latlng": WorldData.station_endpoint(station, side), "stationId": hit_id, "side": side, "depthM": float(station.get("depthM", map_view.current_depth_m))}
	if hit_type == "track_node":
		var node := TrackNetwork.find_node(world, hit_id)
		if not node.is_empty(): return {"nodeId": hit_id, "latlng": node.get("latlng", latlng).duplicate(), "stationId": str(node.get("stationId", "")), "side": str(node.get("side", "")), "depthM": float(node.get("depthM", map_view.current_depth_m))}
	if hit_type == "track_edge" and hit_t >= 0.0:
		var edge := _find_link(hit_id)
		if not edge.is_empty():
			var depth_a := float(edge.get("depthM", map_view.current_depth_m))
			var depth_b := depth_a
			if edge.has("aNodeId"):
				var ends := TrackNetwork._edge_node_ids(edge, world)
				if ends.size() == 2:
					depth_a = float(TrackNetwork.find_node(world, ends[0]).get("depthM", depth_a))
					depth_b = float(TrackNetwork.find_node(world, ends[1]).get("depthM", depth_b))
			elif not edge.get("schematic", false):
				var ends := TrackNetwork._edge_node_ids(edge, world)
				if ends.size() == 2:
					depth_a = float(TrackNetwork.find_node(world, ends[0]).get("depthM", depth_a))
					depth_b = float(TrackNetwork.find_node(world, ends[1]).get("depthM", depth_b))
			var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
			var t := _edge_distance_fraction(edge, latlng, ref_lat)
			return {"nodeId": "", "latlng": latlng.duplicate(), "stationId": "", "side": "", "depthM": lerpf(depth_a, depth_b, t), "splitEdgeId": hit_id, "splitT": t}
	return {"nodeId": "", "latlng": latlng.duplicate(), "stationId": "", "side": "", "depthM": map_view.current_depth_m}

func _edge_distance_fraction(edge: Dictionary, latlng: Array, ref_lat: float) -> float:
	var points := TrackNetwork.edge_points(edge, world, ref_lat, 128)
	if points.size() < 2: return 0.5
	var target := Geo.local_m(latlng, ref_lat)
	var lengths: Array[float] = []
	var total := 0.0
	for index in range(points.size() - 1):
		var length := Geo.local_m(points[index], ref_lat).distance_to(Geo.local_m(points[index + 1], ref_lat))
		lengths.append(length); total += length
	var best_distance := INF
	var best_along := total * 0.5
	var walked := 0.0
	for index in range(points.size() - 1):
		var a := Geo.local_m(points[index], ref_lat)
		var b := Geo.local_m(points[index + 1], ref_lat)
		var segment := b - a
		var fraction := clampf((target - a).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var distance_to_path := target.distance_to(a.lerp(b, fraction))
		if distance_to_path < best_distance:
			best_distance = distance_to_path
			best_along = walked + float(lengths[index]) * fraction
		walked += float(lengths[index])
	return clampf(best_along / maxf(total, 0.001), 0.02, 0.98)

func _handle_track_click(latlng: Array, hit_type: String, hit_id: String, side: String, hit_t: float = -1.0) -> void:
	if hit_type == "station":
		var station := WorldData.find_station(world, hit_id)
		if not station.is_empty():
			var start_distance := _distance_m(latlng, WorldData.station_endpoint(station, "start"))
			var end_distance := _distance_m(latlng, WorldData.station_endpoint(station, "end"))
			side = "start" if start_distance <= end_distance else "end"
			latlng = WorldData.station_endpoint(station, side)
			hit_type = "endpoint"
	var ref := _track_ref_from_hit(latlng, hit_type, hit_id, side, hit_t)
	if map_view.track_start_ref.is_empty():
		map_view.track_start_ref = ref
		map_view.track_end_ref = {}
		map_view.track_control_latlng = []
		map_view.track_preview_conflict = ""
		map_view.track_preview_notice = ""
		map_view.requested_redraw(); _refresh_tools()
		_refresh_onboarding_card()
		_show_toast("已选择铺轨起点；移动地图后点终点" if current_tool == "track" else "已选择曲线起点；再点一处作为弯曲控制位置")
		return
	if current_tool == "track_curve" and map_view.track_control_latlng.is_empty():
		map_view.track_control_latlng = latlng.duplicate()
		map_view.requested_redraw(); _refresh_tools(); _refresh_onboarding_card()
		_show_toast("弯曲方向已设定；现在点终点预览")
		return
	if not confirming_track_preview:
		map_view.track_end_ref = ref
		map_view.track_preview_conflict = ""
		var snapped_target := not str(ref.get("nodeId", "")).is_empty() or not str(ref.get("splitEdgeId", "")).is_empty()
		map_view.track_preview_notice = "目标已吸附到车站或既有轨道 · 确认后接入网络" if snapped_target else "自由端点 · 确认后加入轨网，需继续连接才形成服务"
		map_view.requested_redraw(); _refresh_tools(); _refresh_onboarding_card()
		_show_toast("轨道段已预览；确认后才写入规划")
		return
	confirming_track_preview = false
	var start: Dictionary = map_view.track_start_ref.duplicate(true)
	var finish: Dictionary = ref
	var start_ll: Array = start.get("latlng", [])
	var end_ll: Array = finish.get("latlng", [])
	if start_ll.size() < 2 or end_ll.size() < 2: return
	var a_node_id := str(start.get("nodeId", ""))
	var b_node_id := str(finish.get("nodeId", ""))
	if not a_node_id.is_empty() and a_node_id == b_node_id:
		_show_toast("起点和终点相同；请点另一端或空地")
		return
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var p0 := Geo.local_m(start_ll, ref_lat)
	var p3 := Geo.local_m(end_ll, ref_lat)
	var length_m := p0.distance_to(p3)
	if length_m < 1.0:
		_show_toast("轨道长度不足 1 米；请换一个终点")
		return
	var start_depth := float(start.get("depthM", map_view.current_depth_m))
	var end_depth := float(finish.get("depthM", map_view.current_depth_m))
	var start_split_id := str(start.get("splitEdgeId", ""))
	var finish_split_id := str(finish.get("splitEdgeId", ""))
	if not start_split_id.is_empty() and start_split_id == finish_split_id:
		map_view.track_preview_conflict = "同一轨道段不能同时作为本段两端；分两次从接点继续铺设"
		map_view.requested_redraw(); _refresh_tools(); return
	var curve_offset := Vector2.ZERO
	if not map_view.track_control_latlng.is_empty():
		curve_offset = Geo.local_m(map_view.track_control_latlng, ref_lat) - (p0 + p3) * 0.5
	var chord := p3 - p0
	var handle_length := minf(chord.length() * 0.34, 420.0)
	var start_direction := _track_endpoint_tangent(start, true, chord, ref_lat)
	var end_direction := _track_endpoint_tangent(finish, false, chord, ref_lat)
	var control_a := chord / 3.0 + curve_offset
	var control_b := -chord / 3.0 + curve_offset
	if not a_node_id.is_empty() or not start_split_id.is_empty(): control_a = start_direction * handle_length
	if not b_node_id.is_empty() or not finish_split_id.is_empty(): control_b = -end_direction * handle_length
	var candidate := {"a": start_ll, "b": end_ll, "aNodeId": a_node_id, "bNodeId": b_node_id, "geometry": "bezier" if current_tool == "track_curve" else "straight", "controlA": [control_a.x, control_a.y], "controlB": [control_b.x, control_b.y], "depthM": (start_depth + end_depth) * 0.5}
	var preview_state := _candidate_with_temp_nodes(candidate, ref_lat)
	var preview_edge: Dictionary = preview_state.trackEdges[0]
	var candidate_points := TrackNetwork.edge_points(preview_edge, preview_state, ref_lat, 32)
	var actual_length := TrackNetwork.edge_length_m(preview_edge, preview_state, ref_lat)
	var grade := absf(end_depth - start_depth) / maxf(actual_length, 1.0)
	if grade > 0.035:
		map_view.track_preview_conflict = "纵坡 %.1f‰ 超过 35‰；拉长坡段或调整深度" % (grade * 1000.0)
		map_view.requested_redraw(); _refresh_tools(); return
	var ignored_edges: Array[String] = []
	if not start_split_id.is_empty(): ignored_edges.append(start_split_id)
	if not finish_split_id.is_empty() and not ignored_edges.has(finish_split_id): ignored_edges.append(finish_split_id)
	var conflict := _track_crossing_conflict(candidate_points, candidate, start_depth, end_depth, ref_lat, ignored_edges)
	if not conflict.is_empty():
		map_view.track_preview_conflict = conflict
		map_view.requested_redraw(); _refresh_tools(); return
	var curve_warning := ""
	if str(candidate.get("geometry", "")) == "bezier":
		var radius := _minimum_curve_radius(candidate_points, ref_lat)
		if radius < 300.0: curve_warning = "最小转弯半径约 %.0f 米，低于 300 米游戏建议" % radius
	var edge_id := "te_%d" % Time.get_ticks_usec()
	var committed_target: Dictionary = {}
	var changed := history.execute("铺设地下轨道", func(state: Dictionary):
		var a_id := _materialize_track_ref(state, start, ref_lat)
		var b_id := _materialize_track_ref(state, finish, ref_lat)
		var edge := {"id": edge_id, "aNodeId": a_id, "bNodeId": b_id, "geometry": candidate.geometry, "controlA": candidate.controlA, "controlB": candidate.controlB, "depthM": candidate.depthM, "routeIds": [], "speedLimitKmh": -1.0}
		state.trackEdges.append(edge)
		committed_target = {"nodeId": b_id, "latlng": end_ll.duplicate(), "stationId": str(finish.get("stationId", "")), "side": str(finish.get("side", "")), "depthM": end_depth}
	)
	if not changed: return
	map_view.track_end_ref = {}
	map_view.set_world(world)
	map_view.track_preview_conflict = ""
	map_view.track_preview_notice = ""
	if map_view.continuous_track and str(finish.get("stationId", "")).is_empty():
		map_view.track_start_ref = committed_target
		map_view.track_control_latlng = []
		_refresh_tools(); _show_toast("轨道段已确认；可从终点继续铺设，Esc 结束" if curve_warning.is_empty() else curve_warning)
	else:
		map_view.track_start_ref = {}; map_view.track_control_latlng = []
		current_tool = "select"; map_view.tool = current_tool
		_refresh_tools(); _show_toast("轨道段已确认；可撤销，之后可创建运营线路" if curve_warning.is_empty() else curve_warning)
	_after_planning_change("地下轨道已铺设；当前仅为物理轨网")

func _commit_track_preview() -> void:
	if map_view.track_end_ref.is_empty(): return
	var finish: Dictionary = map_view.track_end_ref.duplicate(true)
	confirming_track_preview = true
	var node_id := str(finish.get("nodeId", ""))
	var split_id := str(finish.get("splitEdgeId", ""))
	var hit_type := "track_edge" if not split_id.is_empty() else "track_node" if not node_id.is_empty() else ""
	_handle_track_click(finish.get("latlng", []), hit_type, split_id if not split_id.is_empty() else node_id, str(finish.get("side", "")), float(finish.get("splitT", -1.0)))
	confirming_track_preview = false

func _materialize_track_ref(state: Dictionary, ref: Dictionary, ref_lat: float) -> String:
	var node_id := str(ref.get("nodeId", ""))
	if not node_id.is_empty() and not TrackNetwork.find_node(state, node_id).is_empty(): return node_id
	var split_edge_id := str(ref.get("splitEdgeId", ""))
	if not split_edge_id.is_empty():
		var split_node_id := _split_track_edge(state, split_edge_id, float(ref.get("splitT", 0.5)), ref_lat)
		if not split_node_id.is_empty(): return split_node_id
	var latlng: Array = ref.get("latlng", [0.0, 0.0])
	return str(TrackNetwork.create_node(state, latlng, float(ref.get("depthM", map_view.current_depth_m))).get("id", ""))

func _track_endpoint_tangent(ref: Dictionary, is_start: bool, chord: Vector2, ref_lat: float) -> Vector2:
	var station_id := str(ref.get("stationId", ""))
	if not station_id.is_empty():
		var station := WorldData.find_station(world, station_id)
		if not station.is_empty():
			var outward := WorldData.station_outward(station, str(ref.get("side", "end")))
			return outward if is_start else -outward
	var node_id := str(ref.get("nodeId", ""))
	if node_id.is_empty(): node_id = str(ref.get("splitNodeId", ""))
	var split_edge_id := str(ref.get("splitEdgeId", ""))
	if node_id.is_empty() and not split_edge_id.is_empty():
		var split_edge := _find_link(split_edge_id)
		if not split_edge.is_empty():
			var split_points := TrackNetwork.edge_points(split_edge, world, ref_lat, 32)
			if split_points.size() >= 2:
				var split_index := clampi(roundi(clampf(float(ref.get("splitT", 0.5)), 0.0, 1.0) * float(split_points.size() - 1)), 0, split_points.size() - 2)
				var split_tangent := Geo.local_m(split_points[split_index + 1], ref_lat) - Geo.local_m(split_points[split_index], ref_lat)
				if split_tangent.length_squared() > 0.001:
					split_tangent = split_tangent.normalized()
					if split_tangent.dot(chord) < 0.0: split_tangent = -split_tangent
					return split_tangent
	for edge in TrackNetwork.all_physical_edges(world):
		var ends := TrackNetwork._edge_node_ids(edge, world)
		if ends.size() != 2 or not ends.has(node_id): continue
		var points := TrackNetwork.edge_points(edge, world, ref_lat, 8)
		if points.size() < 2: continue
		var local_points: Array[Vector2] = []
		for point in points: local_points.append(Geo.local_m(point, ref_lat))
		var tangent := local_points[1] - local_points[0] if ends[0] == node_id else local_points[-1] - local_points[-2]
		if tangent.length_squared() > 0.001:
			tangent = tangent.normalized()
			if tangent.dot(chord) < 0.0: tangent = -tangent
			return tangent
	return chord.normalized() if chord.length_squared() > 0.001 else Vector2.RIGHT

func _split_track_edge(state: Dictionary, edge_id: String, split_t: float, ref_lat: float) -> String:
	TrackNetwork.ensure_station_nodes(state)
	var edge: Dictionary = {}
	var is_legacy_link := false
	for candidate in state.get("trackEdges", []):
		if str(candidate.get("id", "")) == edge_id: edge = candidate; break
	if edge.is_empty():
		for legacy in state.get("trackLinks", []):
			if str(legacy.get("id", "")) != edge_id: continue
			var endpoints := TrackNetwork._edge_node_ids(legacy, state)
			if endpoints.size() != 2: return ""
			var converted := {"id": edge_id, "aNodeId": endpoints[0], "bNodeId": endpoints[1], "geometry": "straight" if legacy.get("schematic", false) else "bezier", "routeIds": legacy.get("routeIds", []).duplicate(), "speedLimitKmh": float(legacy.get("speedLimitKmh", -1.0)), "depthM": -15.0}
			if str(converted.geometry) == "bezier":
				var controls := WorldData.link_control_points(legacy, state, ref_lat)
				if controls.size() == 4:
					converted["controlA"] = [(controls[1] - controls[0]).x, (controls[1] - controls[0]).y]
					converted["controlB"] = [(controls[2] - controls[3]).x, (controls[2] - controls[3]).y]
			state.trackLinks = state.trackLinks.filter(func(item: Dictionary): return str(item.get("id", "")) != edge_id)
			state.trackEdges.append(converted)
			edge = converted
			is_legacy_link = true
			break
	if edge.is_empty(): return ""
	var ends := TrackNetwork._edge_node_ids(edge, state)
	if ends.size() != 2: return ""
	var node_a := TrackNetwork.find_node(state, ends[0]); var node_b := TrackNetwork.find_node(state, ends[1])
	if node_a.is_empty() or node_b.is_empty(): return ""
	var p0 := Geo.local_m(node_a.get("latlng", [0, 0]), ref_lat)
	var p3 := Geo.local_m(node_b.get("latlng", [0, 0]), ref_lat)
	var geometry := str(edge.get("geometry", "straight"))
	var p1 := p0.lerp(p3, 1.0 / 3.0)
	var p2 := p0.lerp(p3, 2.0 / 3.0)
	if geometry == "bezier":
		var delta := p3 - p0
		var ca: Array = edge.get("controlA", [delta.x / 3.0, delta.y / 3.0])
		var cb: Array = edge.get("controlB", [-delta.x / 3.0, -delta.y / 3.0])
		p1 = p0 + Vector2(float(ca[0]), float(ca[1]))
		p2 = p3 + Vector2(float(cb[0]), float(cb[1]))
	var distance_fraction := clampf(split_t, 0.02, 0.98)
	var t := _curve_t_at_distance(edge, state, ref_lat, distance_fraction)
	var q0 := p0.lerp(p1, t); var q1 := p1.lerp(p2, t); var q2 := p2.lerp(p3, t)
	var r0 := q0.lerp(q1, t); var r1 := q1.lerp(q2, t)
	var split_point := r0.lerp(r1, t)
	var split_latlng := Geo.from_local(split_point, ref_lat)
	var depth_a := float(node_a.get("depthM", edge.get("depthM", -15.0)))
	var depth_b := float(node_b.get("depthM", edge.get("depthM", -15.0)))
	var split_depth := lerpf(depth_a, depth_b, distance_fraction)
	var split_node := TrackNetwork.create_node(state, split_latlng, split_depth)
	var shared_routes: Array = edge.get("routeIds", []).duplicate()
	if is_legacy_link:
		for route_id in shared_routes:
			var route := WorldData.find_route(state, str(route_id))
			if not route.is_empty(): route.networkBased = true
	var base_id := "split_%d" % Time.get_ticks_usec()
	var left := {"id": base_id + "_a", "aNodeId": ends[0], "bNodeId": split_node.id, "geometry": geometry, "routeIds": shared_routes.duplicate(), "speedLimitKmh": edge.get("speedLimitKmh", -1.0), "depthM": (depth_a + split_depth) * 0.5}
	var right := {"id": base_id + "_b", "aNodeId": split_node.id, "bNodeId": ends[1], "geometry": geometry, "routeIds": shared_routes.duplicate(), "speedLimitKmh": edge.get("speedLimitKmh", -1.0), "depthM": (split_depth + depth_b) * 0.5}
	if geometry == "bezier":
		left["controlA"] = [(q0 - p0).x, (q0 - p0).y]
		left["controlB"] = [(r0 - split_point).x, (r0 - split_point).y]
		right["controlA"] = [(r1 - split_point).x, (r1 - split_point).y]
		right["controlB"] = [(q2 - p3).x, (q2 - p3).y]
	state.trackEdges = state.get("trackEdges", []).filter(func(item: Dictionary): return str(item.get("id", "")) != edge_id)
	state.trackEdges.append(left); state.trackEdges.append(right)
	if is_legacy_link: state.trackLinks = state.trackLinks.filter(func(item: Dictionary): return str(item.get("id", "")) != edge_id)
	_replace_split_edge_in_route_paths(state, edge_id, left, right)
	return str(split_node.get("id", ""))

func _curve_t_at_distance(edge: Dictionary, state: Dictionary, ref_lat: float, distance_fraction: float) -> float:
	if str(edge.get("geometry", "straight")) == "straight": return distance_fraction
	var samples := TrackNetwork.edge_points(edge, state, ref_lat, 256)
	var total := TrackNetwork.edge_length_m(edge, state, ref_lat)
	var target := total * distance_fraction
	var walked := 0.0
	for index in range(samples.size() - 1):
		var length := Geo.local_m(samples[index], ref_lat).distance_to(Geo.local_m(samples[index + 1], ref_lat))
		if walked + length >= target: return (float(index) + (target - walked) / maxf(length, 0.001)) / float(samples.size() - 1)
		walked += length
	return distance_fraction

func _replace_split_edge_in_route_paths(state: Dictionary, old_id: String, left: Dictionary, right: Dictionary) -> void:
	for route in state.get("routes", []):
		for direction in route.get("directions", []):
			if not direction is Dictionary: continue
			var paths: Array = direction.get("edgePathsBySegment", [])
			for segment_index in range(paths.size()):
				var segment: Array = paths[segment_index]
				var rewritten: Array = []
				for item in segment:
					if str(item.get("id", "")) != old_id:
						rewritten.append(item)
						continue
					if bool(item.get("forward", true)):
						rewritten.append({"id": str(left.id), "forward": true}); rewritten.append({"id": str(right.id), "forward": true})
					else:
						rewritten.append({"id": str(right.id), "forward": false}); rewritten.append({"id": str(left.id), "forward": false})
				paths[segment_index] = rewritten
			direction["edgePathsBySegment"] = paths

func _candidate_with_temp_nodes(edge: Dictionary, ref_lat: float) -> Dictionary:
	var temp := {"trackNodes": [], "stations": [], "trackEdges": [], "trackLinks": []}
	var a_id := str(edge.get("aNodeId", "")); var b_id := str(edge.get("bNodeId", ""))
	var a_ll: Array = edge.get("a", [])
	var b_ll: Array = edge.get("b", [])
	if a_id.is_empty(): a_id = "preview_a"; temp.trackNodes.append({"id": a_id, "latlng": a_ll, "depthM": float(map_view.track_start_ref.get("depthM", map_view.current_depth_m))})
	else: temp.trackNodes.append(TrackNetwork.find_node(world, a_id).duplicate(true))
	if b_id.is_empty(): b_id = "preview_b"; temp.trackNodes.append({"id": b_id, "latlng": b_ll, "depthM": float(map_view.track_end_ref.get("depthM", map_view.current_depth_m))})
	else: temp.trackNodes.append(TrackNetwork.find_node(world, b_id).duplicate(true))
	var preview := edge.duplicate(true); preview.aNodeId = a_id; preview.bNodeId = b_id
	temp.trackEdges.append(preview)
	return temp

func _track_crossing_conflict(points_geo: Array, candidate: Dictionary, start_depth: float, end_depth: float, ref_lat: float, ignored_edges: Array[String] = [], check_state: Dictionary = {}) -> String:
	var state: Dictionary = check_state if not check_state.is_empty() else world
	var shared: Dictionary = {}
	for node_id in [str(candidate.get("aNodeId", "")), str(candidate.get("bNodeId", ""))]:
		if not node_id.is_empty(): shared[node_id] = true
	var candidate_local: Array[Vector2] = []
	for point in points_geo: candidate_local.append(Geo.local_m(point, ref_lat))
	var candidate_lengths := _polyline_segment_lengths(candidate_local)
	var candidate_total := _sum_lengths(candidate_lengths)
	for existing in TrackNetwork.all_physical_edges(state):
		if ignored_edges.has(str(existing.get("id", ""))): continue
		var ids := TrackNetwork._edge_node_ids(existing, state)
		if ids.size() != 2: continue
		var old_geo := TrackNetwork.edge_points(existing, state, ref_lat, 24)
		var old_local: Array[Vector2] = []
		for point in old_geo: old_local.append(Geo.local_m(point, ref_lat))
		var old_lengths := _polyline_segment_lengths(old_local)
		var old_total := _sum_lengths(old_lengths)
		var old_node_a := TrackNetwork.find_node(state, ids[0])
		var old_node_b := TrackNetwork.find_node(state, ids[1])
		var depth_a := float(old_node_a.get("depthM", existing.get("depthM", -15.0)))
		var depth_b := float(old_node_b.get("depthM", existing.get("depthM", -15.0)))
		var candidate_travelled := 0.0
		for i in range(candidate_local.size() - 1):
			var candidate_length := candidate_lengths[i] if i < candidate_lengths.size() else 0.0
			var old_travelled := 0.0
			for j in range(old_local.size() - 1):
				var old_length := old_lengths[j] if j < old_lengths.size() else 0.0
				var params := _segment_intersection_parameters(candidate_local[i], candidate_local[i + 1], old_local[j], old_local[j + 1])
				if params.x >= 0.0:
					var crossing := candidate_local[i].lerp(candidate_local[i + 1], float(params.x))
					var is_shared_endpoint := false
					for node_id in ids:
						if not shared.has(node_id): continue
						var shared_node := TrackNetwork.find_node(state, node_id)
						if shared_node.is_empty(): continue
						var shared_position := Geo.local_m(shared_node.get("latlng", [0, 0]), ref_lat)
						if crossing.distance_to(shared_position) <= 1.0: is_shared_endpoint = true; break
					if not is_shared_endpoint:
						var candidate_fraction := (candidate_travelled + candidate_length * float(params.x)) / maxf(candidate_total, 0.001)
						var old_fraction := (old_travelled + old_length * float(params.y)) / maxf(old_total, 0.001)
						var candidate_depth := lerpf(start_depth, end_depth, candidate_fraction)
						var existing_depth := lerpf(depth_a, depth_b, old_fraction)
						if absf(candidate_depth - existing_depth) < 5.0:
							return "交叉点深度差不足 5 米；调整纵断面或明确接轨"
				old_travelled += old_length
			candidate_travelled += candidate_length
	return ""

func _polyline_segment_lengths(points: Array[Vector2]) -> Array[float]:
	var lengths: Array[float] = []
	for index in range(points.size() - 1): lengths.append(points[index].distance_to(points[index + 1]))
	return lengths

func _sum_lengths(lengths: Array[float]) -> float:
	var total := 0.0
	for length in lengths: total += length
	return total

func _segment_intersection_parameters(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var ab := b - a; var cd := d - c
	var divisor := ab.cross(cd)
	if absf(divisor) < 0.001: return Vector2(-1, -1)
	var t := (c - a).cross(cd) / divisor
	var u := (c - a).cross(ab) / divisor
	return Vector2(t, u) if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0 else Vector2(-1, -1)

func _minimum_curve_radius(points_geo: Array, ref_lat: float) -> float:
	var minimum := INF
	for index in range(1, points_geo.size() - 1):
		var a := Geo.local_m(points_geo[index - 1], ref_lat)
		var b := Geo.local_m(points_geo[index], ref_lat)
		var c := Geo.local_m(points_geo[index + 1], ref_lat)
		var ab := a.distance_to(b); var bc := b.distance_to(c); var ac := a.distance_to(c)
		var twice_area := absf((b - a).cross(c - a))
		if twice_area > 0.01: minimum = minf(minimum, ab * bc * ac / (2.0 * twice_area))
	return minimum

func _adjust_track_depth(delta: float) -> void:
	map_view.current_depth_m = clampf(map_view.current_depth_m + delta, -60.0, -5.0)
	map_view.requested_redraw(); _refresh_tools()
	_show_toast("当前施工深度 %.0f 米（游戏参考地面）" % map_view.current_depth_m)

func _change_station_depth(station_id: String, delta: float) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var old_depth := float(station.get("depthM", -15.0))
	var new_depth := clampf(old_depth + delta, -60.0, -5.0)
	if is_equal_approx(old_depth, new_depth): return
	var draft := station.duplicate(true); draft["depthM"] = new_depth
	_apply_station_geometry_draft(station, draft, "调整车站深度", "车站深度已调整为 %.0f 米" % new_depth)

func _confirm_station() -> void:
	if map_view.draft_station.is_empty(): return
	var draft: Dictionary = map_view.draft_station.duplicate(true)
	if _station_overlaps(draft):
		map_view.draft_conflict = true
		map_view.requested_redraw(); _refresh_tools()
		_show_toast("站体与另一座站重叠；移到空位或转向后再确认")
		return
	var route_id := ""
	var created: Dictionary = {}
	var station_count_before: int = world.get("stations", []).size()
	var success := history.execute("新建%s站" % draft.get("name", "车站"), func(state: Dictionary):
		created = WorldData.create_station(state, draft.latlng, float(draft.heading), route_id, str(draft.get("vehicleId", station_vehicle_id)), float(draft.get("depthM", map_view.current_depth_m)))
		created["name"] = str(draft.get("name", "新建车站"))
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

func _next_station_name() -> String:
	var ordinal: int = world.get("stations", []).size() + 1
	var candidate := "新建车站 %d" % ordinal
	while true:
		var exists := false
		for station in world.get("stations", []):
			if str(station.get("name", "")) == candidate:
				exists = true
				break
		if not exists: return candidate
		ordinal += 1
		candidate = "新建车站 %d" % ordinal
	return candidate

func _on_draft_station_changed() -> void:
	map_view.draft_conflict = not map_view.draft_station.is_empty() and _station_overlaps(map_view.draft_station)
	map_view.requested_redraw()
	_refresh_tools()

func _cancel_tool_step() -> void:
	if world.is_empty(): return
	if station_construction_draft.kind == "move_station":
		_clear_station_move_preview()
		map_view._drag_preview.clear()
		map_view.requested_redraw()
	endpoint_choice_candidates.clear(); map_view.endpoint_choice_candidates.clear()
	interaction_state.snap_candidates.clear()
	if not map_view.draft_station.is_empty(): map_view.draft_station = {}; map_view.draft_conflict = false
	elif not map_view.link_start.is_empty(): map_view.link_start = {}
	elif not map_view.track_end_ref.is_empty(): map_view.track_end_ref = {}; map_view.track_preview_conflict = ""; map_view.track_preview_notice = ""
	elif not map_view.track_control_latlng.is_empty(): map_view.track_control_latlng = []
	elif not map_view.track_start_ref.is_empty(): map_view.track_start_ref = {}
	elif current_tool == "line" and not line_draft_stops.is_empty(): line_draft_stops.pop_back(); _update_line_draft_preview()
	elif current_tool == "repair_route_segment":
		_clear_route_repair_draft()
		current_tool = "select"
	else:
		current_tool = "select"
	map_view.tool = current_tool
	map_view.cancel_pointer_interaction()
	map_view.requested_redraw(); _refresh_tools()

func _set_tool(new_tool: String) -> void:
	if new_tool == "connect": new_tool = "track"
	if new_tool == current_tool:
		_cancel_tool_step(); return
	map_view.draft_station = {}; map_view.link_start = {}; map_view.track_start_ref = {}; map_view.track_end_ref = {}; map_view.track_control_latlng = []; map_view.track_preview_conflict = ""; map_view.track_preview_notice = ""
	map_view.cancel_pointer_interaction()
	map_view.clear_curve_preview()
	line_draft_stops.clear()
	line_draft_path_options.clear(); line_draft_path_choices.clear()
	line_draft_segment_index = -1
	_clear_route_repair_draft()
	endpoint_choice_candidates.clear(); map_view.endpoint_choice_candidates.clear()
	map_view.line_draft_points.clear()
	current_tool = new_tool
	map_view.tool = current_tool
	interaction_state.set_tool(current_tool)
	interaction_state.select_object(selected_type, selected_id)
	if current_tool in ["track", "track_curve", "station"]:
		map_view.current_depth_m = -15.0 if current_tool == "station" and map_view.current_depth_m > -5.0 else map_view.current_depth_m
	map_view.requested_redraw(); _refresh_tools()
	match current_tool:
		"station": _show_toast("点地图放置车站；站内轨道自动生成，站端 A／B 可接轨")
		"track": _show_toast("点站端或空地作为起点，再点终点；按 Esc 结束铺轨")
		"track_curve": _show_toast("依次点起点、曲线控制位置和终点；预览通过后确认")
		"line": _show_toast("按实际停站顺序点击已有车站；轨道交叉不会自动成为换乘")
		"curve": _show_toast("拖动线路上的蓝色控制点调整弯曲；里程和时间将同步重算")
		"delete": _show_toast("点击车站拆除；线路和相邻区间一并调整")
		_: _show_toast("选择模式：点击对象查看，拖动车站调整位置")
	if bool(world.get("onboarding", {}).get("active", false)): _refresh_onboarding_card()

func _station_overlaps(candidate: Dictionary) -> bool:
	return _station_overlaps_in(candidate, world.get("stations", []))

func _station_overlaps_in(candidate: Dictionary, stations: Array) -> bool:
	var ref_lat := float(candidate.latlng[0])
	var center := Geo.local_m(candidate.latlng, ref_lat)
	var ang := deg_to_rad(float(candidate.heading))
	var along := Vector2(sin(ang), cos(ang))
	var across := Vector2(along.y, -along.x)
	var poly := _rect_points(center, along, across, float(candidate.lengthM)*.5, float(candidate.widthM)*.5)
	for station in stations:
		if str(station.get("id", "")) == str(candidate.get("id", "")): continue
		var other_center := Geo.local_m(station.latlng, ref_lat)
		var a := deg_to_rad(float(station.get("heading", 90)))
		var other_along := Vector2(sin(a), cos(a))
		var other_across := Vector2(other_along.y, -other_along.x)
		var other_poly := _rect_points(other_center, other_along, other_across, float(station.get("lengthM", 118.8))*.5, float(station.get("widthM", 20.0))*.5)
		if _polygons_intersect(poly, other_poly): return true
	return false

func _station_geometry_issue(candidate: Dictionary) -> String:
	return _station_geometry_issue_in(candidate, world)

func _station_geometry_issue_in(candidate: Dictionary, source_state: Dictionary) -> String:
	return str(_station_preview_analysis(candidate, source_state).get("issue", ""))

func _station_preview_analysis(candidate: Dictionary, source_state: Dictionary) -> Dictionary:
	# A station drag touches only the station, its endpoint nodes, and attached
	# edges. Keep the simulation, demand data, history and unrelated world arrays
	# shared; cloning the complete save on every mouse move caused avoidable stalls.
	var test_state: Dictionary = source_state.duplicate(false)
	var station_id := str(candidate.get("id", ""))
	var test_stations: Array = source_state.get("stations", []).duplicate()
	var test_station: Dictionary = {}
	var found_index := -1
	for index in range(test_stations.size()):
		if str(test_stations[index].get("id", "")) == station_id:
			found_index = index
			break
	test_station = candidate.duplicate(true)
	if found_index >= 0: test_stations[found_index] = test_station
	else: test_stations.append(test_station)
	test_state["stations"] = test_stations
	# Make only this station's endpoint nodes writable. Unrelated nodes and
	# stations remain shared read-only references during pointer-move previews.
	var test_nodes: Array = source_state.get("trackNodes", []).duplicate()
	test_state["trackNodes"] = test_nodes
	var endpoint_refs: Dictionary = test_station.get("endpointNodes", {}).duplicate(true)
	for side in ["start", "end"]:
		var key := "A" if side == "start" else "B"
		var node_id := str(endpoint_refs.get(key, "node_%s_%s" % [station_id, key.to_lower()]))
		var node_index := -1
		for index in range(test_nodes.size()):
			if str(test_nodes[index].get("id", "")) == node_id:
				node_index = index
				break
		var node_value := {"id": node_id, "latlng": WorldData.station_endpoint(test_station, side), "stationId": station_id, "side": side, "depthM": float(test_station.get("depthM", -15.0))}
		if node_index >= 0: test_nodes[node_index] = node_value
		else: test_nodes.append(node_value)
		endpoint_refs[key] = node_id
	test_station["endpointNodes"] = endpoint_refs
	test_state["trackEdges"] = source_state.get("trackEdges", []).duplicate()
	test_state["trackLinks"] = source_state.get("trackLinks", []).duplicate()
	var original_station := WorldData.find_station(source_state, station_id)
	var old_heading := float(original_station.get("heading", candidate.get("heading", 90.0)))
	var new_heading := float(candidate.get("heading", old_heading))
	var old_position: Array = original_station.get("latlng", [])
	var new_position: Array = candidate.get("latlng", old_position)
	var position_changed := old_position.size() >= 2 and new_position.size() >= 2 and _distance_m(old_position, new_position) > 0.05
	var length_changed := not is_equal_approx(float(original_station.get("lengthM", 0.0)), float(candidate.get("lengthM", original_station.get("lengthM", 0.0))))
	if position_changed or length_changed or not is_equal_approx(old_heading, new_heading):
		_align_station_edge_handles(test_state, station_id)
	var preview_edges: Dictionary = {}
	var issue := "站体与另一座车站重叠" if _station_overlaps_in(test_station, test_state.get("stations", [])) else ""
	var attached_nodes: Array = test_station.get("endpointNodes", {}).values()
	var ref_lat := float(WorldData.city(str(source_state.get("cityId", active_city_id))).get("center", [31.23, 121.47])[0])
	for edge in TrackNetwork.all_physical_edges(test_state):
		var ends := TrackNetwork._edge_node_ids(edge, test_state)
		if ends.size() != 2 or not (attached_nodes.has(ends[0]) or attached_nodes.has(ends[1])): continue
		var edge_issue := _physical_edge_geometry_issue(edge, test_state)
		if issue.is_empty() and not edge_issue.is_empty(): issue = edge_issue
		var points_geo := TrackNetwork.edge_points(edge, test_state, ref_lat, 32)
		var local_points: Array[Vector2] = []
		for point in points_geo: local_points.append(Geo.local_m(point, ref_lat))
		preview_edges[str(edge.get("id", ""))] = local_points
	return {"issue": issue, "state": test_state, "edges": preview_edges}

func _align_station_edge_handles(state: Dictionary, station_id: String) -> void:
	var station := WorldData.find_station(state, station_id)
	if station.is_empty(): return
	var ref_lat := float(WorldData.city(str(state.get("cityId", active_city_id))).get("center", [31.23, 121.47])[0])
	for collection_name in ["trackLinks", "trackEdges"]:
		var collection: Array = state.get(collection_name, [])
		for index in range(collection.size()):
			var source_edge: Dictionary = collection[index]
			var is_straight := str(source_edge.get("geometry", "straight")) == "straight"
			var endpoint_data: Array[Dictionary] = []
			if collection_name == "trackLinks" and source_edge.has("a") and not source_edge.has("aNodeId"):
				for side_key in ["a", "b"]:
					var endpoint: Dictionary = source_edge.get(side_key, {})
					if str(endpoint.get("stationId", "")) == station_id:
						endpoint_data.append({"which": side_key, "side": str(endpoint.get("side", "end")), "stationId": station_id})
				if not endpoint_data.is_empty() and is_straight:
					for side_key in ["a", "b"]:
						var endpoint: Dictionary = source_edge.get(side_key, {})
						if str(endpoint.get("stationId", "")).is_empty(): continue
						var already_added := false
						for item in endpoint_data:
							if str(item.which) == side_key: already_added = true
						if not already_added: endpoint_data.append({"which": side_key, "side": str(endpoint.get("side", "end")), "stationId": str(endpoint.get("stationId", ""))})
			else:
				var ends := TrackNetwork._edge_node_ids(source_edge, state)
				if ends.size() == 2:
					for position in range(2):
						var endpoint_node := TrackNetwork.find_node(state, ends[position])
						var side_name := str(endpoint_node.get("side", ""))
						var endpoint_station_id := str(endpoint_node.get("stationId", ""))
						if not side_name.is_empty() and endpoint_station_id == station_id:
							endpoint_data.append({"which": "a" if position == 0 else "b", "side": side_name, "stationId": endpoint_station_id})
					if not endpoint_data.is_empty() and is_straight:
						for position in range(2):
							var endpoint_node := TrackNetwork.find_node(state, ends[position])
							var side_name := str(endpoint_node.get("side", ""))
							var endpoint_station_id := str(endpoint_node.get("stationId", ""))
							var endpoint_key := "a" if position == 0 else "b"
							var already_added := false
							for item in endpoint_data:
								if str(item.which) == endpoint_key: already_added = true
							if not side_name.is_empty() and not endpoint_station_id.is_empty() and not already_added:
								endpoint_data.append({"which": endpoint_key, "side": side_name, "stationId": endpoint_station_id})
			if endpoint_data.is_empty() or bool(source_edge.get("schematic", false)): continue
			var edge: Dictionary = source_edge.duplicate(true)
			var endpoints := TrackNetwork._edge_node_ids(edge, state)
			var chord := Vector2.ZERO
			if endpoints.size() == 2:
				var first := TrackNetwork.find_node(state, endpoints[0])
				var last := TrackNetwork.find_node(state, endpoints[1])
				if not first.is_empty() and not last.is_empty(): chord = Geo.local_m(last.get("latlng", []), ref_lat) - Geo.local_m(first.get("latlng", []), ref_lat)
			for endpoint in endpoint_data:
				var at_a := str(endpoint.which) == "a"
				var key := ("controlA" if at_a else "controlB") if collection_name == "trackEdges" else ("curveA" if at_a else "curveB")
				var handle: Array = edge.get(key, [])
				var length := Vector2(float(handle[0]), float(handle[1])).length() if handle.size() >= 2 else 0.0
				if length < 1.0: length = maxf(20.0, chord.length() * 0.34)
				var endpoint_station := WorldData.find_station(state, str(endpoint.get("stationId", station_id)))
				if endpoint_station.is_empty(): endpoint_station = station
				var vector := WorldData.station_outward(endpoint_station, str(endpoint.side)) * length
				edge[key] = [vector.x, vector.y]
			if is_straight:
				edge["geometry"] = "bezier"
				if endpoint_data.size() == 1:
					var remote_key := ("controlB" if endpoint_data[0].which == "a" else "controlA") if collection_name == "trackEdges" else ("curveB" if endpoint_data[0].which == "a" else "curveA")
					var remote := -chord.normalized() * maxf(20.0, chord.length() * 0.34) if endpoint_data[0].which == "a" else chord.normalized() * maxf(20.0, chord.length() * 0.34)
					edge[remote_key] = [remote.x, remote.y]
			collection[index] = edge
		state[collection_name] = collection

func _apply_station_candidate(state: Dictionary, candidate: Dictionary, candidate_state: Dictionary) -> void:
	var target := WorldData.find_station(state, str(candidate.get("id", "")))
	if target.is_empty(): return
	for key in ["latlng", "heading", "lengthM", "widthM", "depthM", "vehicleId"]:
		if candidate.has(key): target[key] = candidate[key].duplicate(true) if candidate[key] is Array or candidate[key] is Dictionary else candidate[key]
	state["trackNodes"] = candidate_state.get("trackNodes", []).duplicate(true)
	state["trackLinks"] = candidate_state.get("trackLinks", []).duplicate(true)
	state["trackEdges"] = candidate_state.get("trackEdges", []).duplicate(true)
	TrackNetwork.ensure_station_nodes(state)

func _apply_station_geometry_draft(station: Dictionary, candidate: Dictionary, history_label: String, success_message: String) -> void:
	var analysis := _station_preview_analysis(candidate, world)
	var issue := str(analysis.get("issue", ""))
	if not issue.is_empty():
		_show_toast("修改无效：%s；原方案已保留" % issue)
		return
	var station_id := str(station.get("id", ""))
	var station_name := str(station.get("name", "车站"))
	var original_revision := int(world.get("revision", 0))
	var commit := func():
		var fresh := analysis
		if int(world.get("revision", 0)) != original_revision: fresh = _station_preview_analysis(candidate, world)
		var fresh_issue := str(fresh.get("issue", ""))
		if not fresh_issue.is_empty():
			_show_toast("规划已变化，修改未应用：%s" % fresh_issue)
			return
		var changed := history.execute(history_label + " · " + station_name, func(state: Dictionary):
			_apply_station_candidate(state, candidate, fresh.get("state", {}))
		)
		if changed: _after_planning_change(success_message)
	_confirm_service_impact(_routes_for_station(station), "%s「%s」" % [history_label, station_name], commit)

func _physical_edge_geometry_issue(edge: Dictionary, check_state: Dictionary) -> String:
	var ends := TrackNetwork._edge_node_ids(edge, check_state)
	if ends.size() != 2: return "相邻轨道接点缺失"
	var node_a := TrackNetwork.find_node(check_state, ends[0])
	var node_b := TrackNetwork.find_node(check_state, ends[1])
	if node_a.is_empty() or node_b.is_empty(): return "相邻轨道接点缺失"
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var points := TrackNetwork.edge_points(edge, check_state, ref_lat, 40)
	var length := TrackNetwork.edge_length_m(edge, check_state, ref_lat)
	if length <= 0.1: return "相邻轨道长度为零"
	var depth_a := float(node_a.get("depthM", edge.get("depthM", -15.0)))
	var depth_b := float(node_b.get("depthM", edge.get("depthM", -15.0)))
	var grade := absf(depth_b - depth_a) / length
	if grade > 0.035: return "相邻区间纵坡 %.1f‰ 超过 35‰ 游戏预设" % (grade * 1000.0)
	var local_points: Array[Vector2] = []
	for point in points: local_points.append(Geo.local_m(point, ref_lat))
	if str(edge.get("geometry", "straight")) == "bezier":
		var endpoint_checks: Array[Dictionary] = []
		if edge.has("aNodeId"):
			for at_a in [true, false]:
				var node := TrackNetwork.find_node(check_state, str(edge.get("aNodeId" if at_a else "bNodeId", "")))
				if not node.is_empty() and not str(node.get("stationId", "")).is_empty():
					endpoint_checks.append({"station": WorldData.find_station(check_state, str(node.stationId)), "side": str(node.get("side", "")), "atA": at_a})
		else:
			for at_a in [true, false]:
				var ref: Dictionary = edge.get("a" if at_a else "b", {})
				var station := WorldData.find_station(check_state, str(ref.get("stationId", "")))
				if not station.is_empty(): endpoint_checks.append({"station": station, "side": str(ref.get("side", "")), "atA": at_a})
		for endpoint in endpoint_checks:
			var station: Dictionary = endpoint.station
			var side := str(endpoint.side)
			var is_a := bool(endpoint.atA)
			var key := ("controlA" if is_a else "controlB") if edge.has("aNodeId") else ("curveA" if is_a else "curveB")
			var handle: Array = edge.get(key, [])
			if handle.size() < 2: return "车站接头缺少顺接控制点"
			var tangent := Vector2(float(handle[0]), float(handle[1]))
			var outward := WorldData.station_outward(station, side)
			if tangent.length() < 1.0 or outward.length() < 0.5: return "车站接头方向无效"
			if absf(rad_to_deg(tangent.normalized().angle_to(outward.normalized()))) > 5.0:
				return "轨道与「%s」%s端方向不顺接" % [str(station.get("name", "车站")), "A" if side in ["start", "A"] else "B"]
	for first in range(local_points.size() - 1):
		for second in range(first + 2, local_points.size() - 1):
			if first == 0 and second == local_points.size() - 2: continue
			var params := _segment_intersection_parameters(local_points[first], local_points[first + 1], local_points[second], local_points[second + 1])
			if params.x >= 0.0: return "轨道曲线自身交叉"
	var crossing := _track_crossing_conflict(points, edge, depth_a, depth_b, ref_lat, [str(edge.get("id", ""))], check_state)
	return crossing

func _station_required_length(station: Dictionary, requested_vehicle_id: String) -> float:
	var required := maxf(float(station.get("lengthM", 118.8)), float(WorldData.vehicle(requested_vehicle_id).get("trainLengthM", 118.8)))
	for route_id in _routes_for_station(station):
		var route := WorldData.find_route(world, route_id)
		if route.is_empty(): continue
		required = maxf(required, float(WorldData.vehicle(str(route.get("vehicleId", "B-6"))).get("trainLengthM", 118.8)))
	return required

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
	if bool(onboarding.get("active", false)) and int(onboarding.get("step", 0)) == 5:
		var target_route := _onboarding_route_for_pair(false)
		if target_route.is_empty() or str(target_route.get("id", "")) != str(route.get("id", "")):
			onboarding.lastError = "当前线路没有通过任务里的两座车站形成连续轨道。"
			world["onboarding"] = onboarding
			_refresh_onboarding_card()
			_show_issue("任务线路尚未连通；开通其他线路不能完成这一步。")
			return
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var route_path := RoutePathScript.for_route(route, world, ref_lat)
	if not bool(route_path.get("valid", false)):
		var errors: Array = route_path.get("errors", [])
		var reason := str(errors[0]) if not errors.is_empty() else "线路没有形成连续的停站路径"
		_show_issue("阻断：%s。请检查停站顺序和区间连接。" % reason)
		return
	history.execute("开通%s" % route.get("name", "线路"), func(state: Dictionary):
		var r := WorldData.find_route(state, str(route.id))
		RoutePathScript.normalize_station_order(r, state)
		r.open = true
		r.serviceStartMinute = int(state.get("simulation", {}).get("elapsedMinutes", 420))
	)
	_update_tutorial(); _refresh_ui(); _after_planning_change("线路已开通；站距只影響行车时间")

func _delete_station(station_id: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var affected_routes := _routes_for_station(station)
	_confirm_service_impact(affected_routes, "拆除车站「%s」" % station.get("name", "车站"), Callable(self, "_apply_delete_station").bind(station_id))

func _apply_delete_station(station_id: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var station_name := str(station.get("name", "车站"))
	history.execute("删除%s" % station_name, func(state: Dictionary):
		state.stations = state.stations.filter(func(st: Dictionary): return str(st.get("id", "")) != station_id)
		state.trackLinks = state.trackLinks.filter(func(link: Dictionary): return str(link.get("a", {}).get("stationId", "")) != station_id and str(link.get("b", {}).get("stationId", "")) != station_id)
		var node_ids: Array = station.get("endpointNodes", {}).values()
		state.trackEdges = state.get("trackEdges", []).filter(func(edge: Dictionary): return str(edge.get("aNodeId", "")) not in node_ids and str(edge.get("bNodeId", "")) not in node_ids)
		state.trackNodes = state.get("trackNodes", []).filter(func(node: Dictionary): return str(node.get("id", "")) not in node_ids)
		for route in state.routes:
			route.stationOrder = route.get("stationOrder", []).filter(func(id: String): return id != station_id)
			if route.get("directions", []) is Array:
				for direction in route.get("directions", []):
					if direction.get("stationIds", []).has(station_id): route.open = false
		for route in state.routes:
			if station.get("routeIds", []).has(str(route.get("id", ""))): route.open = false
	)
	selected_id = ""; selected_type = ""; _after_planning_change("车站与相邻区间已一并移除")

func _delete_route(route_id: String) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	_confirm_service_impact([route_id], "删除线路「%s」" % route.get("name", "线路"), Callable(self, "_apply_delete_route").bind(route_id))

func _apply_delete_route(route_id: String) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	history.execute("删除线路%s" % route.get("name", ""), func(state: Dictionary):
		for link in state.trackLinks: link["routeIds"] = link.get("routeIds", []).filter(func(id: String): return id != route_id)
		for edge in state.get("trackEdges", []): edge["routeIds"] = edge.get("routeIds", []).filter(func(id: String): return id != route_id)
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
	var required_length := _station_required_length(station, vehicle_id)
	var draft := station.duplicate(true); draft["vehicleId"] = vehicle_id; draft["lengthM"] = required_length
	_apply_station_geometry_draft(station, draft, "更换车站车型", "车型已更换；站体保留所需长度并通过相邻轨道检查")

func _change_route_vehicle(route_id: String, vehicle_id: String) -> void:
	var profile := WorldData.vehicle(vehicle_id); var route := WorldData.find_route(world, route_id)
	if profile.is_empty() or route.is_empty(): return
	var required_by_station: Dictionary = {}
	var test_state: Dictionary = world.duplicate(true)
	for station_id in route.get("stationOrder", []):
		var st := WorldData.find_station(test_state, str(station_id))
		if st.is_empty(): continue
		var required := maxf(float(st.get("lengthM", 118.8)), float(profile.get("trainLengthM", 118.8)))
		var current_station := WorldData.find_station(world, str(station_id))
		for other_route_id in _routes_for_station(current_station):
			if other_route_id == route_id: continue
			var other_route := WorldData.find_route(world, other_route_id)
			if not other_route.is_empty():
				required = maxf(required, float(WorldData.vehicle(str(other_route.get("vehicleId", "B-6"))).get("trainLengthM", 118.8)))
		required_by_station[str(station_id)] = required
		st["lengthM"] = required
	TrackNetwork.ensure_station_nodes(test_state)
	for station_id in required_by_station:
		var candidate := WorldData.find_station(test_state, str(station_id))
		var issue := _station_geometry_issue_in(candidate, test_state)
		if not issue.is_empty():
			_show_toast("车型替换未应用：%s（%s）；原线路与站体保持不变" % [candidate.get("name", "车站"), issue])
			return
	var affected_routes: Array = [route_id]
	for station_id in route.get("stationOrder", []):
		var station := WorldData.find_station(world, str(station_id))
		for shared_route_id in _routes_for_station(station):
			if not affected_routes.has(shared_route_id): affected_routes.append(shared_route_id)
	var change := func():
		history.execute("更换线路车型", func(state: Dictionary):
			var r := WorldData.find_route(state, route_id); r.vehicleId = vehicle_id
			for sid in r.stationOrder:
				var st := WorldData.find_station(state, str(sid)); if not st.is_empty(): st.lengthM = maxf(float(st.get("lengthM", 118.8)), float(profile.get("trainLengthM", 118.8)))
			TrackNetwork.ensure_station_nodes(state)
		)
		_after_planning_change("线路车型已更换；站体至少保留现有长度，并检查共享车站")
	_confirm_service_impact(affected_routes, "更换「%s」的车型" % route.get("name", "线路"), change)

func _routes_for_station(station: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if station.is_empty(): return result
	for route in world.get("routes", []):
		var route_id := str(route.get("id", ""))
		if route_id.is_empty(): continue
		if station.get("routeIds", []).has(route_id) or route.get("stationOrder", []).has(str(station.get("id", ""))):
			if not result.has(route_id): result.append(route_id)
	for edge in TrackNetwork.all_physical_edges(world):
		var node_ids := TrackNetwork._edge_node_ids(edge, world)
		var endpoint_nodes: Array = station.get("endpointNodes", {}).values()
		if node_ids.any(func(node_id: String): return endpoint_nodes.has(node_id)):
			for route_id in edge.get("routeIds", []):
				if not result.has(str(route_id)): result.append(str(route_id))
	return result

func _routes_for_edge(edge_id: String) -> Array[String]:
	var result: Array[String] = []
	for route in world.get("routes", []):
		var route_id := str(route.get("id", ""))
		for direction in route.get("directions", []):
			for segment in direction.get("edgePathsBySegment", []):
				for record in segment:
					if str(record.get("id", "")) == edge_id and not result.has(route_id): result.append(route_id)
	var edge := _find_link(edge_id)
	if not edge.is_empty():
		for route_id in edge.get("routeIds", []):
			if not result.has(str(route_id)): result.append(str(route_id))
	return result

func _live_route_ids(route_ids: Array) -> Array[String]:
	var live: Array[String] = []
	var trips: Array = world.get("simulation", {}).get("trainTrips", [])
	for raw_id in route_ids:
		var route_id := str(raw_id)
		if route_id.is_empty() or live.has(route_id): continue
		var route := WorldData.find_route(world, route_id)
		var has_trip := false
		for trip in trips:
			if str(trip.get("routeId", "")) == route_id:
				has_trip = true
				break
		if (not route.is_empty() and bool(route.get("open", false))) or has_trip:
			live.append(route_id)
	return live

func _confirm_service_impact(route_ids: Array, action_name: String, apply_action: Callable, cancel_action: Callable = Callable()) -> void:
	var live_ids := _live_route_ids(route_ids)
	if live_ids.is_empty():
		if apply_action.is_valid(): apply_action.call()
		return
	var names: Array[String] = []
	var train_counts: Dictionary = {}
	for route_id in live_ids:
		var route := WorldData.find_route(world, route_id)
		if not route.is_empty(): names.append("• %s" % str(route.get("name", "线路")))
		train_counts[route_id] = 0
	for trip in world.get("simulation", {}).get("trainTrips", []):
		var route_id := str(trip.get("routeId", ""))
		if train_counts.has(route_id): train_counts[route_id] = int(train_counts[route_id]) + 1
	var active_train_count := 0
	for count in train_counts.values(): active_train_count += int(count)
	var detail := "\n".join(names)
	var text := "%s 会影响正在运营的线路：\n%s\n\n当前有 %d 趟列车在运行。继续后会暂停模拟，重算受影响乘客路径；已完成出行与游戏时间会保留。此操作可以撤销。" % [action_name, detail, active_train_count]
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认影响运营"
	dialog.dialog_text = text
	add_child(dialog)
	dialog.get_ok_button().text = "暂停并继续"
	dialog.get_cancel_button().text = "取消操作"
	dialog.confirmed.connect(func():
		dialog.queue_free()
		if apply_action.is_valid(): apply_action.call()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
		if cancel_action.is_valid(): cancel_action.call()
		if is_instance_valid(map_view): map_view.requested_redraw()
		_refresh_ui()
	)
	dialog.popup_centered(Vector2i(520, 320))

func _station_vehicle_conflict(station: Dictionary, vehicle_id: String) -> bool:
	var draft := station.duplicate(true)
	draft["lengthM"] = _station_required_length(station, vehicle_id)
	return not _station_geometry_issue(draft).is_empty()

func _change_headway(route_id: String, value: int) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty() or int(route.get("headway", 3)) == value: return
	var change := func():
		history.execute("调整发车间隔", func(state: Dictionary): WorldData.find_route(state, route_id).headway = value)
		SimulationEngineScript.reschedule_route(world, route_id)
		_after_planning_change("发车间隔已更新")
	_confirm_service_impact([route_id], "调整「%s」的发车间隔" % route.get("name", "线路"), change)

func _rotate_station(station_id: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	_set_station_heading(station_id, fposmod(float(station.get("heading", 90.0)) + 15.0, 360.0))

func _set_station_heading(station_id: String, degrees: float) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var heading := fposmod(degrees, 360.0)
	if is_equal_approx(heading, float(station.get("heading", 90.0))): return
	var draft := station.duplicate(true); draft["heading"] = heading
	_apply_station_geometry_draft(station, draft, "旋转车站", "车站方向已调整")

func _on_station_drag_preview(station_id: String, latlng: Array) -> void:
	map_view._station_drag_preview_update(station_id, latlng)
	var now_usec := Time.get_ticks_usec()
	if _station_preview_last_usec > 0 and now_usec - _station_preview_last_usec < 33333: return
	_station_preview_last_usec = now_usec
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var candidate: Dictionary = station.duplicate(true)
	candidate["latlng"] = latlng.duplicate()
	var analysis := _station_preview_analysis(candidate, world)
	var route_ids := _routes_for_station(station)
	station_construction_draft.begin("move_station", station_id, int(world.get("revision", 0)), candidate)
	station_construction_draft.update(candidate, analysis.get("edges", {}), str(analysis.get("issue", "")), route_ids)
	interaction_state.draft = station_construction_draft
	interaction_state.phase = "preview"
	interaction_state.error_message = station_construction_draft.issue
	map_view.station_preview_edges = analysis.get("edges", {})
	map_view.station_preview_issue = station_construction_draft.issue
	map_view.draft_conflict = not station_construction_draft.valid
	map_view.requested_redraw()
	if is_instance_valid(tool_instruction_label):
		tool_instruction_label.text = "移站预览：相邻轨道已同步检查。" + (" 冲突：%s" % station_construction_draft.issue if not station_construction_draft.valid else " 松开确认，Esc 可取消。")

func _on_station_drag_finished(station_id: String, latlng: Array) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty():
		_clear_station_move_preview()
		return
	if _distance_m(station.get("latlng", []), latlng) < 0.5:
		_clear_station_move_preview()
		return
	var draft: Dictionary = station.duplicate(true); draft["latlng"] = latlng.duplicate()
	var analysis := _station_preview_analysis(draft, world)
	var issue := str(analysis.get("issue", ""))
	if not issue.is_empty():
		_show_toast("位置无效：%s；已恢复原位" % issue)
		_clear_station_move_preview()
		map_view.requested_redraw(); return
	var base_revision := int(world.get("revision", 0))
	var move_station := func():
		var current_analysis := analysis
		if int(world.get("revision", 0)) != base_revision: current_analysis = _station_preview_analysis(draft, world)
		if not str(current_analysis.get("issue", "")).is_empty():
			_show_toast("规划已变化，移站预览需要重新检查：%s" % current_analysis.get("issue", ""))
			_clear_station_move_preview()
			return
		var changed := history.execute("移动%s" % station.get("name", "车站"), func(state: Dictionary):
			_apply_station_candidate(state, draft, current_analysis.get("state", {}))
		)
		_clear_station_move_preview()
		if changed:
			if current_tool == "move_station": current_tool = "select"; map_view.tool = current_tool
			_after_planning_change("站点已移动；相邻轨道已检查并重新计算")
	var cancel_move := func():
		_clear_station_move_preview()
		if is_instance_valid(map_view): map_view.requested_redraw()
	_confirm_service_impact(_routes_for_station(station), "移动车站「%s」" % station.get("name", "车站"), move_station, cancel_move)

func _clear_station_move_preview() -> void:
	station_construction_draft.clear()
	interaction_state.draft.clear()
	interaction_state.phase = "active" if current_tool != "select" else "idle"
	interaction_state.error_message = ""
	map_view.station_preview_edges.clear()
	map_view.station_preview_issue = ""
	map_view.draft_conflict = false

func _on_curve_control_finished(link_id: String, control_name: String, offset_m: Array) -> void:
	var link := _find_link(link_id)
	if link.is_empty(): return
	var key := ("controlA" if control_name == "curveA" else "controlB") if link.has("aNodeId") else ("curveA" if control_name == "curveA" else "curveB")
	if JSON.stringify(link.get(key, [])) == JSON.stringify(offset_m): return
	_on_curve_control_previewed(link_id, control_name, offset_m, true)
	var issue := map_view.curve_preview_issue
	if not issue.is_empty():
		_show_toast("曲线修改无效：%s；已保留原曲线" % issue)
		_clear_curve_edit_draft()
		return
	var expected_revision := int(world.get("revision", 0))
	var committed_offset := offset_m.duplicate(true)
	var change := func():
		if int(world.get("revision", 0)) != expected_revision:
			_on_curve_control_previewed(link_id, control_name, committed_offset, true)
			var refreshed_issue := map_view.curve_preview_issue
			_clear_curve_edit_draft()
			_show_issue("规划在确认期间发生变化，曲线没有提交。请重新调整并确认。%s" % (" " + refreshed_issue if not refreshed_issue.is_empty() else ""))
			return
		history.execute("调整轨道曲线", func(state: Dictionary):
			var collection: Array = state.trackEdges if link.has("aNodeId") else state.trackLinks
			for item in collection:
				if str(item.get("id", "")) == link_id:
					item[key] = committed_offset.duplicate(true)
					break
		)
		_clear_curve_edit_draft()
		_after_planning_change("轨道曲线已更新；线路里程与乘客时间随之重算")
	var cancel := func():
		_clear_curve_edit_draft()
		_show_toast("已取消曲线修改；原线路保持不变")
	_confirm_service_impact(_routes_for_edge(link_id), "调整运营轨道曲线", change, cancel)

func _clear_curve_edit_draft() -> void:
	map_view.clear_curve_preview()
	station_construction_draft.clear()
	interaction_state.draft.clear()
	interaction_state.error_message = ""
	_refresh_tools()

func _on_curve_control_previewed(link_id: String, control_name: String, offset_m: Array, force: bool = false) -> void:
	var now := Time.get_ticks_usec()
	if not force and now - _curve_preview_last_usec < 33333: return
	_curve_preview_last_usec = now
	var edge := _find_link(link_id)
	if edge.is_empty(): return
	var key := ("controlA" if control_name == "curveA" else "controlB") if edge.has("aNodeId") else ("curveA" if control_name == "curveA" else "curveB")
	var preview_state: Dictionary = world.duplicate(false)
	preview_state["trackLinks"] = world.get("trackLinks", []).duplicate()
	preview_state["trackEdges"] = world.get("trackEdges", []).duplicate()
	var preview_edge: Dictionary = {}
	var collection: Array = preview_state.trackEdges if edge.has("aNodeId") else preview_state.trackLinks
	for index in range(collection.size()):
		if str(collection[index].get("id", "")) == link_id:
			preview_edge = collection[index].duplicate(true)
			preview_edge[key] = offset_m.duplicate(true)
			collection[index] = preview_edge
			break
	var issue := _physical_edge_geometry_issue(preview_edge, preview_state) if not preview_edge.is_empty() else "找不到待调整区间"
	map_view.curve_preview_issue = issue
	station_construction_draft.begin("curve", link_id, int(world.get("revision", 0)), {"control": control_name, "offset": offset_m})
	station_construction_draft.update({"control": control_name, "offset": offset_m}, {link_id: TrackNetwork.edge_points(preview_edge, preview_state, float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0]), 32)}, issue, _routes_for_edge(link_id))
	interaction_state.draft = station_construction_draft
	interaction_state.phase = "preview"
	interaction_state.error_message = issue
	if is_instance_valid(tool_instruction_label): tool_instruction_label.text = "曲线预览：%s" % (issue if not issue.is_empty() else "松开确认；Esc 取消")

func _select_object(kind: String, object_id: String) -> void:
	selected_type = kind; selected_id = object_id
	if kind == "route": active_route_id = object_id
	_right_requested = true
	if _layout_narrow: _left_requested = false
	interaction_state.select_object(kind, object_id)
	_update_responsive_layout()
	map_view.active_route_id = active_route_id
	map_view.selected_type = kind; map_view.selected_id = object_id; map_view.requested_redraw()
	_refresh_ui()

func _find_link(link_id: String) -> Dictionary:
	for link in TrackNetwork.all_physical_edges(world):
		if str(link.get("id", "")) == link_id: return link
	return {}

func _delete_link(link_id: String) -> void:
	var link := _find_link(link_id)
	if link.is_empty(): return
	_confirm_service_impact(_routes_for_edge(link_id), "拆除轨道区间", Callable(self, "_apply_delete_link").bind(link_id))

func _apply_delete_link(link_id: String) -> void:
	var link := _find_link(link_id)
	if link.is_empty(): return
	var affected_names: Array[String] = []
	var affected_routes := _routes_for_edge(link_id)
	for route_id in affected_routes:
		var route := WorldData.find_route(world, route_id)
		if not route.is_empty(): affected_names.append(str(route.get("name", "线路")))
	history.execute("删除轨道区间", func(state: Dictionary):
		state.trackLinks = state.get("trackLinks", []).filter(func(item: Dictionary): return str(item.get("id", "")) != link_id)
		state.trackEdges = state.get("trackEdges", []).filter(func(item: Dictionary): return str(item.get("id", "")) != link_id)
		for route in state.get("routes", []):
			var route_affected := false
			for direction in route.get("directions", []):
				var paths: Array = direction.get("edgePathsBySegment", [])
				for segment_index in range(paths.size()):
					var segment: Array = paths[segment_index] if paths[segment_index] is Array else []
					var uses_deleted_edge := false
					for reference in segment:
						if reference is Dictionary and str(reference.get("id", "")) == link_id:
							uses_deleted_edge = true
							break
					if uses_deleted_edge:
						paths[segment_index] = []
						route_affected = true
				direction["edgePathsBySegment"] = paths
			if route_affected: route["open"] = false
	)
	selected_type = ""
	selected_id = ""
	_after_planning_change("区间已删除%s；受影响线路已暂停，操作可撤销" % (" · " + "、".join(affected_names) if not affected_names.is_empty() else ""))

func _do_undo() -> void:
	if world.is_empty(): return
	world.simulation.paused = true
	var previous_type := selected_type
	var previous_id := selected_id
	var label := history.undo()
	if label.is_empty(): _show_toast("没有可撤销的规划操作"); return
	if _selection_still_exists(previous_type, previous_id):
		selected_type = previous_type; selected_id = previous_id
	else:
		selected_type = ""; selected_id = ""
	map_view.selected_type = selected_type; map_view.selected_id = selected_id
	interaction_state.select_object(selected_type, selected_id)
	map_view.set_world(world); _update_tutorial(); _autosave(); _refresh_ui(); _show_toast("已撤销：%s · 游戏时钟保持不变" % label)

func _selection_still_exists(kind: String, object_id: String) -> bool:
	if object_id.is_empty(): return false
	match kind:
		"station": return not WorldData.find_station(world, object_id).is_empty()
		"route": return not WorldData.find_route(world, object_id).is_empty()
		"link":
			for edge in TrackNetwork.all_physical_edges(world):
				if str(edge.get("id", "")) == object_id: return true
			return false
		"demand": return not _find_demand(object_id).is_empty()
	return false

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
	save_dirty = true
	_update_topbar()
	if _flow_cache_revision != int(world.get("revision", 0)):
		_rebuild_flow_cache()
	var minute_of_day := posmod(int(world.simulation.get("elapsedMinutes", world.simulation.get("minute", 420))) + 1, 1440)
	var hour := minute_of_day / 60
	var peak := 0.55
	if hour >= 7 and hour < 10: peak = 2.1
	elif hour >= 16 and hour < 19: peak = 1.8
	elif hour >= 11 and hour < 14: peak = 1.1
	var minute_flows: Array[Dictionary] = []
	for flow in _flow_cache:
		var minute_flow := flow.duplicate(false)
		minute_flow["peakMultiplier"] = _flow_peak_multiplier(flow, hour, peak)
		minute_flows.append(minute_flow)
	var onboarding: Dictionary = world.get("onboarding", {})
	var observe_target := bool(onboarding.get("active", false)) and bool(onboarding.get("observationStarted", false))
	var target_flow_id := "%s>%s" % [str(onboarding.get("originId", "")), str(onboarding.get("destinationId", ""))]
	var target_flow := _onboarding_flow() if observe_target else {}
	var sim_result := SimulationEngineScript.step_one_minute(world, minute_flows, 1.0)
	var goals_changed := NeighborhoodGoalsScript.update(world, _flow_cache, int(world.simulation.get("elapsedMinutes", world.simulation.minute)))
	if goals_changed: _refresh_left_panel()
	if observe_target and bool(target_flow.get("valid", false)):
		onboarding.observedTargetArrivals = int(onboarding.get("observedTargetArrivals", 0)) + int(sim_result.get("arrivalsByFlow", {}).get(target_flow_id, 0))
		onboarding.observedTargetServed = int(onboarding.get("observedTargetServed", 0)) + int(sim_result.get("completedByFlow", {}).get(target_flow_id, 0))
		world["onboarding"] = onboarding
	_update_tutorial()

func _network_summary() -> Dictionary:
	return {"stations": world.get("stations", []).size(), "links": world.get("trackLinks", []).size() + world.get("trackEdges", []).size(), "routes": world.get("routes", []).size()}

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
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var network := JourneyModelScript.build_network(world, ref_lat)
	for origin in housing:
		for destination in demands:
			var target_type := str(destination.get("type", ""))
			if not destinations.has(target_type): continue
			if str(origin.get("id", "")) == str(destination.get("id", "")): continue
			var distance := _distance_m(origin.get("latlng", [0,0]), destination.get("latlng", [0,0]))
			if distance > 40000.0: continue
			var daily := minf(float(origin.get("gameDemand", {}).get("base", 0)), float(destination.get("gameDemand", {}).get("base", 0))) * float(destinations[target_type])
			_append_flow_pair(origin, destination, daily, network, ref_lat)
			_append_flow_pair(destination, origin, daily * 0.85, network, ref_lat)
	_flow_cache_revision = int(world.get("revision", 0))
	var canceled_trips := SimulationEngineScript.reconcile_train_trips(world)
	SimulationEngineScript.reconcile_passengers(world, _flow_cache)
	if canceled_trips > 0:
		world.simulation.paused = true
		_show_issue("%d 趟受影响列车已停在最近的有效车站；车上乘客将从该站重新寻路。" % canceled_trips)

func _append_flow_pair(origin: Dictionary, destination: Dictionary, people_per_day: float, network: Dictionary, ref_lat: float) -> void:
	var journey := JourneyModelScript.find_journey(origin, destination, world, network, ref_lat)
	_flow_cache.append({"id": "%s>%s" % [origin.get("id", ""), destination.get("id", "")], "fromId": origin.get("id", ""), "toId": destination.get("id", ""), "from": origin.get("name", ""), "to": destination.get("name", ""), "fromType": origin.get("type", ""), "toType": destination.get("type", ""), "originLatLng": origin.get("latlng", []).duplicate(), "destinationLatLng": destination.get("latlng", []).duplicate(), "peoplePerDay": people_per_day, "valid": bool(journey.get("valid", false)), "routeId": str(journey.get("routeId", "")), "routeIds": journey.get("routeIds", []), "originStationId": str(journey.get("originStationId", "")), "destinationStationId": str(journey.get("destinationStationId", "")), "tripMinutes": float(journey.get("totalMinutes", 0.0)), "journey": journey})

func _flow_peak_multiplier(flow: Dictionary, hour: int, fallback: float) -> float:
	var from_type := str(flow.get("fromType", ""))
	var to_type := str(flow.get("toType", ""))
	if from_type == "housing" and to_type in ["employment", "education"]:
		if hour >= 7 and hour < 10: return 2.1
		if hour >= 16 and hour < 19: return 0.55
		return 0.65
	if from_type in ["employment", "education"] and to_type == "housing":
		if hour >= 16 and hour < 19: return 2.0
		if hour >= 7 and hour < 10: return 0.45
		return 0.7
	if to_type == "commerce" or from_type == "commerce":
		if hour >= 11 and hour < 14: return 1.5
		if hour >= 17 and hour < 21: return 1.65
		return 0.8
	if to_type == "hub" or from_type == "hub":
		if hour >= 7 and hour < 10 or hour >= 16 and hour < 19: return 1.6
		return 0.75
	if to_type == "health" or from_type == "health": return 0.75
	return fallback

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

func _find_cached_flow(flow_id: String) -> Dictionary:
	for flow in _flow_cache:
		if str(flow.get("id", "")) == flow_id: return flow
	return {}

func _focus_route(route_id: String) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	active_route_id = route_id
	_select_object("route", route_id)
	var station_id := str(route.get("stationOrder", [""])[0]) if not route.get("stationOrder", []).is_empty() else ""
	if station_id.is_empty():
		for link in world.get("trackLinks", []):
			if link.get("routeIds", []).has(route_id):
				station_id = str(link.get("a", {}).get("stationId", ""))
				break
	var station := WorldData.find_station(world, station_id)
	if not station.is_empty(): map_view.center_on(station.get("latlng", [0, 0]), maxi(map_view.current_zoom, 14))

func _focus_track_link(link_id: String) -> void:
	var edge := _find_link(link_id)
	if edge.is_empty(): return
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var points := TrackNetwork.edge_points(edge, world, ref_lat, 24)
	if points.size() < 2: return
	var a: Array = points[0]; var b: Array = points[-1]
	var center := [(float(a[0]) + float(b[0])) * 0.5, (float(a[1]) + float(b[1])) * 0.5]
	_select_object("link", link_id)
	map_view.center_on(center, maxi(map_view.current_zoom, 14))

func _focus_flow(flow: Dictionary) -> void:
	if flow.is_empty(): return
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
	map_view.show_road_names = UiPreferencesScript.load_road_names()
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
		var focus_points: Array = [origin.get("latlng", []), destination.get("latlng", [])]
		for station_id_key in ["originStationId", "destinationStationId"]:
			var station := WorldData.find_station(world, str(onboarding.get(station_id_key, "")))
			if station.is_empty(): continue
			focus_points.append(station.get("latlng", []))
			focus_points.append(WorldData.station_endpoint(station, "start"))
			focus_points.append(WorldData.station_endpoint(station, "end"))
		_focus_map_points_around_guide(focus_points)
	map_view.requested_redraw()

func _focus_map_points_around_guide(points: Array) -> void:
	if points.is_empty() or map_view.size.x <= 1.0 or map_view.size.y <= 1.0: return
	var min_pixel := Vector2(INF, INF)
	var max_pixel := Vector2(-INF, -INF)
	for point in points:
		if not point is Array or point.size() < 2: continue
		for zoom in [19]:
			var projected := Geo.project(point, zoom)
			min_pixel.x = minf(min_pixel.x, projected.x); min_pixel.y = minf(min_pixel.y, projected.y)
			max_pixel.x = maxf(max_pixel.x, projected.x); max_pixel.y = maxf(max_pixel.y, projected.y)
	if not is_finite(min_pixel.x) or not is_finite(max_pixel.x): return
	var zoom := 19
	var card_width := minf(390.0 * _ui_scale, map_view.size.x * 0.44)
	var available_width := maxf(240.0, map_view.size.x - card_width - 56.0 * _ui_scale)
	var available_height := maxf(240.0, map_view.size.y - 160.0 * _ui_scale)
	var extent := max_pixel - min_pixel
	while zoom > 3:
		var zoom_extent := extent / pow(2.0, float(19 - zoom))
		if zoom_extent.x <= available_width * 0.78 and zoom_extent.y <= available_height * 0.78: break
		zoom -= 1
	var midpoint := (min_pixel + max_pixel) * 0.5 / pow(2.0, float(19 - zoom))
	var desired_screen := Vector2(minf(map_view.size.x * 0.62, map_view.size.x - 110.0 * _ui_scale), map_view.size.y * 0.60)
	var desired_camera_pixel := midpoint - (desired_screen - map_view.size * 0.5)
	map_view.center_on(Geo.unproject(desired_camera_pixel, zoom), zoom)

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
	var headings := ["先看懂这组出行", "第一站：覆盖 A 起点", "第二站：覆盖 B 终点", "铺设两站之间的轨道", "安排这段轨道的运营线路", "检查并开通任务线路", "运行一小段时间", "这一组街区需求已接入"]
	box.add_child(_label("街区规划引导   %s" % ("已完成" if step >= 7 else "第 %d / 7 步" % (step + 1)), 13, TEAL, true))
	box.add_child(_label(headings[clampi(step, 0, headings.size() - 1)], 19, TEXT, true))
	var description := ""
	var condition := ""
	match step:
		0:
			description = "A 是出发点，B 是目的地。"
			condition = "橙色虚线只表示出行方向。"
		1:
			description = "在 A 附近放置一座车站，可以调整位置和朝向。"
			condition = "站体中心需在 A 起点 800 米内，确认后才算完成。"
		2:
			description = "在 B 附近放置第二座车站，再调整朝向以便接轨。"
			condition = "需要一座不同的车站覆盖 B 终点。"
		3:
			description = "从一座车站的端点开始，铺轨并接到另一座车站。"
			condition = "地图上必须存在能从 A 站到 B 站的连续物理轨道。"
		4:
			description = "按顺序点击任务两站，预览并确认运营线路。"
			condition = "任务线路必须明确包含 A 站与 B 站，且两站之间有连续轨道。"
		5:
			description = "检查停站顺序和车型，然后开通线路。"
			condition = "开通的必须是刚才建立并服务任务两站的线路。"
		6:
			var flow := _onboarding_flow()
			var arrived := int(onboarding.get("observedTargetArrivals", 0))
			var served := int(onboarding.get("observedTargetServed", 0))
			description = "播放模拟，观察这组出行是否真正到达。" if not bool(onboarding.get("observationStarted", false)) else "目标需求进入 %d 人，已到达 %d 人。" % [arrived, served]
			condition = "结果来自聚合模拟，不是逐人动画。"
			if bool(flow.get("valid", false)):
				condition += " 当前估算：约 %s 人次/日，出行 %.1f 分钟。" % [_number(int(round(float(flow.get("peoplePerDay", 0.0))))), float(flow.get("tripMinutes", 0.0))]
		7:
			var complete_flow := _onboarding_flow()
			var observed_arrivals := int(onboarding.get("observedTargetArrivals", 0))
			var observed_completed := int(onboarding.get("observedTargetServed", 0))
			description = "本次观察：进入需求 %d 人，实际完成出行 %d 人。" % [observed_arrivals, observed_completed]
			condition = "游戏模型估算：约 %s 人次/日，出行 %.1f 分钟。可继续扩建当前街区。" % [_number(int(round(float(complete_flow.get("peoplePerDay", 0.0))))), float(complete_flow.get("tripMinutes", 0.0))]
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
	var has_station_draft := current_tool == "station" and not map_view.draft_station.is_empty()
	var has_track_preview := current_tool in ["track", "track_curve"] and not map_view.track_end_ref.is_empty()
	var has_line_draft := current_tool == "line" and line_draft_stops.size() >= 2
	var primary_label := "开始规划" if step == 0 else ("确认第一站" if has_station_draft else "定位 A 起点" if current_tool == "station" else "进入建站工具") if step == 1 else ("确认第二站" if has_station_draft else "定位 B 终点" if current_tool == "station" else "进入建站工具") if step == 2 else "启用铺轨工具" if step == 3 and current_tool not in ["track", "track_curve"] else "确认轨道段" if step == 3 and has_track_preview else "选择终点端" if step == 3 and not map_view.track_start_ref.is_empty() else "点击起点端" if step == 3 else "开始安排运营线路" if step == 4 and current_tool != "line" else "确认线路走向" if step == 4 and has_line_draft else "按顺序选择停站" if step == 4 else "检查并开通任务线路" if step == 5 else "播放并观察" if step == 6 and not bool(onboarding.get("observationStarted", false)) else "继续扩建这个街区" if step == 7 else "正在运行 · 等待这组需求的模拟结果"
	var primary := _button(primary_label, Color("#eafff8"), Color("#17644f"), 16)
	primary.custom_minimum_size.y = 44.0 * _ui_scale
	primary.disabled = step in [1, 2] and has_station_draft and map_view.draft_conflict or step == 3 and has_track_preview and not map_view.track_preview_conflict.is_empty() or step == 6 and bool(onboarding.get("observationStarted", false))
	if step in [1, 2] and has_station_draft: primary.pressed.connect(_confirm_station)
	elif step == 3 and has_track_preview: primary.pressed.connect(_commit_track_preview)
	elif step == 4 and has_line_draft: primary.pressed.connect(_confirm_operating_line)
	else: primary.pressed.connect(_onboarding_primary_action)
	box.add_child(primary)
	var more := MenuButton.new()
	more.text = "为什么这样做？ ▾" if not _onboarding_reason_expanded else "更多选项 ▾"
	more.custom_minimum_size.y = roundi(40.0 * _ui_scale)
	more.add_theme_font_size_override("font_size", roundi(16.0 * _ui_scale))
	more.add_theme_color_override("font_color", MUTED)
	more.add_theme_stylebox_override("normal", _style(PANEL_LIGHT, BORDER, 8, 1))
	more.add_theme_stylebox_override("hover", _style(PANEL_LIGHT.lightened(0.1), BORDER, 8, 1))
	var menu := more.get_popup()
	menu.add_item("为什么这样做？", 0)
	menu.add_separator()
	menu.add_item("跳过引导", 1)
	menu.add_item("查看全城", 2)
	menu.add_item("返回任务位置", 3)
	menu.set_item_disabled(menu.get_item_index(3), not bool(onboarding.get("viewingCity", false)))
	menu.id_pressed.connect(func(action: int):
		if action == 0:
			_onboarding_reason_expanded = not _onboarding_reason_expanded
			_refresh_onboarding_card()
		elif action == 1:
			_end_onboarding(true)
		elif action == 2:
			_show_onboarding_city()
		elif action == 3:
			_return_to_onboarding_mission()
	)
	box.add_child(more)
	if _onboarding_reason_expanded:
		var reason := _label(str(mission.get("reason", "")) + " 出行虚线表示需求方向，不是建议照着修建的轨道。", 13, MUTED)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(reason)

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
			if current_tool not in ["track", "track_curve"]: _set_tool("track")
			else: _show_toast("从任务起点站端铺到终点站端；每段确认后按 Esc 结束")
		4:
			if current_tool != "line": _set_tool("line")
			else: _show_toast("依次点选任务两站和需要停靠的中间站，再确认线路走向")
		5:
			var route := _onboarding_route_for_pair(false)
			if route.is_empty():
				onboarding.lastError = "任务两站之间还没有连续轨道。"
				_refresh_onboarding_card()
				return
			active_route_id = str(route.get("id", ""))
			selected_type = "route"; selected_id = active_route_id
			_open_route()
		6:
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
		7:
			_end_onboarding(false)

func _set_onboarding_step(step: int) -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	onboarding.step = clampi(step, 0, 7)
	onboarding.lastError = ""
	world["onboarding"] = onboarding
	# The first track-building step must show both confirmed stations and their
	# endpoints together. A normal refresh leaves the camera centered on B,
	# which makes the tutorial impossible to follow without manually panning.
	_sync_onboarding_map(step == 3)
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
		var path := RoutePathScript.for_route(route, world, float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0]))
		if not bool(path.get("valid", false)): continue
		for direction in path.get("directions", []):
			var ids: Array = direction.get("stationIds", [])
			if ids.has(start_id) and ids.has(end_id): return route
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
	if bool(route.get("networkBased", false)):
		var path := RoutePathScript.for_route(route, world, float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0]))
		if bool(path.get("valid", false)) and not path.get("directions", []).is_empty(): return float(path.directions[0].get("distanceM", 0.0)) / 1000.0
	var total := 0.0
	for link in world.get("trackLinks", []):
		if not link.get("routeIds", []).has(str(route.get("id", ""))): continue
		var a := WorldData.find_station(world, str(link.get("a", {}).get("stationId", "")))
		var b := WorldData.find_station(world, str(link.get("b", {}).get("stationId", "")))
		if not a.is_empty() and not b.is_empty():
			total += WorldData.track_length_m(link, world, float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0]))
	return total / 1000.0

func _begin_route_segment_repair(route_id: String, direction_id: String, segment_index: int) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	var direction: Dictionary = {}
	for candidate in route.get("directions", []):
		if str(candidate.get("id", "")) == direction_id:
			direction = candidate
			break
	var stops: Array = direction.get("stationIds", [])
	if segment_index < 0 or segment_index + 1 >= stops.size():
		_show_issue("这个停站区间已不存在，请重新打开线路详情。")
		return
	repair_route_id = route_id
	repair_direction_id = direction_id
	repair_segment_index = segment_index
	repair_from_station_id = str(stops[segment_index])
	repair_to_station_id = str(stops[segment_index + 1])
	line_draft_stops = [repair_from_station_id, repair_to_station_id]
	repair_plan_revision = int(world.get("revision", 0))
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	repair_path_options = TrackNetwork.station_path_options(repair_from_station_id, repair_to_station_id, world, ref_lat)
	repair_path_choice = 0
	selected_type = "route"
	selected_id = route_id
	active_route_id = route_id
	current_tool = "repair_route_segment"
	map_view.tool = current_tool
	map_view.link_start = {}
	interaction_state.set_tool(current_tool)
	interaction_state.select_object("route", route_id)
	var from_station := WorldData.find_station(world, repair_from_station_id)
	var to_station := WorldData.find_station(world, repair_to_station_id)
	map_view.center_on([(float(from_station.latlng[0]) + float(to_station.latlng[0])) * 0.5, (float(from_station.latlng[1]) + float(to_station.latlng[1])) * 0.5], 14)
	_update_repair_preview()
	_refresh_ui()
	if repair_path_options.is_empty():
		_show_toast("这两站之间暂时没有连续轨道；先铺轨，再从线路详情修复")

func _update_repair_preview() -> void:
	map_view.line_draft_points.clear()
	if repair_path_options.is_empty() or repair_path_choice >= repair_path_options.size():
		map_view.requested_redraw()
		return
	var option: Dictionary = repair_path_options[repair_path_choice]
	for point in option.get("points", []):
		map_view.line_draft_points.append(point.duplicate())
	map_view.requested_redraw()

func _confirm_route_segment_repair() -> void:
	if repair_path_options.is_empty() or repair_plan_revision < 0: return
	var route := WorldData.find_route(world, repair_route_id)
	if route.is_empty(): _show_issue("待修复线路已不存在。"); _finish_tool(); return
	var option: Dictionary = repair_path_options[repair_path_choice]
	var references: Array[Dictionary] = []
	for connection in option.get("edges", []):
		var edge: Dictionary = connection.get("edge", {})
		if bool(edge.get("platform", false)): continue
		references.append({"id": str(edge.get("id", "")), "forward": bool(connection.get("forward", true))})
	if references.is_empty():
		_show_issue("候选走向没有可用轨道。")
		return
	var expected_revision := repair_plan_revision
	var apply_repair := func():
		if int(world.get("revision", 0)) != expected_revision:
			_show_issue("规划在确认期间发生变化；请重新检查这个区间的候选走向。")
			repair_path_options = TrackNetwork.station_path_options(repair_from_station_id, repair_to_station_id, world, float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0]))
			repair_plan_revision = int(world.get("revision", 0))
			repair_path_choice = 0
			_update_repair_preview()
			_refresh_ui()
			return
		var candidate_state: Dictionary = world.duplicate(false)
		candidate_state["routes"] = world.get("routes", []).duplicate()
		var route_index := -1
		for index in range(candidate_state.routes.size()):
			if str(candidate_state.routes[index].get("id", "")) == repair_route_id:
				route_index = index
				break
		if route_index < 0: _show_issue("待修复线路已不存在。"); return
		var candidate_route: Dictionary = candidate_state.routes[route_index].duplicate(true)
		candidate_state.routes[route_index] = candidate_route
		var candidate_directions: Array = candidate_route.get("directions", []).duplicate(true)
		var selected_direction_index := -1
		for index in range(candidate_directions.size()):
			if str(candidate_directions[index].get("id", "")) == repair_direction_id:
				selected_direction_index = index
				break
		if selected_direction_index < 0: _show_issue("待修复方向已变化，请重新选择区间。"); return
		var selected_direction: Dictionary = candidate_directions[selected_direction_index]
		var selected_paths: Array = selected_direction.get("edgePathsBySegment", []).duplicate(true)
		while selected_paths.size() <= repair_segment_index: selected_paths.append([])
		selected_paths[repair_segment_index] = references.duplicate(true)
		selected_direction["edgePathsBySegment"] = selected_paths
		var reverse_direction_index := -1
		var reverse_segment_index := -1
		for direction_index in range(candidate_directions.size()):
			if direction_index == selected_direction_index: continue
			var other_stops: Array = candidate_directions[direction_index].get("stationIds", [])
			for other_segment_index in range(maxi(0, other_stops.size() - 1)):
				if str(other_stops[other_segment_index]) == repair_to_station_id and str(other_stops[other_segment_index + 1]) == repair_from_station_id:
					reverse_direction_index = direction_index
					reverse_segment_index = other_segment_index
					break
			if reverse_direction_index >= 0: break
		if reverse_direction_index >= 0:
			var reverse_direction: Dictionary = candidate_directions[reverse_direction_index]
			var reverse_paths: Array = reverse_direction.get("edgePathsBySegment", []).duplicate(true)
			while reverse_paths.size() <= reverse_segment_index: reverse_paths.append([])
			reverse_paths[reverse_segment_index] = _reverse_edge_paths([references])[0]
			reverse_direction["edgePathsBySegment"] = reverse_paths
		candidate_route["directions"] = candidate_directions
		candidate_route["open"] = false
		var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
		var validation := TrackNetwork.ordered_station_path(repair_from_station_id, repair_to_station_id, references, candidate_state, ref_lat)
		if not bool(validation.get("valid", false)):
			_show_issue("候选轨道无法连续接入两座停站：%s" % str(validation.get("error", "轨道顺序无效")))
			return
		var reversed_references: Array = _reverse_edge_paths([references])[0]
		var reverse_validation := TrackNetwork.ordered_station_path(repair_to_station_id, repair_from_station_id, reversed_references, candidate_state, ref_lat)
		if reverse_direction_index >= 0 and not bool(reverse_validation.get("valid", false)):
			_show_issue("反向走向检查未通过：%s" % str(reverse_validation.get("error", "方向不连续")))
			return
		history.execute("修复%s区间" % route.get("name", "线路"), func(state: Dictionary):
			var live_route := WorldData.find_route(state, repair_route_id)
			if live_route.is_empty(): return
			live_route["directions"] = candidate_directions.duplicate(true)
			live_route["open"] = false
		)
		selected_type = "route"
		selected_id = repair_route_id
		current_tool = "select"
		map_view.tool = current_tool
		interaction_state.set_tool(current_tool)
		interaction_state.select_object("route", repair_route_id)
		_clear_route_repair_draft()
		map_view.set_world(world)
		_after_planning_change("区间走向已修复；线路仍保持暂停，请检查后重新开通")
	_confirm_service_impact([repair_route_id], "修复运营线路区间", apply_repair, func(): _show_toast("已取消修复；线路和原有走向未更改"))

func _clear_route_repair_draft() -> void:
	repair_route_id = ""
	repair_direction_id = ""
	repair_segment_index = -1
	repair_from_station_id = ""
	repair_to_station_id = ""
	repair_path_options.clear()
	repair_path_choice = 0
	repair_plan_revision = -1
	line_draft_stops.clear()
	map_view.line_draft_points.clear()
	map_view.requested_redraw()

func _confirm_operating_line() -> void:
	if line_draft_stops.size() < 2: return
	_ensure_line_draft_path_options()
	var stops := line_draft_stops.duplicate()
	var is_loop: bool = stops.size() >= 4 and str(stops.front()) == str(stops.back())
	if is_loop and stops.size() < 4:
		_show_toast("环线至少需要三座不同的车站")
		return
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0])
	var used_edges: Dictionary = {}
	var edge_paths_by_segment: Array = []
	for index in range(stops.size() - 1):
		var options: Array = line_draft_path_options[index] if index < line_draft_path_options.size() else []
		var choice_index := clampi(line_draft_path_choices[index], 0, maxi(0, options.size() - 1)) if index < line_draft_path_choices.size() else 0
		var selected_edge_ids: Array = options[choice_index].get("linkIds", []) if not options.is_empty() else []
		var segment := TrackNetwork.shortest_station_path(str(stops[index]), str(stops[index + 1]), world, ref_lat, selected_edge_ids)
		if not bool(segment.get("valid", false)):
			_show_toast(str(segment.get("error", "停站之间没有连续轨道")))
			return
		var segment_path: Array[Dictionary] = []
		for connection in segment.get("edges", []):
			var physical_edge: Dictionary = connection.get("edge", {})
			if bool(physical_edge.get("platform", false)): continue
			var edge_id := str(physical_edge.get("id", ""))
			used_edges[edge_id] = true
			segment_path.append({"id": edge_id, "forward": bool(connection.get("forward", true))})
		edge_paths_by_segment.append(segment_path)
	var colors := ["#e25263", "#478fdf", "#34a67f", "#db9638", "#9b69ce", "#36aeb4"]
	var line_index: int = world.get("routes", []).size()
	var route_name := "%d号线" % (line_index + 1)
	# Allocate this outside the mutation callback. GDScript lambda captures are
	# not a reliable way to return a newly assigned ID to the surrounding scope.
	var route_id := "r_%d" % Time.get_ticks_msec()
	var unique_stops: Array[String] = []
	for station_id in stops:
		if not unique_stops.has(str(station_id)): unique_stops.append(str(station_id))
	var reverse_stops: Array[String] = stops.duplicate(); reverse_stops.reverse()
	var reverse_edge_paths_by_segment: Array = _reverse_edge_paths(edge_paths_by_segment)
	history.execute("创建运营线路%s" % route_name, func(state: Dictionary):
		var route := WorldData.add_route(state, route_name, colors[line_index % colors.size()])
		route["id"] = route_id
		route.networkBased = true
		route.stationOrder = unique_stops.duplicate()
		route.directions = [
			{"id": "forward", "stationIds": stops.duplicate(), "edgePathsBySegment": edge_paths_by_segment.duplicate(true)},
			{"id": "reverse", "stationIds": reverse_stops, "edgePathsBySegment": reverse_edge_paths_by_segment}
		]
		for edge in TrackNetwork.all_physical_edges(state):
			if not used_edges.has(str(edge.get("id", ""))): continue
			if not edge.has("routeIds"): edge.routeIds = []
			if not edge.routeIds.has(route_id): edge.routeIds.append(route_id)
		for station_id in unique_stops:
			var station := WorldData.find_station(state, str(station_id))
			if not station.is_empty() and not station.get("routeIds", []).has(route_id): station.routeIds.append(route_id)
	)
	if route_id.is_empty(): return
	active_route_id = route_id; selected_type = "route"; selected_id = route_id
	line_draft_stops.clear(); line_draft_path_options.clear(); line_draft_path_choices.clear(); current_tool = "select"; map_view.tool = "select"
	map_view.line_draft_points.clear()
	map_view.set_world(world); _after_planning_change("运营线路已建立；检查车型与路径后即可开通")

func _reverse_edge_paths(paths: Array) -> Array:
	var result: Array = paths.duplicate(true)
	result.reverse()
	for segment in result:
		if not segment is Array: continue
		segment.reverse()
		for edge in segment:
			if edge is Dictionary: edge["forward"] = not bool(edge.get("forward", true))
	return result

func _update_line_draft_preview() -> void:
	map_view.line_draft_points.clear()
	if line_draft_stops.size() < 2:
		map_view.requested_redraw(); return
	_ensure_line_draft_path_options()
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0])
	for index in range(line_draft_stops.size() - 1):
		var options: Array = line_draft_path_options[index]
		var choice_index := clampi(line_draft_path_choices[index], 0, maxi(0, options.size() - 1))
		var selected_ids: Array = options[choice_index].get("linkIds", []) if not options.is_empty() else []
		var segment := TrackNetwork.shortest_station_path(line_draft_stops[index], line_draft_stops[index + 1], world, ref_lat, selected_ids)
		if not bool(segment.get("valid", false)): continue
		for point in segment.get("points", []):
			if map_view.line_draft_points.is_empty() or _distance_m(map_view.line_draft_points.back(), point) > 0.5: map_view.line_draft_points.append(point.duplicate())
	map_view.requested_redraw()

func _ensure_line_draft_path_options() -> void:
	var needed := maxi(0, line_draft_stops.size() - 1)
	var previous_count := line_draft_path_options.size()
	while line_draft_path_options.size() > needed: line_draft_path_options.pop_back(); line_draft_path_choices.pop_back()
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0])
	while line_draft_path_options.size() < needed:
		var index := line_draft_path_options.size()
		line_draft_path_options.append(TrackNetwork.station_path_options(line_draft_stops[index], line_draft_stops[index + 1], world, ref_lat))
		line_draft_path_choices.append(0)
	if needed == 0:
		line_draft_segment_index = -1
	elif needed > previous_count:
		line_draft_segment_index = needed - 1
	else:
		line_draft_segment_index = clampi(line_draft_segment_index, 0, needed - 1)

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
		var physical_path := TrackNetwork.shortest_station_path(str(onboarding.get("originStationId", "")), str(onboarding.get("destinationStationId", "")), world, float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0]))
		if not bool(physical_path.get("valid", false)):
			if step >= 4: onboarding.lastError = "任务两站之间的物理轨道已断开；请重新铺轨。"
			step = 3
			onboarding.taskRouteId = ""
			onboarding.observationStarted = false
		elif step == 3:
			step = 4
	if step >= 4:
		var connected_route := _onboarding_route_for_pair(false)
		if connected_route.is_empty():
			if step >= 5: onboarding.lastError = "还没有一条运营线路按停站顺序服务任务两站。"
			step = 4
			onboarding.taskRouteId = ""
			onboarding.observationStarted = false
		else:
			onboarding.taskRouteId = str(connected_route.get("id", ""))
			if step == 4: step = 5
			if bool(connected_route.get("open", false)):
				if step == 5: step = 6
			elif step >= 6:
				step = 5
				onboarding.observationStarted = false
				onboarding.observedTargetArrivals = 0
				onboarding.observedTargetServed = 0
				onboarding.lastError = "任务线路已停止运营；重新开通后再观察。"
	if step >= 6:
		var flow := _onboarding_flow()
		if flow.is_empty() or not bool(flow.get("valid", false)) or str(flow.get("routeId", "")) != str(onboarding.get("taskRouteId", "")):
			if step >= 7: step = 5 if not _onboarding_route_for_pair(false).is_empty() else 3
			if bool(onboarding.get("observationStarted", false)):
				onboarding.lastError = "模拟路径当前不再由这条任务线路服务；请检查站点覆盖和开通状态。"
				onboarding.observationStarted = false
		else:
			if step == 6 and bool(onboarding.get("observationStarted", false)) and int(onboarding.get("observedTargetServed", 0)) > 0:
				step = 7
				onboarding.completed = true
				world.simulation.paused = true
				if UiPreferencesScript.save_onboarding_completed(true) != OK:
					_show_toast("引导已完成，但全局完成标记未能保存")
	if step != old_step:
		onboarding.step = step
		if step in [2, 3, 4, 5, 6, 7] and old_step < step: onboarding.lastError = ""
	world["onboarding"] = onboarding
	if step != old_step or str(onboarding.get("lastError", "")) != old_error:
		_sync_onboarding_map(step == 3 and step > old_step)
		_refresh_onboarding_card()
		_refresh_tools()
		if step != old_step:
			_autosave()
			if step == 7:
				_update_sim_labels()
				if left_tab == "stats": _refresh_left_panel()
				_show_toast("教学完成：实际到达人数已记录，后续需求是模型估算")
	elif step == 6:
		_refresh_onboarding_card()

func _on_city_change_requested(index: int) -> void:
	var new_id := str(WorldData.cities()[index].get("id", "shanghai"))
	if new_id == active_city_id: return
	var mode := str(world.get("mode", "blank"))
	_request_world_transition(func():
		var loaded := SaveManager.load_world(new_id, mode, true)
		if loaded.ok:
			if bool(loaded.get("pendingRecoveryConfirmation", false)):
				_confirm_recovery_before_load(loaded, func(confirmed: Dictionary): _load_world(confirmed.world))
			else:
				_load_world(loaded.world)
				if bool(loaded.get("recovered", false)): _show_toast(str(loaded.get("error", "已从备份恢复")))
		elif not SaveManager.save_exists(new_id, mode):
			_load_world(_prepared_new_world(new_id, mode))
		else:
			_select_current_city_in_picker()
			_show_issue(str(loaded.get("error", "载入城市存档失败；当前规划仍保留")), "无法切换城市")
	)

func _select_current_city_in_picker() -> void:
	if not is_instance_valid(city_picker): return
	for index in range(WorldData.cities().size()):
		if str(WorldData.cities()[index].get("id", "")) == active_city_id:
			city_picker.select(index)
			return

func _on_camera_changed(center: Array, zoom: int) -> void:
	if not world.is_empty():
		world.view = {"center": center.duplicate(), "zoom": zoom}
		save_dirty = true
		_update_topbar()

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
		var elapsed := int(sim.get("elapsedMinutes", sim.get("minute", 420)))
		var minute_of_day := posmod(elapsed, 1440)
		time_label.text = "D%d · %02d:%02d" % [elapsed / 1440 + 1, minute_of_day / 60, minute_of_day % 60]
	if is_instance_valid(pause_button):
		pause_button.text = "▶" if bool(sim.get("paused", true)) else "Ⅱ"
		var coach_play := not bool(world.get("tutorialDone", false)) and int(world.get("tutorialStep", 0)) == 3
		pause_button.tooltip_text = "教学下一步：播放并观察乘客" if coach_play else "暂停／继续 · 空格"
		pause_button.add_theme_stylebox_override("normal", _style(Color("#236548"), Color("#8cf0c6"), 8, 2) if coach_play else _style(Color("#142e2c"), BORDER, 8, 1))
	if is_instance_valid(speed_picker): speed_picker.select([1,3,10].find(int(sim.get("speed", 1))))
	if is_instance_valid(undo_button): undo_button.disabled = history.undo_label().is_empty()
	if is_instance_valid(redo_button): redo_button.disabled = history.redo_label().is_empty()
	if is_instance_valid(save_badge):
		save_badge.text = "保存失败 · 重试" if save_failed else "未保存" if save_dirty else "已保存"
		save_badge.tooltip_text = save_failure_reason if save_failed else "点击立即保存"
		save_badge.add_theme_color_override("font_color", Color("#ff9e92") if save_failed else Color("#f0bd69") if save_dirty else TEAL)

func _update_sim_labels() -> void:
	if not is_instance_valid(stats_label) or world.is_empty(): return
	var sim: Dictionary = world.simulation
	var completed := int(sim.get("completed", 0)); var attempted := int(sim.get("attempted", 0))
	var waiting := int(sim.get("waiting", 0)); var in_transit := int(sim.get("inTransit", 0))
	stats_label.text = "等候 %s  ·  在途 %s  ·  已完成 %s" % [_number(waiting), _number(in_transit), _number(completed)]
	if completed <= 0:
		stats_label.tooltip_text = "暂无已完成行程，暂不显示效率评分。\n需求 %s · 已乘车 %s · 放弃 %s · 中断 %s" % [_number(attempted), _number(int(sim.get("departed", 0))), _number(int(sim.get("abandoned", 0))), _number(int(sim.get("interrupted", 0)))]
	else:
		var rate := 100.0 * float(completed) / maxf(1.0, float(attempted))
		var average := float(sim.get("tripMinutesTotal", 0.0)) / maxf(1.0, float(completed))
		var crowd := 100.0 * float(sim.get("peakCrowding", 0.0))
		stats_label.tooltip_text = "游戏估算 · 到达率 %.0f%% · 平均出行 %.1f 分钟 · 区间占用 %.0f%%\n需求 %s · 已乘车 %s · 放弃 %s · 中断 %s" % [rate, average, crowd, _number(attempted), _number(int(sim.get("departed", 0))), _number(int(sim.get("abandoned", 0))), _number(int(sim.get("interrupted", 0)))]

func _autosave(show_error: bool = true) -> bool:
	if world.is_empty(): return false
	save_dirty = true; _update_topbar()
	var result := SaveManager.save_world(world)
	if result.ok:
		var index_result := SaveManager.save_last_game(world)
		if index_result.ok:
			save_dirty = false
			save_failed = false
			save_failure_reason = ""
			_update_topbar()
			return true
		save_dirty = true
		save_failed = true
		save_failure_reason = str(index_result.get("error", "继续游戏索引保存失败"))
		_update_topbar()
		if show_error: _show_issue(save_failure_reason, "保存失败")
	else:
		save_dirty = true
		save_failed = true
		save_failure_reason = str(result.get("error", "本地存档失败"))
		_update_topbar()
		if show_error: _show_issue(save_failure_reason, "保存失败")
	return false

func _request_world_transition(action: Callable) -> void:
	if world.is_empty():
		if action.is_valid(): action.call()
		return
	world.simulation.paused = true
	_update_topbar()
	if _autosave(false):
		if action.is_valid(): action.call()
		return
	_show_save_failure_choice(action)

func _show_save_failure_choice(action: Callable) -> void:
	if is_instance_valid(pending_transition_dialog): pending_transition_dialog.queue_free()
	var dialog := ConfirmationDialog.new()
	dialog.title = "保存未完成"
	dialog.dialog_text = "%s\n\n重试保存，另存一份 JSON，或明确放弃未保存修改。取消会留在当前暂停的游戏中。" % save_failure_reason
	dialog.get_ok_button().text = "重试保存"
	dialog.add_button("另存 JSON…", false, "export")
	dialog.add_button("放弃未保存修改", true, "discard")
	dialog.add_cancel_button("留在游戏中")
	add_child(dialog)
	pending_transition_dialog = dialog
	dialog.confirmed.connect(func():
		if is_instance_valid(dialog): dialog.queue_free()
		pending_transition_dialog = null
		if _autosave(false):
			if action.is_valid(): action.call()
		else: _show_save_failure_choice(action)
	)
	dialog.custom_action.connect(func(action_id: StringName):
		if is_instance_valid(dialog): dialog.queue_free()
		pending_transition_dialog = null
		if action_id == &"discard":
			if action.is_valid(): action.call()
		elif action_id == &"export":
			_select_current_city_in_picker()
			SaveManager.export_world(world.duplicate(true), func(result: Dictionary):
				if bool(result.get("ok", false)):
					if action.is_valid(): action.call()
				else:
					_show_issue(str(result.get("error", "JSON 导出失败；当前游戏仍保留")), "导出失败")
					_show_save_failure_choice(action)
			)
	)
	dialog.canceled.connect(func():
		pending_transition_dialog = null
		_select_current_city_in_picker()
	)
	dialog.popup_centered(Vector2i(560, 260))

func _retry_or_save() -> void:
	if _autosave(): _show_toast("本地存档已成功保存")

func _show_save_menu() -> void:
	var popup := PopupMenu.new()
	popup.add_item("立即保存", 1)
	popup.add_item("另存为 JSON…", 2)
	popup.add_item("导入 JSON…", 3)
	popup.add_item("打开存档目录", 4)
	popup.id_pressed.connect(func(id: int):
		match id:
			1:
				if _autosave(): _show_toast("本地存档已写入")
			2: SaveManager.export_world(world, func(result: Dictionary): _show_toast("JSON 已导出" if bool(result.get("ok", false)) else str(result.get("error", "导出失败"))))
			3: SaveManager.import_world(func(loaded: Dictionary):
				if not _autosave():
					_show_issue("无法先保存当前进度，导入已取消。")
					return
				_load_world(loaded)
				if _autosave(): _show_toast("存档已导入并保存")
				else: _show_issue("存档已载入到当前会话，但未能同步写入本机。原存档备份仍保留。")
			, func(error: String): _show_issue(error))
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
		_request_world_transition(func():
			var result := SaveManager.load_world(str(choice[0]), str(choice[1]), true)
			if result.ok:
				if bool(result.get("pendingRecoveryConfirmation", false)):
					_confirm_recovery_before_load(result, func(confirmed: Dictionary): _load_world(confirmed.world))
				else:
					_load_world(result.world)
					if bool(result.get("recovered", false)): _show_toast(str(result.get("error", "已从备份恢复")))
			else:
				_select_current_city_in_picker()
				_show_issue(str(result.get("error", "载入存档失败；当前规划仍保留")), "无法载入存档")
		)
	)
	if is_instance_valid(menu_layer): menu_layer.add_child(popup)
	else: add_child(popup)
	popup.popup_centered(Vector2i(350, 330))

func _leave_to_menu() -> void:
	_request_world_transition(func():
		for child in get_children():
			if child != map_view and child.get_name() != "Background": child.queue_free()
		world = {}; _show_main_menu()
	)

func _show_issue(text: String, title: String = "规划检查") -> void:
	var dialog := AcceptDialog.new(); dialog.title = title; dialog.dialog_text = text; add_child(dialog); dialog.confirmed.connect(func(): dialog.queue_free()); dialog.canceled.connect(func(): dialog.queue_free()); dialog.popup_centered()

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
	item.custom_minimum_size.y = roundi(46.0 * minf(_ui_scale, 1.25))
	if font_color == TEAL or text in ["检查并开通线路", "检查并开通此线路", "确认站点"]:
		item.add_theme_font_override("font", _bold_font)
	return item

func _set_control_base_font(control: Control, font_size: int) -> void:
	var readable_size := maxi(16, font_size)
	control.set_meta("ui_base_font_size", readable_size)
	control.add_theme_font_size_override("font_size", roundi(float(readable_size) * _ui_scale))

func _style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color = background; box.border_color = border; box.set_border_width_all(border_width); box.set_corner_radius_all(radius); box.content_margin_left = 10; box.content_margin_right = 10; box.content_margin_top = 4; box.content_margin_bottom = 4; return box
