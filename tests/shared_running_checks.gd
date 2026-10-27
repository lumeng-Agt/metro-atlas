extends SceneTree
const App=preload("res://scripts/main.gd")
const Story=preload("res://scripts/story_session.gd")
const Shared=preload("res://scripts/shared_running_audit.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var cutoff:Dictionary=CampaignSystem.city_config("chengdu").chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var fixture:=cutoff.duplicate(true);fixture.id="fixture-cd18-19-shared-physical";fixture.lineGroups=[];fixture.requiredTransfers=[];fixture.scopeCorrections=[];fixture.chapterScope="";fixture.requireOpen=true;fixture.eventOnly=false
	var rule:Dictionary={"physicalLineId":"chengdu-line18-13","serviceLineId":"chengdu-line19-14","intervalEndpoints":["三岔","天府机场北"],"stationNames":["三岔","福田","天府机场1号2号航站楼","天府机场北"],"source":"https://www.chengdurail.com/info/1331/52042.htm"}
	var definition:Dictionary={"sharedRunningSections":[rule.duplicate(true)],"sharedRunningEvidence":rule.stationNames.map(func(name:Variant):return {"stationName":name,"physicalLineId":rule.physicalLineId,"serviceLineId":rule.serviceLineId})}
	check(Shared.definition_errors(definition).is_empty(),"independent shared rule covers all documented physical stops")
	var unstated:Dictionary=definition.duplicate(true);unstated.sharedRunningSections[0].erase("intervalEndpoints")
	check(not Shared.definition_errors(unstated).is_empty(),"a section that never states the published interval cannot pass")
	var short_endpoint:Dictionary=definition.duplicate(true);short_endpoint.sharedRunningSections[0].intervalEndpoints=["三岔","宝山路"]
	check(not Shared.definition_errors(short_endpoint).is_empty(),"naming an endpoint the section never reaches is rejected")
	definition.sharedRunningSections[0].stationNames.pop_back()
	check(not Shared.definition_errors(definition).is_empty(),"omitting the last shared station cannot pass by shortening the rule")
	definition.sharedRunningSections=[]
	check(not Shared.definition_errors(definition).is_empty(),"removing the actual-geometry requirement does not hide source evidence")
	for group in cutoff.lineGroups:
		if str(group.historicalLineId) not in [rule.physicalLineId,rule.serviceLineId]:continue
		var part:Dictionary=group.duplicate(true);part.taskId="fixture:"+str(group.historicalLineId)
		part.stationIds=group.stationIds.filter(func(id:Variant):return rule.stationNames.has(str(group.get("stationNames",{}).get(str(id),WorldData.find_station(WorldData.city("chengdu"),str(id)).get("name","")))))
		fixture.lineGroups.append(part)
	CampaignSystem._catalog.cities.chengdu.chapters.append(fixture)
	var world:=WorldData.new_world("chengdu","campaign");world.storyState.chapterId=fixture.id;world.storyState.stage="build";world.storyState.tutorialEnabled=false;world.storyState.learnedTools=true;app._enter(world)
	var candidate:Dictionary=app._assist_candidate()
	check(str(candidate.get("issue","")).is_empty(),"actual common station geometry previews")
	var built:Dictionary=app._commit_assisted_construction(candidate,int(world.revision))
	check(bool(built.get("ok",false)),"shared prerequisites build through the formal command")
	if not bool(built.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	for group in Story.groups(world,true):check(bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),"each service confirms its actual directed path")
	check(world.stations.size()==4,"two services reuse four physical bodies, not eight invented platforms")
	check(Shared.errors(world,rule).is_empty(),"opposite directions normalize to the same physical shared tracks")
	check(world.transferConnections.is_empty(),"shared running does not create four pedestrian contacts")
	var duplicate:=world.duplicate(true)
	var body:Dictionary=duplicate.stations[0].duplicate(true);body.id="parallel-body";body.stationInstanceId="parallel-body";body.stationLineId=rule.serviceLineId;duplicate.stations.append(body)
	for route in duplicate.routes:
		if route.historicalLineId!=rule.serviceLineId:continue
		for direction in route.directions:
			for index in range(direction.stationIds.size()):
				if direction.stationIds[index]==world.stations[0].id:direction.stationIds[index]=body.id
	check(not Shared.errors(duplicate,rule).is_empty(),"a same-position, same-name separate body cannot certify physical sharing")
	var parallel:=world.duplicate(true);var replacement:Dictionary={}
	for edge in world.trackEdges:
		var copied:Dictionary=edge.duplicate(true);copied.id="parallel_"+str(edge.id);parallel.trackEdges.append(copied);replacement[str(edge.id)]=copied.id
	for route in parallel.routes:
		if route.historicalLineId!=rule.serviceLineId:continue
		for direction in route.directions:
			for segment in direction.edgePathsBySegment:
				for ref in segment:
					if replacement.has(str(ref.id)):ref.id=replacement[str(ref.id)]
	check(not Shared.errors(parallel,rule).is_empty(),"geometrically identical but distinct parallel edges are not the same physical track")
	var broken:=world.duplicate(true);broken.trackEdges.pop_back()
	check(not Shared.errors(broken,rule).is_empty(),"missing physical shared track invalidates both service claims")
	var closed:=world.duplicate(true)
	for route in closed.routes:
		if route.historicalLineId==rule.serviceLineId:route.open=false
	check(not Shared.errors(closed,rule).is_empty(),"an unopened candidate does not certify active shared operation")
	var saved:Dictionary=SaveManager.save_world(world);var loaded:Dictionary=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and Shared.errors(loaded.get("world",{}),rule).is_empty(),"shared physical identities and paths survive actual disk reload")
	app.queue_free();await process_frame
	print("SHARED_RUNNING_FIXTURE ",checks," FAILURES ",failures,"; focused actual station segment, not whole-city history")
	quit(0 if failures==0 else 1)
