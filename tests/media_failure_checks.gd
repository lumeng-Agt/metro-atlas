extends SceneTree

class FullDiskJob extends "res://scripts/media_export_job.gd":
	func _write_frame(_frame:Image,_path:String) -> Error:return ERR_FILE_CANT_WRITE

class LockedTargetJob extends "res://scripts/media_export_job.gd":
	func _replace_output(_source:String,_target:String) -> Error:return ERR_FILE_CANT_WRITE

var failures:Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not SaveManager.using_explicit_data_dir() or DisplayServer.get_name()=="headless":quit(2);return
	WorldData.load_assets();DirAccess.make_dir_recursive_absolute(SaveManager.root_path())
	var app=preload("res://scripts/main.gd").new();root.add_child(app);await process_frame
	var world:=WorldData.new_world("shanghai","story")
	var archive:={"cityId":"shanghai","cityName":"上海","initialWorld":world,"frames":[{"world":world,"date":"1993-05-28","title":"写入故障检查","planning":false,"source":"https://www.shmetro.com/"}]}
	var path:=SaveManager.root_path().path_join("retain-existing.webm")
	var original:=FileAccess.open(path,FileAccess.WRITE);original.store_string("previous valid target sentinel");original.close()
	var before:=FileAccess.get_sha256(path)
	for job in [FullDiskJob.new(),LockedTargetJob.new()]:
		app.add_child(job)
		var result:Dictionary=await job.export_video(archive,path,30,app.theme)
		if result.get("ok",true):failures.append("injected failure was reported as success")
		if FileAccess.get_sha256(path)!=before:failures.append("failed export altered the existing target")
		if DirAccess.dir_exists_absolute(job.temporary_dir):failures.append("registered temporary files were not cleaned")
		job.queue_free();await process_frame
	for failure in failures:push_error(failure)
	app.queue_free();await process_frame
	print("PASS: export full-disk and locked-target failures preserve original" if failures.is_empty() else "FAIL: media failures")
	quit(0 if failures.is_empty() else 1)
