extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._load_world(WorldData.new_world("shanghai", "blank"))
	main.map_view.center_on([31.19779295, 121.54595875], 14)
	await create_timer(8.0).timeout
	var count: int = main.map_view._tile_textures.size()
	var valid_count: int = main.map_view._tile_valid_count
	var visible_tile_keys: Dictionary = main.map_view._visible_tile_bounds()
	var visible_cached := 0
	for y in range(visible_tile_keys.top, visible_tile_keys.bottom + 1):
		for x in range(visible_tile_keys.left, visible_tile_keys.right + 1):
			if main.map_view._tile_textures.has("14/%d/%d" % [x, y]): visible_cached += 1
	if count > 0 and valid_count > 0 and visible_cached > 0 and not main.map_view._network_blocked:
		print("PASS: real map tiles loaded; visible=%d valid=%d visible_cached=%d stale blocked placeholders rejected=%d" % [count, valid_count, visible_cached, main.map_view._tile_placeholder_rejections])
		quit(0)
	else:
		push_error("No valid OSM map tile loaded; visible=%d valid=%d blocked=%s rejected=%d queued=%d active=%d city=%s map_size=%s" % [count, valid_count, str(main.map_view._network_blocked), main.map_view._tile_placeholder_rejections, main.map_view._tile_queue.size(), main.map_view._requests.size(), str(main.map_view.city_data.get("id", "")), str(main.map_view.size)])
		quit(1)
