extends SceneTree

const FRAME_COUNT_PER_LEVEL := 60

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 980))
	var benchmark_state := WorldData.new_world("shanghai", "expand")
	benchmark_state["view"] = {"center": [31.2304, 121.4737], "zoom": 14}
	# Invalid mode makes save validation fail before opening any player's files.
	benchmark_state["mode"] = "benchmark"
	main._load_world(benchmark_state)
	var scenarios := [
		{"name":"城市总览", "zoom":12, "pan":0.000010},
		{"name":"街区道路", "zoom":14, "pan":0.000005},
		{"name":"站点周边建筑", "zoom":17, "pan":0.000001}
	]
	var has_failure := false
	for scenario in scenarios:
		var map_view: MapView = main.map_view
		var zoom := int(scenario.zoom)
		map_view.current_zoom = zoom
		map_view.current_center = [31.2304, 121.4737]
		map_view.requested_redraw()
		var cold_start := Time.get_ticks_usec()
		var maximum_loading_frame_ms := 0.0
		var maximum_loading_frame_index := -1
		var first_window_frame_ms := 0.0
		for frame_index in range(1800):
			var frame_started := Time.get_ticks_usec()
			await process_frame
			var frame_ms := float(Time.get_ticks_usec() - frame_started) / 1000.0
			if frame_index == 0:
				first_window_frame_ms = frame_ms
			elif frame_ms > maximum_loading_frame_ms:
				maximum_loading_frame_ms = frame_ms
				maximum_loading_frame_index = frame_index
			if not map_view._base_map_thread_busy and map_view._base_map_pending_request.is_empty() and not map_view.base_map_features.is_empty(): break
		var base_ready := not map_view.base_map_features.is_empty() and not map_view._base_map_thread_busy and map_view._base_map_pending_request.is_empty()
		if not base_ready:
			push_error("本地地图未能在性能场景中完成加载：%s" % str(scenario.name))
			has_failure = true
		var cold_ms := float(Time.get_ticks_usec() - cold_start) / 1000.0
		var kinds: Dictionary = {}
		var visible_kinds: Dictionary = {}
		map_view._refresh_camera_cache()
		var visible_half: Vector2 = map_view.size * 0.5 * map_view._camera_mpp
		var visible_rect := Rect2(map_view._camera_local_center - visible_half, visible_half * 2.0).grow(80.0 * map_view._camera_mpp)
		for feature in map_view.base_map_features:
			var kind := str(feature.get("kind", ""))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			if visible_rect.intersects(feature.get("bounds", Rect2())):
				visible_kinds[kind] = int(visible_kinds.get(kind, 0)) + 1
		var deltas: Array[float] = []
		var last_frame := Time.get_ticks_usec()
		for frame in range(FRAME_COUNT_PER_LEVEL):
			map_view.current_center = [31.2304 + frame * float(scenario.pan), 121.4737 + frame * float(scenario.pan)]
			map_view.requested_redraw()
			await process_frame
			var now := Time.get_ticks_usec()
			deltas.append(float(now - last_frame) / 1000.0)
			last_frame = now
		var sorted_deltas := deltas.duplicate(); sorted_deltas.sort()
		var mean_ms := 0.0; var slow_frames := 0
		for delta_ms in deltas:
			mean_ms += delta_ms
			if delta_ms > 33.333: slow_frames += 1
		mean_ms /= maxf(1.0, float(deltas.size()))
		var percentile_index := mini(sorted_deltas.size() - 1, floori(float(sorted_deltas.size() - 1) * 0.95))
		var p95_ms: float = sorted_deltas[percentile_index] if percentile_index >= 0 else 0.0
		var fps := 1000.0 / maxf(0.001, mean_ms)
		print("MAP %s zoom=%d cold_load_ms=%.1f initial_window_frame_ms=%.2f maximum_map_loading_frame_ms=%.2f at_frame=%d prepared_features=%s visible_features=%s average_fps=%.1f p95_frame_ms=%.2f frames_over_33ms=%d" % [str(scenario.name), zoom, cold_ms, first_window_frame_ms, maximum_loading_frame_ms, maximum_loading_frame_index, kinds, visible_kinds, fps, p95_ms, slow_frames])
		if fps < 30.0 or p95_ms > 33.333 or maximum_loading_frame_ms > 100.0: has_failure = true
	var simulation_started := Time.get_ticks_usec()
	for _minute in range(60): main._simulate_one_minute()
	var simulation_ms := float(Time.get_ticks_usec() - simulation_started) / 1000.0
	var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var peak_memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576.0
	print("SIMULATION Shanghai max-network stations=%d routes=%d links=%d game_minutes=60 simulation_ms=%.1f memory_mb=%.1f peak_memory_mb=%.1f" % [main.world.stations.size(), main.world.routes.size(), main.world.trackEdges.size() + main.world.trackLinks.size(), simulation_ms, memory_mb, peak_memory_mb])
	if has_failure:
		push_error("Native map performance did not meet the 30 FPS / 33.3 ms pressure target.")
		quit(1)
	else:
		print("PASS: multi-scale native map performance met the pressure target")
		quit(0)
