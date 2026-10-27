class_name StorySession
extends RefCounted

## Construction and explicit story actions are the only authoritative inputs.
## Presentation time and UI refresh never advance a chapter.
const Catalog = preload("res://scripts/campaign_system.gd")
const Paths = preload("res://scripts/route_path.gd")
const Engineering = preload("res://scripts/engineering_construction.gd")
const Reservation = preload("res://scripts/transfer_reservation.gd")

static func config(world: Dictionary) -> Dictionary:
	return Catalog.city_config(str(world.get("cityId", "")))

static func network_coverage(city_id: String) -> Dictionary:
	return Catalog.network_coverage(city_id)

static func chapter(world: Dictionary) -> Dictionary:
	return Catalog.story_chapter_definition(str(world.get("cityId","")),world.get("storyState",{}))

static func task_id(chapter_row:Dictionary, group:Dictionary, index:int) -> String:
	return str(group.get("taskId", "line:%s:%d" % [str(chapter_row.get("id", "")), index]))

static func path_option_for_segment(options: Array, requested_index: int, prior_arrival_node: String, explicit_choice: bool) -> Dictionary:
	if options.is_empty(): return {}
	var selected: Dictionary = options[clampi(requested_index, 0, options.size() - 1)]
	if explicit_choice or prior_arrival_node.is_empty(): return selected
	if _path_starts_at_node(selected, prior_arrival_node):
		for candidate in options:
			if candidate is Dictionary and not _path_starts_at_node(candidate, prior_arrival_node): return candidate
	return selected

static func _path_starts_at_node(path: Dictionary, node_id: String) -> bool:
	var edges: Array = path.get("edges", [])
	return not edges.is_empty() and str(edges[0].get("fromNodeId", "")) == node_id

static func groups(world: Dictionary, final_plan: bool = false, selected_task_id:String="") -> Array:
	var ch := chapter(world)
	var versions: Array = ch.get("story", {}).get("planVersions", [])
	var result:Array=[]
	var uses_revision:=false
	if not versions.is_empty() and not final_plan:
		var index := clampi(int(world.get("storyPlan", {}).get("planIndex", 0)), 0, versions.size() - 1)
		# The last revision adopts this chapter's actual build scope. The chapter
		# data carries stable physical station-body identities for interchanges;
		# the older plan snapshots may only contain one schematic target per name.
		if index < versions.size() - 1:
			result=versions[index].get("lineGroups", [])
			uses_revision=true
	if not uses_revision:result=ch.get("lineGroups", [])
	# A loop binds each physical station once, but its path explicitly includes
	# the final-to-first section. Every drawing/builder/evaluator consumes this
	# normalized order so a ring cannot pass using an open chain.
	var normalized:Array=[]
	for source_group in result:
		var normalized_group:Dictionary=source_group.duplicate(true)
		var station_ids:Array=normalized_group.get("stationIds",[])
		if bool(normalized_group.get("loop",false)) and station_ids.size()>2 and station_ids.front()!=station_ids.back():station_ids.append(station_ids.front())
		normalized.append(normalized_group)
	result=normalized
	if selected_task_id.is_empty():return result
	var filtered:Array=[]
	for group_index in range(result.size()):
		var group:Dictionary=result[group_index]
		if task_id(ch,group,group_index)==selected_task_id:filtered.append(group)
	return filtered

static func targets(world: Dictionary, final_plan: bool = false, selected_task_id:String="") -> Array[Dictionary]:
	var refs: Dictionary = {}
	for station in WorldData.city(str(world.get("cityId", ""))).get("stations", []): refs[str(station.get("id", ""))] = station
	var seen: Dictionary = {}
	var result: Array[Dictionary] = []
	for group in groups(world, final_plan, selected_task_id):
		for id_index in range(group.get("stationIds", []).size()):
			var id := str(group.stationIds[id_index])
			var instance_id:=station_instance_id(group,id)
			var canonical_complex:=Catalog.canonical_station_complex(str(world.get("cityId", "")),id)
			var reference_id:=str(group.get("stationReferenceIds",{}).get(id,id))
			if seen.has(instance_id) or not refs.has(reference_id): continue
			seen[instance_id] = true
			var item: Dictionary = refs[reference_id].duplicate(true)
			item["id"]=instance_id;item["referenceId"]=reference_id;item["stationInstanceId"]=instance_id;item["stationComplexId"]=canonical_complex;item["historicalId"]=canonical_complex;item["historicalLineId"]=str(group.get("historicalLineId",""))
			item["historicalLineName"]=str(group.get("name",group.get("historicalLineId","本期线路")))
			item["engineeringExistingAnchor"]=Engineering.is_group(group) and not group.get("newStationIds",[]).has(id)
			var coordinate_reference:=ReferenceAlignment.station_reference(reference_id)
			if not coordinate_reference.is_empty() and plan_is_final(world):
				item["rawLatlng"]=item.latlng;item["latlng"]=coordinate_reference.latlng;item["coordinateSource"]=coordinate_reference
			item["name"] = str(group.get("stationNames", {}).get(id, item.get("name", "车站")))
			item["historicalNameRequired"]=group.get("stationNames",{}).has(id) and not _uses_planned_names(world,group)
			item["toleranceM"] = float(group.get("toleranceM", 100.0))
			# A same-line station at this complex is not proof that the requested
			# physical body exists. Interchange stations must have their own stable
			# instance ID before a chapter can bind a route or establish a transfer.
			item["built"] = not bound_station(world, id,instance_id).is_empty()
			item["referenceHeading"]=ReferenceAlignment.heading(reference_id,[group],float(WorldData.city(str(world.cityId)).center[0]),str(group.get("historicalLineId","")))
			result.append(item)
	if str(chapter(world).get("operationType",""))=="transfer_connection" and selected_task_id.is_empty():
		for pairing in chapter(world).get("requiredTransfers",[]):
			for index in range(pairing.get("stationInstanceIds",[]).size()):
				var instance_id:=str(pairing.stationInstanceIds[index])
				var reference_id:=instance_id.get_slice("__",0)
				if seen.has(instance_id) or not refs.has(reference_id):continue
				seen[instance_id]=true
				var physical:=bound_station(world,reference_id,instance_id)
				var item:Dictionary=refs[reference_id].duplicate(true)
				item.merge({"id":instance_id,"referenceId":reference_id,"stationInstanceId":instance_id,"stationComplexId":str(pairing.complexId),"historicalId":str(pairing.complexId),"historicalLineId":str(pairing.lineIds[index]),"historicalLineName":str(physical.get("stationLineName",pairing.lineIds[index])),"built":not physical.is_empty(),"existingTransferAnchor":true,"engineeringExistingAnchor":true,"toleranceM":100.0,"referenceHeading":float(physical.get("heading",90))},true)
				if not physical.is_empty():item.latlng=physical.latlng
				result.append(item)
	return result

static func _uses_planned_names(world:Dictionary,group:Dictionary) -> bool:
	return str(world.get("storyState",{}).get("phase","history"))=="future" and not bool(chapter(world).get("requireOpen",true)) and bool(group.get("constructionVariant",false)) and not str(group.get("stationNamingSource","")).is_empty()

static func station_instance_id(group:Dictionary,historical_id:String) -> String:
	var alias := Catalog.station_instance_alias(group, historical_id)
	if not alias.is_empty(): return alias
	return str(group.get("stationInstances",{}).get(historical_id,historical_id))

static func bound_station(world: Dictionary, historical_id: String, instance_id:String="", line_id:String="") -> Dictionary:
	for station in world.get("stations", []):
		var identity:=instance_id if not instance_id.is_empty() else historical_id
		if str(station.get("stationInstanceId",station.get("id","")))==identity:return station
		if instance_id.is_empty() and str(station.get("historicalId", "")) == historical_id: return station
	# Keep the line/complex fallback only for callers asking for a historical
	# complex without a physical instance. An explicit missing instance must
	# stay missing so a new interchange body can be built or a legacy save can
	# offer its reversible binding repair.
	if instance_id.is_empty() and not line_id.is_empty():
		var city_id := str(world.get("cityId", ""))
		var expected_complex := Catalog.canonical_station_complex(city_id, historical_id)
		for station in world.get("stations", []):
			var station_line := str(station.get("stationLineId", ""))
			if station_line != line_id: continue
			var station_complex := str(station.get("stationComplexId", station.get("historicalId", "")))
			if Catalog.canonical_station_complex(city_id, station_complex) == expected_complex: return station
	return {}

## Describes a safe, reversible repair for saves created before an interchange
## complex was split into line-specific station bodies. The existing connected
## body must match the new target geometry exactly; only an isolated duplicate
## target can be removed.
static func legacy_station_body_repair(world:Dictionary,group:Dictionary,historical_id:String) -> Dictionary:
	var canonical_instance:=station_instance_id(group,historical_id)
	if canonical_instance==historical_id:return {}
	var line_id:=str(group.get("historicalLineId",""))
	var exact:Array=[];var legacy:Array=[]
	for station in world.get("stations",[]):
		if str(station.get("stationComplexId",station.get("historicalId","")))!=historical_id:continue
		if str(station.get("historicalId",""))!=historical_id:continue
		var instance:=str(station.get("stationInstanceId",station.get("id","")))
		if instance==canonical_instance:exact.append(station)
		elif instance==historical_id and str(station.get("stationLineId",""))==line_id:legacy.append(station)
	if exact.size()!=1 or legacy.size()!=1:return {}
	var duplicate:Dictionary=exact[0];var connected:Dictionary=legacy[0]
	if str(duplicate.get("id",""))==str(connected.get("id","")):return {}
	var ref_lat:=float(WorldData.city(str(world.get("cityId",""))).get("center",[31.23])[0])
	if Geo.local_m(duplicate.get("latlng",[]),ref_lat).distance_to(Geo.local_m(connected.get("latlng",[]),ref_lat))>3.0:return {}
	if _angle_delta(float(duplicate.get("heading",0.0)),float(connected.get("heading",0.0)))>1.0:return {}
	for key in ["lengthM","widthM","depthM"]:
		if absf(float(duplicate.get(key,0.0))-float(connected.get(key,0.0)))>0.5:return {}
	var duplicate_node_ids:Array[String]=[]
	for node_id in duplicate.get("endpointNodes",{}).values():duplicate_node_ids.append(str(node_id))
	var connected_node_ids:Array[String]=[]
	for node_id in connected.get("endpointNodes",{}).values():connected_node_ids.append(str(node_id))
	var duplicate_edge_count:=0;var connected_edge_count:=0
	for edge in TrackNetwork.all_physical_edges(world):
		var ends:=TrackNetwork._edge_node_ids(edge,world)
		if ends.any(func(node_id:String):return duplicate_node_ids.has(node_id)):duplicate_edge_count+=1
		if ends.any(func(node_id:String):return connected_node_ids.has(node_id)):connected_edge_count+=1
	if duplicate_edge_count!=0 or connected_edge_count<2:return {}
	for route in world.get("routes",[]):
		if route.get("stationOrder",[]).has(str(duplicate.get("id",""))):return {}
		for direction in route.get("directions",[]):
			if direction.get("stationIds",[]).has(str(duplicate.get("id",""))):return {}
	for transfer in world.get("transferConnections",[]):
		if transfer.get("stationInstanceIds",[]).has(canonical_instance):return {}
	var station_index:=int(group.get("stationIds",[]).find(historical_id))
	if station_index<0:return {}
	var probe:=world.duplicate(true)
	if station_index>0:
		var previous_id:=station_instance_id(group,str(group.stationIds[station_index-1]))
		var previous_station:=_station_for_instance(probe,previous_id)
		if previous_station.is_empty() or not bool(TrackNetwork.shortest_station_path(str(previous_station.id),str(connected.id),probe,ref_lat).get("valid",false)):return {}
	if station_index+1<group.stationIds.size():
		var next_id:=station_instance_id(group,str(group.stationIds[station_index+1]))
		var next_station:=_station_for_instance(probe,next_id)
		if next_station.is_empty() or not bool(TrackNetwork.shortest_station_path(str(connected.id),str(next_station.id),probe,ref_lat).get("valid",false)):return {}
	return {"historicalId":historical_id,"canonicalInstanceId":canonical_instance,"lineId":line_id,"lineName":str(group.get("name",line_id)),"stationName":str(connected.get("name",duplicate.get("name","车站"))),"connectedStationId":str(connected.get("id","")),"duplicateStationId":str(duplicate.get("id","")),"expectedRevision":int(world.get("revision",0))}

static func prepare_legacy_station_body_repair(world:Dictionary,request:Dictionary,expected_revision:int) -> Dictionary:
	if int(world.get("revision",0))!=expected_revision:return {"ok":false,"error":"规划已变化，请重新检查后再修复。"}
	var group:Dictionary={}
	for candidate in groups(world,true):
		if str(candidate.get("historicalLineId",""))==str(request.get("lineId","")) and candidate.get("stationIds",[]).has(str(request.get("historicalId",""))):group=candidate;break
	if group.is_empty():return {"ok":false,"error":"本章目标已变化，无法安全修复。"}
	var repair:=legacy_station_body_repair(world,group,str(request.get("historicalId","")))
	if repair.is_empty() or str(repair.get("connectedStationId",""))!=str(request.get("connectedStationId","")) or str(repair.get("duplicateStationId",""))!=str(request.get("duplicateStationId","")):
		return {"ok":false,"error":"站体或轨道已变化；为避免移动或删除你的建设，本次没有修改。请重新检查。"}
	var candidate:=world.duplicate(true)
	var kept:Dictionary={}
	for station in candidate.get("stations",[]):
		if str(station.get("id",""))==str(repair.connectedStationId):kept=station;break
	if kept.is_empty():return {"ok":false,"error":"已接轨的旧站体不存在。"}
	candidate.stations=candidate.stations.filter(func(station:Dictionary):return str(station.get("id",""))!=str(repair.duplicateStationId))
	candidate.trackNodes=candidate.trackNodes.filter(func(node:Dictionary):return str(node.get("stationId",""))!=str(repair.duplicateStationId))
	kept.stationInstanceId=str(repair.canonicalInstanceId)
	kept.stationLineId=str(repair.lineId)
	kept.stationLineName=str(repair.lineName)
	var validation:=SaveManager.validate(candidate)
	if not validation.is_empty():return {"ok":false,"error":"修复预览未通过存档检查：%s" % validation}
	return {"ok":true,"world":candidate,"repair":repair}

static func _station_for_instance(world:Dictionary,instance_id:String) -> Dictionary:
	for station in world.get("stations",[]):
		if str(station.get("stationInstanceId",station.get("id","")))==instance_id:return station
	return {}

static func _angle_delta(a:float,b:float) -> float:
	return absf(fposmod(a-b+180.0,360.0)-180.0)

static func nearest_target(world: Dictionary, latlng: Array, selected_task_id:String="") -> Dictionary:
	var result: Dictionary = {}
	var best := INF
	var ref_lat := float(WorldData.city(str(world.get("cityId", ""))).get("center", [31.23])[0])
	for target in targets(world, false, selected_task_id):
		if bool(target.get("existingTransferAnchor",false)):continue
		if bool(target.get("built", false)): continue
		var distance := Geo.local_m(latlng, ref_lat).distance_to(Geo.local_m(target.latlng, ref_lat))
		if distance <= float(target.toleranceM) and distance < best:
			result = target; best = distance
	return result

static func blueprint(world: Dictionary, show_previous: bool = false, selected_task_id:String="") -> Dictionary:
	var stations := targets(world, false, selected_task_id)
	var corridors: Array = []
	var engineering_markers:Array=[]
	var map: Dictionary = {}
	for target in stations: map[str(target.id)] = target
	for group in groups(world, false, selected_task_id):
		if Engineering.is_group(group):
			for endpoint in group.get("engineeringEndpoints",[]):
				if not endpoint.has("stationId"):engineering_markers.append({"id":endpoint.id,"name":str(endpoint.name),"latlng":endpoint.latlng})
			for segment in group.get("engineeringSegments",[]):corridors.append({"points":segment.get("points",[]),"targets":[],"precision":"schematic","referenceLabel":"工程近似走廊"})
			continue
		var points: Array = []; var corridor_targets: Array = []
		for id_value in group.get("stationIds", []):
			var instance_id:=station_instance_id(group,str(id_value))
			if map.has(instance_id):
				points.append(map[instance_id].latlng)
				corridor_targets.append(map[instance_id])
		for i in range(corridor_targets.size()-1):
			var a:Dictionary=corridor_targets[i];var b:Dictionary=corridor_targets[i+1]
			var reference:=ReferenceAlignment.between(str(a.referenceId),str(b.referenceId)) if plan_is_final(world) else {}
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
	return {"visible":(not stations.is_empty() or not engineering_markers.is_empty()) and str(state.get("stage","intro"))!="outcome", "stations":stations, "engineeringMarkers":engineering_markers,"corridors":corridors, "previous":previous, "title":chapter(world).get("title", ""), "date":chapter(world).get("date", ""), "draftOnly":not plan_is_final(world)}

static func plan_is_final(world: Dictionary) -> bool:
	var versions: Array = chapter(world).get("story", {}).get("planVersions", [])
	return versions.is_empty() or int(world.get("storyPlan", {}).get("planIndex", 0)) == versions.size() - 1

static func evaluate(world: Dictionary, selected_task_id: String = "") -> Dictionary:
	var issues: Array[Dictionary] = []
	var routes: Array = []
	var engineering_complete:=0
	var ch := chapter(world)
	if ch.is_empty(): return {"complete":false,"issues":[{"text":"当前没有可验收章节。"}],"routes":[],"revision":int(world.get("revision",0))}
	var all_groups: Array = groups(world, true)
	var scoped_groups: Array = all_groups
	var selected_group_index := -1
	if not selected_task_id.is_empty():
		scoped_groups = []
		for group_index in range(all_groups.size()):
			var candidate: Dictionary = all_groups[group_index]
			if task_id(ch, candidate, group_index) == selected_task_id:
				selected_group_index = group_index
				scoped_groups.append(candidate)
				break
		if scoped_groups.is_empty():
			return {"complete":false,"issues":[{"text":"当前建设任务已不存在，请刷新任务列表。","kind":"task"}],"routes":[],"revision":int(world.get("revision",0)),"taskId":selected_task_id}
	if not plan_is_final(world): issues.append({"text":"请先在故事页对比并采用本章的最终修订方案。", "kind":"plan"})
	if bool(ch.get("requiresLineReorganization",false)) and not bool(world.get("storyPlan",{}).get("reorganizationAccepted",false)):issues.append({"text":"请使用下方「线路整理」核对并确认本期贯通站序。","kind":"plan"})
	var reference_lat := float(WorldData.city(str(world.cityId)).get("center", [31.23])[0])
	var path_index := TrackNetwork.build_path_index(world, reference_lat)
	var reference_map: Dictionary = {}
	for target in targets(world, true, selected_task_id): reference_map[str(target.id)] = target
	var bindings: Dictionary = {}
	for station in world.get("stations", []):
		var id := str(station.get("stationInstanceId",station.get("id","")))
		if id.is_empty(): continue
		if bindings.has(id): issues.append({"text":"同一个物理站体目标被绑定到两座车站。", "objectId":str(station.id), "kind":"station"})
		bindings[id] = station
	for scoped_index in range(scoped_groups.size()):
		var group: Dictionary = scoped_groups[scoped_index]
		if Engineering.is_group(group):
			var engineering_result:=Engineering.evaluate(world,group,path_index)
			issues.append_array(engineering_result.issues)
			if bool(engineering_result.complete):engineering_complete+=1
			continue
		var group_index := selected_group_index if selected_group_index >= 0 else scoped_index
		var ids: Array = []; var paths: Array = []; var group_valid := true;var repair_targets_reported:Dictionary={}
		for target_index in range(group.get("stationIds",[]).size()):
			var target_id := str(group.stationIds[target_index])
			var instance_id:=station_instance_id(group,target_id)
			var target: Dictionary = reference_map.get(instance_id, {})
			var station: Dictionary = bindings.get(instance_id, {})
			if station.is_empty(): station = bound_station(world,target_id,instance_id,str(group.get("historicalLineId", "")))
			if station.is_empty():
				issues.append({"text":"尚未建设：%s（%s线路站体）" % [str(target.get("name", target_id)),str(group.get("name","本期"))], "kind":"target", "objectId":instance_id,"latlng":target.get("latlng", [])}); group_valid = false; continue
			var expected_complex := Catalog.canonical_station_complex(str(world.get("cityId", "")), target_id)
			var actual_complex := Catalog.canonical_station_complex(str(world.get("cityId", "")), str(station.get("stationComplexId",station.get("historicalId",""))))
			if actual_complex != expected_complex:
				issues.append({"text":"该站体绑定到了错误的历史站区。","kind":"station","objectId":str(station.id)});group_valid=false
			var distance := Geo.local_m(station.latlng, reference_lat).distance_to(Geo.local_m(target.get("latlng", station.latlng), reference_lat))
			if distance > float(target.get("toleranceM",100)):
				issues.append({"text":"%s 超出目标站区 %.0f 米容差。" % [str(target.get("name","车站")),float(target.get("toleranceM",100))],"kind":"station","objectId":str(station.id),"latlng":station.latlng,"referenceTargetId":instance_id}); group_valid = false
			if group.get("stationNames",{}).has(target_id) and str(station.get("name",""))!=str(target.get("name","")) and not _uses_planned_names(world,group):
				issues.append({"text":"请在车站详情将「%s」更名为本章名称「%s」。" % [str(station.get("name","车站")),str(target.name)],"kind":"station","objectId":str(station.id),"latlng":station.latlng});group_valid=false
			ids.append(str(station.id))
		if not group_valid: continue
		var prior_end := ""
		var first_departure := ""
		for i in range(ids.size()-1):
			var path_key := "%d:%d" % [group_index,i]
			var path_choices: Dictionary = world.get("storyPlan",{}).get("pathChoices",{})
			var choice := int(path_choices.get(path_key,0))
			var options:Array[Dictionary]=[]
			if path_choices.has(path_key):
				# Preserve the selected route while avoiding enumeration of unused
				# alternatives during full-network chapter evaluation. A choice of 0
				# needs only the shortest route; choice N needs the first N+1.
				options=TrackNetwork.station_path_options_indexed(str(ids[i]),str(ids[i+1]),world,path_index,reference_lat,clampi(choice+1,1,4))
			else:
				var default_path:=TrackNetwork.shortest_station_path_indexed(str(ids[i]),str(ids[i+1]),world,path_index,reference_lat)
				if bool(default_path.get("valid",false)):options.append(default_path)
			if options.is_empty():
				var repair:Dictionary={}
				for candidate_index in [i,i+1]:
					var candidate_historical_id:=str(group.stationIds[candidate_index])
					repair=legacy_station_body_repair(world,group,candidate_historical_id)
					if not repair.is_empty():break
				if not repair.is_empty():
					var duplicate_id:=str(repair.get("duplicateStationId",""))
					if not repair_targets_reported.has(duplicate_id):
						repair_targets_reported[duplicate_id]=true
						var connected_station:Dictionary=WorldData.find_station(world,str(repair.get("connectedStationId","")))
						issues.append({"text":"这段轨道已接到旧版「%s」站体，但章节目标是%s。轨道与站位一致，可修复站体关联并保留现有轨道。" % [str(repair.get("stationName","车站")),str(repair.get("lineName","本期线路"))],"kind":"legacy_station_binding","objectId":str(repair.get("connectedStationId","")),"latlng":connected_station.get("latlng",[]),"stationBindingRepair":repair})
				else:
					var from_station:Dictionary=WorldData.find_station(world,str(ids[i]));var to_station:Dictionary=WorldData.find_station(world,str(ids[i+1]))
					issues.append({"text":"尚未接通：%s—%s" % [str(from_station.get("name","车站")),str(to_station.get("name","车站"))],"kind":"station","objectId":str(ids[i]),"latlng":from_station.get("latlng",[])})
				group_valid=false; continue
			var path: Dictionary = path_option_for_segment(options, choice, prior_end, path_choices.has(path_key))
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
			if not path.edges.is_empty():
				if first_departure.is_empty():first_departure=str(path.edges[0].get("fromNodeId",""))
				prior_end=str(path.edges[-1].get("toNodeId",""))
			# Exact centerlines are evaluated only when sourced geometry is available.
			var corridor: Array = group.get("alignment",[])
			var pair_reference:=ReferenceAlignment.between(str(group.stationIds[i]),str(group.stationIds[i+1]))
			if not str(group.get("requiredPlanningCorridorId","")).is_empty():
				var corridor_error:=ReferenceAlignment.planning_corridor_issue(path.points,str(group.requiredPlanningCorridorId),reference_lat,float(group.get("planningCorridorToleranceM",0)))
				if not corridor_error.is_empty():issues.append({"text":corridor_error,"kind":"station","objectId":str(ids[i])});group_valid=false
			if str(pair_reference.get("precision",""))=="verified_alignment" and ReferenceAlignment.corridor_issue(path.points,pair_reference.points,reference_lat,float(group.get("alignmentToleranceM",80))):
				issues.append({"text":"该区间偏离对应站间的核验走廊，或跳过必经走向。","kind":"station","objectId":str(ids[i])});group_valid=false
			if corridor.size() >= 2 and str(ch.get("precision","")) == "verified_alignment":
				for point in path.points:
					var nearest := INF; var local := Geo.local_m(point,reference_lat)
					for j in range(corridor.size()-1): nearest=minf(nearest,local.distance_to(Geometry2D.get_closest_point_to_segment(local,Geo.local_m(corridor[j],reference_lat),Geo.local_m(corridor[j+1],reference_lat))))
					if nearest > float(group.get("alignmentToleranceM",80)):
						issues.append({"text":"区间明显偏离已核验参考走廊。","kind":"station","objectId":str(ids[i])});group_valid=false;break
			paths.append(ordered)
		if bool(group.get("loop",false)) and not prior_end.is_empty() and prior_end==first_departure:
			issues.append({"text":"环线首站的闭合区间与出发区间接在同一站端，尚未形成连续环线。","kind":"station","objectId":str(ids[0])});group_valid=false
		# A status action belongs to its named line. A chapter can reconcile
		# many other open lines at the same time; do not reset them to built.
		var has_status_action:bool=ch.get("serviceTransitions",[]).any(func(t:Dictionary):return str(t.get("historicalLineId",""))==str(group.get("historicalLineId","")))
		var default_status:="open" if bool(ch.get("requireOpen",true)) and not has_status_action else "built"
		default_status=str(group.get("defaultServiceStatus",default_status))
		var segment_statuses:Array=[]
		for segment_index in range(paths.size()):
			segment_statuses.append("built" if bool(group.get("constructionVariant",false)) else _effective_service_status(world,str(group.get("historicalLineId","")),str(ids[segment_index]),str(ids[segment_index+1]),default_status))
		var any_open:=segment_statuses.any(func(status:String):return status in ["trial","open"])
		var service_status:="built"
		if segment_statuses.all(func(status:String):return status=="open"):service_status="open"
		elif segment_statuses.all(func(status:String):return status=="trial"):service_status="trial"
		elif segment_statuses.has("trial") or segment_statuses.has("open"):service_status="mixed"
		elif not segment_statuses.is_empty() and segment_statuses.all(func(status:String):return status=="suspended"):service_status="suspended"
		var route := {"id":"historical_%s" % str(group.get("historicalLineId", group.get("name","line"))),"name":str(group.get("name","线路")),"color":str(group.get("color","#36769c")),"stationOrder":ids,"networkBased":true,"vehicleId":str(group.get("vehicleId",profile(world).get("vehicleId","historical-schematic"))),"open":any_open,"serviceStatus":service_status,"directions":[{"id":"forward","stationIds":ids,"edgePathsBySegment":paths,"serviceStatusBySegment":segment_statuses}],"historicalLineId":str(group.get("historicalLineId",group.get("name","line"))),"chapterId":str(ch.get("id",""))}
		if bool(group.get("replaceExistingService",false)):route["replaceExistingService"]=true
		if not str(group.get("servicePatternId","")).is_empty():route.directions[0]["servicePatternId"]=str(group.servicePatternId)
		if bool(group.get("constructionVariant",false)):
			route["constructionVariantId"]=str(group.get("taskId",group.get("coverageGroupId","")))
			route["id"]+="_construction_"+str(route.constructionVariantId).sha256_text().substr(0,12)
		if _uses_planned_names(world,group):
			var planned_names:Dictionary={}
			for index in range(ids.size()):planned_names[str(ids[index])]=str(reference_map.get(station_instance_id(group,str(group.stationIds[index])),{}).get("name",""))
			route["plannedStationNames"]=planned_names
			route["plannedNameSource"]=str(group.stationNamingSource)
		if bool(group.get("reconfirmLaterServices",false)):route["reconfirmLaterServices"]=true
		if group.has("retainDocumentedFutureService"):route["retainDocumentedFutureService"]=bool(group.retainDocumentedFutureService)
		if group_valid and paths.size()==maxi(0,ids.size()-1):
			var canonical := Paths.for_route(route,world,reference_lat,path_index)
			if not bool(canonical.get("valid",false)):
				issues.append({"text":"%s：%s" % [route.name,"；".join(canonical.get("errors",[]))],"kind":"route"})
			routes.append(route)
	for connection in ch.get("requiredConnections",[]):
		if not selected_task_id.is_empty() and (not scoped_groups[0].get("stationIds",[]).has(str(connection.get("fromId",""))) or not scoped_groups[0].get("stationIds",[]).has(str(connection.get("toId","")))): continue
		var a:=bound_station(world,str(connection.fromId));var b:=bound_station(world,str(connection.toId))
		if a.is_empty() or b.is_empty() or not bool(TrackNetwork.shortest_station_path_indexed(str(a.get("id","")),str(b.get("id","")),world,path_index,reference_lat).get("valid",false)):
			issues.append({"text":str(connection.get("description","需要连接前后建设段。")),"kind":"target","objectId":str(connection.fromId),"latlng":a.get("latlng",[])})
	for transfer in ch.get("requiredTransfers",[]):
		# A line task commits its own physical route first. The separate,
		# explicitly confirmed transfer action remains a chapter-level condition.
		if not selected_task_id.is_empty(): continue
		if str(transfer.get("status",""))=="reserved":
			var reservation_errors:Array[String]=["预留换乘只能在未开放的规划建设篇确认。"] if bool(ch.get("requireOpen",true)) or str(world.get("storyState",{}).get("phase","history"))!="future" else Reservation.errors(world,transfer,groups(world,true))
			for issue in reservation_errors:issues.append({"text":issue,"kind":"transfer","objectId":str(transfer.get("complexId",""))})
			if reservation_errors.is_empty() and not Reservation.saved_matches(world,transfer):issues.append({"text":"%s：工程站体已就绪，请确认预留换乘接口；它还不是已开放换乘。"%str(transfer.get("name","本期站区")),"kind":"transfer","objectId":str(transfer.get("complexId","")),"pendingConfirmation":true})
			continue
		var transfer_ok:=true
		var instance_ids:Array=transfer.get("stationInstanceIds",[])
		var line_ids:Array=transfer.get("lineIds",[])
		var transfer_stations:Dictionary={}
		for transfer_index in range(instance_ids.size()):
			var instance_id := str(instance_ids[transfer_index])
			var transfer_line_id := str(line_ids[transfer_index]) if transfer_index < line_ids.size() else ""
			var physical:Dictionary=bindings.get(instance_id,{})
			if physical.is_empty(): physical=bound_station(world,str(transfer.get("complexId","")),instance_id,transfer_line_id)
			var expected_transfer_complex := Catalog.canonical_station_complex(str(world.get("cityId", "")), str(transfer.get("complexId", "")))
			var actual_transfer_complex := Catalog.canonical_station_complex(str(world.get("cityId", "")), str(physical.get("stationComplexId",physical.get("historicalId","")))) if not physical.is_empty() else ""
			if physical.is_empty() or actual_transfer_complex!=expected_transfer_complex:
				transfer_ok=false
			else:transfer_stations[instance_id]=physical
		if instance_ids.size()<2 or line_ids.size()<2 or transfer_stations.size()!=instance_ids.size():transfer_ok=false
		if not transfer_ok:issues.append({"text":"尚未建设%s的各线路独立站体。" % str(transfer.get("name","本期换乘站")),"kind":"transfer","objectId":str(transfer.get("complexId",""))});continue
		for line_index in range(line_ids.size()):
			var line_id:=str(line_ids[line_index])
			var body_id:=str(transfer_stations[str(instance_ids[line_index])].get("id","")) if line_index<instance_ids.size() else ""
			var line_route:=route_for_station_body(routes,line_id,body_id)
			# A transfer milestone often adds the second line, while the first
			# line was confirmed in an earlier chapter. Resolve that line from the
			# saved formal network instead of demanding that both lines be rebuilt
			# in the current chapter. A same-line route may also be split across
			# historical segments; select the route that actually contains this
			# station body instead of the first route with the matching line ID.
			if line_route.is_empty():
				var existing_routes:Array=world.get("routes",[]).filter(func(route:Dictionary):return bool(route.get("networkBased",false)))
				line_route=route_for_station_body(existing_routes,line_id,body_id)
			if line_route.is_empty():
				var line_name:=line_id
				for group in groups(world,true):
					if str(group.get("historicalLineId",""))==line_id:line_name=str(group.get("name",line_id));break
				issues.append({"text":"%s所需的%s尚未形成连续站序；请先修复上方列出的站间连接问题。" % [str(transfer.get("name","本期换乘站")),line_name],"kind":"transfer","objectId":str(transfer.get("complexId",""))});transfer_ok=false;break
			if body_id.is_empty() or not _route_contains_station_body(line_route,body_id):
				issues.append({"text":"%s的独立站体没有接入对应线路%s。" % [str(transfer.get("name","本期换乘站")),line_id],"kind":"transfer","objectId":str(transfer.get("complexId",""))});transfer_ok=false;break
		if transfer_ok and instance_ids.size()!=line_ids.size():
			issues.append({"text":"%s的线路与物理站体对应关系不完整。" % str(transfer.get("name","本期换乘站")),"kind":"transfer","objectId":str(transfer.get("complexId",""))});transfer_ok=false
		if transfer_ok:
			var linked:=false
			for saved in world.get("transferConnections",[]):
				if str(saved.get("id",""))!=str(transfer.get("id","")) or str(saved.get("status","active"))!="active":continue
				if JSON.stringify(saved.get("stationInstanceIds",[]))==JSON.stringify(instance_ids) and JSON.stringify(saved.get("lineIds",[]))==JSON.stringify(line_ids) and str(saved.get("transferKind","interchange"))==str(transfer.get("transferKind","interchange")):
					linked=true
					break
			if not linked:issues.append({"text":"%s：两侧独立站体和线路已就绪，请明确确认建立换乘联系。" % str(transfer.get("name","本章换乘站")),"kind":"transfer","pendingConfirmation":true,"objectId":str(transfer.get("complexId",""))})
	var service_transitions:Array=[]
	for transition_index in range(ch.get("serviceTransitions",[]).size()):
		var transition:Dictionary=ch.serviceTransitions[transition_index]
		var line_id:=str(transition.get("historicalLineId",""));var matched_route:Dictionary={};var matched_group:Dictionary={}
		if not selected_task_id.is_empty() and str(scoped_groups[0].get("historicalLineId","")) != line_id: continue
		for route in routes:
			if str(route.get("historicalLineId",""))==line_id:matched_route=route;break
		for group in groups(world,true):
			if str(group.get("historicalLineId",""))==line_id:matched_group=group;break
		var proposal:=_service_transition_proposal(world,transition,transition_index,matched_route,matched_group)
		if proposal.is_empty():
			issues.append({"text":"历史服务状态范围无法匹配到本期连续站序；请核对资料配置。","kind":"service","objectId":line_id})
			continue
		service_transitions.append(proposal)
		if not _has_service_range(world, str(proposal.id)):
			issues.append({"text":"请明确确认%s「%s」的%s范围。" % [str(transition.get("historicalLineId","本期线路")),"—".join(transition.get("displayStationNames",[])),service_status_label(str(transition.get("status","built")))],"kind":"service","objectId":str(proposal.id),"latlng":proposal.get("focusLatlng",[])})
	return {"complete":issues.is_empty() and routes.size()+engineering_complete==scoped_groups.size(),"issues":issues,"routes":routes,"engineeringComplete":engineering_complete,"serviceRanges":world.get("serviceRanges",[]).duplicate(true),"serviceTransitions":service_transitions,"requiredTransfers":[] if not selected_task_id.is_empty() else ch.get("requiredTransfers",[]),"revision":int(world.get("revision",0)),"chapterId":str(ch.get("id","")),"taskId":selected_task_id,"taskScoped":not selected_task_id.is_empty(),"taskCount":all_groups.size()}

static func _has_service_range(world:Dictionary,range_id:String) -> bool:
	for saved in world.get("serviceRanges",[]):
		if str(saved.get("id",""))==range_id and bool(saved.get("confirmed",true)):return true
	return false

static func _effective_service_status(world:Dictionary,line_id:String,from_station_id:String,to_station_id:String,fallback:String) -> String:
	var latest_date:="";var status:=fallback
	for saved in world.get("serviceRanges",[]):
		if str(saved.get("historicalLineId",""))!=line_id:continue
		var ids:Array=saved.get("stationIds",[])
		var includes:=false
		for index in range(maxi(0,ids.size()-1)):
			if (str(ids[index])==from_station_id and str(ids[index+1])==to_station_id) or (str(ids[index])==to_station_id and str(ids[index+1])==from_station_id):includes=true;break
		if includes:
			var date:=str(saved.get("effectiveDate",""))
			if date>=latest_date:latest_date=date;status=str(saved.get("status",fallback))
	return status

static func _route_contains_station_body(route:Dictionary,station_id:String) -> bool:
	if route.get("stationOrder",[]).has(station_id):return true
	for direction in route.get("directions",[]):
		if direction.get("stationIds",[]).has(station_id):return true
	return false

static func route_for_station_body(routes:Array,line_id:String,station_id:String) -> Dictionary:
	for route in routes:
		if route is Dictionary and str(route.get("historicalLineId",""))==line_id and _route_contains_station_body(route,station_id):return route
	return {}

static func _service_transition_proposal(world:Dictionary,transition:Dictionary,transition_index:int,route:Dictionary,group:Dictionary) -> Dictionary:
	if route.is_empty() or group.is_empty():return {}
	var targets:Array=transition.get("stationIds",[]);var group_ids:Array=group.get("stationIds",[])
	if targets.size()<2 or targets.size()>group_ids.size():return {}
	var first_index:=group_ids.find(str(targets[0]));if first_index<0:return {}
	for index in range(targets.size()):
		if first_index+index>=group_ids.size() or str(group_ids[first_index+index])!=str(targets[index]):return {}
	var station_ids:Array=route.get("stationOrder",[]);var directions:Array=route.get("directions",[])
	var unique_count:=group_ids.size()-1 if group_ids.size()>2 and group_ids.front()==group_ids.back() else group_ids.size()
	var loop_route:bool=bool(group.get("loop",false)) and station_ids.size()==unique_count+1 and station_ids.front()==station_ids.back()
	if (station_ids.size()!=group_ids.size() and not loop_route) or directions.is_empty():return {}
	var include_closing:bool=bool(transition.get("includeClosingSegment",false))
	if include_closing and (not loop_route or first_index!=0 or targets.size()!=unique_count):return {}
	var all_paths:Array=directions[0].get("edgePathsBySegment",[])
	if all_paths.size()!=station_ids.size()-1:return {}
	var physical_stations:=station_ids.slice(first_index,first_index+targets.size())
	var paths:=all_paths.slice(first_index,first_index+targets.size()-1)
	if include_closing:
		physical_stations.append(physical_stations[0]);paths.append(all_paths[-1])
	var names:Array[String]=[];var focus:Array=[]
	for offset in range(targets.size()):
		var instance_id:=station_instance_id(group,str(targets[offset]));var station:=bound_station(world,str(targets[offset]),instance_id)
		if station.is_empty():return {}
		names.append(str(station.get("name","车站")))
		if focus.is_empty():focus=station.get("latlng",[])
	if include_closing:names.append(names[0])
	var line_id:=str(transition.get("historicalLineId",""));var status:=str(transition.get("status",""));var chapter_id:=str(chapter(world).get("id",""))
	if status not in ["built","trial","open","suspended"]:return {}
	var transition_id:=str(transition.get("id","%s_%d" % [line_id,transition_index]))
	return {"id":"service_%s_%s" % [chapter_id,transition_id],"chapterId":chapter_id,"routeId":str(route.get("id","")),"historicalLineId":line_id,"stationIds":physical_stations,"edgePathsBySegment":paths,"status":status,"effectiveDate":str(chapter(world).get("date","")),"source":str(transition.get("source",chapter(world).get("source",""))),"confirmed":true,"displayStationNames":names,"focusLatlng":focus}

static func task_confirmed(world: Dictionary, selected_task_id: String) -> bool:
	var ch := chapter(world)
	if ch.is_empty() or selected_task_id.is_empty(): return false
	var chapter_progress: Dictionary = world.get("storyState", {}).get("chapterTaskProgress", {}).get(str(ch.get("id", "")), {})
	var task_progress: Dictionary = chapter_progress.get("tasks", {})
	var record:Dictionary=task_progress.get(selected_task_id,{})
	if str(record.get("status",""))!="confirmed":return false
	if bool(ch.get("requiresScopeRecheck",false)):
		return str(record.get("scopeFingerprint",""))==task_scope_fingerprint(world,selected_task_id)
	return true

static func task_scope_fingerprint(world:Dictionary,selected_task_id:String) -> String:
	var ch:=chapter(world)
	var all_groups:=groups(world,true)
	for index in range(all_groups.size()):
		if task_id(ch,all_groups[index],index)==selected_task_id:
			var fingerprint:=Catalog.group_scope_fingerprint(all_groups[index])
			var corrections:Array=ch.get("scopeCorrections",[]).filter(func(c:Dictionary):return str(c.get("taskId",""))==selected_task_id)
			if not corrections.is_empty():fingerprint+=":corrections:"+JSON.stringify(corrections).sha256_text()
			return fingerprint
	return ""

static func confirmed_task_count(world: Dictionary) -> int:
	var ch := chapter(world)
	if ch.is_empty(): return 0
	var chapter_progress: Dictionary = world.get("storyState", {}).get("chapterTaskProgress", {}).get(str(ch.get("id", "")), {})
	var task_progress: Dictionary = chapter_progress.get("tasks", {})
	var count := 0
	for group_index in range(groups(world, true).size()):
		if task_confirmed(world,task_id(ch, groups(world, true)[group_index], group_index)): count += 1
	return count

static func _merge_route_directions(existing_direction: Dictionary, incoming_direction: Dictionary) -> Dictionary:
	# Explicit operating patterns may use different platforms at the same
	# named station. Never reverse, concatenate or absorb one into the other.
	var old_pattern:=str(existing_direction.get("servicePatternId",""))
	var new_pattern:=str(incoming_direction.get("servicePatternId",""))
	if (not old_pattern.is_empty() or not new_pattern.is_empty()) and old_pattern!=new_pattern:return {}
	var old_ids: Array = existing_direction.get("stationIds", [])
	var old_paths: Array = existing_direction.get("edgePathsBySegment", [])
	var new_ids: Array = incoming_direction.get("stationIds", [])
	var new_paths: Array = incoming_direction.get("edgePathsBySegment", [])
	if old_ids.is_empty() or new_ids.is_empty(): return {}
	# Two sections can be authored in opposite geographic directions. A single
	# shared endpoint permits reversal; a shared trunk does not, because that
	# would turn a real branch into a path traversing the trunk twice.
	var common:Array=[]
	for id in new_ids:
		if old_ids.has(id) and not common.has(id):common.append(id)
	var reverse_ids:=new_ids.duplicate();reverse_ids.reverse()
	var reverse_is_contained:=false
	for offset in range(maxi(0,old_ids.size()-reverse_ids.size()+1)):
		if old_ids.slice(offset,offset+reverse_ids.size())==reverse_ids:reverse_is_contained=true;break
	for offset in range(maxi(0,reverse_ids.size()-old_ids.size()+1)):
		if reverse_ids.slice(offset,offset+old_ids.size())==old_ids:reverse_is_contained=true;break
	if reverse_is_contained or (common.size()==1 and (old_ids.front()==new_ids.front() or old_ids.back()==new_ids.back())):
		incoming_direction=_reverse_service_direction(incoming_direction)
		new_ids=incoming_direction.stationIds;new_paths=incoming_direction.edgePathsBySegment
	var mode := ""
	var overlap := 0
	if old_ids == new_ids:
		mode = "same"
	else:
		for size in range(mini(old_ids.size(), new_ids.size()), 0, -1):
			if old_ids.slice(old_ids.size() - size) == new_ids.slice(0, size):
				mode = "append"; overlap = size; break
		if mode.is_empty():
			for size in range(mini(old_ids.size(), new_ids.size()), 0, -1):
				if new_ids.slice(new_ids.size() - size) == old_ids.slice(0, size):
					mode = "prepend"; overlap = size; break
	# A later opening can replace an obsolete schematic gap between two stops.
	if mode.is_empty() and new_ids.size() >= 2:
		var start_index := old_ids.find(new_ids.front())
		var end_index := old_ids.find(new_ids.back())
		if start_index >= 0 and end_index > start_index:
			var old_section: Array = old_ids.slice(start_index, end_index + 1)
			var new_cursor := 0
			var contains_old_section := true
			for station_id in old_section:
				while new_cursor < new_ids.size() and str(new_ids[new_cursor]) != str(station_id): new_cursor += 1
				if new_cursor >= new_ids.size(): contains_old_section = false; break
				new_cursor += 1
			if contains_old_section: mode = "insert"
	if mode.is_empty(): return {}
	if mode == "same":
		var same := existing_direction.duplicate(true)
		same["edgePathsBySegment"] = new_paths.duplicate(true) if not new_paths.is_empty() else old_paths.duplicate(true)
		same["serviceStatusBySegment"] = incoming_direction.get("serviceStatusBySegment",existing_direction.get("serviceStatusBySegment",[])).duplicate()
		return {"direction": same, "mode": mode}
	var merged_ids: Array = []
	var merged_paths: Array = []
	var merged_statuses:Array=[]
	var old_statuses:Array=existing_direction.get("serviceStatusBySegment",[])
	var new_statuses:Array=incoming_direction.get("serviceStatusBySegment",[])
	if mode == "append":
		merged_ids = old_ids.duplicate(); merged_ids.append_array(new_ids.slice(overlap))
		merged_paths = old_paths.duplicate(true)
		if overlap < new_ids.size(): merged_paths.append_array(new_paths.slice(overlap - 1))
		merged_statuses=old_statuses.duplicate()
		if overlap < new_ids.size():merged_statuses.append_array(new_statuses.slice(overlap-1))
	elif mode == "prepend":
		merged_ids = new_ids.duplicate(); merged_ids.append_array(old_ids.slice(overlap))
		merged_paths = new_paths.duplicate(true)
		if overlap < old_ids.size(): merged_paths.append_array(old_paths.slice(overlap - 1))
		merged_statuses=new_statuses.duplicate()
		if overlap < old_ids.size():merged_statuses.append_array(old_statuses.slice(overlap-1))
	else:
		var start_index := old_ids.find(new_ids.front())
		var end_index := old_ids.find(new_ids.back())
		merged_ids.append_array(old_ids.slice(0, start_index))
		merged_ids.append_array(new_ids)
		merged_ids.append_array(old_ids.slice(end_index + 1))
		merged_paths.append_array(old_paths.slice(0, start_index))
		merged_paths.append_array(new_paths)
		merged_paths.append_array(old_paths.slice(end_index))
		merged_statuses.append_array(old_statuses.slice(0,start_index))
		merged_statuses.append_array(new_statuses)
		merged_statuses.append_array(old_statuses.slice(end_index))
	# Sharing an endpoint does not license traversing an overlapping trunk
	# twice (for example an old built west arm and a newer full trial route).
	# Preserve them as separate directions instead of manufacturing a reversal.
	var seen_stops:Dictionary={}
	for index in range(merged_ids.size()):
		var id:=str(merged_ids[index])
		if seen_stops.has(id) and not (index==merged_ids.size()-1 and id==str(merged_ids.front())):return {}
		seen_stops[id]=true
	var merged := existing_direction.duplicate(true)
	merged["stationIds"] = merged_ids
	merged["edgePathsBySegment"] = merged_paths
	# An opening event can reconfirm an overlapping existing section without
	# extending either endpoint. Its segment statuses still replace the prior
	# built-only values; unrelated earlier segments retain their own status.
	merged_statuses=[]
	for index in range(merged_ids.size()-1):
		var status:="built"
		var old_index:=old_ids.find(merged_ids[index])
		if old_index>=0 and old_index+1<old_ids.size() and old_ids[old_index+1]==merged_ids[index+1] and old_index<old_statuses.size():status=str(old_statuses[old_index])
		var new_index:=new_ids.find(merged_ids[index])
		if new_index>=0 and new_index+1<new_ids.size() and new_ids[new_index+1]==merged_ids[index+1] and new_index<new_statuses.size():status=str(new_statuses[new_index])
		merged_statuses.append(status)
	merged["serviceStatusBySegment"] = merged_statuses
	return {"direction": merged, "mode": mode}

static func _reverse_service_direction(direction:Dictionary) -> Dictionary:
	var reversed:=direction.duplicate(true)
	reversed.stationIds.reverse()
	var paths:Array=[]
	var old_paths:Array=direction.get("edgePathsBySegment",[]).duplicate(true);old_paths.reverse()
	for segment in old_paths:
		if segment is Array:
			segment.reverse()
			for reference in segment:
				if reference is Dictionary:reference["forward"]=not bool(reference.get("forward",true))
		paths.append(segment)
	reversed.edgePathsBySegment=paths
	if reversed.get("serviceStatusBySegment") is Array:reversed.serviceStatusBySegment.reverse()
	return reversed

static func _merge_historical_route(existing: Dictionary, incoming: Dictionary) -> Dictionary:
	if existing.is_empty(): return incoming.duplicate(true)
	# A complete closed circuit is authoritative for this line, rather than an
	# extension to append to an earlier open circuit from the same project.
	var incoming_order:Array=incoming.get("stationOrder",[])
	if incoming_order.size()>2 and incoming_order.front()==incoming_order.back() and not incoming.get("directions",[]).any(func(d:Dictionary):return not str(d.get("servicePatternId","")).is_empty()):return incoming.duplicate(true)
	var result := existing.duplicate(true)
	var old_directions: Array = result.get("directions", []).duplicate(true)
	var new_directions: Array = incoming.get("directions", []).duplicate(true)
	for direction in old_directions:_fill_direction_statuses(direction,existing)
	for direction in new_directions:_fill_direction_statuses(direction,incoming)
	if old_directions.is_empty() or new_directions.is_empty():
		result.merge(incoming, true)
		return result
	for incoming_direction_value in new_directions:
		var incoming_direction: Dictionary = incoming_direction_value
		var matched_index := -1
		var merged_direction: Dictionary = {}
		for direction_index in range(old_directions.size()):
			var merge_result := _merge_route_directions(old_directions[direction_index], incoming_direction)
			if merge_result.is_empty(): continue
			matched_index = direction_index
			merged_direction = merge_result.direction
			break
		if matched_index < 0:
			# Disconnected opening sections remain separate until a later project
			# physically joins them; sharing a line number does not invent a link.
			var branch := incoming_direction.duplicate(true)
			branch["id"] = "segment_%s_%d" % [str(incoming.get("chapterId", "new")), old_directions.size()]
			old_directions.append(branch)
			continue
		old_directions[matched_index] = merged_direction
		# One segment may connect two previously separate operating sections.
		# Absorb every direction whose physical endpoint now joins this path.
		var absorbed := true
		while absorbed:
			absorbed = false
			for direction_index in range(old_directions.size()):
				if direction_index == matched_index: continue
				var merge_result := _merge_route_directions(old_directions[matched_index], old_directions[direction_index])
				if merge_result.is_empty(): merge_result = _merge_route_directions(old_directions[direction_index], old_directions[matched_index])
				if merge_result.is_empty(): continue
				old_directions[matched_index] = merge_result.direction
				old_directions.remove_at(direction_index)
				if direction_index < matched_index: matched_index -= 1
				absorbed = true
				break
	result.merge(incoming, true)
	result["directions"] = old_directions
	if not old_directions.is_empty(): result["stationOrder"] = old_directions[0].get("stationIds", []).duplicate()
	result["name"] = incoming.get("name", result.get("name", "线路"))
	result["color"] = incoming.get("color", result.get("color", "#36769c"))
	result["networkBased"] = true
	result["chapterId"] = incoming.get("chapterId", result.get("chapterId", ""))
	var statuses:Array=[]
	for direction in old_directions:statuses.append_array(direction.get("serviceStatusBySegment",[]))
	result["open"] = statuses.any(func(status:String):return status in ["open","trial"])
	result["serviceStatus"] = str(statuses[0]) if not statuses.is_empty() and statuses.all(func(status:String):return status==str(statuses[0])) else "mixed"
	return result

static func _fill_direction_statuses(direction:Dictionary,route:Dictionary) -> void:
	var count:=maxi(0,direction.get("stationIds",[]).size()-1)
	if direction.get("serviceStatusBySegment",[]).size()==count:return
	var fallback:=str(route.get("serviceStatus","open" if bool(route.get("open",false)) else "built"))
	if fallback=="mixed":fallback="built"
	var statuses:Array=[]
	for index in range(count):statuses.append(fallback)
	direction["serviceStatusBySegment"]=statuses

static func _store_historical_route(world: Dictionary, route: Dictionary) -> void:
	# An unopened infill or future realignment is physical construction, not
	# permission to reroute the existing open service through the new station.
	if not str(route.get("constructionVariantId","")).is_empty():
		for index in range(world.get("routes",[]).size()):
			if str(world.routes[index].get("constructionVariantId",""))==str(route.constructionVariantId):
				world.routes[index]=route.duplicate(true);return
		world.routes.append(route.duplicate(true));return
	var route_index := -1
	for index in range(world.get("routes", []).size()):
		var saved: Dictionary = world.routes[index]
		if not str(saved.get("constructionVariantId","")).is_empty():continue
		if str(saved.get("id", "")) == str(route.get("id", "")) or (str(route.get("historicalLineId", "")) != "" and str(saved.get("historicalLineId", "")) == str(route.get("historicalLineId", ""))):
			route_index = index; break
	if route_index < 0: world.routes.append(route.duplicate(true))
	elif bool(route.get("replaceExistingService",false)):
		var replacement:=route.duplicate(true)
		# A cutoff correction in an old save can coexist with completed future
		# extensions. Preserve only their documented, physically continuous
		# sections from the previous service; never append an arbitrary old path.
		if str(chapter(world).get("chapterScope",""))=="cutoff_reconciliation" and bool(route.get("retainDocumentedFutureService",true)):
			for plan in Catalog.city_config(str(world.cityId)).get("futurePlans",[]):
				var state:Dictionary=world.get("storyState",{})
				if not state.get("completedChapterIds",[]).has(str(plan.id)) and not state.get("serviceReconfirmationIds",[]).has(str(plan.id)) and not state.get("legacyTaskProgress",{}).has(str(plan.id)):continue
				for group in plan.get("lineGroups",[]):
					if str(group.get("historicalLineId",""))==str(route.get("historicalLineId","")):
						replacement=_preserve_documented_service_section(world,world.routes[route_index],replacement,group)
		# A second arm can be built and confirmed first. Replacing an obsolete
		# service must preserve that already-confirmed arm, while discarding
		# unrelated ghost directions. No task is confirmed by this preservation.
		for group in groups(world,true):
			if str(group.get("historicalLineId",""))!=str(route.get("historicalLineId","")) or bool(group.get("replaceExistingService",false)):continue
			var group_index:=groups(world,true).find(group)
			if not task_confirmed(world,task_id(chapter(world),group,group_index)):continue
			var wanted:Array=[]
			for id in group.get("stationIds",[]):
				var station:=_station_for_instance(world,station_instance_id(group,str(id)))
				if not station.is_empty():wanted.append(str(station.id))
			if wanted.size()!=group.get("stationIds",[]).size():continue
			for direction in world.routes[route_index].get("directions",[]):
				var ids:Array=direction.get("stationIds",[])
				for offset in range(maxi(0,ids.size()-wanted.size()+1)):
					if ids.slice(offset,offset+wanted.size())!=wanted:continue
					var retained:Dictionary=direction.duplicate(true)
					retained.stationIds=wanted.duplicate()
					retained.edgePathsBySegment=direction.get("edgePathsBySegment",[]).slice(offset,offset+wanted.size()-1)
					retained.serviceStatusBySegment=direction.get("serviceStatusBySegment",[]).slice(offset,offset+wanted.size()-1)
					retained.id="confirmed_branch_"+str(group.get("coverageGroupId",group_index))
					replacement=_merge_historical_route(replacement,{"chapterId":route.get("chapterId",""),"historicalLineId":route.get("historicalLineId",""),"directions":[retained]})
					break
		world.routes[route_index]=replacement
		_recheck_future_services_after_cutoff_correction(world,route)
		_recheck_later_historical_services(world,route)
	else:
		var existing:Dictionary=_scope_upgrade_route_base(world,world.routes[route_index],route)
		if str(existing.get("chapterId",""))==str(route.get("chapterId","")):
			# Reconfirming a corrected task replaces that task's former physical
			# platform bindings, rather than adding an obsolete parallel service.
			var retained:Array=[]
			for old_direction in existing.get("directions",[]):
				var old_complexes:=_direction_complexes(world,old_direction)
				var replaced:=false
				for new_direction in route.get("directions",[]):
					if str(old_direction.get("servicePatternId",""))!=str(new_direction.get("servicePatternId","")) and (not str(old_direction.get("servicePatternId","")).is_empty() or not str(new_direction.get("servicePatternId","")).is_empty()):continue
					var new_complexes:=_direction_complexes(world,new_direction)
					if old_complexes==new_complexes or _scope_contains(new_complexes,old_complexes):replaced=true;break
				if not replaced:retained.append(old_direction)
			existing["directions"]=retained
			if retained.is_empty():world.routes[route_index]=route.duplicate(true);return
		world.routes[route_index] = _merge_historical_route(existing, route)

static func _preserve_documented_service_section(world:Dictionary,old_route:Dictionary,replacement:Dictionary,group:Dictionary) -> Dictionary:
	# An earlier release may have merged a future construction variant into
	# the live service. Preserve its geometry, not that erroneous open branch.
	# Its normal future task will explicitly restore the separate variant.
	if bool(group.get("constructionVariant",false)):return replacement
	var wanted:Array=[]
	for id in group.get("stationIds",[]):
		var station:=_station_for_instance(world,station_instance_id(group,str(id)))
		if station.is_empty():return replacement
		wanted.append(str(station.id))
	if wanted.size()<2:return replacement
	var reverse_wanted:=wanted.duplicate();reverse_wanted.reverse()
	for direction in old_route.get("directions",[]):
		var ids:Array=direction.get("stationIds",[])
		for offset in range(maxi(0,ids.size()-wanted.size()+1)):
			var section:=ids.slice(offset,offset+wanted.size())
			if section!=wanted and section!=reverse_wanted:continue
			var paths:Array=direction.get("edgePathsBySegment",[])
			if paths.size()!=ids.size()-1:continue
			var retained:Dictionary=direction.duplicate(true)
			retained.stationIds=section
			retained.edgePathsBySegment=paths.slice(offset,offset+wanted.size()-1)
			retained.serviceStatusBySegment=direction.get("serviceStatusBySegment",[]).slice(offset,offset+wanted.size()-1)
			retained.id="retained_documented_extension"
			var merged:=_merge_historical_route(replacement,{"chapterId":replacement.get("chapterId",""),"historicalLineId":replacement.get("historicalLineId",""),"directions":[retained]})
			var check_world:=world.duplicate(false);check_world.routes=[merged]
			var issue:=changed_service_continuity_error(check_world,[merged])
			if issue.is_empty():return merged
			# An old extension can have been committed against the wrong terminal
			# end by a former release. Keep its physical work and exact old path,
			# but do not poison the corrected historical service with a reversal.
			# The future task is already explicitly queued for reconfirmation.
			var pending:Array=replacement.get("legacyUnjoinedDirections",[]).duplicate(true)
			pending.append({"direction":retained,"reason":issue,"source":str(group.get("source",group.get("stationOrderSource",""))),"requiresReconnection":true})
			replacement["legacyUnjoinedDirections"]=pending
			return replacement
	return replacement

static func _recheck_future_services_after_cutoff_correction(world:Dictionary,route:Dictionary) -> void:
	if str(chapter(world).get("chapterScope",""))!="cutoff_reconciliation" and not bool(route.get("reconfirmLaterServices",false)):return
	var state:Dictionary=world.get("storyState",{})
	var completed:Array=state.get("completedChapterIds",[])
	var line_id:=str(route.get("historicalLineId",""))
	for plan in Catalog.city_config(str(world.cityId)).get("futurePlans",[]):
		var id:=str(plan.get("id",""))
		if not completed.has(id):continue
		if not _plan_uses_line(plan,line_id):continue
		# The dated correction replaces service, never construction. Retain the
		# earlier completion as evidence and ask to reconfirm the future service
		# from the already-built track instead of silently losing its extension.
		var archived:Dictionary=state.get("legacyTaskProgress",{})
		archived[id]=state.get("chapterTaskProgress",{}).get(id,{}).duplicate(true)
		state["legacyTaskProgress"]=archived
		state.get("chapterTaskProgress",{}).erase(id)
		completed.erase(id)
		var pending:Array=state.get("serviceReconfirmationIds",[])
		if not pending.has(id):pending.append(id)
		state["serviceReconfirmationIds"]=pending

static func _plan_uses_line(plan:Dictionary,line_id:String) -> bool:
	if plan.get("lineGroups",[]).any(func(group:Dictionary):return str(group.get("historicalLineId",""))==line_id):return true
	return plan.get("requiredTransfers",[]).any(func(transfer:Dictionary):return transfer.get("lineIds",[]).has(line_id))

## A corrected early scope can replace an old modern snapshot. Keep later
## construction and milestones, but explicitly restore the affected service
## through its dated task. Otherwise a retained completion flag can skip the
## later extension after the earlier service is corrected.
static func _recheck_later_historical_services(world:Dictionary,route:Dictionary) -> void:
	if not bool(route.get("reconfirmLaterServices",false)):return
	var current:=chapter(world)
	var state:Dictionary=world.get("storyState",{})
	var line_id:=str(route.get("historicalLineId",""))
	for plan in Catalog.city_config(str(world.cityId)).get("chapters",[]):
		var id:=str(plan.get("id",""))
		if str(plan.get("date",""))<=str(current.get("date","")) or not state.get("completedChapterIds",[]).has(id):continue
		if not _plan_uses_line(plan,line_id):continue
		var archived:Dictionary=state.get("legacyTaskProgress",{})
		archived[id]=state.get("chapterTaskProgress",{}).get(id,{}).duplicate(true)
		state["legacyTaskProgress"]=archived
		state.get("chapterTaskProgress",{}).erase(id)
		state.completedChapterIds.erase(id)
		var pending:Array=state.get("serviceReconfirmationIds",[])
		if not pending.has(id):pending.append(id)
		state["serviceReconfirmationIds"]=pending

static func _scope_contains(new_ids:Array,old_ids:Array) -> bool:
	if old_ids.size()<2 or new_ids.size()<old_ids.size() or new_ids.front()!=old_ids.front() or new_ids.back()!=old_ids.back():return false
	var cursor:=0
	for id in new_ids:
		if cursor<old_ids.size() and old_ids[cursor]==id:cursor+=1
	return cursor==old_ids.size()

static func _scope_upgrade_route_base(world:Dictionary,existing:Dictionary,incoming:Dictionary) -> Dictionary:
	var id:=str(incoming.get("chapterId",""))
	if not world.get("storyState",{}).get("legacyTaskProgress",{}).has(id):return existing.duplicate(true)
	# A reconfirmed task is already the new authority. A chapter-wide commit
	# must not rewind it to a stale milestone's "before" snapshot merely because
	# the corrected path happens to equal an earlier milestone's "after" path.
	if id==str(chapter(world).get("id","")):
		var all_groups:=groups(world,true)
		for index in range(all_groups.size()):
			var group:Dictionary=all_groups[index]
			if str(group.get("historicalLineId",""))!=str(incoming.get("historicalLineId","")):continue
			var wanted:Array=[]
			for station_id in group.get("stationIds",[]):
				var body:=_station_for_instance(world,station_instance_id(group,str(station_id)))
				if not body.is_empty():wanted.append(str(body.id))
			if wanted==incoming.get("stationOrder",[]) and task_confirmed(world,task_id(chapter(world),group,index)):return existing.duplicate(true)
	for milestone in world.get("storyState",{}).get("milestones",[]):
		if str(milestone.get("chapterId",""))!=id:continue
		var change:Dictionary=milestone.get("planningDiff",{}).get("fields",{}).get("routes",{}).get("items",{}).get(str(existing.get("id","")),{})
		var after:Variant=change.get("after")
		if after is Dictionary and after.get("stationOrder",[])==existing.get("stationOrder",[]) and after.get("directions",[])==existing.get("directions",[]):
			var before:Variant=change.get("before")
			var base:Dictionary=before.duplicate(true) if before is Dictionary else {}
			# Reconfirming one task must not roll an unchanged, disconnected
			# sibling back to the chapter's old before-state. In an upgraded save
			# that sibling may already support an explicit interchange. Preserve
			# only the exact current source-defined body order and valid physical
			# path; neither its task nor any event is marked confirmed here.
			if id==str(chapter(world).get("id","")):
				for sibling in groups(world,true):
					if str(sibling.get("historicalLineId",""))!=str(incoming.get("historicalLineId","")):continue
					var wanted:Array=[]
					for station_id in sibling.get("stationIds",[]):
						var body:=_station_for_instance(world,station_instance_id(sibling,str(station_id)))
						if not body.is_empty():wanted.append(str(body.id))
					var reverse_wanted:=wanted.duplicate();reverse_wanted.reverse()
					if wanted==incoming.get("stationOrder",[]) or reverse_wanted==incoming.get("stationOrder",[]):continue
					base=_preserve_documented_service_section(world,existing,base,sibling)
			return base
	return existing.duplicate(true)

static func _direction_complexes(world:Dictionary,direction:Dictionary) -> Array:
	var result:Array=[]
	for id in direction.get("stationIds",[]):
		var station:=WorldData.find_station(world,str(id))
		result.append(Catalog.canonical_station_complex(str(world.cityId),str(station.get("stationComplexId",station.get("historicalId",id)))))
	return result

## Content corrections are explicit, sourced proposals. Loading never applies
## them; the player accepts them together with the corrected task's route.
static func scope_correction_preview(world:Dictionary, selected_task_id:String) -> Dictionary:
	var ch:=chapter(world)
	var changes:Array=[]
	# Inserted old tasks can be replayed in a save that already contains later
	# source-recorded interchanges. Retire the exact later pairing explicitly
	# while the earlier service is restored, retaining its record and all works.
	# Unknown/player-edited pairs are never silently changed.
	var replaced_lines:Dictionary={};var allowed_bodies:Dictionary={}
	for group in groups(world,true,selected_task_id):
		if bool(group.get("replaceExistingService",false)):replaced_lines[str(group.get("historicalLineId",""))]=str(group.get("stationOrderSource",ch.get("source","")))
	for group in groups(world,true):
		var line_id:=str(group.get("historicalLineId",""))
		if not allowed_bodies.has(line_id):allowed_bodies[line_id]=[]
		for id in group.get("stationIds",[]):allowed_bodies[line_id].append(station_instance_id(group,str(id)))
	var known_pairs:Dictionary={}
	var config:=Catalog.city_config(str(world.cityId))
	for node in config.get("chapters",[])+config.get("futurePlans",[]):
		for pairing in node.get("requiredTransfers",[]):known_pairs[str(pairing.id)]=pairing
	for connection in world.get("transferConnections",[]):
		if str(connection.get("status","active"))!="active":continue
		if connection.get("lineIds",[]).size()!=connection.get("stationInstanceIds",[]).size():return {"ok":false,"error":"换乘配对不完整，请先核对；本次不会改写。","changes":[]}
		var explicit:=false
		for correction in ch.get("scopeCorrections",[]):
			if str(correction.get("transferId",""))==str(connection.get("id","")) and (selected_task_id.is_empty() or str(correction.get("taskId",""))==selected_task_id):explicit=true;break
		if explicit:continue
		var missing_line:=""
		for index in range(connection.get("lineIds",[]).size()):
			var line_id:=str(connection.lineIds[index])
			if replaced_lines.has(line_id) and not allowed_bodies.get(line_id,[]).has(str(connection.get("stationInstanceIds",[])[index])):missing_line=line_id;break
		if missing_line.is_empty():continue
		var known:Dictionary=known_pairs.get(str(connection.get("id","")),{})
		if known.is_empty() or known.get("lineIds",[])!=connection.get("lineIds",[]) or known.get("stationInstanceIds",[])!=connection.get("stationInstanceIds",[]):
			return {"ok":false,"error":"换乘「%s」的配对已自定义；请先核对，本次不会自动删除或改配。"%str(connection.get("name","换乘")),"changes":[]}
		changes.append({"id":str(connection.id),"text":"%s：本期尚未开放此线路站体，保留建设和原联系记录，在其对应的后续任务重新确认换乘。"%str(connection.get("name","换乘")),"source":str(replaced_lines[missing_line])})
	if str(ch.get("chapterScope",""))=="cutoff_reconciliation" or groups(world,true,selected_task_id).any(func(group:Dictionary):return bool(group.get("reconfirmLaterServices",false))):
		var lines:Array=[]
		for group in groups(world,true,selected_task_id):
			if bool(group.get("replaceExistingService",false)):lines.append(str(group.get("historicalLineId","")))
		for plan in Catalog.city_config(str(world.cityId)).get("futurePlans",[]):
			if not world.get("storyState",{}).get("completedChapterIds",[]).has(str(plan.id)):continue
			if lines.any(func(line_id:String):return _plan_uses_line(plan,line_id)):
				changes.append({"id":"future-service-recheck:"+str(plan.id),"text":"%s：保留已经建设的站轨，截止日线路更正后重新确认该规划篇线路关系。"%str(plan.get("title","后续建设")),"source":str(ch.get("source",""))})
	for correction in ch.get("scopeCorrections",[]):
		if not selected_task_id.is_empty() and str(correction.get("taskId",""))!=selected_task_id:continue
		if not str(correction.get("restoreAfterTaskId","")).is_empty() and task_confirmed(world,str(correction.restoreAfterTaskId)):continue
		if correction.has("obsoleteService"):
			var obsolete:Dictionary=correction.obsoleteService
			var wanted:Array=obsolete.get("stationInstanceIds",[])
			var preserved:Array=obsolete.get("preservedStationInstanceIds",[])
			if not preserved.is_empty() and (preserved.size()<2 or wanted.slice(0,preserved.size())!=preserved):
				return {"ok":false,"error":"旧版线路更正的保留范围无效，本次不会修改。","changes":[]}
			for route in world.get("routes",[]):
				if str(route.get("historicalLineId",""))!=str(obsolete.get("historicalLineId","")):continue
				for direction in route.get("directions",[]):
					var instances:Array=[]
					for id in direction.get("stationIds",[]):instances.append(str(WorldData.find_station(world,str(id)).get("stationInstanceId",id)))
					var reversed:=instances.duplicate();reversed.reverse()
					if instances==wanted or reversed==wanted:
						var change:Dictionary={"kind":"archive_service_direction","id":str(route.id),"stationIds":direction.stationIds.duplicate(),"text":str(correction.description),"source":str(correction.source)}
						if not preserved.is_empty():
							var retained:Dictionary=direction.duplicate(true)
							if reversed==wanted:retained=_reverse_service_direction(direction)
							retained.stationIds=retained.stationIds.slice(0,preserved.size())
							retained.edgePathsBySegment=retained.get("edgePathsBySegment",[]).slice(0,preserved.size()-1)
							retained.serviceStatusBySegment=retained.get("serviceStatusBySegment",[]).slice(0,preserved.size()-1)
							change["retainedDirection"]=retained
						changes.append(change)
					elif instances.filter(func(id:Variant):return wanted.has(id)).size()>1:
						# An already corrected service may include later documented
						# extensions. Only the known obsolete suffix needs removal.
						if not preserved.is_empty() and not instances.any(func(id:Variant):return wanted.slice(preserved.size()).has(id)):continue
						return {"ok":false,"error":"原规划支线的站序已经修改，请先核对线路归属，本次不会覆盖。","changes":[]}
			continue
		if correction.has("bodyLineReclassification"):
			var reclassification:Dictionary=correction.bodyLineReclassification
			var station:=_station_for_instance(world,str(reclassification.stationInstanceId))
			if station.is_empty() or str(station.get("stationLineId",""))==str(reclassification.newLineId):continue
			if str(station.get("stationLineId",""))!=str(reclassification.oldLineId):return {"ok":false,"error":"站体线路归属已经修改，请先核对，本次不会覆盖。","changes":[]}
			changes.append({"kind":"reclassify_station_line","id":str(station.id),"newLineId":str(reclassification.newLineId),"newLineName":str(reclassification.get("newLineName","")),"text":str(correction.description),"source":str(correction.source)})
			continue
		for connection in world.get("transferConnections",[]):
			if str(connection.get("id",""))!=str(correction.get("transferId","")) or str(connection.get("status","active"))!="active":continue
			if not correction.get("bodyRebindings",[]).is_empty():
				if connection.get("lineIds",[])!=correction.get("oldLineIds",[]):return {"ok":false,"error":"旧换乘线路已被修改，请先核对 %s。"%str(connection.get("name","换乘")),"changes":[]}
				var current_ids:Array=connection.get("stationInstanceIds",[]).duplicate()
				var changed:=false
				for binding in correction.bodyRebindings:
					var index:=int(binding.index)
					if index<0 or index>=current_ids.size():return {"ok":false,"error":"换乘站体配对不完整，请先核对 %s。"%str(connection.get("name","换乘")),"changes":[]}
					if current_ids[index]==binding.newStationInstanceId:continue
					if current_ids[index]!=binding.oldStationInstanceId:return {"ok":false,"error":"旧换乘站体已被修改，请先核对 %s，不能自动替换。"%str(connection.get("name","换乘")),"changes":[]}
					current_ids[index]=binding.newStationInstanceId;changed=true
				if changed:changes.append({"id":str(connection.id),"text":str(correction.get("description","")),"source":str(correction.get("source","")),"newStationInstanceIds":current_ids})
				continue
			if not correction.get("newStationInstanceIds",[]).is_empty() and connection.get("lineIds",[])==correction.get("newLineIds",correction.get("oldLineIds",[])) and connection.get("stationInstanceIds",[])==correction.get("newStationInstanceIds",[]):continue
			var known_old_pair:bool=connection.get("stationInstanceIds",[])==correction.get("oldStationInstanceIds",[]) or correction.get("alternativeOldStationInstanceIds",[]).has(connection.get("stationInstanceIds",[]))
			if connection.get("lineIds",[])!=correction.get("oldLineIds",[]) or not known_old_pair:
				return {"ok":false,"error":"旧换乘关系已被修改，请先核对 %s，不能自动替换。"%str(connection.get("name","换乘")),"changes":[]}
			changes.append({"id":str(connection.id),"text":str(correction.get("description","")),"source":str(correction.get("source","")),"newStationInstanceIds":correction.get("newStationInstanceIds",[]).duplicate(),"newLineIds":correction.get("newLineIds",connection.get("lineIds",[])).duplicate()})
	return {"ok":true,"changes":changes}

static func _apply_scope_corrections(candidate:Dictionary, preview:Dictionary) -> void:
	for change in preview.get("changes",[]):
		if str(change.get("kind",""))=="archive_service_direction":
			for route in candidate.get("routes",[]):
				if str(route.id)!=str(change.id):continue
				var retained:Array=[];var archive:Array=route.get("legacyDirections",[]).duplicate(true)
				for direction in route.get("directions",[]):
					if direction.get("stationIds",[])==change.stationIds:
						archive.append({"direction":direction.duplicate(true),"reason":change.text,"source":change.source})
						if change.has("retainedDirection"):retained.append(change.retainedDirection.duplicate(true))
					else:retained.append(direction)
				route.directions=retained;route["legacyDirections"]=archive
				route.stationOrder=[] if retained.is_empty() else retained[0].get("stationIds",[]).duplicate()
				if retained.is_empty():route["open"]=false;route["retired"]=true
				elif change.has("retainedDirection"):
					# Trimming a documented obsolete suffix may expose the joint
					# where its corrected extension was already built. Rejoin the
					# actual directed paths, retaining genuine forks separately.
					var normalized:Dictionary=route.duplicate(true)
					normalized.directions=[];normalized.stationOrder=[]
					for direction in retained:
						var section:Dictionary=route.duplicate(false)
						section.directions=[direction];section.stationOrder=direction.stationIds
						normalized=_merge_historical_route(normalized,section)
					route.directions=normalized.directions;route.stationOrder=normalized.stationOrder
					var segment_statuses:Array=[]
					for direction in normalized.directions:segment_statuses.append_array(direction.get("serviceStatusBySegment",[]))
					route["open"]=segment_statuses.any(func(status:String):return status in ["open","trial"])
					route["serviceStatus"]=str(segment_statuses[0]) if not segment_statuses.is_empty() and segment_statuses.all(func(status:String):return status==str(segment_statuses[0])) else "mixed"
			continue
		if str(change.get("kind",""))=="reclassify_station_line":
			for station in candidate.get("stations",[]):
				if str(station.id)!=str(change.id):continue
				station["previousStationLineId"]=station.get("stationLineId","")
				station["stationLineId"]=change.newLineId;station["stationLineName"]=change.newLineName
				station["lineReclassificationSource"]=change.source
			continue
		for connection in candidate.get("transferConnections",[]):
			if str(connection.get("id",""))!=str(change.id):continue
			if not change.get("newStationInstanceIds",[]).is_empty():
				connection["previousStationInstanceIds"]=connection.get("stationInstanceIds",[]).duplicate()
				connection["stationInstanceIds"]=change.newStationInstanceIds.duplicate()
				if change.has("newLineIds"):
					connection["previousLineIds"]=connection.get("lineIds",[]).duplicate()
					connection["lineIds"]=change.newLineIds.duplicate()
			else:connection["status"]="superseded"
			connection["supersededByScopeRevision"]=str(chapter(candidate).get("scopeRevision",""))
			connection["supersededReason"]=str(change.text)
			connection["correctionSource"]=str(change.source)

static func _refresh_route_memberships(world: Dictionary) -> void:
	for station in world.get("stations", []): station["routeIds"] = []
	var physical_edges := TrackNetwork.all_physical_edges(world)
	var edges_by_id: Dictionary = {}
	for edge in physical_edges:
		edge["routeIds"] = []
		edges_by_id[str(edge.get("id", ""))] = edge
	for route in world.get("routes", []):
		if not bool(route.get("open", false)): continue
		for station in world.get("stations", []):
			for direction in route.get("directions", []):
				if direction.get("stationIds", route.get("stationOrder", [])).has(str(station.get("id", ""))):
					if not station.routeIds.has(str(route.get("id", ""))): station.routeIds.append(str(route.get("id", "")))
			for direction in route.get("directions", []):
				for segment in direction.get("edgePathsBySegment", []):
					for reference in segment:
						var edge: Dictionary = edges_by_id.get(str(reference.get("id", "")), {})
						if not edge.is_empty() and not edge.routeIds.has(str(route.get("id", ""))): edge.routeIds.append(str(route.get("id", "")))

## Check the joined service, not just each newly built subsection. A two-stop
## extension can be valid in isolation but reverse at its existing terminus.
static func changed_service_continuity_error(world:Dictionary,changed_routes:Array) -> String:
	var line_ids:Array=[]
	for route in changed_routes:line_ids.append(str(route.get("historicalLineId","")))
	var ref_lat:=float(WorldData.city(str(world.cityId)).get("center",[0])[0])
	var path_index:=TrackNetwork.build_path_index(world,ref_lat)
	for route in world.get("routes",[]):
		if bool(route.get("retired",false)) or not line_ids.has(str(route.get("historicalLineId",""))):continue
		for direction in route.get("directions",[]):
			var ids:Array=direction.get("stationIds",[]);var paths:Array=direction.get("edgePathsBySegment",[])
			if ids.size()<2 or paths.size()!=ids.size()-1:return "线路站序与区间走向数量不一致，请重新检查。"
			var prior_arrival:="";var first_departure:=""
			for index in range(paths.size()):
				var path:=TrackNetwork.ordered_station_path(str(ids[index]),str(ids[index+1]),paths[index],world,ref_lat,path_index)
				if not bool(path.get("valid",false)):return "线路接续无效："+str(path.get("error","区间断开"))
				if prior_arrival==str(path.fromNodeId):return "%s 的延伸接到了原进站端，形成隐含折返；请从另一站端接出并重新预览。"%str(WorldData.find_station(world,str(ids[index])).get("name","接续站"))
				if first_departure.is_empty():first_departure=str(path.fromNodeId)
				prior_arrival=str(path.toNodeId)
			if ids.front()==ids.back() and first_departure==prior_arrival:return "环线在首站同端折返，请核对闭合区间。"
	return ""

static func confirm_task(world: Dictionary, selected_task_id: String, expected_revision: int, checked: Dictionary = {}) -> Dictionary:
	if expected_revision != int(world.get("revision", 0)): return {"ok":false,"error":"规划已变化，请重新检查当前任务。"}
	var ch := chapter(world)
	if ch.is_empty() or bool(ch.get("eventOnly", false)): return {"ok":false,"error":"当前章节没有可确认的建设任务。"}
	if world.get("storyState", {}).get("completedChapterIds", []).has(str(ch.get("id", ""))): return {"ok":false,"error":"本章历史节点已经确认。"}
	if task_confirmed(world, selected_task_id): return {"ok":false,"error":"这项建设任务已经确认。"}
	if not checked.is_empty() and (int(checked.get("revision", -1)) != expected_revision or str(checked.get("chapterId", "")) != str(ch.get("id", "")) or str(checked.get("taskId", "")) != selected_task_id): return {"ok":false,"error":"建设检查已过期，请重新检查当前任务。"}
	var result := checked if not checked.is_empty() else evaluate(world, selected_task_id)
	if not bool(result.get("complete", false)): return {"ok":false,"error":"当前任务还有未完成条件。","evaluation":result}
	var candidate: Dictionary = world.duplicate(true)
	var correction_preview:=scope_correction_preview(world,selected_task_id)
	if not bool(correction_preview.ok):return correction_preview
	for route in result.get("routes", []): _store_historical_route(candidate, route)
	_apply_scope_corrections(candidate,correction_preview)
	var continuity_error:=changed_service_continuity_error(candidate,result.get("routes",[]))
	if not continuity_error.is_empty():return {"ok":false,"error":continuity_error}
	_refresh_route_memberships(candidate)
	var validation := SaveManager.validate(candidate)
	if not validation.is_empty(): return {"ok":false,"error":"任务线路暂时无法保存：%s" % validation}
	world["routes"] = candidate.get("routes", []).duplicate(true)
	for key in ["stations", "trackEdges", "trackLinks", "transferConnections"]:
		world[key] = candidate.get(key, []).duplicate(true)
	var state: Dictionary = candidate.get("storyState", {}).duplicate(true)
	var progress_by_chapter: Dictionary = state.get("chapterTaskProgress", {})
	var progress: Dictionary = progress_by_chapter.get(str(ch.get("id", "")), {})
	var tasks: Dictionary = progress.get("tasks", {})
	var group_index := -1
	var all_groups := groups(world, true)
	for index in range(all_groups.size()):
		if task_id(ch, all_groups[index], index) == selected_task_id: group_index = index; break
	if group_index < 0: return {"ok":false,"error":"当前任务已不存在。"}
	var group: Dictionary = all_groups[group_index]
	var confirmed_routes:Array=result.get("routes",[])
	tasks[selected_task_id] = {"status":"confirmed","type":"engineering_track" if Engineering.is_group(group) else "line_group","historicalLineId":str(group.get("historicalLineId", "")),"confirmedAt":str(ch.get("date", "")),"routeId":"" if confirmed_routes.is_empty() else str(confirmed_routes[0].get("id", "")),"scopeFingerprint":task_scope_fingerprint(world,selected_task_id)}
	progress["status"] = "in_progress"
	progress["tasks"] = tasks
	progress["taskCount"] = all_groups.size()
	progress["confirmedTaskCount"] = tasks.values().filter(func(record:Dictionary): return str(record.get("status", "")) == "confirmed").size()
	progress["date"] = str(ch.get("date", ""))
	progress_by_chapter[str(ch.get("id", ""))] = progress
	state["chapterTaskProgress"] = progress_by_chapter
	world["storyState"] = state
	world["history"] = {"undo":[],"redo":[]}
	world["revision"] = int(world.get("revision", 0)) + 1
	return {"ok":true,"taskOnly":true,"taskId":selected_task_id,"confirmedTaskCount":int(progress.confirmedTaskCount),"taskCount":all_groups.size(),"allTasksConfirmed":int(progress.confirmedTaskCount) >= all_groups.size(),"revision":int(world.get("revision", 0))}

static func commit_chapter(world: Dictionary, expected_revision: int, checked: Dictionary = {}) -> Dictionary:
	if expected_revision != int(world.get("revision",0)): return {"ok":false,"error":"规划已变化，请重新检查本章。"}
	var current_chapter := chapter(world)
	if not checked.is_empty() and (int(checked.get("revision", -1)) != expected_revision or str(checked.get("chapterId", "")) != str(current_chapter.get("id", ""))): return {"ok":false,"error":"本章检查已过期，请重新检查。"}
	var result := checked if not checked.is_empty() else evaluate(world)
	if not bool(result.complete): return {"ok":false,"error":"仍有未完成的复现条件。","evaluation":result}
	var state: Dictionary = world.storyState
	var ch := chapter(world)
	if state.completedChapterIds.has(str(ch.id)): return {"ok":false,"error":"该历史节点已经确认。"}
	var chapter_groups := groups(world, true)
	if chapter_groups.size() > 1:
		var chapter_progress: Dictionary = state.get("chapterTaskProgress", {}).get(str(ch.id), {})
		var confirmed_tasks: Dictionary = chapter_progress.get("tasks", {})
		for group_index in range(chapter_groups.size()):
			var required_task_id := task_id(ch, chapter_groups[group_index], group_index)
			if not task_confirmed(world,required_task_id):
				return {"ok":false,"error":"请先逐项确认本章各条线路建设任务；未确认的任务不会被本次操作一并盖章。"}
	if not (state.get("chapterTaskProgress", null) is Dictionary): state["chapterTaskProgress"] = {}
	if not (state.get("confirmedHistoricalEventIds", null) is Array): state["confirmedHistoricalEventIds"] = []
	# A chapter-wide reconfirmation must apply the same sourced corrections
	# as task confirmation, including tasks already confirmed by an older pack.
	# Validate the complete candidate before changing progress or milestones.
	var correction_preview:=scope_correction_preview(world,"")
	if not bool(correction_preview.get("ok",false)):return correction_preview
	var candidate:=world.duplicate(true)
	for id in ch.get("retireRouteIds",[]):
		var old:=WorldData.find_route(candidate,str(id))
		if not old.is_empty():old["open"]=false;old["retired"]=true;old["retiredAt"]=str(ch.date)
	for route in result.routes: _store_historical_route(candidate, route)
	_apply_scope_corrections(candidate,correction_preview)
	var continuity_error:=changed_service_continuity_error(candidate,result.routes)
	if not continuity_error.is_empty():return {"ok":false,"error":continuity_error}
	_refresh_route_memberships(candidate)
	var candidate_error:=SaveManager.validate(candidate)
	if not candidate_error.is_empty():return {"ok":false,"error":"历史节点尚未确认：%s" % candidate_error}
	for key in ["stations","routes","trackEdges","trackLinks","transferConnections","storyState"]:
		world[key]=candidate.get(key,[] if key!="storyState" else {}).duplicate(true)
	state=world.storyState
	StoryTutorial.finish(world)
	if not world.get("serviceRanges",[]) is Array:world["serviceRanges"]=[]
	_refresh_route_memberships(world)
	var h := CommandHistory.new(); h.attach(world)
	var planning := h._capture_planning()
	var delta := h._build_diff(world.get("milestoneBaseline",{}),planning)
	state.milestones.append({"chapterId":str(ch.id),"date":str(ch.date),"title":str(ch.title),"planningDiff":delta,"source":str(ch.get("source","")),"assisted":bool(world.get("storyPlan",{}).get("assisted",false))})
	world["milestoneBaseline"]=planning.duplicate(true)
	state.completedChapterIds.append(str(ch.id))
	# A chapter that was queued for reconfirmation has now been re-confirmed
	# against the corrected network; keeping it pending would ask again forever.
	if state.get("serviceReconfirmationIds",[]) is Array:
		var still_pending:Array=state.get("serviceReconfirmationIds",[])
		still_pending.erase(str(ch.id))
		state["serviceReconfirmationIds"]=still_pending
	var interval:Dictionary=Catalog.milestone_interval(str(world.get("cityId","")),str(ch.id))
	var event_ids:Array=ch.get("historicalEventIds",[])
	if event_ids.is_empty():event_ids=[str(ch.id)]
	for event_id in event_ids:
		if not state.confirmedHistoricalEventIds.has(str(event_id)):state.confirmedHistoricalEventIds.append(str(event_id))
	state.chapterTaskProgress[str(ch.id)]={"status":"confirmed","confirmedHistoricalEventIds":event_ids.duplicate(),"tasks":Catalog.chapter_task_records(str(world.get("cityId","")),str(ch.id)),"date":str(ch.get("date","")),"scopeRevision":Catalog.chapter_scope_revision(ch)}
	state["stage"]="outcome"
	state["chapterId"]=str(ch.id)
	if bool(world.get("storyPlan",{}).get("assisted",false)) and not state.get("assistedChapters",[]).has(str(ch.id)):state.assistedChapters.append(str(ch.id))
	world["history"]={"undo":[],"redo":[]}
	world["revision"]=int(world.get("revision",0))+1
	return {"ok":true,"chapter":ch,"routeIds":result.routes.map(func(r:Dictionary):return str(r.id))}

## A chapter summary is derived from the same planning diff stored at its
## milestone. It deliberately reports topology and construction only; it does
## not invent demand, cost, or engineering scores.
static func chapter_changes(world: Dictionary) -> Dictionary:
	var ch := chapter(world)
	var milestones: Array = world.get("storyState", {}).get("milestones", [])
	if ch.is_empty() or milestones.is_empty(): return {}
	var milestone: Dictionary = milestones.back()
	if str(milestone.get("chapterId", "")) != str(ch.get("id", "")): return {}
	var fields: Dictionary = milestone.get("planningDiff", {}).get("fields", {})
	var added_station_ids: Array[String] = []
	var added_station_names: Array[String] = []
	var added_edges: Array[String] = []
	var changed_interchanges: Array[String] = []
	var new_routes: Array[String] = []
	for collection in ["stations", "trackEdges", "trackLinks", "routes", "transferConnections"]:
		var field: Dictionary = fields.get(collection, {})
		var item_changes: Dictionary = field.get("items", {}).duplicate(true)
		# Early 0.20 saves could have an empty, uninitialized milestone baseline.
		# Their first milestone used a whole-value diff instead of identified items.
		if str(field.get("type", "")) == "value" and field.get("after") is Array:
			for item in field.after:
				if item is Dictionary: item_changes[str(item.get("id", ""))] = {"before": null, "after": item}
		for id in item_changes:
			var change: Dictionary = item_changes[id]
			var before: Variant = change.get("before")
			var after: Variant = change.get("after")
			if before == null and after is Dictionary:
				if collection == "stations":
					added_station_ids.append(str(id)); added_station_names.append(str(after.get("name", "未命名站")))
				elif collection in ["trackEdges", "trackLinks"]: added_edges.append(str(id))
				elif collection == "routes": new_routes.append(str(after.get("name", "线路")))
				elif collection == "transferConnections": changed_interchanges.append(str(after.get("name", "换乘站")))
			if collection == "stations" and before is Dictionary and after is Dictionary:
				var old_routes: Array = before.get("routeIds", [])
				var current_routes: Array = after.get("routeIds", [])
				if old_routes.size() < 2 and current_routes.size() >= 2:
					changed_interchanges.append(str(after.get("name", "换乘站")))
	var reused_station_names: Array[String] = []
	var seen_reused: Dictionary = {}
	for group in ch.get("lineGroups", []):
		for id in group.get("stationIds", []):
			var station := bound_station(world, str(id))
			if not station.is_empty() and not added_station_ids.has(str(station.get("id", ""))) and not seen_reused.has(str(station.get("id", ""))):
				reused_station_names.append(str(station.get("name", "車站"))); seen_reused[str(station.get("id", ""))] = true
	var reference_lat := float(WorldData.city(str(world.get("cityId", ""))).get("center", [31.23])[0])
	var added_length := 0.0
	for id in added_edges:
		var edge: Dictionary = {}
		for candidate in TrackNetwork.all_physical_edges(world):
			if str(candidate.get("id", "")) == id: edge = candidate; break
		if not edge.is_empty(): added_length += TrackNetwork.edge_length_m(edge, world, reference_lat)
	var focus_results: Array[Dictionary] = []
	var pairs: Array = ch.get("focusPairs", [])
	if pairs.is_empty():
		for group in ch.get("lineGroups", []):
			var ids: Array = group.get("stationIds", [])
			if ids.size() >= 2: pairs.append({"fromId": ids.front(), "toId": ids.back()})
	for pair in pairs:
		if not pair is Dictionary: continue
		var from_id := str(pair.get("fromId", pair.get("from", "")))
		var to_id := str(pair.get("toId", pair.get("to", "")))
		var a := bound_station(world, from_id); var b := bound_station(world, to_id)
		var transfers := _minimum_route_transfers(world, str(a.get("id", "")), str(b.get("id", "")), reference_lat) if not a.is_empty() and not b.is_empty() else -1
		focus_results.append({"from": str(a.get("name", from_id)), "to": str(b.get("name", to_id)), "connected": transfers >= 0, "transfers": transfers})
	var next_targets: Array[String] = []
	var service_changes: Array[String] = []
	var service_field: Dictionary = fields.get("serviceRanges", {})
	for service_id in service_field.get("items", {}):
		var change: Dictionary = service_field.items[service_id]
		var after: Variant = change.get("after")
		if after is Dictionary:
			service_changes.append("%s：%s" % [str(after.get("historicalLineId", "线路")), service_status_label(str(after.get("status", "built")))])
	var chapters: Array = config(world).get("chapters", [])
	var current_index := int(world.get("storyState", {}).get("chapterIndex", 0))
	if current_index + 1 < chapters.size():
		var next_chapter: Dictionary = chapters[current_index + 1]
		for group in next_chapter.get("lineGroups", []):
			for id in group.get("stationIds", []):
				if bound_station(world, str(id)).is_empty():
					for data_station in WorldData.city(str(world.get("cityId", ""))).get("stations", []):
						if str(data_station.get("id", "")) == str(id): next_targets.append(str(group.get("stationNames", {}).get(str(id), data_station.get("name", "車站"))))
					if next_targets.size() >= 3: break
			if next_targets.size() >= 3: break
	return {"chapterId": str(ch.id), "addedStations": added_station_names, "reusedStations": reused_station_names, "addedTrackSections": added_edges.size(), "addedLengthM": added_length, "newRoutes": new_routes, "newInterchanges": changed_interchanges, "focusPairs": focus_results, "nextTargets": next_targets, "serviceChanges": service_changes}

## Precise offsets are shown only against a verified alignment. Station offsets
## remain explicitly tied to modern reference station areas, never survey data.
static func factual_report(world: Dictionary) -> Dictionary:
	var ref_lat := float(WorldData.city(str(world.get("cityId", ""))).get("center", [31.23])[0])
	var station_offsets: Array[Dictionary] = []
	for target in targets(world, true):
		if not bool(target.get("built", false)): continue
		var station := bound_station(world, str(target.get("id", "")), str(target.get("stationInstanceId", "")),str(target.get("historicalLineId", "")))
		if station.is_empty(): continue
		var distance := Geo.local_m(station.get("latlng", []), ref_lat).distance_to(Geo.local_m(target.get("latlng", []), ref_lat))
		station_offsets.append({"name": str(target.get("name", "车站")), "distanceM": distance, "toleranceM": float(target.get("toleranceM", 100.0)), "label": "相对现代地理参考站区中心；不是历史工程测量"})
	var segment_facts: Array[Dictionary] = []
	var all_groups := groups(world, true)
	for group_index in range(all_groups.size()):
		var group: Dictionary = all_groups[group_index]
		var ids: Array = group.get("stationIds", [])
		for index in range(ids.size() - 1):
			var a_id := str(ids[index]); var b_id := str(ids[index + 1])
			var a := bound_station(world, a_id, station_instance_id(group, a_id),str(group.get("historicalLineId", ""))); var b := bound_station(world, b_id, station_instance_id(group, b_id),str(group.get("historicalLineId", "")))
			if a.is_empty() or b.is_empty(): continue
			var options := TrackNetwork.station_path_options(str(a.id), str(b.id), world, ref_lat, 4)
			if options.is_empty(): continue
			var choice := int(world.get("storyPlan", {}).get("pathChoices", {}).get("%d:%d" % [group_index, index], 0))
			var option: Dictionary = options[clampi(choice, 0, options.size() - 1)]
			var alignment := ReferenceAlignment.between(a_id, b_id)
			var fact: Dictionary = {"from": str(a.get("name", a_id)), "to": str(b.get("name", b_id)), "lengthM": float(option.get("distanceM", 0.0)), "precision": ReferenceAlignment.label_for(alignment)}
			if str(alignment.get("precision", "")) == "verified_alignment":
				var distances: Array[float] = []
				for point in option.get("points", []): distances.append(_distance_to_polyline_m(point, alignment.get("points", []), ref_lat))
				if not distances.is_empty():
					var total := 0.0; var maximum := 0.0
					for distance in distances: total += distance; maximum = maxf(maximum, distance)
					fact["meanDeviationM"] = total / distances.size(); fact["maxDeviationM"] = maximum
			segment_facts.append(fact)
	return {"stationOffsets": station_offsets, "segments": segment_facts}

static func _distance_to_polyline_m(point: Array, line: Array, ref_lat: float) -> float:
	if line.size() < 2: return 0.0
	var p := Geo.local_m(point, ref_lat); var nearest := INF
	for index in range(line.size() - 1):
		nearest = minf(nearest, p.distance_to(Geometry2D.get_closest_point_to_segment(p, Geo.local_m(line[index], ref_lat), Geo.local_m(line[index + 1], ref_lat))))
	return nearest

static func service_status_label(status: String) -> String:
	match status:
		"built": return "工程建成，尚未记为试运营"
		"trial": return "有限试运营"
		"open": return "正式向社会开放运营"
		"mixed": return "本期各区间服务阶段不同"
		"suspended": return "因工程需要暂停开放，保留既有站轨"
		_: return "历史状态待核验"

static func _minimum_route_transfers(world: Dictionary, from_station: String, to_station: String, _ref_lat: float) -> int:
	if from_station == to_station: return 0
	var routes_at_station: Dictionary = {}
	var stations_by_route: Dictionary = {}
	for route in world.get("routes", []):
		if not bool(route.get("open", false)): continue
		var route_id := str(route.get("id", ""))
		var station_ids: Array = route.get("stationOrder", [])
		stations_by_route[route_id] = station_ids.duplicate()
		for station_value in station_ids:
			var station_id := str(station_value)
			if not routes_at_station.has(station_id): routes_at_station[station_id] = []
			routes_at_station[station_id].append(route_id)
	var transfer_peers: Dictionary = {}
	for transfer in world.get("transferConnections", []):
		if str(transfer.get("status", "active")) != "active": continue
		var physical_ids: Array[String] = []
		for instance_id in transfer.get("stationInstanceIds", []):
			for station in world.get("stations", []):
				if str(station.get("stationInstanceId", station.get("id", ""))) == str(instance_id):
					physical_ids.append(str(station.get("id", "")))
					break
		for source in physical_ids:
			if not transfer_peers.has(source): transfer_peers[source] = []
			for destination in physical_ids:
				if destination != source: transfer_peers[source].append(destination)
	var permitted_transfer_routes:Dictionary={}
	for transfer in world.get("transferConnections", []):
		if str(transfer.get("status", "active")) != "active": continue
		var instance_ids:Array=transfer.get("stationInstanceIds",[])
		var line_ids:Array=transfer.get("lineIds",[])
		for index in range(mini(instance_ids.size(),line_ids.size())):
			var instance_id=instance_ids[index]
			var permitted_route_id:=str(line_ids[index])
			for route in world.get("routes",[]):
				if str(route.get("id",""))==permitted_route_id or str(route.get("historicalLineId",""))==permitted_route_id:
					permitted_route_id=str(route.get("id",""));break
			for station in world.get("stations",[]):
				if str(station.get("stationInstanceId",station.get("id","")))==str(instance_id):
					var station_id:=str(station.get("id",""))
					if not permitted_transfer_routes.has(station_id):permitted_transfer_routes[station_id]={}
					permitted_transfer_routes[station_id][str(transfer.get("id",""))]=permitted_route_id
					break
	var queue: Array = []
	var distance: Dictionary = {}
	for route_id in routes_at_station.get(from_station, []):
		var key := from_station + "\u001f" + str(route_id)
		distance[key] = 0
		queue.append({"station": from_station, "route": str(route_id), "cost": 0})
	while not queue.is_empty():
		var best_index := 0
		for index in range(1, queue.size()):
			if int(queue[index].cost) < int(queue[best_index].cost): best_index = index
		var current: Dictionary = queue.pop_at(best_index)
		var key := str(current.station) + "\u001f" + str(current.route)
		if int(current.cost) != int(distance.get(key, 999999)): continue
		if str(current.station) == to_station: return int(current.cost)
		for station_value in stations_by_route.get(str(current.route), []):
			var next_station := str(station_value)
			var next_key := next_station + "\u001f" + str(current.route)
			if int(current.cost) < int(distance.get(next_key, 999999)):
				distance[next_key] = int(current.cost)
				queue.append({"station": next_station, "route": str(current.route), "cost": int(current.cost)})
		for peer in transfer_peers.get(str(current.station), []):
			for next_route in routes_at_station.get(str(peer), []):
				var permitted:=false
				for transfer_id in permitted_transfer_routes.get(str(current.station),{}):
					if str(permitted_transfer_routes[str(current.station)][transfer_id])==str(current.route) and str(permitted_transfer_routes.get(str(peer),{}).get(transfer_id,""))==str(next_route):permitted=true;break
				if not permitted:continue
				var transfer_key := str(peer) + "\u001f" + str(next_route)
				var transfer_cost := int(current.cost) + 1
				if transfer_cost < int(distance.get(transfer_key, 999999)):
					distance[transfer_key] = transfer_cost
					queue.append({"station": str(peer), "route": str(next_route), "cost": transfer_cost})
	return -1

static func chapter_baseline_world(world: Dictionary) -> Dictionary:
	var milestones: Array = world.get("storyState", {}).get("milestones", [])
	if milestones.is_empty() or str(milestones.back().get("chapterId", "")) != str(chapter(world).get("id", "")): return {}
	var copy: Dictionary = world.duplicate(true)
	var history := CommandHistory.new(); history.attach(copy)
	history._apply_diff(milestones.back().get("planningDiff", {}), false)
	for key in ["stations", "routes", "trackLinks", "trackNodes", "trackEdges", "depots", "planningPhases", "serviceRanges"]:
		if not (copy.get(key, null) is Array): copy[key] = []
	if not (copy.get("storyPlan", null) is Dictionary): copy["storyPlan"] = {"planIndex": 0, "pathChoices": {}}
	return copy

static func next_chapter(world: Dictionary) -> void:
	if str(world.get("storyState",{}).get("stage",""))!="outcome":return
	var st: Dictionary=world.storyState
	var current:=chapter(world)
	# An old checkpoint can still be at the final planning outcome while new
	# historical tasks have been inserted. Re-enter the first missing history
	# at this safe boundary; never interrupt an active draft or skip by date.
	if str(st.get("phase","history"))=="future":
		var historical:Array=config(world).get("chapters",[])
		for index in range(historical.size()):
			if st.get("completedChapterIds",[]).has(str(historical[index].id)):continue
			st["phase"]="history";st["chapterIndex"]=index;st["chapterId"]=str(historical[index].id);st["stage"]="intro"
			world["storyPlan"]={"planIndex":0,"pathChoices":{}}
			return
	var chapters:Array=config(world).get("chapters",[]) if str(st.get("phase","history"))!="future" else Catalog.playable_future_plans(str(world.cityId))
	var index:=int(st.get("chapterIndex",0))
	for i in range(chapters.size()):
		if str(chapters[i].get("id",""))==str(current.get("id","")):index=i;break
	if StoryTutorial.is_first(world):st["tutorialEnabled"]=false;st["learnedTools"]=true
	var next_index:=-1
	var completed:Array=st.get("completedChapterIds",[])
	for candidate_index in range(index+1,chapters.size()):
		if not completed.has(str(chapters[candidate_index].get("id",""))):next_index=candidate_index;break
	if next_index<0:
		for candidate_index in range(mini(index+1,chapters.size())):
			if not completed.has(str(chapters[candidate_index].get("id",""))):next_index=candidate_index;break
	# Backfilling an earlier opening can introduce a former service pattern
	# alongside the later saved network. A prior cutoff completion flag cannot
	# certify that changed network: offer its real reconciliation task again.
	if next_index<0 and str(st.get("phase","history"))!="future":
		for candidate_index in range(chapters.size()):
			var cutoff:Dictionary=chapters[candidate_index]
			if str(cutoff.get("chapterScope",""))!="cutoff_reconciliation" or not completed.has(str(cutoff.id)):continue
			if str(current.get("date",""))>=str(cutoff.get("date","")):continue
			var errors:=OfficialNetworkAudit.cutoff_errors(world)
			if errors.is_empty():continue
			var previous:Dictionary=st.get("chapterTaskProgress",{}).get(str(cutoff.id),{}).duplicate(true)
			st.get_or_add("legacyTaskProgress",{})[str(cutoff.id)]=previous
			st.get_or_add("chapterTaskProgress",{})[str(cutoff.id)]={"status":"needs_scope_recheck","tasks":{},"previousScopeRetained":true,"reason":"post_backfill_network_changed","auditErrors":errors}
			completed.erase(str(cutoff.id));next_index=candidate_index
			world["contentUpgradeNotice"]="补充历史建设后，当前线路关系需要重新核对。原站轨及里程碑保留，请完成截止日路网核对。"
			break
	st["chapterIndex"]=next_index if next_index>=0 else chapters.size()
	st["chapterId"]=str(chapters[next_index].get("id","")) if next_index>=0 else ""
	st["stage"]="intro";world["storyPlan"]={"planIndex":0,"pathChoices":{}}
	if next_index<0:
		var history_status:=str(config(world).get("historyStatus","partial"))
		if str(st.get("phase","history"))=="future":
			st["phase"]="future_gap";st["chapterIndex"]=Catalog.playable_future_plans(str(world.cityId)).size()
		elif history_status in ["complete", "route_inventory_complete"]:
			var playable := Catalog.playable_future_plans(str(world.cityId))
			var next_plan: Dictionary = {}
			var future_index := -1
			for plan_index in range(playable.size()):
				var candidate: Dictionary = playable[plan_index]
				if st.get("completedChapterIds", []).has(str(candidate.get("id", ""))): continue
				next_plan = candidate; future_index = plan_index; break
			if future_index >= 0:
				st["phase"]="future";st["chapterIndex"]=future_index;st["chapterId"]=str(next_plan.get("id", ""));st["stage"]="intro"
			else:
				st["phase"]="history_content_gap" if history_status=="route_inventory_complete" else "future_gap"
		elif history_status=="partial": st["phase"]="history_gap"
		else: st["phase"]="history_content_gap"
	if not chapter(world).is_empty():st["chapterId"]=str(chapter(world).id)

static func can_create_workshop_copy(world: Dictionary) -> bool:
	return bool(completion_eligibility(world).get("ok",false))

## Free creation is a reward for what the player built, not for how much of the
## archive has been independently reviewed. The evidence review still runs, but
## its reasons are reported separately as `auditReasons`; they never keep a
## player who finished every published chapter out of free creation.
static func completion_eligibility(world:Dictionary) -> Dictionary:
	var content:=Catalog.delivery_eligibility(str(world.get("cityId","")))
	var reasons:Array=[]
	if str(world.get("mode",""))!="campaign":reasons.append("当前不是历史主进度。")
	var completed:Array=world.get("storyState",{}).get("completedChapterIds",[])
	var campaign:=config(world)
	var required:Array=campaign.get("chapters",[]).duplicate()
	for plan in campaign.get("futurePlans",[]):
		if bool(plan.get("required",false)):required.append(plan)
	for entry in required:
		if not completed.has(str(entry.get("id",""))):reasons.append("尚未完成：%s" % str(entry.get("title",entry.get("id",""))))
	if not chapter(world).is_empty():reasons.append("本章尚未完成。")
	# A completion flag is not a built network. Both checks run whether or not
	# the list above is empty, so a forged flag cannot skip either one.
	var saved_problem:=SaveManager.validate(world)
	if not saved_problem.is_empty():reasons.append(saved_problem)
	var project_ids:Array=[]
	for plan in campaign.get("futurePlans",[]):
		if bool(plan.get("required",false)):project_ids.append_array(plan.get("projectIds",[]))
	reasons.append_array(OfficialNetworkAudit.current_project_errors(world,project_ids))
	return {"ok":reasons.is_empty(),"reasons":reasons,"auditReasons":content.get("reasons",[]),"contentReady":bool(content.get("ok",false))}

static func unlock_free(world:Dictionary,expected_revision:int) -> Dictionary:
	if int(world.get("revision",0))!=expected_revision:return {"ok":false,"error":"进度已变化，请重新检查。"}
	var qualification:=completion_eligibility(world)
	if not bool(qualification.ok):return {"ok":false,"error":"必做章节、存档校验或线路核对尚未通过。","qualification":qualification}
	world["mode"]="workshop"
	world.storyState["phase"]="free";world.storyState["stage"]="free";world.storyState["freeUnlocked"]=true
	world.storyState["tutorialEnabled"]=false
	world["revision"]=int(world.get("revision",0))+1
	return {"ok":true}

static func create_workshop_copy(world: Dictionary) -> Dictionary:
	if not can_create_workshop_copy(world): return {}
	var copy: Dictionary = world.duplicate(true)
	var fresh: Dictionary = WorldData.new_world(str(world.get("cityId", "")), "workshop")
	copy["gameId"] = str(fresh.get("gameId", ""))
	copy["schemaVersion"] = WorldData.SAVE_VERSION
	copy["mode"] = "workshop"
	copy["title"] = "%s · 自由创作副本" % str(world.get("cityName", "城市"))
	copy["workshopSourceGameId"] = str(world.get("gameId", ""))
	copy["workshopPublishedChapterIds"] = world.get("storyState", {}).get("completedChapterIds", []).duplicate()
	var state: Dictionary = copy.get("storyState", {}).duplicate(true)
	state["phase"] = "published_content_complete"
	state["freeUnlocked"] = true
	state["tutorialEnabled"] = false
	state["tutorialStatus"] = "completed"
	state["learnedTools"] = true
	state["stage"] = "free"
	copy["storyState"] = state
	copy["history"] = {"undo": [], "redo": []}
	copy["revision"] = int(copy.get("revision", 0)) + 1
	return copy

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
	if chapter(world).is_empty():
		var phase:=str(world.get("storyState",{}).get("phase",""))
		if phase=="history_gap":return "历史建设任务尚未接续"
		if phase=="history_content_gap":return "现有线路任务已完成，逐期历史仍待补齐"
		if phase=="future_gap":return "已完成截至日历史建设；截止日后的项目篇尚未数字化"
		return "资料边界"
	if str(world.get("storyState",{}).get("stage","intro"))=="outcome":return "历史节点已确认"
	return "本期建成目标" if plan_is_final(world) else "未实施的历史方案"

static func current_action(world:Dictionary) -> String:
	if bool(chapter(world).get("eventOnly",false)):return "查看来源并确认这个历史节点；本节点没有新增铺轨范围。"
	if str(chapter(world).get("operationType",""))=="transfer_connection":return "查看两侧独立站体，预览并建立本期换乘联系；无需新铺轨道。"
	if not plan_is_final(world):return "对比新旧方案，再采用下一版调整。"
	var active_groups:=groups(world,true,str(world.get("storyState",{}).get("activeTaskId","")))
	if not active_groups.is_empty() and active_groups.all(func(group:Dictionary):return Engineering.is_group(group)):return "预览并连接工程轨道，再检查确认；接口不是车站。"
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
