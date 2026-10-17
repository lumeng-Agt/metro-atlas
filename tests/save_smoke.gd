extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var world := WorldData.new_world("shanghai", "blank")
	var expected_root := SaveManager.root_path() if SaveManager.using_explicit_data_dir() else OS.get_environment("APPDATA").path_join("MetroAtlas")
	_assert(SaveManager.root_path() == expected_root, "Windows 存档根目录为 APPDATA\\MetroAtlas")
	_assert(UiPreferences.path().get_base_dir() == SaveManager.root_path(), "偏好与存档、恢复副本共用同一数据根目录")
	if SaveManager.using_explicit_data_dir():
		var requested_root := ""
		for argument in OS.get_cmdline_user_args():
			if str(argument).begins_with("--data-dir="): requested_root = str(argument).trim_prefix("--data-dir=")
		_assert(SaveManager.root_path().begins_with(requested_root), "--data-dir 将存档与偏好完全隔离在测试目录")
	var save_path := SaveManager.save_path("shanghai", "blank")
	var recovery_failure_path := SaveManager.save_path("beijing", "blank")
	var migration_source_path := SaveManager.save_path("beijing", "expand")
	var migration_backup_dir := SaveManager.root_path().path_join("migration_backups")
	var last_path := SaveManager.last_game_path()
	var export_path := OS.get_user_data_dir().path_join("save-smoke-export.json")
	var preference_path := UiPreferences.path()
	var preference_original := FileAccess.get_file_as_bytes(preference_path) if FileAccess.file_exists(preference_path) else PackedByteArray()
	var manual_directory := SaveManager.manual_saves_dir()
	var protected_paths := [save_path, save_path + ".bak", save_path + ".tmp", recovery_failure_path, recovery_failure_path + ".bak", recovery_failure_path + ".tmp", migration_source_path, migration_source_path + ".bak", last_path, last_path + ".bak", last_path + ".tmp", export_path, export_path + ".bak", export_path + ".tmp"]
	var originals: Dictionary = {}
	for path in protected_paths: originals[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var first := SaveManager.save_world(world)
	_assert(bool(first.get("ok", false)), "可以创建本地存档")
	_assert(FileAccess.file_exists(save_path), "存档写入预期目录")
	world.simulation.minute = 481
	world.simulation.elapsedMinutes = 481
	world.simulation.elapsedSeconds = 481 * 60
	var second := SaveManager.save_world(world)
	_assert(bool(second.get("ok", false)), "可以更新本地存档")
	_assert(FileAccess.file_exists(save_path + ".bak"), "覆盖前保留恢复备份")
	for history_minute in range(482, 487):
		world.simulation.minute = history_minute
		world.simulation.elapsedMinutes = history_minute
		world.simulation.elapsedSeconds = history_minute * 60
		_assert(bool(SaveManager.save_world(world, true).get("ok", false)), "定时自动存档可保留上一份有效进度")
	var auto_history := SaveManager.list_auto_history("shanghai", "blank")
	_assert(auto_history.size() == 3, "每个城市与开局只保留最近3份自动历史")
	var latest_history := SaveManager.load_auto_history(str(auto_history[0].get("path", "")), "shanghai", "blank")
	_assert(bool(latest_history.get("ok", false)) and int(latest_history.world.simulation.elapsedMinutes) == 485, "最近自动历史能按校验入口载入并恢复真实时钟")
	world.simulation.minute = 481
	world.simulation.elapsedMinutes = 481
	world.simulation.elapsedSeconds = 481 * 60
	_assert(bool(SaveManager.save_world(world).get("ok", false)), "普通即时保存不轮换自动历史")
	var index_result := SaveManager.save_last_game(world)
	_assert(bool(index_result.get("ok", false)) and FileAccess.file_exists(last_path), "继续游戏索引写入成功")
	var loaded := SaveManager.load_world("shanghai", "blank")
	_assert(bool(loaded.get("ok", false)), "本地存档可以读取")
	_assert(int(loaded.get("world", {}).get("simulation", {}).get("minute", -1)) == 481, "重新读取最新模拟进度")
	var last_loaded := SaveManager.load_last_game()
	_assert(bool(last_loaded.get("ok", false)) and int(last_loaded.get("world", {}).get("simulation", {}).get("minute", -1)) == 481, "继续游戏索引经过相同结构校验后可读取")
	var manual_world: Dictionary = world.duplicate(true)
	manual_world.simulation.paused = false
	var manual_result := SaveManager.save_manual_snapshot(manual_world, "第一条线开通前")
	_assert(bool(manual_result.get("ok", false)) and FileAccess.file_exists(str(manual_result.get("path", ""))), "手动存档生成独立命名进度文件")
	var manual_entries := SaveManager.list_manual_snapshots()
	var listed_manual: Dictionary = {}
	for entry in manual_entries:
		if str(entry.get("path", "")) == str(manual_result.get("path", "")): listed_manual = entry
	_assert(not listed_manual.is_empty() and bool(listed_manual.get("valid", false)) and str(listed_manual.get("name", "")) == "第一条线开通前", "手动存档列表显示可用名称与状态")
	var manual_loaded := SaveManager.load_manual_snapshot(str(manual_result.get("path", "")))
	_assert(bool(manual_loaded.get("ok", false)) and str(manual_loaded.get("manualSaveName", "")) == "第一条线开通前", "手动存档通过完整校验后可以载入")
	_assert(bool(manual_loaded.get("world", {}).get("simulation", {}).get("paused", false)), "载入手动存档后默认暂停")
	_assert(not manual_loaded.get("world", {}).has("_manualSave"), "存档界面元数据不会进入游戏世界")
	var manual_renamed := SaveManager.rename_manual_snapshot(str(manual_result.get("path", "")), "站点方案草稿")
	_assert(bool(manual_renamed.get("ok", false)) and str(SaveManager.load_manual_snapshot(str(manual_result.get("path", ""))).get("manualSaveName", "")) == "站点方案草稿", "重命名只更新显示名称，进度仍可载入")
	manual_world.simulation.minute = 499
	manual_world.simulation.elapsedMinutes = 499
	var manual_overwritten := SaveManager.overwrite_manual_snapshot(str(manual_result.get("path", "")), manual_world, "站点方案草稿")
	_assert(bool(manual_overwritten.get("ok", false)) and int(SaveManager.load_manual_snapshot(str(manual_result.get("path", ""))).world.simulation.minute) == 499, "确认覆盖接口替换存档内容且保留可载入性")
	_assert(not SaveManager.load_manual_snapshot(save_path).get("ok", false), "手动存档读取拒绝存档目录之外的路径")
	var manual_delete := SaveManager.delete_manual_snapshot(str(manual_result.get("path", "")).get_file())
	_assert(bool(manual_delete.get("ok", false)) and not FileAccess.file_exists(str(manual_result.get("path", ""))), "可以删除单份手动存档")
	_assert(not bool(SaveManager.delete_manual_snapshot(save_path).get("ok", true)), "命名存档删除接口拒绝任意路径，只接受存档编号")
	var manual_bad_path := manual_directory.path_join("corrupt-manual-smoke.json")
	var manual_bad_file := FileAccess.open(manual_bad_path, FileAccess.WRITE)
	if manual_bad_file != null:
		manual_bad_file.store_string("not json")
		manual_bad_file.close()
	var manual_bad_listed := false
	for entry in SaveManager.list_manual_snapshots():
		if str(entry.get("path", "")) == manual_bad_path:
			manual_bad_listed = true
			_assert(not bool(entry.get("valid", true)), "损坏的手动存档显示为不可载入")
	_assert(manual_bad_listed, "手动存档列表保留损坏文件并明确标记")
	if FileAccess.file_exists(manual_bad_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(manual_bad_path))
	var old_autosave_enabled := UiPreferences.load_timed_autosave_enabled()
	var old_autosave_interval := UiPreferences.load_timed_autosave_interval()
	_assert(UiPreferences.save_timed_autosave_enabled(not old_autosave_enabled) == OK and UiPreferences.load_timed_autosave_enabled() == not old_autosave_enabled, "定时自动存档开关可本地保存与恢复")
	_assert(UiPreferences.save_timed_autosave_interval(10) == OK and UiPreferences.load_timed_autosave_interval() == 10, "自动存档间隔可本地保存与恢复")
	_assert(UiPreferences.save_timed_autosave_interval(3) != OK, "无效自动存档间隔被拒绝")
	if preference_original.is_empty():
		if FileAccess.file_exists(preference_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(preference_path))
	else:
		var restore_preferences := FileAccess.open(preference_path, FileAccess.WRITE)
		if restore_preferences:
			restore_preferences.store_buffer(preference_original)
			restore_preferences.close()
	world.simulation.minute = 482
	var index_update := SaveManager.save_last_game(world)
	_assert(bool(index_update.get("ok", false)) and FileAccess.file_exists(last_path + ".bak"), "更新继续游戏索引前保留有效备份")
	var known_good_index_backup := FileAccess.get_file_as_bytes(last_path + ".bak")
	var damaged_index := FileAccess.open(last_path, FileAccess.WRITE)
	if damaged_index != null:
		damaged_index.store_string(JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION, "cityId":"shanghai", "mode":"blank", "routes":"broken"}))
		damaged_index.close()
	var recovered_index := SaveManager.load_last_game()
	_assert(bool(recovered_index.get("ok", false)) and bool(recovered_index.get("recovered", false)) and bool(recovered_index.get("recoveryCopySaved", false)), "结构损坏的继续游戏索引会从有效备份恢复")
	_assert(int(recovered_index.get("world", {}).get("simulation", {}).get("minute", -1)) == 481, "继续游戏索引恢复到备份中的完整状态")
	var saved_recovered_index := SaveManager.save_last_game(recovered_index.world)
	_assert(bool(saved_recovered_index.get("ok", false)), "恢复继续游戏索引后可重新保存")
	_assert(FileAccess.get_file_as_bytes(last_path + ".bak") == known_good_index_backup, "恢复继续游戏索引时不覆盖仍有效的备份")
	var damaged_index_again := FileAccess.open(last_path, FileAccess.WRITE)
	if damaged_index_again != null:
		damaged_index_again.store_string(JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION, "cityId":"shanghai", "mode":"blank", "routes":"broken"}))
		damaged_index_again.close()
	var pending_index_recovery := SaveManager.load_last_game(true)
	_assert(bool(pending_index_recovery.get("ok", false)) and bool(pending_index_recovery.get("pendingRecoveryConfirmation", false)) and not bool(pending_index_recovery.get("recoveryCopySaved", false)), "继续游戏索引先等待玩家确认，不提前创建恢复副本")
	var confirmed_index_recovery := SaveManager.confirm_backup_recovery(pending_index_recovery)
	_assert(bool(confirmed_index_recovery.get("ok", false)) and bool(confirmed_index_recovery.get("recoveryCopySaved", false)), "确认索引恢复后才写入独立恢复副本")
	var index_restore := SaveManager.save_last_game(confirmed_index_recovery.world)
	_assert(bool(index_restore.get("ok", false)), "确认索引恢复后能够重新保存")
	var known_good_backup := FileAccess.get_file_as_bytes(save_path + ".bak")
	var damaged_main := FileAccess.open(save_path, FileAccess.WRITE)
	if damaged_main != null:
		damaged_main.store_string(JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION, "cityId":"shanghai", "mode":"blank", "stations":"broken"}))
		damaged_main.close()
	var recovered := SaveManager.load_world("shanghai", "blank")
	_assert(bool(recovered.get("ok", false)) and bool(recovered.get("recovered", false)) and bool(recovered.get("recoveryCopySaved", false)), "结构校验失败的主存档会从有效备份恢复并先留独立副本")
	_assert(str(recovered.get("recoverySource", "")) == save_path + ".bak", "恢复结果显示实际来源备份")
	var save_after_recovery := SaveManager.save_world(recovered.get("world", {}))
	_assert(bool(save_after_recovery.get("ok", false)), "恢复后的有效规划可以再次保存")
	_assert(FileAccess.get_file_as_bytes(save_path + ".bak") == known_good_backup, "损坏主档恢复后不会覆盖原有效备份")
	var reloaded_backup := SaveManager.prepare_loaded_world(JSON.parse_string(FileAccess.get_file_as_string(save_path + ".bak")))
	_assert(bool(reloaded_backup.get("ok", false)), "恢复后保留的主备份仍可独立校验")
	var damaged_main_again := FileAccess.open(save_path, FileAccess.WRITE)
	if damaged_main_again != null:
		damaged_main_again.store_string(JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION, "cityId":"shanghai", "mode":"blank", "stations":"broken"}))
		damaged_main_again.close()
	var pending_main_recovery := SaveManager.load_world("shanghai", "blank", true)
	_assert(bool(pending_main_recovery.get("ok", false)) and bool(pending_main_recovery.get("pendingRecoveryConfirmation", false)) and not bool(pending_main_recovery.get("recoveryCopySaved", false)), "城市主档恢复需要玩家确认，读取阶段不写恢复文件")
	var confirmed_main_recovery := SaveManager.confirm_backup_recovery(pending_main_recovery)
	_assert(bool(confirmed_main_recovery.get("ok", false)) and bool(confirmed_main_recovery.get("recoveryCopySaved", false)), "确认城市恢复后独立恢复副本写入成功")
	var save_confirmed_recovery := SaveManager.save_world(confirmed_main_recovery.world)
	_assert(bool(save_confirmed_recovery.get("ok", false)), "确认恢复后的城市存档可以正常保存")
	var protected_main_bytes := FileAccess.get_file_as_bytes(save_path)
	var main_backup_blocker := ProjectSettings.globalize_path(save_path + ".bak.tmp")
	DirAccess.make_dir_absolute(main_backup_blocker)
	world.simulation.minute = 483
	var failed_main_backup := SaveManager.save_world(world)
	_assert(not bool(failed_main_backup.get("ok", false)), "恢复备份无法写入时拒绝覆盖主存档")
	_assert(FileAccess.get_file_as_bytes(save_path) == protected_main_bytes, "主存档备份写入失败后原进度字节保持不变")
	DirAccess.remove_absolute(main_backup_blocker)
	var protected_index_bytes := FileAccess.get_file_as_bytes(last_path)
	var index_backup_blocker := ProjectSettings.globalize_path(last_path + ".bak.tmp")
	DirAccess.make_dir_absolute(index_backup_blocker)
	var failed_index_backup := SaveManager.save_last_game(world)
	_assert(not bool(failed_index_backup.get("ok", false)), "继续游戏备份无法写入时拒绝覆盖索引")
	_assert(FileAccess.get_file_as_bytes(last_path) == protected_index_bytes, "继续游戏索引备份失败后原进度字节保持不变")
	DirAccess.remove_absolute(index_backup_blocker)
	var malformed := WorldData.new_world("shanghai", "blank")
	malformed["trackNodes"] = [{"id":"bad-coordinate", "latlng":[INF, 121.0], "depthM":-15.0}]
	var malformed_result := SaveManager.prepare_loaded_world(malformed)
	_assert(not bool(malformed_result.get("ok", false)) and str(malformed_result.get("status", "")) == "corrupt", "非有限轨道节点坐标在载入和自动保存前被拒绝")
	var exported := SaveManager._write_export(export_path, world)
	_assert(bool(exported.get("ok", false)) and FileAccess.file_exists(export_path), "JSON 导出成功并创建文件")
	world.simulation.minute = 510
	var exported_again := SaveManager._write_export(export_path, world)
	_assert(bool(exported_again.get("ok", false)) and FileAccess.file_exists(export_path + ".bak"), "覆盖 JSON 导出时保留恢复副本")
	var old_version := WorldData.new_world("beijing", "expand")
	old_version.schemaVersion = 10
	var old_file := FileAccess.open(migration_source_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_version))
	old_file.close()
	var migrated := SaveManager.load_world("beijing", "expand")
	_assert(bool(migrated.get("ok", false)) and int(migrated.get("world", {}).get("schemaVersion", 0)) == WorldData.SAVE_VERSION, "读取版本 10 存档时升级至当前格式")
	var migration_files := DirAccess.get_files_at(ProjectSettings.globalize_path(migration_backup_dir))
	var has_migration_backup := false
	for filename in migration_files:
		if filename.begins_with("beijing_expand_v10-") and filename.ends_with("-original.json"): has_migration_backup = true
	_assert(has_migration_backup, "版本 10 转换前按原始内容保留独立副本")
	var recovery_world := WorldData.new_world("beijing", "blank")
	_assert(bool(SaveManager.save_world(recovery_world).get("ok", false)), "故障恢复测试能够创建隔离存档")
	recovery_world.simulation.minute = 445
	_assert(bool(SaveManager.save_world(recovery_world).get("ok", false)), "故障恢复测试能够保留有效备份")
	var recovery_backup_bytes := FileAccess.get_file_as_bytes(recovery_failure_path + ".bak")
	var damaged_recovery_main := FileAccess.open(recovery_failure_path, FileAccess.WRITE)
	if damaged_recovery_main != null:
		damaged_recovery_main.store_string(JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION, "cityId":"beijing", "mode":"blank", "stations":"damaged"}))
		damaged_recovery_main.close()
	var damaged_recovery_bytes := FileAccess.get_file_as_bytes(recovery_failure_path)
	var recovery_root := SaveManager.root_path().path_join("recovery_backups")
	var recovery_hold := SaveManager.root_path().path_join("recovery_backups_test_hold")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(recovery_root)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(recovery_root), ProjectSettings.globalize_path(recovery_hold))
	var blocker := FileAccess.open(recovery_root, FileAccess.WRITE)
	if blocker != null:
		blocker.store_string("block recovery folder creation")
		blocker.close()
	var blocked_recovery := SaveManager.load_world("beijing", "blank")
	_assert(not bool(blocked_recovery.get("ok", false)) and str(blocked_recovery.get("status", "")) == "backup_failed", "独立恢复副本无法写入时停止载入")
	_assert(FileAccess.get_file_as_bytes(recovery_failure_path + ".bak") == recovery_backup_bytes, "恢复副本写入失败不会覆盖有效备份")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery_root))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(recovery_hold)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(recovery_hold), ProjectSettings.globalize_path(recovery_root))
	_assert(FileAccess.get_file_as_bytes(recovery_failure_path) == damaged_recovery_bytes, "故障注入期间保留原始损坏主存档，不以空白开局覆盖")
	for path in protected_paths:
		if originals[path].is_empty():
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var restore := FileAccess.open(path, FileAccess.WRITE)
			if restore:
				restore.store_buffer(originals[path])
				restore.close()
	print("PASS: local autosaves, named manual saves, last-game index, export, reload, and backups")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition: push_error("FAIL: %s" % message); quit(1)
