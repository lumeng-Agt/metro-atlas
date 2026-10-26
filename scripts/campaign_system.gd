class_name CampaignSystem
extends RefCounted

const CATALOG_PATH := "res://data/campaigns.json"
const NETWORK_BASELINE_PATH := "res://data/network_baselines_2026-10-01.json"
const OFFICIAL_TARGET_PATH := "res://data/official_targets_2026-10-01.json"
const Engineering = preload("res://scripts/engineering_construction.gd")
const SharedRunning = preload("res://scripts/shared_running_audit.gd")
static var _catalog: Dictionary = {}
static var _network_baseline: Dictionary = {}
static var _known_station_ids_by_city: Dictionary = {}

static func published_inventory_errors(target:Dictionary,cutoff_date:String) -> Array[String]:
	var reasons:Array[String]=[]
	var requirements:Array=target.get("projects",[])
	if str(target.get("inventoryReviewStatus",""))=="verified" and target.get("sourceProjectInventory",[]).is_empty():reasons.append("官方清单核对标记没有对应的独立项目记录。")
	var inventoried:Dictionary={}
	for row in target.get("sourceProjectInventory",[]):
		var project_id:=str(row.get("projectId",""))
		if project_id.is_empty() or inventoried.has(project_id):reasons.append("官方项目清单缺少稳定身份或存在重复。")
		inventoried[project_id]=true
		if not str(row.get("source","")).begins_with("https://") or str(row.get("sourcePublicationDate","")).is_empty() or str(row.get("sourcePublicationDate",""))>cutoff_date:reasons.append("项目%s的清单证据缺失或晚于截止日。"%project_id)
		if bool(row.get("required",true)) and (not target.get("requiredProjectIds",[]).has(project_id) or requirements.filter(func(p:Dictionary):return str(p.get("id",""))==project_id and not bool(p.get("optional",false))).size()!=1):reasons.append("官方已列入的必做项目%s缺少独立建设目标。"%project_id)
	return reasons

static func delivery_eligibility(city_id:String) -> Dictionary:
	var reasons:Array[String]=[]
	var file:=FileAccess.open(OFFICIAL_TARGET_PATH,FileAccess.READ)
	if file==null:return {"ok":false,"reasons":["缺少独立官方目标清单。"]}
	var parsed:Variant=JSON.parse_string(file.get_as_text());file.close()
	if not parsed is Dictionary:return {"ok":false,"reasons":["官方目标清单格式无效。"]}
	var target:Dictionary=parsed.get("cities",{}).get(city_id,{})
	if str(target.get("inventoryReviewStatus",""))!="verified":reasons.append("截止日项目与路网清单尚未完成独立核对。")
	if str(target.get("historyReviewStatus",""))!="verified" or target.get("historicalMilestones",[]).is_empty():reasons.append("各历史里程碑的官方范围尚未全部核对。")
	var cutoff:Dictionary=target.get("cutoffNetwork",{})
	if cutoff.get("groups",[]).is_empty() or str(cutoff.get("date",""))!=str(parsed.get("cutoffDate","2026-10-01")):reasons.append("缺少对应截止日的独立站序目标。")
	if str(cutoff.get("temporalReviewStatus",""))!="verified" or cutoff.get("temporalEvidence",[]).is_empty():reasons.append("截止日开放范围缺少独立日期证据，现行时刻表不能代替。")
	if str(cutoff.get("transferReviewStatus",""))!="verified":reasons.append("截止日全量换乘联系尚未完成独立核对。")
	if str(cutoff.get("sharedRunningReviewStatus","verified"))!="verified":reasons.append("截止日共线运行的实际轨道关系尚未核对完成。")
	reasons.append_array(SharedRunning.definition_errors(cutoff))
	for evidence in cutoff.get("temporalEvidence",[]):
		if str(evidence.get("source","")).is_empty() or str(evidence.get("effectiveDate","")).is_empty() or str(evidence.get("effectiveDate",""))>str(parsed.get("cutoffDate","2026-10-01")):reasons.append("截止日证据缺失或包含后期开通。")
	var campaign:=city_config(city_id)
	var cutoff_plans:Array=campaign.get("chapters",[]).filter(func(plan:Dictionary):return str(plan.get("id",""))==str(cutoff.get("chapterId","")))
	for definition in cutoff.get("transferDefinitions",[]):
		var pairs:Array=[]
		for plan in cutoff_plans:
			pairs.append_array(plan.get("requiredTransfers",[]).filter(func(pair:Dictionary):return str(pair.get("id",""))==str(definition.get("id",""))))
		if pairs.size()!=1 or str(definition.get("id","")).is_empty() or not str(definition.get("source","")).begins_with("https://"):reasons.append("独立换乘结构缺失或重复。");continue
		if pairs[0].get("lineIds",[])!=definition.get("lineIds",[]) or pairs[0].get("stationInstanceIds",[])!=definition.get("stationInstanceIds",[]) or str(pairs[0].get("complexId",""))!=str(definition.get("complexId","")) or str(pairs[0].get("transferKind","interchange"))!=str(definition.get("transferKind","interchange")):reasons.append("%s的站内／出站换乘结构与独立证据不符。"%str(definition.get("name","换乘站")))
	var requirements:Array=target.get("projects",[])
	reasons.append_array(published_inventory_errors(target,str(parsed.get("cutoffDate","2026-10-01"))))
	for project_id in target.get("requiredProjectIds",[]):
		if not requirements.any(func(p:Dictionary):return str(p.get("id",""))==str(project_id) and not bool(p.get("optional",false))):reasons.append("项目%s缺少独立建设目标。" % str(project_id))
	for requirement in requirements:
		if bool(requirement.get("optional",false)):continue
		var project_id:=str(requirement.get("id",""))
		if str(requirement.get("reviewStatus",""))!="verified" or str(requirement.get("source",""))=="" or str(requirement.get("sourcePublicationDate",""))=="":reasons.append("项目%s的官方范围尚未核对。" % project_id)
		if str(requirement.get("transferReviewStatus","verified"))!="verified":reasons.append("项目%s的完整换乘范围尚未核对。" % project_id)
		var matching:Array=campaign.get("futurePlans",[]).filter(func(p:Dictionary):return p.get("projectIds",[]).has(project_id))
		var passage:bool=str(requirement.get("operationType",""))=="transfer_connection" and not requirement.get("reservedTransfers",[]).is_empty() and matching.all(func(plan:Dictionary):return pedestrian_reservation_task(plan,city_id))
		if matching.is_empty() or (requirement.get("groups",[]).is_empty() and not passage):reasons.append("项目%s缺少可玩建设目标。" % project_id)
		var actual_groups:Array=[]
		for plan in matching:actual_groups.append_array(plan.get("lineGroups",[]))
		for required_transfer in requirement.get("transfers",[]):
			if not matching.any(func(plan:Dictionary):return plan.get("requiredTransfers",[]).any(func(relation:Dictionary):return str(relation.get("id",""))==str(required_transfer))):reasons.append("项目%s缺少必要换乘目标。" % project_id)
		for reserved in requirement.get("reservedTransfers",[]):
			var reservation_found:bool=matching.any(func(plan:Dictionary):return not bool(plan.get("requireOpen",true)) and plan.get("requiredTransfers",[]).any(func(relation:Dictionary):return relation.get("status")=="reserved" and relation.get("id")==reserved.get("id") and relation.get("lineIds")==reserved.get("lineIds") and relation.get("stationInstanceIds")==reserved.get("stationInstanceIds") and relation.get("reservationEvidence")==reserved.get("reservationEvidence") and relation.get("reservationKind")==reserved.get("reservationKind") and relation.get("source")==reserved.get("source") and not str(relation.get("reservationEvidence","")).is_empty()))
			if not reservation_found:reasons.append("项目%s缺少明确的预留换乘接口，或误记为已经开放。"%project_id)
		for expected in requirement.get("groups",[]):
			var matching_groups:Array=actual_groups.filter(func(g:Dictionary):return str(g.get("coverageGroupId",g.get("historicalLineId","")))==str(expected.get("id","")))
			if matching_groups.size()!=1:reasons.append("项目%s的区段范围不完整。" % project_id);continue
			var group:Dictionary=matching_groups[0]
			if str(expected.get("scopeType",""))=="engineering":
				reasons.append_array(Engineering.coverage_errors(group,expected))
				continue
			var names:Array=[]
			for station_id in group.get("stationIds",[]):
				var name:=str(group.get("stationNames",{}).get(str(station_id),""))
				if name.is_empty():
					for station in WorldData.city(city_id).get("stations",[]):
						if str(station.get("id",""))==str(station_id):name=str(station.get("name",""));break
				names.append(name)
			if str(expected.get("scopeType","stations"))=="stations":
				var wanted:Array=expected.get("stationNames",[])
				var matches:bool=names==wanted
				if bool(expected.get("allowReverse",false)):
					var reversed:=wanted.duplicate();reversed.reverse();matches=matches or names==reversed
				if str(expected.get("matchScope",""))=="contiguous_subsequence" and not wanted.is_empty():
					var reverse_wanted:=wanted.duplicate();reverse_wanted.reverse()
					for start in range(maxi(0,names.size()-wanted.size()+1)):
						var section:=names.slice(start,start+wanted.size())
						if section==wanted or (bool(expected.get("allowReverse",false)) and section==reverse_wanted):matches=true
				if wanted.is_empty() or not matches:reasons.append("项目%s仍有缺站或站序差异。" % project_id)
			else:
				if str(expected.get("unpublishedStationOrderEvidence",""))=="":reasons.append("项目%s的走廊验收缺少依据。" % project_id)
				for name in expected.get("requiredPlaces",[]):
					if not names.has(name):reasons.append("项目%s缺少必经区域。" % project_id)
			if bool(group.get("loop",false))!=bool(expected.get("loop",false)):reasons.append("项目%s的闭环关系不完整。" % project_id)
	return {"ok":reasons.is_empty(),"reasons":reasons}

static func load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		_catalog = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_catalog = parsed if parsed is Dictionary else {}
	var baseline_file := FileAccess.open(NETWORK_BASELINE_PATH, FileAccess.READ)
	if baseline_file == null:
		_network_baseline = {}
	else:
		var baseline_value: Variant = JSON.parse_string(baseline_file.get_as_text())
		baseline_file.close()
		_network_baseline = baseline_value if baseline_value is Dictionary else {}

static func cutoff_date() -> String:
	return str(_catalog.get("cutoffDate", "2026-10-01"))

static func content_version() -> String:
	if _catalog.is_empty():load_catalog()
	return str(_catalog.get("contentVersion","unknown"))

static func content_revision() -> String:
	if _catalog.is_empty():load_catalog()
	return str(_catalog.get("contentRevision","unknown"))

static func city_config(city_id: String) -> Dictionary:
	if _catalog.is_empty(): load_catalog()
	return _catalog.get("cities", {}).get(city_id, {}).duplicate(true)

## A tool/label query needs one chapter, not a copy of every historical and
## future construction object in the city. Still return an isolated definition:
## callers and preview candidates must never mutate the source catalogue.
static func story_chapter_definition(city_id:String,state:Dictionary) -> Dictionary:
	if _catalog.is_empty():load_catalog()
	var phase:=str(state.get("phase","history"))
	if phase in ["future_gap","published_content_complete","free"]:return {}
	var city:Dictionary=_catalog.get("cities",{}).get(city_id,{})
	var rows:Array=city.get("futurePlans",[]) if phase=="future" else city.get("chapters",[])
	var stable_id:=str(state.get("chapterId",""))
	var completed:Array=state.get("completedChapterIds",[])
	var is_gap:=phase in ["history_gap","history_content_gap"]
	if not stable_id.is_empty():
		for entry in rows:
			if str(entry.get("id",""))!=stable_id:continue
			if phase=="future" and (not bool(entry.get("required",false)) or not future_data_ready(entry,WorldData.city(city_id))):continue
			if not is_gap or not completed.has(stable_id):return entry.duplicate(true)
		if not is_gap:return {}
	if phase=="future":
		var eligible:Array=[]
		for entry in rows:
			if bool(entry.get("required",false)) and future_data_ready(entry,WorldData.city(city_id)):eligible.append(entry)
		rows=eligible
	var index:=int(state.get("chapterIndex",0))
	if is_gap or index<0 or index>=rows.size():
		for entry in rows:
			if not completed.has(str(entry.get("id",""))):return entry.duplicate(true)
	return rows[index].duplicate(true) if index>=0 and index<rows.size() else {}

## Several source map extracts represent the same interchange/renamed station
## with different OSM IDs. These explicit content aliases preserve one stable
## station-complex identity while keeping each line's physical station body.
static func canonical_station_complex(city_id: String, station_id: String) -> String:
	if _catalog.is_empty(): load_catalog()
	var aliases: Dictionary = _catalog.get("cities", {}).get(city_id, {}).get("stationComplexAliases", {})
	var current := station_id
	var visited: Dictionary = {}
	while aliases.has(current) and not visited.has(current):
		visited[current] = true
		current = str(aliases[current])
	return current

static func station_instance_alias(group: Dictionary, station_id: String) -> String:
	if _catalog.is_empty(): load_catalog()
	var line_id := str(group.get("historicalLineId", ""))
	var station_city := station_id.get_slice("-", 0)
	var aliases: Dictionary = _catalog.get("cities", {}).get(station_city, {}).get("stationInstanceAliases", {})
	return str(aliases.get("%s|%s" % [line_id, station_id], ""))

static func network_coverage(city_id: String) -> Dictionary:
	if _catalog.is_empty() or _network_baseline.is_empty(): load_catalog()
	var baseline: Dictionary = _network_baseline.get("cities", {}).get(city_id, {})
	var city: Dictionary = WorldData.city(city_id)
	var campaign: Dictionary = _catalog.get("cities", {}).get(city_id, {})
	if baseline.is_empty() or city.is_empty(): return {}
	var chapter_targets: Dictionary = {}
	for chapter in campaign.get("chapters", []):
		var groups: Array = chapter.get("lineGroups", []).duplicate()
		for version in chapter.get("story", {}).get("planVersions", []): groups.append_array(version.get("lineGroups", []))
		for group in groups:
			for station_id in group.get("stationIds", []): chapter_targets[str(station_id)] = true
	var map_station_ids: Dictionary = {}
	var full_routes := 0
	var partial_routes := 0
	var uncovered_routes := 0
	var uncovered_route_names: Array[String] = []
	for route in baseline.get("routes", []):
		var route_ids: Array = route.get("cutoffStationIds", [])
		var matched := 0
		for station_id in route_ids:
			map_station_ids[str(station_id)] = true
			if chapter_targets.has(str(station_id)): matched += 1
		if not route_ids.is_empty() and matched == route_ids.size(): full_routes += 1
		elif matched > 0: partial_routes += 1
		else:
			uncovered_routes += 1
			uncovered_route_names.append(str(route.get("name", route.get("ref", route.get("mapRouteId", "线路")))))
	var milestone_chapters: Array = baseline.get("milestoneChapters", [])
	var pending_milestones: Array[Dictionary] = []
	var playable_chapter_ids: Dictionary = {}
	for chapter in campaign.get("chapters", []): playable_chapter_ids[str(chapter.get("id", ""))] = true
	for event in baseline.get("documentedMilestones", []):
		var chapter_id := str(event.get("chapterId", ""))
		if not chapter_id.is_empty() and playable_chapter_ids.has(chapter_id): continue
		pending_milestones.append({"id":str(event.get("id", "")), "date":str(event.get("date", "")), "title":str(event.get("title", "历史节点")), "source":str(event.get("source", "")), "routeIds":event.get("routeIds", [])})
	var pending_intervals: Array[Dictionary] = []
	for milestone_chapter in milestone_chapters:
		if str(milestone_chapter.get("contentStatus", "")) != "content_missing": continue
		pending_intervals.append(milestone_chapter.duplicate(true))
	var project_ids_with_playable_tasks: Dictionary = {}
	for plan_value in campaign.get("futurePlans", []):
		if not plan_value is Dictionary: continue
		var project_ids: Variant = plan_value.get("projectIds", [])
		if not project_ids is Array or project_ids.is_empty(): continue
		if not future_data_ready(plan_value, city): continue
		for project_id in project_ids: project_ids_with_playable_tasks[str(project_id)] = true
	var projects: Array = baseline.get("projectsAtCutoff", [])
	var playable_project_count := 0
	for project_value in projects:
		if project_value is Dictionary and project_ids_with_playable_tasks.has(str(project_value.get("id", ""))): playable_project_count += 1
	var targeted_count := 0
	for station_id in map_station_ids:
		if chapter_targets.has(str(station_id)): targeted_count += 1
	return {
		"cutoffDate": str(_network_baseline.get("cutoffDate", "2026-10-01")),
		"officialRouteCount": baseline.get("officialRouteCount"),
		"officialStationCount": baseline.get("officialStationCount"),
		"countBasis": str(baseline.get("countBasis", "")),
		"stationCountBasis": str(baseline.get("stationCountBasis", "")),
		"mapRouteEntryCount": int(baseline.get("mapRouteEntryCount", 0)),
		"mapRouteStopOccurrenceCount": int(baseline.get("mapRouteStopOccurrenceCount", 0)),
		"mapUniqueStationCount": map_station_ids.size(),
		"chapterCount": campaign.get("chapters", []).size(),
		"fullyTargetedRouteEntryCount": full_routes,
		"partiallyTargetedRouteEntryCount": partial_routes,
		"uncoveredRouteEntryCount": uncovered_routes,
		"uncoveredRouteNames": uncovered_route_names,
		"targetedStationCount": targeted_count,
		"documentedMilestones": int(baseline.get("documentedMilestoneCount", 0)),
		"milestoneChapters": milestone_chapters.duplicate(true),
		"milestoneChapterCount": milestone_chapters.size(),
		"playableMilestoneCount": milestone_chapters.filter(func(item: Dictionary): return str(item.get("contentStatus", "")) in ["playable_sample", "playable_milestone", "network_reconciliation_complete"]).size(),
		"missingMilestoneCount": milestone_chapters.filter(func(item: Dictionary): return str(item.get("contentStatus", "")) in ["content_missing", "network_reconciliation_missing"]).size(),
		"pendingMilestones": pending_milestones,
		"pendingMilestoneIntervals": pending_intervals,
		"projectsAtCutoff": projects,
		"projectInventoryCount": projects.size(),
		"playableProjectCount": playable_project_count,
		"pendingPlayableProjectCount": maxi(0, projects.size() - playable_project_count),
		"sources": baseline.get("sources", []),
	}

static func milestone_interval(city_id: String, chapter_id: String) -> Dictionary:
	if _catalog.is_empty() or _network_baseline.is_empty(): load_catalog()
	var rows: Array = _network_baseline.get("cities", {}).get(city_id, {}).get("milestoneChapters", [])
	for row in rows:
		if str(row.get("playableChapterId", "")) == chapter_id or row.get("chapterIds", []).has(chapter_id):
			return row.duplicate(true)
	return {}

static func group_scope_fingerprint(group:Dictionary) -> String:
	var normalized:=group.duplicate(true)
	var ids:Array=normalized.get("stationIds",[])
	if bool(normalized.get("loop",false)) and ids.size()>2 and ids.front()!=ids.back():ids.append(ids.front())
	return JSON.stringify(normalized).sha256_text()

static func chapter_scope_revision(plan:Dictionary) -> String:
	# Author revision and actual scope are both required: a forgotten manual
	# bump cannot hide expanded station/section/transfer requirements.
	var scope:Dictionary={}
	for key in ["lineGroups","requiredTransfers","requiredConnections","serviceTransitions","scopeCorrections"]:
		scope[key]=plan.get(key,[])
	var result:=str(plan.get("scopeRevision",""))+":"+JSON.stringify(scope).sha256_text()
	if str(plan.get("chapterScope",""))=="cutoff_reconciliation":result+=":historical-status-v2"
	return result

static func chapter_task_records(city_id: String, chapter_id: String) -> Dictionary:
	var result: Dictionary = {}
	var chapter_row: Dictionary = {}
	var definitions:Array=city_config(city_id).get("chapters",[]).duplicate()
	definitions.append_array(city_config(city_id).get("futurePlans",[]))
	for candidate in definitions:
		if str(candidate.get("id", "")) == chapter_id: chapter_row = candidate; break
	if chapter_row.is_empty(): return result
	for group in chapter_row.get("lineGroups", []):
		var line_id := str(group.get("historicalLineId", group.get("id", "line")))
		var task_id := str(group.get("taskId", "line:" + line_id))
		result[task_id] = {"status":"confirmed", "type":"engineering_track" if Engineering.is_group(group) else "line_group", "historicalLineId":line_id,"scopeFingerprint":group_scope_fingerprint(group)}
	for transition in chapter_row.get("serviceTransitions", []):
		var transition_id := str(transition.get("id", transition.get("historicalLineId", "service")))
		result["service:" + transition_id] = {"status":"confirmed", "type":"service_range", "historicalLineId":str(transition.get("historicalLineId", ""))}
	for transfer in chapter_row.get("requiredTransfers", []):
		var transfer_id := str(transfer.get("id", transfer.get("complexId", "transfer")))
		result["transfer:" + transfer_id] = {"status":"confirmed", "type":"transfer", "complexId":str(transfer.get("complexId", ""))}
	for connection in chapter_row.get("requiredConnections", []):
		var from_id := str(connection.get("fromId", "")); var to_id := str(connection.get("toId", ""))
		result["connection:%s:%s" % [from_id, to_id]] = {"status":"confirmed", "type":"track_connection", "fromId":from_id, "toId":to_id}
	return result

static func backfill_story_milestone_records(story_state: Dictionary, city_id: String) -> void:
	var task_progress: Dictionary = story_state.get("chapterTaskProgress", {}) if story_state.get("chapterTaskProgress", {}) is Dictionary else {}
	var confirmed: Array = story_state.get("confirmedHistoricalEventIds", []) if story_state.get("confirmedHistoricalEventIds", []) is Array else []
	for chapter_id_value in story_state.get("completedChapterIds", []):
		var chapter_id := str(chapter_id_value)
		var interval: Dictionary = milestone_interval(city_id, chapter_id)
		# Do not infer that an old completed sample covered every event in its
		# newly expanded milestone interval. Only inherit event IDs that were
		# explicitly bound to that exact old chapter before the catalog changed.
		var event_ids: Array = []
		for event in _network_baseline.get("cities", {}).get(city_id, {}).get("documentedMilestones", []):
			if str(event.get("chapterId", "")) == chapter_id:
				var event_id:=str(event.get("id", ""))
				if not event_id.is_empty():event_ids.append(event_id)
		if event_ids.is_empty(): event_ids = [chapter_id]
		var normalized: Array = []
		for event_id in confirmed:
			if not normalized.has(str(event_id)): normalized.append(str(event_id))
		for event_id in event_ids:
			if not normalized.has(str(event_id)): normalized.append(str(event_id))
		confirmed = normalized
		if not task_progress.has(chapter_id):
			# Old saves predate stable task records. Keep the chapter milestone,
			# but do not mark every task added by a later catalog expansion as done.
			task_progress[chapter_id] = {"status":"legacy_milestone_confirmed", "confirmedHistoricalEventIds":event_ids.duplicate(), "tasks":{}, "date":str(interval.get("periodEndInclusive", ""))}
	story_state["chapterTaskProgress"] = task_progress
	story_state["confirmedHistoricalEventIds"] = confirmed

static func first_chapter_id(city_id:String) -> String:
	if _catalog.is_empty():load_catalog()
	var chapters:Array=_catalog.get("cities",{}).get(city_id,{}).get("chapters",[])
	for chapter_index in range(chapters.size()):
		var chapter_row:Dictionary=chapters[chapter_index]
		if not bool(chapter_row.get("eventOnly",false)) and not chapter_row.get("lineGroups",[]).is_empty():return str(chapter_row.get("id",""))
	return ""

static func first_chapter_index(city_id:String) -> int:
	if _catalog.is_empty():load_catalog()
	var chapters:Array=_catalog.get("cities",{}).get(city_id,{}).get("chapters",[])
	for chapter_index in range(chapters.size()):
		var chapter_row:Dictionary=chapters[chapter_index]
		if not bool(chapter_row.get("eventOnly",false)) and not chapter_row.get("lineGroups",[]).is_empty():return chapter_index
	return 0 if not chapters.is_empty() else -1

static func future_data_ready(plan: Dictionary, city_data: Dictionary = {}) -> bool:
	# Only plans with a locally audited blueprint may be marked reproduced.
	# Official document links alone are not enough to claim a route was built.
	if str(plan.get("dataStatus", "not_digitized")) != "blueprint_ready": return false
	if str(plan.get("exactAlignment", "not_available")) not in ["station_areas", "corridor_only","verified_alignment"]: return false
	var groups: Variant = plan.get("lineGroups", [])
	if not groups is Array:return false
	if groups.is_empty():return pedestrian_reservation_task(plan,str(city_data.get("id",plan.get("cityId",""))))
	var known_stations: Dictionary = {}
	if not city_data.is_empty():
		for station in city_data.get("stations", []): known_stations[str(station.get("id", ""))] = true
	else:
		known_stations = _known_station_ids_by_city.get(str(plan.get("cityId", "")), {})
	for group_value in groups:
		if not group_value is Dictionary: return false
		if group_value.has("stationNamingSource"):
			var naming_source:Variant=group_value.stationNamingSource
			if not naming_source is String or not (str(naming_source).begins_with("https://") or str(naming_source).begins_with("http://")):return false
			if not bool(group_value.get("constructionVariant",false)) or bool(plan.get("requireOpen",false)):return false
		if Engineering.is_group(group_value):
			if not Engineering.definition_errors(group_value,known_stations.keys()).is_empty():return false
			continue
		var station_ids: Variant = group_value.get("stationIds", [])
		if not station_ids is Array or station_ids.size() < 2: return false
		if float(group_value.get("toleranceM", 0.0)) <= 0.0: return false
		if str(plan.get("exactAlignment",""))=="verified_alignment" and group_value.get("alignment",[]).size()<2:return false
		for station_id in station_ids:
			if not known_stations.is_empty() and not known_stations.has(str(station_id)): return false
	return true

static func pedestrian_reservation_task(plan:Dictionary,city_id:String) -> bool:
	if city_id.is_empty() or not plan.get("lineGroups",[]).is_empty() or bool(plan.get("eventOnly",false)) or str(plan.get("phase",""))!="future" or str(plan.get("operationType",""))!="transfer_connection" or bool(plan.get("requireOpen",true)) or not str(plan.get("source","")).begins_with("https://"):return false
	var pairs:Array=plan.get("requiredTransfers",[]);var seen:Dictionary={}
	if pairs.is_empty():return false
	for pair in pairs:
		var id:=str(pair.get("id",""));var lines:Array=pair.get("lineIds",[]);var bodies:Array=pair.get("stationInstanceIds",[])
		if id.is_empty() or seen.has(id) or lines.size()!=2 or bodies.size()!=2 or lines[0]==lines[1] or bodies[0]==bodies[1] or str(pair.get("status",""))!="reserved" or str(pair.get("reservationKind",""))!="pedestrian_passage" or not str(pair.get("source","")).begins_with("https://") or not str(pair.get("reservationEvidence","")).begins_with("https://"):return false
		for value in lines+bodies:
			if not str(value).begins_with(city_id+"-"):return false
		seen[id]=true
	return true

static func playable_future_plans(city_id: String) -> Array:
	var city_data := WorldData.city(city_id)
	var result: Array = []
	for plan_value in city_config(city_id).get("futurePlans", []):
		if not plan_value is Dictionary: continue
		var plan: Dictionary = plan_value
		if bool(plan.get("required", false)) and future_data_ready(plan, city_data): result.append(plan)
	return result

static func validate_catalog(city_data_list: Array) -> Array[String]:
	if _catalog.is_empty(): load_catalog()
	var errors: Array[String] = []
	var city_ids: Dictionary = {}
	_known_station_ids_by_city.clear()
	for city in city_data_list:
		var city_id := str(city.get("id", ""))
		city_ids[city_id] = city
		var station_id_map: Dictionary = {}
		for station in city.get("stations", []): station_id_map[str(station.get("id", ""))] = true
		_known_station_ids_by_city[city_id] = station_id_map
	for city_id in _catalog.get("cities", {}):
		if not city_ids.has(str(city_id)):
			errors.append("历史资料包引用未知城市：%s" % str(city_id))
			continue
		var city_config_value: Dictionary = _catalog.cities[city_id]
		if str(city_config_value.get("historyStatus", "")) not in ["partial", "route_inventory_complete", "complete"]: errors.append("%s 缺少历史资料覆盖状态" % str(city_id))
		if str(city_config_value.get("futureStatus", "")) not in ["not_digitized", "partial", "complete"]: errors.append("%s 缺少远期资料状态" % str(city_id))
		if str(city_config_value.get("coverageNote", "")).is_empty(): errors.append("%s 缺少历史资料范围说明" % str(city_id))
		var station_ids := {}
		for station in city_ids[str(city_id)].get("stations", []): station_ids[str(station.get("id", ""))] = true
		var seen_chapters: Dictionary = {}
		var last_chapter_date := ""
		for chapter in _catalog.cities[city_id].get("chapters", []):
			var chapter_id := str(chapter.get("id", ""))
			if chapter_id.is_empty() or seen_chapters.has(chapter_id): errors.append("%s 历史章节编号无效或重复" % str(city_id))
			seen_chapters[chapter_id] = true
			var chapter_date := str(chapter.get("date", ""))
			if chapter_date.is_empty() or chapter_date > cutoff_date(): errors.append("%s 章节日期无效或晚于资料截止日期" % chapter_id)
			if not last_chapter_date.is_empty() and chapter_date < last_chapter_date: errors.append("%s 历史章节未按日期排序" % chapter_id)
			last_chapter_date = chapter_date
			if str(chapter.get("source", "")).is_empty(): errors.append("%s 缺少来源" % chapter_id)
			if chapter.get("lineGroups",[]).is_empty() and not bool(chapter.get("eventOnly",false)):
				if str(chapter.get("operationType",""))!="transfer_connection" or chapter.get("requiredTransfers",[]).is_empty():errors.append("%s 没有建设范围或明确换乘操作"%chapter_id)
				var pairing_ids:Dictionary={}
				for pairing in chapter.get("requiredTransfers",[]):
					var pair_id:=str(pairing.get("id",""));var lines:Array=pairing.get("lineIds",[]);var bodies:Array=pairing.get("stationInstanceIds",[])
					if pair_id.is_empty() or pairing_ids.has(pair_id) or lines.size()<2 or lines.size()!=bodies.size() or not str(pairing.get("source","")).begins_with("https://"):errors.append("%s 换乘任务配对或来源无效"%chapter_id)
					pairing_ids[pair_id]=true
					var unique_lines:Dictionary={};var unique_bodies:Dictionary={}
					for identity in lines:
						if not str(identity).begins_with(str(city_id)+"-") or unique_lines.has(str(identity)):errors.append("%s 换乘任务引用重复或其他城市线路"%chapter_id)
						unique_lines[str(identity)]=true
					for identity in bodies:
						if not station_ids.has(str(identity).get_slice("__",0)) or unique_bodies.has(str(identity)):errors.append("%s 换乘任务引用未知或共用站体"%chapter_id)
						unique_bodies[str(identity)]=true
			if str(chapter.get("sourceTitle", "")).is_empty(): errors.append("%s 缺少来源标题" % chapter_id)
			if str(chapter.get("sourceCheckedAt", "")).is_empty(): errors.append("%s 缺少来源核验日期" % chapter_id)
			if str(chapter.get("sourceType", "")).is_empty(): errors.append("%s 缺少来源类型" % chapter_id)
			if str(chapter.get("status", "")).is_empty(): errors.append("%s 缺少历史实施状态" % chapter_id)
			if str(chapter.get("alignmentNote", "")).is_empty(): errors.append("%s 缺少线位精度说明" % chapter_id)
			if str(chapter.get("precision", "")) not in ["station_areas", "corridor", "schematic","verified_alignment"]: errors.append("%s 缺少有效的线位精度等级" % chapter_id)
			var story:Dictionary=chapter.get("story",{})
			for field in ["opening","purpose","outcome"]:
				if str(story.get(field,"")).is_empty():errors.append("%s 缺少故事内容：%s" % [chapter_id,field])
			if story.get("steps",[]).is_empty():errors.append("%s 缺少可操作故事步骤" % chapter_id)
			var beat_ids:Dictionary={}
			for beat in story.get("beats",[]):
				var beat_id:=str(beat.get("id",""))
				if beat_id.is_empty() or beat_ids.has(beat_id):errors.append("%s 地点故事编号无效或重复" % chapter_id)
				beat_ids[beat_id]=true
				for field in ["title","text","source","sourceTitle","verifiedAt","date"]:
					if str(beat.get(field,"")).is_empty():errors.append("%s 地点故事缺少%s" % [chapter_id,field])
					if beat.get("stationIds",[]).is_empty() or beat.get("triggers",[]).is_empty():errors.append("%s 地点故事缺少位置或触发条件" % chapter_id)
				for id in beat.get("stationIds",[]):
					if not station_ids.has(str(id)):errors.append("%s 地点故事引用未知站区" % chapter_id)
			var profile:Dictionary=chapter.get("constructionProfile",{})
			for field in ["lengthM","widthM","depthM","vehicleId"]:
				if profile.has(field) and not profile.get("parameterStatus",{}).has(field):errors.append("%s 建设参数未说明公开数据或游戏估算" % chapter_id)
			var plan_ids:Dictionary={};var previous_date:=""
			for version in story.get("planVersions",[]):
				var plan_id:=str(version.get("id",""));var date:=str(version.get("date",""))
				if plan_id.is_empty() or plan_ids.has(plan_id):errors.append("%s 方案版本编号为空或重复" % chapter_id)
				plan_ids[plan_id]=true
				if date.is_empty() or date>chapter_date or (not previous_date.is_empty() and date<previous_date):errors.append("%s 方案版本日期错误" % chapter_id)
				previous_date=date
				if str(version.get("source","")).is_empty() or str(version.get("description","")).is_empty():errors.append("%s 方案缺少来源或变化说明" % chapter_id)
				for group in version.get("lineGroups",[]):
					for id in group.get("stationIds",[]):
						if not station_ids.has(str(id)):errors.append("%s 方案引用未知站点" % chapter_id)
			for group in chapter.get("lineGroups", []):
				if Engineering.is_group(group):
					errors.append_array(Engineering.definition_errors(group,station_ids.keys()))
					continue
				if str(chapter.get("precision",""))=="verified_alignment" and group.get("alignment",[]).size()<2:errors.append("%s 声称精确线位但缺少中心线" % chapter_id)
				if group.get("stationIds", []).size() < 2: errors.append("%s 目标线路少于两站" % chapter_id)
				if float(group.get("toleranceM", 0.0)) <= 0.0: errors.append("%s 目标站缺少正的容差" % chapter_id)
				if group.has("defaultServiceStatus") and str(group.defaultServiceStatus) not in ["built","trial","open","suspended"]:errors.append("%s 本期线路状态无效"%chapter_id)
				var group_targets: Dictionary = {}
				for station_id in group.get("stationIds", []):
					if not station_ids.has(str(station_id)): errors.append("%s 引用了未知目标站：%s" % [chapter_id, str(station_id)])
					if group_targets.has(str(station_id)): errors.append("%s 在同一线路组重复引用目标站：%s" % [chapter_id, str(station_id)])
					group_targets[str(station_id)] = true
			var service_transition_ids:Dictionary={}
			for transition in chapter.get("serviceTransitions", []):
				var transition_id:=str(transition.get("id",""))
				var line_id := str(transition.get("historicalLineId", ""))
				var status := str(transition.get("status", ""))
				var transition_ids: Array = transition.get("stationIds", [])
				var matching_group: Dictionary = {}
				for group in chapter.get("lineGroups", []):
					if str(group.get("historicalLineId", "")) == line_id: matching_group = group; break
				if line_id.is_empty() or matching_group.is_empty(): errors.append("%s 服务阶段引用了不存在的线路组" % chapter_id)
				if status not in ["built", "trial", "open", "suspended"]: errors.append("%s 服务阶段状态无效" % chapter_id)
				if transition_ids.size() < 2 or str(transition.get("source", "")).is_empty(): errors.append("%s 服务阶段缺少范围或来源" % chapter_id)
				for id in transition_ids:
					if not station_ids.has(str(id)) or not matching_group.get("stationIds", []).has(str(id)): errors.append("%s 服务阶段范围与本期线路站序不一致：%s" % [chapter_id, str(id)])
				var group_order: Array = matching_group.get("stationIds", [])
				var start_index := group_order.find(str(transition_ids[0])) if not transition_ids.is_empty() else -1
				if start_index < 0: errors.append("%s 服务阶段起点不在线路站序中" % chapter_id)
				else:
					for offset in range(transition_ids.size()):
						if start_index + offset >= group_order.size() or str(group_order[start_index + offset]) != str(transition_ids[offset]):
							errors.append("%s 服务阶段必须是线路站序中的连续区间" % chapter_id); break
				if transition_id.is_empty() or service_transition_ids.has(transition_id):errors.append("%s 服务阶段缺少或重复稳定编号" % chapter_id)
				service_transition_ids[transition_id]=true
			for connection in chapter.get("requiredConnections",[]):
				if not station_ids.has(str(connection.get("fromId",""))) or not station_ids.has(str(connection.get("toId",""))) or str(connection.get("source","")).is_empty():errors.append("%s 建设段连接缺少站点引用或来源" % chapter_id)
		var last_event_date := ""
		for event in city_config_value.get("historicalEvents", []):
			var event_date := str(event.get("date", ""))
			if event_date.is_empty() or event_date > cutoff_date(): errors.append("%s 历史事件日期无效或晚于资料截止日期" % str(event.get("title", city_id)))
			if not last_event_date.is_empty() and event_date < last_event_date: errors.append("%s 历史事件未按日期排序" % str(city_id))
			last_event_date = event_date
			if str(event.get("id", "")).is_empty(): errors.append("%s 历史事件缺少稳定编号" % str(event.get("title", city_id)))
			if str(event.get("source", "")).is_empty() or str(event.get("sourceTitle", "")).is_empty(): errors.append("%s 历史事件缺少可追溯来源" % str(event.get("title", city_id)))
			if str(event.get("sourceCheckedAt", "")).is_empty() or str(event.get("scope", "")).is_empty() or str(event.get("status", "")).is_empty() or str(event.get("sourceType", "")).is_empty(): errors.append("%s 缺少核验日期、范围、来源类型或实施状态" % str(event.get("title", city_id)))
			if not event.has("sourcePublicationDate"): errors.append("%s 未明确记录来源公开日期是否已核实" % str(event.get("title", city_id)))
		for future in _catalog.cities[city_id].get("futurePlans", []):
			for pairing in future.get("requiredTransfers",[]):
				if str(pairing.get("status",""))!="reserved":continue
				var lines:Array=pairing.get("lineIds",[]);var bodies:Array=pairing.get("stationInstanceIds",[])
				if bool(future.get("requireOpen",true)) or lines.size()!=2 or bodies.size()!=2 or lines[0]==lines[1] or bodies[0]==bodies[1] or not str(pairing.get("reservationEvidence","")).begins_with("https://") or not str(pairing.get("source","")).begins_with("https://"):errors.append("%s 预留换乘的未开放状态、独立站体或来源无效"%str(future.get("id","")))
			if str(future.get("date", "")) > cutoff_date(): errors.append("%s 远期资料晚于资料截止日期" % str(future.get("id", city_id)))
			if str(future.get("source", "")).is_empty(): errors.append("%s 远期资料缺少来源" % str(future.get("id", city_id)))
			if str(future.get("sourceCheckedAt", "")).is_empty(): errors.append("%s 远期资料缺少核验日期" % str(future.get("id", city_id)))
			if str(future.get("sourceTitle", "")).is_empty(): errors.append("%s 远期资料缺少来源标题" % str(future.get("id", city_id)))
			if str(future.get("status", "")).is_empty() or str(future.get("sourceType", "")).is_empty(): errors.append("%s 远期条目缺少实施状态或来源类型" % str(future.get("id", city_id)))
			if not future.has("required"): errors.append("%s 未说明是否阻塞自由阶段" % str(future.get("id", city_id)))
			if str(future.get("dataStatus", "")) == "blueprint_ready" and not future_data_ready(future, city_ids[str(city_id)]): errors.append("%s 声称蓝图已就绪但缺少有效目标几何或站点引用" % str(future.get("id", city_id)))
	return errors

static func validate_network_baseline(city_data_list: Array) -> Array[String]:
	if _network_baseline.is_empty(): load_catalog()
	var errors: Array[String] = []
	if int(_network_baseline.get("schemaVersion", 0)) != 2: errors.append("截止日路网基准格式版本无效")
	if str(_network_baseline.get("cutoffDate", "")) != cutoff_date(): errors.append("截止日路网基准与故事资料包日期不一致")
	var city_lookup: Dictionary = {}
	for city in city_data_list: city_lookup[str(city.get("id", ""))] = city
	for city_id in _network_baseline.get("cities", {}):
		if not city_lookup.has(str(city_id)):
			errors.append("截止日路网基准引用未知城市：%s" % str(city_id)); continue
		var city: Dictionary = city_lookup[str(city_id)]
		var baseline: Dictionary = _network_baseline.cities[city_id]
		var map_routes: Dictionary = {}
		for route in city.get("lines", []): map_routes[str(route.get("id", ""))] = route
		var baseline_routes: Dictionary = {}
		for route in baseline.get("routes", []):
			var route_id := str(route.get("mapRouteId", ""))
			if route_id.is_empty() or baseline_routes.has(route_id): errors.append("%s 截止日线路编号为空或重复" % str(city_id))
			baseline_routes[route_id] = true
			if not map_routes.has(route_id): errors.append("%s 截止日基准引用缺失地图线路：%s" % [str(city_id), route_id]); continue
			var known: Dictionary = {}
			for station in city.get("stations", []): known[str(station.get("id", ""))] = true
			for station_id in route.get("cutoffStationIds", []):
				if not known.has(str(station_id)): errors.append("%s/%s 截止日线路引用未知地图站：%s" % [str(city_id), route_id, str(station_id)])
		if baseline_routes.size() != map_routes.size(): errors.append("%s 截止日基准与离线线路关系条目数不一致" % str(city_id))
		for milestone in baseline.get("documentedMilestones", []):
			var date := str(milestone.get("date", ""))
			if str(milestone.get("id", "")).is_empty() or date.is_empty() or date > cutoff_date(): errors.append("%s 截止日里程碑编号或日期无效" % str(city_id))
			if str(milestone.get("source", "")).is_empty(): errors.append("%s 里程碑缺少来源：%s" % [str(city_id), str(milestone.get("id", ""))])
			for route_id in milestone.get("routeIds", []):
				if not map_routes.has(str(route_id)): errors.append("%s 里程碑引用未知地图线路：%s" % [str(city_id), str(route_id)])
		var schedule: Variant = baseline.get("milestoneChapters", [])
		if not schedule is Array or schedule.is_empty():
			errors.append("%s 缺少里程碑章节区间" % str(city_id)); continue
		var known_chapters: Dictionary = {}
		for chapter in _catalog.get("cities", {}).get(str(city_id), {}).get("chapters", []): known_chapters[str(chapter.get("id", ""))] = true
		var previous_end := ""
		var scheduled_events: Dictionary = {}
		var final_row: Dictionary = {}
		for index in range(schedule.size()):
			var interval: Variant = schedule[index]
			if not interval is Dictionary: errors.append("%s 里程碑章节包含无效记录" % str(city_id)); continue
			var start_date := str(interval.get("periodStartExclusive", ""))
			var end_date := str(interval.get("periodEndInclusive", ""))
			if start_date != previous_end or end_date.is_empty() or end_date > cutoff_date() or (not previous_end.is_empty() and end_date < previous_end): errors.append("%s 里程碑章节日期区间不连续或超出截止日" % str(city_id))
			previous_end = end_date
			var content_status := str(interval.get("contentStatus", ""))
			if index == schedule.size() - 1:
				final_row = interval
				if content_status not in ["network_reconciliation_missing", "network_reconciliation_complete"] or end_date != cutoff_date(): errors.append("%s 缺少截止日现状核对节点" % str(city_id))
			elif content_status not in ["playable_sample", "playable_milestone", "content_missing"]:
				errors.append("%s 历史里程碑区间状态无效" % str(city_id))
			var playable_id := str(interval.get("playableChapterId", ""))
			if content_status in ["playable_sample", "playable_milestone"] and (playable_id.is_empty() or not known_chapters.has(playable_id)): errors.append("%s 可玩里程碑区间引用未知章节" % str(city_id))
			if content_status == "content_missing" and not playable_id.is_empty(): errors.append("%s 待制作里程碑区间错误标成可玩" % str(city_id))
			for event_id_value in interval.get("eventIds", []):
				var event_id := str(event_id_value)
				if event_id.is_empty() or scheduled_events.has(event_id): errors.append("%s 里程碑事件缺少编号或在区间中重复" % str(city_id))
				scheduled_events[event_id] = true
			for route_id in interval.get("targetMapRouteIds", interval.get("routeIds", [])):
				if not map_routes.has(str(route_id)): errors.append("%s 里程碑区间引用未知地图线路：%s" % [str(city_id), str(route_id)])
		var documented_events: Dictionary = {}
		for event in baseline.get("documentedMilestones", []): documented_events[str(event.get("id", ""))] = true
		if documented_events.keys().size() != scheduled_events.keys().size(): errors.append("%s 已登记历史事件与里程碑章节区间覆盖数量不一致" % str(city_id))
		for event_id in documented_events:
			if not scheduled_events.has(str(event_id)): errors.append("%s 历史事件未归入任何里程碑区间：%s" % [str(city_id), str(event_id)])
		var target_route_ids: Dictionary = {}
		for route in baseline.get("routes", []): target_route_ids[str(route.get("mapRouteId", ""))] = true
		var final_target_ids: Dictionary = {}
		for route_id in final_row.get("targetMapRouteIds", []): final_target_ids[str(route_id)] = true
		if final_target_ids.keys().size() != target_route_ids.keys().size(): errors.append("%s 截止日核对节点未包含全部地图线路" % str(city_id))
		for route_id in target_route_ids:
			if not final_target_ids.has(str(route_id)): errors.append("%s 截止日核对节点遗漏地图线路：%s" % [str(city_id), str(route_id)])
	return errors
