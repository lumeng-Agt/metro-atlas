extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)
func fragment(source:Dictionary,ids:Array,task:String) -> Dictionary:
	var group:=source.duplicate(true);group.stationIds=ids.duplicate();group.taskId=task
	return group
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var config:=CampaignSystem.city_config("beijing")
	var plan:Dictionary=config.futurePlans.filter(func(c:Dictionary):return str(c.id)=="bj-line19-north-build")[0]
	var cap:Dictionary=config.futurePlans.filter(func(c:Dictionary):return str(c.id)=="bj-line13-capacity-build")[0]
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var by_line:Dictionary={}
	for group in cutoff.lineGroups:by_line[str(group.historicalLineId)]=group
	# Source-derived local anchors, explicitly not a city chronology proof.
	var prelude:=plan.duplicate(true);prelude.id="fixture-bj19-anchors";prelude.requiredTransfers=[];prelude.lineGroups=[]
	prelude.lineGroups.append(fragment(by_line["beijing-line19-19"],["beijing-s178","beijing-s389"],"fixture-current19"))
	prelude.lineGroups.append(fragment(by_line["beijing-line15-15"],["beijing-s2","beijing-s3","beijing-s4"],"fixture-line15"))
	prelude.lineGroups.append(fragment(by_line["beijing-route-20"],["beijing-s96","beijing-changping-zhufangbei","beijing-s250"],"fixture-changping"))
	prelude.lineGroups.append(fragment(by_line["beijing-line13-13"],["beijing-s97","beijing-s96","beijing-s95"],"fixture-current13"))
	prelude.lineGroups.append(fragment(cap.lineGroups[0],["beijing-s96","beijing-s95","beijing-open18-longzexi"],"fixture-capacityA"))
	prelude.lineGroups.append(fragment(cap.lineGroups[1],["beijing-open18-dongbeiwang","beijing-open18-longzexi","beijing-s94"],"fixture-capacityB"))
	prelude.lineGroups.append(fragment(by_line["beijing-line18-18"],["beijing-open18-dongbeiwang","beijing-open18-longzexi","beijing-open18-huilongguanwest"],"fixture-current18"))
	CampaignSystem._catalog.cities.beijing.futurePlans.append(prelude)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.phase="future";world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate();var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(result.get("ok",false)),"all real-side anchor fragments build: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	for group in Story.groups(world,true):
		result=Story.confirm_task(world,str(group.taskId),int(world.revision));check(bool(result.get("ok",false)),"each existing-side task confirms "+str(group.taskId)+": "+JSON.stringify(result.get("evaluation",{}).get("issues",[])))
	var old19:=JSON.stringify(WorldData.find_route(world,"historical_beijing-line19-19"))
	var before:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	world.storyState.phase="future";world.storyState.chapterId=plan.id;world.storyState.stage="build";app._enter(world)
	check(Story.targets(world,true).size()==9,"seven north stops plus branch stop and reused Mudanyuan are all explicit")
	var road:=ReferenceAlignment.planning_corridor("beijing19-qinghe-road-corridor")
	check(road.get("points",[]).size()>10 and str(road.get("sourceKind",""))=="official_road_corridor","branch uses explicit curved road corridor, never mislabels it as measured rail")
	check(ReferenceAlignment.label_for(road).contains("非施工线位"),"source precision remains visible")
	check(not ReferenceAlignment.planning_corridor_issue([],str(road.id),39.9,650).is_empty(),"missing actual path is a failure")
	check(not ReferenceAlignment.planning_corridor_issue([road.points[0],road.points[-1]],str(road.id),39.9,650).is_empty(),"two-point shortcut cannot pass the required road route")
	check(not ReferenceAlignment.planning_corridor_issue(road.points,"missing-source",39.9,650).is_empty(),"missing corridor reference cannot silently pass")
	preview=app._assist_candidate();check(str(preview.get("issue","")).is_empty(),"whole main and branch preview: "+str(preview.get("issue","")))
	check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"preview is isolated")
	result=app._commit_assisted_construction(preview,int(world.revision));check(bool(result.get("ok",false)),"main and branch commit atomically: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	var constructed:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	app.history.undo();check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"one undo restores all existing-side geometry")
	app.history.redo();check(constructed==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"redo restores the exact main and branch geometry")
	for group in Story.groups(world,true):
		result=Story.confirm_task(world,str(group.taskId),int(world.revision));check(bool(result.get("ok",false)),"main and branch have distinct task confirmations: "+str(result.get("error","")))
	for pair in plan.requiredTransfers:
		check(app._transfer_ready(pair),"actual paired routes serve both bodies: "+str(pair.id))
		var connection:Dictionary=pair.duplicate(true);connection.status="active"
		result=app._commit_transfer_connection(pair,connection,int(world.revision));check(bool(result.get("ok",false)),"explicit contact: "+str(result.get("error","")))
		var a:=Story.bound_station(world,str(pair.complexId),str(pair.stationInstanceIds[0]));var b:=Story.bound_station(world,str(pair.complexId),str(pair.stationInstanceIds[1]))
		check(a.id!=b.id and not bool(TrackNetwork.shortest_station_path(str(a.id),str(b.id),world,39.9).get("valid",false)),"independent line bodies never become train-connected via interchange")
	check(old19==JSON.stringify(WorldData.find_route(world,"historical_beijing-line19-19")),"planned extension does not replace today's 19-line service")
	var lifegu:=Story.bound_station(world,"beijing-f19-lifegu","beijing-f19-lifegu__north19")
	check(str(lifegu.get("constructionForm",""))=="地面一层双岛四线" and is_zero_approx(float(lifegu.depthM)),"final EIA surface station is not omitted or shown as a deep tunnel")
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing.projects.filter(func(t:Dictionary):return str(t.id)=="bj-line19-north-phase2")[0]
	check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"built main, branch and contacts satisfy independent scope")
	check(target.get("transferDefinitions",[]).size()==8 and str(target.get("transferReviewStatus",""))=="verified","eight EIA metro pairings have independent physical identities")
	var structure:=Story.bound_station(world,"beijing-f19-lifescience-south","beijing-f19-lifescience-south__north19")
	check(str(structure.get("constructionForm",""))=="地下三层双岛四线","Life Science South uses the three-floor structure in the final EIA")
	var mispaired:=world.duplicate(true)
	for connection in mispaired.transferConnections:
		if str(connection.id)=="future-transfer-bj19-newlongze-capacity13B":connection.stationInstanceIds[1]="beijing-open18-longzexi"
	check(not OfficialNetworkAudit.project_errors(mispaired,target).is_empty(),"a valid-looking wrong counterpart cannot pass by retaining the same connection ID")
	var no_pair:=world.duplicate(true)
	no_pair.transferConnections=no_pair.transferConnections.filter(func(p:Dictionary):return str(p.id)!="future-transfer-bj19-qinghe-changping")
	check(not OfficialNetworkAudit.project_errors(no_pair,target).is_empty(),"one omitted metro interface is a project failure")
	var broken:=world.duplicate(true)
	for edge in broken.trackEdges:
		if str(edge.get("referenceAlignmentId",""))==str(road.id):
			edge.geometry="straight";edge.erase("referencePoints");edge.erase("referenceAlignmentId")
	check(not OfficialNetworkAudit.project_errors(broken,target).is_empty(),"independent saved-world audit rejects a straightened branch even with correct station names")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"both planned branches and contacts survive actual disk reload")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("BEIJING19_NORTH_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
