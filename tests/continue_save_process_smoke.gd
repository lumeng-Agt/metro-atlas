extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1366, 768)
	WorldData.load_assets()
	var main_scene := load("res://scenes/main.tscn")
	var main: Variant = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if not FileAccess.file_exists(SaveManager.last_game_path()):
		var seed_world := WorldData.new_world("shanghai", "blank")
		seed_world.simulation["elapsedMinutes"] = 420
		seed_world.simulation["minute"] = 420
		seed_world.simulation["completed"] = 27
		var save_result := SaveManager.save_world(seed_world)
		var index_result := SaveManager.save_last_game(seed_world)
		if not bool(save_result.get("ok", false)) or not bool(index_result.get("ok", false)):
			push_error("failed to seed isolated game save")
			quit(1)
			return
	main._continue_last_game()
	await process_frame
	var elapsed := int(main.world.get("simulation", {}).get("elapsedMinutes", -1))
	if main.active_city_id != "shanghai" or elapsed < 420 or int(main.world.simulation.get("completed", 0)) != 27 or main.save_failed or main.save_dirty:
		push_error("restart did not restore the world and complete its autosave")
		quit(1)
		return
	main.world.simulation["elapsedMinutes"] = elapsed + 1
	main.world.simulation["minute"] = posmod(elapsed + 1, 1440)
	if not main._autosave(false):
		push_error("restart autosave failed")
		quit(1)
		return
	print("PASS: fresh process restored and saved game at minute %d" % elapsed)
	quit(0)
