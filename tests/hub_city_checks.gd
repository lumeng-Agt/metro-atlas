extends SceneTree

## The challenge hub and the save sheet are the two other places a player can
## see a city. Neither may offer a city this release does not ship.

const App = preload("res://scripts/main.gd")
const ChallengeHub = preload("res://scripts/challenge_hub.gd")
const ChallengeCatalog = preload("res://scripts/challenge_catalog.gd")

var app: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _collect_labels(node: Node, out: Array) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		out.append(str((node as Label).text))
	for child in node.get_children():
		_collect_labels(child, out)

func _collect_options(node: Node, out: Array) -> void:
	if node is OptionButton and (node as OptionButton).is_visible_in_tree():
		var picker := node as OptionButton
		var items: Array = []
		for index in range(picker.item_count):
			items.append(str(picker.get_item_text(index)))
		out.append(items)
	for child in node.get_children():
		_collect_options(child, out)

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

	# --- The challenge hub offers one city ---
	var hub := ChallengeHub.new()
	app.add_child(hub)
	await process_frame
	hub.open()
	await process_frame
	await process_frame
	var options: Array = []
	_collect_options(hub, options)
	var city_options: Array = []
	for entry in options:
		for item in entry:
			if item in ["深圳", "上海", "北京", "广州", "成都"]:
				city_options.append(item)
	_check(city_options == ["深圳"], "the challenge hub offers only Shenzhen, got %s" % JSON.stringify(city_options))
	var hub_labels: Array = []
	_collect_labels(hub, hub_labels)
	var hub_text := "|".join(hub_labels)
	for other in ["上海", "北京", "广州", "成都"]:
		_check(not hub_text.contains(other), "the challenge hub never names %s" % other)
	hub.queue_free()
	await process_frame

	# --- The bank still carries other cities, so the filter is doing the work ---
	var bank: Dictionary = ChallengeCatalog.load_bank()
	var other_questions := 0
	for question in bank.get("questions", []):
		if not WorldData.is_published(str(question.get("cityId", ""))):
			other_questions += 1
	_check(other_questions > 0, "the bank still carries other-city questions in the data, got %d" % other_questions)

	# --- The save sheet lists only published cities ---
	app._saves()
	await process_frame
	await process_frame
	var save_labels: Array = []
	_collect_labels(app, save_labels)
	var save_text := "|".join(save_labels)
	_check(save_text.contains("深圳"), "the save sheet lists the Shenzhen save")
	for other in ["上海", "北京", "广州", "成都"]:
		_check(not save_text.contains(other), "the save sheet never names %s" % other)

	print("PASS: %d hub and save checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
