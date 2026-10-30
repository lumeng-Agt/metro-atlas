extends Control

const BUILD_VERSION := "0.26.0 · 2026.10.27"
const SaveWriter = preload("res://scripts/save_coordinator.gd")
const Tutorial = preload("res://scripts/story_tutorial.gd")
const Beats = preload("res://scripts/story_beats.gd")
const Story = preload("res://scripts/story_session.gd")
const Engineering = preload("res://scripts/engineering_construction.gd")
const Catalog = preload("res://scripts/campaign_system.gd")
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
var batch_track_mode := false
var batch_track_targets: Array[String] = []
var batch_track_segments: Array[Dictionary] = []
var batch_track_revision := -1
var evaluation: Dictionary = {}
var ui_scale := 1.0
var face: Font
var strong_face: Font
var frame: VBoxContainer
var map_area: Control
var map_hint: Label
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
var save_writer:=SaveWriter.new()
var save_change_serial:=0
var saves_in_flight:=0
var problem := ""
var auto_seconds := 0.0
var auto_enabled := true
var auto_interval_seconds := 300.0
var auto_retry_seconds := 0.0
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
var pending_beat_id := ""
var practice_return: Dictionary = {}
var plan_view_index := -1
var guide_map_step := ""
var advanced_edit := false
var end_button:Button
var nav_pages:HFlowContainer
var tool_flow:HFlowContainer
var feedback_enabled := true
var feedback_volume := 0.35
var feedback_player: AudioStreamPlayer
var feedback_audio: Dictionary = {}
var outcome_comparison := false
var construction_feedback:Control

func _ready() -> void:
	get_tree().auto_accept_quit=false
	if SaveManager.root_path().is_empty():push_error("--data-dir必须指定绝对目录，已停止启动。");get_tree().quit(2);return
	RenderingServer.set_default_clear_color(Ui.CANVAS)
	WorldData.load_assets()
	ui_scale=Prefs.load_scale();auto_enabled=Prefs.load_timed_autosave_enabled();auto_interval_seconds=Prefs.load_timed_autosave_interval()*60.0
	feedback_enabled=Prefs.load_feedback_enabled();feedback_volume=Prefs.load_feedback_volume()
	var base:=load("res://fonts/NotoSansSC.ttf") as Font
	var regular:=FontVariation.new();regular.base_font=base;regular.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):500.0};face=regular
	var bold:=FontVariation.new();bold.base_font=base;bold.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):700.0};strong_face=bold
	theme=Ui.create_theme(face,strong_face,ui_scale)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	add_child(save_writer)
	_setup_feedback_audio()
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
	construction_feedback=preload("res://scripts/construction_feedback.gd").new();construction_feedback.map=map_view;map_view.add_child(construction_feedback)
	map_view.map_clicked.connect(_click);map_view.cancel_requested.connect(_cancel)
	map_view.station_dragged.connect(_drag_station);map_view.station_drag_finished.connect(_finish_station_drag)
	map_view.draft_station_changed.connect(_station_changed)
	map_view.curve_control_previewed.connect(_preview_curve);map_view.curve_control_finished.connect(_finish_curve)
	map_view.camera_changed.connect(func(_center:Array,_zoom:int):pass)
	rules.map_view=map_view
	left_panel=PanelContainer.new();map_area.add_child(left_panel)
	var ls:=ScrollContainer.new();ls.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;left_panel.add_child(ls)
	left=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;ls.add_child(left)
	right_panel=PanelContainer.new();map_area.add_child(right_panel)
	var rb:=VBoxContainer.new();right_panel.add_child(rb)
	var rs:=ScrollContainer.new();rs.size_flags_vertical=Control.SIZE_EXPAND_FILL;rs.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;rb.add_child(rs)
	right=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rs.add_child(right)
	# The earliest chapters are dated before the city had a metro, so the map is
	# legitimately empty. Say so on the map itself; otherwise a blank basemap
	# reads as a rendering failure.
	map_hint=label("",17);map_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	map_hint.add_theme_color_override("font_color",Color("#16202e"))
	map_hint.add_theme_color_override("font_outline_color",Color(1,1,1,0.92))
	map_hint.add_theme_constant_override("outline_size",6)
	map_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;map_hint.hide();map_area.add_child(map_hint)
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

func _setup_feedback_audio() -> void:
	# Logic/data checks have no audio output. Do not leave a WAV playback
	# queued on the dummy mixer when a headless process exits immediately.
	if DisplayServer.get_name()=="headless":return
	# Finite, cached cues end naturally; a generator would keep an audio
	# playback alive after its last buffer (and leaked during quick teardown).
	for kind in ["track","station","chapter","transfer"]:
		var frequency:=720.0 if kind=="station" else 880.0 if kind=="chapter" else 1040.0 if kind=="transfer" else 620.0
		var rate:=22050;var count:=roundi(rate*0.11)
		var frames:=PackedByteArray();frames.resize(count*2)
		for index in range(count):
			var envelope:=minf(1.0,float(index)/220.0)*exp(-float(index)/900.0)
			var sample:=sin(TAU*frequency*float(index)/rate)*envelope*0.16
			frames.encode_s16(index*2,roundi(sample*32767.0))
		var cue:=AudioStreamWAV.new();cue.format=AudioStreamWAV.FORMAT_16_BITS;cue.mix_rate=rate;cue.stereo=false;cue.data=frames
		feedback_audio[kind]=cue
	feedback_player=AudioStreamPlayer.new();add_child(feedback_player)

func _play_feedback(kind:String) -> void:
	if not feedback_enabled or feedback_volume<=0.001 or not is_instance_valid(feedback_player):return
	feedback_player.stop();feedback_player.stream=feedback_audio.get(kind,feedback_audio.get("track"))
	feedback_player.volume_db=linear_to_db(feedback_volume);feedback_player.play()

func _exit_tree() -> void:
	if is_instance_valid(feedback_player):
		feedback_player.stop()
		feedback_player.stream=null
	feedback_audio.clear()

func _layout() -> void:
	if not is_instance_valid(map_area):return
	if is_instance_valid(tool_flow):tool_flow.custom_minimum_size.x=minf(740*ui_scale,maxf(220,size.x-48))
	var w:=minf(420,maxf(320,320*ui_scale));var h:=maxf(100,map_area.size.y-24)
	left_panel.position=Vector2(12,12);left_panel.size=Vector2(minf(w,map_area.size.x-24),h)
	right_panel.size=Vector2(minf(w,map_area.size.x-24),h);right_panel.position=Vector2(map_area.size.x-right_panel.size.x-12,12)
	left_panel.visible=show_left and not world.is_empty();right_panel.visible=show_right and not world.is_empty()
	if _narrow() and show_left and show_right:left_panel.hide()
	if is_instance_valid(map_hint) and map_hint.visible:
		var hint_width:=minf(560*ui_scale,maxf(220,map_area.size.x-64))
		map_hint.size=Vector2(hint_width,0)
		map_hint.reset_size()
		map_hint.size.x=hint_width
		map_hint.position=Vector2((map_area.size.x-hint_width)*0.5,maxf(56,map_area.size.y*0.40))
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
	if auto_enabled:
		auto_seconds+=delta
		if auto_retry_seconds>0.0:auto_retry_seconds=maxf(0.0,auto_retry_seconds-delta)
		if auto_seconds>=auto_interval_seconds and auto_retry_seconds<=0.0 and saves_in_flight==0:
			if dirty:
				if not (await _save()):auto_retry_seconds=60.0
			else:auto_seconds=0.0
	if tool=="track" and not map_view.track_start_ref.is_empty() and map_view.track_end_ref.is_empty() and not map_view.hover_latlng.is_empty() and Time.get_ticks_usec()-last_preview_usec>33333:
		last_preview_usec=Time.get_ticks_usec()
		var hit:=map_view._pick(map_view._to_screen(map_view.hover_latlng))
		if str(hit.get("type",""))!="endpoint_choice":_track_preview(_ref(hit.get("latlng",map_view.hover_latlng),str(hit.get("type","")),str(hit.get("id","")),str(hit.get("side","")),float(hit.get("t",-1))))
	_focus_tutorial()
	if not pending_beat_id.is_empty() and not Tutorial.active(world) and not is_instance_valid(beat_panel):
		var queued_beat:=Beats.find(world,pending_beat_id);pending_beat_id=""
		if not queued_beat.is_empty():_show_beat(queued_beat)

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if world.is_empty():get_tree().quit()
		else:_leave(func():get_tree().quit())
	elif what==NOTIFICATION_APPLICATION_FOCUS_OUT and not world.is_empty():
		display_paused=true

func _show_menu() -> void:
	if is_instance_valid(menu):remove_child(menu);menu.queue_free()
	world={};outcome_comparison=false;map_view.chapter_baseline_overlay={};map_view.set_world({});map_view.set_blueprint({});map_view.requested_redraw();frame.hide();spotlight.clear_focus()
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
	body.add_child(button("地铁挑战 · 默写与每日题",_open_challenges))
	var extra:=HFlowContainer.new();body.add_child(extra)
	extra.add_child(button("设置",_settings));extra.add_child(button("基本操作练习",_restart_guide));extra.add_child(button("退出",func():get_tree().quit()))
	body.add_child(label("五城 · 截止日路网建设章节\n从早期线路逐阶段建设，并在终章核对2026年10月1日路网。",16))
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
	outcome_comparison=false
	map_view.chapter_baseline_overlay={}
	world=state
	if str(world.get("storyState",{}).get("tutorialStatus",""))=="completed":Prefs.save_onboarding_completed(true)
	if str(world.get("mode",""))=="campaign" and str(world.get("storyState",{}).get("chapterId","")).is_empty():world.storyState["chapterId"]=str(Story.chapter(world).get("id",""))
	if is_instance_valid(menu):remove_child(menu);menu.queue_free();menu=null
	frame.show();history.attach(world);rules.world=world;rules.active_city_id=str(world.cityId)
	map_view.set_context(WorldData.city(str(world.cityId)),world);map_view.show_road_names=Prefs.load_road_names();map_view.show_train_display=display_enabled
	selected_id="";selected_kind="";show_left=true;show_right=false;page="story";dirty=false;save_error="";evaluation={};display_seconds=0;auto_seconds=0;auto_retry_seconds=0;pending_beat_id=""
	_tool("select");_refresh();call_deferred("_locate_chapter")

func _mark_dirty() -> void:
	if world.is_empty():return
	save_change_serial+=1
	dirty=true;save_badge.text="保存失败 · 重试" if not save_error.is_empty() else "未保存 · 保存"

func _active_task_id() -> String:
	var chapter:=Story.chapter(world)
	if chapter.is_empty():return ""
	var groups:Array=Story.groups(world,true)
	if groups.is_empty():return ""
	var state:Dictionary=world.get("storyState",{})
	var chapter_id:=str(chapter.get("id",""))
	var progress:Dictionary=state.get("chapterTaskProgress",{}).get(chapter_id,{})
	var task_progress:Dictionary=progress.get("tasks",{})
	var selected:=str(state.get("activeTaskId","")) if str(state.get("activeTaskChapterId",""))==chapter_id else ""
	for index in range(groups.size()):
		var task_id:=Story.task_id(chapter,groups[index],index)
		if task_id==selected and str(task_progress.get(task_id,{}).get("status",""))!="confirmed":return selected
	for index in range(groups.size()):
		var task_id:=Story.task_id(chapter,groups[index],index)
		if str(task_progress.get(task_id,{}).get("status",""))=="confirmed":continue
		var targets:=Story.targets(world,true,task_id)
		if targets.any(func(target:Dictionary):return not bool(target.get("built",false))):
			state["activeTaskId"]=task_id;state["activeTaskChapterId"]=chapter_id;world["storyState"]=state
			return task_id
	for index in range(groups.size()):
		var task_id:=Story.task_id(chapter,groups[index],index)
		if str(task_progress.get(task_id,{}).get("status",""))!="confirmed":
			state["activeTaskId"]=task_id;state["activeTaskChapterId"]=chapter_id;world["storyState"]=state
			return task_id
	return ""

func _select_chapter_task(task_id:String) -> void:
	if task_id==_active_task_id():return
	var has_draft:=not map_view.draft_station.is_empty() or not map_view.track_start_ref.is_empty() or not map_view.track_end_ref.is_empty() or batch_track_mode or not map_view.draft_track_segments.is_empty()
	var apply:=func():
		_cancel_drafts();tool="select";map_view.tool="select";evaluation={};problem=""
		world.storyState["activeTaskId"]=task_id;world.storyState["activeTaskChapterId"]=str(Story.chapter(world).get("id",""))
		_mark_dirty();_refresh();_locate_chapter()
	if has_draft:_confirm("切换本章任务","当前有未提交建设草稿。丢弃草稿并切换任务吗？正式路网不会改变。",apply)
	else:apply.call()

## Jump to the first line this chapter still needs confirmed on its own.
func _confirm_pending_tasks() -> void:
	var chapter:=Story.chapter(world)
	if chapter.is_empty():return
	var groups:Array=Story.groups(world,true)
	for index in range(groups.size()):
		var task:=Story.task_id(chapter,groups[index],index)
		if Story.task_confirmed(world,task):continue
		_select_chapter_task(task)
		# With no draft to discard the switch is immediate, so the confirmation
		# dialog can follow in the same click. With a draft the switch asks first,
		# and the player lands on that task's own confirm button.
		if _active_task_id()==task:_confirm_active_task()
		return

func _save(_rotate:bool=false) -> bool:
	if world.is_empty():return true
	var requested_id:=str(world.gameId)
	var requested_serial:=save_change_serial
	var ticket:=save_writer.request(world,requested_serial)
	saves_in_flight+=1
	save_badge.text="保存中…"
	var result:Dictionary=await save_writer.wait_for(ticket)
	saves_in_flight-=1
	if str(world.get("gameId",""))!=requested_id:return bool(result.get("ok",false))
	if not bool(result.get("ok",false)):
		save_error=str(result.get("error","保存失败"));dirty=true;save_badge.text="保存失败 · 重试";save_badge.tooltip_text=save_error;auto_retry_seconds=60.0;return false
	world["savedAt"]=str(result.get("savedAt",world.get("savedAt","")))
	save_error="";auto_seconds=0;auto_retry_seconds=0
	# The writer may have coalesced this request with a newer queued snapshot.
	dirty=save_change_serial!=int(result.get("changeSerial",requested_serial))
	save_badge.text="未保存 · 保存" if dirty else ("保存中…" if saves_in_flight>0 else "已保存")
	save_badge.tooltip_text=""
	return true

func _operation_label(chapter:Dictionary) -> String:
	var labels:Dictionary={"first_build":"首次建设","extension":"线路延伸","phased_opening":"分期建设","interchange":"形成换乘","transfer_connection":"换乘通道启用","reorganization":"贯通与线路重组","plan_revision":"方案调整","network_opening":"线路开通"}
	return str(labels.get(str(chapter.get("operationType", "")), "历史线路建设"))

func _save_commemorative_image() -> void:
	var dialog:=FileDialog.new();dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.add_filter("*.png","PNG纪念图")
	var city_name:=str(world.get("cityName", "城市"));var date:=Story.node_date(world).replace("/", "-").replace("\\", "-")
	dialog.current_file="%s_%s_地铁建设纪念.png" % [city_name,date];add_child(dialog)
	dialog.file_selected.connect(func(path:String):
		dialog.queue_free();call_deferred("_write_commemorative_image",path))
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(0.72)

func _write_commemorative_image(path:String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var city_name:=str(world.get("cityName", "城市"))
	var captured:=get_viewport().get_texture().get_image()
	if captured.is_empty():_message("纪念图失败","无法读取当前画面。");return
	var footer_height:=140
	var output:=Image.create(captured.get_width(),captured.get_height()+footer_height,false,Image.FORMAT_RGBA8)
	output.fill(Color("#111923"));output.blit_rect(captured,Rect2i(Vector2i.ZERO,captured.get_size()),Vector2i.ZERO)
	var view:=SubViewport.new();view.size=Vector2i(output.get_width(),output.get_height());view.transparent_bg=false;view.render_target_update_mode=SubViewport.UPDATE_ONCE;add_child(view)
	var root:=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);view.add_child(root)
	var image_texture:=TextureRect.new();image_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);image_texture.texture=ImageTexture.create_from_image(captured);image_texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;root.add_child(image_texture)
	var footer:=PanelContainer.new();footer.position=Vector2(0,captured.get_height());footer.size=Vector2(captured.get_width(),footer_height);footer.add_theme_stylebox_override("panel",Ui._box(Color("#111923"),Color("#344353"),0));root.add_child(footer)
	var box:=VBoxContainer.new();footer.add_child(box)
	box.add_child(label("%s · %s · %s" % [city_name,Story.node_date(world),str(Story.chapter(world).get("title", "地铁建设纪念"))],22,true))
	box.add_child(label("本期路网 %d 站 · %d 条线路 · 精度：%s" % [world.get("stations",[]).size(),world.get("routes",[]).size(),str(Story.chapter(world).get("alignmentNote", "历史位置资料待核验"))],15))
	box.add_child(label("现代地理参考 · © OpenStreetMap contributors · 地图日期：%s" % str(map_view.base_map_snapshot),15))
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image();var result:=image.save_png(path);view.queue_free()
	if result!=OK:_message("纪念图保存失败","无法写入所选文件：%s" % path)
	else:_message("纪念图已保存",path)

func _historical_target_name(historical_id:String) -> String:
	for target in Story.targets(world,true):
		if str(target.get("id", ""))==historical_id:return str(target.get("name", "目标站"))
	return "目标站"

func _leave(callback:Callable) -> void:
	if world.is_empty() or (await _save()):callback.call();return
	var dialog:=_dialog("保存失败")
	var box:=VBoxContainer.new();dialog.add_child(box);box.add_child(label(save_error+"\n当前会话保留。重试、另存JSON或取消离开。",16))
	box.add_child(button("重试并离开",func():
		if await _save():dialog.queue_free();callback.call()))
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
	var active_task_id:=_active_task_id() if str(world.mode)=="campaign" and plan_view_index<0 else ""
	map_view.set_world(world);map_view.set_blueprint(Story.blueprint(world,true,active_task_id) if str(world.mode)=="campaign" else {})
	map_view.selected_id=selected_id;map_view.selected_type=selected_kind
	var ch:=Story.chapter(world)
	map_view.story_markers=Beats.markers(world) if not Tutorial.active(world) or bool(world.storyState.get("learnedTools",false)) else []
	line_button.visible=str(world.mode)!="campaign" or bool(ch.get("requiresLineReorganization",false))
	end_button.visible=tool!="select"
	var waiting_for_plan:=str(world.mode)=="campaign" and str(world.storyState.get("stage",""))=="build" and not Story.plan_is_final(world)
	var transfer_only:=str(world.mode)=="campaign" and str(ch.get("operationType",""))=="transfer_connection"
	station_button.disabled=waiting_for_plan or transfer_only;track_button.disabled=waiting_for_plan or transfer_only
	if transfer_only:
		station_button.tooltip_text="本期连接既有线路的独立站体，无需新建车站。请在故事页预览并建立换乘。"
		track_button.tooltip_text=station_button.tooltip_text
	elif waiting_for_plan:
		station_button.tooltip_text="当前是尚未实施的历史草案。先在故事页采用本期方案，再建设。"
		track_button.tooltip_text=station_button.tooltip_text
	else:
		station_button.tooltip_text="按本章目标站区放置历史车站。";track_button.tooltip_text="连接已放置车站，或按本章顺序连续复现区间。"
	line_button.disabled=str(world.mode)=="campaign" and not bool(ch.get("requiresLineReorganization",false))
	line_button.tooltip_text="普通章节由检查结果生成历史线路；重组章节再使用此工具。" if line_button.disabled else "核对本章线路重组，或在作品中整理线路。"
	year.text="%s · %s" % [str(world.get("cityName","")),Story.node_date(world)+" · "+Story.plan_status(world) if str(world.mode)=="campaign" else "路网作品"]
	undo_button.disabled=history.undo_label().is_empty();undo_button.tooltip_text=history.undo_label();redo_button.disabled=history.redo_label().is_empty();redo_button.tooltip_text=history.redo_label()
	_update_map_hint()
	_left();_right();_instruction();_layout()

## Explain an empty map instead of leaving the player to guess.
func _update_map_hint() -> void:
	if not is_instance_valid(map_hint):return
	if world.is_empty() or not world.get("stations",[]).is_empty():map_hint.hide();return
	var chapter:=Story.chapter(world)
	var city:=str(world.get("cityName","本市"))
	if not chapter.is_empty() and bool(chapter.get("eventOnly",false)):
		map_hint.text="截至 %s，%s还没有开通任何地铁线路。\n本节点只登记史料，不需要建站或铺轨。" % [Story.node_date(world),city]
	elif not chapter.is_empty():
		map_hint.text="%s的路网还没有开始建设。\n按右侧提示放置本章目标站，或点「展开本章蓝图」查看本期范围。" % city
	else:
		map_hint.text="%s还没有已建线路。\n点下方「车站」开始建设。" % city
	map_hint.show()

func _left() -> void:
	clear(left);begin_button=null;revision_button=null;check_button=null
	if world.is_empty():return
	var nav:=HFlowContainer.new();left.add_child(nav)
	for entry in [["本章","story"],["时间轴","timeline"],["资料","sources"]]:
		var tab:=button(str(entry[0]),_open_page.bind(str(entry[1])));tab.toggle_mode=true;tab.button_pressed=page==str(entry[1]);nav.add_child(tab)
	if page=="timeline":
		left.add_child(label("城市时间轴",24,true))
		left.add_child(button("观看发展史／导出视频",_open_history_player))
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
		var phase:=str(world.get("storyState",{}).get("phase",""))
		var coverage:Dictionary={}
		if phase in ["history_gap","history_content_gap","future_gap"]:
			coverage=Story.network_coverage(str(world.get("cityId","")))
		if Story.can_create_workshop_copy(world):
			left.add_child(label("历史与规划必做建设已完成",24,true))
			left.add_child(label("可以在当前进度继续自由创作。已确认的历史记录和原存档身份会保留。",16))
			left.add_child(button("进入自由创作",_unlock_free))
		else:
			var blocked:=Story.completion_eligibility(world)
			var why:Array=blocked.get("reasons",[])
			left.add_child(label("暂不能进入自由创作",24,true))
			left.add_child(label(str(why[0]) if not why.is_empty() else "完成度校验未通过。",16))
			if not bool(blocked.get("contentReady",true)):
				left.add_child(label("另有资料核对未完成项，属内容缺项，不影响本版可玩范围。",16))
		if phase in ["history_gap","history_content_gap","future_gap"]:
			left.add_child(label("截至 2026-10-01 路网目录",18,true))
			if not coverage.is_empty():
				var official_count:Variant=coverage.get("officialRouteCount",null)
				var official_label:=str(official_count) if official_count!=null else "官方统计口径不同"
				left.add_child(label("官方线路口径：%s\n地图候选线路关系：%d 条；站点：%d 个" % [official_label,int(coverage.get("mapRouteEntryCount",0)),int(coverage.get("mapUniqueStationCount",0))],15))
				left.add_child(label("当前章节目标覆盖：完整 %d 条、部分 %d 条、未覆盖 %d 条地图线路关系" % [int(coverage.get("fullyTargetedRouteEntryCount",0)),int(coverage.get("partiallyTargetedRouteEntryCount",0)),int(coverage.get("uncoveredRouteEntryCount",0))],15,true))
				left.add_child(label("历史里程碑区间：%d 个；可玩章节：%d 个；尚未制作：%d 个" % [int(coverage.get("milestoneChapterCount",0)),int(coverage.get("playableMilestoneCount",0)),int(coverage.get("missingMilestoneCount",0))],15,true))
				left.add_child(label("以下为已登记的历史事件，不代表已做成可玩章节：",15))
				var schedule:Array=coverage.get("milestoneChapters",[])
				var pending_intervals:Array=coverage.get("pendingMilestoneIntervals",[])
				for interval in pending_intervals.slice(0,4):
					var period_start:=str(interval.get("periodStartExclusive",""))
					var period_end:=str(interval.get("periodEndInclusive",""))
					left.add_child(label("待制作历史区间：%s—%s · %s" % [period_start if not period_start.is_empty() else "历史起点",period_end,str(interval.get("title","里程碑建设"))],15))
				if not schedule.is_empty() and str(schedule.back().get("contentStatus",""))=="network_reconciliation_missing":left.add_child(label("最后节点：截至2026-10-01核对全网（尚未制作）",15,true))
				var pending:Array=coverage.get("pendingMilestones",[])
				left.add_child(label("已登记但尚未做成可玩章节的里程碑：%d 项" % pending.size(),16,true))
				for index in range(mini(5,pending.size())):
					var milestone:Dictionary=pending[index]
					left.add_child(label("%s · %s" % [str(milestone.get("date","")),str(milestone.get("title","历史节点"))],15))
					var source_url:=str(milestone.get("source",""))
					if not source_url.is_empty():left.add_child(button("查看来源",func():OS.shell_open(source_url)))
				var project_rows:Array=coverage.get("projectsAtCutoff",[])
				if not project_rows.is_empty():
					var policy_count:=project_rows.filter(func(row:Dictionary):return str(row.get("playabilityStatus",""))=="policy_only_not_playable").size()
					left.add_child(label("截止日后的建设篇 · %d 项资料登记，可玩建设章 %d 项，待制作 %d 项，政策方向 %d 项" % [int(coverage.get("projectInventoryCount",project_rows.size())),int(coverage.get("playableProjectCount",0)),int(coverage.get("pendingPlayableProjectCount",project_rows.size()))-policy_count,policy_count],18,true))
				for project in project_rows:
					var project_type:=str(project.get("projectType",""))
					var type_label:="项目资料"
					match project_type:
						"under_construction": type_label="在建项目"
						"under_construction_or_planned": type_label="在建／规划方向"
						"approved_and_under_construction": type_label="已批并推进建设"
						"approved_project": type_label="已批准项目"
						"approved_plan": type_label="已批规划"
						"public_consultation": type_label="征求意见方案"
					var playability:=str(project.get("playabilityStatus",""))
					var task_status:="已有关联建设任务"
					if playability=="policy_only_not_playable":task_status="政策／规划方向，未发布逐站蓝图，不阻塞解锁"
					elif playability=="engineering_works_only":task_status="联络／扩能工程，不新增运营车站，按工程条目单列"
					elif playability!="playable_build_task":task_status="尚无可玩的逐站建设任务"
					left.add_child(label("%s · %s\n%s\n%s" % [type_label,str(project.get("name","")),str(project.get("note","尚未完成项目章节核对。")),task_status],15))
					var project_url:=str(project.get("source",""))
					if not project_url.is_empty():left.add_child(button("查看官方项目资料 · %s" % str(project.get("sourceTitle","来源页面")),func():OS.shell_open(project_url)))
		if phase=="history_gap":left.add_child(label("历史建设任务尚未接续；当前画面中的整城线路不等于已逐段复现。",18,true))
		elif phase=="history_content_gap":left.add_child(label("地图线路目标已列入章节，但五城逐期建设和截止日后的项目任务仍未补齐。",18,true))
		else:left.add_child(label("历史篇已完成；后续建设规划与截止日路网分开呈现。",18,true))
		return
	left.add_child(label("%s\n%s" % [Story.node_date(world),str(chapter.title)],24,true))
	var is_project_phase:=str(world.get("storyState",{}).get("phase",""))=="future"
	var chapter_rows:Array=Catalog.playable_future_plans(str(world.get("cityId",""))) if is_project_phase else Story.config(world).get("chapters",[])
	var chapter_position:=0
	for chapter_index in range(chapter_rows.size()):
		if str(chapter_rows[chapter_index].get("id",""))==str(chapter.get("id","")):chapter_position=chapter_index+1;break
	if chapter_position>0:left.add_child(label(("截止日后项目建设 %d / %d" if is_project_phase else "历史里程碑 %d / %d · 截止2026-10-01") % [chapter_position,chapter_rows.size()],15,true))
	var milestone_interval:Dictionary=CampaignSystem.milestone_interval(str(world.get("cityId","")),str(chapter.get("id","")))
	if not milestone_interval.is_empty():
		var interval_start:=str(milestone_interval.get("periodStartExclusive",""))
		var interval_end:=str(milestone_interval.get("periodEndInclusive",chapter.get("date","")))
		left.add_child(label("本章建设区间：%s—%s" % [interval_start if not interval_start.is_empty() else "历史起点",interval_end],15,true))
	var story:Dictionary=chapter.get("story",{})
	var stage:=str(world.storyState.get("stage","intro"))
	if stage=="intro":
		left.add_child(label("历史节点" if bool(chapter.get("eventOnly",false)) else "本期建设",18,true));left.add_child(label(str(story.get("opening",chapter.get("eventText",""))),18));left.add_child(label(str(story.get("purpose","按目标站区和站序完成本章建设。")),16))
		if is_project_phase:
			left.add_child(label("项目状态：%s。完成后记录为规划建设成果，不计作已开通线路。" % str(chapter.get("status","截止日后建设")),15,true))
			left.add_child(label(str(chapter.get("description","按截止日后的项目范围建设本期目标。")),15))
		if bool(chapter.get("eventOnly",false)):
			left.add_child(label("此节点没有可核实的新增站段，不会要求你铺设虚构线路。",15))
		begin_button=button("查看并确认历史节点" if bool(chapter.get("eventOnly",false)) else "展开本章蓝图",_begin_chapter);left.add_child(begin_button)
	elif stage=="outcome":
		left.add_child(label("历史节点已确认",20,true));left.add_child(label(str(story.get("outcome",chapter.get("eventText",""))),18))
		var changes:=Story.chapter_changes(world)
		if changes.is_empty():
			left.add_child(label("本章路网变化正在整理；历史节点已保存。",16))
		else:
			left.add_child(label("本章变化",20,true))
			left.add_child(label("新增车站：%s" % ("、".join(changes.addedStations) if not changes.addedStations.is_empty() else "无；复用既有站点 %s" % ("、".join(changes.reusedStations) if not changes.reusedStations.is_empty() else "无")),16))
			left.add_child(label("新增轨道 %d 段 · 约 %.1f 公里" % [int(changes.addedTrackSections),float(changes.addedLengthM)/1000.0],16))
			for pair in changes.focusPairs:
				var relation:="未形成连续线路" if not bool(pair.connected) else "同线直达" if int(pair.transfers)==0 else "最少换乘 %d 次" % int(pair.transfers)
				left.add_child(label("%s → %s：%s" % [str(pair.from),str(pair.to),relation],16))
			if not changes.newInterchanges.is_empty():left.add_child(label("新形成换乘：%s" % "、".join(changes.newInterchanges),16))
			if not changes.newRoutes.is_empty():left.add_child(label("本期线路：%s" % "、".join(changes.newRoutes),16))
			if not changes.serviceChanges.is_empty():left.add_child(label("历史服务阶段：%s" % "；".join(changes.serviceChanges),16))
			if not changes.nextTargets.is_empty():left.add_child(label("后续接口：%s" % "、".join(changes.nextTargets),16))
		left.add_child(button("返回本章现状" if outcome_comparison else "对照本章建设前",func():
			outcome_comparison=not outcome_comparison
			map_view.chapter_baseline_overlay=Story.chapter_baseline_world(world) if outcome_comparison else {}
			map_view.requested_redraw();_left()))
		left.add_child(button("保存纪念图 PNG",_save_commemorative_image))
		left.add_child(button("线路图视图",_open_schematic))
		left.add_child(button("观看发展史／导出视频",_open_history_player))
		left.add_child(label("列车只作开通展示；车型、站体尺寸及未核验工程参数均为游戏示意。",15))
		left.add_child(button("继续下一章",_next));left.add_child(button("暂停／继续开通展示",func():display_paused=not display_paused))
	else:
		var versions:Array=story.get("planVersions",[])
		left.add_child(label(("历史资料：" if bool(chapter.get("eventOnly",false)) else "为什么建设：")+str(story.get("purpose","复现本期历史建设。")),15))
		if bool(chapter.get("eventOnly",false)):
			left.add_child(label("资料节点 · 无新增建设任务",20,true))
			if not str(chapter.get("source","" )).is_empty():left.add_child(button("查看本节点来源",func():OS.shell_open(str(chapter.get("source","")))))
			left.add_child(button("确认并继续时间线",_check))
		if not versions.is_empty():
			var index:=clampi(int(world.storyPlan.get("planIndex",0)),0,versions.size()-1)
			left.add_child(label(str(versions[index].get("title","方案")),20,true));left.add_child(label(str(versions[index].get("description","")),16))
			if not Story.plan_is_final(world):
				left.add_child(label("尚未实施的历史草案；采用修订方案后再建设最终范围。",16))
				revision_button=button("对比并采用下一版方案",_revise);left.add_child(revision_button)
		if not bool(chapter.get("eventOnly",false)):
			left.add_child(label("现在要做："+Story.current_action(world),18,true))
			left.add_child(label("本章操作："+_operation_label(chapter),16,true))
			left.add_child(label(str(chapter.get("operationGuide","按目标站区、站序与参考走廊复现本期范围。")),15))
		var chapter_groups:Array=Story.groups(world,true)
		if chapter_groups.size()>1:
			var selected_task:=_active_task_id()
			var task_progress:Dictionary=world.get("storyState",{}).get("chapterTaskProgress",{}).get(str(chapter.get("id","")),{}).get("tasks",{})
			left.add_child(label("本章建设任务 · %d 项" % chapter_groups.size(),18,true))
			for group_index in range(chapter_groups.size()):
				var task_group:Dictionary=chapter_groups[group_index]
				var task_id:=Story.task_id(chapter,task_group,group_index)
				var task_targets:=Story.targets(world,true,task_id)
				var task_built:=task_targets.filter(func(target:Dictionary):return bool(target.get("built",false))).size()
				var task_name:=str(task_group.get("name",task_group.get("historicalLineId","本期线路")))
				var task_confirmed:=str(task_progress.get(task_id,{}).get("status",""))=="confirmed"
				var task_state:="已确认" if task_confirmed else "站体 %d/%d" % [task_built,task_targets.size()]
				if task_targets.size()>0 and task_built==task_targets.size():task_state="站体已就位 · 待核对区间"
				if Engineering.is_group(task_group):task_state="轨道接口工程 · 待检查"
				if task_confirmed:task_state="已确认"
				left.add_child(button(("当前 · " if task_id==selected_task else "")+task_name+"  ·  "+task_state,_select_chapter_task.bind(task_id)))
				if task_id==selected_task and not str(task_group.get("constructionScopeNote","")).is_empty():left.add_child(label(str(task_group.get("constructionScopeNote","")),15))
			if not selected_task.is_empty():
				left.add_child(button("检查并确认当前建设任务",_confirm_active_task))
				left.add_child(label("每项任务单独确认；确认一条线路不会替本章其他线路或历史事件盖章。",15))
		for transition_index in range(chapter.get("serviceTransitions",[]).size()):
			var transition:Dictionary=chapter.serviceTransitions[transition_index]
			var proposal:=_service_transition_proposal(transition,transition_index)
			var transition_confirmed:=not proposal.is_empty() and Story._has_service_range(world,str(proposal.get("id","")))
			left.add_child(label("本期状态 · %s：%s%s" % [str(transition.get("historicalLineId","线路")),Story.service_status_label(str(transition.get("status","built")))," · 已确认" if transition_confirmed else ""],16,true))
			if transition_confirmed:
				left.add_child(label("范围：%s" % "—".join(proposal.get("displayStationNames",[])),15))
			else:
				var status_button:=button("预览并确认本期范围",_preview_service_transition.bind(transition,transition_index))
				status_button.disabled=proposal.is_empty()
				left.add_child(status_button)
				if proposal.is_empty():left.add_child(label("先完成该线路的目标站和连续轨道，才能确认历史服务范围。",15))
		var active_targets:=Story.targets(world,true,_active_task_id())
		var active_groups:=Story.groups(world,true,_active_task_id())
		var engineering_only:=not active_groups.is_empty() and active_groups.all(func(group:Dictionary):return Engineering.is_group(group))
		var built:=active_targets.filter(func(target:Dictionary):return bool(target.get("built",false))).size()
		var transfer_only:=str(chapter.get("operationType",""))=="transfer_connection" and active_groups.is_empty()
		if transfer_only:
			var linked:int=chapter.get("requiredTransfers",[]).filter(func(t:Dictionary):return _transfer_connected(t)).size()
			left.add_child(label("本期换乘联系 %d / %d"%[linked,chapter.get("requiredTransfers",[]).size()],20,true))
		elif engineering_only:
			var new_station_count:=0
			for group in active_groups:new_station_count+=group.get("newStationIds",[]).size()
			left.add_child(label("轨道接口工程 · 本任务不新增车站" if new_station_count==0 else "工程轨道与 %d 座本线新站体"%new_station_count,18,true))
		elif not bool(chapter.get("eventOnly",false)):left.add_child(label("当前任务站体 %d / %d" % [built,active_targets.size()],20,true))
		var missing_targets:Array[Dictionary]=active_targets.filter(func(target:Dictionary):return not bool(target.built))
		if not missing_targets.is_empty():
			left.add_child(label("尚未建设：",15,true))
			for missing_target in missing_targets.slice(0,4):
				left.add_child(label("· %s · %s线站体" % [str(missing_target.get("name","目标站")),str(missing_target.get("historicalLineName",missing_target.get("historicalLineId","本期")))],15))
			if missing_targets.size()>4:left.add_child(label("另有 %d 座目标站体" % (missing_targets.size()-4),15))
		elif engineering_only:left.add_child(label("沿本期走廊连接目标站端与工程接口；方形接口不是车站。未纳入本期的界外区间不会自动补齐，完成工程不会生成运营线路。",15))
		elif transfer_only:left.add_child(label("既有线路和轨道保持原样；通过下面的换乘预览确认联系。",15))
		elif not bool(chapter.get("eventOnly",false)):left.add_child(label("目标站体已建齐；还需核对连续轨道、本期站序和线路关系。",15))
		if bool(chapter.get("requiresLineReorganization",false)) and not bool(world.storyPlan.get("reorganizationAccepted",false)):left.add_child(label("原有站轨保留：请点击下方「线路整理」，核对分段记录的贯通站序。",18))
		var transfer_evaluation:Dictionary=Story.evaluate(world) if not chapter.get("requiredTransfers",[]).is_empty() else {}
		var pending_transfers:Array=chapter.get("requiredTransfers",[]).filter(func(t:Dictionary):return not _transfer_connected(t))
		if chapter.get("requiredTransfers",[]).size()>3:
			left.add_child(label("换乘联系：已确认 %d / %d" % [chapter.get("requiredTransfers",[]).size()-pending_transfers.size(),chapter.get("requiredTransfers",[]).size()],16,true))
			left.add_child(button("查看全部换乘联系",_transfer_list))
		for transfer in pending_transfers.slice(0,3):
			var transfer_line_names:=_transfer_line_names(transfer)
			var transfer_title:=str(transfer.get("name","换乘站"))
			var transfer_pair:=" ↔ ".join(transfer_line_names)
			if str(transfer.get("status",""))=="reserved":
				var passage:bool=str(transfer.get("reservationKind",""))=="pedestrian_passage"
				left.add_child(label(("规划通道 · " if passage else "预留换乘 · ")+transfer_title,18,true))
				left.add_child(label(transfer_pair+"；保留独立站体，工程尚未开放，不计为现状站内换乘。",15))
				if _transfer_connected(transfer):left.add_child(label("已记录规划通道" if passage else "已确认预留接口",16,true))
				else:
					var reservation_button:=button("预览并确认规划通道" if passage else "预览并确认预留接口",_preview_transfer.bind(transfer));reservation_button.disabled=not _transfer_ready(transfer,transfer_evaluation);left.add_child(reservation_button)
					if reservation_button.disabled:
						for reason in TransferReservation.errors(world,transfer,Story.groups(world,true)):left.add_child(label(reason,15))
				continue
			left.add_child(label("换乘站 · %s" % transfer_title,18,true))
			left.add_child(label("%d座独立站体：%s" % [transfer.get("stationInstanceIds",[]).size(),transfer_pair],15))
			if str(transfer.get("transferKind",""))=="out_of_station":left.add_child(label("出闸换乘：按导向经公共区域步行至另一站体，两侧名称与实体保留。",15))
			left.add_child(label("建立的是站体之间的换乘联系；不会合并站厅，也不会把两条轨道接在一起。",15))
			if _transfer_connected(transfer):left.add_child(label("已建立换乘联系 · %s" % transfer_pair,16,true))
			else:
				var transfer_button:=button("建立换乘关系 · %s" % transfer_pair,_preview_transfer.bind(transfer));transfer_button.disabled=not _transfer_ready(transfer,transfer_evaluation);left.add_child(transfer_button)
				if transfer_button.disabled:
					for status_line in _transfer_status_lines(transfer,transfer_evaluation):left.add_child(label(status_line,15))
					left.add_child(label("两侧都显示“已接入本期线路”后，才能建立换乘关系。",15))
		if pending_transfers.size()>3:left.add_child(label("另有 %d 组待确认；完成后依次显示，也可从全部列表选择。" % (pending_transfers.size()-3),15))
		if not bool(chapter.get("eventOnly",false)):check_button=button("检查本章复现",_check);left.add_child(check_button)
		if not engineering_only and bool(world.storyState.get("learnedTools",false)) and Story.plan_is_final(world):left.add_child(button("连续复现相邻区间",_begin_batch_tracks))
		if not bool(chapter.get("eventOnly",false)):
			if not engineering_only:left.add_child(button("核对区间走向",_path_picker))
			if not Tutorial.active(world) or bool(world.storyState.get("learnedTools",false)):left.add_child(button("预览工程轨道" if engineering_only else "预览辅助完成重复建设",_assist))
			left.add_child(button("返回本章位置",_locate_chapter))
		if Tutorial.active(world):
			left.add_child(button("跳过操作引导",func():Tutorial.skip(world);_mark_dirty();spotlight.clear_focus();_refresh()))
		else:left.add_child(label("需要重学基本操作时，可从菜单进入独立练习。",15))
	if world.has("practiceOf"):left.add_child(button("结束练习，返回原进度",_return_from_practice))
	left.add_child(label("现代地理参考 · 蓝色虚线为近似走廊；灰色虚线为示意。",15))

func _begin_chapter() -> void:
	guide_map_step=""
	world.storyState.stage="build";_mark_dirty();_refresh();_locate_chapter()

func _service_transition_proposal(transition:Dictionary,transition_index:int) -> Dictionary:
	var expected_id:="service_%s_%s" % [str(Story.chapter(world).get("id","")),str(transition.get("id","%s_%d" % [str(transition.get("historicalLineId","")),transition_index]))]
	for proposal in Story.evaluate(world).get("serviceTransitions",[]):
		if str(proposal.get("id",""))==expected_id:return proposal
	return {}

func _preview_service_transition(transition:Dictionary,transition_index:int) -> void:
	var proposal:=_service_transition_proposal(transition,transition_index)
	if proposal.is_empty():
		var checked:=Story.evaluate(world);var details:Array[String]=[]
		for issue in checked.get("issues",[]):details.append(str(issue.get("text","")))
		_message("本期范围暂不可确认", "先完成指定站序与连续轨道。\n"+"\n".join(details.slice(0,4)));return
	if Story._has_service_range(world,str(proposal.id)):_message("本期范围已确认", "该历史服务范围已记录，可在操作历史中撤销。");return
	var expected_revision:=int(world.get("revision",0))
	var names:Array=proposal.get("displayStationNames",[])
	var status:=str(proposal.get("status","built"))
	var line_name:=str(transition.get("historicalLineId","本期线路"))
	var source:=str(proposal.get("source",""))
	var message:="线路：%s\n范围：%s\n历史状态：%s\n\n这是历史范围状态记录，不会创建客流、班次或列车运行安排。确认后作为一步建设历史，可撤销。" % [line_name,"—".join(names),Story.service_status_label(status)]
	if not source.is_empty():message+="\n\n资料来源："+source
	_confirm("预览本期历史范围",message,func():
		var committed:=_commit_service_transition(proposal,expected_revision)
		if not bool(committed.get("ok",false)):_message("历史范围未确认",str(committed.get("error","请重新检查本期范围。")))
		_refresh())

func _commit_service_transition(proposal:Dictionary,expected_revision:int,checked:Dictionary={}) -> Dictionary:
	if expected_revision!=int(world.get("revision",0)):return {"ok":false,"error":"规划已变化，请重新预览历史范围。"}
	var current:Dictionary={}
	if checked.is_empty():current=_service_transition_proposal_for_id(str(proposal.get("id","")))
	else:
		for candidate in checked.get("serviceTransitions",[]):
			if str(candidate.get("id",""))==str(proposal.get("id","")):current=candidate;break
	if current.is_empty() or current.get("stationIds",[])!=proposal.get("stationIds",[]) or current.get("edgePathsBySegment",[])!=proposal.get("edgePathsBySegment",[]):return {"ok":false,"error":"本期站序或轨道已变化，请重新预览。"}
	if Story._has_service_range(world,str(proposal.get("id",""))):return {"ok":false,"error":"本期历史范围已经确认。"}
	var record:=proposal.duplicate(true);record.erase("displayStationNames");record.erase("focusLatlng")
	var candidate:=world.duplicate(true);candidate.serviceRanges.append(record)
	# The explicit scope action changes the actual presentation service now,
	# rather than leaving it open until a later chapter/task confirmation.
	var transition_routes:Array=Story.evaluate(candidate).get("routes",[])
	for route in transition_routes:
		if str(route.get("historicalLineId",""))==str(record.get("historicalLineId","")):Story._store_historical_route(candidate,route)
	var continuity_error:=Story.changed_service_continuity_error(candidate,transition_routes)
	if not continuity_error.is_empty():return {"ok":false,"error":continuity_error}
	Story._refresh_route_memberships(candidate)
	var invalid:=SaveManager.validate(candidate)
	if not invalid.is_empty():return {"ok":false,"error":invalid}
	_execute("确认历史服务范围",func(state:Dictionary):
		for key in ["serviceRanges","routes","stations","trackEdges","trackLinks"]:state[key]=candidate[key].duplicate(true))
	_play_feedback("track")
	return {"ok":true}

func _service_transition_proposal_for_id(proposal_id:String) -> Dictionary:
	var transitions:Array=Story.chapter(world).get("serviceTransitions",[])
	for index in range(transitions.size()):
		var proposal:=_service_transition_proposal(transitions[index],index)
		if str(proposal.get("id",""))==proposal_id:return proposal
	return {}

func _transfer_connected(transfer: Dictionary) -> bool:
	if str(transfer.get("status",""))=="reserved":return TransferReservation.saved_matches(world,transfer)
	for saved in world.get("transferConnections", []):
		if str(saved.get("id", "")) == str(transfer.get("id", "")) and str(saved.get("status", "active")) == "active" and saved.get("stationInstanceIds", []) == transfer.get("stationInstanceIds", []) and saved.get("lineIds", []) == transfer.get("lineIds", []) and str(saved.get("transferKind","interchange"))==str(transfer.get("transferKind","interchange")): return true
	return false

func _transfer_ready(transfer: Dictionary,checked:Dictionary={}) -> bool:
	if str(transfer.get("status",""))=="reserved":return str(world.get("storyState",{}).get("phase","history"))=="future" and not bool(Story.chapter(world).get("requireOpen",true)) and TransferReservation.errors(world,transfer,Story.groups(world,true)).is_empty()
	var instance_ids: Array = transfer.get("stationInstanceIds", [])
	var line_ids: Array = transfer.get("lineIds", [])
	if instance_ids.size() < 2 or instance_ids.size() != line_ids.size(): return false
	var bodies: Array[Dictionary] = []
	for instance_id in instance_ids:
		var station := Story.bound_station(world, str(transfer.get("complexId", "")), str(instance_id))
		if station.is_empty(): return false
		bodies.append(station)
	if checked.is_empty():checked=Story.evaluate(world)
	for index in range(line_ids.size()):
		var body_id:=str(bodies[index].get("id", ""));var line_id:=str(line_ids[index])
		var line_route:=Story.route_for_station_body(checked.get("routes",[]),line_id,body_id)
		if line_route.is_empty():
			var existing_routes:Array=world.get("routes",[]).filter(func(route:Dictionary):return bool(route.get("networkBased",false)))
			line_route=Story.route_for_station_body(existing_routes,line_id,body_id)
		if line_route.is_empty():return false
	return true

func _historical_line_name(line_id:String) -> String:
	for group in Story.groups(world,true):
		if str(group.get("historicalLineId",""))==line_id:return str(group.get("name",line_id))
	for route in world.get("routes",[]):
		if str(route.get("historicalLineId",""))==line_id:return str(route.get("name",line_id))
	return line_id

func _station_line_name(station:Dictionary) -> String:
	var saved_name:=str(station.get("stationLineName",""))
	if not saved_name.is_empty():return saved_name
	var line_id:=str(station.get("stationLineId",""))
	if line_id.is_empty():
		for route in world.get("routes",[]):
			if station.get("routeIds",[]).has(str(route.get("id",""))):return str(route.get("name","线路"))
	return _historical_line_name(line_id) if not line_id.is_empty() else "线路未标记"

func _transfer_line_names(transfer:Dictionary) -> Array[String]:
	var result:Array[String]=[]
	for line_id in transfer.get("lineIds",[]):result.append(_historical_line_name(str(line_id)))
	return result

func _transfer_page(chapter:Dictionary,page_index:int) -> Array:
	var transfers:Array=chapter.get("requiredTransfers",[])
	var start:=clampi(page_index,0,maxi(0,ceili(transfers.size()/10.0)-1))*10
	return transfers.slice(start,start+10)

func _transfer_list(page_index:int=0) -> void:
	_tool("select");show_right=true
	if _narrow():show_left=false
	clear(right);clear(actions)
	var chapter:=Story.chapter(world);var transfers:Array=chapter.get("requiredTransfers",[])
	var page_count:=maxi(1,ceili(transfers.size()/10.0));page_index=clampi(page_index,0,page_count-1)
	right.add_child(label("本期换乘联系",24,true))
	right.add_child(label("第 %d / %d 页 · 共 %d 组" % [page_index+1,page_count,transfers.size()],16))
	for transfer in _transfer_page(chapter,page_index):
		var connected:=_transfer_connected(transfer)
		var pair_name:=" ↔ ".join(_transfer_line_names(transfer))
		right.add_child(label(str(transfer.get("name","换乘站"))+" · "+pair_name,18,true))
		if connected:right.add_child(label("已确认预留" if str(transfer.get("status",""))=="reserved" else "已建立换乘",15))
		else:right.add_child(button("查看并预览",_inspect_transfer.bind(transfer)))
	if page_index>0:actions.add_child(button("上一页",_transfer_list.bind(page_index-1)))
	if page_index+1<page_count:actions.add_child(button("下一页",_transfer_list.bind(page_index+1)))
	actions.add_child(button("返回本章",func():show_left=true;show_right=false;_refresh()))
	_layout()

func _inspect_transfer(transfer:Dictionary) -> void:
	var instances:Array=transfer.get("stationInstanceIds",[])
	if not instances.is_empty():
		var station:=Story.bound_station(world,str(transfer.get("complexId","")),str(instances[0]))
		if not station.is_empty():map_view.center_on(station.latlng,16)
	_preview_transfer(transfer)

func _transfer_candidate() -> Dictionary:
	# Transfer proposals can update service membership in these five fields.
	# The milestone archive, history, geometry nodes and story progress remain
	# read-only; copying their full nested archive for each pair is unnecessary.
	var candidate:=world.duplicate(false)
	for key in ["routes","stations","trackEdges","trackLinks","transferConnections"]:candidate[key]=world.get(key,[]).duplicate(true)
	return candidate

func _transfer_station_status(transfer:Dictionary,index:int,checked:Dictionary={}) -> String:
	var instance_ids:Array=transfer.get("stationInstanceIds",[]);var line_ids:Array=transfer.get("lineIds",[])
	if index<0 or index>=instance_ids.size() or index>=line_ids.size():return "配置不完整"
	var instance_id:=str(instance_ids[index]);var line_id:=str(line_ids[index]);var complex_id:=str(transfer.get("complexId",""))
	var station:=Story.bound_station(world,complex_id,instance_id)
	if station.is_empty():return "未建设站体"
	if checked.is_empty():checked=Story.evaluate(world)
	var checked_routes:Array=checked.get("routes",[])
	if not Story.route_for_station_body(checked_routes,line_id,str(station.get("id",""))).is_empty():return "已接入本期线路"
	var existing_routes:Array=world.get("routes",[]).filter(func(route:Dictionary):return bool(route.get("networkBased",false)))
	if not Story.route_for_station_body(existing_routes,line_id,str(station.get("id",""))).is_empty():return "已接入既有线路"
	return "已建站；待本线站序与轨道检查通过"

func _transfer_status_lines(transfer:Dictionary,checked:Dictionary={}) -> Array[String]:
	var result:Array[String]=[];var names:=_transfer_line_names(transfer)
	if checked.is_empty():checked=Story.evaluate(world)
	for index in range(transfer.get("stationInstanceIds",[]).size()):
		var line_name:=names[index] if index<names.size() else "线路"
		result.append("· %s站体：%s" % [line_name,_transfer_station_status(transfer,index,checked)])
	return result

func _preview_transfer(transfer: Dictionary) -> void:
	if str(transfer.get("status",""))=="reserved":
		_preview_transfer_reservation(transfer);return
	var checked:=Story.evaluate(world)
	if not _transfer_ready(transfer,checked):_message("换乘联系尚不能建立", "请先分别建设两侧线路的目标站体，并完成各自轨道与站序。相邻或几何交叉不自动形成换乘。");return
	if _transfer_connected(transfer):_message("换乘关系已存在", str(transfer.get("name", "换乘站")) + "已在本期明确建立。");return
	var instance_ids: Array = transfer.get("stationInstanceIds", []);var line_ids: Array = transfer.get("lineIds", [])
	var details: Array[String] = []
	for index in range(instance_ids.size()):
		var station := Story.bound_station(world, str(transfer.get("complexId", "")), str(instance_ids[index]))
		details.append("%s站体：%s（独立站体）" % [_historical_line_name(str(line_ids[index])), str(station.get("name", "车站"))])
	var expected_revision := int(world.get("revision", 0))
	var connection: Dictionary = {"id":str(transfer.get("id","")),"name":str(transfer.get("name","换乘站")),"complexId":str(transfer.get("complexId","")),"stationInstanceIds":instance_ids.duplicate(),"lineIds":line_ids.duplicate(),"status":"active","precision":str(transfer.get("precision","schematic")),"source":str(transfer.get("source","")),"effectiveDate":str(Story.chapter(world).get("date",""))}
	var probe: Dictionary = _transfer_candidate()
	for route in checked.get("routes", []):
		var draft_route:Dictionary=route.duplicate(true)
		var existing:=WorldData.find_route(probe,str(route.get("id","")))
		draft_route["open"]=bool(existing.get("open",false))
		Story._store_historical_route(probe,draft_route)
	probe.transferConnections.append(connection.duplicate(true))
	var validation := SaveManager.validate(probe)
	if not validation.is_empty():_message("换乘预览无效", validation);return
	var body_count:=instance_ids.size()
	var contact_note:="出闸后按导向经公共区域步行至另一站体，两侧名称与实体保留。" if str(transfer.get("transferKind",""))=="out_of_station" else "保留不同线路的独立站体，列车仍沿各自轨道运行。"
	_confirm("建立换乘关系 · " + str(transfer.get("name","换乘站")), "将建立%d座独立站体之间的换乘联系：\n%s\n\n%s\n确认后可撤销。" % [body_count,"\n".join(details),contact_note], func():
		var committed:=_commit_transfer_connection(transfer,connection,expected_revision,checked)
		if not bool(committed.get("ok",false)):_message("换乘联系未建立",str(committed.get("error","请重新预览。")))
		_refresh())

func _commit_transfer_connection(transfer:Dictionary,connection:Dictionary,expected_revision:int,checked:Dictionary={}) -> Dictionary:
	if str(transfer.get("status",""))=="reserved":return _commit_transfer_reservation(transfer,connection,expected_revision)
	if expected_revision!=int(world.get("revision",0)):return {"ok":false,"error":"规划已变化，请重新检查两侧线路。"}
	if bool(Story.chapter(world).get("requiresLineReorganization",false)) and not bool(world.get("storyPlan",{}).get("reorganizationAccepted",false)):return {"ok":false,"error":"请使用下方「线路整理」核对并确认本期贯通站序。"}
	# Recheck formal planning, not a caller's previously computed readiness.
	checked=Story.evaluate(world)
	var current_transfers:Array=Story.chapter(world).get("requiredTransfers",[])
	if not current_transfers.any(func(t:Dictionary):return str(t.get("id",""))==str(transfer.get("id","")) and t.get("stationInstanceIds",[])==transfer.get("stationInstanceIds",[]) and t.get("lineIds",[])==transfer.get("lineIds",[]) and str(t.get("status","active"))==str(transfer.get("status","active")) and str(t.get("transferKind","interchange"))==str(transfer.get("transferKind","interchange"))):return {"ok":false,"error":"换乘目标已变化，请重新预览。"}
	if str(connection.get("status","active"))!="active":return {"ok":false,"error":"普通换乘与预留接口不能互相替代，请重新预览。"}
	for key in ["id","complexId","stationInstanceIds","lineIds"]:
		if connection.get(key)!=transfer.get(key):return {"ok":false,"error":"换乘预览与当前目标不一致。"}
	if not _transfer_ready(transfer,checked):return {"ok":false,"error":"两侧独立站体、连续轨道和线路站序尚未全部就绪。"}
	if _transfer_connected(transfer):return {"ok":false,"error":"这条换乘联系已经建立。"}
	var candidate:=_transfer_candidate()
	# A reviewed map duplicate can be an alias of the same historical complex.
	# Persist the canonical identity already used by its independent bodies;
	# never create a second complex just to satisfy a raw catalogue reference.
	var canonical_connection:=connection.duplicate(true)
	canonical_connection["complexId"]=CampaignSystem.canonical_station_complex(str(world.cityId),str(connection.complexId))
	canonical_connection["transferKind"]=str(transfer.get("transferKind","interchange"))
	for route in checked.get("routes",[]):
		var route_copy:Dictionary=route.duplicate(true)
		var existing:=WorldData.find_route(candidate,str(route.get("id","")))
		route_copy["open"]=bool(existing.get("open",false))
		Story._store_historical_route(candidate,route_copy)
	var continuity_error:=Story.changed_service_continuity_error(candidate,checked.get("routes",[]))
	if not continuity_error.is_empty():return {"ok":false,"error":continuity_error}
	var restored:=false
	for index in range(candidate.transferConnections.size()):
		var saved:Dictionary=candidate.transferConnections[index]
		if str(saved.get("id",""))!=str(connection.id):continue
		if str(saved.get("status","active"))=="active":
			var same_pair:bool=saved.get("lineIds",[])==canonical_connection.lineIds and saved.get("stationInstanceIds",[])==canonical_connection.stationInstanceIds and CampaignSystem.canonical_station_complex(str(world.cityId),str(saved.get("complexId","")))==str(canonical_connection.complexId)
			# Explicitly reconfirm a reviewed in/out-of-gate classification on
			# exactly the same pair. Different bodies or lines remain protected.
			if not same_pair:return {"ok":false,"error":"同一换乘编号仍有不同的有效配对，请先核对变更；本次不会覆盖。"}
		var restored_connection:=canonical_connection.duplicate(true)
		var previous:=saved.duplicate(true);previous.erase("previousConnection")
		restored_connection["previousConnection"]=previous
		candidate.transferConnections[index]=restored_connection;restored=true;break
	if not restored:candidate.transferConnections.append(canonical_connection)
	Story._refresh_route_memberships(candidate)
	var validation:=SaveManager.validate(candidate)
	if not validation.is_empty():return {"ok":false,"error":validation}
	_execute("建立换乘联系",func(state:Dictionary):
		for key in ["routes","stations","trackEdges","trackLinks","transferConnections"]:state[key]=candidate[key].duplicate(true))
	return {"ok":true}

func _preview_transfer_reservation(transfer:Dictionary) -> void:
	if not _transfer_ready(transfer):_message("预留接口尚未就绪","请先完成两侧独立站体及本期实际工程轨道。");return
	var revision:=int(world.revision)
	var connection:Dictionary=transfer.duplicate(true)
	connection["effectiveDate"]=str(Story.chapter(world).get("date",""))
	var passage:bool=str(transfer.get("reservationKind",""))=="pedestrian_passage"
	_confirm(("确认规划通道 · " if passage else "确认预留换乘 · ")+str(transfer.get("name","站区")),"记录两侧独立站体之间的规划联系。工程尚未开放，当前换乘方式保持原样；不会合并站厅或接通列车轨道。确认后可撤销。",func():
		var result:=_commit_transfer_reservation(transfer,connection,revision)
		if not bool(result.get("ok",false)):_message("预留接口未确认",str(result.get("error","请重新预览。")))
		_refresh())

func _commit_transfer_reservation(transfer:Dictionary,connection:Dictionary,expected_revision:int) -> Dictionary:
	if expected_revision!=int(world.revision):return {"ok":false,"error":"规划已变化，请重新预览预留接口。"}
	var configured:Array=Story.chapter(world).get("requiredTransfers",[])
	if not configured.any(func(pair:Dictionary):return pair==transfer):return {"ok":false,"error":"预留接口目标已经变化。"}
	if not _transfer_ready(transfer):return {"ok":false,"error":"预留接口的独立站体及实际工程轨道尚未就绪。"}
	for key in ["id","complexId","lineIds","stationInstanceIds","status","reservationEvidence","source","reservationKind"]:
		if connection.get(key)!=transfer.get(key):return {"ok":false,"error":"预留接口草稿与当前来源或配对不一致。"}
	if _transfer_connected(transfer):return {"ok":false,"error":"这处预留换乘已确认。"}
	for saved in world.get("transferConnections",[]):
		if str(saved.get("id",""))==str(transfer.get("id","")):return {"ok":false,"error":"同一编号已经存在联系记录，不能覆盖。"}
	var candidate:=world.duplicate(true);candidate.transferConnections.append(connection.duplicate(true))
	var invalid:=SaveManager.validate(candidate)
	if not invalid.is_empty():return {"ok":false,"error":invalid}
	_execute("确认预留换乘",func(state:Dictionary):state.transferConnections=candidate.transferConnections.duplicate(true))
	return {"ok":true}

func _unlock_free() -> void:
	var revision:=int(world.revision)
	_confirm("进入自由创作","保留当前城市路网、历史成果与存档，在同一进度解除蓝图建设限制。",func():
		var result:=Story.unlock_free(world,revision)
		if not bool(result.get("ok",false)):_message("尚不能进入自由创作",str(result.get("error","请重新检查必做建设。")));return
		_enter(world);_mark_dirty()
		if not (await _save()):_message("自由创作尚未保存",save_error))

func _create_workshop_copy() -> void:
	var copy := Story.create_workshop_copy(world)
	if copy.is_empty():_message("暂时不能创建", "需要先完成本城当前已发布的全部历史章节。");return
	_leave(func():
		_enter(copy)
		if not (await _save()):_message("自由创作副本保存失败", save_error))

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
		var result:=_commit_plan_revision(index+1,revision)
		if not bool(result.get("ok",false)):_message("方案未采用",str(result.get("error","请重新对照。"))),func():map_view.set_blueprint(Story.blueprint(world,true)))

func _commit_plan_revision(index:int,expected_revision:int) -> Dictionary:
	if expected_revision!=int(world.revision):return {"ok":false,"error":"规划已变化，请重新对照。"}
	var versions:Array=Story.chapter(world).get("story",{}).get("planVersions",[])
	if index!=int(world.storyPlan.get("planIndex",0))+1 or index>=versions.size():return {"ok":false,"error":"只能依次采用本章下一版方案。"}
	_execute("采用历史修订方案",func(state:Dictionary):state.storyPlan.planIndex=index)
	return {"ok":true}

func _right() -> void:
	clear(right);clear(actions);confirm_button=null
	if world.is_empty():return
	right.add_child(button("收起详情",func():show_right=false;_layout()))
	if not map_view.draft_station.is_empty():
		var st:Dictionary=map_view.draft_station
		right.add_child(label("车站预览",24,true));right.add_child(label(str(st.name),20,true));right.add_child(label("拖动换位置；R旋转；确认后加入本章。",16))
		var elevation_text:="地下示意深度 %.0f 米" % -float(st.get("depthM",-15))
		if float(st.get("depthM",-15))>0:elevation_text="高架示意高度 %.0f 米" % float(st.depthM)
		elif is_zero_approx(float(st.get("depthM",-15))):elevation_text="地面示意站体"
		_angle(st,true);right.add_child(label("站体 %.0f × %.0f 米 · %s\n尺寸为游戏简化表达。" % [float(st.get("lengthM",119)),float(st.get("widthM",20)),elevation_text],16))
		var details:=CheckButton.new();details.text="建设资料与高级参数";details.button_pressed=advanced_edit;details.toggled.connect(func(value:bool):advanced_edit=value;_right());right.add_child(details)
		if advanced_edit:right.add_child(label(str(st.get("constructionNote","原始站体尺寸与埋深待核验，当前为游戏示意。")),15))
		confirm_button=button("确认车站",_commit_station);actions.add_child(confirm_button)
	elif not map_view.track_end_ref.is_empty():
		right.add_child(label("复现这一段",24,true));right.add_child(label("%s → %s" % [_ref_name(map_view.track_start_ref),_ref_name(map_view.track_end_ref)],18))
		right.add_child(label("长度 %.0f 米\n%s" % [float(pending_track.get("lengthM",0)),str(pending_track.get("issue",""))],16))
		right.add_child(label(str(pending_track.get("referenceLabel","手工示意连接")),15))
		if not str(pending_track.get("advisory","")).is_empty():right.add_child(label(str(pending_track.advisory),15))
		confirm_button=button("确认轨道段",_commit_track);actions.add_child(confirm_button)
	elif tool=="track" and batch_track_mode:
		right.add_child(label("连续复现相邻区间",24,true))
		right.add_child(label("按本章站序点击已经建设的相邻目标站。全部区间共用一次确认与撤销。",16))
		for index in range(batch_track_targets.size()):
			var target_name:=_historical_target_name(batch_track_targets[index])
			right.add_child(label("%d. %s" % [index+1,target_name],16))
		for segment in batch_track_segments:
			var a_name:=str(Story.bound_station(world,str(segment.fromId)).get("name","站点"));var b_name:=str(Story.bound_station(world,str(segment.toId)).get("name","站点"))
			right.add_child(label("%s → %s · %.0f 米 · %s" % [a_name,b_name,float(segment.get("lengthM",0)),"复用既有轨道" if bool(segment.get("reused",false)) else str(segment.get("referenceLabel", "参考线位"))],15))
			if not str(segment.get("issue", "")).is_empty():right.add_child(label("错误："+str(segment.issue),15,true))
		if not batch_track_targets.is_empty():
			actions.add_child(button("移除最后一个区间",_remove_last_batch_segment))
			actions.add_child(button("清空所选区间",func():batch_track_targets.clear();batch_track_segments.clear();map_view.draft_track_segments.clear();problem="已清空草稿；正式路网未改变。";_right();_instruction()))
		var batch_valid:=not batch_track_segments.is_empty() and batch_track_segments.all(func(segment:Dictionary):return str(segment.get("issue", "")).is_empty())
		confirm_button=button("确认全部 %d 段区间" % batch_track_segments.size(),_commit_batch_tracks);confirm_button.disabled=not batch_valid;actions.add_child(confirm_button)
	elif tool=="station":
		right.add_child(label("放置车站",24,true));right.add_child(label("点击地图中的历史目标站区，调整朝向后确认。尚未放置预览，不会修改正式路网。",18))
	elif tool=="track":
		right.add_child(label("连接轨道",24,true));right.add_child(label("点站端或节点，再点终点。自由端点标为待连接。",18))
		if str(world.get("mode", ""))=="campaign" and bool(world.storyState.get("learnedTools",false)):
			right.add_child(button("连续复现本章相邻区间",_begin_batch_tracks))
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
		var pending_lines:Array=evaluation.get("pendingTasks",[])
		if bool(evaluation.get("complete",false)) and pending_lines.is_empty():
			if bool(Story.chapter(world).get("eventOnly",false)):
				right.add_child(label("本节点的来源与日期已登记；没有新增铺轨目标。",18))
			else:
				right.add_child(label("目标站、站序和连续轨道已符合本章范围。",18))
			var facts:=Story.factual_report(world)
			if not facts.stationOffsets.is_empty():
				right.add_child(label("站区位置事实（相对现代地理参考，不是工程测量）",16,true))
				for fact in facts.stationOffsets.slice(0,5):
					right.add_child(label("%s：距参考站区中心 %.0f 米；章节容差 %.0f 米" % [str(fact.name),float(fact.distanceM),float(fact.toleranceM)],15))
			if not facts.segments.is_empty():
				right.add_child(label("区间资料",16,true))
				for fact in facts.segments.slice(0,6):
					var line_text:="· %s · %.2f 公里" % [str(fact.precision),float(fact.lengthM)/1000.0]
					if fact.has("meanDeviationM"):line_text+=" · 核验线位平均偏差 %.0f 米，最大 %.0f 米" % [float(fact.meanDeviationM),float(fact.maxDeviationM)]
					right.add_child(label("%s—%s %s" % [str(fact.from),str(fact.to),line_text],15))
			var current_chapter:=Story.chapter(world)
			var confirmation_label:="确认历史节点并开通展示" if bool(current_chapter.get("requireOpen",true)) else "确认建成节点（暂不运营）"
			if bool(current_chapter.get("eventOnly",false)):confirmation_label="确认历史资料节点"
			confirm_button=button(confirmation_label,_commit_chapter);actions.add_child(confirm_button)
		else:
			for issue in evaluation.get("issues",[]):
				right.add_child(label(str(issue.get("text","未完成")),16))
				if issue.has("stationBindingRepair"):
					right.add_child(button("保留现有轨道，修复站体关联",_repair_legacy_station_binding.bind(issue)))
				if issue.has("referenceTargetId"):
					right.add_child(button("预览调整到参考站区",_preview_reference_station_adjustment.bind(str(issue.get("objectId","")))))
				if issue.has("objectId"):right.add_child(button("定位问题",_locate_issue.bind(issue)))
			# Track is complete but the lines are not confirmed one by one yet. The
			# chapter-wide confirmation would refuse, so offer the step that works.
			if bool(evaluation.get("complete",false)) and not pending_lines.is_empty():
				right.add_child(label("本章 %d 项线路建设要先逐项确认：%s" % [pending_lines.size(),"、".join(pending_lines)],16,true))
				right.add_child(button("逐项确认本章线路建设",_confirm_pending_tasks))
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
				if str(target.get("stationInstanceId",""))!=str(st.get("stationInstanceId",st.id)) or str(target.name)==str(st.name):continue
				if bool(target.get("historicalNameRequired",false)):
					var value:=str(target.name);right.add_child(button("确认历史更名："+value,_rename_station.bind(value)))
				else:
					right.add_child(label("本期规划名称："+str(target.name),16,true))
					right.add_child(label("用于核对本期方案；当前开放站名保留。",15))
		right.add_child(button("移动车站",func():tool="move_station";map_view.tool=tool;_instruction()))
		var advanced:=CheckButton.new();advanced.text="高级几何编辑";advanced.button_pressed=advanced_edit;advanced.toggled.connect(func(value:bool):advanced_edit=value;_right());right.add_child(advanced)
		if advanced_edit:_angle(st,false)
		right.add_child(button("从A端铺轨",_from_station.bind(str(st.id),"start")));right.add_child(button("从B端铺轨",_from_station.bind(str(st.id),"end")))
		right.add_child(label("建设形式："+str(st.get("constructionForm","待核验")),15))
		right.add_child(label(str(st.get("constructionNote","车型、站体及埋深为游戏示意，历史参数待核验。")),15))
		right.add_child(label("历史身份：%s" % str(st.get("historicalId","自定车站")),15))
		var complex_id:=Catalog.canonical_station_complex(str(world.cityId),str(st.get("stationComplexId","")))
		if not complex_id.is_empty():
			right.add_child(label("所属换乘站区：%s" % complex_id,16,true))
			for member in world.get("stations",[]):
				if Catalog.canonical_station_complex(str(world.cityId),str(member.get("stationComplexId","")))!=complex_id or str(member.get("id",""))==str(st.get("id","")):continue
				right.add_child(button("切换到另一线路站体 · %s" % _station_line_name(member),func():selected_id=str(member.id);selected_kind="station";map_view.selected_id=selected_id;_right();_layout()))
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
		right.add_child(label("历史服务阶段："+Story.service_status_label(str(route.get("serviceStatus","open" if bool(route.get("open",false)) else "built"))),16))
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
	if value in ["station","track","line"] and str(world.get("mode",""))=="campaign" and str(Story.chapter(world).get("operationType",""))=="transfer_connection":
		page="story";show_left=true;show_right=false;problem="本期只需连接既有站体。请点击左侧“预览并建立换乘”，无需重新建站或铺轨。";_refresh();return
	if value!="select" and str(world.get("mode",""))=="campaign" and Story.chapter(world).is_empty():
		problem="当前资料已到边界，自由创作尚未解锁：请先完成本章结算与必做建设。";_instruction();return
	# A construction tool must leave read-only comparison first. Otherwise the
	# user sees an old proposal while the action guard correctly blocks editing,
	# which looks like the station/track tool ignored the click.
	if value in ["station","track","line"] and plan_view_index>=0:
		plan_view_index=-1;map_view.set_blueprint(Story.blueprint(world,true))
	if value in ["station","track","line"] and str(world.get("mode",""))=="campaign" and not Story.plan_is_final(world):
		page="story";show_left=true;show_right=false;problem="当前显示的是未实施历史草案。请先点击左侧“对比并采用下一版方案”，之后才能建设。";_refresh();return
	if value!="select":selected_id="";selected_kind="";map_view.selected_id=""
	_cancel_drafts();tool=value;map_view.tool=value;line_stops.clear();evaluation={};problem="";show_right=value!="select"
	if show_right and _narrow():show_left=false
	_right();_instruction();_layout()

func _cancel_drafts() -> void:
	map_view.assisted_preview={}
	map_view.draft_track_segments.clear();batch_track_targets.clear();batch_track_segments.clear();batch_track_mode=false;batch_track_revision=-1
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
			var a_id:=str(ids[si]);var b_id:=str(ids[si+1]);var a:=Story.bound_station(world,a_id,Story.station_instance_id(groups[gi],a_id),str(groups[gi].get("historicalLineId", "")));var b:=Story.bound_station(world,b_id,Story.station_instance_id(groups[gi],b_id),str(groups[gi].get("historicalLineId", "")))
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
	if batch_track_mode:
		_cancel_drafts();problem="连续铺轨草稿已取消；正式路网未改变。";_tool("select");return
	if not map_view.draft_station.is_empty() or not map_view.track_end_ref.is_empty():map_view.draft_station={};map_view.track_end_ref={};map_view.draft_track_points=[];pending_track={};map_view.clear_curve_preview()
	elif not map_view.track_start_ref.is_empty():map_view.track_start_ref={};map_view.draft_track_points=[]
	else:_tool("select")
	problem="";map_view.requested_redraw();_right();_instruction()

func _click(ll:Array,kind:String,id:String,side:String,t:float=-1) -> void:
	if world.is_empty():return
	if kind=="story_beat":_show_beat(Beats.find(world,id));return
	if kind=="blueprint_choice":
		var choices:=map_view.blueprint_choice_candidates.duplicate(true);show_right=true;clear(right);clear(actions)
		right.add_child(label("请选择目标站体",20,true))
		for entry in choices:
			var target:Dictionary=entry
			actions.add_child(button("%s · %s线站体" % [str(target.get("name","目标站")),str(target.get("historicalLineName",target.get("historicalLineId","本期线路")))],func():_click(target.get("latlng",ll),"blueprint",str(target.get("id","")),"")))
		_layout();return
	if kind=="station_choice":
		var choices:=map_view.station_choice_candidates.duplicate(true);show_right=true;clear(right);clear(actions)
		right.add_child(label("请选择具体线路站体",20,true))
		for entry in choices:
			var candidate:Dictionary=entry;var candidate_id:=str(candidate.get("id",""));var station:=WorldData.find_station(world,candidate_id)
			var choice_button:=button("%s线 · %s站体" % [_station_line_name(station),str(station.get("name","车站"))],func():_tool("select");_select("station",candidate_id))
			choice_button.mouse_entered.connect(func():map_view.selected_id=candidate_id;map_view.selected_type="station";map_view.requested_redraw())
			choice_button.mouse_exited.connect(func():map_view.selected_id=selected_id;map_view.selected_type=selected_kind;map_view.requested_redraw())
			actions.add_child(choice_button)
		_layout();return
	if tool=="track" and batch_track_mode and kind in ["blueprint","station"]:
		var historical_id:=id
		if kind=="station":historical_id=str(WorldData.find_station(world,id).get("stationInstanceId",WorldData.find_station(world,id).get("historicalId","")))
		if not historical_id.is_empty():_batch_select_target(historical_id)
		return
	if kind=="endpoint_choice":
		var candidates:=map_view.endpoint_choice_candidates.duplicate(true);show_right=true;clear(right);clear(actions)
		right.add_child(label("请选择接轨端点",20,true))
		for entry in candidates:
			var c:Dictionary=entry
			actions.add_child(button("%s · %s" % [str(WorldData.find_station(world,str(c.id)).get("name","节点")),"A端" if str(c.side)=="start" else "B端"],func():_click(c.latlng,str(c.type),str(c.id),str(c.side))))
		_layout();return
	if tool=="station":
		if str(world.mode)=="campaign" and not Story.plan_is_final(world):problem="这是未实施历史草案，先在左侧采用本期方案，再放置车站。";_instruction();_right();return
		var target:Dictionary={}
		if str(world.mode)=="campaign":
			if kind=="blueprint":
				for item in Story.targets(world,false,_active_task_id()):
					if str(item.get("id",""))==id:target=item;break
			else:target=Story.nearest_target(world,ll,_active_task_id())
		if str(world.mode)=="campaign" and target.is_empty():problem="请在蓝图目标站区放置车站；可点击左侧目标定位。";_instruction();return
		var construction_profile:=Story.profile(world,str(target.get("id","")))
		var candidate:={"id":"draft","name":str(target.get("name","新建车站%d" % (world.stations.size()+1))),"latlng":ll.duplicate(),"heading":90.0,"lengthM":118.788,"widthM":20.0,"depthM":map_view.current_depth_m,"historicalId":str(target.get("historicalId",target.get("id",""))),"stationInstanceId":str(target.get("stationInstanceId",target.get("id",""))),"referenceId":str(target.get("referenceId",target.get("id",""))),"stationComplexId":str(target.get("stationComplexId",target.get("historicalId",target.get("id","")))),"stationLineId":str(target.get("historicalLineId","")),"stationLineName":str(target.get("historicalLineName",target.get("historicalLineId",""))),"vehicleId":"B-6","existing":false,"routeIds":[]}
		if not target.is_empty():candidate.latlng=target.latlng.duplicate();candidate.heading=map_view.blueprint_heading_for(str(target.id))
		_apply_profile(candidate,construction_profile)
		if str(construction_profile.get("parameterStatus",{}).get("depthM","game_estimate"))=="game_estimate" and not str(construction_profile.get("form","")).contains("高架") and not str(construction_profile.get("form","")).contains("地面"):candidate.depthM=map_view.current_depth_m
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
		selected_kind="blueprint";selected_id=id;map_view.selected_id=id;map_view.selected_type="blueprint";show_right=true;evaluation={}
		if _narrow():show_left=false
		_trigger_beat("select",[id]);problem="已选中历史目标站区。右侧显示能否建设及下一步。";_right();_instruction();_layout()
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

func _begin_batch_tracks() -> void:
	if str(world.get("mode", "")) != "campaign" or not Story.plan_is_final(world): return
	_tool("track");batch_track_mode=true;batch_track_revision=int(world.get("revision", 0));map_view.draft_track_segments=[]
	problem="连续铺轨已就绪。依次点击本章中已经放置、彼此相邻的目标车站；可一次预览并确认多个区间。"
	show_right=true;_right();_instruction();_layout()

func _targets_adjacent(first_id:String,second_id:String) -> bool:
	for group in Story.groups(world,true,_active_task_id()):
		var ids:Array=group.get("stationIds",[])
		var instances:Array=[]
		for raw_id in ids:instances.append(Story.station_instance_id(group,str(raw_id)))
		var first_index:=instances.find(first_id);var second_index:=instances.find(second_id)
		if first_index>=0 and absi(first_index-second_index)==1:return true
	return false

func _batch_select_target(historical_id:String) -> void:
	var target:Dictionary={}
	for item in Story.targets(world,true,_active_task_id()):
		if str(item.get("id", ""))==historical_id:target=item;break
	if target.is_empty():problem="这不是本章目标站。请点选带目标标记的车站。";_right();_instruction();return
	var station:=Story.bound_station(world,historical_id)
	if station.is_empty():problem="请先使用“车站”工具放置并确认「%s」，再从这里批量铺轨。" % str(target.get("name", "目标站"));_right();_instruction();return
	if batch_track_targets.is_empty():
		batch_track_targets.append(historical_id);batch_track_revision=int(world.get("revision", 0));problem="已选起点「%s」。请点击同一线路中相邻的下一座目标站。" % str(station.get("name", "车站"))
	else:
		var previous_id:=batch_track_targets[-1]
		if historical_id==previous_id:return
		if not _targets_adjacent(previous_id,historical_id):problem="「%s」与「%s」不是本章线路中的相邻站；请按蓝图顺序选择相邻目标。" % [str(Story.bound_station(world,previous_id).get("name", "车站")),str(station.get("name", "车站"))];_right();_instruction();return
		var from_station:=Story.bound_station(world,previous_id)
		var ref_lat:=float(WorldData.city(str(world.cityId)).get("center",[31.23])[0])
		var existing_path:=TrackNetwork.shortest_station_path(str(from_station.id),str(station.id),world,ref_lat)
		var segment:Dictionary={"fromId":previous_id,"toId":historical_id,"issue":"","reused":false,"points":[],"lengthM":0.0}
		if bool(existing_path.get("valid",false)):
			segment.reused=true;segment.points=existing_path.get("points",[]);segment.lengthM=float(existing_path.get("distanceM",0))
		else:
			var ends:=_facing(from_station,station)
			var start_ref:=_ref(from_station.latlng,"endpoint",str(from_station.id),str(ends[0]))
			var finish_ref:=_ref(station.latlng,"endpoint",str(station.id),str(ends[1]))
			var alignment:=ReferenceAlignment.between(_target_reference_id(previous_id),_target_reference_id(historical_id))
			var preview:=ReferenceAlignment.preview(alignment,start_ref,finish_ref,world,ref_lat) if not alignment.is_empty() else rules.track_preview(start_ref,finish_ref,[],true)
			segment.start=start_ref;segment.finish=finish_ref;segment.edge=preview.get("edge",{});segment.points=preview.get("points",[]);segment.lengthM=float(preview.get("lengthM",0));segment.issue=str(preview.get("issue", ""));segment.referenceLabel=str(preview.get("referenceLabel",ReferenceAlignment.label_for({})))
		batch_track_segments.append(segment);batch_track_targets.append(historical_id)
		if not str(segment.get("issue", "")).is_empty():problem="%s → %s：%s" % [str(from_station.name),str(station.name),str(segment.issue)]
		else:problem="已加入「%s → %s」%s。继续点相邻目标站，或确认全部区间。" % [str(from_station.name),str(station.name),"（复用既有轨道）" if bool(segment.reused) else ""]
		_trigger_beat("preview_track",[previous_id,historical_id])
	map_view.draft_track_segments=batch_track_segments.duplicate(true);map_view.requested_redraw();_right();_instruction()

func _target_reference_id(instance_id:String) -> String:
	for target in Story.targets(world,true):
		if str(target.get("id",""))==instance_id:return str(target.get("referenceId",target.get("historicalId",instance_id)))
	return instance_id

func _remove_last_batch_segment() -> void:
	if not batch_track_segments.is_empty():batch_track_segments.pop_back()
	if batch_track_targets.size()>1:batch_track_targets.pop_back()
	map_view.draft_track_segments=batch_track_segments.duplicate(true)
	problem="已移除最后一个区间；正式路网未改变。"
	_right();_instruction();map_view.requested_redraw()

func _rebuild_batch_tracks() -> void:
	var targets:=batch_track_targets.duplicate()
	batch_track_targets.clear();batch_track_segments.clear();map_view.draft_track_segments.clear();batch_track_revision=int(world.get("revision",0))
	for id in targets:_batch_select_target(id)
	problem="规划已变化，连续区间已重新校验。请检查更新后的地图预览，再次确认。";_right();_instruction()

func _commit_batch_tracks() -> void:
	if batch_track_segments.is_empty():return
	if int(world.get("revision",0))!=batch_track_revision:_rebuild_batch_tracks();return
	for segment in batch_track_segments:
		if not str(segment.get("issue", "")).is_empty():problem="存在无效区间；没有任何轨道提交。请调整车站或改用单段工具修正。";_right();_instruction();return
	var to_commit:=batch_track_segments.duplicate(true)
	var add_count:=to_commit.filter(func(segment:Dictionary):return not bool(segment.get("reused",false))).size()
	if add_count==0:problem="选中的区间均已连通；正式路网没有变化。";_right();_instruction();return
	_execute("连续复现%d段区间" % to_commit.size(),func(state:Dictionary):
		for segment in to_commit:
			if bool(segment.get("reused",false)):continue
			var edge:Dictionary=segment.edge.duplicate(true);var start_ref:Dictionary=segment.start;var finish_ref:Dictionary=segment.finish
			edge.id="edge_%d_%d" % [Time.get_ticks_usec(),state.trackEdges.size()]
			edge.aNodeId=rules.materialize(state,start_ref);edge.bNodeId=rules.materialize(state,finish_ref);state.trackEdges.append(edge))
	if str(world.get("mode", ""))=="campaign":
		world.storyState.learnedTools=true
		for segment in to_commit:_trigger_beat("build_track",[str(segment.fromId),str(segment.toId)])
	_play_feedback("track");_tool("select");show_left=true;show_right=false;_refresh()

func _track_preview(finish:Dictionary) -> void:
	var start:=map_view.track_start_ref
	var a:=WorldData.find_station(world,str(start.get("stationId","")));var b:=WorldData.find_station(world,str(finish.get("stationId","")))
	var reference:=ReferenceAlignment.for_stations(a,b)
	if str(world.mode)=="campaign" and not advanced_edit and not reference.is_empty():
		pending_track=ReferenceAlignment.preview(reference,start,finish,world,float(WorldData.city(str(world.cityId)).center[0]))
	else:
		pending_track=rules.track_preview(start,finish,map_view.track_control_latlng,str(world.mode)=="campaign" and not advanced_edit)
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
	_play_feedback("track")
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
	_refresh()

func _station_changed() -> void:
	map_view.draft_conflict=rules._station_overlaps_in(map_view.draft_station,world.get("stations",[]));map_view.requested_redraw()

func _commit_station() -> void:
	var candidate:Dictionary=map_view.draft_station.duplicate(true)
	if candidate.is_empty():return
	if rules._station_overlaps_in(candidate,world.stations):problem="站体重叠，请移动或旋转后确认。";_right();return
	if not str(candidate.get("historicalId","")).is_empty() and not Story.bound_station(world,str(candidate.historicalId),str(candidate.get("stationInstanceId",""))).is_empty():problem="该线路站体目标已经建设。";_right();return
	_execute("建设%s" % str(candidate.name),func(state:Dictionary):
		candidate.id="station_%d" % Time.get_ticks_usec()
		var instance_id:=str(candidate.get("stationInstanceId",""));candidate.stationInstanceId=instance_id if not instance_id.is_empty() else candidate.id
		var complex_id:=str(candidate.get("stationComplexId",""))
		if not complex_id.is_empty():
			if not state.get("stationComplexes",[]).any(func(item:Dictionary):return str(item.get("id",""))==complex_id):state.stationComplexes.append({"id":complex_id,"name":str(candidate.name),"locationPrecision":"station_area_approximation","structureStatus":"not_surveyed"})
		state.stations.append(candidate);TrackNetwork.ensure_station_nodes(state))
	_play_feedback("station")
	_trigger_beat("build_station",[str(candidate.get("historicalId",""))])
	# Keep the station tool active so the next target can be placed immediately.
	map_view.draft_station={};map_view.tool="station";tool="station"
	selected_kind="";selected_id="";map_view.selected_id="";map_view.selected_type=""
	show_left=true;show_right=false;_refresh()

func _execute(title:String,mutation:Callable) -> void:
	if str(world.get("mode",""))=="campaign" and Story.chapter(world).is_empty():problem="当前已到资料边界，自由创作尚未解锁；已确认路网保持不变。";_instruction();_right();return
	var fields:Array=["stations","stationComplexes","transferConnections","serviceRanges","trackNodes","trackEdges","trackLinks","routes"]
	if title in ["采用历史修订方案","确认区间走向"]:fields=["storyPlan"]
	elif title=="确认线路重组":fields=["storyPlan","storyState","routes","stations","trackEdges","trackLinks","transferConnections"]
	elif title=="修改站名":fields=["stations"]
	elif title=="确认预留换乘":fields=["transferConnections"]
	elif title=="建立换乘联系":fields=["routes","stations","trackEdges","trackLinks","transferConnections"]
	elif title=="添加建设阶段":fields=["planningPhases","currentPlanningPhaseId"]
	elif title=="辅助完成重复建设":fields=["stations","stationComplexes","transferConnections","trackNodes","trackEdges","storyPlan"]
	if not history.execute(title,mutation,fields):return
	var coordinates:Array=[]
	var diff:Dictionary=world.history.undo.back().get("diff",{}).get("fields",{})
	for item in diff.get("stations",{}).get("items",{}).values():
		if item.get("before")==null and item.get("after") is Dictionary:coordinates.append(item.after.latlng)
	for item in diff.get("trackEdges",{}).get("items",{}).values():
		if item.get("before")==null and item.get("after") is Dictionary:
			var geometry:=TrackNetwork.edge_points(item.after,world,float(WorldData.city(str(world.cityId)).center[0]),8)
			if not geometry.is_empty():coordinates.append(geometry[geometry.size()/2])
	if title=="建立换乘联系":
		_play_feedback("transfer")
		for item in diff.get("transferConnections",{}).get("items",{}).values():
			if item.get("after") is Dictionary:
				for instance_id in item.after.get("stationInstanceIds",[]):
					for station in world.stations:
						if station.get("stationInstanceId","")==instance_id:coordinates.append(station.latlng)
	construction_feedback.pulse(coordinates)
	evaluation={};problem="";rules.world=world;_mark_dirty();_refresh()

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

func _reference_station_adjustment(station_id:String) -> Dictionary:
	var station:=WorldData.find_station(world,station_id)
	if station.is_empty():return {"ok":false,"error":"该站体已不存在。"}
	for target in Story.targets(world,true):
		if str(target.get("stationInstanceId",""))!=str(station.get("stationInstanceId",station_id)):continue
		var candidate:=station.duplicate(true)
		candidate.latlng=target.latlng.duplicate()
		var preview:=rules._station_preview_analysis(candidate,world)
		if not str(preview.get("issue","")).is_empty():return {"ok":false,"error":str(preview.issue)}
		return {"ok":true,"candidate":candidate,"preview":preview,"target":target,"revision":int(world.revision),"gameId":str(world.get("gameId","")),"chapterId":str(Story.chapter(world).get("id",""))}
	return {"ok":false,"error":"当前任务没有这个线路站体目标，请返回对应任务再调整。"}

func _commit_reference_station_adjustment(proposal:Dictionary,expected_revision:int) -> Dictionary:
	if expected_revision!=int(world.revision) or int(proposal.get("revision",-1))!=expected_revision or str(proposal.get("gameId",""))!=str(world.get("gameId","")) or str(proposal.get("chapterId",""))!=str(Story.chapter(world).get("id","")):
		return {"ok":false,"error":"规划或任务已变化，请重新预览参考站位。"}
	var fresh:=_reference_station_adjustment(str(proposal.get("candidate",{}).get("id","")))
	if not bool(fresh.get("ok",false)):return fresh
	if fresh.candidate!=proposal.get("candidate",{}):return {"ok":false,"error":"参考站区已变化，请重新预览。"}
	var preview:Dictionary=fresh.preview
	_execute("调整到参考站区",func(state:Dictionary):
		for key in ["stations","trackNodes","trackEdges","trackLinks"]:state[key]=preview.state.get(key,[]))
	return {"ok":true}

func _preview_reference_station_adjustment(station_id:String) -> void:
	var proposal:=_reference_station_adjustment(station_id)
	if not bool(proposal.get("ok",false)):_message("暂时无法调整",str(proposal.get("error","请先处理关联轨道。")));return
	var revision:=int(world.revision)
	var preview:Dictionary=proposal.preview
	preview_station=preview;preview_station["candidate"]=proposal.candidate
	selected_kind="station";selected_id=station_id;map_view.selected_id=station_id;map_view.selected_type="station"
	map_view._station_drag_preview_update(station_id,proposal.candidate.latlng)
	map_view.station_preview_edges=preview.edges;map_view.station_preview_issue="";map_view.requested_redraw()
	_confirm("调整到参考站区","将移动这座线路站体，并更新与它直接相连的轨道。其他站体和已确认历史记录保留；确认后可整步撤销。参考位置精度："+str(proposal.target.get("coordinateNote","近似站区，并非工程测量。")),func():
		var result:=_commit_reference_station_adjustment(proposal,revision)
		_discard_adjustment()
		if not bool(result.get("ok",false)):_message("站位未调整",str(result.get("error","请重新预览。"))),_discard_adjustment)

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
	_mark_dirty();_refresh()

func _check() -> void:
	_tool("select")
	evaluation=Story.evaluate(world);show_right=true
	if _narrow():show_left=false
	_right();_layout()

func _confirm_active_task() -> void:
	var selected_task:=_active_task_id()
	if selected_task.is_empty():return
	var result:=Story.evaluate(world,selected_task)
	if not bool(result.get("complete",false)):
		var details:Array[String]=[]
		for issue in result.get("issues",[]):details.append(str(issue.get("text","")))
		_message("本项建设还不能确认","\n".join(details.slice(0,8)) if not details.is_empty() else "请先完成这条线路的目标站、站序和相邻轨道。")
		return
	var chapter:=Story.chapter(world)
	var group_name:=selected_task
	for index in range(Story.groups(world,true).size()):
		var group:Dictionary=Story.groups(world,true)[index]
		if Story.task_id(chapter,group,index)==selected_task:group_name=str(group.get("name",group.get("historicalLineId",selected_task)));break
	var expected_revision:=int(result.get("revision",-1))
	var corrections:=Story.scope_correction_preview(world,selected_task)
	if not bool(corrections.ok):
		_message("请核对旧方案关系",str(corrections.get("error","")))
		return
	var confirmation_text:="只确认这项线路建设及其本期范围，不会确认同一章节里的其他线路、换乘或历史事件。确认后该任务成为当前历史记录。"
	for correction in corrections.get("changes",[]):confirmation_text+="\n\n资料修正："+str(correction.text)+" 原关系保留为历史记录，原有站体与轨道不删除。\n来源："+str(correction.source)
	_confirm("确认建设任务 · "+group_name,confirmation_text,func():
		var committed:=Story.confirm_task(world,selected_task,expected_revision,result)
		if not bool(committed.get("ok",false)):
			_message("建设任务未确认",str(committed.get("error","请重新检查当前任务。")))
			_refresh()
			return
		_play_feedback("track")
		_mark_dirty();evaluation={};show_left=true;show_right=false;_refresh();_locate_chapter())

func _commit_chapter() -> void:
	var chapter_groups:=Story.groups(world,true)
	if chapter_groups.size()>1 and not _active_task_id().is_empty():
		_confirm_active_task()
		return
	var teaching:=Tutorial.active(world)
	var result:=Story.commit_chapter(world,int(evaluation.get("revision",-1)),evaluation)
	if not bool(result.get("ok",false)):
		# A refusal only in the bottom strip reads as a dead button.
		problem=str(result.get("error","无法确认"))
		_message("历史节点未确认",problem)
		_check()
		return
	_play_feedback("chapter")
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

func _repair_legacy_station_binding(issue:Dictionary) -> void:
	var request:Dictionary=issue.get("stationBindingRepair",{})
	if request.is_empty():return
	var expected_revision:=int(request.get("expectedRevision",-1))
	var preview:=Story.prepare_legacy_station_body_repair(world,request,expected_revision)
	if not bool(preview.get("ok",false)):_message("无法安全修复",str(preview.get("error","请重新检查本章。")));return
	var repair:Dictionary=preview.repair
	var explanation:="将保留已经接好的全部轨道和「%s」站位，把它绑定为%s的本期目标；移除同位置、没有接轨的重复站体。修复会记为一步建设操作，可以撤销。" % [str(repair.get("stationName","车站")),str(repair.get("lineName","本期线路"))]
	_confirm("修复历史站体关联",explanation,func():
		if int(world.get("revision",0))!=expected_revision:_check();_message("规划已变化","修复预览已过期，请重新检查。没有修改建设。");return
		var confirmed:=Story.prepare_legacy_station_body_repair(world,request,expected_revision)
		if not bool(confirmed.get("ok",false)):_message("没有修改建设",str(confirmed.get("error","请重新检查。")));return
		var fixed_world:Dictionary=confirmed.world
		selected_kind="station";selected_id=str(repair.get("connectedStationId",""));map_view.selected_type="station";map_view.selected_id=selected_id
		_execute("修复历史站体关联",func(state:Dictionary):
			state.stations=fixed_world.stations.duplicate(true)
			state.trackNodes=fixed_world.trackNodes.duplicate(true))
		_check()
	)

func _locate_chapter() -> void:
	var blueprint:=Story.blueprint(world,false,_active_task_id())
	var targets:Array=blueprint.get("stations",[]).duplicate()
	targets.append_array(blueprint.get("engineeringMarkers",[]))
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
	elif tool=="station":
		var next_target:Dictionary={}
		for item in Story.targets(world,true,_active_task_id()):
			if not bool(item.get("built",false)):next_target=item;break
		hint.text="站点：下一目标「%s」· 点击目标圈预览，调整后确认。R旋转。" % str(next_target.get("name","点击目标站区"))
	elif tool=="track" and batch_track_mode:
		var selected_names:Array[String]=[]
		for id in batch_track_targets:
			var target:=Story.targets(world,true).filter(func(item:Dictionary):return str(item.id)==id)
			if not target.is_empty():selected_names.append(str(target[0].name))
		hint.text="连续复现：%s · 点击下一座相邻目标站；确认会一次提交全部区间。" % (" → ".join(selected_names) if not selected_names.is_empty() else "请选择起始目标站")
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
		elif bool(evaluation.get("complete",false)) and evaluation.get("pendingTasks",[]).is_empty():target=confirm_button;text="确认本章历史节点"
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

## Two different neighbours must not share one platform end. A ring closes
## through the opposite end of its first station, so a section that simply took
## the facing end again would leave both the closing section and the departure
## on one end and the ring could never be confirmed.
func _free_end_for(state:Dictionary,station:Dictionary,side:String,other_id:String) -> String:
	var node_id:=TrackNetwork.station_node_id(station,side)
	if node_id.is_empty():return side
	var other_side:="end" if side=="start" else "start"
	var other_node:=TrackNetwork.station_node_id(station,other_side)
	var facing_used_by:=_edge_neighbour_station(state,node_id,str(station.get("id","")))
	var other_used_by:=_edge_neighbour_station(state,other_node,str(station.get("id","")))
	if facing_used_by.is_empty() or facing_used_by==other_id:return side
	if other_used_by.is_empty() or other_used_by==other_id:return other_side
	return side

func _edge_neighbour_station(state:Dictionary,node_id:String,own_station_id:String) -> String:
	if node_id.is_empty():return ""
	for edge in TrackNetwork.all_physical_edges(state):
		var ends:Array=TrackNetwork._edge_node_ids(edge,state)
		if ends.size()!=2 or not ends.has(node_id):continue
		var far_node:=str(ends[0]) if str(ends[1])==node_id else str(ends[1])
		var far_station:=str(TrackNetwork.find_node(state,far_node).get("stationId",""))
		if far_station.is_empty() or far_station==own_station_id:continue
		return far_station
	return ""

func _facing(a:Dictionary,b:Dictionary) -> Array:
	var alignment:=ReferenceAlignment.for_stations(a,b)
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
		var committed:=_commit_assisted_construction(result,revision)
		if not bool(committed.get("ok",false)):_message("辅助建设未应用",str(committed.get("error","请重新预览。")));return
		_tool("select");show_left=true;show_right=false;_refresh(),func():map_view.assisted_preview={};map_view.requested_redraw())

## A terminal extension uses the unused platform end. Nearest endpoints alone
## may reconnect to the arrival end and introduce a hidden reversal.
func _existing_terminal_port(state:Dictionary,station_id:String,line_id:String,path_index:Dictionary,ref_lat:float) -> String:
	if line_id.is_empty():return ""
	for route in state.get("routes",[]):
		if str(route.get("historicalLineId",""))!=line_id or bool(route.get("retired",false)) or not str(route.get("constructionVariantId","")).is_empty():continue
		for direction in route.get("directions",[]):
			var ids:Array=direction.get("stationIds",[]);var paths:Array=direction.get("edgePathsBySegment",[])
			if ids.size()<2 or paths.size()!=ids.size()-1:continue
			if str(ids.front())==station_id:
				var path:=TrackNetwork.ordered_station_path(str(ids[0]),str(ids[1]),paths[0],state,ref_lat,path_index)
				if bool(path.get("valid",false)):return str(path.fromNodeId)
			if str(ids.back())==station_id:
				var path:=TrackNetwork.ordered_station_path(str(ids[-2]),str(ids[-1]),paths[-1],state,ref_lat,path_index)
				if bool(path.get("valid",false)):return str(path.toNodeId)
	return ""

func _required_extension_port(state:Dictionary,station_id:String,other_id:String,line_id:String,path_index:Dictionary,ref_lat:float,scope_instances:Array=[]) -> String:
	# Reconfirming an already served pair uses its existing path. A prebuilt
	# but unopened pair is different: it must still join the unused terminal
	# end, even when a shorter old edge is present in the physical graph.
	for route in state.get("routes",[]):
		if str(route.get("historicalLineId",""))!=line_id or bool(route.get("retired",false)) or not str(route.get("constructionVariantId","")).is_empty():continue
		for direction in route.get("directions",[]):
			var ids:Array=direction.get("stationIds",[])
			for i in range(ids.size()-1):
				if (str(ids[i])==station_id and str(ids[i+1])==other_id) or (str(ids[i])==other_id and str(ids[i+1])==station_id):return ""
	# Inserting a delayed station replaces the old section between two existing
	# anchors. At either boundary preserve the port toward the in-scope old
	# neighbour, so the untouched section outside the draft stays continuous.
	# Geographic proximity alone can choose that outside section's occupied end.
	var replacement_ports:Dictionary={}
	if not scope_instances.is_empty():
		for route in state.get("routes",[]):
			if str(route.get("historicalLineId",""))!=line_id or bool(route.get("retired",false)) or not str(route.get("constructionVariantId","")).is_empty():continue
			for direction in route.get("directions",[]):
				var ids:Array=direction.get("stationIds",[]);var paths:Array=direction.get("edgePathsBySegment",[])
				var at:=int(ids.find(station_id))
				# Only an interior station has one neighbour on each side. A
				# terminal has a single neighbour, and extending from it must use
				# the free end instead of stacking onto the neighbour it already
				# serves.
				if at<=0 or at+1>=ids.size() or paths.size()!=ids.size()-1:continue
				var neighbours:Array=[]
				if at>0:neighbours.append(at-1)
				if at+1<ids.size():neighbours.append(at+1)
				var inside:Array=neighbours.filter(func(i:int):
					var neighbour:=WorldData.find_station(state,str(ids[i]))
					return scope_instances.has(str(neighbour.get("stationInstanceId",neighbour.get("id","")))))
				if inside.size()!=1:continue
				var neighbour_index:=int(inside[0]);var segment_index:=mini(at,neighbour_index)
				var old_path:=TrackNetwork.ordered_station_path(str(ids[segment_index]),str(ids[segment_index+1]),paths[segment_index],state,ref_lat,path_index)
				if bool(old_path.get("valid",false)):replacement_ports[str(old_path.toNodeId if neighbour_index<at else old_path.fromNodeId)]=true
	if replacement_ports.size()==1:return str(replacement_ports.keys()[0])
	var used:=_existing_terminal_port(state,station_id,line_id,path_index,ref_lat)
	if used.is_empty():return ""
	var station:=WorldData.find_station(state,station_id)
	var free_side:="end" if used==TrackNetwork.station_node_id(station,"start") else "start"
	var free_node:=TrackNetwork.station_node_id(station,free_side)
	# Only a terminal keeps a genuinely unused end. A through station already
	# serves two different neighbours; taking that end again would stack a
	# second section onto the neighbour that owns it, so a ring could never
	# close and the loop would report the same platform end twice. Leave the
	# port open here and let the path search reuse the existing section.
	for edge in TrackNetwork.all_physical_edges(state):
		var ends:Array=TrackNetwork._edge_node_ids(edge,state)
		if ends.size()!=2 or not ends.has(free_node):continue
		var other_node:=str(ends[0]) if str(ends[1])==free_node else str(ends[1])
		var other_station_id:=str(TrackNetwork.find_node(state,other_node).get("stationId",""))
		if not other_station_id.is_empty() and other_station_id!=other_id:return ""
	return free_node

func _assist_required_ports(state:Dictionary,group:Dictionary,index:int,prior_arrival:String,path_index:Dictionary,ref_lat:float) -> Array:
	var ids:Array=group.get("stationIds",[]);var line_id:=str(group.get("historicalLineId",""))
	var a:=Story.bound_station(state,str(ids[index]),Story.station_instance_id(group,str(ids[index])),line_id)
	var b:=Story.bound_station(state,str(ids[index+1]),Story.station_instance_id(group,str(ids[index+1])),line_id)
	var departure:="";var arrival:=""
	# Replacing a line after an infill is not an extension beyond its former
	# terminal. The old arrival end stays the arrival end. Asking for its unused
	# end here made the inserted final section turn back through the platform,
	# leaving the following genuine extension impossible. Constrain a replacement
	# to its reference-facing ends, preserving all old physical construction.
	# A separately stored future infill uses those same facing ports without
	# replacing the current service. A real extension still needs the free end.
	var replacing:=bool(group.get("replaceExistingService",false)) or str(group.get("connectionMode",""))=="infill"
	var facing:=_facing(a,b) if replacing else []
	var scope_instances:Array=[]
	if not replacing and (index==0 or index==ids.size()-2):
		for id in ids:scope_instances.append(Story.station_instance_id(group,str(id)))
	if not prior_arrival.is_empty():departure=TrackNetwork.station_node_id(a,"end" if prior_arrival==TrackNetwork.station_node_id(a,"start") else "start")
	elif index==0:departure=TrackNetwork.station_node_id(a,str(facing[0])) if replacing else _required_extension_port(state,str(a.id),str(b.id),line_id,path_index,ref_lat,scope_instances)
	if index==ids.size()-2:arrival=TrackNetwork.station_node_id(b,str(facing[1])) if replacing else _required_extension_port(state,str(b.id),str(a.id),line_id,path_index,ref_lat,scope_instances)
	elif index+2<ids.size():
		var next:=Story.bound_station(state,str(ids[index+2]),Story.station_instance_id(group,str(ids[index+2])),line_id)
		if not next.is_empty():
			var onward:=TrackNetwork.shortest_station_path_indexed(str(b.id),str(next.id),state,path_index,ref_lat)
			if bool(onward.get("valid",false)) and not onward.get("edges",[]).is_empty() and not onward.edges.any(func(ref:Dictionary):return bool(ref.edge.get("platform",false))):
				arrival=TrackNetwork.station_node_id(b,"end" if str(onward.edges[0].fromNodeId)==TrackNetwork.station_node_id(b,"start") else "start")
	return [departure,arrival]

func _assist_path_matches_ports(path:Dictionary,ports:Array) -> bool:
	if not bool(path.get("valid",false)) or path.get("edges",[]).is_empty():return false
	if path.edges.any(func(ref:Dictionary):return bool(ref.edge.get("platform",false))):return false
	return (str(ports[0]).is_empty() or str(path.edges[0].get("fromNodeId",""))==str(ports[0])) and (str(ports[1]).is_empty() or str(path.edges[-1].get("toNodeId",""))==str(ports[1]))

func _assist_candidate() -> Dictionary:
	if Story.chapter(world).is_empty() or bool(Story.chapter(world).get("eventOnly",false)):return {"issue":"当前没有建设任务。请先在故事页选择本期建设范围。"}
	var candidate:=world.duplicate(true);var helper:=Rules.new();helper.world=candidate;helper.active_city_id=str(world.cityId);helper.map_view=map_view
	for target in Story.targets(candidate,true):
		if bool(target.built):
			if bool(target.get("historicalNameRequired",false)):Story.bound_station(candidate,str(target.historicalId),str(target.stationInstanceId),str(target.get("historicalLineId", ""))).name=target.name
			continue
		if bool(target.get("engineeringExistingAnchor",false)):return {"issue":"既有接头「%s」缺少对应线路站体。请先修复原线路；本工程不会增建这个车站。"%str(target.name)}
		var station:={"id":"assist_%s" % str(target.id),"stationInstanceId":str(target.stationInstanceId),"referenceId":str(target.get("referenceId",target.id)),"stationComplexId":str(target.stationComplexId),"stationLineId":str(target.historicalLineId),"stationLineName":str(target.get("historicalLineName",target.historicalLineId)),"name":str(target.name),"historicalId":str(target.historicalId),"latlng":target.latlng.duplicate(),"heading":float(target.referenceHeading) if float(target.referenceHeading)>=0 else map_view.blueprint_heading_for(str(target.id)),"lengthM":118.788,"widthM":20.0,"depthM":-15.0,"vehicleId":"B-6","existing":false,"routeIds":[]}
		_apply_profile(station,Story.profile(candidate,str(target.id)))
		if helper._station_overlaps_in(station,candidate.stations):return {"issue":"%s 与现有站体冲突，请手动调整。" % str(station.name)}
		candidate.stations.append(station)
		var complex_id:=str(target.stationComplexId)
		if not candidate.get("stationComplexes",[]).any(func(item:Dictionary):return str(item.get("id",""))==complex_id):candidate.stationComplexes.append({"id":complex_id,"name":str(target.name),"locationPrecision":"station_area_approximation","structureStatus":"not_surveyed"})
		TrackNetwork.ensure_station_nodes(candidate)
	var construction_groups:Array=Story.groups(candidate,true)
	for connection in Story.chapter(candidate).get("requiredConnections",[]):construction_groups.append({"stationIds":[connection.fromId,connection.toId]})
	var construction_lat:=float(WorldData.city(str(world.cityId)).center[0])
	TrackNetwork.ensure_station_nodes(candidate)
	var path_index:=TrackNetwork.build_path_index(candidate,construction_lat)
	for group in construction_groups:
		if Engineering.is_group(group):
			var engineering_result:=Engineering.add_preview(candidate,group)
			if not str(engineering_result.get("issue","")).is_empty():return engineering_result
			path_index=TrackNetwork.build_path_index(candidate,construction_lat)
			continue
		var ids:Array=group.get("stationIds",[]);var prior_arrival:="";var first_departure:=""
		for index in range(ids.size()-1):
			var a_id:=str(ids[index]);var b_id:=str(ids[index+1]);var a_instance:=Story.station_instance_id(group,a_id);var b_instance:=Story.station_instance_id(group,b_id)
			var a:=Story.bound_station(candidate,a_id,a_instance,str(group.get("historicalLineId", "")));var b:=Story.bound_station(candidate,b_id,b_instance,str(group.get("historicalLineId", "")))
			var reusable:Dictionary={}
			var required_ports:=_assist_required_ports(candidate,group,index,prior_arrival,path_index,construction_lat)
			var primary:=TrackNetwork.shortest_station_path_indexed(str(a.id),str(b.id),candidate,path_index,construction_lat)
			if _assist_path_matches_ports(primary,required_ports):
				reusable=primary
			else:
				# Search alternate branches only when the cheapest path would use a
				# station platform or force an immediate same-end reversal.
				var options:=TrackNetwork.station_path_options_indexed(str(a.id),str(b.id),candidate,path_index,construction_lat,4)
				for option in options:
					if not _assist_path_matches_ports(option,required_ports):continue
					reusable=option;break
			if not reusable.is_empty():
				if first_departure.is_empty():first_departure=str(reusable.edges[0].get("fromNodeId",""))
				prior_arrival=str(reusable.edges[-1].get("toNodeId",""));continue
			var ends:=_facing(a,b)
			ends[0]=_free_end_for(candidate,a,str(ends[0]),str(b.id))
			ends[1]=_free_end_for(candidate,b,str(ends[1]),str(a.id))
			if not str(required_ports[0]).is_empty():ends[0]="start" if required_ports[0]==TrackNetwork.station_node_id(a,"start") else "end"
			if not str(required_ports[1]).is_empty():ends[1]="start" if required_ports[1]==TrackNetwork.station_node_id(b,"start") else "end"
			if bool(group.get("loop",false)) and index==ids.size()-2 and not first_departure.is_empty():ends[1]="end" if first_departure==TrackNetwork.station_node_id(b,"start") else "start"
			var start:={"nodeId":TrackNetwork.station_node_id(a,str(ends[0])),"stationId":a.id,"side":str(ends[0]),"latlng":WorldData.station_endpoint(a,str(ends[0])),"depthM":a.get("depthM",-15)}
			var finish:={"nodeId":TrackNetwork.station_node_id(b,str(ends[1])),"stationId":b.id,"side":str(ends[1]),"latlng":WorldData.station_endpoint(b,str(ends[1])),"depthM":b.get("depthM",-15)}
			var alignment:=ReferenceAlignment.between(str(group.get("stationReferenceIds",{}).get(a_id,a_id)),str(group.get("stationReferenceIds",{}).get(b_id,b_id)))
			var preview:=ReferenceAlignment.preview(alignment,start,finish,candidate,construction_lat) if not alignment.is_empty() else helper.track_preview(start,finish,[],true)
			if not str(preview.get("issue","")).is_empty():return {"issue":"%s—%s：%s；请手工处理。" % [str(a.name),str(b.name),str(preview.issue)]}
			var edge:Dictionary=preview.edge;edge.id="assist_edge_%d_%d" % [index,Time.get_ticks_usec()];candidate.trackEdges.append(edge);TrackNetwork.add_path_index_edge(path_index,edge,candidate,construction_lat);prior_arrival=str(finish.nodeId)
			if first_departure.is_empty():first_departure=str(start.nodeId)
	# The preview has already selected a continuous, non-reversing path for each
	# segment. Persist those choices in the draft so the evaluator and the
	# eventual commit inspect the same physical branch instead of independently
	# falling back to a shorter route through the opposite platform end.
	var assisted_choices:Dictionary={}
	var assisted_groups:Array=Story.groups(candidate,true)
	for group_index in range(assisted_groups.size()):
		var assisted_group:Dictionary=assisted_groups[group_index]
		if Engineering.is_group(assisted_group):continue
		var station_ids:Array=assisted_group.get("stationIds",[])
		var prior_end:=""
		for segment_index in range(station_ids.size()-1):
			var from_station:=Story.bound_station(candidate,str(station_ids[segment_index]),Story.station_instance_id(assisted_group,str(station_ids[segment_index])),str(assisted_group.get("historicalLineId","")))
			var to_station:=Story.bound_station(candidate,str(station_ids[segment_index+1]),Story.station_instance_id(assisted_group,str(station_ids[segment_index+1])),str(assisted_group.get("historicalLineId","")))
			if from_station.is_empty() or to_station.is_empty():continue
			var required_ports:=_assist_required_ports(candidate,assisted_group,segment_index,prior_end,path_index,construction_lat)
			var primary:=TrackNetwork.shortest_station_path_indexed(str(from_station.id),str(to_station.id),candidate,path_index,construction_lat)
			if _assist_path_matches_ports(primary,required_ports):
				prior_end=str(primary.edges[-1].get("toNodeId",""))
				continue
			var options:=TrackNetwork.station_path_options_indexed(str(from_station.id),str(to_station.id),candidate,path_index,construction_lat,4)
			var selected_index:=-1
			for option_index in range(options.size()):
				var option:Dictionary=options[option_index]
				var path_edges:Array=option.get("edges",[])
				if not _assist_path_matches_ports(option,required_ports):continue
				selected_index=option_index
				break
			if selected_index<0:
				if options.is_empty():continue
				selected_index=0
			var selected_path:Dictionary=options[selected_index]
			assisted_choices["%d:%d" % [group_index,segment_index]]=selected_index
			if not selected_path.get("edges",[]).is_empty():prior_end=str(selected_path.edges[-1].get("toNodeId",""))
	candidate.storyPlan["pathChoices"]=assisted_choices
	return {"state":candidate,"issue":"","revision":int(world.revision),"gameId":str(world.gameId),"chapterId":str(Story.chapter(world).get("id",""))}

## The same transaction is used by the visible preview confirmation and replay.
func _commit_assisted_construction(preview:Dictionary,expected_revision:int) -> Dictionary:
	if Story.chapter(world).is_empty() or bool(Story.chapter(world).get("eventOnly",false)):return {"ok":false,"error":"当前没有可提交的建设任务，请返回故事页选择。"}
	if expected_revision!=int(world.revision) or int(preview.get("revision",-1))!=expected_revision:return {"ok":false,"error":"规划已变化，请重新预览辅助建设。"}
	if str(preview.get("gameId",""))!=str(world.gameId) or str(preview.get("chapterId",""))!=str(Story.chapter(world).get("id","")):return {"ok":false,"error":"草稿不属于当前游戏或章节。"}
	if not Story.plan_is_final(world):return {"ok":false,"error":"请先采用本期方案。"}
	if not str(preview.get("issue","")).is_empty() or not preview.get("state") is Dictionary:return {"ok":false,"error":str(preview.get("issue","辅助草稿无效。"))}
	var candidate:Dictionary=preview.state
	var invalid:=SaveManager.validate(candidate)
	if not invalid.is_empty():return {"ok":false,"error":invalid}
	var changed:=history.execute("辅助完成重复建设",func(state:Dictionary):
		for key in ["stations","stationComplexes","trackNodes","trackEdges"]:state[key]=candidate.get(key,[]).duplicate(true)
		state.storyPlan["pathChoices"]=candidate.get("storyPlan",{}).get("pathChoices",{}).duplicate(true)
		state.storyPlan["assisted"]=true,
		["stations","stationComplexes","trackNodes","trackEdges","storyPlan"])
	if changed:evaluation={};problem="";rules.world=world;_mark_dirty();_refresh()
	return {"ok":true,"changed":changed}

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
	var result:=_commit_line_reorganization(int(world.revision))
	if not bool(result.get("ok",false)):evaluation=result.get("evaluation",Story.evaluate(world));show_right=true;_right();_layout();return
	_tool("select");show_left=true;show_right=false;_refresh()

func _commit_line_reorganization(expected_revision:int) -> Dictionary:
	if expected_revision!=int(world.revision):return {"ok":false,"error":"规划已变化，请重新核对线路重组。"}
	if not bool(Story.chapter(world).get("requiresLineReorganization",false)):return {"ok":false,"error":"当前章节不需要线路重组。"}
	var probe:=world.duplicate(false);probe["storyPlan"]=world.storyPlan.duplicate(true);probe.storyPlan.reorganizationAccepted=true
	var checked:=Story.evaluate(probe)
	# Ready interchange pairs are a separate player confirmation after the
	# service split. Their absence must not create a circular prerequisite.
	if checked.get("issues",[]).any(func(issue:Dictionary):return not bool(issue.get("pendingConfirmation",false))):return {"ok":false,"error":"请先完成本期站序、连接与换乘。","evaluation":checked}
	var correction:=Story.scope_correction_preview(world,"")
	if not bool(correction.get("ok",false)):return correction
	var candidate:=world.duplicate(true)
	candidate.storyPlan["reorganizationAccepted"]=true
	for route in checked.routes:Story._store_historical_route(candidate,route)
	Story._apply_scope_corrections(candidate,correction)
	var continuity_error:=Story.changed_service_continuity_error(candidate,checked.routes)
	if not continuity_error.is_empty():return {"ok":false,"error":continuity_error}
	Story._refresh_route_memberships(candidate)
	var invalid:=SaveManager.validate(candidate)
	if not invalid.is_empty():return {"ok":false,"error":invalid}
	_execute("确认线路重组",func(state:Dictionary):
		for key in ["storyPlan","storyState","routes","stations","trackEdges","trackLinks","transferConnections"]:state[key]=candidate[key].duplicate(true))
	return {"ok":true}

func _new_phase() -> void:
	_text_prompt("建设阶段","新的规划阶段",func(value:String):_execute("添加建设阶段",func(state:Dictionary):
		var id:="phase_%d" % Time.get_ticks_usec();state.planningPhases.append({"id":id,"name":value,"stationIds":[],"edgeIds":[],"routeIds":[]});state.currentPlanningPhaseId=id))

func _replay(index:int) -> void:
	_confirm("创建复盘副本","当前进度会先保存。复盘副本不会覆盖本城原进度。",func():
		var copy:=Story.replay_copy(world,index)
		if copy.is_empty():_message("无法安全复盘","旧章节未能匹配当前资料包，已保留原记录；当前进度不会被替换。");return
		_leave(func():_enter(copy);_save()))

func _open_history_player() -> void:
	var player:=preload("res://scripts/history_player.gd").new()
	add_child(player)
	set_process_unhandled_key_input(false)
	player.tree_exiting.connect(func():set_process_unhandled_key_input(true))
	player.open(world)

func _open_challenges() -> void:
	var hub:=preload("res://scripts/challenge_hub.gd").new()
	add_child(hub)
	hub.open()

func _open_schematic() -> void:
	var canvas_size:=Vector2(minf(1400,size.x-96),minf(800,size.y-180))
	var layout:=preload("res://scripts/schematic_layout.gd").build(world,canvas_size)
	if not layout.get("ok",false):problem=str(layout.get("reason","线路图暂不可用。"));_instruction();return
	var dialog:=_dialog("游戏线路示意图 · %s"%str(world.get("cityName","")))
	var column:=VBoxContainer.new();dialog.add_child(column)
	var view:=preload("res://scripts/schematic_view.gd").new();view.layout=layout;view.font=face;view.custom_minimum_size=canvas_size;column.add_child(view)
	column.add_child(label("游戏线路示意图 · 按已确认线路关系绘制 · 虚线表示换乘联系",15))
	dialog.popup_centered_ratio(0.9)

func _dialog(title:String) -> AcceptDialog:
	var d:=AcceptDialog.new();d.title=title;d.ok_button_text="关闭";add_child(d);d.confirmed.connect(d.queue_free);d.close_requested.connect(d.queue_free);return d

func _message(title:String,text:String) -> void:
	if not world.is_empty() and title in ["本期范围暂不可确认","本期范围已确认","换乘联系尚不能建立","换乘关系已存在","换乘预览无效","换乘联系未建立","预留接口尚未就绪","预留接口未确认","规划已变化","方案未采用","辅助建设不可应用","辅助建设未应用"]:
		problem=text;show_right=true;_right()
		var inline_note:=label(title+"\n"+text,16,true);right.add_child(inline_note);right.move_child(inline_note,0)
		_instruction();_layout();return
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
		summary.text="共%d份 · %.1f MB；新自动保存覆盖单一进度槽，旧版自动历史可逐份删除。" % [entries.size(),float(total)/1048576.0]
	search.text_changed.connect(refresh);refresh.call()
	var row:=HFlowContainer.new();body.add_child(row)
	if not world.is_empty():
		row.add_child(button("立即保存",func():
			if not (await _save()):_message("保存失败",save_error)
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
	if str(entry.kind) in ["自动进度","自动历史","旧版自动历史原件","手动存档"]:
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
		elif str(entry.kind)=="旧版自动历史原件":result=SaveManager.delete_legacy_auto_history(str(entry.path))
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
	body.add_child(label("建设反馈音效",18,true))
	var motion_toggle:=CheckButton.new();motion_toggle.text="减少建设动画";motion_toggle.button_pressed=not Prefs.load_ui_motion_enabled();body.add_child(motion_toggle)
	motion_toggle.toggled.connect(func(value:bool):Prefs.save_ui_motion_enabled(not value))
	var audio_toggle:=CheckButton.new();audio_toggle.text="播放建站、接轨和历史节点提示音";audio_toggle.button_pressed=feedback_enabled;body.add_child(audio_toggle)
	audio_toggle.toggled.connect(func(value:bool):
		feedback_enabled=value;Prefs.save_feedback_enabled(value)
		if value:_play_feedback("track"))
	var volume:=HSlider.new();volume.min_value=0;volume.max_value=1;volume.step=0.05;volume.value=feedback_volume;volume.custom_minimum_size.y=32;body.add_child(volume)
	var volume_label:=label("音量 %.0f%%" % roundi(feedback_volume*100),15);body.add_child(volume_label)
	volume.value_changed.connect(func(value:float):feedback_volume=value;Prefs.save_feedback_volume(value);volume_label.text="音量 %.0f%%" % roundi(value*100))
	var automatic:=CheckButton.new();automatic.text="定时自动保存未保存修改";automatic.button_pressed=auto_enabled;body.add_child(automatic)
	automatic.toggled.connect(func(value:bool):auto_enabled=value;Prefs.save_timed_autosave_enabled(value))
	body.add_child(label("自动保存每5分钟检查一次；有修改时覆盖当前进度槽。手动保存和离开游戏时也会保存。",15))
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
	elif selected_kind=="blueprint":
		var target:Dictionary={}
		for candidate in Story.targets(world,true):
			if str(candidate.get("id",""))==selected_id:target=candidate;break
		if target.is_empty():return
		right.add_child(label("历史目标站区",24,true));right.add_child(label("%s · %s" % [str(target.get("historicalLineId","本期线路")),str(target.get("name","目标站"))],20,true))
		if bool(target.get("built",false)):
			right.add_child(label("已建设；该目标不会重复放置。",16))
			var existing:=Story.bound_station(world,str(target.get("id","")),str(target.get("stationInstanceId","")))
			if not existing.is_empty():right.add_child(button("查看已建站体",_select.bind("station",str(existing.id))))
		elif not Story.plan_is_final(world):
			right.add_child(label("当前显示的是未实施历史草案，尚不能建设。",16,true));right.add_child(button("对比并采用下一版方案",_revise))
		else:
			right.add_child(label("可建设 · 参考站区容差 %.0f 米；该容差不代表资料测量精度。" % float(target.get("toleranceM",100)),16))
			right.add_child(button("按参考位置与朝向放置",func():_tool("station");_click(target.get("latlng",[]),"blueprint",str(target.get("id","")),"")))
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
	var beat:=Beats.eligible(world,event,ids)
	if Tutorial.active(world) and not bool(world.get("storyState",{}).get("learnedTools",false)):
		if not beat.is_empty():pending_beat_id=str(beat.get("id",""))
		return
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
