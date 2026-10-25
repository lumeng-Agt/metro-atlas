extends SceneTree
const Story=preload("res://scripts/story_session.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
func _run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	for city in WorldData.cities():
		var id:=str(city.id);var world:=WorldData.new_world(id,"campaign");var config:Dictionary=CampaignSystem.city_config(id)
		var first:Dictionary=config.chapters[0];var construction_id:=CampaignSystem.first_chapter_id(id)
		_check(Story.chapter(world)==first,"new game retains its first sourced history event: "+id)
		world.storyState.chapterId=construction_id;world.storyState.chapterIndex=999
		var definition:=Story.chapter(world)
		_check(str(definition.id)==construction_id,"stable chapter identity wins over obsolete array position: "+id)
		var original_order:Array=definition.lineGroups[0].stationIds.duplicate()
		definition.lineGroups[0].stationIds[0]="test-mutation-must-not-leak"
		_check(Story.chapter(world).lineGroups[0].stationIds==original_order,"returned nested chapter data cannot mutate the catalogue: "+id)
		world.storyState.chapterId="missing-stable-id"
		_check(Story.chapter(world).is_empty(),"unknown normal chapter does not silently select another chapter: "+id)
		world.storyState.phase="history_gap";world.storyState.completedChapterIds=[]
		_check(Story.chapter(world)==first,"old content gap resumes the earliest missing historical event: "+id)
		world.storyState.completedChapterIds=[str(first.id)]
		_check(Story.chapter(world)==config.chapters[1],"gap continuation does not reconfirm an already recorded event: "+id)
		world.storyState.phase="history";world.storyState.chapterId="";world.storyState.chapterIndex=-1
		_check(Story.chapter(world)==config.chapters[1],"index-only old save falls back to the earliest incomplete definition: "+id)
		var plans:=CampaignSystem.playable_future_plans(id)
		if not plans.is_empty():
			world.storyState.phase="future";world.storyState.chapterId=str(plans[0].id)
			_check(Story.chapter(world)==plans[0],"future lookup returns only a validated required blueprint: "+id)
		for phase in ["future_gap","published_content_complete","free"]:
			world.storyState.phase=phase
			_check(Story.chapter(world).is_empty(),"completed/content-boundary state remains explicit: "+id+" "+phase)
	var probe:=WorldData.new_world("shanghai","campaign");probe.storyState.chapterId=CampaignSystem.first_chapter_id("shanghai")
	var started:=Time.get_ticks_usec()
	for _i in range(100):
		var old_city_copy:=CampaignSystem.city_config("shanghai")
		for entry in old_city_copy.chapters:
			if str(entry.id)==str(probe.storyState.chapterId):break
	var old_average:=(Time.get_ticks_usec()-started)/100000.0;started=Time.get_ticks_usec()
	for _i in range(100):Story.chapter(probe)
	var new_average:=(Time.get_ticks_usec()-started)/100000.0
	print("CHAPTER_LOOKUP_TIMING ",JSON.stringify({"oldWholeCityAverageMs":old_average,"singleChapterAverageMs":new_average,"iterations":100,"scope":"Definition lookup only, not rendered FPS or maximum-network acceptance."}))
	print("CHAPTER_LOOKUP_CHECKS ",checks," FAILURES ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
