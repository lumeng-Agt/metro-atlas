extends SceneTree
const Engineering=preload("res://scripts/engineering_construction.gd")
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
	WorldData.load_assets()
	var world:=WorldData.new_world("shenzhen","workshop")
	var anchor:=WorldData.create_station(world,[22.55,114.05],0)
	anchor.stationInstanceId="fixture-existing-platform"
	var group:Dictionary={"taskId":"fixture-zero-new-station","taskKind":"engineering_track","source":"https://example.invalid/labelled-test-fixture",
		"engineeringEndpoints":[{"id":"anchor","name":"既有端点","stationId":"fixture-geographic-id","stationInstanceId":"fixture-existing-platform"},
			{"id":"boundary","name":"工程边界（不是车站）","latlng":[22.557,114.05],"toleranceM":30.0}],
		"engineeringSegments":[{"fromId":"anchor","toId":"boundary","points":[[22.55,114.05],[22.554,114.05],[22.557,114.05]],"corridorToleranceM":80.0}]}
	_check(Engineering.definition_errors(group,["fixture-geographic-id"]).is_empty(),"a zero-new-station engineering scope is valid")
	_check(not bool(Engineering.evaluate(world,group).complete),"an unbuilt engineering section cannot pass")
	var original:=JSON.stringify(world);var draft:=world.duplicate(true)
	_check(str(Engineering.add_preview(draft,group).get("issue","")).is_empty(),"engineering preview creates actual physical track")
	_check(JSON.stringify(world)==original,"preview cannot mutate the original session")
	_check(draft.stations.size()==world.stations.size() and draft.routes.is_empty() and draft.transferConnections.is_empty(),"a boundary interface never becomes a passenger station, service or transfer")
	_check(draft.trackNodes.size()==world.trackNodes.size()+1 and draft.trackEdges.size()==1,"one free interface and one actual edge are constructed")
	_check(bool(Engineering.evaluate(draft,group).complete),"continuous constructed engineering track passes")
	var repeated:=draft.duplicate(true)
	_check(str(Engineering.add_preview(repeated,group).get("issue","")).is_empty() and repeated.trackNodes.size()==draft.trackNodes.size() and repeated.trackEdges.size()==draft.trackEdges.size(),"repeated preview reuses its existing node and physical section")
	var missing:=draft.duplicate(true);missing.trackEdges=[]
	_check(not bool(Engineering.evaluate(missing,group).complete),"nearby endpoints alone cannot substitute for a physical connection")
	var fake:=draft.duplicate(true);fake.trackEdges[0].transfer=true
	_check(not bool(Engineering.evaluate(fake,group).complete),"a transfer edge cannot substitute for a tunnel")
	var moved:=draft.duplicate(true)
	for node in moved.trackNodes:
		if node.get("engineeringTargetId","")=="boundary":node.latlng=[22.57,114.05]
	_check(not bool(Engineering.evaluate(moved,group).complete) and not str(Engineering.add_preview(moved,group).get("issue","")).is_empty(),"an existing interface outside its tolerance is reported rather than silently moved")
	var duplicate:=draft.duplicate(true)
	var extra:Dictionary=duplicate.trackNodes[-1].duplicate(true);extra.id="duplicate-interface";duplicate.trackNodes.append(extra)
	_check(not bool(Engineering.evaluate(duplicate,group).complete),"duplicate interface bindings are rejected")
	var detour:=draft.duplicate(true);detour.trackEdges[0].referencePoints.insert(1,[22.553,114.08])
	_check(not bool(Engineering.evaluate(detour,group).complete),"a physically connected detour outside the project corridor fails")
	var wrong:=group.duplicate(true);wrong.engineeringSegments[0].toId="unknown"
	_check(not Engineering.definition_errors(wrong).is_empty(),"unknown engineering endpoints fail definition validation")
	wrong=group.duplicate(true);wrong.engineeringEndpoints[1].latlng=[NAN,114.0]
	_check(not Engineering.definition_errors(wrong).is_empty(),"invalid engineering coordinates fail definition validation")
	wrong=group.duplicate(true);wrong.engineeringEndpoints[1].latlng=["22.55",114.0]
	_check(not Engineering.definition_errors(wrong).is_empty(),"coordinate strings cannot silently become geographic numbers")
	wrong=group.duplicate(true);wrong.engineeringSegments[0].corridorToleranceM=INF
	_check(not Engineering.definition_errors(wrong).is_empty(),"an infinite tolerance cannot waive the engineering corridor")
	var saved:=SaveManager.save_world(draft)
	var loaded:=SaveManager.load_file(str(saved.get("path","")))
	_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and loaded.get("world",{}).get("trackNodes",[])==JSON.parse_string(JSON.stringify(draft.trackNodes)) and loaded.get("world",{}).get("trackEdges",[])==JSON.parse_string(JSON.stringify(draft.trackEdges)),"engineering identities and geometry survive disk save/reload: "+str(saved.get("error",loaded.get("error",""))))
	_check(bool(Engineering.evaluate(loaded.get("world",{}),group).get("complete",false)),"reloaded actual geometry still satisfies the engineering scope")
	# Labelled command fixture: the real Songgang/Bitou bodies are first built
	# with the same assisted command as the player. The synthetic boundary below
	# tests the engineering workflow; it is not evidence of the real north project.
	var cutoff:Dictionary=CampaignSystem.city_config("shenzhen").chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var prelude:Dictionary=cutoff.duplicate(true);prelude.id="fixture-existing-shenzhen11";prelude.requiredTransfers=[];prelude.scopeCorrections=[]
	var existing_group:Dictionary=prelude.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="shenzhen-line11-12")[0].duplicate(true)
	existing_group.stationIds=["shenzhen-s201","shenzhen-s202"];existing_group.taskId="fixture-existing-11";existing_group.replaceExistingService=false
	prelude.lineGroups=[existing_group]
	var app:=App.new();root.add_child(app);await process_frame
	CampaignSystem._catalog.cities.shenzhen.chapters.append(prelude)
	var command_world:=WorldData.new_world("shenzhen","campaign")
	command_world.storyState.chapterId=prelude.id;command_world.storyState.stage="build";app._enter(command_world)
	var prelude_preview:=app._assist_candidate()
	var prelude_commit:=app._commit_assisted_construction(prelude_preview,int(command_world.revision))
	var prelude_confirm:=Story.confirm_task(command_world,"fixture-existing-11",int(command_world.revision))
	_check(bool(prelude_commit.get("ok",false)) and bool(prelude_confirm.get("ok",false)),"formal prelude constructs and confirms the two existing line bodies: "+str(prelude_commit.get("error",prelude_confirm.get("error",""))))
	var anchor_instance:=Story.station_instance_id(existing_group,"shenzhen-s202")
	var anchor_body:=Story.bound_station(command_world,"shenzhen-s202",anchor_instance)
	if anchor_body.is_empty():push_error("Prelude did not bind the actual anchor: "+JSON.stringify({"commit":prelude_commit,"confirm":prelude_confirm,"instance":anchor_instance,"stations":command_world.stations.map(func(s:Dictionary):return [s.id,s.get("historicalId",""),s.get("stationInstanceId","")])}));quit(1);return
	var a_point:Array=anchor_body.latlng.duplicate();var b_point:Array=[float(a_point[0])+0.007,float(a_point[1])]
	var engineering_group:Dictionary={"taskKind":"engineering_track","taskId":"fixture-engineering-task","coverageGroupId":"fixture-engineering-independent","name":"测试工程接口","source":"https://example.invalid/labelled-command-fixture","stationIds":["shenzhen-s202"],"stationInstances":{"shenzhen-s202":anchor_instance},"historicalLineId":"shenzhen-line11-12","toleranceM":100,
		"engineeringEndpoints":[{"id":"existing","name":"既有碧头接头","stationId":"shenzhen-s202","stationInstanceId":anchor_instance},
			{"id":"fixture-boundary","name":"测试边界（非真实项目）","latlng":b_point,"toleranceM":30.0}],
		"engineeringSegments":[{"fromId":"existing","toId":"fixture-boundary","points":[a_point,b_point],"corridorToleranceM":120.0}]}
	var engineering_chapter:Dictionary=CampaignSystem.city_config("shenzhen").futurePlans.filter(func(plan:Dictionary):return str(plan.id)=="sz-line15-build")[0].duplicate(true)
	engineering_chapter.id="fixture-engineering-chapter";engineering_chapter.lineGroups=[engineering_group];engineering_chapter.requiredTransfers=[];engineering_chapter.scopeCorrections=[];engineering_chapter.requireOpen=false;engineering_chapter.projectIds=[]
	CampaignSystem._catalog.cities.shenzhen.futurePlans.append(engineering_chapter)
	command_world.storyState.phase="future";command_world.storyState.chapterId=engineering_chapter.id;command_world.storyState.stage="build";app._enter(command_world)
	var missing_anchor:=command_world.duplicate(true);missing_anchor.stations=missing_anchor.stations.filter(func(s:Dictionary):return str(s.get("stationInstanceId",""))!=anchor_instance)
	app.world=missing_anchor
	_check(not str(app._assist_candidate().get("issue","")).is_empty() and missing_anchor.stations.size()==command_world.stations.size()-1,"a zero-new-station task reports a missing existing anchor rather than automatically creating a passenger station")
	app.world=command_world
	var before:Dictionary=JSON.parse_string(JSON.stringify(command_world));var candidate:Dictionary=app._assist_candidate()
	_check(str(candidate.get("issue","")).is_empty() and JSON.parse_string(JSON.stringify(command_world))==before,"visible engineering preview leaves the session unchanged")
	_check(not bool(app._commit_assisted_construction(candidate,int(command_world.revision)-1).get("ok",true)),"stale engineering preview cannot commit")
	_check(bool(app._commit_assisted_construction(candidate,int(command_world.revision)).get("ok",false)),"engineering track commits through the shared construction transaction")
	_check(command_world.stations.size()==before.stations.size() and command_world.routes==before.routes,"formal engineering commit adds no passenger station or service")
	_check(not app.history.undo().is_empty() and command_world.trackEdges.size()==before.trackEdges.size(),"engineering construction undoes in one step")
	_check(not app.history.redo().is_empty() and bool(Story.evaluate(command_world).get("complete",false)),"engineering redo restores a checkable physical connection")
	var blueprint:=Story.blueprint(command_world)
	_check(blueprint.get("engineeringMarkers",[]).size()==1 and blueprint.stations.size()==1,"blueprint separates a free interface from the existing passenger station")
	var expected:=engineering_group.duplicate(true);expected["id"]="fixture-engineering-independent";expected["scopeType"]="engineering"
	var independent:Dictionary={"source":engineering_group.source,"groups":[expected],"constructionOnly":true}
	_check(Engineering.coverage_errors(engineering_group,expected).is_empty() and OfficialNetworkAudit.project_errors(command_world,independent).is_empty(),"independent engineering coverage and actual construction both pass")
	var severed:=command_world.duplicate(true);severed.trackEdges.pop_back()
	_check(not OfficialNetworkAudit.project_errors(severed,independent).is_empty(),"independent audit rejects a severed engineering section")
	_check(bool(Story.confirm_task(command_world,"fixture-engineering-task",int(command_world.revision)).get("ok",false)),"engineering task confirms without manufacturing a route")
	var task_saved:=SaveManager.save_world(command_world);var task_loaded:=SaveManager.load_file(str(task_saved.get("path","")))
	_check(bool(task_saved.get("ok",false)) and bool(task_loaded.get("ok",false)) and bool(Story.evaluate(task_loaded.get("world",{})).get("complete",false)),"confirmed engineering task saves and resumes through the common save validator")
	_check(bool(Story.commit_chapter(command_world,int(command_world.revision)).get("ok",false)) and command_world.routes==before.routes,"engineering milestone confirms while retaining existing services unchanged")
	CampaignSystem._catalog.cities.shenzhen.futurePlans.pop_back();CampaignSystem._catalog.cities.shenzhen.chapters.pop_back()
	await _real_east_project(app,cutoff)
	app.queue_free();await process_frame
	print("ENGINEERING_CONSTRUCTION_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _real_east_project(app:Control,cutoff:Dictionary) -> void:
	# Real published engineering scope, isolated from full-city completion. Only
	# its two existing terminal neighbourhoods are built as a labelled prelude.
	var prelude:Dictionary=cutoff.duplicate(true)
	prelude.id="fixture-shenzhen10-existing-neighbours";prelude.requiredTransfers=[];prelude.scopeCorrections=[];prelude.lineGroups=[]
	for line_id in ["shenzhen-line10-11","shenzhen-line16-16"]:
		var group:Dictionary=cutoff.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)==str(line_id))[0].duplicate(true)
		if str(line_id)=="shenzhen-line10-11":group.stationIds=group.stationIds.slice(-2)
		else:
			var index:int=group.stationIds.find("shenzhen-s379")
			group.stationIds=group.stationIds.slice(index,index+2)
		group.taskId="fixture-neighbour:"+str(line_id);group.replaceExistingService=false
		prelude.lineGroups.append(group)
	CampaignSystem._catalog.cities.shenzhen.chapters.append(prelude)
	var world:=WorldData.new_world("shenzhen","campaign")
	world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var prepared:Dictionary=app._commit_assisted_construction(app._assist_candidate(),int(world.revision))
	_check(bool(prepared.get("ok",false)),"real east-extension prelude builds existing terminal neighbourhoods: "+str(prepared.get("error","")))
	for group in prelude.lineGroups:
		_check(bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),"real east-extension prelude confirms its labelled existing line fragment")
	world.storyState.phase="future";world.storyState.chapterId="sz-line10-east-build";world.storyState.stage="build";app._enter(world)
	var before:=JSON.parse_string(JSON.stringify(world)) as Dictionary
	var preview:Dictionary=app._assist_candidate()
	_check(str(preview.get("issue","")).is_empty() and JSON.parse_string(JSON.stringify(world))==before,"real east-extension preview does not mutate the session: "+str(preview.get("issue","")))
	var committed:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	_check(bool(committed.get("ok",false)),"real east-extension geometry commits through the player's construction transaction: "+str(committed.get("error","")))
	if not bool(committed.get("ok",false)):
		CampaignSystem._catalog.cities.shenzhen.chapters.pop_back();return
	_check(world.stations.size()==before.stations.size()+1 and world.routes==before.routes and world.transferConnections==before.transferConnections,"real Shenzhen-only extension adds one documented body, without a fictitious through service or active transfer")
	_check(not app.history.undo().is_empty() and world.stations.size()==before.stations.size(),"the real east-extension new body and both sections undo together")
	_check(not app.history.redo().is_empty() and bool(Story.evaluate(world).get("complete",false)),"the real east-extension redo restores both independently checked sections")
	var actual_group:Dictionary=Story.groups(world,true)[0]
	var latitude:=float(WorldData.city("shenzhen").center[0]);var path_index:=TrackNetwork.build_path_index(world,latitude)
	var west:=Engineering._resolve(world,actual_group.engineeringEndpoints[1],latitude)
	var east:=Engineering._resolve(world,actual_group.engineeringEndpoints[2],latitude)
	_check(Engineering.physical_path(world,path_index,str(west.node.id),str(east.node.id)).is_empty(),"the unapproved Dongguan middle is not filled in between the two real Shenzhen fragments")
	var definition:Dictionary=OfficialNetworkAudit.target_data().cities.shenzhen.projects.filter(func(p:Dictionary):return str(p.id)=="sz-line10-east-shenzhen")[0]
	_check(OfficialNetworkAudit.project_errors(world,definition).is_empty(),"real east-extension built geometry matches the independently recorded project scope")
	var broken:=world.duplicate(true);broken.trackEdges.pop_back()
	_check(not OfficialNetworkAudit.project_errors(broken,definition).is_empty(),"missing either real east-extension section fails independent checking")
	_check(bool(Story.confirm_task(world,"project:sz-line10-east-build",int(world.revision)).get("ok",false)) and bool(Story.commit_chapter(world,int(world.revision)).get("ok",false)),"real east-extension task and engineering milestone confirm without opening a train service")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),definition).is_empty(),"real east-extension identities, boundary interfaces and both tracks survive save/reload")
	CampaignSystem._catalog.cities.shenzhen.chapters.pop_back()
