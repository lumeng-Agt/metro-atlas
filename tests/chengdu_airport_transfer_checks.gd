extends SceneTree
const App=preload("res://scripts/main.gd")
const Story=preload("res://scripts/story_session.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();var app:=App.new();root.add_child(app);await process_frame
	var cutoff:Dictionary=CampaignSystem.city_config("chengdu").chapters.filter(func(c:Dictionary):return str(c.get("chapterScope",""))=="cutoff_reconciliation")[0]
	var prelude:=cutoff.duplicate(true);prelude.id="fixture-cd-airport-three-lines";prelude.lineGroups=[];prelude.requiredTransfers=[];prelude.scopeCorrections=[];prelude.chapterScope="";prelude.eventOnly=false;prelude.requireOpen=true
	for group in cutoff.lineGroups:
		if not str(group.historicalLineId) in ["chengdu-line10-10","chengdu-line19-14","chengdu-line30-16"]:continue
		for index in range(group.stationIds.size()):
			var name:=str(group.get("stationNames",{}).get(group.stationIds[index],WorldData.find_station(WorldData.city("chengdu"),str(group.stationIds[index])).get("name","")))
			if not name in ["双流机场2航站楼","双流机场2航站楼东"]:continue
			var part:Dictionary=group.duplicate(true);part.stationIds=group.stationIds.slice(maxi(0,index-1),mini(group.stationIds.size(),index+2));part.taskId="fixture:"+str(group.historicalLineId);part.loop=false
			prelude.lineGroups.append(part);break
	CampaignSystem._catalog.cities.chengdu.chapters.append(prelude)
	var world:=WorldData.new_world("chengdu","campaign");world.storyState.chapterId=prelude.id;world.storyState.stage="build";world.storyState.tutorialEnabled=false;world.storyState.learnedTools=true;app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	check(str(preview.get("issue","")).is_empty(),"real airport station fragments preview through construction commands")
	var built:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	check(bool(built.get("ok",false)),"airport prerequisite geometry commits formally")
	if not bool(built.get("ok",false)):app.queue_free();await process_frame;quit(1);return
	for group in Story.groups(world,true):check(bool(Story.confirm_task(world,str(group.taskId),int(world.revision)).get("ok",false)),"each actual prerequisite line confirms separately")
	var contact:=prelude.duplicate(true);contact.id="fixture-cd-airport-contacts";contact.operationType="transfer_connection";contact.lineGroups=[]
	contact.requiredTransfers=cutoff.requiredTransfers.filter(func(t:Dictionary):return str(t.get("name","")) in ["双流机场2航站楼","双流机场2航站楼东"])
	check(contact.requiredTransfers.size()==3,"official airport guide has all three pairings, not only an indirect two-transfer chain")
	CampaignSystem._catalog.cities.chengdu.chapters.append(contact);world.storyState.chapterId=contact.id;app._enter(world)
	var geometry:Dictionary={}
	for key in ["stations","trackNodes","trackEdges","trackLinks","routes"]:geometry[key]=world.get(key,[]).duplicate(true)
	var airport_names:Array=world.stations.map(func(s:Dictionary):return str(s.name))
	check(airport_names.has("双流机场2航站楼") and airport_names.has("双流机场2航站楼东"),"out-of-gate interchange retains the two actual physical station names")
	for pair in contact.requiredTransfers:
		var connection:Dictionary={"id":pair.id,"name":pair.name,"complexId":pair.complexId,"lineIds":pair.lineIds.duplicate(),"stationInstanceIds":pair.stationInstanceIds.duplicate(),"status":"active","precision":"schematic","source":pair.source}
		if str(pair.get("transferKind",""))=="out_of_station":
			var forged:Dictionary=pair.duplicate(true);forged.transferKind="interchange"
			check(not bool(app._commit_transfer_connection(forged,connection,int(world.revision)).get("ok",false)),"caller cannot relabel an out-of-gate contact as an ordinary interchange")
		check(not bool(app._commit_transfer_connection(pair,connection,int(world.revision)-1).get("ok",false)),"stale airport preview cannot commit")
		var committed:Dictionary=app._commit_transfer_connection(pair,connection,int(world.revision))
		check(bool(committed.get("ok",false)),"actual separate station bodies explicitly establish their contact")
		check(not app.history.undo().is_empty() and not app._transfer_connected(pair),"cancelled by undo, a contact leaves the physical network alone")
		check(not app.history.redo().is_empty() and app._transfer_connected(pair),"redo restores the same explicit contact")
		if str(pair.get("transferKind",""))=="out_of_station":
			var stored:Dictionary=world.transferConnections.filter(func(t:Dictionary):return str(t.id)==str(pair.id))[0]
			stored.erase("transferKind")
			check(not app._transfer_connected(pair),"a legacy unclassified contact cannot falsely confirm an out-of-gate target")
			var checked:Dictionary=Story.evaluate(world)
			check(checked.issues.any(func(issue:Dictionary):return bool(issue.get("pendingConfirmation",false))),"legacy transfer type needs explicit confirmation in chapter evaluation too")
			var upgraded:Dictionary=app._commit_transfer_connection(pair,connection,int(world.revision))
			check(bool(upgraded.get("ok",false)) and app._transfer_connected(pair),"explicit confirmation upgrades contact metadata through the formal transaction: "+str(upgraded.get("error","")))
			check(not app.history.undo().is_empty() and not app._transfer_connected(pair),"undo restores the old unclassified contact")
			check(not app.history.redo().is_empty() and app._transfer_connected(pair),"redo restores the reviewed out-of-gate type")
	for key in geometry:check(world.get(key)==geometry[key],"pedestrian contact preserves actual "+key)
	check(world.transferConnections.filter(func(c:Dictionary):return str(c.get("transferKind",""))=="out_of_station").size()==2,"two out-of-gate contacts are stored distinctly from the paid-area 19/30 relation")
	var corrupt:=world.duplicate(true);corrupt.transferConnections[0].transferKind="shared_running"
	check(not SaveManager.validate(corrupt).is_empty(),"a shared-running label cannot be smuggled in as a walking contact type")
	var ten:Dictionary={};var thirty:Dictionary={}
	for station in world.stations:
		if station.stationLineId=="chengdu-line10-10" and station.name=="双流机场2航站楼":ten=station
		if station.stationLineId=="chengdu-line30-16" and station.name=="双流机场2航站楼东":thirty=station
	check(not ten.is_empty() and not thirty.is_empty() and not bool(TrackNetwork.shortest_station_path(str(ten.get("id","")),str(thirty.get("id","")),world,30.6).get("valid",false)),"trains cannot use the pedestrian out-of-gate contact")
	check(Story._minimum_route_transfers(world,str(ten.get("id","")),str(thirty.get("id","")),30.6)==1,"10 to 30 is one line change, not two via an invented ride on 19")
	var saved:Dictionary=SaveManager.save_world(world);var loaded:Dictionary=SaveManager.load_file(str(saved.get("path","")))
	check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)) and loaded.get("world",{}).get("transferConnections",[])==world.transferConnections,"physical names and contact classifications survive actual disk reload")
	app.queue_free();await process_frame
	print("CHENGDU_AIRPORT_TRANSFER_FIXTURE ",checks," FAILURES ",failures,"; real line fragments, not whole-city acceptance")
	quit(0 if failures==0 else 1)
