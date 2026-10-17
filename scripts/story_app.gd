extends Control

const BUILD_VERSION := "0.20.0 · 2026.10.18"
const Tutorial = preload("res://scripts/story_tutorial.gd")
const Beats = preload("res://scripts/story_beats.gd")
const Story = preload("res://scripts/story_session.gd")
const MapScript = preload("res://scripts/map_view.gd")
const Rules = preload("res://scripts/story_construction.gd")
const Ui = preload("res://scripts/ui_theme.gd")
const Prefs = preload("res://scripts/ui_preferences.gd")
const Spotlight = preload("res://scripts/tutorial_spotlight.gd")

var world: Dictionary = {}
var history := CommandHistory.new()
var rules := Rules.new()
var map_view: MapView
var tool := "select"
var selected_kind := ""
var selected_id := ""
var pending_track: Dictionary = {}
var evaluation: Dictionary = {}
var ui_scale := 1.0
var face: Font
var strong_face: Font
var frame: VBoxContainer
var map_area: Control
var left_panel: PanelContainer
var right_panel: PanelContainer
var left: VBoxContainer
var right: VBoxContainer
var actions: VBoxContainer
var menu: PanelContainer
var save_overlay: Control
var save_panel: PanelContainer
var year: Label
var save_badge: Button
var hint: Label
var undo_button: Button
var redo_button: Button
var station_button: Button
var track_button: Button
var line_button: Button
var begin_button: Button
var revision_button: Button
var check_button: Button
var confirm_button: Button
var spotlight: Control
var page := "story"
var dirty := false
var save_error := ""
var problem := ""
var auto_seconds := 0.0
var auto_enabled := true
var auto_interval_seconds := 300.0
var display_seconds := 0.0
var display_paused := false
var display_enabled := true
var last_preview_usec := 0
var show_left := true
var show_right := false
var line_stops: Array[String] = []
var preview_station: Dictionary = {}
var beat_panel: PanelContainer
var active_beat_id := ""
var practice_return: Dictionary = {}
var plan_view_index := -1
var guide_map_step := ""
var advanced_edit := false
var end_button:Button
var nav_pages:HFlowContainer
var tool_flow:HFlowContainer

func _ready() -> void:
	get_tree().auto_accept_quit=false
	if SaveManager.root_path().is_empty():push_error("--data-dir必须指定绝对目录，已停止启动。");get_tree().quit(2);return
	RenderingServer.set_default_clear_color(Ui.CANVAS)
	WorldData.load_assets()
	ui_scale=Prefs.load_scale();auto_enabled=Prefs.load_timed_autosave_enabled();auto_interval_seconds=Prefs.load_timed_autosave_interval()*60.0
	var base:=load("res://fonts/NotoSansSC.ttf") as Font
	var regular:=FontVariation.new();regular.base_font=base;regular.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):500.0};face=regular
	var bold:=FontVariation.new();bold.base_font=base;bold.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):700.0};strong_face=bold
	theme=Ui.create_theme(face,strong_face,ui_scale)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_show_menu()

func button(text:String,callback:Callable) -> Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size.y=44*ui_scale
	b.add_theme_font_size_override("font_size",roundi(18*ui_scale));b.pressed.connect(callback)
	if text.begins_with("确认") or text.begins_with("进入") or text.begins_with("展开本章"):
		b.add_theme_stylebox_override("normal",Ui._box(Ui.ACCENT,Ui.ACCENT,6));b.add_theme_stylebox_override("hover",Ui._box(Color("#73d6c4"),Ui.ACCENT,6))
		b.add_theme_color_override("font_color",Color("#102b2b"));b.add_theme_color_override("font_hover_color",Color("#102b2b"))
	return b

func label(text:String,pixels:int=18,bold:bool=false) -> Label:
	var l:=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size",roundi(pixels*ui_scale));l.add_theme_font_override("font",strong_face if bold else face)
	return l

func clear(node:Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()

func _build() -> void:
	frame=VBoxContainer.new();frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);frame.add_theme_constant_override("separation",0);add_child(frame)
	var top_panel:=PanelContainer.new();frame.add_child(top_panel)
	var top:=HFlowContainer.new();top_panel.add_child(top)
	top.add_child(button("☰  故事",_open_page.bind("story")))
	year=label("",18,true);year.custom_minimum_size.x=240;year.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(year)
	undo_button=button("↶",_undo.bind(false));top.add_child(undo_button)
	redo_button=button("↷",_undo.bind(true));top.add_child(redo_button)
	save_badge=button("保存",_save);top.add_child(save_badge)
	top.add_child(button("存档",_saves));top.add_child(button("菜单",_game_menu))
	map_area=Control.new();map_area.size_flags_vertical=Control.SIZE_EXPAND_FILL;frame.add_child(map_area)
	map_view=MapScript.new();map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);map_area.add_child(map_view)
	map_view.bold_font=strong_face;map_view.ui_scale=ui_scale
	map_view.map_clicked.connect(_click);map_view.cancel_requested.connect(_cancel)
	map_view.station_dragged.connect(_drag_station);map_view.station_drag_finished.connect(_finish_station_drag)
	map_view.draft_station_changed.connect(_station_changed)
	map_view.curve_control_previewed.connect(_preview_curve);map_view.curve_control_finished.connect(_finish_curve)
	map_view.camera_changed.connect(func(_center:Array,_zoom:int):_mark_dirty())
	rules.map_view=map_view
	left_panel=PanelContainer.new();map_area.add_child(left_panel)
	var ls:=ScrollContainer.new();ls.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;left_panel.add_child(ls)
	left=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;ls.add_child(left)
	right_panel=PanelContainer.new();map_area.add_child(right_panel)
	var rb:=VBoxContainer.new();right_panel.add_child(rb)
	var rs:=ScrollContainer.new();rs.size_flags_vertical=Control.SIZE_EXPAND_FILL;rs.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;rb.add_child(rs)
	right=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rs.add_child(right)
	actions=VBoxContainer.new();rb.add_child(actions)
	var bottom_panel:=PanelContainer.new();frame.add_child(bottom_panel)
	var bottom:=VBoxContainer.new();bottom_panel.add_child(bottom)
	var center:=CenterContainer.new();bottom.add_child(center)
	var tools:=HFlowContainer.new();tools.alignment=FlowContainer.ALIGNMENT_CENTER;tool_flow=tools;center.add_child(tools)
	tools.add_child(button("选择",_tool.bind("select")))
	station_button=button("车站",_tool.bind("station"));tools.add_child(station_button)
	track_button=button("铺轨",_tool.bind("track"));tools.add_child(track_button)
	line_button=button("线路整理",_tool.bind("line"));tools.add_child(line_button)
	end_button=button("结束操作",_tool.bind("select"));tools.add_child(end_button)
	tools.add_child(button("图层",_layers))
	hint=label("",15);bottom.add_child(hint)
	var attribution:=LinkButton.new();attribution.text="© OpenStreetMap · 现代地理参考底图";attribution.pressed.connect(func():_message("地图来源","现代底图仅作位置参考，不是当年的城市环境或工程线位。OSM / Geofabrik派生数据依据ODbL 1.0提供。"))
	attribution.custom_minimum_size.y=24;attribution.add_theme_font_size_override("font_size",12);bottom.add_child(attribution)
	spotlight=Spotlight.new();add_child(spotlight)
	map_area.resized.connect(_layout)
	call_deferred("_layout")

func _layout() -> void:
	if not is_instance_valid(map_area):return
	if is_instance_valid(tool_flow):tool_flow.custom_minimum_size.x=minf(740*ui_scale,maxf(220,size.x-48))
	var w:=minf(420,maxf(320,320*ui_scale));var h:=maxf(100,map_area.size.y-24)
	left_panel.position=Vector2(12,12);left_panel.size=Vector2(minf(w,map_area.size.x-24),h)
	right_panel.size=Vector2(minf(w,map_area.size.x-24),h);right_panel.position=Vector2(map_area.size.x-right_panel.size.x-12,12)
	left_panel.visible=show_left and not world.is_empty();right_panel.visible=show_right and not world.is_empty()
	if _narrow() and show_left and show_right:left_panel.hide()
	if is_instance_valid(beat_panel):
		var available := usable_map_rect()
		beat_panel.size=Vector2(minf(380,available.size.x-16),minf(230,available.size.y-16))
		beat_panel.position=Vector2(available.position.x+8,available.end.y-beat_panel.size.y-8)
	if is_instance_valid(save_panel):
		save_panel.size=Vector2(minf(1050,size.x-32),minf(740,size.y-32));save_panel.position=(size-save_panel.size)*0.5
	if is_instance_valid(menu):menu.size=Vector2(minf(760*minf(ui_scale,1.15),size.x-40),minf(700*minf(ui_scale,1.15),size.y-40));menu.position=(size-menu.size)*0.5

func _narrow() -> bool:
	return size.x<1650 or ui_scale>1.25

func _process(delta:float) -> void:
	if world.is_empty() or is_instance_valid(menu):return
	if display_enabled and not display_paused:
		display_seconds+=delta;map_view.presentation_seconds=display_seconds;map_view.requested_train_redraw()
	if dirty and auto_enabled:
		auto_seconds+=delta
		if auto_seconds>=auto_interval_seconds:_save(true)
	if tool=="track" and not map_view.track_start_ref.is_empty() and map_view.track_end_ref.is_empty() and not map_view.hover_latlng.is_empty() and Time.get_ticks_usec()-last_preview_usec>33333:
		last_preview_usec=Time.get_ticks_usec()
		var hit:=map_view._pick(map_view._to_screen(map_view.hover_latlng))
		if str(hit.get("type",""))!="endpoint_choice":_track_preview(_ref(hit.get("latlng",map_view.hover_latlng),str(hit.get("type","")),str(hit.get("id","")),str(hit.get("side","")),float(hit.get("t",-1))))
	_focus_tutorial()

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if world.is_empty():get_tree().quit()
		else:_leave(func():get_tree().quit())
	elif what==NOTIFICATION_APPLICATION_FOCUS_OUT and not world.is_empty():
		display_paused=true
		if dirty:_save()

func _show_menu() -> void:
	if is_instance_valid(menu):remove_child(menu);menu.queue_free()
	world={};frame.hide();map_view.set_world({});map_view.set_blueprint({});spotlight.clear_focus()
	menu=PanelContainer.new();add_child(menu)
	var margin:=MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:margin.add_theme_constant_override(side,24)
	menu.add_child(margin)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;margin.add_child(scroll)
	var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",12);scroll.add_child(body)
	body.add_child(label("METRO ATLAS  /  城市建设档案",15))
	body.add_child(label("造一座地铁",44,true))
	body.add_child(label("一座城市，一段亲手重现的地铁历史。",20))
	var divider:=HSeparator.new();body.add_child(divider)
	var continue_button:=button("继续城市故事  →",func():_load_result(SaveManager.load_last_game()))
	continue_button.disabled=not FileAccess.file_exists(SaveManager.root_path().path_join("last_game.json")) and not FileAccess.file_exists(SaveManager.root_path().path_join("last_game.json.bak"));body.add_child(continue_button)
	body.add_child(button("选择城市 · 开始新故事",_show_new_game))
	body.add_child(button("存档与路网作品",_saves))
	var extra:=HFlowContainer.new();body.add_child(extra)
	extra.add_child(button("设置",_settings));extra.add_child(button("基本操作练习",_restart_guide));extra.add_child(button("退出",func():get_tree().quit()))
	body.add_child(label("五城 · 13个已发布章节\n从首条线路、延伸到贯通与方案变化。后续历史和远期仍在核验。",16))
	body.add_child(label(BUILD_VERSION+"  ·  离线地图 / 本地保存",15))
	_layout()

func _show_new_game() -> void:
	if is_instance_valid(menu):remove_child(menu);menu.queue_free()
	menu=PanelContainer.new();add_child(menu)
	var sc:=ScrollContainer.new();sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;menu.add_child(sc)
	var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",16);sc.add_child(body)
	body.add_child(button("← 返回",_show_menu));body.add_child(label("选择一座城市",30,true))
	body.add_child(label("沿历史蓝图建设，用自己的操作见证路网形成。",18))
	var cities:=OptionButton.new();cities.custom_minimum_size.y=48*ui_scale
	for city in WorldData.cities():cities.add_item(str(city.name));cities.set_item_metadata(cities.item_count-1,str(city.id))
	body.add_child(cities)
	var summary:=label("",16);body.add_child(summary)
	var describe:=func(index:int):
		var config:=Story.config({"cityId":cities.get_item_metadata(index)})
		summary.text="已发布 %d 章 · %s\n%s" % [config.get("chapters",[]).size(),str(config.get("chapters",[])[0].get("title","")),str(config.get("coverageNote",""))]
	cities.item_selected.connect(describe);describe.call(0)
	var tutorial:=CheckButton.new();tutorial.text="首章逐步教学";tutorial.button_pressed=not Prefs.load_onboarding_completed();tutorial.disabled=Prefs.load_onboarding_completed();body.add_child(tutorial)
	if tutorial.disabled:body.add_child(label("基本操作已学会；新城市直接开始故事，可从菜单进入独立练习。",15))
	body.add_child(button("进入城市故事  →",func():_new_game(str(cities.get_item_metadata(cities.selected)),tutorial.button_pressed)))
	_layout()

func _game_menu() -> void:
	var d:=_dialog("城市地铁故事")
	var body:=VBoxContainer.new();d.add_child(body)
	body.add_child(button("设置",func():d.hide();_settings()))
	body.add_child(button("重新学习基本操作",func():d.hide();_restart_guide()))
	body.add_child(button("返回主菜单",func():d.hide();_leave(_show_menu)))
	d.popup_centered(Vector2i(mini(480,int(size.x)-32),280))

func _new_game(city_id:String,tutorial:bool=true) -> void:
	var state:=WorldData.new_world(city_id,"campaign");Tutorial.configure(state,tutorial and not Prefs.load_onboarding_completed());_enter(state);_save()

func _enter(state:Dictionary) -> void:
	_close_beat()
	guide_map_step=""
	world=state
	if str(world.get("storyState",{}).get("tutorialStatus",""))=="completed":Prefs.save_onboarding_completed(true)
	if str(world.get("mode",""))=="campaign" and str(world.get("storyState",{}).get("chapterId","")).is_empty():world.storyState["chapterId"]=str(Story.chapter(world).get("id",""))
	if is_instance_valid(menu):remove_child(menu);menu.queue_free();menu=null
	frame.show();history.attach(world);rules.world=world;rules.active_city_id=str(world.cityId)
	map_view.set_context(WorldData.city(str(world.cityId)),world);map_view.show_road_names=Prefs.load_road_names();map_view.show_train_display=display_enabled
	selected_id="";selected_kind="";show_left=true;show_right=false;page="story";dirty=false;save_error="";evaluation={};display_seconds=0
	_tool("select");_refresh();call_deferred("_locate_chapter")

func _mark_dirty() -> void:
	if world.is_empty():return
	dirty=true;save_badge.text="保存失败 · 重试" if not save_error.is_empty() else "未保存 · 保存"

func _save(rotate:bool=false) -> bool:
	if world.is_empty():return true
	var result:=SaveManager.save_world(world,rotate)
	if not bool(result.get("ok",false)):
		save_error=str(result.get("error","保存失败"));dirty=true;save_badge.text="保存失败 · 重试";save_badge.tooltip_text=save_error;return false
	dirty=false;save_error="";auto_seconds=0;save_badge.text="已保存";save_badge.tooltip_text="";return true

func _leave(callback:Callable) -> void:
	if world.is_empty() or _save():callback.call();return
	var dialog:=_dialog("保存失败")
	var box:=VBoxContainer.new();dialog.add_child(box);box.add_child(label(save_error+"\n当前会话保留。重试、另存JSON或取消离开。",16))
	box.add_child(button("重试并离开",func():
		if _save():dialog.queue_free();callback.call()))
	box.add_child(button("另存JSON",_export))
	box.add_child(button("放弃未保存修改",func():_confirm("放弃修改","确定放弃未保存修改？",func():dialog.queue_free();callback.call())))
	dialog.popup_centered(Vector2i(700,380))

func _load_result(result:Dictionary) -> void:
	if str(result.get("status",""))=="recovery_available":
		_confirm("发现可用备份","主档有问题：%s\n备份时间：%s\n确认后保留独立恢复副本再载入。" % [str(result.get("error","")),str(result.get("backupAt","未知"))],func():_load_result(SaveManager.load_last_game(true) if str(result.get("recoveryKind",""))=="continue_index" else SaveManager.load_file(str(result.path),true)));return
	if not bool(result.get("ok",false)):_message("载入失败",str(result.get("error","无法载入")));return
	var loaded:Dictionary=result.world
	_leave(func():_enter(loaded);_save())

func _open_page(value:String) -> void:
	page=value;show_left=true
	if _narrow():show_right=false
	_left();_layout()

func _refresh() -> void:
	if world.is_empty():return
	map_view.set_world(world);map_view.set_blueprint(Story.blueprint(world,true) if str(world.mode)=="campaign" else {})
	map_view.selected_id=selected_id;map_view.selected_type=selected_kind
	var ch:=Story.chapter(world)
	map_view.story_markers=Beats.markers(world) if not Tutorial.active(world) or bool(world.storyState.get("learnedTools",false)) else []
	line_button.visible=str(world.mode)!="campaign" or bool(ch.get("requiresLineReorganization",false))
	end_button.visible=tool!="select"
	line_button.disabled=str(world.mode)=="campaign" and not bool(ch.get("requiresLineReorganization",false))
	line_button.tooltip_text="普通章节由检查结果生成历史线路；重组章节再使用此工具。" if line_button.disabled else "核对本章线路重组，或在作品中整理线路。"
	year.text="%s · %s" % [str(world.get("cityName","")),Story.node_date(world)+" · "+Story.plan_status(world) if str(world.mode)=="campaign" else "路网作品"]
	undo_button.disabled=history.undo_label().is_empty();undo_button.tooltip_text=history.undo_label();redo_button.disabled=history.redo_label().is_empty();redo_button.tooltip_text=history.redo_label()
	_left();_right();_instruction();_layout()

func _left() -> void:
	clear(left);begin_button=null;revision_button=null;check_button=null
	if world.is_empty():return
	var nav:=HFlowContainer.new();left.add_child(nav)
	for entry in [["本章","story"],["时间轴","timeline"],["资料","sources"]]:
		var tab:=button(str(entry[0]),_open_page.bind(str(entry[1])));tab.toggle_mode=true;tab.button_pressed=page==str(entry[1]);nav.add_child(tab)
	if page=="timeline":
		left.add_child(label("城市时间轴",24,true))
		for entry in Story.config(world).get("historicalEvents",[]):left.add_child(label("%s · %s" % [str(entry.get("date","")),str(entry.get("title",""))],16))
		for index in range(world.get("storyState",{}).get("milestones",[]).size()):
			var milestone:Dictionary=world.storyState.milestones[index]
			left.add_child(button("复盘副本 · %s" % str(milestone.title),_replay.bind(index)))
		return
	if page=="sources":
		left.add_child(label("资料与边界",24,true));left.add_child(label(str(Story.config(world).get("coverageNote","")),15))
		var ch:=Story.chapter(world)
		left.add_child(label(str(ch.get("sourceTitle","")),18,true));left.add_child(label(str(ch.get("alignmentNote","现代地图只作位置参考。")),15))
		left.add_child(label("本章地点故事",20,true))
		for beat in Beats.entries(world):left.add_child(button(("已读 · " if world.storyState.get("beatRead",{}).has(str(beat.id)) else "未读 · ")+str(beat.title),_show_beat.bind(beat)))
		left.add_child(label(Story.profile(world).get("note",""),15))
		if ch.has("source"):left.add_child(button("打开章节来源",func():OS.shell_open(str(ch.source))))
		for entry in ch.get("additionalSources",[]):
			var source_url:=str(entry.get("url",""));left.add_child(button(str(entry.get("title","补充来源")),func():OS.shell_open(source_url)))
		var plans:Array=ch.get("story",{}).get("planVersions",[])
		if not plans.is_empty():
			left.add_child(label("历史方案对照（只读）",18,true))
			for index in range(plans.size()):left.add_child(button(str(plans[index].get("title","方案")),_view_plan.bind(index)))
			left.add_child(button("返回当前建设方案",func():plan_view_index=-1;map_view.set_blueprint(Story.blueprint(world,true));_instruction()))
		for entry in Story.config(world).get("futurePlans",[]):
			left.add_child(label(str(entry.get("title","")),18,true));left.add_child(label(str(entry.get("description","")),15))
			var url:=str(entry.get("source",""));left.add_child(button("打开规划来源",func():OS.shell_open(url)))
		return
	if str(world.mode)!="campaign":
		left.add_child(label(str(world.get("title","路网作品")),24,true));left.add_child(label("放置车站，铺设轨道，整理线路；保存自己的城市路网作品。",18))
		left.add_child(button("添加建设阶段",_new_phase))
		for phase in world.get("planningPhases",[]):left.add_child(label(str(phase.get("name","建设阶段")),16))
		for route in world.routes:left.add_child(button(str(route.name),_select.bind("route",str(route.id))))
		if world.has("legacyArchive"):left.add_child(label(str(world.legacyArchive.get("note","")),15))
		return
	var chapter:=Story.chapter(world)
	left.add_child(label("%s · 地铁故事" % str(world.cityName),20,true))
	if chapter.is_empty():
		left.add_child(label("当前资料已到边界",24,true));left.add_child(label(str(Story.config(world).get("coverageNote","后续故事待核验。")),16))
		left.add_child(label("已确认的路网已保存。完整历史和远期蓝图核验完成后继续；本次不把样板当作全部历史。",16));return
	left.add_child(label("%s\n%s" % [Story.node_date(world),str(chapter.title)],24,true))
	var story:Dictionary=chapter.get("story",{})
	var stage:=str(world.storyState.get("stage","intro"))
	if stage=="intro":
		left.add_child(label("为什么建设",18,true));left.add_child(label(str(story.get("opening",chapter.get("eventText",""))),18));left.add_child(label(str(story.get("purpose","按目标站区和站序完成本章建设。")),16))
		begin_button=button("展开本章蓝图",_begin_chapter);left.add_child(begin_button)
	elif stage=="outcome":
		left.add_child(label("历史节点已确认",20,true));left.add_child(label(str(story.get("outcome",chapter.get("eventText",""))),18))
		left.add_child(label("路网现有 %d 站 · %d 组展示区段。列车仅作自动展示，车型与尺寸为游戏示意。" % [world.stations.size(),world.routes.filter(func(route:Dictionary):return bool(route.get("open",false))).size()],16))
		left.add_child(button("继续下一章",_next));left.add_child(button("暂停／继续开通展示",func():display_paused=not display_paused))
	else:
		var versions:Array=story.get("planVersions",[])
		left.add_child(label("为什么建设："+str(story.get("purpose","复现本期历史建设。")),15))
		if not versions.is_empty():
			var index:=clampi(int(world.storyPlan.get("planIndex",0)),0,versions.size()-1)
			left.add_child(label(str(versions[index].get("title","方案")),20,true));left.add_child(label(str(versions[index].get("description","")),16))
			if not Story.plan_is_final(world):
				left.add_child(label("尚未实施的历史草案；采用修订方案后再建设最终范围。",16))
				revision_button=button("对比并采用下一版方案",_revise);left.add_child(revision_button)
		var built:=0
		for target in Story.targets(world,true):
			if bool(target.built):built+=1
		left.add_child(label("现在要做："+Story.current_action(world),18,true))
		left.add_child(label("目标站区 %d / %d" % [built,Story.targets(world,true).size()],20,true))
		var missing_names:Array=Story.targets(world,true).filter(func(target:Dictionary):return not bool(target.built)).map(func(target:Dictionary):return str(target.name))
		left.add_child(label("还缺："+"、".join(missing_names.slice(0,3))+("等站区" if missing_names.size()>3 else "") if not missing_names.is_empty() else "站区齐备；还需核对连续轨道、本期站序和线路关系。",15))
		if bool(chapter.get("requiresLineReorganization",false)) and not bool(world.storyPlan.get("reorganizationAccepted",false)):left.add_child(label("原有站轨保留：请点击下方「线路整理」，核对分段记录的贯通站序。",18))
		check_button=button("检查本章复现",_check);left.add_child(check_button)
		left.add_child(button("核对区间走向",_path_picker))
		if not Tutorial.active(world) or bool(world.storyState.get("learnedTools",false)):left.add_child(button("预览辅助完成重复建设",_assist))
		left.add_child(button("返回本章位置",_locate_chapter))
		if Tutorial.active(world):
			left.add_child(button("跳过操作引导",func():Tutorial.skip(world);_mark_dirty();spotlight.clear_focus();_refresh();_save()))
		else:left.add_child(label("需要重学基本操作时，可从菜单进入独立练习。",15))
	if world.has("practiceOf"):left.add_child(button("结束练习，返回原进度",_return_from_practice))
	left.add_child(label("现代地理参考 · 蓝色虚线为近似走廊；灰色虚线为示意。",15))

func _begin_chapter() -> void:
	guide_map_step=""
	world.storyState.stage="build";_mark_dirty();_refresh();_locate_chapter();_save()

func _restart_guide() -> void:
	_confirm("独立操作练习","当前进度会先保存。练习使用首章的新副本，结束后可回到原进度。",func():
		_leave(func():
			practice_return=world.duplicate(true)
			var city_id:=str(world.get("cityId","shanghai"))
			var practice:=WorldData.new_world(city_id,"campaign")
			practice["title"]="操作练习 · "+str(practice.cityName)
			practice["practiceOf"]=str(world.get("gameId",""))
			Tutorial.configure(practice,true);_enter(practice);_save()))

func _return_from_practice() -> void:
	var original:=practice_return
	practice_return={}
	if original.is_empty():
		var id:=str(world.get("practiceOf",""))
		if not id.is_empty():_load_result(SaveManager.load_file(SaveManager.save_path(id)))
		else:_leave(_show_menu)
	else:_leave(func():_enter(original);_save())

func _revise() -> void:
	var versions:Array=Story.chapter(world).get("story",{}).get("planVersions",[])
	var index:=int(world.storyPlan.get("planIndex",0))
	if index+1>=versions.size():return
	var change:=Story.plan_change(world,index,index+1)
	var revision:=int(world.revision)
	var preview:=world.duplicate(false);preview["storyPlan"]=world.storyPlan.duplicate(true);preview.storyPlan.planIndex=index+1
	map_view.set_blueprint(Story.blueprint(preview,true))
	_confirm("方案变化 · "+str(versions[index+1].get("date","")),change+"\n旧方案保留在历史草案层，不生成开通线路。",func():
		if revision!=int(world.revision):_refresh();_message("规划已变化","请重新对比方案。");return
		_execute("采用历史修订方案",func(state:Dictionary):state.storyPlan.planIndex=index+1),func():map_view.set_blueprint(Story.blueprint(world,true)))

func _right() -> void:
	clear(right);clear(actions);confirm_button=null
	if world.is_empty():return
	right.add_child(button("收起详情",func():show_right=false;_layout()))
	if not map_view.draft_station.is_empty():
		var st:Dictionary=map_view.draft_station
		right.add_child(label("车站预览",24,true));right.add_child(label(str(st.name),20,true));right.add_child(label("拖动换位置；R旋转；确认后加入本章。",16))
		_angle(st,true);right.add_child(label("站体 %.0f × %.0f 米 · 地下 %.0f 米\n尺寸为游戏简化表达。" % [float(st.get("lengthM",119)),float(st.get("widthM",20)),-float(st.get("depthM",-15))],16))
		var details:=CheckButton.new();details.text="建设资料与高级参数";details.button_pressed=advanced_edit;details.toggled.connect(func(value:bool):advanced_edit=value;_right());right.add_child(details)
		if advanced_edit:right.add_child(label(str(st.get("constructionNote","原始站体尺寸与埋深待核验，当前为游戏示意。")),15))
		confirm_button=button("确认车站",_commit_station);actions.add_child(confirm_button)
	elif not map_view.track_end_ref.is_empty():
		right.add_child(label("复现这一段",24,true));right.add_child(label("%s → %s" % [_ref_name(map_view.track_start_ref),_ref_name(map_view.track_end_ref)],18))
		right.add_child(label("长度 %.0f 米\n%s" % [float(pending_track.get("lengthM",0)),str(pending_track.get("issue",""))],16))
		right.add_child(label(str(pending_track.get("referenceLabel","手工示意连接")),15))
		confirm_button=button("确认轨道段",_commit_track);actions.add_child(confirm_button)
	elif tool=="station":
		right.add_child(label("放置车站",24,true));right.add_child(label("点击地图中的历史目标站区，调整朝向后确认。尚未放置预览，不会修改正式路网。",18))
	elif tool=="track":
		right.add_child(label("连接轨道",24,true));right.add_child(label("点站端或节点，再点终点。自由端点标为待连接。",18))
		var advanced:=CheckButton.new();advanced.text="高级编辑";advanced.button_pressed=advanced_edit;advanced.toggled.connect(func(value:bool):advanced_edit=value;_cancel_drafts();_right());right.add_child(advanced)
		if advanced_edit or str(world.mode)!="campaign":
			var continuous:=CheckButton.new();continuous.text="连续铺设至空地";continuous.button_pressed=map_view.continuous_track;continuous.toggled.connect(func(value:bool):map_view.continuous_track=value);right.add_child(continuous)
			var depth:=SpinBox.new();depth.min_value=5;depth.max_value=60;depth.step=5;depth.value=-map_view.current_depth_m;depth.suffix=" 米深（游戏示意）";depth.value_changed.connect(func(value:float):map_view.current_depth_m=-value);right.add_child(depth)
		else:right.add_child(label("选择相邻两站，沿本区间参考走廊生成完整预览。接头会适配站位；主体走向保持。",16))
	elif tool=="line":
		right.add_child(label("线路整理",24,true))
		if str(world.mode)=="campaign":
			right.add_child(label("核对分期记录合并后的贯通站序。已有站轨保持，旧分段记录在确认历史节点后归档。",18))
			for target in Story.targets(world,true):right.add_child(label(str(target.name),16))
			if bool(Story.chapter(world).get("requiresLineReorganization",false)):confirm_button=button("确认贯通站序",_confirm_line_reorganization);actions.add_child(confirm_button)
		else:
			right.add_child(label("依次点击已接轨车站，再确认线路。",18))
			for id in line_stops:right.add_child(label(str(WorldData.find_station(world,id).get("name","车站")),16))
			confirm_button=button("确认线路",_workshop_line);actions.add_child(confirm_button)
	elif not evaluation.is_empty():
		right.add_child(label("本章复现检查",24,true))
		if bool(evaluation.get("complete",false)):
			right.add_child(label("目标站、站序和连续轨道已符合本章范围。",18))
			confirm_button=button("确认历史节点并开通展示" if bool(Story.chapter(world).get("requireOpen",true)) else "确认建成节点（暂不运营）",_commit_chapter);actions.add_child(confirm_button)
		else:
			for issue in evaluation.get("issues",[]):
				right.add_child(label(str(issue.get("text","未完成")),16))
				if issue.has("objectId"):right.add_child(button("定位问题",_locate_issue.bind(issue)))
	elif selected_kind=="station":
		var st:=WorldData.find_station(world,selected_id)
		if st.is_empty():return
		right.add_child(label("车站详情",24,true))
		right.add_child(label(str(st.name),24,true))
		if str(world.mode)!="campaign":
			var name_input:=LineEdit.new();name_input.text=str(st.name);name_input.custom_minimum_size.y=44*ui_scale;right.add_child(name_input)
			right.add_child(button("保存站名",func():_rename_station(name_input.text)))
		else:
			for target in Story.targets(world,true):
				if str(target.id)==str(st.get("historicalId","")) and str(target.name)!=str(st.name):
					var value:=str(target.name);right.add_child(button("确认历史更名："+value,_rename_station.bind(value)))
		right.add_child(button("移动车站",func():tool="move_station";map_view.tool=tool;_instruction()))
		var advanced:=CheckButton.new();advanced.text="高级几何编辑";advanced.button_pressed=advanced_edit;advanced.toggled.connect(func(value:bool):advanced_edit=value;_right());right.add_child(advanced)
		if advanced_edit:_angle(st,false)
		right.add_child(button("从A端铺轨",_from_station.bind(str(st.id),"start")));right.add_child(button("从B端铺轨",_from_station.bind(str(st.id),"end")))
		right.add_child(label("建设形式："+str(st.get("constructionForm","待核验")),15))
		right.add_child(label(str(st.get("constructionNote","车型、站体及埋深为游戏示意，历史参数待核验。")),15))
		right.add_child(label("历史身份：%s" % str(st.get("historicalId","自定车站")),15))
		actions.add_child(button("删除车站",_delete))
	elif selected_kind=="link":
		right.add_child(label("轨道区间",24,true))
		var edge:=rules._find_link(selected_id)
		right.add_child(label("沿参考走廊建设" if str(edge.get("geometry",""))=="reference_polyline" else "手工示意轨道",18))
		right.add_child(label("%.0f 米" % TrackNetwork.edge_length_m(edge,world,float(WorldData.city(str(world.cityId)).center[0])),18))
		if str(edge.get("geometry",""))!="reference_polyline":right.add_child(button("高级：调整曲线",func():tool="curve";map_view.tool=tool;_instruction()))
		actions.add_child(button("删除轨道",_delete))
	elif selected_kind=="route":
		var route:=WorldData.find_route(world,selected_id);right.add_child(label(str(route.get("name","线路")),24,true))
		for id in route.get("stationOrder",[]):right.add_child(label(str(WorldData.find_station(world,str(id)).get("name","车站")),16))
		actions.add_child(button("删除线路记录（保留轨道）",_delete))
	if not problem.is_empty():actions.add_child(label(problem,15,true))
	if tool!="select":actions.add_child(button("取消本步",_cancel));actions.add_child(button("结束操作",_tool.bind("select")))

func _angle(st:Dictionary,is_draft:bool) -> void:
	var input:=SpinBox.new();input.min_value=0;input.max_value=359.9;input.step=0.1;input.value=float(st.get("heading",90));input.suffix=" °";right.add_child(input)
	right.add_child(button("应用朝向",func():
		if is_draft:st.heading=input.value;_station_changed()
		else:
			var candidate:=st.duplicate(true);candidate.heading=input.value;_apply_station(candidate)))

func _rename_station(value:String) -> void:
	if value.strip_edges().is_empty():return
	_execute("修改站名",func(state:Dictionary):WorldData.find_station(state,selected_id).name=value.strip_edges())

func _tool(value:String) -> void:
	if value!="select" and str(world.get("mode",""))=="campaign" and Story.chapter(world).is_empty():
		problem="当前资料已到边界。后续历史与远期蓝图核验完成后继续，自由创作尚未解锁。";_instruction();return
	if value!="select":selected_id="";selected_kind="";map_view.selected_id=""
	if plan_view_index>=0:plan_view_index=-1;map_view.set_blueprint(Story.blueprint(world,true))
	_cancel_drafts();tool=value;map_view.tool=value;line_stops.clear();evaluation={};problem="";show_right=value!="select"
	if show_right and _narrow():show_left=false
	_right();_instruction();_layout()

func _cancel_drafts() -> void:
	map_view.assisted_preview={}
	map_view.cancel_pointer_interaction();map_view.draft_station={};map_view.track_start_ref={};map_view.track_end_ref={};map_view.track_control_latlng=[];map_view.draft_track_points=[];map_view.track_preview_conflict="";map_view.station_preview_edges={};map_view.clear_curve_preview();pending_track={};preview_station={}
	map_view.highlight_path_points=[]

func _path_picker() -> void:
	_tool("select")
	show_right=true
	if _narrow():show_left=false
	clear(right);clear(actions)
	right.add_child(label("核对相邻站走向",24,true))
	var groups:Array=Story.groups(world,true)
	for gi in range(groups.size()):
		var ids:Array=groups[gi].get("stationIds",[])
		for si in range(ids.size()-1):
			var a:=Story.bound_station(world,str(ids[si]));var b:=Story.bound_station(world,str(ids[si+1]))
			if a.is_empty() or b.is_empty():continue
			right.add_child(label("%s—%s" % [str(a.name),str(b.name)],16,true))
			var options:=TrackNetwork.station_path_options(str(a.id),str(b.id),world,float(WorldData.city(str(world.cityId)).center[0]),4)
			for index in range(options.size()):
				var key:="%d:%d" % [gi,si];var choice:=index;var points:Array=options[index].get("points",[])
				right.add_child(button("采用走向%d · %.0f米" % [index+1,float(options[index].get("distanceM",0))],func():
					_execute("确认区间走向",func(state:Dictionary):state.storyPlan.pathChoices[key]=choice)
					map_view.highlight_path_points=points;map_view.requested_redraw();_path_picker()))
	actions.add_child(button("返回检查",_check));_layout()

func _cancel() -> void:
	if not map_view.draft_station.is_empty() or not map_view.track_end_ref.is_empty():map_view.draft_station={};map_view.track_end_ref={};map_view.draft_track_points=[];pending_track={};map_view.clear_curve_preview()
	elif not map_view.track_start_ref.is_empty():map_view.track_start_ref={};map_view.draft_track_points=[]
	else:_tool("select")
	problem="";map_view.requested_redraw();_right();_instruction()

func _click(ll:Array,kind:String,id:String,side:String,t:float=-1) -> void:
	if world.is_empty():return
	if kind=="story_beat":_show_beat(Beats.find(world,id));return
	if kind=="endpoint_choice":
		var candidates:=map_view.endpoint_choice_candidates.duplicate(true);show_right=true;clear(right);clear(actions)
		right.add_child(label("请选择接轨端点",20,true))
		for entry in candidates:
			var c:Dictionary=entry
			actions.add_child(button("%s · %s" % [str(WorldData.find_station(world,str(c.id)).get("name","节点")),"A端" if str(c.side)=="start" else "B端"],func():_click(c.latlng,str(c.type),str(c.id),str(c.side))))
		_layout();return
	if tool=="station":
		if str(world.mode)=="campaign" and not Story.plan_is_final(world):_open_page("story");return
		var target:=Story.nearest_target(world,ll) if str(world.mode)=="campaign" else {}
		if str(world.mode)=="campaign" and target.is_empty():problem="请在蓝图目标站区放置车站；可点击左侧目标定位。";_instruction();return
		var construction_profile:=Story.profile(world,str(target.get("id","")))
		var candidate:={"id":"draft","name":str(target.get("name","新建车站%d" % (world.stations.size()+1))),"latlng":ll.duplicate(),"heading":90.0,"lengthM":118.788,"widthM":20.0,"depthM":map_view.current_depth_m,"historicalId":str(target.get("id","")),"vehicleId":"B-6","existing":false,"routeIds":[]}
		if not target.is_empty():candidate.latlng=target.latlng.duplicate();candidate.heading=map_view.blueprint_heading_for(str(target.id))
		_apply_profile(candidate,construction_profile)
		if str(construction_profile.get("parameterStatus",{}).get("depthM","game_estimate"))=="game_estimate":candidate.depthM=map_view.current_depth_m
		map_view.draft_station=candidate;show_right=true;_station_changed();_right();_layout();_trigger_beat("select",[str(target.get("id",""))]);return
	if tool=="track":
		var ref:=_ref(ll,kind,id,side,t)
		if str(world.mode)=="campaign" and not advanced_edit and kind=="station" and not map_view.track_start_ref.is_empty():
			var a:=WorldData.find_station(world,str(map_view.track_start_ref.get("stationId","")));var b:=WorldData.find_station(world,id)
			if not a.is_empty() and not b.is_empty():
				var ends:=_facing(a,b);map_view.track_start_ref=_ref(a.latlng,"endpoint",str(a.id),str(ends[0]));ref=_ref(b.latlng,"endpoint",str(b.id),str(ends[1]))
		if map_view.track_start_ref.is_empty():map_view.track_start_ref=ref;_instruction();return
		map_view.track_end_ref=ref;_track_preview(ref);show_right=true;_right();_layout();return
	if tool=="line" and str(world.mode)!="campaign" and kind=="station":
		if line_stops.is_empty() or line_stops[-1]!=id:line_stops.append(id)
		_right();return
	if kind in ["station","link"]:_select(kind,id)
	elif kind=="blueprint":
		_trigger_beat("select",[id]);problem="目标站区：请点击下方「车站」，再在此处放置预览。";_instruction()
	else:show_left=false;show_right=false;selected_id="";selected_kind="";map_view.selected_id="";map_view.requested_redraw();_layout()

func _ref(ll:Array,kind:String,id:String,side:String,t:float=-1) -> Dictionary:
	if kind in ["station","endpoint"]:
		var st:=WorldData.find_station(world,id)
		if not st.is_empty():
			if side.is_empty():side="start" if rules._distance_m(ll,WorldData.station_endpoint(st,"start"))<rules._distance_m(ll,WorldData.station_endpoint(st,"end")) else "end"
			return {"nodeId":TrackNetwork.station_node_id(st,side),"stationId":id,"side":side,"latlng":WorldData.station_endpoint(st,side),"depthM":st.get("depthM",-15)}
	if kind=="track_node":
		var node:=TrackNetwork.find_node(world,id)
		if not node.is_empty():return {"nodeId":id,"stationId":node.get("stationId",""),"side":node.get("side",""),"latlng":node.latlng,"depthM":node.get("depthM",-15)}
	if kind in ["track_edge","link"] and t>=0:
		var edge:=rules._find_link(id)
		if not edge.is_empty():return {"latlng":ll,"splitEdgeId":id,"splitT":rules._edge_distance_fraction(edge,ll,float(WorldData.city(str(world.cityId)).center[0])),"depthM":edge.get("depthM",-15)}
	return {"latlng":ll.duplicate(),"depthM":map_view.current_depth_m}

func _ref_name(ref:Dictionary) -> String:
	var st:=WorldData.find_station(world,str(ref.get("stationId","")))
	if not st.is_empty():return "%s · %s端" % [str(st.name),"A" if str(ref.get("side",""))=="start" else "B"]
	return "轨道节点" if not str(ref.get("nodeId","")).is_empty() else "自由端点 · 待连接"

func _from_station(id:String,side:String) -> void:
	_tool("track");map_view.track_start_ref=_ref(WorldData.find_station(world,id).latlng,"endpoint",id,side);_instruction()

func _track_preview(finish:Dictionary) -> void:
	var start:=map_view.track_start_ref
	var a:=WorldData.find_station(world,str(start.get("stationId","")));var b:=WorldData.find_station(world,str(finish.get("stationId","")))
	var reference:=ReferenceAlignment.between(str(a.get("historicalId","")),str(b.get("historicalId","")))
	if str(world.mode)=="campaign" and not advanced_edit and not reference.is_empty():
		pending_track=ReferenceAlignment.preview(reference,start,finish,world,float(WorldData.city(str(world.cityId)).center[0]))
	else:
		pending_track=rules.track_preview(start,finish,map_view.track_control_latlng)
		pending_track["referenceLabel"]=ReferenceAlignment.label_for({})
	map_view.draft_track_points=pending_track.get("points",[]);map_view.track_preview_conflict=str(pending_track.get("issue",""));map_view.requested_redraw()
	if not map_view.track_end_ref.is_empty():_trigger_beat("preview_track",_track_historical_ids(map_view.track_start_ref,finish))

func _commit_track() -> void:
	if map_view.track_start_ref.is_empty() or map_view.track_end_ref.is_empty():return
	_track_preview(map_view.track_end_ref)
	if not str(pending_track.get("issue","")).is_empty():problem=str(pending_track.issue);_right();return
	var start:=map_view.track_start_ref.duplicate(true);var finish:=map_view.track_end_ref.duplicate(true);var edge:Dictionary=pending_track.edge.duplicate(true)
	var continuous:=map_view.continuous_track and str(finish.get("stationId","")).is_empty()
	_execute("铺设轨道",func(state:Dictionary):edge.id="edge_%d" % Time.get_ticks_usec();edge.aNodeId=rules.materialize(state,start);edge.bNodeId=rules.materialize(state,finish);state.trackEdges.append(edge))
	if str(world.mode)=="campaign":
		var first_targets:=Story.targets(world,true)
		if first_targets.size()>=2:
			var first:=Story.bound_station(world,str(first_targets[0].id));var second:=Story.bound_station(world,str(first_targets[1].id))
			if not first.is_empty() and not second.is_empty() and bool(TrackNetwork.shortest_station_path(str(first.id),str(second.id),world,float(WorldData.city(str(world.cityId)).center[0])).get("valid",false)):world.storyState.learnedTools=true
	_trigger_beat("build_track",_track_historical_ids(start,finish))
	var next:={"nodeId":str(edge.bNodeId),"latlng":finish.latlng,"depthM":finish.get("depthM",-15)}
	if str(world.mode)=="campaign" and not str(finish.get("stationId","")).is_empty():
		var st:=WorldData.find_station(world,str(finish.stationId));var side:="end" if str(finish.side)=="start" else "start"
		next=_ref(st.latlng,"endpoint",str(st.id),side);continuous=true
	_tool("track" if continuous else "select")
	if continuous:map_view.track_start_ref=next
	else:show_left=true;show_right=false
	_save();_refresh()

func _station_changed() -> void:
	map_view.draft_conflict=rules._station_overlaps_in(map_view.draft_station,world.get("stations",[]));map_view.requested_redraw()

func _commit_station() -> void:
	var candidate:Dictionary=map_view.draft_station.duplicate(true)
	if candidate.is_empty():return
	if rules._station_overlaps_in(candidate,world.stations):problem="站体重叠，请移动或旋转后确认。";_right();return
	if not str(candidate.get("historicalId","")).is_empty() and not Story.bound_station(world,str(candidate.historicalId)).is_empty():problem="该历史目标已有车站。";_right();return
	_execute("建设%s" % str(candidate.name),func(state:Dictionary):candidate.id="station_%d" % Time.get_ticks_usec();state.stations.append(candidate);TrackNetwork.ensure_station_nodes(state))
	_trigger_beat("build_station",[str(candidate.get("historicalId",""))])
	_tool("select");selected_kind="station";selected_id=str(candidate.id);show_left=true;show_right=false;_refresh();_save()

func _execute(title:String,mutation:Callable) -> void:
	if str(world.get("mode",""))=="campaign" and Story.chapter(world).is_empty():problem="当前已到资料边界，后续故事与自由创作尚未解锁；已确认路网保持不变。";_instruction();_right();return
	var fields:Array=["stations","trackNodes","trackEdges","trackLinks","routes"]
	if title in ["采用历史修订方案","确认区间走向"]:fields=["storyPlan"]
	elif title=="确认线路重组":fields=["storyPlan","routes"]
	elif title=="修改站名":fields=["stations"]
	elif title=="添加建设阶段":fields=["planningPhases","currentPlanningPhaseId"]
	elif title=="辅助完成重复建设":fields=["stations","trackNodes","trackEdges","storyPlan"]
	if not history.execute(title,mutation,fields):return
	evaluation={};problem="";rules.world=world;_mark_dirty();_refresh();_save(true)

func _select(kind:String,id:String) -> void:
	selected_kind=kind;selected_id=id;evaluation={};show_right=true
	if _narrow():show_left=false
	map_view.selected_id=id;map_view.selected_type=kind;map_view.requested_redraw();_right();_layout()
	if kind=="station":_trigger_beat("select",[str(WorldData.find_station(world,id).get("historicalId",""))])

func _drag_station(id:String,ll:Array) -> void:
	if Time.get_ticks_usec()-last_preview_usec<33333:return
	last_preview_usec=Time.get_ticks_usec()
	var candidate:=WorldData.find_station(world,id).duplicate(true);candidate.latlng=ll
	preview_station=rules._station_preview_analysis(candidate,world);preview_station["candidate"]=candidate;preview_station["revision"]=int(world.revision)
	map_view.station_preview_edges=preview_station.edges;map_view.station_preview_issue=str(preview_station.issue);map_view.requested_redraw()

func _finish_station_drag(id:String,ll:Array) -> void:
	var candidate:=WorldData.find_station(world,id).duplicate(true);candidate.latlng=ll;_apply_station(candidate)

func _apply_station(candidate:Dictionary) -> void:
	var preview:=rules._station_preview_analysis(candidate,world)
	if not str(preview.issue).is_empty():problem=str(preview.issue);map_view.station_preview_edges={};map_view.station_preview_issue="";map_view.requested_redraw();_right();return
	var revision:=int(world.revision)
	var apply:=func():
		if revision!=int(world.revision):problem="规划已变化，请重新调整。";_right();return
		_execute("调整车站",func(state:Dictionary):
			for key in ["stations","trackNodes","trackEdges","trackLinks"]:state[key]=preview.state.get(key,[]))
		map_view.station_preview_edges={};map_view.station_preview_issue="";map_view.requested_redraw()
	if not WorldData.find_station(world,str(candidate.id)).get("routeIds",[]).is_empty():_confirm("调整已确认路网","关联线路的展示几何将随车站一起改变。是否应用？",apply,_discard_adjustment)
	else:apply.call()

func _preview_curve(id:String,control:String,offset:Array) -> void:
	if Time.get_ticks_usec()-last_preview_usec<33333:return
	last_preview_usec=Time.get_ticks_usec()
	var candidate:=rules._find_link(id).duplicate(true);candidate["controlA" if control=="curveA" else "controlB"]=offset
	var test:=world.duplicate(false);test["trackEdges"]=world.trackEdges.duplicate()
	for i in range(test.trackEdges.size()):
		if str(test.trackEdges[i].id)==id:test.trackEdges[i]=candidate
	problem=rules._physical_edge_geometry_issue(candidate,test);map_view.curve_preview_issue=problem
	preview_station={"candidate":candidate,"revision":int(world.revision),"issue":problem}

func _finish_curve(id:String,control:String,offset:Array) -> void:
	last_preview_usec=0;_preview_curve(id,control,offset)
	if not str(preview_station.get("issue","")).is_empty():map_view.clear_curve_preview();_right();return
	var revision:=int(world.revision);var candidate:Dictionary=preview_station.candidate.duplicate(true)
	_confirm("确认曲线调整","将应用当前预览并更新关联线路几何。",func():
		if revision!=int(world.revision):problem="规划已变化，请重新调整。";map_view.clear_curve_preview();_right();return
		_execute("调整曲线",func(state:Dictionary):
			for i in range(state.trackEdges.size()):
				if str(state.trackEdges[i].id)==id:state.trackEdges[i]=candidate)
		map_view.clear_curve_preview(),_discard_adjustment)

func _discard_adjustment() -> void:
	preview_station={};problem="";map_view.station_preview_edges={};map_view.station_preview_issue="";map_view.clear_curve_preview();map_view.cancel_pointer_interaction();map_view.requested_redraw();_right()

func _delete() -> void:
	var kind:=selected_kind;var id:=selected_id
	_confirm("确认删除","相关线路展示将暂停。可撤销；已确认的历史里程碑保留。",func():_execute("删除对象",func(state:Dictionary):_delete_from(state,kind,id)))

func _delete_from(state:Dictionary,kind:String,id:String) -> void:
	if kind=="route":state.routes=state.routes.filter(func(r:Dictionary):return str(r.id)!=id);return
	var removed:Array[String]=[]
	if kind=="station":
		var st:=WorldData.find_station(state,id);var nodes:Array=st.get("endpointNodes",{}).values()
		for edge in TrackNetwork.all_physical_edges(state):
			if TrackNetwork._edge_node_ids(edge,state).any(func(n:String):return nodes.has(n)):removed.append(str(edge.id))
		state.stations=state.stations.filter(func(s:Dictionary):return str(s.id)!=id)
		state.trackNodes=state.trackNodes.filter(func(n:Dictionary):return str(n.get("stationId",""))!=id)
	else:removed.append(id)
	state.trackEdges=state.trackEdges.filter(func(e:Dictionary):return not removed.has(str(e.id)))
	state.trackLinks=state.trackLinks.filter(func(e:Dictionary):return not removed.has(str(e.id)))
	for route in state.routes:
		if route.get("stationOrder",[]).has(id):route.stationOrder.erase(id);route.open=false
		for direction in route.get("directions",[]):
			direction.stationIds=direction.get("stationIds",[]).filter(func(sid):return str(sid)!=id)
			for segment in direction.get("edgePathsBySegment",[]):
				if segment.any(func(ref:Dictionary):return removed.has(str(ref.id))):segment.clear();route.open=false
	selected_id="";selected_kind=""

func _undo(redo:bool) -> void:
	if world.is_empty():return
	_cancel_drafts();evaluation={}
	if redo:history.redo()
	else:history.undo()
	if selected_kind=="station" and WorldData.find_station(world,selected_id).is_empty():selected_id="";selected_kind=""
	_mark_dirty();_refresh();_save()

func _check() -> void:
	_tool("select")
	evaluation=Story.evaluate(world);show_right=true
	if _narrow():show_left=false
	_right();_layout()

func _commit_chapter() -> void:
	var teaching:=Tutorial.active(world)
	var result:=Story.commit_chapter(world,int(evaluation.get("revision",-1)))
	if not bool(result.get("ok",false)):problem=str(result.get("error","无法确认"));_check();return
	if teaching:
		world.storyState.tutorialEnabled=false;world.storyState.tutorialStatus="completed";world.storyState.learnedTools=true
		if Prefs.save_onboarding_completed(true)!=OK:_message("教学设置未保存","本局教程已完成；跨城市的学习记录写入失败，可在设置中重试。")
	_close_beat()
	_cancel_drafts();evaluation={};tool="select";map_view.tool=tool;display_seconds=0;display_paused=false;show_left=true;show_right=false;_mark_dirty();_refresh();_locate_chapter();_save()

func _next() -> void:
	_close_beat();Story.next_chapter(world);_mark_dirty();_refresh();_locate_chapter();_save()

func _locate_issue(issue:Dictionary) -> void:
	var ll:Array=issue.get("latlng",[])
	if ll.is_empty():ll=WorldData.find_station(world,str(issue.get("objectId",""))).get("latlng",[])
	if not ll.is_empty():map_view.center_on(ll,16)

func _locate_chapter() -> void:
	var targets:Array=Story.blueprint(world).get("stations",[])
	if targets.is_empty() or map_area.size.x<100:return
	var left_width:=left_panel.size.x+32 if left_panel.visible else 32.0
	var right_width:=right_panel.size.x+32 if right_panel.visible else 32.0
	var usable:=Vector2(maxf(180,map_area.size.x-left_width-right_width),maxf(180,map_area.size.y-110))
	for z in range(17,9,-1):
		var lo:=Geo.project(targets[0].latlng,z);var hi:=lo
		for target in targets:
			var point:=Geo.project(target.latlng,z);lo=lo.min(point);hi=hi.max(point)
		if (hi-lo).x<=usable.x and (hi-lo).y<=usable.y:
			map_view.center_on(Geo.unproject((lo+hi)*0.5-Vector2((left_width-right_width)*0.5,0),z),z);return

func _instruction() -> void:
	if not problem.is_empty():hint.text=problem
	elif tool=="station":hint.text="站点：点击目标站区，调整后确认。R旋转。"
	elif tool=="track":hint.text="轨道：%s → 请选择终点；自由端点待连接。" % _ref_name(map_view.track_start_ref) if not map_view.track_start_ref.is_empty() else "轨道：点击站端或节点选择起点。"
	else:hint.text="点击选择；拖动空白处平移，滚轮缩放。Esc取消，Ctrl+Z撤销。"

func _focus_tutorial() -> void:
	for child in get_children():
		if child is Window and child.visible:spotlight.clear_focus();return
	if is_instance_valid(save_overlay):spotlight.clear_focus();return
	if not Tutorial.active(world):spotlight.clear_focus();return
	var target:Control=null;var rect:=Rect2();var text:=""
	if str(world.storyState.get("stage","intro"))=="intro":target=begin_button;text="展开本章蓝图"
	elif not Story.plan_is_final(world):target=revision_button;text="查看并采用下一版方案"
	elif is_instance_valid(confirm_button) and (not map_view.draft_station.is_empty() or not map_view.track_end_ref.is_empty()):target=confirm_button;text="点击这里确认本次建设"
	else:
		var missing:Dictionary={}
		for item in Story.blueprint(world).get("stations",[]):
			if not bool(item.built):missing=item;break
		if not missing.is_empty():
			if tool!="station":target=station_button;text="点击下方「车站」"
			else:
				rect=_tutorial_map_rect(missing.latlng,"station:"+str(missing.id),24);text="放置「%s」预览" % str(missing.name)
		elif not bool(world.storyState.get("learnedTools",false)):
			if tool!="track":target=track_button;text="点击下方「铺轨」"
			else:
				var targets:=Story.targets(world)
				if targets.size()>=2:
					var a:=Story.bound_station(world,str(targets[0].id));var b:=Story.bound_station(world,str(targets[1].id));var ends:=_facing(a,b)
					var ll:=WorldData.station_endpoint(a,str(ends[0])) if map_view.track_start_ref.is_empty() else WorldData.station_endpoint(b,str(ends[1]))
					rect=_tutorial_map_rect(ll,"track:"+("start" if map_view.track_start_ref.is_empty() else "end"),18);text="点击这里的车站接轨端"
		elif bool(Story.chapter(world).get("requiresLineReorganization",false)) and not bool(world.storyPlan.get("reorganizationAccepted",false)):
			target=confirm_button if tool=="line" else line_button;text="确认贯通站序" if tool=="line" else "点击下方「线路整理」核对贯通"
		elif bool(evaluation.get("complete",false)):target=confirm_button;text="确认本章历史节点"
		else:target=check_button;text="在故事页检查本章复现"
	if is_instance_valid(target) and target.is_visible_in_tree():
		var ancestor:=target.get_parent()
		while ancestor!=null:
			if ancestor is ScrollContainer:
				if not ancestor.get_global_rect().encloses(target.get_global_rect()):ancestor.ensure_control_visible(target)
				break
			ancestor=ancestor.get_parent()
		rect=target.get_global_rect()
	if rect.has_area():spotlight.set_focus(rect,text,"rect",face,roundi(18*ui_scale))
	else:spotlight.clear_focus()

func _tutorial_map_rect(latlng:Array,step_id:String,radius:float) -> Rect2:
	# Reframe only on a real tutorial step transition, never on a normal refresh.
	if guide_map_step!=step_id:
		guide_map_step=step_id;_locate_chapter()
	var point:=map_view._to_screen(latlng)+map_area.position
	return Rect2(point-Vector2(radius,radius),Vector2(radius*2,radius*2))

func _facing(a:Dictionary,b:Dictionary) -> Array:
	var alignment:=ReferenceAlignment.between(str(a.get("historicalId","")),str(b.get("historicalId","")))
	if not alignment.is_empty():return ReferenceAlignment.sides(a,b,alignment,float(WorldData.city(str(world.cityId)).center[0]))
	var result:=["end","start"];var best:=INF
	for aside in ["start","end"]:
		for bside in ["start","end"]:
			var distance:=rules._distance_m(WorldData.station_endpoint(a,aside),WorldData.station_endpoint(b,bside))
			if distance<best:best=distance;result=[aside,bside]
	return result

func _assist() -> void:
	if Tutorial.active(world) and not bool(world.storyState.get("learnedTools",false)):_message("先完成基础操作","请先亲手确认两座目标站和一段轨道。");return
	var result:=_assist_candidate()
	if not str(result.get("issue","")).is_empty():_message("辅助建设不可应用",str(result.issue));return
	var revision:=int(world.revision)
	map_view.assisted_preview=result.state;map_view.requested_redraw();_locate_chapter()
	_confirm("辅助完成预览","金色为将加入的站轨：新增 %d 座站、%d 段轨道，并核对本章历史名称。保留已有建设；整体应用并可撤销，不自动确认历史节点。" % [result.state.stations.size()-world.stations.size(),result.state.trackEdges.size()-world.trackEdges.size()],func():
		map_view.assisted_preview={};map_view.requested_redraw()
		if revision!=int(world.revision):_message("规划已变化","请重新预览辅助建设。");return
		_execute("辅助完成重复建设",func(state:Dictionary):
			for key in ["stations","trackNodes","trackEdges"]:state[key]=result.state[key]
			state.storyPlan["assisted"]=true)
		_tool("select");show_left=true;show_right=false;_refresh();_save(),func():map_view.assisted_preview={};map_view.requested_redraw())

func _assist_candidate() -> Dictionary:
	var candidate:=world.duplicate(true);var helper:=Rules.new();helper.world=candidate;helper.active_city_id=str(world.cityId);helper.map_view=map_view
	for target in Story.targets(candidate,true):
		if bool(target.built):
			if bool(target.get("historicalNameRequired",false)):Story.bound_station(candidate,str(target.id)).name=target.name
			continue
		var station:={"id":"assist_%s" % str(target.id),"name":str(target.name),"historicalId":str(target.id),"latlng":target.latlng.duplicate(),"heading":map_view.blueprint_heading_for(str(target.id)),"lengthM":118.788,"widthM":20.0,"depthM":-15.0,"vehicleId":"B-6","existing":false,"routeIds":[]}
		_apply_profile(station,Story.profile(candidate,str(target.id)))
		if helper._station_overlaps_in(station,candidate.stations):return {"issue":"%s 与现有站体冲突，请手动调整。" % str(station.name)}
		candidate.stations.append(station);TrackNetwork.ensure_station_nodes(candidate)
	var construction_groups:Array=Story.groups(candidate,true)
	for connection in Story.chapter(candidate).get("requiredConnections",[]):construction_groups.append({"stationIds":[connection.fromId,connection.toId]})
	for group in construction_groups:
		var ids:Array=group.get("stationIds",[]);var prior_arrival:=""
		for index in range(ids.size()-1):
			var a:=Story.bound_station(candidate,str(ids[index]));var b:=Story.bound_station(candidate,str(ids[index+1]))
			var options:=TrackNetwork.station_path_options(str(a.id),str(b.id),candidate,float(WorldData.city(str(world.cityId)).center[0]),4)
			var reusable:Dictionary={}
			for option in options:
				if option.get("edges",[]).is_empty():continue
				if not prior_arrival.is_empty() and str(option.edges[0].get("fromNodeId",""))==prior_arrival:continue
				if option.edges.any(func(ref:Dictionary):return bool(ref.edge.get("platform",false))):continue
				reusable=option;break
			if not reusable.is_empty():prior_arrival=str(reusable.edges[-1].get("toNodeId",""));continue
			var ends:=_facing(a,b)
			if not prior_arrival.is_empty():ends[0]="end" if prior_arrival==TrackNetwork.station_node_id(a,"start") else "start"
			# An extension entering an already built section must use the other
			# platform end; nearest geometry alone can imply a hidden reversal.
			if index+2<ids.size():
				var next_station:=Story.bound_station(candidate,str(ids[index+2]))
				if not next_station.is_empty():
					var onward:=TrackNetwork.shortest_station_path(str(b.id),str(next_station.id),candidate,float(WorldData.city(str(world.cityId)).center[0]))
					if bool(onward.get("valid",false)) and not onward.get("edges",[]).is_empty():
						ends[1]="end" if str(onward.edges[0].fromNodeId)==TrackNetwork.station_node_id(b,"start") else "start"
			var start:={"nodeId":TrackNetwork.station_node_id(a,str(ends[0])),"stationId":a.id,"side":str(ends[0]),"latlng":WorldData.station_endpoint(a,str(ends[0])),"depthM":a.get("depthM",-15)}
			var finish:={"nodeId":TrackNetwork.station_node_id(b,str(ends[1])),"stationId":b.id,"side":str(ends[1]),"latlng":WorldData.station_endpoint(b,str(ends[1])),"depthM":b.get("depthM",-15)}
			var alignment:=ReferenceAlignment.between(str(a.get("historicalId","")),str(b.get("historicalId","")))
			var preview:=ReferenceAlignment.preview(alignment,start,finish,candidate,float(WorldData.city(str(world.cityId)).center[0])) if not alignment.is_empty() else helper.track_preview(start,finish)
			if not str(preview.get("issue","")).is_empty():return {"issue":"%s—%s：%s；请手工处理。" % [str(a.name),str(b.name),str(preview.issue)]}
			var edge:Dictionary=preview.edge;edge.id="assist_edge_%d_%d" % [index,Time.get_ticks_usec()];candidate.trackEdges.append(edge);prior_arrival=str(finish.nodeId)
	return {"state":candidate,"issue":""}

func _workshop_line() -> void:
	if line_stops.size()<2:problem="请选择至少两座车站。";_right();return
	var paths:Array=[]
	for index in range(line_stops.size()-1):
		var path:=TrackNetwork.shortest_station_path(line_stops[index],line_stops[index+1],world,float(WorldData.city(str(world.cityId)).center[0]))
		if not bool(path.get("valid",false)):problem="相邻车站尚未接轨。";_right();return
		var segment:Array=[]
		for ref in path.edges:
			if not bool(ref.edge.get("platform",false)):segment.append({"id":str(ref.edge.id),"forward":bool(ref.forward)})
		paths.append(segment)
	var order:=line_stops.duplicate()
	_text_prompt("线路名称","新线路",func(value:String):
		_execute("整理线路",func(state:Dictionary):state.routes.append({"id":"line_%d" % Time.get_ticks_usec(),"name":value,"color":"#24745e","open":true,"networkBased":true,"stationOrder":order,"vehicleId":"B-6","directions":[{"id":"forward","stationIds":order,"edgePathsBySegment":paths}]}))
		_tool("select"))

func _confirm_line_reorganization() -> void:
	var probe:=world.duplicate(false);probe["storyPlan"]=world.storyPlan.duplicate(true);probe.storyPlan.reorganizationAccepted=true
	var checked:=Story.evaluate(probe)
	if not bool(checked.complete):evaluation=checked;_tool("select");evaluation=checked;show_right=true;_right();_layout();return
	var routes:Array=checked.routes
	_execute("确认线路重组",func(state:Dictionary):
		state.storyPlan["reorganizationAccepted"]=true
		for route in routes:
			route=route.duplicate(true);route["open"]=false
			state.routes=state.routes.filter(func(old:Dictionary):return str(old.get("historicalLineId",""))!=str(route.get("historicalLineId","")))
			state.routes.append(route))
	_tool("select");show_left=true;show_right=false;_refresh()

func _new_phase() -> void:
	_text_prompt("建设阶段","新的规划阶段",func(value:String):_execute("添加建设阶段",func(state:Dictionary):
		var id:="phase_%d" % Time.get_ticks_usec();state.planningPhases.append({"id":id,"name":value,"stationIds":[],"edgeIds":[],"routeIds":[]});state.currentPlanningPhaseId=id))

func _replay(index:int) -> void:
	_confirm("创建复盘副本","当前进度会先保存。复盘副本不会覆盖本城原进度。",func():
		var copy:=Story.replay_copy(world,index)
		if copy.is_empty():_message("无法安全复盘","旧章节未能匹配当前资料包，已保留原记录；当前进度不会被替换。");return
		_leave(func():_enter(copy);_save()))

func _dialog(title:String) -> AcceptDialog:
	var d:=AcceptDialog.new();d.title=title;d.ok_button_text="关闭";add_child(d);d.confirmed.connect(d.queue_free);d.close_requested.connect(d.queue_free);return d

func _message(title:String,text:String) -> void:
	var d:=_dialog(title);d.dialog_autowrap=true;d.dialog_text=text;d.popup_centered(Vector2i(mini(780,int(size.x-32)),340))

func _confirm(title:String,text:String,callback:Callable,cancel_callback:Callable=Callable()) -> void:
	var d:=ConfirmationDialog.new();d.title=title;d.dialog_autowrap=true;d.dialog_text=text;d.ok_button_text="确认";d.cancel_button_text="取消";add_child(d)
	d.confirmed.connect(func():d.queue_free();callback.call());d.canceled.connect(func():
		if cancel_callback.is_valid():cancel_callback.call()
		d.queue_free())
	d.popup_centered(Vector2i(mini(780,int(size.x-32)),210))

func _text_prompt(title:String,initial:String,callback:Callable) -> void:
	var d:=ConfirmationDialog.new();d.title=title;d.ok_button_text="确认";d.cancel_button_text="取消";add_child(d)
	var edit:=LineEdit.new();edit.text=initial;edit.custom_minimum_size=Vector2(420,48);d.add_child(edit)
	d.confirmed.connect(func():
		var value:=edit.text.strip_edges()
		if not value.is_empty():d.queue_free();callback.call(value))
	d.canceled.connect(d.queue_free);d.popup_centered(Vector2i(560,180));edit.grab_focus()

func _open_sheet(title:String) -> Dictionary:
	if is_instance_valid(save_overlay):save_overlay.queue_free()
	var d:=Control.new();d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(d);save_overlay=d
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.35);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);d.add_child(shade)
	save_panel=PanelContainer.new();d.add_child(save_panel)
	save_panel.size=Vector2(minf(1050,size.x-32),minf(740,size.y-32));save_panel.position=(size-save_panel.size)*0.5
	var viewport_box:=Control.new();viewport_box.clip_contents=true;save_panel.add_child(viewport_box)
	var body:=VBoxContainer.new();body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);viewport_box.add_child(body)
	var heading:=HFlowContainer.new();body.add_child(heading);heading.add_child(label(title,24,true));heading.add_child(button("关闭",d.queue_free))
	_layout()
	return {"overlay":d,"body":body}

func _saves() -> void:
	var sheet:=_open_sheet("存档与路网作品");var d:Control=sheet.overlay;var body:VBoxContainer=sheet.body
	var search:=LineEdit.new();search.placeholder_text="搜索名称或城市";search.custom_minimum_size.y=44*ui_scale;body.add_child(search)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	var summary:=label("",15);body.add_child(summary)
	var refresh:=func(_query:String=""):
		clear(list)
		var entries:=SaveManager.list_saves();var total:=0
		for row in entries:
			total+=int(row.bytes)
			if not search.text.is_empty() and not (str(row.title)+str(row.city)+str(row.kind)).to_lower().contains(search.text.to_lower()):continue
			_save_row(row,list,d)
		summary.text="共%d份 · %.1f MB；自动历史每局最多3份。原始迁移备份单独归档。" % [entries.size(),float(total)/1048576.0]
	search.text_changed.connect(refresh);refresh.call()
	var row:=HFlowContainer.new();body.add_child(row)
	if not world.is_empty():
		row.add_child(button("立即保存",func():
			if not _save():_message("保存失败",save_error)
			else:refresh.call()))
		row.add_child(button("当前进度另存为…",func():_text_prompt("保存当前进度副本",str(world.get("title","路网作品")),func(value:String):
			var result:=SaveManager.save_named(world,value)
			if not bool(result.ok):_message("保存失败",str(result.error))
			else:refresh.call())))
		row.add_child(button("导出JSON",_export))
	row.add_child(button("导入JSON",_import))
	_layout()

func _save_row(entry:Dictionary,list:VBoxContainer,dialog:Control) -> void:
	var card:=PanelContainer.new();list.add_child(card)
	var content:=VBoxContainer.new();card.add_child(content)
	content.add_child(label("%s · %s" % [str(entry.title),str(entry.kind)],18,true))
	content.add_child(label("%s · %s · %d站 / %d线 · %.1f MB" % [str(entry.city),str(entry.savedAt),int(entry.stations),int(entry.routes),float(entry.bytes)/1048576.0],15))
	var buttons:=HFlowContainer.new();content.add_child(buttons)
	buttons.add_child(button("载入恢复备份" if bool(entry.get("backupOnly",false)) else "载入",func():dialog.hide();_load_result(SaveManager.load_file(str(entry.path)));dialog.queue_free()))
	if str(entry.kind)=="手动存档":
		buttons.add_child(button("改名",func():_text_prompt("存档改名",str(entry.title),func(value:String):
			var result:=SaveManager.rename_manual(str(entry.path),value)
			if bool(result.ok):dialog.queue_free();_saves()
			else:_message("改名失败",str(result.error)))))
		if not world.is_empty():buttons.add_child(button("覆盖为当前进度",func():_confirm("覆盖命名存档","将用当前进度覆盖「%s」。原内容将被替换。" % str(entry.title),func():
			var result:=SaveManager.overwrite_manual(str(entry.path),world)
			if bool(result.ok):dialog.queue_free();_saves()
			else:_message("覆盖失败",str(result.error)))))
	if str(entry.kind) in ["自动进度","自动历史","手动存档"]:
		var deletion:=button("删除",_delete_save.bind(entry,dialog));buttons.add_child(deletion)
		if str(entry.kind)=="自动进度" and str(entry.gameId)==str(world.get("gameId","")):
			deletion.disabled=true;content.add_child(label("正在使用：请先返回主菜单，再删除此自动进度。",15))

func _delete_save(entry:Dictionary,dialog:Control) -> void:
	var scope:="仅删除这一份文件。"
	if str(entry.kind)=="自动进度":scope="删除此游戏的主档、恢复备份及自动历史；独立命名存档和导出JSON保留。"
	_confirm("删除存档 · 不可撤销","%s · %s\n%s\n%s" % [str(entry.title),str(entry.city),str(entry.savedAt),scope],func():
		var result:Dictionary
		if str(entry.kind)=="自动进度":result=SaveManager.delete_game(str(entry.gameId),str(world.get("gameId","")))
		elif str(entry.kind)=="自动历史":result=SaveManager.delete_auto_history(str(entry.gameId),str(entry.path).get_file())
		else:result=SaveManager.delete_manual(str(entry.path))
		if bool(result.ok):dialog.queue_free();_saves()
		else:_message("删除失败",str(result.error)))

func _export() -> void:
	if world.is_empty():return
	var d:=FileDialog.new();d.file_mode=FileDialog.FILE_MODE_SAVE_FILE;d.access=FileDialog.ACCESS_FILESYSTEM;d.add_filter("*.json","地铁作品");d.current_file=str(world.gameId)+".json";add_child(d)
	d.file_selected.connect(func(path:String):
		var result:=SaveManager._write_atomic(path,JSON.stringify(world))
		if not bool(result.ok):_message("导出失败",str(result.error))
		d.queue_free())
	d.canceled.connect(d.queue_free);d.popup_centered_ratio(0.7)

func _import() -> void:
	var d:=FileDialog.new();d.file_mode=FileDialog.FILE_MODE_OPEN_FILE;d.access=FileDialog.ACCESS_FILESYSTEM;d.add_filter("*.json","地铁存档");add_child(d)
	d.file_selected.connect(func(path:String):d.queue_free();_load_result(SaveManager.load_file(path)));d.canceled.connect(d.queue_free);d.popup_centered_ratio(0.7)

func _settings() -> void:
	var sheet:=_open_sheet("显示与存档设置");var d:Control=sheet.overlay
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;sheet.body.add_child(scroll)
	var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	body.add_child(label("界面缩放",18,true))
	var picker:=OptionButton.new();picker.custom_minimum_size.y=44*ui_scale
	for value in [100,125,150,175]:picker.add_item("%d%%" % value)
	picker.select([1.0,1.25,1.5,1.75].find(ui_scale));body.add_child(picker)
	picker.item_selected.connect(func(index:int):
		ui_scale=[1.0,1.25,1.5,1.75][index];Prefs.save_scale(ui_scale);theme=Ui.create_theme(face,strong_face,ui_scale);d.queue_free();_rescale())
	var trains:=CheckButton.new();trains.text="显示自动演示列车";trains.button_pressed=display_enabled;body.add_child(trains)
	trains.toggled.connect(func(value:bool):display_enabled=value;map_view.show_train_display=value;map_view.requested_train_redraw())
	body.add_child(button("暂停／继续展示",func():display_paused=not display_paused))
	var automatic:=CheckButton.new();automatic.text="定时自动保存未保存修改";automatic.button_pressed=auto_enabled;body.add_child(automatic)
	automatic.toggled.connect(func(value:bool):auto_enabled=value;Prefs.save_timed_autosave_enabled(value))
	var minutes:=OptionButton.new();minutes.custom_minimum_size.y=44*ui_scale
	for value in [2,5,10,15]:minutes.add_item("每%d分钟" % value)
	minutes.select([2,5,10,15].find(int(auto_interval_seconds/60)));body.add_child(minutes)
	minutes.item_selected.connect(func(index:int):auto_interval_seconds=[2,5,10,15][index]*60;Prefs.save_timed_autosave_interval(int(auto_interval_seconds/60)))
	body.add_child(label("确认建设仍会立即自动保存；每局保留最近3份有效自动历史。关闭定时保存不会关闭建设确认时的进度保护。",15))
	body.add_child(label("Ctrl+Z撤销；Ctrl+Shift+Z / Ctrl+Y重做；R旋转；Esc先取消本步，再退出工具。",15))
	_layout()

func _rescale() -> void:
	var current:=world
	if is_instance_valid(menu):remove_child(menu);menu.queue_free();menu=null
	remove_child(frame);frame.queue_free();remove_child(spotlight);spotlight.queue_free();_build()
	if current.is_empty():_show_menu()
	else:_enter(current)

func _layers() -> void:
	var d:=_dialog("地图图层");var body:=VBoxContainer.new();d.add_child(body)
	body.add_child(label("实线：已建线路；蓝色虚线：本期蓝图；淡紫虚线：未实施的历史草案。",15))
	for entry in [["主要道路名称","show_road_names"],["车站站体","show_stations"],["轨道与线路","show_network"]]:
		var key:=str(entry[1]);var toggle:=CheckButton.new();toggle.text=str(entry[0]);toggle.button_pressed=bool(map_view.get(key));body.add_child(toggle)
		toggle.toggled.connect(func(value:bool):
			map_view.set(key,value);map_view.requested_redraw()
			if key=="show_road_names":Prefs.save_road_names(value))
	d.popup_centered(Vector2i(560,300))

func _unhandled_key_input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or world.is_empty():return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:return
	if event.keycode==KEY_ESCAPE:_cancel()
	elif (event.ctrl_pressed or event.meta_pressed) and event.keycode==KEY_Z:_undo(event.shift_pressed)
	elif (event.ctrl_pressed or event.meta_pressed) and event.keycode==KEY_Y:_undo(true)
	elif event.keycode==KEY_R:
		if not map_view.draft_station.is_empty():map_view.draft_station.heading=fposmod(float(map_view.draft_station.heading)+15,360);_station_changed();_right()
		elif selected_kind=="station":
			var candidate:=WorldData.find_station(world,selected_id).duplicate(true);candidate.heading=fposmod(float(candidate.get("heading",90))+15,360);_apply_station(candidate)
	elif event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN] and tool in ["station","track"]:
		map_view.current_depth_m=clampf(map_view.current_depth_m+(5 if event.keycode==KEY_PAGEUP else -5),-60,-5)
		if not map_view.draft_station.is_empty():map_view.draft_station.depthM=map_view.current_depth_m;_station_changed()
		_right();map_view.requested_redraw()
	elif event.keycode==KEY_SPACE:display_paused=not display_paused
	get_viewport().set_input_as_handled()

func usable_map_rect() -> Rect2:
	var left_edge:float=left_panel.size.x+24 if left_panel.visible else 12.0
	var right_edge:float=right_panel.size.x+24 if right_panel.visible else 12.0
	return Rect2(Vector2(left_edge,12),Vector2(maxf(240,map_area.size.x-left_edge-right_edge),maxf(160,map_area.size.y-24)))

func _close_beat() -> void:
	if is_instance_valid(beat_panel):beat_panel.queue_free()
	beat_panel=null;active_beat_id=""

func _show_beat(beat:Dictionary) -> void:
	if beat.is_empty():return
	_close_beat();active_beat_id=str(beat.id)
	Beats.mark_read(world,active_beat_id);_mark_dirty()
	beat_panel=PanelContainer.new();map_area.add_child(beat_panel)
	var box:=VBoxContainer.new();beat_panel.add_child(box)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(scroll)
	var text_box:=VBoxContainer.new();text_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(text_box)
	text_box.add_child(label(str(beat.get("date",""))+" · "+str(beat.title),18,true))
	text_box.add_child(label(str(beat.text),15))
	text_box.add_child(label("来源："+str(beat.get("sourceTitle","公开资料")),15))
	var controls:=HFlowContainer.new();box.add_child(controls)
	controls.add_child(button("收起故事",_close_beat))
	controls.add_child(button("来源",func():OS.shell_open(str(beat.get("source","")))))
	map_view.story_markers=Beats.markers(world);map_view.requested_redraw();_layout()

func _trigger_beat(event:String,ids:Array) -> void:
	if is_instance_valid(beat_panel):return
	# Basic instruction retains the single visual focus; stories remain readable in sources.
	if Tutorial.active(world):return
	var beat:=Beats.eligible(world,event,ids)
	if not beat.is_empty():_show_beat(beat)

func _track_historical_ids(start:Dictionary,finish:Dictionary) -> Array:
	var result:Array=[]
	for ref in [start,finish]:
		var station:=WorldData.find_station(world,str(ref.get("stationId","")))
		if not station.is_empty():result.append(str(station.get("historicalId","")))
	return result

func _apply_profile(station:Dictionary,profile:Dictionary) -> void:
	for pair in [["lengthM","lengthM"],["widthM","widthM"],["depthM","depthM"],["heading","heading"],["vehicleId","vehicleId"],["form","constructionForm"],["note","constructionNote"],["id","constructionProfileId"]]:
		if profile.has(pair[0]):station[pair[1]]=profile[pair[0]]

func _view_plan(index:int) -> void:
	var versions:Array=Story.chapter(world).get("story",{}).get("planVersions",[])
	if index<0 or index>=versions.size():return
	_cancel_drafts();tool="select";map_view.tool=tool
	var copy:=world.duplicate(false);copy["storyPlan"]=world.storyPlan.duplicate(true);copy.storyPlan.planIndex=index
	copy["storyState"]=world.storyState.duplicate(true);copy.storyState.stage="build"
	plan_view_index=index;map_view.set_blueprint(Story.blueprint(copy,true))
	hint.text="正在只读对照历史方案；按建设工具返回当前方案。未实施草案不会生成列车。"
