class_name ChallengeCatalog
extends RefCounted

const Story=preload("res://scripts/story_session.gd")
const Session=preload("res://scripts/challenge_session.gd")

static func load_bank() -> Dictionary:
	var file:=FileAccess.open("res://data/challenges.json",FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file else {}

static func memory_stations(city_id:String,date:String,line_id:String="") -> Array[Dictionary]:
	var result:={}
	var chapters:Array=CampaignSystem.city_config(city_id).get("chapters",[])
	for index in range(chapters.size()):
		var chapter:Dictionary=chapters[index]
		if str(chapter.get("date","9999"))>date or bool(chapter.get("eventOnly",false)):continue
		var context:={"cityId":city_id,"mode":"campaign","stations":[],"storyPlan":{},"storyState":{"chapterId":chapter.id,"chapterIndex":index,"phase":"history"}}
		for target in Story.targets(context,true):
			if not line_id.is_empty() and str(target.get("historicalLineId",""))!=line_id:continue
			var id:=str(target.get("historicalId",target.id))
			var previous:Dictionary=result.get(id,{})
			var aliases:Array=previous.get("aliases",[]).duplicate()
			if not previous.is_empty() and str(previous.name)!=str(target.name) and not aliases.has(previous.name):aliases.append(previous.name)
			result[id]={"id":id,"historicalId":id,"referenceId":target.get("referenceId",target.id),"stationInstanceId":target.get("stationInstanceId",target.id),"name":target.name,"aliases":aliases,"latlng":target.latlng.duplicate(),"line":target.get("historicalLineName",""),"source":chapter.get("source","")}
	var stations:Array[Dictionary]=[]
	for item in result.values():stations.append(item)
	return stations

static func location_questions(city_id:String,date:String) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var bank:=load_bank()
	for question in bank.get("locations",[]):
		if question.get("cityId","")==city_id and str(question.get("validFrom","0000"))<=date and date<=str(question.get("validTo","9999")) and Session.eligible(question):result.append(question.duplicate(true))
	if result.size()<5:
		result=[]
		for station in memory_stations(city_id,date):
			var question:Dictionary=station.duplicate(true)
			question.merge({"id":"reference:%s:%s:%s"%[city_id,date,station.id],"referenceId":station.get("referenceId",station.id),"referenceBasis":"game_reference","reviewStatus":"reference_bound","period":date,"cityId":city_id,"version":bank.get("version","unknown"),"referenceDataVersion":ReferenceAlignment.version(),"contentRevision":CampaignSystem.content_revision(),"fact":"相对游戏参考坐标评分，不代表测绘精度。","hint":"观察道路、水系和地标位置。"},true)
			if Session.eligible(question):result.append(question)
	return result
