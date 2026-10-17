extends SceneTree
const App=preload("res://scripts/main.gd")
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if DisplayServer.get_name()=="headless" or not SaveManager.using_explicit_data_dir():quit(2);return
	root.size=Vector2i(1600,980)
	var app:=App.new();root.add_child(app);await process_frame
	var world:=WorldData.new_world("shanghai","workshop")
	WorldData._import_existing_network(world,WorldData.city("shanghai"));TrackNetwork.ensure_station_nodes(world)
	world.mode="campaign";world.storyState.chapterId="sh-line1-south-1996";world.storyState.chapterIndex=2;world.storyState.stage="build";StoryTutorial.skip(world)
	app._enter(world);app.auto_enabled=false;app.show_left=false;app.show_right=false;app._layout()
	app.map_view.center_on([31.14,121.41],17)
	for _frame in range(5):await process_frame
	var deadline:=Time.get_ticks_msec()+20000
	while app.map_view._base_map_thread_busy and Time.get_ticks_msec()<deadline:await process_frame
	app._show_beat(StoryBeats.entries(world)[0]);await process_frame
	var samples:Array[float]=[];var start:=Time.get_ticks_usec();var prior:=start
	while Time.get_ticks_usec()-start<30000000:
		var t:=(Time.get_ticks_usec()-start)/1000000.0
		app.map_view.center_on([31.14+sin(t*0.2)*0.001,121.41+cos(t*0.2)*0.001],17)
		await process_frame
		var now:=Time.get_ticks_usec();samples.append((now-prior)/1000.0);prior=now
	var duration:=(Time.get_ticks_usec()-start)/1000000.0;samples.sort()
	var result:={"version":"0.20.0","kind":"native-story-overlay-30s","fixture":"验收组合场景：最大既有路网＋1996蓝图＋地点故事；非正式通关存档","date":Time.get_datetime_string_from_system(),"seconds":duration,"averageFps":samples.size()/duration,"p95Ms":samples[ceili(samples.size()*0.95)-1],"maxFrameMs":samples[-1],"blueprintStations":app.map_view.campaign_blueprint.stations.size(),"storyMarkers":app.map_view.story_markers.size(),"storyPanel":is_instance_valid(app.beat_panel)}
	result["pressureGoalMet"]=float(result.averageFps)>=30 and float(result.p95Ms)<=33.3
	SaveManager._write_atomic(SaveManager.root_path().path_join("overlay-performance.json"),JSON.stringify(result,"  "));print(JSON.stringify(result))
	app.queue_free();await process_frame;quit(0 if bool(result.pressureGoalMet) else 1)
