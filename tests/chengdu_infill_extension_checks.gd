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
	var world:=WorldData.new_world("chengdu","campaign")
	# Explicit sequential Line 1 fixture; other city events are not claimed here.
	var stages:=["cd-line1-2010","chengdu-line1-ocean-2013","chengdu-line1-jincheng-rename-2013","cd-line1-2015"]
	var terminal_id:="";var terminal_before:Dictionary={}
	for id in stages:
		world.storyState.chapterId=id;world.storyState.stage="build";app._enter(world)
		var preview:Dictionary=app._assist_candidate()
		_check(str(preview.get("issue","")).is_empty(),id+" preview: "+str(preview.get("issue","")))
		if not str(preview.get("issue","")).is_empty():break
		var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
		_check(bool(result.get("ok",false)),id+" formal commit: "+str(result.get("error","")))
		if not bool(result.get("ok",false)):break
		if not terminal_id.is_empty():
			var terminal:=WorldData.find_station(world,terminal_id)
			_check(terminal.latlng==terminal_before.latlng and terminal.heading==terminal_before.heading and terminal.endpointNodes==terminal_before.endpointNodes,id+" preserves original Century City physical body")
		for group in Story.groups(world,true):
			result=Story.confirm_task(world,str(group.taskId),int(world.revision))
			_check(bool(result.get("ok",false)),id+" confirms connected path: "+str(result.get("error","")))
		var expected:Array=OfficialNetworkAudit.target_data().cities.chengdu.historicalMilestones.filter(func(m:Dictionary):return str(m.chapterId)==id)
		_check(expected.size()==1 and OfficialNetworkAudit.project_errors(world,expected[0]).is_empty(),id+" independent opening range")
		var terminal:=Story._station_for_instance(world,"chengdu-s7")
		terminal_id=str(terminal.id);terminal_before=terminal.duplicate(true)
		var saved:=SaveManager.save_world(world)
		var loaded:=SaveManager.load_file(str(saved.get("path","")))
		_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)),id+" save and reload")
		if bool(loaded.get("ok",false)):world=loaded.world
	if stages.back()==str(world.storyState.chapterId):
		var route:=WorldData.find_route(world,"historical_chengdu-line1")
		_check(route.stationOrder.size()==22,"infill followed by south extension yields continuous 22-stop Line 1")
		_check(Story.changed_service_continuity_error(world,[route]).is_empty(),"infill terminal does not force a reversal in later extension")
	app.queue_free();await process_frame
	for failure in failures:print("FAIL ",failure)
	print("CHENGDU_INFILL_EXTENSION_CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
