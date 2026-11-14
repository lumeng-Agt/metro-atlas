extends SceneTree
const App=preload("res://scripts/main.gd")
const Flow=preload("res://tests/story_test_flow.gd")
var app:Control
func _initialize():call_deferred("run")
func capture(name:String):
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/ui-0.20-"+name+".png")
func ready_map():
	var limit:=Time.get_ticks_msec()+25000
	while (app.map_view._base_map_thread_busy or not app.map_view._base_map_pending_request.is_empty()) and Time.get_ticks_msec()<limit:await process_frame
	for i in range(5):await process_frame
func run():
	if DisplayServer.get_name()=="headless" or not SaveManager.using_explicit_data_dir():quit(2);return
	root.size=Vector2i(1600,980);app=App.new();root.add_child(app);await process_frame
	await capture("menu");app._show_new_game();await capture("cities")
	# Advance through opening historical archive milestones to the first construction chapter.
	app._new_game("shenzhen",false);await Flow.reach_first_construction(app);app._begin_chapter()
	for i in range(4):await process_frame
	app.map_view.center_on([22.541,114.085],13)
	await ready_map();await capture("workbench")
	# Grayscale structure review uses the actual page and actual content.
	var material:=ShaderMaterial.new();var shader:=Shader.new();shader.code="shader_type canvas_item; uniform sampler2D screen_texture: hint_screen_texture, filter_nearest; void fragment(){ vec4 c=texture(screen_texture,SCREEN_UV); float y=dot(c.rgb,vec3(0.2126,0.7152,0.0722)); COLOR=vec4(vec3(y),c.a); }";material.shader=shader
	var gray:=ColorRect.new();gray.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);gray.material=material;gray.mouse_filter=Control.MOUSE_FILTER_IGNORE;app.add_child(gray)
	await capture("structure");gray.queue_free();await process_frame
	app._revise();await capture("revision")
	for d in app.find_children("*","ConfirmationDialog",true,false):d.canceled.emit()
	while not StorySession.plan_is_final(app.world):
		app._commit_plan_revision(int(app.world.storyPlan.get("planIndex",0))+1,int(app.world.revision))
	var beats:Array=StoryBeats.entries(app.world)
	if not beats.is_empty():
		app._show_beat(beats[0]);await capture("story");app._close_beat()
	app._tool("station")
	var targets:Array=StorySession.targets(app.world)
	if not targets.is_empty():
		var target:Dictionary=targets[0];app._click(target.latlng,"blueprint",str(target.id),"")
		await capture("station")
	app._tool("select")
	app._saves();await capture("saves")
	if is_instance_valid(app.save_overlay):app.save_overlay.queue_free()
	app.queue_free();await process_frame;quit()
