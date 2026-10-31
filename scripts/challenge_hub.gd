extends Control

const Catalog=preload("res://scripts/challenge_catalog.gd")
const Session=preload("res://scripts/challenge_session.gd")
var profile:Dictionary
var body:VBoxContainer
var map:MapView
var answer_edit:LineEdit
var note:Label
var cities:OptionButton
var periods:OptionButton
var lines:OptionButton
var stations:Array[Dictionary]=[]
var found:Dictionary={}
var mode:="memory"
var memory_key:=""
var questions:Array[Dictionary]=[]
var question_index:=0
var candidate:Array=[]
var practice:=false
var answer_locked:=false
var results:Array=[]
var daily_question:Dictionary={}
var save_problem:=""
var ambiguity_buttons:Array[Button]=[]

func open() -> void:
	theme=get_parent().theme;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	profile=Session.load_profile()
	var panel:=ColorRect.new();panel.color=Color("#111923");panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	var column:=VBoxContainer.new();column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(column)
	var top:=HBoxContainer.new();column.add_child(top)
	_add_button(top,"← 返回主菜单",func():queue_free())
	_add_button(top,"站名默写",func():mode="memory";_select_scope())
	_add_button(top,"站位挑战",func():mode="location";_select_scope())
	_add_button(top,"每日一题",_daily)
	var selectors:=HFlowContainer.new();column.add_child(selectors)
	cities=OptionButton.new()
	for city in WorldData.cities():cities.add_item(city.name);cities.set_item_metadata(cities.item_count-1,city.id)
	selectors.add_child(cities);cities.item_selected.connect(func(_index:int):_periods())
	periods=OptionButton.new();selectors.add_child(periods);periods.item_selected.connect(func(_index:int):_select_scope())
	lines=OptionButton.new();selectors.add_child(lines);lines.item_selected.connect(func(_index:int):_select_scope())
	var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(split)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.x=330;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;split.add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	map=preload("res://scripts/map_view.gd").new();map.size_flags_horizontal=Control.SIZE_EXPAND_FILL;map.bold_font=theme.default_font;map.show_train_display=false;split.add_child(map)
	map.map_clicked.connect(func(ll:Array,_kind:String,_id:String,_side:String,_t:float):
		if mode=="daily_location" and not answer_locked:candidate=ll.duplicate();_draw_found(true);return
		if mode=="location" and not answer_locked and question_index<questions.size():candidate=ll.duplicate();_draw_found(true))
	var attribution:=Label.new();attribution.text="现代地理参考 · © OpenStreetMap contributors · 站位奖牌仅对照游戏参考坐标，不代表测绘精度。";attribution.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;attribution.add_theme_font_size_override("font_size",15);column.add_child(attribution)
	_periods()

func _add_button(parent:Node,text:String,callback:Callable) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=44;parent.add_child(button);button.pressed.connect(callback);return button

func _label(text:String) -> Label:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(label);return label

func _periods() -> void:
	periods.clear();lines.clear();lines.add_item("全部线路");lines.set_item_metadata(0,"")
	var city:=str(cities.get_selected_metadata())
	var dates:={}
	for chapter in CampaignSystem.city_config(city).get("chapters",[]):
		var date:=str(chapter.get("date",""))
		if date.length()==10 and date<="2026-10-01" and not chapter.get("lineGroups",[]).is_empty():dates[date]=true
	for date in dates:periods.add_item(str(date));periods.set_item_metadata(periods.item_count-1,date)
	if periods.item_count>0:periods.select(periods.item_count-1)
	var line_ids:={}
	for chapter in CampaignSystem.city_config(city).get("chapters",[]):
		for group in chapter.get("lineGroups",[]):
			var id:=str(group.get("historicalLineId",""))
			if id.is_empty() or line_ids.has(id):continue
			line_ids[id]=true;lines.add_item(str(group.get("name","历史线路")));lines.set_item_metadata(lines.item_count-1,id)
	_select_scope()

func _clear() -> void:
	_clear_ambiguity()
	for child in body.get_children():body.remove_child(child);child.queue_free()

func _select_scope() -> void:
	_clear();candidate=[];results=[];question_index=0;practice=false;found={}
	map.highlight_path_points=[]
	var city:=str(cities.get_selected_metadata());var date:=str(periods.get_selected_metadata())
	map.set_context(WorldData.city(city),{"cityId":city,"mode":"workshop","stations":[],"routes":[],"revision":0})
	if profile.has("error"):_label(str(profile.error));return
	if mode=="location":
		questions=Catalog.location_questions(city,date)
		if questions.size()<5:
			questions=[]
			var practice_pool:=Catalog.memory_stations(city,date,str(lines.get_selected_metadata()))
			practice_pool.shuffle()
			for station in practice_pool.slice(0,5):
				var question:Dictionary=station.duplicate(true)
				question.merge({"period":date,"practiceOnly":true,"fact":"此题尚未绑定完整参考版本，仅作位置练习，不授奖牌。","hint":"可按道路、水系和地标判断大致位置。"},true)
				questions.append(question)
			if questions.size()<5:_label("本范围不足5个站点，请选择较晚时期或全部线路。");return
		questions=questions.slice(0,5);_location_question();return
	mode="memory"
	stations=Catalog.memory_stations(city,date,str(lines.get_selected_metadata()))
	memory_key="%s:%s:%s:%s"%[Catalog.load_bank().get("version",""),city,date,str(lines.get_selected_metadata())]
	found=profile.get("memory",{}).get(memory_key,{}).duplicate(true)
	_label("站名默写 · %s"%date)
	_label("输入这一时期已发布建设目标的站名。可接受有记录的曾用名；换乘站只计一次。")
	_label("站名")
	answer_edit=LineEdit.new();answer_edit.placeholder_text="输入站名，按回车确认";answer_edit.custom_minimum_size.y=44;body.add_child(answer_edit)
	answer_edit.text_submitted.connect(_answer)
	note=_label("")
	_add_button(body,"提示一站",func():_reveal(false))
	_add_button(body,"查看全部答案（练习）",func():_reveal(true))
	_draw_found();_memory_note();answer_edit.grab_focus()

func _answer(text:String) -> void:
	if not DisplayServer.ime_get_text().is_empty():return
	_clear_ambiguity()
	var matches:=Session.match_name(stations,text)
	if matches.is_empty():note.text="本范围没有匹配的站名，请检查时期和线路。";return
	if matches.size()>1:
		note.text="同名站，请选择对应线路："
		for station in matches:
			var entry:Dictionary=station
			ambiguity_buttons.append(_add_button(body,"%s · %s"%[entry.name,entry.line],func():_accept(entry)))
		return
	_accept(matches[0])

func _accept(station:Dictionary) -> void:
	_clear_ambiguity()
	var id:=str(station.historicalId)
	if found.has(id):note.text="这座站已经点亮。";return
	found[id]="independent";_persist_memory();_draw_found();_memory_note()
	note.text+="\n本期名称："+str(station.name)
	if not station.get("aliases",[]).is_empty():note.text+="\n记录中的曾用名："+"、".join(station.aliases)
	answer_edit.clear();answer_edit.grab_focus()

func _clear_ambiguity() -> void:
	for button in ambiguity_buttons:
		if is_instance_valid(button):
			if button.get_parent()!=null:button.get_parent().remove_child(button)
			button.queue_free()
	ambiguity_buttons.clear()

func _persist_memory() -> void:
	if not profile.has("memory"):profile.memory={}
	profile.memory[memory_key]=found.duplicate(true)
	var saved:=Session.save_profile(profile)
	save_problem="" if bool(saved.get("ok",false)) else "挑战记录保存失败："+str(saved.get("error","请重试"))

func _memory_note() -> void:
	var independent:=0
	for value in found.values():
		if value=="independent":independent+=1
	note.text="独立答对 %d / %d · 提示或查看 %d"%[independent,stations.size(),found.size()-independent]
	if not save_problem.is_empty():note.text+="\n"+save_problem

func _reveal(all_stations:bool) -> void:
	for station in stations:
		if not found.has(str(station.historicalId)):
			found[str(station.historicalId)]="hint"
			if not all_stations:break
	_persist_memory();_draw_found();_memory_note()

func _draw_found(with_candidate:bool=false) -> void:
	var shown:Array=[]
	if mode=="memory":
		for station in stations:
			if found.has(str(station.historicalId)):shown.append({"id":station.id,"name":station.name,"latlng":station.latlng,"heading":90,"lengthM":20,"widthM":10,"depthM":-15})
	if with_candidate and not candidate.is_empty():shown.append({"id":"answer","name":"我的落点","latlng":candidate.duplicate(),"heading":90,"lengthM":20,"widthM":10,"depthM":-15})
	map.set_world({"stations":shown,"routes":[],"mode":"workshop","revision":Time.get_ticks_usec()})

func _location_question() -> void:
	_clear();candidate=[];practice=false;answer_locked=false
	map.highlight_path_points=[];_draw_found()
	if question_index>=questions.size():
		_label("本局已完成")
		for result in results:_label("偏差约 %d 米 · %s"%[result.displayDistanceM,result.medal])
		return
	var question:Dictionary=questions[question_index]
	practice=bool(question.get("practiceOnly",false))
	_label("第 %d / 5 题\n%s · %s · %s"%[question_index+1,question.name,question.line,question.period])
	if question.get("referenceBasis","")=="game_reference":_label("按游戏参考坐标评分，不代表测绘精度。")
	if practice:_label("位置练习 · 不授奖牌\n显示距离只用于本游戏对照。")
	note=_label("点击地图放置答案，再确认。")
	var submit:Button
	submit=_add_button(body,"确认落点",func():
		if answer_locked:return
		if candidate.is_empty():note.text="请先在地图放置答案。";return
		var result:=Session.location_practice(question,candidate) if bool(question.get("practiceOnly",false)) else Session.location_result(question,candidate,practice)
		if not result.get("ok",false):note.text=str(result.error);return
		answer_locked=true
		# A deferred refresh prevents a second click from crediting this question.
		for child in body.get_children():
			if child is Button:child.disabled=true
		results.append(result);question_index+=1
		if not profile.has("location"):profile.location=[]
		profile.location.append(result.duplicate(true))
		while profile.location.size()>500:profile.location.pop_front()
		var saved:=Session.save_profile(profile)
		note.text="偏差约 %d 米 · %s\n%s"%[result.displayDistanceM,result.medal,question.get("fact","")]
		if not saved.get("ok",false):note.text+="\n成绩保存失败，请重试。"
		map.highlight_path_points=[candidate.duplicate(),question.latlng.duplicate()]
		var shown:Dictionary={"id":"reference","name":"参考位置 · "+str(question.name),"latlng":question.latlng.duplicate(),"heading":90,"lengthM":20,"widthM":10,"depthM":-15}
		var answer:Dictionary=shown.duplicate(true);answer.id="answer";answer.name="我的落点";answer.latlng=candidate.duplicate()
		map.set_world({"stations":[shown,answer],"routes":[],"mode":"workshop","revision":Time.get_ticks_usec()})
		_add_button(body,"查看位置核验来源",func():OS.shell_open(str(question.source)))
		_add_button(body,"下一题",_location_question))
	_add_button(body,"提示（本题转练习）",func():practice=true;note.text=str(question.get("hint","可查看该站相关历史资料。")))
	_draw_found()

func _daily() -> void:
	mode="daily";candidate=[];map.highlight_path_points=[];_clear();_draw_found()
	var bank:=Catalog.load_bank();var date:=Session.beijing_date(Time.get_unix_time_from_system())
	var assigned:=Session.daily(bank,date)
	if assigned.is_empty():_label("今天没有已审核的每日题；可以选择站名默写进行练习。");return
	daily_question={}
	for question in bank.get("questions",[]):
		if str(question.get("id",""))==str(assigned.get("questionId","")) and (question.get("reviewStatus","")=="verified" or (question.get("type","")=="location" and Session.eligible(question))):daily_question=question.duplicate(true)
	if daily_question.is_empty():_label("每日题缺失，未记成绩。");return
	daily_question.merge({"date":date,"version":bank.version},true)
	_label("每日一题 · "+date);_label("历史知识循环复习 · 第%d轮"%int(assigned.get("reviewCycle",1)));_label(str(daily_question.prompt))
	var daily_key:="%s:%s"%[bank.version,date]
	var previous:Dictionary=profile.get("daily",{}).get(daily_key,{})
	if not previous.is_empty():_label("今日首次结果已保存，再答为练习。")
	if daily_question.get("type","")=="location":_daily_location(daily_key);return
	for index in range(daily_question.get("options",[]).size()):
		var choice:=index
		_add_button(body,str(daily_question.options[index]),func():
			var correct:=choice==int(daily_question.answer)
			var result:={"correct":correct,"practice":profile.get("daily",{}).has(daily_key)}
			Session.record_daily(profile,daily_key,result)
			var saved:=Session.save_profile(profile)
			_clear();_label(("回答正确。" if correct else "已完成，查看历史解释：")+str(daily_question.get("explanation","")))
			if not saved.get("ok",false):_label("保存失败："+str(saved.get("error","")))
			_add_button(body,"打开题目来源",func():OS.shell_open(str(daily_question.source)))
			_add_button(body,"导出分享卡 PNG",func():_share_card(result)))

func _daily_location(key:String) -> void:
	mode="daily_location";answer_locked=false;candidate=[];practice=profile.get("daily",{}).has(key)
	map.set_context(WorldData.city(str(daily_question.cityId)),{"stations":[],"routes":[],"mode":"workshop"})
	_label("按游戏参考坐标评分，不代表测绘精度。")
	note=_label("在地图上点击落点，再确认答案。")
	_add_button(body,"确认今日落点",func():
		if answer_locked:return
		var result:=Session.location_result(daily_question,candidate,practice)
		if not result.get("ok",false):note.text="请先在地图放置有效落点。";return
		answer_locked=true
		Session.record_daily(profile,key,result)
		var saved:=Session.save_profile(profile)
		_clear();_label("相对参考坐标偏差约 %d 米 · %s\n不代表测绘精度。"%[result.displayDistanceM,result.medal])
		if not saved.get("ok",false):_label("成绩保存失败，请重试。")
		map.highlight_path_points=[candidate.duplicate(),daily_question.latlng.duplicate()]
		map.set_world({"stations":[{"id":"reference","name":"参考位置 · "+str(daily_question.name),"latlng":daily_question.latlng.duplicate(),"heading":90,"lengthM":20,"widthM":10,"depthM":-15}],"routes":[],"mode":"workshop","revision":Time.get_ticks_usec()})
		_add_button(body,"查看参考来源",func():OS.shell_open(str(daily_question.source)))
		_add_button(body,"导出分享卡 PNG",func():_share_card(result)))
	_add_button(body,"提示（本题转练习）",func():practice=true;note.text=str(daily_question.get("hint","请观察道路与地标。")))

func _share_card(result:Dictionary) -> void:
	var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;dialog.add_filter("*.png","PNG分享卡");dialog.current_file="每日地铁题.png";add_child(dialog)
	dialog.title="保存每日题分享卡";dialog.ok_button_text="保存分享卡";dialog.cancel_button_text="取消"
	dialog.file_selected.connect(func(path:String):
		dialog.queue_free()
		var viewport:=SubViewport.new();viewport.size=Vector2i(900,600);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var background:=ColorRect.new();background.color=Color("#182733");background.size=Vector2(900,600);viewport.add_child(background)
		var text:=Label.new();text.theme=theme;text.position=Vector2(48,80);text.size=Vector2(804,440);text.add_theme_font_size_override("font_size",28);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.text=Session.share_text(daily_question,result);viewport.add_child(text)
		await RenderingServer.frame_post_draw
		var error:=preload("res://scripts/media_export_job.gd").save_png_atomic(viewport.get_texture().get_image(),path);viewport.queue_free()
		_label("分享卡已导出。" if error==OK else "分享卡写入失败。"))
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(0.7)
