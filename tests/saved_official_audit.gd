extends SceneTree

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var loaded:=SaveManager.load_last_game()
	if not bool(loaded.get("ok",false)):push_error("Isolated replay checkpoint missing");quit(2);return
	var world:Dictionary=loaded.world
	var targets:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OfficialNetworkAudit.TARGET_PATH))
	var results:Array=[];var failures:=0
	for project in targets.cities.get(str(world.cityId),{}).get("projects",[]):
		var errors:=OfficialNetworkAudit.project_errors(world,project)
		results.append({"project":project.id,"ok":errors.is_empty(),"errors":errors})
		if not errors.is_empty():failures+=1
		print("SAVED_OFFICIAL ",world.cityId," ",project.id," ","PASS" if errors.is_empty() else JSON.stringify(errors))
	var cutoff:Dictionary=targets.cities.get(str(world.cityId),{}).get("cutoffNetwork",{})
	if not cutoff.is_empty():
		var errors:=OfficialNetworkAudit.cutoff_errors(world)
		results.append({"project":"cutoff_network","ok":errors.is_empty(),"errors":errors})
		if not errors.is_empty():failures+=1
		print("SAVED_OFFICIAL ",world.cityId," cutoff_network ","PASS" if errors.is_empty() else JSON.stringify(errors.slice(0,12)))
	var report:Dictionary={"city":world.cityId,"gameId":world.gameId,"contentRevision":CampaignSystem.content_revision(),"checkedKnownProjects":results,"knownProjectFailures":failures,"completeDeliveryEligibility":CampaignSystem.delivery_eligibility(str(world.cityId)),"note":"Only independently authored project requirements are checked here. Empty or unreviewed city inventory is not complete delivery."}
	SaveManager._write_atomic(SaveManager.root_path().path_join("official-built-audit.json"),JSON.stringify(report,"  "))
	quit(0 if failures==0 else 1)
