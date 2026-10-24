extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var round:=0
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--round="):round=int(str(arg).trim_prefix("--round="))
	var world:Dictionary
	if round==0:
		world=WorldData.new_world("shanghai","campaign");world.storyState.stage="build"
		# The current first nodes introduce historical plans without stations.
		# Advance those through actual event confirmation; a restart fixture
		# must not index empty targets or pretend these events contain geometry.
		var introductions:=0
		while bool(StorySession.chapter(world).get("eventOnly",false)):
			var confirmed:=StorySession.commit_chapter(world,int(world.revision),StorySession.evaluate(world))
			if not bool(confirmed.get("ok",false)) or introductions>100:push_error("Unable to confirm story introduction");quit(1);return
			StorySession.next_chapter(world);world.storyState.stage="build";introductions+=1
		var refs:Array=StorySession.targets(world)
		if refs.size()<2:push_error("Restart fixture requires two real construction targets");quit(1);return
		var a:=WorldData.create_station(world,refs[0].latlng,90)
		var b:=WorldData.create_station(world,refs[1].latlng,90)
		a.historicalId=refs[0].id;b.historicalId=refs[1].id
		world.trackEdges.append({"id":"restart_edge","aNodeId":TrackNetwork.station_node_id(a,"end"),"bNodeId":TrackNetwork.station_node_id(b,"start"),"geometry":"straight","routeIds":[],"depthM":-15})
		world.routes.append({"id":"restart_line","name":"续玩核对线路","stationOrder":[a.id,b.id],"open":true,"directions":[{"id":"forward","stationIds":[a.id,b.id],"edgePathsBySegment":[[{"id":"restart_edge","forward":true}]]}]})
	else:
		var result:=SaveManager.load_last_game()
		if not bool(result.get("ok",false)):push_error(str(result));quit(1);return
		world=result.world
		if int(world.get("testRound",-1))!=round-1 or world.stations.size()!=2 or world.routes.size()!=1 or world.trackEdges.size()!=1 or world.history.undo.size()!=round or str(world.storyState.stage)!="build" or world.has("simulation"):
			push_error("Cross-process story state mismatch");quit(1);return
	var history:=CommandHistory.new();history.attach(world)
	history.execute("保存前改名",func(state:Dictionary):state.stations[0].name="续玩第%d轮" % round,["stations"])
	world["testRound"]=round
	var save:=SaveManager.save_world(world,true)
	if not bool(save.ok):push_error(str(save));quit(1);return
	print("PASS independent process round %d: two stations, route, history and story restored; no simulation" % round)
	quit(0)
