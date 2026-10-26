extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)
func fragment(source:Dictionary,ids:Array,task:String) -> Dictionary:
	var group:=source.duplicate(true);group.stationIds=ids.duplicate();group.taskId=task
	return group
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var inventory:Dictionary={"sourceProjectInventory":[{"projectId":"infill-fixture","source":"https://example.org/roster","sourcePublicationDate":"2026-02-03"}],"projects":[],"requiredProjectIds":[]}
	check(not CampaignSystem.published_inventory_errors(inventory,"2026-10-01").is_empty(),"published roster catches a completely omitted project")
	inventory.projects=[{"id":"infill-fixture"}];inventory.requiredProjectIds=["infill-fixture"]
	check(CampaignSystem.published_inventory_errors(inventory,"2026-10-01").is_empty(),"dated source row has a mandatory independent target")
	inventory.projects[0].optional=true
	check(not CampaignSystem.published_inventory_errors(inventory,"2026-10-01").is_empty(),"mandatory source row cannot be hidden as optional")
	inventory.sourceProjectInventory[0].sourcePublicationDate="2026-10-02"
	check(not CampaignSystem.published_inventory_errors(inventory,"2026-10-01").is_empty(),"post-cutoff roster cannot prove earlier requirements")
	check(not CampaignSystem.published_inventory_errors({"inventoryReviewStatus":"verified"},"2026-10-01").is_empty(),"verified flag without source records cannot unlock content")
	var config:=CampaignSystem.city_config("beijing")
	var plans:Array=[]
	for id in ["bj-yizhuang-taihu-build","bj-line15-guozhan-build","bj-airport-wangjingnan-build"]:
		plans.append(config.futurePlans.filter(func(p:Dictionary):return str(p.id)==id)[0])
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var by_line:Dictionary={}
	for group in cutoff.lineGroups:by_line[str(group.historicalLineId)]=group
	# Local source-derived anchors only: not a complete historical replay.
	var prelude:Dictionary=plans[0].duplicate(true);prelude.id="fixture-infill-anchors";prelude.requiredTransfers=[];prelude.lineGroups=[]
	prelude.lineGroups.append(fragment(by_line["beijing-route-24"],["beijing-s265","beijing-s266"],"fixture-yizhuang"))
	prelude.lineGroups.append(fragment(by_line["beijing-line15-15"],["beijing-s14","beijing-s15"],"fixture-15"))
	prelude.lineGroups.append(fragment(by_line["beijing-route-23"],["beijing-s174","beijing-s207","beijing-s208"],"fixture-airport"))
	prelude.lineGroups.append(fragment(by_line["beijing-line14-14"],["beijing-s270","beijing-s271","beijing-s272"],"fixture-14"))
	CampaignSystem._catalog.cities.beijing.futurePlans.append(prelude)
	var world:=WorldData.new_world("beijing","campaign");world.storyState.phase="future";world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate();var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(result.get("ok",false)),"local existing-line anchors commit: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	for group in Story.groups(world,true):
		result=Story.confirm_task(world,str(group.taskId),int(world.revision));check(bool(result.get("ok",false)),"local anchor service confirms: "+str(group.taskId))
	var current:Dictionary={}
	for route in world.routes:current[str(route.id)]=JSON.stringify(route)
	var original_names:Dictionary={}
	for station in world.stations:original_names[str(station.id)]=str(station.name)
	var old14:=Story.bound_station(world,"beijing-s271","beijing-s271").duplicate(true)
	for plan in plans:
		world.storyState.phase="future";world.storyState.chapterId=plan.id;world.storyState.stage="build";app._enter(world)
		var before:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
		preview=app._assist_candidate();check(str(preview.get("issue","")).is_empty(),"preview "+str(plan.id)+": "+str(preview.get("issue","")))
		check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"preview is isolated")
		result=app._commit_assisted_construction(preview,int(world.revision));check(bool(result.get("ok",false)),"formal infill commit: "+str(result.get("error","")))
		if not bool(result.get("ok",false)):break
		var built:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges])
		app.history.undo();check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"one undo preserves the existing network")
		app.history.redo();check(built==JSON.stringify([world.stations,world.trackNodes,world.trackEdges]),"redo restores exact new geometry")
		for group in Story.groups(world,true):
			result=Story.confirm_task(world,str(group.taskId),int(world.revision));check(bool(result.get("ok",false)),"each infill task confirms its own path: "+str(result.get("error","")))
		for pair in plan.requiredTransfers:
			check(app._transfer_ready(pair),"both line-specific station bodies are available")
			var connection:Dictionary=pair.duplicate(true);connection.status="active"
			result=app._commit_transfer_connection(pair,connection,int(world.revision));check(bool(result.get("ok",false)),"explicit pedestrian contact: "+str(result.get("error","")))
		var project_id:=str(plan.projectIds[0])
		var target:Dictionary=OfficialNetworkAudit.target_data().cities.beijing.projects.filter(func(p:Dictionary):return str(p.id)==project_id)[0]
		check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"actual built project matches independent station order: "+project_id)
		var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
		check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"actual save/reload preserves infill and contact")
	for route_id in current:check(current[route_id]==JSON.stringify(WorldData.find_route(world,str(route_id))),"existing service is not replaced by future infill "+str(route_id))
	for station_id in original_names:check(original_names[station_id]==str(WorldData.find_station(world,station_id).name),"future engineering labels do not rename existing station "+station_id)
	check(old14==Story.bound_station(world,"beijing-s271","beijing-s271"),"original underground Line 14 station is not moved or shared")
	var airport:=Story.bound_station(world,"beijing-s271","beijing-s271__airport-infill")
	check(not airport.is_empty() and str(airport.get("referenceId",""))=="beijing-airport-wangjingnan","airport body keeps its own geographic reference")
	check(str(airport.get("constructionForm",""))=="高架三层侧式站" and float(airport.get("depthM",0))>0,"airport station has the sourced elevated form")
	check(not bool(TrackNetwork.shortest_station_path(str(old14.id),str(airport.get("id","")),world,39.9).get("valid",false)),"train cannot cross the pedestrian skybridge")
	var taihu:=Story.bound_station(world,"beijing-future-taihu","beijing-future-taihu")
	check(str(taihu.get("constructionForm",""))=="地面单侧站" and is_zero_approx(float(taihu.get("depthM",-15))),"Taihu is ground-level, not a new underground depot requirement")
	var exhibition:=Story.bound_station(world,"beijing-future-guozhan2","beijing-future-guozhan2")
	check(str(exhibition.get("constructionForm",""))=="高架两层侧式站","approved exhibition station structure is retained")
	for source in Story.groups(world,true):
		var heading:=ReferenceAlignment.heading("beijing-airport-wangjingnan",[source],39.9,"beijing-route-23")
		check(heading>=0,"line-specific reference identity yields a real heading")
	var reference:=ReferenceAlignment.between("beijing-s174","beijing-airport-wangjingnan")
	var legacy_terminal:={"historicalId":"beijing-s174","stationInstanceId":"beijing-s174__line23"}
	check(ReferenceAlignment.for_stations(legacy_terminal,airport).get("id")==reference.get("id"),"manual linking resolves a mixed legacy terminal and new geographic reference")
	check(ReferenceAlignment.for_stations(airport,legacy_terminal).get("points",[]).front()==reference.points.back(),"manual reverse linking retains exactly the reversed reference geometry")
	var length:=0.0
	# Compare reference geography directly, independent of the displayed label.
	length=0
	for i in range(reference.get("points",[]).size()-1):length+=Geo.local_m(reference.points[i],39.9).distance_to(Geo.local_m(reference.points[i+1],39.9))
	check(length>2500 and length<4500,"nearest opposite rail never makes Sanyuanqiao–Wangjingnan detour to the airport")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("BEIJING_INFILL_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
