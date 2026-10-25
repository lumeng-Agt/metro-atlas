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
	var cutoff:Dictionary=CampaignSystem.city_config("shenzhen").chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var prelude:Dictionary=cutoff.duplicate(true);prelude.id="fixture-current-station-names";prelude.requiredTransfers=[];prelude.scopeCorrections=[];prelude.projectIds=[]
	var group:Dictionary=cutoff.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)=="shenzhen-line11-12")[0].duplicate(true)
	group.stationIds=["shenzhen-s201","shenzhen-s202"];group.taskId="fixture-current-11";group.replaceExistingService=false;prelude.lineGroups=[group]
	CampaignSystem._catalog.cities.shenzhen.chapters.append(prelude)
	var world:=WorldData.new_world("shenzhen","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	_check(bool(app._commit_assisted_construction(app._assist_candidate(),int(world.revision)).get("ok",false)) and bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),"labelled fixture builds and confirms an existing open service through formal commands")
	var before_names:Array=world.stations.map(func(s:Dictionary):return str(s.name));var before_geometry:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges]);var before_route:Dictionary=world.routes[0].duplicate(true)
	var future:Dictionary=CampaignSystem.city_config("shenzhen").futurePlans.filter(func(p:Dictionary):return str(p.id)=="sz-line15-build")[0].duplicate(true)
	future.id="fixture-planned-station-names";future.projectIds=[];future.requiredTransfers=[];future.scopeCorrections=[]
	var proposed:=group.duplicate(true);proposed.taskId="fixture-proposed-11";proposed.constructionVariant=true;proposed.stationNamingSource="https://example.invalid/labelled-planned-name-fixture"
	proposed.stationNames={"shenzhen-s201":"规划名称A","shenzhen-s202":"规划名称B"};future.lineGroups=[proposed]
	CampaignSystem._catalog.cities.shenzhen.futurePlans.append(future)
	_check(CampaignSystem.future_data_ready(future,WorldData.city("shenzhen")),"a sourced planning variant is a valid future blueprint")
	var bad_blueprint:=future.duplicate(true);bad_blueprint.lineGroups[0].stationNamingSource=""
	_check(not CampaignSystem.future_data_ready(bad_blueprint,WorldData.city("shenzhen")),"an unsourced planning name cannot advertise a ready blueprint")
	bad_blueprint=future.duplicate(true);bad_blueprint.lineGroups[0].constructionVariant=false
	_check(not CampaignSystem.future_data_ready(bad_blueprint,WorldData.city("shenzhen")),"contextual names cannot advertise replacement of the open service")
	world.storyState.phase="future";world.storyState.chapterId=future.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	_check(str(preview.get("issue","")).is_empty() and JSON.stringify([preview.get("state",{}).get("stations",[]),preview.get("state",{}).get("trackNodes",[]),preview.get("state",{}).get("trackEdges",[])])==before_geometry,"a future name preview reuses actual bodies and geometry without renaming the current service")
	_check(bool(app._commit_assisted_construction(preview,int(world.revision)).get("ok",false)) and bool(Story.confirm_task(world,str(proposed.taskId),int(world.revision)).get("ok",false)),"future name context confirms through the common transaction and task flow")
	_check(world.stations.map(func(s:Dictionary):return str(s.name))==before_names and world.routes[0]==before_route,"confirming a sourced proposal leaves existing station names and open service unchanged")
	app._tool("select");app.evaluation={};app.selected_kind="station";app.selected_id=str(world.stations[0].id);app._right()
	var texts:Array=[]
	for node in app.right.find_children("*","Label",true,false):texts.append(str(node.text))
	_check(texts.has("本期规划名称：规划名称A"),"station details distinguish the plan label from the current open name")
	_check(not app.right.find_children("*","Button",true,false).any(func(b:Button):return b.text.begins_with("确认历史更名")),"a contextual planning alias does not offer to rename the current station")
	var expected:Dictionary={"constructionOnly":true,"groups":[{"id":"planning-name-scope","historicalLineId":"shenzhen-line11-12","stationNames":["规划名称A","规划名称B"],"stationNamingSource":str(proposed.stationNamingSource)}]}
	_check(OfficialNetworkAudit.project_errors(world,expected).is_empty(),"independent future checking can use the explicitly sourced planning names")
	var current:Dictionary={"groups":[{"id":"current-name-scope","historicalLineId":"shenzhen-line11-12","stationNames":["松岗","碧头"]}]}
	_check(OfficialNetworkAudit.project_errors(world,current).is_empty(),"historical/current checking continues to read the original open names")
	var wrong_source:=expected.duplicate(true);wrong_source.groups[0].stationNamingSource="https://example.invalid/unrelated-source"
	_check(not OfficialNetworkAudit.project_errors(world,wrong_source).is_empty(),"a planning alias cannot substitute for independently required naming evidence")
	var false_history:=expected.duplicate(true);false_history.constructionOnly=false
	_check(not OfficialNetworkAudit.project_errors(world,false_history).is_empty(),"planned names cannot manufacture a historical opening")
	var invalid:=world.duplicate(true);invalid.routes[-1].open=true
	_check(not SaveManager.validate(invalid).is_empty(),"a planning-name variant cannot be saved as an open service")
	invalid=world.duplicate(true);invalid.routes[-1].plannedStationNames["unknown-body"]="假的站"
	_check(not SaveManager.validate(invalid).is_empty(),"planning names may reference only real stops in that variant")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),expected).is_empty() and loaded.get("world",{}).stations.map(func(s:Dictionary):return str(s.name))==before_names,"planning labels and unchanged current names survive actual disk reload")
	CampaignSystem._catalog.cities.shenzhen.chapters.pop_back();CampaignSystem._catalog.cities.shenzhen.futurePlans.pop_back();app.queue_free();await process_frame
	print("PLANNED_STATION_NAME_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
