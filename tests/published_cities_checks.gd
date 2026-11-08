extends SceneTree

## The release presents one city. The other cities stay loaded so catalog
## validation, historical replay and existing saves keep working; they must not
## appear as choices for a new game.

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
	var published: Array = WorldData.cities()
	var all_cities: Array = WorldData.all_cities()
	_check(published.size() == 1, "release offers exactly one city, got %d" % published.size())
	_check(not published.is_empty() and str(published[0].get("id", "")) == "shenzhen", "the published city is Shenzhen")
	_check(all_cities.size() == 5, "all five city definitions stay loaded, got %d" % all_cities.size())
	_check(WorldData.is_published("shenzhen"), "Shenzhen is published")
	for city_id in ["shanghai", "beijing", "guangzhou", "chengdu"]:
		_check(not WorldData.is_published(city_id), "%s is not published" % city_id)
		_check(not WorldData.city(city_id).is_empty(), "%s still resolves for existing saves" % city_id)
		var legacy := WorldData.new_world(city_id, "campaign")
		_check(str(legacy.get("cityId", "")) == city_id, "%s legacy save can still be reconstructed" % city_id)
	var shenzhen := WorldData.new_world("shenzhen", "campaign")
	_check(str(shenzhen.get("cityName", "")) == "深圳", "Shenzhen new game carries its city name")
	_check(int(shenzhen.get("schemaVersion", 0)) == WorldData.SAVE_VERSION, "Shenzhen new game uses the current save version")
	print("PASS: %d published-city checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
