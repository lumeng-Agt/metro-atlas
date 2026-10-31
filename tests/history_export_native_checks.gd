extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not SaveManager.using_explicit_data_dir() or DisplayServer.get_name()=="headless":quit(2);return
	WorldData.load_assets()
	DirAccess.make_dir_recursive_absolute(SaveManager.root_path())
	var source:="D:/gam1/testdata/gameplay-verify/run-20261029-202922/shanghai-fresh/games/shanghai_1793276976_6aee24c37732/current.json"
	var loaded:=SaveManager.load_file(source)
	if not loaded.get("ok",false):push_error("Full-city isolated fixture unavailable");quit(1);return
	var app=preload("res://scripts/main.gd").new();root.add_child(app);await process_frame
	var before:=FileAccess.get_sha256(source)
	var archive:=preload("res://scripts/history_playback.gd").build(loaded.world)
	print("EXPORT_ARCHIVE frames=",archive.frames.size()," warning=",archive.warning)
	if archive.frames.size()<20:push_error("Full history was not recovered");quit(1);return
	var history_frames:Array=[]
	for index in range(archive.frames.size()):
		var frame:Dictionary=archive.frames[index].duplicate(false)
		frame.beforeWorld=archive.frames[index-1].world if index>0 else archive.initialWorld
		if not frame.planning:history_frames.append(frame)
	archive.frames=history_frames
	for duration in [60,120]:
		var job:=preload("res://scripts/media_export_job.gd").new();app.add_child(job)
		job.progress.connect(func(text:String):print("EXPORT ",duration," ",text))
		var result:Dictionary=await job.export_video(archive,SaveManager.root_path().path_join("shanghai-history-%d.webm"%duration),float(duration),app.theme)
		if not result.get("ok",false):push_error("Export failed: "+str(result));quit(1);return
		job.queue_free()
	if FileAccess.get_sha256(source)!=before:push_error("Exporter modified the source checkpoint");quit(1);return
	app.queue_free();await process_frame;print("PASS: full-city 60/120 second native exports");quit()
