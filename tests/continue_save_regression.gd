extends SceneTree

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
	var world := WorldData.new_world("shanghai", "blank")
	world.simulation.elapsedMinutes = 613
	world.simulation.minute = 613
	world.simulation.completed = 27
	world.simulation.attempted = 35
	world.simulation.waiting = 4
	var saved := SaveManager.save_world(world)
	_assert(bool(saved.get("ok", false)), "隔离环境建立测试存档")
	var indexed := SaveManager.save_last_game(world)
	_assert(bool(indexed.get("ok", false)), "隔离环境建立继续游戏索引")
	for attempt in range(5):
		main._continue_last_game()
		await process_frame
		_assert(main.active_city_id == "shanghai", "第 %d 次继续游戏恢复城市" % (attempt + 1))
		_assert(int(main.world.simulation.get("elapsedMinutes", -1)) == 613 + attempt, "第 %d 次继续游戏恢复累计时间" % (attempt + 1))
		_assert(int(main.world.simulation.get("completed", -1)) == 27, "第 %d 次继续游戏恢复到达统计" % (attempt + 1))
		_assert(not bool(main.save_failed) and not bool(main.save_dirty), "第 %d 次载入后的自动保存成功" % (attempt + 1))
		if attempt < 4:
			main.world.simulation.elapsedMinutes = 614 + attempt
			main.world.simulation.minute = posmod(614 + attempt, 1440)
			var roundtrip: bool = main._autosave()
			_assert(roundtrip, "第 %d 次修改后完整写入世界与索引" % (attempt + 1))
	if failures.is_empty():
		print("PASS: continue → load → full autosave repeated five times")
		quit(0)
	else:
		quit(1)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FAIL: %s" % message)
