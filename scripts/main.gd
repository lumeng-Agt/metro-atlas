extends Control

const MapViewScript = preload("res://scripts/map_view.gd")
const UiPreferencesScript = preload("res://scripts/ui_preferences.gd")
const MenuArtScript = preload("res://scripts/menu_art.gd")
const OnboardingScript = preload("res://scripts/onboarding.gd")
const TravelModelScript = preload("res://scripts/travel_model.gd")
const RoutePathScript = preload("res://scripts/route_path.gd")
const JourneyModelScript = preload("res://scripts/journey_model.gd")
const SimulationEngineScript = preload("res://scripts/simulation_engine.gd")
const ServiceScheduleScript = preload("res://scripts/service_schedule.gd")
const NeighborhoodGoalsScript = preload("res://scripts/neighborhood_goals.gd")
const CityProgressionScript = preload("res://scripts/city_progression.gd")
const AudioFeedbackScript = preload("res://scripts/audio_feedback.gd")
const TutorialSpotlightScript = preload("res://scripts/tutorial_spotlight.gd")
const UiThemeScript = preload("res://scripts/ui_theme.gd")
const BUILD_VERSION := "0.16.1 · 2026.10.17"
const APP_BG := UiThemeScript.CANVAS
const PANEL := UiThemeScript.SURFACE
const PANEL_LIGHT := UiThemeScript.SURFACE_ALT
const BORDER := UiThemeScript.BORDER
const TEXT := UiThemeScript.INK
const MUTED := UiThemeScript.MUTED
const TEAL := UiThemeScript.ACCENT

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
var timed_autosave_enabled := true
var timed_autosave_interval_minutes := 5
var autosave_elapsed_seconds := 0.0
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
var tool_context_panel: VBoxContainer
var demand_toggle: CheckButton
var hall_toggle: CheckButton
var analysis_picker: OptionButton
var accessibility_minutes_by_demand: Dictionary = {}
var ui_audio_player: AudioStreamPlayer
var feedback_enabled := true
var feedback_volume := 0.35
var menu_layer: Control
var menu_city_picker: OptionButton
var menu_onboarding_toggle: CheckButton
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
var route_extension_context: Dictionary = {}
var endpoint_choice_candidates: Array[Dictionary] = []
var station_vehicle_id := "B-6"
var confirming_track_preview := false
var _flow_cache_revision := -1
var _flow_cache: Array[Dictionary] = []
var _ui_scale := 1.0
var ui_motion_enabled := true
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
var tutorial_spotlight: Control
var tutorial_targets: Dictionary = {}
var _tutorial_focus_signature := ""
var _tutorial_map_size := Vector2.ZERO
var _more_tools_expanded := false
var _complexity_expanded := false
var _onboarding_reason_expanded := false
var _station_preview_last_usec := 0
var _curve_preview_last_usec := 0
var _stats_live_labels: Dictionary = {}
var _stats_wait_buttons: Dictionary = {}
var _stats_utilization_labels: Dictionary = {}

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
	_update_tutorial_spotlight()
	if timed_autosave_enabled and save_dirty:
		autosave_elapsed_seconds += delta
		if autosave_elapsed_seconds >= float(timed_autosave_interval_minutes * 60):
			autosave_elapsed_seconds = 0.0
			if not _autosave(false, true):
				autosave_elapsed_seconds = maxf(0.0, float(timed_autosave_interval_minutes * 60) - 30.0)
	else:
		autosave_elapsed_seconds = 0.0
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
				map_view.requested_redraw()
			if bool(world.simulation.get("paused", true)):
				sim_accumulator = 0.0
				break
	map_view.simulation_fraction = sim_accumulator if not bool(world.simulation.get("paused", true)) else 0.0
	if simulation_advanced:
		_update_sim_labels()
		if left_tab == "stats": _update_stats_live_labels()
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
	ui_motion_enabled = UiPreferencesScript.load_ui_motion_enabled()
	feedback_enabled = UiPreferencesScript.load_feedback_enabled()
	feedback_volume = UiPreferencesScript.load_feedback_volume()
	timed_autosave_enabled = UiPreferencesScript.load_timed_autosave_enabled()
	timed_autosave_interval_minutes = UiPreferencesScript.load_timed_autosave_interval()
	_base_font = load("res://fonts/NotoSansSC.ttf")
	_base_font = _font_weight(_base_font, 500)
	_bold_font = _font_weight(load("res://fonts/NotoSansSC.ttf"), 700)
	_theme = UiThemeScript.create_theme(_base_font, _bold_font, _ui_scale)
	theme = _theme
	var background := ColorRect.new()
	background.name = "Background"
	background.color = APP_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	ui_audio_player = AudioStreamPlayer.new()
	ui_audio_player.name = "UiFeedbackAudio"
	ui_audio_player.bus = "Master"
	add_child(ui_audio_player)
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
	if is_instance_valid(_theme): _theme.default_font_size = roundi(16.0 * _ui_scale)
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

func _fade_in(control: Control) -> void:
	if not ui_motion_enabled or not is_instance_valid(control): return
	control.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(control, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _update_responsive_layout() -> void:
	if not is_instance_valid(map_view) or not is_instance_valid(_left_panel) or not is_instance_valid(_right_panel): return
	var logical_width := get_viewport_rect().size.x / maxf(1.0, _ui_scale)
	var should_collapse := logical_width < 1100.0
	var use_two_top_rows := logical_width < 1440.0
	if is_instance_valid(_top_content) and is_instance_valid(_top_primary_row) and is_instance_valid(_top_actions):
		if use_two_top_rows and _top_actions.get_parent() == _top_primary_row:
			_top_primary_row.remove_child(_top_actions)
			_top_content.add_child(_top_actions)
		elif not use_two_top_rows and _top_actions.get_parent() == _top_content:
			_top_content.remove_child(_top_actions)
			_top_primary_row.add_child(_top_actions)
	if should_collapse != _layout_narrow:
		_layout_narrow = should_collapse
		_left_requested = not _layout_narrow and not bool(world.get("onboarding", {}).get("active", false))
		_right_requested = false
	if logical_width < 1440.0 and logical_width >= 1100.0:
		_left_requested = not bool(world.get("onboarding", {}).get("active", false))
	_left_panel.visible = _left_requested
	_right_panel.visible = _right_requested
	var layout_scale := minf(_ui_scale, 1.25)
	var top_height := roundi((112.0 if use_two_top_rows else 68.0) * layout_scale)
	var footer_height := _calculate_footer_height(top_height, layout_scale)
	if is_instance_valid(_top_panel): _top_panel.offset_bottom = top_height
	_left_panel.offset_top = top_height
	_left_panel.offset_bottom = -footer_height - 12.0 * layout_scale
	var rail_width := 288.0 * _ui_scale
	var detail_width := minf(336.0 * _ui_scale, get_viewport_rect().size.x - 40.0)
	_left_panel.offset_left = 0.0 if not _layout_narrow else 0.0
	_left_panel.offset_right = minf(rail_width, get_viewport_rect().size.x - 32.0)
	_right_panel.offset_top = top_height
	_right_panel.offset_bottom = -footer_height - 12.0 * layout_scale
	_right_panel.offset_left = -detail_width
	_right_panel.offset_right = 0.0
	if _layout_narrow:
		_left_panel.offset_bottom = -roundi(footer_height + 12.0 * layout_scale)
		_right_panel.offset_bottom = -roundi(footer_height + 12.0 * layout_scale)
	map_view.offset_left = rail_width if _left_panel.visible and not _layout_narrow else 0.0
	map_view.offset_top = top_height
	map_view.offset_right = -detail_width if _right_panel.visible and logical_width >= 1440.0 else 0.0
	map_view.offset_bottom = -footer_height
	if is_instance_valid(_footer_panel):
		var footer_width := minf(840.0 * layout_scale, get_viewport_rect().size.x - 24.0)
		_footer_panel.offset_left = -footer_width * 0.5
		_footer_panel.offset_right = footer_width * 0.5
		_footer_panel.offset_top = -footer_height - 10.0
		_footer_panel.offset_bottom = -10.0
	if is_instance_valid(left_content): left_content.custom_minimum_size.x = maxf(0.0, _left_panel.size.x - 24.0 * layout_scale)
	if is_instance_valid(right_content): right_content.custom_minimum_size.x = maxf(0.0, detail_width - 24.0 * layout_scale)
	if is_instance_valid(_left_panel_button): _left_panel_button.text = "线路 ▾" if _left_panel.visible else "线路 ▸"
	if is_instance_valid(_right_panel_button): _right_panel_button.text = "详情 ▾" if _right_panel.visible else "详情 ▸"
	if is_instance_valid(_mode_badge): _mode_badge.visible = not _layout_narrow
	if is_instance_valid(_layer_panel):
		var layer_width := minf(342.0 * layout_scale, maxf(220.0, get_viewport_rect().size.x - 24.0))
		var right_drawer_cover := detail_width if _layout_narrow and _right_panel.visible else 0.0
		_layer_panel.offset_left = -layer_width - right_drawer_cover - 12.0
		_layer_panel.offset_right = -12.0 - right_drawer_cover
		_layer_panel.custom_minimum_size.x = layer_width
	if is_instance_valid(_attribution_panel):
		var map_origin_x := map_view.position.x
		var left_drawer_cover := minf(rail_width, get_viewport_rect().size.x - 32.0) if _layout_narrow and _left_panel.visible else 0.0
		var attribution_width := minf(228.0 * layout_scale, maxf(120.0, map_view.size.x - left_drawer_cover - 24.0))
		_attribution_panel.offset_left = map_origin_x + left_drawer_cover + 12.0
		_attribution_panel.offset_right = map_origin_x + left_drawer_cover + 12.0 + attribution_width
		_attribution_panel.offset_top = -footer_height - roundi(76.0 * layout_scale)
		_attribution_panel.offset_bottom = -footer_height - roundi(42.0 * layout_scale)
	if is_instance_valid(attribution_label): attribution_label.add_theme_font_size_override("font_size", roundi(12.0 * _ui_scale))
	if is_instance_valid(onboarding_panel):
		onboarding_panel.custom_minimum_size.x = minf(370.0 * layout_scale, get_viewport_rect().size.x - 32.0)

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
	var dialog := _new_accept_dialog()
	dialog.title = "地图数据来源"
	dialog.dialog_text = "地图数据 © OpenStreetMap contributors\n许可：Open Database License（ODbL）\n本地快照：%s\n地图几何仅用于显示；不代表已取得步行道路、过街或建筑施工校核数据。" % map_view.base_map_snapshot
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(560, 260))

func _new_accept_dialog() -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.theme = theme
	return dialog

func _new_confirmation_dialog() -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.theme = theme
	return dialog

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
	var instruction_height := 34.0 * layout_scale if is_instance_valid(tool_instruction_label) and tool_instruction_label.visible else 0.0
	var stats_height := 26.0 * layout_scale
	var desired := 18.0 * layout_scale + panel_rows * (control_height + 5.0) + action_rows * (control_height + 5.0) + instruction_height + stats_height
	return clampi(roundi(desired), mini(112, maximum), maximum)

func _show_main_menu() -> void:
	_render_planning_menu(false)

func _show_new_city_menu() -> void:
	_render_planning_menu(true)

func _render_planning_menu(new_city: bool) -> void:
	map_view.visible = false
	menu_onboarding_toggle = null
	if is_instance_valid(menu_layer): menu_layer.queue_free()
	menu_layer = Control.new()
	menu_layer.name = "MainMenu"
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.theme = theme
	add_child(menu_layer)
	var backdrop := ColorRect.new()
	backdrop.name = "Background"
	backdrop.color = APP_BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(backdrop)
	var card := PanelContainer.new()
	card.name = "MenuCard"
	card.anchor_left = 0.5; card.anchor_right = 0.5
	card.anchor_top = 0.5; card.anchor_bottom = 0.5
	var viewport_size := get_viewport_rect().size
	var card_width := minf(1120.0, viewport_size.x - 32.0)
	var card_height := minf(744.0, viewport_size.y - 32.0)
	card.offset_left = -card_width * 0.5; card.offset_right = card_width * 0.5
	card.offset_top = -card_height * 0.5; card.offset_bottom = card_height * 0.5
	var panel_style := _style(PANEL, BORDER, 18, 1)
	panel_style.shadow_color = Color(0.20, 0.24, 0.18, 0.11)
	panel_style.shadow_size = 16
	panel_style.shadow_offset = Vector2(0, 6)
	panel_style.content_margin_left = 28; panel_style.content_margin_right = 28
	panel_style.content_margin_top = 24; panel_style.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", panel_style)
	menu_layer.add_child(card)
	_fade_in(card)
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
	intro.add_theme_constant_override("separation", 12)
	intro.custom_minimum_size.x = 390.0 if wide else 0.0
	body.add_child(intro)
	intro.add_child(_menu_label("METRO ATLAS  /  DESKTOP %s" % BUILD_VERSION, 14, TEAL, true))
	var title := _menu_label("造一座地铁", 48, TEXT, true)
	title.custom_minimum_size.y = 70
	intro.add_child(title)
	intro.add_child(_menu_label("从真实街区出发，连接人们每天要去的地方。", 18, MUTED))
	var illustration_panel := PanelContainer.new()
	illustration_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	illustration_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	illustration_panel.custom_minimum_size.y = 260 if wide else 180
	illustration_panel.add_theme_stylebox_override("panel", _style(Color("#F0F1EB"), BORDER, 12, 1))
	intro.add_child(illustration_panel)
	var illustration := MenuArtScript.new()
	illustration.name = "MetroNetworkIllustration"
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	illustration_panel.add_child(illustration)
	intro.add_child(_menu_label("找出行需求　→　选站　→　铺轨　→　开通运营", 16, MUTED, true))
	var actions := VBoxContainer.new()
	actions.name = "MenuActions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 10)
	actions.custom_minimum_size.x = 330.0 if wide else 0.0
	body.add_child(actions)
	if new_city:
		actions.add_child(_menu_label("选择一座城市", 24, TEXT, true))
		actions.add_child(_menu_label("规划新线路，或在真实路网基础上继续扩建。", 15, MUTED))
		menu_city_picker = OptionButton.new()
		menu_city_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu_city_picker.custom_minimum_size.y = 44
		_set_control_base_font(menu_city_picker, 16)
		for city in WorldData.cities(): menu_city_picker.add_item(str(city.get("name", "城市")))
		for index in range(WorldData.cities().size()):
			if str(WorldData.cities()[index].get("id", "")) == active_city_id: menu_city_picker.select(index); break
		menu_city_picker.item_selected.connect(func(index: int): active_city_id = str(WorldData.cities()[index].get("id", "shanghai")))
		actions.add_child(menu_city_picker)
		if new_city:
			menu_onboarding_toggle = CheckButton.new()
			menu_onboarding_toggle.name = "NewGameOnboardingToggle"
			menu_onboarding_toggle.text = "开启逐步新手教程（仅从零规划）"
			menu_onboarding_toggle.button_pressed = true
			menu_onboarding_toggle.custom_minimum_size.y = 44.0 * _ui_scale
			_set_control_base_font(menu_onboarding_toggle, 15)
			actions.add_child(menu_onboarding_toggle)
		var blank := _button("从零规划", TEAL, PANEL_LIGHT, 19)
		blank.custom_minimum_size.y = 48
		blank.pressed.connect(func(): _start_new_game(active_city_id, "blank", "free", is_instance_valid(menu_onboarding_toggle) and menu_onboarding_toggle.button_pressed))
		actions.add_child(blank)
		var challenge := _button("街区挑战", Color("#a77921"), PANEL_LIGHT, 17)
		challenge.custom_minimum_size.y = 44
		challenge.tooltip_text = "在同一份城市规划中逐步完成需求覆盖、扩建和换乘目标。"
		challenge.pressed.connect(func(): _start_neighborhood_challenge(active_city_id))
		actions.add_child(challenge)
		var expand := _button("扩建现实路网", Color("#365F8C"), PANEL_LIGHT, 17)
		expand.custom_minimum_size.y = 44
		expand.pressed.connect(func(): _start_new_game(active_city_id, "expand", "free", false))
		actions.add_child(expand)
		var back := _button("返回主菜单", TEXT, PANEL_LIGHT, 15)
		back.pressed.connect(_show_main_menu)
		actions.add_child(back)
	else:
		actions.add_child(_menu_label("继续你的城市", 22, TEXT, true))
		menu_continue_button = _button("继续上次游戏   →", TEAL, PANEL_LIGHT, 18)
		menu_continue_button.custom_minimum_size.y = 52
		menu_continue_button.disabled = true
		menu_continue_button.pressed.connect(_continue_last_game)
		actions.add_child(menu_continue_button)
		var new_button := _button("新建城市规划", TEXT, PANEL_LIGHT, 17)
		new_button.custom_minimum_size.y = 48
		new_button.pressed.connect(_show_new_city_menu)
		actions.add_child(new_button)
		var saves_button := _button("存档中心", TEXT, PANEL_LIGHT, 16)
		saves_button.custom_minimum_size.y = 44
		saves_button.pressed.connect(_show_load_menu)
		actions.add_child(saves_button)
		var manual_saves_button := _button("命名存档", TEXT, PANEL_LIGHT, 15)
		manual_saves_button.custom_minimum_size.y = 44
		manual_saves_button.pressed.connect(_show_manual_load_menu)
		actions.add_child(manual_saves_button)
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
		actions.add_child(_menu_label("五座城市　·　本地存档　·　随时撤销", 14, MUTED))
	_update_continue_button()

func _show_main_menu_legacy() -> void:
	_render_planning_menu(false)

func _show_settings() -> void:
	if not is_instance_valid(menu_layer): return
	var dialog := _new_accept_dialog()
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
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var viewport_size := get_viewport_rect().size
	content_scroll.custom_minimum_size = Vector2(
		minf(440.0 * _ui_scale, maxf(240.0, viewport_size.x - 96.0)),
		minf(220.0 * _ui_scale, maxf(160.0, viewport_size.y - 96.0))
	)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.x = maxf(0.0, content_scroll.custom_minimum_size.x - 2.0)
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
	var motion_toggle := CheckButton.new()
	motion_toggle.text = "启用轻量界面淡入动效"
	motion_toggle.button_pressed = ui_motion_enabled
	motion_toggle.custom_minimum_size.y = 44.0 * _ui_scale
	motion_toggle.toggled.connect(func(enabled: bool):
		ui_motion_enabled = enabled
		if UiPreferencesScript.save_ui_motion_enabled(enabled) != OK: _show_toast("动效设置保存失败")
	)
	content.add_child(motion_toggle)
	scale_picker.item_selected.connect(func(index: int):
		var value: float = [1.0, 1.25, 1.5, 1.75][index]
		var save_error: Error = UiPreferencesScript.save_scale(value)
		if save_error != OK:
			_show_toast("界面设置保存失败；本次缩放仍已生效")
		_apply_ui_scale(value, true)
	)
	content.add_child(HSeparator.new())
	content.add_child(_label("操作反馈", 18, TEXT, true))
	var feedback_toggle := CheckButton.new()
	feedback_toggle.text = "启用轻量操作提示音"
	feedback_toggle.button_pressed = feedback_enabled
	feedback_toggle.custom_minimum_size.y = 44.0 * _ui_scale
	feedback_toggle.toggled.connect(func(enabled: bool):
		feedback_enabled = enabled
		if UiPreferencesScript.save_feedback_enabled(enabled) != OK: _show_toast("提示音设置保存失败")
		if enabled: _play_ui_feedback("confirm")
	)
	content.add_child(feedback_toggle)
	var volume_row := HBoxContainer.new()
	volume_row.add_child(_label("音量", 15, MUTED))
	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0; volume_slider.max_value = 1.0; volume_slider.step = 0.05; volume_slider.value = feedback_volume
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.custom_minimum_size.y = 38.0 * _ui_scale
	volume_slider.editable = feedback_enabled
	volume_slider.value_changed.connect(func(value: float):
		feedback_volume = value
		if UiPreferencesScript.save_feedback_volume(value) != OK: _show_toast("音量设置保存失败")
	)
	feedback_toggle.toggled.connect(func(enabled: bool): volume_slider.editable = enabled)
	volume_row.add_child(volume_slider)
	var preview_sound := _button("试听", TEXT, PANEL_LIGHT, 14)
	preview_sound.custom_minimum_size.y = 44.0 * _ui_scale
	preview_sound.pressed.connect(func(): _play_ui_feedback("confirm"))
	volume_row.add_child(preview_sound)
	content.add_child(volume_row)
	content.add_child(HSeparator.new())
	content.add_child(_label("自动存档", 18, TEXT, true))
	var autosave_toggle := CheckButton.new()
	autosave_toggle.text = "启用定时自动存档"
	autosave_toggle.button_pressed = timed_autosave_enabled
	autosave_toggle.custom_minimum_size.y = 44.0 * _ui_scale
	autosave_toggle.toggled.connect(func(enabled: bool):
		timed_autosave_enabled = enabled
		autosave_elapsed_seconds = 0.0
		if UiPreferencesScript.save_timed_autosave_enabled(enabled) != OK: _show_toast("自动存档设置保存失败")
		_update_topbar()
	)
	content.add_child(autosave_toggle)
	var autosave_row := HBoxContainer.new()
	autosave_row.add_child(_label("定时保存间隔（现实时间）", 15, MUTED))
	var autosave_interval_picker := OptionButton.new()
	for minutes in [2, 5, 10, 15]: autosave_interval_picker.add_item("%d 分钟" % minutes)
	autosave_interval_picker.select([2, 5, 10, 15].find(timed_autosave_interval_minutes))
	autosave_interval_picker.custom_minimum_size = Vector2(140.0 * _ui_scale, 44.0 * _ui_scale)
	autosave_interval_picker.disabled = not timed_autosave_enabled
	autosave_interval_picker.item_selected.connect(func(index: int):
		timed_autosave_interval_minutes = [2, 5, 10, 15][index]
		autosave_elapsed_seconds = 0.0
		if UiPreferencesScript.save_timed_autosave_interval(timed_autosave_interval_minutes) != OK: _show_toast("自动存档间隔保存失败")
	)
	autosave_toggle.toggled.connect(func(enabled: bool): autosave_interval_picker.disabled = not enabled)
	autosave_row.add_child(autosave_interval_picker)
	content.add_child(autosave_row)
	var autosave_info := _label("有未保存变化时按此间隔自动保存。建设确认、暂停和退出仍会即时保存；手动存档会另存独立命名进度。", 14, MUTED)
	autosave_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(autosave_info)
	var settings_info := _label("地图：随游戏附带五城 OSM 矢量底图，断网也能规划。\n模拟速度使用固定游戏时间步长。", 14, MUTED)
	settings_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(settings_info)
	content_scroll.add_child(content)
	_fade_in(content_scroll)
	dialog.add_child(content_scroll)
	menu_layer.add_child(dialog)
	dialog.popup_centered(Vector2i(mini(roundi(520.0 * _ui_scale), int(viewport_size.x - 32.0)), mini(roundi(360.0 * _ui_scale), int(viewport_size.y - 32.0))))

func _start_new_game(city_id: String, mode: String, challenge_mode: String = "free", onboarding_enabled: bool = true) -> void:
	if SaveManager.save_exists(city_id, mode):
		var confirm := _new_confirmation_dialog()
		confirm.title = "替换本地进度？"
		confirm.dialog_text = "这个城市与开局已有存档。继续会先将旧文件保存在 .bak。"
		add_child(confirm)
		confirm.confirmed.connect(func():
			confirm.queue_free()
			_load_world(_prepared_new_world(city_id, mode, challenge_mode, onboarding_enabled))
		)
		confirm.canceled.connect(func(): confirm.queue_free())
		confirm.popup_centered()
		return
	_load_world(_prepared_new_world(city_id, mode, challenge_mode, onboarding_enabled))

func _start_neighborhood_challenge(city_id: String) -> void:
	# Challenge mode is a goal layer on the same blank-city save, never a duplicate world.
	if SaveManager.save_exists(city_id, "blank"):
		var loaded := SaveManager.load_world(city_id, "blank", true)
		if not bool(loaded.get("ok", false)):
			_show_issue(str(loaded.get("error", "无法载入这座城市的本地进度")), "挑战载入失败")
			return
		if bool(loaded.get("pendingRecoveryConfirmation", false)):
			_confirm_recovery_before_load(loaded, Callable(self, "_enter_neighborhood_challenge"))
		else:
			_enter_neighborhood_challenge(loaded)
		return
	_start_new_game(city_id, "blank", "neighborhood", false)

func _enter_neighborhood_challenge(loaded: Dictionary) -> void:
	var challenge_world: Dictionary = loaded.get("world", {})
	challenge_world["challengeMode"] = "neighborhood"
	var challenge_state: Dictionary = challenge_world.get("challengeState", {"step": 0, "startedAt": -1, "completedAt": -1})
	if int(challenge_state.get("startedAt", -1)) < 0:
		challenge_state["startedAt"] = int(challenge_world.get("simulation", {}).get("elapsedMinutes", 420))
	challenge_world["challengeState"] = challenge_state
	_load_world(challenge_world)

func _prepared_new_world(city_id: String, mode: String, challenge_mode: String = "free", onboarding_enabled: bool = true) -> Dictionary:
	var state := WorldData.new_world(city_id, mode)
	state["challengeMode"] = challenge_mode
	if challenge_mode == "neighborhood":
		state["challengeState"] = {"step": 0, "startedAt": int(state.get("simulation", {}).get("elapsedMinutes", 420)), "completedAt": -1}
	state["onboarding"] = OnboardingScript.create_state(city_id, mode, onboarding_enabled)
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
	var dialog := _new_confirmation_dialog()
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
		# Older saves may predate the click-by-click tutorial. Honor the player's
		# completion preference instead of silently marking that tutorial done.
		# Legacy saves have no click-by-click state; derive a one-time migration from their own flag.
		var legacy_tutorial_enabled := not bool(world.get("tutorialDone", true))
		world["onboarding"] = OnboardingScript.create_state(str(world.get("cityId", "shanghai")), str(world.get("mode", "blank")), legacy_tutorial_enabled)
		if not legacy_tutorial_enabled and str(world.get("mode", "blank")) == "blank":
			world["tutorialDone"] = true # Disable only the retired tutorial flow.
	# A prior build could persist an empty, inactive tutorial state while marking
	# the retired tutorial as done. Recover that exact unfinished state on load.
	# Completed or explicitly skipped tutorials remain closed, and expand starts
	# keep their lighter local-browsing guidance.
	var onboarding_state: Dictionary = world.get("onboarding", {})
	if str(world.get("mode", "blank")) == "blank" \
		and onboarding_state.has("missionId") \
		and not bool(onboarding_state.get("active", false)) \
		and not bool(onboarding_state.get("completed", false)) \
		and not bool(onboarding_state.get("skipped", false)) \
		and bool(onboarding_state.get("enabled", true)):
		onboarding_state["active"] = true
		onboarding_state["viewingCity"] = false
		world["onboarding"] = onboarding_state
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
	if not world.has("cityProgression"): world["cityProgression"] = CityProgressionScript.create_state(active_city_id)
	if not world.has("planningPhases") or world.get("planningPhases", []).is_empty():
		world["planningPhases"] = [{"id":"phase_1", "name":"一期建设", "createdAt":int(world.simulation.get("elapsedMinutes", 420)), "routeIds":world.get("routes", []).map(func(route: Dictionary): return str(route.get("id", ""))), "stationIds":world.get("stations", []).map(func(station: Dictionary): return str(station.get("id", ""))), "edgeIds":[], "flowIds":[]}]
	for phase in world.get("planningPhases", []):
		for key in ["routeIds", "stationIds", "edgeIds", "flowIds"]:
			if not phase.get(key, []) is Array: phase[key] = []
	if not world.has("currentPlanningPhaseId"): world["currentPlanningPhaseId"] = str(world.planningPhases.back().get("id", "phase_1"))
	world.simulation.paused = true
	if not bool(world.get("onboarding", {}).get("active", false)):
		CityProgressionScript.start(world, int(world.simulation.get("elapsedMinutes", 420)))
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
	map_view.analysis_mode = "planning"
	map_view.show_demand = false
	map_view.reachability_minutes_by_demand.clear()
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
	tutorial_targets.clear()
	tutorial_spotlight = null
	_tutorial_focus_signature = ""
	_tutorial_map_size = Vector2.ZERO
	_layout_narrow = get_viewport_rect().size.x / maxf(1.0, _ui_scale) < 1100.0
	_left_requested = not _layout_narrow and not bool(world.get("onboarding", {}).get("active", false))
	_right_requested = false
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
	top.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 0, 1))
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
	var logo := _label("造一座地铁", 18, TEAL, true); logo.custom_minimum_size.x = 148.0 * _ui_scale; top_row.add_child(logo)
	_left_panel_button = _button("线路 ▾", MUTED, PANEL_LIGHT, 14)
	_left_panel_button.pressed.connect(func():
		_left_requested = not _left_requested
		if _layout_narrow and _left_requested: _right_requested = false
		_update_responsive_layout()
	)
	top_row.add_child(_left_panel_button)
	city_picker = OptionButton.new(); city_picker.custom_minimum_size = Vector2(120, 40)
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
	time_label = _label("D1 · 07:00", 16, TEXT, true); time_label.custom_minimum_size.x = 92; _top_actions.add_child(time_label)
	pause_button = _button("▶", TEAL, Color("#142e2c"), 18); pause_button.name = "TutorialTop_play"; pause_button.custom_minimum_size = Vector2(44, 42); pause_button.pressed.connect(_toggle_pause); _top_actions.add_child(pause_button)
	_register_tutorial_target("play", pause_button)
	speed_picker = OptionButton.new(); speed_picker.custom_minimum_size = Vector2(82, 38)
	for speed in [1,3,10]: speed_picker.add_item("%d×" % speed)
	speed_picker.item_selected.connect(func(index: int): world.simulation.speed = [1,3,10][index]; _autosave())
	_top_actions.add_child(speed_picker)
	undo_button = _button("↶", TEXT, PANEL_LIGHT, 20); undo_button.tooltip_text = "撤销 Ctrl+Z"; undo_button.pressed.connect(_do_undo); _top_actions.add_child(undo_button)
	redo_button = _button("↷", TEXT, PANEL_LIGHT, 20); redo_button.tooltip_text = "重做 Ctrl+Y"; redo_button.pressed.connect(_do_redo); _top_actions.add_child(redo_button)
	var saves := _button("存档中心", MUTED, PANEL_LIGHT, 13); saves.pressed.connect(_show_save_center); _top_actions.add_child(saves)
	save_badge = _button("已保存", TEAL, Color("#142e2c"), 13)
	save_badge.custom_minimum_size = Vector2(96, 38)
	save_badge.pressed.connect(_retry_or_save)
	_top_actions.add_child(save_badge)
	var menu_button := _button("菜单", MUTED, PANEL_LIGHT, 13); menu_button.pressed.connect(_leave_to_menu); _top_actions.add_child(menu_button)

	var left := PanelContainer.new()
	left.anchor_left = 0; left.anchor_right = 0; left.anchor_top = 0; left.anchor_bottom = 1
	left.offset_top = 68; left.offset_bottom = -35; left.offset_left = 0; left.offset_right = 288
	left.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 0, 0)); add_child(left)
	_left_panel = left
	var left_body := VBoxContainer.new(); left_body.add_theme_constant_override("separation", 4); left_body.add_theme_constant_override("margin_left", 8); left_body.add_theme_constant_override("margin_right", 8); left_body.add_theme_constant_override("margin_top", 8); left_body.add_theme_constant_override("margin_bottom", 8); left.add_child(left_body)
	var left_tabs := HBoxContainer.new(); left_tabs.add_theme_constant_override("separation", 5); left_body.add_child(left_tabs)
	for tab_data in [["routes", "线路"], ["tasks", "任务"], ["stats", "统计"]]:
		var tab_button := _button(str(tab_data[1]), TEXT, PANEL_LIGHT, 14)
		tab_button.name = "TutorialTab_%s" % str(tab_data[0])
		tab_button.custom_minimum_size.y = 40.0 * _ui_scale
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.pressed.connect(_on_left_tab_pressed.bind(str(tab_data[0])))
		left_tabs.add_child(tab_button)
		left_tab_buttons[str(tab_data[0])] = tab_button
		if str(tab_data[0]) == "tasks": _register_tutorial_target("tab_tasks", tab_button)
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
	var right_scroll := ScrollContainer.new(); right_scroll.name = "DetailsScroll"; right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right_body.add_child(right_scroll)
	var detail_stack := VBoxContainer.new()
	detail_stack.add_theme_constant_override("separation", 6)
	detail_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(detail_stack)
	right_content = VBoxContainer.new(); right_content.custom_minimum_size.x = 312; right_content.add_theme_constant_override("separation", 9); right_content.add_theme_constant_override("margin_left", 14); right_content.add_theme_constant_override("margin_right", 14); right_content.add_theme_constant_override("margin_top", 14); right_content.add_theme_constant_override("margin_bottom", 8); detail_stack.add_child(right_content)
	tool_context_panel = VBoxContainer.new()
	tool_context_panel.name = "ConstructionDetails"
	tool_context_panel.add_theme_constant_override("separation", 8)
	tool_context_panel.add_theme_constant_override("margin_left", 14)
	tool_context_panel.add_theme_constant_override("margin_right", 14)
	tool_context_panel.add_theme_constant_override("margin_top", 4)
	tool_context_panel.add_theme_constant_override("margin_bottom", 14)
	detail_stack.add_child(tool_context_panel)
	_right_pinned_footer = VBoxContainer.new()
	_right_pinned_footer.add_theme_constant_override("margin_left", 14)
	_right_pinned_footer.add_theme_constant_override("margin_right", 14)
	_right_pinned_footer.add_theme_constant_override("margin_top", 8)
	_right_pinned_footer.add_theme_constant_override("margin_bottom", 14)
	right_body.add_child(_right_pinned_footer)

	var footer := PanelContainer.new()
	footer.anchor_left = 0.5; footer.anchor_right = 0.5; footer.anchor_top = 1; footer.anchor_bottom = 1
	footer.offset_left = -560; footer.offset_right = 560; footer.offset_top = -158; footer.offset_bottom = -12
	var footer_style := _style(PANEL, BORDER, 14, 1)
	footer_style.shadow_color = Color(0.24, 0.25, 0.19, 0.09); footer_style.shadow_size = 10; footer_style.shadow_offset = Vector2(0, 3)
	footer.add_theme_stylebox_override("panel", footer_style); add_child(footer)
	_footer_panel = footer
	var footer_body := VBoxContainer.new(); footer_body.add_theme_constant_override("separation", 3); footer_body.add_theme_constant_override("margin_left", 10); footer_body.add_theme_constant_override("margin_right", 10); footer_body.add_theme_constant_override("margin_top", 6); footer_body.add_theme_constant_override("margin_bottom", 5); footer.add_child(footer_body)
	tool_panel = HFlowContainer.new(); tool_panel.add_theme_constant_override("h_separation", 7); tool_panel.add_theme_constant_override("v_separation", 5); footer_body.add_child(tool_panel)
	tool_action_panel = HFlowContainer.new(); tool_action_panel.visible = false; tool_action_panel.add_theme_constant_override("h_separation", 7); tool_action_panel.add_theme_constant_override("v_separation", 5); footer_body.add_child(tool_action_panel)
	tool_instruction_label = _label("", 14, TEAL)
	tool_instruction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_instruction_label.custom_minimum_size.y = 18.0 * minf(_ui_scale, 1.25)
	footer_body.add_child(tool_instruction_label)
	var footer_row := HFlowContainer.new(); footer_row.add_theme_constant_override("h_separation", 12); footer_row.add_theme_constant_override("v_separation", 4); footer_body.add_child(footer_row)
	stats_label = _label("等候 0  ·  在途 0  ·  已完成 0", 15, MUTED); stats_label.name = "TutorialStats"; stats_label.custom_minimum_size.x = minf(430.0 * _ui_scale, 460.0); footer_row.add_child(stats_label)
	_register_tutorial_target("stats", stats_label)
	toast_label = _label("", 14, TEXT); toast_label.custom_minimum_size.x = minf(300.0 * _ui_scale, 300.0); footer_row.add_child(toast_label)
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
	analysis_picker = OptionButton.new()
	for mode_label in ["规划", "需求", "可达性", "运营问题"]: analysis_picker.add_item(mode_label)
	analysis_picker.custom_minimum_size = Vector2(126.0 * _ui_scale, 38.0 * _ui_scale)
	analysis_picker.select(0)
	analysis_picker.item_selected.connect(func(index: int): _set_map_analysis_mode(["planning", "demand", "accessibility", "operations"][index]))
	layers.add_child(analysis_picker)
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
	_fade_in(self)
	_refresh_ui()
	tutorial_spotlight = TutorialSpotlightScript.new()
	tutorial_spotlight.name = "TutorialSpotlight"
	tutorial_spotlight.theme = theme
	add_child(tutorial_spotlight)
	_update_tutorial_spotlight()

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
	_update_tutorial_spotlight()

func _refresh_left_panel() -> void:
	if not is_instance_valid(left_content): return
	_stats_live_labels.clear()
	_stats_wait_buttons.clear()
	_stats_utilization_labels.clear()
	for child in left_content.get_children(): child.queue_free()
	if _flow_cache_revision != int(world.get("revision", 0)): _rebuild_flow_cache()
	for tab_id in left_tab_buttons:
		var button: Button = left_tab_buttons[tab_id]
		var active := str(tab_id) == left_tab
		button.add_theme_stylebox_override("normal", _style(UiThemeScript.ACCENT_SOFT if active else PANEL_LIGHT, TEAL if active else BORDER, 8, 1))
		button.add_theme_color_override("font_color", TEAL if active else TEXT)
	match left_tab:
		"tasks": _refresh_tasks_tab()
		"stats": _refresh_stats_tab()
		_: _refresh_routes_tab()

func _on_left_tab_pressed(tab_id: String) -> void:
	left_tab = tab_id
	_refresh_left_panel()
	_update_tutorial_spotlight()

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
	tutorial_targets.erase("campaign_next")
	left_content.add_child(_label("任务与扩建", 20, TEXT, true))
	var onboarding_state: Dictionary = world.get("onboarding", {})
	var progression_state: Dictionary = world.get("cityProgression", {})
	if bool(progression_state.get("started", false)) and (not bool(onboarding_state.get("active", false)) or bool(onboarding_state.get("completed", false))) and str(world.get("challengeMode", "free")) != "neighborhood":
		_refresh_city_campaign_tab()
		return
	if str(world.get("challengeMode", "free")) == "neighborhood":
		var challenge_state: Dictionary = world.get("challengeState", {})
		var challenge_step := int(challenge_state.get("step", 0))
		var challenge_text := "1/3 · 接通一组基础出行需求" if challenge_step == 0 else ("2/3 · 补足附近另一组出行需求" if challenge_step == 1 else ("3/3 · 建立可实际乘坐的换乘路径" if challenge_step == 2 else "挑战完成 · 继续改善街区网络"))
		var challenge_card := PanelContainer.new()
		challenge_card.add_theme_stylebox_override("panel", _style(Color("#352e20"), Color("#a8823c"), 9, 1))
		left_content.add_child(challenge_card)
		var challenge_box := VBoxContainer.new()
		challenge_box.add_theme_constant_override("separation", 5)
		challenge_box.add_theme_constant_override("margin_left", 10); challenge_box.add_theme_constant_override("margin_right", 10)
		challenge_box.add_theme_constant_override("margin_top", 9); challenge_box.add_theme_constant_override("margin_bottom", 9)
		challenge_card.add_child(challenge_box)
		challenge_box.add_child(_label("街区挑战 · %s" % challenge_text, 15, Color("#f1ca79"), true))
		challenge_box.add_child(_label("目标随当前城市规划推进；退出挑战不会另建或覆盖一份网络。", 13, MUTED))
		var leave_challenge := _button("继续自由扩建", MUTED, PANEL_LIGHT, 14)
		leave_challenge.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
		leave_challenge.pressed.connect(_leave_neighborhood_challenge)
		challenge_box.add_child(leave_challenge)
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

func _refresh_city_campaign_tab() -> void:
	var progression: Dictionary = world.get("cityProgression", {})
	var stage := CityProgressionScript.current_stage(world)
	var elapsed := int(world.get("simulation", {}).get("elapsedMinutes", 420))
	var phases: Array = world.get("planningPhases", [])
	var current_phase_id := str(world.get("currentPlanningPhaseId", "phase_1"))
	var current_phase: Dictionary = {}
	var has_campaign_action := false
	for phase in phases:
		if str(phase.get("id", "")) == current_phase_id: current_phase = phase; break
	left_content.add_child(_label("城市议程 · 第 %d 天 %02d:%02d" % [elapsed / 1440 + 1, posmod(elapsed, 1440) / 60, posmod(elapsed, 60)], 14, MUTED))
	if not stage.is_empty():
		var chapter := PanelContainer.new()
		chapter.add_theme_stylebox_override("panel", _style(Color("#1a3533"), Color("#398773"), 9, 1))
		left_content.add_child(chapter)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 7)
		box.add_theme_constant_override("margin_left", 11); box.add_theme_constant_override("margin_right", 11)
		box.add_theme_constant_override("margin_top", 10); box.add_theme_constant_override("margin_bottom", 10)
		chapter.add_child(box)
		box.add_child(_label("当前主目标 · %s" % str(stage.get("title", "城市议程")), 18, TEAL, true))
		box.add_child(_label(str(stage.get("description", "")), 15, TEXT))
		box.add_child(_label("为什么：%s" % str(stage.get("why", "")), 14, MUTED))
		box.add_child(_label("完成条件：%s" % str(stage.get("action", "")), 14, MUTED))
		var flow: Dictionary = _campaign_stage_flow(progression, stage)
		if not flow.is_empty():
			var coverage_text := "已有完整地铁路径；等待真实乘客到达。" if bool(flow.get("valid", false)) else "目前没有连续、已开通的完整旅程。"
			box.add_child(_label("%s → %s · 游戏设定约 %s 人次/日\n%s" % [str(flow.get("from", "起点")), str(flow.get("to", "目的地")), _number(int(round(float(flow.get("peoplePerDay", 0.0))))), coverage_text], 14, Color("#f1d291") if not bool(flow.get("valid", false)) else TEXT))
			var actions := HFlowContainer.new()
			actions.add_theme_constant_override("h_separation", 6)
			var focus := _button("定位这条出行", Color("#9ad8f3"), PANEL_LIGHT, 14)
			focus.name = "TutorialCampaign_next"
			focus.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
			focus.pressed.connect(func(): _onboarding_campaign_action(flow))
			actions.add_child(focus)
			_register_tutorial_target("campaign_next", focus)
			has_campaign_action = true
			var expected := _button("查看预计旅程", TEXT, PANEL_LIGHT, 14)
			expected.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
			expected.disabled = not bool(flow.get("valid", false))
			expected.pressed.connect(func(): _show_expected_journey(flow))
			actions.add_child(expected)
			box.add_child(actions)
		elif str(stage.get("kind", "")) == "transfer":
			box.add_child(_label("先在车站详情标记拟换乘站，再比较周边需求。标记仅是规划提示；两条已开通线路实际停靠同一站后才形成换乘。", 14, MUTED))
		elif str(stage.get("kind", "")) == "operations":
			var sim: Dictionary = world.get("simulation", {})
			var waiting := int(sim.get("waiting", 0))
			var crowded := str(sim.get("peakCrowdedRoute", ""))
			var issue_text := "目前等候 %s 人。" % _number(waiting)
			if not crowded.is_empty(): issue_text += "近期拥挤区间位于 %s。" % str(WorldData.find_route(world, crowded).get("name", "运营线路"))
			if waiting == 0 and crowded.is_empty(): issue_text = "目前没有持续排队或明显拥挤；持续观察 60 个游戏分钟即可完成本阶段。"
			box.add_child(_label(issue_text + "停运或乘客放弃不计作改善。", 14, TEXT))
	else:
		left_content.add_child(_label("本城连续章节已完成。城市议程会继续显示尚未服务的出行和实际运营问题。", 15, TEAL, true))
		var current := _next_neighborhood_flow(world.get("onboarding", {}))
		if not current.is_empty():
			left_content.add_child(_label("可自主选择的下一片区", 17, TEXT, true))
			left_content.add_child(_label("%s → %s · 游戏估算 %s 人次/日" % [current.get("from", "居住区"), current.get("to", "目的地"), _number(int(round(float(current.get("peoplePerDay", 0.0)))))], 15, MUTED))
			var locate_next := _button("查看附近需求", Color("#9ad8f3"), PANEL_LIGHT, 14)
			locate_next.name = "TutorialCampaign_next"
			locate_next.pressed.connect(func(): _onboarding_campaign_action(current))
			left_content.add_child(locate_next)
			_register_tutorial_target("campaign_next", locate_next)
			has_campaign_action = true
	if not has_campaign_action and bool(world.get("onboarding", {}).get("active", false)) and int(world.get("onboarding", {}).get("step", -1)) >= 7:
		var continue_goal := _button("查看本阶段目标", Color("#9ad8f3"), PANEL_LIGHT, 14)
		continue_goal.name = "TutorialCampaign_next"
		continue_goal.pressed.connect(func(): _onboarding_campaign_action({}))
		left_content.add_child(continue_goal)
		_register_tutorial_target("campaign_next", continue_goal)
	var upcoming := CityProgressionScript.next_event(world, elapsed)
	if not upcoming.is_empty():
		var announce_in := maxi(0, int(upcoming.get("announceMinute", elapsed)) - elapsed)
		var start_in := maxi(0, int(upcoming.get("startMinute", elapsed)) - elapsed)
		var upcoming_text := "城市变化预告：%s · %s" % [str(upcoming.get("title", "城市变化")), str(upcoming.get("description", "客流变化为游戏设定。"))]
		if announce_in > 0: upcoming_text += "\n约 %d 游戏分钟后预告；约 %d 分钟后开始。" % [announce_in, start_in]
		else: upcoming_text += "\n即将开始 · 客流变化幅度为游戏设定。"
		var upcoming_label := _label(upcoming_text, 14, Color("#f1c97b"))
		upcoming_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_content.add_child(upcoming_label)
	var active_events: Array[String] = CityProgressionScript.active_event_ids(world)
	if not active_events.is_empty():
		left_content.add_child(_label("当前城市变化", 16, TEXT, true))
		for event in CityProgressionScript.events_for_city(active_city_id):
			if active_events.has(str(event.get("id", ""))):
				left_content.add_child(_label("● %s · 需求增幅为游戏设定" % str(event.get("title", "城市变化")), 14, Color("#eacb85")))
	var event_history: Array = progression.get("eventHistory", [])
	if not event_history.is_empty():
		var last_event: Dictionary = event_history.back()
		left_content.add_child(_label("最近事件：%s · %s" % [str(last_event.get("title", "城市变化")), "已结束" if str(last_event.get("status", "")) == "ended" else "需求已变化"], 13, MUTED))
	var completed_stages: Array = progression.get("completedStages", [])
	if not completed_stages.is_empty():
		left_content.add_child(_label("已完成章节", 16, TEXT, true))
		for result in completed_stages.slice(maxi(0, completed_stages.size() - 4), completed_stages.size()):
			var result_flow := _find_cached_flow(str(result.get("flowId", "")))
			var outcome := "实际完成 %s 人次" % _number(int(result.get("completed", 0))) if result.has("completed") else str(result.get("note", "已记录当前服务状态"))
			if result.has("actualAverageMinutes"): outcome += " · 这批乘客平均 %.1f 分钟" % float(result.get("actualAverageMinutes", 0.0))
			left_content.add_child(_label("✓ %s · %s" % [str(result.get("title", "规划目标")), outcome], 14, TEAL))
			if not result_flow.is_empty():
				var compare := CityProgressionScript.compare_flow_windows(world, str(result.get("flowId", "")), elapsed)
				left_content.add_child(_label(str(compare.get("label", "暂无可比的同一时段数据。")), 12, MUTED))
	left_content.add_child(HSeparator.new())
	left_content.add_child(_label("建设阶段", 17, TEXT, true))
	var phase_actions := HFlowContainer.new()
	var create_phase := _button("＋ 新建阶段", TEAL, Color("#15362f"), 14)
	create_phase.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
	create_phase.pressed.connect(_prompt_new_planning_phase)
	phase_actions.add_child(create_phase)
	left_content.add_child(phase_actions)
	for phase in phases:
		var phase_id := str(phase.get("id", ""))
		var route_ids: Array = phase.get("routeIds", [])
		var route_names: Array[String] = []
		var pending := 0
		for route_id in route_ids:
			var route := WorldData.find_route(world, str(route_id))
			if route.is_empty(): continue
			route_names.append(str(route.get("name", "线路")))
			if not bool(route.get("open", false)): pending += _route_pending_segment_count(route)
		var title := ("● " if phase_id == current_phase_id else "○ ") + str(phase.get("name", "建设阶段"))
		var station_count := 0
		for station_id in phase.get("stationIds", []):
			if not WorldData.find_station(world, str(station_id)).is_empty(): station_count += 1
		var edge_count := 0
		for edge_id in phase.get("edgeIds", []):
			if not _find_link(str(edge_id)).is_empty(): edge_count += 1
		var summary := "%d 站 · %d 段轨道 · %d 条线路" % [station_count, edge_count, route_names.size()]
		if pending > 0: summary += " · %d 段尚未开通" % pending
		if not route_names.is_empty(): summary += " · " + "、".join(route_names.slice(0, 3))
		var phase_button := _button(title + "\n" + summary, TEXT, PANEL_LIGHT, 14)
		phase_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		phase_button.custom_minimum_size.y = 54.0 * minf(_ui_scale, 1.2)
		phase_button.pressed.connect(func(): _set_current_planning_phase(phase_id))
		left_content.add_child(phase_button)
		var phase_flows: Array = phase.get("flowIds", [])
		if phase_id == current_phase_id:
			var assign_targets := _button("为本阶段选择服务目标", Color("#9ad8f3"), PANEL_LIGHT, 14)
			assign_targets.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
			assign_targets.pressed.connect(func(): _prompt_phase_flow_goals(phase_id))
			left_content.add_child(assign_targets)
		if not phase_flows.is_empty():
			var targets: Array[String] = []
			for flow_id in phase_flows:
				var target_flow := _find_cached_flow(str(flow_id))
				if target_flow.is_empty(): continue
				var serves_from_phase := false
				if bool(target_flow.get("valid", false)):
					for used_route_id in target_flow.get("routeIds", []):
						if str(WorldData.find_route(world, str(used_route_id)).get("planningPhaseId", "")) == phase_id: serves_from_phase = true
				var status := "本阶段已接通" if serves_from_phase else ("其他阶段已有服务" if bool(target_flow.get("valid", false)) else "尚未接通")
				targets.append("%s → %s：%s" % [str(target_flow.get("from", "起点")), str(target_flow.get("to", "目的地")), status])
			if not targets.is_empty(): left_content.add_child(_label("本阶段服务目标\n" + "\n".join(targets), 13, Color("#c8d8e2")))
	if not current_phase.is_empty(): left_content.add_child(_label("新建线路会归入当前阶段“%s”。未通过检查或未开通的线路不会计入已服务乘客。" % str(current_phase.get("name", "")), 13, MUTED))
	var optional := CityProgressionScript.optional_goals(world, _flow_cache)
	if not optional.is_empty():
		left_content.add_child(HSeparator.new())
		left_content.add_child(_label("可选委托 · 最多 2 项", 16, TEXT, true))
		for goal in optional:
			var flow := _find_cached_flow(str(goal.get("flowId", "")))
			var row := VBoxContainer.new()
			left_content.add_child(row)
			row.add_child(_label(str(goal.get("title", "街区委托")), 15, TEAL, true))
			row.add_child(_label("受影响出行约 %s 人次/日；需使用完整可达路径。" % _number(int(round(float(goal.get("peoplePerDay", 0.0))))), 13, MUTED))
			var button := _button("查看位置", Color("#9ad8f3"), PANEL_LIGHT, 13)
			button.pressed.connect(func(): _focus_flow(flow))
			row.add_child(button)
	var transfer_stations: Array[Dictionary] = []
	for station in world.get("stations", []):
		if bool(station.get("plannedTransfer", false)): transfer_stations.append(station)
	if not transfer_stations.is_empty():
		left_content.add_child(HSeparator.new())
		left_content.add_child(_label("拟换乘站 · 仅作规划标记", 15, Color("#e5b96d"), true))
		for station in transfer_stations.slice(0, 4):
			var locate_station := _button("◎ %s · 查看周边出行" % str(station.get("name", "车站")), TEXT, PANEL_LIGHT, 14)
			locate_station.pressed.connect(func(): _select_object("station", str(station.get("id", ""))); map_view.center_on(station.get("latlng", [0, 0]), maxi(map_view.current_zoom, 14)))
			left_content.add_child(locate_station)
	if not str(world.get("migrationNotice", "")).is_empty():
		var migration := _label(str(world.get("migrationNotice", "")), 13, Color("#e1b975"))
		migration.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_content.add_child(migration)

func _campaign_stage_flow(progression: Dictionary, stage: Dictionary) -> Dictionary:
	var stage_index := int(progression.get("chapterIndex", 0))
	if str(stage.get("kind", "")) != "flow": return {}
	var configured: Array = CityProgressionScript.config(active_city_id).get("flows", [])
	var flow_index := 0 if stage_index == 0 else 1
	if flow_index >= configured.size(): return {}
	return _find_cached_flow(str(configured[flow_index]))

func _route_pending_segment_count(route: Dictionary) -> int:
	var missing := 0
	for direction in route.get("directions", []):
		for segment in direction.get("edgePathsBySegment", []):
			if not segment is Array or segment.is_empty(): missing += 1
	return missing

func _create_planning_phase(raw_name: String) -> void:
	var phase_name := raw_name.strip_edges()
	if phase_name.is_empty(): _show_toast("先给这个建设阶段起个名字"); return
	var phase_id := "phase_%d_%d" % [int(world.get("planningPhases", []).size() + 1), Time.get_ticks_msec()]
	var now := int(world.get("simulation", {}).get("elapsedMinutes", 420))
	history.execute("新建建设阶段%s" % phase_name, func(state: Dictionary):
		var phase := {"id":phase_id, "name":phase_name, "createdAt":now, "routeIds":[], "stationIds":[], "edgeIds":[], "flowIds":[]}
		state.get("planningPhases", []).append(phase)
		state["currentPlanningPhaseId"] = phase_id
	)
	_refresh_left_panel(); _autosave(); _show_toast("已新建建设阶段：%s" % phase_name)

func _prompt_new_planning_phase() -> void:
	var dialog := _new_confirmation_dialog()
	dialog.title = "新建建设阶段"
	dialog.get_ok_button().text = "创建并切换"
	dialog.get_cancel_button().text = "取消"
	var input := LineEdit.new()
	input.placeholder_text = "例如：二期 · 北蔡走廊"
	_set_control_base_font(input, 16)
	dialog.add_child(input)
	add_child(dialog)
	dialog.confirmed.connect(func(): _create_planning_phase(input.text); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(480, 180))
	input.grab_focus()

func _prompt_phase_flow_goals(phase_id: String) -> void:
	var phase := _find_planning_phase(phase_id)
	if phase.is_empty(): return
	if _flow_cache.is_empty(): _rebuild_flow_cache()
	var candidates: Array[Dictionary] = []
	var included: Dictionary = {}
	for flow in _flow_cache:
		var flow_id := str(flow.get("id", ""))
		if flow_id.is_empty(): continue
		candidates.append(flow)
		included[flow_id] = true
	for flow_id in CityProgressionScript.config(active_city_id).get("flows", []):
		if included.has(str(flow_id)): continue
		var flow := _find_cached_flow(str(flow_id))
		if not flow.is_empty(): candidates.append(flow)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("peoplePerDay", 0.0)) > float(b.get("peoplePerDay", 0.0)))
	var chosen: Array = phase.get("flowIds", []).duplicate()
	var dialog := _new_confirmation_dialog()
	dialog.title = "选择本阶段要服务的出行"
	dialog.get_ok_button().text = "保存目标"
	dialog.get_cancel_button().text = "取消"
	var explanation := Label.new()
	explanation.text = "最多选择 3 组。状态会在这里显示：本阶段已接通、其他阶段已有服务或尚未接通。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(explanation)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 340)
	dialog.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var checks: Array[CheckBox] = []
	for flow in candidates.slice(0, 24):
		var flow_id := str(flow.get("id", ""))
		var from_point := _find_demand(str(flow.get("fromId", "")))
		var to_point := _find_demand(str(flow.get("toId", "")))
		var checkbox := CheckBox.new()
		checkbox.text = "%s → %s · 游戏设定约 %s 人次/日%s" % [str(flow.get("from", "起点")), str(flow.get("to", "目的地")), _number(int(round(float(flow.get("peoplePerDay", 0.0))))), " · 待核验" if not bool(from_point.get("verified", false)) or not bool(to_point.get("verified", false)) else ""]
		checkbox.button_pressed = chosen.has(flow_id)
		checkbox.tooltip_text = "地点类别：%s → %s；覆盖与接驳是游戏估算。" % [_type_name(str(from_point.get("type", ""))), _type_name(str(to_point.get("type", "")))]
		checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(checkbox)
		checks.append(checkbox)
	for checkbox in checks:
		checkbox.toggled.connect(_on_phase_flow_goal_toggled.bind(checks, checkbox))
	var allowed_ids: Array[String] = []
	for flow in candidates.slice(0, 24): allowed_ids.append(str(flow.get("id", "")))
	for raw_flow_id in chosen:
		if not allowed_ids.has(str(raw_flow_id)):
			var old_flow := _find_cached_flow(str(raw_flow_id))
			if not old_flow.is_empty():
				var old_check := CheckBox.new()
				old_check.text = "%s → %s · 已选目标" % [str(old_flow.get("from", "起点")), str(old_flow.get("to", "目的地"))]
				old_check.button_pressed = true
				old_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				rows.add_child(old_check)
				checks.append(old_check)
				allowed_ids.append(str(raw_flow_id))
	add_child(dialog)
	dialog.confirmed.connect(func():
		var selected_flows: Array[String] = []
		for index in range(checks.size()):
			if checks[index].button_pressed and index < allowed_ids.size(): selected_flows.append(allowed_ids[index])
		if selected_flows.size() > 3:
			_show_toast("每个阶段最多选择 3 组服务目标")
			dialog.queue_free()
			return
		history.execute("设置阶段服务目标", func(state: Dictionary):
			var target_phase := _find_planning_phase_in(state, phase_id)
			if not target_phase.is_empty(): target_phase["flowIds"] = selected_flows.duplicate()
		)
		dialog.queue_free()
		_refresh_left_panel()
		_autosave()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(600, 470))

func _on_phase_flow_goal_toggled(pressed: bool, checkboxes: Array[CheckBox], checkbox: CheckBox) -> void:
	if not pressed: return
	var selected_count := 0
	for item in checkboxes:
		if item.button_pressed: selected_count += 1
	if selected_count > 3:
		checkbox.set_pressed_no_signal(false)
		_show_toast("每个建设阶段最多指定 3 组出行")

func _find_planning_phase(phase_id: String) -> Dictionary:
	return _find_planning_phase_in(world, phase_id)

func _find_planning_phase_in(state: Dictionary, phase_id: String) -> Dictionary:
	for phase in state.get("planningPhases", []):
		if str(phase.get("id", "")) == phase_id: return phase
	return {}

func _set_current_planning_phase(phase_id: String) -> void:
	if str(world.get("currentPlanningPhaseId", "")) == phase_id: return
	history.execute("切换当前建设阶段", func(state: Dictionary): state["currentPlanningPhaseId"] = phase_id)
	_refresh_left_panel(); _autosave()

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
	var time_label := _label("第 %d 天 · %02d:%02d" % [elapsed / 1440 + 1, posmod(elapsed, 1440) / 60, posmod(elapsed, 60)], 15, MUTED)
	_stats_live_labels["time"] = time_label
	left_content.add_child(time_label)
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
		_stats_live_labels[str(metric[0])] = metric_value
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
		var average_label := _label("平均完整出行 · %.1f 分钟" % average, 17, TEXT, true)
		_stats_live_labels["average"] = average_label
		left_content.add_child(average_label)
	else:
		var average_label := _label("尚无完成行程，暂不显示平均耗时或效率评分。", 14, MUTED)
		_stats_live_labels["average"] = average_label
		left_content.add_child(average_label)
	var crowding_label := _label("高峰区间占用 · %.0f%%" % (float(sim.get("peakCrowding", 0.0)) * 100.0), 15, TEXT)
	_stats_live_labels["crowding"] = crowding_label
	left_content.add_child(crowding_label)
	var waiting_by_route: Dictionary = sim.get("waitingByRoute", {})
	left_content.add_child(_label("线路候车", 17, TEXT, true))
	left_content.add_child(_label("方向运力利用 · 近1个游戏小时", 14, MUTED))
	for route in world.get("routes", []):
		var route_id := str(route.get("id", ""))
		var current_headway := ServiceScheduleScript.headway_minutes(route, int(sim.get("elapsedSeconds", int(elapsed) * 60)))
		var line_row := _button("%s   等待 %s 人 · 当前班距 %d 分钟" % [str(route.get("name", "线路")), _number(int(waiting_by_route.get(route_id, 0))), current_headway], TEXT, PANEL_LIGHT, 14)
		line_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		line_row.custom_minimum_size.y = 42.0 * _ui_scale
		line_row.pressed.connect(func(): _focus_route(route_id))
		_stats_wait_buttons[route_id] = line_row
		left_content.add_child(line_row)
		var utilization_label := _label(_route_utilization_text(route_id), 14, MUTED)
		utilization_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats_utilization_labels[route_id] = utilization_label
		left_content.add_child(utilization_label)
	left_content.add_child(HSeparator.new())
	left_content.add_child(_label("15分钟统计 · 最近7个游戏日", 17, TEXT, true))
	var buckets: Array = sim.get("statisticsBuckets", [])
	for bucket in buckets.slice(maxi(0, buckets.size() - 8), buckets.size()):
		var attempted_total := 0
		var completed_total := 0
		for count in bucket.get("attemptedByFlow", {}).values(): attempted_total += int(count)
		for count in bucket.get("completedByFlow", {}).values(): completed_total += int(count)
		var start_minute := int(bucket.get("startMinute", 0))
		var clock := "%02d:%02d" % [posmod(start_minute, 1440) / 60, posmod(start_minute, 60)]
		left_content.add_child(_label("第%d天 %s · 发起 %s · 到达 %s" % [start_minute / 1440 + 1, clock, _number(attempted_total), _number(completed_total)], 13, MUTED))
	left_content.add_child(HSeparator.new())
	left_content.add_child(_label("实际旅程抽样 · 全城完成批次", 17, TEXT, true))
	var journey_records: Array = sim.get("journeyRecords", [])
	if journey_records.is_empty(): left_content.add_child(_label("暂无抽样记录；记录只展示实际完成的乘客批次。", 14, MUTED))
	for record_index in range(journey_records.size() - 1, maxi(-1, journey_records.size() - 9), -1):
		var raw_record: Variant = journey_records[record_index]
		if not raw_record is Dictionary: continue
		var record: Dictionary = raw_record
		var ids := str(record.get("flowId", "")).split(">")
		var from_demand := _find_demand(ids[0]) if ids.size() > 0 else {}
		var to_demand := _find_demand(ids[1]) if ids.size() > 1 else {}
		var record_button := _button("%s → %s\n%d人 · %.1f分钟 · %s" % [str(from_demand.get("name", "起点")), str(to_demand.get("name", "目的地")), int(record.get("count", 0)), float(record.get("durationMinutes", 0.0)), _format_game_clock(int(record.get("arrivalSeconds", 0)))], TEXT, PANEL_LIGHT, 13)
		record_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		record_button.custom_minimum_size.y = 54.0 * _ui_scale
		record_button.pressed.connect(_show_journey_record.bind(record.duplicate(true)))
		left_content.add_child(record_button)
	left_content.add_child(_label("以上均为游戏模拟。地图上的示意线路与客流数字不是现实运营预测。", 13, MUTED))

func _format_game_clock(absolute_seconds: int) -> String:
	var absolute_minutes := floori(float(absolute_seconds) / 60.0)
	return "第%d天 %02d:%02d" % [absolute_minutes / 1440 + 1, posmod(absolute_minutes, 1440) / 60, posmod(absolute_minutes, 60)]

func _route_utilization_text(route_id: String) -> String:
	var buckets: Array = world.get("simulation", {}).get("routeUtilizationBuckets", [])
	var now_minute := int(world.get("simulation", {}).get("elapsedMinutes", 420))
	var count := 0
	var load_sum := 0.0
	var empty_sum := 0.0
	var peak := 0.0
	for bucket in buckets:
		if now_minute - int(bucket.get("startMinute", now_minute)) > 60: continue
		for sample in bucket.get("byRoute", {}).values():
			if str(sample.get("routeId", "")) != route_id: continue
			var samples := int(sample.get("samples", 0))
			count += samples
			load_sum += float(sample.get("loadRatioSum", 0.0))
			empty_sum += float(sample.get("emptyEdgeRatioSum", 0.0))
			peak = maxf(peak, float(sample.get("peakLoadRatio", 0.0)))
	if count <= 0: return "运力利用：近1小时暂无足够的实际班次样本。"
	return "近1小时方向样本 %d 班次 · 平均载客率 %.0f%% · 空载区间比例 %.0f%% · 峰值 %.0f%%（游戏估算）" % [count, 100.0 * load_sum / float(count), 100.0 * empty_sum / float(count), 100.0 * peak]

func _update_stats_live_labels() -> void:
	if world.is_empty(): return
	var sim: Dictionary = world.get("simulation", {})
	var elapsed := int(sim.get("elapsedMinutes", sim.get("minute", 420)))
	var values := {"累计发起": int(sim.get("attempted", 0)), "已到达": int(sim.get("completed", 0)), "等候": int(sim.get("waiting", 0)), "在途": int(sim.get("inTransit", 0)), "已放弃": int(sim.get("abandoned", 0)), "中断记录": int(sim.get("interrupted", 0)), "无法接入": int(sim.get("unreachable", 0))}
	if _stats_live_labels.get("time") is Label: _stats_live_labels.time.text = "第 %d 天 · %02d:%02d" % [elapsed / 1440 + 1, posmod(elapsed, 1440) / 60, posmod(elapsed, 60)]
	for metric_name in values:
		var label: Variant = _stats_live_labels.get(str(metric_name))
		if label is Label: label.text = _number(int(values[metric_name]))
	var average_label: Variant = _stats_live_labels.get("average")
	if average_label is Label:
		var completed := int(sim.get("completed", 0))
		average_label.text = "平均完整出行 · %.1f 分钟" % (float(sim.get("tripMinutesTotal", 0.0)) / float(completed)) if completed > 0 else "尚无完成行程，暂不显示平均耗时或效率评分。"
	var crowding: Variant = _stats_live_labels.get("crowding")
	if crowding is Label: crowding.text = "高峰区间占用 · %.0f%%" % (float(sim.get("peakCrowding", 0.0)) * 100.0)
	var waiting_by_route: Dictionary = sim.get("waitingByRoute", {})
	for route in world.get("routes", []):
		var route_id := str(route.get("id", ""))
		var wait_button: Variant = _stats_wait_buttons.get(route_id)
		if wait_button is Button:
			var headway := ServiceScheduleScript.headway_minutes(route, int(sim.get("elapsedSeconds", elapsed * 60)))
			wait_button.text = "%s   等待 %s 人 · 当前班距 %d 分钟" % [str(route.get("name", "线路")), _number(int(waiting_by_route.get(route_id, 0))), headway]
		var utilization: Variant = _stats_utilization_labels.get(route_id)
		if utilization is Label: utilization.text = _route_utilization_text(route_id)

func _show_journey_record(record: Dictionary) -> void:
	var flow_parts := str(record.get("flowId", "")).split(">")
	var origin := _find_demand(flow_parts[0]) if flow_parts.size() > 0 else {}
	var destination := _find_demand(flow_parts[1]) if flow_parts.size() > 1 else {}
	var lines: Array[String] = []
	lines.append("出发：%s" % _format_game_clock(int(record.get("departureSeconds", 0))))
	lines.append("到达：%s · 用时 %.1f 分钟 · 批次 %d 人" % [_format_game_clock(int(record.get("arrivalSeconds", 0))), float(record.get("durationMinutes", 0.0)), int(record.get("count", 0))])
	lines.append("\n实际经过：")
	var steps: Array = record.get("steps", [])
	for step in steps:
		if not step is Dictionary: continue
		match str(step.get("type", "")):
			"rail":
				var route := WorldData.find_route(world, str(step.get("routeId", "")))
				var from_station := WorldData.find_station(world, str(step.get("fromStationId", "")))
				var to_station := WorldData.find_station(world, str(step.get("toStationId", "")))
				lines.append("· 乘坐%s：%s → %s" % [str(route.get("name", "地铁线路")), str(from_station.get("name", "车站")), str(to_station.get("name", "车站"))])
			"walk", "access": lines.append("· 地面步行约 %.0f 米（直线估算）" % float(step.get("distanceM", 0.0)))
			"transfer": lines.append("· 站内换乘步行，游戏估算 %.1f 分钟" % float(step.get("transferMinutes", step.get("minutes", 0.0))))
			"wait": lines.append("· 候车，游戏估算 %.1f 分钟" % float(step.get("minutes", 0.0)))
	var events: Array = record.get("events", [])
	if not events.is_empty():
		lines.append("\n批次事件：")
		for event in events:
			if not event is Dictionary: continue
			var station := WorldData.find_station(world, str(event.get("stationId", "")))
			var event_text := str(event.get("type", "事件"))
			match event_text:
				"departure": event_text = "需求出发"
				"train_board": event_text = "上车 · %s" % str(station.get("name", "车站"))
				"train_arrive": event_text = "列车到站 · %s" % str(station.get("name", "车站"))
				"step_complete": event_text = "步行／换乘完成"
			lines.append("· %s · %s" % [_format_game_clock(int(event.get("timeSeconds", 0))), event_text])
	var dialog := _new_confirmation_dialog()
	dialog.title = "实际旅程记录 · %s → %s" % [str(origin.get("name", "起点")), str(destination.get("name", "目的地"))]
	dialog.dialog_text = "\n".join(lines)
	dialog.add_button("定位起点", false, "origin")
	dialog.add_button("定位终点", false, "destination")
	var follow_index := 0
	for event in events:
		if not event is Dictionary or str(event.get("type", "")) not in ["train_board", "train_arrive"]: continue
		var event_station := WorldData.find_station(world, str(event.get("stationId", "")))
		if event_station.is_empty(): continue
		dialog.add_button("跟随 %s · %s" % [_format_game_clock(int(event.get("timeSeconds", 0))), str(event_station.get("name", "车站"))], false, "event_%d" % follow_index)
		follow_index += 1
		if follow_index >= 6: break
	add_child(dialog)
	dialog.custom_action.connect(func(action: StringName):
		dialog.queue_free()
		if str(action).begins_with("event_"):
			var action_index := int(str(action).trim_prefix("event_"))
			var followed := 0
			for event in events:
				if not event is Dictionary or str(event.get("type", "")) not in ["train_board", "train_arrive"]: continue
				var event_station := WorldData.find_station(world, str(event.get("stationId", "")))
				if event_station.is_empty(): continue
				if followed == action_index:
					_select_object("station", str(event_station.get("id", "")))
					map_view.center_on(event_station.get("latlng", [0, 0]), maxi(map_view.current_zoom, 14))
					return
				followed += 1
			return
		var demand: Dictionary = origin if action == &"origin" else destination
		if not demand.is_empty():
			_select_object("demand", str(demand.get("id", "")))
			map_view.center_on(demand.get("latlng", [0, 0]), maxi(map_view.current_zoom, 14))
	)
	dialog.popup_centered(Vector2i(mini(640, int(get_viewport_rect().size.x - 32.0)), mini(560, int(get_viewport_rect().size.y - 32.0))))

func _show_expected_journey(flow: Dictionary) -> void:
	var journey: Dictionary = flow.get("journey", {})
	if journey.is_empty() or not bool(flow.get("valid", false)):
		_show_issue("当前没有可用的完整路径。请检查站点覆盖、连续轨道及线路开通状态。", "预计旅程")
		return
	var lines: Array[String] = ["这是按当前规划与班次计算的预计旅程，不是实际乘客记录。", "", "预计总耗时：%.1f 分钟" % float(journey.get("totalMinutes", 0.0))]
	for step in journey.get("steps", []):
		if not step is Dictionary: continue
		match str(step.get("type", "")):
			"access", "walk": lines.append("· 地面步行约 %.0f 米，游戏估算 %.1f 分钟（直线接驳）" % [float(step.get("distanceM", 0.0)), float(step.get("minutes", 0.0))])
			"wait": lines.append("· 候车约 %.1f 分钟，按当前班距估算" % float(step.get("minutes", 0.0)))
			"transfer": lines.append("· 换乘步行约 %.1f 分钟" % float(step.get("transferMinutes", step.get("minutes", 0.0))))
			"rail":
				var route := WorldData.find_route(world, str(step.get("routeId", "")))
				var from_station := WorldData.find_station(world, str(step.get("fromStationId", "")))
				var to_station := WorldData.find_station(world, str(step.get("toStationId", "")))
				lines.append("· 乘坐%s：%s → %s，约 %.1f 分钟" % [str(route.get("name", "地铁线路")), str(from_station.get("name", "车站")), str(to_station.get("name", "车站")), float(step.get("minutes", 0.0))])
	var dialog := _new_accept_dialog()
	dialog.title = "预计旅程 · %s → %s" % [str(flow.get("from", "起点")), str(flow.get("to", "目的地"))]
	dialog.dialog_text = "\n".join(lines)
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(mini(620, int(get_viewport_rect().size.x - 32.0)), mini(520, int(get_viewport_rect().size.y - 32.0))))


func _tutorial_detail(step: int) -> String:
	match step:
		0: return "用「放置车站」在需求点附近建立站台；按 R 调整朝向。"
		1: return "使用「直线铺轨」或「曲线铺轨」连接站端；物理轨道不属于某条线路。"
		2: return "选择「创建运营线路」，按停站顺序点击车站并确认线路走向。"
		3: return "在线路详情检查并开通；车辆自动保障，站间距只影响运行时间。"
		4: return "按播放，批次乘客真正到达后才计入完成出行。"
	return "基础教学可以跳过，也可以从菜单重开。"

func _refresh_right_panel() -> void:
	tutorial_targets.erase("route_open")
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
		right_content.add_child(HSeparator.new())
		var complexity_toggle := _button("规划复杂度　%s" % ("▾" if _complexity_expanded else "▸"), TEXT, PANEL_LIGHT, 14)
		complexity_toggle.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
		complexity_toggle.pressed.connect(func(): _complexity_expanded = not _complexity_expanded; _refresh_right_panel())
		right_content.add_child(complexity_toggle)
		if _complexity_expanded:
			var complexity := _network_complexity_summary()
			right_content.add_child(_label("线路总里程　%.1f 公里\n最深施工　%.0f 米\n曲线区间　%d 段\n换乘车站　%d 座\n\n这些是游戏中的方案比较指标，不合成为工程评分。" % [float(complexity.get("lengthKm", 0.0)), float(complexity.get("deepestM", 0.0)), int(complexity.get("curves", 0)), int(complexity.get("transfers", 0))], 14, MUTED))

func _leave_neighborhood_challenge() -> void:
	if world.is_empty() or str(world.get("challengeMode", "free")) != "neighborhood": return
	world["challengeMode"] = "free"
	save_dirty = true
	_update_topbar()
	_refresh_left_panel()
	_refresh_right_panel()
	if not _autosave(false):
		_show_issue("挑战进度已保留在当前会话；保存失败，可从顶部重试。", "切回自由扩建")

func _network_complexity_summary() -> Dictionary:
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	var total_length := 0.0
	var deepest := 0.0
	var curves := 0
	for edge in TrackNetwork.all_physical_edges(world):
		total_length += TrackNetwork.edge_length_m(edge, world, ref_lat)
		if str(edge.get("geometry", "")) in ["bezier", "curve"]: curves += 1
		for node_id in TrackNetwork._edge_node_ids(edge, world):
			var node := TrackNetwork.find_node(world, node_id)
			deepest = minf(deepest, float(node.get("depthM", edge.get("depthM", -15.0))))
	var transfers := 0
	for station in world.get("stations", []):
		if station.get("routeIds", []).size() > 1: transfers += 1
	return {"lengthKm": total_length / 1000.0, "deepestM": absf(deepest), "curves": curves, "transfers": transfers}

func _station_details(station: Dictionary) -> void:
	var fixed_header: Control = _right_pinned_header if is_instance_valid(_right_pinned_header) else right_content
	var fixed_footer: Control = _right_pinned_footer if is_instance_valid(_right_pinned_footer) else right_content
	fixed_header.add_child(_label("车站详情", 20, TEXT, true))
	var service_status := _station_service_status(station)
	var service_label := _label("● %s" % str(service_status.get("text", "未接轨")), 15, Color(str(service_status.get("color", "#70848d"))), true)
	service_label.name = "StationServiceStatus"
	fixed_header.add_child(service_label)
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
	var transfer_marked := bool(station.get("plannedTransfer", false))
	var transfer_mark := _button("◎ %s拟换乘站" % ("取消" if transfer_marked else "标记为"), Color("#edc477"), Color("#3b3020"), 14)
	transfer_mark.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
	transfer_mark.pressed.connect(func(): _toggle_planned_transfer(str(station.id)))
	right_content.add_child(transfer_mark)
	if transfer_marked:
		var nearby_flows := _flows_near_station(station)
		var candidate_text := "标记只表示预留规划意向，不产生换乘。"
		if not nearby_flows.is_empty():
			candidate_text += "\n附近需求："
			for candidate in nearby_flows.slice(0, 2): candidate_text += "\n· %s → %s" % [str(candidate.get("from", "起点")), str(candidate.get("to", "目的地"))]
		var candidate_label := _label(candidate_text, 13, MUTED)
		candidate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right_content.add_child(candidate_label)
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

func _toggle_planned_transfer(station_id: String) -> void:
	var station := WorldData.find_station(world, station_id)
	if station.is_empty(): return
	var marked := not bool(station.get("plannedTransfer", false))
	history.execute("%s拟换乘站标记" % ("设置" if marked else "取消"), func(state: Dictionary): WorldData.find_station(state, station_id)["plannedTransfer"] = marked)
	map_view.requested_redraw(); _refresh_right_panel(); _refresh_left_panel(); _autosave()
	_show_toast("已标记为预留换乘位置" if marked else "已取消拟换乘标记；实际换乘仍由运营路径决定")

func _flows_near_station(station: Dictionary) -> Array[Dictionary]:
	_ensure_flow_cache()
	var position: Array = station.get("latlng", [])
	var ranked: Array[Dictionary] = []
	for flow in _flow_cache:
		if position.size() < 2: continue
		var origin: Array = flow.get("originLatLng", [])
		var destination: Array = flow.get("destinationLatLng", [])
		if origin.size() < 2 or destination.size() < 2: continue
		var d0 := _distance_m(position, origin)
		var d1 := _distance_m(position, destination)
		if mini(d0, d1) > 2500.0: continue
		var copy: Dictionary = flow.duplicate(false)
		copy["nearbyDistanceM"] = mini(d0, d1)
		ranked.append(copy)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("peoplePerDay", 0.0)) > float(b.get("peoplePerDay", 0.0)))
	return ranked

func _route_details(route: Dictionary) -> void:
	right_content.add_child(_label("线路详情", 17, TEXT, true))
	var extension_row := HFlowContainer.new()
	extension_row.add_theme_constant_override("h_separation", 6)
	var extend_start := _button("从起点继续扩建", TEAL, PANEL_LIGHT, 14)
	extend_start.pressed.connect(_begin_route_extension.bind(str(route.get("id", "")), true))
	extension_row.add_child(extend_start)
	var extend_end := _button("从终点继续扩建", TEAL, PANEL_LIGHT, 14)
	extend_end.pressed.connect(_begin_route_extension.bind(str(route.get("id", "")), false))
	extension_row.add_child(extend_end)
	right_content.add_child(extension_row)
	right_content.add_child(_label("扩建会保留线路身份；确认后线路暂停，检查并开通后才恢复运营。", 13, MUTED))
	right_content.add_child(_label("线路名称", 11, MUTED))
	var name_edit := LineEdit.new(); name_edit.text = str(route.get("name", "")); name_edit.text_submitted.connect(func(value: String): _rename_route(str(route.id), value)); name_edit.focus_exited.connect(func(): _rename_route(str(route.id), name_edit.text)); right_content.add_child(name_edit)
	right_content.add_child(_label("车辆与发车间隔", 14, MUTED))
	var vehicle_picker := OptionButton.new()
	for profile in WorldData.vehicles():
		vehicle_picker.add_item(str(profile.get("name", profile.get("id", "车型"))))
		vehicle_picker.set_item_metadata(vehicle_picker.item_count - 1, str(profile.get("id", "")))
	for i in range(vehicle_picker.item_count):
		if vehicle_picker.get_item_metadata(i) == str(route.get("vehicleId", "B-6")): vehicle_picker.select(i)
	vehicle_picker.item_selected.connect(func(index: int): _change_route_vehicle(str(route.id), str(vehicle_picker.get_item_metadata(index))))
	right_content.add_child(vehicle_picker)
	var schedule: Dictionary = ServiceScheduleScript.ensure_profile(route)
	var schedule_picker := OptionButton.new()
	schedule_picker.add_item("全天统一班距")
	schedule_picker.add_item("分时段班距")
	schedule_picker.select(1 if str(schedule.get("mode", "uniform")) == "time_of_day" else 0)
	schedule_picker.item_selected.connect(func(index: int): _change_schedule_mode(str(route.id), "time_of_day" if index == 1 else "uniform"))
	right_content.add_child(schedule_picker)
	if str(schedule.get("mode", "uniform")) == "time_of_day":
		for period in [["早高峰 · 07—10时", "peakAM"], ["晚高峰 · 16—19时", "peakPM"], ["平峰", "offPeak"]]:
			var schedule_row := HBoxContainer.new()
			schedule_row.add_child(_label(str(period[0]), 13, MUTED))
			var period_headway := SpinBox.new(); period_headway.min_value = 1; period_headway.max_value = 60; period_headway.step = 1; period_headway.value = int(schedule.get(str(period[1]), route.get("headway", 3))); period_headway.suffix = " 分"
			period_headway.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			period_headway.value_changed.connect(func(value: float): _change_schedule_headway(str(route.id), str(period[1]), int(value)))
			schedule_row.add_child(period_headway)
			right_content.add_child(schedule_row)
	else:
		var headway := SpinBox.new(); headway.min_value = 1; headway.max_value = 60; headway.step = 1; headway.value = int(route.get("headway", 3)); headway.suffix = " 分钟"
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
	check.name = "TutorialRoute_open"
	if not bool(world.get("tutorialDone", false)) and int(world.get("tutorialStep", 0)) == 2:
		check.add_theme_stylebox_override("normal", _style(Color("#246a52"), Color("#78edc4"), 8, 2))
	check.pressed.connect(_open_route); right_content.add_child(check); _register_tutorial_target("route_open", check)
	var del := _button("删除线路", Color("#ef8b8b"), Color("#41272d"), 12); del.pressed.connect(func(): _delete_route(str(route.id))); right_content.add_child(del)

func _station_service_status(station: Dictionary) -> Dictionary:
	var station_id := str(station.get("id", ""))
	var connected := false
	var start_node := TrackNetwork.station_node_id(station, "start")
	var end_node := TrackNetwork.station_node_id(station, "end")
	for edge in TrackNetwork.all_physical_edges(world):
		var node_ids := TrackNetwork._edge_node_ids(edge, world)
		if node_ids.has(start_node) or node_ids.has(end_node):
			connected = true
			break
	var open_routes := 0
	var repair_needed := false
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	for route in world.get("routes", []):
		if not bool(route.get("open", false)) or not route.get("stationOrder", []).has(station_id): continue
		var route_check := RoutePathScript.for_route(route, world, ref_lat)
		if bool(route_check.get("valid", false)):
			open_routes += 1
		else:
			repair_needed = true
	if open_routes > 0: return {"text": "运营中 · %d 条线路" % open_routes, "color": "#1c8a67"}
	if repair_needed: return {"text": "待修复 · 运营路径无效", "color": "#b34a4a"}
	if connected: return {"text": "已接轨 · 未运营", "color": "#bd842e"}
	return {"text": "未接轨", "color": "#72838d"}

func _begin_route_extension(route_id: String, from_start: bool) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	var directions: Array = route.get("directions", [])
	if directions.is_empty():
		_show_issue("这条线路没有可用的有向路径，先在详情中修复区间后再扩建。")
		return
	var direction: Dictionary = directions[0]
	var stops: Array[String] = []
	for raw_id in direction.get("stationIds", []): stops.append(str(raw_id))
	var paths: Array = direction.get("edgePathsBySegment", []).duplicate(true)
	if stops.size() < 2 or paths.size() < stops.size() - 1:
		_show_issue("线路中仍有待接通区间；先修复路径，再开始扩建。")
		return
	while paths.size() > stops.size() - 1: paths.pop_back()
	if from_start:
		stops.reverse()
		paths = _reverse_edge_paths(paths)
	_set_tool("line")
	route_extension_context = {"routeId": route_id, "routeName": str(route.get("name", "线路")), "baseStopCount": stops.size(), "baseSegmentPaths": paths.duplicate(true), "revision": int(world.get("revision", 0)), "fromStart": from_start}
	line_draft_stops = stops.duplicate()
	line_draft_path_options.clear()
	line_draft_path_choices.clear()
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23, 121.47])[0])
	for index in range(paths.size()):
		var fixed_path: Array = paths[index]
		var checked := TrackNetwork.ordered_station_path(stops[index], stops[index + 1], fixed_path, world, ref_lat)
		if not bool(checked.get("valid", false)):
			route_extension_context.clear()
			line_draft_stops.clear()
			_set_tool("select")
			_show_issue("原线路的已确认走向无法完整读取：%s" % str(checked.get("error", "路径无效")))
			return
		line_draft_path_options.append([checked])
		line_draft_path_choices.append(0)
	line_draft_segment_index = maxi(0, line_draft_path_options.size() - 1)
	selected_type = "route"
	selected_id = route_id
	active_route_id = route_id
	interaction_state.select_object("route", route_id)
	_update_line_draft_preview()
	_refresh_ui()
	var terminal_id := str(stops.back())
	var terminal: Dictionary = WorldData.find_station(world, terminal_id)
	if not terminal.is_empty(): map_view.center_on(terminal.get("latlng", [0, 0]), maxi(map_view.current_zoom, 14))
	_show_toast("已保留「%s」原有走向；从「%s」端继续添加停站。新段确认后线路暂停，不会自动开通。" % [str(route.get("name", "线路")), str(terminal.get("name", "终点站"))])

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
			right_content.add_child(_label("→ %s · 约 %s 人次/日\n%s" % [flow.get("to", "目的地"), _number(int(round(float(flow.get("peoplePerDay", 0))))), status], 13, MUTED))
			if bool(flow.get("valid", false)):
				var preview := _button("查看预计旅程", TEAL, PANEL_LIGHT, 13)
				preview.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
				preview.pressed.connect(_show_expected_journey.bind(flow.duplicate(true)))
				right_content.add_child(preview)
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
	for key in ["tool_station", "tool_track", "tool_line", "confirm_station", "confirm_track", "confirm_line"]:
		tutorial_targets.erase(str(key))
	for c in tool_panel.get_children():
		tool_panel.remove_child(c)
		c.queue_free()
	for c in tool_action_panel.get_children():
		tool_action_panel.remove_child(c)
		c.queue_free()
	tool_action_panel.visible = false
	if is_instance_valid(tool_context_panel):
		for c in tool_context_panel.get_children():
			tool_context_panel.remove_child(c)
			c.queue_free()
	var footer_instruction := _tool_instruction()
	if is_instance_valid(tool_instruction_label):
		tool_instruction_label.text = footer_instruction
		tool_instruction_label.visible = current_tool != "select"
		tool_instruction_label.add_theme_color_override("font_color", TEAL if current_tool == "station" else MUTED)
	var onboarding: Dictionary = world.get("onboarding", {})
	var guide_active := bool(onboarding.get("active", false)) and not _more_tools_expanded
	var tools: Array = [["select", "选择"], ["station", "车站"], ["track", "轨道"], ["line", "运营线路"]]
	var focus_spec := _onboarding_focus_spec() if guide_active else {}
	var coached_tool := str(focus_spec.get("tool", ""))
	for item in tools:
		var active: bool = current_tool == item[0] or (str(item[0]) == "track" and current_tool in ["track", "track_curve"])
		var coached := guide_active and str(item[0]) == coached_tool
		var button := _button(item[1], TEAL if active or coached else TEXT, Color("#174037") if active else Color("#1c4039") if coached else PANEL_LIGHT, 14)
		button.name = "TutorialTool_%s" % str(item[0])
		button.custom_minimum_size = Vector2(118.0 * minf(_ui_scale, 1.25), 46.0 * minf(_ui_scale, 1.25))
		button.set_meta("metro_core_tool", true)
		if coached: button.tooltip_text = "当前教学建议使用此工具；其他工具仍可自由使用"
		button.pressed.connect(func(): _set_tool(str(item[0])))
		tool_panel.add_child(button)
		if str(item[0]) in ["station", "track", "line"]: _register_tutorial_target("tool_%s" % str(item[0]), button)
	if not guide_active and _more_tools_expanded:
		for item in [["track_curve", "曲线轨道"], ["curve", "调曲线"], ["delete", "拆除"]]:
			var button := _button(str(item[1]), TEAL if current_tool == item[0] else TEXT, PANEL_LIGHT, 14)
			button.custom_minimum_size = Vector2(108.0 * minf(_ui_scale, 1.25), 44.0 * minf(_ui_scale, 1.25))
			button.set_meta("metro_core_tool", true)
			button.pressed.connect(func(): _set_tool(str(item[0])))
			tool_panel.add_child(button)
	var more := _button("收起更多 ▾" if _more_tools_expanded else "更多工具 ▸", MUTED, PANEL_LIGHT, 13)
	more.custom_minimum_size.y = 44.0 * minf(_ui_scale, 1.25)
	more.set_meta("metro_core_tool", true)
	more.pressed.connect(func(): _more_tools_expanded = not _more_tools_expanded; _refresh_tools())
	tool_panel.add_child(more)
	if current_tool == "station" and not map_view.draft_station.is_empty():
		var confirm := _button("确认任务车站" if bool(onboarding.get("active", false)) else "确认站点", TEAL, Color("#164034"), 14); confirm.name = "TutorialAction_confirm_station"; confirm.disabled = map_view.draft_conflict; confirm.pressed.connect(_confirm_station); _add_tool_action(confirm); _register_tutorial_target("confirm_station", confirm)
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
			var confirm_track := _button("确认轨道段", Color("#eafff8"), Color("#17644f"), 14); confirm_track.name = "TutorialAction_confirm_track"; confirm_track.disabled = not map_view.track_preview_conflict.is_empty(); confirm_track.pressed.connect(_commit_track_preview); _add_tool_action(confirm_track); _register_tutorial_target("confirm_track", confirm_track)
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
		var extension_active := not route_extension_context.is_empty()
		var line_hint_text := "延伸「%s」· 停站 %d 座" % [str(route_extension_context.get("routeName", "线路")), line_draft_stops.size()] if extension_active else "停站 %d 座" % line_draft_stops.size()
		var line_hint := _button(line_hint_text, TEAL, PANEL_LIGHT, 13); line_hint.disabled = true; tool_panel.add_child(line_hint)
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
		var can_confirm_line := line_draft_stops.size() > int(route_extension_context.get("baseStopCount", 0)) if extension_active else line_draft_stops.size() >= 2
		if can_confirm_line:
			var confirm_line := _button("确认扩建并暂停线路" if extension_active else "确认线路走向", Color("#eafff8"), Color("#17644f"), 14); confirm_line.name = "TutorialAction_confirm_line"; confirm_line.pressed.connect(_confirm_operating_line); _add_tool_action(confirm_line); _register_tutorial_target("confirm_line", confirm_line)
		var minimum_stops := int(route_extension_context.get("baseStopCount", 0)) if extension_active else 0
		var undo_stop := _button("撤回上一站", MUTED, PANEL_LIGHT, 13); undo_stop.disabled = line_draft_stops.size() <= minimum_stops; undo_stop.pressed.connect(func(): if line_draft_stops.size() > minimum_stops: line_draft_stops.pop_back(); _update_line_draft_preview(); _refresh_tools()); _add_tool_action(undo_stop)
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
	for control in tool_panel.get_children().duplicate():
		if bool(control.get_meta("metro_core_tool", false)): continue
		tool_panel.remove_child(control)
		tool_context_panel.add_child(control)
	for control in tool_action_panel.get_children().duplicate():
		tool_action_panel.remove_child(control)
		tool_context_panel.add_child(control)
	if current_tool != "select":
		tool_context_panel.add_child(HSeparator.new())
		tool_context_panel.add_child(_label("当前操作", 20, TEXT, true))
		var context_instruction := _label(_tool_instruction(), 14, MUTED)
		context_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tool_context_panel.add_child(context_instruction)
		tool_context_panel.move_child(context_instruction, 1)
		_right_requested = true
	interaction_state.set_tool(current_tool)
	interaction_state.phase = "choose_snap" if not endpoint_choice_candidates.is_empty() else "preview" if current_tool == "station" and not map_view.draft_station.is_empty() or current_tool in ["track", "track_curve"] and not map_view.track_end_ref.is_empty() else "active" if current_tool != "select" else "idle"
	interaction_state.select_object(selected_type, selected_id)
	if is_instance_valid(_right_panel_button): _right_panel_button.text = "建设 ▾" if current_tool != "select" else "详情 ▾"
	call_deferred("_update_responsive_layout")
	_update_tutorial_spotlight()

func _add_tool_action(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 44.0 * minf(_ui_scale, 1.25))
	tool_action_panel.visible = true
	tool_action_panel.add_child(button)

func _register_tutorial_target(key: String, control: Control) -> void:
	if is_instance_valid(control): tutorial_targets[key] = control

func _tool_instruction() -> String:
	match current_tool:
		"station":
			if map_view.draft_conflict: return "位置冲突：站体与现有车站重叠，请移动或旋转。"
			return "建站：点空地放置预览，可拖动、按 R 转向，再确认。" if map_view.draft_station.is_empty() else "站址预览有效：确认后加入规划。"
		"track": return "直线铺轨：点起点，再点终点预览，确认后写入轨网。"
		"track_curve": return "曲线铺轨：点起点、控制点和终点预览，再确认写入。"
		"line":
			if not route_extension_context.is_empty(): return "延伸「%s」：原有停站与走向已锁定；点击下一座接轨车站，确认后线路暂停，检查并开通恢复。" % str(route_extension_context.get("routeName", "线路"))
			return "创建运营线路：按停靠顺序点击已接轨车站；可再次点击首站闭合环线。"
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
	route_extension_context.clear()
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
	elif hit_type == "demand":
		_select_object("demand", hit_id)
		_record_onboarding_demand_viewed(hit_id)
	else:
		selected_type = ""; selected_id = ""
		interaction_state.clear_selection()
		if _layout_narrow:
			_left_requested = false
			_right_requested = false
		elif get_viewport_rect().size.x / maxf(1.0, _ui_scale) < 1440.0:
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
		if _track_ref_is_snapped(ref): _play_ui_feedback("snap")
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
		if snapped_target: _play_ui_feedback("snap")
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
		var phase_id := str(state.get("currentPlanningPhaseId", "phase_1"))
		var edge := {"id": edge_id, "aNodeId": a_id, "bNodeId": b_id, "geometry": candidate.geometry, "controlA": candidate.controlA, "controlB": candidate.controlB, "depthM": candidate.depthM, "routeIds": [], "speedLimitKmh": -1.0, "planningPhaseId": phase_id}
		state.trackEdges.append(edge)
		for phase in state.get("planningPhases", []):
			if str(phase.get("id", "")) != phase_id: continue
			if not phase.has("edgeIds"): phase["edgeIds"] = []
			phase.edgeIds.append(edge_id)
			break
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

func _track_ref_is_snapped(ref: Dictionary) -> bool:
	return not str(ref.get("nodeId", "")).is_empty() or not str(ref.get("splitEdgeId", "")).is_empty()

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
	var phase_id := str(edge.get("planningPhaseId", ""))
	if phase_id.is_empty():
		for phase in state.get("planningPhases", []):
			if phase.get("edgeIds", []).has(edge_id): phase_id = str(phase.get("id", "")); break
	var left := {"id": base_id + "_a", "aNodeId": ends[0], "bNodeId": split_node.id, "geometry": geometry, "routeIds": shared_routes.duplicate(), "speedLimitKmh": edge.get("speedLimitKmh", -1.0), "depthM": (depth_a + split_depth) * 0.5, "planningPhaseId":phase_id}
	var right := {"id": base_id + "_b", "aNodeId": split_node.id, "bNodeId": ends[1], "geometry": geometry, "routeIds": shared_routes.duplicate(), "speedLimitKmh": edge.get("speedLimitKmh", -1.0), "depthM": (split_depth + depth_b) * 0.5, "planningPhaseId":phase_id}
	if geometry == "bezier":
		left["controlA"] = [(q0 - p0).x, (q0 - p0).y]
		left["controlB"] = [(r0 - split_point).x, (r0 - split_point).y]
		right["controlA"] = [(r1 - split_point).x, (r1 - split_point).y]
		right["controlB"] = [(q2 - p3).x, (q2 - p3).y]
	state.trackEdges = state.get("trackEdges", []).filter(func(item: Dictionary): return str(item.get("id", "")) != edge_id)
	state.trackEdges.append(left); state.trackEdges.append(right)
	if not phase_id.is_empty():
		for phase in state.get("planningPhases", []):
			if str(phase.get("id", "")) != phase_id: continue
			var phase_edge_ids: Array = phase.get("edgeIds", [])
			phase_edge_ids.erase(edge_id)
			if not phase_edge_ids.has(str(left.id)): phase_edge_ids.append(str(left.id))
			if not phase_edge_ids.has(str(right.id)): phase_edge_ids.append(str(right.id))
			phase["edgeIds"] = phase_edge_ids
			break
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
	var had_step := not map_view.draft_station.is_empty() or not map_view.link_start.is_empty() or not map_view.track_start_ref.is_empty() or not map_view.track_end_ref.is_empty() or not map_view.track_control_latlng.is_empty() or not line_draft_stops.is_empty() or not repair_path_options.is_empty() or station_construction_draft.kind == "move_station"
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
	elif current_tool == "line" and not line_draft_stops.is_empty():
		var base_stop_count := int(route_extension_context.get("baseStopCount", 0))
		if not route_extension_context.is_empty() and line_draft_stops.size() <= base_stop_count:
			route_extension_context.clear()
			current_tool = "select"
			line_draft_stops.clear(); line_draft_path_options.clear(); line_draft_path_choices.clear()
		else:
			line_draft_stops.pop_back()
			_update_line_draft_preview()
	elif current_tool == "repair_route_segment":
		_clear_route_repair_draft()
		current_tool = "select"
	else:
		current_tool = "select"
	map_view.tool = current_tool
	map_view.cancel_pointer_interaction()
	map_view.requested_redraw(); _refresh_tools()
	if had_step: _play_ui_feedback("cancel")

func _set_tool(new_tool: String) -> void:
	if new_tool == "connect": new_tool = "track"
	if new_tool == current_tool:
		_cancel_tool_step(); return
	var canceled_pending := not map_view.draft_station.is_empty() or not map_view.link_start.is_empty() or not map_view.track_start_ref.is_empty() or not map_view.track_end_ref.is_empty() or not map_view.track_control_latlng.is_empty() or not line_draft_stops.is_empty() or not repair_path_options.is_empty() or station_construction_draft.kind == "move_station"
	map_view.draft_station = {}; map_view.link_start = {}; map_view.track_start_ref = {}; map_view.track_end_ref = {}; map_view.track_control_latlng = []; map_view.track_preview_conflict = ""; map_view.track_preview_notice = ""
	map_view.cancel_pointer_interaction()
	map_view.clear_curve_preview()
	line_draft_stops.clear()
	line_draft_path_options.clear(); line_draft_path_choices.clear()
	line_draft_segment_index = -1
	route_extension_context.clear()
	_clear_route_repair_draft()
	endpoint_choice_candidates.clear(); map_view.endpoint_choice_candidates.clear()
	map_view.line_draft_points.clear()
	current_tool = new_tool
	if current_tool != "select":
		_right_requested = true
		if _layout_narrow: _left_requested = false
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
	if canceled_pending: _play_ui_feedback("cancel")

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
	var dialog := _new_confirmation_dialog()
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
		history.execute("调整发车间隔", func(state: Dictionary): ServiceScheduleScript.set_headway(WorldData.find_route(state, route_id), "uniform", value))
		SimulationEngineScript.reschedule_route(world, route_id)
		_after_planning_change("发车间隔已更新")
	change.call()

func _change_schedule_mode(route_id: String, mode: String) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	var profile: Dictionary = route.get("serviceSchedule", {})
	if str(profile.get("mode", "uniform")) == mode: return
	var change := func():
		history.execute("切换班次模式", func(state: Dictionary): ServiceScheduleScript.set_mode(WorldData.find_route(state, route_id), mode))
		SimulationEngineScript.reschedule_route(world, route_id)
		_after_planning_change("班次模式已更新；下一班按新间隔安排")
	change.call()

func _change_schedule_headway(route_id: String, period: String, value: int) -> void:
	var route := WorldData.find_route(world, route_id)
	if route.is_empty(): return
	var profile: Dictionary = route.get("serviceSchedule", {})
	if int(profile.get(period, route.get("headway", 3))) == value: return
	var period_name: String = {"peakAM": "早高峰", "peakPM": "晚高峰", "offPeak": "平峰"}.get(period, "时段")
	var change := func():
		history.execute("调整%s班距" % period_name, func(state: Dictionary): ServiceScheduleScript.set_headway(WorldData.find_route(state, route_id), period, value))
		SimulationEngineScript.reschedule_route(world, route_id)
		_after_planning_change("%s班距已更新；既有列车保持原时刻" % period_name)
	change.call()

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
	if kind == "demand" and map_view.analysis_mode == "accessibility": _update_accessibility_for_demand(object_id)
	_right_requested = true
	if _layout_narrow: _left_requested = false
	interaction_state.select_object(kind, object_id)
	_update_responsive_layout()
	map_view.active_route_id = active_route_id
	map_view.selected_type = kind; map_view.selected_id = object_id; map_view.requested_redraw()
	_refresh_ui()

func _set_map_analysis_mode(mode: String) -> void:
	if not is_instance_valid(map_view): return
	map_view.analysis_mode = mode if mode in ["planning", "demand", "accessibility", "operations"] else "planning"
	map_view.show_network = true
	map_view.show_demand = mode in ["demand", "accessibility"]
	accessibility_minutes_by_demand.clear()
	map_view.reachability_minutes_by_demand = accessibility_minutes_by_demand
	if mode == "accessibility" and selected_type == "demand": _update_accessibility_for_demand(selected_id)
	map_view.requested_redraw()
	if mode == "accessibility": _show_toast("点选一个需求地点；按完整旅程时间分为15、30、45分钟，接驳仍是直线估算")
	elif mode == "operations": _show_toast("红色区间表示最近模拟时段出现高占用；没有红线时当前没有记录到瓶颈")

func _update_accessibility_for_demand(origin_id: String) -> void:
	if not is_instance_valid(map_view): return
	var origin := _find_demand(origin_id)
	if origin.is_empty(): return
	var city := WorldData.city(active_city_id)
	var ref_lat := float(city.get("center", [31.23, 121.47])[0])
	var network := JourneyModelScript.build_network(world, ref_lat)
	var reachability: Dictionary = {}
	for destination in city.get("demand", []):
		var destination_id := str(destination.get("id", ""))
		if destination_id == origin_id: continue
		var journey := JourneyModelScript.find_journey(origin, destination, world, network, ref_lat)
		reachability[destination_id] = float(journey.get("totalMinutes", INF)) if bool(journey.get("valid", false)) else INF
	accessibility_minutes_by_demand = reachability
	map_view.reachability_minutes_by_demand = reachability
	map_view.requested_redraw()

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
	var schedules_before := _capture_route_schedules(world)
	var label := history.undo()
	if label.is_empty(): _show_toast("没有可撤销的规划操作"); return
	_reschedule_changed_routes(schedules_before)
	_play_ui_feedback("cancel")
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

func _capture_route_schedules(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for route in state.get("routes", []):
		result[str(route.get("id", ""))] = JSON.stringify([route.get("headway", 3), route.get("serviceSchedule", {})])
	return result

func _reschedule_changed_routes(previous: Dictionary) -> void:
	for route in world.get("routes", []):
		var route_id := str(route.get("id", ""))
		var before := str(previous.get(route_id, ""))
		var after := JSON.stringify([route.get("headway", 3), route.get("serviceSchedule", {})])
		if not before.is_empty() and before != after:
			SimulationEngineScript.reschedule_route(world, route_id)

func _do_redo() -> void:
	if world.is_empty(): return
	world.simulation.paused = true
	var schedules_before := _capture_route_schedules(world)
	var label := history.redo()
	if label.is_empty(): _show_toast("没有可重做的操作"); return
	_reschedule_changed_routes(schedules_before)
	_play_ui_feedback("confirm")
	selected_type = ""; selected_id = ""; map_view.set_world(world); _update_tutorial(); _autosave(); _refresh_ui(); _show_toast("已重做：%s" % label)

func _toggle_pause() -> void:
	world.simulation.paused = not bool(world.simulation.get("paused", true))
	if not bool(world.simulation.get("paused", true)):
		var onboarding: Dictionary = world.get("onboarding", {})
		if bool(onboarding.get("active", false)) and int(onboarding.get("step", 0)) == 6 and not bool(onboarding.get("observationStarted", false)):
			onboarding["observationStarted"] = true
			onboarding["observationStartMinute"] = int(world.simulation.get("elapsedMinutes", 420))
			world["onboarding"] = onboarding
			_refresh_onboarding_card()
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
	var next_elapsed_minute := int(world.simulation.get("elapsedMinutes", world.simulation.get("minute", 420))) + 1
	var event_messages := CityProgressionScript.advance_events(world, next_elapsed_minute)
	var event_signature := CityProgressionScript.event_signature(world)
	world.simulation["currentEventSignature"] = event_signature
	var minute_flows: Array[Dictionary] = []
	for flow in _flow_cache:
		var minute_flow := flow.duplicate(false)
		minute_flow["peakMultiplier"] = _flow_peak_multiplier(flow, hour, peak) * CityProgressionScript.multiplier_for_flow(world, flow)
		minute_flow["eventSignature"] = event_signature
		minute_flows.append(minute_flow)
	var onboarding: Dictionary = world.get("onboarding", {})
	var observe_target := bool(onboarding.get("active", false)) and bool(onboarding.get("observationStarted", false))
	var target_flow_id := "%s>%s" % [str(onboarding.get("originId", "")), str(onboarding.get("destinationId", ""))]
	var target_flow := _onboarding_flow() if observe_target else {}
	var sim_result := SimulationEngineScript.step_one_minute(world, minute_flows, 1.0)
	for event_message in event_messages:
		var prefix := "城市变化预告" if str(event_message.get("kind", "")) == "announcement" else "城市事件" if str(event_message.get("kind", "")) == "started" else "活动结束"
		_show_toast("%s：%s。客流变化为游戏设定。" % [prefix, str(event_message.get("message", event_message.get("title", "")))])
	if not event_messages.is_empty() and left_tab == "tasks" and not bool(world.get("onboarding", {}).get("active", false)):
		_refresh_left_panel()
	var stage_update := CityProgressionScript.update_stage(world, _flow_cache, int(world.simulation.get("elapsedMinutes", world.simulation.minute)))
	if bool(stage_update.get("changed", false)):
		var result: Dictionary = stage_update.get("result", {})
		_play_ui_feedback("confirm")
		var completed_count := int(result.get("completed", 0))
		var outcome := "实际到达 %s 人次" % _number(completed_count) if result.has("completed") else str(result.get("note", "已记录当前状态"))
		_show_toast("章节完成：%s · %s" % [str(result.get("title", "城市目标")), outcome])
		_refresh_left_panel()
		_autosave(false)
	var previous_completed_goals: int = world.get("goalBoard", {}).get("completed", []).size()
	var goals_changed := NeighborhoodGoalsScript.update(world, _flow_cache, int(world.simulation.get("elapsedMinutes", world.simulation.minute)))
	if goals_changed: _refresh_left_panel()
	if int(world.get("goalBoard", {}).get("completed", []).size()) > previous_completed_goals:
		_play_ui_feedback("confirm")
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
	tutorial_targets.erase("onboarding_more")
	for child in onboarding_panel.get_children(): child.queue_free()
	var onboarding: Dictionary = world.get("onboarding", {}) if not world.is_empty() else {}
	var active := bool(onboarding.get("active", false))
	onboarding_panel.visible = active
	if not active: return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.add_theme_constant_override("margin_left", 11); box.add_theme_constant_override("margin_right", 11)
	box.add_theme_constant_override("margin_top", 8); box.add_theme_constant_override("margin_bottom", 8)
	onboarding_panel.add_child(box)
	var step := int(onboarding.get("step", 0))
	var mission := OnboardingScript.mission(active_city_id)
	var headings := ["查看出行需求", "建设起点车站", "建设终点车站", "连接两座车站", "安排运营线路", "开通线路", "观察乘客", "查看下一项目标"]
	box.add_child(_label("街区规划引导 · %s" % ("基础线路已接通" if step >= 7 else "第 %d 步" % (step + 1)), 13, TEAL, true))
	box.add_child(_label(headings[clampi(step, 0, headings.size() - 1)], 17, TEXT, true))
	if step == 0:
		box.add_child(_label("%s → %s" % [str(_find_demand(str(onboarding.get("originId", ""))).get("name", "起点")), str(_find_demand(str(onboarding.get("destinationId", ""))).get("name", "目的地"))], 14, MUTED))
	var error_text := str(onboarding.get("lastError", ""))
	if not error_text.is_empty():
		var error_label := _label("需要处理：" + error_text, 14, Color("#ffad91"), true)
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(error_label)
	var more := MenuButton.new()
	more.text = "原因与选项 ▾"
	more.custom_minimum_size.y = roundi(36.0 * minf(_ui_scale, 1.25))
	more.add_theme_font_size_override("font_size", roundi(14.0 * _ui_scale))
	more.add_theme_color_override("font_color", MUTED)
	more.add_theme_stylebox_override("normal", _style(PANEL_LIGHT, BORDER, 8, 1))
	more.add_theme_stylebox_override("hover", _style(PANEL_LIGHT.lightened(0.1), BORDER, 8, 1))
	var menu := more.get_popup()
	menu.add_item("为什么这样做？", 0)
	menu.add_separator()
	menu.add_item("跳过引导", 1)
	menu.add_item("查看全城", 2)
	menu.add_item("返回任务位置", 3)
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
	_register_tutorial_target("onboarding_more", more)
	if _onboarding_reason_expanded:
		var reason := _label(str(mission.get("reason", "")) + " 出行虚线表示需求方向，不是建议照着修建的轨道。", 14, MUTED)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(reason)
	_update_tutorial_spotlight()

func _onboarding_focus_spec() -> Dictionary:
	var onboarding: Dictionary = world.get("onboarding", {})
	if not bool(onboarding.get("active", false)): return {}
	var step := int(onboarding.get("step", 0))
	var origin_id := str(onboarding.get("originId", ""))
	var destination_id := str(onboarding.get("destinationId", ""))
	var origin := _find_demand(origin_id)
	var destination := _find_demand(destination_id)
	var visited: Array = onboarding.get("visitedDemandIds", [])
	match step:
		0:
			var next_id := origin_id if not visited.has(origin_id) else destination_id
			var point := origin if next_id == origin_id else destination
			if point.is_empty(): return {}
			return {"kind":"map", "latlng":point.get("latlng", []), "radius":23.0, "shape":"circle", "message":"点击 %s 地点查看需求" % ("A" if next_id == origin_id else "B")}
		1, 2:
			if current_tool != "station": return _focus_control("tool_station", "点击下方「车站」", "station")
			if map_view.draft_station.is_empty():
				var target_point: Dictionary = origin if step == 1 else destination
				if target_point.is_empty(): return {}
				return {"kind":"map", "latlng":target_point.get("latlng", []), "radius":68.0, "shape":"circle", "message":"在 %s 附近点击，放置车站预览" % ("A" if step == 1 else "B")}
			return _focus_control("confirm_station", "点击这里确认%s车站" % ("第一座" if step == 1 else "第二座"))
		3:
			if current_tool not in ["track", "track_curve"]: return _focus_control("tool_track", "点击下方「轨道」", "track")
			if not map_view.track_end_ref.is_empty(): return _focus_control("confirm_track", "点击这里确认轨道")
			var origin_station := WorldData.find_station(world, str(onboarding.get("originStationId", "")))
			var destination_station := WorldData.find_station(world, str(onboarding.get("destinationStationId", "")))
			if map_view.track_start_ref.is_empty():
				if origin_station.is_empty(): return {}
				return _focus_station_endpoint(origin_station, "end", "点击第一站的 B 端作为起点")
			if current_tool == "track_curve" and map_view.track_control_latlng.is_empty():
				if origin_station.is_empty() or destination_station.is_empty(): return {}
				return {"kind":"map", "latlng":_midpoint_latlng(origin_station.get("latlng", []), destination_station.get("latlng", [])), "radius":20.0, "shape":"circle", "message":"点击线路中部，确定曲线方向"}
			var start_station_id := str(map_view.track_start_ref.get("stationId", ""))
			var target_station: Dictionary = origin_station if start_station_id == str(destination_station.get("id", "")) else destination_station
			if target_station.is_empty(): return {}
			var start_latlng: Array = map_view.track_start_ref.get("latlng", [])
			var side := _closest_station_side(target_station, start_latlng)
			return _focus_station_endpoint(target_station, side, "点击另一座车站的 %s 端" % ("A" if side == "start" else "B"))
		4:
			if current_tool != "line": return _focus_control("tool_line", "点击下方「运营线路」", "line")
			var origin_station_id := str(onboarding.get("originStationId", ""))
			var destination_station_id := str(onboarding.get("destinationStationId", ""))
			if not line_draft_stops.has(origin_station_id):
				var station_a := WorldData.find_station(world, origin_station_id)
				return _focus_station(station_a, "点击第一座车站") if not station_a.is_empty() else {}
			if not line_draft_stops.has(destination_station_id):
				var station_b := WorldData.find_station(world, destination_station_id)
				return _focus_station(station_b, "点击第二座车站") if not station_b.is_empty() else {}
			return _focus_control("confirm_line", "点击这里确认运营线路")
		5:
			return _focus_control("route_open", "点击「检查并开通此线路」")
		6:
			if not bool(onboarding.get("observationStarted", false)) or bool(world.get("simulation", {}).get("paused", true)):
				return _focus_control("play", "点击顶部播放，开始观察乘客")
			return _focus_control("stats", "等待乘客实际到达；进度显示在这里")
		7:
			if left_tab != "tasks": return _focus_control("tab_tasks", "点击左侧「任务」，查看下一项扩建目标")
			return _focus_control("campaign_next", "点击这里查看下一项扩建目标")
	return {}

func _focus_control(key: String, prompt: String, tool: String = "") -> Dictionary:
	return {"kind":"control", "key":key, "tool":tool, "message":prompt}

func _focus_station(station: Dictionary, prompt: String) -> Dictionary:
	if station.is_empty(): return {}
	return {"kind":"map", "latlng":station.get("latlng", []), "radius":24.0, "shape":"circle", "message":prompt}

func _focus_station_endpoint(station: Dictionary, side: String, prompt: String) -> Dictionary:
	return {"kind":"map", "latlng":WorldData.station_endpoint(station, side), "radius":17.0, "shape":"circle", "message":prompt}

func _closest_station_side(station: Dictionary, from_latlng: Array) -> String:
	if from_latlng.size() < 2: return "start"
	var a := WorldData.station_endpoint(station, "start")
	var b := WorldData.station_endpoint(station, "end")
	return "start" if _distance_m(a, from_latlng) <= _distance_m(b, from_latlng) else "end"

func _midpoint_latlng(a: Array, b: Array) -> Array:
	if a.size() < 2 or b.size() < 2: return []
	return [(float(a[0]) + float(b[0])) * 0.5, (float(a[1]) + float(b[1])) * 0.5]

func _update_tutorial_spotlight() -> void:
	if not is_instance_valid(tutorial_spotlight): return
	var spec := _onboarding_focus_spec()
	if spec.is_empty():
		_tutorial_focus_signature = ""
		tutorial_spotlight.clear_focus()
		return
	var prompt := str(spec.get("message", ""))
	var focus_signature := "%d|%s|%s|%s" % [int(world.get("onboarding", {}).get("step", -1)), str(spec.get("kind", "")), str(spec.get("key", "")), prompt]
	if str(spec.get("kind", "")) == "map":
		var signature_latlng: Array = spec.get("latlng", [])
		if signature_latlng.size() >= 2:
			focus_signature += "|%.7f|%.7f" % [float(signature_latlng[0]), float(signature_latlng[1])]
	var focus_changed := focus_signature != _tutorial_focus_signature
	var rect := Rect2()
	var shape := str(spec.get("shape", "rect"))
	if str(spec.get("kind", "")) == "control":
		var key := str(spec.get("key", ""))
		if key == "route_open" and (not _right_requested or not _right_panel.visible):
			_right_requested = true
			if _layout_narrow: _left_requested = false
			_update_responsive_layout()
			_refresh_right_panel()
		elif key in ["tab_tasks", "campaign_next"] and (not _left_requested or not _left_panel.visible):
			_left_requested = true
			if _layout_narrow: _right_requested = false
			_update_responsive_layout()
			if key == "campaign_next": _refresh_left_panel()
		var target: Control = tutorial_targets.get(key) as Control
		if not is_instance_valid(target) or not target.is_visible_in_tree() or target.size.x <= 0.0 or target.size.y <= 0.0:
			tutorial_spotlight.clear_focus()
			return
		# Confirmation controls live in the construction details scroll area. Keep
		# the actual button on screen when a tutorial step points to it; otherwise
		# its off-screen rectangle can line up with the pinned delete action below.
		if focus_changed and key in ["confirm_station", "confirm_track", "confirm_line"]:
			call_deferred("_scroll_tutorial_confirmation_into_view", focus_signature)
		var target_transform := target.get_global_transform_with_canvas()
		var overlay_inverse := tutorial_spotlight.get_global_transform_with_canvas().affine_inverse()
		var p0 := overlay_inverse * target_transform * Vector2.ZERO
		var p1 := overlay_inverse * target_transform * target.size
		rect = _rect_from_corners(p0, p1)
	else:
		var latlng: Array = spec.get("latlng", [])
		if latlng.size() < 2: tutorial_spotlight.clear_focus(); return
		var local_point := map_view._to_screen(latlng)
		# During a fresh scene build the anchored map can briefly be smaller than
		# the spotlight's inset. Wait for layout instead of constructing a negative
		# Rect2, then _process will resolve the real target on the next frame.
		if map_view.size.x <= 40.0 or map_view.size.y <= 40.0:
			_tutorial_map_size = map_view.size
			tutorial_spotlight.clear_focus()
			return
		var map_rect := Rect2(Vector2.ZERO, map_view.size)
		var resized_map := map_view.size != _tutorial_map_size
		if not map_rect.grow(-20.0).has_point(local_point) and (focus_changed or resized_map):
			map_view.center_on(latlng, maxi(map_view.current_zoom, 14))
			local_point = map_view._to_screen(latlng)
		_tutorial_map_size = map_view.size
		# Let the player explore freely. If they pan the active lesson target off
		# screen, keep the compact lesson text but stop dimming the whole world;
		# recenter only when the lesson target or available map viewport changes.
		if not map_rect.has_point(local_point):
			var more_target: Control = tutorial_targets.get("onboarding_more") as Control
			if not is_instance_valid(more_target) or not more_target.is_visible_in_tree():
				_tutorial_focus_signature = focus_signature
				tutorial_spotlight.clear_focus()
				return
			var more_transform := more_target.get_global_transform_with_canvas()
			var more_inverse := tutorial_spotlight.get_global_transform_with_canvas().affine_inverse()
			var more_start := more_inverse * more_transform * Vector2.ZERO
			var more_end := more_inverse * more_transform * more_target.size
			rect = _rect_from_corners(more_start, more_end)
			prompt = "目标在视野外；点“原因与选项”返回任务位置"
			shape = "rect"
			_tutorial_focus_signature = focus_signature
			tutorial_spotlight.set_focus(rect, prompt, shape, _bold_font, roundi(18.0 * _ui_scale))
			return
		var overlay_inverse := tutorial_spotlight.get_global_transform_with_canvas().affine_inverse()
		var global_point := map_view.get_global_transform_with_canvas() * local_point
		var point := overlay_inverse * global_point
		var radius := float(spec.get("radius", 22.0))
		rect = Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	_tutorial_focus_signature = focus_signature
	tutorial_spotlight.set_focus(rect, prompt, shape, _bold_font, roundi(18.0 * _ui_scale))

func _scroll_tutorial_confirmation_into_view(expected_signature: String) -> void:
	await get_tree().process_frame
	if _tutorial_focus_signature != expected_signature or not is_instance_valid(_right_panel): return
	var details_scroll := _right_panel.find_child("DetailsScroll", true, false) as ScrollContainer
	if not is_instance_valid(details_scroll): return
	var vertical_bar := details_scroll.get_v_scroll_bar()
	if is_instance_valid(vertical_bar): details_scroll.scroll_vertical = roundi(vertical_bar.max_value)

func _rect_from_corners(first: Vector2, second: Vector2) -> Rect2:
	return Rect2(
		Vector2(minf(first.x, second.x), minf(first.y, second.y)),
		Vector2(absf(second.x - first.x), absf(second.y - first.y))
	)

func _onboarding_campaign_action(flow: Dictionary) -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	if bool(onboarding.get("active", false)) and int(onboarding.get("step", -1)) >= 7:
		_end_onboarding(false)
	if not flow.is_empty(): _focus_flow(flow)

func _record_onboarding_demand_viewed(demand_id: String) -> void:
	var onboarding: Dictionary = world.get("onboarding", {})
	if not bool(onboarding.get("active", false)) or int(onboarding.get("step", -1)) != 0: return
	if demand_id not in [str(onboarding.get("originId", "")), str(onboarding.get("destinationId", ""))]: return
	var visited: Array = onboarding.get("visitedDemandIds", [])
	var expected_id := str(onboarding.get("originId", "")) if not visited.has(str(onboarding.get("originId", ""))) else str(onboarding.get("destinationId", ""))
	if demand_id != expected_id:
		onboarding["lastError"] = "先点击 A 起点，再查看 B 目的地。"
		world["onboarding"] = onboarding
		_refresh_onboarding_card()
		return
	if not visited.has(demand_id): visited.append(demand_id)
	onboarding["visitedDemandIds"] = visited
	world["onboarding"] = onboarding
	var origin_seen := visited.has(str(onboarding.get("originId", "")))
	var destination_seen := visited.has(str(onboarding.get("destinationId", "")))
	if origin_seen and destination_seen:
		_set_onboarding_step(1)
		_update_onboarding()
		_show_toast("已看过起点和目的地；下一步请选择底栏「车站」工具")
	else:
		onboarding["lastError"] = ""
		_refresh_onboarding_card()

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
	_update_tutorial_spotlight()
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

func _find_onboarding_station_covering(demand: Dictionary, excluded_station_id: String = "") -> Dictionary:
	if demand.is_empty(): return {}
	var best: Dictionary = {}
	var best_distance := INF
	for station in world.get("stations", []):
		var station_id := str(station.get("id", ""))
		if station_id == excluded_station_id: continue
		var distance := _distance_m(station.get("latlng", []), demand.get("latlng", []))
		if distance <= 800.0 and distance < best_distance:
			best = station
			best_distance = distance
	return best

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
	CityProgressionScript.start(world, int(world.get("simulation", {}).get("elapsedMinutes", 420)))
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
	var state := OnboardingScript.create_state(active_city_id, str(world.get("mode", "blank")), true)
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
	var extension_active := not route_extension_context.is_empty()
	if extension_active and line_draft_stops.size() <= int(route_extension_context.get("baseStopCount", 0)):
		_show_toast("先从原线路端点增加一座新停靠车站。")
		return
	if extension_active and int(world.get("revision", 0)) != int(route_extension_context.get("revision", -1)):
		_show_issue("规划在扩建预览期间发生变化；请结束本步后重新从线路详情开始扩建。")
		return
	var stops := line_draft_stops.duplicate()
	var is_loop: bool = stops.size() >= 4 and str(stops.front()) == str(stops.back())
	if is_loop and stops.size() < 4:
		_show_toast("环线至少需要三座不同的车站")
		return
	var ref_lat := float(WorldData.city(active_city_id).get("center", [31.23,121.47])[0])
	var used_edges: Dictionary = {}
	var edge_paths_by_segment: Array = []
	for index in range(stops.size() - 1):
		var segment: Dictionary = {}
		var base_count := int(route_extension_context.get("baseStopCount", 0))
		var fixed_paths: Array = route_extension_context.get("baseSegmentPaths", [])
		if extension_active and index < base_count - 1 and index < fixed_paths.size():
			segment = TrackNetwork.ordered_station_path(str(stops[index]), str(stops[index + 1]), fixed_paths[index], world, ref_lat)
		else:
			var options: Array = line_draft_path_options[index] if index < line_draft_path_options.size() else []
			var choice_index := clampi(line_draft_path_choices[index], 0, maxi(0, options.size() - 1)) if index < line_draft_path_choices.size() else 0
			var selected_edge_ids: Array = options[choice_index].get("linkIds", []) if not options.is_empty() else []
			segment = TrackNetwork.shortest_station_path(str(stops[index]), str(stops[index + 1]), world, ref_lat, selected_edge_ids)
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
	var extension_route := WorldData.find_route(world, str(route_extension_context.get("routeId", ""))) if extension_active else {}
	if extension_active and extension_route.is_empty():
		_show_issue("要扩建的线路已不存在；请重新选择线路。")
		return
	var route_name := str(extension_route.get("name", "线路")) if extension_active else "%d号线" % (line_index + 1)
	# Allocate this outside the mutation callback. GDScript lambda captures are
	# not a reliable way to return a newly assigned ID to the surrounding scope.
	var route_id := str(route_extension_context.get("routeId", "")) if extension_active else "r_%d" % Time.get_ticks_msec()
	var unique_stops: Array[String] = []
	for station_id in stops:
		if not unique_stops.has(str(station_id)): unique_stops.append(str(station_id))
	var reverse_stops: Array[String] = stops.duplicate(); reverse_stops.reverse()
	var reverse_edge_paths_by_segment: Array = _reverse_edge_paths(edge_paths_by_segment)
	var apply_route := func(state: Dictionary):
		var target_route := WorldData.find_route(state, route_id) if extension_active else {}
		if extension_active and target_route.is_empty(): return
		if not extension_active:
			target_route = WorldData.add_route(state, route_name, colors[line_index % colors.size()])
			var generated_id := str(target_route.get("id", ""))
			target_route["id"] = route_id
			target_route["planningPhaseId"] = str(state.get("currentPlanningPhaseId", "phase_1"))
			for phase in state.get("planningPhases", []):
				if str(phase.get("id", "")) != str(target_route.planningPhaseId): continue
				var phase_route_ids: Array = phase.get("routeIds", [])
				phase_route_ids.erase(generated_id)
				if not phase_route_ids.has(route_id): phase_route_ids.append(route_id)
				phase["routeIds"] = phase_route_ids
				break
		else:
			target_route["open"] = false
			target_route["serviceStartMinute"] = int(state.get("simulation", {}).get("elapsedMinutes", 420))
			target_route["extensionNote"] = "线路已扩建，检查并重新开通后恢复运营。"
			target_route["revision"] = int(state.get("revision", 0)) + 1
		target_route["networkBased"] = true
		target_route["stationOrder"] = unique_stops.duplicate()
		target_route["directions"] = [
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
	var commit_route := func():
		var action_name := "延伸运营线路%s" % route_name if extension_active else "创建运营线路%s" % route_name
		if not history.execute(action_name, apply_route): return
		active_route_id = route_id; selected_type = "route"; selected_id = route_id
		line_draft_stops.clear(); line_draft_path_options.clear(); line_draft_path_choices.clear(); route_extension_context.clear(); current_tool = "select"; map_view.tool = "select"
		map_view.line_draft_points.clear()
		map_view.set_world(world)
		_after_planning_change("线路扩建已保存并暂停；检查路径后手动开通" if extension_active else "运营线路已建立；检查车型与路径后即可开通")
	if extension_active:
		_confirm_service_impact([route_id], "延伸运营线路%s" % route_name, commit_route)
	else:
		commit_route.call()

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
		var segment: Dictionary = {}
		var base_count := int(route_extension_context.get("baseStopCount", 0))
		var fixed_paths: Array = route_extension_context.get("baseSegmentPaths", [])
		if not route_extension_context.is_empty() and index < base_count - 1 and index < fixed_paths.size():
			segment = TrackNetwork.ordered_station_path(line_draft_stops[index], line_draft_stops[index + 1], fixed_paths[index], world, ref_lat)
		else:
			var options: Array = line_draft_path_options[index]
			var choice_index := clampi(line_draft_path_choices[index], 0, maxi(0, options.size() - 1))
			var selected_ids: Array = options[choice_index].get("linkIds", []) if not options.is_empty() else []
			segment = TrackNetwork.shortest_station_path(line_draft_stops[index], line_draft_stops[index + 1], world, ref_lat, selected_ids)
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
	# Reconcile committed work before asking for another click. This covers a
	# station, connection, or route built ahead of the tutorial, and after reload.
	if step == 1 and origin_station.is_empty() and not origin.is_empty():
		origin_station = _find_onboarding_station_covering(origin)
		if not origin_station.is_empty():
			onboarding.originStationId = str(origin_station.get("id", ""))
			step = 2
	if step == 2 and not origin_station.is_empty() and destination_station.is_empty() and not destination.is_empty():
		destination_station = _find_onboarding_station_covering(destination, str(origin_station.get("id", "")))
		if not destination_station.is_empty():
			onboarding.destinationStationId = str(destination_station.get("id", ""))
			step = 3
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
				CityProgressionScript.start(world, int(world.get("simulation", {}).get("elapsedMinutes", 420)))
				if UiPreferencesScript.save_onboarding_completed(true) != OK:
					_show_toast("引导已完成，但全局完成标记未能保存")
	if step != old_step:
		onboarding.step = step
		if step in [2, 3, 4, 5, 6, 7] and old_step < step: onboarding.lastError = ""
	world["onboarding"] = onboarding
	if step != old_step or str(onboarding.get("lastError", "")) != old_error:
		if step == 5 and old_step < 5:
			var route_to_open := _onboarding_route_for_pair(false)
			if not route_to_open.is_empty(): _select_object("route", str(route_to_open.get("id", "")))
		if step == 7 and old_step < 7:
			_left_requested = true
			_right_requested = false
			_update_responsive_layout()
			_refresh_left_panel()
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
		_play_ui_feedback("confirm")
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
		var onboarding: Dictionary = world.get("onboarding", {})
		var coach_play := (bool(onboarding.get("active", false)) and int(onboarding.get("step", 0)) == 6) or (not bool(world.get("tutorialDone", false)) and int(world.get("tutorialStep", 0)) == 3)
		pause_button.tooltip_text = "教学下一步：播放并观察乘客" if coach_play else "暂停／继续 · 空格"
		pause_button.add_theme_stylebox_override("normal", _style(Color("#236548"), Color("#8cf0c6"), 8, 2) if coach_play else _style(Color("#142e2c"), BORDER, 8, 1))
	if is_instance_valid(speed_picker): speed_picker.select([1,3,10].find(int(sim.get("speed", 1))))
	if is_instance_valid(undo_button): undo_button.disabled = history.undo_label().is_empty()
	if is_instance_valid(redo_button): redo_button.disabled = history.redo_label().is_empty()
	if is_instance_valid(save_badge):
		save_badge.text = "保存失败 · 重试" if save_failed else "未保存" if save_dirty else "已保存"
		save_badge.tooltip_text = save_failure_reason if save_failed else "点击立即保存\n定时自动存档：%s（现实时间）" % ("每 %d 分钟" % timed_autosave_interval_minutes if timed_autosave_enabled else "已关闭")
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

func _autosave(show_error: bool = true, preserve_history: bool = false) -> bool:
	if world.is_empty(): return false
	save_dirty = true; _update_topbar()
	var result := SaveManager.save_world(world, preserve_history)
	if result.ok:
		var index_result := SaveManager.save_last_game(world)
		if index_result.ok:
			save_dirty = false
			save_failed = false
			save_failure_reason = ""
			autosave_elapsed_seconds = 0.0
			_update_topbar()
			if result.has("warning") and show_error: _show_toast(str(result.warning))
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
	var dialog := _new_confirmation_dialog()
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
	_show_save_center()

func _show_save_center(initial_tab: String = "automatic") -> void:
	var dialog := _new_accept_dialog()
	dialog.title = "存档中心"
	dialog.dialog_text = ""
	dialog.get_ok_button().text = "完成"
	var viewport_size := get_viewport_rect().size
	var scroll := ScrollContainer.new()
	scroll.name = "SaveCenterScroll"
	scroll.custom_minimum_size = Vector2(minf(740.0 * _ui_scale, viewport_size.x - 56.0), minf(500.0 * _ui_scale, viewport_size.y - 160.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = maxf(0.0, scroll.custom_minimum_size.x - 24.0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	content.add_child(_label("各城市自动保存的进度与独立命名存档", 15, MUTED))
	var tabs := TabContainer.new()
	tabs.name = "SaveCenterTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = minf(380.0 * _ui_scale, maxf(220.0, viewport_size.y - 320.0))
	var automatic_page := ScrollContainer.new()
	automatic_page.name = "AutomaticSaves"
	automatic_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	automatic_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	automatic_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_configure_save_list_scrollbar(automatic_page)
	var automatic_rows := VBoxContainer.new()
	automatic_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	automatic_rows.add_theme_constant_override("separation", 6)
	for city in WorldData.cities():
		var city_title := _label(str(city.get("name", "城市")), 18, TEXT, true)
		city_title.custom_minimum_size.y = 30
		automatic_rows.add_child(city_title)
		for mode in ["blank", "expand"]:
			var city_id := str(city.get("id", ""))
			var has_save := SaveManager.save_exists(city_id, mode)
			var has_auto_data := SaveManager.auto_slot_has_data(city_id, mode)
			var row := VBoxContainer.new()
			row.name = "SaveRow_%s_%s" % [city_id, mode]
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var slot_summary: Dictionary = SaveManager.auto_save_summary(city_id, mode) if has_auto_data else {}
			var slot_state := "已保存" if has_save else ("仅有历史或继续记录" if has_auto_data else "尚无存档")
			var slot_text := "%s　%s" % [_mode_name(mode), slot_state]
			if not slot_summary.is_empty():
				var old_minute := int(slot_summary.get("elapsedMinutes", 0))
				slot_text += "\n%s · 第%d天 %02d:%02d · %d站 / %d线" % [str(slot_summary.get("savedAt", "" )).replace("T", " "), old_minute / 1440 + 1, posmod(old_minute, 1440) / 60, posmod(old_minute, 60), int(slot_summary.get("stationCount", 0)), int(slot_summary.get("routeCount", 0))]
			var save_description := _label(slot_text, 14, MUTED)
			save_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(save_description)
			var row_actions := HFlowContainer.new()
			row_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_actions.add_theme_constant_override("h_separation", 8)
			var load_button := _button("载入", TEXT, PANEL_LIGHT, 14)
			load_button.custom_minimum_size = Vector2(88.0, 44.0) * minf(_ui_scale, 1.25)
			load_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			load_button.disabled = not has_save
			load_button.pressed.connect(_load_automatic_snapshot.bind(city_id, mode, dialog))
			row_actions.add_child(load_button)
			var delete_slot := _button("删除自动进度", Color("#A33D32"), PANEL_LIGHT, 13)
			delete_slot.name = "DeleteAutoSlot_%s_%s" % [city_id, mode]
			delete_slot.custom_minimum_size = Vector2(142.0, 44.0) * minf(_ui_scale, 1.25)
			var is_active_slot: bool = not world.is_empty() and str(world.get("cityId", "")) == city_id and str(world.get("mode", "")) == mode
			delete_slot.disabled = not has_auto_data or is_active_slot
			delete_slot.tooltip_text = "请先返回主菜单，再删除当前正在使用的自动进度。" if is_active_slot else "删除主进度、恢复备份与自动历史"
			delete_slot.pressed.connect(_confirm_auto_slot_delete.bind(city_id, mode, dialog))
			row_actions.add_child(delete_slot)
			row.add_child(row_actions)
			automatic_rows.add_child(row)
			for history_entry in SaveManager.list_auto_history(city_id, mode):
				var history_row := VBoxContainer.new()
				history_row.name = "AutoHistory_%s_%s_%s" % [city_id, mode, str(history_entry.get("id", ""))]
				history_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var old_minute := int(history_entry.get("elapsedMinutes", 0))
				var history_label := _label("历史 · %s · 第%d天 %02d:%02d · %d站 / %d线" % [str(history_entry.get("savedAt", "" )).replace("T", " "), old_minute / 1440 + 1, posmod(old_minute, 1440) / 60, posmod(old_minute, 60), int(history_entry.get("stationCount", 0)), int(history_entry.get("routeCount", 0))], 13, MUTED)
				history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				history_row.add_child(history_label)
				var history_actions := HFlowContainer.new()
				history_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				history_actions.add_theme_constant_override("h_separation", 8)
				var history_load := _button("载入历史", TEXT, PANEL_LIGHT, 13)
				history_load.custom_minimum_size = Vector2(104.0, 40.0) * minf(_ui_scale, 1.25)
				history_load.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				history_load.disabled = not bool(history_entry.get("valid", false))
				history_load.pressed.connect(_load_auto_history_snapshot.bind(history_entry.duplicate(true), city_id, mode, dialog))
				history_actions.add_child(history_load)
				var delete_history := _button("删除此历史", Color("#A33D32"), PANEL_LIGHT, 13)
				delete_history.custom_minimum_size = Vector2(112.0, 40.0) * minf(_ui_scale, 1.25)
				delete_history.pressed.connect(_confirm_auto_history_delete.bind(history_entry.duplicate(true), city_id, mode, dialog))
				history_actions.add_child(delete_history)
				history_row.add_child(history_actions)
				automatic_rows.add_child(history_row)
	automatic_page.add_child(automatic_rows)
	tabs.add_child(automatic_page)
	tabs.set_tab_title(0, "自动存档")
	var manual_page := ScrollContainer.new()
	manual_page.name = "ManualSaves"
	manual_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	manual_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_configure_save_list_scrollbar(manual_page)
	var manual_rows := VBoxContainer.new()
	manual_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_rows.add_theme_constant_override("separation", 8)
	manual_rows.add_child(_label("命名存档占用 %.1f MB · 自动历史占用 %.1f MB（每个城市开局最多保留3份）" % [float(SaveManager.manual_storage_bytes()) / 1048576.0, float(SaveManager.auto_history_bytes()) / 1048576.0], 14, MUTED))
	var manual_search := LineEdit.new()
	manual_search.name = "ManualSaveSearch"
	manual_search.placeholder_text = "搜索名称、城市或开局方式"
	manual_search.custom_minimum_size.y = 44.0 * _ui_scale
	_set_control_base_font(manual_search, 15)
	manual_rows.add_child(manual_search)
	var entries: Array = SaveManager.list_manual_snapshots()
	if entries.is_empty():
		manual_rows.add_child(_label("还没有命名存档。创建后，它会独立保留，不被自动保存覆盖。", 15, MUTED))
	for entry in entries:
		var row := VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var entry_text := "%s\n%s · %s · %s" % [str(entry.get("name", "未命名")), str(entry.get("cityName", "城市")), _mode_name(str(entry.get("mode", "blank"))), str(entry.get("savedAt", "" )).replace("T", " ")]
		var entry_label := _label(entry_text, 14, TEXT, true)
		entry_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry_label.custom_minimum_size.y = 52
		entry_label.tooltip_text = str(entry.get("error", "")) if not bool(entry.get("valid", false)) else ""
		row.add_child(entry_label)
		row.set_meta("search_text", (entry_text + " " + str(entry.get("name", "")) + " " + str(entry.get("cityId", ""))).to_lower())
		var manual_actions := HFlowContainer.new()
		manual_actions.name = "ManualSaveActions"
		manual_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		manual_actions.add_theme_constant_override("h_separation", 8)
		var load_manual := _button("载入", TEXT, PANEL_LIGHT, 14)
		load_manual.custom_minimum_size = Vector2(76.0, 44.0) * minf(_ui_scale, 1.25)
		load_manual.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		load_manual.disabled = not bool(entry.get("valid", false))
		load_manual.tooltip_text = str(entry.get("error", "这份存档无法载入")) if load_manual.disabled else "载入此命名存档"
		load_manual.pressed.connect(_load_manual_snapshot.bind(entry.duplicate(true), dialog))
		manual_actions.add_child(load_manual)
		var rename_manual := _button("改名", TEXT, PANEL_LIGHT, 13)
		rename_manual.custom_minimum_size = Vector2(68.0, 44.0) * minf(_ui_scale, 1.25)
		rename_manual.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rename_manual.disabled = not bool(entry.get("valid", false))
		rename_manual.pressed.connect(_prompt_manual_rename.bind(entry.duplicate(true), dialog))
		manual_actions.add_child(rename_manual)
		var overwrite_manual := _button("覆盖", TEXT, PANEL_LIGHT, 13)
		overwrite_manual.custom_minimum_size = Vector2(68.0, 44.0) * minf(_ui_scale, 1.25)
		overwrite_manual.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var same_world := not world.is_empty() and str(world.get("cityId", "")) == str(entry.get("cityId", "")) and str(world.get("mode", "")) == str(entry.get("mode", ""))
		overwrite_manual.disabled = not bool(entry.get("valid", false)) or not same_world
		overwrite_manual.tooltip_text = "用当前城市进度覆盖此存档" if not overwrite_manual.disabled else "载入相同城市与开局后才能覆盖"
		overwrite_manual.pressed.connect(_confirm_manual_overwrite.bind(entry.duplicate(true), dialog))
		manual_actions.add_child(overwrite_manual)
		var delete_manual := _button("删除", Color("#A33D32"), PANEL_LIGHT, 13)
		delete_manual.custom_minimum_size = Vector2(68.0, 44.0) * minf(_ui_scale, 1.25)
		delete_manual.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		delete_manual.name = "DeleteManual_%s" % str(entry.get("id", ""))
		delete_manual.pressed.connect(_confirm_manual_delete.bind(entry.duplicate(true), dialog))
		manual_actions.add_child(delete_manual)
		row.add_child(manual_actions)
		manual_rows.add_child(row)
	manual_search.text_changed.connect(func(query: String):
		var normalized := query.strip_edges().to_lower()
		for child in manual_rows.get_children():
			if child is VBoxContainer and child.has_meta("search_text"):
				child.visible = normalized.is_empty() or str(child.get_meta("search_text", "")).contains(normalized)
	)
	manual_page.add_child(manual_rows)
	tabs.add_child(manual_page)
	tabs.set_tab_title(1, "命名存档")
	tabs.current_tab = 1 if initial_tab == "manual" else 0
	content.add_child(tabs)
	var actions := HFlowContainer.new()
	actions.name = "SaveCenterActions"
	actions.add_theme_constant_override("h_separation", 8)
	var save_now := _button("立即保存", TEAL, PANEL_LIGHT, 14)
	save_now.disabled = world.is_empty()
	if save_now.disabled: save_now.tooltip_text = "进入城市后才能保存当前进度"
	save_now.pressed.connect(func(): _close_save_center(dialog); if _autosave(): _show_toast("本地存档已写入"))
	actions.add_child(save_now)
	var save_manual := _button("当前进度另存为…", TEXT, PANEL_LIGHT, 14)
	save_manual.disabled = world.is_empty()
	if save_manual.disabled: save_manual.tooltip_text = "进入城市后才能创建命名存档"
	save_manual.pressed.connect(func(): _close_save_center(dialog); _prompt_manual_save())
	actions.add_child(save_manual)
	var export_json := _button("导出 JSON", TEXT, PANEL_LIGHT, 14)
	export_json.disabled = world.is_empty()
	if export_json.disabled: export_json.tooltip_text = "进入城市后才能导出当前进度"
	export_json.pressed.connect(func(): _close_save_center(dialog); SaveManager.export_world(world, func(result: Dictionary): _show_toast("JSON 已导出" if bool(result.get("ok", false)) else str(result.get("error", "导出失败")))) )
	actions.add_child(export_json)
	var import_json := _button("导入 JSON", TEXT, PANEL_LIGHT, 14)
	import_json.pressed.connect(func():
		_close_save_center(dialog)
		SaveManager.import_world(func(loaded: Dictionary):
			if not world.is_empty() and not _autosave(): _show_issue("无法先保存当前进度，导入已取消。"); return
			_load_world(loaded)
			if _autosave(): _show_toast("存档已导入并保存")
			else: _show_issue("存档已载入到当前会话，但未能同步写入本机。原存档备份仍保留。")
		, func(error: String): _show_issue(error))
	)
	actions.add_child(import_json)
	var open_folder := _button("打开存档目录", TEXT, PANEL_LIGHT, 14)
	open_folder.pressed.connect(func(): _close_save_center(dialog); _open_manual_saves_folder())
	actions.add_child(open_folder)
	content.add_child(actions)
	scroll.add_child(content)
	_fade_in(scroll)
	dialog.add_child(scroll)
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	# Leave room for the embedded title bar as well as the client content.
	dialog.popup_centered(Vector2i(mini(roundi(790.0 * _ui_scale), int(viewport_size.x) - 32), mini(roundi(600.0 * _ui_scale), int(viewport_size.y) - 64)))

func _configure_save_list_scrollbar(list: ScrollContainer) -> void:
	var track := _theme.get_stylebox("scroll", "VScrollBar").duplicate() as StyleBoxFlat
	# ScrollContainer reserves the style's minimum width, not a custom control width.
	track.content_margin_left = 6.0 * minf(_ui_scale, 1.25)
	track.content_margin_right = 6.0 * minf(_ui_scale, 1.25)
	list.get_v_scroll_bar().add_theme_stylebox_override("scroll", track)

func _close_save_center(dialog: AcceptDialog) -> void:
	if not is_instance_valid(dialog): return
	# Release the exclusive modal before opening an import/export or naming dialog.
	dialog.hide()
	dialog.queue_free()

func _load_automatic_snapshot(city_id: String, mode: String, dialog: AcceptDialog) -> void:
	_close_save_center(dialog)
	_request_world_transition(func():
		var result := SaveManager.load_world(city_id, mode, true)
		if not bool(result.get("ok", false)):
			_select_current_city_in_picker()
			_show_issue(str(result.get("error", "载入存档失败；当前规划仍保留")), "无法载入存档")
		elif bool(result.get("pendingRecoveryConfirmation", false)):
			_confirm_recovery_before_load(result, func(confirmed: Dictionary): _load_world(confirmed.world))
		else:
			_load_world(result.world)
			if bool(result.get("recovered", false)): _show_toast(str(result.get("error", "已从备份恢复")))
	)

func _load_auto_history_snapshot(entry: Dictionary, city_id: String, mode: String, dialog: AcceptDialog) -> void:
	_close_save_center(dialog)
	var loaded := SaveManager.load_auto_history(str(entry.get("path", "")), city_id, mode)
	if not bool(loaded.get("ok", false)):
		_show_issue(str(loaded.get("error", "自动存档历史无法读取")), "无法载入历史进度")
		return
	var state: Dictionary = loaded.get("world", {})
	var confirm := _new_confirmation_dialog()
	confirm.title = "载入自动存档历史？"
	var elapsed := int(state.get("simulation", {}).get("elapsedMinutes", 0))
	confirm.dialog_text = "这会回到第%d天 %02d:%02d的自动存档。当前进度会先保存；历史记录保留。" % [elapsed / 1440 + 1, posmod(elapsed, 1440) / 60, posmod(elapsed, 60)]
	confirm.get_ok_button().text = "保存当前进度并载入"
	confirm.get_cancel_button().text = "取消"
	add_child(confirm)
	confirm.confirmed.connect(func():
		confirm.queue_free()
		_request_world_transition(func():
			_load_world(state)
			_show_toast("已载入自动存档历史，并暂停游戏")
		)
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	confirm.popup_centered(Vector2i(560, 240))

func _prompt_manual_rename(entry: Dictionary, save_dialog: AcceptDialog) -> void:
	_close_save_center(save_dialog)
	await get_tree().process_frame
	var dialog := _new_confirmation_dialog()
	dialog.title = "重命名存档"
	dialog.dialog_text = "修改这份独立存档的显示名称。保存时间与进度不会改变。"
	dialog.get_ok_button().text = "保存名称"
	dialog.get_cancel_button().text = "取消"
	var edit := LineEdit.new()
	edit.text = str(entry.get("name", ""))
	edit.max_length = 48
	edit.custom_minimum_size.y = 44.0 * _ui_scale
	dialog.add_child(edit)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var result := SaveManager.rename_manual_snapshot(str(entry.get("path", "")), edit.text)
		dialog.hide()
		dialog.queue_free()
		if bool(result.get("ok", false)):
			_show_toast("存档已改名")
			call_deferred("_reopen_save_center", "manual")
		else: _show_issue(str(result.get("error", "重命名失败")), "存档未修改")
	)
	dialog.canceled.connect(func(): dialog.hide(); dialog.queue_free(); call_deferred("_reopen_save_center", "manual"))
	dialog.popup_centered(Vector2i(560, 240))
	edit.grab_focus()
	edit.select_all()

func _confirm_auto_slot_delete(city_id: String, mode: String, save_dialog: AcceptDialog) -> void:
	_close_save_center(save_dialog)
	await get_tree().process_frame
	var summary: Dictionary = SaveManager.auto_save_summary(city_id, mode)
	var elapsed := int(summary.get("elapsedMinutes", 0))
	var dialog := _new_confirmation_dialog()
	dialog.title = "删除自动进度？"
	dialog.dialog_text = "%s · %s\n%s%s\n\n将永久删除这个开局的自动进度、恢复备份和自动历史。独立命名存档与导出的 JSON 会保留。此操作不可撤销。" % [_city_name(city_id), _mode_name(mode), str(summary.get("savedAt", "没有可用主进度时间" )).replace("T", " "), " · 第%d天 %02d:%02d · %d站 / %d线" % [elapsed / 1440 + 1, posmod(elapsed, 1440) / 60, posmod(elapsed, 60), int(summary.get("stationCount", 0)), int(summary.get("routeCount", 0))] if not summary.is_empty() else ""]
	dialog.get_ok_button().text = "删除此自动进度"
	dialog.get_cancel_button().text = "保留"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var current_city := str(world.get("cityId", "")) if not world.is_empty() else ""
		var current_mode := str(world.get("mode", "")) if not world.is_empty() else ""
		var result := SaveManager.delete_auto_slot(city_id, mode, current_city, current_mode)
		dialog.hide()
		dialog.queue_free()
		if bool(result.get("ok", false)):
			_update_continue_button()
			_show_toast("自动进度及其历史已删除")
			call_deferred("_reopen_save_center", "automatic")
		else:
			_show_issue(str(result.get("error", "自动进度删除失败")), "删除失败")
			call_deferred("_reopen_save_center", "automatic")
	)
	dialog.canceled.connect(func(): dialog.hide(); dialog.queue_free(); call_deferred("_reopen_save_center", "automatic"))
	dialog.popup_centered(Vector2i(620, 330))

func _confirm_auto_history_delete(entry: Dictionary, city_id: String, mode: String, save_dialog: AcceptDialog) -> void:
	_close_save_center(save_dialog)
	await get_tree().process_frame
	var elapsed := int(entry.get("elapsedMinutes", 0))
	var dialog := _new_confirmation_dialog()
	dialog.title = "删除自动历史？"
	dialog.dialog_text = "%s · %s\n%s · 第%d天 %02d:%02d · %d站 / %d线\n\n只删除这份历史记录，当前自动进度和其他历史不受影响。此操作不可撤销。" % [_city_name(city_id), _mode_name(mode), str(entry.get("savedAt", "" )).replace("T", " "), elapsed / 1440 + 1, posmod(elapsed, 1440) / 60, posmod(elapsed, 60), int(entry.get("stationCount", 0)), int(entry.get("routeCount", 0))]
	dialog.get_ok_button().text = "删除此历史"
	dialog.get_cancel_button().text = "保留"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var result := SaveManager.delete_auto_history(city_id, mode, str(entry.get("id", "")))
		dialog.hide()
		dialog.queue_free()
		if bool(result.get("ok", false)):
			_show_toast("自动历史已删除")
			call_deferred("_reopen_save_center", "automatic")
		else:
			_show_issue(str(result.get("error", "自动历史删除失败")), "删除失败")
			call_deferred("_reopen_save_center", "automatic")
	)
	dialog.canceled.connect(func(): dialog.hide(); dialog.queue_free(); call_deferred("_reopen_save_center", "automatic"))
	dialog.popup_centered(Vector2i(600, 300))

func _confirm_manual_delete(entry: Dictionary, save_dialog: AcceptDialog) -> void:
	_close_save_center(save_dialog)
	await get_tree().process_frame
	var dialog := _new_confirmation_dialog()
	dialog.title = "删除命名存档？"
	dialog.dialog_text = "将永久删除「%s」\n%s · %s\n\n其他自动存档和命名存档不受影响。" % [str(entry.get("name", "未命名")), str(entry.get("cityName", "城市")), str(entry.get("savedAt", ""))]
	dialog.get_ok_button().text = "删除此存档"
	dialog.get_cancel_button().text = "保留"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var result := SaveManager.delete_manual_snapshot(str(entry.get("id", "")))
		dialog.hide()
		dialog.queue_free()
		if bool(result.get("ok", false)):
			_show_toast("命名存档已删除")
			call_deferred("_reopen_save_center", "manual")
		else: _show_issue(str(result.get("error", "无法删除存档")), "删除失败")
	)
	dialog.canceled.connect(func(): dialog.hide(); dialog.queue_free(); call_deferred("_reopen_save_center", "manual"))
	dialog.popup_centered(Vector2i(560, 240))

func _confirm_manual_overwrite(entry: Dictionary, save_dialog: AcceptDialog) -> void:
	var snapshot := world.duplicate(true)
	_close_save_center(save_dialog)
	await get_tree().process_frame
	var dialog := _new_confirmation_dialog()
	dialog.title = "覆盖命名存档？"
	dialog.dialog_text = "用当前进度覆盖「%s」\n%s · %s\n\n覆盖后无法从这份命名存档恢复原内容。" % [str(entry.get("name", "未命名")), str(entry.get("cityName", "城市")), str(entry.get("savedAt", ""))]
	dialog.get_ok_button().text = "确认覆盖"
	dialog.get_cancel_button().text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var result := SaveManager.overwrite_manual_snapshot(str(entry.get("path", "")), snapshot, str(entry.get("name", "未命名")))
		dialog.hide()
		dialog.queue_free()
		if bool(result.get("ok", false)):
			_show_toast("命名存档已覆盖")
			call_deferred("_reopen_save_center", "manual")
		else: _show_issue(str(result.get("error", "覆盖失败；原存档仍保留")), "覆盖失败")
	)
	dialog.canceled.connect(func(): dialog.hide(); dialog.queue_free(); call_deferred("_reopen_save_center", "manual"))
	dialog.popup_centered(Vector2i(560, 260))

func _reopen_save_center(tab: String) -> void:
	_show_save_center(tab)

func _load_manual_snapshot(entry: Dictionary, dialog: AcceptDialog) -> void:
	if is_instance_valid(dialog):
		_close_save_center(dialog)
		await get_tree().process_frame
	var loaded := SaveManager.load_manual_snapshot(str(entry.get("path", "")))
	if not bool(loaded.get("ok", false)):
		_show_issue(str(loaded.get("error", "无法读取手动存档；当前进度仍保留。")), "手动存档读取失败")
		return
	_confirm_manual_load(entry, loaded)

func _prompt_manual_save() -> void:
	if world.is_empty(): return
	var dialog := _new_confirmation_dialog()
	dialog.title = "当前进度另存为"
	dialog.dialog_text = "保存当前城市进度的独立副本，不会开始新游戏，也不会被后续自动存档覆盖。"
	dialog.get_ok_button().text = "保存进度"
	dialog.get_cancel_button().text = "取消"
	var name_edit := LineEdit.new()
	var elapsed := int(world.get("simulation", {}).get("elapsedMinutes", 420))
	var day := elapsed / 1440 + 1
	var minute_of_day := posmod(elapsed, 1440)
	name_edit.text = "%s · 第%d天 %02d:%02d" % [str(world.get("cityName", "城市")), day, minute_of_day / 60, minute_of_day % 60]
	name_edit.placeholder_text = "例如：第一条线路开通前"
	name_edit.max_length = 48
	_set_control_base_font(name_edit, 16)
	dialog.add_child(name_edit)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var manual_result := SaveManager.save_manual_snapshot(world, name_edit.text)
		dialog.queue_free()
		if not bool(manual_result.get("ok", false)):
			_show_issue(str(manual_result.get("error", "手动存档失败；当前进度仍保留。")), "手动存档失败")
			return
		var auto_ok := _autosave(false)
		if auto_ok:
			_show_toast("已保存手动存档「%s」" % str(manual_result.get("name", name_edit.text)))
		else:
			_show_issue("手动存档已安全保留，但当前自动存档未能更新。\n%s" % save_failure_reason, "自动存档未更新")
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(520, 190))
	name_edit.grab_focus()
	name_edit.select_all()

func _show_manual_load_menu() -> void:
	_show_save_center("manual")

func _open_manual_saves_folder() -> void:
	var folder := ProjectSettings.globalize_path(SaveManager.manual_saves_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(folder)
	if directory_error != OK and not DirAccess.dir_exists_absolute(folder):
		_show_issue("无法打开手动存档目录。", "存档目录不可用")
		return
	var open_error := OS.shell_open(folder)
	if open_error != OK: _show_issue("无法打开手动存档目录。", "存档目录不可用")

func _confirm_manual_load(entry: Dictionary, loaded: Dictionary) -> void:
	var state: Dictionary = loaded.get("world", {})
	var dialog := _new_confirmation_dialog()
	dialog.title = "载入手动存档？"
	dialog.dialog_text = "将载入「%s」\n%s · %s · %s\n\n载入后游戏会暂停，并更新该城市的自动存档。当前进度会先自动保存；手动存档文件会保留。" % [str(entry.get("name", "未命名")), str(entry.get("cityName", "城市")), _mode_name(str(entry.get("mode", "blank"))), str(entry.get("savedAt", ""))]
	dialog.get_ok_button().text = "保存当前进度并载入"
	dialog.get_cancel_button().text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		_request_world_transition(func():
			_load_world(state)
			_show_toast("已载入手动存档「%s」" % str(entry.get("name", loaded.get("manualSaveName", "未命名"))))
		)
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(560, 260))

func _show_load_menu() -> void:
	_show_save_center()

func _leave_to_menu() -> void:
	_request_world_transition(func():
		for child in get_children():
			if child != map_view and child.get_name() != "Background": child.queue_free()
		world = {}; _show_main_menu()
	)

func _show_issue(text: String, title: String = "规划检查") -> void:
	_play_ui_feedback("error")
	var dialog := _new_accept_dialog(); dialog.title = title; dialog.dialog_text = text; add_child(dialog); dialog.confirmed.connect(func(): dialog.queue_free()); dialog.canceled.connect(func(): dialog.queue_free()); dialog.popup_centered()

func _show_toast(text: String) -> void:
	if is_instance_valid(toast_label): toast_label.text = text

func _play_ui_feedback(kind: String) -> void:
	if not feedback_enabled or feedback_volume <= 0.0 or not is_instance_valid(ui_audio_player): return
	ui_audio_player.stop()
	ui_audio_player.stream = AudioFeedbackScript.make_tone(kind, feedback_volume)
	ui_audio_player.play()

func _type_name(kind: String) -> String:
	return {"housing":"居住", "employment":"就业", "education":"教育", "health":"医疗", "hub":"枢纽", "commerce":"商业", "culture":"文化休闲", "service":"生活服务"}.get(kind, "需求")

func _type_color(kind: String) -> Color:
	return {"housing":Color("#e57272"),"employment":Color("#55a4ed"),"education":Color("#b585e8"),"health":Color("#ed8b9b"),"hub":Color("#3dbba7"),"commerce":Color("#edaf57"),"culture":Color("#4abc91"),"service":Color("#edaf57")}.get(kind, MUTED)

func _mode_name(mode: String) -> String:
	return "从零规划" if mode == "blank" else "扩建既有路网"

func _city_name(city_id: String) -> String:
	return str(WorldData.city(city_id).get("name", city_id))

func _number(value: int) -> String:
	if value >= 10000: return "%.1f万" % (float(value) / 10000.0)
	if value >= 1000: return "%.1f千" % (float(value) / 1000.0)
	return str(value)

func _label(text: String, font_size: int = 13, color: Color = TEXT, bold: bool = false) -> Label:
	var readable_size := maxi(14, font_size)
	var item := Label.new(); item.text = text; item.set_meta("ui_base_font_size", readable_size); item.add_theme_font_size_override("font_size", roundi(float(readable_size) * _ui_scale)); item.add_theme_color_override("font_color", _readable_text_color(color))
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
	var readable_size := maxi(14, font_size)
	item.set_meta("ui_base_font_size", readable_size)
	item.add_theme_font_size_override("font_size", roundi(float(readable_size) * _ui_scale))
	var warning_action := text.contains("挑战") or text.contains("拟换乘")
	var danger_action := text.begins_with("拆除") or text.begins_with("删除") or text.contains("放弃未保存")
	var primary_action := text.begins_with("确认") or text.contains("检查并开通") or text.contains("创建线路") or text == "从零规划" or text.contains("继续上次游戏")
	var selected_action := font_color == TEAL or (font_color.h >= 0.49 and font_color.h <= 0.72 and font_color.s > 0.26)
	var foreground := _readable_text_color(font_color)
	var surface := PANEL_LIGHT
	if primary_action:
		surface = TEAL
		foreground = Color.WHITE
	elif danger_action:
		surface = UiThemeScript.DANGER_SOFT
		foreground = UiThemeScript.DANGER
	elif warning_action:
		surface = UiThemeScript.WARNING_SOFT
		foreground = UiThemeScript.WARNING
	elif selected_action:
		surface = UiThemeScript.ACCENT_SOFT if font_color == TEAL else UiThemeScript.BLUE_SOFT
		foreground = TEAL if font_color == TEAL else UiThemeScript.BLUE
	item.add_theme_color_override("font_color", foreground)
	item.add_theme_color_override("font_hover_color", foreground)
	item.add_theme_color_override("font_pressed_color", foreground)
	item.add_theme_color_override("font_disabled_color", Color("#92948D"))
	var edge := UiThemeScript.BORDER_STRONG if primary_action or danger_action or warning_action or selected_action else BORDER
	item.add_theme_stylebox_override("normal", _component_style(surface, edge, 7, 1))
	var hover_surface := surface.darkened(0.07) if primary_action else surface.lightened(0.035)
	item.add_theme_stylebox_override("hover", _component_style(hover_surface, edge.lightened(0.06), 7, 1))
	item.add_theme_stylebox_override("pressed", _component_style(surface.darkened(0.09), edge.darkened(0.03), 7, 1))
	item.add_theme_stylebox_override("disabled", _component_style(UiThemeScript.SURFACE_ALT, BORDER, 7, 1))
	item.add_theme_stylebox_override("focus", _component_style(surface, TEAL, 7, 2))
	item.custom_minimum_size.y = roundi(44.0 * minf(_ui_scale, 1.25))
	if primary_action:
		item.add_theme_font_override("font", _bold_font)
	return item

func _set_control_base_font(control: Control, font_size: int) -> void:
	var readable_size := maxi(16, font_size)
	control.set_meta("ui_base_font_size", readable_size)
	control.add_theme_font_size_override("font_size", roundi(float(readable_size) * _ui_scale))

func _style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var fill := background
	if background.r < 0.22 and background.g < 0.30 and background.b < 0.34:
		fill = PANEL
	elif background.h >= 0.02 and background.h <= 0.12 and background.s > 0.30:
		fill = UiThemeScript.WARNING_SOFT
	elif background.h >= 0.92 or background.h <= 0.025 and background.s > 0.3:
		fill = UiThemeScript.DANGER_SOFT
	elif background.h >= 0.45 and background.h <= 0.70 and background.s > 0.25:
		fill = UiThemeScript.BLUE_SOFT
	elif background.s > 0.32 and background.h > 0.25 and background.h < 0.46:
		fill = UiThemeScript.ACCENT_SOFT
	elif background.get_luminance() > 0.42 and background.get_luminance() < 0.85:
		fill = UiThemeScript.SURFACE_ALT
	var box := StyleBoxFlat.new(); box.bg_color = fill; box.border_color = border if border_width > 0 else Color.TRANSPARENT; box.set_border_width_all(border_width); box.set_corner_radius_all(radius); box.content_margin_left = 12; box.content_margin_right = 12; box.content_margin_top = 6; box.content_margin_bottom = 6; return box

func _component_style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border if border_width > 0 else Color.TRANSPARENT
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func _readable_text_color(color: Color) -> Color:
	if color == TEAL or color == UiThemeScript.ACCENT: return UiThemeScript.ACCENT
	if color == TEXT or color == Color.WHITE or color == Color.WHITE_SMOKE: return UiThemeScript.INK
	if color == MUTED or color == Color("#b4c5ce") or color == Color("#b9c8d0") or color == Color("#e0ebed"): return UiThemeScript.MUTED
	if color.s > 0.27:
		var hue := color.h
		if hue >= 0.94 or hue <= 0.03: return UiThemeScript.DANGER
		if hue <= 0.12: return UiThemeScript.WARNING
		if hue <= 0.43: return UiThemeScript.SUCCESS
		if hue <= 0.70: return UiThemeScript.BLUE
		return Color("#71528F")
	return UiThemeScript.INK if color.get_luminance() > 0.64 else UiThemeScript.MUTED
