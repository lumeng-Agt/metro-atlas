class_name SaveManager
extends RefCounted

const CityProgressionScript = preload("res://scripts/city_progression.gd")

static func root_path() -> String:
	var user_args := OS.get_cmdline_user_args()
	for index in range(user_args.size()):
		var arg := str(user_args[index])
		if arg.begins_with("--data-dir="):
			var requested := arg.trim_prefix("--data-dir=").strip_edges()
			if not requested.is_empty(): return ProjectSettings.globalize_path(requested)
		if arg == "--data-dir" and index + 1 < user_args.size():
			var requested := str(user_args[index + 1]).strip_edges()
			if not requested.is_empty(): return ProjectSettings.globalize_path(requested)
	if OS.get_name() == "Windows":
		var roaming := OS.get_environment("APPDATA")
		if not roaming.is_empty(): return roaming.path_join("MetroAtlas")
	return "user://MetroAtlas"

static func using_explicit_data_dir() -> bool:
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--data-dir" or str(arg).begins_with("--data-dir="):
			return true
	return false

static func save_dir() -> String:
	return root_path().path_join("saves")

static func last_game_path() -> String:
	return root_path().path_join("last_game.json")

static func save_path(city_id: String, mode: String) -> String:
	return save_dir().path_join("%s_%s.json" % [city_id, mode])

static func auto_history_dir(city_id: String, mode: String) -> String:
	return root_path().path_join("auto_history").path_join("%s_%s" % [city_id, mode])

static func _read_valid_current_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"valid": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"valid": false}
	var parsed: Variant = _parse_json_text(file.get_as_text())
	file.close()
	if not parsed is Dictionary: return {"valid": false}
	return {"valid": _validate_world(parsed).is_empty()}

static func _copy_file(source_path: String, target_path: String) -> Dictionary:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null: return {"ok": false, "error": "无法读取来源文件"}
	var bytes := source.get_buffer(source.get_length())
	source.close()
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null: return {"ok": false, "error": "无法创建临时副本"}
	target.store_buffer(bytes)
	target.flush()
	var write_error := target.get_error()
	target.close()
	if write_error != OK or not FileAccess.file_exists(target_path): return {"ok": false, "error": "临时副本写入不完整"}
	if FileAccess.get_file_as_bytes(source_path) != FileAccess.get_file_as_bytes(target_path): return {"ok": false, "error": "临时副本校验不一致"}
	return {"ok": true}

static func _prepare_backup(source_path: String, backup_path: String, label: String) -> Dictionary:
	var backup_temp := backup_path + ".tmp"
	var copied := _copy_file(source_path, backup_temp)
	if not bool(copied.get("ok", false)):
		return {"ok": false, "error": "%s：%s" % [label, copied.get("error", "复制失败")]}
	var previous_backup := backup_path + ".previous_%d" % Time.get_ticks_usec()
	var had_previous := FileAccess.file_exists(backup_path)
	if had_previous:
		var hold_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(previous_backup))
		if hold_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_temp))
			return {"ok": false, "error": "%s：无法暂存上一份备份" % label}
	var promote_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_temp), ProjectSettings.globalize_path(backup_path))
	if promote_error != OK:
		if had_previous:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(previous_backup), ProjectSettings.globalize_path(backup_path))
		return {"ok": false, "error": "%s：无法完成备份替换" % label}
	if had_previous: DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_backup))
	return {"ok": true}

static func _restore_main_from_backup_if_missing(main_path: String, backup_path: String) -> void:
	if FileAccess.file_exists(main_path) or not FileAccess.file_exists(backup_path): return
	var restore_temp := main_path + ".restore.tmp"
	var copied := _copy_file(backup_path, restore_temp)
	if not bool(copied.get("ok", false)): return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(restore_temp), ProjectSettings.globalize_path(main_path))

static func save_world(world: Dictionary, preserve_history: bool = false) -> Dictionary:
	var validation_error := _validate_world(world)
	if not validation_error.is_empty(): return {"ok": false, "error": validation_error}
	var path := save_path(str(world.get("cityId", "unknown")), str(world.get("mode", "blank")))
	var dir_path := ProjectSettings.globalize_path(save_dir())
	var dir_error := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_error != OK and not DirAccess.dir_exists_absolute(dir_path): return {"ok": false, "error": "无法创建本地存档目录"}
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "存档写入失败：%s" % error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(world, "\t"))
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK: return {"ok": false, "error": "存档未能完整写入"}
	if FileAccess.file_exists(path):
		var existing := _read_valid_current_save(path)
		if bool(existing.get("valid", false)):
			# Prepare and verify a replacement backup before touching the live file.
			var backup_result := _prepare_backup(path, backup_path, "无法安全准备恢复备份")
			if not bool(backup_result.get("ok", false)): return {"ok": false, "error": str(backup_result.get("error", "无法完成恢复备份"))}
		else:
			# A damaged main file must never replace a known-good .bak.
			var damaged_path := path + ".corrupt_%d" % Time.get_ticks_usec()
			var preserve_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(damaged_path))
			if preserve_error != OK: return {"ok": false, "error": "原存档损坏且无法隔离；为保护原文件，保存已停止"}
	var replace_err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if replace_err != OK:
		_restore_main_from_backup_if_missing(path, backup_path)
		return {"ok": false, "error": "无法替换旧存档"}
	var result := {"ok": true, "path": path}
	if preserve_history and FileAccess.file_exists(backup_path):
		var archived := _archive_auto_snapshot(backup_path, str(world.get("cityId", "unknown")), str(world.get("mode", "blank")))
		if not bool(archived.get("ok", false)): result["warning"] = str(archived.get("error", "自动存档历史未更新"))
	return result

static func _archive_auto_snapshot(source_path: String, city_id: String, mode: String) -> Dictionary:
	var checked := _read_valid_current_save(source_path)
	if not bool(checked.get("valid", false)): return {"ok": false, "error": "上一份自动存档无效，未加入历史"}
	var history_path := auto_history_dir(city_id, mode)
	var absolute_dir := ProjectSettings.globalize_path(history_path)
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if make_error != OK and not DirAccess.dir_exists_absolute(absolute_dir): return {"ok": false, "error": "无法创建自动存档历史目录"}
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace("/", "-").replace("T", "_")
	var target := history_path.path_join("%s_%s_%s_%d.json" % [city_id, mode, stamp, Time.get_ticks_usec()])
	var copied := _copy_file(source_path, target)
	if not bool(copied.get("ok", false)): return copied
	_prune_auto_history(city_id, mode)
	return {"ok": true, "path": target}

static func _prune_auto_history(city_id: String, mode: String) -> void:
	var entries := list_auto_history(city_id, mode)
	for index in range(3, entries.size()):
		var path := str(entries[index].get("path", ""))
		if not path.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func list_auto_history(city_id: String, mode: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var expected_dir := ProjectSettings.globalize_path(auto_history_dir(city_id, mode)).simplify_path()
	var dir := DirAccess.open(expected_dir)
	if dir == null: return entries
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.to_lower().ends_with(".json"):
			var path := auto_history_dir(city_id, mode).path_join(filename)
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var parsed: Variant = _parse_json_text(file.get_as_text())
				file.close()
				if parsed is Dictionary:
					var prepared := prepare_loaded_world(parsed)
					entries.append({"path": path, "valid": bool(prepared.get("ok", false)), "error": str(prepared.get("error", "")), "savedAt": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path), true), "modified": FileAccess.get_modified_time(path), "elapsedMinutes": int(parsed.get("simulation", {}).get("elapsedMinutes", 0)), "stationCount": parsed.get("stations", []).size(), "routeCount": parsed.get("routes", []).size()})
		filename = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_modified := int(a.get("modified", 0))
		var b_modified := int(b.get("modified", 0))
		if a_modified != b_modified: return a_modified > b_modified
		return str(a.get("path", "")) > str(b.get("path", ""))
	)
	return entries

static func load_auto_history(path: String, city_id: String, mode: String) -> Dictionary:
	var expected_dir := ProjectSettings.globalize_path(auto_history_dir(city_id, mode)).simplify_path()
	var normalized_path := ProjectSettings.globalize_path(path).simplify_path()
	if normalized_path.get_base_dir() != expected_dir: return {"ok": false, "status": "invalid_path", "error": "自动存档历史位置无效。"}
	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null: return {"ok": false, "status": "read_error", "error": "无法读取自动存档历史。"}
	var parsed: Variant = _parse_json_text(file.get_as_text())
	file.close()
	if not parsed is Dictionary: return {"ok": false, "status": "corrupt", "error": "自动存档历史损坏。"}
	var prepared := prepare_loaded_world(parsed)
	if bool(prepared.get("ok", false)): prepared["historyPath"] = normalized_path
	return prepared

static func auto_history_bytes(city_id: String = "", mode: String = "") -> int:
	var total := 0
	var paths: Array[String] = []
	if not city_id.is_empty():
		for entry in list_auto_history(city_id, mode): paths.append(str(entry.get("path", "")))
	else:
		for city in WorldData.cities():
			for save_mode in ["blank", "expand"]:
				for entry in list_auto_history(str(city.get("id", "")), save_mode): paths.append(str(entry.get("path", "")))
	for path in paths:
		if FileAccess.file_exists(path): total += FileAccess.get_file_as_bytes(path).size()
	return total

static func _parse_json_text(source_text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(source_text) != OK:
		return null
	return parser.data

static func save_last_game(world: Dictionary) -> Dictionary:
	var validation_error := _validate_world(world)
	if not validation_error.is_empty(): return {"ok": false, "error": validation_error}
	var root := root_path()
	var absolute_dir := ProjectSettings.globalize_path(root)
	var err := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK and not DirAccess.dir_exists_absolute(absolute_dir): return {"ok": false, "error": "无法创建继续游戏索引目录"}
	var path := last_game_path()
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法写入继续游戏索引"}
	file.store_string(JSON.stringify(world))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return {"ok": false, "error": "继续游戏索引未能完整写入"}
	var backup_path := path + ".bak"
	if FileAccess.file_exists(path):
		var existing := _read_valid_current_save(path)
		if bool(existing.get("valid", false)):
			var backup_result := _prepare_backup(path, backup_path, "无法安全准备继续游戏索引备份")
			if not bool(backup_result.get("ok", false)): return {"ok": false, "error": str(backup_result.get("error", "无法完成继续游戏索引备份"))}
		else:
			var damaged_path := path + ".corrupt_%d" % Time.get_ticks_usec()
			var preserve_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(damaged_path))
			if preserve_error != OK: return {"ok": false, "error": "继续游戏索引损坏且无法隔离；为保护恢复备份，保存已停止"}
	var replace_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if replace_error != OK:
		_restore_main_from_backup_if_missing(path, backup_path)
		return {"ok": false, "error": "无法替换继续游戏索引"}
	return {"ok": true, "path": path}

static func load_world(city_id: String, mode: String, defer_recovery_confirmation: bool = false) -> Dictionary:
	var path := save_path(city_id, mode)
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"): return _recover_backup(city_id, mode, "主存档文件缺失", defer_recovery_confirmation)
		return {"ok": false, "status": "missing", "error": "没有找到这个开局的存档"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if FileAccess.file_exists(path + ".bak"): return _recover_backup(city_id, mode, "主存档无法读取", defer_recovery_confirmation)
		return {"ok": false, "status": "read_error", "error": "无法读取本地存档"}
	var source_text := file.get_as_text()
	file.close()
	var parsed: Variant = _parse_json_text(source_text)
	if not parsed is Dictionary:
		if FileAccess.file_exists(path + ".bak"): return _recover_backup(city_id, mode, "主存档内容损坏", defer_recovery_confirmation)
		return {"ok": false, "status": "corrupt", "error": "存档内容无效，原文件已保留"}
	var prepared := prepare_loaded_world(parsed)
	if not bool(prepared.get("ok", false)) and str(prepared.get("status", "")) == "corrupt" and FileAccess.file_exists(path + ".bak"):
		return _recover_backup(city_id, mode, "主存档结构校验失败：%s" % prepared.get("error", "内容损坏"), defer_recovery_confirmation)
	if bool(prepared.get("ok", false)): prepared["path"] = path
	return prepared

static func _recover_backup(city_id: String, mode: String, cause: String, defer_confirmation: bool = false) -> Dictionary:
	var backup_path := save_path(city_id, mode) + ".bak"
	var file := FileAccess.open(backup_path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "%s，且无法读取恢复备份" % cause}
	var source_text := file.get_as_text()
	file.close()
	var parsed: Variant = _parse_json_text(source_text)
	if not parsed is Dictionary: return {"ok": false, "error": "%s，最近备份也已损坏" % cause}
	var prepared := prepare_loaded_world(parsed)
	if not bool(prepared.get("ok", false)): return prepared
	if defer_confirmation:
		prepared["pendingRecoveryConfirmation"] = true
		prepared["recoveryPayload"] = parsed
		prepared["recoverySource"] = backup_path
		prepared["recoveryModifiedTime"] = FileAccess.get_modified_time(backup_path)
		prepared["recoveryCause"] = cause
		return prepared
	var copy_result := _preserve_recovery_copy(parsed)
	if not bool(copy_result.get("ok", false)):
		return {"ok": false, "status": "backup_failed", "error": "%s；备份有效，但无法写入独立恢复副本，已停止载入以保护数据：%s" % [cause, copy_result.get("error", "未知写入错误")], "recoverySource": backup_path}
	var recovery_message := "%s；已从最近恢复备份载入。" % cause
	recovery_message += "独立恢复副本：%s" % str(copy_result.get("path", ""))
	prepared["recovered"] = true
	prepared["recoveryCopySaved"] = true
	prepared["recoverySource"] = backup_path
	prepared["error"] = recovery_message
	return prepared

static func confirm_backup_recovery(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)) or not bool(result.get("pendingRecoveryConfirmation", false)):
		return {"ok": false, "status": "invalid", "error": "这个载入结果没有待确认的备份恢复"}
	var source_path := str(result.get("recoverySource", ""))
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {"ok": false, "status": "read_error", "error": "恢复来源已不存在；当前存档未载入"}
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null: return {"ok": false, "status": "read_error", "error": "无法重新读取恢复来源；当前存档未载入"}
	var source_text := file.get_as_text()
	file.close()
	var parsed: Variant = _parse_json_text(source_text)
	if not parsed is Dictionary or JSON.stringify(parsed) != JSON.stringify(result.get("recoveryPayload", {})):
		return {"ok": false, "status": "source_changed", "error": "恢复来源在确认前发生变化；请重新打开存档列表"}
	var copy_result := _preserve_recovery_copy(parsed)
	if not bool(copy_result.get("ok", false)):
		return {"ok": false, "status": "backup_failed", "error": "无法写入独立恢复副本；当前存档未载入：%s" % copy_result.get("error", "未知错误")}
	var confirmed := result.duplicate(true)
	confirmed.erase("pendingRecoveryConfirmation")
	confirmed.erase("recoveryPayload")
	confirmed["recovered"] = true
	confirmed["recoveryCopySaved"] = true
	confirmed["recoveryCopyPath"] = str(copy_result.get("path", ""))
	confirmed["error"] = "%s；已保留恢复副本：%s" % [str(result.get("recoveryCause", "已从备份恢复")), str(copy_result.get("path", ""))]
	confirmed["notice"] = confirmed["error"]
	return confirmed

static func recovery_source_label(result: Dictionary) -> String:
	var source := str(result.get("recoverySource", "备份文件"))
	var modified := int(result.get("recoveryModifiedTime", 0))
	var date_label := "时间未知"
	if modified > 0:
		var date := Time.get_datetime_dict_from_unix_time(modified)
		date_label = "%04d-%02d-%02d %02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute]
	return "%s · %s" % [source.get_file(), date_label]

static func _preserve_recovery_copy(data: Dictionary) -> Dictionary:
	var recovery_dir := root_path().path_join("recovery_backups")
	var absolute_dir := ProjectSettings.globalize_path(recovery_dir)
	var err := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK and not DirAccess.dir_exists_absolute(absolute_dir): return {"ok": false, "error": "无法创建恢复副本目录"}
	var stamp := "%s_%d" % [Time.get_datetime_string_from_system(false, true).replace(":", "-").replace("/", "-"), Time.get_ticks_usec()]
	var name := "%s_%s_recovered_%s.json" % [str(data.get("cityId", "city")), str(data.get("mode", "blank")), stamp]
	var path := recovery_dir.path_join(name)
	var copy := FileAccess.open(path, FileAccess.WRITE)
	if copy == null: return {"ok": false, "error": "无法创建恢复副本文件"}
	copy.store_string(JSON.stringify(data, "\t"))
	copy.flush()
	var write_error := copy.get_error()
	copy.close()
	if write_error != OK:
		return {"ok": false, "error": "恢复副本未能完整写入"}
	return {"ok": true, "path": path}

static func load_last_game(defer_recovery_confirmation: bool = false) -> Dictionary:
	var path := last_game_path()
	var candidates := [path, path + ".bak"]
	var errors: Array[String] = []
	for candidate in candidates:
		if not FileAccess.file_exists(candidate): continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			errors.append("%s 无法读取" % ("继续游戏索引" if candidate == path else "继续游戏索引备份"))
			continue
		var source_text := file.get_as_text()
		file.close()
		var parsed: Variant = _parse_json_text(source_text)
		if not parsed is Dictionary:
			errors.append("%s 内容损坏" % ("继续游戏索引" if candidate == path else "继续游戏索引备份"))
			continue
		var prepared := prepare_loaded_world(parsed)
		if not bool(prepared.get("ok", false)):
			if str(prepared.get("status", "")) == "unsupported":
				return prepared
			errors.append(str(prepared.get("error", "无法校验继续游戏索引")))
			continue
		prepared["recovered"] = candidate != path
		if candidate != path:
			if defer_recovery_confirmation:
				prepared["pendingRecoveryConfirmation"] = true
				prepared["recoveryPayload"] = parsed
				prepared["recoverySource"] = candidate
				prepared["recoveryModifiedTime"] = FileAccess.get_modified_time(candidate)
				prepared["recoveryCause"] = "继续游戏索引备份"
				return prepared
			var copy_result := _preserve_recovery_copy(parsed)
			if not bool(copy_result.get("ok", false)):
				return {"ok": false, "status": "backup_failed", "error": "继续游戏索引备份有效，但无法写入独立恢复副本；已停止载入以保护数据：%s" % copy_result.get("error", "未知错误")}
			prepared["recoveryCopySaved"] = true
			prepared["recoverySource"] = candidate
			prepared["notice"] = "继续游戏索引已从备份读取；独立恢复副本已保留：%s" % copy_result.get("path", "")
		return prepared
	if errors.is_empty(): return {"ok": false, "status": "missing", "error": "没有可继续的本地存档"}
	return {"ok": false, "status": "invalid", "error": "；".join(errors) + "。原文件已保留，请从存档列表恢复或导入 JSON。"}

static func prepare_loaded_world(parsed: Dictionary) -> Dictionary:
	var version := int(parsed.get("schemaVersion", -1))
	if version > WorldData.SAVE_VERSION:
		return {"ok": false, "status": "unsupported", "error": "存档来自更新版本，无法安全载入"}
	var source_error := _validate_source_shape(parsed)
	if not source_error.is_empty(): return {"ok": false, "status": "corrupt", "error": source_error}
	if version >= 8 and version < WorldData.SAVE_VERSION and not _preserve_version_original(parsed, version):
		return {"ok": false, "status": "backup_failed", "error": "无法创建版本 %d 原始存档备份，已停止迁移以保护原档" % version}
	var world: Dictionary = migrate(parsed) if version < WorldData.SAVE_VERSION else parsed.duplicate(true)
	var validation_error := _validate_world(world)
	if not validation_error.is_empty(): return {"ok": false, "status": "corrupt", "error": validation_error}
	return {"ok": true, "status": "ok", "world": world}

static func _validate_source_shape(data: Dictionary) -> String:
	var known_city_id := str(data.get("cityId", data.get("city", "")))
	if not known_city_id.is_empty() and WorldData.city(known_city_id).is_empty():
		return "存档引用了不支持的城市。"
	for key in ["stations", "routes", "trackLinks", "trackNodes", "trackEdges", "stationPlans"]:
		if data.has(key) and not data[key] is Array:
			return "存档结构损坏：%s 必须是列表。" % key
	if data.has("simulation") and not data.simulation is Dictionary:
		return "存档结构损坏：模拟状态无效。"
	var simulation: Dictionary = data.get("simulation", {})
	for key in ["trainTrips", "passengerBatches", "interruptedEvents", "statisticsBuckets", "journeyRecords"]:
		if simulation.has(key) and not simulation[key] is Array: return "存档结构损坏：模拟字段 %s 必须是列表。" % key
	for key in ["nextDepartureSeconds", "flowRemainders", "capacityLoads", "flowSamples"]:
		if simulation.has(key) and not simulation[key] is Dictionary: return "存档结构损坏：模拟字段 %s 必须是对象。" % key
	for key in ["trainTrips", "passengerBatches"]:
		for item in simulation.get(key, []):
			if not item is Dictionary: return "存档结构损坏：模拟字段 %s 含有无效记录。" % key
	for bucket in simulation.get("statisticsBuckets", []):
		if not bucket is Dictionary:
			return "存档结构损坏：15分钟统计桶格式无效。"
		var bucket_start: Variant = bucket.get("startMinute", -1)
		if not (bucket_start is int or bucket_start is float) or not is_finite(float(bucket_start)) or not is_equal_approx(float(bucket_start), roundf(float(bucket_start))):
			return "存档结构损坏：15分钟统计桶格式无效。"
		for key in ["attemptedByFlow", "completedByFlow", "tripMinutesByFlow"]:
			if bucket.has(key) and not bucket[key] is Dictionary: return "存档结构损坏：统计桶字段 %s 必须是对象。" % key
	for record in simulation.get("journeyRecords", []):
		if not record is Dictionary or str(record.get("id", "")).is_empty() or str(record.get("flowId", "")).is_empty():
			return "存档结构损坏：实际旅程记录缺少编号或需求引用。"
		for key in ["steps", "events"]:
			if record.has(key) and not record[key] is Array: return "存档结构损坏：实际旅程字段 %s 必须是列表。" % key
		for event in record.get("events", []):
			if not event is Dictionary: return "存档结构损坏：实际旅程事件格式无效。"
			var event_seconds: Variant = event.get("timeSeconds", -1)
			if not (event_seconds is int or event_seconds is float) or not is_finite(float(event_seconds)) or float(event_seconds) < 0.0: return "存档结构损坏：实际旅程事件格式无效。"
	if data.has("challengeMode") and str(data.challengeMode) not in ["free", "neighborhood"]:
		return "存档结构损坏：挑战模式无法识别。"
	if data.has("challengeState") and not data.challengeState is Dictionary:
		return "存档结构损坏：挑战进度格式无效。"
	if data.has("cityProgression") and not data.cityProgression is Dictionary:
		return "存档结构损坏：城市章节与事件进度格式无效。"
	if data.has("planningPhases") and not data.planningPhases is Array:
		return "存档结构损坏：分期建设计划格式无效。"
	for phase in data.get("planningPhases", []):
		if not phase is Dictionary or str(phase.get("id", "")).is_empty() or not phase.get("routeIds", []) is Array:
			return "存档结构损坏：分期建设计划包含无效记录。"
	for key in ["stations", "routes", "trackLinks", "trackNodes", "trackEdges"]:
		for item in data.get(key, []):
			if not item is Dictionary:
				return "存档结构损坏：%s 含有无效对象。" % key
	for station in data.get("stations", []):
		if str(station.get("id", "")).is_empty(): return "存档包含没有编号的车站。"
		var point: Variant = station.get("latlng", [])
		if not point is Array or point.size() < 2: return "存档包含资料不完整的车站坐标。"
		if not point[0] is int and not point[0] is float: return "存档包含非数值车站坐标。"
		if not point[1] is int and not point[1] is float: return "存档包含非数值车站坐标。"
		if not is_finite(float(point[0])) or not is_finite(float(point[1])) or absf(float(point[0])) > 90.0 or absf(float(point[1])) > 180.0:
			return "存档包含超出地理范围的车站坐标。"
	for node in data.get("trackNodes", []):
		if str(node.get("id", "")).is_empty(): return "存档包含没有编号的轨道节点。"
		var point: Variant = node.get("latlng", [])
		if not point is Array or point.size() < 2: return "存档包含资料不完整的轨道节点坐标。"
		if not point[0] is int and not point[0] is float or not point[1] is int and not point[1] is float:
			return "存档包含非数值轨道节点坐标。"
		if not is_finite(float(point[0])) or not is_finite(float(point[1])) or absf(float(point[0])) > 90.0 or absf(float(point[1])) > 180.0:
			return "存档包含超出地理范围的轨道节点坐标。"
	for route in data.get("routes", []):
		if route.has("stationOrder") and not route["stationOrder"] is Array: return "存档线路的停站顺序无效。"
		if route.has("directions") and not route["directions"] is Array: return "存档线路的方向信息无效。"
		if route.has("serviceSchedule") and not route.serviceSchedule is Dictionary: return "存档线路的分时班次配置无效。"
		if route.get("serviceSchedule", {}) is Dictionary:
			var schedule: Dictionary = route.get("serviceSchedule", {})
			if str(schedule.get("mode", "uniform")) not in ["uniform", "time_of_day"]: return "存档线路的班次模式无法识别。"
			for period in ["peakAM", "peakPM", "offPeak"]:
				if not schedule.has(period): continue
				var headway_value: Variant = schedule[period]
				if not (headway_value is int or headway_value is float) or not is_finite(float(headway_value)) or not is_equal_approx(float(headway_value), roundf(float(headway_value))) or int(headway_value) < 1 or int(headway_value) > 60:
					return "存档线路的分时班距必须在 1 至 60 分钟之间。"
		for direction in route.get("directions", []):
			if not direction is Dictionary: return "存档线路包含无效的运行方向。"
			if direction.has("stationIds") and not direction["stationIds"] is Array: return "存档线路的方向停站表无效。"
			if direction.has("edgePathsBySegment") and not direction["edgePathsBySegment"] is Array: return "存档线路的有向轨道路径无效。"
	return ""

static func migrate(data: Dictionary) -> Dictionary:
	var raw_simulation: Variant = data.get("simulation", {})
	if data.has("stationPlans") or data.has("trackNetwork") and (not raw_simulation is Dictionary or not raw_simulation.has("minute")):
		return _migrate_web_world(data)
	var source_version := int(data.get("schemaVersion", 0))
	var migrated := data.duplicate(true)
	migrated["schemaVersion"] = WorldData.SAVE_VERSION
	var history_result := _migrate_history(migrated.get("history", {"undo": [], "redo": []}), str(migrated.get("cityId", "shanghai")), source_version)
	if bool(history_result.get("ok", false)):
		migrated["history"] = history_result.get("history", {"undo": [], "redo": []})
	else:
		migrated["legacyHistory"] = migrated.get("history", {"undo": [], "redo": []})
		migrated["history"] = {"undo": [], "redo": []}
	migrated["fleetMode"] = migrated.get("fleetMode", "automatic")
	migrated["depots"] = migrated.get("depots", [])
	migrated["trackLinks"] = migrated.get("trackLinks", [])
	migrated["trackNodes"] = migrated.get("trackNodes", [])
	migrated["trackEdges"] = migrated.get("trackEdges", [])
	migrated["goalBoard"] = migrated.get("goalBoard", {"active": [], "completed": []})
	migrated["challengeMode"] = str(migrated.get("challengeMode", "free"))
	if migrated["challengeMode"] not in ["free", "neighborhood"]: migrated["challengeMode"] = "free"
	migrated["challengeState"] = migrated.get("challengeState", {"step": 0, "startedAt": -1, "completedAt": -1})
	var simulation: Dictionary = migrated.get("simulation", {})
	simulation["statisticsBuckets"] = simulation.get("statisticsBuckets", [])
	simulation["journeyRecords"] = simulation.get("journeyRecords", [])
	simulation["routeUtilizationBuckets"] = simulation.get("routeUtilizationBuckets", [])
	while simulation.statisticsBuckets.size() > 672: simulation.statisticsBuckets.pop_front()
	while simulation.journeyRecords.size() > 1000: simulation.journeyRecords.pop_front()
	while simulation.routeUtilizationBuckets.size() > 672: simulation.routeUtilizationBuckets.pop_front()
	for route in migrated.get("routes", []):
		var inherited_headway := clampi(int(route.get("headway", 3)), 1, 60)
		var profile: Dictionary = route.get("serviceSchedule", {})
		if profile.is_empty(): profile = {"mode": "uniform", "peakAM": inherited_headway, "peakPM": inherited_headway, "offPeak": inherited_headway}
		for period in ["peakAM", "peakPM", "offPeak"]: profile[period] = clampi(int(profile.get(period, inherited_headway)), 1, 60)
		if str(profile.get("mode", "uniform")) not in ["uniform", "time_of_day"]: profile["mode"] = "uniform"
		route["serviceSchedule"] = profile
	var old_minute := int(simulation.get("minute", 420))
	simulation["elapsedMinutes"] = int(simulation.get("elapsedMinutes", old_minute))
	simulation["minute"] = posmod(int(simulation.elapsedMinutes), 1440)
	if source_version < 13:
		simulation["elapsedSeconds"] = int(simulation.get("elapsedMinutes", old_minute)) * 60
		simulation["nextDepartureSeconds"] = {}
		simulation["trainTripsInitialized"] = true
	else:
		simulation["elapsedSeconds"] = int(simulation.get("elapsedSeconds", int(simulation.get("elapsedMinutes", old_minute)) * 60))
		simulation["nextDepartureSeconds"] = simulation.get("nextDepartureSeconds", {})
		simulation["trainTripsInitialized"] = bool(simulation.get("trainTripsInitialized", false))
	if source_version < 9:
		migrated["legacyMetrics"] = {"completedEstimate": int(simulation.get("completed", simulation.get("served", 0))), "attemptedEstimate": int(simulation.get("attempted", 0)), "note": "旧版按估算服务量记数，未作为新版真实到达统计导入。"}
		for key in ["completed", "attempted", "served", "boarded", "departed", "waiting", "inTransit", "abandoned", "unreachable", "interrupted"]: simulation[key] = 0
		simulation["tripMinutesTotal"] = 0.0
		simulation["passengerBatches"] = []
		simulation["flowRemainders"] = {}
		simulation["capacityLoads"] = {}
		simulation["capacitySlot"] = -1
		for key in ["completedByFlow", "attemptedByFlow", "tripMinutesByFlow", "waitingByRoute"]: simulation[key] = {}
		simulation["crowdingSamples"] = []
	else:
		simulation["passengerBatches"] = simulation.get("passengerBatches", [])
		simulation["flowRemainders"] = simulation.get("flowRemainders", {})
		simulation["capacityLoads"] = simulation.get("capacityLoads", {})
		simulation["capacitySlot"] = int(simulation.get("capacitySlot", -1))
	if source_version < 11:
		# Version 11 keys loads by train departure and service day. Old transient
		# occupancy cannot be translated safely, while passenger batches remain.
		simulation["capacityLoads"] = {}
		simulation["capacitySlot"] = -1
	simulation["interrupted"] = int(simulation.get("interrupted", 0))
	simulation["flowSamples"] = simulation.get("flowSamples", {})
	simulation["trainTrips"] = simulation.get("trainTrips", [])
	simulation["interruptedEvents"] = simulation.get("interruptedEvents", [])
	simulation["paused"] = true
	simulation["speed"] = int(simulation.get("speed", 1))
	migrated["simulation"] = simulation
	var city_id := str(migrated.get("cityId", "shanghai"))
	var phases: Array = migrated.get("planningPhases", [])
	if phases.is_empty():
		phases = [{"id":"phase_1", "name":"一期建设", "createdAt":int(simulation.get("elapsedMinutes", 420)), "routeIds":[], "stationIds":[], "edgeIds":[], "flowIds":[]}]
	var phase_ids: Dictionary = {}
	for phase in phases:
		phase["routeIds"] = []
		phase["stationIds"] = []
		phase["edgeIds"] = []
		phase["flowIds"] = phase.get("flowIds", []) if phase.get("flowIds", []) is Array else []
		phase_ids[str(phase.get("id", ""))] = phase
	for station in migrated.get("stations", []):
		var station_phase_id := str(station.get("planningPhaseId", phases[0].get("id", "phase_1")))
		if not phase_ids.has(station_phase_id): station_phase_id = str(phases[0].get("id", "phase_1"))
		station["planningPhaseId"] = station_phase_id
		var station_phase: Dictionary = phase_ids[station_phase_id]
		if not station_phase.stationIds.has(str(station.get("id", ""))): station_phase.stationIds.append(str(station.get("id", "")))
	for edge_key in ["trackLinks", "trackEdges"]:
		for edge in migrated.get(edge_key, []):
			var edge_phase_id := str(edge.get("planningPhaseId", phases[0].get("id", "phase_1")))
			if not phase_ids.has(edge_phase_id): edge_phase_id = str(phases[0].get("id", "phase_1"))
			edge["planningPhaseId"] = edge_phase_id
			var edge_phase: Dictionary = phase_ids[edge_phase_id]
			if not edge_phase.edgeIds.has(str(edge.get("id", ""))): edge_phase.edgeIds.append(str(edge.get("id", "")))
	for route in migrated.get("routes", []):
		var phase_id := str(route.get("planningPhaseId", phases[0].get("id", "phase_1")))
		if not phase_ids.has(phase_id):
			phase_id = str(phases[0].get("id", "phase_1"))
			route["planningPhaseId"] = phase_id
		var phase: Dictionary = phase_ids[phase_id]
		if not phase.routeIds.has(str(route.get("id", ""))): phase.routeIds.append(str(route.get("id", "")))
	migrated["planningPhases"] = phases
	if not phase_ids.has(str(migrated.get("currentPlanningPhaseId", ""))):
		migrated["currentPlanningPhaseId"] = str(phases.back().get("id", "phase_1"))
	if source_version < 15:
		migrated["cityProgression"] = CityProgressionScript.create_state(city_id)
		var old_onboarding: Dictionary = migrated.get("onboarding", {})
		if not bool(old_onboarding.get("active", false)):
			CityProgressionScript.start(migrated, int(simulation.get("elapsedMinutes", 420)))
	else:
		migrated["cityProgression"] = migrated.get("cityProgression", CityProgressionScript.create_state(city_id))
	TrackNetwork.ensure_station_nodes(migrated)
	WorldData.load_assets()
	var ref_lat := float(WorldData.city(str(migrated.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0])
	var route_path_needs_review := _pin_route_paths(migrated, ref_lat)
	if source_version < WorldData.SAVE_VERSION:
		simulation["trainTrips"] = _restore_train_trips_seconds(migrated, ref_lat) if source_version < 13 else simulation.get("trainTrips", [])
		if source_version < 13:
			_migrate_passenger_timing(simulation)
			simulation["capacityLoads"] = {}
			simulation["nextDepartureSeconds"] = _initial_dispatch_schedule(migrated, int(simulation.get("elapsedSeconds", 0)), ref_lat)
			simulation["trainTripsInitialized"] = true
		for route in migrated.get("routes", []):
			if bool(route.get("open", false)) and not route.has("serviceStartMinute"): route["serviceStartMinute"] = int(simulation.get("elapsedMinutes", 420))
	if source_version < WorldData.SAVE_VERSION:
		migrated["migrationNotice"] = "存档已升级为 15：保留规划、时钟、乘客和完成量，并开始城市章节与确定日程事件。章节地点和变化客流均为游戏设定；原始存档已单独备份。"
	if route_path_needs_review:
		if not migrated.has("migrationNotice"): migrated["migrationNotice"] = "线路走向资料需要整理。"
		migrated["migrationNotice"] += " 部分旧线路无法解析连续轨道，已标记为待整理，不会自动改走其他区间。"
	return migrated

static func _migrate_history(raw_history: Variant, city_id: String = "shanghai", source_version: int = 0) -> Dictionary:
	if not raw_history is Dictionary: return {"ok": false}
	var converted := {"undo": [], "redo": []}
	for direction in ["undo", "redo"]:
		var entries: Variant = raw_history.get(direction, [])
		if not entries is Array: return {"ok": false}
		for raw_entry in entries:
			if not raw_entry is Dictionary: return {"ok": false}
			if raw_entry.has("diff"):
				if source_version < 12 or not raw_entry.get("diff") is Dictionary: return {"ok": false}
				var diff_entry: Dictionary = raw_entry.duplicate(true)
				var fields: Variant = diff_entry.get("diff", {}).get("fields", {})
				if not fields is Dictionary: return {"ok": false}
				for key in fields:
					var change: Variant = fields[key]
					if not change is Dictionary: return {"ok": false}
					var change_type := str(change.get("type", ""))
					if change_type == "identified_array":
						if not change.get("beforeOrder", []) is Array or not change.get("afterOrder", []) is Array or not change.get("items", {}) is Dictionary: return {"ok": false}
					elif change_type != "value": return {"ok": false}
				converted[direction].append(diff_entry)
				continue
			if not raw_entry.has("snapshot") or not raw_entry.get("snapshot") is Dictionary: return {"ok": false}
			var entry: Dictionary = raw_entry.duplicate(true)
			var snapshot: Dictionary = entry.get("snapshot", {}).duplicate(true)
			if not snapshot.get("stations", []) is Array or not snapshot.get("routes", []) is Array or not snapshot.get("trackLinks", []) is Array:
				return {"ok": false}
			snapshot["trackNodes"] = snapshot.get("trackNodes", [])
			snapshot["trackEdges"] = snapshot.get("trackEdges", [])
			var snapshot_world := {"stations": snapshot.get("stations", []), "routes": snapshot.get("routes", []), "trackLinks": snapshot.get("trackLinks", []), "trackNodes": snapshot.get("trackNodes", []), "trackEdges": snapshot.get("trackEdges", [])}
			TrackNetwork.ensure_station_nodes(snapshot_world)
			WorldData.load_assets()
			var ref_lat := float(WorldData.city(city_id).get("center", [31.23, 121.47])[0])
			_pin_route_paths(snapshot_world, ref_lat)
			snapshot["trackNodes"] = snapshot_world.get("trackNodes", [])
			snapshot["routes"] = snapshot_world.get("routes", [])
			for key in ["depots", "fleetMode"]:
				if not snapshot.has(key): snapshot[key] = [] if key == "depots" else "automatic"
			entry["snapshot"] = snapshot
			converted[direction].append(entry)
	return {"ok": true, "history": converted}

static func _pin_route_paths(state: Dictionary, ref_lat: float) -> bool:
	var needs_review := false
	for route in state.get("routes", []):
		if not bool(route.get("networkBased", false)): continue
		for direction in route.get("directions", []):
			if not direction is Dictionary or not direction.get("edgePathsBySegment", []).is_empty(): continue
			var station_ids: Array = direction.get("stationIds", [])
			var previous_paths: Array = direction.get("edgeIdsBySegment", [])
			var edge_paths: Array = []
			for index in range(station_ids.size() - 1):
				var allowed: Array = previous_paths[index] if index < previous_paths.size() and previous_paths[index] is Array else []
				var path := TrackNetwork.shortest_station_path(str(station_ids[index]), str(station_ids[index + 1]), state, ref_lat, allowed)
				var locked: Array[Dictionary] = []
				if bool(path.get("valid", false)):
					for connection in path.get("edges", []):
						var edge: Dictionary = connection.get("edge", {})
						if bool(edge.get("platform", false)): continue
						locked.append({"id": str(edge.get("id", "")), "forward": bool(connection.get("forward", true))})
				else:
					locked.append({"id": "__path_unavailable__", "forward": true})
					needs_review = true
				edge_paths.append(locked)
			direction["edgePathsBySegment"] = edge_paths
			direction.erase("edgeIdsBySegment")
	return needs_review

static func _restore_train_trips_seconds(state: Dictionary, ref_lat: float) -> Array:
	var sim: Dictionary = state.get("simulation", {})
	var now := int(sim.get("elapsedSeconds", int(sim.get("elapsedMinutes", sim.get("minute", 420))) * 60))
	var trips: Array = []
	for raw_trip in sim.get("trainTrips", []):
		if not raw_trip is Dictionary: continue
		var old_trip: Dictionary = raw_trip
		var route_id := str(old_trip.get("routeId", ""))
		var direction_id := str(old_trip.get("directionId", ""))
		var route := WorldData.find_route(state, route_id)
		if route.is_empty() or not bool(route.get("open", false)): continue
		var path: Dictionary = RoutePath.for_route(route, state, ref_lat)
		var direction: Dictionary = {}
		for candidate in path.get("directions", []):
			if str(candidate.get("id", "")) == direction_id: direction = candidate; break
		var age_seconds := float(old_trip.get("elapsedSeconds", float(old_trip.get("elapsedMinutes", 0.0)) * 60.0))
		if direction.is_empty() or age_seconds < 0.0 or age_seconds >= float(direction.get("travelMinutes", 0.0)) * 60.0: continue
		var departure_seconds := now - roundi(age_seconds)
		var trip := SimulationEngine._make_train_trip_seconds(route_id, direction, departure_seconds)
		trip["capacity"] = int(WorldData.vehicle(str(route.get("vehicleId", "B-6"))).get("capacity", 1800))
		trip["edgeSignatures"] = SimulationEngine._direction_edge_signatures(state, direction)
		trip["elapsedSeconds"] = age_seconds
		trip["elapsedMinutes"] = age_seconds / 60.0
		var age_minutes := age_seconds / 60.0
		var found_phase := false
		var timetable: Array = trip.get("stationTimetable", [])
		var segments: Array = direction.get("segments", [])
		for index in range(segments.size()):
			var from_stop: Dictionary = timetable[index]
			var to_stop: Dictionary = timetable[index + 1]
			var depart_offset := float(from_stop.get("departureOffsetMinutes", 0.0))
			var arrive_offset := float(to_stop.get("arrivalOffsetMinutes", depart_offset))
			var depart_next_offset := float(to_stop.get("departureOffsetMinutes", arrive_offset))
			if age_minutes >= depart_offset and age_minutes < arrive_offset:
				trip["phase"] = "moving"; trip["currentStopIndex"] = index; trip["nextStopIndex"] = index + 1
				trip["nextEventSeconds"] = float(departure_seconds) + arrive_offset * 60.0
				found_phase = true; break
			if age_minutes >= arrive_offset and age_minutes < depart_next_offset:
				trip["phase"] = "dwell"; trip["currentStopIndex"] = index + 1; trip["nextStopIndex"] = -1
				trip["nextEventSeconds"] = float(departure_seconds) + depart_next_offset * 60.0
				found_phase = true; break
		if found_phase: trips.append(trip)
	return trips

static func _initial_dispatch_schedule(state: Dictionary, now_seconds: int, ref_lat: float) -> Dictionary:
	var schedules: Dictionary = {}
	for route in state.get("routes", []):
		if not bool(route.get("open", false)): continue
		var path: Dictionary = RoutePath.for_route(route, state, ref_lat)
		if not bool(path.get("valid", false)): continue
		var next_seconds := now_seconds + maxi(1, int(route.get("headway", 3))) * 60
		for direction in path.get("directions", []):
			var key := "%s|%s" % [str(route.get("id", "")), str(direction.get("id", "forward"))]
			schedules[key] = next_seconds
	return schedules

static func _migrate_passenger_timing(simulation: Dictionary) -> void:
	var now_seconds := int(simulation.get("elapsedSeconds", int(simulation.get("elapsedMinutes", 420)) * 60))
	var trips_by_id: Dictionary = {}
	for trip in simulation.get("trainTrips", []):
		trips_by_id[str(trip.get("id", ""))] = trip
	var batches: Array = simulation.get("passengerBatches", [])
	var replan_count := 0
	for batch in batches:
		if not batch is Dictionary: continue
		var status := str(batch.get("status", ""))
		if status == "riding":
			var trip_id := str(batch.get("trainTripId", ""))
			if trips_by_id.has(trip_id):
				var trip: Dictionary = trips_by_id[trip_id]
				var stop_index := int(trip.get("currentStopIndex", 0))
				var records: Array = trip.get("stationTimetable", [])
				if str(trip.get("phase", "")) == "moving": stop_index = maxi(0, stop_index)
				if stop_index >= 0 and stop_index < records.size():
					batch["lastValidStationId"] = str(records[stop_index].get("stationId", batch.get("lastValidStationId", "")))
			batch["status"] = "replan"
			batch["trainTripId"] = ""
			batch["capacityLoadKeys"] = []
			batch["plannedRevision"] = -1
			batch["nextEventSeconds"] = now_seconds
			replan_count += int(batch.get("count", 0))
		elif status == "waiting":
			batch["waitStartedSeconds"] = float(now_seconds - int(batch.get("waitedMinutes", 0)) * 60)
			batch["nextEventSeconds"] = -1.0
		elif status in ["walking", "transferring"]:
			batch["nextEventSeconds"] = float(now_seconds) + float(batch.get("remainingMinutes", 0.0)) * 60.0
		elif status in ["disrupted", "interrupted"]:
			batch["status"] = "interrupted"
			batch["nextEventSeconds"] = -1.0
	simulation["passengerBatches"] = batches
	simulation["legacyPassengersReplanned"] = replan_count

static func _preserve_v8_original(data: Dictionary) -> bool:
	var backup_dir := root_path().path_join("migration_backups")
	var absolute_dir := ProjectSettings.globalize_path(backup_dir)
	var err := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK and not DirAccess.dir_exists_absolute(absolute_dir): return false
	var filename := "%s_%s_v8-original.json" % [str(data.get("cityId", "city")), str(data.get("mode", "blank"))]
	var path := backup_dir.path_join(filename)
	if FileAccess.file_exists(path): return true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error == OK

static func _preserve_version_original(data: Dictionary, version: int) -> bool:
	var backup_dir := root_path().path_join("migration_backups")
	var absolute_dir := ProjectSettings.globalize_path(backup_dir)
	var err := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK and not DirAccess.dir_exists_absolute(absolute_dir): return false
	var digest := JSON.stringify(data).sha256_text().substr(0, 12)
	var filename := "%s_%s_v%d-%s-original.json" % [str(data.get("cityId", "city")), str(data.get("mode", "blank")), version, digest]
	var path := backup_dir.path_join(filename)
	if FileAccess.file_exists(path): return true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error == OK

static func _migrate_web_world(source: Dictionary) -> Dictionary:
	var city_id := str(source.get("cityId", "shanghai"))
	var mode := str(source.get("mode", "blank"))
	var city := WorldData.city(city_id)
	var raw_routes: Array = source.get("routes", [])
	var raw_stations: Array = source.get("stations", [])
	var plans: Dictionary = source.get("stationPlans", {})
	var station_route_ids: Dictionary = {}
	var routes: Array[Dictionary] = []
	var links: Array[Dictionary] = []
	var pair_to_link: Dictionary = {}
	for raw_route in raw_routes:
		if not raw_route is Dictionary: continue
		var route: Dictionary = raw_route.duplicate(true)
		var vehicle_id := str(route.get("vehicleId", route.get("vehicleProfileId", "B-6")))
		if WorldData.vehicle(vehicle_id).is_empty(): vehicle_id = "B-6"
		route["vehicleId"] = vehicle_id
		route["headway"] = int(route.get("headway", route.get("headwayMinutes", 3)))
		var inherited_headway := clampi(int(route["headway"]), 1, 60)
		route["serviceSchedule"] = {"mode": "uniform", "peakAM": inherited_headway, "peakPM": inherited_headway, "offPeak": inherited_headway}
		if not route.has("open"):
			route["open"] = str(route.get("status", "")) == "operating"
		route["schematic"] = true
		var directions: Array = route.get("directions", [])
		if directions.is_empty() and route.get("stationIds", []) is Array:
			directions = [{"id": "legacy", "stationIds": route.get("stationIds", [])}]
		var station_order: Array[String] = []
		for direction in directions:
			if not direction is Dictionary: continue
			for raw_id in direction.get("stationIds", []):
				var station_id := str(raw_id)
				if station_id.is_empty(): continue
				if not station_order.has(station_id): station_order.append(station_id)
				if not station_route_ids.has(station_id): station_route_ids[station_id] = []
				if not station_route_ids[station_id].has(str(route.get("id", ""))): station_route_ids[station_id].append(str(route.get("id", "")))
		route["stationOrder"] = station_order
		route["directions"] = directions
		routes.append(route)
	for route in routes:
		var route_id := str(route.get("id", ""))
		for direction in route.get("directions", []):
			if not direction is Dictionary: continue
			var ids: Array = direction.get("stationIds", [])
			for index in range(ids.size() - 1):
				var a_id := str(ids[index]); var b_id := str(ids[index + 1])
				if a_id == b_id or _find_station(raw_stations, a_id).is_empty() or _find_station(raw_stations, b_id).is_empty(): continue
				var pair_key := "%s|%s" % [a_id, b_id] if a_id < b_id else "%s|%s" % [b_id, a_id]
				if pair_to_link.has(pair_key):
					var shared_link: Dictionary = links[int(pair_to_link[pair_key])]
					if not shared_link.routeIds.has(route_id): shared_link.routeIds.append(route_id)
				else:
					var link := {"id": "web_%s_%d" % [route_id, links.size()], "a": {"stationId": a_id, "side": "end"}, "b": {"stationId": b_id, "side": "start"}, "routeIds": [route_id], "schematic": true, "migrationNote": "由网页版本站序转换；站间线位为示意"}
					pair_to_link[pair_key] = links.size()
					links.append(link)
	var stations: Array[Dictionary] = []
	for raw_station in raw_stations:
		if not raw_station is Dictionary: continue
		var station: Dictionary = raw_station.duplicate(true)
		var station_id := str(station.get("id", ""))
		var plan: Dictionary = plans.get(station_id, {})
		var halls: Array = plan.get("halls", [])
		var hall: Dictionary = halls[0] if not halls.is_empty() and halls[0] is Dictionary else plan.get("hall", {})
		var station_routes: Array = station_route_ids.get(station_id, station.get("routeIds", []))
		var vehicle_id := str(hall.get("profileId", plan.get("profileId", "")))
		if vehicle_id.is_empty() and not station_routes.is_empty():
			var route := _find_route(routes, str(station_routes[0]))
			vehicle_id = str(route.get("vehicleId", "B-6"))
		if WorldData.vehicle(vehicle_id).is_empty(): vehicle_id = "B-6"
		var profile := WorldData.vehicle(vehicle_id)
		station["heading"] = float(station.get("heading", station.get("orientation", hall.get("headingDeg", 90.0))))
		station["lengthM"] = float(hall.get("lengthM", station.get("lengthM", profile.get("trainLengthM", 118.788))))
		station["widthM"] = float(hall.get("widthM", station.get("widthM", 20.0)))
		station["vehicleId"] = vehicle_id
		station["routeIds"] = station_routes.duplicate()
		station["schematic"] = true
		stations.append(station)
	var old_sim: Dictionary = source.get("simulation", {})
	var stats: Dictionary = source.get("simStats", {})
	var minute := int(old_sim.get("minute", source.get("timeMinutes", 420)))
	var simulation := {"minute": posmod(minute, 1440), "elapsedMinutes": minute, "elapsedSeconds": minute * 60, "nextDepartureSeconds": {}, "trainTripsInitialized": false, "speed": 1, "paused": true, "seed": int(source.get("seed", source.get("randomSeed", 45281))), "completed": 0, "attempted": 0, "served": 0, "boarded": 0, "departed": 0, "waiting": 0, "inTransit": 0, "abandoned": 0, "unreachable": 0, "interrupted": 0, "tripMinutesTotal": 0.0, "peakCrowding": 0.0, "passengerBatches": [], "flowRemainders": {}, "capacityLoads": {}, "capacitySlot": -1, "trainTrips": [], "completedByFlow": {}, "attemptedByFlow": {}, "tripMinutesByFlow": {}, "waitingByRoute": {}, "crowdingSamples": [], "flowSamples": {}, "statisticsBuckets": [], "journeyRecords": [], "routeUtilizationBuckets": []}
	var tutorial: Dictionary = source.get("tutorial", {})
	var migrated := {"schemaVersion": WorldData.SAVE_VERSION, "cityId": city_id, "cityName": str(source.get("cityName", city.get("name", city_id))), "mode": mode, "dataVersion": str(source.get("mobilityVersion", source.get("dataVersion", "web-v7"))), "stations": stations, "routes": routes, "trackLinks": links, "trackNodes": [], "trackEdges": [], "depots": source.get("depots", []), "goalBoard": {"active": [], "completed": []}, "challengeMode": "free", "challengeState": {"step": 0, "startedAt": -1, "completedAt": -1}, "simulation": simulation, "legacyMetrics": {"completedEstimate": int(stats.get("served", 0)), "attemptedEstimate": int(stats.get("requested", stats.get("served", 0))), "note": "网页版本旧服务量为模型估算；新版完成量从真实到达重新统计。"}, "fleetMode": "automatic", "tutorialStep": mini(4, int(tutorial.get("step", 0))), "tutorialDone": bool(tutorial.get("completed", tutorial.get("skipped", false))), "randomSeed": int(source.get("seed", source.get("randomSeed", 45281))), "revision": int(source.get("networkRevision", 1)), "view": source.get("view", {"center": city.get("center", [0, 0]), "zoom": 12}), "history": {"undo": [], "redo": []}, "source": {"attribution": "© OpenStreetMap contributors", "license": "ODbL 1.0", "snapshot": str(city.get("sources", {}).get("snapshot", "2026-10-05"))}, "migrationNotice": "已导入网页存档并升级为版本16。车站站体按列车长度转换；原区间线位作为站序示意，复核后可逐段重建。旧版客流保留为历史估算，新版统计和实际旅程记录从导入后重新累积。网页原始 JSON 未修改，可留作恢复备份。"}
	migrated["planningPhases"] = [{"id":"phase_1", "name":"一期建设", "createdAt":minute, "routeIds":[], "stationIds":[], "edgeIds":[], "flowIds":[]}]
	migrated["currentPlanningPhaseId"] = "phase_1"
	for station in stations:
		station["planningPhaseId"] = "phase_1"
		migrated.planningPhases[0].stationIds.append(str(station.get("id", "")))
	for edge in links:
		edge["planningPhaseId"] = "phase_1"
		migrated.planningPhases[0].edgeIds.append(str(edge.get("id", "")))
	for route in routes:
		route["planningPhaseId"] = "phase_1"
		migrated["planningPhases"][0]["routeIds"].append(str(route.get("id", "")))
	migrated["cityProgression"] = CityProgressionScript.create_state(city_id)
	if bool(migrated.get("tutorialDone", false)) or mode == "expand":
		CityProgressionScript.start(migrated, minute)
	migrated["migrationNotice"] = "已导入网页存档并升级为版本15。旧线路的站间线位仍是示意；新城市章节和确定日程事件从导入后开始。章节地点与客流变化为游戏设定，网页原始 JSON 未修改，可留作恢复备份。"
	TrackNetwork.ensure_station_nodes(migrated)
	var ref_lat := float(city.get("center", [31.23, 121.47])[0])
	_pin_route_paths(migrated, ref_lat)
	return migrated

static func _find_station(stations: Array, station_id: String) -> Dictionary:
	for station in stations:
		if station is Dictionary and str(station.get("id", "")) == station_id: return station
	return {}

static func _find_route(routes: Array[Dictionary], route_id: String) -> Dictionary:
	for route in routes:
		if str(route.get("id", "")) == route_id: return route
	return {}

static func save_exists(city_id: String, mode: String) -> bool:
	var path := save_path(city_id, mode)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")

static func manual_saves_dir() -> String:
	return root_path().path_join("manual_saves")

static func save_manual_snapshot(world: Dictionary, requested_name: String) -> Dictionary:
	var validation_error := _validate_world(world)
	if not validation_error.is_empty(): return {"ok": false, "error": validation_error}
	var label := _sanitize_manual_name(requested_name)
	if label.is_empty(): return {"ok": false, "error": "请先输入手动存档名称。"}
	var directory := ProjectSettings.globalize_path(manual_saves_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK and not DirAccess.dir_exists_absolute(directory):
		return {"ok": false, "error": "无法创建手动存档目录。"}
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace("/", "-").replace("T", "_")
	var city_id := str(world.get("cityId", "city"))
	var mode := str(world.get("mode", "blank"))
	var filename := "%s_%s_%s_%d_%s.json" % [city_id, mode, stamp, Time.get_ticks_usec(), label]
	var path := manual_saves_dir().path_join(filename)
	var snapshot := world.duplicate(true)
	snapshot["_manualSave"] = {"name": label, "savedAt": Time.get_datetime_string_from_system(false, true)}
	var result := _write_export(path, snapshot)
	if bool(result.get("ok", false)):
		result["name"] = label
		result["cityName"] = str(world.get("cityName", city_id))
		result["mode"] = mode
	return result

static func _sanitize_manual_name(requested_name: String) -> String:
	var label := requested_name.strip_edges().left(48)
	for forbidden in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		label = label.replace(str(forbidden), "_")
	return label.replace("..", "_").strip_edges()

static func _replace_manual_snapshot_atomic(path: String, snapshot: Dictionary) -> Dictionary:
	var temp_path := path + ".tmp"
	var backup_path := path + ".replace-%d.bak" % Time.get_ticks_usec()
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法写入手动存档临时文件。"}
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return {"ok": false, "error": "手动存档未能完整写入。"}
	var hold_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path))
	if hold_error != OK: return {"ok": false, "error": "无法安全暂存原手动存档。"}
	var replace_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if replace_error != OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(path))
		return {"ok": false, "error": "手动存档替换失败，原文件已恢复。"}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	return {"ok": true, "path": path}

static func rename_manual_snapshot(path: String, requested_name: String) -> Dictionary:
	var expected_dir := ProjectSettings.globalize_path(manual_saves_dir()).simplify_path()
	var normalized_path := ProjectSettings.globalize_path(path).simplify_path()
	if normalized_path.get_base_dir() != expected_dir: return {"ok": false, "error": "手动存档位置无效。"}
	var label := _sanitize_manual_name(requested_name)
	if label.is_empty(): return {"ok": false, "error": "请先输入手动存档名称。"}
	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "无法读取这份手动存档。"}
	var parsed: Variant = _parse_json_text(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("_manualSave", {}) is Dictionary: return {"ok": false, "error": "手动存档内容损坏，未修改原文件。"}
	var snapshot: Dictionary = parsed
	var metadata: Dictionary = snapshot.get("_manualSave", {})
	var checked := snapshot.duplicate(true)
	checked.erase("_manualSave")
	var valid := prepare_loaded_world(checked)
	if not bool(valid.get("ok", false)): return {"ok": false, "error": str(valid.get("error", "手动存档校验失败"))}
	metadata["name"] = label
	metadata["renamedAt"] = Time.get_datetime_string_from_system(false, true)
	snapshot["_manualSave"] = metadata
	var replaced := _replace_manual_snapshot_atomic(normalized_path, snapshot)
	if bool(replaced.get("ok", false)): replaced["name"] = label
	return replaced

static func overwrite_manual_snapshot(path: String, world: Dictionary, requested_name: String) -> Dictionary:
	var expected_dir := ProjectSettings.globalize_path(manual_saves_dir()).simplify_path()
	var normalized_path := ProjectSettings.globalize_path(path).simplify_path()
	if normalized_path.get_base_dir() != expected_dir: return {"ok": false, "error": "手动存档位置无效。"}
	var validation_error := _validate_world(world)
	if not validation_error.is_empty(): return {"ok": false, "error": validation_error}
	var label := _sanitize_manual_name(requested_name)
	if label.is_empty(): return {"ok": false, "error": "请先输入手动存档名称。"}
	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "无法读取原手动存档。"}
	var old: Variant = _parse_json_text(file.get_as_text())
	file.close()
	if not old is Dictionary or str(old.get("cityId", "")) != str(world.get("cityId", "")) or str(old.get("mode", "")) != str(world.get("mode", "")):
		return {"ok": false, "error": "只能覆盖相同城市与开局的命名存档。"}
	var snapshot := world.duplicate(true)
	snapshot["_manualSave"] = {"name": label, "savedAt": Time.get_datetime_string_from_system(false, true)}
	var replaced := _replace_manual_snapshot_atomic(normalized_path, snapshot)
	if bool(replaced.get("ok", false)): replaced["name"] = label
	return replaced

static func list_manual_snapshots() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var directory := ProjectSettings.globalize_path(manual_saves_dir())
	var dir := DirAccess.open(directory)
	if dir == null: return entries
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.to_lower().ends_with(".json"):
			var path := manual_saves_dir().path_join(filename)
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var parsed: Variant = _parse_json_text(file.get_as_text())
				file.close()
				var metadata_value: Variant = parsed.get("_manualSave", {}) if parsed is Dictionary else {}
				var metadata: Dictionary = metadata_value if metadata_value is Dictionary else {}
				var city_id := str(parsed.get("cityId", "")) if parsed is Dictionary else ""
				var city := WorldData.city(city_id)
				var valid := false
				var error_text := "手动存档内容损坏。"
				if parsed is Dictionary and metadata_value is Dictionary and not city_id.is_empty():
					var candidate: Dictionary = parsed.duplicate(true)
					candidate.erase("_manualSave")
					var checked := prepare_loaded_world(candidate)
					valid = bool(checked.get("ok", false))
					error_text = "" if valid else str(checked.get("error", error_text))
				entries.append({
					"path": path,
					"name": str(metadata.get("name", filename.get_basename())),
					"savedAt": str(metadata.get("savedAt", "")),
					"cityId": city_id,
					"cityName": str(parsed.get("cityName", city.get("name", city_id))) if parsed is Dictionary else "未知城市",
					"mode": str(parsed.get("mode", "blank")) if parsed is Dictionary else "blank",
					"elapsedMinutes": int(parsed.get("simulation", {}).get("elapsedMinutes", 0)) if parsed is Dictionary else 0,
					"stationCount": parsed.get("stations", []).size() if parsed is Dictionary else 0,
					"routeCount": parsed.get("routes", []).size() if parsed is Dictionary else 0,
					"sizeBytes": FileAccess.get_file_as_bytes(path).size(),
					"valid": valid,
					"error": error_text
				})
		filename = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("savedAt", "")) > str(b.get("savedAt", "")))
	return entries

static func manual_storage_bytes() -> int:
	var total := 0
	for entry in list_manual_snapshots(): total += int(entry.get("sizeBytes", 0))
	return total

static func load_manual_snapshot(path: String) -> Dictionary:
	var expected_dir := ProjectSettings.globalize_path(manual_saves_dir()).simplify_path()
	var normalized_path := ProjectSettings.globalize_path(path).simplify_path()
	if normalized_path.get_base_dir() != expected_dir:
		return {"ok": false, "status": "invalid_path", "error": "手动存档位置无效。"}
	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null: return {"ok": false, "status": "read_error", "error": "无法读取这份手动存档。"}
	var parsed: Variant = _parse_json_text(file.get_as_text())
	file.close()
	if not parsed is Dictionary: return {"ok": false, "status": "corrupt", "error": "手动存档内容损坏；文件未修改。"}
	var metadata_value: Variant = parsed.get("_manualSave", {})
	if not metadata_value is Dictionary:
		return {"ok": false, "status": "corrupt", "error": "手动存档名称信息损坏；文件未修改。"}
	var metadata: Dictionary = metadata_value
	parsed.erase("_manualSave")
	var prepared := prepare_loaded_world(parsed)
	if bool(prepared.get("ok", false)):
		var restored_world: Dictionary = prepared.get("world", {})
		if restored_world.get("simulation", {}) is Dictionary:
			restored_world.simulation.paused = true
			prepared["world"] = restored_world
		prepared["manualSaveName"] = str(metadata.get("name", normalized_path.get_file().get_basename()))
		prepared["manualSavePath"] = normalized_path
	return prepared

static func delete_manual_snapshot(path: String) -> Dictionary:
	var expected_dir := ProjectSettings.globalize_path(manual_saves_dir()).simplify_path()
	var normalized_path := ProjectSettings.globalize_path(path).simplify_path()
	if normalized_path.get_base_dir() != expected_dir:
		return {"ok": false, "error": "手动存档位置无效。"}
	if not FileAccess.file_exists(normalized_path): return {"ok": false, "error": "手动存档已经不存在。"}
	var remove_error := DirAccess.remove_absolute(normalized_path)
	if remove_error != OK: return {"ok": false, "error": "无法删除这份手动存档。"}
	return {"ok": true}

static func saves_root_path() -> String:
	return ProjectSettings.globalize_path(save_dir())

static func export_world(world: Dictionary, on_result: Callable = Callable()) -> void:
	var dialog := FileDialog.new()
	_apply_app_theme(dialog)
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json ; Metro Atlas 保存文件")
	dialog.current_file = "%s_%s.json" % [world.get("cityId", "city"), world.get("mode", "blank")]
	dialog.file_selected.connect(func(path: String):
		var result := _write_export(path, world)
		if on_result.is_valid(): on_result.call(result)
		dialog.queue_free()
	)
	Engine.get_main_loop().root.add_child(dialog)
	dialog.popup_centered_ratio(0.65)

static func _write_export(path: String, world: Dictionary) -> Dictionary:
	var validation_error := _validate_world(world)
	if not validation_error.is_empty(): return {"ok": false, "error": validation_error}
	var absolute_path := ProjectSettings.globalize_path(path)
	var temp_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法创建导出临时文件"}
	file.store_string(JSON.stringify(world, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return {"ok": false, "error": "导出文件未能完整写入"}
	if FileAccess.file_exists(absolute_path):
		if FileAccess.file_exists(backup_path): DirAccess.remove_absolute(backup_path)
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK: return {"ok": false, "error": "无法保留已有导出文件"}
	var replace_error := DirAccess.rename_absolute(temp_path, absolute_path)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path): DirAccess.rename_absolute(backup_path, absolute_path)
		return {"ok": false, "error": "无法完成导出文件替换"}
	return {"ok": true, "path": path}

static func _validate_world(data: Dictionary) -> String:
	var source_shape_error := _validate_source_shape(data)
	if not source_shape_error.is_empty(): return source_shape_error
	var version := int(data.get("schemaVersion", -1))
	if version != WorldData.SAVE_VERSION: return "存档版本未迁移至当前版本，无法安全保存。"
	var city_id := str(data.get("cityId", ""))
	if city_id.is_empty() or WorldData.city(city_id).is_empty(): return "存档未包含受支持的城市资料。"
	if str(data.get("mode", "")) not in ["blank", "expand"]: return "存档开局模式无效。"
	for key in ["stations", "routes", "trackLinks", "trackNodes", "trackEdges"]:
		if not data.get(key, []) is Array: return "存档结构损坏：%s 必须是列表。" % key
	if not data.get("simulation", {}) is Dictionary: return "存档结构损坏：模拟状态无效。"
	for station in data.get("stations", []):
		if not station is Dictionary or str(station.get("id", "")).is_empty(): return "存档包含资料不完整的车站。"
		var coordinates: Variant = station.get("latlng", [])
		if not coordinates is Array or coordinates.size() < 2: return "存档包含资料不完整的车站坐标。"
	for route in data.get("routes", []):
		if not route is Dictionary or str(route.get("id", "")).is_empty(): return "存档包含资料不完整的线路。"
	var station_ids: Dictionary = {}
	for station in data.get("stations", []):
		var station_id := str(station.get("id", ""))
		if station_ids.has(station_id): return "存档包含重复车站编号：%s" % station_id
		station_ids[station_id] = true
	var node_ids: Dictionary = {}
	for node in data.get("trackNodes", []):
		var node_id := str(node.get("id", ""))
		if node_id.is_empty() or node_ids.has(node_id): return "存档包含重复或无效轨道节点编号。"
		node_ids[node_id] = true
	var edge_ids: Dictionary = {}
	for edge in TrackNetwork.all_physical_edges(data):
		var edge_id := str(edge.get("id", ""))
		if edge_id.is_empty() or edge_ids.has(edge_id): return "存档包含重复或无效轨道编号。"
		edge_ids[edge_id] = true
		var endpoints := TrackNetwork._edge_node_ids(edge, data)
		if endpoints.size() != 2 or not node_ids.has(endpoints[0]) or not node_ids.has(endpoints[1]):
			return "轨道 %s 引用了不存在的端点。" % edge_id
		if edge.has("a") and not edge.has("aNodeId"):
			for ref in [edge.get("a", {}), edge.get("b", {})]:
				if not station_ids.has(str(ref.get("stationId", ""))): return "线路接头引用了不存在的车站。"
	var route_ids: Dictionary = {}
	for route in data.get("routes", []):
		var route_id := str(route.get("id", ""))
		if route_ids.has(route_id): return "存档包含重复线路编号：%s" % route_id
		route_ids[route_id] = true
		for station_id in route.get("stationOrder", []):
			if not station_ids.has(str(station_id)): return "线路 %s 引用了不存在的停靠车站。" % str(route.get("name", route_id))
		for direction in route.get("directions", []):
			if not direction is Dictionary: return "线路包含无效运行方向。"
			for segment in direction.get("edgePathsBySegment", []):
				if not segment is Array: return "线路包含无效轨道走向。"
				for reference in segment:
					if not reference is Dictionary or not edge_ids.has(str(reference.get("id", ""))):
						return "线路包含不存在的有向轨道。"
	return ""

static func import_world(on_loaded: Callable, on_error: Callable = Callable()) -> void:
	var dialog := FileDialog.new()
	_apply_app_theme(dialog)
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json ; Metro Atlas 保存文件")
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			if on_error.is_valid(): on_error.call("无法读取所选 JSON 文件。")
			dialog.queue_free()
			return
		var source_text := file.get_as_text()
		file.close()
		var parsed: Variant = _parse_json_text(source_text)
		if not parsed is Dictionary:
			if on_error.is_valid(): on_error.call("所选文件不是有效的存档 JSON；原文件未修改。")
			dialog.queue_free()
			return
		var prepared := prepare_loaded_world(parsed)
		if not bool(prepared.get("ok", false)):
			if on_error.is_valid(): on_error.call(str(prepared.get("error", "存档校验失败")))
			dialog.queue_free()
			return
		on_loaded.call(prepared.world)
		dialog.queue_free()
	)
	Engine.get_main_loop().root.add_child(dialog)
	dialog.popup_centered_ratio(0.65)

static func _apply_app_theme(dialog: Window) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var app := tree.root.get_node_or_null("Main") as Control
	if app != null:
		dialog.theme = app.theme
