class_name CityContext
extends RefCounted

## Background for a city: why the network looks the way it does. Markers point
## at existing stations so nothing new is placed on the map, and every note is
## quoted from a dated official source.

const PATH := "res://data/city_context.json"

static var _data: Dictionary = {}

static func load_data() -> void:
	if not _data.is_empty():
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if value is Dictionary:
		_data = value

static func for_city(city_id: String) -> Dictionary:
	load_data()
	var entry: Variant = _data.get("cities", {}).get(city_id, {})
	return entry if entry is Dictionary else {}

static func markers(city_id: String) -> Array:
	return for_city(city_id).get("markers", [])

static func summary(city_id: String) -> String:
	return str(for_city(city_id).get("summary", ""))

static func source(city_id: String) -> Dictionary:
	return for_city(city_id).get("source", {})

## A marker is only usable when it points at a station that exists and carries
## a coordinate, so the layer cannot invent geography.
static func usable_markers(city_id: String) -> Array:
	var stations: Dictionary = {}
	for station in WorldData.city(city_id).get("stations", []):
		stations[str(station.get("id", ""))] = station
	var out: Array = []
	for marker in markers(city_id):
		var station: Dictionary = stations.get(str(marker.get("stationId", "")), {})
		var position: Variant = station.get("latlng", [])
		if position is Array and position.size() >= 2:
			var row: Dictionary = marker.duplicate(true)
			row["latlng"] = position
			row["stationName"] = str(station.get("name", ""))
			out.append(row)
	return out
