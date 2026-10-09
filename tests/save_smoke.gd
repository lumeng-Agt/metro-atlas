extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var world := WorldData.new_world("shanghai", "blank")
	var expected_root := OS.get_environment("APPDATA").path_join("MetroAtlas")
	_assert(SaveManager.root_path() == expected_root, "Windows 存档根目录为 APPDATA\\MetroAtlas")
	var first := SaveManager.save_world(world)
	_assert(bool(first.get("ok", false)), "可以创建本地存档")
	var save_path := SaveManager.save_path("shanghai", "blank")
	_assert(FileAccess.file_exists(save_path), "存档写入预期目录")
	world.simulation.minute = 481
	var second := SaveManager.save_world(world)
	_assert(bool(second.get("ok", false)), "可以更新本地存档")
	_assert(FileAccess.file_exists(save_path + ".bak"), "覆盖前保留恢复备份")
	var loaded := SaveManager.load_world("shanghai", "blank")
	_assert(bool(loaded.get("ok", false)), "本地存档可以读取")
	_assert(int(loaded.get("world", {}).get("simulation", {}).get("minute", -1)) == 481, "重新读取最新模拟进度")
	for path in [save_path, save_path + ".bak", save_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PASS: local save location, reload, and backup")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition: push_error("FAIL: %s" % message); quit(1)
