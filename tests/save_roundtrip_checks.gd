extends SceneTree
## Loading a healthy save must not rewrite it. The load-time repair only fixes
## records a superseded build produced, so a save written by the current build
## has to come back byte-identical in every persisted collection.
##
## The save under test is produced here rather than borrowed from a replay, so
## the check runs on its own. A fresh game starts with no track, so it is given
## a small real network first — an empty world would round-trip trivially.

const DEFAULT_CITY = "chengdu"

func _initialize() -> void:call_deferred("_run")

func _roundtrip_city() -> String:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--roundtrip-city="):
			var city := text.trim_prefix("--roundtrip-city=").strip_edges()
			if not city.is_empty():return city
	return DEFAULT_CITY

func _seed(state: Dictionary, city_id: String) -> bool:
	var catalog := WorldData.city(city_id)
	var rails: Array = catalog.get("stations", [])
	if rails.size() < 3:return false
	var route := WorldData.add_route(state, "往返校验线", "#3b82f6")
	var picked: Array = []
	for index in range(3):
		var raw: Dictionary = rails[index]
		var station := {"id": "rt_%d" % index, "name": str(raw.get("name", "校验站%d" % index)),
			"latlng": raw.get("latlng", [0.0, 0.0]), "heading": 90.0, "lengthM": 118.788,
			"widthM": 20.0, "vehicleId": "B-6", "schematic": false, "existing": false,
			"planningPhaseId": str(state.get("currentPlanningPhaseId", "history_1")), "routeIds": [str(route.id)]}
		state["stations"].append(station)
		picked.append(station)
	# Edges point at station endpoint nodes, so the nodes have to exist first.
	TrackNetwork.ensure_station_nodes(state)
	for index in range(picked.size() - 1):
		var a: Dictionary = picked[index]
		var b: Dictionary = picked[index + 1]
		state["trackEdges"].append({"id": "rte_%d" % index,
			"aNodeId": TrackNetwork.station_node_id(a, "end"), "bNodeId": TrackNetwork.station_node_id(b, "start"),
			"routeIds": [str(route.id)], "geometry": "straight", "schematic": false})
	route["stationOrder"] = picked.map(func(s: Dictionary): return str(s.id))
	route["open"] = true
	state.storyState["completedChapterIds"] = ["roundtrip-fixture"]
	state.storyState["beatRead"] = {"roundtrip-beat": 1}
	state.storyState["chapterTaskProgress"] = {"roundtrip-task": {"confirmed": true, "count": 2}}
	return true

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var city := _roundtrip_city()
	var world := WorldData.new_world(city, "campaign")
	if not _seed(world, city):push_error("fixture seed failed");quit(2);return
	var problem := SaveManager.validate(world)
	if not problem.is_empty():push_error("seed invalid: " + problem);quit(2);return
	var created := SaveManager.save_world(world)
	if not bool(created.get("ok",false)):push_error("fixture save failed: "+str(created.get("error","")));quit(2);return
	var loaded:=SaveManager.load_last_game()
	if not bool(loaded.get("ok",false)):push_error("isolated save missing");quit(2);return
	var before:Dictionary=JSON.parse_string(JSON.stringify(loaded.world))
	var saved:Dictionary=SaveManager.save_world(loaded.world)
	if not bool(saved.get("ok",false)):push_error("save failed: "+str(saved.get("error","")));quit(2);return
	var again:=SaveManager.load_file(str(saved.path))
	if not bool(again.get("ok",false)):push_error("reload failed: "+str(again.get("error","")));quit(2);return
	var failures:=0
	if before.get("stations",[]).is_empty() or before.get("trackEdges",[]).is_empty():
		print("ROUNDTRIP_EMPTY fixture produced no network")
		failures+=1
	for key in ["stations","stationComplexes","transferConnections","trackNodes","trackEdges","routes","serviceRanges","history","storyState","storyPlan"]:
		if before.get(key)==again.world.get(key):continue
		failures+=1
		print("ROUNDTRIP_DIFF ",key)
	print("ROUNDTRIP ",str(before.get("cityId",""))," stations=",str(before.get("stations",[]).size())," edges=",str(before.get("trackEdges",[]).size())," failures=",failures)
	quit(0 if failures==0 else 1)
