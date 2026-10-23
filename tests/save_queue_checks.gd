extends SceneTree
const Writer=preload("res://scripts/save_coordinator.gd")
const App=preload("res://scripts/main.gd")
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	if not value:push_error(message);failures+=1
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var writer:=Writer.new();root.add_child(writer)
	var world:=WorldData.new_world("shanghai","workshop")
	world.title="snapshot one"
	var one:=writer.request(world,1)
	world.title="snapshot two"
	var two:=writer.request(world,2)
	world.title="snapshot three"
	var three:=writer.request(world,3)
	world.title="unsaved modification"
	var first:Dictionary=await writer.wait_for(one)
	var second:Dictionary=await writer.wait_for(two)
	var third:Dictionary=await writer.wait_for(three)
	check(bool(first.ok) and int(first.changeSerial)==1,"active request lost its checkpoint")
	check(bool(second.ok) and int(second.changeSerial)==3 and int(third.changeSerial)==3,"queued requests did not coalesce to latest snapshot")
	var loaded:=SaveManager.load_file(SaveManager.save_path(str(world.gameId)))
	check(bool(loaded.ok) and str(loaded.world.title)=="snapshot three","writer read mutable world after capture")
	check(str(world.title)=="unsaved modification","writer mutated live session")
	var app:=App.new();root.add_child(app);await process_frame
	app._enter(world)
	app._mark_dirty()
	app._save()
	app.world.title="changed during write";app._mark_dirty()
	while app.saves_in_flight>0:await process_frame
	check(app.dirty,"completion incorrectly cleared newer unsaved changes")
	check(await app._save(),"latest UI checkpoint failed")
	check(not app.dirty,"latest checkpoint left clean session dirty")
	# Force the continue index replacement to fail after world writing.
	var index:=SaveManager.root_path().path_join("last_game.json")
	DirAccess.remove_absolute(index)
	DirAccess.make_dir_recursive_absolute(index)
	var other:=WorldData.new_world("beijing","workshop")
	var failed:Dictionary=await writer.wait_for(writer.request(other,4))
	check(not bool(failed.ok),"index failure was reported as success")
	check(str(app.world.gameId)==str(world.gameId),"failed save replaced current session")
	print("SAVE_QUEUE_FAILURES ",failures," metrics=",JSON.stringify(writer.last_metrics))
	app.queue_free();writer.queue_free();await process_frame
	quit(0 if failures==0 else 1)
