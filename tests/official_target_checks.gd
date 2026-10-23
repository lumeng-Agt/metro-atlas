extends SceneTree

const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var failures:Array[String]=[]
var checks:=0

func _initialize() -> void:call_deferred("_run")

func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var app:=App.new();root.add_child(app);await process_frame
	# A focused project fixture, not evidence of cumulative city completion.
	var world:=WorldData.new_world("shenzhen","campaign")
	world.storyState.phase="future";world.storyState.chapterId="sz-line15-build";world.storyState.stage="build"
	app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	var stale:Dictionary=app._commit_assisted_construction(preview,int(world.revision)-1)
	_check(not bool(stale.get("ok",false)) and world.stations.is_empty(),"stale construction cannot change the world")
	var applied:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	_check(bool(applied.get("ok",false)),"24-station circuit uses formal assisted commit")
	var task:="project:sz-line15-build"
	var confirmed:=Story.confirm_task(world,task,int(world.revision))
	_check(bool(confirmed.get("ok",false)),"ring task confirms after real construction")
	var official:=OfficialNetworkAudit.current_project_errors(world,["sz-line15"])
	_check(official.is_empty(),"built ring matches independently transcribed official order: "+JSON.stringify(official))
	var route:Dictionary=WorldData.find_route(world,"historical_shenzhen-line15-15")
	_check(route.stationOrder.size()==25 and route.stationOrder.front()==route.stationOrder.back(),"24 unique stops require an actual closing segment")
	var broken:=world.duplicate(true)
	var closing_id:=str(route.directions[0].edgePathsBySegment[-1][0].id)
	broken.trackEdges=broken.trackEdges.filter(func(edge:Dictionary):return str(edge.id)!=closing_id)
	_check(not OfficialNetworkAudit.current_project_errors(broken,["sz-line15"]).is_empty(),"missing ring edge fails actual-world audit")
	var missing:=world.duplicate(true);missing.stations[3].name="错误站名"
	_check(not OfficialNetworkAudit.current_project_errors(missing,["sz-line15"]).is_empty(),"wrong intermediate stop fails independent order")
	var wrong_body:=world.duplicate(true);wrong_body.stations[3].stationLineId="another-line"
	_check(not OfficialNetworkAudit.current_project_errors(wrong_body,["sz-line15"]).is_empty(),"another line's physical platform cannot stand in")
	_check(Story.task_confirmed(world,task),"fresh scope fingerprint confirms")
	world.storyState.chapterTaskProgress["sz-line15-build"].tasks[task].scopeFingerprint="obsolete"
	_check(not Story.task_confirmed(world,task),"old task completion cannot cover changed construction scope")
	var legacy:=WorldData.new_world("beijing","campaign")
	legacy.storyState.phase="future_gap";legacy.storyState.chapterId="";legacy.storyState.completedChapterIds=["bj-m101-phase1-build"]
	legacy.storyState.scopeContentRevision="old-content"
	legacy.storyState.chapterTaskProgress={"bj-m101-phase1-build":{"status":"confirmed","scopeRevision":"old","tasks":{}}}
	var before:=JSON.stringify(legacy.stations)
	_check(bool(SaveManager.save_world(legacy).get("ok",false)),"legacy scope fixture saves")
	var loaded:=SaveManager.load_file(SaveManager.save_path(str(legacy.gameId)))
	_check(bool(loaded.get("ok",false)),"scope upgrade can load")
	if bool(loaded.get("ok",false)):
		_check(not loaded.world.storyState.completedChapterIds.has("bj-m101-phase1-build"),"four-point legacy completion does not skip fourteen-station scope")
		_check(JSON.stringify(loaded.world.stations)==before,"scope upgrade preserves physical planning")
		_check(loaded.world.storyState.get("legacyTaskProgress",{}).has("bj-m101-phase1-build"),"original completion record remains archived")
		var originals:=DirAccess.open(SaveManager.root_path().path_join("originals"))
		_check(originals!=null and not originals.get_files().is_empty(),"content migration preserves original file before loading")
	_check(not CampaignSystem.delivery_eligibility("shenzhen").ok,"unreviewed remaining city content blocks complete release")
	var rebinding:Dictionary={"cityId":"shenzhen","stations":[],"routes":[]}
	for suffix in ["old","new"]:
		for name in ["a","b","c"]:rebinding.stations.append({"id":name+suffix,"stationComplexId":name})
	var old_route:Dictionary={"id":"line","historicalLineId":"line","chapterId":"same-task","stationOrder":["aold","bold","cold"],"directions":[{"stationIds":["aold","bold","cold"],"edgePathsBySegment":[[],[]]}]}
	rebinding.routes.append(old_route)
	var corrected:Dictionary={"id":"line","historicalLineId":"line","chapterId":"same-task","stationOrder":["anew","bnew","cnew"],"directions":[{"stationIds":["anew","bnew","cnew"],"edgePathsBySegment":[[],[]]}]}
	Story._store_historical_route(rebinding,corrected)
	_check(rebinding.routes[0].directions.size()==1 and rebinding.routes[0].stationOrder==corrected.stationOrder,"same-task physical rebinding replaces obsolete service instead of retaining a ghost branch")
	app.queue_free();await process_frame
	print("OFFICIAL_TARGET_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
