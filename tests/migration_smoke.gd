extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var old_web_save := {
		"schemaVersion": 7,
		"cityId": "shanghai",
		"mode": "blank",
		"timeMinutes": 615,
		"stations": [
			{"id": "old-a", "name": "旧站 A", "latlng": [31.23, 121.47], "orientation": 90.0},
			{"id": "old-b", "name": "旧站 B", "latlng": [31.24, 121.48], "orientation": 90.0}
		],
		"routes": [{
			"id": "old-line", "name": "网页规划线", "color": "#34a67f", "status": "operating",
			"imported": false, "vehicleProfileId": "B-4", "headwayMinutes": 6,
			"directions": [
				{"id": "out", "stationIds": ["old-a", "old-b"]},
				{"id": "back", "stationIds": ["old-b", "old-a"]}
			]
		}],
		"stationPlans": {
			"old-a": {"profileId": "B-4", "hall": {"lengthM": 80.24, "widthM": 18.0, "headingDeg": 45.0}},
			"old-b": {"profileId": "B-4", "hall": {"lengthM": 80.24, "widthM": 18.0, "headingDeg": 90.0}}
		},
		"trackNetwork": {"nodes": [], "segments": []},
		"tutorial": {"step": 3, "completed": false}
	}
	var world := SaveManager.migrate(old_web_save)
	_assert(int(world.get("schemaVersion", 0)) == WorldData.SAVE_VERSION, "网页存档升级到当前格式")
	_assert(world.get("stations", []).size() == 2, "保留原有车站")
	_assert(world.get("routes", []).size() == 1, "双向行车方向仍是一条线路")
	_assert(world.get("trackLinks", []).size() == 1, "往返站序合并为一个站间示意区间")
	_assert(bool(world.get("routes", [])[0].get("open", false)), "保留已开通状态")
	_assert(int(world.get("routes", [])[0].get("headway", 0)) == 6, "保留发车间隔")
	_assert(is_equal_approx(float(world.get("stations", [])[0].get("lengthM", 0)), 80.24), "保留网页站体长度")
	_assert(world.get("stations", [])[0].get("routeIds", []).has("old-line"), "车站保留线路关联")
	_assert(int(world.get("simulation", {}).get("minute", 0)) == 615 and bool(world.simulation.paused), "保留游戏时间且恢复时暂停")
	_assert(old_web_save.has("stationPlans") and not old_web_save.has("trackLinks"), "迁移不修改原始网页 JSON")
	print("PASS: web save migration")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: %s" % message)
		quit(1)
