extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var config:=CampaignSystem.city_config("beijing")
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing
	# Focused real 6/8/14-line construction fixture, not an invented full-city
	# completion record. Full old-save continuation is a separate actual replay.
	var world:=WorldData.new_world("beijing","campaign")
	var cases:Array=[
		["beijing-network-milestone-2025-12-27","beijing-line6-6",35,["通运门"]],
		["beijing-line6-tongyunmen-2026","beijing-line6-6",36,[]],
		["beijing-network-milestone-2021-12-31","beijing-line8-8",35,[]],
		["beijing-network-milestone-2021-12-31","beijing-line14-14",33,["红庙","陶然桥","高家园"]],
		["beijing-network-milestone-1987-12-28","beijing-lineearly1",18,[]],
	]
	for row in cases:
		var original:Dictionary=config.chapters.filter(func(c:Dictionary):return c.id==row[0])[0]
		var fixture:Dictionary=original.duplicate(true)
		fixture.id="fixture-bj-current-"+str(row[1])+"-"+str(row[2]);fixture.requiredTransfers=[];fixture.historicalEventIds=[]
		fixture.scopeCorrections=[]
		fixture.lineGroups=original.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)==str(row[1]))
		CampaignSystem._catalog.cities.beijing.chapters.append(fixture)
		world.storyState.chapterId=fixture.id;world.storyState.stage="build";app._enter(world)
		var retained:Dictionary={}
		for s in world.stations:retained[str(s.id)]={"latlng":s.latlng.duplicate(),"heading":s.heading,"endpointNodes":s.endpointNodes.duplicate()}
		var preview:Dictionary=app._assist_candidate()
		check(str(preview.get("issue","")).is_empty(),str(row[1])+" preview: "+str(preview.get("issue","")))
		var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
		check(bool(result.get("ok",false)),str(row[1])+" formal commit: "+str(result.get("error","")))
		if not bool(result.get("ok",false)):break
		check(world.stations.all(func(s:Dictionary):return not retained.has(str(s.id)) or (s.latlng==retained[str(s.id)].latlng and s.heading==retained[str(s.id)].heading and s.endpointNodes==retained[str(s.id)].endpointNodes)),"construction preserves existing geometry and station ports")
		var geometry:=JSON.stringify([world.stations,world.trackEdges,world.trackNodes])
		app.history.undo();app.history.redo()
		check(geometry==JSON.stringify([world.stations,world.trackEdges,world.trackNodes]),"whole construction undo/redo")
		for proposal in Story.evaluate(world).get("serviceTransitions",[]):
			if Story._has_service_range(world,str(proposal.id)):continue
			result=app._commit_service_transition(proposal,int(world.revision))
			check(bool(result.get("ok",false)),"explicit opening range commits through the normal command: "+str(result.get("error","")))
			if str(row[1])=="beijing-lineearly1":
				check(proposal.stationIds.size()==19 and proposal.stationIds.front()==proposal.stationIds.back() and proposal.edgePathsBySegment.size()==18,"the explicit opening includes the ring-closing segment")
				check(Story._effective_service_status(world,str(row[1]),str(proposal.stationIds[0]),str(proposal.stationIds[-2]),"built")=="open","closing interval status applies in the reverse direction too")
				check(not app.history.undo().is_empty() and not Story._has_service_range(world,str(proposal.id)),"whole opening action can be undone")
				check(not app.history.redo().is_empty() and Story._has_service_range(world,str(proposal.id)),"whole opening action can be redone")
		for g in Story.groups(world,true):
			result=Story.confirm_task(world,str(g.taskId),int(world.revision))
			check(bool(result.get("ok",false)),"confirm actual continuous service: "+str(result.get("error","")))
		var route:Dictionary=WorldData.find_route(world,"historical_"+str(row[1]))
		if route.is_empty():check(false,str(row[1])+" formal route missing after opening/task confirmation");break
		var names:Array=[]
		for id in route.get("stationOrder",[]):names.append(WorldData.find_station(world,str(id)).get("name",""))
		var unique:Dictionary={}
		for name in names:unique[name]=true
		var is_ring:bool=str(row[1])=="beijing-lineearly1"
		check(names.size()==int(row[2])+(1 if is_ring else 0) and unique.size()==int(row[2]),str(row[1])+" has unique period stops plus the explicit ring closure where required")
		if is_ring:check(route.stationOrder.front()==route.stationOrder.back() and route.directions[0].edgePathsBySegment.size()==18,"18-stop ring requires its real eighteenth rail section")
		check(row[3].all(func(n:String):return not names.has(n)),"reserved/deferred stops are not prematurely open")
		check(Story.changed_service_continuity_error(world,[route]).is_empty(),"actual directed service is continuous")
		var expected:Dictionary=target.historicalMilestones.filter(func(m:Dictionary):return str(m.chapterId)==str(row[0]))[0]
		var scope:Dictionary={"groups":expected.groups.filter(func(g:Dictionary):return str(g.get("historicalLineId",""))==str(row[1]))}
		var errors:=OfficialNetworkAudit.project_errors(world,scope)
		check(errors.is_empty(),"independent full period scope: "+JSON.stringify(errors))
		var original_direction:Dictionary=route.directions[0].duplicate(true)
		route.directions[0].stationIds.append(route.directions[0].stationIds[-1])
		check(not OfficialNetworkAudit.project_errors(world,scope).is_empty(),"appended duplicate cannot pass a full service snapshot")
		route.directions[0]=original_direction
		route.directions.append(original_direction.duplicate(true));route.directions[-1].stationIds.append(route.directions[-1].stationIds[-1])
		check(not OfficialNetworkAudit.project_errors(world,scope).is_empty(),"valid main direction cannot hide an obsolete invalid parallel direction")
		route.directions.pop_back()
		var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
		check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)),"actual construction save/reload")
		if not bool(loaded.get("ok",false)):break
		world=loaded.world
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("BEIJING_CURRENT_SCOPE_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
