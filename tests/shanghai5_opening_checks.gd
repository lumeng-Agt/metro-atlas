extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var count:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	count+=1
	if not value:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var world:=WorldData.new_world("shanghai","campaign")
	var milestones:Array=OfficialNetworkAudit.target_data().cities.shanghai.historicalMilestones
	var previous_edges:Array=[]
	for original_id in ["shanghai-line5-first-2003","shanghai-network-milestone-2018-12-30","shanghai-network-milestone-2020-12-26"]:
		var original:Dictionary=CampaignSystem.city_config("shanghai").chapters.filter(func(c:Dictionary):return str(c.id)==original_id)[0]
		var fixture:=original.duplicate(true);fixture.id="fixture-sh5-"+str(original.date);fixture.requiredTransfers=[];fixture.scopeCorrections=[];fixture.serviceTransitions=[]
		fixture.lineGroups=fixture.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="shanghai-line5-5")
		CampaignSystem._catalog.cities.shanghai.chapters.append(fixture)
		world.storyState.chapterId=fixture.id;world.storyState.stage="build";world.storyState.tutorialEnabled=false;app._enter(world)
		var candidate:Dictionary=app._assist_candidate()
		check(str(candidate.get("issue","")).is_empty(),"preview "+original_id+": "+str(candidate.get("issue","")))
		var built:Dictionary=app._commit_assisted_construction(candidate,int(world.revision))
		check(bool(built.get("ok",false)),"formal construction "+original_id+": "+str(built.get("error","")))
		if not bool(built.get("ok",false)):break
		for edge in previous_edges:check(world.trackEdges.any(func(e:Dictionary):return str(e.id)==str(edge)),"existing physical track reused: "+str(edge))
		for group in fixture.lineGroups:
			var result:=Story.confirm_task(world,str(group.taskId),int(world.revision))
			check(bool(result.get("ok",false)),"individual task "+str(group.taskId)+": "+JSON.stringify(result.get("evaluation",{}).get("issues",[])))
		var expected:Dictionary=milestones.filter(func(m:Dictionary):return str(m.chapterId)==original_id)[0].duplicate(true)
		expected.groups=expected.groups.filter(func(g:Dictionary):return str(g.historicalLineId)=="shanghai-line5-5")
		check(OfficialNetworkAudit.project_errors(world,expected).is_empty(),"independent dated service order: "+original_id)
		var route:=WorldData.find_route(world,"historical_shanghai-line5-5")
		if str(original.date)=="2003-11-25":check(world.stations.size()==11 and route.directions.size()==1,"first opening contains only eleven stations")
		else:
			check(world.stations.size()==19 and route.directions.size()==2,"south extension keeps two real arms, without duplicate stations")
			var lengths:Array=[]
			for direction in route.directions:lengths.append(direction.stationIds.size())
			lengths.sort()
			check(lengths==([5,15] if str(original.date)=="2018-12-30" else [11,15]),"2018 five-stop shuttle becomes an eleven-stop through branch only in 2020")
		var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
		check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)),"dated service survives actual save/reload")
		if not bool(loaded.get("ok",false)):break
		world=loaded.world;previous_edges=[]
		for edge in world.trackEdges:previous_edges.append(str(edge.id))
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("SHANGHAI5_OPENING_CHECKS ",count," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
