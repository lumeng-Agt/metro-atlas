extends SceneTree

const Onboarding = preload("res://scripts/onboarding.gd")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	WorldData.load_assets()
	var dimension_text := OS.get_environment("METRO_TUTORIAL_SIZE")
	var dimensions := dimension_text.split("x")
	var target_size := Vector2i(int(dimensions[0]), int(dimensions[1])) if dimensions.size() == 2 else Vector2i(1600, 980)
	root.size = target_size
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var state := WorldData.new_world("shanghai", "blank")
	state["onboarding"] = Onboarding.create_state("shanghai", "blank", false)
	state.onboarding.active = true
	state["tutorialDone"] = true
	main.world = state
	main.active_city_id = "shanghai"
	main.active_route_id = ""
	main.history.attach(state)
	main._left_requested = false
	main._right_requested = false
	main.map_view.visible = true
	main.map_view.set_context(WorldData.city("shanghai"), state)
	main._build_game_ui()
	main._sync_onboarding_map(true)
	main._refresh_ui()
	main.map_view.requested_redraw()
	# The local vector package is loaded synchronously for the initial view; the
	# small frame wait only lets the game UI settle before capture.
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.5).timeout
		if not main.map_view.base_map_features.is_empty(): break
	for frame in range(5): await process_frame
	await create_timer(0.22).timeout
	var texture := root.get_texture()
	if texture == null:
		push_error("需要带窗口的桌面渲染来截取新手界面。")
		quit(1)
		return
	var image := texture.get_image()
	var screenshot_name := "tutorial-preview-%dx%d.png" % [target_size.x, target_size.y]
	var preview_prefix := OS.get_environment("METRO_PREVIEW_PREFIX").strip_edges()
	if not preview_prefix.is_empty(): screenshot_name = "%s-%s" % [preview_prefix, screenshot_name]
	var screenshot_path := "res://docs/" + screenshot_name
	var error := image.save_png(screenshot_path)
	if error != OK:
		push_error("无法保存引导截图：%s" % error)
		quit(1)
		return
	print("Saved tutorial preview %dx%d to %s (%d local map features)" % [image.get_width(), image.get_height(), screenshot_path, main.map_view.base_map_features.size()])
	quit(0)
