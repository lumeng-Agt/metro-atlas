extends SceneTree

## The proposal page has to actually render. A stage with no branch in the left
## panel leaves the player on a blank page with no way forward, which no
## state-machine test would catch.

const App = preload("res://scripts/main.gd")
const Catalog = preload("res://scripts/campaign_system.gd")
const DecisionSystem = preload("res://scripts/decision_system.gd")

var app: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _labels(node: Node, out: Array) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		out.append(str((node as Label).text))
	for child in node.get_children():
		_labels(child, out)

func _buttons(node: Node, out: Array) -> void:
	if node is Button and (node as Button).is_visible_in_tree():
		out.append(str((node as Button).text))
	for child in node.get_children():
		_buttons(child, out)

func _open(chapter_id: String) -> void:
	app.world.storyState["phase"] = "future"
	app.world.storyState["chapterId"] = chapter_id
	app.world.storyState["stage"] = "intro"
	app.world.storyState.erase("proposals")
	app._begin_chapter()

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

	# --- A chapter with a planning card ---
	_open("sz-line17-phase1-build")
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "the chapter opens the proposal stage")
	var labels: Array = []
	_labels(app, labels)
	var buttons: Array = []
	_buttons(app, buttons)
	var label_text := "|".join(labels)
	var button_text := "|".join(buttons)
	_check(label_text.contains("本期提案"), "the proposal panel is rendered")
	_check(label_text.contains("当时的取舍"), "the planning decision card is shown before the proposal")
	_check(label_text.contains("已选 0 /"), "the panel counts the picked stations")
	_check(button_text.contains("不做提案，直接建设"), "the skip button is available immediately")
	# The map hint explains the page instead of offering an ordinary selection.
	_check(str(app.hint.text).contains("提案"), "the map hint explains the proposal stage")
	_check(str(app.hint.text).contains("跳过"), "the map hint mentions skipping")
	# No build tool is usable while the player is drawing.
	_check(app.station_button.disabled, "the station tool is disabled while drawing")
	_check(app.track_button.disabled, "the track tool is disabled while drawing")
	_check(app.line_button.disabled, "the line tool is disabled while drawing")
	_check(not button_text.contains("提交提案并进入建设"), "the submit button waits for two stations")
	# Every published station is offered as a tap target.
	var offered := 0
	for row in app.proposal_candidates:
		if button_text.contains(str(row.get("name", ""))):
			offered += 1
	_check(offered == app.proposal_candidates.size(), "every published station is tappable, got %d of %d" % [offered, app.proposal_candidates.size()])
	# The card's options are rendered as choices.
	var card := DecisionSystem.planning_for_chapter("sz-line17-phase1-build")
	_check(not card.is_empty(), "the chapter carries a planning card")
	for option in card.get("options", []):
		_check(button_text.contains(str(option.get("label", ""))), "the card option is rendered: %s" % str(option.get("label", "")))

	# --- Picking two stations reveals the submit button ---
	app._toggle_proposal_station(str(app.proposal_candidates[0].get("id", "")))
	app._toggle_proposal_station(str(app.proposal_candidates[1].get("id", "")))
	await process_frame
	var picked_buttons: Array = []
	_buttons(app, picked_buttons)
	_check("|".join(picked_buttons).contains("提交提案并进入建设"), "the submit button appears after two stations")
	var picked_labels: Array = []
	_labels(app, picked_labels)
	_check("|".join(picked_labels).contains("已选 2 /"), "the panel counts two picked stations")
	app._submit_proposal()
	await process_frame
	_check(not str(app.hint.text).contains("提案："), "the hint leaves the proposal text after submitting")

	# --- A chapter without a planning card still renders the proposal ---
	_open("sz-line32-phase1-build")
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "the card-less chapter opens the proposal stage")
	var bare_labels: Array = []
	_labels(app, bare_labels)
	var bare_buttons: Array = []
	_buttons(app, bare_buttons)
	_check("|".join(bare_labels).contains("本期提案"), "the proposal panel renders without a card")
	_check("|".join(bare_buttons).contains("不做提案，直接建设"), "skipping is still offered without a card")

	print("PASS: %d proposal panel checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
