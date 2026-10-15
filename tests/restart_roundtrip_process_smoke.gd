extends SceneTree

const Simulation = preload("res://scripts/simulation_engine.gd")
const Journey = preload("res://scripts/journey_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var args := OS.get_cmdline_user_args()
	var phase := _argument(args, "--phase", "cycle")
	var cycle := int(_argument(args, "--cycle", "1"))
	if phase == "seed":
		_seed_roundtrip()
		return
	var main_scene := load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var state_path := SaveManager.root_path().path_join("roundtrip_state.json")
	var state_file := FileAccess.open(state_path, FileAccess.READ)
	if state_file == null:
		_fail("测试状态文件缺失")
		return
	var expected: Variant = JSON.parse_string(state_file.get_as_text())
	state_file.close()
	if not expected is Dictionary:
		_fail("测试状态文件损坏")
		return
	main._continue_last_game()
	await process_frame
	await process_frame
	var world: Dictionary = main.world
	if world.is_empty() or main.active_city_id != "shanghai":
		_fail("独立进程未能继续载入上海规划")
		return
	var simulation: Dictionary = world.get("simulation", {})
	if int(simulation.get("elapsedSeconds", -1)) != int(expected.get("elapsedSeconds", -2)):
		_fail("第 %d 次重新启动未恢复累计游戏秒" % cycle)
		return
	if int(simulation.get("completed", -1)) != int(expected.get("completed", -2)) or int(simulation.get("inTransit", -1)) != int(expected.get("inTransit", -2)):
		_fail("第 %d 次重新启动未恢复到达与在途人数" % cycle)
		return
	if world.get("stations", []).size() != 2 or world.get("routes", []).size() != 1 or world.get("trackEdges", []).size() != 1:
		_fail("第 %d 次重新启动未恢复两站、一条线路和物理区间" % cycle)
		return
	var batches: Array = simulation.get("passengerBatches", [])
	var has_ride_batch := false
	for batch in batches:
		if str(batch.get("status", "")) == "riding": has_ride_batch = true
	if int(simulation.get("inTransit", 0)) > 0 and not has_ride_batch:
		_fail("在途统计没有对应的乘客批次")
		return
	var route_id := str(world.routes[0].get("id", ""))
	var flow := _test_flow(world)
	if not bool(flow.get("valid", false)):
		_fail("恢复后的运营线路不能生成测试旅程")
		return
	Simulation.step_one_minute(world, [flow], 1.0)
	var new_elapsed := int(world.simulation.get("elapsedSeconds", -1))
	if new_elapsed != int(expected.elapsedSeconds) + 60:
		_fail("重新启动后的实际模拟推进没有增加 60 游戏秒")
		return
	var save_result: bool = main._autosave(false)
	if not save_result or main.save_failed or main.save_dirty:
		_fail("继续游戏后保存规划与运行状态失败")
		return
	var reloaded := SaveManager.load_world("shanghai", "blank")
	if not bool(reloaded.get("ok", false)):
		_fail("独立进程写入的存档不能重新读取")
		return
	var saved_world: Dictionary = reloaded.get("world", {})
	if int(saved_world.get("simulation", {}).get("elapsedSeconds", -1)) != new_elapsed:
		_fail("自动保存未写入秒级模拟时钟")
		return
	var next_state := {
		"elapsedSeconds": new_elapsed,
		"completed": int(world.simulation.get("completed", 0)),
		"inTransit": int(world.simulation.get("inTransit", 0)),
		"batchCount": world.simulation.get("passengerBatches", []).size(),
		"routeId": route_id,
	}
	var state_write := FileAccess.open(state_path, FileAccess.WRITE)
	if state_write == null:
		_fail("无法更新独立进程测试状态")
		return
	state_write.store_string(JSON.stringify(next_state))
	state_write.flush()
	var state_error := state_write.get_error()
	state_write.close()
	if state_error != OK:
		_fail("独立进程测试状态写入不完整")
		return
	print("PASS: restart %d restored route and passenger batches at %d seconds; next save completed" % [cycle, new_elapsed])
	quit(0)

func _seed_roundtrip() -> void:
	var world := WorldData.new_world("shanghai", "blank")
	var route: Dictionary = WorldData.add_route(world, "重启续玩测试线", "#42b98f")
	route["id"] = "roundtrip-route"
	route["networkBased"] = true
	route["open"] = true
	route["vehicleId"] = "B-4"
	route["headway"] = 3
	var first := WorldData.create_station(world, [31.2304, 121.4737], 90.0, str(route.id), "B-4", -15.0)
	first["id"] = "roundtrip-station-a"
	first["name"] = "重启测试 A 站"
	var second := WorldData.create_station(world, [31.2334, 121.4737], 90.0, str(route.id), "B-4", -15.0)
	second["id"] = "roundtrip-station-b"
	second["name"] = "重启测试 B 站"
	for node in world.trackNodes:
		if str(node.get("id", "")) in first.get("endpointNodes", {}).values(): node["stationId"] = str(first.id)
		elif str(node.get("id", "")) in second.get("endpointNodes", {}).values(): node["stationId"] = str(second.id)
	TrackNetwork.ensure_station_nodes(world)
	var edge_id := "roundtrip-physical-edge"
	world.trackEdges.append({
		"id": edge_id,
		"aNodeId": TrackNetwork.station_node_id(first, "end"),
		"bNodeId": TrackNetwork.station_node_id(second, "start"),
		"geometry": "straight",
		"depthM": -15.0,
		"routeIds": [str(route.id)],
	})
	route["stationOrder"] = [str(first.id), str(second.id)]
	route["directions"] = [
		{"id":"out", "stationIds":[str(first.id), str(second.id)], "edgePathsBySegment":[[{"id":edge_id, "forward":true}]]},
		{"id":"back", "stationIds":[str(second.id), str(first.id)], "edgePathsBySegment":[[{"id":edge_id, "forward":false}]]},
	]
	world.simulation["elapsedSeconds"] = 420 * 60
	world.simulation["elapsedMinutes"] = 420
	world.simulation["minute"] = 420
	var flow := _test_flow(world)
	if not bool(flow.get("valid", false)):
		_fail("无法为重启测试生成实际的乘客旅程")
		return
	var attempts := 0
	while attempts < 30 and int(world.simulation.get("inTransit", 0)) == 0:
		Simulation.step_one_minute(world, [flow], 1.0)
		attempts += 1
	if int(world.simulation.get("inTransit", 0)) <= 0:
		_fail("种子模拟没有产生在途乘客批次")
		return
	var save_result := SaveManager.save_world(world)
	var index_result := SaveManager.save_last_game(world)
	if not bool(save_result.get("ok", false)) or not bool(index_result.get("ok", false)):
		_fail("无法写入隔离的续玩种子存档")
		return
	var state_path := SaveManager.root_path().path_join("roundtrip_state.json")
	var state_file := FileAccess.open(state_path, FileAccess.WRITE)
	if state_file == null:
		_fail("无法建立独立进程测试状态")
		return
	state_file.store_string(JSON.stringify({
		"elapsedSeconds": int(world.simulation.get("elapsedSeconds", 0)),
		"completed": int(world.simulation.get("completed", 0)),
		"inTransit": int(world.simulation.get("inTransit", 0)),
		"batchCount": world.simulation.get("passengerBatches", []).size(),
		"routeId": str(route.id),
	}))
	state_file.flush()
	var error := state_file.get_error()
	state_file.close()
	if error != OK:
		_fail("种子模拟状态写入失败")
		return
	print("PASS: isolated seed contains two stations, a route, %d passengers in transit and %d batches at %d seconds" % [int(world.simulation.inTransit), world.simulation.passengerBatches.size(), int(world.simulation.elapsedSeconds)])
	quit(0)

func _test_flow(world: Dictionary) -> Dictionary:
	var route: Dictionary = world.get("routes", [{}])[0] if not world.get("routes", []).is_empty() else {}
	if route.is_empty(): return {"valid": false}
	var city := WorldData.city(str(world.get("cityId", "shanghai")))
	var ref_lat := float(city.get("center", [31.23, 121.47])[0])
	var network := Journey.build_network(world, ref_lat)
	var first: Dictionary = world.get("stations", [])[0]
	var second: Dictionary = world.get("stations", [])[1]
	var origin := {"id":"roundtrip-origin", "name":"测试起点", "latlng":first.get("latlng", [])}
	var destination := {"id":"roundtrip-destination", "name":"测试终点", "latlng":second.get("latlng", [])}
	var journey := Journey.find_journey(origin, destination, world, network, ref_lat)
	return {"id":"roundtrip-origin>roundtrip-destination", "fromId":origin.id, "toId":destination.id, "peoplePerDay":57600.0, "valid":bool(journey.get("valid", false)), "routeId":str(route.get("id", "")), "journey":journey}

func _argument(args: PackedStringArray, key: String, fallback: String) -> String:
	for index in range(args.size()):
		var value := str(args[index])
		if value.begins_with(key + "="): return value.trim_prefix(key + "=")
		if value == key and index + 1 < args.size(): return str(args[index + 1])
	return fallback

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
