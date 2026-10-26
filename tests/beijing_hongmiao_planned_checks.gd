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
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var original:Dictionary=config.futurePlans.filter(func(c:Dictionary):return str(c.id)=="bj-line22-build")[0]
	# Explicitly scoped real station fragments exercise the current/future
	# boundary. The full replay separately verifies all 33 and all 22 stops.
	var prelude:=cutoff.duplicate(true);prelude.id="fixture-hongmiao-current14";prelude.lineGroups=[];prelude.requiredTransfers=[];prelude.serviceTransitions=[];prelude.scopeCorrections=[]
	var main:Dictionary=cutoff.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="beijing-line14-14")[0].duplicate(true)
	main.stationIds=["beijing-s276","beijing-s278","beijing-s279"];main.taskId="fixture-main14";main.replaceExistingService=false;main.defaultServiceStatus="open"
	prelude.lineGroups=[main];CampaignSystem._catalog.cities.beijing.chapters.append(prelude)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate();var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(result.get("ok",false)),"current 14-line fragment is built through the normal command")
	result=Story.confirm_task(world,str(main.taskId),int(world.revision));check(bool(result.get("ok",false)),"current fragment confirms without Red Temple as a stop")
	var main_before:=JSON.stringify(WorldData.find_route(world,"historical_beijing-line14-14"))
	var future:=original.duplicate(true);future.id="fixture-hongmiao-future";future.lineGroups=[]
	for group in original.lineGroups:
		if str(group.get("coverageGroupId",""))=="beijing-line14-hongmiao-planned":future.lineGroups.append(group.duplicate(true))
		elif str(group.get("coverageGroupId",""))=="beijing-line22-first-opening":
			var short:Dictionary=group.duplicate(true);short.stationIds=short.stationIds.slice(0,2);future.lineGroups.append(short)
	future.requiredTransfers=original.requiredTransfers.filter(func(t:Dictionary):return str(t.id)=="future-transfer-bj22-hongmiao-14")
	CampaignSystem._catalog.cities.beijing.futurePlans.append(future);world.storyState.phase="future";world.storyState.chapterId=future.id;app._enter(world)
	preview=app._assist_candidate();check(str(preview.get("issue","")).is_empty(),"planned independent 14/22 bodies preview together: "+str(preview.get("issue","")))
	result=app._commit_assisted_construction(preview,int(world.revision));check(bool(result.get("ok",false)),"planned infill commits formally: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	var physical:=JSON.stringify([world.stations,world.trackEdges,world.trackNodes])
	app.history.undo();app.history.redo();check(physical==JSON.stringify([world.stations,world.trackEdges,world.trackNodes]),"the whole two-line construction restores exactly")
	for group in Story.groups(world,true):
		result=Story.confirm_task(world,str(group.taskId),int(world.revision));check(bool(result.get("ok",false)),"each project task confirms separately: "+str(result.get("error","")))
	check(main_before==JSON.stringify(WorldData.find_route(world,"historical_beijing-line14-14")),"planned infill preserves the actual current service and directed path")
	var pair:Dictionary=future.requiredTransfers[0]
	check(app._transfer_ready(pair),"14-side infill is an actual continuous planned path, not a falsely open current stop")
	var connection:=pair.duplicate(true);connection.status="active"
	result=app._commit_transfer_connection(pair,connection,int(world.revision));check(bool(result.get("ok",false)),"explicit planned 14/22 contact confirms: "+str(result.get("error","")))
	check(main_before==JSON.stringify(WorldData.find_route(world,"historical_beijing-line14-14")),"contact confirmation cannot open or replace current line 14")
	var red14:=Story.bound_station(world,"beijing-s277",str(pair.stationInstanceIds[pair.lineIds.find("beijing-line14-14")]))
	var red22:=Story.bound_station(world,"beijing-s277",str(pair.stationInstanceIds[pair.lineIds.find("beijing-line22-22")]))
	check(not red14.is_empty() and not red22.is_empty() and red14.id!=red22.id,"planned interchange has two different physical line bodies")
	check(not bool(TrackNetwork.shortest_station_path(str(red14.id),str(red22.id),world,39.9).get("valid",false)),"contact never becomes a train track")
	var scope:Dictionary={"groups":[{"id":"current14-fragment","historicalLineId":"beijing-line14-14","stationNames":["金台路","大望路","九龙山"],"fullServiceOrder":true,"forbiddenStationNames":["红庙"]}]}
	check(OfficialNetworkAudit.project_errors(world,scope).is_empty(),"current stop audit excludes the built-only infill variant")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),scope).is_empty(),"current/future separation survives actual disk reload")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("BEIJING_HONGMIAO_PLANNED_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
