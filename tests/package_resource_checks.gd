extends SceneTree

func _initialize() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	var allowed:=[".godot","assets","data","fonts","scenes","scripts"]
	for folder in DirAccess.get_directories_at("res://"):
		if not allowed.has(folder):push_error("Unexpected packed directory: "+folder);quit(1);return
	for name in DirAccess.get_files_at("res://"):
		if name.begins_with(".tmp") or name.ends_with(".log"):push_error("Temporary packed resource: "+name);quit(1);return
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/announcement_manifest.json"))
	if not manifest is Dictionary or manifest.get("clips",[]).is_empty():push_error("Packaged voice manifest missing");quit(1);return
	var count:=0
	for clip in manifest.clips:
		var audio:=ResourceLoader.load("res://"+str(clip.path),"AudioStream",ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
		if audio==null or audio.get_length()<0.35:push_error("Packaged voice cannot decode: "+str(clip.name));quit(1);return
		count+=1
	var bank:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/challenges.json"))
	if not bank is Dictionary or bank.get("days",{}).size()!=180:push_error("Packaged daily bank incomplete");quit(1);return
	print("PASS: packaged roots, 180 daily dates and %d decoded announcement names"%count)
	quit()
