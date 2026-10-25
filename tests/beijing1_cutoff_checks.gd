extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var config:=CampaignSystem.city_config("beijing")
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var plan:Dictionary=config.futurePlans.filter(func(p:Dictionary):return str(p.id)=="bj-line1-branch-build")[0]
	# Isolated actual-line/branch command fixture, not city chronology proof.
	var prelude:=cutoff.duplicate(true);prelude.id="fixture-beijing1-current-and14";prelude.requiredTransfers=[];prelude.scopeCorrections=[]
	prelude.lineGroups=prelude.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId) in ["beijing-lineearly0","beijing-line14-14"])
	CampaignSystem._catalog.cities.beijing.chapters.append(prelude)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var candidate:Dictionary=app._assist_candidate()
	_check(str(candidate.get("issue","")).is_empty(),"current real Line1/14 geometry previews: "+str(candidate.get("issue","")))
	var result:Dictionary=app._commit_assisted_construction(candidate,int(world.revision))
	_check(bool(result.get("ok",false)),"current scope commits through formal command: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):await _finish(app);return
	for proposal in Story.evaluate(world).get("serviceTransitions",[]):
		result=app._commit_service_transition(proposal,int(world.revision))
		_check(bool(result.get("ok",false)),"explicit current open scope replaces old built-only status: "+str(result.get("error","")))
	for group in prelude.lineGroups:
		result=Story.confirm_task(world,str(group.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"current route confirms: "+str(result.get("error","")))
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing.cutoffNetwork.duplicate(true)
	target.groups=target.groups.filter(func(g:Dictionary):return str(g.get("historicalLineId",g.id))=="beijing-lineearly0");target.transfers=[]
	_check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"35-stop official current service has valid physical paths")
	_check(bool(WorldData.find_route(world,"historical_beijing-line14-14").get("open",false)),"a Line1 status action does not close the unrelated Line14 service")
	var main:=WorldData.find_route(world,"historical_beijing-lineearly0").duplicate(true)
	_check(main.stationOrder.size()==35,"cutoff excludes unopened Fushouling and nonstopping Bajiao")
	_check(not WorldData.find_station(WorldData.city("beijing"),"beijing-s67").is_empty(),"legacy Fushouling geographic object is retained")
	world.storyState.phase="future";world.storyState.chapterId=plan.id;world.storyState.stage="build";app._enter(world)
	candidate=app._assist_candidate()
	_check(str(candidate.get("issue","")).is_empty(),"real future branch previews: "+str(candidate.get("issue","")))
	result=app._commit_assisted_construction(candidate,int(world.revision))
	_check(bool(result.get("ok",false)),"future physical branch commits: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):await _finish(app);return
	for pairing in plan.requiredTransfers:
		var connection:Dictionary={"id":pairing.id,"name":pairing.name,"complexId":pairing.complexId,"stationInstanceIds":pairing.stationInstanceIds.duplicate(),"lineIds":pairing.lineIds.duplicate(),"status":"active","precision":"schematic","source":pairing.source,"effectiveDate":plan.date}
		result=app._commit_transfer_connection(pairing,connection,int(world.revision))
		_check(bool(result.get("ok",false)),"explicit separate Zhangguozhuang interchange: "+str(result.get("error","")))
	for group in plan.lineGroups:
		result=Story.confirm_task(world,str(group.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"future branch task confirms: "+str(result.get("error","")))
	_check(WorldData.find_route(world,"historical_beijing-lineearly0")==main,"planned branch preserves actual open main-line route")
	_check(bool(WorldData.find_route(world,"historical_beijing-line14-14").get("open",false)),"unrelated Line14 remains open after future branch confirmation")
	_check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"future Bajiao branch is not an open current-service stop")
	_check(OfficialNetworkAudit.current_project_errors(world,["bj-line1-branch"]).is_empty(),"independent branch order and transfer still pass")
	var variants:Array=world.routes.filter(func(r:Dictionary):return not str(r.get("constructionVariantId","")).is_empty() and str(r.get("historicalLineId",""))=="beijing-lineearly0")
	_check(variants.size()==1 and not bool(variants[0].get("open",true)),"future branch is a single nonoperating construction variant")
	# Reproduce the old saved relationship without changing its physical work.
	# This function regression is separate from normal-entry old-save replay.
	var legacy:=world.duplicate(true)
	var old_main:=WorldData.find_route(legacy,"historical_beijing-lineearly0")
	old_main.directions.append(variants[0].directions[0].duplicate(true))
	_check(not OfficialNetworkAudit.project_errors(legacy,target).is_empty(),"legacy future branch incorrectly merged into current service is detected")
	var legacy_edges:Array=legacy.trackEdges.duplicate(true)
	var replacement:Dictionary=main.duplicate(true)
	replacement=Story._preserve_documented_service_section(legacy,old_main,replacement,plan.lineGroups[0])
	_check(replacement.directions==main.directions and legacy.trackEdges==legacy_edges,"cutoff preservation excludes construction variants and keeps all built track")
	var broken:=world.duplicate(true)
	WorldData.find_route(broken,"historical_beijing-lineearly0").directions[0].stationIds.append(variants[0].stationOrder[0])
	_check(not OfficialNetworkAudit.project_errors(broken,target).is_empty(),"an open route falsely stopping at Bajiao fails independent current scope")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"save reload preserves current main-line and separate future branch")
	CampaignSystem._catalog.cities.beijing.chapters.pop_back()
	await _finish(app)
func _finish(app:Control) -> void:
	app.queue_free();await process_frame
	print("BEIJING1_CUTOFF_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
