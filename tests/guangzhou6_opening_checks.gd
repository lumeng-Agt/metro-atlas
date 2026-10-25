extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var city:=CampaignSystem.city_config("guangzhou")
	var independent:Dictionary=OfficialNetworkAudit.target_data().cities.guangzhou
	# Only Line 6 is constructed in this focused fixture. Full-city replay
	# separately exercises the other lines and each real interchange.
	var world:=WorldData.new_world("guangzhou","campaign")
	var cases:Array=[
		["guangzhou-line6-first-2013",20,20,["一德路","沙河","植物园","柯木塱","香雪"]],
		["guangzhou-line6-yide-2015",3,21,["沙河","植物园","柯木塱","香雪"]],
		["guangzhou-network-milestone-2016-12-28",9,29,["沙河","植物园","柯木塱"]],
		["guangzhou-line6-gardens-2017",5,31,["沙河"]],
		["guangzhou-line11-ring-opening-2024",3,32,[]],
	]
	for row in cases:
		var original:Dictionary=city.chapters.filter(func(c:Dictionary):return c.id==row[0])[0]
		var fixture:Dictionary=original.duplicate(true)
		fixture.id="fixture-gz6-"+str(row[0]);fixture.requiredTransfers=[];fixture.historicalEventIds=[]
		fixture.lineGroups=original.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="guangzhou-line6-6")
		CampaignSystem._catalog.cities.guangzhou.chapters.append(fixture)
		world.storyState.chapterId=fixture.id;world.storyState.stage="build";app._enter(world)
		check(Story.targets(world,true).size()==int(row[1]),str(row[0])+" uses only this period's construction range")
		var retained:Dictionary={}
		for station in world.stations:retained[str(station.id)]={"latlng":station.latlng.duplicate(),"heading":station.heading,"endpointNodes":station.endpointNodes.duplicate()}
		var preview:Dictionary=app._assist_candidate()
		check(str(preview.get("issue","")).is_empty(),str(row[0])+" preview: "+str(preview.get("issue","")))
		var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
		check(bool(result.get("ok",false)),str(row[0])+" formal transaction: "+str(result.get("error","")))
		if not bool(result.get("ok",false)):break
		check(world.stations.all(func(station:Dictionary):return not retained.has(str(station.id)) or (station.latlng==retained[str(station.id)].latlng and station.heading==retained[str(station.id)].heading and station.endpointNodes==retained[str(station.id)].endpointNodes)),str(row[0])+" preserves existing station positions and ports")
		var geometry:Dictionary={"stations":world.stations.duplicate(true),"trackEdges":world.trackEdges.duplicate(true)}
		app.history.undo();app.history.redo()
		check(world.stations==geometry.stations and world.trackEdges==geometry.trackEdges,str(row[0])+" whole transaction undo/redo")
		for group in Story.groups(world,true):
			result=Story.confirm_task(world,str(group.taskId),int(world.revision))
			check(bool(result.get("ok",false)),str(row[0])+" confirms actual line relationship: "+str(result.get("error","")))
		var route:Dictionary=WorldData.find_route(world,"historical_guangzhou-line6-6")
		var names:Array=[]
		for id in route.get("stationOrder",[]):names.append(WorldData.find_station(world,str(id)).get("name",""))
		check(names.size()==int(row[2]) and route.get("directions",[]).size()==1,str(row[0])+" cumulative open service count")
		check(row[3].all(func(name:String):return not names.has(name)),str(row[0])+" cannot open deferred stations early")
		check(Story.changed_service_continuity_error(world,[route]).is_empty(),str(row[0])+" remains continuous outside both construction boundaries")
		var expected:Dictionary=independent.historicalMilestones.filter(func(m:Dictionary):return str(m.chapterId)==str(row[0]))[0]
		var scope:Dictionary={"groups":expected.groups.filter(func(g:Dictionary):return str(g.get("historicalLineId",""))=="guangzhou-line6-6")}
		var errors:=OfficialNetworkAudit.project_errors(world,scope)
		check(errors.is_empty(),str(row[0])+" matches independently reviewed full period service: "+JSON.stringify(errors))
		var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
		check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)),str(row[0])+" save/reload")
		if not bool(loaded.get("ok",false)):break
		world=loaded.world
	if failures.is_empty():
		# Narrow negative progress fixture, not a fabricated full-city replay:
		# the real constructed Line 6 is the sole independent cutoff scope here.
		var last:Dictionary=CampaignSystem._catalog.cities.guangzhou.chapters.filter(func(c:Dictionary):return str(c.id)=="fixture-gz6-guangzhou-line11-ring-opening-2024")[0]
		var cutoff:Dictionary={"id":"fixture-gz6-cutoff","date":"2026-10-01","chapterScope":"cutoff_reconciliation","lineGroups":last.lineGroups.duplicate(true)}
		CampaignSystem._catalog.cities.guangzhou.chapters=[last,cutoff]
		CampaignSystem._catalog.cities.guangzhou.futurePlans=[]
		var actual:Dictionary=independent.historicalMilestones.filter(func(m:Dictionary):return str(m.chapterId)=="guangzhou-line11-ring-opening-2024")[0]
		OfficialNetworkAudit._target_snapshot.cities.guangzhou.cutoffNetwork={"groups":actual.groups.filter(func(g:Dictionary):return str(g.get("historicalLineId",""))=="guangzhou-line6-6")}
		OfficialNetworkAudit._target_snapshot.cities.guangzhou.projects=[]
		check(OfficialNetworkAudit.cutoff_errors(world).is_empty(),"the focused real 32-stop route is initially a valid cutoff scope")
		world.storyState.merge({"phase":"history","chapterId":last.id,"chapterIndex":0,"stage":"outcome","completedChapterIds":[last.id,cutoff.id]},true)
		Story.next_chapter(world)
		check(world.storyState.completedChapterIds.has(cutoff.id) and str(world.storyState.chapterId)!=str(cutoff.id),"a valid later network does not force redundant cutoff rebuilding")
		world.storyState.merge({"phase":"history","chapterId":last.id,"chapterIndex":0,"stage":"outcome"},true)
		world.storyState.chapterTaskProgress[cutoff.id]={"status":"confirmed","originalRecord":"retain"}
		var changed_route:=WorldData.find_route(world,"historical_guangzhou-line6-6")
		changed_route.directions.append(changed_route.directions[0].duplicate(true))
		var physical_before:=JSON.stringify([world.stations,world.trackEdges,world.trackNodes])
		Story.next_chapter(world)
		check(str(world.storyState.chapterId)==str(cutoff.id) and not world.storyState.completedChapterIds.has(cutoff.id),"changed backfill service reopens the real cutoff task")
		check(str(world.storyState.chapterTaskProgress[cutoff.id].get("reason",""))=="post_backfill_network_changed" and str(world.storyState.legacyTaskProgress[cutoff.id].originalRecord)=="retain","cutoff recheck keeps the original historical confirmation record")
		check(physical_before==JSON.stringify([world.stations,world.trackEdges,world.trackNodes]),"reopening a check does not silently move or reconnect player construction")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("GUANGZHOU6_OPENING_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
