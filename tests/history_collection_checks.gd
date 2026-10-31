extends SceneTree

const Playback=preload("res://scripts/history_playback.gd")
const Challenge=preload("res://scripts/challenge_session.gd")
const Export=preload("res://scripts/media_export_job.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)

func _initialize() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	var seed:={"stations":[],"routes":[],"trackLinks":[]}
	var history:=CommandHistory.new();history.attach(seed)
	var original:=history._capture_planning()
	seed.stations=[{"id":"a","name":"旧站名","latlng":[31,121]}]
	var first:=history._capture_planning()
	var diff1:=history._build_diff(original,first)
	seed.stations[0].name="新站名"
	seed.stations.append({"id":"b","name":"延伸站","latlng":[31.01,121]})
	seed.routes=[{"id":"line","stops":["a","b"]}]
	var final:=history._capture_planning()
	var diff2:=history._build_diff(first,final)
	var source:={"cityId":"shanghai","cityName":"上海","stations":[{"id":"unconfirmed"}],"milestoneBaseline":final,"storyState":{"milestones":[{"date":"1993-05-28","title":"首开","planningDiff":diff1},{"date":"1995-04-10","title":"延伸改名","planningDiff":diff2}]}}
	var before:=JSON.stringify(source)
	var replay:=Playback.build(source)
	check(replay.frames.size()==2,"two confirmed nodes restored")
	check(replay.frames[0].world.stations.size()==1 and replay.frames[0].world.stations[0].name=="旧站名","earlier names and range survive")
	check(replay.frames[1].world.routes.size()==1,"later service restored")
	check(JSON.stringify(source)==before,"reconstruction never mutates live save")
	replay.frames[0].world.stations[0].name="display only"
	check(source.milestoneBaseline.stations[0].name=="新站名","frame mutations isolated")
	check(Playback.build({}).frames.is_empty(),"legacy missing baseline never invents history")
	var corrupt:=source.duplicate(true);corrupt.milestoneBaseline.stations[0].name="not confirmed"
	check(Playback.build(corrupt).frames.is_empty(),"inconsistent checkpoint rejected")
	check(Playback.frame_index(60,60,2)==1 and Playback.frame_index(-1,60,2)==0,"fixed time boundary clamps")
	check(Challenge.normalize(" Ａ 徐　家桥 ")=="a徐家桥","width and whitespace normalization")
	var stations:=[{"id":"one","historicalId":"complex","name":"新站","aliases":["老站"]},{"id":"two","historicalId":"complex","name":"新站"},{"id":"elsewhere","name":"新站"}]
	check(Challenge.match_name(stations,"老站").size()==1,"documented former name accepted")
	check(Challenge.match_name(stations,"新站").size()==2,"same complex deduplicated, unrelated homonym retained")
	check(Challenge.match_name(stations,"新").is_empty(),"no fuzzy automatic credit")
	var q:={"id":"test","latlng":[0,0],"reviewStatus":"verified","positionErrorM":20,"source":"https://example.test/source"}
	check(Challenge.eligible(q),"explicit reviewed accuracy qualifies")
	var inaccurate:=q.duplicate(true);inaccurate.positionErrorM=100
	check(not Challenge.eligible(inaccurate),"construction tolerance cannot qualify quiz")
	check(Challenge.location_practice(inaccurate,[0,0]).medal=="练习","approximate reference supports practice without awarding medal")
	for spec in [[99,"金牌"],[101,"银牌"],[249,"银牌"],[251,"铜牌"],[499,"铜牌"],[501,"已完成"]]:
		var answer:Array=[0,float(spec[0])/111320.0]
		check(Challenge.location_result(q,answer).medal==spec[1],"distance band %s"%spec[0])
	check(Challenge.location_result(q,[0,0],true).medal=="练习","hint never earns medal")
	check(not Challenge.location_result(q,[NAN,0]).ok,"invalid answer blocked")
	check(Challenge.beijing_date(0)=="1970-01-01" and Challenge.beijing_date(16*3600)=="1970-01-02","Beijing midnight independent of OS zone")
	check(Challenge.daily({"days":{}},"2030-01-01").is_empty(),"expired schedule does not silently loop")
	var profile:={"schemaVersion":1,"daily":{},"memory":{},"location":[]}
	check(Challenge.record_daily(profile,"version:date",{"correct":true}),"first daily result recorded")
	check(not Challenge.record_daily(profile,"version:date",{"correct":false}) and profile.daily["version:date"].correct,"retry cannot overwrite first result")
	var share:=Challenge.share_text({"date":"2026-10-30","version":"one","id":"q1","answer":"secret","path":"private"},{})
	check(not share.contains("secret") and not share.contains("private"),"share allowlist does not leak answers or paths")
	check(not Challenge.share_text({"id":"station-secret-answer"},{}).contains("secret"),"semantic question ids are not leaked on share cards")
	var saved:=Challenge.save_profile(profile)
	check(saved.get("ok",false) and Challenge.load_profile().daily==profile.daily,"separate profile survives reload")
	var profile_path:=SaveManager.root_path().path_join("challenges.json")
	SaveManager._write_atomic(profile_path,JSON.stringify({"schemaVersion":1,"daily":[],"memory":{},"location":[]}))
	var damaged_hash:=FileAccess.get_sha256(profile_path)
	var damaged:=Challenge.load_profile()
	check(damaged.has("error"),"malformed profile structure rejected")
	check(not Challenge.save_profile(damaged).get("ok",true) and FileAccess.get_sha256(profile_path)==damaged_hash,"rejected profile never overwrites original")
	Challenge.save_profile(profile)
	var png_path:=SaveManager.root_path().path_join("atomic-image.png")
	var png:=Image.create(2,2,false,Image.FORMAT_RGBA8);png.fill(Color.GREEN)
	check(Export.save_png_atomic(png,png_path)==OK,"PNG first write succeeds")
	png.fill(Color.RED)
	check(Export.save_png_atomic(png,png_path)==OK and Image.load_from_file(png_path).get_pixel(0,0)==Color.RED,"verified PNG replaces existing file")
	var png_hash:=FileAccess.get_sha256(png_path)
	check(Export.save_png_atomic(Image.new(),png_path)!=OK and FileAccess.get_sha256(png_path)==png_hash,"invalid PNG cannot truncate existing target")
	var blocked:=SaveManager.root_path().path_join("blocked-target.png")
	DirAccess.make_dir_absolute(blocked)
	var sentinel:=FileAccess.open(blocked.path_join("retain.txt"),FileAccess.WRITE);sentinel.store_string("retain");sentinel.close()
	check(Export.save_png_atomic(png,blocked)!=OK and FileAccess.get_file_as_string(blocked.path_join("retain.txt"))=="retain" and not Array(DirAccess.get_files_at(SaveManager.root_path())).any(func(name):return str(name).begins_with(".metro-png-")),"PNG replacement failure preserves existing data and cleans temporary file")
	check(Export.valid_probe({"code":0,"data":{"format":{"duration":"60.0"},"streams":[{"codec_name":"vp9","width":1920,"height":1080,"r_frame_rate":"30/1"}]}},60),"valid video accepted")
	check(not Export.valid_probe({"code":0,"data":{"format":{"duration":"10"},"streams":[]}},60),"truncated video cannot replace output")
	var bank:=preload("res://scripts/challenge_catalog.gd").load_bank()
	check(bank.days.size()==180,"180 explicit daily dates supplied")
	var ids:={}
	for question in bank.questions:
		check(not ids.has(question.id) and (question.reviewStatus=="verified" or Challenge.eligible(question)) and str(question.source).begins_with("https://"),"unique reviewed or explicitly game-reference question with source")
		ids[question.id]=true
		if question.type!="location":check(int(question.answer)>=0 and int(question.answer)<question.options.size(),"answer belongs to explicit options")
		else:check(question.referenceBasis=="game_reference" and SaveManager._coordinate_valid(question.latlng),"location answer explicitly binds game reference")
	for day in bank.days:check(ids.has(bank.days[day].questionId),"scheduled day refers to existing question")
	if failures.is_empty():print("PASS: %d history collection checks"%checks)
	else:
		for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
