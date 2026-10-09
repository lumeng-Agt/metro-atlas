class_name SaveManager
extends RefCounted

static func root_path() -> String:
	if OS.get_name() == "Windows":
		var roaming := OS.get_environment("APPDATA")
		if not roaming.is_empty(): return roaming.path_join("MetroAtlas")
	return "user://MetroAtlas"

static func save_dir() -> String:
	return root_path().path_join("saves")

static func last_game_path() -> String:
	return root_path().path_join("last_game.json")

static func save_path(city_id: String, mode: String) -> String:
	return save_dir().path_join("%s_%s.json" % [city_id, mode])

static func save_world(world: Dictionary) -> Dictionary:
	var path := save_path(str(world.get("cityId", "unknown")), str(world.get("mode", "blank")))
	var dir_path := ProjectSettings.globalize_path(save_dir())
	var dir_error := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_error != OK and not DirAccess.dir_exists_absolute(dir_path): return {"ok": false, "error": "无法创建本地存档目录"}
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "存档写入失败：%s" % error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(world, "\t"))
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK: return {"ok": false, "error": "存档未能完整写入"}
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
		var backup_err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path))
		if backup_err != OK: return {"ok": false, "error": "无法创建恢复备份"}
	var replace_err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if replace_err != OK:
		if FileAccess.file_exists(backup_path): DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(path))
		return {"ok": false, "error": "无法替换旧存档"}
	return {"ok": true, "path": path}

static func load_world(city_id: String, mode: String) -> Dictionary:
	var path := save_path(city_id, mode)
	if not FileAccess.file_exists(path): return {"ok": false, "error": "没有找到这个开局的存档"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "无法读取本地存档"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return {"ok": false, "error": "存档内容无效，原文件已保留"}
	var version := int(parsed.get("schemaVersion", 0))
	if version > WorldData.SAVE_VERSION: return {"ok": false, "error": "存档来自更新版本，无法安全载入"}
	if version < WorldData.SAVE_VERSION: parsed = migrate(parsed)
	return {"ok": true, "world": parsed}

static func migrate(data: Dictionary) -> Dictionary:
	if data.has("stationPlans") or data.has("trackNetwork") and not data.get("simulation", {}).has("minute"):
		return _migrate_web_world(data)
	var migrated := data.duplicate(true)
	migrated["schemaVersion"] = WorldData.SAVE_VERSION
	migrated["history"] = migrated.get("history", {"undo": [], "redo": []})
	migrated["fleetMode"] = migrated.get("fleetMode", "automatic")
	migrated["depots"] = migrated.get("depots", [])
	migrated["trackLinks"] = migrated.get("trackLinks", [])
	var simulation: Dictionary = migrated.get("simulation", {})
	simulation["minute"] = int(simulation.get("minute", 420))
	simulation["paused"] = true
	simulation["speed"] = int(simulation.get("speed", 1))
	migrated["simulation"] = simulation
	return migrated

static func _migrate_web_world(source: Dictionary) -> Dictionary:
	var city_id := str(source.get("cityId", "shanghai"))
	var mode := str(source.get("mode", "blank"))
	var city := WorldData.city(city_id)
	var raw_routes: Array = source.get("routes", [])
	var raw_stations: Array = source.get("stations", [])
	var plans: Dictionary = source.get("stationPlans", {})
	var station_route_ids: Dictionary = {}
	var routes: Array[Dictionary] = []
	var links: Array[Dictionary] = []
	var pair_to_link: Dictionary = {}
	for raw_route in raw_routes:
		if not raw_route is Dictionary: continue
		var route: Dictionary = raw_route.duplicate(true)
		var vehicle_id := str(route.get("vehicleId", route.get("vehicleProfileId", "B-6")))
		if WorldData.vehicle(vehicle_id).is_empty(): vehicle_id = "B-6"
		route["vehicleId"] = vehicle_id
		route["headway"] = int(route.get("headway", route.get("headwayMinutes", 3)))
		if not route.has("open"):
			route["open"] = str(route.get("status", "")) == "operating"
		route["schematic"] = true
		var directions: Array = route.get("directions", [])
		if directions.is_empty() and route.get("stationIds", []) is Array:
			directions = [{"id": "legacy", "stationIds": route.get("stationIds", [])}]
		var station_order: Array[String] = []
		for direction in directions:
			if not direction is Dictionary: continue
			for raw_id in direction.get("stationIds", []):
				var station_id := str(raw_id)
				if station_id.is_empty(): continue
				if not station_order.has(station_id): station_order.append(station_id)
				if not station_route_ids.has(station_id): station_route_ids[station_id] = []
				if not station_route_ids[station_id].has(str(route.get("id", ""))): station_route_ids[station_id].append(str(route.get("id", "")))
		route["stationOrder"] = station_order
		route["directions"] = directions
		routes.append(route)
	for route in routes:
		var route_id := str(route.get("id", ""))
		for direction in route.get("directions", []):
			if not direction is Dictionary: continue
			var ids: Array = direction.get("stationIds", [])
			for index in range(ids.size() - 1):
				var a_id := str(ids[index]); var b_id := str(ids[index + 1])
				if a_id == b_id or _find_station(raw_stations, a_id).is_empty() or _find_station(raw_stations, b_id).is_empty(): continue
				var pair_key := "%s|%s" % [a_id, b_id] if a_id < b_id else "%s|%s" % [b_id, a_id]
				if pair_to_link.has(pair_key):
					var shared_link: Dictionary = links[int(pair_to_link[pair_key])]
					if not shared_link.routeIds.has(route_id): shared_link.routeIds.append(route_id)
				else:
					var link := {"id": "web_%s_%d" % [route_id, links.size()], "a": {"stationId": a_id, "side": "end"}, "b": {"stationId": b_id, "side": "start"}, "routeIds": [route_id], "schematic": true, "migrationNote": "由网页版本站序转换；站间线位为示意"}
					pair_to_link[pair_key] = links.size()
					links.append(link)
	var stations: Array[Dictionary] = []
	for raw_station in raw_stations:
		if not raw_station is Dictionary: continue
		var station: Dictionary = raw_station.duplicate(true)
		var station_id := str(station.get("id", ""))
		var plan: Dictionary = plans.get(station_id, {})
		var halls: Array = plan.get("halls", [])
		var hall: Dictionary = halls[0] if not halls.is_empty() and halls[0] is Dictionary else plan.get("hall", {})
		var station_routes: Array = station_route_ids.get(station_id, station.get("routeIds", []))
		var vehicle_id := str(hall.get("profileId", plan.get("profileId", "")))
		if vehicle_id.is_empty() and not station_routes.is_empty():
			var route := _find_route(routes, str(station_routes[0]))
			vehicle_id = str(route.get("vehicleId", "B-6"))
		if WorldData.vehicle(vehicle_id).is_empty(): vehicle_id = "B-6"
		var profile := WorldData.vehicle(vehicle_id)
		station["heading"] = float(station.get("heading", station.get("orientation", hall.get("headingDeg", 90.0))))
		station["lengthM"] = float(hall.get("lengthM", station.get("lengthM", profile.get("trainLengthM", 118.788))))
		station["widthM"] = float(hall.get("widthM", station.get("widthM", 20.0)))
		station["vehicleId"] = vehicle_id
		station["routeIds"] = station_routes.duplicate()
		station["schematic"] = true
		stations.append(station)
	var old_sim: Dictionary = source.get("simulation", {})
	var stats: Dictionary = source.get("simStats", {})
	var minute := int(old_sim.get("minute", source.get("timeMinutes", 420)))
	var simulation := {"minute": minute, "speed": 1, "paused": true, "seed": int(source.get("seed", source.get("randomSeed", 45281))), "completed": int(stats.get("served", 0)), "attempted": int(stats.get("requested", stats.get("served", 0))), "served": int(stats.get("served", 0)), "tripMinutesTotal": float(stats.get("servedMinutes", 0.0)), "peakCrowding": float(stats.get("crowded", 0.0))}
	var tutorial: Dictionary = source.get("tutorial", {})
	var migrated := {"schemaVersion": WorldData.SAVE_VERSION, "cityId": city_id, "cityName": str(source.get("cityName", city.get("name", city_id))), "mode": mode, "dataVersion": str(source.get("mobilityVersion", source.get("dataVersion", "web-v7"))), "stations": stations, "routes": routes, "trackLinks": links, "depots": source.get("depots", []), "simulation": simulation, "fleetMode": "automatic", "tutorialStep": mini(4, int(tutorial.get("step", 0))), "tutorialDone": bool(tutorial.get("completed", tutorial.get("skipped", false))), "randomSeed": int(source.get("seed", source.get("randomSeed", 45281))), "revision": int(source.get("networkRevision", 1)), "view": source.get("view", {"center": city.get("center", [31.2304, 121.4737]), "zoom": city.get("zoom", 12)}), "history": {"undo": [], "redo": []}, "source": {"attribution": "© OpenStreetMap contributors", "license": "ODbL 1.0", "snapshot": str(city.get("sources", {}).get("snapshot", "2026-10-05"))}, "migrationNotice": "已导入网页存档。车站站体按列车长度转换；原区间线位作为站序示意，复核后可逐段重建。网页原始 JSON 未修改，可留作恢复备份。"}
	return migrated

static func _find_station(stations: Array, station_id: String) -> Dictionary:
	for station in stations:
		if station is Dictionary and str(station.get("id", "")) == station_id: return station
	return {}

static func _find_route(routes: Array[Dictionary], route_id: String) -> Dictionary:
	for route in routes:
		if str(route.get("id", "")) == route_id: return route
	return {}

static func save_exists(city_id: String, mode: String) -> bool:
	return FileAccess.file_exists(save_path(city_id, mode))

static func saves_root_path() -> String:
	return ProjectSettings.globalize_path(save_dir())

static func export_world(world: Dictionary) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json ; Metro Atlas 保存文件")
	dialog.current_file = "%s_%s.json" % [world.get("cityId", "city"), world.get("mode", "blank")]
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(world, "\t"))
		dialog.queue_free()
	)
	Engine.get_main_loop().root.add_child(dialog)
	dialog.popup_centered_ratio(0.65)

static func import_world(on_loaded: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json ; Metro Atlas 保存文件")
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary: on_loaded.call(migrate(parsed))
		dialog.queue_free()
	)
	Engine.get_main_loop().root.add_child(dialog)
	dialog.popup_centered_ratio(0.65)
