extends Node

signal progress(text: String)
var cancelled := false
var pid := -1
var busy := false
var worker := Thread.new()
var temporary_files: Array[String] = []
var temporary_dir := ""

func cancel() -> void:
	cancelled=true
	if pid>0 and OS.is_process_running(pid):OS.kill(pid)

func _exit_tree() -> void:
	cancel()
	if worker.is_started():worker.wait_to_finish()
	_cleanup()

func encoder_path(name:String) -> String:
	var bundled:=OS.get_executable_path().get_base_dir().path_join("media").path_join(name+".exe")
	if FileAccess.file_exists(bundled):return bundled
	var development:=ProjectSettings.globalize_path("res://.tools/media-runtime/"+name+".exe")
	if FileAccess.file_exists(development):return development
	# Development can use an explicitly installed component. Release packaging
	# must supply media/ with its redistribution notices and source information.
	for folder in OS.get_environment("PATH").split(";"):
		var candidate:=folder.path_join(name+".exe")
		if FileAccess.file_exists(candidate):return candidate
	return ""

func export_video(archive:Dictionary,path:String,duration:float,ui_theme:Theme) -> Dictionary:
	if busy:return {"ok":false,"error":"已有导出正在进行。"}
	if archive.get("frames",[]).is_empty():return {"ok":false,"error":"没有可导出的历史节点。"}
	var encoder:=encoder_path("ffmpeg");var probe:=encoder_path("ffprobe")
	if encoder.is_empty() or probe.is_empty():
		progress.emit("未找到视频编码组件；发行包需包含 media/ffmpeg.exe 和 ffprobe.exe。")
		return {"ok":false,"error":"缺少视频编码组件。"}
	busy=true;cancelled=false
	temporary_dir=path.get_base_dir().path_join(".metro-export-%d"%Time.get_ticks_usec())
	if DirAccess.make_dir_absolute(temporary_dir)!=OK:return _finish(false,"无法创建导出临时目录。")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1920,1080);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var column:=VBoxContainer.new();column.size=Vector2(1920,1080);column.theme=ui_theme;viewport.add_child(column)
	var title:=Label.new();title.custom_minimum_size.y=80;title.add_theme_font_size_override("font_size",28);column.add_child(title)
	var map:=preload("res://scripts/map_view.gd").new();map.custom_minimum_size=Vector2(1920,930);map.bold_font=ui_theme.default_font;map.show_train_display=false;column.add_child(map)
	var growth:=preload("res://scripts/history_growth.gd").new();growth.map=map;map.add_child(growth)
	var attribution:=Label.new();attribution.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;attribution.add_theme_font_size_override("font_size",15);attribution.text="玩家复现 · 现代地理参考 · © OpenStreetMap contributors";column.add_child(attribution)
	var final_world:Dictionary=archive.frames.back().world
	map.set_context(WorldData.city(str(archive.cityId)),final_world.duplicate(true))
	var center:Array=WorldData.city(str(archive.cityId)).get("center",[31.23,121.47])
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for station in final_world.get("stations",[]):
		var point:=Geo.project(station.latlng,12);low=low.min(point);high=high.max(point)
	var zoom:=12
	if low.is_finite():
		center=Geo.unproject((low+high)*0.5,12)
		zoom=clampi(12+int(floor(log(minf(1700/maxf(high.x-low.x,1),780/maxf(high.y-low.y,1)))/log(2.0))),7,17)
	map.center_on(center,zoom)
	# Keep input responsive while asynchronous local tiles settle. Readiness,
	# not a fixed delay, decides whether a complete map can be captured.
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if cancelled:break
		if not map._base_map_thread_busy and map._base_map_pending_request.is_empty():break
	if map._base_map_thread_busy or not map._base_map_pending_request.is_empty():
		viewport.queue_free();return _finish(false,"本地地图仍未就绪，请稍后重试导出。")
	var concat:=""
	var last_file:=""
	for index in range(archive.frames.size()):
		if cancelled:break
		var frame:Dictionary=archive.frames[index]
		title.text="%s · %s · %s  %s"%[archive.cityName,frame.date,frame.title,"规划建设展示" if frame.planning else ""]
		attribution.text="玩家复现 · 现代地理参考 · © OpenStreetMap contributors · 地图日期：%s\n节点来源：%s"%[map.base_map_snapshot,str(frame.get("source","未保留来源"))]
		var before:Dictionary=frame.get("beforeWorld",archive.frames[index-1].world if index>0 else archive.get("initialWorld",{}))
		growth.prepare(before,frame.world,map.geometry_ref_lat)
		var samples:=16 if growth.total_m>0 or not growth.stations.is_empty() else 1
		map.set_world(before.duplicate(true) if samples>1 else frame.world.duplicate(true))
		for sample_index in range(samples):
			if cancelled:break
			growth.progress=float(sample_index)/maxi(1,samples-1) if samples>1 else 1.0
			if sample_index==samples-1:map.set_world(frame.world.duplicate(true))
			growth.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file:="frame-%05d-%02d.png"%[index,sample_index]
			var frame_path:=temporary_dir.path_join(file);temporary_files.append(frame_path)
			if _write_frame(viewport.get_texture().get_image(),frame_path)!=OK:
				viewport.queue_free();return _finish(false,"无法写入视频帧，请检查磁盘空间。")
			concat+="file '%s'\nduration %.9f\n"%[file,duration/archive.frames.size()/samples]
			last_file=file
		progress.emit("准备历史节点 %d / %d；可取消导出。"%[index+1,archive.frames.size()])
	viewport.queue_free()
	if cancelled:return _finish(false,"导出已取消。")
	concat+="file '%s'\n"%last_file
	var list_path:=temporary_dir.path_join("frames.txt");temporary_files.append(list_path)
	var list_file:=FileAccess.open(list_path,FileAccess.WRITE)
	if list_file==null:return _finish(false,"无法写入编码清单。")
	list_file.store_string(concat);list_file.close()
	var output:=temporary_dir.path_join("result.webm");temporary_files.append(output)
	pid=OS.create_process(encoder,PackedStringArray(["-hide_banner","-loglevel","error","-nostdin","-y","-f","concat","-safe","0","-i",list_path,"-an","-vf","fps=30,tpad=stop_mode=clone:stop_duration=120","-c:v","libvpx-vp9","-deadline","realtime","-cpu-used","6","-crf","35","-b:v","0","-pix_fmt","yuv420p","-r","30","-frames:v",str(roundi(duration*30)),"-t",str(duration),output]),false)
	if pid<=0:return _finish(false,"无法启动视频编码。")
	progress.emit("正在编码1920×1080视频；可继续操作或取消。")
	while OS.is_process_running(pid):await get_tree().process_frame
	var encoder_exit:=OS.get_process_exit_code(pid)
	pid=-1
	if cancelled:return _finish(false,"导出已取消。")
	worker.start(func():
		var result:Array=[]
		var exit_code:=OS.execute(probe,PackedStringArray(["-v","error","-show_streams","-show_format","-of","json",output]),result,false,false)
		return {"code":exit_code,"data":JSON.parse_string("".join(result))})
	while worker.is_alive():await get_tree().process_frame
	var verified:Dictionary=worker.wait_to_finish()
	if not valid_probe(verified,duration):
		push_warning("Media verification: encoder=%s probe=%s"%[encoder_exit,JSON.stringify(verified)])
		return _finish(false,"视频校验失败，原目标文件已保留。")
	if cancelled:return _finish(false,"导出已取消。")
	if _replace_output(output,path)!=OK:return _finish(false,"无法替换目标文件，原文件已保留。")
	return _finish(true,"发展史视频已导出："+path)

func _write_frame(frame:Image,path:String) -> Error:
	return frame.save_png(path)

func _replace_output(source:String,target:String) -> Error:
	return DirAccess.rename_absolute(source,target)

static func valid_probe(result:Dictionary,duration:float) -> bool:
	if int(result.get("code",-1))!=0 or not result.get("data") is Dictionary:return false
	var data:Dictionary=result.data
	if absf(float(data.get("format",{}).get("duration",0))-duration)>0.2:return false
	for stream in data.get("streams",[]):
		if stream.get("codec_name","")=="vp9" and int(stream.get("width",0))==1920 and int(stream.get("height",0))==1080 and str(stream.get("r_frame_rate",""))=="30/1":return true
	return false

func _finish(ok:bool,text:String) -> Dictionary:
	busy=false;_cleanup();progress.emit(text)
	return {"ok":ok,"message":text}

func _cleanup() -> void:
	for path in temporary_files:
		if path.get_base_dir()==temporary_dir and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	temporary_files.clear()
	if not temporary_dir.is_empty():DirAccess.remove_absolute(temporary_dir)
