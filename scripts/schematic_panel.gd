extends Control
const Ui=preload("res://scripts/ui_theme.gd")
signal export_requested(layout:Dictionary)
var worker:=Thread.new()
var prepared:=false
var cancelled:=false
var result:Dictionary={}

func open(source:Dictionary,font:Font) -> void:
	theme=get_parent().theme;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Ui.CANVAS;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var column:=VBoxContainer.new();column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(column)
	var top:=HBoxContainer.new();column.add_child(top)
	var back:=Button.new();back.text="← 返回建设";back.custom_minimum_size.y=44;top.add_child(back)
	var status:=Label.new();status.text="正在生成线路拓扑示意图……";status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(status)
	back.pressed.connect(func():
		if worker.is_alive():cancelled=true;status.text="正在取消，请稍候。"
		else:queue_free())
	var preferred:=Vector2(clampf(get_viewport_rect().size.x-96,400,1400),clampf(get_viewport_rect().size.y-180,260,800))
	worker.start(func():return SchematicLayout.fit(source,preferred))
	while worker.is_alive():await get_tree().process_frame
	result=worker.wait_to_finish()
	if cancelled:queue_free();return
	prepared=true
	if not result.get("ok",false):status.text=str(result.get("reason","请使用地理视图查看。"));return
	status.text="线路示意图 · 虚线表示规划线路 · 细虚线表示换乘通道"
	var save:=Button.new();save.text="导出示意图 PNG";save.custom_minimum_size.y=44;top.add_child(save);save.pressed.connect(func():export_requested.emit(result))
	var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(split)
	var scroll:=ScrollContainer.new();scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;split.add_child(scroll)
	var view:=preload("res://scripts/schematic_view.gd").new();view.layout=result;view.font=font;view.custom_minimum_size=result.bounds;scroll.add_child(view)
	var legend_scroll:=ScrollContainer.new();legend_scroll.custom_minimum_size.x=230;legend_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;split.add_child(legend_scroll)
	var legend:=VBoxContainer.new();legend.size_flags_horizontal=Control.SIZE_EXPAND_FILL;legend_scroll.add_child(legend)
	var attribution:=Label.new();attribution.text="玩家复现 · 现代地理参考 · © OpenStreetMap contributors";attribution.add_theme_font_size_override("font_size",15);attribution.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(attribution)
	var seen:={}
	for stroke in result.strokes:
		var key:=str(stroke.name)+str(stroke.color)
		if seen.has(key):continue
		seen[key]=true
		var row:=HBoxContainer.new();legend.add_child(row)
		var color:=ColorRect.new();color.color=Color(str(stroke.color));color.custom_minimum_size=Vector2(20,6);color.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(color)
		var label:=Label.new();label.text=str(stroke.name)+("（规划）" if stroke.get("planned",false) else "");label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)

func _exit_tree() -> void:
	if worker.is_started():worker.wait_to_finish()
