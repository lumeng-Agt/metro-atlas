class_name AnnouncementPlayer
extends AudioStreamPlayer

signal caption_changed(text:String)
var clips:Dictionary={}
var streams:Dictionary={}
var last_key:=""
var last_route:=""
var last_seconds:=-100.0
var last_request_msec:=-10000
var context_key:=""
var enabled:=true

func _ready() -> void:
	enabled=UiPreferences.load_announcements_enabled()
	var file:=FileAccess.open("res://data/announcement_manifest.json",FileAccess.READ)
	if file:
		var data:Variant=JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			for clip in data.get("clips",[]):
				if clip.get("pronunciationReview","") in ["dictionary_checked","verified"]:clips[str(clip.name)]=clip

func reset() -> void:
	stop();last_key="";last_route="";last_seconds=-100;caption_changed.emit("")

static func next_stop(display_path:Dictionary,seconds:float) -> Dictionary:
	var total:=float(display_path.get("lengthM",0))
	if total<=0:return {}
	var cycle_duration:=maxf(18,total/120)
	var position:=fposmod(seconds/cycle_duration,1)*total
	for stop in display_path.get("stops",[]):
		if float(stop.get("distanceM",0))>position+0.01:
			return {"stationId":stop.stationId,"cycle":int(floor(seconds/cycle_duration))}
	return {}

func update_from_map(map:MapView,seconds:float,display_active:bool) -> void:
	if not enabled or not display_active:
		stop();caption_changed.emit("");return
	var next_context:="%s:%s:%s"%[str(map.world.get("gameId","playback")),str(map.world.get("storyState",{}).get("chapterId","")),str(map.world.get("storyState",{}).get("stage",""))]
	if next_context!=context_key:reset();context_key=next_context
	if seconds<last_seconds:reset()
	last_seconds=seconds
	var route_id:=map.active_route_id
	if route_id.is_empty():
		for id in map.route_path_cache:
			if not map.route_path_cache[id].get("displayPaths",[]).is_empty():route_id=str(id);break
	if route_id!=last_route:stop();last_key="";last_route=route_id
	var paths:Array=map.route_path_cache.get(route_id,{}).get("displayPaths",[])
	if paths.is_empty():stop();return
	var next:=next_stop(paths[0],seconds)
	if next.is_empty():return
	var station:=WorldData.find_station(map.world,str(next.stationId))
	if station.is_empty():return
	var key:="%s:%s:%s:%d"%[str(map.world.get("gameId","playback")),route_id,str(next.stationId),int(next.cycle)]
	if key==last_key:return
	if playing or Time.get_ticks_msec()-last_request_msec<3000:return
	last_key=key;last_request_msec=Time.get_ticks_msec()
	var name:=str(station.name)
	caption_changed.emit("下一站，%s · 示意合成报站"%name)
	if not clips.has(name):return
	var path:="res://"+str(clips[name].path)
	if not streams.has(path):
		if not ResourceLoader.exists(path):return
		if streams.size()>=8:streams.erase(streams.keys()[0])
		streams[path]=load(path)
	stream=streams[path];volume_db=linear_to_db(UiPreferences.load_feedback_volume());play()
