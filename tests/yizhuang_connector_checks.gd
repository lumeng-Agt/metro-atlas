extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const Engineering=preload("res://scripts/engineering_construction.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	# Labelled isolated prelude, not a shortcut in the full-city replay: build
	# the two existing lines through the same formal commands as a player.
	var cutoff:Dictionary=CampaignSystem.city_config("beijing").chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var prelude:=cutoff.duplicate(true);prelude.id="fixture-existing-yizhuang-five";prelude.requiredTransfers=[];prelude.scopeCorrections=[];prelude.projectIds=[]
	prelude.serviceTransitions=[]
	prelude.lineGroups=prelude.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId) in ["beijing-line5-5","beijing-route-24"])
	CampaignSystem._catalog.cities.beijing.chapters.append(prelude)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var candidate:Dictionary=app._assist_candidate()
	_check(str(candidate.get("issue","")).is_empty(),"existing 5/Yizhuang lines have a valid formal construction preview: "+str(candidate.get("issue","")))
	var applied:Dictionary=app._commit_assisted_construction(candidate,int(world.revision))
	_check(bool(applied.get("ok",false)),"existing line prelude commits through the normal construction command")
	for group in prelude.lineGroups:
		_check(bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),"existing line service confirms normally: "+str(group.taskId))
	var before_stations:Array=world.stations.duplicate(true);var before_routes:Array=world.routes.duplicate(true);var before_edges:int=world.trackEdges.size()
	var plan:Dictionary=CampaignSystem.city_config("beijing").futurePlans.filter(func(p:Dictionary):return str(p.id)=="bj-yizhuang-connector-build")[0]
	world.storyState.phase="future";world.storyState.chapterId=plan.id;world.storyState.stage="build";app._enter(world)
	candidate=app._assist_candidate()
	_check(str(candidate.get("issue","")).is_empty(),"actual reviewed connector and through relation preview: "+str(candidate.get("issue","")))
	_check(world.stations==before_stations and world.routes==before_routes and world.trackEdges.size()==before_edges,"preview leaves existing stations, tracks and current services unchanged")
	_check(not bool(app._commit_assisted_construction(candidate,int(world.revision)-1).get("ok",true)),"stale connector geometry cannot commit")
	applied=app._commit_assisted_construction(candidate,int(world.revision))
	_check(bool(applied.get("ok",false)),"connector geometry commits in one formal transaction: "+str(applied.get("error","")))
	_check(world.stations==before_stations and world.routes==before_routes and world.trackEdges.size()==before_edges+3,"three physical corridor sections add no passenger station or current service")
	_check(not app.history.undo().is_empty() and world.trackEdges.size()==before_edges,"entire connector undoes in one step")
	_check(not app.history.redo().is_empty() and bool(Engineering.evaluate(world,plan.lineGroups[0]).complete),"redo restores actual engineering continuity")
	for group in plan.lineGroups:
		var result:=Story.confirm_task(world,str(group.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"reviewed engineering/through task confirms: "+JSON.stringify(result))
	_check(world.stations==before_stations and world.routes.slice(0,before_routes.size())==before_routes,"future through confirmation keeps both open services and their existing bodies")
	var future:Dictionary=world.routes[-1]
	_check(not bool(future.open) and str(future.get("serviceStatus",""))=="built" and future.stationOrder.size()==36,"future 36-stop through relation remains unopen")
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing.projects.filter(func(p:Dictionary):return str(p.id)=="bj-yizhuang-connector")[0]
	var issues:=OfficialNetworkAudit.project_errors(world,target)
	_check(issues.is_empty(),"independent physical corridor and full through-order check: "+JSON.stringify(issues))
	var broken:=world.duplicate(true);broken.trackEdges=broken.trackEdges.filter(func(e:Dictionary):return str(e.get("engineeringTaskId",""))!=str(plan.lineGroups[0].taskId))
	_check(not OfficialNetworkAudit.project_errors(broken,target).is_empty(),"old Songjiazhuang/Xiaocun service cannot substitute for the missing new connector")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"actual disk reload retains geometry, both current services and future through relation")
	_check(bool(Story.commit_chapter(world,int(world.revision)).get("ok",false)),"construction milestone confirms without opening a future project")
	_check(not bool(CampaignSystem.delivery_eligibility("beijing").get("ok",false)),"unfinished independent city/platform review continues to block full delivery")
	CampaignSystem._catalog.cities.beijing.chapters.pop_back();app.queue_free();await process_frame
	print("YIZHUANG_CONNECTOR_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
