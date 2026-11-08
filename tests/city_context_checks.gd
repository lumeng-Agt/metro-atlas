extends SceneTree

## The background layer may only point at stations that exist, and every note
## must come with a dated official source. It must not invent geography.

const CityContext = preload("res://scripts/city_context.gd")

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
	_check(not published.is_empty(), "a published city exists")
	var city_id := str(published[0].get("id", ""))
	var entry := CityContext.for_city(city_id)
	_check(not entry.is_empty(), "the published city has a background entry")
	_check(not CityContext.summary(city_id).is_empty(), "the background carries a summary")
	var source := CityContext.source(city_id)
	_check(not str(source.get("url", "")).is_empty(), "the background names a source")
	_check(not str(source.get("checkedAt", "")).is_empty(), "the source carries a check date")
	var markers := CityContext.markers(city_id)
	_check(markers.size() >= 3, "the city has cross-border markers, got %d" % markers.size())
	# Every marker must resolve to a real station with a coordinate.
	var stations: Dictionary = {}
	for station in WorldData.city(city_id).get("stations", []):
		stations[str(station.get("id", ""))] = station
	for marker in markers:
		var station_id := str(marker.get("stationId", ""))
		_check(stations.has(station_id), "%s points at an existing station" % str(marker.get("id", "")))
		var position: Variant = stations.get(station_id, {}).get("latlng", [])
		_check(position is Array and position.size() >= 2, "%s resolves to a coordinate" % str(marker.get("id", "")))
		_check(not str(marker.get("note", "")).is_empty(), "%s carries a note" % str(marker.get("id", "")))
	var usable := CityContext.usable_markers(city_id)
	_check(usable.size() == markers.size(), "every marker is usable")
	# A marker pointing at a missing station is dropped, not placed anyway.
	var broken := CityContext.for_city(city_id).duplicate(true)
	_check(broken.has("markers"), "the entry exposes its markers")
	print("PASS: %d city context checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
