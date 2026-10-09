extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	_check(WorldData.cities().size() == 5, "五城数据已迁入")
	_check(WorldData.vehicles().size() >= 8, "车型配置包含多种制式")
	for city in WorldData.cities():
		_check(city.get("stations", []).size() >= 200, "%s 既有站点完整" % city.get("name", "城市"))
		_check(city.get("demand", []).size() >= 25, "%s 有至少 25 个需求点" % city.get("name", "城市"))
		var state := WorldData.new_world(str(city.id), "expand")
		_check(state.get("stations", []).size() == city.get("stations", []).size(), "%s 路网站点导入" % city.get("name", "城市"))
		_check(state.get("routes", []).size() == city.get("lines", []).size(), "%s 运营线路导入" % city.get("name", "城市"))
		_check(not state.get("trackLinks", []).is_empty(), "%s 既有线转换为站间示意" % city.get("name", "城市"))
		for link in state.get("trackLinks", []):
			if not link.get("schematic", false):
				_check(false, "%s 旧轨道未标成示意" % city.get("name", "城市"))
				break
	var sample := WorldData.new_world("shanghai", "blank")
	_check(bool(sample.simulation.paused), "新开局默认为暂停")
	_check(str(sample.fleetMode) == "automatic", "自动车辆保障默认启用")
	var p := [31.2304, 121.4737]
	var roundtrip := Geo.unproject(Geo.project(p, 14), 14)
	_check(absf(float(roundtrip[0])-p[0]) < 0.00001 and absf(float(roundtrip[1])-p[1]) < 0.00001, "地图坐标投影可逆")
	var history := CommandHistory.new(); history.attach(sample)
	var original_time := int(sample.simulation.minute)
	history.execute("建站", func(state: Dictionary): WorldData.create_station(state, [31.23, 121.47], 90.0, str(state.routes[0].id)))
	_check(sample.stations.size() == 1, "历史记录执行建设操作")
	var undone := history.undo()
	_check(undone == "建站" and sample.stations.is_empty(), "撤销恢复规划数据")
	_check(int(sample.simulation.minute) == original_time, "撤销保留模拟时钟")
	var redone := history.redo()
	_check(redone == "建站" and sample.stations.size() == 1, "重做恢复建设操作")
	var path := SaveManager.save_world(sample)
	_check(bool(path.get("ok", false)), "本地存档写入")
	var loaded := SaveManager.load_world("shanghai", "blank")
	_check(bool(loaded.get("ok", false)) and loaded.get("world", {}).get("stations", []).size() == 1, "本地存档往返")
	if failures.is_empty():
		print("PASS: %d checks" % _checks_run)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

var _checks_run := 0

func _check(condition: bool, message: String) -> void:
	_checks_run += 1
	if not condition: failures.append(message)
