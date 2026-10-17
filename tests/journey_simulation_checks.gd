extends SceneTree

const Journey = preload("res://scripts/journey_model.gd")
const PathModel = preload("res://scripts/route_path.gd")
const Simulation = preload("res://scripts/simulation_engine.gd")
const Goals = preload("res://scripts/neighborhood_goals.gd")
const ServiceSchedule = preload("res://scripts/service_schedule.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var utilization_probe := {"elapsedMinutes":15, "trainTrips":[{"id":"trip-u", "routeId":"route-u", "directionId":"out", "capacity":100, "directionSnapshot":{"segments":[{"linkIds":["edge-a", "edge-b"], "linkDirections":[{"id":"edge-a", "forward":true}, {"id":"edge-b", "forward":false}]}]}, "loadByEdge":{"trip-u|edge-a|fwd":50, "trip-u|edge-b|rev":0}}], "routeUtilizationBuckets":[]}
	Simulation._record_route_utilization_sample(utilization_probe)
	var utilization_sample: Dictionary = utilization_probe.routeUtilizationBuckets[0].byRoute["route-u|out"]
	_check(is_equal_approx(float(utilization_sample.get("loadRatioSum", 0.0)), 0.25), "线路方向利用率按班次实际区间载客与容量计算")
	_check(is_equal_approx(float(utilization_sample.get("emptyEdgeRatioSum", 0.0)), 0.5) and int(utilization_sample.get("samples", 0)) == 1, "空载区间比例按实际班次区间记录")
	var utilization_no_sample := {"elapsedMinutes":16, "trainTrips":[], "routeUtilizationBuckets":[]}
	Simulation._record_route_utilization_sample(utilization_no_sample)
	_check(utilization_no_sample.routeUtilizationBuckets.is_empty(), "运力利用率每15个游戏分钟采样且无班次不伪造样本")
	var schedule_probe := {"headway": 9, "serviceSchedule": {"mode": "time_of_day", "peakAM": 4, "peakPM": 5, "offPeak": 12}}
	_check(ServiceSchedule.headway_minutes(schedule_probe, 6 * 3600 + 59 * 60) == 12 and ServiceSchedule.headway_minutes(schedule_probe, 7 * 3600) == 4, "分时班距在早高峰边界切换")
	_check(ServiceSchedule.headway_minutes(schedule_probe, 10 * 3600) == 12 and ServiceSchedule.headway_minutes(schedule_probe, 16 * 3600) == 5 and ServiceSchedule.headway_minutes(schedule_probe, 19 * 3600) == 12, "分时班距在早晚高峰结束与晚高峰开始时正确切换")
	_check(ServiceSchedule.next_boundary_after(6 * 3600 + 59 * 60) == 7 * 3600 and ServiceSchedule.next_boundary_after(20 * 3600) == 31 * 3600, "班次边界跨日计算保持累计游戏秒")
	var boundary_world := WorldData.new_world("shanghai", "blank")
	var boundary_route: Dictionary = WorldData.add_route(boundary_world, "边界切换测试线", "#34a67f")
	boundary_route.id = "boundary-line"; boundary_route.networkBased = true; boundary_route.headway = 12; boundary_route.vehicleId = "B-4"; boundary_route.open = true
	ServiceSchedule.set_mode(boundary_route, "time_of_day")
	ServiceSchedule.set_headway(boundary_route, "peakAM", 4)
	boundary_world.stations = [_station("bd-a", [31.23, 121.47], ["boundary-line"]), _station("bd-b", [31.24, 121.47], ["boundary-line"])]
	TrackNetwork.ensure_station_nodes(boundary_world)
	boundary_world.trackEdges = [{"id":"boundary-ab", "aNodeId":TrackNetwork.station_node_id(boundary_world.stations[0], "end"), "bNodeId":TrackNetwork.station_node_id(boundary_world.stations[1], "start"), "geometry":"straight", "depthM":-15.0}]
	boundary_route.stationOrder = ["bd-a", "bd-b"]
	boundary_route.directions = [{"id":"out", "stationIds":["bd-a", "bd-b"], "edgeIdsBySegment":[["boundary-ab"]]}, {"id":"back", "stationIds":["bd-b", "bd-a"], "edgeIdsBySegment":[["boundary-ab"]]}]
	boundary_world.simulation.elapsedSeconds = 6 * 3600 + 59 * 60
	boundary_world.simulation.elapsedMinutes = floori(float(boundary_world.simulation.elapsedSeconds) / 60.0)
	boundary_world.simulation.minute = posmod(boundary_world.simulation.elapsedMinutes, 1440)
	boundary_world.simulation.nextDepartureSeconds = {"boundary-line|out": 7 * 3600 + 9 * 60, "boundary-line|back": 7 * 3600 + 9 * 60}
	var no_flows: Array[Dictionary] = []
	Simulation.step_one_minute(boundary_world, no_flows, 1.0)
	_check(int(boundary_world.simulation.nextDepartureSeconds.get("boundary-line|out", -1)) == 7 * 3600 + 4 * 60, "跨入早高峰时将尚未发出的班次按新班距重新锚定")
	boundary_world.simulation.elapsedSeconds = 7 * 3600 - 60
	boundary_world.simulation.elapsedMinutes = 7 * 60 - 1
	boundary_world.simulation.minute = 7 * 60 - 1
	boundary_world.simulation.trainTrips = []
	boundary_world.simulation.capacityLoads = {}
	boundary_world.simulation.nextDepartureSeconds = {"boundary-line|out": 7 * 3600, "boundary-line|back": 7 * 3600}
	Simulation.step_one_minute(boundary_world, no_flows, 1.0)
	var boundary_departures := 0
	for boundary_trip in boundary_world.simulation.trainTrips:
		if int(boundary_trip.get("departureSeconds", -1)) == 7 * 3600: boundary_departures += 1
	_check(boundary_departures == 2 and int(boundary_world.simulation.nextDepartureSeconds.get("boundary-line|out", -1)) == 7 * 3600 + 4 * 60, "恰在时段边界发车的两个方向均保留且后续按新班距运行")
	var world := WorldData.new_world("shanghai", "blank")
	var route_a: Dictionary = WorldData.add_route(world, "1号线", "#e25263")
	route_a.id = "route-a"
	route_a.headway = 3
	route_a.vehicleId = "B-4"
	var route_b := WorldData.add_route(world, "2号线", "#4288d1")
	route_b.id = "route-b"
	route_b.headway = 4
	var a := _station("a", [31.23, 121.47], ["route-a"])
	var b := _station("b", [31.24, 121.47], ["route-a", "route-b"])
	var c := _station("c", [31.25, 121.47], ["route-b"])
	var isolated := _station("isolated", [31.2301, 121.47], [])
	world.stations = [a, b, c, isolated]
	route_a.stationOrder = ["a", "b"]
	route_b.stationOrder = ["b", "c"]
	world.trackLinks = [_link("ab", "a", "b", "route-a"), _link("bc", "b", "c", "route-b")]
	world.routes[0].open = true
	route_b.open = true
	var ref_lat := 31.23
	var route_path := PathModel.for_route(route_a, world, ref_lat)
	_check(bool(route_path.get("valid", false)), "线路站序与实际区间生成统一双向路径")
	_check(route_path.get("directions", []).size() == 2, "普通新线包含正反两个方向")
	for direction in route_path.get("directions", []):
		for segment in direction.get("segments", []):
			_check(str(segment.get("directionId", "")) == str(direction.get("id", "")), "乘客路径使用线路班次的实际方向编号")
	var network := Journey.build_network(world, ref_lat)
	var cached_transfer_minutes := -1.0
	for edge in network.get("adjacency", {}).get(Journey._state_key("b", "route-a"), []):
		if str(edge.get("type", "")) == "transfer" and str(edge.get("routeId", "")) == "route-b": cached_transfer_minutes = float(edge.get("waitMinutes", -1.0))
	route_b.headway = 8
	var refreshed_network := Journey.build_network(world, ref_lat)
	var refreshed_transfer_minutes := -1.0
	for edge in refreshed_network.get("adjacency", {}).get(Journey._state_key("b", "route-a"), []):
		if str(edge.get("type", "")) == "transfer" and str(edge.get("routeId", "")) == "route-b": refreshed_transfer_minutes = float(edge.get("waitMinutes", -1.0))
	_check(is_equal_approx(cached_transfer_minutes, 2.0) and is_equal_approx(refreshed_transfer_minutes, 4.0), "复用线路网络时仍会按未改版号的最新班距更新换乘等待")
	route_b.headway = 4
	network = Journey.build_network(world, ref_lat)
	var origin := {"id": "origin", "name": "居住点", "latlng": [31.2301, 121.47]}
	var destination := {"id": "destination", "name": "就业点", "latlng": [31.25, 121.47]}
	var journey := Journey.find_journey(origin, destination, world, network, ref_lat)
	_check(bool(journey.get("valid", false)), "离最近站不通时仍能从附近可运营车站选路")
	_check(str(journey.get("originStationId", "")) == "a", "孤立站不会阻断可用路径搜索")
	_check(journey.get("routeIds", []).has("route-a") and journey.get("routeIds", []).has("route-b"), "同一站对象连接两条线路后可形成换乘行程")
	var transfer_count := 0
	for step in journey.get("steps", []):
		if str(step.get("type", "")) == "transfer": transfer_count += 1
	_check(transfer_count == 1, "换乘路径显式包含站内步行")
	_check(float(journey.get("totalMinutes", 0.0)) > float(journey.get("walkMinutes", 0.0)), "出行总时间包含候车、轨道与换乘")

	var schedule_world := WorldData.new_world("shanghai", "blank")
	var schedule_route: Dictionary = WorldData.add_route(schedule_world, "错峰班次测试线", "#34a67f")
	schedule_route.id = "schedule-line"; schedule_route.networkBased = true; schedule_route.headway = 10; schedule_route.vehicleId = "B-4"; schedule_route.open = true
	schedule_world.stations = [_station("s-a", [31.23, 121.47], ["schedule-line"]), _station("s-b", [31.24, 121.47], ["schedule-line"]), _station("s-c", [31.25, 121.47], ["schedule-line"])]
	TrackNetwork.ensure_station_nodes(schedule_world)
	schedule_world.trackEdges = [
		{"id":"schedule-ab", "aNodeId":TrackNetwork.station_node_id(schedule_world.stations[0], "end"), "bNodeId":TrackNetwork.station_node_id(schedule_world.stations[1], "start"), "geometry":"straight", "depthM":-15.0},
		{"id":"schedule-bc", "aNodeId":TrackNetwork.station_node_id(schedule_world.stations[1], "end"), "bNodeId":TrackNetwork.station_node_id(schedule_world.stations[2], "start"), "geometry":"straight", "depthM":-15.0}
	]
	schedule_route.stationOrder = ["s-a", "s-b", "s-c"]
	schedule_route.directions = [
		{"id":"out", "stationIds":["s-a", "s-b", "s-c"], "edgeIdsBySegment":[["schedule-ab"], ["schedule-bc"]]},
		{"id":"back", "stationIds":["s-c", "s-b", "s-a"], "edgeIdsBySegment":[["schedule-bc"], ["schedule-ab"]]}
	]
	var schedule_network := Journey.build_network(schedule_world, ref_lat)
	var schedule_journey := Journey.find_journey({"id":"s-origin", "latlng":[31.24,121.47]}, {"id":"s-dest", "latlng":[31.25,121.47]}, schedule_world, schedule_network, ref_lat)
	var scheduled_rail: Dictionary = {}
	for schedule_step in schedule_journey.get("steps", []):
		if str(schedule_step.get("type", "")) == "rail": scheduled_rail = schedule_step
	_check(bool(schedule_journey.get("valid", false)) and int(scheduled_rail.get("stationOffsetMinutes", 0)) > 0, "线路路径为中间站计算方向与错峰发车时刻")
	var schedule_flow: Array[Dictionary] = [{"id":"s-origin>s-dest", "fromId":"s-origin", "toId":"s-dest", "peoplePerDay":57600.0, "valid":true, "journey":schedule_journey}]
	var scheduled_direction: Dictionary = schedule_network.get("routePaths", {}).get("schedule-line", {}).get("directions", [])[0]
	var preceding_segment: Dictionary = scheduled_direction.get("segments", [])[int(scheduled_rail.get("fromStopIndex", 1)) - 1]
	var next_train_arrival := 420.0 + float(scheduled_rail.get("stationOffsetMinutes", 0.0)) - float(preceding_segment.get("dwellMinutes", 0.0))
	while next_train_arrival <= 421.0: next_train_arrival += 10.0
	var expected_departure := ceili(next_train_arrival)
	var boarded_on_expected_minute := 0
	while int(schedule_world.simulation.elapsedMinutes) < expected_departure:
		var tick := Simulation.step_one_minute(schedule_world, schedule_flow, 1.0)
		if int(schedule_world.simulation.elapsedMinutes) < expected_departure: _check(int(tick.get("boarded", 0)) == 0, "乘客不会在错开的列车到站前上车")
		else: boarded_on_expected_minute = int(tick.get("boarded", 0))
	_check(boarded_on_expected_minute > 0, "到达线路时刻表的发车分钟后乘客可上车")

	var legacy_schedule_world := WorldData.new_world("shanghai", "blank")
	var legacy_schedule_route: Dictionary = WorldData.add_route(legacy_schedule_world, "既有线路时刻表测试", "#6c91ca")
	legacy_schedule_route.id = "legacy-schedule-line"; legacy_schedule_route.open = true; legacy_schedule_route.headway = 10; legacy_schedule_route.stationOrder = ["l-a", "l-b", "l-c"]
	legacy_schedule_world.stations = [_station("l-a", [31.23, 121.47], ["legacy-schedule-line"]), _station("l-b", [31.24, 121.47], ["legacy-schedule-line"]), _station("l-c", [31.25, 121.47], ["legacy-schedule-line"])]
	legacy_schedule_world.trackLinks = [_link("legacy-ab", "l-a", "l-b", "legacy-schedule-line"), _link("legacy-bc", "l-b", "l-c", "legacy-schedule-line")]
	var legacy_path := PathModel.for_route(legacy_schedule_route, legacy_schedule_world, ref_lat)
	var legacy_direction: Dictionary = legacy_path.get("directions", [])[0] if not legacy_path.get("directions", []).is_empty() else {}
	var legacy_segments: Array = legacy_direction.get("segments", [])
	_check(legacy_segments.size() == 2 and float(legacy_segments[1].get("stationOffsetMinutes", 0.0)) > 0.0, "既有线路中间站保留累计的非整数到发偏移")
	var legacy_trip := Simulation._make_train_trip("legacy-schedule-line", legacy_direction, 420, 0.0)
	var middle_stop: Dictionary = legacy_trip.get("stationTimetable", [])[1] if legacy_trip.get("stationTimetable", []).size() > 1 else {}
	_check(float(middle_stop.get("arrivalOffsetMinutes", INF)) <= float(middle_stop.get("departureOffsetMinutes", -INF)), "既有线路班次在中间站按到达和发车时刻停站")
	var exact_trip := Simulation._make_train_trip_seconds("exact-time-line", {"id":"forward", "segments":[{"fromStationId":"e-a", "toStationId":"e-b", "movingMinutes":0.25, "dwellMinutes":0.5}, {"fromStationId":"e-b", "toStationId":"e-c", "movingMinutes":1.25, "dwellMinutes":0.0}]}, 1234)
	var exact_stops: Array = exact_trip.get("stationTimetable", [])
	_check(int(exact_stops[1].get("arrivalSeconds", -1)) == 1249 and int(exact_stops[1].get("departureSeconds", -1)) == 1279, "非整分钟到站使用游戏秒记录，并将停站时间放在中间站")
	_check(int(exact_stops[2].get("arrivalSeconds", -1)) == 1354, "第二段到站时刻从前站实际发车时刻累计")
	var reschedule_before := int(schedule_world.simulation.get("elapsedSeconds", 0))
	var existing_departures: Array[int] = []
	for existing_trip in schedule_world.simulation.get("trainTrips", []): existing_departures.append(int(existing_trip.get("departureSeconds", -1)))
	schedule_route.headway = 4
	Simulation.reschedule_route(schedule_world, "schedule-line")
	_check(int(schedule_world.simulation.nextDepartureSeconds.get("schedule-line|out", -1)) == reschedule_before + 240 and int(schedule_world.simulation.nextDepartureSeconds.get("schedule-line|back", -1)) == reschedule_before + 240, "调整班次只从当前游戏时刻安排未来发车")
	var departures_unchanged := true
	var current_trips: Array = schedule_world.simulation.get("trainTrips", [])
	for i in range(mini(existing_departures.size(), current_trips.size())):
		if int(current_trips[i].get("departureSeconds", -2)) != existing_departures[i]: departures_unchanged = false
	_check(departures_unchanged, "调整发车间隔不会改写已经发出的列车时刻")
	ServiceSchedule.set_mode(schedule_route, "time_of_day")
	ServiceSchedule.set_headway(schedule_route, "peakAM", 4)
	var schedule_history := CommandHistory.new()
	schedule_history.attach(schedule_world)
	var schedule_clock_before := int(schedule_world.simulation.get("elapsedSeconds", 0))
	schedule_history.execute("调整早高峰班距", func(state: Dictionary): ServiceSchedule.set_headway(WorldData.find_route(state, "schedule-line"), "peakAM", 7))
	Simulation.reschedule_route(schedule_world, "schedule-line")
	_check(int(schedule_world.simulation.nextDepartureSeconds.get("schedule-line|out", -1)) == schedule_clock_before + 420, "分时班次配置应用后按当前时段安排下一班")
	schedule_history.undo()
	Simulation.reschedule_route(schedule_world, "schedule-line")
	_check(int(schedule_world.simulation.get("elapsedSeconds", -1)) == schedule_clock_before and int(schedule_world.simulation.nextDepartureSeconds.get("schedule-line|out", -1)) == schedule_clock_before + 240, "撤销班次配置恢复原班距且不回退游戏时钟")
	schedule_history.redo()
	Simulation.reschedule_route(schedule_world, "schedule-line")
	_check(int(schedule_world.simulation.get("elapsedSeconds", -1)) == schedule_clock_before and int(schedule_world.simulation.nextDepartureSeconds.get("schedule-line|out", -1)) == schedule_clock_before + 420, "重做班次配置只重排未来发车")

	# A demand group must remain in the queue, then abandon after the stated wait limit.
	var waiting_world := WorldData.new_world("shanghai", "blank")
	var waiting_route: Dictionary = WorldData.add_route(waiting_world, "候车测试线", "#34a67f")
	waiting_route.id = "wait-line"
	waiting_route.headway = 1440
	waiting_route.vehicleId = "B-4"
	waiting_world.stations = [_station("wa", [31.23, 121.47], ["wait-line"]), _station("wb", [31.24, 121.47], ["wait-line"])]
	waiting_route.stationOrder = ["wa", "wb"]
	waiting_route.open = true
	waiting_world.trackLinks = [_link("wlink", "wa", "wb", "wait-line")]
	var waiting_network := Journey.build_network(waiting_world, ref_lat)
	var waiting_journey := Journey.find_journey(origin, {"id":"d2", "name":"目的地", "latlng":[31.24,121.47]}, waiting_world, waiting_network, ref_lat)
	var flow: Array[Dictionary] = [{"id":"origin>d2", "fromId":"origin", "toId":"d2", "peoplePerDay":57600.0, "valid":true, "routeId":"wait-line", "journey":waiting_journey}]
	var first_tick := Simulation.step_one_minute(waiting_world, flow, 1.0)
	_check(int(first_tick.get("completed", 0)) == 0, "新產生的乘客不會在出發當分鐘被計為完成")
	for index in range(35): Simulation.step_one_minute(waiting_world, flow, 1.0)
	_check(int(waiting_world.simulation.get("completed", 0)) == 0, "沒有發車的乘客不會虛報到達")
	_check(int(waiting_world.simulation.get("abandoned", 0)) > 0, "排隊超過 30 遊戲分鐘會記為放棄")
	_check(int(waiting_world.simulation.get("attempted", 0)) > int(waiting_world.simulation.get("completed", 0)), "需求量與真實完成量分開統計")

	var running_world := WorldData.new_world("shanghai", "blank")
	var running_route: Dictionary = WorldData.add_route(running_world, "运行测试线", "#4288d1")
	running_route.id = "running-line"
	running_route.headway = 1
	running_route.vehicleId = "B-4"
	running_route.open = true
	running_route.stationOrder = ["ra", "rb"]
	running_world.stations = [_station("ra", [31.23, 121.47], ["running-line"]), _station("rb", [31.24, 121.47], ["running-line"])]
	running_world.trackLinks = [_link("rlink", "ra", "rb", "running-line")]
	var running_network := Journey.build_network(running_world, ref_lat)
	var running_journey := Journey.find_journey(origin, {"id":"d3", "name":"工作地", "latlng":[31.24,121.47]}, running_world, running_network, ref_lat)
	var running_flow: Array[Dictionary] = [{"id":"origin>d3", "fromId":"origin", "toId":"d3", "peoplePerDay":57600.0, "valid":true, "routeId":"running-line", "journey":running_journey}]
	Simulation.step_one_minute(running_world, running_flow, 1.0)
	_check(int(running_world.simulation.get("completed", 0)) == 0, "实际出行到达前完成量保持为零")
	for index in range(10): Simulation.step_one_minute(running_world, running_flow, 1.0)
	_check(int(running_world.simulation.get("completed", 0)) > 0, "乘客经过等候和乘车后才计入完成")
	_check(float(running_world.simulation.get("tripMinutesTotal", 0.0)) > 0.0, "完成出行累计实际模拟耗时")
	_check(int(running_world.simulation.get("departed", 0)) > 0, "乘客登车后单独记录离站人数")
	var scheduled_trip: Dictionary = running_world.simulation.get("trainTrips", [])[0] if not running_world.simulation.get("trainTrips", []).is_empty() else {}
	_check(scheduled_trip.get("stationTimetable", []).size() == 2 and scheduled_trip.has("loadByEdge"), "真实班次保存逐站时刻与车辆载客状态")
	_check(not JSON.stringify(running_world).contains("inf"), "等候与乘车状态使用可安全写入 JSON 的时间标记")
	var load_key := "trip-a|edge-a|fwd"
	var load_test_sim := {"trainTrips":[{"id":"trip-a", "loadByEdge":{load_key:7}}]}
	var load_test := {load_key:7}
	Simulation._release_batch_capacity(load_test_sim, load_test, {"trainTripId":"trip-a", "capacityLoadKeys":[load_key], "count":7})
	_check(load_test.is_empty() and int(load_test_sim.trainTrips[0].loadByEdge.get(load_key, 0)) == 0, "乘客到站下车后释放该班次的区间容量")
	var two_edge_trip := {"id":"capacity-trip", "directionSnapshot":{"segments":[{"linkIds":["edge-a"], "linkDirections":[{"id":"edge-a", "forward":true}]}, {"linkIds":["edge-b"], "linkDirections":[{"id":"edge-b", "forward":true}]}]}, "loadByEdge":{"capacity-trip|edge-a|fwd":12, "capacity-trip|edge-b|fwd":12}}
	var two_edge_rail_step := {"fromStopIndex":0, "toStopIndex":2, "segments":[{"fromStopIndex":0, "toStopIndex":1, "fromStationId":"ca", "linkIds":["edge-a"], "linkDirections":[{"id":"edge-a", "forward":true}]}, {"fromStopIndex":1, "toStopIndex":2, "fromStationId":"cb", "linkIds":["edge-b"], "linkDirections":[{"id":"edge-b", "forward":true}]}]}
	var current_edge_keys := Simulation._capacity_keys_for_step_at_stop(two_edge_trip, two_edge_rail_step, 0)
	_check(current_edge_keys == ["capacity-trip|edge-a|fwd"], "乘客上车时只占用当前区间的列车容量，不提前占未来区间")
	var through_batch := {"trainTripId":"capacity-trip", "capacityLoadKeys":["capacity-trip|edge-a|fwd"], "count":12}
	var through_loads := {"capacity-trip|edge-a|fwd":12, "capacity-trip|edge-b|fwd":12}
	Simulation._release_passed_capacity({"trainTrips":[two_edge_trip]}, through_loads, through_batch, two_edge_trip, 1)
	_check(not through_loads.has("capacity-trip|edge-a|fwd") and int(through_loads.get("capacity-trip|edge-b|fwd", 0)) == 12, "到站后仅释放已驶过区间的容量")
	_check(Simulation._capacity_keys_for_step_at_stop(two_edge_trip, two_edge_rail_step, 1) == ["capacity-trip|edge-b|fwd"], "继续乘车的批次在到站后转入下一实际区间")

	var reroute_world := WorldData.new_world("shanghai", "blank")
	var reroute_route: Dictionary = WorldData.add_route(reroute_world, "重新寻路测试线", "#9b69ce")
	reroute_route.id = "reroute-line"
	reroute_route.headway = 1
	reroute_route.vehicleId = "B-4"
	reroute_route.open = true
	reroute_route.stationOrder = ["xa", "xb"]
	reroute_world.stations = [_station("xa", [31.23, 121.47], ["reroute-line"]), _station("xb", [31.24, 121.47], ["reroute-line"])]
	var reroute_link := _link("xlink", "xa", "xb", "reroute-line")
	reroute_world.trackLinks = [reroute_link]
	var reroute_origin := {"id":"x-origin", "latlng":[31.23, 121.47]}
	var reroute_destination := {"id":"x-destination", "latlng":[31.24, 121.47]}
	var reroute_network := Journey.build_network(reroute_world, ref_lat)
	var reroute_journey := Journey.find_journey(reroute_origin, reroute_destination, reroute_world, reroute_network, ref_lat)
	var reroute_flows: Array[Dictionary] = [{"id":"x-origin>x-destination", "originLatLng":reroute_origin.latlng, "destinationLatLng":reroute_destination.latlng, "peoplePerDay":57600.0, "valid":true, "journey":reroute_journey}]
	Simulation.step_one_minute(reroute_world, reroute_flows, 1.0)
	reroute_world.revision += 1
	reroute_world.trackLinks.clear()
	reroute_flows[0].valid = false
	reroute_flows[0].journey = {"valid":false, "steps":[]}
	Simulation.reconcile_passengers(reroute_world, reroute_flows)
	_check(int(reroute_world.simulation.get("completed", 0)) == 0 and int(reroute_world.simulation.get("interrupted", 0)) > 0, "线路失效时在途乘客记为中断，不会误记到达")
	_check(str(reroute_world.simulation.passengerBatches[0].get("status", "")) == "interrupted", "失去可用路径的乘客批次明确记录为中断并保留人数")
	reroute_world.revision += 1
	reroute_world.trackLinks = [reroute_link]
	reroute_flows[0].valid = true
	reroute_network = Journey.build_network(reroute_world, ref_lat)
	reroute_flows[0].journey = Journey.find_journey(reroute_origin, reroute_destination, reroute_world, reroute_network, ref_lat)
	Simulation.reconcile_passengers(reroute_world, reroute_flows)
	for index in range(10): Simulation.step_one_minute(reroute_world, reroute_flows, 1.0)
	_check(int(reroute_world.simulation.get("completed", 0)) > 0, "恢复连续轨道后中断批次可重新寻路并完成出行")

	var disrupted_world := WorldData.new_world("shanghai", "blank")
	var disrupted_route: Dictionary = WorldData.add_route(disrupted_world, "运行中改线测试", "#bc6f44")
	disrupted_route.id = "disrupted-line"; disrupted_route.open = true; disrupted_route.headway = 1; disrupted_route.vehicleId = "B-4"; disrupted_route.stationOrder = ["da", "db"]
	disrupted_world.stations = [_station("da", [31.23, 121.47], ["disrupted-line"]), _station("db", [31.24, 121.47], ["disrupted-line"])]
	var disrupted_link := _link("disrupted-edge", "da", "db", "disrupted-line")
	disrupted_world.trackLinks = [disrupted_link]
	var disrupted_origin := {"id":"d-origin", "latlng":[31.23, 121.47]}
	var disrupted_destination := {"id":"d-destination", "latlng":[31.24, 121.47]}
	var disrupted_network := Journey.build_network(disrupted_world, ref_lat)
	var disrupted_journey := Journey.find_journey(disrupted_origin, disrupted_destination, disrupted_world, disrupted_network, ref_lat)
	var disrupted_flows: Array[Dictionary] = [{"id":"d-origin>d-destination", "originLatLng":disrupted_origin.latlng, "destinationLatLng":disrupted_destination.latlng, "peoplePerDay":57600.0, "valid":true, "journey":disrupted_journey}]
	for index in range(5): Simulation.step_one_minute(disrupted_world, disrupted_flows, 1.0)
	var riding_before_change := 0
	var people_before_change := 0
	for batch in disrupted_world.simulation.passengerBatches:
		people_before_change += int(batch.get("count", 0))
		if str(batch.get("status", "")) == "riding": riding_before_change += int(batch.get("count", 0))
	var completed_before_change := int(disrupted_world.simulation.get("completed", 0))
	_check(riding_before_change > 0, "运行中改线测试确有乘客在车上")
	disrupted_world.trackLinks.clear()
	disrupted_world.revision += 1
	var canceled_during_edit := Simulation.reconcile_train_trips(disrupted_world)
	disrupted_network = Journey.build_network(disrupted_world, ref_lat)
	disrupted_journey = Journey.find_journey(disrupted_origin, disrupted_destination, disrupted_world, disrupted_network, ref_lat)
	disrupted_flows[0].valid = bool(disrupted_journey.get("valid", false))
	disrupted_flows[0].journey = disrupted_journey
	Simulation.reconcile_passengers(disrupted_world, disrupted_flows)
	var people_after_change := 0
	var riding_after_change := 0
	for batch in disrupted_world.simulation.passengerBatches:
		people_after_change += int(batch.get("count", 0))
		if str(batch.get("status", "")) == "riding": riding_after_change += int(batch.get("count", 0))
	_check(canceled_during_edit > 0 and disrupted_world.simulation.trainTrips.is_empty(), "轨道变化会终止引用旧路径的活动班次")
	_check(people_after_change == people_before_change and riding_after_change == 0, "运行中改线保留所有未完成乘客并退出旧列车")
	_check(int(disrupted_world.simulation.get("completed", 0)) == completed_before_change and int(disrupted_world.simulation.get("interrupted", 0)) > 0, "改线不会凭空完成出行，无法续行的乘客明确计入中断")

	var goal_world := WorldData.new_world("shanghai", "blank")
	goal_world.simulation.completedByFlow = {"g>a": 1}
	goal_world.simulation.attemptedByFlow = {"g>a": 1}
	goal_world.simulation.tripMinutesByFlow = {"g>a": 12.0}
	goal_world.simulation.flowSamples = {"g>a": [{"minute":940, "attempted":60, "completed":0, "tripMinutes":0.0}, {"minute":1020, "attempted":1, "completed":1, "tripMinutes":12.0}]}
	goal_world.goalBoard.active = [{"id":"coverage|g>a", "type":"coverage", "flowId":"g>a", "title":"居住区 → 就业区", "status":"build", "baselineCompleted":0, "stableSince":-1}]
	var goal_flow: Array[Dictionary] = [{"id":"g>a", "from":"居住区", "to":"就业区", "peoplePerDay":100.0, "valid":true, "routeIds":["one"], "journey":{"valid":true, "routeIds":["one"], "totalMinutes":12.0}}]
	Goals.update(goal_world, goal_flow, 1000)
	goal_world.simulation.completedByFlow["g>a"] = 2
	goal_world.simulation.attemptedByFlow["g>a"] = 2
	goal_world.simulation.tripMinutesByFlow["g>a"] = 24.0
	Goals.update(goal_world, goal_flow, 1059)
	_check(goal_world.goalBoard.completed.is_empty(), "街区成果不会早于稳定观察一小时记录")
	Goals.update(goal_world, goal_flow, 1060)
	_check(goal_world.goalBoard.completed.size() == 1, "一小时真实改善会形成成果记录")
	_check(int(goal_world.goalBoard.completed[0].get("completed", 0)) == 1 and is_equal_approx(float(goal_world.goalBoard.completed[0].get("averageMinutes", 0.0)), 12.0), "成果使用同一需求组的真实到达数和平均耗时")
	_check(int(goal_world.goalBoard.completed[0].get("beforeWindow", {}).get("attempted", 0)) == 60 and int(goal_world.goalBoard.completed[0].get("afterWindow", {}).get("completed", 0)) == 1, "成果卡记录改造前后各一小时的同组需求数据")

	var midnight_world := WorldData.new_world("shanghai", "blank")
	midnight_world.simulation.elapsedMinutes = 1439
	midnight_world.simulation.elapsedSeconds = 1439 * 60
	midnight_world.simulation.minute = 1439
	Simulation.step_one_minute(midnight_world, [], 1.0)
	_check(int(midnight_world.simulation.elapsedMinutes) == 1440 and int(midnight_world.simulation.minute) == 0, "模擬跨日後累計時間不歸零")
	Simulation.step_one_minute(midnight_world, [], 1.0)
	_check(int(midnight_world.simulation.elapsedMinutes) == 1441, "跨日后第二分钟仍保持累计计时")
	_check(not midnight_world.simulation.get("statisticsBuckets", []).is_empty(), "模拟推进会生成可供统计页读取的15分钟数据桶")

	var sampled_totals := {"completed": 0, "completedByFlow": {}, "tripMinutesAdded": 0.0, "tripMinutesByFlow": {}, "journeyRecords": []}
	var sampled_batch_id := "journey-sample"
	for sample_index in range(512):
		if Simulation._is_sampled_journey_record("%s|1800|2" % sampled_batch_id): break
		sampled_batch_id += "x"
	Simulation._add_completion(sampled_totals, {"id": sampled_batch_id, "flowId": "origin>destination", "count": 2, "bornAtSeconds": 1200, "steps": [{"type":"rail", "routeId":"r", "fromStationId":"a", "toStationId":"b"}], "events": [{"type":"train_board", "timeSeconds":1500, "stationId":"a"}]}, 1800)
	_check(sampled_totals.journeyRecords.size() == 1 and sampled_totals.journeyRecords[0].get("events", []).size() == 1 and sampled_totals.journeyRecords[0].get("steps", []).size() == 1, "确定性抽样保留实际批次事件和规划旅程步骤")

	var v13_world := WorldData.new_world("shanghai", "blank")
	v13_world.schemaVersion = 13
	var v13_route: Dictionary = WorldData.add_route(v13_world, "旧班次迁移线", "#4a91e8")
	v13_route.headway = 7
	var migrated_v13 := SaveManager.migrate(v13_world)
	var migrated_v13_route := WorldData.find_route(migrated_v13, str(v13_route.get("id", "")))
	_check(int(migrated_v13.schemaVersion) == WorldData.SAVE_VERSION and migrated_v13_route.get("serviceSchedule", {}).get("mode", "") == "uniform" and int(migrated_v13_route.serviceSchedule.get("offPeak", 0)) == 7, "13版固定班距迁移为保留原值的全天统一配置")
	_check(migrated_v13.simulation.get("statisticsBuckets", []) is Array and migrated_v13.simulation.get("journeyRecords", []) is Array and migrated_v13.get("challengeMode", "") == "free", "13版迁移初始化挑战与统计记录容器")
	_check(migrated_v13.simulation.get("routeUtilizationBuckets", []) is Array and migrated_v13.simulation.routeUtilizationBuckets.is_empty(), "13版升级至16版时初始化有界线路运力记录，不伪造旧样本")
	var web_v15 := {"cityId":"shanghai", "mode":"blank", "stations":[], "routes":[], "stationPlans":{}, "simulation":{"minute":420}}
	var migrated_web_v15 := SaveManager.migrate(web_v15)
	_check(int(migrated_web_v15.get("schemaVersion", 0)) == WorldData.SAVE_VERSION and migrated_web_v15.simulation.get("routeUtilizationBuckets", []) is Array, "网页旧存档直接迁移到16版时包含运力统计容器")

	var old_v8 := {"schemaVersion": 8, "cityId": "migration-test", "mode": "blank", "stations": [], "routes": [], "trackLinks": [], "simulation": {"minute": 615, "completed": 47, "attempted": 80, "served": 53, "paused": false}, "history": {"undo": [{"label":"old patch"}], "redo": []}}
	var migrated := SaveManager.migrate(old_v8)
	_check(int(migrated.get("schemaVersion", 0)) == WorldData.SAVE_VERSION, "旧版存档升级至当前格式")
	_check(int(migrated.simulation.get("elapsedMinutes", -1)) == 615 and bool(migrated.simulation.paused), "旧存档按一天内时刻恢复并暂停")
	_check(int(migrated.simulation.get("completed", -1)) == 0 and int(migrated.legacyMetrics.get("completedEstimate", 0)) == 47, "旧完成量归档为估算，不混入新真实到达统计")
	_check(migrated.get("history", {}).get("undo", []).is_empty() and not migrated.get("legacyHistory", {}).get("undo", []).is_empty(), "旧撤销历史隔离保留为恢复信息")

	var old_v10 := WorldData.new_world("shanghai", "blank")
	old_v10.schemaVersion = 10
	old_v10.stations = [_station("m-a", [31.23, 121.47], ["m-line"]), _station("m-b", [31.24, 121.47], ["m-line"])]
	TrackNetwork.ensure_station_nodes(old_v10)
	var old_line: Dictionary = WorldData.add_route(old_v10, "迁移路径线", "#34a67f")
	old_line.id = "m-line"; old_line.networkBased = true; old_line.stationOrder = ["m-a", "m-b"]
	old_line.directions = [{"id":"out", "stationIds":["m-a", "m-b"]}, {"id":"back", "stationIds":["m-b", "m-a"]}]
	var m_a_end := TrackNetwork.station_node_id(old_v10.stations[0], "end")
	var m_b_start := TrackNetwork.station_node_id(old_v10.stations[1], "start")
	var mid_node := TrackNetwork.create_node(old_v10, Geo.from_local(Geo.local_m([31.235, 121.47], 31.23) + Vector2(0, 260), 31.23), -15.0)
	old_v10.trackEdges = [
		{"id":"m-edge", "aNodeId":m_a_end, "bNodeId":m_b_start, "geometry":"straight", "depthM":-15.0},
		{"id":"m-alt-a", "aNodeId":m_a_end, "bNodeId":str(mid_node.id), "geometry":"straight", "depthM":-15.0},
		{"id":"m-alt-b", "aNodeId":str(mid_node.id), "bNodeId":m_b_start, "geometry":"straight", "depthM":-15.0}
	]
	var route_options := TrackNetwork.station_path_options("m-a", "m-b", old_v10, 31.23)
	_check(route_options.size() == 2 and route_options[0].get("linkIds", []) != route_options[1].get("linkIds", []), "有分岔时线路规划会提供不同的可选走向")
	var migrated_v10 := SaveManager.migrate(old_v10)
	var migrated_line: Dictionary = WorldData.find_route(migrated_v10, "m-line")
	_check(int(migrated_v10.get("schemaVersion", 0)) == WorldData.SAVE_VERSION and migrated_line.directions[0].edgePathsBySegment[0] == [{"id":"m-edge", "forward":true}], "10 版路线迁移时固定当前可解析的有向轨道走向")
	var old_v11 := old_v10.duplicate(true)
	old_v11.schemaVersion = 11
	var migrated_v11 := SaveManager.migrate(old_v11)
	var migrated_v11_line: Dictionary = WorldData.find_route(migrated_v11, "m-line")
	_check(int(migrated_v11.get("schemaVersion", 0)) == WorldData.SAVE_VERSION and migrated_v11_line.directions[0].edgePathsBySegment[0] == [{"id":"m-edge", "forward":true}], "11 版存档升级时保留已锁定的运营路径")
	var old_v12 := old_v10.duplicate(true)
	old_v12.schemaVersion = 12
	old_v12.routes[0].open = true
	old_v12.simulation.elapsedMinutes = 615
	old_v12.simulation.minute = 615
	old_v12.simulation.paused = false
	var v12_original_name := str(old_v12.stations[0].get("name", ""))
	var v12_history := CommandHistory.new()
	v12_history.attach(old_v12)
	v12_history.execute("改名历史迁移", func(state: Dictionary): WorldData.find_station(state, "m-a").name = "临时名称")
	var migrated_v12 := SaveManager.migrate(old_v12)
	_check(int(migrated_v12.get("schemaVersion", 0)) == WorldData.SAVE_VERSION and int(migrated_v12.simulation.get("elapsedSeconds", 0)) == 615 * 60, "12 版存档迁移累计游戏秒且保持原游戏时刻")
	_check(bool(migrated_v12.simulation.get("paused", false)) and bool(migrated_v12.simulation.get("trainTripsInitialized", false)), "12 版存档升级后暂停并初始化班次状态")
	_check(int(migrated_v12.simulation.nextDepartureSeconds.get("m-line|out", -1)) == 615 * 60 + int(old_v12.routes[0].get("headway", 3)) * 60, "旧线路迁移后首班新计划从恢复时刻之后发出")
	_check(migrated_v12.get("history", {}).get("undo", []).size() == 1 and not migrated_v12.has("legacyHistory"), "12 版差量撤销历史升级时继续保留")
	var migrated_history := CommandHistory.new()
	migrated_history.attach(migrated_v12)
	migrated_history.undo()
	_check(str(WorldData.find_station(migrated_v12, "m-a").get("name", "")) == v12_original_name, "迁移后的旧版差量历史仍能撤销既有改名")
	migrated_v10.trackEdges.append({"id":"m-shortcut", "aNodeId":TrackNetwork.station_node_id(migrated_v10.stations[0], "end"), "bNodeId":TrackNetwork.station_node_id(migrated_v10.stations[1], "start"), "geometry":"straight", "depthM":-15.0})
	var migrated_path: Dictionary = PathModel.for_route(migrated_line, migrated_v10, ref_lat)
	_check(migrated_path.get("directions", [])[0].get("segments", [])[0].get("linkIds", []) == ["m-edge"], "迁移后的旧线不会因新增捷径改变路径")
	_check(bool(migrated_path.get("valid", false)) and migrated_path.get("directions", [])[1].get("segments", [])[0].get("linkIds", []) == ["m-edge"], "反向有序路径也能精确读取同一区间")
	var reverse_lock: Dictionary = migrated_line.directions[0].duplicate(true)
	reverse_lock.edgePathsBySegment = [[{"id":"m-edge", "forward":false}]]
	var invalid_order: Dictionary = PathModel.for_route({"id":"m-line", "networkBased":true, "vehicleId":"B-4", "directions":[reverse_lock]}, migrated_v10, ref_lat)
	_check(not bool(invalid_order.get("valid", false)), "既有线路的区间方向不匹配时会报错而不会暗中反向")

	if failures.is_empty():
		print("PASS: %d journey/simulation checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _station(id: String, latlng: Array, routes: Array) -> Dictionary:
	return {"id": id, "name": id, "latlng": latlng, "heading": 90.0, "lengthM": 80.24, "widthM": 18.0, "vehicleId": "B-4", "routeIds": routes, "schematic": true}

func _link(id: String, a: String, b: String, route_id: String) -> Dictionary:
	return {"id": id, "a": {"stationId": a, "side": "end"}, "b": {"stationId": b, "side": "start"}, "routeIds": [route_id], "schematic": true}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
