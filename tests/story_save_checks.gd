extends SceneTree

const Story=preload("res://scripts/story_session.gd")
var checks:=0
var failures:Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	if not SaveManager.using_explicit_data_dir():push_error("Use explicit --data-dir for isolated save tests");quit(1);return
	var a:=WorldData.new_world("shanghai","campaign")
	var b:=WorldData.new_world("shanghai","campaign")
	_check(bool(SaveManager.save_world(a).ok),"保存第一局")
	_check(bool(SaveManager.save_world(b).ok),"保存同城第二局")
	_check(SaveManager.save_path(str(a.gameId))!=SaveManager.save_path(str(b.gameId)),"自动槽按gameId隔离")
	var loaded:=SaveManager.load_file(SaveManager.save_path(str(a.gameId)))
	_check(bool(loaded.ok) and str(loaded.world.gameId)==str(a.gameId),"继续准确恢复指定游戏")
	for i in range(5):
		a.revision+=1
		_check(bool(SaveManager.save_world(a,true).ok),"自动历史写入%d" % i)
	var dir:=DirAccess.open(SaveManager.game_dir(str(a.gameId)).path_join("auto"))
	_check(dir!=null and dir.get_files().size()<=3,"自动历史最多三份")
	_check(not bool(SaveManager.delete_game(str(a.gameId),str(a.gameId)).ok),"活动自动槽拒绝直接删除")
	_check(bool(SaveManager.save_named(a,"独立作品").ok),"命名副本保留")
	_check(bool(SaveManager.delete_game(str(b.gameId)).ok) and not FileAccess.file_exists(SaveManager.save_path(str(b.gameId))),"删除指定自动槽")
	_check(FileAccess.file_exists(SaveManager.save_path(str(a.gameId))),"其他同城进度不受影响")
	var newer:=a.duplicate(true);newer.schemaVersion=WorldData.SAVE_VERSION+1
	var future_path:=SaveManager.root_path().path_join("unknown.json");SaveManager._write_atomic(future_path,JSON.stringify(newer))
	_check(not bool(SaveManager.load_file(future_path).ok),"拒绝未知新版本")
	var old:=a.duplicate(true);old.schemaVersion=17;old.mode="blank";old.erase("storyState");old.erase("gameId");old["simulation"]={"completed":123,"elapsedSeconds":27001,"passengerBatches":[{"count":5}]}
	var raw:=JSON.stringify(old);var old_path:=SaveManager.root_path().path_join("legacy.json");SaveManager._write_atomic(old_path,raw)
	var migrated:=SaveManager.load_file(old_path)
	_check(bool(migrated.ok) and int(migrated.world.schemaVersion)==WorldData.SAVE_VERSION,"旧存档转换19")
	_check(str(migrated.world.mode)=="workshop" and not migrated.world.has("simulation"),"旧档转为路网作品而非旧模拟模式")
	_check(int(migrated.world.legacyArchive.completed)==123,"旧客流只归档")
	_check(FileAccess.get_file_as_string(old_path)==raw,"迁移不改写原件")
	_check(FileAccess.file_exists(SaveManager.root_path().path_join("originals").path_join("v17_%s.json" % raw.sha256_text())),"迁移前独立原始备份存在")
	var old_campaign:=old.duplicate(true);old_campaign.mode="campaign";old_campaign["campaignState"]={"chapterIndex":2,"completedChapterIds":["sh-line1-1997"]}
	var converted:=SaveManager.migrate(old_campaign)
	_check(converted.storyState.completedChapterIds.is_empty() and int(converted.storyState.chapterIndex)==0,"旧版通关条件不同，从首章核对而非复用错误索引")
	_check(converted.storyState.legacyMilestones.has("sh-line1-1997"),"旧章节完成记录归档保留")
	_check(converted.stations.size()==old_campaign.stations.size(),"重新核对不清空既有建设")
	var current_path:=SaveManager.save_path(str(a.gameId))
	SaveManager._write_atomic(current_path,"broken JSON")
	var pending:=SaveManager.load_file(current_path)
	_check(str(pending.get("status",""))=="recovery_available","损坏主档先询问恢复")
	_check(FileAccess.get_file_as_string(current_path)=="broken JSON","未确认恢复不改原件")
	var recovered:=SaveManager.load_file(current_path,true)
	_check(bool(recovered.ok),"确认后从有效备份恢复")
	_check(not bool(SaveManager.delete_game("../outside").ok),"删除拒绝路径注入")
	var bad:=a.duplicate(true);bad.stations=[{"id":"x","latlng":["bad",1]}]
	_check(not SaveManager.validate(bad).is_empty(),"拒绝无效坐标")
	var all_rows:=SaveManager.list_saves()
	var histories:Array=all_rows.filter(func(row:Dictionary):return str(row.kind)=="自动历史" and str(row.gameId)==str(a.gameId))
	_check(histories.size()==3,"三份自动历史均可从列表找到")
	if not histories.is_empty():
		_check(bool(SaveManager.load_file(str(histories[0].path)).ok),"自动历史可以独立载入")
		_check(bool(SaveManager.delete_auto_history(str(a.gameId),str(histories[0].path).get_file()).ok),"单独删除自动历史")
	_check(not bool(SaveManager.delete_auto_history(str(a.gameId),"../current.json").ok),"自动历史删除拒绝目录穿越")
	var named:Array=SaveManager.list_saves().filter(func(row:Dictionary):return str(row.kind)=="手动存档")
	_check(not named.is_empty(),"手动存档可见")
	if not named.is_empty():
		_check(bool(SaveManager.rename_manual(str(named[0].path),"改名作品").ok),"手动改名保存")
		_check(str(SaveManager.load_file(str(named[0].path)).world.title)=="改名作品","改名不改变存档内容")
		_check(bool(SaveManager.overwrite_manual(str(named[0].path),a).ok),"手动覆盖当前进度")
		_check(bool(SaveManager.delete_manual(str(named[0].path)).ok),"手动删除可用")
	_check(not bool(SaveManager.rename_manual(current_path,"错误目标").ok),"改名接口拒绝非命名目录")
	_check(not bool(SaveManager.overwrite_manual(current_path,a).ok),"覆盖接口拒绝非命名目录")
	var wrong_shape:=a.duplicate(true);wrong_shape.routes=[{"id":"x","directions":"bad"}]
	_check(not SaveManager.validate(wrong_shape).is_empty(),"畸形方向容器被拒绝而非崩溃")
	wrong_shape=a.duplicate(true);wrong_shape.history={"undo":"bad"}
	_check(not SaveManager.validate(wrong_shape).is_empty(),"畸形历史容器被拒绝")
	var unchanged:=WorldData.new_world("chengdu","campaign")
	SaveManager.save_world(unchanged)
	SaveManager.save_world(unchanged,true)
	_check(not DirAccess.dir_exists_absolute(SaveManager.game_dir(str(unchanged.gameId)).path_join("auto")),"无变化保存不推进自动历史")
	SaveManager.save_world(a)
	var valid_before:=FileAccess.get_file_as_string(current_path)
	DirAccess.make_dir_recursive_absolute(current_path+".tmp")
	a.revision+=1
	_check(not bool(SaveManager.save_world(a).ok),"主档写入失败不假报成功")
	_check(FileAccess.get_file_as_string(current_path)==valid_before,"主档写入失败保留有效文件")
	DirAccess.remove_absolute(current_path+".tmp")
	var broken_text:="broken JSON recovery-copy-failure"
	SaveManager._write_atomic(current_path,broken_text)
	var blocked_copy:=SaveManager.root_path().path_join("originals").path_join("recovery_%s.json.tmp" % broken_text.sha256_text())
	DirAccess.make_dir_recursive_absolute(blocked_copy)
	_check(not bool(SaveManager.load_file(current_path,true).ok),"恢复副本写入失败阻止切换会话")
	_check(FileAccess.get_file_as_string(current_path)==broken_text,"恢复失败不覆盖损坏原件")
	DirAccess.remove_absolute(blocked_copy)
	var index_path:=SaveManager.root_path().path_join("last_game.json")
	SaveManager._write_atomic(index_path,JSON.stringify(old_campaign))
	var legacy_continue:=SaveManager.load_last_game()
	_check(bool(legacy_continue.get("ok",false)) and bool(legacy_continue.get("migrated",false)),"旧版完整世界继续记录走统一备份迁移入口")
	if bool(legacy_continue.get("ok",false)):
		SaveManager.save_world(legacy_continue.world)
		SaveManager.delete_game(str(legacy_continue.world.gameId))
		_check(not FileAccess.file_exists(index_path) and not FileAccess.file_exists(index_path+".bak"),"删除迁移进度同时清掉可重新迁入它的旧继续备份")
	SaveManager.save_world(a);SaveManager.save_world(a)
	SaveManager._write_atomic(index_path,"corrupt continue index")
	var continue_pending:=SaveManager.load_last_game()
	_check(str(continue_pending.get("recoveryKind",""))=="continue_index","损坏引用索引需要单独确认恢复")
	_check(FileAccess.get_file_as_string(index_path)=="corrupt continue index","未确认索引恢复不修改文件")
	_check(bool(SaveManager.load_last_game(true).get("ok",false)),"确认后引用索引备份可恢复正确世界")
	SaveManager._write_atomic(index_path,JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION+1,"gameId":a.gameId}))
	_check(str(SaveManager.load_last_game().get("status",""))=="unsupported","未来版本继续索引不降级回旧备份")
	SaveManager.save_world(a)
	var index_before:=FileAccess.get_file_as_string(index_path)
	DirAccess.make_dir_recursive_absolute(index_path+".tmp")
	_check(not bool(SaveManager.save_world(a).ok),"继续索引写入失败不显示保存成功")
	_check(FileAccess.get_file_as_string(index_path)==index_before,"索引写入失败保留原有效索引")
	DirAccess.remove_absolute(index_path+".tmp")
	DirAccess.make_dir_recursive_absolute(index_path+".bak.tmp")
	_check(not bool(SaveManager.save_world(a).ok),"继续索引备份写入失败保留会话")
	DirAccess.remove_absolute(index_path+".bak.tmp")
	if failures.is_empty():print("PASS: %d story save checks" % checks);quit(0)
	else:
		for error in failures:push_error(error)
		quit(1)

func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
