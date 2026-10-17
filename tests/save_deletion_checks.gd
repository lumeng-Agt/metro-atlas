extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		push_error("Save deletion checks require an isolated --data-dir.")
		quit(2)
		return
	WorldData.load_assets()
	var main_path := SaveManager.save_path("shanghai", "blank")
	var backup_path := main_path + ".bak"
	var index_path := SaveManager.last_game_path()
	var manual_path := ""
	var shanghai := WorldData.new_world("shanghai", "blank")
	_check(bool(SaveManager.save_world(shanghai).get("ok", false)), "建立上海自动进度")
	for minute in range(421, 426):
		shanghai.simulation.minute = minute
		shanghai.simulation.elapsedMinutes = minute
		shanghai.simulation.elapsedSeconds = minute * 60
		_check(bool(SaveManager.save_world(shanghai, true).get("ok", false)), "写入自动历史和主进度")
	var histories := SaveManager.list_auto_history("shanghai", "blank")
	_check(histories.size() == 3, "自动历史保持最近三份")
	var last_game := SaveManager.save_last_game(shanghai)
	_check(bool(last_game.get("ok", false)), "继续游戏索引指向上海自动进度")
	var manual := SaveManager.save_manual_snapshot(shanghai, "保留的独立命名存档")
	manual_path = str(manual.get("path", ""))
	_check(bool(manual.get("ok", false)), "建立独立命名存档")
	var beijing := WorldData.new_world("beijing", "blank")
	_check(bool(SaveManager.save_world(beijing).get("ok", false)), "建立另一城市的自动进度")
	var active_delete := SaveManager.delete_auto_slot("shanghai", "blank", "shanghai", "blank")
	_check(not bool(active_delete.get("ok", true)) and str(active_delete.get("status", "")) == "active_slot", "当前正在使用的自动进度无法直接删除")
	_check(FileAccess.file_exists(main_path) and FileAccess.file_exists(backup_path), "活动进度删除被拦截且主档与备份保留")
	histories = SaveManager.list_auto_history("shanghai", "blank")
	if not histories.is_empty():
		var history_id := str(histories[0].get("id", ""))
		var history_path := str(histories[0].get("path", ""))
		var deleted_history := SaveManager.delete_auto_history("shanghai", "blank", history_id)
		_check(bool(deleted_history.get("ok", false)) and not FileAccess.file_exists(history_path), "使用稳定编号单独删除一份自动历史")
	else:
		_check(false, "存在可单独删除的自动历史")
	_check(not bool(SaveManager.delete_auto_history("shanghai", "blank", "..\\last_game.json").get("ok", true)), "自动历史删除拒绝目录穿越标识")
	_check(not bool(SaveManager.delete_manual_snapshot(main_path).get("ok", true)), "命名存档删除拒绝任意文件路径")
	var deleted_slot := SaveManager.delete_auto_slot("shanghai", "blank")
	_check(bool(deleted_slot.get("ok", false)), "离开城市后可删除自动进度")
	_check(not FileAccess.file_exists(main_path) and not FileAccess.file_exists(backup_path), "删除自动槽后主进度和恢复备份均清除")
	_check(SaveManager.list_auto_history("shanghai", "blank").is_empty(), "删除自动槽后其余自动历史均清除")
	_check(not FileAccess.file_exists(index_path) and not FileAccess.file_exists(index_path + ".bak"), "指向已删自动槽的继续游戏索引及备份一并清除")
	_check(FileAccess.file_exists(manual_path), "删除自动槽不会影响独立命名存档")
	_check(SaveManager.save_exists("beijing", "blank"), "删除上海自动槽不会影响北京进度")
	var manual_deleted := SaveManager.delete_manual_snapshot(manual_path.get_file())
	_check(bool(manual_deleted.get("ok", false)) and not FileAccess.file_exists(manual_path), "命名存档可通过稳定编号删除")
	var beijing_deleted := SaveManager.delete_auto_slot("beijing", "blank")
	_check(bool(beijing_deleted.get("ok", false)), "测试结束清理另一城市自动槽")
	if failures.is_empty():
		print("PASS: %d save deletion checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
