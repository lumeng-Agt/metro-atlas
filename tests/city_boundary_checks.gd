extends SceneTree

## The city boundary is enforced at every door a player can reach: the save
## list, the continue button and the JSON import. Saves from other cities stay
## on disk and are never modified.

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

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		quit(2)
		return
	WorldData.load_assets()
	app = App.new()
	root.add_child(app)
	await process_frame
	await process_frame

	# A Shenzhen save makes continue available.
	app._new_game("shenzhen", false)
	while app.saves_in_flight > 0:
		await process_frame
	_check(app._last_game_is_published(), "a Shenzhen save is recognised as continueable")
	var shenzhen_rows := 0
	for row in SaveManager.list_saves():
		if WorldData.is_published(str(row.get("cityId", ""))):
			shenzhen_rows += 1
	_check(shenzhen_rows > 0, "the save list carries the Shenzhen save with a cityId")

	# A save from another city is written directly, as an older build would
	# have left it, and must stay untouched and unlisted.
	var other_id := "shanghai_1700000000_abcdef123456"
	var other_dir := SaveManager.root_path().path_join("games").path_join(other_id)
	DirAccess.make_dir_recursive_absolute(other_dir)
	var other_world: Dictionary = app.world.duplicate(true)
	other_world["cityId"] = "shanghai"
	other_world["cityName"] = "上海"
	other_world["gameId"] = other_id
	var other_path := other_dir.path_join("current.json")
	var other_file := FileAccess.open(other_path, FileAccess.WRITE)
	other_file.store_string(JSON.stringify(other_world))
	other_file.close()
	_check(FileAccess.file_exists(other_path), "the other city's save was written")
	var other_before := FileAccess.get_modified_time(other_path)

	var listed_other := false
	for row in SaveManager.list_saves():
		if str(row.get("cityId", "")) == "shanghai":
			listed_other = true
	_check(listed_other, "the save list still finds the other city's save on disk")
	# The UI filter is what keeps it out of sight.
	var visible_other := false
	for row in SaveManager.list_saves():
		if WorldData.is_published(str(row.get("cityId", ""))) and str(row.get("cityId", "")) == "shanghai":
			visible_other = true
	_check(not visible_other, "the other city's save is not offered to the player")

	# Loading it is refused and the file is left alone.
	app._load_result(SaveManager.load_file(other_path))
	# _load_result saves the current world before switching, so the switch (or
	# the refusal) lands a few frames later rather than immediately.
	for _frame in range(30):
		await process_frame
	_check(str(app.world.get("cityId", "")) == "shenzhen", "loading another city's save does not replace the current world")
	_check(FileAccess.get_modified_time(other_path) == other_before, "refusing to load does not modify the other city's save")
	_check(FileAccess.file_exists(other_path), "refusing to load does not delete the other city's save")

	# The continue button follows the last game, not the save list.
	_check(app._last_game_is_published(), "continue still points at the Shenzhen save")

	print("PASS: %d city boundary checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
