class_name StorySession
extends RefCounted

## Construction and explicit story actions are the only authoritative inputs.
## Presentation time and UI refresh never advance a chapter.
const Catalog = preload("res://scripts/campaign_system.gd")
const Paths = preload("res://scripts/route_path.gd")

static func config(world: Dictionary) -> Dictionary:
	return Catalog.city_config(str(world.get("cityId", "")))

static func chapter(world: Dictionary) -> Dictionary:
	var chapters: Array = config(world).get("chapters", [])
	var index := int(world.get("storyState", {}).get("chapterIndex", 0))
	if str(world.get("storyState", {}).get("phase", "history")) == "future":
		chapters = config(world).get("futurePlans", []).filter(func(p: Dictionary): return bool(p.get("required", false)) and Catalog.future_data_ready(p, WorldData.city(str(world.get("cityId", "")))))
	var stable_id:=str(world.get("storyState",{}).get("chapterId",""))
	if not stable_id.is_empty():
		for entry in chapters:
			if str(entry.get("id",""))==stable_id:return entry
		return {}
	return chapters[index] if index >= 0 and index < chapters.size() else {}

static func groups(world: Dictionary, final_plan: bool = false) -> Array:
	var ch := chapter(world)
	var versions: Array = ch.get("story", {}).get("planVersions", [])
	if not versions.is_empty() and not final_plan:
		var index := clampi(int(world.get("storyPlan", {}).get("planIndex", 0)), 0, versions.size() - 1)
		return versions[index].get("lineGroups", [])
	return ch.get("lineGroups", [])

static func targets(world: Dictionary, final_plan: bool = false) -> Array[Dictionary]:
	var refs: Dictionary = {}
	for station in WorldData.city(str(world.get("cityId", ""))).get("stations", []): refs[str(station.get("id", ""))] = station
	var seen: Dictionary = {}
	var result: Array[Dictionary] = []
	for group in groups(world, final_plan):
		for id_value in group.get("stationIds", []):
			var id := str(id_value)
			if seen.has(id) or not refs.has(id): continue
			seen[id] = true
			var item: Dictionary = refs[id].duplicate(true)
			var coordinate_reference:=ReferenceAlignment.station_reference(id)
			if not coordinate_reference.is_empty() and plan_is_final(world):
				item["rawLatlng"]=item.latlng;item["latlng"]=coordinate_reference.latlng;item["coordinateSource"]=coordinate_reference
			item["name"] = str(group.get("stationNames", {}).get(id, item.get("name", "车站")))
			item["historicalNameRequired"]=group.get("stationNames",{}).has(id)
			item["toleranceM"] = float(group.get("toleranceM", 100.0))
			item["built"] = not bound_station(world, id).is_empty()
			item["referenceHeading"]=ReferenceAlignment.heading(id,groups(world,final_plan),float(WorldData.city(str(world.cityId)).center[0]))
			result.append(item)
	return result

static func bound_station(world: Dictionary, historical_id: String) -> Dictionary:
	for station in world.get("stations", []):
		if str(station.get("historicalId", "")) == historical_id: return station
	return {}

static func nearest_target(world: Dictionary, latlng: Array) -> Dictionary:
	var result: Dictionary = {}
	var best := INF
	var ref_lat := float(WorldData.city(str(world.get("cityId", ""))).get("center", [31.23])[0])
	for target in targets(world):
		if bool(target.get("built", false)): continue
		var distance := Geo.local_m(latlng, ref_lat).distance_to(Geo.local_m(target.latlng, ref_lat))
		if distance <= float(target.toleranceM) and distance < best:
			result = target; best = distance
	return result

static func blueprint(world: Dictionary, show_previous: bool = false) -> Dictionary:
	var stations := targets(world)
	var corridors: Array = []
	var map: Dictionary = {}
	for target in stations: map[str(target.id)] = target
	for group in groups(world):
		var points: Array = []; var corridor_targets: Array = []
		for id in group.get("stationIds", []):
			if map.has(str(id)):
				points.append(map[str(id)].latlng)
				corridor_targets.append(map[str(id)])
		for i in range(corridor_targets.size()-1):
			var a:Dictionary=corridor_targets[i];var b:Dictionary=corridor_targets[i+1]
			var reference:=ReferenceAlignment.between(str(a.id),str(b.id)) if plan_is_final(world) else {}
			corridors.append({"points":reference.get("points",[a.latlng,b.latlng]),"targets":[a,b],"precision":reference.get("precision","schematic"),"referenceId":reference.get("id",""),"referenceLabel":ReferenceAlignment.label_for(reference)})
	for connection in chapter(world).get("requiredConnections",[]):
		var a:Dictionary=map.get(str(connection.fromId),{});var b:Dictionary=map.get(str(connection.toId),{})
		if not a.is_empty() and not b.is_empty():corridors.append({"points":[a.latlng,b.latlng],"targets":[a,b],"precision":"schematic"})
	var state: Dictionary = world.get("storyState", {})
	if StoryTutorial.active(world) and not bool(state.get("learnedTools", false)) and plan_is_final(world):
		stations = stations.slice(0, 2)
		var visible_ids:Array=stations.map(func(target:Dictionary):return str(target.id))
		for corridor in corridors:
			corridor["targets"] = corridor.targets.filter(func(target:Dictionary):return visible_ids.has(str(target.id)))
			corridor["points"] = corridor.targets.map(func(target:Dictionary):return target.latlng)
	var previous: Array = []
	var versions: Array = chapter(world).get("story", {}).get("planVersions", [])
	var plan_index := int(world.get("storyPlan", {}).get("planIndex", 0))
	if show_previous and plan_index > 0 and plan_index < versions.size():
		for group in versions[plan_index - 1].get("lineGroups", []):
			var points: Array = []
			for id in group.get("stationIds", []):
				for reference in WorldData.city(str(world.cityId)).get("stations", []):
					if str(reference.id) == str(id): points.append(reference.latlng); break
			previous.append(points)
	return {"visible":not stations.is_empty() and str(state.get("stage","intro"))!="outcome", "stations":stations, "corridors":corridors, "previous":previous, "title":chapter(world).get("title", ""), "date":chapter(world).get("date", ""), "draftOnly":not plan_is_final(world)}

static func plan_is_final(world: Dictionary) -> bool:
	var versions: Array = chapter(world).get("story", {}).get("planVersions", [])
	return versions.is_empty() or int(world.get("storyPlan", {}).get("planIndex", 0)) == versions.size() - 1

static func evaluate(world: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	var routes: Array = []
	var ch := chapter(world)
	if ch.is_empty(): return {"complete":false,"issues":[{"text":"当前没有可验收章节。"}],"routes":[],"revision":int(world.get("revision",0))}
	if not plan_is_final(world): issues.append({"text":"请先在故事页对比并采用本章的最终修订方案。", "kind":"plan"})
	if bool(ch.get("requiresLineReorganization",false)) and not bool(world.get("storyPlan",{}).get("reorganizationAccepted",false)):issues.append({"text":"请使用下方「线路整理」核对并确认本期贯通站序。","kind":"plan"})
	var reference_lat := float(WorldData.city(str(world.cityId)).get("center", [31.23])[0])
	var reference_map: Dictionary = {}
	for target in targets(world, true): reference_map[str(target.id)] = target
	var bindings: Dictionary = {}
	for station in world.get("stations", []):
		var id := str(station.get("historicalId", ""))
		if id.is_empty(): continue
		if bindings.has(id): issues.append({"text":"同一个历史目标被绑定到两座车站。", "objectId":str(station.id), "kind":"station"})
		bindings[id] = station
	for group_index in range(groups(world, true).size()):
		var group: Dictionary = groups(world, true)[group_index]
		var ids: Array = []; var paths: Array = []; var group_valid := true
		for raw_id in group.get("stationIds", []):
			var target_id := str(raw_id)
			var target: Dictionary = reference_map.get(target_id, {})
			var station: Dictionary = bindings.get(target_id, {})
			if station.is_empty():
				issues.append({"text":"尚未建设：%s" % str(target.get("name", target_id)), "kind":"target", "objectId":target_id,"latlng":target.get("latlng", [])}); group_valid = false; continue
			var distance := Geo.local_m(station.latlng, reference_lat).distance_to(Geo.local_m(target.get("latlng", station.latlng), reference_lat))
			if distance > float(target.get("toleranceM",100)):
				issues.append({"text":"%s 超出目标站区 %.0f 米容差。" % [str(target.get("name","车站")),float(target.get("toleranceM",100))],"kind":"station","objectId":str(station.id),"latlng":station.latlng}); group_valid = false
			if group.get("stationNames",{}).has(target_id) and str(station.get("name",""))!=str(target.get("name","")):
				issues.append({"text":"请在车站详情将「%s」更名为本章名称「%s」。" % [str(station.get("name","车站")),str(target.name)],"kind":"station","objectId":str(station.id),"latlng":station.latlng});group_valid=false
			ids.append(str(station.id))
		if not group_valid: continue
		var prior_end := ""
		for i in range(ids.size()-1):
			var options := TrackNetwork.station_path_options(str(ids[i]), str(ids[i+1]), world, reference_lat, 4)
			var choice := int(world.get("storyPlan",{}).get("pathChoices",{}).get("%d:%d" % [group_index,i],0))
			if options.is_empty():
				issues.append({"text":"尚未接通：%s—%s" % [WorldData.find_station(world,str(ids[i])).name,WorldData.find_station(world,str(ids[i+1])).name],"kind":"station","objectId":str(ids[i]),"latlng":WorldData.find_station(world,str(ids[i])).latlng}); group_valid=false; continue
			var path: Dictionary = options[clampi(choice,0,options.size()-1)]
			var ordered: Array = []; var intermediate: Array = []
			for connection in path.get("edges",[]):
				if bool(connection.edge.get("platform",false)):
					intermediate.append(str(connection.edge.get("id","")).trim_prefix("platform:"))
				else: ordered.append({"id":str(connection.edge.id),"forward":bool(connection.forward)})
			if not intermediate.is_empty():
				issues.append({"text":"%s—%s 的轨道经过了未列入本期相邻站序的其他车站。" % [WorldData.find_station(world,str(ids[i])).name,WorldData.find_station(world,str(ids[i+1])).name],"kind":"station","objectId":str(ids[i])});group_valid=false
			if not prior_end.is_empty() and not ordered.is_empty():
				var first: Dictionary = path.edges[0]
				if prior_end == str(first.get("fromNodeId","")):
					issues.append({"text":"%s 的相邻区间从同一站端进出，形成了未经确认的站内折返。" % str(WorldData.find_station(world,str(ids[i])).name),"kind":"station","objectId":str(ids[i])});group_valid=false
			if not path.edges.is_empty(): prior_end=str(path.edges[-1].get("toNodeId",""))
			# Exact centerlines are evaluated only when sourced geometry is available.
			var corridor: Array = group.get("alignment",[])
			var pair_reference:=ReferenceAlignment.between(str(group.stationIds[i]),str(group.stationIds[i+1]))
			if str(pair_reference.get("precision",""))=="verified_alignment" and ReferenceAlignment.corridor_issue(path.points,pair_reference.points,reference_lat,float(group.get("alignmentToleranceM",80))):
				issues.append({"text":"该区间偏离对应站间的核验走廊，或跳过必经走向。","kind":"station","objectId":str(ids[i])});group_valid=false
			if corridor.size() >= 2 and str(ch.get("precision","")) == "verified_alignment":
				for point in path.points:
					var nearest := INF; var local := Geo.local_m(point,reference_lat)
					for j in range(corridor.size()-1): nearest=minf(nearest,local.distance_to(Geometry2D.get_closest_point_to_segment(local,Geo.local_m(corridor[j],reference_lat),Geo.local_m(corridor[j+1],reference_lat))))
					if nearest > float(group.get("alignmentToleranceM",80)):
						issues.append({"text":"区间明显偏离已核验参考走廊。","kind":"station","objectId":str(ids[i])});group_valid=false;break
			paths.append(ordered)
		var route := {"id":"historical_%s" % str(group.get("historicalLineId", group.get("name","line"))),"name":str(group.get("name","线路")),"color":str(group.get("color","#36769c")),"stationOrder":ids,"networkBased":true,"vehicleId":str(group.get("vehicleId",profile(world).get("vehicleId","historical-schematic"))),"open":bool(ch.get("requireOpen",true)),"directions":[{"id":"forward","stationIds":ids,"edgePathsBySegment":paths}],"historicalLineId":str(group.get("historicalLineId",group.get("name","line"))),"chapterId":str(ch.get("id",""))}
		if group_valid and paths.size()==maxi(0,ids.size()-1):
			var canonical := Paths.for_route(route,world,reference_lat)
			if not bool(canonical.get("valid",false)):
				issues.append({"text":"%s：%s" % [route.name,"；".join(canonical.get("errors",[]))],"kind":"route"})
			routes.append(route)
	for connection in ch.get("requiredConnections",[]):
		var a:=bound_station(world,str(connection.fromId));var b:=bound_station(world,str(connection.toId))
		if a.is_empty() or b.is_empty() or not bool(TrackNetwork.shortest_station_path(str(a.get("id","")),str(b.get("id","")),world,reference_lat).get("valid",false)):
			issues.append({"text":str(connection.get("description","需要连接前后建设段。")),"kind":"target","objectId":str(connection.fromId),"latlng":a.get("latlng",[])})
	return {"complete":issues.is_empty() and routes.size()==groups(world,true).size(),"issues":issues,"routes":routes,"revision":int(world.get("revision",0)),"chapterId":str(ch.get("id",""))}

static func commit_chapter(world: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != int(world.get("revision",0)): return {"ok":false,"error":"规划已变化，请重新检查本章。"}
	var result := evaluate(world)
	if not bool(result.complete): return {"ok":false,"error":"仍有未完成的复现条件。","evaluation":result}
	var state: Dictionary = world.storyState
	var ch := chapter(world)
	if state.completedChapterIds.has(str(ch.id)): return {"ok":false,"error":"该历史节点已经确认。"}
	StoryTutorial.finish(world)
	for id in ch.get("retireRouteIds",[]):
		var old:=WorldData.find_route(world,str(id))
		if not old.is_empty():old["open"]=false;old["retired"]=true;old["retiredAt"]=str(ch.date)
	for route in result.routes:
		var old := WorldData.find_route(world,str(route.id))
		if old.is_empty(): world.routes.append(route)
		else:
			old.clear(); old.merge(route,true)
	for station in world.stations:
		station["routeIds"]=[]
		for route in world.routes:
			if bool(route.get("open",false)) and route.get("stationOrder",[]).has(str(station.id)): station.routeIds.append(str(route.id))
	for edge in TrackNetwork.all_physical_edges(world):
		edge["routeIds"]=[]
		for route in world.routes:
			if not bool(route.get("open",false)):continue
			for direction in route.get("directions",[]):
				for segment in direction.get("edgePathsBySegment",[]):
					for ref in segment:
						if str(ref.get("id",""))==str(edge.id) and not edge.routeIds.has(str(route.id)): edge.routeIds.append(str(route.id))
	var h := CommandHistory.new(); h.attach(world)
	var planning := h._capture_planning()
	var delta := h._build_diff(world.get("milestoneBaseline",{}),planning)
	state.milestones.append({"chapterId":str(ch.id),"date":str(ch.date),"title":str(ch.title),"planningDiff":delta,"source":str(ch.get("source","")),"assisted":bool(world.get("storyPlan",{}).get("assisted",false))})
	world["milestoneBaseline"]=planning.duplicate(true)
	state.completedChapterIds.append(str(ch.id));state["stage"]="outcome"
	state["chapterId"]=str(ch.id)
	if bool(world.get("storyPlan",{}).get("assisted",false)) and not state.get("assistedChapters",[]).has(str(ch.id)):state.assistedChapters.append(str(ch.id))
	world["history"]={"undo":[],"redo":[]}
	world["revision"]=int(world.get("revision",0))+1
	return {"ok":true,"chapter":ch,"routeIds":result.routes.map(func(r:Dictionary):return str(r.id))}

static func next_chapter(world: Dictionary) -> void:
	if str(world.get("storyState",{}).get("stage",""))!="outcome":return
	var st: Dictionary=world.storyState
	var current:=chapter(world)
	var chapters:Array=config(world).get("chapters",[]) if str(st.get("phase","history"))!="future" else config(world).get("futurePlans",[]).filter(func(p:Dictionary):return bool(p.get("required",false)) and Catalog.future_data_ready(p,WorldData.city(str(world.cityId))))
	var index:=int(st.get("chapterIndex",0))
	for i in range(chapters.size()):
		if str(chapters[i].get("id",""))==str(current.get("id","")):index=i;break
	st["tutorialEnabled"]=false;st["learnedTools"]=true
	st["chapterIndex"]=index+1;st["chapterId"]=""
	st["stage"]="intro";world["storyPlan"]={"planIndex":0,"pathChoices":{}}
	if chapter(world).is_empty():
		if str(config(world).get("historyStatus","partial"))!="complete": st["phase"]="history_gap"
		elif str(st.get("phase","history"))=="history":
			var required: Array=config(world).get("futurePlans",[]).filter(func(p:Dictionary):return bool(p.get("required",false)))
			var ready := str(config(world).get("futureStatus","not_digitized"))=="complete" and required.all(func(p:Dictionary):return Catalog.future_data_ready(p,WorldData.city(str(world.cityId))))
			st["phase"]="future" if ready else "future_gap";st["chapterIndex"]=0
			if ready and required.is_empty():st["phase"]="free";st["freeUnlocked"]=true;world["mode"]="workshop"
		elif str(st.get("phase",""))=="future": st["phase"]="free";st["freeUnlocked"]=true;world["mode"]="workshop"
	if not chapter(world).is_empty():st["chapterId"]=str(chapter(world).id)

static func replay_copy(world: Dictionary, milestone_index: int) -> Dictionary:
	var milestones: Array=world.get("storyState",{}).get("milestones",[])
	if milestone_index<0 or milestone_index>=milestones.size():return {}
	var target_id:=str(milestones[milestone_index].get("chapterId",""))
	var copy := WorldData.new_world(str(world.cityId),"campaign")
	copy.storyState["chapterId"]=target_id
	if chapter(copy).is_empty():return {}
	var h:=CommandHistory.new();h.attach(copy)
	# Start at the preceding historical state, keeping later construction out of
	# the replay. A replay remains a story, not an early free-creation unlock.
	for index in range(milestone_index): h._apply_diff(milestones[index].get("planningDiff",{}),true)
	copy["title"]="章节复盘 · %s" % str(milestones[milestone_index].get("title","章节"))
	copy.storyState["milestones"]=milestones.slice(0,milestone_index).duplicate(true)
	copy.storyState["completedChapterIds"]=copy.storyState.milestones.map(func(entry:Dictionary):return str(entry.get("chapterId","")))
	copy.storyState["learnedTools"]=true;copy.storyState["stage"]="intro"
	copy.storyState["tutorialEnabled"]=false;copy.storyState["tutorialStatus"]="skipped"
	copy["storyPlan"]={"planIndex":0,"pathChoices":{}};copy["milestoneBaseline"]=h._capture_planning()
	copy["replayOf"]=str(world.get("gameId",""));copy["history"]={"undo":[],"redo":[]}
	return copy

static func node_date(world:Dictionary) -> String:
	var ch:=chapter(world)
	if str(world.get("storyState",{}).get("stage","intro"))=="outcome":return str(ch.get("date","资料边界"))
	var versions:Array=ch.get("story",{}).get("planVersions",[])
	if versions.is_empty():return str(ch.get("date","资料边界"))
	return str(versions[clampi(int(world.get("storyPlan",{}).get("planIndex",0)),0,versions.size()-1)].get("date",ch.get("date","")))

static func plan_status(world:Dictionary) -> String:
	if chapter(world).is_empty():return "后续资料待核验"
	if str(world.get("storyState",{}).get("stage","intro"))=="outcome":return "历史节点已确认"
	return "本期建成目标" if plan_is_final(world) else "未实施的历史方案"

static func current_action(world:Dictionary) -> String:
	if not plan_is_final(world):return "对比新旧方案，再采用下一版调整。"
	if bool(chapter(world).get("requiresLineReorganization",false)) and not bool(world.storyPlan.get("reorganizationAccepted",false)):return "在「线路整理」确认贯通站序。"
	for target in targets(world,true):
		if not bool(target.built):return "建设本期目标站，并连接相邻站端。"
	return "核对区间连接，检查并确认历史节点。"

static func profile(world:Dictionary,historical_id:String="") -> Dictionary:
	var ch:=chapter(world)
	var result:Dictionary=ch.get("constructionProfile",{"id":"unverified","lengthM":118.788,"widthM":20.0,"depthM":-15.0,"vehicleId":"B-6","form":"待核验","note":"矩形、车型与埋深为游戏示意；原始工程参数待核验。"}).duplicate(true)
	var overrides:Dictionary=ch.get("stationProfiles",{}).get(historical_id,{}).duplicate(true)
	for key in ["parameterStatus","parameterSources"]:
		if overrides.has(key):
			var merged:Dictionary=result.get(key,{}).duplicate(true);merged.merge(overrides[key],true);result[key]=merged;overrides.erase(key)
	result.merge(overrides,true)
	return result

static func plan_change(world:Dictionary,old_index:int,new_index:int) -> String:
	var versions:Array=chapter(world).get("story",{}).get("planVersions",[])
	if old_index<0 or new_index>=versions.size():return "方案不存在。"
	var old_ids:Array=[];var new_ids:Array=[]
	for group in versions[old_index].get("lineGroups",[]):old_ids.append_array(group.get("stationIds",[]))
	for group in versions[new_index].get("lineGroups",[]):new_ids.append_array(group.get("stationIds",[]))
	var names:Dictionary={}
	for station in WorldData.city(str(world.cityId)).get("stations",[]):names[str(station.id)]=str(station.name)
	var added:Array=new_ids.filter(func(id):return not old_ids.has(id)).map(func(id):return str(names.get(id,id)))
	var removed:Array=old_ids.filter(func(id):return not new_ids.has(id)).map(func(id):return str(names.get(id,id)))
	return str(versions[new_index].get("description",""))+"\n新增目标："+("、".join(added) if not added.is_empty() else "无")+"\n移出本期："+("、".join(removed) if not removed.is_empty() else "无")
