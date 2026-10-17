extends SceneTree

## Run with the exported executable mounted as --main-pack. This verifies the
## shipped resource graph; it is not a replacement for mouse/keyboard testing.
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if not FileAccess.file_exists("res://project.binary") or not SaveManager.using_explicit_data_dir():push_error("Exported --main-pack and isolated --data-dir required");quit(2);return
	WorldData.load_assets()
	if WorldData.SAVE_VERSION!=20 or str(ProjectSettings.get_setting("application/config/version",""))!="0.20.1":push_error("Wrong exported version");quit(1);return
	ReferenceAlignment.load_data()
	if ReferenceAlignment._data.get("alignments",[]).size()!=81:push_error("Missing exported reference corridors");quit(1);return
	if WorldData.cities().size()!=5 or not CampaignSystem.validate_catalog(WorldData.cities()).is_empty():push_error("Missing exported city/story data");quit(1);return
	if not ResourceLoader.exists("res://fonts/NotoSansSC.ttf"):push_error("Missing exported font");quit(1);return
	var file:=FileAccess.open("res://data/basemap/manifest.json",FileAccess.READ)
	if file==null:push_error("Missing map manifest");quit(1);return
	var manifest:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	var chunks:=0
	for id in manifest.cities:
		var package:Dictionary=manifest.cities[id]
		for name in package.chunks:
			var path:="res://data/basemap/%s/%s" % [str(id),str(name)]
			if not FileAccess.file_exists(path):push_error("Missing map chunk: "+path);quit(1);return
			chunks+=1
	var app=load("res://scripts/main.gd").new();root.add_child(app);await process_frame
	app._new_game("shanghai",false);app._begin_chapter()
	var preview:Dictionary=app._assist_candidate()
	if not str(preview.get("issue","")).is_empty():push_error(str(preview));quit(1);return
	for key in ["stations","trackNodes","trackEdges"]:app.world[key]=preview.state[key]
	app._check();app._commit_chapter()
	if str(app.world.storyState.stage)!="outcome" or not app._save():push_error("Exported story/save flow failed");quit(1);return
	print("PASS exported resources: five cities, %d chunks, 81 corridors, font, story helpers, chapter confirmation and schema20 save" % chunks)
	app.queue_free();await process_frame;quit(0)
