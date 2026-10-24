extends SceneTree

const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
var failures:Array[String]=[]
var checks:=0

func _initialize() -> void:call_deferred("_run")

func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var app:=App.new();root.add_child(app);await process_frame
	# A focused project fixture, not evidence of cumulative city completion.
	var world:=WorldData.new_world("shenzhen","campaign")
	world.storyState.phase="future";world.storyState.chapterId="sz-line15-build";world.storyState.stage="build"
	app._enter(world)
	var preview:Dictionary=app._assist_candidate()
	var stale:Dictionary=app._commit_assisted_construction(preview,int(world.revision)-1)
	_check(not bool(stale.get("ok",false)) and world.stations.is_empty(),"stale construction cannot change the world")
	var applied:Dictionary=app._commit_assisted_construction(preview,int(world.revision))
	_check(bool(applied.get("ok",false)),"24-station circuit uses formal assisted commit")
	var task:="project:sz-line15-build"
	var confirmed:=Story.confirm_task(world,task,int(world.revision))
	_check(bool(confirmed.get("ok",false)),"ring task confirms after real construction")
	var official:=OfficialNetworkAudit.current_project_errors(world,["sz-line15"])
	_check(official.is_empty(),"built ring matches independently transcribed official order: "+JSON.stringify(official))
	var route:Dictionary=WorldData.find_route(world,"historical_shenzhen-line15-15")
	_check(route.stationOrder.size()==25 and route.stationOrder.front()==route.stationOrder.back(),"24 unique stops require an actual closing segment")
	var broken:=world.duplicate(true)
	var closing_id:=str(route.directions[0].edgePathsBySegment[-1][0].id)
	broken.trackEdges=broken.trackEdges.filter(func(edge:Dictionary):return str(edge.id)!=closing_id)
	_check(not OfficialNetworkAudit.current_project_errors(broken,["sz-line15"]).is_empty(),"missing ring edge fails actual-world audit")
	var missing:=world.duplicate(true);missing.stations[3].name="错误站名"
	_check(not OfficialNetworkAudit.current_project_errors(missing,["sz-line15"]).is_empty(),"wrong intermediate stop fails independent order")
	var wrong_body:=world.duplicate(true);wrong_body.stations[3].stationLineId="another-line"
	_check(not OfficialNetworkAudit.current_project_errors(wrong_body,["sz-line15"]).is_empty(),"another line's physical platform cannot stand in")
	var retired_world:=world.duplicate(true);retired_world.routes[0].retired=true
	_check(not OfficialNetworkAudit.current_project_errors(retired_world,["sz-line15"]).is_empty(),"a retired correct route cannot certify the current project")
	var closed_world:=world.duplicate(true);closed_world.routes[0].open=false
	var target_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OfficialNetworkAudit.TARGET_PATH))
	var ring_requirement:Dictionary={}
	for target in target_data.cities.shenzhen.projects:
		if target.id=="sz-line15":ring_requirement=target.duplicate(true);break
	_check(OfficialNetworkAudit.current_project_errors(closed_world,["sz-line15"]).is_empty(),"an unopened planned path can certify construction without inventing historical opening")
	ring_requirement["constructionOnly"]=false
	_check(not OfficialNetworkAudit.project_errors(closed_world,ring_requirement).is_empty(),"the same unopened path cannot certify historical operation")
	var built_section:=world.duplicate(true);built_section.routes[0].directions[0].serviceStatusBySegment[0]="built"
	_check(not OfficialNetworkAudit.project_errors(built_section,ring_requirement).is_empty(),"one built-only segment fails historical opening even when another segment keeps the line open")
	_check(Story.task_confirmed(world,task),"fresh scope fingerprint confirms")
	var final_records:=CampaignSystem.chapter_task_records("shenzhen","sz-line15-build")
	_check(str(final_records.get(task,{}).get("scopeFingerprint",""))==Story.task_scope_fingerprint(world,task),"chapter completion preserves the normalized task scope fingerprint, including a ring closure")
	world.storyState.chapterTaskProgress["sz-line15-build"].tasks[task].scopeFingerprint="obsolete"
	_check(not Story.task_confirmed(world,task),"old task completion cannot cover changed construction scope")
	var legacy:=WorldData.new_world("beijing","campaign")
	legacy.storyState.phase="future_gap";legacy.storyState.chapterId="";legacy.storyState.completedChapterIds=["bj-m101-phase1-build"]
	legacy.storyState.scopeContentRevision="old-content"
	legacy.storyState.chapterTaskProgress={"bj-m101-phase1-build":{"status":"confirmed","scopeRevision":"old","tasks":{}}}
	var before:=JSON.stringify(legacy.stations)
	_check(bool(SaveManager.save_world(legacy).get("ok",false)),"legacy scope fixture saves")
	var loaded:=SaveManager.load_file(SaveManager.save_path(str(legacy.gameId)))
	_check(bool(loaded.get("ok",false)),"scope upgrade can load")
	if bool(loaded.get("ok",false)):
		_check(not loaded.world.storyState.completedChapterIds.has("bj-m101-phase1-build"),"four-point legacy completion does not skip fourteen-station scope")
		_check(JSON.stringify(loaded.world.stations)==before,"scope upgrade preserves physical planning")
		_check(loaded.world.storyState.get("legacyTaskProgress",{}).has("bj-m101-phase1-build"),"original completion record remains archived")
		var originals:=DirAccess.open(SaveManager.root_path().path_join("originals"))
		_check(originals!=null and not originals.get_files().is_empty(),"content migration preserves original file before loading")
	_check(not CampaignSystem.delivery_eligibility("shenzhen").ok,"unreviewed remaining city content blocks complete release")
	var rebinding:Dictionary={"cityId":"shenzhen","stations":[],"routes":[]}
	for suffix in ["old","new"]:
		for name in ["a","b","c"]:rebinding.stations.append({"id":name+suffix,"stationComplexId":name})
	var old_route:Dictionary={"id":"line","historicalLineId":"line","chapterId":"same-task","stationOrder":["aold","bold","cold"],"directions":[{"stationIds":["aold","bold","cold"],"edgePathsBySegment":[[],[]]}]}
	rebinding.routes.append(old_route)
	var corrected:Dictionary={"id":"line","historicalLineId":"line","chapterId":"same-task","stationOrder":["anew","bnew","cnew"],"directions":[{"stationIds":["anew","bnew","cnew"],"edgePathsBySegment":[[],[]]}]}
	Story._store_historical_route(rebinding,corrected)
	_check(rebinding.routes[0].directions.size()==1 and rebinding.routes[0].stationOrder==corrected.stationOrder,"same-task physical rebinding replaces obsolete service instead of retaining a ghost branch")
	var correction_world:=WorldData.new_world("shenzhen","campaign")
	correction_world.storyState.phase="future";correction_world.storyState.chapterId="sz-line32-phase1-build";correction_world.storyState.stage="build"
	var old_transfer:Dictionary={"id":"future-transfer-sz32-xichong","name":"溪涌","lineIds":["shenzhen-line8-9","shenzhen-line2-2","shenzhen-line32-32"],"stationInstanceIds":["shenzhen-s291","shenzhen-s291__line2-2","shenzhen-s291__line32-32"],"status":"active"}
	correction_world.transferConnections=[old_transfer.duplicate(true),{"id":"unrelated","status":"active"}]
	var corrections:=Story.scope_correction_preview(correction_world,"project:sz-line32-phase1-build")
	_check(corrections.ok and corrections.changes.size()==1,"obsolete transfer has an explicit correction preview")
	_check(correction_world.transferConnections[0].status=="active","preview does not change the original relationship")
	var corrected_world:=correction_world.duplicate(true)
	Story._apply_scope_corrections(corrected_world,corrections)
	_check(corrected_world.transferConnections[0].status=="superseded" and corrected_world.transferConnections[1].status=="active","confirmed correction archives only the specified old relation")
	correction_world.transferConnections[0].lineIds=["player-edited"]
	_check(not Story.scope_correction_preview(correction_world,"project:sz-line32-phase1-build").ok,"player-edited old relationship is a conflict rather than silently overwritten")
	var replacement_world:Dictionary={"cityId":"shenzhen","stations":[],"routes":[old_route.duplicate(true),{"id":"unrelated-line","stationOrder":["keep"]}]}
	var replacement:=corrected.duplicate(true);replacement.chapterId="later-official-correction";replacement.replaceExistingService=true
	Story._store_historical_route(replacement_world,replacement)
	_check(replacement_world.routes[0].directions.size()==1 and replacement_world.routes[0].stationOrder==replacement.stationOrder,"explicit official scope correction replaces obsolete branches")
	_check(replacement_world.routes[1].stationOrder==["keep"],"scope replacement does not touch unrelated services")
	var rebinding_world:=WorldData.new_world("shenzhen","campaign")
	rebinding_world.storyState.phase="history";rebinding_world.storyState.chapterId="shenzhen-network-reconciliation-2026-10-01";rebinding_world.storyState.stage="build"
	rebinding_world.transferConnections=[{"id":"future-transfer-laojie-line3","name":"老街","lineIds":["shenzhen-line3-3","shenzhen-line17-17"],"stationInstanceIds":["shenzhen-s3","shenzhen-s3__line17-17"],"status":"active"}]
	var rebind:=Story.scope_correction_preview(rebinding_world,"route:shenzhen-r3")
	_check(rebind.ok and rebind.changes.size()==1,"physical platform correction is included in explicit task preview")
	_check(rebinding_world.transferConnections[0].stationInstanceIds[0]=="shenzhen-s3","platform correction does not run during preview")
	Story._apply_scope_corrections(rebinding_world,rebind)
	_check(rebinding_world.transferConnections[0].stationInstanceIds[0]=="shenzhen-s3__line3-3" and rebinding_world.transferConnections[0].status=="active","confirm rebinds the specified platform without destroying transfer identity")
	var repeated:=Story.scope_correction_preview(rebinding_world,"route:shenzhen-r3")
	_check(repeated.ok and repeated.changes.is_empty(),"a correctly rebound transfer is idempotent when another line in the chapter is checked")
	var extension_world:=WorldData.new_world("shanghai","campaign")
	extension_world.storyState.chapterId="shanghai-network-reconciliation-2026-10-01"
	extension_world.storyState.completedChapterIds=["sh-line12-west-build"]
	extension_world.storyState.chapterTaskProgress={"sh-line12-west-build":{"tasks":{"earlier":{"status":"confirmed"}}}}
	extension_world.stations=[{"id":"physical-track-remains"}]
	extension_world.routes=[{"id":"old-service","historicalLineId":"shanghai-line12-12","stationOrder":["old"]}]
	var extension_notice:=Story.scope_correction_preview(extension_world,"route:shanghai-r12")
	_check(extension_notice.ok and extension_notice.changes.any(func(change:Dictionary):return str(change.id)=="future-service-recheck:sh-line12-west-build"),"cutoff correction explains why an already-built future extension needs service reconfirmation")
	_check(extension_world.storyState.completedChapterIds.has("sh-line12-west-build"),"preview cannot revoke a future completion")
	Story._store_historical_route(extension_world,{"id":"corrected-service","historicalLineId":"shanghai-line12-12","replaceExistingService":true,"stationOrder":["correct"]})
	_check(not extension_world.storyState.completedChapterIds.has("sh-line12-west-build") and extension_world.storyState.legacyTaskProgress.has("sh-line12-west-build"),"confirmed cutoff replacement retains the old completion evidence and reopens only its future service")
	_check(extension_world.stations.size()==1 and extension_world.stations[0].id=="physical-track-remains","service reconfirmation preserves already-built physical objects")
	_check(extension_world.storyState.serviceReconfirmationIds==["sh-line12-west-build"],"service reconfirmation has a stable pending project identity")
	var branch_world:Dictionary={"stations":[{"id":"a","name":"A"},{"id":"b","name":"B"},{"id":"c","name":"C"},{"id":"d","name":"D"}],"routes":[{"historicalLineId":"branch-line","directions":[{"stationIds":["a","b","c"]},{"stationIds":["a","b","d"]}]}]}
	var branches:Dictionary={"groups":[{"id":"one","historicalLineId":"branch-line","stationNames":["A","B","C"]},{"id":"two","historicalLineId":"branch-line","stationNames":["A","B","D"]}]}
	_check(OfficialNetworkAudit.service_shape_errors(branch_world,branches).is_empty(),"independent branch orders accept two physical paths sharing a trunk")
	branch_world.routes[0].directions.append({"stationIds":["a","c"]})
	_check(not OfficialNetworkAudit.service_shape_errors(branch_world,branches).is_empty(),"an extra ghost branch is rejected even if every stop name is documented")
	branch_world.routes[0].directions=[{"stationIds":["a","b","a"]}]
	var ring_shape:Dictionary={"groups":[{"id":"branch-line","stationNames":["A","B"],"loop":true}]}
	_check(OfficialNetworkAudit.service_shape_errors(branch_world,ring_shape).is_empty(),"a documented ring repeats its departure stop exactly once for closure")
	branch_world.routes[0].directions[0].stationIds=["a","b","b","a"]
	_check(not OfficialNetworkAudit.service_shape_errors(branch_world,ring_shape).is_empty(),"a duplicate middle platform is not legitimized by ring closure")
	var opposite:=Story._merge_route_directions({"stationIds":["A","B"],"edgePathsBySegment":[[{"id":"AB","forward":true}]]},{"stationIds":["A","C","D"],"edgePathsBySegment":[[{"id":"AC","forward":true}],[{"id":"CD","forward":true}]]})
	_check(not opposite.is_empty() and opposite.direction.stationIds==["D","C","A","B"],"oppositely authored extensions join at a single shared endpoint")
	_check(opposite.direction.edgePathsBySegment[0][0]=={"id":"CD","forward":false} and opposite.direction.edgePathsBySegment[1][0]=={"id":"AC","forward":false},"reversing an extension also reverses segment order and every directed edge")
	var real_fork:=Story._merge_route_directions({"stationIds":["A","B","C"],"edgePathsBySegment":[[],[]]},{"stationIds":["A","B","D"],"edgePathsBySegment":[[],[]]})
	_check(real_fork.is_empty(),"a shared trunk remains two branches, never a fake route traversing it twice")
	var reconfirmed_opposite:=Story._merge_route_directions({"stationIds":["D","C","A","B"],"edgePathsBySegment":[[{"id":"CD","forward":false}],[{"id":"AC","forward":false}],[{"id":"AB","forward":true}]]},{"stationIds":["A","C","D"],"edgePathsBySegment":[[{"id":"AC","forward":true}],[{"id":"CD","forward":true}]]})
	_check(not reconfirmed_opposite.is_empty() and reconfirmed_opposite.direction.stationIds==["D","C","A","B"] and reconfirmed_opposite.direction.edgePathsBySegment.size()==3,"reconfirming an already-contained reverse extension cannot double back over its stations")
	var corrected_branch:=WorldData.new_world("shanghai","campaign")
	corrected_branch.storyState.chapterId="shanghai-network-reconciliation-2026-10-01"
	var tenth:Array=Story.groups(corrected_branch,true).filter(func(group:Dictionary):return str(group.get("historicalLineId",""))=="shanghai-line10-10")
	var first_group:Dictionary=tenth[0];var second_group:Dictionary=tenth[1]
	var physical:Dictionary={};var older_directions:Array=[]
	for group in [first_group,second_group]:
		var ids:Array=[]
		for id in group.stationIds:
			var instance:=Story.station_instance_id(group,str(id));var actual:="physical_"+instance
			ids.append(actual)
			if not physical.has(instance):corrected_branch.stations.append({"id":actual,"stationInstanceId":instance,"stationComplexId":str(id)})
			physical[instance]=true
		var paths:Array=[]
		for i in range(ids.size()-1):paths.append([])
		older_directions.append({"id":str(group.taskId),"stationIds":ids,"edgePathsBySegment":paths})
	corrected_branch.routes=[{"id":"old10","historicalLineId":"shanghai-line10-10","chapterId":corrected_branch.storyState.chapterId,"directions":older_directions+[{'stationIds':['ghost'],'edgePathsBySegment':[]}]}]
	corrected_branch.storyState.chapterTaskProgress={str(corrected_branch.storyState.chapterId):{"tasks":{str(second_group.taskId):{"status":"confirmed","scopeFingerprint":Story.task_scope_fingerprint(corrected_branch,str(second_group.taskId))}}}}
	var first_service:Dictionary={"id":"old10","historicalLineId":"shanghai-line10-10","chapterId":corrected_branch.storyState.chapterId,"stationOrder":older_directions[0].stationIds,"directions":[older_directions[0]],"replaceExistingService":true}
	Story._store_historical_route(corrected_branch,first_service)
	_check(corrected_branch.routes[0].directions.size()==2 and not corrected_branch.routes[0].directions.any(func(direction:Dictionary):return direction.stationIds.has("ghost")),"cutoff replacement preserves an already-confirmed sibling arm and removes an undocumented ghost")
	corrected_branch.storyState.legacyTaskProgress={str(corrected_branch.storyState.chapterId):{}}
	corrected_branch.storyState.milestones=[{"chapterId":corrected_branch.storyState.chapterId,"planningDiff":{"fields":{"routes":{"items":{"old10":{"after":corrected_branch.routes[0].duplicate(true),"before":{"id":"old10","historicalLineId":"shanghai-line10-10","stationOrder":["ghost"],"directions":[{"stationIds":["ghost"],"edgePathsBySegment":[]}]}}}}}}}]
	Story._store_historical_route(corrected_branch,{"id":"old10","historicalLineId":"shanghai-line10-10","chapterId":corrected_branch.storyState.chapterId,"stationOrder":older_directions[1].stationIds,"directions":[older_directions[1]]})
	_check(corrected_branch.routes[0].directions.size()==2 and not corrected_branch.routes[0].directions.any(func(direction:Dictionary):return direction.stationIds.has("ghost")),"chapter confirmation cannot rewind a reconfirmed branch to a stale milestone snapshot")
	var old_branch:=WorldData.new_world("guangzhou","campaign")
	old_branch.storyState.phase="future";old_branch.storyState.chapterId="gz-line8-north-branch-build"
	var branch_group:Dictionary=Story.groups(old_branch,true)[0]
	var old_branch_ids:Array=[]
	for id in branch_group.stationIds:
		var instance:=Story.station_instance_id(branch_group,str(id));var actual:="old_"+instance
		old_branch_ids.append(actual)
		old_branch.stations.append({"id":actual,"stationInstanceId":instance,"stationLineId":"guangzhou-line8-8","latlng":[23.2,113.2],"heading":27.0})
	old_branch.routes=[{"id":"main8","historicalLineId":"guangzhou-line8-8","directions":[{"stationIds":["base-A","base-B"],"edgePathsBySegment":[[]]},{"stationIds":old_branch_ids.duplicate(),"edgePathsBySegment":[]}]}]
	var physical_before:Array=old_branch.stations.map(func(station:Dictionary):return [station.id,station.latlng.duplicate(),station.heading])
	var split_notice:=Story.scope_correction_preview(old_branch,str(branch_group.taskId))
	_check(split_notice.ok and split_notice.changes.any(func(change:Dictionary):return str(change.get("kind",""))=="archive_service_direction"),"the old wrongly attached branch has an explicit service-identity correction preview")
	Story._apply_scope_corrections(old_branch,split_notice)
	_check(old_branch.routes[0].directions.size()==1 and old_branch.routes[0].directions[0].stationIds==["base-A","base-B"] and old_branch.routes[0].legacyDirections.size()==1,"branch correction archives only the matching old path and preserves the main line")
	_check(old_branch.stations.all(func(station:Dictionary):return station.stationLineId=="guangzhou-line24-planned") and old_branch.stations.map(func(station:Dictionary):return [station.id,station.latlng,station.heading])==physical_before,"line-identity correction changes ownership without moving or duplicating any station body")
	_check(Story.scope_correction_preview(old_branch,str(branch_group.taskId)).changes.is_empty(),"the independent-branch correction is idempotent")
	old_branch.routes[0].directions.append({"stationIds":old_branch_ids.slice(1),"edgePathsBySegment":[]})
	_check(not Story.scope_correction_preview(old_branch,str(branch_group.taskId)).ok,"an edited old branch is a conflict, rather than a direction to delete by guesswork")
	var suffix_world:=WorldData.new_world("shenzhen","campaign")
	suffix_world.storyState.phase="future";suffix_world.storyState.chapterId="sz-line20-phase2-build"
	var known_prefix:Array=["shenzhen-s306","shenzhen-s307__line20-17","shenzhen-s308__line20-17","shenzhen-s309","shenzhen-s194__line20-17"]
	var obsolete_ids:Array=known_prefix+["shenzhen-f20-futianhuizhan"]
	for instance in obsolete_ids:suffix_world.stations.append({"id":instance,"stationInstanceId":instance})
	var obsolete_direction:Dictionary={"stationIds":obsolete_ids.duplicate(),"edgePathsBySegment":[[],[],[],[],[]],"serviceStatusBySegment":["open","open","open","open","built"]}
	suffix_world.routes=[{"id":"old20","historicalLineId":"shenzhen-line20-17","open":true,"directions":[obsolete_direction]}]
	var suffix_preview:=Story.scope_correction_preview(suffix_world,"project:sz-line20-phase2-build")
	_check(suffix_preview.ok and suffix_preview.changes.size()==1 and suffix_preview.changes[0].retainedDirection.stationIds==known_prefix,"old erroneous extension correction explicitly retains its documented phase-1 prefix")
	Story._apply_scope_corrections(suffix_world,suffix_preview)
	_check(suffix_world.routes[0].directions[0].stationIds==known_prefix and suffix_world.routes[0].directions[0].serviceStatusBySegment==["open","open","open","open"],"trimming an obsolete suffix preserves the operating segment states and archives the original route")
	_check(suffix_world.stations.size()==6 and suffix_world.routes[0].legacyDirections.size()==1 and Story.scope_correction_preview(suffix_world,"").changes.is_empty(),"the correction preserves physical stations and is idempotent")
	suffix_world.routes[0].directions=[Story._reverse_service_direction(obsolete_direction)]
	var reverse_suffix:=Story.scope_correction_preview(suffix_world,"")
	_check(reverse_suffix.ok and reverse_suffix.changes[0].retainedDirection.stationIds==known_prefix,"reverse-authored obsolete extensions retain the same ordered prefix")
	suffix_world.routes[0].directions[0].stationIds[1]="player-changed-body"
	_check(not Story.scope_correction_preview(suffix_world,"").ok,"a player-edited obsolete service is not silently trimmed")
	suffix_world.routes[0].directions=[obsolete_direction.duplicate(true),{"stationIds":[known_prefix.back(),"correct-extension"],"edgePathsBySegment":[[]],"serviceStatusBySegment":["built"]}]
	var joint_preview:=Story.scope_correction_preview(suffix_world,"")
	Story._apply_scope_corrections(suffix_world,joint_preview)
	_check(suffix_world.routes[0].directions.size()==1 and suffix_world.routes[0].stationOrder==known_prefix+["correct-extension"],"trimming the wrong tail rejoins an already-built corrected extension at the actual shared endpoint")
	_check(suffix_world.routes[0].directions[0].serviceStatusBySegment==["open","open","open","open","built"],"rejoining a corrected extension does not open its planning segment")
	var missing_revision:Dictionary={"lineGroups":[{"stationIds":["A","B"]}]}
	var first_revision:=SaveManager._chapter_scope_revision(missing_revision)
	_check(not first_revision.is_empty(),"a missing optional scope revision cannot skip old-save content revalidation")
	missing_revision.lineGroups[0].stationIds.append("C")
	_check(SaveManager._chapter_scope_revision(missing_revision)!=first_revision,"adding a target changes the fallback scope revision")
	var collision_rules=load("res://scripts/story_construction.gd").new()
	collision_rules.active_city_id="guangzhou"
	var east_old:Dictionary={"id":"old-east","stationComplexId":"guangzhou-s342","stationInstanceId":"old-line11","latlng":[23.1552,113.3197],"heading":90.0,"lengthM":120.0,"widthM":20.0}
	var east_new:=east_old.duplicate(true);east_new.id="new-east";east_new.stationInstanceId="new-line18";east_new.stationComplexId="guangzhou-s177"
	_check(not collision_rules._station_overlaps_in(east_new,[east_old]),"documented complex aliases allow independent interchange bodies without moving the old structure")
	east_new.stationComplexId="unrelated-place"
	_check(collision_rules._station_overlaps_in(east_new,[east_old]),"nearby unrelated station bodies still conflict")
	var pending_north:=WorldData.new_world("chengdu","campaign")
	pending_north.storyState.chapterId="chengdu-network-reconciliation-2026-10-01"
	pending_north.transferConnections=[{"id":"future-transfer-nijiaqiao-line8","lineIds":["chengdu-line8-8","chengdu-line18-13"],"stationInstanceIds":["chengdu-s274","chengdu-s274__line18-18"],"status":"active"}]
	var old_pair_notice:=Story.scope_correction_preview(pending_north,"route:chengdu-r13")
	_check(old_pair_notice.ok and old_pair_notice.changes.size()==1,"known old shared-body pairing is explicitly archived before future service reconstruction")
	pending_north.transferConnections[0].stationInstanceIds[0]="chengdu-s274__line8-8"
	_check(Story.scope_correction_preview(pending_north,"route:chengdu-r13").ok,"the separately repaired old platform pairing is also recognized")
	pending_north.transferConnections[0].stationInstanceIds[0]="player-edited-platform"
	_check(not Story.scope_correction_preview(pending_north,"route:chengdu-r13").ok,"unknown player-edited pairing is not archived by the known-version alternatives")
	var phased_branch:=WorldData.new_world("guangzhou","campaign")
	phased_branch.storyState.chapterId="guangzhou-network-reconciliation-2026-10-01"
	var branch_correction:Dictionary={}
	for correction in Story.chapter(phased_branch).get("scopeCorrections",[]):
		if not str(correction.get("restoreAfterTaskId","")).is_empty():branch_correction=correction;break
	_check(not branch_correction.is_empty(),"branch replacement documents its temporary transfer boundary")
	if not branch_correction.is_empty():
		phased_branch.transferConnections=[{"id":branch_correction.transferId,"lineIds":branch_correction.oldLineIds.duplicate(),"stationInstanceIds":branch_correction.oldStationInstanceIds.duplicate(),"status":"active"}]
		var phase_preview:=Story.scope_correction_preview(phased_branch,str(branch_correction.taskId))
		_check(phase_preview.ok and phase_preview.changes.size()==1,"first path temporarily archives only its documented unavailable branch connection")
		var restored_task:=str(branch_correction.restoreAfterTaskId)
		phased_branch.storyState.chapterTaskProgress={str(Story.chapter(phased_branch).id):{"tasks":{restored_task:{"status":"confirmed","scopeFingerprint":Story.task_scope_fingerprint(phased_branch,restored_task)}}}}
		_check(Story.scope_correction_preview(phased_branch,"").changes.is_empty(),"chapter confirmation does not archive a transfer restored after the second path")
	var dependent_plan:=WorldData.new_world("guangzhou","campaign")
	dependent_plan.storyState.chapterId="guangzhou-network-reconciliation-2026-10-01"
	dependent_plan.storyState.completedChapterIds=["gz-line13-phase2-west-build"]
	Story._recheck_future_services_after_cutoff_correction(dependent_plan,{"historicalLineId":"guangzhou-line12-12"})
	_check(not dependent_plan.storyState.completedChapterIds.has("gz-line13-phase2-west-build"),"a changed interchange dependency requires project reconfirmation even when its own track line is unchanged")
	var operating:Dictionary={"open":true,"serviceStatus":"open","directions":[{"stationIds":["A","B"],"edgePathsBySegment":[[]],"serviceStatusBySegment":["open"]}]}
	var planned:Dictionary={"open":false,"serviceStatus":"built","directions":[{"stationIds":["B","C"],"edgePathsBySegment":[[]],"serviceStatusBySegment":["built"]}]}
	var mixed_path:=Story._merge_historical_route(operating,planned)
	_check(mixed_path.open and mixed_path.serviceStatus=="mixed" and mixed_path.directions[0].serviceStatusBySegment==["open","built"],"adding a built-only extension preserves the actual operating segment")
	var reopened:=Story._merge_historical_route(mixed_path,{"open":true,"serviceStatus":"trial","directions":[{"stationIds":["B","C"],"edgePathsBySegment":[[]],"serviceStatusBySegment":["trial"]}]})
	_check(reopened.open and reopened.directions[0].serviceStatusBySegment==["open","trial"],"opening a later section changes only that section's service status")
	var status_world:Dictionary={"routes":[mixed_path.duplicate(true)]}
	status_world.routes[0]["historicalLineId"]="L"
	var planned_status:=planned.duplicate(true);planned_status["historicalLineId"]="L"
	_check(SaveManager._planning_statuses_match(status_world,[planned_status]),"old-save status check accepts a planned extension beside an open historical segment")
	status_world.routes[0].directions[0].serviceStatusBySegment=["open","open"]
	_check(not SaveManager._planning_statuses_match(status_world,[planned_status]),"geometry alone does not retain an incorrect future opening completion")
	status_world.routes[0].directions[0].serviceStatusBySegment=[]
	_check(not SaveManager._planning_statuses_match(status_world,[planned_status]),"missing old segment statuses require explicit reconfirmation")
	var phase_fixture:=WorldData.new_world("chengdu","campaign")
	for chapter_id in ["cd-line1-2010","cd-line1-2015"]:
		phase_fixture.storyState.phase="history";phase_fixture.storyState.chapterId=chapter_id;phase_fixture.storyState.stage="build"
		app._enter(phase_fixture)
		var phase_draft:Dictionary=app._assist_candidate()
		_check(bool(app._commit_assisted_construction(phase_draft,int(phase_fixture.revision)).get("ok",false)),"period fixture uses the formal station-and-track commit")
		var phase_groups:=Story.groups(phase_fixture,true)
		_check(bool(Story.confirm_task(phase_fixture,Story.task_id(Story.chapter(phase_fixture),phase_groups[0],0),int(phase_fixture.revision)).get("ok",false)),"period fixture uses formal task confirmation")
	_check(not OfficialNetworkAudit.historical_chapter_errors(phase_fixture,"cd-line1-2010").is_empty(),"a fresh 2010 checkpoint rejects the later 2015 south extension")
	_check(OfficialNetworkAudit.historical_chapter_errors(phase_fixture,"cd-line1-2010",true).is_empty(),"an explicitly separate compatibility scope check retains later construction without certifying 2010 chronology")
	# Focused interface fixture: give the real two-line initial scope a split
	# operation solely to exercise ordering, atomic validation and undo. This
	# is not a new Shenzhen historical event or cumulative-city evidence.
	var fixtures:Array=CampaignSystem._catalog.cities.shenzhen.chapters
	var reorganization_index:=-1
	for index in range(fixtures.size()):
		if str(fixtures[index].id)=="sz-initial-cross-2004":reorganization_index=index;break
	var original_definition:Dictionary=fixtures[reorganization_index].duplicate(true)
	fixtures[reorganization_index]["requiresLineReorganization"]=true
	var reorganization_world:=WorldData.new_world("shenzhen","campaign")
	reorganization_world.storyState.phase="history";reorganization_world.storyState.chapterId="sz-initial-cross-2004";reorganization_world.storyState.stage="build"
	app._enter(reorganization_world)
	while not Story.plan_is_final(reorganization_world):
		var revised:Dictionary=app._commit_plan_revision(int(reorganization_world.storyPlan.get("planIndex",0))+1,int(reorganization_world.revision))
		_check(bool(revised.get("ok",false)),"reorganization fixture adopts each sourced plan through the formal revision command")
	var before_reorganization:=JSON.stringify(reorganization_world.routes)
	_check(not bool(app._commit_line_reorganization(int(reorganization_world.revision)).get("ok",false)) and JSON.stringify(reorganization_world.routes)==before_reorganization,"missing construction blocks reorganization without partially changing service")
	var reorganization_draft:Dictionary=app._assist_candidate()
	_check(bool(app._commit_assisted_construction(reorganization_draft,int(reorganization_world.revision)).get("ok",false)),"reorganization fixture uses formal construction")
	var ready_reorganization:=Story.evaluate(reorganization_world)
	_check(ready_reorganization.issues.any(func(issue:Dictionary):return bool(issue.get("pendingConfirmation",false))),"ready interchange confirmation is distinct from missing geometry")
	var stale_reorganization:=JSON.stringify(reorganization_world.routes)
	_check(not bool(app._commit_line_reorganization(int(reorganization_world.revision)-1).get("ok",false)) and JSON.stringify(reorganization_world.routes)==stale_reorganization,"stale reorganization does not change planning")
	_check(bool(app._commit_line_reorganization(int(reorganization_world.revision)).get("ok",false)),"ready-but-unconfirmed interchange does not create a circular reorganization dependency")
	var organized_routes:=JSON.stringify(reorganization_world.routes)
	_check(reorganization_world.routes.size()==2 and SaveManager.validate(reorganization_world).is_empty() and reorganization_world.transferConnections.is_empty(),"reorganization validates actual service while keeping the new interchange explicitly unconfirmed")
	_check(not app.history.undo().is_empty() and not bool(reorganization_world.storyPlan.get("reorganizationAccepted",false)) and reorganization_world.routes.is_empty(),"undo restores both service and reorganization acceptance")
	_check(not app.history.redo().is_empty() and JSON.stringify(reorganization_world.routes)==organized_routes,"redo restores exactly the validated service transaction")
	for required in Story.chapter(reorganization_world).get("requiredTransfers",[]):
		var link:Dictionary={"id":required.id,"name":required.name,"complexId":required.complexId,"stationInstanceIds":required.stationInstanceIds.duplicate(),"lineIds":required.lineIds.duplicate(),"status":"active","source":required.get("source","")}
		_check(bool(app._commit_transfer_connection(required,link,int(reorganization_world.revision)).get("ok",false)),"interchange is explicitly established after the service reorganization")
	_check(Story.evaluate(reorganization_world).complete,"construction, actual reorganization and explicit interchange jointly satisfy the fixture")
	fixtures[reorganization_index]=original_definition
	var corrected_early:=WorldData.new_world("chengdu","campaign")
	corrected_early.storyState.chapterId="chengdu-network-milestone-2020-12-18"
	corrected_early.storyState.completedChapterIds=["chengdu-opening-line10-phase3-first-2025","cd-line1-2010"]
	corrected_early.storyState.chapterTaskProgress={"chengdu-opening-line10-phase3-first-2025":{"tasks":{"previous":{"status":"confirmed"}}}}
	var retained_geometry:=JSON.stringify(corrected_early.stations)
	Story._recheck_later_historical_services(corrected_early,{"historicalLineId":"chengdu-line17-12","reconfirmLaterServices":true})
	_check(not corrected_early.storyState.completedChapterIds.has("chengdu-opening-line10-phase3-first-2025") and corrected_early.storyState.completedChapterIds.has("cd-line1-2010"),"correcting an old modern snapshot reopens only later affected historical service")
	_check(corrected_early.storyState.legacyTaskProgress.has("chengdu-opening-line10-phase3-first-2025") and JSON.stringify(corrected_early.stations)==retained_geometry,"later completion evidence and all construction survive a dated service correction")
	var correction_history:=CommandHistory.new();correction_history.attach(corrected_early)
	_check(not correction_history._capture_planning().has("storyState"),"default milestone snapshots cannot recursively capture story milestones")
	var previous_story:=JSON.stringify(corrected_early.storyState)
	correction_history.execute("reconfirm fixture",func(state:Dictionary):state.storyState.completedChapterIds.append("fixture-later"),["storyState"])
	_check(not correction_history.undo().is_empty() and JSON.stringify(corrected_early.storyState)==previous_story,"explicit reorganization progress is restored with the same undo transaction")
	_check(not correction_history.redo().is_empty() and corrected_early.storyState.completedChapterIds.has("fixture-later"),"explicit reorganization progress also survives redo")
	var presentation_fixture:Dictionary={"valid":true,"directions":[{"id":"f","segments":[{"id":"A"},{"id":"B"},{"id":"C"},{"id":"D"}]}]}
	var presentation_route:Dictionary={"open":true,"serviceStatus":"mixed","directions":[{"serviceStatusBySegment":["open","built","trial","suspended"]}]}
	var shown:=RoutePath.presentation_directions(presentation_fixture,presentation_route)
	_check(shown.size()==2 and shown[0].segments==[{"id":"A"}] and shown[1].segments==[{"id":"C"}],"presentation splits at every built-only or suspended gap rather than driving across it")
	presentation_route.directions[0].serviceStatusBySegment=[]
	_check(RoutePath.presentation_directions(presentation_fixture,presentation_route).is_empty(),"a mixed route without segment evidence is not displayed as fully open")
	var closure_fixture:=WorldData.new_world("chengdu","campaign")
	closure_fixture.storyState.chapterId="chengdu-line2-east-suspended";closure_fixture.storyState.phase="history";closure_fixture.storyState.stage="build"
	app._enter(closure_fixture)
	_check(bool(app._commit_assisted_construction(app._assist_candidate(),int(closure_fixture.revision)).get("ok",false)),"closure fixture obtains real physical geometry through the formal construction command")
	var closure_transitions:Array=Story.evaluate(closure_fixture).serviceTransitions
	for proposal in closure_transitions:
		_check(bool(app._commit_service_transition(proposal,int(closure_fixture.revision)).get("ok",false)),"the source-backed open or suspended scope requires an explicit service transaction")
	_check(closure_fixture.routes[0].directions[0].serviceStatusBySegment[-1]=="suspended","confirming the range immediately changes the actual service, before task confirmation")
	_check(not app.history.undo().is_empty() and closure_fixture.routes[0].directions[0].serviceStatusBySegment[-1]!="suspended","undo restores the same range record and actual service atomically")
	_check(not app.history.redo().is_empty() and closure_fixture.routes[0].directions[0].serviceStatusBySegment[-1]=="suspended","redo restores the confirmed suspended range")
	var closure_task:=Story.task_id(Story.chapter(closure_fixture),Story.groups(closure_fixture,true)[0],0)
	_check(bool(Story.confirm_task(closure_fixture,closure_task,int(closure_fixture.revision)).get("ok",false)),"mixed open/suspended line can be confirmed without closing the unaffected western line")
	_check(OfficialNetworkAudit.historical_chapter_errors(closure_fixture,"chengdu-line2-east-suspended").is_empty(),"independent closure audit checks both the operating west and actual suspended east")
	var closure_path:=RoutePath.for_route(closure_fixture.routes[0],closure_fixture,float(WorldData.city("chengdu").center[0]))
	var closure_display:=RoutePath.presentation_directions(closure_path,closure_fixture.routes[0])
	_check(closure_display.size()==1 and closure_display[0].segments.size()==25,"closure presentation ends at Chengdu University of Administration and does not enter the six suspended stations")
	closure_fixture.routes[0].directions[0].serviceStatusBySegment[-1]="open"
	_check(not OfficialNetworkAudit.historical_chapter_errors(closure_fixture,"chengdu-line2-east-suspended").is_empty(),"falsely reopening a suspended segment fails the independent dated audit")
	var inserted_history:=WorldData.new_world("chengdu","campaign")
	var cd_chapters:Array=CampaignSystem.city_config("chengdu").chapters
	inserted_history.storyState.completedChapterIds=cd_chapters.filter(func(c:Dictionary):return str(c.id)!="chengdu-line2-east-suspended").map(func(c:Dictionary):return str(c.id))
	inserted_history.storyState.phase="future";inserted_history.storyState.stage="build";inserted_history.storyState.chapterId="cd-line18-phase4-build"
	Story.next_chapter(inserted_history)
	_check(inserted_history.storyState.phase=="future" and inserted_history.storyState.stage=="build","new historical content does not discard an active planning draft")
	inserted_history.storyState.stage="outcome";Story.next_chapter(inserted_history)
	_check(inserted_history.storyState.phase=="history" and inserted_history.storyState.chapterId=="chengdu-line2-east-suspended","the saved final planning outcome resumes newly inserted historical construction")
	inserted_history.storyState.phase="future_gap";inserted_history.storyState.chapterId="chengdu-network-reconciliation-2026-10-01"
	SaveManager._resume_expanded_history(inserted_history.storyState,"chengdu","campaign")
	_check(inserted_history.storyState.phase=="history" and inserted_history.storyState.chapterId=="chengdu-line2-east-suspended","a boundary save cannot let its retained valid historical ID hide new missing tasks")
	app.queue_free();await process_frame
	print("OFFICIAL_TARGET_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
