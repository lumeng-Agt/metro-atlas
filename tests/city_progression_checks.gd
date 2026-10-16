extends SceneTree

const Progression = preload("res://scripts/city_progression.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const CommandHistory = preload("res://scripts/command_history.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var city_ids := ["shanghai", "beijing", "guangzhou", "shenzhen", "chengdu"]
	for city_id in city_ids:
		var city := WorldData.city(city_id)
		var errors := Progression.validate_city(city_id, city)
		_check(errors.is_empty(), "%s 的章节出行与发展事件地点均存在且已核验：%s" % [city_id, "；".join(errors)])
		var cfg := Progression.config(city_id)
		_check(cfg.get("flows", []).size() >= 2 and cfg.get("events", []).size() >= 3, "%s 配有连续章节和至少三项城市变化" % city_id)
		var kinds: Array[String] = []
		for event in cfg.get("events", []): kinds.append(str(event.get("kind", "")))
		_check(kinds.has("permanent") and kinds.has("temporary"), "%s 同时包含永久发展与定期活动" % city_id)
		for flow_id in cfg.get("flows", []):
			var points := str(flow_id).split(">")
			if points.size() != 2: continue
			var from_point := _find_demand(city, points[0])
			var to_point := _find_demand(city, points[1])
			_check(not from_point.is_empty() and not to_point.is_empty() and bool(from_point.get("verified", false)) and bool(to_point.get("verified", false)), "%s 章节起终点采用可核验具体地点" % city_id)
	for city_id in city_ids:
		var city := WorldData.city(city_id)
		for event in Progression.events_for_city(city_id):
			var point := _find_demand(city, str(event.get("pointId", "")))
			_check(not point.is_empty() and bool(point.get("verified", false)), "%s 事件“%s”对应已核验地点" % [city_id, str(event.get("title", "城市事件"))])

	_test_deterministic_events()
	_test_campaign_completion()
	_test_same_window_comparison()
	_test_phase_history_and_v14_migration()
	if failures.is_empty():
		print("PASS: %d city progression checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _test_deterministic_events() -> void:
	var world := WorldData.new_world("shanghai", "blank")
	var base := 420
	Progression.start(world, base)
	var first_notice := Progression.advance_events(world, base + 120)
	_check(first_notice.size() == 1 and str(first_notice[0].get("kind", "")) == "announcement", "永久变化先按确定时间预告")
	_check(Progression.advance_events(world, base + 120).is_empty(), "同一预告时间重复载入或刷新不重复播报")
	var housing_start := Progression.advance_events(world, base + 180)
	_check(housing_start.size() == 1 and str(housing_start[0].get("kind", "")) == "started", "永久住宅入住只触发一次")
	var config := Progression.config("shanghai")
	var affected_parts := str(config.flows[0]).split(">")
	var affected := {"fromId":affected_parts[0], "toId":affected_parts[1]}
	var unrelated := {"fromId":"shanghai-d3", "toId":"shanghai-d10"}
	_check(is_equal_approx(Progression.multiplier_for_flow(world, affected), 1.3), "事件只增加涉及该地点的需求组")
	_check(is_equal_approx(Progression.multiplier_for_flow(world, unrelated), 1.0), "无关需求组不受事件乘数影响")
	Progression.advance_events(world, base + 900)
	_check(Progression.active_event_ids(world).has("job_expansion"), "就业增长事件在固定游戏时刻生效")
	var event_start := Progression.advance_events(world, base + 1560)
	_check(Progression.active_event_ids(world).has("yu_garden_festival") and event_start.any(func(item: Dictionary): return str(item.get("kind", "")) == "started"), "临时活动按确定日程开始")
	var persisted := world.duplicate(true)
	_check(Progression.advance_events(persisted, base + 1560).is_empty(), "保存并重载后不会重新抽取或重复触发已记录事件")
	var ended := Progression.advance_events(world, base + 1740)
	_check(not Progression.active_event_ids(world).has("yu_garden_festival") and ended.any(func(item: Dictionary): return str(item.get("kind", "")) == "ended"), "临时活动到期后结束并记录")
	var next_notice := Progression.advance_events(world, base + 1560 + Progression.REPEAT_WEEK_MINUTES - 60)
	_check(next_notice.any(func(item: Dictionary): return str(item.get("kind", "")) == "announcement"), "临时活动按固定周周期预告下一次")

func _test_campaign_completion() -> void:
	var world := WorldData.new_world("shanghai", "blank")
	Progression.start(world, 420)
	var configured: Array = Progression.config("shanghai").flows
	var first := str(configured[0]); var second := str(configured[1])
	var flows: Array[Dictionary] = [
		{"id":first, "valid":true, "peoplePerDay":300.0, "routeIds":["r1"]},
		{"id":second, "valid":true, "peoplePerDay":200.0, "routeIds":["r1"]}
	]
	world.simulation.completedByFlow[first] = 2
	world.simulation.tripMinutesByFlow[first] = 40.0
	var neighborhood := Progression.update_stage(world, flows, 421)
	_check(bool(neighborhood.get("changed", false)) and int(world.cityProgression.chapterIndex) == 1 and int(neighborhood.result.get("completed", 0)) == 2, "周边目标依据指定需求组的真实到达完成")
	world.simulation.completedByFlow[second] = 1
	world.simulation.tripMinutesByFlow[second] = 30.0
	var destination := Progression.update_stage(world, flows, 422)
	_check(bool(destination.get("changed", false)) and int(world.cityProgression.chapterIndex) == 2, "重要目的地章节依据第二组真实出行完成")
	flows.append({"id":"other>place", "valid":true, "peoplePerDay":100.0, "routeIds":["r1", "r2"]})
	world.simulation.completedByFlow["other>place"] = 1
	var transfer := Progression.update_stage(world, flows, 423)
	_check(bool(transfer.get("changed", false)) and int(world.cityProgression.chapterIndex) == 3, "换乘目标要求有效旅程实际使用两条线路")
	var route := WorldData.add_route(world, "运营线", "#35a67c")
	route.id = "r1"; route.open = true
	world.simulation.waitingByRoute["r1"] = 20
	world.simulation.peakCrowding = 0.95
	Progression.update_stage(world, flows, 424)
	world.simulation.waitingByRoute["r1"] = 0
	world.simulation.peakCrowding = 0.0
	world.simulation.attempted = 100
	world.simulation.abandoned = 100
	var abandonment_only := Progression.update_stage(world, flows, 425)
	_check(not bool(abandonment_only.get("changed", false)), "只靠停运或乘客放弃造成的低拥挤不算运营改善")
	world.simulation.completed = 1
	var first_improved := Progression.update_stage(world, flows, 426)
	_check(not bool(first_improved.get("changed", false)) and int(world.cityProgression.operationBaseline.get("stableSince", -1)) == 426, "运营改善开始后仍需稳定观察一小时")
	var stable := Progression.update_stage(world, flows, 486)
	_check(bool(stable.get("changed", false)) and bool(stable.result.get("improvement", false)), "真实到达增加且瓶颈持续改善后完成高峰优化")

func _test_same_window_comparison() -> void:
	var world := WorldData.new_world("shanghai", "blank")
	var buckets: Array = []
	for start in [1500, 1515, 1530, 1545, 2940, 2955, 2970, 2985]:
		buckets.append({"startMinute":start, "attemptedByFlow":{"a>b":10}, "completedByFlow":{"a>b":5}, "tripMinutesByFlow":{"a>b":100.0}, "eventSignature":"", "mixedEventState":false})
	world.simulation.statisticsBuckets = buckets
	var comparison := Progression.compare_flow_windows(world, "a>b", 3000)
	_check(bool(comparison.get("available", false)) and bool(comparison.get("sameEventState", false)), "成果比较只使用完整且城市事件状态一致的昨日同一时段样本")
	world.simulation.statisticsBuckets[5].mixedEventState = true
	var mixed := Progression.compare_flow_windows(world, "a>b", 3000)
	_check(not bool(mixed.get("available", false)), "跨越不同事件状态的统计桶不会被用于归因比较")
	var optional := Progression.optional_goals(world, [{"id":"x", "valid":false}, {"id":"y", "valid":false}, {"id":"z", "valid":false}])
	_check(optional.size() <= 2, "城市议程同时最多提供两项可选委托")

func _test_phase_history_and_v14_migration() -> void:
	var world := WorldData.new_world("shanghai", "blank")
	var history := CommandHistory.new()
	history.attach(world)
	history.execute("新建二期", func(state: Dictionary):
		state.planningPhases.append({"id":"phase_2", "name":"二期 · 就业走廊", "routeIds":[], "stationIds":[], "edgeIds":[], "flowIds":["shanghai-tutorial-jingui>shanghai-d10"]})
		state.currentPlanningPhaseId = "phase_2"
	)
	_check(world.planningPhases.size() == 2 and world.currentPlanningPhaseId == "phase_2", "规划阶段目标与切换记录为一项建设操作")
	history.undo()
	_check(world.planningPhases.size() == 1 and world.currentPlanningPhaseId == "phase_1", "撤销恢复规划阶段与当前阶段")
	history.redo()
	_check(world.planningPhases.size() == 2 and world.planningPhases[1].flowIds.size() == 1, "重做恢复阶段目标需求")
	var old := WorldData.new_world("shanghai", "blank")
	old.schemaVersion = 14
	old.stations = [{"id":"old-station", "name":"旧车站", "latlng":[31.23, 121.47], "heading":90.0, "lengthM":118.8, "widthM":20.0, "routeIds":[]}]
	old.trackLinks = [{"id":"old-edge", "a":{"stationId":"old-station", "side":"start"}, "b":{"stationId":"old-station", "side":"end"}, "routeIds":[]}]
	old.planningPhases = [{"id":"phase_1", "name":"一期建设", "routeIds":[]}]
	var migrated := SaveManager.migrate(old)
	_check(int(migrated.get("schemaVersion", 0)) == WorldData.SAVE_VERSION and bool(migrated.cityProgression.started), "14版存档升级并从当前路网开启城市章节")
	_check(migrated.planningPhases[0].stationIds.has("old-station") and migrated.planningPhases[0].edgeIds.has("old-edge"), "14版站点和轨道映射到第一期建设")

func _find_demand(city: Dictionary, demand_id: String) -> Dictionary:
	for point in city.get("demand", []):
		if str(point.get("id", "")) == demand_id: return point
	return {}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
