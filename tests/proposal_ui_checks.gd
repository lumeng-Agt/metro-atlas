extends SceneTree

## Black-box checks driven through the real Controls a player touches: the main
## menu, the new-game screen, the proposal panel, the skip and submit buttons,
## and the comparison dialog. Nothing here calls Story directly for a step the
## player would take through the UI.

const App = preload("res://scripts/main.gd")
const Story = preload("res://scripts/story_session.gd")
const Catalog = preload("res://scripts/campaign_system.gd")
const ProposalSession = preload("res://scripts/proposal_session.gd")

var app: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button and (node as Button).is_visible_in_tree():
		out.append(str((node as Button).text))
	for child in node.get_children():
		_collect_buttons(child, out)

func _collect_labels(node: Node, out: Array) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		out.append(str((node as Label).text))
	for child in node.get_children():
		_collect_labels(child, out)

func _find_button(node: Node, fragment: String) -> Button:
	if node is Button and str((node as Button).text).contains(fragment) and (node as Button).is_visible_in_tree():
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, fragment)
		if found != null:
			return found
	return null

func _find_city_picker(node: Node) -> OptionButton:
	if node is OptionButton and (node as OptionButton).is_visible_in_tree():
		var picker := node as OptionButton
		for index in range(picker.item_count):
			if str(picker.get_item_text(index)) == "深圳":
				return picker
	for child in node.get_children():
		var found := _find_city_picker(child)
		if found != null:
			return found
	return null

func _visible_dialog() -> AcceptDialog:
	for child in app.get_children():
		if child is AcceptDialog and (child as AcceptDialog).visible:
			return child as AcceptDialog
	return null

func _open_planning_chapter() -> String:
	var plans: Array = Catalog.playable_future_plans("shenzhen")
	var plan: Dictionary = plans[0]
	app.world.storyState["phase"] = "future"
	app.world.storyState["chapterId"] = str(plan.get("id", ""))
	app.world.storyState["stage"] = "intro"
	app.world.storyState.erase("proposals")
	app._begin_chapter()
	return str(app.world.storyState.get("chapterId", ""))

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		quit(2)
		return
	WorldData.load_assets()
	app = App.new()
	root.add_child(app)
	await process_frame
	await process_frame

	# --- Main menu: one city, no menu entry for the others ---
	var menu_buttons: Array = []
	_collect_buttons(app, menu_buttons)
	var menu_labels: Array = []
	_collect_labels(app, menu_labels)
	var button_text := "|".join(menu_buttons)
	var label_text := "|".join(menu_labels)
	for other in ["上海", "北京", "广州", "成都"]:
		_check(not button_text.contains(other), "the menu offers no %s entry" % other)
		_check(not label_text.contains(other), "the menu names no %s" % other)
	_check(not label_text.contains("五城"), "the subtitle does not claim five cities")
	_check(label_text.contains("深圳"), "the subtitle names Shenzhen")
	var continue_button := _find_button(app, "继续城市故事")
	_check(continue_button != null, "the continue button exists")
	if continue_button != null:
		_check(continue_button.disabled, "continue is disabled with no save")

	# --- New game: the city picker holds exactly Shenzhen ---
	var new_game := _find_button(app, "选择城市 · 开始新故事")
	_check(new_game != null, "the new game entry exists")
	if new_game != null:
		new_game.pressed.emit()
		await process_frame
		await process_frame
		var picker := _find_city_picker(app)
		_check(picker != null, "the city picker exists")
		if picker != null:
			_check(picker.item_count == 1, "the picker offers exactly one city, got %d" % picker.item_count)
			_check(str(picker.get_item_text(0)) == "深圳", "the only city is Shenzhen")
		var new_labels: Array = []
		_collect_labels(app, new_labels)
		_check(not "|".join(new_labels).contains("选择一座城市"), "the screen does not ask to choose a city")

	# --- A planning chapter opens with a proposal ---
	app._new_game("shenzhen", false)
	while app.saves_in_flight > 0:
		await process_frame
	var chapter_id := _open_planning_chapter()
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "a planning chapter opens the proposal stage")
	_check(app.proposal_candidates.size() >= 2, "the proposal offers published stations to pick")
	# Construction is closed while drawing.
	_check(app.station_button.disabled, "station building is blocked during the proposal")
	_check(app.track_button.disabled, "track building is blocked during the proposal")
	# The chapter cannot be confirmed while drawing.
	var commit := Story.commit_chapter(app.world, int(app.world.get("revision", 0)))
	_check(not bool(commit.get("ok", false)), "a chapter cannot be confirmed during the proposal")

	# --- Tapping stations, the way a player picks ---
	var candidates: Array = app.proposal_candidates
	app._toggle_proposal_station(str(candidates[0].get("id", "")))
	app._toggle_proposal_station(str(candidates[1].get("id", "")))
	_check(app.proposal_picked.size() == 2, "tapping two stations records two")
	app._toggle_proposal_station(str(candidates[0].get("id", "")))
	_check(app.proposal_picked.size() == 1, "tapping a picked station removes it")
	app._toggle_proposal_station(str(candidates[0].get("id", "")))
	_check(app.proposal_picked.size() == 2, "tapping it again adds it back")

	# --- Submitting opens construction and shows the comparison ---
	var stations_before: int = app.world.stations.size()
	var routes_before: int = app.world.routes.size()
	app._submit_proposal()
	await process_frame
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "build", "submitting opens construction")
	_check(app.world.stations.size() == stations_before, "a proposal adds no stations")
	_check(app.world.routes.size() == routes_before, "a proposal adds no routes")
	_check(not app.station_button.disabled, "construction is available after submitting")
	var record := Story.proposal_for(app.world, chapter_id)
	_check(not record.is_empty(), "the proposal is recorded")
	_check((record.get("stationIds", []) as Array).size() == 2, "the record keeps the picked stations")
	var dialog := _visible_dialog()
	_check(dialog != null, "the comparison dialog is shown")
	if dialog != null:
		var text := str(dialog.dialog_text)
		_check(str(dialog.title) == "公开方案对照", "the dialog is titled as a comparison")
		_check(text.contains("分"), "the dialog reports a score")
		_check(text.contains("不代表测绘精度"), "the dialog disclaims surveying accuracy")
		_check(text.contains("不评估客流"), "the dialog disclaims ridership")
		_check(text.contains("公开方案站序"), "the dialog shows the published order")
		_check(text.contains("不改变本章建设范围"), "the dialog says the proposal does not change the build")
		dialog.hide()

	# --- Skipping is allowed and records nothing ---
	_open_planning_chapter()
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "re-entering opens the proposal again")
	app._skip_proposal()
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "build", "skipping opens construction")
	_check(Story.proposal_for(app.world, chapter_id).is_empty(), "skipping records no proposal")
	_check(not app.station_button.disabled, "construction is available after skipping")

	# --- A one-station proposal is refused rather than accepted ---
	_open_planning_chapter()
	await process_frame
	app.proposal_picked = [str(app.proposal_candidates[0].get("id", ""))]
	app._submit_proposal()
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "a one-station proposal does not open construction")
	var refusal := _visible_dialog()
	_check(refusal != null, "a refused proposal explains itself")
	if refusal != null:
		_check(str(refusal.dialog_text).contains("至少选择 2 座车站"), "the refusal says how many stations are needed")
		refusal.hide()

	print("PASS: %d proposal UI checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
