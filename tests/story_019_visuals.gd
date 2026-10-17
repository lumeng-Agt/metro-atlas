extends SceneTree
const App=preload("res://scripts/main.gd")
var app:Control
func _initialize() -> void:call_deferred("_run")
func ready_map() -> bool:
	for _frame in range(3):await process_frame
	var limit:=Time.get_ticks_msec()+20000
	while (app.map_view._base_map_thread_busy or not app.map_view._base_map_pending_request.is_empty()) and Time.get_ticks_msec()<limit:await process_frame
	for _frame in range(4):await process_frame
	return not app.map_view.base_map_features.is_empty()
func capture(name:String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/"+name+".png")
func _run() -> void:
	if DisplayServer.get_name()=="headless" or not SaveManager.using_explicit_data_dir():quit(2);return
	root.size=Vector2i(1600,980)
	app=App.new();root.add_child(app);await process_frame
	app._new_game("shanghai",false);app._begin_chapter()
	app.show_left=false;app.show_right=false;app._layout()
	for row in [["city",12],["blocks",15],["station",17]]:
		app.map_view.center_on([31.1947,121.4376],row[1])
		if not await ready_map():push_error("Map did not become ready");quit(1);return
		await capture("map-0.19-"+str(row[0])+"-1600x980")
	app.world.storyState.chapterId="sh-line1-south-1996";app.world.storyState.chapterIndex=2
	app._refresh();app.show_left=true;app._layout();app._locate_chapter()
	await ready_map()
	app._show_beat(StoryBeats.entries(app.world)[0])
	for _frame in range(4):await process_frame
	await capture("story-0.19-location-1600x980")
	app.queue_free();await process_frame;quit(0)
