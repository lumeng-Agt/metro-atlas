extends SceneTree

const Story = preload("res://scripts/story_session.gd")
const Construction = preload("res://scripts/story_construction.gd")
const Catalog = preload("res://scripts/campaign_system.gd")
const TrackNetwork = preload("res://scripts/track_network.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		push_error("显式隔离 --data-dir 是必需的，避免测试写入玩家存档。")
		quit(2)
		return
	WorldData.load_assets()
	_check(Catalog.canonical_station_complex("shenzhen", "shenzhen-s271") == "shenzhen-s69", "Shenzhen historical map duplicates resolve to one stable interchange complex")
	_check(Catalog.canonical_station_complex("shenzhen", "shenzhen-s270") == "shenzhen-s5", "Science Museum map anchors retain separate bodies under one interchange identity")
	_check(Catalog.canonical_station_complex("shenzhen", "shenzhen-s34") == "shenzhen-s9", "Shopping Park map anchors retain separate bodies under one interchange identity")
	_check(Catalog.canonical_station_complex("shenzhen", "shenzhen-s212") == "shenzhen-s11", "Chegongmiao map anchors retain separate bodies under one interchange identity")
	var initial_line1_group:Dictionary={}
	for group in Catalog.city_config("shenzhen").chapters.filter(func(chapter:Dictionary):return str(chapter.get("id",""))=="sz-initial-cross-2004")[0].get("lineGroups",[]):
		if str(group.get("historicalLineId",""))=="shenzhen-line1":initial_line1_group=group;break
	_check(initial_line1_group.get("stationIds",[]).has("shenzhen-s5") and initial_line1_group.get("stationIds",[]).has("shenzhen-s9") and initial_line1_group.get("stationIds",[]).has("shenzhen-s11") and not initial_line1_group.get("stationIds",[]).has("shenzhen-s270"), "2004 Line 1 targets its own mapped station bodies instead of nearby copies from later lines")
	var transfer_milestones:Array=Catalog.city_config("shenzhen").get("chapters",[])
	var has_science_transfer:=false;var has_shopping_transfer:=false;var has_chegongmiao_transfer:=false
	for chapter in transfer_milestones:
		for transfer in chapter.get("requiredTransfers",[]):
			if str(transfer.get("id",""))=="sz-transfer-science-museum-line1-line6":has_science_transfer=transfer.get("stationInstanceIds",[]).size()==2
			if str(transfer.get("id",""))=="sz-transfer-shopping-park-line1-line3":has_shopping_transfer=transfer.get("stationInstanceIds",[]).size()==2
			if str(transfer.get("id",""))=="sz-transfer-chegongmiao-lines1-7-9-11":has_chegongmiao_transfer=transfer.get("stationInstanceIds",[]).size()==4
	_check(has_science_transfer and has_shopping_transfer and has_chegongmiao_transfer, "Shenzhen transfer milestones explicitly connect two-line and four-line complexes")
	_check(Story.station_instance_id({"historicalLineId":"shenzhen-line4"}, "shenzhen-s69") == "shenzhen-s271", "Shenzhen Line 4 reuses its existing Fumin station body across milestones")
	_check(Story.station_instance_id({"historicalLineId":"beijing-lineearly1","stationIds":["beijing-s73"],"stationInstances":{"beijing-s73":"beijing-s73__line1"}},"beijing-s73")=="beijing-s73__line1","Beijing Line 2 keeps a separate Yonghegong body for its later Line 5 transfer")
	_check(Story._route_contains_station_body({"stationOrder":["a","b"],"directions":[{"stationIds":["a","b"]},{"stationIds":["c","d"]}]}, "d"), "transfer validation searches every saved route section")
	var split_line_routes:Array=[{"historicalLineId":"line_1","stationOrder":["old_a","old_b"]},{"historicalLineId":"line_1","stationOrder":["new_a","new_b"]}]
	_check(str(Story.route_for_station_body(split_line_routes,"line_1","new_b").get("stationOrder",[]).back())=="new_b","transfer validation chooses the same-line section that actually contains its body")
	_check(Story.route_for_station_body(split_line_routes,"line_1","missing_body").is_empty(),"a same-line section without the target body cannot satisfy transfer readiness")
	var body_identity_world:Dictionary=WorldData.new_world("beijing","campaign")
	body_identity_world.stations=[{"id":"legacy_complex_body","stationInstanceId":"legacy_complex_body","historicalId":"beijing-s73","stationComplexId":"beijing-s73","stationLineId":"beijing-lineearly1","name":"雍和宫","latlng":[39.9478,116.4115]}]
	_check(Story.bound_station(body_identity_world,"beijing-s73","beijing-s73__line1","beijing-lineearly1").is_empty(),"a different physical station at the same complex cannot satisfy an explicit interchange-body binding")
	_check(str(Story.bound_station(body_identity_world,"beijing-s73","","beijing-lineearly1").get("id",""))=="legacy_complex_body","complex lookup without a requested body still supports legacy line-scoped inspection")
	body_identity_world.stations.append({"id":"line1_body","stationInstanceId":"beijing-s73__line1","historicalId":"beijing-s73","stationComplexId":"beijing-s73","stationLineId":"beijing-lineearly1","name":"雍和宫","latlng":[39.9478,116.4115]})
	_check(str(Story.bound_station(body_identity_world,"beijing-s73","beijing-s73__line1","beijing-lineearly1").get("id",""))=="line1_body","an explicit interchange lookup selects only its matching physical body")
	var endpoint_options:Array=[{"edges":[{"fromNodeId":"arrived_end"}]},{"edges":[{"fromNodeId":"opposite_end"}]}]
	_check(str(Story.path_option_for_segment(endpoint_options,0,"arrived_end",false).edges[0].fromNodeId)=="opposite_end","default route continuation avoids an unrequested same-end reversal when another path exists")
	_check(str(Story.path_option_for_segment(endpoint_options,0,"arrived_end",true).edges[0].fromNodeId)=="arrived_end","an explicitly selected historical route remains visible for validation instead of being silently changed")
	var path_fixture:Dictionary=WorldData.new_world("shenzhen","campaign")
	path_fixture.stations=[
		{"id":"path_a","name":"路径甲","latlng":[22.54,114.06],"heading":90.0,"lengthM":100.0,"widthM":20.0},
		{"id":"path_b","name":"路径乙","latlng":[22.54,114.061],"heading":90.0,"lengthM":100.0,"widthM":20.0}
	]
	TrackNetwork.ensure_station_nodes(path_fixture)
	path_fixture.trackEdges=[{"id":"path_edge","aNodeId":"node_path_a_b","bNodeId":"node_path_b_a","geometry":"straight","distanceM":100.0}]
	var path_index:Dictionary=TrackNetwork.build_path_index(path_fixture,22.54)
	var indexed_path:Dictionary=TrackNetwork.shortest_station_path_indexed("path_a","path_b",path_fixture,path_index,22.54)
	var rebuilt_path:Dictionary=TrackNetwork.shortest_station_path("path_a","path_b",path_fixture,22.54)
	_check(bool(indexed_path.get("valid",false)) and bool(rebuilt_path.get("valid",false)),"indexed and one-shot path queries both find a connected segment")
	_check(indexed_path.get("linkIds",[])==rebuilt_path.get("linkIds",[]) and is_equal_approx(float(indexed_path.get("distanceM",0.0)),float(rebuilt_path.get("distanceM",0.0))),"reusing a path index preserves route identity and length")
	var world:Dictionary=WorldData.new_world("shenzhen","campaign")
	world.storyState.chapterId="sz-initial-cross-2004" # Explicit 2004 body-selection unit fixture.
	var chapter_targets:Array=Story.targets(world,true)
	var huizhan_targets:Array=[]
	for target in chapter_targets:
		if str(target.get("stationComplexId",""))=="shenzhen-s8":huizhan_targets.append(target)
	_check(huizhan_targets.size()==2,"Shenzhen 2004 interchange exposes one target for each physical line station")
	if huizhan_targets.size()==2:
		_check(str(huizhan_targets[0].stationInstanceId)!=str(huizhan_targets[1].stationInstanceId),"interchange station instances have separate stable identities")
		_check(str(huizhan_targets[0].stationComplexId)==str(huizhan_targets[1].stationComplexId),"separate station bodies share only their historical complex identity")
		_check(huizhan_targets.all(func(target:Dictionary):return not str(target.get("historicalLineName","")).contains("shenzhen-line")),"interchange blueprint targets expose readable line names instead of duplicate station names only")

	var first:Dictionary={"id":"body_l1","stationInstanceId":"body_l1_instance","stationComplexId":"complex_x","historicalId":"complex_x","latlng":[22.54,114.06],"heading":90.0,"lengthM":120.0,"widthM":22.0,"routeIds":["route_l1"]}
	var second:Dictionary={"id":"body_l4","stationInstanceId":"body_l4_instance","stationComplexId":"complex_x","historicalId":"complex_x","latlng":[22.54,114.06],"heading":0.0,"lengthM":120.0,"widthM":22.0,"routeIds":["route_l4"]}
	world.stations=[first,second]
	world.stationComplexes=[{"id":"complex_x","name":"示例换乘站区","locationPrecision":"station_area_approximation","structureStatus":"not_surveyed"}]
	world.routes=[
		{"id":"route_l1","historicalLineId":"line_1","name":"1号线","open":true,"stationOrder":["body_l1"],"directions":[{"id":"forward","stationIds":["body_l1"],"edgePathsBySegment":[]}]},
		{"id":"route_l4","historicalLineId":"line_4","name":"4号线","open":true,"stationOrder":["body_l4"],"directions":[{"id":"forward","stationIds":["body_l4"],"edgePathsBySegment":[]}]}
	]
	world.transferConnections=[]
	_check(Story._minimum_route_transfers(world,"body_l1","body_l4",22.54)==-1,"co-location and matching historical names do not create a transfer by themselves")
	world.transferConnections=[{"id":"transfer_x","complexId":"complex_x","stationInstanceIds":["body_l1_instance","body_l4_instance"],"lineIds":["line_1","line_4"],"status":"active"}]
	_check(Story._minimum_route_transfers(world,"body_l1","body_l4",22.54)==1,"explicit interchange joins the independently served station bodies")
	world.transferConnections[0].lineIds=["line_4","line_1"]
	_check(Story._minimum_route_transfers(world,"body_l1","body_l4",22.54)==-1,"a transfer cannot silently map each station body to the other line")

	var validator:=SaveManager.validate(world)
	_check(not validator.is_empty(),"save validation rejects a transfer whose physical bodies are assigned to the wrong lines")
	world.transferConnections[0].lineIds=["line_1","line_4"]
	_check(SaveManager.validate(world).is_empty(),"save validation accepts two distinct station bodies linked to their own lines")
	var direction_only_transfer_world:Dictionary=world.duplicate(true)
	direction_only_transfer_world.routes[0].stationOrder=[]
	_check(SaveManager.validate(direction_only_transfer_world).is_empty(),"save validation recognizes a transfer body listed in a saved route direction even when it is outside the legacy top-level station order")
	var split_transfer_world:Dictionary=world.duplicate(true)
	var unrelated_line_section:Dictionary=split_transfer_world.routes[0].duplicate(true)
	unrelated_line_section.id="route_l1_other_section"
	unrelated_line_section.stationOrder=["body_l4"]
	unrelated_line_section.directions[0].stationIds=["body_l4"]
	split_transfer_world.routes.push_front(unrelated_line_section)
	_check(SaveManager.validate(split_transfer_world).is_empty(),"save validation searches every split section of a historical line instead of stopping at the first unrelated section")
	var saved:Dictionary=SaveManager.save_world(world)
	_check(bool(saved.get("ok",false)),"format 22 writes the physical station bodies and explicit transfer link")
	if bool(saved.get("ok",false)):
		var loaded:Dictionary=SaveManager.load_file(str(saved.path))
		_check(bool(loaded.get("ok",false)) and loaded.world.stations.size()==2 and loaded.world.transferConnections.size()==1,"save and reload preserve separate bodies and one transfer relation")

	var construction:=Construction.new()
	construction.active_city_id="shenzhen"
	construction.world=world
	_check(not construction._station_overlaps_in(first,[second]),"separate station structures in one complex are not collapsed by 2-D overlap checks")
	var same_instance:Dictionary=second.duplicate(true);same_instance.stationInstanceId=first.stationInstanceId
	_check(construction._station_overlaps_in(first,[same_instance]),"duplicate geometry for the same physical station is still rejected")

	for old_version in [20,21]:
		var legacy:Dictionary=WorldData.new_world("shenzhen","campaign")
		legacy.schemaVersion=old_version
		legacy.storyState.chapterIndex=3;legacy.storyState.chapterId="sz-initial-cross-2004";legacy.storyState.stage="build";legacy.storyState.completedChapterIds=["prior_chapter"]
		legacy.storyState.milestones=[{"chapterId":"prior_chapter","planningDiff":{"stations":{}}}]
		legacy["gameId"]="legacy_fixture_%d" % old_version
		legacy.stations=[{"id":"legacy_station","name":"旧站","historicalId":"shenzhen-s8","latlng":[22.54,114.06]}]
		legacy.erase("stationComplexes");legacy.erase("transferConnections")
		var migrated:Dictionary=SaveManager.migrate(legacy,"legacy fixture %d" % old_version)
		_check(int(migrated.schemaVersion)==WorldData.SAVE_VERSION and migrated.get("stationComplexes",[]) is Array and migrated.get("transferConnections",[]) is Array and migrated.get("serviceRanges",[]) is Array and migrated.storyState.get("chapterTaskProgress",null) is Dictionary and migrated.storyState.get("confirmedHistoricalEventIds",null) is Array,"format %d migration initializes station, transfer, service, and milestone history collections" % old_version)
		_check(str(migrated.stations[0].get("stationInstanceId",""))=="legacy_station" and str(migrated.stations[0].get("stationComplexId",""))=="shenzhen-s8","format %d migration preserves legacy station identity and its historical complex" % old_version)
		_check(str(migrated.gameId)==str(legacy.gameId) and str(migrated.storyState.chapterId)=="sz-initial-cross-2004" and str(migrated.storyState.stage)=="build" and migrated.storyState.completedChapterIds==["prior_chapter"],"format %d migration preserves valid active story progress and game identity" % old_version)
		_check(migrated.storyState.milestones==legacy.storyState.milestones and migrated.routes==legacy.routes and migrated.history==legacy.history,"format %d migration preserves milestones, routes, and undo history" % old_version)
		_check(SaveManager._index_usable({"schemaVersion":old_version,"gameId":"legacy_fixture_%d" % old_version}),"format %d continue-game index remains loadable" % old_version)

	var app=preload("res://scripts/main.gd").new()
	root.add_child(app)
	await process_frame
	var reviewed_cutoff:Dictionary=CampaignSystem.city_config("shenzhen").get("chapters",[]).filter(func(c:Dictionary):return str(c.id)=="shenzhen-network-reconciliation-2026-10-01")[0]
	var listed:Array=[]
	for page_index in range(ceili(reviewed_cutoff.get("requiredTransfers",[]).size()/10.0)):
		var items:Array=app._transfer_page(reviewed_cutoff,page_index)
		_check(items.size()<=10,"full-network interchange pages remain bounded")
		listed.append_array(items.map(func(t:Dictionary):return str(t.id)))
	_check(listed==reviewed_cutoff.get("requiredTransfers",[]).map(func(t:Dictionary):return str(t.id)),"paging exposes every reviewed transfer exactly once, including the last partial page")
	app._new_game("shenzhen",false)
	app._begin_chapter()
	app.world.storyState.chapterId="sz-initial-cross-2004"
	app.world.storyState.learnedTools=true
	app.world.storyState.tutorialStatus="completed"
	app.world.storyPlan.planIndex=Story.chapter(app.world).get("story",{}).get("planVersions",[]).size()-1
	var ui_transfer:Dictionary=Story.chapter(app.world).get("requiredTransfers",[])[0]
	var initial_transfer_lines:Array[String]=app._transfer_status_lines(ui_transfer)
	_check(app._historical_line_name("shenzhen-line1").contains("1号线") and app._historical_line_name("shenzhen-line4").contains("4号线"),"transfer explanation resolves historical line ids to familiar line names")
	var line1_waiting:=initial_transfer_lines.any(func(line:String):return line.contains("1号线") and line.contains("未建设站体"))
	var line4_waiting:=initial_transfer_lines.any(func(line:String):return line.contains("4号线") and line.contains("未建设站体"))
	_check(initial_transfer_lines.size()==2 and line1_waiting and line4_waiting,"disabled transfer action explains each missing independent body separately")
	app.map_view.set_blueprint(Story.blueprint(app.world))
	var mapped_huizhan:Array=app.map_view.campaign_blueprint.get("stations",[]).filter(func(target:Dictionary):return str(target.get("stationComplexId",""))=="shenzhen-s8")
	_check(mapped_huizhan.size()==2 and mapped_huizhan.all(func(target:Dictionary):return str(target.get("stationInstanceId","")) in ["shenzhen-s8-line1","shenzhen-s8-line4"]),"adopted chapter blueprint displays each interchange body as a separate target")
	_check(app.map_view._station_line_label({"stationInstanceId":"shenzhen-s8-line1","stationLineId":"shenzhen-line1"}).contains("1号线"),"map labels can identify a co-located physical body by its own line")
	_check(app.map_view._station_line_label({"stationInstanceId":"shenzhen-s8-line4","stationLineId":"shenzhen-line4"}).contains("4号线"),"map labels distinguish the other co-located physical body")
	var target_line4:Dictionary={}
	var line4_task_id:=""
	var chapter_groups:Array=Story.groups(app.world,true)
	for group_index in range(chapter_groups.size()):
		if str(chapter_groups[group_index].get("historicalLineId",""))=="shenzhen-line4":
			line4_task_id=Story.task_id(Story.chapter(app.world),chapter_groups[group_index],group_index);break
	if not line4_task_id.is_empty():app._select_chapter_task(line4_task_id)
	for target in Story.targets(app.world):
		if str(target.get("stationInstanceId",""))=="shenzhen-s8-line4":target_line4=target;break
	_check(not target_line4.is_empty(),"the final adopted scope exposes the 4号线 body to the station placement tool")
	if not target_line4.is_empty():
		app._tool("station");app._click(target_line4.latlng,"blueprint",str(target_line4.id),"")
		_check(str(app.map_view.draft_station.get("stationInstanceId",""))=="shenzhen-s8-line4","clicking the 4号线 target drafts its own station body, not the 1号线 body")
		app._cancel()
	# The chapter intentionally begins on the 2002 adopted draft; the 2004
	# construction checks are only valid after the player adopts the final scope.
	var shenzhen_chapter:Dictionary=Story.chapter(app.world)
	var shenzhen_versions:Array=shenzhen_chapter.get("story",{}).get("planVersions",[])
	app.world.storyPlan.planIndex=shenzhen_versions.size()-1
	app.world.storyState.stage="build"
	var assisted:Dictionary=app._assist_candidate()
	_check(assisted.has("state"),"深圳一期的整章建设辅助可生成待确认预览：%s" % str(assisted.get("issue","未知原因")))
	if assisted.has("state"):
		var candidate:Dictionary=assisted.state
		var built_instances:Array=[]
		for station in candidate.stations:
			if str(station.get("stationComplexId",""))=="shenzhen-s8":built_instances.append(station)
		_check(built_instances.size()==2,"会展中心在预览中包含两个独立物理站体")
		if built_instances.size()==2:
			_check(str(built_instances[0].stationInstanceId)!=str(built_instances[1].stationInstanceId),"辅助建设不会合并换乘站体")
			_check(Story._minimum_route_transfers(candidate,str(built_instances[0].id),str(built_instances[1].id),22.54)==-1,"未确认章节前两座站体不产生换乘")
		var missing_transfer_evaluation:Dictionary=Story.evaluate(candidate)
		_check(not bool(missing_transfer_evaluation.get("complete",false)) and missing_transfer_evaluation.issues.any(func(issue:Dictionary):return str(issue.get("kind",""))=="transfer"),"换乘未由章节确认自动生成，必须显式建立")
		# Reproduce older saves where the line-1 track is attached to the former
		# generic Huizhan body while a newer, coincident line-specific body is
		# isolated. The evaluator should explain the mismatch and offer a safe,
		# reversible identity repair instead of claiming the visible track is gone.
		var legacy_fixture:Dictionary=candidate.duplicate(true)
		var line1_body:Dictionary={}
		for station in legacy_fixture.stations:
			if str(station.get("stationInstanceId",""))=="shenzhen-s8-line1":line1_body=station;break
		if not line1_body.is_empty():
			var legacy_body:Dictionary=line1_body.duplicate(true)
			legacy_body.id="legacy_huizhan_line1";legacy_body.stationInstanceId="shenzhen-s8";legacy_body.stationLineId="shenzhen-line1";legacy_body.stationLineName=""
			var old_endpoints:Dictionary=line1_body.endpointNodes.duplicate(true)
			var new_endpoints:Dictionary={"A":"legacy_huizhan_node_a","B":"legacy_huizhan_node_b"}
			legacy_body.endpointNodes=new_endpoints
			for side in ["A","B"]:
				for node in legacy_fixture.trackNodes:
					if str(node.get("id",""))==str(old_endpoints.get(side,"")):
						var copied_node:Dictionary=node.duplicate(true);copied_node.id=str(new_endpoints[side]);copied_node.stationId="legacy_huizhan_line1";legacy_fixture.trackNodes.append(copied_node);break
			for edge in legacy_fixture.trackEdges:
				for side in ["A","B"]:
					if str(edge.get("aNodeId",""))==str(old_endpoints.get(side,"")):edge.aNodeId=str(new_endpoints[side])
					if str(edge.get("bNodeId",""))==str(old_endpoints.get(side,"")):edge.bNodeId=str(new_endpoints[side])
			legacy_fixture.stations.append(legacy_body)
			var before_station_count:int=legacy_fixture.stations.size()
			var legacy_evaluation:Dictionary=Story.evaluate(legacy_fixture)
			var repair_issue:Dictionary={}
			for issue in legacy_evaluation.get("issues",[]):
				if str(issue.get("kind",""))=="legacy_station_binding":repair_issue=issue;break
			_check(not repair_issue.is_empty() and str(repair_issue.get("text","")).contains("轨道已接到旧版"),"connected legacy station is identified as the cause rather than reported as visually disconnected")
			_check(legacy_evaluation.get("issues",[]).count(repair_issue)==1,"the same old station mismatch is reported once for both adjacent segments")
			if not repair_issue.is_empty():
				var repair_request:Dictionary=repair_issue.stationBindingRepair
				var prepared:Dictionary=Story.prepare_legacy_station_body_repair(legacy_fixture,repair_request,int(legacy_fixture.revision))
				_check(bool(prepared.get("ok",false)),"safe repair preview preserves existing connected track and validates the updated save")
				if bool(prepared.get("ok",false)):
					var repaired_world:Dictionary=prepared.world
					_check(repaired_world.stations.size()==before_station_count-1 and repaired_world.trackEdges.size()==legacy_fixture.trackEdges.size(),"repair removes only the isolated duplicate and keeps every rail edge")
					var canonical_body:=Story.bound_station(repaired_world,"shenzhen-s8","shenzhen-s8-line1")
					_check(not canonical_body.is_empty() and str(canonical_body.id)=="legacy_huizhan_line1","existing track-connected body receives the required line-specific target identity")
					var after_repair:Dictionary=Story.evaluate(repaired_world)
					_check(not after_repair.issues.any(func(issue:Dictionary):return str(issue.get("text","")).contains("尚未接通：岗厦—会展中心") or str(issue.get("text","")).contains("尚未接通：会展中心—购物公园")),"repaired visible connections pass both adjacent station-pair checks")
					_check(after_repair.get("routes",[]).any(func(route:Dictionary):return str(route.get("historicalLineId",""))=="shenzhen-line1"),"repair allows the continuous 1号线 chapter route to be formed")
					var repair_history=preload("res://scripts/command_history.gd").new();repair_history.attach(legacy_fixture)
					repair_history.execute("repair_fixture",func(state:Dictionary):state.stations=repaired_world.stations.duplicate(true);state.trackNodes=repaired_world.trackNodes.duplicate(true),["stations","trackNodes"])
					_check(repair_history.undo()=="repair_fixture" and legacy_fixture.stations.size()==before_station_count and str(Story.bound_station(legacy_fixture,"shenzhen-s8","shenzhen-s8-line1").get("id",""))!="legacy_huizhan_line1","station-body repair can be undone without losing the original topology")
					_check(repair_history.redo()=="repair_fixture" and legacy_fixture.stations.size()==before_station_count-1 and str(Story.bound_station(legacy_fixture,"shenzhen-s8","shenzhen-s8-line1").id)=="legacy_huizhan_line1","redo restores the repaired body binding and connected network")
		var transfer_groups:Array=Story.groups(candidate,true)
		for group_index in range(transfer_groups.size()):
			var group:Dictionary=transfer_groups[group_index]
			var task_id:=Story.task_id(Story.chapter(candidate),group,group_index)
			var confirmed_task:Dictionary=Story.confirm_task(candidate,task_id,int(candidate.get("revision",0)))
			_check(bool(confirmed_task.get("ok",false)),"换乘确认前单独保存%s线路任务：%s" % [str(group.get("name",task_id)),str(confirmed_task.get("error",""))])
		for planned_route in missing_transfer_evaluation.get("routes",[]):
			if WorldData.find_route(candidate,str(planned_route.get("id",""))).is_empty():
				var draft_route:Dictionary=planned_route.duplicate(true);draft_route["open"]=false;candidate.routes.append(draft_route)
		var transfer_config:Dictionary=Story.chapter(candidate).requiredTransfers[0]
		candidate.transferConnections.append({"id":str(transfer_config.id),"name":str(transfer_config.get("name","换乘")),"complexId":str(transfer_config.complexId),"stationInstanceIds":transfer_config.stationInstanceIds.duplicate(),"lineIds":transfer_config.lineIds.duplicate(),"status":"active","precision":str(transfer_config.get("precision","schematic")),"source":str(transfer_config.get("source","")),"effectiveDate":str(Story.chapter(candidate).date)})
		var assisted_evaluation:Dictionary=Story.evaluate(candidate)
		_check(bool(assisted_evaluation.get("complete",false)),"独立站体与显式换乘关系通过本期目标检查")
		if bool(assisted_evaluation.get("complete",false)):
			var committed:Dictionary=Story.commit_chapter(candidate,int(assisted_evaluation.revision))
			_check(bool(committed.get("ok",false)),"确认历史节点后两条线路和换乘关系整体提交")
			_check(candidate.transferConnections.size()==1,"章节确认保留此前明确建立的换乘联系")
			if candidate.transferConnections.size()==1:
				var body_ids:Array=candidate.transferConnections[0].stationInstanceIds
				var body_a:Dictionary={};var body_b:Dictionary={}
				for station in candidate.stations:
					if str(station.stationInstanceId)==str(body_ids[0]):body_a=station
					if str(station.stationInstanceId)==str(body_ids[1]):body_b=station
				_check(not TrackNetwork.shortest_station_path(str(body_a.id),str(body_b.id),candidate,22.54).get("valid",false),"换乘步行联系不会被列车轨道寻路当成实体轨道")
				_check(Story._minimum_route_transfers(candidate,str(body_a.id),str(body_b.id),22.54)==1,"确认后网络分析可识别真实换乘")
			_check(SaveManager.validate(candidate).is_empty(),"独立站体、线路和换乘可通过完整存档校验")
	app.queue_free()
	await process_frame

	print("0.23 transfer/service model: %d checks, %d failures" % [checks,failures.size()])
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
