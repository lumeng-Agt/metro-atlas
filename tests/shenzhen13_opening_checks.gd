extends SceneTree
const Story=preload("res://scripts/story_session.gd")
const App=preload("res://scripts/main.gd")
const LINE="shenzhen-line13-14"
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
## The city-wide project scope to audit. Read from the official target data
## rather than the campaign catalog, because this fixture deliberately trims
## the catalog down to line 13 — auditing the trimmed list would ask nothing.
func city_project_ids() -> Array:
	return OfficialNetworkAudit.target_data().get("cities",{}).get("shenzhen",{}).get("requiredProjectIds",[])
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var app:=App.new();root.add_child(app);await process_frame
	var original:Dictionary=CampaignSystem.city_config("shenzhen")
	var ids:Array=["shenzhen-network-milestone-2024-12-28","shenzhen-network-milestone-2025-12-28","shenzhen-network-milestone-2026-06-28"]
	# Labelled isolated single-line chronological fixture. Other contemporary
	# projects/transfers are excluded here, never skipped in the full-city replay.
	var chapters:Array=[]
	for id in ids:
		var chapter:Dictionary=original.chapters.filter(func(c:Dictionary):return str(c.id)==str(id))[0].duplicate(true)
		chapter.lineGroups=chapter.lineGroups.filter(func(g:Dictionary):return str(g.historicalLineId)==LINE)
		chapter.requiredTransfers=[];chapter.scopeCorrections=[];chapter.serviceTransitions=[]
		chapter.requiresLineReorganization=false;chapter.eventOnly=false
		chapters.append(chapter)
	CampaignSystem._catalog.cities.shenzhen.chapters=chapters
	CampaignSystem._catalog.cities.shenzhen.futurePlans=[]
	app._new_game("shenzhen",false)
	while app.saves_in_flight>0:await process_frame
	var expected_counts:Array=[7,15,26]
	for index in range(ids.size()):
		var chapter:=Story.chapter(app.world)
		_check(str(chapter.get("id",""))==str(ids[index]),"normal progression reaches dated phase "+str(ids[index]))
		app._begin_chapter()
		var before_stations:int=app.world.stations.size()
		var candidate:Dictionary=app._assist_candidate()
		_check(str(candidate.get("issue","")).is_empty(),"dated extension previews: "+str(candidate.get("issue","")))
		var applied:Dictionary=app._commit_assisted_construction(candidate,int(app.world.revision))
		_check(bool(applied.get("ok",false)),"formal construction commits: "+str(applied.get("error","")))
		if not bool(applied.get("ok",false)):break
		_check(not app.history.undo().is_empty() and app.world.stations.size()==before_stations,"new phase undoes without removing older stations")
		_check(not app.history.redo().is_empty(),"phase redoes as one construction")
		for group in chapter.lineGroups:
			var result:=Story.confirm_task(app.world,str(group.taskId),int(app.world.revision))
			_check(bool(result.get("ok",false)),"dated task confirms through common command: "+str(result.get("error","")))
		var route:=WorldData.find_route(app.world,"historical_"+LINE)
		_check(route.get("stationOrder",[]).size()==int(expected_counts[index]),"correct cumulative open stop count at "+str(chapter.date))
		_check(app.world.stations.size()==int(expected_counts[index]),"extension reuses old bodies and endpoint")
		var issues:=OfficialNetworkAudit.historical_chapter_errors(app.world,str(chapter.id))
		_check(issues.is_empty(),"independent dated order, real paths and no later stops: "+JSON.stringify(issues))
		var complete:=Story.commit_chapter(app.world,int(app.world.revision))
		_check(bool(complete.get("ok",false)),"confirm only this historical phase: "+str(complete.get("error","")))
		var saved:=SaveManager.save_world(app.world)
		var loaded:=SaveManager.load_file(str(saved.get("path","")))
		_check(bool(saved.get("ok",false)) and bool(loaded.get("ok",false)),"dated checkpoint saves and reloads")
		if not bool(loaded.get("ok",false)):break
		app._enter(loaded.world)
		_check(OfficialNetworkAudit.historical_chapter_errors(app.world,str(chapter.id)).is_empty(),"reloaded official paths remain correct")
		Story.next_chapter(app.world)
	_check(not OfficialNetworkAudit.historical_chapter_errors(app.world,str(ids[0])).is_empty(),"2026 full line cannot pass as the 2024 seven-stop opening")
	var targets:Dictionary=OfficialNetworkAudit.target_data().cities.shenzhen
	var final_target:Dictionary=targets.historicalMilestones.filter(func(m:Dictionary):return str(m.chapterId)==str(ids[2]))[0].duplicate(true)
	final_target.groups=final_target.groups.filter(func(g:Dictionary):return str(g.get("historicalLineId",""))==LINE)
	final_target.transfers=[]
	var broken:=app.world.duplicate(true)
	broken.trackEdges.remove_at(broken.trackEdges.size()-1)
	_check(not OfficialNetworkAudit.project_errors(broken,final_target).is_empty(),"missing northern physical segment fails official final scope")
	_check(app.world.stations.all(func(s:Dictionary):return not str(s.name).contains("西丽高铁")),"announced skipped Xili station is not an open stop")
	# Only line 13 exists in this fixture. The city-wide audit is what the
	# release evidence reads, so it has to report the missing scope — that is
	# the check that a single-line success cannot be recorded as a whole city.
	# (The `completion_eligibility` object cannot stand in for it here: the
	# fixture restores the untouched catalog, so no required future plan is
	# staged for it to evaluate, and it would read `ok` on the built chapter
	# alone. `tests/story_checks.gd` covers the forged-flag path.)
	var city_audit:Array=OfficialNetworkAudit.current_project_errors(app.world,city_project_ids())
	_check(not city_audit.is_empty(),"official audit reports the single-line fixture's missing city scope")
	_check(city_audit.any(func(text:String):return text.contains("shenzhen-line15-15")),"audit names the concrete missing official scope")
	CampaignSystem._catalog.cities.shenzhen=original
	app.queue_free();await process_frame
	print("SHENZHEN13_OPENING_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
