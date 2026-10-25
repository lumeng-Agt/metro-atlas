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
	for key in ["stations","stationComplexes","transferConnections","serviceRanges","routes","trackLinks","trackNodes","trackEdges"]:
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
		if not str(station.get("stationComplexId","")).is_empty() and not indexes.stationComplexes.has(str(station.stationComplexId)):return "车站引用了不存在的换乘站区。"
	var instance_ids:Dictionary={}
	for station in data.get("stations",[]):
		var instance_id:=str(station.get("stationInstanceId",station.get("id","")))
		if instance_id.is_empty() or instance_ids.has(instance_id):return "物理站体编号为空或重复。"
		instance_ids[instance_id]=true
	for connection in data.get("transferConnections",[]):
		if str(connection.get("complexId","")).is_empty() or not indexes.stationComplexes.has(str(connection.complexId)):return "换乘关系引用了不存在的站区。"
		if not connection.get("stationInstanceIds",[]) is Array or connection.stationInstanceIds.size()<2:return "换乘关系至少需要两个独立站体。"
		var linked_instances:Dictionary={}
		for instance_id in connection.stationInstanceIds:
			if not instance_ids.has(str(instance_id)):return "换乘关系引用了不存在的物理站体。"
			if linked_instances.has(str(instance_id)):return "换乘关系重复引用了同一物理站体。"
			linked_instances[str(instance_id)]=true
			for station in data.get("stations",[]):
				if str(station.get("stationInstanceId",station.get("id","")))!=str(instance_id):continue
				var body_complex:=CampaignSystem.canonical_station_complex(str(data.cityId),str(station.get("stationComplexId",station.get("historicalId",""))))
				var relation_complex:=CampaignSystem.canonical_station_complex(str(data.cityId),str(connection.complexId))
				if body_complex!=relation_complex:return "换乘站体与其历史站区不一致。"
		if str(connection.get("status","active"))=="active":
			if not connection.get("lineIds",[]) is Array or connection.lineIds.size()!=connection.stationInstanceIds.size():return "已建立的换乘关系需要逐一对应物理站体和线路。"
			var linked_lines:Dictionary={}
			for index in range(connection.lineIds.size()):
				var line_id:=str(connection.lineIds[index])
				if line_id.is_empty() or linked_lines.has(line_id):return "换乘关系重复引用或漏填了线路。"
				linked_lines[line_id]=true
				var serving_instance:=str(connection.stationInstanceIds[index]);var serving_station_id:=""
				for station in data.get("stations",[]):
					if str(station.get("stationInstanceId",station.get("id","")))==serving_instance:serving_station_id=str(station.get("id",""));break
				var matching_line_found:=false;var route_serves_station:=false
				for route in data.get("routes",[]):
					if str(route.get("id",""))!=line_id and str(route.get("historicalLineId",""))!=line_id:continue
					matching_line_found=true
					if route.get("stationOrder",[]).has(serving_station_id):route_serves_station=true;break
					for direction in route.get("directions",[]):
						if direction is Dictionary and direction.get("stationIds",[]).has(serving_station_id):
							route_serves_station=true
							break
					if route_serves_station:break
				if not matching_line_found:return "换乘关系引用了不存在的线路。"
				if not route_serves_station:return "换乘「%s」的%s没有停靠站体%s（关系%s）。"%[str(connection.get("name","换乘")),line_id,serving_instance,str(connection.get("id",""))]
	for node in data.get("trackNodes",[]):
		if not _coordinate_valid(node.get("latlng")):return "轨道节点坐标无效。"
		if not str(node.get("stationId","")).is_empty() and not indexes.stations.has(str(node.stationId)):return "站端节点引用了不存在的车站。"
	for edge in data.get("trackEdges",[]):
		if str(edge.get("geometry",""))=="reference_polyline":
			if not edge.get("referencePoints",[]) is Array or edge.get("referencePoints",[]).size()<2:return "参考轨道缺少连续坐标。"
			for point in edge.referencePoints:
				if not _coordinate_valid(point):return "参考轨道坐标无效。"
		if not indexes.trackNodes.has(str(edge.get("aNodeId",""))) or not indexes.trackNodes.has(str(edge.get("bNodeId",""))):return "轨道引用了不存在的节点。"
		for key in ["controlA","controlB"]:
			if edge.has(key) and not _vector_valid(edge[key]):return "曲线控制点无效。"
	for link in data.get("trackLinks",[]):
		if not link.get("a",{}) is Dictionary or not link.get("b",{}) is Dictionary:return "旧轨道端点格式错误。"
		if not indexes.stations.has(str(link.get("a",{}).get("stationId",""))) or not indexes.stations.has(str(link.get("b",{}).get("stationId",""))):return "旧轨道引用了不存在的车站。"
	var edge_ids:Dictionary={}
	for edge in data.get("trackEdges",[])+data.get("trackLinks",[]):edge_ids[str(edge.id)]=true
	for service_range in data.get("serviceRanges",[]):
		if str(service_range.get("status","")) not in ["built","trial","open","suspended"]:return "历史服务范围状态无效。"
		if not service_range.get("stationIds",[]) is Array or service_range.stationIds.size()<2:return "历史服务范围至少需要两个站点。"
		if not service_range.get("edgePathsBySegment",[]) is Array or service_range.edgePathsBySegment.size()!=service_range.stationIds.size()-1:return "历史服务范围的站间路径数量不匹配。"
		for station_id in service_range.stationIds:
			if not indexes.stations.has(str(station_id)):return "历史服务范围引用了不存在的物理站体。"
		for segment in service_range.edgePathsBySegment:
			if not segment is Array:return "历史服务范围区间格式错误。"
			for ref in segment:
				if not ref is Dictionary or not edge_ids.has(str(ref.get("id",""))):return "历史服务范围引用了不存在的实体轨道。"
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
	if int(data.get("schemaVersion",0))>=18:
		if not valid_id(str(data.get("gameId",""))):return "游戏编号无效。"
		if data.has("simulation"):return "新故事存档不应包含运行中的旧客流模拟。"
		if not data.get("storyState",{}) is Dictionary or not data.get("storyPlan",{}) is Dictionary:return "章节或规划容器无效。"
		if not data.get("storyState",{}).get("beatRead",{}) is Dictionary:return "故事阅读记录格式错误。"
		if str(data.get("storyState",{}).get("tutorialStatus","active")) not in ["active","completed","skipped"]:return "操作教程状态无效。"
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
	var write_world:=true
	if bool(old.get("ok",false)) and validate(old.data).is_empty():
		var previous:Dictionary=old.data.duplicate(true);previous.erase("savedAt")
		var next:Dictionary=current.duplicate(true);next.erase("savedAt")
		# JSON reads numbers as floats; compare the same persisted representation.
		# Timed and manual saves update one current slot. `rotate` is retained for
		# callers from older builds, but no longer creates timestamped auto files.
		if JSON.stringify(previous)==JSON.stringify(next):
			write_world=false;current["savedAt"]=str(old.data.get("savedAt",current.savedAt))
		else:
			var backup:=_write_atomic(path+".bak",str(old.text))
			if not bool(backup.ok):return backup
	elif FileAccess.file_exists(path) and old.has("text"):
		var preserved:=_preserve_original(str(old.text),"replaced_corrupt")
		if not bool(preserved.get("ok",false)):return preserved
	var result:Dictionary={"ok":true}
	if write_world:
		result=_write_atomic(path,text)
		if not bool(result.ok):return result
	var index_path:=root_path().path_join("last_game.json");var prior_index:=_read(index_path)
	var index_is_current:=bool(prior_index.get("ok",false)) and _index_usable(prior_index.data) and str(prior_index.data.get("gameId",""))==id
	if not index_is_current:
		if bool(prior_index.get("ok",false)) and _index_usable(prior_index.data):
			result=_write_atomic(index_path+".bak",str(prior_index.text))
			if not bool(result.ok):return {"ok":false,"error":"进度已写入，但继续索引备份失败，请重试。"}
		elif FileAccess.file_exists(index_path) and prior_index.has("text"):
			var preserved_index:=_preserve_original(str(prior_index.text),"replaced_continue_index")
			if not bool(preserved_index.get("ok",false)):return preserved_index
		result=_write_atomic(index_path,JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION,"gameId":id}))
		if not bool(result.ok):return {"ok":false,"error":"进度已写入，但继续游戏索引失败，请重试。"}
	var backup_index:=_read(index_path+".bak")
	if not bool(backup_index.get("ok",false)) or not _index_usable(backup_index.data):
		if backup_index.has("text"):
			var preserved_backup:=_preserve_original(str(backup_index.text),"replaced_continue_backup")
			if not bool(preserved_backup.get("ok",false)):return preserved_backup
		result=_write_atomic(index_path+".bak",JSON.stringify({"schemaVersion":WorldData.SAVE_VERSION,"gameId":id}))
		if not bool(result.get("ok",false)):return {"ok":false,"error":"进度已写入，但继续索引恢复备份失败，请重试。"}
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
	if bool(raw.get("ok",false)) and int(raw.data.get("schemaVersion",0))>WorldData.SAVE_VERSION:return {"ok":false,"error":problem,"status":"unsupported"}
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
	if int(raw.data.get("schemaVersion",0))<WorldData.SAVE_VERSION:
		var preserved:=_preserve_original(str(raw.text),"v%d" % int(raw.data.get("schemaVersion",0)))
		if not bool(preserved.ok):return preserved
		var migrated:=migrate(raw.data,str(raw.text))
		_recheck_expanded_projects(migrated)
		if str(migrated.get("storyState",{}).get("phase","")) in ["history_gap","history_content_gap","future_gap"]:
			_resume_expanded_history(migrated.storyState,str(migrated.get("cityId","")),str(migrated.get("mode","")))
		problem=validate(migrated)
		return {"ok":problem.is_empty(),"error":problem,"world":migrated,"migrated":true}
	# Content catalogs evolve independently of the save schema. Old saves with
	# a persisted gap phase must resume into the first new dated chapter even
	# when their data format is already current.
	var loaded_world:Dictionary=raw.data.duplicate(true)
	var content_recheck:=_recheck_expanded_projects(loaded_world)
	if bool(content_recheck.get("changed",false)):
		var preserved:=_preserve_original(str(raw.text),"content_upgrade")
		if not bool(preserved.get("ok",false)):return preserved
	var resumed_phase:=str(loaded_world.get("storyState",{}).get("phase",""))
	if resumed_phase in ["history_gap","history_content_gap","future_gap"]:
		var loaded_state:Dictionary=loaded_world.storyState
		_resume_expanded_history(loaded_state,str(loaded_world.get("cityId","")),str(loaded_world.get("mode","")))
		loaded_world["storyState"]=loaded_state
	return {"ok":true,"world":loaded_world}

static func _recheck_expanded_projects(world:Dictionary) -> Dictionary:
	if str(world.get("mode",""))!="campaign":return {"changed":false}
	var state:Dictionary=world.get("storyState",{})
	if str(state.get("scopeContentRevision",""))==CampaignSystem.content_revision():return {"changed":false}
	var story=load("res://scripts/story_session.gd")
	var changed:=false
	var completed:Array=state.get("completedChapterIds",[])
	var progress:Dictionary=state.get("chapterTaskProgress",{})
	var definitions:Array=[]
	for row in CampaignSystem.city_config(str(world.get("cityId",""))).get("chapters",[]):definitions.append({"phase":"history","definition":row})
	for row in CampaignSystem.city_config(str(world.get("cityId",""))).get("futurePlans",[]):definitions.append({"phase":"future","definition":row})
	var history_reopened:=str(state.get("phase","history")) in ["history","history_gap","history_content_gap"]
	for entry in definitions:
		var plan:Dictionary=entry.definition
		var id:=str(plan.get("id",""))
		if not completed.has(id) or not bool(plan.get("requiresScopeRecheck",false)):continue
		var old:Dictionary=progress.get(id,{})
		var scope_revision:=_chapter_scope_revision(plan)
		if str(old.get("scopeRevision",""))==scope_revision:continue
		var probe:Dictionary=world.duplicate(false)
		probe["storyState"]=state.duplicate(true)
		probe.storyState["phase"]=str(entry.phase);probe.storyState["chapterId"]=id;probe.storyState["stage"]="build"
		var checked:Dictionary=story.evaluate(probe)
		var official_errors:=OfficialNetworkAudit.current_project_errors(probe,plan.get("projectIds",[]))
		if str(plan.get("chapterScope",""))=="cutoff_reconciliation":official_errors.append_array(OfficialNetworkAudit.cutoff_errors(probe))
		if str(entry.phase)=="future" and not bool(plan.get("requireOpen",true)) and not _planning_statuses_match(world,checked.get("routes",[])):
			official_errors.append("规划区间开放状态需重新确认，不能把旧版开放标记直接沿用为真实开通。")
		if bool(checked.get("complete",false)) and official_errors.is_empty():
			old["scopeRevision"]=scope_revision;progress[id]=old
		else:
			var archived:Dictionary=state.get("legacyTaskProgress",{})
			archived[id]=old.duplicate(true);state["legacyTaskProgress"]=archived
			completed.erase(id)
			progress[id]={"status":"needs_scope_recheck","tasks":{},"previousScopeRetained":true}
			if str(entry.phase)=="history":history_reopened=true
			state["phase"]="history_gap" if history_reopened else "future_gap";state["chapterId"]="";state["stage"]="intro"
		changed=true
	state["scopeContentRevision"]=CampaignSystem.content_revision()
	state["completedChapterIds"]=completed;state["chapterTaskProgress"]=progress
	world["storyState"]=state
	if changed:world["contentUpgradeNotice"]="项目范围已补充。原路网与历史里程碑保留；只重新检查新增站点、区段和闭环。"
	return {"changed":changed}

static func _planning_statuses_match(world:Dictionary,expected_routes:Array) -> bool:
	for expected in expected_routes:
		for wanted_direction in expected.get("directions",[]):
			var wanted:Array=wanted_direction.get("stationIds",[])
			var desired:Array=wanted_direction.get("serviceStatusBySegment",[])
			if wanted.size()<2 or desired.size()!=wanted.size()-1:return false
			var found:=false
			for route in world.get("routes",[]):
				if bool(route.get("retired",false)) or str(route.get("historicalLineId",""))!=str(expected.get("historicalLineId","")):continue
				if str(route.get("constructionVariantId",""))!=str(expected.get("constructionVariantId","")):continue
				for direction in route.get("directions",[]):
					var ids:Array=direction.get("stationIds",[])
					var statuses:Array=direction.get("serviceStatusBySegment",[])
					if statuses.size()!=ids.size()-1:continue
					for offset in range(maxi(0,ids.size()-wanted.size()+1)):
						var section:=ids.slice(offset,offset+wanted.size())
						var reversed:=wanted.duplicate();reversed.reverse()
						if section!=wanted and section!=reversed:continue
						var current:=statuses.slice(offset,offset+wanted.size()-1)
						if section==reversed:current.reverse()
						if current==desired:found=true
			if not found:return false
	return true

static func _chapter_scope_revision(plan:Dictionary) -> String:
	return CampaignSystem.chapter_scope_revision(plan)

static func _preserve_original(text: String, prefix: String) -> Dictionary:
	var path:=root_path().path_join("originals").path_join("%s_%s.json" % [prefix,text.sha256_text()])
	if FileAccess.file_exists(path):return {"ok":true,"path":path}
	return _write_atomic(path,text)

static func migrate(data: Dictionary, original_text: String = "") -> Dictionary:
	var result:=data.duplicate(true)
	var old_version:=int(data.get("schemaVersion",0))
	result["schemaVersion"]=WorldData.SAVE_VERSION
	if not (result.get("serviceRanges",null) is Array):result["serviceRanges"]=[]
	_upgrade_station_complexes(result)
	if old_version>=19 and old_version<WorldData.SAVE_VERSION:
		result["referenceDataVersion"]=ReferenceAlignment.version()
		if not (result.get("storyState",null) is Dictionary):
			result["storyState"]={"chapterIndex":0,"chapterId":"","stage":"intro","completedChapterIds":[],"milestones":[],"chapterTaskProgress":{},"confirmedHistoricalEventIds":[],"tutorialEnabled":false,"tutorialStatus":"skipped","beatRead":{},"learnedTools":true,"assistedChapters":[],"catalogVersion":CampaignSystem.content_version(),"phase":"history","freeUnlocked":false}
		var story_state:Dictionary=result.storyState
		if not (story_state.get("chapterTaskProgress",null) is Dictionary):story_state["chapterTaskProgress"]={}
		if not (story_state.get("confirmedHistoricalEventIds",null) is Array):story_state["confirmedHistoricalEventIds"]=[]
		CampaignSystem.backfill_story_milestone_records(story_state,str(result.get("cityId","")))
		_resume_expanded_history(story_state,str(result.get("cityId","")),str(result.get("mode","")))
		result["storyState"]=story_state
		if not (result.get("storyPlan",null) is Dictionary):result["storyPlan"]={"planIndex":0,"pathChoices":{}}
		if not (result.get("history",null) is Dictionary):result["history"]={"undo":[],"redo":[]}
		result["migrationNotice"]="已独立备份格式%d原档。既有路网、故事步骤、里程碑、任务记录和撤销历史保持原位；新增换乘关系不会从同名或相邻站点推断。" % old_version
		return result
	if old_version==18:
		var state: Dictionary=result.get("storyState",{})
		if not StoryTutorial.is_first(result) or str(state.get("stage",""))=="outcome":
			var chapters:Array=CampaignSystem.city_config(str(result.get("cityId",""))).get("chapters",[])
			var first_build_id:=CampaignSystem.first_chapter_id(str(result.get("cityId","")))
			var completed_teaching:bool=bool(state.get("tutorialEnabled",false)) and not first_build_id.is_empty() and state.get("completedChapterIds",[]).has(first_build_id)
			state["tutorialEnabled"]=false;state["tutorialStatus"]="completed" if completed_teaching else "skipped";state["learnedTools"]=true
		else:state["tutorialStatus"]="active" if bool(state.get("tutorialEnabled",false)) else "skipped"
		state["beatRead"]={}
		if not (state.get("chapterTaskProgress",null) is Dictionary):state["chapterTaskProgress"]={}
		if not (state.get("confirmedHistoricalEventIds",null) is Array):state["confirmedHistoricalEventIds"]=[]
		CampaignSystem.backfill_story_milestone_records(state,str(result.get("cityId","")))
		_resume_expanded_history(state,str(result.get("cityId","")),str(result.get("mode","")))
		result["storyState"]=state
		result["migrationNotice"]="已备份格式18原档。路网、已完成里程碑和历史保持；新增章内任务与稳定事件编号已初始化，操作引导仅在首章继续。"
		return result
	result["gameId"]="legacy_%s" % (original_text if not original_text.is_empty() else JSON.stringify(data)).sha256_text().substr(0,20)
	result["mode"]="campaign" if str(data.get("mode",""))=="campaign" else "workshop"
	result["title"]="%s · %s" % [str(data.get("cityName",data.get("cityId","城市"))),"历史进度" if result.mode=="campaign" else "旧路网作品"]
	var sim:Dictionary=data.get("simulation",{}) if data.get("simulation",{}) is Dictionary else {}
	result["legacyArchive"]={"sourceVersion":old_version,"completed":sim.get("completed",0),"elapsedSeconds":sim.get("elapsedSeconds",int(sim.get("elapsedMinutes",0))*60),"oldHistorySteps":data.get("history",{}).get("undo",[]).size(),"note":"原始文件已独立归档。原客流仅作历史记录，不继续运行。"}
	for key in ["simulation","goalBoard","cityProgression","challengeState","challengeMode","onboarding","tutorialStep","tutorialDone","fleetMode"]:result.erase(key)
	var old:Dictionary=data.get("campaignState",{})
	result["storyState"]={"chapterIndex":0,"chapterId":"","stage":"intro","completedChapterIds":[],"milestones":[],"chapterTaskProgress":{},"confirmedHistoricalEventIds":[],"tutorialEnabled":false,"tutorialStatus":"skipped","beatRead":{},"learnedTools":true,"assistedChapters":[],"catalogVersion":CampaignSystem.content_version(),"phase":"history","freeUnlocked":false,"legacyMilestones":old.get("completedChapterIds",[])}
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

static func _resume_expanded_history(state:Dictionary,city_id:String,mode:String) -> void:
	if mode!="campaign" or str(state.get("phase","history")) not in ["history","history_gap","history_content_gap","future_gap"]:return
	var chapters:Array=CampaignSystem.city_config(city_id).get("chapters",[])
	if chapters.is_empty():return
	var current_id:=str(state.get("chapterId",""))
	var current_index:=-1
	for index in range(chapters.size()):
		if str(chapters[index].get("id",""))==current_id:current_index=index;break
	var gap:=str(state.get("phase","")) in ["history_gap","history_content_gap","future_gap"] or current_index<0 or int(state.get("chapterIndex",0))>=chapters.size()
	if not gap:
		state["chapterIndex"]=current_index
		return
	var completed:Array=state.get("completedChapterIds",[]) if state.get("completedChapterIds",[]) is Array else []
	for index in range(chapters.size()):
		var chapter_id:=str(chapters[index].get("id",""))
		if completed.has(chapter_id):continue
		# Resume by stable chapter identity, never by date. Both construction
		# chapters and source-backed milestone events are actionable. Skipping an
		# event-only node here made old boundary saves appear permanently stuck.
		state["phase"]="history";state["chapterIndex"]=index;state["chapterId"]=chapter_id
		state["stage"]="intro";state["tutorialEnabled"]=false
		return
	var future_plans:Array=CampaignSystem.playable_future_plans(city_id)
	for plan_index in range(future_plans.size()):
		var plan:Dictionary=future_plans[plan_index]
		if completed.has(str(plan.get("id",""))):continue
		state["phase"]="future";state["chapterIndex"]=plan_index;state["chapterId"]=str(plan.get("id",""));state["stage"]="intro";state["tutorialEnabled"]=false
		return
	state["phase"]="history_content_gap" if str(CampaignSystem.city_config(city_id).get("historyStatus","partial"))=="route_inventory_complete" else "future_gap"
	state["chapterIndex"]=chapters.size();state["chapterId"]="";state["stage"]="intro"

static func _upgrade_station_complexes(result:Dictionary) -> void:
	if not result.has("stationComplexes") or not result.get("stationComplexes",[]) is Array:result["stationComplexes"]=[]
	if not result.has("transferConnections") or not result.get("transferConnections",[]) is Array:result["transferConnections"]=[]
	var complexes:Dictionary={}
	var used_instances:Dictionary={}
	for complex in result.get("stationComplexes",[]):
		if complex is Dictionary:complexes[str(complex.get("id",""))]=complex
	for station in result.get("stations",[]):
		if not station is Dictionary:continue
		var historical_id:=str(station.get("historicalId",""))
		var instance_id:=str(station.get("stationInstanceId",station.get("id","")))
		if instance_id.is_empty() or used_instances.has(instance_id):instance_id=str(station.get("id",""))
		station["stationInstanceId"]=instance_id;used_instances[instance_id]=true
		var complex_id:=str(station.get("stationComplexId",historical_id))
		station["stationComplexId"]=complex_id
		if not complex_id.is_empty() and not complexes.has(complex_id):
			var complex:Dictionary={"id":complex_id,"name":str(station.get("name","历史站区")),"locationPrecision":"station_area_approximation","structureStatus":"legacy_unresolved"}
			result.stationComplexes.append(complex);complexes[complex_id]=complex

static func _index_usable(data:Dictionary) -> bool:
	if data.has("stations"):return validate(data).is_empty()
	var version:=int(data.get("schemaVersion",0))
	return version>=18 and version<=WorldData.SAVE_VERSION and valid_id(str(data.get("gameId","")))

static func load_last_game(confirm_recovery:bool=false) -> Dictionary:
	var index_path:=root_path().path_join("last_game.json")
	var index:=_read(index_path)
	if bool(index.get("ok",false)) and int(index.data.get("schemaVersion",0))>WorldData.SAVE_VERSION:return {"ok":false,"status":"unsupported","error":"继续进度来自更新版本，无法载入。"}
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

static func delete_legacy_auto_history(path:String) -> Dictionary:
	if root_path().is_empty() or not path.ends_with(".json"):return {"ok":false,"error":"无效的旧版自动历史文件。"}
	var root:=ProjectSettings.globalize_path(root_path().path_join("auto_history")).simplify_path()
	var target:=ProjectSettings.globalize_path(path).simplify_path()
	var prefix:=root+"/"
	if not target.begins_with(prefix):return {"ok":false,"error":"文件不在旧版自动历史目录中。"}
	var relative:=target.trim_prefix(prefix).split("/",false)
	if relative.size()!=2:return {"ok":false,"error":"无效的旧版自动历史路径。"}
	for part in relative:
		if part in [".",".."]:return {"ok":false,"error":"无效的旧版自动历史路径。"}
	var error:=DirAccess.remove_absolute(target)
	return {"ok":error==OK,"error":"无法删除该旧版自动历史：%s" % error_string(error) if error!=OK else ""}

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
