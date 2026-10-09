extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var window_size := OS.get_environment("METRO_WINDOW_SIZE").split("x")
	if window_size.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(window_size[0]), int(window_size[1])))
	main._load_world(WorldData.new_world("shanghai", "blank"))
	var preview_scale := float(OS.get_environment("METRO_UI_SCALE"))
	if preview_scale > 1.0:
		main._apply_ui_scale(preview_scale)
	for frame in range(8): await process_frame
	await create_timer(8.0).timeout
	print("Map preview: scale=%.2f visible_tiles=%d queued=%d active=%d unavailable=%s blocked=%s" % [main._ui_scale, main.map_view._tile_textures.size(), main.map_view._tile_queue.size(), main.map_view._requests.size(), str(main.map_view._network_unavailable), str(main.map_view._network_blocked)])
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
	var error := image.save_png(screenshot_path)
	if error != OK:
		push_error("Could not save native UI preview: %s" % error)
		quit(1)
		return
	print("Saved native UI preview %dx%d to %s" % [image.get_width(), image.get_height(), screenshot_path])
	quit(0)
