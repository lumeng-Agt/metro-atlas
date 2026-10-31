extends SceneTree
## Explicit content-authoring command; never run by gameplay or regression tests.
func _initialize() -> void:
	WorldData.load_assets()
	var catalog=preload("res://scripts/challenge_catalog.gd")
	var bank:Dictionary=catalog.load_bank()
	bank.version="2026.10.30.2"
	bank.locations=[]
	bank.questions=bank.questions.filter(func(q:Dictionary):return str(q.get("type",""))!="location")
	for city in WorldData.cities():
		var pool:Array=catalog.memory_stations(str(city.id),"2026-10-01")
		for entry in pool.slice(0,5):
			var question:Dictionary=entry.duplicate(true)
			question.merge({"id":"reference:%s:2026-10-01:%s"%[city.id,entry.id],"type":"location","cityId":city.id,"period":"2026-10-01","referenceBasis":"game_reference","reviewStatus":"reference_bound","validFrom":"2026-10-01","validTo":"2026-10-01","fact":"按游戏参考坐标评分，不代表测绘精度。","hint":"观察道路、水系和地标。","prompt":"%s · %s：请在地图上找到%s。"%[city.name,entry.line,entry.name]},true)
			question.merge({"version":bank.version,"referenceDataVersion":ReferenceAlignment.version(),"contentRevision":CampaignSystem.content_revision()},true)
			bank.locations.append(question)
			bank.questions.append(question.duplicate(true))
	bank.days={}
	var start:=int(Time.get_unix_time_from_datetime_string("2026-10-30T00:00:00"))
	var buckets:={"location":[],"former_name":[],"order":[]}
	for question in bank.questions:buckets[str(question.type)].append(str(question.id))
	var kinds:=["location","former_name","order"]
	for index in range(180):
		var kind:String=kinds[index%3];var bucket:Array=buckets[kind]
		var round_index:=index/3
		bank.days[Time.get_date_string_from_unix_time(start+index*86400)]={"questionId":bucket[int(round_index)%bucket.size()],"reviewCycle":int(round_index/bucket.size())+1}
	bank.reviewNote="历史知识题逐题保留出处；位置题相对已发布游戏参考坐标评分，不代表测绘精度，不声称25米精度。"
	bank.scheduleNote="180个明确日期，站位／曾用名／历史顺序三种类型轮换；32道基础题循环复习。"
	var file:=FileAccess.open("res://data/challenges.json",FileAccess.WRITE)
	if file==null:push_error("Cannot write challenge bank");quit(1);return
	file.store_string(JSON.stringify(bank,"  ")+"\n");file.close()
	print("Authored %d location questions, %d questions and %d dates"%[bank.locations.size(),bank.questions.size(),bank.days.size()]);quit()
