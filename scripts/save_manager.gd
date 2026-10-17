class_name SaveManager
extends RefCounted

static func root_path() -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		var arg := str(args[index])
		if arg.begins_with("--data-dir="):
			var path := arg.trim_prefix("--data-dir=")
			if path.is_empty() or not path.is_absolute_path(): return ""
			return path.simplify_path()
		if arg == "--data-dir" and index+1 < args.size():
			var path := str(args[index+1])
			return path.simplify_path() if path.is_absolute_path() else ""
		if arg=="--data-dir":return ""
	var roaming := OS.get_environment("APPDATA")
	return roaming.path_join("MetroAtlas") if not roaming.is_empty() else "user://MetroAtlas"

static func using_explicit_data_dir() -> bool:
	for arg in OS.get_cmdline_user_args():
		if str(arg)=="--data-dir" or str(arg).begins_with("--data-dir="):return true
	return false

static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length()>140:return false
	for ch in id:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(ch):return false
	return true

static func game_dir(id: String) -> String:
	return root_path().path_join("games").path_join(id) if valid_id(id) else ""

static func save_path(id: String, _mode: String = "") -> String:
	return game_dir(id).path_join("current.json") if valid_id(id) else ""

static func _read(path: String) -> Dictionary:
	if root_path().is_empty():return {"ok":false,"status":"invalid_data_dir","error":"--data-dir必须指定绝对目录，已停止读写。"}
	if not FileAccess.file_exists(path):return {"ok":false,"status":"not_found","error":"没有找到该存档。"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:return {"ok":false,"status":"read_failed","error":"无法读取存档。"}
	var text:=file.get_as_text();file.close()
	var parser:=JSON.new()
	if parser.parse(text)!=OK:return {"ok":false,"status":"corrupt","error":"JSON内容损坏。","text":text,"path":path}
	if not parser.data is Dictionary:return {"ok":false,"status":"corrupt","error":"存档根对象格式错误。","text":text,"path":path}
	return {"ok":true,"data":parser.data,"text":text,"path":path}

static func validate(data: Dictionary) -> String:
	if int(data.get("schemaVersion",0))>WorldData.SAVE_VERSION:return "存档来自更新版本，无法载入。"
	if WorldData.city(str(data.get("cityId",""))).is_empty():return "存档引用了未知城市。"
	var indexes:Dictionary={}
	for key in ["stations","routes","trackLinks","trackNodes","trackEdges"]:
		if not data.get(key,[]) is Array:return "%s必须是数组。" % key
		var ids:Dictionary={}
		for item in data.get(key,[]):
			if not item is Dictionary:return "%s包含无效对象。" % key
			var id:=str(item.get("id",""))
			if id.is_empty() or ids.has(id):return "%s包含空编号或重复编号。" % key
			ids[id]=true
		indexes[key]=ids
	for station in data.get("stations",[]):
		if not _coordinate_valid(station.get("latlng")):return "车站坐标无效。"
		for key in ["heading","lengthM","widthM","depthM"]:
			if station.has(key) and (not (station[key] is int or station[key] is float) or not is_finite(float(station[key]))):return "车站尺寸或方向无效。"
	for node in data.get("trackNodes",[]):
		if not _coordinate_valid(node.get("latlng")):return "轨道节点坐标无效。"
		if not str(node.get("stationId","")).is_empty() and not indexes.stations.has(str(node.stationId)):return "站端节点引用了不存在的车站。"
	for edge in data.get("trackEdges",[]):
		if not indexes.trackNodes.has(str(edge.get("aNodeId",""))) or not indexes.trackNodes.has(str(edge.get("bNodeId",""))):return "轨道引用了不存在的节点。"
		for key in ["controlA","controlB"]:
			if edge.has(key) and not _vector_valid(edge[key]):return "曲线控制点无效。"
	for link in data.get("trackLinks",[]):
		if not link.get("a",{}) is Dictionary or not link.get("b",{}) is Dictionary:return "旧轨道端点格式错误。"
		if not indexes.stations.has(str(link.get("a",{}).get("stationId",""))) or not indexes.stations.has(str(link.get("b",{}).get("stationId",""))):return "旧轨道引用了不存在的车站。"
	var edge_ids:Dictionary={}
	for edge in data.get("trackEdges",[])+data.get("trackLinks",[]):edge_ids[str(edge.id)]=true
	for route in data.get("routes",[]):
		if not route.get("stationOrder",[]) is Array or not route.get("directions",[]) is Array:return "线路站序或方向格式错误。"
		for id in route.get("stationOrder",[]):
			if not indexes.stations.has(str(id)):return "线路引用了不存在的车站。"
		for direction in route.get("directions",[]):
			if not direction is Dictionary or not direction.get("stationIds",[]) is Array or not direction.get("edgePathsBySegment",[]) is Array:return "线路方向路径容器错误。"
			for id in direction.get("stationIds",[]):
				if not indexes.stations.has(str(id)):return "线路方向引用了不存在的车站。"
			for segment in direction.get("edgePathsBySegment",[]):
				if not segment is Array:return "线路区间路径必须是数组。"
				for ref in segment:
					if not ref is Dictionary:return "线路轨道引用格式错误。"
					if not edge_ids.has(str(ref.get("id",""))):return "线路路径引用了不存在的轨道。"
	for key in ["history","campaignState"]:
		if data.has(key) and not data[key] is Dictionary:return "章节或历史容器错误。"
	if data.has("history"):
		for key in ["undo","redo"]:
			if not data.history.get(key,[]) is Array:return "撤销历史格式错误。"
	if int(data.get("schemaVersion",0))==18:
		if not valid_id(str(data.get("gameId",""))):return "游戏编号无效。"
		if data.has("simulation"):return "新故事存档不应包含运行中的旧客流模拟。"
		if not data.get("storyState",{}) is Dictionary or not data.get("storyPlan",{}) is Dictionary:return "章节或规划容器无效。"
		for key in ["milestones","completedChapterIds"]:
			if not data.get("storyState",{}).get(key,[]) is Array:return "历史里程碑格式错误。"
	return ""

static func _coordinate_valid(value: Variant) -> bool:
	return _vector_valid(value) and absf(float(value[0]))<=85.06 and absf(float(value[1]))<=180.0

static func _vector_valid(value:Variant) -> bool:
	return value is Array and value.size()==2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int) and is_finite(float(value[0])) and is_finite(float(value[1]))

static func _write_atomic(path: String, text: String) -> Dictionary:
	if root_path().is_empty():return {"ok":false,"error":"--data-dir必须指定绝对目录，已停止写入。"}
	var error:=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error!=OK:return {"ok":false,"error":"无法创建存档目录：%s" % error_string(error)}
	var temp:=path+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:return {"ok":false,"error":"无法写入：%s" % path.get_file()}
	file.store_string(text);file.flush()
	var write_error:=file.get_error();file.close()
	if write_error!=OK:return {"ok":false,"error":"磁盘写入失败。"}
	var replacement:=DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
	return {"ok":replacement==OK,"error":"" if replacement==OK else "无法替换文件：%s" % error_string(replacement)}

static func save_world(world: Dictionary, rotate: bool = false) -> Dictionary:
	var problem:=validate(world)
	if not problem.is_empty():return {"ok":false,"error":problem}
	var id:=str(world.gameId);var path:=save_path(id)
	var old:=_read(path)
	var current:=world.duplicate(true);current["savedAt"]=Time.get_datetime_string_from_system(false,true)
	var text:=JSON.stringify(current)
	if bool(old.get("ok",false)) and validate(old.data).is_empty():
		var backup:=_write_atomic(path+".bak",str(old.text))
		if not bool(backup.ok):return backup
		var previous:Dictionary=old.data.duplicate(true);previous.erase("savedAt")
		var next:Dictionary=current.duplicate(true);next.erase("savedAt")
		# JSON reads numbers as floats; compare the same persisted representation.
		if rotate and JSON.stringify(previous)!=JSON.stringify(JSON.parse_string(JSON.stringify(next))):
			var archive:=game_dir(id).path_join("auto").path_join("%d_%d.json" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()])
			var result:=_write_atomic(archive,str(old.text))
			if not bool(result.ok):return result
	var result:=_write_atomic(path,text)
	if not bool(result.ok):return result
	var index_path:=root_path().path_join("last_game.json");var prior_index:=_read(index_path)
	if bool(prior_index.get("ok",false)) and _index_usable(prior_index.data):
		result=_write_atomic(index_path+".bak",str(prior_index.text))
		if not bool(result.ok):return {"ok":false,"error":"进度已写入，但继续索引备份失败，请重试。"}
	result=_write_atomic(index_path,JSON.stringify({"schemaVersion":18,"gameId":id}))
	if not bool(result.ok):return {"ok":false,"error":"进度已写入，但继续游戏索引失败，请重试。"}
	_prune_auto(id)
	world["savedAt"]=current.savedAt
	return {"ok":true,"path":path}

static func _prune_auto(id: String) -> void:
	var path:=game_dir(id).path_join("auto")
	var dir:=DirAccess.open(path)
	if dir==null:return
	var files:Array[String]=[]
	for filename in dir.get_files():
		if filename.ends_with(".json"):files.append(filename)
	files.sort()
	while files.size()>3:DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(files.pop_front())))

static func load_file(path: String, confirm_recovery: bool = false) -> Dictionary:
	var raw:=_read(path)
	var problem:=validate(raw.get("data",{})) if bool(raw.get("ok",false)) else str(raw.get("error",""))
	if bool(raw.get("ok",false)) and int(raw.data.get("schemaVersion",0))>18:return {"ok":false,"error":problem,"status":"unsupported"}
	if not bool(raw.get("ok",false)) or not problem.is_empty():
		var backup:=_read(path+".bak")
		if not bool(backup.get("ok",false)) or not validate(backup.data).is_empty():return {"ok":false,"error":problem,"status":"corrupt"}
		if not confirm_recovery:return {"ok":false,"status":"recovery_available","error":problem,"path":path,"backupAt":str(backup.data.get("savedAt","未知"))}
		# Both source and valid fallback must be preserved before entering a session.
		for source in [raw,backup]:
			if not source.has("text"):continue
			var preserved:=_preserve_original(str(source.text),"recovery")
			if not bool(preserved.ok):return preserved
		raw=backup
	if int(raw.data.get("schemaVersion",0))<18:
		var preserved:=_preserve_original(str(raw.text),"v%d" % int(raw.data.get("schemaVersion",0)))
		if not bool(preserved.ok):return preserved
		var migrated:=migrate(raw.data,str(raw.text))
		problem=validate(migrated)
		return {"ok":problem.is_empty(),"error":problem,"world":migrated,"migrated":true}
	return {"ok":true,"world":raw.data}

static func _preserve_original(text: String, prefix: String) -> Dictionary:
	var path:=root_path().path_join("originals").path_join("%s_%s.json" % [prefix,text.sha256_text()])
	if FileAccess.file_exists(path):return {"ok":true,"path":path}
	return _write_atomic(path,text)

static func migrate(data: Dictionary, original_text: String = "") -> Dictionary:
	var result:=data.duplicate(true)
	var old_version:=int(data.get("schemaVersion",0))
	result["schemaVersion"]=18
	result["gameId"]="legacy_%s" % (original_text if not original_text.is_empty() else JSON.stringify(data)).sha256_text().substr(0,20)
	result["mode"]="campaign" if str(data.get("mode",""))=="campaign" else "workshop"
	result["title"]="%s · %s" % [str(data.get("cityName",data.get("cityId","城市"))),"历史进度" if result.mode=="campaign" else "旧路网作品"]
	var sim:Dictionary=data.get("simulation",{}) if data.get("simulation",{}) is Dictionary else {}
	result["legacyArchive"]={"sourceVersion":old_version,"completed":sim.get("completed",0),"elapsedSeconds":sim.get("elapsedSeconds",int(sim.get("elapsedMinutes",0))*60),"oldHistorySteps":data.get("history",{}).get("undo",[]).size(),"note":"原始文件已独立归档。原客流仅作历史记录，不继续运行。"}
	for key in ["simulation","goalBoard","cityProgression","challengeState","challengeMode","onboarding","tutorialStep","tutorialDone","fleetMode"]:result.erase(key)
	var old:Dictionary=data.get("campaignState",{})
	result["storyState"]={"chapterIndex":0,"chapterId":"","stage":"intro","completedChapterIds":[],"milestones":[],"tutorialEnabled":false,"learnedTools":true,"assistedChapters":[],"catalogVersion":CampaignSystem.content_version(),"phase":"history","freeUnlocked":false,"legacyMilestones":old.get("completedChapterIds",[])}
	result.erase("campaignState")
	result["storyPlan"]={"planIndex":0,"pathChoices":{}}
	result["history"]={"undo":[],"redo":[]}
	result["milestoneBaseline"]={}
	for key in ["stations","routes","trackLinks","trackNodes","trackEdges"]:
		if not result.has(key):result[key]=[]
	TrackNetwork.ensure_station_nodes(result)
	# Existing campaign targets are explicitly adopted once during conversion.
	if result.mode=="campaign":
		var catalog:=preload("res://scripts/campaign_system.gd").city_config(str(result.cityId))
		var refs:Dictionary={}
		for c in catalog.get("chapters",[]):
			for group in c.get("lineGroups",[]):
				for id in group.get("stationIds",[]):refs[str(id)]=true
		var used:Dictionary={}
		var lat:=float(WorldData.city(str(result.cityId)).get("center",[31.23])[0])
		for reference in WorldData.city(str(result.cityId)).get("stations",[]):
			if not refs.has(str(reference.id)):continue
			var best:Dictionary={};var distance:=100.0
			for station in result.stations:
				if used.has(str(station.id)):continue
				var d:=Geo.local_m(station.latlng,lat).distance_to(Geo.local_m(reference.latlng,lat))
				if d<distance:best=station;distance=d
			if not best.is_empty():best["historicalId"]=str(reference.id);used[str(best.id)]=true
	result["migrationNotice"]="已转换为故事进度或旧路网作品。旧统计和旧历史保存在原始备份；旧章节与旧历史留在原始备份及恢复记录；新故事从首章核对已有建设，不清空路网。"
	return result

static func _index_usable(data:Dictionary) -> bool:
	if data.has("stations"):return validate(data).is_empty()
	return int(data.get("schemaVersion",0))==18 and valid_id(str(data.get("gameId","")))

static func load_last_game(confirm_recovery:bool=false) -> Dictionary:
	var index_path:=root_path().path_join("last_game.json")
	var index:=_read(index_path)
	if bool(index.get("ok",false)) and int(index.data.get("schemaVersion",0))>18:return {"ok":false,"status":"unsupported","error":"继续进度来自更新版本，无法载入。"}
	if not bool(index.get("ok",false)) or not _index_usable(index.data):
		var backup:=_read(index_path+".bak")
		if not bool(backup.get("ok",false)) or not _index_usable(backup.data):
			if str(index.get("status",""))=="not_found" and str(backup.get("status",""))=="not_found":return {"ok":false,"status":"not_found","error":"还没有继续进度，请开始城市故事。"}
			return {"ok":false,"status":"corrupt","error":"继续记录损坏，请从存档中心载入。"}
		if not confirm_recovery:return {"ok":false,"status":"recovery_available","recoveryKind":"continue_index","path":index_path,"error":"继续记录损坏。","backupAt":str(backup.data.get("savedAt","上一次有效继续记录"))}
		for source in [index,backup]:
			if source.has("text"):
				var preserved:=_preserve_original(str(source.text),"continue_recovery")
				if not bool(preserved.ok):return preserved
		index=backup
	# Earlier releases stored a complete world in the continue record. Load that
	# checkpoint through validation/migration rather than choosing an older slot.
	if index.data.has("stations"):
		if str(index.get("path",index_path))==index_path:return load_file(index_path)
		return load_file(index_path+".bak")
	var id:=str(index.data.get("gameId",""))
	if valid_id(id):return load_file(save_path(id))
	var city_id:=str(index.data.get("cityId",""));var mode:=str(index.data.get("mode",""))
	if (not valid_id(city_id) or not valid_id(mode)) and not index.data.has("stations"):return {"ok":false,"error":"继续记录无效，请从存档列表载入。"}
	var legacy_path:=root_path().path_join("saves").path_join("%s_%s.json" % [city_id,mode])
	if FileAccess.file_exists(legacy_path):return load_file(legacy_path)
	if index.data.has("stations"):return load_file(root_path().path_join("last_game.json"))
	return {"ok":false,"error":"继续记录无效，请从存档列表载入。"}

static func list_saves() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var games:=DirAccess.open(root_path().path_join("games"))
	if games!=null:
		for id in games.get_directories():
			if not valid_id(id):continue
			if FileAccess.file_exists(save_path(id)):_append_row(result,save_path(id),"自动进度",id)
			elif FileAccess.file_exists(save_path(id)+".bak"):
				_append_row(result,save_path(id)+".bak","自动进度",id);result[-1]["backupOnly"]=true;result[-1].title=str(result[-1].title)+" · 仅剩恢复备份"
			var automatic:=DirAccess.open(game_dir(id).path_join("auto"))
			if automatic!=null:
				for file in automatic.get_files():
					if file.ends_with(".json"):_append_row(result,game_dir(id).path_join("auto").path_join(file),"自动历史",id)
	var legacy:=DirAccess.open(root_path().path_join("saves"))
	if legacy!=null:
		for name in legacy.get_files():
			if name.ends_with(".json"):_append_row(result,root_path().path_join("saves").path_join(name),"旧版原件","")
	var manual:=DirAccess.open(root_path().path_join("manual_saves"))
	if manual!=null:
		for name in manual.get_files():
			if name.ends_with(".json"):_append_row(result,root_path().path_join("manual_saves").path_join(name),"手动存档","")
	var old_histories:=DirAccess.open(root_path().path_join("auto_history"))
	if old_histories!=null:
		for slot in old_histories.get_directories():
			var directory:=DirAccess.open(root_path().path_join("auto_history").path_join(slot))
			if directory!=null:
				for file in directory.get_files():
					if file.ends_with(".json"):_append_row(result,root_path().path_join("auto_history").path_join(slot).path_join(file),"旧版自动历史原件","")
	result.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.get("modified",0))>int(b.get("modified",0)))
	return result

static func _append_row(rows: Array[Dictionary],path:String,kind:String,id:String) -> void:
	var raw:=_read(path)
	var data:Dictionary=raw.get("data",{})
	rows.append({"path":path,"gameId":id,"kind":kind,"title":str(data.get("title",data.get("cityName","损坏存档"))),"city":str(data.get("cityName","")),"stations":data.get("stations",[]).size() if data.get("stations",[]) is Array else 0,"routes":data.get("routes",[]).size() if data.get("routes",[]) is Array else 0,"savedAt":str(data.get("savedAt","旧存档")),"modified":FileAccess.get_modified_time(path),"bytes":str(raw.get("text","")).to_utf8_buffer().size()})

static func save_named(world:Dictionary,title:String) -> Dictionary:
	var problem:=validate(world)
	if not problem.is_empty():return {"ok":false,"error":problem}
	var copy:=world.duplicate(true);copy["title"]=title;copy["savedAt"]=Time.get_datetime_string_from_system(false,true)
	return _write_atomic(root_path().path_join("manual_saves").path_join("%s_%d.json" % [str(world.gameId),Time.get_ticks_usec()]),JSON.stringify(copy))

static func _manual_path_valid(path:String) -> bool:
	return ProjectSettings.globalize_path(path.get_base_dir()).simplify_path()==ProjectSettings.globalize_path(root_path().path_join("manual_saves")).simplify_path() and path.ends_with(".json")

static func rename_manual(path:String,title:String) -> Dictionary:
	if not _manual_path_valid(path) or title.strip_edges().is_empty():return {"ok":false,"error":"无效存档或名称。"}
	var raw:=_read(path)
	if not bool(raw.get("ok",false)):return raw
	var data:Dictionary=raw.data;data["title"]=title.strip_edges()
	return _write_atomic(path,JSON.stringify(data))

static func overwrite_manual(path:String,world:Dictionary) -> Dictionary:
	if not _manual_path_valid(path) or not FileAccess.file_exists(path):return {"ok":false,"error":"该命名存档已不存在。"}
	var problem:=validate(world)
	if not problem.is_empty():return {"ok":false,"error":problem}
	var raw:=_read(path)
	var data:=world.duplicate(true);data["title"]=str(raw.get("data",{}).get("title",world.get("title","路网作品")));data["savedAt"]=Time.get_datetime_string_from_system(false,true)
	return _write_atomic(path,JSON.stringify(data))

static func delete_auto_history(id:String,file:String) -> Dictionary:
	if not valid_id(id) or file!=file.get_file() or not file.ends_with(".json"):return {"ok":false,"error":"无效自动历史编号。"}
	var error:=DirAccess.remove_absolute(ProjectSettings.globalize_path(game_dir(id).path_join("auto").path_join(file)))
	return {"ok":error==OK,"error":"无法删除该历史：%s" % error_string(error) if error!=OK else ""}

static func delete_game(id:String,active_id:String="") -> Dictionary:
	if not valid_id(id):return {"ok":false,"error":"无效游戏编号。"}
	if id==active_id:return {"ok":false,"error":"请先返回主菜单再删除当前自动进度。"}
	var path:=save_path(id)
	var files:Array[String]=[path,path+".bak"]
	var dir:=DirAccess.open(game_dir(id).path_join("auto"))
	if dir!=null:
		for name in dir.get_files():
			if name.ends_with(".json"):files.append(game_dir(id).path_join("auto").path_join(name))
	var failed:Array[String]=[]
	var deleted:Array[String]=[]
	for file in files:
		if FileAccess.file_exists(file):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(file))!=OK:failed.append(file.get_file())
			else:deleted.append(file.get_file())
	for file in [root_path().path_join("last_game.json"),root_path().path_join("last_game.json.bak")]:
		var index:=_read(file)
		var index_id:=str(index.get("data",{}).get("gameId",""))
		if bool(index.get("ok",false)) and index.data.has("stations") and int(index.data.get("schemaVersion",0))<18:index_id="legacy_%s" % str(index.text).sha256_text().substr(0,20)
		if bool(index.get("ok",false)) and index_id==id:
			if FileAccess.file_exists(file) and DirAccess.remove_absolute(ProjectSettings.globalize_path(file))!=OK:failed.append(file.get_file())
	return {"ok":failed.is_empty(),"deleted":deleted,"failed":failed,"error":("已删除：%s\n未删除：%s" % ["、".join(deleted) if not deleted.is_empty() else "无","、".join(failed)]) if not failed.is_empty() else ""}

static func delete_manual(path:String) -> Dictionary:
	if not _manual_path_valid(path):return {"ok":false,"error":"只能删除命名存档目录中的指定文件。"}
	var error:=DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"ok":error==OK,"error":"无法删除：%s" % error_string(error) if error!=OK else ""}
