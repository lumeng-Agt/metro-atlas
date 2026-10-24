extends SceneTree

const Story = preload("res://scripts/story_session.gd")
const Catalog = preload("res://scripts/campaign_system.gd")
const App = preload("res://scripts/main.gd")
var app: Control
var failures := 0
var checkpoints := 0

func _trace(stage:String) -> void:
	if OS.get_environment("METRO_REPLAY_TRACE")=="1":print("REPLAY_TRACE ",str(Story.chapter(app.world).get("id",""))," ",stage)

func _initialize() -> void:
	call_deferred("_run")

func _fail(city:String,chapter:String,task:String,message:String) -> bool:
	print("REPLAY_FAIL city=",city," chapter=",chapter," task=",task," error=",message)
	failures += 1
	return false

func _checkpoint(city:String,chapter:String,task:String) -> bool:
	var before:Dictionary=JSON.parse_string(JSON.stringify(app.world))
	var saved:Dictionary=SaveManager.save_world(app.world)
	if not bool(saved.get("ok",false)):return _fail(city,chapter,task,"save: "+str(saved.get("error","")))
	var loaded:Dictionary=SaveManager.load_file(str(saved.path))
	if not bool(loaded.get("ok",false)):return _fail(city,chapter,task,"reload: "+str(loaded.get("error","")))
	for key in ["stations","stationComplexes","transferConnections","trackNodes","trackEdges","routes","serviceRanges","history","storyState","storyPlan"]:
		if before.get(key)!=loaded.world.get(key):return _fail(city,chapter,task,"roundtrip contents differ: "+key)
	app._enter(loaded.world)
	checkpoints+=1
	print("REPLAY_CHECKPOINT_OK ",city," ",chapter," ",task)
	return true

func _construct_chapter(city:String,chapter:Dictionary) -> bool:
	var id:=str(chapter.id)
	app._begin_chapter()
	var versions:Array=chapter.get("story",{}).get("planVersions",[])
	while not Story.plan_is_final(app.world):
		var revision_result:Dictionary=app._commit_plan_revision(int(app.world.storyPlan.get("planIndex",0))+1,int(app.world.revision))
		if not bool(revision_result.get("ok",false)):return _fail(city,id,"plan",str(revision_result.get("error","")))
	var groups:Array=Story.groups(app.world,true)
	if not groups.is_empty():
		_trace("assist-preview")
		var preview:Dictionary=app._assist_candidate()
		if not str(preview.get("issue","")).is_empty():return _fail(city,id,"preview",str(preview.issue))
		var applied:Dictionary=app._commit_assisted_construction(preview,int(app.world.revision))
		if not bool(applied.get("ok",false)):return _fail(city,id,"commit",str(applied.get("error","")))
		# Exercise the undo transaction once per chapter, then replay exactly it.
		if bool(applied.get("changed",false)):
			var constructed:Dictionary=JSON.parse_string(JSON.stringify(app.world))
			if app.history.undo().is_empty():return _fail(city,id,"undo","construction created no undo transaction")
			if app.history.redo().is_empty():return _fail(city,id,"redo","construction could not be restored")
			for key in ["stations","stationComplexes","trackNodes","trackEdges","storyPlan"]:
				if constructed.get(key)!=JSON.parse_string(JSON.stringify(app.world.get(key))):return _fail(city,id,"redo","geometry differs: "+key)
	_trace("evaluate-service")
	var checked:Dictionary=Story.evaluate(app.world)
	for proposal in checked.get("serviceTransitions",[]):
		if Story._has_service_range(app.world,str(proposal.id)):continue
		var transition:Dictionary=app._commit_service_transition(proposal,int(app.world.revision))
		if not bool(transition.get("ok",false)):return _fail(city,id,"service",str(transition.get("error","")))
	if not bool(chapter.get("requiresLineReorganization",false)):
		for i in range(groups.size()):
			var task:=Story.task_id(chapter,groups[i],i)
			if Story.task_confirmed(app.world,task):continue
			var result:Dictionary=Story.confirm_task(app.world,task,int(app.world.revision))
			if not bool(result.get("ok",false)):return _fail(city,id,task,JSON.stringify(result))
			if not _checkpoint(city,id,task):return false
	_trace("evaluate-reorganization")
	checked=Story.evaluate(app.world)
	if bool(chapter.get("requiresLineReorganization",false)):
		var reorganized:Dictionary=app._commit_line_reorganization(int(app.world.revision))
		if not bool(reorganized.get("ok",false)):return _fail(city,id,"reorganization",JSON.stringify(reorganized))
		checked=Story.evaluate(app.world)
	for transfer in checked.get("requiredTransfers",[]):
		if app._transfer_connected(transfer):continue
		var connection:Dictionary={"id":str(transfer.id),"name":str(transfer.get("name","换乘")),"complexId":str(transfer.get("complexId","")),"stationInstanceIds":transfer.get("stationInstanceIds",[]).duplicate(),"lineIds":transfer.get("lineIds",[]).duplicate(),"status":"active","precision":str(transfer.get("precision","schematic")),"source":str(transfer.get("source","")),"effectiveDate":str(chapter.get("date",""))}
		var linked:Dictionary=app._commit_transfer_connection(transfer,connection,int(app.world.revision))
		if not bool(linked.get("ok",false)):return _fail(city,id,str(transfer.id),str(linked.get("error","")))
	if bool(chapter.get("requiresLineReorganization",false)):
		for i in range(groups.size()):
			var task:=Story.task_id(chapter,groups[i],i)
			if Story.task_confirmed(app.world,task):continue
			var result:Dictionary=Story.confirm_task(app.world,task,int(app.world.revision))
			if not bool(result.get("ok",false)):return _fail(city,id,task,JSON.stringify(result))
			if not _checkpoint(city,id,task):return false
	_trace("evaluate-chapter")
	var evaluated:Dictionary=Story.evaluate(app.world)
	_trace("commit-chapter")
	var completed:Dictionary=Story.commit_chapter(app.world,int(app.world.revision),evaluated)
	if not bool(completed.get("ok",false)):return _fail(city,id,"chapter",JSON.stringify(completed))
	_trace("official-audit")
	var official_errors:=OfficialNetworkAudit.current_project_errors(app.world,chapter.get("projectIds",[]))
	if str(chapter.get("chapterScope",""))!="cutoff_reconciliation":
		var backfill:=false
		if OS.get_environment("METRO_REPLAY_RESUME")=="1":
			for milestone in app.world.get("storyState",{}).get("milestones",[]):
				if str(milestone.get("date",""))>str(chapter.get("date","")) and not milestone.get("planningDiff",{}).get("fields",{}).get("routes",{}).get("items",{}).is_empty():backfill=true;break
		if backfill:print("REPLAY_BACKFILL_SCOPE_ONLY ",city," ",id," later saved construction retained; not a fresh period-exclusive check")
		official_errors.append_array(OfficialNetworkAudit.historical_chapter_errors(app.world,id,backfill))
	if str(chapter.get("chapterScope",""))=="cutoff_reconciliation":
		var targets:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OfficialNetworkAudit.TARGET_PATH))
		if not targets.get("cities",{}).get(city,{}).get("cutoffNetwork",{}).is_empty():official_errors.append_array(OfficialNetworkAudit.cutoff_errors(app.world))
	if not official_errors.is_empty():return _fail(city,id,"official_target",JSON.stringify(official_errors))
	if not _checkpoint(city,id,"milestone"):return false
	Story.next_chapter(app.world)
	return true

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():push_error("isolated --data-dir required");quit(2);return
	WorldData.load_assets()
	var catalog_errors:=Catalog.validate_catalog(WorldData.cities())
	catalog_errors.append_array(Catalog.validate_network_baseline(WorldData.cities()))
	if not catalog_errors.is_empty():
		_fail("catalog","startup","references",JSON.stringify(catalog_errors));quit(1);return
	print("REPLAY_CONTENT_VERSION ",Catalog.content_version()," REVISION ",Catalog.content_revision())
	app=App.new();root.add_child(app);await process_frame
	var city_ids:Array=["shenzhen","shanghai","beijing","guangzhou","chengdu"]
	var selected:=OS.get_environment("METRO_REPLAY_CITY")
	if not selected.is_empty():city_ids=[selected]
	var include_future:=OS.get_environment("METRO_REPLAY_FUTURE")=="1"
	var limit:=int(OS.get_environment("METRO_REPLAY_STOP_AFTER_INDEX")) if not OS.get_environment("METRO_REPLAY_STOP_AFTER_INDEX").is_empty() else -1
	for city in city_ids:
		if OS.get_environment("METRO_REPLAY_RESUME")=="1":
			var loaded:Dictionary=SaveManager.load_last_game()
			if not bool(loaded.get("ok",false)) or str(loaded.world.get("cityId",""))!=str(city):_fail(str(city),"load","resume","checkpoint unavailable");continue
			app._enter(loaded.world)
			if str(app.world.storyState.get("stage",""))=="outcome":Story.next_chapter(app.world)
		else:
			app._new_game(str(city),false)
			# Finish the initial queued save before synchronous replay checkpoints.
			while app.saves_in_flight>0:await process_frame
		var visited:Dictionary={}
		var index:=0
		while not Story.chapter(app.world).is_empty():
			if str(app.world.storyState.get("phase","history"))=="future" and not include_future:break
			var chapter:Dictionary=Story.chapter(app.world)
			var id:=str(chapter.id)
			if visited.has(id):_fail(str(city),id,"navigation","chapter did not advance");break
			visited[id]=true
			print("REPLAY_CHAPTER_START ",city," ",index," ",id)
			if not _construct_chapter(str(city),chapter):break
			print("REPLAY_CHAPTER_OK ",city," ",id," stations=",app.world.stations.size()," edges=",app.world.trackEdges.size())
			if limit>=0 and index>=limit:break
			index+=1
		print("REPLAY_CITY_DONE ",city," visited=",visited.size()," phase=",app.world.storyState.phase)
	print("REPLAY_FAILURES ",failures," checkpoints=",checkpoints)
	quit(0 if failures==0 else 1)
