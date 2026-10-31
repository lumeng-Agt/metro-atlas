extends SceneTree
const Announcements=preload("res://scripts/announcement_player.gd")
const Geometry=preload("res://scripts/presentation_geometry.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,text:String) -> void:
	checks+=1
	if not ok:failures.append(text)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var path:=Geometry.prepare({"segments":[{"fromStationId":"a","toStationId":"b","points":[[0,0],[0,100.0/111320.0]]},{"fromStationId":"b","toStationId":"c","points":[[0,100.0/111320.0],[200.0/111132.0,100.0/111320.0]]}]},0)
	check(path.stops.size()==3,"stop distances follow canonical segments")
	check(Announcements.next_stop(path,0).stationId=="b","first cue names next real station")
	check(Announcements.next_stop(path,9).stationId=="c","turning train advances next station")
	check(Announcements.next_stop(path,18).stationId=="b" and Announcements.next_stop(path,18).cycle==1,"presentation loop is explicit")
	check(Announcements.next_stop({},0).is_empty(),"missing geometry cannot invent a stop")
	var original:=JSON.stringify(path)
	Announcements.next_stop(path,2)
	check(JSON.stringify(path)==original,"speech query cannot change geometry")
	check(UiPreferences.save_announcements_enabled(false)==OK and not UiPreferences.load_announcements_enabled(),"announcement mute persists independently")
	var player:=Announcements.new();root.add_child(player)
	check(not player.enabled,"player respects saved mute")
	player.reset();check(not player.playing and player.last_key.is_empty(),"reset stops and clears cue state")
	var file:=FileAccess.open("res://data/announcement_manifest.json",FileAccess.READ)
	check(file!=null,"offline voice manifest exists")
	if file:
		var manifest:Dictionary=JSON.parse_string(file.get_as_text())
		check(manifest.license=="MIT" and not manifest.clips.is_empty(),"voice license and inventory recorded")
		for name in ["徐家汇","新龙华","西塱","苹果园","罗湖","文殊院"]:
			check(player.clips.has(name),"historical/current cue exists: "+name)
			if player.clips.has(name):
				var clip:Dictionary=player.clips[name]
				var stream:=load("res://"+str(clip.path)) as AudioStream
				check(stream!=null and stream.get_length()>0.35,"offline voice decodes: "+name)
		for clip in manifest.clips:
			if str(clip.name).begins_with("车陂"):check(not str(clip.spokenText).contains("车波"),"Chebei is not chepo")
			if clip.name=="什刹海":check(str(clip.spokenText).contains("石岔海"),"Shichahai keeps fourth-tone cha")
	player.queue_free();await process_frame
	UiPreferences.save_announcements_enabled(true)
	if failures.is_empty():print("PASS: %d announcement checks"%checks)
	else:
		for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
