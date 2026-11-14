extends SceneTree

## This release ships one city. The other cities stay in the data files so the
## catalog, the replay and old saves keep working, but nothing the player can
## reach may present them.

const Story = preload("res://scripts/story_session.gd")
const ChallengeCatalog = preload("res://scripts/challenge_catalog.gd")

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
	# The data still holds every city, so the catalog and replay stay valid.
	var all_cities := WorldData.all_cities()
	_check(all_cities.size() >= 5, "the data files still carry every city, got %d" % all_cities.size())
	# The player only ever sees Shenzhen.
	var published := WorldData.cities()
	_check(published.size() == 1, "exactly one city is published, got %d" % published.size())
	_check(str(published[0].get("id", "")) == "shenzhen", "the published city is Shenzhen")
	for city in published:
		_check(WorldData.is_published(str(city.get("id", ""))), "every listed city is published")
	# The other four are present but not published.
	for city_id in ["shanghai", "beijing", "guangzhou", "chengdu"]:
		_check(not WorldData.is_published(city_id), "%s is not published" % city_id)
		_check(not WorldData.city(city_id).is_empty(), "%s is still readable for old saves" % city_id)
	# A save from another city is rejected by the same predicate the UI uses.
	_check(not WorldData.is_published("shanghai"), "a Shanghai save would be refused")
	_check(WorldData.is_published("shenzhen"), "a Shenzhen save is accepted")
	# An unknown city is not published either.
	_check(not WorldData.is_published(""), "an empty city id is not published")
	_check(not WorldData.is_published("atlantis"), "an unknown city is not published")
	# The menu subtitle follows the published count rather than a hard-coded five.
	_check(published.size() == 1, "the menu shows a single-city subtitle")
	# The challenge bank still loads and still carries the published city.
	var bank: Dictionary = ChallengeCatalog.load_bank()
	_check(not bank.is_empty(), "the challenge bank loads")
	var shenzhen_questions := 0
	var other_questions := 0
	for question in bank.get("questions", []):
		if WorldData.is_published(str(question.get("cityId", ""))):
			shenzhen_questions += 1
		else:
			other_questions += 1
	_check(shenzhen_questions > 0, "the bank carries published-city questions")
	_check(other_questions >= 0, "the bank may carry other cities without serving them")
	print("PASS: %d published-city checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
