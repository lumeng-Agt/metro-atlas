extends SceneTree

const App=preload("res://scripts/main.gd")
const Story=preload("res://scripts/story_session.gd")
var checks:=0
var failures:Array[String]=[]

func _initialize() -> void:call_deferred("_run")

func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	UiPreferences.save_onboarding_completed(false)
	var app:=App.new();root.add_child(app);await process_frame
	app._new_game("shanghai",true);app._begin_chapter();await process_frame
	check(StoryTutorial.active(app.world),"首局首章操作教学开启")
	var fresh:=app.world.duplicate(true)
	app.world.storyState.learnedTools=true
	var all:=app._assist_candidate()
	check(str(all.get("issue",""))=="","首章可完整建设")
	if all.has("state"):
		for key in ["stations","trackNodes","trackEdges"]:app.world[key]=all.state[key]
	app._check();app._commit_chapter()
	check(str(app.world.storyState.tutorialStatus)=="completed" and not StoryTutorial.active(app.world),"首章确认后明确结束教学")
	check(UiPreferences.load_onboarding_completed(),"学会记录独立保存")
	app._next();app._begin_chapter();app._focus_tutorial()
	check(not bool(app.world.storyState.tutorialEnabled),"第二章不继承教程开关")
	check(Story.blueprint(app.world).stations.size()==Story.targets(app.world).size(),"第二章显示全部本期目标")
	for city in WorldData.cities():
		app._new_game(str(city.id),true)
		check(not StoryTutorial.active(app.world),"已学会后%s首章不自动教学" % city.id)
		for chapter in CampaignSystem.city_config(str(city.id)).chapters:
			app.world.storyState.chapterId=chapter.id;app.world.storyState.stage="build"
			var chapter_beats:Array=chapter.get("story",{}).get("beats",[])
			if chapter_beats.is_empty():
				check(not str(chapter.get("source","")).is_empty() and (bool(chapter.get("eventOnly",false)) or not chapter.get("lineGroups",[]).is_empty()),"%s无地点旁注时仍须保留来源与明确节点类型" % chapter.id)
				continue
			var beat:Dictionary=chapter_beats[0]
			var untouched:=JSON.stringify(app.world.storyState)
			check(StoryBeats.eligible(app.world,"select",["unknown"]).is_empty(),"无关点击不触发故事")
			check(not StoryBeats.eligible(app.world,"select",beat.stationIds).is_empty(),"相关地点触发故事")
			check(JSON.stringify(app.world.storyState)==untouched,"查询触发条件不修改章节")
			StoryBeats.mark_read(app.world,str(beat.id))
			check(StoryBeats.eligible(app.world,"build_station",beat.stationIds).is_empty(),"建设和撤销后不重复弹出已读故事")
			check(not StoryBeats.find(app.world,str(beat.id)).is_empty(),"已读故事仍可重新阅读")
			check(str(Story.profile(app.world).parameterStatus.depthM)=="game_estimate","未知埋深不伪装成历史实测")
			check(not bool(app.world.has("simulation")),"故事会话无客流后台")
	# Existing unfinished stories restore their own status even after another city taught controls.
	app._enter(fresh)
	check(StoryTutorial.active(app.world),"旧首章恢复自身尚未完成的教学")
	StoryTutorial.skip(app.world)
	check(not StoryTutorial.active(app.world) and str(app.world.storyState.tutorialStatus)=="skipped","跳过与完成分开")
	UiPreferences.save_onboarding_completed(false);app._new_game("beijing",true)
	check(StoryTutorial.active(app.world),"跳过不冒充全局学会")
	var replay:=WorldData.new_world("shanghai","campaign");replay["replayOf"]="original"
	StoryTutorial.configure(replay,false)
	check(not StoryTutorial.active(replay),"复盘默认不教学")
	var sz:=WorldData.new_world("shenzhen","campaign")
	check(Story.node_date(sz)=="1998-05","初始方案显示1998而不是最终开通日期")
	sz.storyPlan.planIndex=1
	check(Story.node_date(sz)=="2000-05","节点年代跟随当前方案")
	check(Story.plan_change(sz,0,1).contains("新增目标"),"方案差异列出新增站区")
	sz.storyState.stage="outcome"
	check(Story.node_date(sz)=="2004-12-28","开通成果显示实际开通日期")
	# Migration must preserve identity, geometry and undo history exactly.
	var v18:=fresh.duplicate(true);v18.schemaVersion=18;v18.storyState.tutorialEnabled=true;v18.storyState.erase("tutorialStatus");v18.storyState.erase("beatRead")
	var original:=JSON.stringify(v18);var path:=SaveManager.root_path().path_join("v18.json")
	SaveManager._write_atomic(path,original)
	var migrated:=SaveManager.load_file(path)
	check(bool(migrated.ok) and int(migrated.world.schemaVersion)==WorldData.SAVE_VERSION,"格式18统一入口迁移19")
	check(str(migrated.world.gameId)==str(v18.gameId),"迁移不另建游戏编号")
	check(JSON.stringify(migrated.world.history)==JSON.stringify(v18.history),"迁移保留历史")
	check(FileAccess.get_file_as_string(path)==original,"原始文件不被迁移覆盖")
	check(FileAccess.file_exists(SaveManager.root_path().path_join("originals/v18_%s.json" % original.sha256_text())),"格式18迁移独立内容备份")
	check(StoryTutorial.active(migrated.world),"格式18首章继续原教学")
	v18.storyState.chapterIndex=1;v18.storyState.chapterId="sh-line1-1995";v18.storyState.tutorialEnabled=true
	var later:=SaveManager.migrate(v18)
	check(not StoryTutorial.active(later) and not later.storyState.tutorialEnabled,"格式18后续章节关闭重复教学")
	v18.storyState.tutorialEnabled=false;v18.storyState.completedChapterIds=["sh-line1-1993"]
	check(str(SaveManager.migrate(v18).storyState.tutorialStatus)=="skipped","旧档跳过后即使通关首章也不冒充完成教学")
	app._enter(later);app.world.storyState.stage="build"
	var beat:Dictionary=StoryBeats.entries(app.world)[0]
	app._show_beat(beat);await process_frame;app._layout()
	check(str(app.active_beat_id)==str(beat.id),"实际故事浮层创建")
	check(not app.beat_panel.get_global_rect().intersects(app.station_button.get_global_rect()),"故事浮层不盖建设工具")
	check(bool(SaveManager.save_world(app.world).ok),"故事已读可保存")
	var loaded:=SaveManager.load_file(SaveManager.save_path(str(app.world.gameId)))
	check(loaded.world.storyState.beatRead.has(str(beat.id)),"重载保留已读记录")
	check(StoryBeats.eligible(loaded.world,"select",beat.stationIds).is_empty(),"重载不重复弹出")
	var bad:Dictionary=loaded.world.duplicate(true);bad.storyState.beatRead=[]
	check(not SaveManager.validate(bad).is_empty(),"拒绝损坏的阅读容器")
	# A single palette and preparation path also serves the first uncached frame.
	var points:=PackedVector2Array([Vector2.ZERO,Vector2(1,0)])
	var f:Dictionary={"kind":"road_major","name":"短主路","points":points,"pairs":points,"bounds":Rect2(Vector2.ZERO,Vector2.ONE)}
	var batch:=MapView._prepare_basemap_draw_batches_for([f],13,10)
	check(batch.majorLines.size()==2,"短主路仍保留，不能因片段短造成道路断裂")
	check(batch.roadLabels.size()==1,"城市尺度主要道路有名称")
	check(absf(MapView._road_angle(PackedVector2Array([Vector2.ZERO,Vector2(1,1)]))+PI/4)<0.01,"路名跟随屏幕道路切线")
	check(MetroMapStyle.CANVAS!=MetroMapStyle.WATER and MetroMapStyle.BUILDING!=MetroMapStyle.CANVAS,"水域建筑与街区有独立样式")
	var base_index:=0
	for index in range(CampaignSystem._catalog.cities.shanghai.chapters.size()):
		var candidate:Dictionary=CampaignSystem._catalog.cities.shanghai.chapters[index]
		if not bool(candidate.get("eventOnly",false)) and not candidate.get("lineGroups",[]).is_empty():base_index=index;break
	var base:Dictionary=CampaignSystem._catalog.cities.shanghai.chapters[base_index].duplicate(true)
	var target_id:=str(base.lineGroups[0].stationIds[0])
	CampaignSystem._catalog.cities.shanghai.chapters[base_index]["stationProfiles"]={target_id:{"lengthM":150.0,"heading":37.2,"depthM":-14.5,"parameterStatus":{"depthM":"public_reference"},"note":"隔离验收配置，不发布为史实"}}
	var profile_world:=WorldData.new_world("shanghai","campaign");StoryTutorial.configure(profile_world,false)
	app._enter(profile_world);app._begin_chapter();app._tool("station")
	var target:Dictionary=Story.targets(app.world)[0]
	app._click(target.latlng,"blueprint",target_id,"")
	check(is_equal_approx(float(app.map_view.draft_station.lengthM),150.0) and is_equal_approx(float(app.map_view.draft_station.heading),37.2),"站点核验配置优先于统一站体与蓝图估算朝向")
	check(is_equal_approx(float(app.map_view.draft_station.depthM),-14.5),"已有核验埋深可用于对应目标")
	check(Story.profile(app.world,target_id).parameterStatus.has("lengthM"),"站点覆盖不丢失其他参数来源状态")
	CampaignSystem._catalog.cities.shanghai.chapters[base_index]=base
	app._new_game("shenzhen",false);app._begin_chapter()
	var before_plan:=JSON.stringify(app.world.storyPlan)
	app._view_plan(2)
	check(JSON.stringify(app.world.storyPlan)==before_plan and app.world.routes.is_empty(),"只读历史方案不修改目标或生成开通线路")
	check(str(app.world.storyState.stage)=="build","只读查看不改变故事步骤")
	app._tool("station")
	check(app.plan_view_index==-1,"施工时返回正式方案")
	app._revise()
	var dialogs:=app.find_children("*","ConfirmationDialog",true,false)
	if not dialogs.is_empty():dialogs[-1].canceled.emit();await process_frame
	check(JSON.stringify(app.world.storyPlan)==before_plan,"取消方案变化不修改正式历史状态")
	app.queue_free();await process_frame
	if failures.is_empty():print("PASS: %d version 0.19 checks" % checks);quit(0)
	else:
		for error in failures:push_error(error)
		quit(1)
