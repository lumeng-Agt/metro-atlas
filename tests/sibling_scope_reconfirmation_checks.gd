extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var app:=App.new();root.add_child(app);await process_frame
	var fixture:Dictionary=CampaignSystem.city_config("shenzhen").futurePlans.filter(func(p:Dictionary):return str(p.id)=="sz-line27-phase1-build")[0].duplicate(true)
	fixture.id="fixture-source-defined-disconnected-sibling";fixture.scopeCorrections=[];fixture.projectIds=[];fixture.scopeRevision="fixture-explicit-revision"
	fixture.requiredTransfers=fixture.requiredTransfers.filter(func(t:Dictionary):return str(t.id)=="future-transfer-sz27-jihuayiyuan-25")
	var adjoining:Dictionary=CampaignSystem.city_config("shenzhen").futurePlans.filter(func(p:Dictionary):return str(p.id)=="sz-line25-phase1-build")[0].lineGroups[0].duplicate(true)
	adjoining.stationIds=adjoining.stationIds.slice(-2);adjoining.taskId="fixture-adjoining-25"
	fixture.lineGroups.append(adjoining)
	CampaignSystem._catalog.cities.shenzhen.futurePlans.append(fixture)
	var world:=WorldData.new_world("shenzhen","campaign")
	world.storyState.phase="future";world.storyState.chapterId=fixture.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate();var built:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	_check(bool(built.get("ok",false)),"source-based fixture builds both disconnected 27-line sections and the adjoining 25-line body: "+str(built.get("error","")))
	for group in fixture.lineGroups:
		var result:=Story.confirm_task(world,str(group.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"each source-defined fixture task confirms: "+str(result.get("error","")))
	var target:Dictionary=fixture.requiredTransfers[0];var connection:=target.duplicate(true);connection.status="active"
	var linked:Dictionary=app._commit_transfer_connection(target,connection,int(world.revision))
	_check(bool(linked.get("ok",false)),"the real independent station bodies establish their explicitly confirmed relationship: "+str(linked.get("error","")))
	var milestone:=Story.commit_chapter(world,int(world.revision))
	_check(bool(milestone.get("ok",false)),"fixture milestone records its actual before/after planning difference: "+str(milestone.get("error","")))
	_check(str(world.storyState.chapterTaskProgress[str(fixture.id)].scopeRevision)==SaveManager._chapter_scope_revision(fixture),"milestone confirmation and content upgrade use the same scope identity")
	var unchanged:=world.duplicate(true)
	var catalogue_revision:=str(CampaignSystem._catalog.contentRevision)
	CampaignSystem._catalog.contentRevision="fixture-unrelated-content-update"
	_check(not bool(SaveManager._recheck_expanded_projects(unchanged).get("changed",true)) and unchanged.storyState.completedChapterIds.has(str(fixture.id)),"an unrelated content update does not reopen an unchanged confirmed scope")
	CampaignSystem._catalog.contentRevision=catalogue_revision
	var expanded:=fixture.duplicate(true);expanded.lineGroups[0].stationIds.append("fixture-missing-stop")
	_check(CampaignSystem.chapter_scope_revision(expanded)!=CampaignSystem.chapter_scope_revision(fixture),"expanded targets change scope identity even if an author forgets the manual revision bump")
	var original_stations:=JSON.stringify(world.stations);var original_edges:=JSON.stringify(world.trackEdges)
	# Simulate precisely a content migration, not a completion shortcut: archive
	# old task progress and require every task to go through confirmation again.
	world.storyState.legacyTaskProgress={str(fixture.id):world.storyState.chapterTaskProgress[str(fixture.id)].duplicate(true)}
	world.storyState.chapterTaskProgress.erase(str(fixture.id));world.storyState.completedChapterIds.erase(str(fixture.id));world.storyState.stage="build"
	app._enter(world)
	var first:Dictionary=Story.confirm_task(world,str(fixture.lineGroups[0].taskId),int(world.revision))
	_check(bool(first.get("ok",false)),"reconfirming the main task preserves a valid disconnected sibling already supporting a relationship: "+str(first.get("error","")))
	_check(not Story.task_confirmed(world,str(fixture.lineGroups[1].taskId)),"preserving a sibling path never silently confirms its task")
	_check(world.transferConnections.size()==1 and str(world.transferConnections[0].status)=="active","the valid independently confirmed relationship is neither deleted nor silently archived")
	_check(SaveManager.validate(world).is_empty(),"the intermediate reconfirmation state remains saveable")
	for group in fixture.lineGroups.slice(1):
		_check(bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),"the remaining task still needs and accepts its own confirmation")
	_check(bool(Story.commit_chapter(world,int(world.revision)).get("ok",false)),"all individually reconfirmed tasks complete the milestone")
	_check(JSON.stringify(world.stations)==original_stations and JSON.stringify(world.trackEdges)==original_edges,"scope reconfirmation never moves, deletes or reconstructs existing physical work")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and SaveManager.validate(loaded.get("world",{})).is_empty(),"reconfirmed disconnected scopes and the relationship survive actual disk reload")
	CampaignSystem._catalog.cities.shenzhen.futurePlans.pop_back()
	app.queue_free();await process_frame
	print("SIBLING_SCOPE_RECONFIRMATION_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
