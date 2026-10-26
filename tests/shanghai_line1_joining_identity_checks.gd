extends SceneTree

const App=preload("res://scripts/main.gd")
const Story=preload("res://scripts/story_session.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("_run")

func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	var app:=App.new();root.add_child(app);await process_frame
	app._new_game("shanghai",false)
	while app.saves_in_flight>0:await process_frame
	var prior:Dictionary={};var completed:=false
	for step in range(16):
		var chapter:Dictionary=Story.chapter(app.world)
		if chapter.is_empty():break
		app._begin_chapter()
		while not Story.plan_is_final(app.world):
			var adopted:Dictionary=app._commit_plan_revision(int(app.world.storyPlan.get("planIndex",0))+1,int(app.world.revision))
			_check(bool(adopted.get("ok",false)),"normal historical plan adoption succeeds")
			if not bool(adopted.get("ok",false)):app.queue_free();await process_frame;quit(1);return
		if not Story.groups(app.world,true).is_empty():
			var candidate:Dictionary=app._assist_candidate()
			_check(str(candidate.get("issue","")).is_empty(),"actual first-four-chapter geometry can be previewed")
			var built:Dictionary=app._commit_assisted_construction(candidate,int(app.world.revision))
			_check(bool(built.get("ok",false)),"actual first-four-chapter construction commits formally")
			if not bool(built.get("ok",false)):app.queue_free();await process_frame;quit(1);return
		if bool(chapter.get("requiresLineReorganization",false)):
			var identity_preview:Dictionary=Story.scope_correction_preview(app.world,"")
			_check(bool(identity_preview.get("ok",false)) and identity_preview.get("changes",[]).size()==3,"joining preview lists all three explicit identity corrections")
			_check(str(Story.bound_station(app.world,"shanghai-s128","shanghai-s128").get("stationLineId"))=="shanghai-line1-south-extension","merely previewing the identity change leaves the formal body unchanged")
			var joined:Dictionary=app._commit_line_reorganization(int(app.world.revision))
			_check(bool(joined.get("ok",false)),"1997 joining changes real route relationships")
			_check(not app.history.undo().is_empty(),"joining preview submission can be undone before milestone confirmation")
			_check(str(Story.bound_station(app.world,"shanghai-s128","shanghai-s128").get("stationLineId"))=="shanghai-line1-south-extension","undo restores the physical body's pre-joining identity")
			_check(not app.history.redo().is_empty(),"joining submission redoes before confirmation")
			_check(str(Story.bound_station(app.world,"shanghai-s128","shanghai-s128").get("stationLineId"))=="shanghai-line1","redo restores the joined physical identity")
		var groups:Array=Story.groups(app.world,true)
		for index in range(groups.size()):
			var task:Dictionary=Story.confirm_task(app.world,Story.task_id(chapter,groups[index],index),int(app.world.revision))
			_check(bool(task.get("ok",false)),"normal task confirmation applies its scoped identity changes")
		if str(chapter.id)=="sh-line1-south-1996":
			for instance in ["shanghai-s126","shanghai-s127","shanghai-s128"]:
				var station:Dictionary=Story.bound_station(app.world,instance,instance)
				# The next normal chapter is entered after a JSON disk round trip.
				# Compare its persisted precision, not unsaved binary float digits.
				prior[instance]=JSON.parse_string(JSON.stringify(station))
				_check(str(station.get("stationLineId",""))=="shanghai-line1-south-extension","separate 1996 service keeps its original temporary line identity")
		if str(chapter.id)=="sh-line1-1997":
			_check(prior.size()==3,"all three actual southern bodies came from the preceding normal chapter")
			for instance in prior:
				var station:Dictionary=Story.bound_station(app.world,instance,instance)
				_check(str(station.get("stationLineId",""))=="shanghai-line1","joining gives the same physical body its permanent Line 1 identity")
				for key in ["id","stationInstanceId","latlng","heading","depthM","lengthM"]:
					_check(station.get(key)==prior[instance].get(key),"joining preserves existing physical "+key)
			_check(app.history.undo().is_empty(),"ordinary undo cannot cross an explicitly confirmed historical task")
			completed=true
		var evaluation:Dictionary=Story.evaluate(app.world)
		var committed:Dictionary=Story.commit_chapter(app.world,int(app.world.revision),evaluation)
		_check(bool(committed.get("ok",false)),"actual early milestone passes construction and joining conditions")
		if not bool(committed.get("ok",false)):app.queue_free();await process_frame;quit(1);return
		var saved:Dictionary=SaveManager.save_world(app.world)
		_check(bool(saved.get("ok",false)),"actual milestone saves")
		var loaded:Dictionary=SaveManager.load_file(str(saved.get("path","")))
		_check(bool(loaded.get("ok",false)),"actual milestone reloads")
		if not bool(loaded.get("ok",false)):app.queue_free();await process_frame;quit(1);return
		app._enter(loaded.world)
		if completed:
			_check(str(Story.bound_station(app.world,"shanghai-s128","shanghai-s128").get("stationLineId"))=="shanghai-line1","permanent joining identity survives disk reload")
			break
		Story.next_chapter(app.world)
	_check(completed,"normal new-game sequence reaches 1997 without setting chapter or completion flags")
	app.queue_free();await process_frame
	print("SHANGHAI_LINE1_JOINING_IDENTITY ",checks," FAILURES ",failures)
	quit(0 if failures==0 else 1)
