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
	var city:=CampaignSystem.city_config("chengdu")
	var plan:Dictionary=city.futurePlans.filter(func(p:Dictionary):return str(p.id)=="cd-line12-phase1-build")[0]
	# The EIA notice publishes 34.2 km, 28 stations and the Pu'an-Shunhejiayuan
	# extent, but no station table. Only two sections have detailed planning
	# announcements, so the task must stay inside those two sections.
	check(bool(plan.required) and str(plan.status)=="approved_preparatory","phase one stays a required preparatory project")
	check(plan.lineGroups.size()==2,"two published sections are separate tasks")
	var puan:Dictionary=plan.lineGroups[0]
	var tiansheng:Dictionary=plan.lineGroups[1]
	check(puan.stationIds.size()==2 and tiansheng.stationIds.size()==2,"each published section has its two announced stations")
	var puan_names:Array=[]
	for id in puan.stationIds:puan_names.append(str(puan.stationNames[id]))
	var tiansheng_names:Array=[]
	for id in tiansheng.stationIds:tiansheng_names.append(str(tiansheng.stationNames[id]))
	check(puan_names==["普安","通港路"],"Pu'an section order follows the 2026-08-12 announcement: "+str(puan_names))
	check(tiansheng_names==["天盛路","光明村"],"Tiansheng section order follows the 2026-08-14 announcement: "+str(tiansheng_names))
	var world:=WorldData.new_world("chengdu","campaign")
	world.storyState.phase="future";world.storyState.futurePlanId=plan.id;world.storyState.chapterId=plan.id
	world.storyState.stage="build";world.storyState.tutorialEnabled=false;app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	check(str(preview.get("issue","")).is_empty(),"published sections preview: "+str(preview.get("issue","")))
	var before:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	var applied:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(applied.get("ok",false)),"published sections build through the player command: "+str(applied.get("error","")))
	if not bool(applied.get("ok",false)):
		app.queue_free();await process_frame
		for failure in failures:push_error(failure)
		print("CHENGDU12_PHASE1_CHECKS ",count," FAILURES ",failures.size());quit(1);return
	app.history.undo()
	check(JSON.stringify([world.stations,world.trackNodes,world.trackEdges])==before,"whole construction undo restores the empty site")
	app.history.redo()
	for group in [puan,tiansheng]:
		var result:=Story.confirm_task(world,str(group.taskId),int(world.revision))
		check(bool(result.get("ok",false)),"task confirms: "+str(group.taskId)+" "+str(result.get("evaluation",{}).get("issues",[])))
	# Only four published stations exist; the unpublished 24 must not appear.
	var names:Array=[]
	for station in world.stations:names.append(str(station.name))
	check(names.size()==4,"exactly the four announced stations were built: "+str(names))
	check(not names.has("舜和家园") and not names.has("电子科大"),"unpublished stations are not invented")
	# The two sections must stay disconnected instead of a made-up gap corridor.
	var route:Dictionary=WorldData.find_route(world,"historical_chengdu-line12")
	var directions:Array=route.get("directions",[])
	check(directions.size()==2,"the two published sections keep separate service directions")
	check(directions.all(func(d:Dictionary):return d.get("stationIds",[]).size()==2),"neither direction bridges the unpublished gap")
	var joined:=false
	for direction in directions:
		var order:Array=direction.get("stationIds",[])
		if order.size()==4:joined=true
	check(not joined,"no four-station service is invented across unpublished stations")
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.chengdu.projects.filter(func(p:Dictionary):return str(p.id)=="cd-line12-phase1")[0]
	check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"independent four-station answer matches the built sections")
	var missing:=world.duplicate(true)
	missing.stations=missing.stations.filter(func(s:Dictionary):return str(s.get("name",""))!="通港路")
	check(not OfficialNetworkAudit.project_errors(missing,target).is_empty(),"dropping an announced station fails the independent check")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"both sections survive an actual disk reload")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("CHENGDU12_PHASE1_CHECKS ",count," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
