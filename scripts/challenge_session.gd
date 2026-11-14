class_name ChallengeSession
extends RefCounted

const VERSION := 1
var state: Dictionary = {}

static func normalize(value:String) -> String:
	var result:=""
	for character in value:
		var point:=character.unicode_at(0)
		if point>=0xff01 and point<=0xff5e:character=String.chr(point-0xfee0)
		if character in [" ","\t","\n","\r","　"]:continue
		result+=character.to_lower()
	return result

static func eligible(question:Dictionary) -> bool:
	if question.get("referenceBasis","")=="game_reference":
		return question.get("reviewStatus","")=="reference_bound" and SaveManager._coordinate_valid(question.get("latlng")) and not str(question.get("referenceId","")).is_empty() and not str(question.get("source","")).is_empty()
	return question.get("reviewStatus","")=="verified" and question.has("positionErrorM") and float(question.positionErrorM)>=0 and float(question.positionErrorM)<=25 and SaveManager._coordinate_valid(question.get("latlng")) and not str(question.get("source","")).is_empty()

static func location_result(question:Dictionary,answer:Array,practice:bool=false) -> Dictionary:
	if not eligible(question) or not SaveManager._coordinate_valid(answer):return {"ok":false,"error":"题目缺少核验位置数据，无法评定奖牌。"}
	var distance:=Geo.local_m(answer,float(question.latlng[0])).distance_to(Geo.local_m(question.latlng,float(question.latlng[0])))
	var medal:="金牌" if distance<=100.0 else "银牌" if distance<=250.0 else "铜牌" if distance<=500.0 else "已完成"
	return {"ok":true,"distanceM":distance,"displayDistanceM":roundi(distance/10)*10,"medal":medal if not practice else "练习","practice":practice,"questionId":question.get("id",""),"catalogVersion":question.get("version","unknown"),"referenceDataVersion":question.get("referenceDataVersion","unknown"),"contentRevision":question.get("contentRevision","unknown"),"referenceBasis":question.get("referenceBasis","verified_position"),"notice":"相对游戏参考坐标评分，不代表测绘精度。"}

static func location_practice(question:Dictionary,answer:Array) -> Dictionary:
	if not SaveManager._coordinate_valid(question.get("latlng")) or not SaveManager._coordinate_valid(answer):return {"ok":false,"error":"参考位置或落点无效。"}
	var distance:=Geo.local_m(answer,float(question.latlng[0])).distance_to(Geo.local_m(question.latlng,float(question.latlng[0])))
	return {"ok":true,"distanceM":distance,"displayDistanceM":roundi(distance/10)*10,"medal":"练习","practice":true,"referencePrecision":"unverified","questionId":question.get("id","")}

static func match_name(stations:Array,answer:String) -> Array[Dictionary]:
	var matched:Array[Dictionary]=[]
	var seen:={}
	var text:=normalize(answer)
	if text.is_empty():return matched
	for station in stations:
		var names:Array=station.get("aliases",[]).duplicate()
		names.append(station.get("name",""))
		for name in names:
			var id:=str(station.get("historicalId",station.get("id","")))
			if normalize(str(name))==text and not seen.has(id):matched.append(station);seen[id]=true;break
	return matched

static func beijing_date(unix_seconds:float) -> String:
	return Time.get_date_string_from_unix_time(int(unix_seconds)+8*3600)

static func daily(schedule:Dictionary,date:String) -> Dictionary:
	return schedule.get("days",{}).get(date,{}).duplicate(true)

static func load_profile() -> Dictionary:
	var path:=SaveManager.root_path().path_join("challenges.json")
	if not FileAccess.file_exists(path):return {"schemaVersion":VERSION,"daily":{},"memory":{},"location":[]}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"error":"无法读取挑战记录。"}
	var value:Variant=JSON.parse_string(file.get_as_text())
	if not value is Dictionary or int(value.get("schemaVersion",0))!=VERSION:return {"error":"挑战记录损坏或来自不兼容版本；原文件已保留。"}
	if not value.get("daily",{}) is Dictionary or not value.get("memory",{}) is Dictionary or not value.get("location",[]) is Array:return {"error":"挑战记录结构损坏；原文件已保留。"}
	for entry in value.get("daily",{}).values()+value.get("memory",{}).values()+value.get("location",[]):
		if not entry is Dictionary:return {"error":"挑战记录条目损坏；原文件已保留。"}
	return value

static func save_profile(profile:Dictionary) -> Dictionary:
	if profile.has("error"):return {"ok":false,"error":profile.error}
	return SaveManager._write_atomic(SaveManager.root_path().path_join("challenges.json"),JSON.stringify(profile))

static func record_daily(profile:Dictionary,key:String,result:Dictionary) -> bool:
	if profile.has("error") or profile.get("daily",{}).has(key):return false
	if not profile.has("daily"):profile.daily={}
	profile.daily[key]=result.duplicate(true)
	return true

static func share_text(question:Dictionary,result:Dictionary) -> String:
	# Deliberate allow-list: answers, coordinates, names and paths never enter.
	var outcome:="练习已完成" if bool(result.get("practice",false)) else "今日挑战已完成"
	if result.has("correct") and not bool(result.get("practice",false)):outcome="今日挑战：回答正确" if bool(result.correct) else "今日挑战已完成：已查看历史解释"
	if result.has("displayDistanceM"):outcome="相对游戏参考偏差约 %d 米 · %s\n不代表测绘精度"%[int(result.displayDistanceM),str(result.get("medal","练习"))]
	# Internal ids may contain the station name. Public hashes cannot reveal it.
	var public_id:="Q"+str(question.get("id","")).sha256_text().left(8).to_upper()
	return "造一座地铁 · 每日一题\n%s · 题库 %s · 题号 %s\n%s\n玩家本地挑战，无联网排名" % [str(question.get("date","")),str(question.get("version","")),public_id,outcome]
