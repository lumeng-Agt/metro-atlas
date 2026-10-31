extends SceneTree
const Flow=preload("res://tests/story_test_flow.gd")
const Playback=preload("res://scripts/history_playback.gd")
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,text:String) -> void:
	if not ok:failures.append(text);push_error(text)
func run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var app=preload("res://scripts/main.gd").new();root.add_child(app);await process_frame
	app._new_game("shanghai",false)
	check(await Flow.reach_first_construction(app),"normal prologue reaches first build")
	app._begin_chapter()
	var preview:Dictionary=app._assist_candidate()
	check(bool(app._commit_assisted_construction(preview,int(app.world.revision)).get("ok",false)),"normal construction commit")
	app._check();app._commit_chapter()
	while app.saves_in_flight>0:await process_frame
	check(app.world.storyState.stage=="outcome","first build historical node confirmed")
	var schematic:=preload("res://scripts/schematic_layout.gd").build(app.world,Vector2(1400,800))
	check(bool(schematic.get("ok",false)),"actual confirmed path creates schematic")
	check(schematic.get("positions",{}).size()==app.world.stations.size(),"schematic preserves all served physical bodies")
	check(schematic==preload("res://scripts/schematic_layout.gd").build(app.world,Vector2(1400,800)),"schematic deterministic")
	var before:=JSON.stringify(app.world)
	app._open_history_player();await process_frame
	var player=app.get_child(app.get_child_count()-1)
	while not player.prepared:await process_frame
	check(player.archive.frames.size()>0,"actual confirmed save reconstructs")
	var deadline:=Time.get_ticks_msec()+30000
	await process_frame
	while player.map._base_map_thread_busy or not player.map._base_map_pending_request.is_empty():
		if Time.get_ticks_msec()>deadline:check(false,"history basemap readiness timeout");break
		await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(SaveManager.root_path().path_join("history-player.png"))
	player.queue_free();await process_frame
	check(JSON.stringify(app.world)==before,"viewing actual history leaves mainline byte-equivalent")
	app._open_schematic();await process_frame
	var schematic_panel=app.get_child(app.get_child_count()-1)
	while not schematic_panel.prepared:await process_frame
	check(schematic_panel.result.get("ok",false),"threaded schematic panel uses actual confirmed paths")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(SaveManager.root_path().path_join("schematic.png"))
	schematic_panel.queue_free();await process_frame
	check(JSON.stringify(app.world)==before,"schematic view leaves mainline byte-equivalent")
	var memory:=preload("res://scripts/challenge_catalog.gd").memory_stations("shanghai","1993-05-28")
	check(memory.size()>0,"historical memory catalog contains real first-period stations")
	app._open_challenges();await process_frame
	var hub=app.get_child(app.get_child_count()-1)
	check(hub.stations.size()>0,"memory UI loads actual catalog")
	hub.mode="location";hub._select_scope()
	check(hub.questions.size()==5,"five reference-location questions are playable")
	for index in range(5):
		var question:Dictionary=hub.questions[index]
		hub.map.map_clicked.emit(question.latlng.duplicate(),"","","",0.0)
		for button in hub.body.get_children():
			if button is Button and button.text=="确认落点":button.pressed.emit();break
		check(hub.results.size()==index+1 and hub.results.back().referenceBasis=="game_reference" and hub.results.back().medal=="金牌","actual map answer scores against declared game reference")
		for button in hub.body.get_children():
			if button is Button and button.text=="下一题":button.pressed.emit();break
	check(hub.question_index==5,"five-answer flow reaches results")
	for city_index in range(WorldData.cities().size()):
		hub.cities.select(city_index);hub.mode="location";hub._periods()
		check(hub.questions.size()==5,"five-city practice pool exists: %s"%str(hub.cities.get_selected_metadata()))
		for question in hub.questions:
			check(question.get("referenceBasis","")=="game_reference" and SaveManager._coordinate_valid(question.latlng),"five-city positions explicitly bind game reference")
	hub.mode="memory";hub._select_scope()
	check(hub.map.highlight_path_points.is_empty(),"switching from location to memory clears the previous answer path")
	var bank:=preload("res://scripts/challenge_catalog.gd").load_bank()
	hub.daily_question=bank.locations[0].duplicate(true)
	hub.daily_question.merge({"date":"2026-10-30","version":bank.version},true)
	var daily_key:="test-first:%s"%str(bank.version)
	hub._clear();hub._daily_location(daily_key)
	hub.map.map_clicked.emit(hub.daily_question.latlng.duplicate(),"","","",0.0)
	for button in hub.body.get_children():
		if button is Button and button.text=="确认今日落点":button.pressed.emit();break
	check(hub.profile.daily[daily_key].medal=="金牌","daily map question awards reference-based medal")
	var first_result:=JSON.stringify(hub.profile.daily[daily_key])
	hub._clear();hub._daily_location(daily_key)
	hub.map.map_clicked.emit(Geo.offset(hub.daily_question.latlng,1000,0),"","","",0.0)
	for button in hub.body.get_children():
		if button is Button and button.text=="确认今日落点":button.pressed.emit();break
	check(JSON.stringify(hub.profile.daily[daily_key])==first_result,"repeated daily map submission preserves first result")
	hub.mode="memory";hub._select_scope()
	check(hub.map.highlight_path_points.is_empty(),"switching from daily position clears the previous answer path")
	deadline=Time.get_ticks_msec()+30000
	while hub.map._base_map_thread_busy or not hub.map._base_map_pending_request.is_empty():
		if Time.get_ticks_msec()>deadline:check(false,"challenge basemap readiness timeout");break
		await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(SaveManager.root_path().path_join("challenge-hub.png"))
	hub.queue_free();await process_frame
	check(JSON.stringify(app.world)==before,"challenge UI cannot modify current save")
	if OS.get_cmdline_user_args().has("--layout-matrix") and DisplayServer.get_name()!="headless":
		for window_size in [Vector2i(1366,768),Vector2i(1600,980),Vector2i(1920,1080)]:
			DisplayServer.window_set_size(window_size)
			for scale in [1.0,1.25,1.5,1.75]:
				app.theme=preload("res://scripts/ui_theme.gd").create_theme(app.face,app.strong_face,scale)
				app._open_history_player();await process_frame;await process_frame
				var matrix_player=app.get_child(app.get_child_count()-1)
				while not matrix_player.prepared:await process_frame
				check(_buttons_inside(matrix_player,Rect2(Vector2.ZERO,Vector2(window_size))),"history buttons inside %s/%s"%[window_size,scale])
				matrix_player.queue_free();await process_frame
				app._open_challenges();await process_frame;await process_frame
				var matrix_hub=app.get_child(app.get_child_count()-1)
				check(_buttons_inside(matrix_hub,Rect2(Vector2.ZERO,Vector2(window_size))),"challenge buttons inside %s/%s"%[window_size,scale])
				matrix_hub.queue_free();await process_frame
				app._open_schematic();await process_frame
				var matrix_schematic=app.get_child(app.get_child_count()-1)
				while not matrix_schematic.prepared:await process_frame
				check(_buttons_inside(matrix_schematic,Rect2(Vector2.ZERO,Vector2(window_size))),"schematic buttons inside %s/%s"%[window_size,scale])
				matrix_schematic.queue_free();await process_frame
	if OS.get_cmdline_user_args().has("--video-smoke") and DisplayServer.get_name()!="headless":
		var archive:=Playback.build(app.world)
		var job:=preload("res://scripts/media_export_job.gd").new();app.add_child(job)
		job.progress.connect(func(text:String):print(text))
		var result:Dictionary=await job.export_video(archive,SaveManager.root_path().path_join("history-smoke.webm"),30,app.theme)
		check(bool(result.get("ok",false)),"actual video encoded and validated")
		var before_hash:=FileAccess.get_sha256(SaveManager.root_path().path_join("history-smoke.webm"))
		job.queue_free()
		var cancelled_job:=preload("res://scripts/media_export_job.gd").new();app.add_child(cancelled_job)
		cancelled_job.progress.connect(func(text:String):
			if text.begins_with("正在编码"):cancelled_job.cancel())
		var cancelled:Dictionary=await cancelled_job.export_video(archive,SaveManager.root_path().path_join("history-smoke.webm"),30,app.theme)
		check(not cancelled.get("ok",true),"cancellation reports failure rather than success")
		check(FileAccess.get_sha256(SaveManager.root_path().path_join("history-smoke.webm"))==before_hash,"cancelled replacement preserves existing video")
		cancelled_job.queue_free()
	app.queue_free();await process_frame
	print("PASS: collection player-command flow" if failures.is_empty() else "FAIL: collection player-command flow")
	quit(0 if failures.is_empty() else 1)

func _buttons_inside(node:Node,bounds:Rect2) -> bool:
	if node is Button and node.is_visible_in_tree():
		if not bounds.grow(2).encloses(node.get_global_rect()):return false
	for child in node.get_children():
		if not _buttons_inside(child,bounds):return false
	return true
