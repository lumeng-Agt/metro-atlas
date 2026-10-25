extends SceneTree
const Writer=preload("res://scripts/save_coordinator.gd")
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	var source:=""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--source-checkpoint="):source=str(arg).trim_prefix("--source-checkpoint=").replace("\\","/")
	# This diagnostic reads only registered isolated replay output, never a
	# player's active save. Writes stay in its separate explicit data directory.
	var prefix:=ProjectSettings.globalize_path("res://.tmp-remediation-").replace("\\","/")
	if not source.begins_with(prefix) or not FileAccess.file_exists(source):push_error("Isolated replay checkpoint required");quit(2);return
	WorldData.load_assets()
	var loaded:=SaveManager.load_file(source)
	if not bool(loaded.get("ok",false)):push_error("Replay checkpoint failed validation");quit(2);return
	var world:Dictionary=loaded.world
	# Exercise the actual retained network with the full history allowance.
	# These explicit naming commands affect only the isolated in-memory copy;
	# no source checkpoint or real player's world is rewritten.
	var history:=CommandHistory.new();history.attach(world)
	for index in range(200):history.execute("性能检查命名",func(state:Dictionary):state.stations[0].name="性能检查%d"%index,["stations"])
	var signature:=JSON.stringify(world).sha256_text()
	var writer:=Writer.new();root.add_child(writer)
	var report:Dictionary={"kind":"actual-replay-save-diagnostic","date":Time.get_datetime_string_from_system(),"sourceSha256":FileAccess.get_sha256(source),"contentRevision":CampaignSystem.content_revision(),"city":world.cityId,"stations":world.stations.size(),"edges":world.trackEdges.size(),"milestones":world.get("storyState",{}).get("milestones",[]).size(),"undoSteps":world.get("history",{}).get("undo",[]).size(),"saveCoordinatorSha256":FileAccess.get_sha256("res://scripts/save_coordinator.gd"),"saveManagerSha256":FileAccess.get_sha256("res://scripts/save_manager.gd"),"concurrencyNote":"Other formal city replays may be running. These are diagnostic request/worker times, not final EXE frame-rate or isolated performance acceptance.","samples":[]}
	var passed:=true
	for run in range(3):
		var started:=Time.get_ticks_usec()
		var ticket:=writer.request(world,run+1)
		var request_ms:=(Time.get_ticks_usec()-started)/1000.0
		var result:Dictionary=await writer.wait_for(ticket)
		var row:Dictionary={"run":run,"ok":bool(result.get("ok",false)),"mainRequestMs":request_ms,"snapshotMs":float(result.get("snapshotMs",0)),"workerMs":float(result.get("workerMs",0)),"totalMs":(Time.get_ticks_usec()-started)/1000.0}
		report.samples.append(row);print("ACTUAL_SAVE_DIAGNOSTIC ",JSON.stringify(row))
		if not bool(row.ok) or request_ms>100:passed=false
	if JSON.stringify(world).sha256_text()!=signature:passed=false;report["liveWorldChanged"]=true
	report["requestThresholdPassed"]=passed
	var output:=SaveManager._write_atomic(SaveManager.root_path().path_join("actual-save-performance.json"),JSON.stringify(report,"  "))
	if not bool(output.get("ok",false)):passed=false;push_error("Diagnostic report could not be saved")
	writer.queue_free();await process_frame
	quit(0 if passed else 1)
