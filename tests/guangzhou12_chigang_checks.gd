extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var city:=CampaignSystem.city_config("guangzhou")
	var first:Dictionary=city.chapters.filter(func(c:Dictionary):return str(c.id)=="guangzhou-network-milestone-2025-06-29")[0]
	var later:Dictionary=city.chapters.filter(func(c:Dictionary):return str(c.id)=="guangzhou-line12-chigang-2026")[0]
	var cutoff:Dictionary=city.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	# Focused physical prerequisites: a real adjoining Line 8 fragment. Other
	# contemporary lines/transfers are covered by the cumulative city replay.
	var original:Dictionary=cutoff.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="guangzhou-line8-8")[0]
	var at:=int(original.stationIds.find("guangzhou-s164"))
	var fragment:Dictionary=original.duplicate(true);fragment.stationIds=original.stationIds.slice(at-1,at+2);fragment.taskId="fixture-line8-chigang"
	var prelude:Dictionary=first.duplicate(true);prelude.id="fixture-chigang-line8";prelude.lineGroups=[fragment];prelude.requiredTransfers=[];prelude.scopeCorrections=[]
	CampaignSystem._catalog.cities.guangzhou.chapters.append(prelude)
	var world:=WorldData.new_world("guangzhou","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(result.get("ok",false)),"existing Line 8 fragment uses the actual construction transaction")
	check(bool(Story.confirm_task(world,str(fragment.taskId),int(world.revision)).get("ok",false)),"existing Line 8 independently confirms")
	var existing_body:=Story.bound_station(world,"guangzhou-s164","guangzhou-s164__line8-8").duplicate(true)
	for phase in [first,later]:
		var fixture:Dictionary=phase.duplicate(true);fixture.id="fixture-chigang-"+str(phase.id)
		fixture.lineGroups=phase.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="guangzhou-line12-12")
		fixture.scopeCorrections=[];fixture.requiredTransfers=later.requiredTransfers if phase==later else []
		CampaignSystem._catalog.cities.guangzhou.chapters.append(fixture)
		world.storyState.chapterId=fixture.id;world.storyState.stage="build";app._enter(world)
		preview=app._assist_candidate();check(str(preview.get("issue","")).is_empty(),str(phase.id)+" preview")
		result=app._commit_assisted_construction(preview,int(world.revision));check(bool(result.get("ok",false)),str(phase.id)+" formal commit")
		if not bool(result.get("ok",false)):break
		for group in Story.groups(world,true):check(bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),str(phase.id)+" confirms its true service path")
		var route:=WorldData.find_route(world,"historical_guangzhou-line12-12")
		var names:Array=[]
		for direction in route.directions:
			for id in direction.stationIds:names.append(WorldData.find_station(world,str(id)).name)
		check(route.directions.size()==2 and names.size()==(18 if phase==later else 17),str(phase.id)+" keeps the two disconnected opening sections separate")
		check(names.has("赤岗")==bool(phase==later),str(phase.id)+" cannot open Chigang before 2026")
		if phase==later:
			check(not bool(Story.evaluate(world).complete),"the new station alone does not establish its interchange")
			var pair:Dictionary=later.requiredTransfers[0]
			var connection:Dictionary={"id":pair.id,"name":pair.name,"complexId":pair.complexId,"lineIds":pair.lineIds.duplicate(),"stationInstanceIds":pair.stationInstanceIds.duplicate(),"source":pair.source,"status":"active","precision":"schematic","effectiveDate":later.date}
			check(bool(app._commit_transfer_connection(pair,connection,int(world.revision)).get("ok",false)),"8/12 interchange explicitly confirms after the separate 12 body connects")
			check(bool(Story.evaluate(world).complete),"the actual infill and explicit relation complete the 2026 task")
		var retained_body:=Story.bound_station(world,"guangzhou-s164","guangzhou-s164__line8-8")
		check(Geo.local_m(retained_body.latlng,23.13).distance_to(Geo.local_m(existing_body.latlng,23.13))<0.001 and absf(float(retained_body.heading)-float(existing_body.heading))<0.000001,"the existing Line 8 body is not moved or merged (JSON numeric roundtrip tolerance below one millimetre)")
		var milestone:Dictionary=OfficialNetworkAudit.target_data().cities.guangzhou.historicalMilestones.filter(func(m:Dictionary):return str(m.chapterId)==str(phase.id))[0]
		var errors:=OfficialNetworkAudit.project_errors(world,milestone)
		check(errors.is_empty(),str(phase.id)+" matches its independently transcribed opening scope: "+JSON.stringify(errors))
		var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
		check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)),str(phase.id)+" save and reload")
		if bool(loaded.get("ok",false)):world=loaded.world
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("GUANGZHOU12_CHIGANG_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
