extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var config:=CampaignSystem.city_config("beijing")
	var plan:Dictionary=config.futurePlans.filter(func(c:Dictionary):return str(c.id)=="bj-r4-north-build")[0]
	var east:Dictionary=config.futurePlans.filter(func(c:Dictionary):return str(c.id)=="bj-line3-east-build")[0]
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	# Explicit source-derived anchor fixture. This is a focused project replay,
	# not evidence that the whole city's earlier historical phases are correct.
	var prelude:=east.duplicate(true);prelude.id="fixture-r4-existing-anchors";prelude.requiredTransfers=[]
	var airport:Dictionary=cutoff.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="beijing-route-23")[0].duplicate(true)
	airport.taskId="fixture-r4-airport";prelude.lineGroups.append(airport)
	CampaignSystem._catalog.cities.beijing.chapters.append(prelude)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate();var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(result.get("ok",false)),"3-line and airport anchors built through actual command: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	for group in Story.groups(world,true):
		result=Story.confirm_task(world,str(group.taskId),int(world.revision));check(bool(result.get("ok",false)),"anchor task confirms separately")
	var guan:=Story.bound_station(world,"beijing-f3e-guanzhuanglu","beijing-f3e-guanzhuanglu")
	var proposal:Dictionary=app._reference_station_adjustment(str(guan.id))
	check(bool(proposal.get("ok",false)),"updated reference can be previewed through the shared station command")
	var unchanged:=JSON.stringify([world.stations,world.trackEdges,world.revision])
	check(not bool(app._commit_reference_station_adjustment(proposal,int(world.revision)+1).get("ok",false)),"stale reference proposal cannot commit")
	var forged:=proposal.duplicate(true);forged.candidate.latlng=[39.9,116.5]
	check(not bool(app._commit_reference_station_adjustment(forged,int(world.revision)).get("ok",false)),"caller cannot substitute another target position")
	check(unchanged==JSON.stringify([world.stations,world.trackEdges,world.revision]),"reference preview, discard and rejected proposals preserve formal geometry")
	var anchor_routes:=JSON.stringify(world.routes)
	world.storyState.phase="future";world.storyState.chapterId=plan.id;world.storyState.stage="build";app._enter(world)
	check(Story.targets(world,true).size()==5,"R4 task exposes all five stations, not two endpoints")
	var before:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	preview=app._assist_candidate()
	check(str(preview.get("issue","")).is_empty(),"all four intervals preview together: "+str(preview.get("issue","")))
	check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"preview does not add any station or track")
	result=app._commit_assisted_construction(preview,int(world.revision));check(bool(result.get("ok",false)),"complete R4 construction commits: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	var constructed:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	app.history.undo();check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"one undo removes the whole five-station project")
	app.history.redo();check(constructed==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"redo exactly restores the same four physical intervals")
	var linhe:=Story.bound_station(world,"beijing-fr4-linhe","beijing-fr4-linhe__r4north")
	check(str(linhe.get("constructionForm",""))=="高架三层侧式" and float(linhe.get("depthM",0))>0,"known elevated form uses an explicitly illustrative positive elevation")
	check(str(Story.profile(world,"beijing-fr4-linhe__r4north").parameterStatus.depthM)=="game_estimate","display elevation never claims a surveyed height")
	result=Story.confirm_task(world,str(plan.lineGroups[0].taskId),int(world.revision));check(bool(result.get("ok",false)),"formal project task confirms its own directed path")
	check(world.routes.size()>0,"formal line relation is produced by task confirmation")
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing.projects.filter(func(t:Dictionary):return str(t.id)=="bj-r4-north-phase1")[0]
	for pair in plan.requiredTransfers:
		check(app._transfer_ready(pair),"independent station bodies and both paths ready: "+str(pair.id))
		var connection:Dictionary=pair.duplicate(true);connection.status="active"
		result=app._commit_transfer_connection(pair,connection,int(world.revision));check(bool(result.get("ok",false)),"explicit planned contact commits: "+str(result.get("error","")))
		var one:=Story.bound_station(world,str(pair.complexId),str(pair.stationInstanceIds[0]));var two:=Story.bound_station(world,str(pair.complexId),str(pair.stationInstanceIds[1]))
		check(one.id!=two.id,"R4 and its counterpart never share a physical platform identity")
		check(not bool(TrackNetwork.shortest_station_path(str(one.id),str(two.id),world,39.9).get("valid",false)),"train cannot use the pedestrian interchange")
	check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"constructed result matches the independent five-stop project requirement")
	check(anchor_routes==JSON.stringify(world.routes.slice(0,world.routes.size()-1)),"R4 does not replace either anchor's line record")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"project and both contacts survive actual disk reload")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("BEIJING_R4_NORTH_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
