extends SceneTree

const TrackNetworkScript = preload("res://scripts/track_network.gd")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var window_size := OS.get_environment("METRO_WINDOW_SIZE").split("x")
	if window_size.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(window_size[0]), int(window_size[1])))
	var preview_world := WorldData.new_world("shanghai", "blank")
	preview_world["onboarding"] = {"active": false, "step": 0, "completed": true}
	preview_world["tutorialDone"] = true
	main._load_world(preview_world)
	var preview_scale := float(OS.get_environment("METRO_UI_SCALE"))
	if preview_scale > 1.0:
		main._apply_ui_scale(preview_scale)
	if OS.get_environment("METRO_PREVIEW_DRAFT") == "1":
		var city := WorldData.city("shanghai")
		var center: Array = city.get("center", [31.2304, 121.4737])
		main.map_view.current_zoom = 13
		main.map_view.current_center = center.duplicate()
		var station_a := WorldData.create_station(main.world, [float(center[0]) + 0.010, float(center[1]) - 0.018], 90.0, "", "B-6", -15.0)
		station_a["name"] = "人民广场"
		await process_frame
		var station_b := WorldData.create_station(main.world, [float(center[0]) - 0.008, float(center[1]) + 0.012], 90.0, "", "B-6", -15.0)
		station_b["name"] = "世纪大道"
		var a_node := str(station_a.get("endpointNodes", {}).get("B", ""))
		var b_node := str(station_b.get("endpointNodes", {}).get("A", ""))
		if not a_node.is_empty() and not b_node.is_empty():
			main.world.trackEdges.append({"id":"preview-east-west", "aNodeId":a_node, "bNodeId":b_node, "geometry":"straight", "depthM":-15.0, "routeIds":[]})
		TrackNetworkScript.ensure_station_nodes(main.world)
		main.map_view.set_world(main.world)
		main._select_object("station", str(station_a.get("id", "")))
		main._set_tool("station")
		main.map_view.draft_station = {"id":"preview-draft", "name":"南京东路预览站", "latlng":[float(center[0]) + 0.017, float(center[1]) + 0.004], "heading":90.0, "lengthM":118.8, "widthM":20.0, "depthM":-15.0, "vehicleId":"B-6", "routeIds":[]}
		main._on_draft_station_changed()
		main.map_view.show_demand = true
		main.map_view.requested_redraw()
	var preview_mode := OS.get_environment("METRO_PREVIEW_STATE")
	if preview_mode == "stats":
		main.world.simulation.attempted = 138
		main.world.simulation.completed = 98
		main.world.simulation.waiting = 14
		main.world.simulation.inTransit = 26
		main.world.simulation.abandoned = 3
		main.world.simulation.interrupted = 1
		main.world.simulation.unreachable = 2
		main.world.simulation.tripMinutesTotal = 3320.0
		main.world.simulation.peakCrowding = 0.74
		main.left_tab = "stats"
		main._refresh_left_panel()
	var map_deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < map_deadline:
		await create_timer(0.25).timeout
		if not main.map_view.base_map_features.is_empty() and not main.map_view._base_map_thread_busy and main.map_view._base_map_pending_request.is_empty():
			break
	if main.map_view.base_map_features.is_empty():
		push_error("本地矢量底图未在25秒内加载，不能生成有效的规划界面截图。")
		quit(1)
		return
	for frame in range(4): await process_frame
	if preview_mode == "save_center":
		var preview_save_result: Dictionary = SaveManager.save_manual_snapshot(main.world, "示例进度 · 第一条线路开通")
		var preview_saves: Array = SaveManager.list_manual_snapshots()
		print("Save center preview: save_ok=%s entries=%d root=%s" % [str(preview_save_result.get("ok", false)), preview_saves.size(), SaveManager.root_path()])
		if not bool(preview_save_result.get("ok", false)) or preview_saves.is_empty():
			push_error("存档中心预览未能生成可见的命名存档。")
			quit(1)
			return
		main._show_save_center("manual")
		for frame in range(3): await process_frame
		var save_dialog: AcceptDialog
		for child in main.get_children():
			if child is AcceptDialog and child.find_child("SaveCenterTabs", true, false) != null:
				save_dialog = child
		var manual_page := save_dialog.find_child("ManualSaves", true, false) as ScrollContainer if is_instance_valid(save_dialog) else null
		if manual_page == null or manual_page.size.y <= 0.0 or manual_page.get_child_count() == 0:
			push_error("存档中心的命名存档分页未显示列表内容。")
			quit(1)
			return
		await create_timer(0.22).timeout
	print("Map preview: scale=%.2f local_vector_features=%d snapshot=%s" % [main._ui_scale, main.map_view.base_map_features.size(), main.map_view.base_map_snapshot])
	main.map_view.requested_redraw()
	await process_frame
	await process_frame
	await process_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("A rendered display server is required to capture the native UI.")
		quit(1)
		return
	var image := viewport_texture.get_image()
	var screenshot_path := "res://docs/ui-preview.png"
	if preview_scale > 1.0 and window_size.size() == 2:
		screenshot_path = "res://docs/ui-preview-%s-%d.png" % [OS.get_environment("METRO_WINDOW_SIZE"), roundi(preview_scale * 100.0)]
	elif preview_scale > 1.0:
		screenshot_path = "res://docs/ui-preview-%d.png" % roundi(preview_scale * 100.0)
	elif window_size.size() == 2:
		screenshot_path = "res://docs/ui-preview-%s.png" % OS.get_environment("METRO_WINDOW_SIZE")
	var preview_prefix := OS.get_environment("METRO_PREVIEW_PREFIX").strip_edges()
	if not preview_prefix.is_empty():
		screenshot_path = "res://docs/%s-%s" % [preview_prefix, screenshot_path.get_file()]
	if preview_mode in ["stats", "save_center"]:
		var mode_name := preview_mode.replace("_", "-")
		screenshot_path = "res://docs/%s-%s-preview-%s.png" % [preview_prefix if not preview_prefix.is_empty() else "", mode_name, OS.get_environment("METRO_WINDOW_SIZE")]
	var error := image.save_png(screenshot_path)
	if error != OK:
		push_error("Could not save native UI preview: %s" % error)
		quit(1)
		return
	print("Saved native UI preview %dx%d to %s" % [image.get_width(), image.get_height(), screenshot_path])
	quit(0)
