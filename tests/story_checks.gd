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
	_check(WorldData.SAVE_VERSION==20,"故事存档格式20")
	_check(Catalog.validate_catalog(WorldData.cities()).is_empty(),"五城资料引用校验")
	var sh_events:Array=Catalog.city_config("shanghai").historicalEvents
	_check(sh_events.filter(func(e:Dictionary):return str(e.date)=="1996-12-28").size()==1 and sh_events.filter(func(e:Dictionary):return str(e.date)=="1997-07-01").size()==1,"上海时间轴区分1996分段与1997贯通，不重复记载同一节点")
	var sz:=WorldData.new_world("shenzhen","campaign")
	_check(not Story.groups(sz,true)[1].stationIds.has("shenzhen-s68"),"2004年开通范围不能混入2007年才通车的福田口岸")
	var gz:=WorldData.new_world("guangzhou","campaign")
	_check(str(Story.targets(gz)[0].name)=="西朗","广州早期样板使用当时名称")
	var bj:=WorldData.new_world("beijing","campaign");bj.storyState.chapterIndex=1
	var early:Array=Story.groups(bj,true)[0].stationIds
	_check(early.size()==10 and early.find("beijing-s59")<early.find("beijing-s60") and not early.has("beijing-s56"),"1971年10站站序与未运营站排除回归")
	var sh:=WorldData.new_world("shanghai","campaign");sh.storyState.chapterIndex=1
	var historic_names:Dictionary=Story.groups(sh,true)[0].get("stationNames",{})
	_check(str(historic_names.get("shanghai-s118",""))=="黄陂南路" and str(historic_names.get("shanghai-s422",""))=="新龙华","上海早期不使用后来的冠名与新站名")
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
		for index in range(chapters.size()):
			var world:=built_world(str(city.id),index)
			var before:=JSON.stringify(world.storyState)
			var result:=Story.evaluate(world)
			_check(bool(result.complete),"%s可以只靠正确建设通过：%s" % [str(chapters[index].id),JSON.stringify(result.issues)])
			_check(JSON.stringify(world.storyState)==before,"评估和打开面板不推进故事")
			var stale:=Story.commit_chapter(world,int(world.revision)-1)
			_check(not bool(stale.ok),"拒绝过期规划确认")
			var committed:=Story.commit_chapter(world,int(world.revision))
			_check(bool(committed.ok) and str(world.storyState.stage)=="outcome","确认后进入成果而非等待乘客")
			_check(world.history.undo.is_empty() and world.history.redo.is_empty(),"已确认节点成为撤销边界")
			_check(not bool(Story.commit_chapter(world,int(world.revision)).get("ok",true)),"重复确认不重记历史节点")
			var replay:=Story.replay_copy(world,0)
			_check(str(replay.gameId)!=str(world.gameId) and replay.stations.is_empty(),"首个里程碑复盘从建设前独立开始，不带入未来站轨")
			_check(str(replay.mode)=="campaign" and not bool(replay.storyState.freeUnlocked),"复盘不能绕过历史与远期条件提前解锁自由创作")
			Story.next_chapter(world)
			_check(int(world.storyState.chapterIndex)==index+1,"下一章由明确操作推进")
	var broken:=built_world("shanghai",0)
	broken.trackEdges.clear()
	_check(not bool(Story.evaluate(broken).complete),"仅放站、没有轨道不能通过")
	var unnamed:=built_world("shanghai",0)
	for station in unnamed.stations:station.erase("historicalId")
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
	var history:=CommandHistory.new();history.attach(revision_world)
	history.execute("采用下一版",func(state:Dictionary):state.storyPlan.planIndex=1)
	history.undo();_check(int(revision_world.storyPlan.planIndex)==0,"方案修订可以撤销")
	history.redo();_check(int(revision_world.storyPlan.planIndex)==1,"方案修订可以重做")
	var api:=App.new();root.add_child(api)
	await process_frame
	_check(not auto_accept_quit,"关闭窗口由保存结果决定，不由引擎提前退出")
	api._new_game("shanghai",true)
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
		api._execute("辅助完成重复建设",func(state:Dictionary):
			for key in ["stations","trackNodes","trackEdges"]:state[key]=assistant.state[key]
			state.storyPlan["assisted"]=true)
		_check(bool(Story.evaluate(api.world).complete),"真实默认朝向和辅助可通过首章")
		api._undo(false)
		_check(api.world.stations.size()==2 and not bool(api.world.storyPlan.get("assisted",false)),"撤销辅助同时恢复站轨和辅助标记")
		api._undo(true)
		_check(api.world.stations.size()==5 and bool(api.world.storyPlan.get("assisted",false)),"重做辅助完整恢复")
	for city in WorldData.cities():
		api._new_game(str(city.id),false);api.world.storyState.learnedTools=true
		var chapter_count:int=Catalog.city_config(str(city.id)).get("chapters",[]).size()
		for chapter_index in range(chapter_count):
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
			for key in ["stations","trackNodes","trackEdges"]:api.world[key]=preview.state[key]
			if bool(Story.chapter(api.world).get("requiresLineReorganization",false)):
				_check(not bool(Story.evaluate(api.world).complete),"重组章节不能只凭站轨完成")
				api._tool("line");api._confirm_line_reorganization()
			var result:=Story.evaluate(api.world)
			_check(bool(result.complete),"%s/%d 累计故事可以通过：%s" % [str(city.id),chapter_index,JSON.stringify(result.issues)])
			if not bool(result.complete):break
			api._check();api._commit_chapter()
			_check(not api.dirty and api.save_error.is_empty(),"历史节点与镜头一并保存，界面不误报未保存")
			api._next()
			_check(not api.dirty and api.save_error.is_empty(),"章节转换保存完成后保持已保存状态")
		_check(str(api.world.storyState.get("phase",""))=="history_gap" and not bool(api.world.storyState.freeUnlocked),"样板结束停在资料边界，不虚假解锁全史")
	var original_city:Dictionary=Catalog._catalog.cities.shanghai.duplicate(true)
	Catalog._catalog.cities.shanghai.historyStatus="complete"
	Catalog._catalog.cities.shanghai.futurePlans=[]
	var future_gate:=WorldData.new_world("shanghai","campaign");future_gate.storyState.chapterIndex=3;future_gate.storyState.stage="outcome"
	Story.next_chapter(future_gate)
	_check(str(future_gate.storyState.phase)=="future_gap" and not bool(future_gate.storyState.freeUnlocked),"空远期列表不能当作资料已审核完成")
	Catalog._catalog.cities.shanghai.futureStatus="complete"
	future_gate=WorldData.new_world("shanghai","campaign");future_gate.storyState.chapterIndex=3;future_gate.storyState.stage="outcome";Story.next_chapter(future_gate)
	_check(str(future_gate.mode)=="workshop" and bool(future_gate.storyState.freeUnlocked),"明确审核后没有必做远期章节时可以解锁创作")
	var future_plan:Dictionary=original_city.chapters[0].duplicate(true)
	future_plan.merge({"id":"acceptance-only-future","required":true,"dataStatus":"blueprint_ready","exactAlignment":"station_areas"},true)
	Catalog._catalog.cities.shanghai.futurePlans=[future_plan]
	future_gate=WorldData.new_world("shanghai","campaign");future_gate.storyState.chapterIndex=3;future_gate.storyState.stage="outcome";Story.next_chapter(future_gate)
	_check(str(future_gate.storyState.phase)=="future" and not bool(future_gate.storyState.freeUnlocked),"有已核验必做远期内容时先进入远期")
	_check(str(Story.chapter(future_gate).get("id",""))=="acceptance-only-future","远期按稳定编号读取对应蓝图")
	future_gate.storyState.stage="outcome";Story.next_chapter(future_gate)
	_check(str(future_gate.mode)=="workshop" and bool(future_gate.storyState.freeUnlocked),"远期确认后在同一进度解锁创作，测试蓝图不进入发行数据")
	Catalog._catalog.cities.shanghai=original_city
	api.queue_free();await process_frame
	if failures.is_empty():print("PASS: %d story checks" % checks);quit(0)
	else:
		for error in failures:push_error(error)
		quit(1)

func built_world(city_id:String,index:int=0) -> Dictionary:
	var world:=WorldData.new_world(city_id,"campaign");world.storyState.chapterIndex=index;world.storyState.tutorialEnabled=false;world.storyState.stage="build"
	var versions:Array=Story.chapter(world).get("story",{}).get("planVersions",[])
	world.storyPlan.planIndex=maxi(0,versions.size()-1)
	if bool(Story.chapter(world).get("requiresLineReorganization",false)):world.storyPlan["reorganizationAccepted"]=true
	for target in Story.targets(world,true):
		var station:=WorldData.create_station(world,target.latlng,90)
		station.name=target.name;station["historicalId"]=str(target.id)
	var groups:Array=Story.groups(world,true)
	for connection in Story.chapter(world).get("requiredConnections",[]):groups.append({"name":"construction_join","stationIds":[connection.fromId,connection.toId]})
	for group in groups:
		var ids:Array=group.get("stationIds",[])
		for i in range(ids.size()-1):
			var a:=Story.bound_station(world,str(ids[i]));var b:=Story.bound_station(world,str(ids[i+1]))
			world.trackEdges.append({"id":"test_%s_%d" % [str(group.name),i],"aNodeId":TrackNetwork.station_node_id(a,"end"),"bNodeId":TrackNetwork.station_node_id(b,"start"),"geometry":"straight","depthM":-15.0,"routeIds":[]})
	return world

func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)

