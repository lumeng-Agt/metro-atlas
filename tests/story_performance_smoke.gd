extends SceneTree
const App=preload("res://scripts/main.gd")
var report:Dictionary={"kind":"native-renderer-smoke","version":"0.20.0","notFullAcceptance":true,"scenarios":[]}
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if not SaveManager.using_explicit_data_dir() or DisplayServer.get_name()=="headless":push_error("Native rendering and isolated --data-dir required");quit(2);return
	var seconds:=30.0;var repeats:=3
	var scenarios:Array=["overview","blocks","zoom","buildings"]
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--seconds="):seconds=maxf(1,float(str(arg).trim_prefix("--seconds=")))
		if str(arg).begins_with("--repeats="):repeats=maxi(1,int(str(arg).trim_prefix("--repeats=")))
		if str(arg).begins_with("--scenarios="):scenarios=Array(str(arg).trim_prefix("--scenarios=").split(","))
	if scenarios.is_empty() or scenarios.any(func(name):return not ["overview","blocks","zoom","buildings"].has(name)):push_error("Unknown performance scenario");quit(2);return
	root.size=Vector2i(1600,980)
	var app:=App.new();root.add_child(app);await process_frame
	var world:=WorldData.new_world("shanghai","workshop");WorldData._import_existing_network(world,WorldData.city("shanghai"));TrackNetwork.ensure_station_nodes(world)
	var history:=CommandHistory.new();history.attach(world)
	for i in range(200):history.execute("压力历史%d" % i,func(state:Dictionary):state.stations[0]["name"]="压力车站%d" % i,["stations"])
	app._enter(world);app.show_left=false;app.show_right=false;app._layout();app.auto_enabled=false
	report.merge({"date":Time.get_datetime_string_from_system(),"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":[1600,980],"stations":world.stations.size(),"routes":world.routes.size(),"history":world.history.undo.size(),"secondsPerScenario":seconds,"repeats":repeats})
	report["mapSourceSha256"]=FileAccess.get_sha256("res://scripts/map_view.gd")
	for name in scenarios:
		for run in range(repeats):
			var zoom:=12 if name=="overview" else (15 if name=="blocks" else 17)
			app.map_view.center_on([31.2304,121.4737],zoom)
			var ready_started:=Time.get_ticks_usec();var ready_deadline:=Time.get_ticks_msec()+20000
			while app.map_view._base_map_thread_busy and Time.get_ticks_msec()<ready_deadline:await process_frame
			var cold_ms:=(Time.get_ticks_usec()-ready_started)/1000.0
			var samples:Array[float]=[];var start:=Time.get_ticks_usec();var previous:=start
			var last_zoom:=0
			while (Time.get_ticks_usec()-start)/1000000.0<seconds:
				var t:=(Time.get_ticks_usec()-start)/1000000.0
				if name=="zoom":
					if int(t)!=last_zoom:last_zoom=int(t);app.map_view.center_on([31.2304,121.4737],15+int(t)%3)
				else:app.map_view.center_on([31.2304+sin(t*0.3)*0.001,121.4737+cos(t*0.3)*0.002],zoom)
				await process_frame
				var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
			var duration:=(Time.get_ticks_usec()-start)/1000000.0;samples.sort()
			var row:={"scenario":name,"run":run,"frames":samples.size(),"averageFps":samples.size()/duration,"p95Ms":samples[clampi(ceili(samples.size()*0.95)-1,0,samples.size()-1)],"maxFrameMs":samples[-1],"prepareMs":cold_ms,"engineStaticMiB":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}
			row["pressureGoalMet"]=float(row.averageFps)>=30 and float(row.p95Ms)<=33.3
			report.scenarios.append(row);print(JSON.stringify(row))
	var saving:=Time.get_ticks_usec();var result:=SaveManager.save_world(world,true);report["saveMs"]=(Time.get_ticks_usec()-saving)/1000.0;report["saveOk"]=bool(result.ok)
	SaveManager._write_atomic(SaveManager.root_path().path_join("performance.json"),JSON.stringify(report,"  "))
	var passed:=bool(result.ok) and float(report.saveMs)<=100.0
	for row in report.scenarios:
		if not bool(row.pressureGoalMet) or float(row.maxFrameMs)>100.0:passed=false
	report["measuredThresholdsPassed"]=passed
	SaveManager._write_atomic(SaveManager.root_path().path_join("performance.json"),JSON.stringify(report,"  "))
	print("Report: ",SaveManager.root_path().path_join("performance.json"));app.queue_free();await process_frame;quit(0 if passed else 1)
