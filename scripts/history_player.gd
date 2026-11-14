extends Control

signal closed
const Playback = preload("res://scripts/history_playback.gd")
const Ui = preload("res://scripts/ui_theme.gd")
var archive: Dictionary
var map: MapView
var caption: Label
var slider: HSlider
var playing := false
var elapsed := 0.0
var duration := 60.0
var current := -1
var status: Label
var export_job:Node
var back:Button
var all_frames:Array=[]
var announcement:AnnouncementPlayer
var node_start_seconds:=0.0
var growth:Control
var settled:=true
var prepared:=false
var build_worker:=Thread.new()
var cancel_build:=false

func open(source: Dictionary) -> void:
	theme=get_parent().theme;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var loading:=ColorRect.new();loading.color=Ui.CANVAS;loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(loading)
	var loading_text:=Label.new();loading_text.text="正在加载城市发展史……";loading_text.position=Vector2(32,80);loading.add_child(loading_text)
	var cancel:=Button.new();cancel.text="取消";cancel.custom_minimum_size=Vector2(160,44);loading.add_child(cancel)
	cancel.pressed.connect(func():cancel_build=true;loading_text.text="正在取消，请稍候。")
	# The modal overlay holds the formal world read-only until restoration ends.
	# Only detached planning dictionaries are produced on this worker.
	build_worker.start(func():return Playback.build(source))
	while build_worker.is_alive():await get_tree().process_frame
	archive=build_worker.wait_to_finish()
	if cancel_build:closed.emit();queue_free();return
	loading.queue_free()
	announcement=preload("res://scripts/announcement_player.gd").new();add_child(announcement)
	all_frames=archive.frames.duplicate()
	theme = get_parent().theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new(); background.color=Ui.CANVAS;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var column := VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(column)
	var top := HBoxContainer.new(); column.add_child(top)
	back = Button.new(); back.text = "← 返回建设"; back.custom_minimum_size.y = 44; top.add_child(back)
	back.pressed.connect(func():
		playing=false
		if is_instance_valid(export_job):export_job.cancel();status.text="正在取消导出，请稍候。";return
		closed.emit();queue_free())
	caption = Label.new(); caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL; caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; top.add_child(caption)
	var source_button := Button.new(); source_button.text="查看节点来源"; top.add_child(source_button)
	source_button.pressed.connect(func():
		if current>=0:
			var url:=str(archive.frames[current].source)
			if url.begins_with("https://") or url.begins_with("http://"): OS.shell_open(url))
	var lane:=OptionButton.new();lane.add_item("历史通车成果");lane.add_item("规划展示");top.add_child(lane)
	lane.item_selected.connect(func(index:int):_select_lane(index==1))
	map = preload("res://scripts/map_view.gd").new(); map.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(map)
	map.resized.connect(_fit)
	map.bold_font=theme.default_font; map.tool="select"; map.show_train_display=false
	growth=preload("res://scripts/history_growth.gd").new();growth.map=map;map.add_child(growth)
	var controls := HFlowContainer.new(); column.add_child(controls)
	var play := Button.new(); play.text="播放 / 暂停"; play.custom_minimum_size.y=44; controls.add_child(play); play.pressed.connect(func(): playing=not playing)
	slider=HSlider.new(); slider.custom_minimum_size=Vector2(220,44);slider.min_value=0; slider.max_value=maxi(0,archive.frames.size()-1); slider.step=1; slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL; controls.add_child(slider)
	slider.value_changed.connect(func(value:float): elapsed=value/maxf(1,archive.frames.size())*duration; _show_frame(int(value)))
	var length:=OptionButton.new()
	for seconds in [30,60,120]: length.add_item("%d秒"%seconds); length.set_item_metadata(length.item_count-1,seconds)
	length.select(1); controls.add_child(length); length.item_selected.connect(func(index:int):duration=float(length.get_item_metadata(index)))
	var export_button:=Button.new(); export_button.text="导出视频 (WebM)"; controls.add_child(export_button); export_button.pressed.connect(_export)
	var cover:=Button.new();cover.text="导出当前画面 (PNG)";controls.add_child(cover);cover.pressed.connect(_cover)
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.text=str(archive.warning)+"\n玩家复现 · 现代地理参考 · © OpenStreetMap contributors"; column.add_child(status)
	if archive.frames.is_empty(): caption.text="暂无已通车成果"; play.disabled=true; export_button.disabled=true;prepared=true; return
	map.set_context(WorldData.city(str(source.cityId)), archive.frames.back().world.duplicate(true))
	_fit()
	_select_lane(false)
	prepared=true

func _exit_tree() -> void:
	if build_worker.is_started():build_worker.wait_to_finish()

func _select_lane(planning:bool) -> void:
	if is_instance_valid(export_job):return
	playing=false;elapsed=0;current=-1
	announcement.reset()
	archive.frames=[]
	for index in range(all_frames.size()):
		var frame:Dictionary=all_frames[index].duplicate(false)
		frame["beforeWorld"]=all_frames[index-1].world if index>0 else archive.get("initialWorld",{})
		if bool(frame.planning)==planning:archive.frames.append(frame)
	slider.max_value=maxi(0,archive.frames.size()-1);slider.set_value_no_signal(0)
	if archive.frames.is_empty():caption.text="当前存档暂无已确认的"+("规划展示" if planning else "历史通车成果");map.set_world({});return
	_fit();_show_frame(0)

func _cover() -> void:
	if current<0:return
	var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;dialog.add_filter("*.png","PNG 图片");dialog.current_file="地铁发展史.png";add_child(dialog)
	dialog.title="保存发展史画面";dialog.ok_button_text="保存画面";dialog.cancel_button_text="取消"
	dialog.file_selected.connect(func(path:String):
		dialog.hide()
		await RenderingServer.frame_post_draw
		var error:=preload("res://scripts/media_export_job.gd").save_png_atomic(get_viewport().get_texture().get_image(),path)
		status.text="画面已导出。" if error==OK else "画面保存失败，请检查写入权限。"
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(0.7)

func _fit() -> void:
	if archive.frames.is_empty():return
	var stations: Array=archive.frames.back().world.get("stations",[])
	if stations.is_empty():return
	var low:=Vector2(INF,INF); var high:=Vector2(-INF,-INF)
	for station in stations:
		var p:=Geo.project(station.latlng,12); low=low.min(p); high=high.max(p)
	var center:=Geo.unproject((low+high)*0.5,12)
	var span:=high-low
	var scale:=minf(maxf(240,map.size.x-160)/maxf(span.x,1),maxf(240,map.size.y-120)/maxf(span.y,1))
	map.center_on(center,clampi(12+int(floor(log(scale)/log(2.0))),7,17))

func _show_frame(index:int) -> void:
	if index==current or archive.frames.is_empty():return
	current=index
	node_start_seconds=elapsed;announcement.reset()
	var frame:Dictionary=archive.frames[index]
	settled=not playing
	growth.prepare(frame.get("beforeWorld",{}),frame.world,map.geometry_ref_lat)
	growth.progress=1 if settled else 0
	map.set_world((frame.world if settled else frame.get("beforeWorld",{})).duplicate(true))
	caption.text="%s · %s · %s\n%s" % [archive.cityName, frame.date, frame.title, "规划展示" if frame.planning else "历史复现"]

func _process(delta:float) -> void:
	if not prepared:return
	if not playing or archive.frames.is_empty():announcement.stop();return
	elapsed=minf(duration,elapsed+delta)
	slider.set_value_no_signal(Playback.frame_index(elapsed,duration,archive.frames.size()))
	_show_frame(int(slider.value))
	if not settled:
		growth.progress=clampf((elapsed-node_start_seconds)/(duration/maxi(1,archive.frames.size())*0.75),0,1);growth.queue_redraw()
		if growth.progress>=1:map.set_world(archive.frames[current].world.duplicate(true));settled=true
	map.show_train_display=settled;map.presentation_seconds=elapsed-node_start_seconds;map.requested_train_redraw()
	announcement.update_from_map(map,map.presentation_seconds,settled)
	if elapsed>=duration:playing=false; elapsed=0

func _export() -> void:
	if archive.frames.is_empty():status.text="当前分类下没有可导出的记录。";return
	if is_instance_valid(export_job):export_job.cancel();return
	playing=false
	var dialog:=FileDialog.new(); dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE; dialog.add_filter("*.webm","WebM 视频"); dialog.current_file="地铁发展史.webm"; add_child(dialog)
	dialog.title="导出发展史视频";dialog.ok_button_text="导出视频";dialog.cancel_button_text="取消"
	dialog.file_selected.connect(func(path:String):
		dialog.queue_free()
		var job:=preload("res://scripts/media_export_job.gd").new(); add_child(job);export_job=job;back.text="取消导出"
		job.progress.connect(func(text:String):status.text=text)
		await job.export_video(archive,path,duration,theme)
		job.queue_free();export_job=null;back.text="← 返回建设")
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(0.75)
