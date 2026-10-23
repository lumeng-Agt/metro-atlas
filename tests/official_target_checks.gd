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
	var correction_world:=WorldData.new_world("shenzhen","campaign")
	correction_world.storyState.phase="future";correction_world.storyState.chapterId="sz-line32-phase1-build";correction_world.storyState.stage="build"
	var old_transfer:Dictionary={"id":"future-transfer-sz32-xichong","name":"溪涌","lineIds":["shenzhen-line8-9","shenzhen-line2-2","shenzhen-line32-32"],"stationInstanceIds":["shenzhen-s291","shenzhen-s291__line2-2","shenzhen-s291__line32-32"],"status":"active"}
	correction_world.transferConnections=[old_transfer.duplicate(true),{"id":"unrelated","status":"active"}]
	var corrections:=Story.scope_correction_preview(correction_world,"project:sz-line32-phase1-build")
	_check(corrections.ok and corrections.changes.size()==1,"obsolete transfer has an explicit correction preview")
	_check(correction_world.transferConnections[0].status=="active","preview does not change the original relationship")
	var corrected_world:=correction_world.duplicate(true)
	Story._apply_scope_corrections(corrected_world,corrections)
	_check(corrected_world.transferConnections[0].status=="superseded" and corrected_world.transferConnections[1].status=="active","confirmed correction archives only the specified old relation")
	correction_world.transferConnections[0].lineIds=["player-edited"]
	_check(not Story.scope_correction_preview(correction_world,"project:sz-line32-phase1-build").ok,"player-edited old relationship is a conflict rather than silently overwritten")
	var replacement_world:Dictionary={"cityId":"shenzhen","stations":[],"routes":[old_route.duplicate(true),{"id":"unrelated-line","stationOrder":["keep"]}]}
	var replacement:=corrected.duplicate(true);replacement.chapterId="later-official-correction";replacement.replaceExistingService=true
	Story._store_historical_route(replacement_world,replacement)
	_check(replacement_world.routes[0].directions.size()==1 and replacement_world.routes[0].stationOrder==replacement.stationOrder,"explicit official scope correction replaces obsolete branches")
	_check(replacement_world.routes[1].stationOrder==["keep"],"scope replacement does not touch unrelated services")
	var rebinding_world:=WorldData.new_world("shenzhen","campaign")
	rebinding_world.storyState.phase="history";rebinding_world.storyState.chapterId="shenzhen-network-reconciliation-2026-10-01";rebinding_world.storyState.stage="build"
	rebinding_world.transferConnections=[{"id":"future-transfer-laojie-line3","name":"老街","lineIds":["shenzhen-line3-3","shenzhen-line17-17"],"stationInstanceIds":["shenzhen-s3","shenzhen-s3__line17-17"],"status":"active"}]
	var rebind:=Story.scope_correction_preview(rebinding_world,"route:shenzhen-r3")
	_check(rebind.ok and rebind.changes.size()==1,"physical platform correction is included in explicit task preview")
	_check(rebinding_world.transferConnections[0].stationInstanceIds[0]=="shenzhen-s3","platform correction does not run during preview")
	Story._apply_scope_corrections(rebinding_world,rebind)
	_check(rebinding_world.transferConnections[0].stationInstanceIds[0]=="shenzhen-s3__line3-3" and rebinding_world.transferConnections[0].status=="active","confirm rebinds the specified platform without destroying transfer identity")
	app.queue_free();await process_frame
	print("OFFICIAL_TARGET_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
