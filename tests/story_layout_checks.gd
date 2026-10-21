extends SceneTree

const App=preload("res://scripts/main.gd")
const Ui=preload("res://scripts/ui_theme.gd")
var failures:Array[String]=[]
var checks:=0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():push_error("Explicit isolated data directory required");quit(1);return
	var app:=App.new();root.add_child(app)
	await process_frame
	for resolution in [Vector2i(1366,768),Vector2i(1600,980),Vector2i(1920,1080)]:
		root.size=resolution
		for scale in [1.0,1.25,1.5,1.75]:
			app.ui_scale=scale;app.theme=Ui.create_theme(app.face,app.strong_face,scale);app._rescale()
			await process_frame
			await process_frame
			app._layout()
			_check(app.menu.position.x>=0 and app.menu.position.y>=0,"菜单位于窗口内")
			_check(app.menu.get_global_rect().end.x<=resolution.x+1 and app.menu.get_global_rect().end.y<=resolution.y+1,"菜单边界可达")
			app._new_game("shanghai",true)
			await process_frame
			await process_frame
			app._begin_chapter()
			await process_frame
			_check(app.map_area.size.y>=360,"%s/%s地图高度>=360: %s" % [resolution,scale,app.map_area.size.y])
			_check(app.station_button.get_global_rect().end.y<=resolution.y,"站点工具未被裁切")
			_check(app.track_button.get_global_rect().end.x<=resolution.x,"轨道工具未被裁切")
			app._tool("station")
			var target:Dictionary=preload("res://scripts/story_session.gd").targets(app.world)[0]
			app._focus_tutorial()
			var focus_point:Vector2=app.map_view._to_screen(target.latlng)
			_check(app.usable_map_rect().has_point(focus_point),"首章目标避开详情抽屉")
			app._click(target.latlng,"blueprint",str(target.id),"")
			await process_frame
			app._layout()
			_check(is_instance_valid(app.confirm_button),"确认区存在")
			_check(app.confirm_button.get_global_rect().end.y<=resolution.y,"确认按钮始终可达")
			_check(not app.left_panel.visible or not app.right_panel.visible or not app._narrow(),"窄窗口左右抽屉互斥")
			app._show_beat(StoryBeats.entries(app.world)[0])
			await process_frame
			await process_frame
			app._layout()
			_check(app.map_area.get_global_rect().encloses(app.beat_panel.get_global_rect()),"地点故事浮层位于地图内")
			_check(not app.beat_panel.get_global_rect().intersects(app.confirm_button.get_global_rect()),"地点故事不遮挡确认按钮")
			app._close_beat()
			app.world.storyState.chapterIndex=3;app.world.storyState["chapterId"]="sh-line1-1997";app.world.storyState.learnedTools=true
			app._tool("line")
			await process_frame
			_check(is_instance_valid(app.confirm_button),"贯通章节有真实线路整理确认按钮")
			_check(app.confirm_button.get_global_rect().end.y<=resolution.y,"长站序滚动不带走重组确认区")
			app._saves()
			await process_frame
			await process_frame
			await process_frame
			_check(is_instance_valid(app.save_overlay),"存档窗口实际创建")
			var d:Control=app.save_panel
			_check(d.get_global_rect().end.x<=resolution.x and d.get_global_rect().end.y<=resolution.y,"存档窗口不超出视口 %s / %s: %s" % [resolution,scale,d.size])
			var fixed_buttons:=d.find_children("*","Button",true,false)
			for control in fixed_buttons:
				var ancestor:Node=control.get_parent();var in_list:=false
				while ancestor!=null and ancestor!=d:
					if ancestor is ScrollContainer:in_list=true;break
					ancestor=ancestor.get_parent()
				if not in_list:_check(d.get_global_rect().encloses(control.get_global_rect()),"存档固定操作在面板内")
			app.save_overlay.queue_free()
			app._settings()
			await process_frame
			await process_frame
			_check(app.save_panel.get_global_rect().end.y<=resolution.y,"设置页滚动容器位于视口内")
			app.save_overlay.queue_free()
			app._show_menu()
			await process_frame
	app._new_game("shenzhen",false)
	app.world.storyState["phase"]="future_gap"
	app.world.storyState["chapterId"]=""
	app.world.storyState["chapterIndex"]=999
	app._refresh()
	await process_frame
	var gap_labels:Array[String]=[]
	for node in app.left_panel.find_children("*","Label",true,false):gap_labels.append(str(node.text))
	_check(gap_labels.any(func(value:String):return value.contains("当前章节目标覆盖")),"后续资料边界页显示实际线路章节覆盖，而非空白旧页")
	_check(gap_labels.any(func(value:String):return value.contains("历史里程碑区间")),"后续资料边界页显示可玩与未制作里程碑数量")
	_check(app.year.text.contains("已完成截至日历史建设") or app.year.text.contains("截止日后的项目篇尚未数字化"),"顶部状态明确区分历史完成与截止日后规划内容")
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,980);app.ui_scale=1.0;app.theme=Ui.create_theme(app.face,app.strong_face,1.0);app._rescale()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/story-0.20-menu-1600x980.png")
		app._new_game("shenzhen",false);app._begin_chapter()
		var timeout:=Time.get_ticks_msec()+20000
		while app.map_view.base_map_features.is_empty() and Time.get_ticks_msec()<timeout:await process_frame
		_check(not app.map_view.base_map_features.is_empty(),"截图前明确等待本地底图就绪")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/story-0.20-plan-revision-1600x980.png")
		root.size=Vector2i(1366,768);app.ui_scale=1.75;app.theme=Ui.create_theme(app.face,app.strong_face,1.75);app._rescale()
		await process_frame
		app._saves()
		for frame in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/story-0.20-save-1366x768-175.png")
	app.queue_free();await process_frame
	if failures.is_empty():print("PASS: %d story layout checks" % checks);quit(0)
	else:
		for error in failures:push_error(error)
		quit(1)

func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
