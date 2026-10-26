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
	var config:Dictionary=CampaignSystem.city_config("beijing")
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var plan:Dictionary=config.futurePlans.filter(func(p:Dictionary):return str(p.id)=="bj-line13-capacity-build")[0]
	var needed:Dictionary={}
	for transfer in plan.requiredTransfers:
		for index in range(transfer.lineIds.size()):
			var line:=str(transfer.lineIds[index]);var body:=str(transfer.stationInstanceIds[index])
			if not needed.has(line):needed[line]=[]
			needed[line].append(body)
	# This explicitly labelled fixture builds real old lines plus the local
	# fragments needed by the project's interchanges. It is not full-city proof.
	var prelude:=cutoff.duplicate(true);prelude.id="fixture-existing-beijing13-capacity";prelude.lineGroups=[];prelude.requiredTransfers=[];prelude.projectIds=[];prelude.scopeCorrections=[]
	# These are explicitly scoped interchange fragments, not the cutoff's
	# full Line 1/2 public-opening actions (including the complete ring).
	prelude.serviceTransitions=[]
	for original in cutoff.lineGroups:
		var line:=str(original.historicalLineId)
		if line not in ["beijing-line13-13","beijing-line18-18"] and not needed.has(line):continue
		var g:Dictionary=original.duplicate(true);g.replaceExistingService=false;g.loop=false
		if line not in ["beijing-line13-13","beijing-line18-18"]:
			var first:int=g.stationIds.size();var last:=-1
			for index in range(g.stationIds.size()):
				if needed.get(line,[]).has(Story.station_instance_id(g,str(g.stationIds[index]))):first=mini(first,index);last=maxi(last,index)
			if last<0:continue
			if first==last:
				if last<g.stationIds.size()-1:last+=1
				else:first-=1
			g.stationIds=g.stationIds.slice(first,last+1)
		prelude.lineGroups.append(g)
	CampaignSystem._catalog.cities.beijing.chapters.append(prelude)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var candidate:Dictionary=app._assist_candidate()
	_check(str(candidate.get("issue","")).is_empty(),"existing line fragments preview: "+str(candidate.get("issue","")))
	var result:Dictionary=app._commit_assisted_construction(candidate,int(world.revision))
	_check(bool(result.get("ok",false)),"existing fragments commit through formal construction: "+str(result.get("error","")))
	for g in prelude.lineGroups:
		result=Story.confirm_task(world,str(g.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"existing line fragment confirms: "+str(g.taskId)+" "+str(result.get("error","")))
	var names:Dictionary={}
	for station in world.stations:names[str(station.id)]=str(station.name)
	var old_routes:Array=world.routes.duplicate(true);var old_edges:int=world.trackEdges.size()
	_check(CampaignSystem.canonical_station_complex("beijing","beijing-s8")==CampaignSystem.canonical_station_complex("beijing","beijing-s89") and CampaignSystem.canonical_station_complex("beijing","beijing-s85")==CampaignSystem.canonical_station_complex("beijing","beijing-s74"),"documented interchange aliases unify only logical station-complex identity")
	world.storyState.phase="future";world.storyState.chapterId=plan.id;world.storyState.stage="build";app._enter(world)
	candidate=app._assist_candidate()
	_check(str(candidate.get("issue","")).is_empty(),"actual 19/15-stop capacity geometry previews: "+str(candidate.get("issue","")))
	result=app._commit_assisted_construction(candidate,int(world.revision))
	_check(bool(result.get("ok",false)),"capacity station bodies and tracks formally commit: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):await _finish(app);return
	_check(not app.history.undo().is_empty() and world.trackEdges.size()==old_edges,"all new capacity geometry undoes together")
	_check(not app.history.redo().is_empty(),"capacity geometry redoes together")
	result=app._commit_line_reorganization(int(world.revision))
	_check(bool(result.get("ok",false)),"two sourced capacity service paths reorganize through the common command: "+JSON.stringify(result))
	for t in plan.requiredTransfers:
		var connection:Dictionary={"id":str(t.id),"name":str(t.name),"complexId":str(t.complexId),"stationInstanceIds":t.stationInstanceIds.duplicate(),"lineIds":t.lineIds.duplicate(),"status":"active","precision":"schematic","source":str(t.source),"effectiveDate":str(plan.date)}
		var linked:Dictionary=app._commit_transfer_connection(t,connection,int(world.revision))
		_check(bool(linked.get("ok",false)),"capacity independent-body interchange: "+str(t.name)+" "+str(linked.get("error","")))
	for g in plan.lineGroups:
		result=Story.confirm_task(world,str(g.taskId),int(world.revision))
		_check(bool(result.get("ok",false)),"capacity task confirms separately: "+str(g.taskId)+" "+str(result.get("error","")))
	_check(world.routes.slice(0,old_routes.size())==old_routes,"ultimate construction relations do not replace open 13/18 services")
	for station in world.stations:
		if names.has(str(station.id)):_check(str(station.name)==str(names[str(station.id)]),"existing open station name preserved: "+str(station.name))
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing.projects.filter(func(p:Dictionary):return str(p.id)=="bj-line13-capacity")[0]
	var issues:=OfficialNetworkAudit.project_errors(world,target)
	_check(issues.is_empty(),"independent full 19+15 orders, physical paths and listed transfers: "+JSON.stringify(issues))
	var wrong_body:=world.duplicate(true)
	var old_longze:=Story.bound_station(wrong_body,"beijing-s94","beijing-s94")
	for route in wrong_body.routes:
		if str(route.get("historicalLineId",""))!="beijing-capacity13B":continue
		for i in range(route.stationOrder.size()):
			if str(WorldData.find_station(wrong_body,str(route.stationOrder[i])).get("stationInstanceId",""))=="beijing-s94__capacity13B-rebuilt":
				route.stationOrder[i]=old_longze.id;route.directions[0].stationIds[i]=old_longze.id
	var wrong_issues:=OfficialNetworkAudit.project_errors(wrong_body,target)
	_check(wrong_issues.any(func(text:String):return text.contains("documented physical body differs at 龙泽")),"old same-name Longze body cannot replace the documented rebuilt body")
	app._tool("select");app.evaluation={};app.selected_kind="station";app.selected_id=str(Story.bound_station(world,"beijing-s89","beijing-s89__line13-13").id);app._right()
	_check(app.right.find_children("*","Button",true,false).any(func(b:Button):return b.text.begins_with("切换到另一线路站体") and b.text.contains("15")),"station details can select the separate Line 15 body across documented complex aliases")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"full capacity scope survives actual save/reload")
	result=Story.commit_chapter(world,int(world.revision))
	_check(bool(result.get("ok",false)),"capacity construction milestone confirms: "+str(result.get("error","")))
	await _finish(app)
func _finish(app:Control) -> void:
	CampaignSystem._catalog.cities.beijing.chapters.pop_back();app.queue_free();await process_frame
	print("BEIJING13_CAPACITY_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
