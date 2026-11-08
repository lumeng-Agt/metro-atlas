extends SceneTree

const Story = preload("res://scripts/story_session.gd")
const App = preload("res://scripts/main.gd")
const ALLOWED_OPERATIONS := ["first_build", "extension", "phased_opening", "interchange", "reorganization", "plan_revision", "network_opening", "milestone_network_build", "network_reconciliation", "historical_record", "dated_station_segment", "rename", "infill", "infill_station"]

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		push_error("Isolated --data-dir is required."); quit(2); return
	WorldData.load_assets()
	for city in WorldData.all_cities():
		var config := Story.config({"cityId": str(city.id)})
		for chapter in config.get("chapters", []):
			var pedestrian_action:bool=str(chapter.get("operationType",""))=="transfer_connection" and chapter.get("lineGroups",[]).is_empty() and not chapter.get("requiredTransfers",[]).is_empty() and not bool(chapter.get("eventOnly",false))
			_check(ALLOWED_OPERATIONS.has(str(chapter.get("operationType", ""))) or pedestrian_action, "%s has a gameplay operation type" % str(chapter.get("id", "")))
			_check(not str(chapter.get("operationGuide", "")).is_empty(), "%s has a construction instruction" % str(chapter.get("id", "")))

	var app = App.new(); root.add_child(app); await process_frame
	app._new_game("shanghai", false); await _reach_first_construction(app); app._begin_chapter()
	var targets: Array = Story.targets(app.world, true)
	for target in targets.slice(0, 3):
		var station: Dictionary = {"id": "batch_%s" % str(target.id), "name": str(target.name), "historicalId": str(target.id), "latlng": target.latlng.duplicate(), "heading": float(target.get("referenceHeading", 90.0)) if float(target.get("referenceHeading", 90.0)) >= 0 else 90.0, "lengthM": 118.788, "widthM": 20.0, "depthM": -15.0, "vehicleId": "B-6", "existing": false, "routeIds": []}
		app._apply_profile(station, Story.profile(app.world, str(target.id)))
		app.world.stations.append(station)
	TrackNetwork.ensure_station_nodes(app.world); app._refresh()
	var preview_started:=Time.get_ticks_usec()
	for _iteration in range(10):
		app._begin_batch_tracks()
		app._batch_select_target(str(targets[0].id)); app._batch_select_target(str(targets[1].id)); app._batch_select_target(str(targets[2].id))
	var preview_average_ms:=(Time.get_ticks_usec()-preview_started)/10000.0
	_check(app.batch_track_segments.size()==2,"multi-section preview fixture has two sequential sections")
	app._remove_last_batch_segment()
	_check(app.batch_track_targets.size()==2 and app.batch_track_segments.size()==1,"last preview section can be removed without touching the world")
	app._batch_select_target(str(targets[2].id))
	_check_batch(app)
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,980);app._right();app.show_left=false;app.show_right=true;app._layout()
		var city_center:Array=WorldData.city("shanghai").get("center",[31.23,121.47]);var focus: Array=[(float(targets[0].latlng[0])+float(targets[2].latlng[0]))*0.5,(float(targets[0].latlng[1])+float(targets[2].latlng[1]))*0.5]
		app.map_view.center_on(focus,14)
		var ready_deadline:=Time.get_ticks_msec()+25000
		while (app.map_view._base_map_thread_busy or not app.map_view._base_map_pending_request.is_empty()) and Time.get_ticks_msec()<ready_deadline:await process_frame
		for _frame in range(8):await process_frame
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png("res://docs/ui-0.20.2-track-batch.png")==OK,"batched track preview screenshot written")
	var edges_before: int = app.world.trackEdges.size()
	if not app.batch_track_segments.is_empty(): app.batch_track_segments[0].issue = "测试冲突"
	app._commit_batch_tracks()
	_check(app.world.trackEdges.size() == edges_before, "invalid batched segment commits no partial track")
	if not app.batch_track_segments.is_empty(): app.batch_track_segments[0].issue = ""
	app._commit_batch_tracks()
	_check(app.world.trackEdges.size() > edges_before, "valid multi-section preview commits tracks")
	_check(app.history.undo_label().begins_with("连续复现"), "the whole batch is one undo command")
	app.history.undo(); _check(app.world.trackEdges.size() == edges_before, "one undo removes the complete batch")
	app.history.redo(); _check(app.world.trackEdges.size() > edges_before, "one redo restores the complete batch")
	app.queue_free(); await process_frame

	var result_app = App.new(); root.add_child(result_app); await process_frame
	result_app._new_game("shanghai", false); await _reach_first_construction(result_app); result_app._begin_chapter()
	var candidate: Dictionary = result_app._assist_candidate()
	_check(candidate.has("state"), "chapter completion fixture is available")
	if candidate.has("state"):
		var applied:Dictionary=result_app._commit_assisted_construction(candidate,int(result_app.world.revision))
		_check(bool(applied.get("ok",false)),"completion fixture uses formal assisted commit")
		var evaluation: Dictionary = Story.evaluate(result_app.world)
		_check(bool(evaluation.get("complete", false)), "Shanghai first chapter fixture passes its real checks")
		var committed := Story.commit_chapter(result_app.world, int(result_app.world.revision))
		_check(bool(committed.get("ok", false)), "chapter confirmation records a milestone")
		var changes: Dictionary = Story.chapter_changes(result_app.world)
		_check(int(changes.get("addedStations", []).size()) == 5, "chapter summary reports stations added in the milestone diff")
		_check(int(changes.get("addedTrackSections", 0)) > 0 and float(changes.get("addedLengthM", 0.0)) > 0, "chapter summary reports physical track length")
		_check(not changes.get("focusPairs", []).is_empty() and bool(changes.focusPairs[0].get("connected", false)), "chapter focus pair uses the confirmed route graph")
		var baseline: Dictionary = Story.chapter_baseline_world(result_app.world)
		_check(baseline.has("stations") and baseline.get("stations", []) is Array and baseline.get("stations", []).is_empty(), "before-chapter map state can be reconstructed from the milestone diff (chapter=%s, commit=%s)" % [str(Story.chapter(result_app.world).get("id", "")), JSON.stringify(committed)])
		var changes_started:=Time.get_ticks_usec()
		for _iteration in range(100):Story.chapter_changes(result_app.world)
		var changes_average_ms:=(Time.get_ticks_usec()-changes_started)/100000.0
		var baseline_started:=Time.get_ticks_usec()
		for _iteration in range(20):Story.chapter_baseline_world(result_app.world)
		var baseline_average_ms:=(Time.get_ticks_usec()-baseline_started)/20000.0
		var microbench:Dictionary={"version":"0.20.2","date":Time.get_datetime_string_from_system(),"kind":"chapter-preview-microbenchmark","execution":"headless" if DisplayServer.get_name()=="headless" else "native-rendering","iterations":{"two-section_preview":10,"chapter_changes":100,"baseline_reconstruction":20},"averageMs":{"two-section_preview":preview_average_ms,"chapter_changes":changes_average_ms,"baseline_reconstruction":baseline_average_ms},"fixture":{"city":"Shanghai","stations":result_app.world.stations.size(),"trackEdges":TrackNetwork.all_physical_edges(result_app.world).size(),"routes":result_app.world.routes.size()},"scope":"Method timing only; not per-frame renderer time, export mouse test, or maximum-network performance."}
		microbench["version"]=CampaignSystem.content_version();microbench["contentRevision"]=CampaignSystem.content_revision()
		microbench["sourceSha256"]={"storySession":FileAccess.get_sha256("res://scripts/story_session.gd"),"campaignSystem":FileAccess.get_sha256("res://scripts/campaign_system.gd"),"storyApp":FileAccess.get_sha256("res://scripts/story_app.gd")}
		SaveManager._write_atomic(SaveManager.root_path().path_join("chapter-microbench.json"),JSON.stringify(microbench,"  "))
		print(JSON.stringify(microbench))
		if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name()!="headless":
			root.size=Vector2i(1600,980);result_app._refresh();result_app.show_left=true;result_app.show_right=false;result_app._layout();result_app.map_view.center_on(WorldData.city("shanghai").get("center",[31.23,121.47]),13)
			var ready_deadline:=Time.get_ticks_msec()+25000
			while (result_app.map_view._base_map_thread_busy or not result_app.map_view._base_map_pending_request.is_empty()) and Time.get_ticks_msec()<ready_deadline:await process_frame
			result_app._mark_dirty();await result_app._save()
			for _frame in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var screenshot:=root.get_texture().get_image()
			_check(screenshot.save_png("res://docs/ui-0.20.2-chapter-outcome.png")==OK,"chapter outcome UI screenshot written")
	result_app.queue_free(); await process_frame
	print("0.20.2 story polish: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_batch(app: Control) -> void:
	_check(app.batch_track_targets.size() == 3, "batch tool accepts consecutive historical target stations")
	_check(app.batch_track_segments.size() == 2, "batch tool previews each adjacent section")
	_check(app.batch_track_segments.all(func(segment: Dictionary): return str(segment.get("issue", "")).is_empty()), "batch preview is valid before commit")
	_check(app.map_view.draft_track_segments.size() == 2, "map displays all pending section geometries")

func _reach_first_construction(app:Control) -> void:
	while app.saves_in_flight>0:await process_frame
	var count:=0
	while bool(Story.chapter(app.world).get("eventOnly",false)) and count<20:
		app._begin_chapter()
		var confirmed:Dictionary=Story.commit_chapter(app.world,int(app.world.revision))
		_check(bool(confirmed.get("ok",false)),"introductory event confirms through normal story command")
		if not bool(confirmed.get("ok",false)):return
		Story.next_chapter(app.world);count+=1
	app._enter(app.world)
