extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
const Shared=preload("res://scripts/shared_running_audit.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var cutoff:Dictionary=CampaignSystem.city_config("shanghai").chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var fixture:=cutoff.duplicate(true);fixture.id="fixture-shanghai34-shared-platforms";fixture.chapterScope="";fixture.requiredTransfers=[];fixture.scopeCorrections=[]
	fixture.lineGroups=fixture.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId) in ["shanghai-line3-3","shanghai-line4-4"])
	CampaignSystem._catalog.cities.shanghai.chapters.append(fixture)
	var network:Dictionary=OfficialNetworkAudit.target_data().cities.shanghai.cutoffNetwork
	var rule:Dictionary=network.sharedRunningSections[0]
	check(Shared.definition_errors(network).is_empty(),"all eight fully shared and the directional station have independent requirements")
	var missing:=network.duplicate(true);missing.sharedRunningSections[0].directionalStationRules=[]
	check(not Shared.definition_errors(missing).is_empty(),"removing Baoshan directional requirements cannot certify the shared network")
	var wrong_endpoint:=network.duplicate(true);wrong_endpoint.sharedRunningSections[0].intervalEndpoints=["宜山路","虹桥路"]
	check(not Shared.definition_errors(wrong_endpoint).is_empty(),"claiming Yishan Road as the shared interval end is rejected")
	var unstated:=network.duplicate(true);unstated.sharedRunningSections[0].erase("intervalEndpoints")
	check(not Shared.definition_errors(unstated).is_empty(),"a section that never states the published interval cannot pass")
	var world:=WorldData.new_world("shanghai","campaign");world.storyState.chapterId=fixture.id;world.storyState.stage="build";world.storyState.tutorialEnabled=false;app._enter(world)
	var before:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	var candidate:Dictionary=app._assist_candidate()
	check(str(candidate.get("issue","")).is_empty(),"three service patterns preview: "+str(candidate.get("issue","")))
	check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"preview is isolated")
	var built:Dictionary=app._commit_assisted_construction(candidate,int(world.revision))
	check(bool(built.get("ok",false)),"shared physical construction commits through the player command: "+str(built.get("error","")))
	if not bool(built.get("ok",false)):
		for failure in failures:push_error(failure)
		app.queue_free();await process_frame;quit(1);return
	var after:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
	app.history.undo();check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"one undo removes only the candidate construction")
	app.history.redo();check(after==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"redo restores the exact shared rail IDs")
	for group in Story.groups(world,true):
		var confirmed:=Story.confirm_task(world,str(group.taskId),int(world.revision))
		check(bool(confirmed.get("ok",false)),"each line/direction confirms separately: "+str(group.taskId)+" "+JSON.stringify(confirmed.get("evaluation",{}).get("issues",[])))
	var route:=WorldData.find_route(world,"historical_shanghai-line4-4")
	check(route.get("directions",[]).size()==2,"inner and outer circles are preserved as distinct operating patterns")
	check(Shared.errors(world,rule).is_empty(),"actual shared bodies and edge IDs match; outer Baoshan uses its own platform: "+JSON.stringify(Shared.errors(world,rule)))
	check(world.transferConnections.is_empty(),"common physical stations do not require invented walkways")
	# The operator roster counts these two as interchanges because lines 3 and 4
	# both call there. They have no transfer row on purpose: one body, two lines.
	for shared_name in ["中潭路","延安西路"]:
		var bodies:Array=world.stations.filter(func(s:Dictionary):return str(s.get("name",""))==shared_name)
		check(bodies.size()==1,"%s is one physical body rather than two named bodies"%shared_name)
		if bodies.size()!=1:continue
		var callers:Array=world.routes.filter(func(r:Dictionary):return r.get("stationOrder",[]).has(bodies[0].id))
		check(callers.size()==2 and callers.all(func(r:Dictionary):return str(r.get("historicalLineId","")) in ["shanghai-line3-3","shanghai-line4-4"]),"%s is called by both lines 3 and 4 without a walkway"%shared_name)
	var fake_walk:=world.duplicate(true)
	var source:Dictionary=fake_walk.stations.filter(func(s:Dictionary):return str(s.get("name",""))=="虹桥路" and str(s.get("stationLineId",""))=="shanghai-line3-3")[0]
	var phantom:=source.duplicate(true);phantom.id="fixture-old-parallel-body";phantom.stationInstanceId=phantom.id;phantom.stationLineId="shanghai-line4-4";fake_walk.stations.append(phantom)
	fake_walk.transferConnections.append({"id":"fixture-bogus-common-walk","lineIds":["shanghai-line3-3","shanghai-line4-4"],"stationInstanceIds":[source.stationInstanceId,phantom.stationInstanceId],"status":"active"})
	check(not Shared.errors(fake_walk,rule).is_empty(),"retaining an invented walking transfer is rejected even when shared rail is correct")
	var target:Dictionary={"groups":network.groups.filter(func(g:Dictionary):return str(g.historicalLineId) in ["shanghai-line3-3","shanghai-line4-4"])}
	check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"both complete circles and physical instance requirements match independently")
	var wrong:=world.duplicate(true)
	for r in wrong.routes:
		if str(r.get("historicalLineId",""))!="shanghai-line4-4":continue
		for d in r.directions:
			if str(d.get("servicePatternId",""))=="sh4-outer-2026":d.servicePatternId="sh4-inner-2026"
	check(not Shared.errors(wrong,rule).is_empty(),"dropping the outer operating identity is a failure")
	check(not OfficialNetworkAudit.project_errors(wrong,target).is_empty(),"same named circle does not replace the other documented direction")
	var copied:=world.duplicate(true)
	var shadow_id:="";var original_edge:=""
	for r in copied.routes:
		if str(r.get("historicalLineId",""))!="shanghai-line4-4":continue
		for d in r.directions:
			if str(d.get("servicePatternId",""))!="sh4-inner-2026":continue
			for i in range(d.stationIds.size()-1):
				if str(WorldData.find_station(copied,str(d.stationIds[i])).get("name",""))=="虹桥路":original_edge=str(d.edgePathsBySegment[i][0].id)
	for edge in copied.trackEdges:
		if str(edge.id)!=original_edge:continue
		var duplicate:Dictionary=edge.duplicate(true);shadow_id="fixture-parallel-identical-edge";duplicate.id=shadow_id;copied.trackEdges.append(duplicate);break
	check(not original_edge.is_empty() and not shadow_id.is_empty(),"parallel-track negative uses an actual shared segment")
	for r in copied.routes:
		if str(r.get("historicalLineId",""))!="shanghai-line4-4":continue
		for d in r.directions:
			for segment in d.edgePathsBySegment:
				for reference in segment:
					if str(reference.id)==original_edge:reference.id=shadow_id
	check(not Shared.errors(copied,rule).is_empty(),"identical copied geometry is not the same physical shared rail")
	var no_shared:=world.duplicate(true)
	for r in no_shared.routes:
		if str(r.get("historicalLineId",""))=="shanghai-line4-4":r.open=false
	check(not Shared.errors(no_shared,rule).is_empty(),"closed service cannot satisfy shared running")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and Shared.errors(loaded.get("world",{}),rule).is_empty(),"both patterns and physical track sharing survive real disk reload")
	var task:=str(fixture.lineGroups[0].taskId)
	check(Story.task_confirmed(world,task),"task is confirmed before a source-defined correction changes")
	fixture.requiresScopeRecheck=true
	fixture.scopeCorrections=[{"taskId":task,"transferId":"fixture-corrected-contact","oldLineIds":["a","b"],"oldStationInstanceIds":["old-a","b"],"newStationInstanceIds":["new-a","b"],"source":"https://example.org/fixture"}]
	check(not Story.task_confirmed(world,task),"a newly added physical correction invalidates that task's old fingerprint")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("SHANGHAI_SHARED_RUNNING_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
