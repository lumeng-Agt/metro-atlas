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
	var config:=CampaignSystem.city_config("guangzhou")
	var first:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.id)=="guangzhou-network-milestone-2022-03-31")[0]
	var later:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.id)=="guangzhou-line22-west-opening-2025")[0]
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	# Real adjoining line fragments are explicit prerequisites for this focused
	# two-opening fixture; this does not certify Guangzhou city chronology.
	var prelude:=first.duplicate(true);prelude.id="fixture-gz22-existing-transfer-fragments";prelude.lineGroups=[];prelude.requiredTransfers=[];prelude.scopeCorrections=[]
	var wanted:Dictionary={}
	for entry in [first,later]:
		for pairing in entry.requiredTransfers:
			for index in range(pairing.lineIds.size()):
				var line:=str(pairing.lineIds[index])
				if line=="guangzhou-line22-17":continue
				if not wanted.has(line):wanted[line]=[]
				wanted[line].append(str(pairing.stationInstanceIds[index]))
	for group in cutoff.lineGroups:
		var line:=str(group.historicalLineId)
		if not wanted.has(line):continue
		var start:int=group.stationIds.size();var finish:=-1
		for index in range(group.stationIds.size()):
			if wanted[line].has(Story.station_instance_id(group,str(group.stationIds[index]))):start=mini(start,index);finish=maxi(finish,index)
		if finish<0:continue
		if start==finish:
			if start>0:start-=1
			else:finish+=1
		var part:Dictionary=group.duplicate(true);part.stationIds=group.stationIds.slice(start,finish+1);part.loop=false;part.taskId="fixture:"+line;part.replaceExistingService=true
		prelude.lineGroups.append(part);wanted.erase(line)
	_check(wanted.is_empty(),"all documented interchange bodies have actual source-defined prerequisites")
	CampaignSystem._catalog.cities.guangzhou.chapters.append(prelude)
	var world:=WorldData.new_world("guangzhou","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	_check(str(preview.get("issue","")).is_empty(),"existing line fragments preview: "+str(preview.get("issue","")))
	var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	_check(bool(result.get("ok",false)),"existing fragments formally commit")
	if not bool(result.get("ok",false)):await _finish(app);return
	for group in Story.groups(world,true):
		result=Story.confirm_task(world,str(group.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"prerequisite line relationship confirms: "+str(result.get("error","")))
	for entry in [first,later]:
		world.storyState.chapterId=entry.id;world.storyState.stage="build";app._enter(world)
		preview=app._assist_candidate()
		_check(str(preview.get("issue","")).is_empty(),str(entry.id)+" preview: "+str(preview.get("issue","")))
		if not str(preview.get("issue","")).is_empty():break
		var count_before:int=world.stations.size()
		result=app._commit_assisted_construction(preview,int(world.revision))
		_check(bool(result.get("ok",false)),str(entry.id)+" formal construction")
		if not bool(result.get("ok",false)):break
		_check(world.stations.size()==count_before+4,"each dated opening adds exactly four line-specific bodies")
		for pairing in entry.requiredTransfers:
			var connection:Dictionary={"id":pairing.id,"name":pairing.name,"complexId":pairing.complexId,"stationInstanceIds":pairing.stationInstanceIds.duplicate(),"lineIds":pairing.lineIds.duplicate(),"status":"active","precision":"schematic","source":pairing.source,"effectiveDate":entry.date}
			result=app._commit_transfer_connection(pairing,connection,int(world.revision))
			_check(bool(result.get("ok",false)),"explicit independent transfer: "+str(pairing.id)+" "+str(result.get("error","")))
		for group in Story.groups(world,true):
			result=Story.confirm_task(world,str(group.taskId),int(world.revision))
			_check(bool(result.get("ok",false)),"dated route task: "+str(result.get("error","")))
		var errors:=OfficialNetworkAudit.historical_chapter_errors(world,str(entry.id))
		_check(errors.is_empty(),"independent opening range and all transfers: "+JSON.stringify(errors))
		var route:=WorldData.find_route(world,"historical_guangzhou-line22-17")
		_check(route.stationOrder.size()==(4 if entry.id==first.id else 8),"2022 has four stops, 2025 has eight")
		if entry.id==first.id:
			var premature:=world.duplicate(true);WorldData.find_station(premature,str(route.stationOrder[0])).name="芳村"
			_check(not OfficialNetworkAudit.historical_chapter_errors(premature,str(entry.id)).is_empty(),"a 2025 stop cannot stand in for the 2022 opening")
		var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
		_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.historical_chapter_errors(loaded.world,str(entry.id)).is_empty(),"dated service and explicit transfers survive reload")
		if bool(loaded.get("ok",false)):world=loaded.world
	await _finish(app)
func _finish(app:Control) -> void:
	app.queue_free();await process_frame
	for failure in failures:print("FAIL ",failure)
	print("GUANGZHOU22_OPENING_CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
