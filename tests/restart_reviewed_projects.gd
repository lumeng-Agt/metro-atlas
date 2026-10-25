extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var round:=-1
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--round="):round=int(str(arg).trim_prefix("--round="))
	if round<0:push_error("Explicit restart round required");quit(2);return
	var loaded:=SaveManager.load_last_game()
	if not bool(loaded.get("ok",false)):push_error("A copied actual replay checkpoint is required");quit(2);return
	var world:Dictionary=loaded.world
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.get(str(world.cityId),{})
	var errors:Array=OfficialNetworkAudit.cutoff_errors(world)
	for project in target.get("projects",[]):errors.append_array(OfficialNetworkAudit.project_errors(world,project))
	if not errors.is_empty():push_error("Actual reviewed project state differs: "+JSON.stringify(errors));quit(1);return
	var facts:Array=[]
	for key in ["stations","trackNodes","trackEdges","routes","stationComplexes","transferConnections","serviceRanges","storyState","storyPlan","history"]:facts.append(world.get(key))
	var signature:=JSON.stringify(facts).sha256_text()
	if round>0 and (int(world.get("reviewedRestartRound",-1))!=round-1 or str(world.get("reviewedRestartSignature",""))!=signature):push_error("Real project geometry/history changed across processes");quit(1);return
	world["reviewedRestartRound"]=round;world["reviewedRestartSignature"]=signature
	var saved:=SaveManager.save_world(world)
	if not bool(saved.get("ok",false)):push_error(str(saved.get("error","Save failed")));quit(1);return
	print("REVIEWED_RESTART_PASS round=",round," city=",world.cityId," knownProjects=",target.get("projects",[]).size()," geometryHistorySha256=",signature," completeDelivery=",bool(CampaignSystem.delivery_eligibility(str(world.cityId)).get("ok",false)))
	quit(0)
