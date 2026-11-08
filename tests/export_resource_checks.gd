extends SceneTree
const Story = preload("res://scripts/story_session.gd")

## Run with the exported executable mounted as --main-pack. This verifies the
## shipped resource graph; it is not a replacement for mouse/keyboard testing.
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	if not FileAccess.file_exists("res://project.binary") or not SaveManager.using_explicit_data_dir():push_error("Exported --main-pack and isolated --data-dir required");quit(2);return
	WorldData.load_assets()
	if WorldData.SAVE_VERSION!=25 or str(ProjectSettings.get_setting("application/config/version",""))!="0.25.0":push_error("Wrong exported version");quit(1);return
	if not FileAccess.file_exists(OfficialNetworkAudit.TARGET_PATH):push_error("Missing exported official target manifest");quit(1);return
	ReferenceAlignment.load_data()
	if ReferenceAlignment._data.get("alignments",[]).size()!=81:push_error("Missing exported reference corridors");quit(1);return
	if WorldData.all_cities().size()!=5 or not CampaignSystem.validate_catalog(WorldData.all_cities()).is_empty():push_error("Missing exported city/story data");quit(1);return
	if not ResourceLoader.exists("res://fonts/NotoSansSC.ttf"):push_error("Missing exported font");quit(1);return
	var file:=FileAccess.open("res://data/basemap/manifest.json",FileAccess.READ)
	if file==null:push_error("Missing map manifest");quit(1);return
	var manifest:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	var chunks:=0
	for id in manifest.cities:
		var package:Dictionary=manifest.cities[id]
		for name in package.chunks:
			var path:="res://data/basemap/%s/%s" % [str(id),str(name)]
			if not FileAccess.file_exists(path):push_error("Missing map chunk: "+path);quit(1);return
			chunks+=1
	var app=load("res://scripts/main.gd").new();root.add_child(app);await process_frame
	app._new_game("shanghai",false);await _reach_construction(app);app._begin_chapter()
	var preview:Dictionary=app._assist_candidate()
	if not str(preview.get("issue","")).is_empty():push_error(str(preview));quit(1);return
	if not bool(app._commit_assisted_construction(preview,int(app.world.revision)).get("ok",false)):push_error("Exported assisted commit failed");quit(1);return
	app._check();app._commit_chapter()
	if str(app.world.storyState.stage)!="outcome" or not (await app._save()):push_error("Exported story/save flow failed");quit(1);return
	app._new_game("shenzhen",false);await _reach_construction(app);app._begin_chapter()
	var shenzhen_chapter:Dictionary=Story.chapter(app.world)
	var versions:Array=shenzhen_chapter.get("story",{}).get("planVersions",[])
	while not Story.plan_is_final(app.world):
		if not bool(app._commit_plan_revision(int(app.world.storyPlan.planIndex)+1,int(app.world.revision)).get("ok",false)):push_error("Exported plan revision failed");quit(1);return
	var shenzhen_preview:Dictionary=app._assist_candidate()
	if not shenzhen_preview.has("state"):push_error("Exported Shenzhen interchange preview failed: "+str(shenzhen_preview.get("issue","")));quit(1);return
	if not bool(app._commit_assisted_construction(shenzhen_preview,int(app.world.revision)).get("ok",false)):push_error("Exported Shenzhen assisted commit failed");quit(1);return
	var transfer:Dictionary=shenzhen_chapter.get("requiredTransfers",[])[0]
	var shenzhen_groups:Array=Story.groups(app.world,true)
	for group_index in range(shenzhen_groups.size()):
		var group:Dictionary=shenzhen_groups[group_index]
		var task_id:=Story.task_id(shenzhen_chapter,group,group_index)
		var task_result:Dictionary=Story.confirm_task(app.world,task_id,int(app.world.get("revision",0)))
		if not bool(task_result.get("ok",false)):push_error("Exported Shenzhen line task failed: "+str(task_result.get("error","")));quit(1);return
	var connection:Dictionary={"id":str(transfer.get("id","")),"name":str(transfer.get("name","换乘站")),"complexId":str(transfer.get("complexId","")),"stationInstanceIds":transfer.get("stationInstanceIds",[]).duplicate(),"lineIds":transfer.get("lineIds",[]).duplicate(),"status":"active","precision":str(transfer.get("precision","schematic")),"source":str(transfer.get("source","")),"effectiveDate":str(shenzhen_chapter.get("date",""))}
	var transfer_result:Dictionary=app._commit_transfer_connection(transfer,connection,int(app.world.get("revision",0)))
	if not bool(transfer_result.get("ok",false)):push_error("Exported explicit transfer operation failed: "+str(transfer_result.get("error","")));quit(1);return
	var shenzhen_evaluation:Dictionary=Story.evaluate(app.world)
	if not bool(shenzhen_evaluation.get("complete",false)):push_error("Exported Shenzhen interchange chapter check failed: "+str(shenzhen_evaluation.get("issues",[])));quit(1);return
	if not bool(Story.commit_chapter(app.world,int(shenzhen_evaluation.revision)).get("ok",false)) or app.world.transferConnections.size()!=1 or not SaveManager.validate(app.world).is_empty():push_error("Exported separate station bodies or transfer validation failed");quit(1);return
	app.world.storyState["phase"]="future_gap";app.world.storyState["chapterId"]="";app.world.storyState["chapterIndex"]=999
	app._refresh();await process_frame
	var gap_labels:Array[String]=[]
	for node in app.left_panel.find_children("*","Label",true,false):gap_labels.append(str(node.text))
	if not gap_labels.any(func(value:String):return value.contains("当前章节目标覆盖")) or not gap_labels.any(func(value:String):return value.contains("历史里程碑区间")) or not app.year.text.contains("截止日后的项目篇尚未数字化"):
		push_error("Exported history-gap page did not show the actual content coverage");quit(1);return
	print("PASS exported resources: five cities, %d chunks, 81 corridors, font, Shanghai chapter, Shenzhen independent interchange bodies, schema25 saves, and visible future-gap coverage" % chunks)
	app.queue_free();await process_frame;quit(0)

func _reach_construction(app:Control) -> void:
	while app.saves_in_flight>0:await process_frame
	while bool(Story.chapter(app.world).get("eventOnly",false)):
		app._begin_chapter()
		if not bool(Story.commit_chapter(app.world,int(app.world.revision)).get("ok",false)):push_error("Exported introductory event failed");quit(1);return
		Story.next_chapter(app.world)
	app._enter(app.world)
