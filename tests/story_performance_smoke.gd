extends SceneTree
const App=preload("res://scripts/main.gd")
const Story=preload("res://scripts/story_session.gd")
var report:Dictionary={"kind":"native-renderer-smoke","version":"0.25.0","notFullAcceptance":true,"scenarios":[]}
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if not SaveManager.using_explicit_data_dir() or DisplayServer.get_name()=="headless":push_error("Native rendering and isolated --data-dir required");quit(2);return
	var seconds:=30.0;var repeats:=3
	var source:="";var overlays:=false;var capture:=false
	var scenarios:Array=["overview","blocks","zoom","buildings"]
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--seconds="):seconds=maxf(1,float(str(arg).trim_prefix("--seconds=")))
		if str(arg).begins_with("--repeats="):repeats=maxi(1,int(str(arg).trim_prefix("--repeats=")))
		if str(arg).begins_with("--scenarios="):scenarios=Array(str(arg).trim_prefix("--scenarios=").split(","))
		if str(arg).begins_with("--source-checkpoint="):source=str(arg).trim_prefix("--source-checkpoint=").replace("\\","/")
		if str(arg)=="--overlays":overlays=true
		if str(arg)=="--capture":capture=true
	if scenarios.is_empty() or scenarios.any(func(name):return not ["overview","blocks","zoom","buildings"].has(name)):push_error("Unknown performance scenario");quit(2);return
	root.size=Vector2i(1600,980)
	var app:=App.new();root.add_child(app);await process_frame
	var world:Dictionary
	if source.is_empty():
		world=WorldData.new_world("shanghai","workshop");WorldData._import_existing_network(world,WorldData.city("shanghai"));TrackNetwork.ensure_station_nodes(world)
	else:
		if not source.begins_with(ProjectSettings.globalize_path("res://.tmp-remediation-").replace("\\","/")) or not FileAccess.file_exists(source):push_error("Isolated replay checkpoint required; no player-save fallback");quit(2);return
		var loaded:=SaveManager.load_file(source)
		if not bool(loaded.get("ok",false)):push_error("Replay checkpoint failed validation");quit(2);return
		world=loaded.world
		report["sourceCheckpointSha256"]=FileAccess.get_sha256(source)
	var history:=CommandHistory.new();history.attach(world)
	for i in range(200):history.execute("压力历史%d" % i,func(state:Dictionary):state.stations[0]["name"]="压力车站%d" % i,["stations"])
	app._enter(world);app.show_left=false;app.show_right=false;app._layout();app.auto_enabled=false
	app.map_view.render_profile_enabled=true
	if overlays:
		# Render stress only. The source checkpoint and authoritative story state
		# are untouched; this display clone supplies the real cutoff blueprint.
		var display_world:=world.duplicate(false)
		var cutoff:Dictionary=CampaignSystem.city_config(str(world.cityId)).chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
		display_world.storyState={"phase":"history","chapterId":cutoff.id,"stage":"build"};display_world.storyPlan={"planIndex":999}
		app.map_view.set_blueprint(Story.blueprint(display_world,true))
		app.map_view.assisted_preview=world
		var geography:=WorldData.city(str(world.cityId))
		var markers:Array=[];var seen:Dictionary={}
		for chapter in CampaignSystem.city_config(str(world.cityId)).chapters:
			for beat in chapter.get("story",{}).get("beats",[]):
				if beat.get("stationIds",[]).is_empty() or seen.has(str(beat.id)):continue
				var reference:=WorldData.find_station(geography,str(beat.stationIds[0]))
				if reference.is_empty():continue
				markers.append({"id":beat.id,"latlng":reference.latlng,"title":beat.title,"read":false});seen[str(beat.id)]=true
		app.map_view.story_markers=markers;app.map_view.requested_redraw()
		report.merge({"overlayFixture":true,"blueprintTargets":app.map_view.campaign_blueprint.get("stations",[]).size(),"storyMarkers":markers.size(),"previewStationCount":world.stations.size(),"overlayNote":"Real cutoff blueprint and sourced story markers with a full assisted-preview display fixture. This does not advance or certify history."})
	report.merge({"date":Time.get_datetime_string_from_system(),"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":[1600,980],"stations":world.stations.size(),"routes":world.routes.size(),"history":world.history.undo.size(),"secondsPerScenario":seconds,"repeats":repeats})
	report["mapSourceSha256"]=FileAccess.get_sha256("res://scripts/map_view.gd")
	report["presentationGeometrySha256"]=FileAccess.get_sha256("res://scripts/presentation_geometry.gd")
	report["harnessSha256"]=FileAccess.get_sha256("res://tests/story_performance_smoke.gd")
	report["engineVersion"]=Engine.get_version_info().get("string","")
	report["contentRevision"]=CampaignSystem.content_revision()
	for name in scenarios:
		for run in range(repeats):
			var zoom:=12 if name=="overview" else (15 if name=="blocks" else 17)
			app.map_view.center_on([31.2304,121.4737],zoom)
			var ready_started:=Time.get_ticks_usec();var ready_deadline:=Time.get_ticks_msec()+20000
			await process_frame
			var first_frame_ms:=(Time.get_ticks_usec()-ready_started)/1000.0
			while (app.map_view._base_map_thread_busy or not app.map_view._base_map_pending_request.is_empty()) and Time.get_ticks_msec()<ready_deadline:await process_frame
			var cold_ms:=(Time.get_ticks_usec()-ready_started)/1000.0
			var map_ready:bool=not app.map_view._base_map_thread_busy and app.map_view._base_map_pending_request.is_empty() and not app.map_view.base_map_features.is_empty()
			if capture and run==0:
				# Read back before the measured interval, so PNG encoding and GPU
				# synchronization do not pollute frame timings.
				await RenderingServer.frame_post_draw
				if DirAccess.make_dir_recursive_absolute(SaveManager.root_path())!=OK:push_error("Cannot create isolated diagnostic directory");quit(2);return
				var capture_error:=root.get_texture().get_image().save_png(SaveManager.root_path().path_join("render-"+str(name)+".png"))
				if capture_error!=OK:push_error("Failed to capture renderer diagnostic");quit(2);return
			app.map_view.render_phase_metrics.clear()
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
			row.merge({"firstFrameMs":first_frame_ms,"mapReady":map_ready})
			row["drawPhases"]=app.map_view.render_phase_metrics.duplicate(true)
			row["pressureGoalMet"]=float(row.averageFps)>=30 and float(row.p95Ms)<=33.3
			report.scenarios.append(row);print(JSON.stringify(row))
	var saving:=Time.get_ticks_usec()
	var ticket:int=app.save_writer.request(world,1)
	var request_ms:=(Time.get_ticks_usec()-saving)/1000.0
	var result:Dictionary=await app.save_writer.wait_for(ticket)
	report["saveTotalMs"]=(Time.get_ticks_usec()-saving)/1000.0
	report["saveMainThreadRequestMs"]=request_ms
	report["saveSnapshotMs"]=float(result.get("snapshotMs",0))
	report["saveWorkerMs"]=float(result.get("workerMs",0))
	report["saveOk"]=bool(result.ok)
	SaveManager._write_atomic(SaveManager.root_path().path_join("performance.json"),JSON.stringify(report,"  "))
	var passed:=bool(result.ok) and request_ms<=100.0
	for row in report.scenarios:
		if not bool(row.pressureGoalMet) or not bool(row.mapReady) or float(row.maxFrameMs)>100.0:passed=false
	report["measuredThresholdsPassed"]=passed
	SaveManager._write_atomic(SaveManager.root_path().path_join("performance.json"),JSON.stringify(report,"  "))
	print("Report: ",SaveManager.root_path().path_join("performance.json"));app.queue_free();await process_frame;quit(0 if passed else 1)
