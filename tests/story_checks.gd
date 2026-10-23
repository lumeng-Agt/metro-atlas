extends SceneTree

const Story=preload("res://scripts/story_session.gd")
const Catalog=preload("res://scripts/campaign_system.gd")
const App=preload("res://scripts/main.gd")
var checks:=0
var failures:Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	_check(WorldData.SAVE_VERSION==25,"故事存档格式25")
	_check(Catalog.validate_catalog(WorldData.cities()).is_empty(),"五城资料引用校验")
	_check(Catalog.validate_network_baseline(WorldData.cities()).is_empty(),"五城截止日路网基准引用校验")
	var gz_future:Array=Catalog.playable_future_plans("guangzhou")
	var gz_future_ids:Array=gz_future.map(func(plan:Dictionary):return str(plan.get("id","")))
	_check(gz_future.size()==3 and gz_future_ids.has("gz-line12-mid-build") and gz_future_ids.has("gz-line13-phase2-west-build") and gz_future_ids.has("gz-line8-north-branch-build"),"广州12号线中段、13号线二期西段和8号线北延段支线进入可玩项目篇")
	var sh_future_ids:Array=Catalog.playable_future_plans("shanghai").map(func(plan:Dictionary):return str(plan.get("id","")))
	_check(sh_future_ids.has("sh-line23-phase1-build") and sh_future_ids.has("sh-line15-south-build") and sh_future_ids.has("sh-line21-phase1-build"),"上海23号线一期、15号线南延伸和21号线一期进入可玩项目篇")
	var gz_2025:Dictionary={}
	for candidate in Catalog.city_config("guangzhou").get("chapters",[]):
		if str(candidate.get("id",""))=="guangzhou-network-milestone-2025-06-29":gz_2025=candidate;break
	var gz_open12:Array=gz_2025.get("lineGroups",[]).filter(func(group:Dictionary):return str(group.get("historicalLineId",""))=="guangzhou-line12-12")
	_check(gz_open12.size()==2 and gz_open12[0].get("stationIds",[]).has("guangzhou-s363") and not gz_open12[0].get("stationIds",[]).has("guangzhou-s367") and gz_open12[1].get("stationIds",[]).has("guangzhou-s367") and not gz_open12[1].get("stationIds",[]).has("guangzhou-s363"),"广州2025年12号线东西两段保持断开，未提前虚构贯通")
	var bridge_old:Dictionary={"historicalLineId":"test-line","directions":[{"id":"west","stationIds":["A","B"],"edgePathsBySegment":[{"id":"ab"}]},{"id":"east","stationIds":["D","E"],"edgePathsBySegment":[{"id":"de"}]}]}
	var bridge_new:Dictionary={"chapterId":"bridge","directions":[{"id":"bridge","stationIds":["B","C","D"],"edgePathsBySegment":[{"id":"bc"},{"id":"cd"}]}]}
	var bridged:Dictionary=Story._merge_historical_route(bridge_old,bridge_new)
	_check(bridged.get("directions",[]).size()==1 and bridged.directions[0].get("stationIds",[])==["A","B","C","D","E"] and bridged.directions[0].get("edgePathsBySegment",[]).size()==4,"后建连接段把原来断开的两段合为连续线路")
	var shenzhen_coverage:Dictionary=Catalog.network_coverage("shenzhen")
	_check(int(shenzhen_coverage.get("officialRouteCount",0))==17 and int(shenzhen_coverage.get("mapRouteEntryCount",0))==17,"深圳截止日明确列出17个线路／支线标识")
	_check(shenzhen_coverage.get("pendingMilestones",[]).is_empty(),"深圳已登记里程碑均能定位到可玩章节")
	_check(shenzhen_coverage.get("pendingMilestoneIntervals",[]).is_empty(),"五城章节不存在未制作的历史里程碑区间")
	var shenzhen_schedule:Array=shenzhen_coverage.get("milestoneChapters",[])
	_check(not shenzhen_schedule.is_empty() and str(shenzhen_schedule.back().get("periodEndInclusive",""))=="2026-10-01" and shenzhen_schedule.back().get("targetMapRouteIds",[]).size()==17 and str(shenzhen_schedule.back().get("contentStatus",""))=="network_reconciliation_complete","深圳截止日核对节点涵盖全部17个地图线路／支线关系并可玩")
	_check(int(shenzhen_coverage.get("fullyTargetedRouteEntryCount",-1))==17 and int(shenzhen_coverage.get("uncoveredRouteEntryCount",-1))==0,"深圳17个截止日线路／支线均进入章节目标")
	var sh_events:Array=Catalog.city_config("shanghai").historicalEvents
	_check(sh_events.filter(func(e:Dictionary):return str(e.date)=="1996-12-28").size()==1 and sh_events.filter(func(e:Dictionary):return str(e.date)=="1997-07-01").size()==1,"上海时间轴区分1996分段与1997贯通，不重复记载同一节点")
	var sz:=WorldData.new_world("shenzhen","campaign");sz.storyState.chapterId="sz-initial-cross-2004"
	var sz_early_line:=Story.groups(sz,true).filter(func(group:Dictionary):return str(group.get("historicalLineId",""))=="shenzhen-line1")
	_check(sz_early_line.size()==1 and not sz_early_line[0].stationIds.has("shenzhen-s68"),"2004年开通范围不能混入2007年才通车的福田口岸")
	var gz:=WorldData.new_world("guangzhou","campaign");gz.storyState.chapterId="gz-line1-1997"
	_check(str(Story.targets(gz)[0].name)=="西朗","广州早期样板使用当时名称")
	var bj:=WorldData.new_world("beijing","campaign");bj.storyState.chapterId="bj-phase1-trial-1971"
	var early:Array=Story.groups(bj,true)[0].stationIds
	_check(early.size()==10 and early.find("beijing-s59")<early.find("beijing-s60") and not early.has("beijing-s56"),"1971年10站站序与未运营站排除回归")
	var beijing_built:=built_world("beijing",0)
	var built_eval:=Story.evaluate(beijing_built)
	_check(not bool(built_eval.complete) and built_eval.get("serviceTransitions",[]).size()==2 and built_eval.issues.any(func(issue:Dictionary):return str(issue.get("kind",""))=="service"),"1969北京西段与南段必须由玩家确认建成范围")
	_confirm_service_transitions(beijing_built,built_eval)
	built_eval=Story.evaluate(beijing_built)
	_check(bool(built_eval.complete) and beijing_built.serviceRanges.size()==2 and beijing_built.serviceRanges.all(func(item:Dictionary):return str(item.status)=="built"),"1969北京两段工程建成范围分别记录")
	var beijing_trial:=built_world("beijing",1)
	var trial_eval:=Story.evaluate(beijing_trial)
	_check(not bool(trial_eval.complete) and trial_eval.get("serviceTransitions",[]).size()==1 and str(trial_eval.serviceTransitions[0].status)=="trial","1971北京明确等待有限试运营范围确认")
	_check(not bool(trial_eval.routes[0].get("open",false)) and trial_eval.routes[0].directions[0].serviceStatusBySegment.all(func(status:String):return status=="built"),"试运营状态未确认前不提前显示为已运营")
	_confirm_service_transitions(beijing_trial,trial_eval)
	trial_eval=Story.evaluate(beijing_trial)
	_check(bool(trial_eval.complete) and beijing_trial.serviceRanges.size()==1 and str(beijing_trial.serviceRanges[0].status)=="trial" and beijing_trial.serviceRanges[0].stationIds.size()==10 and beijing_trial.serviceRanges[0].edgePathsBySegment.size()==9,"1971北京只记录十站范围内的有限试运营，而非正式开放")
	_check(bool(trial_eval.routes[0].get("open",false)) and trial_eval.routes[0].directions[0].serviceStatusBySegment.all(func(status:String):return status=="trial"),"确认后列车展示使用该阶段的试运营范围")
	var sh:=WorldData.new_world("shanghai","campaign");sh.storyState.chapterIndex=1;sh.storyState.chapterId="sh-line1-1995"
	var historic_names:Dictionary=Story.groups(sh,true)[0].get("stationNames",{})
	var early_sh:=WorldData.new_world("shanghai","campaign");early_sh.storyState.chapterId="sh-line1-1993"
	var early_names:Dictionary=Story.groups(early_sh,true)[0].get("stationNames",{})
	_check(str(historic_names.get("shanghai-s118",""))=="黄陂南路" and str(early_names.get("shanghai-s422",""))=="新龙华" and not Story.groups(sh,true)[0].stationIds.has("shanghai-s422"),"上海早期名称保留在首次建设段，后续只复用已建目标站")
	var identified:=WorldData.new_world("shanghai","campaign");identified.storyState["chapterId"]="sh-line1-1995";identified.storyState.chapterIndex=0
	_check(str(Story.chapter(identified).id)=="sh-line1-1995","章节稳定编号优先于数组位置，内容插入不改当前章")
	identified.storyState.chapterId="unknown-removed-chapter"
	_check(Story.chapter(identified).is_empty(),"章节无法映射时不静默跳到另一章")
	for city in WorldData.cities():
		_check(not city.has("demand"),"%s不加载旧需求数据" % str(city.id))
		var sample:=WorldData.new_world(str(city.id),"campaign")
		_check(not sample.has("simulation") and not sample.has("cityProgression"),"%s无客流或旧任务会话" % str(city.id))
		_check(str(sample.gameId)!=str(WorldData.new_world(str(city.id),"campaign").gameId),"%s同城新局编号独立" % str(city.id))
		var chapters:Array=Catalog.city_config(str(city.id)).get("chapters",[])
		print("Audit playable targets in %d chapters for %s" % [chapters.size(),str(city.id)])
		for index in range(chapters.size()):
			var world:=WorldData.new_world(str(city.id),"campaign")
			world.storyState.chapterIndex=index;world.storyState.chapterId=str(chapters[index].get("id",""));world.storyState.stage="build"
			var selected_chapter:Dictionary=Story.chapter(world)
			var groups:Array=Story.groups(world,true)
			var targets:Array=Story.targets(world,true)
			var expected_target_count:=0
			var task_ids:Dictionary={}
			for group_index in range(groups.size()):
				var group:Dictionary=groups[group_index]
				expected_target_count+=group.get("stationIds",[]).size()
				var task_id:=Story.task_id(selected_chapter,group,group_index)
				_check(not task_ids.has(task_id),"%s任务编号唯一" % str(selected_chapter.get("id","")))
				task_ids[task_id]=true
				_check(not Story.targets(world,true,task_id).is_empty(),"%s任务可定位建设目标：%s" % [str(selected_chapter.get("id","")),task_id])
			var event_only:=bool(selected_chapter.get("eventOnly",false))
			if event_only:
				_check(groups.is_empty() and targets.is_empty() and not str(selected_chapter.get("source","")).is_empty(),"%s只读历史节点明确标记资料来源且不伪装成铺轨任务" % str(selected_chapter.get("id","")))
			else:
				_check(not str(selected_chapter.get("id","" )).is_empty() and not groups.is_empty() and not targets.is_empty(),"%s章节有稳定编号、任务和可定位目标" % str(city.id))
			_check(str(selected_chapter.get("date",""))<="2026-10-01","%s不提前出现截止日后的历史章节" % str(selected_chapter.get("id","")))
			_check(world.storyState.completedChapterIds.is_empty(),"读取章节蓝图不推进历史进度")
		var pending:Array=Catalog.network_coverage(str(city.id)).get("pendingMilestones",[])
		_check(pending.is_empty(),"%s历史事件全部归入可玩章节" % str(city.id))
	var broken:=built_world("shanghai",0)
	broken.trackEdges.clear()
	_check(not bool(Story.evaluate(broken).complete),"仅放站、没有轨道不能通过")
	var unnamed:=built_world("shanghai",0)
	for station in unnamed.stations:
		station.erase("historicalId");station.erase("stationInstanceId");station.erase("stationComplexId")
	_check(not bool(Story.evaluate(unnamed).complete),"同名站不能替代显式历史身份")
	var swapped:=built_world("shanghai",0)
	var temp:Array=swapped.stations[0].latlng
	swapped.stations[0].latlng=swapped.stations[1].latlng;swapped.stations[1].latlng=temp
	_check(not bool(Story.evaluate(swapped).complete),"站序身份与实际坐标不符被定位")
	var duplicate:=built_world("shanghai",0)
	var clone:Dictionary=duplicate.stations[0].duplicate(true);clone.id="duplicate";duplicate.stations.append(clone)
	_check(not bool(Story.evaluate(duplicate).complete),"一个历史目标不能匹配两站")
	var revision_world:=built_world("shenzhen",0)
	revision_world.storyPlan.planIndex=0
	_check(not bool(Story.evaluate(revision_world).complete),"旧版未实施草案不能充当实际开通")
	var separate_interchange:=built_world("shenzhen",0)
	var interchange_bodies:Array=separate_interchange.stations.filter(func(station:Dictionary):return str(station.get("stationComplexId",""))=="shenzhen-s8")
	_check(interchange_bodies.size()==2 and str(interchange_bodies[0].id)!=str(interchange_bodies[1].id),"深圳会展中心由1、4号线两座独立物理站体构成")
	var interchange_result:=Story.evaluate(separate_interchange)
	_check(not bool(interchange_result.complete) and interchange_result.issues.any(func(issue:Dictionary):return str(issue.get("kind",""))=="transfer"),"站体和线路就绪后仍需玩家明确建立换乘联系")
	var interchange_groups:Array=Story.groups(separate_interchange,true)
	for group_index in range(interchange_groups.size()):
		var group:Dictionary=interchange_groups[group_index]
		var task_id:=Story.task_id(Story.chapter(separate_interchange),group,group_index)
		var task_result:=Story.confirm_task(separate_interchange,task_id,int(separate_interchange.revision))
		_check(bool(task_result.get("ok",false)),"深圳首章可单独确认%s建设任务：%s" % [str(group.get("name",task_id)),str(task_result.get("error",""))])
	_check(Story.confirmed_task_count(separate_interchange)==interchange_groups.size(),"多线路章节逐项记录线路任务确认")
	_confirm_required_transfers(separate_interchange,interchange_result)
	interchange_result=Story.evaluate(separate_interchange)
	_check(bool(interchange_result.complete),"明确建立独立站体换乘联系后通过章节检查")
	var repeated_confirm:=Story.commit_chapter(separate_interchange,int(separate_interchange.revision))
	_check(bool(repeated_confirm.get("ok",false)),"逐项确认线路任务和显式换乘后可确认历史节点")
	var saved_interchange:Dictionary={}
	for connection in separate_interchange.transferConnections:
		if str(connection.get("id",""))=="sz-transfer-huizhanzhongxin-2004":saved_interchange=connection;break
	_check(saved_interchange.size()>0,"确认历史节点时保存显式换乘边，不并入实体轨道")
	if not saved_interchange.is_empty():
		for transfer_index in range(saved_interchange.stationInstanceIds.size()):
			var line_id:=str(saved_interchange.lineIds[transfer_index]);var instance_id:=str(saved_interchange.stationInstanceIds[transfer_index]);var serving_route:Dictionary={};var physical_station:Dictionary={}
			for route in separate_interchange.routes:
				if str(route.get("historicalLineId",""))==line_id:serving_route=route;break
			for station in separate_interchange.stations:
				if str(station.get("stationInstanceId",""))==instance_id:physical_station=station;break
			_check(not serving_route.is_empty() and not physical_station.is_empty() and serving_route.get("stationOrder",[]).has(str(physical_station.get("id",""))),"每条线路停靠自己的独立站体")
	var history:=CommandHistory.new();history.attach(revision_world)
	history.execute("采用下一版",func(state:Dictionary):state.storyPlan.planIndex=1)
	history.undo();_check(int(revision_world.storyPlan.planIndex)==0,"方案修订可以撤销")
	history.redo();_check(int(revision_world.storyPlan.planIndex)==1,"方案修订可以重做")
	var api:=App.new();root.add_child(api)
	await process_frame
	_check(not auto_accept_quit,"关闭窗口由保存结果决定，不由引擎提前退出")
	api._new_game("shanghai",true)
	_check(Story.targets(api.world).is_empty(),"新局先展示历史起点，操作教学等待首个建设节点")
	await _reach_first_construction(api)
	await process_frame
	_check(api.world.get("storyState",{}).get("tutorialEnabled",false),"真实新游戏使用首章引导")
	_check(not api.map_view.campaign_blueprint.get("stations",[]).is_empty(),"首章引导不隐藏历史蓝图")
	var state_before:=JSON.stringify(api.world.storyState)
	api._process(12.0)
	_check(JSON.stringify(api.world.storyState)==state_before and not api.world.has("simulation"),"展示时钟不产生乘客或推进历史")
	api._begin_chapter();await process_frame
	_check(api.station_button.text=="车站" and api.track_button.text=="铺轨","引导使用真实底栏工具")
	var tutorial_targets:Array=Story.targets(api.world)
	for target in tutorial_targets.slice(0,2):
		api._tool("station");api._click(target.latlng,"blueprint",str(target.id),"");api._commit_station()
	api._focus_tutorial()
	_check(str(api.spotlight.message).contains("铺轨"),"前两站完成后先指向轨道，不指向隐藏的第三站")
	api._tool("track")
	var first:=Story.bound_station(api.world,str(tutorial_targets[0].id));var second:=Story.bound_station(api.world,str(tutorial_targets[1].id));var ends:Array=api._facing(first,second)
	api._click(WorldData.station_endpoint(first,str(ends[0])),"endpoint",str(first.id),str(ends[0]))
	api._click(WorldData.station_endpoint(second,str(ends[1])),"endpoint",str(second.id),str(ends[1]));api._commit_track()
	_check(bool(api.world.storyState.learnedTools),"真实建设提交后才解锁重复建设辅助")
	_check(Story.blueprint(api.world).stations.size()==5,"学会两站连接后展开后续目标")
	var assistant:=api._assist_candidate()
	_check(str(assistant.get("issue","")).is_empty(),"余下重复建设有有效预览")
	if assistant.has("state"):
		var assisted_commit:Dictionary=api._commit_assisted_construction(assistant,int(api.world.revision))
		_check(bool(assisted_commit.get("ok",false)),"辅助建设经正式提交接口")
		_check(bool(Story.evaluate(api.world).complete),"真实默认朝向和辅助可通过首章")
		api._undo(false)
		_check(api.world.stations.size()==2 and not bool(api.world.storyPlan.get("assisted",false)),"撤销辅助同时恢复站轨和辅助标记")
		api._undo(true)
		_check(api.world.stations.size()==5 and bool(api.world.storyPlan.get("assisted",false)),"重做辅助完整恢复")
	for city in WorldData.cities():
		api._new_game(str(city.id),false);await _reach_first_construction(api);api.world.storyState.learnedTools=true
		var chapter_count:int=Catalog.city_config(str(city.id)).get("chapters",[]).size()
		# The interface path is exercised once per city. All chapter task groups
		# are separately checked for stable IDs and selectable target stations;
		# construction/commit is replayed with representative city chapters.
		for chapter_index in range(mini(chapter_count,1)):
			api._begin_chapter()
			for _revision_index in range(4):
				if Story.plan_is_final(api.world):break
				api._revise()
				var dialogs:=api.find_children("*","ConfirmationDialog",true,false)
				_check(not dialogs.is_empty(),"修订方案先明确确认差异")
				if not dialogs.is_empty():dialogs[-1].confirmed.emit()
				await process_frame
			var preview:=api._assist_candidate()
			_check(str(preview.get("issue","")).is_empty(),"%s/%d 跨章保留建设后仍可辅助连接：%s" % [str(city.id),chapter_index,str(preview.get("issue",""))])
			if not preview.has("state"):break
			var applied:Dictionary=api._commit_assisted_construction(preview,int(api.world.revision))
			_check(bool(applied.get("ok",false)),"城市建设经正式提交接口")
			if bool(Story.chapter(api.world).get("requiresLineReorganization",false)):
				_check(not bool(Story.evaluate(api.world).complete),"重组章节不能只凭站轨完成")
				api._tool("line");api._confirm_line_reorganization()
			var explicit_evaluation:=Story.evaluate(api.world)
			for transfer in explicit_evaluation.get("requiredTransfers",[]):
				if api._transfer_connected(transfer):continue
				var connection:Dictionary={"id":str(transfer.get("id","")),"name":str(transfer.get("name","换乘站")),"complexId":str(transfer.get("complexId","")),"stationInstanceIds":transfer.get("stationInstanceIds",[]).duplicate(),"lineIds":transfer.get("lineIds",[]).duplicate(),"status":"active","precision":str(transfer.get("precision","schematic")),"source":str(transfer.get("source","")),"effectiveDate":str(Story.chapter(api.world).get("date",""))}
				var transfer_commit:=api._commit_transfer_connection(transfer,connection,int(api.world.get("revision",0)))
				_check(bool(transfer_commit.get("ok",false)),"本章换乘通过真实确认事务提交")
				if str(city.id)=="shenzhen" and chapter_index==0 and bool(transfer_commit.get("ok",false)):
					_check(api.history.undo_label()=="建立换乘联系","换乘联系是独立可撤销操作")
					api._undo(false);_check(not api._transfer_connected(transfer),"撤销移除换乘关系但保留站体")
					api._undo(true);_check(api._transfer_connected(transfer),"重做恢复同一显式换乘关系")
			explicit_evaluation=Story.evaluate(api.world)
			for proposal in explicit_evaluation.get("serviceTransitions",[]):
				var status_commit:=api._commit_service_transition(proposal,int(api.world.get("revision",0)))
				_check(bool(status_commit.get("ok",false)),"本期历史服务范围通过可撤销操作确认")
				if str(city.id)=="beijing" and chapter_index==0 and str(proposal.get("status",""))=="built" and bool(status_commit.get("ok",false)):
					var service_id:=str(proposal.get("id",""));api._undo(false)
					_check(not Story._has_service_range(api.world,service_id),"撤销还原本期历史范围状态")
					api._undo(true);_check(Story._has_service_range(api.world,service_id),"重做恢复同一历史状态范围")
			var task_groups:Array=Story.groups(api.world,true)
			for task_index in range(task_groups.size()):
				var task_group:Dictionary=task_groups[task_index]
				var task_id:=Story.task_id(Story.chapter(api.world),task_group,task_index)
				var task_confirmation:Dictionary=Story.confirm_task(api.world,task_id,int(api.world.get("revision",0)))
				_check(bool(task_confirmation.get("ok",false)),"%s本章逐项建设任务确认成功：%s" % [str(city.id),str(task_confirmation.get("error",""))])
			var result:=Story.evaluate(api.world)
			_check(bool(result.complete),"%s/%d 累计故事可以通过：%s" % [str(city.id),chapter_index,JSON.stringify(result.issues)])
			if not bool(result.complete):break
			api._check();api._commit_chapter()
			while api.saves_in_flight>0:await process_frame
			_check(not api.dirty and api.save_error.is_empty(),"历史节点与镜头一并保存，界面不误报未保存")
			api._next()
			while api.saves_in_flight>0:await process_frame
			_check(not api.dirty and api.save_error.is_empty(),"章节转换保存完成后保持已保存状态")
		_check(str(api.world.storyState.get("phase",""))=="history" and not bool(api.world.storyState.freeUnlocked),"代表性建设后继续留在历史章节链")
		var gap_coverage:Dictionary=Catalog.network_coverage(str(api.world.get("cityId","")))
		_check(not gap_coverage.is_empty() and int(gap_coverage.get("fullyTargetedRouteEntryCount",0))==int(gap_coverage.get("mapRouteEntryCount",0)) and int(gap_coverage.get("uncoveredRouteEntryCount",0))==0,"全城已发布章节覆盖截止日线路目标")
	var original_city:Dictionary=Catalog._catalog.cities.shanghai.duplicate(true)
	Catalog._catalog.cities.shanghai.historyStatus="complete"
	Catalog._catalog.cities.shanghai.futurePlans=[]
	var published_ids:Array=Catalog.city_config("shanghai").chapters.map(func(entry:Dictionary):return str(entry.get("id","")))
	var future_gate:=WorldData.new_world("shanghai","campaign");future_gate.storyState.chapterIndex=published_ids.size()-1;future_gate.storyState.chapterId=str(published_ids.back());future_gate.storyState.stage="outcome";future_gate.storyState.completedChapterIds=published_ids.duplicate()
	Story.next_chapter(future_gate)
	_check(str(future_gate.storyState.phase)=="future_gap" and not bool(future_gate.storyState.freeUnlocked),"空远期列表不能当作资料已审核完成")
	_check(Story.plan_status(future_gate)=="已完成截至日历史建设；截止日后的项目篇尚未数字化","远期资料边界明确表示历史篇已完成")
	Catalog._catalog.cities.shanghai.futureStatus="complete"
	future_gate=WorldData.new_world("shanghai","campaign");future_gate.storyState.chapterIndex=published_ids.size()-1;future_gate.storyState.chapterId=str(published_ids.back());future_gate.storyState.stage="outcome";future_gate.storyState.completedChapterIds=published_ids.duplicate();Story.next_chapter(future_gate)
	_check(str(future_gate.mode)=="campaign" and not bool(Story.can_create_workshop_copy(future_gate)) and not bool(future_gate.storyState.freeUnlocked),"没有项目建设章节时不能提前解锁自由创作副本")
	Catalog._catalog.cities.shanghai.historyStatus="route_inventory_complete"
	future_gate=WorldData.new_world("shanghai","campaign");future_gate.storyState.chapterIndex=published_ids.size()-1;future_gate.storyState.chapterId=str(published_ids.back());future_gate.storyState.stage="outcome";future_gate.storyState.completedChapterIds=published_ids.duplicate();Story.next_chapter(future_gate)
	_check(str(future_gate.storyState.phase)=="history_content_gap" and Story.plan_status(future_gate)=="现有线路任务已完成，逐期历史仍待补齐","线路目标覆盖不伪装成五城逐期历史已完成")
	_check(not bool(Story.can_create_workshop_copy(future_gate)),"逐期历史仍有缺口时不能解锁自由创作副本")
	Catalog._catalog.cities.shanghai.historyStatus="complete"
	var future_plan:Dictionary={}
	for candidate in original_city.chapters:
		if not bool(candidate.get("eventOnly",false)) and not candidate.get("lineGroups",[]).is_empty():future_plan=candidate.duplicate(true);break
	future_plan.merge({"id":"acceptance-only-future","required":true,"dataStatus":"blueprint_ready","exactAlignment":"station_areas"},true)
	Catalog._catalog.cities.shanghai.futurePlans=[future_plan]
	Catalog._catalog.cities.shanghai.futureStatus="complete"
	future_gate=WorldData.new_world("shanghai","campaign");future_gate.storyState.chapterIndex=published_ids.size()-1;future_gate.storyState.chapterId=str(published_ids.back());future_gate.storyState.stage="outcome";future_gate.storyState.completedChapterIds=published_ids.duplicate();Story.next_chapter(future_gate)
	_check(str(future_gate.storyState.phase)=="future" and not bool(future_gate.storyState.freeUnlocked),"有已核验必做远期内容时先进入远期")
	_check(str(Story.chapter(future_gate).get("id",""))=="acceptance-only-future","远期按稳定编号读取对应蓝图")
	future_gate.storyState.stage="outcome";future_gate.storyState.completedChapterIds.append("acceptance-only-future");Story.next_chapter(future_gate)
	_check(str(future_gate.mode)=="campaign" and not bool(Story.can_create_workshop_copy(future_gate)) and not bool(future_gate.storyState.freeUnlocked),"伪填完成标记不能绕过独立官方范围核对")
	var workshop_copy:=Story.create_workshop_copy(future_gate)
	_check(workshop_copy.is_empty() and str(future_gate.mode)=="campaign","未满足完整交付资格时不生成假通关副本")
	Catalog._catalog.cities.shanghai=original_city
	api.queue_free();await process_frame
	if failures.is_empty():print("PASS: %d story checks" % checks);quit(0)
	else:
		for error in failures:push_error(error)
		quit(1)

func built_world(city_id:String,index:int=0) -> Dictionary:
	var world:=WorldData.new_world(city_id,"campaign");world.storyState.tutorialEnabled=false;world.storyState.stage="build"
	var all_chapters:Array=Catalog.city_config(city_id).get("chapters",[])
	var build_chapters:Array=all_chapters.filter(func(row:Dictionary):return not bool(row.get("eventOnly",false)) and not row.get("lineGroups",[]).is_empty())
	if index<0 or index>=build_chapters.size():return world
	var selected_id:=str(build_chapters[index].get("id",""));var absolute_index:=0
	for chapter_index in range(all_chapters.size()):
		if str(all_chapters[chapter_index].get("id",""))==selected_id:absolute_index=chapter_index;break
	world.storyState.chapterIndex=absolute_index;world.storyState.chapterId=selected_id
	var versions:Array=Story.chapter(world).get("story",{}).get("planVersions",[])
	world.storyPlan.planIndex=maxi(0,versions.size()-1)
	if bool(Story.chapter(world).get("requiresLineReorganization",false)):world.storyPlan["reorganizationAccepted"]=true
	# Seed only earlier lines needed to verify an interline transfer in this
	# milestone. The test fixture remains small while still modeling a saved
	# formal route from a previous chapter.
	var current_line_ids:Dictionary={}
	for group in Story.groups(world,true):current_line_ids[str(group.get("historicalLineId",""))]=true
	var needed_prior:Dictionary={}
	for transfer in Story.chapter(world).get("requiredTransfers",[]):
		for line_id in transfer.get("lineIds",[]):
			if not current_line_ids.has(str(line_id)):needed_prior[str(line_id)]=true
	for previous_index in range(absolute_index):
		for group in all_chapters[previous_index].get("lineGroups",[]):
			var line_id:=str(group.get("historicalLineId",""))
			if needed_prior.has(line_id):
				_seed_fixture_group(world,group)
	for target in Story.targets(world,true):
		var station:=WorldData.create_station(world,target.latlng,90)
		station.name=target.name;station["historicalId"]=str(target.historicalId);station["stationInstanceId"]=str(target.stationInstanceId);station["stationComplexId"]=str(target.stationComplexId);station["stationLineId"]=str(target.historicalLineId)
		var complex_id:=str(target.stationComplexId)
		if not world.stationComplexes.any(func(complex:Dictionary):return str(complex.get("id",""))==complex_id):
			world.stationComplexes.append({"id":complex_id,"name":str(target.get("name","历史站区")),"locationPrecision":"station_area_approximation","structureStatus":"not_surveyed"})
	var groups:Array=Story.groups(world,true)
	for connection in Story.chapter(world).get("requiredConnections",[]):groups.append({"name":"construction_join","stationIds":[connection.fromId,connection.toId]})
	for group in groups:
		var ids:Array=group.get("stationIds",[])
		for i in range(ids.size()-1):
			var a_instance:=Story.station_instance_id(group,str(ids[i]));var b_instance:=Story.station_instance_id(group,str(ids[i+1]))
			var a:=Story.bound_station(world,str(ids[i]),a_instance);var b:=Story.bound_station(world,str(ids[i+1]),b_instance)
			world.trackEdges.append({"id":"test_%s_%d" % [str(group.name),i],"aNodeId":TrackNetwork.station_node_id(a,"end"),"bNodeId":TrackNetwork.station_node_id(b,"start"),"geometry":"straight","depthM":-15.0,"routeIds":[]})
	return world

func _seed_fixture_group(world:Dictionary,group:Dictionary) -> void:
	var city:=WorldData.city(str(world.get("cityId","")))
	var refs:Dictionary={}
	for reference in city.get("stations",[]):refs[str(reference.get("id",""))]=reference
	var station_ids:Array=[]
	for target_id_value in group.get("stationIds",[]):
		var target_id:=str(target_id_value)
		var instance_id:=Story.station_instance_id(group,target_id)
		var existing:Dictionary={}
		for candidate in world.stations:
			if str(candidate.get("stationInstanceId",""))==instance_id:existing=candidate;break
		if existing.is_empty():
			var reference_id:=str(group.get("stationReferenceIds",{}).get(target_id,target_id))
			var reference:Dictionary=refs.get(reference_id,{})
			if reference.is_empty():continue
			existing=WorldData.create_station(world,reference.get("latlng",[]),90)
			existing["name"]=str(group.get("stationNames",{}).get(target_id,reference.get("name","车站")))
			existing["historicalId"]=target_id;existing["stationComplexId"]=target_id
			existing["stationInstanceId"]=instance_id;existing["stationLineId"]=str(group.get("historicalLineId",""))
		station_ids.append(str(existing.get("id","")))
	TrackNetwork.ensure_station_nodes(world)
	var paths:Array=[]
	for offset in range(maxi(0,station_ids.size()-1)):
		var first:Dictionary=WorldData.find_station(world,str(station_ids[offset]))
		var second:Dictionary=WorldData.find_station(world,str(station_ids[offset+1]))
		var edge_id:="fixture_%s_%s_%s" % [str(group.get("historicalLineId","line")),str(group.stationIds[offset]),str(group.stationIds[offset+1])]
		var has_edge:=false
		for edge in world.trackEdges:
			if str(edge.get("id",""))==edge_id:has_edge=true;break
		if not has_edge:world.trackEdges.append({"id":edge_id,"aNodeId":TrackNetwork.station_node_id(first,"end"),"bNodeId":TrackNetwork.station_node_id(second,"start"),"geometry":"straight","depthM":-15.0,"routeIds":[]})
		paths.append([{"id":edge_id,"forward":true}])
	var line_id:=str(group.get("historicalLineId",""))
	var route:Dictionary={"id":"historical_%s" % line_id,"name":str(group.get("name",line_id)),"historicalLineId":line_id,"networkBased":true,"stationOrder":station_ids,"open":true,"directions":[{"id":"forward","stationIds":station_ids,"edgePathsBySegment":paths}]}
	var replaced:=false
	for route_index in range(world.routes.size()):
		if str(world.routes[route_index].get("historicalLineId",""))==line_id:world.routes[route_index]=route;replaced=true;break
	if not replaced:world.routes.append(route)

func _confirm_required_transfers(world:Dictionary,evaluation:Dictionary) -> void:
	for transfer in evaluation.get("requiredTransfers",[]):
		var exists:=false
		for saved in world.get("transferConnections",[]):
			if str(saved.get("id",""))==str(transfer.get("id","")):exists=true;break
		if exists:continue
		world.transferConnections.append({"id":str(transfer.get("id","")),"name":str(transfer.get("name","换乘")),"complexId":str(transfer.get("complexId","")),"stationInstanceIds":transfer.get("stationInstanceIds",[]).duplicate(),"lineIds":transfer.get("lineIds",[]).duplicate(),"status":"active","precision":str(transfer.get("precision","schematic")),"source":str(transfer.get("source","")),"effectiveDate":str(Story.chapter(world).get("date",""))})

func _confirm_service_transitions(world:Dictionary,evaluation:Dictionary) -> void:
	for proposal in evaluation.get("serviceTransitions",[]):
		var exists:=false
		for saved in world.get("serviceRanges",[]):
			if str(saved.get("id",""))==str(proposal.get("id","")):exists=true;break
		if exists:continue
		var record:Dictionary=proposal.duplicate(true);record.erase("displayStationNames");record.erase("focusLatlng");world.serviceRanges.append(record)

func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)


func _reach_first_construction(app:Control) -> void:
	while app.saves_in_flight>0:await process_frame
	var count:=0
	while bool(Story.chapter(app.world).get("eventOnly",false)) and count<20:
		app._begin_chapter()
		var confirmed:Dictionary=Story.commit_chapter(app.world,int(app.world.revision))
		_check(bool(confirmed.get("ok",false)),"introductory event confirms through normal story command")
		if not bool(confirmed.get("ok",false)):return
		Story.next_chapter(app.world);count+=1
	app._enter(app.world)
