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
	var city:=CampaignSystem.city_config("beijing")
	var cutoff:Dictionary=city.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var current:=cutoff.duplicate(true);current.id="fixture-bj11-current";current.requiredTransfers=[];current.scopeCorrections=[]
	current.lineGroups=current.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="beijing-line11-11")
	CampaignSystem._catalog.cities.beijing.chapters.append(current)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.chapterId=current.id;world.storyState.stage="build";world.storyState.tutorialEnabled=false;app._enter(world)
	var preview:Dictionary=app._assist_candidate();var applied:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(applied.get("ok",false)),"current first phase builds through the player command")
	var task:=str(current.lineGroups[0].taskId);var result:=Story.confirm_task(world,task,int(world.revision))
	check(bool(result.get("ok",false)),"current four-station service confirms")
	var original_service:=JSON.stringify(WorldData.find_route(world,"historical_beijing-line11-11"))
	var plan:Dictionary=city.futurePlans.filter(func(p:Dictionary):return str(p.id)=="bj-line11-phase2-build")[0]
	check(bool(plan.required) and str(plan.status)=="approved","approved second phase is required, without claiming already open")
	check(plan.lineGroups[0].stationIds.size()==15,"fourteen new stations plus the existing terminal")
	check(plan.requiredTransfers.size()==7,"all seven implemented metro contacts are explicit")
	world.storyState.phase="future";world.storyState.futurePlanId=plan.id;world.storyState.chapterId=plan.id;world.storyState.stage="build";app._enter(world)
	preview=app._assist_candidate()
	check(str(preview.get("issue","")).is_empty(),"second-phase preview: "+str(preview.get("issue","")))
	var before:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	applied=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(applied.get("ok",false)),"second-phase formal construction: "+str(applied.get("error","")))
	if bool(applied.get("ok",false)):
		app.history.undo();check(JSON.stringify([world.stations,world.trackNodes,world.trackEdges])==before,"whole construction undo restores the current phase")
		app.history.redo()
		result=Story.confirm_task(world,str(plan.lineGroups[0].taskId),int(world.revision))
		check(bool(result.get("ok",false)),"second-phase task confirms: "+JSON.stringify(result.get("evaluation",{}).get("issues",[])))
		check(JSON.stringify(WorldData.find_route(world,"historical_beijing-line11-11"))==original_service,"current open service is unchanged")
		var construction:Array=world.routes.filter(func(r:Dictionary):return not str(r.get("constructionVariantId","")).is_empty() and str(r.get("historicalLineId",""))=="beijing-line11-11")
		check(construction.size()==1 and not bool(construction[0].get("open",true)),"new extension is a separate unopened construction variant")
		var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing.projects.filter(func(p:Dictionary):return str(p.id)=="bj-line11-phase2")[0].duplicate(true)
		target.transfers=[];target.transferDefinitions=[]
		check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"independent fourteen-station answer matches the real constructed route")
		var missing:=world.duplicate(true)
		missing.stations=missing.stations.filter(func(s:Dictionary):return str(s.get("name",""))!="小瓦窑")
		check(not OfficialNetworkAudit.project_errors(missing,target).is_empty(),"missing a published intermediate station fails")
		var names:Array=[]
		for s in world.stations:names.append(str(s.name))
		check(not names.has("洋桥"),"superseded Yangqiao tail is absent")
		var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
		check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"construction variant survives actual disk reload")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("BEIJING11_PHASE2_CHECKS ",count," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
