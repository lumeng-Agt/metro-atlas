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
	var config:=CampaignSystem.city_config("shanghai")
	var plan:Dictionary=config.futurePlans.filter(func(p:Dictionary):return str(p.id)=="sh-nanjingwest-passage-build")[0]
	check(CampaignSystem.future_data_ready(plan,WorldData.city("shanghai")),"a sourced planned pedestrian project is playable without fake train tracks")
	var invalid:=plan.duplicate(true);invalid.requiredTransfers[0].status="active"
	check(not CampaignSystem.future_data_ready(invalid,WorldData.city("shanghai")),"planned passage cannot be published as an already open transfer")
	invalid=plan.duplicate(true);invalid.requiredTransfers[0].reservationEvidence=""
	check(not CampaignSystem.future_data_ready(invalid,WorldData.city("shanghai")),"missing project evidence blocks the task")
	invalid=plan.duplicate(true);invalid.requiredTransfers[0].reservationKind="other-kind"
	check(not CampaignSystem.future_data_ready(invalid,WorldData.city("shanghai")),"unknown civil-work kind cannot masquerade as a ready passage")
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var prelude:Dictionary=plan.duplicate(true);prelude.id="fixture-nanjing-anchors";prelude.operationType="build";prelude.requiredTransfers=[];prelude.lineGroups=[]
	for line in ["shanghai-line2-2","shanghai-line12-12","shanghai-line13-13"]:
		var original:Dictionary=cutoff.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)==line)[0]
		var wanted:="shanghai-s304" if line=="shanghai-line2-2" else "shanghai-s242" if line=="shanghai-line12-12" else "shanghai-s175"
		var group:=original.duplicate(true);var position:int=group.stationIds.find(wanted)
		group.stationIds=group.stationIds.slice(position-1,position+2);group.taskId="fixture-"+line
		prelude.lineGroups.append(group)
	CampaignSystem._catalog.cities.shanghai.futurePlans.append(prelude)
	var world:=WorldData.new_world("shanghai","campaign");world.storyState.phase="future";world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate();var result:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(result.get("ok",false)),"real-side station fragments commit: "+str(result.get("error","")))
	if not bool(result.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	for group in Story.groups(world,true):
		result=Story.confirm_task(world,str(group.taskId),int(world.revision));check(bool(result.get("ok",false)),"each existing-side line confirms")
	world.storyState.chapterId=plan.id;world.storyState.phase="future";world.storyState.stage="build";app._enter(world)
	var before:=JSON.stringify([world.stations,world.trackNodes,world.trackEdges,world.routes])
	check(not bool(Story.evaluate(world).complete),"reading or opening the project does not create the passage")
	for pair in plan.requiredTransfers:
		check(app._transfer_ready(pair),"two independent bodies and actual line paths are ready")
		var forged:Dictionary=pair.duplicate(true);forged.status="active"
		check(not bool(app._commit_transfer_reservation(pair,forged,int(world.revision)).get("ok",false)),"active status cannot impersonate a planned passage")
		check(not bool(app._commit_transfer_reservation(pair,pair.duplicate(true),int(world.revision)+1).get("ok",false)),"stale preview cannot commit")
		result=app._commit_transfer_reservation(pair,pair.duplicate(true),int(world.revision));check(bool(result.get("ok",false)),"explicit planning transaction: "+str(result.get("error","")))
		check(TransferReservation.saved_matches(world,pair),"saved source, type and physical pair match")
		var a:=Story.bound_station(world,str(pair.complexId),str(pair.stationInstanceIds[0]));var b:=Story.bound_station(world,str(pair.complexId),str(pair.stationInstanceIds[1]))
		check(a.id!=b.id and not bool(TrackNetwork.shortest_station_path(str(a.id),str(b.id),world,31.2).get("valid",false)),"planning a pedestrian passage never joins train tracks or station bodies")
	check(before==JSON.stringify([world.stations,world.trackNodes,world.trackEdges,world.routes]),"all construction-side rail geometry and existing services are untouched")
	check(world.transferConnections.all(func(p:Dictionary):return str(p.status)=="reserved"),"none of the three planned connections becomes a live walk link")
	check(bool(Story.evaluate(world).complete),"all three explicitly confirmed relations complete the construction scope")
	app.history.undo();check(not bool(Story.evaluate(world).complete),"undo removes the last required passage relation")
	app.history.redo();check(bool(Story.evaluate(world).complete),"redo restores exact passage state")
	var target:Dictionary=OfficialNetworkAudit.target_data().cities.shanghai.projects.filter(func(p:Dictionary):return str(p.id)=="sh-nanjingwest-paid-passage")[0]
	check(OfficialNetworkAudit.project_errors(world,target).is_empty(),"formal saved world matches independently defined planned connections")
	var broken:=world.duplicate(true);broken.transferConnections[0].status="active"
	check(not OfficialNetworkAudit.project_errors(broken,target).is_empty(),"independent audit catches premature opening")
	broken=world.duplicate(true);broken.transferConnections[0].reservationKind="other-kind"
	check(not OfficialNetworkAudit.project_errors(broken,target).is_empty(),"a different kind cannot reuse the same completion identity")
	check(bool(Story.commit_chapter(world,int(world.revision),Story.evaluate(world)).get("ok",false)),"planning milestone confirms after real operations")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.project_errors(loaded.get("world",{}),target).is_empty(),"three unopened contacts survive actual save and reload")
	# Structural audit fixtures only, distinct from the construction proof above.
	for expected in OfficialNetworkAudit.target_data().cities.shanghai.cutoffNetwork.transferDefinitions:
		var fixture:={"cityId":"shanghai","transferConnections":[expected.duplicate(true)]}
		check(OfficialNetworkAudit.transfer_structure_errors(fixture,expected).is_empty(),"each independent exit-transfer definition matches")
		fixture.transferConnections[0].transferKind="interchange"
		check(not OfficialNetworkAudit.transfer_structure_errors(fixture,expected).is_empty(),"paid-area label cannot replace a sourced exit transfer")
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("SHANGHAI_PLANNED_PASSAGE_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
