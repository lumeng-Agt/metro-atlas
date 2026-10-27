extends SceneTree
## Loading a healthy save must not rewrite it. The load-time repair only fixes
## records a superseded build produced, so a save written by the current build
## has to come back byte-identical in every persisted collection.

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var loaded:=SaveManager.load_last_game()
	if not bool(loaded.get("ok",false)):push_error("isolated save missing");quit(2);return
	var before:Dictionary=JSON.parse_string(JSON.stringify(loaded.world))
	var saved:Dictionary=SaveManager.save_world(loaded.world)
	if not bool(saved.get("ok",false)):push_error("save failed: "+str(saved.get("error","")));quit(2);return
	var again:=SaveManager.load_file(str(saved.path))
	if not bool(again.get("ok",false)):push_error("reload failed: "+str(again.get("error","")));quit(2);return
	var failures:=0
	for key in ["stations","stationComplexes","transferConnections","trackNodes","trackEdges","routes","serviceRanges","history","storyState","storyPlan"]:
		if before.get(key)==again.world.get(key):continue
		failures+=1
		print("ROUNDTRIP_DIFF ",key)
	print("ROUNDTRIP ",str(before.get("cityId",""))," stations=",str(before.get("stations",[]).size())," edges=",str(before.get("trackEdges",[]).size())," failures=",failures)
	quit(0 if failures==0 else 1)
