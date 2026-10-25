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
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var config:=CampaignSystem.city_config("guangzhou")
	var first:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.id)=="gz-line1-1997")[0].duplicate(true)
	first.id="fixture-guangzhou-original-line1";first.requiredTransfers=[]
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0].duplicate(true)
	cutoff.id="fixture-guangzhou-line1-line22";cutoff.requiredTransfers=[];cutoff.scopeCorrections=[]
	cutoff.lineGroups=cutoff.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId) in ["guangzhou-line1","guangzhou-line22-17"])
	CampaignSystem._catalog.cities.guangzhou.chapters.append_array([first,cutoff])
	var world:=WorldData.new_world("guangzhou","campaign");world.storyState.chapterId=first.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	_check(str(preview.get("issue","")).is_empty(),"original first-line preview: "+str(preview.get("issue","")))
	var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	_check(bool(result.get("ok",false)),"original first-line formal construction")
	if not bool(result.get("ok",false)):await _finish(app);return
	var original:=Story._station_for_instance(world,"guangzhou-s298").duplicate(true)
	var old_edges:Array=world.trackEdges.duplicate(true)
	_check(str(original.get("stationLineId",""))=="guangzhou-line1","original schematic body remains owned by Line 1")
	world.storyState.chapterId=cutoff.id;app._enter(world)
	preview=app._assist_candidate()
	_check(str(preview.get("issue","")).is_empty(),"separate Line22 preview: "+str(preview.get("issue","")))
	_check(Story._station_for_instance(world,"guangzhou-s298__line22-17").is_empty(),"preview does not create a formal Line22 body")
	result=app._commit_assisted_construction(preview,int(world.revision))
	_check(bool(result.get("ok",false)),"Line22 construction commits through normal command: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):await _finish(app);return
	var body:=Story._station_for_instance(world,"guangzhou-s298__line22-17")
	_check(not body.is_empty() and str(body.stationLineId)=="guangzhou-line22-17","Line22 has a separate correctly owned body")
	var preserved:=Story._station_for_instance(world,"guangzhou-s298")
	_check(preserved.latlng==original.latlng and preserved.endpointNodes==original.endpointNodes and preserved.heading==original.heading,"original body is not moved or rotated")
	_check(old_edges.all(func(e:Dictionary):return world.trackEdges.has(e)),"original physical tracks are retained")
	_check(not app.history.undo().is_empty(),"separate body construction is one undo transaction")
	_check(Story._station_for_instance(world,"guangzhou-s298__line22-17").is_empty(),"undo removes only the new Line22 body")
	_check(not app.history.redo().is_empty(),"redo restores the same physical construction")
	for group in cutoff.lineGroups:
		result=Story.confirm_task(world,str(group.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"line task confirms with its own body: "+str(result.get("error","")))
	var expected:Dictionary=OfficialNetworkAudit.target_data().cities.guangzhou.cutoffNetwork.duplicate(true)
	expected.groups=expected.groups.filter(func(g:Dictionary):return str(g.historicalLineId) in ["guangzhou-line1","guangzhou-line22-17"]);expected.transfers=[]
	_check(OfficialNetworkAudit.project_errors(world,expected).is_empty(),"both current official orders have correctly owned physical bodies")
	var saved:=SaveManager.save_world(world)
	_check(bool(saved.get("ok",false)),"isolated current world saves")
	if bool(saved.get("ok",false)):
		var loaded:=SaveManager.load_file(str(saved.path))
		_check(bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.world,expected).is_empty(),"distinct bindings and paths survive reload")
	await _finish(app)
func _finish(app:Control) -> void:
	app.queue_free();await process_frame
	for failure in failures:print("FAIL ",failure)
	print("GUANGZHOU_XILANG_BODY_CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
