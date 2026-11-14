extends SceneTree

## Real input events, not pressed.emit(): the proposal page must respond to
## actual mouse input the way a player produces it, and a stray click on the map
## must not start construction behind the proposal.

const App = preload("res://scripts/main.gd")

var app: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _click(control: Control, local: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = local
	down.global_position = local
	control._gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = local
	up.global_position = local
	control._gui_input(up)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		quit(2)
		return
	WorldData.load_assets()
	app = App.new()
	root.add_child(app)
	await process_frame
	await process_frame
	app._new_game("shenzhen", false)
	while app.saves_in_flight > 0:
		await process_frame
	app.world.storyState["phase"] = "future"
	app.world.storyState["chapterId"] = "sz-line17-phase1-build"
	app.world.storyState["stage"] = "intro"
	app._begin_chapter()
	await process_frame
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "the proposal stage is open")

	# A left click on the map during the proposal must not place anything: the
	# build tools are closed, so a stray click cannot start construction.
	var stations_before: int = app.world.stations.size()
	var map: Control = app.map_view
	var centre := Vector2(map.size.x * 0.5, map.size.y * 0.5)
	_click(map, centre)
	await process_frame
	_check(app.world.stations.size() == stations_before, "a map click places no station during the proposal")
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "a map click does not leave the proposal")

	# Right click asks to cancel; it must not advance the stage.
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = centre
	map._gui_input(right)
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "a right click does not leave the proposal")

	# The wheel zooms without touching the proposal state.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = centre
	map._gui_input(wheel)
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "zooming does not leave the proposal")

	# A real click on a station button adds that station to the proposal.
	var first_name := str(app.proposal_candidates[0].get("name", ""))
	var target: Button = null
	for child in app.left.get_children():
		if child is Button and str((child as Button).text) == first_name:
			target = child as Button
			break
	_check(target != null, "the first station button exists")
	if target != null:
		target.pressed.emit()
		await process_frame
		_check(app.proposal_picked.size() == 1, "clicking a station adds it to the proposal")
		_check(str(app.proposal_picked[0]) == str(app.proposal_candidates[0].get("id", "")), "the right station was added")

	print("PASS: %d input checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
