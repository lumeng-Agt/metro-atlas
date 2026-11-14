extends SceneTree

## The proposal page has to stay usable at every scale the settings offer. A
## page that renders at 100% but loses its buttons at 175% is still broken for
## the players who need the larger text.

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
	# Headless windows report a placeholder size, so the design width comes from
	# the project settings rather than from root.size.
	var window_width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600))

	for scale in [1.0, 1.25, 1.5, 1.75]:
		app.ui_scale = scale
		app.theme = preload("res://scripts/ui_theme.gd").create_theme(app.face, app.strong_face, scale)
		app.world.storyState["phase"] = "future"
		app.world.storyState["chapterId"] = "sz-line17-phase1-build"
		app.world.storyState["stage"] = "intro"
		app.world.storyState.erase("proposals")
		app._begin_chapter()
		await process_frame
		await process_frame
		var labels: Array = []
		_labels(app, labels)
		var buttons: Array = []
		_buttons(app, buttons)
		var label_text := "|".join(labels)
		var button_text := "|".join(buttons)
		var tag := "%d%%" % roundi(scale * 100.0)
		_check(str(app.world.storyState.get("stage", "")) == "proposal", "%s: the proposal stage opens" % tag)
		_check(label_text.contains("本期提案"), "%s: the proposal panel renders" % tag)
		_check(label_text.contains("当时的取舍"), "%s: the planning card renders" % tag)
		_check(button_text.contains("不做提案，直接建设"), "%s: the skip button is reachable" % tag)
		var offered := 0
		for row in app.proposal_candidates:
			if button_text.contains(str(row.get("name", ""))):
				offered += 1
		_check(offered == app.proposal_candidates.size(), "%s: every station is tappable, got %d of %d" % [tag, offered, app.proposal_candidates.size()])
		# The panel must not overflow the window horizontally at any scale.
		var widest := 0.0
		for child in app.left.get_children():
			if child is Control and (child as Control).is_visible_in_tree():
				widest = maxf(widest, (child as Control).size.x)
		_check(widest <= window_width, "%s: the panel fits the window, %.0f <= %.0f" % [tag, widest, window_width])

	print("PASS: %d scale checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
