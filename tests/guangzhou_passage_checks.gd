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
	var config:=CampaignSystem.city_config("guangzhou")
	var passage:Dictionary=config.chapters.filter(func(c:Dictionary):return c.id=="guangzhou-south-paid-passage-2024")[0]
	var cutoff:Dictionary=config.chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var prelude:=passage.duplicate(true);prelude.id="fixture-gz-south-line-fragments";prelude.lineGroups=[];prelude.requiredTransfers=[];prelude.operationType="dated_station_segment"
	prelude.requireOpen=true
	for group in cutoff.lineGroups:
		if not str(group.historicalLineId) in ["guangzhou-line2-2","guangzhou-line7-7","guangzhou-foshan-line2-18"]:continue
		for index in range(group.stationIds.size()):
			var reference:=WorldData.find_station(WorldData.city("guangzhou"),str(group.stationIds[index]))
			if str(reference.get("name",""))!="广州南站":continue
			var part:Dictionary=group.duplicate(true);part.stationIds=group.stationIds.slice(maxi(0,index-1),mini(group.stationIds.size(),index+2));part.taskId="fixture:"+str(group.historicalLineId);part.loop=false
			prelude.lineGroups.append(part);break
	CampaignSystem._catalog.cities.guangzhou.chapters.append(prelude)
	var world:=WorldData.new_world("guangzhou","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	check(str(preview.get("issue","")).is_empty(),"three independent line fragments preview")
	var committed:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(committed.get("ok",false)),"station and track prerequisites use the formal transaction")
	if not bool(committed.get("ok",false)):await _finish(app);return
	for group in Story.groups(world,true):check(bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),"prerequisite line confirms")
	world.storyState.chapterId=passage.id;world.storyState.stage="build";app._enter(world)
	var anchors:=Story.targets(world,true)
	check(anchors.size()==3 and anchors.all(func(target:Dictionary):return bool(target.get("built",false)) and bool(target.get("existingTransferAnchor",false))),"the passage map locates all three existing line bodies")
	check(app.station_button.disabled and app.track_button.disabled,"a pedestrian passage does not offer new rail construction")
	app._tool("station")
	check(app.tool=="select" and app.problem.contains("换乘"),"keyboard construction requests point to the real transfer action")
	var before:Dictionary={}
	for field in ["stations","trackEdges","trackNodes","routes"]:before[field]=world[field].duplicate(true)
	check(not bool(Story.evaluate(world).complete),"a transfer-only milestone cannot pass without its actual relations")
	check(not bool(Story.commit_chapter(world,int(world.revision)).get("ok",false)),"an empty rail target list cannot auto-complete the passage")
	check(Story.current_action(world).contains("换乘") and not Story.current_action(world).contains("相邻站端"),"next action explains pedestrian transfer work")
	for pairing in passage.requiredTransfers:
		var connection:Dictionary={"id":pairing.id,"name":pairing.name,"complexId":pairing.complexId,"lineIds":pairing.lineIds.duplicate(),"stationInstanceIds":pairing.stationInstanceIds.duplicate(),"source":pairing.source,"status":"active","precision":"schematic","effectiveDate":passage.date}
		check(bool(app._commit_transfer_connection(pairing,connection,int(world.revision)).get("ok",false)),"player explicitly establishes each separate line pairing")
	check(bool(Story.evaluate(world).complete),"both relations complete the actual passage milestone")
	app.history.undo()
	check(not bool(Story.evaluate(world).complete),"undoing one pedestrian link makes the milestone incomplete")
	app.history.redo()
	check(bool(Story.evaluate(world).complete),"redo restores the exact independent pair")
	var independent:=OfficialNetworkAudit.historical_chapter_errors(world,str(passage.id))
	check(independent.is_empty(),"independent paid-passage requirements match the built relations: "+JSON.stringify(independent))
	for field in before:check(world[field]==before[field],"pedestrian passage does not change "+str(field))
	check(bool(Story.commit_chapter(world,int(world.revision),Story.evaluate(world)).get("ok",false)),"the real passage chapter confirms after both relations exist")
	var saved:=SaveManager.save_world(world);var loaded:=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and OfficialNetworkAudit.historical_chapter_errors(loaded.world,str(passage.id)).is_empty(),"explicit passage relations survive save and reload")
	await _finish(app)
func _finish(app:Control) -> void:
	app.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("GUANGZHOU_PASSAGE_CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
