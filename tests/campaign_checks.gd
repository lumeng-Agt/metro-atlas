extends SceneTree

const Campaign = preload("res://scripts/campaign_system.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var cities: Array = WorldData.cities()
	var catalog_errors := Campaign.validate_catalog(cities)
	_check(catalog_errors.is_empty(), "五城历史与远期目录引用均有效：%s" % "；".join(catalog_errors))
	_check(Campaign.cutoff_date() == "2026-10-01", "历史资料截止日期固定为 2026-10-01")
	for city in cities:
		var city_id := str(city.get("id", ""))
		var config := Campaign.city_config(city_id)
		var chapters: Array = config.get("chapters", [])
		var sample_world: Dictionary = {}
		_check(not chapters.is_empty(), "%s 至少配置一个历史样板章节" % city_id)
		for chapter in chapters:
			var world := _world_for_chapter(city, chapter)
			if sample_world.is_empty(): sample_world = world
			var result := Campaign.evaluate_chapter(world, city, chapter)
			_check(bool(result.get("complete", false)), "%s / %s 的目标站、站序和连续物理路径可通过评估：%s" % [city_id, str(chapter.get("id", "")), "；".join(result.get("issues", []))])
			var blueprint := Campaign.blueprint_for(world, city)
			_check(bool(blueprint.get("visible", false)) and not blueprint.get("stations", []).is_empty(), "%s / %s 可生成站区蓝图" % [city_id, str(chapter.get("id", ""))])
		var hidden_world := sample_world.duplicate(true)
		hidden_world["onboarding"] = {"active": true}
		_check(not bool(Campaign.blueprint_for(hidden_world, city).get("visible", false)), "%s 教学期间隐藏历史蓝图，避免新手过载" % city_id)
		var plans: Array[Dictionary] = Campaign.future_plans(sample_world)
		_check(not plans.is_empty(), "%s 有官方远期规划来源条目" % city_id)
		for plan in plans:
			_check(not Campaign.future_data_ready(plan), "%s 的远期资料未数字化时不会伪装成可复现蓝图" % city_id)
		var end_state := sample_world.duplicate(true)
		end_state.campaignState["chapterIndex"] = chapters.size()
		_check(not Campaign.history_complete(end_state), "%s 的可玩样板完成不等于全史已经复原" % city_id)
		_check(not Campaign.future_complete(end_state), "%s 的官方来源清单未数字化时不能解锁自由阶段" % city_id)
	_test_direction_and_open_requirements()
	_test_historical_scope_and_precision()
	_test_future_blueprint_contract()
	_test_chengdu_expired_plan_is_not_future()
	_test_documented_plan_changes_are_not_fabricated_blueprints()
	if failures.is_empty():
		print("PASS: %d campaign checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _world_for_chapter(city: Dictionary, chapter: Dictionary) -> Dictionary:
	var city_id := str(city.get("id", ""))
	var world := WorldData.new_world(city_id, "campaign")
	world["onboarding"] = {"active": false, "completed": true}
	var campaign_state: Dictionary = world.get("campaignState", {})
	for index in range(Campaign.city_config(city_id).get("chapters", []).size()):
		if str(Campaign.city_config(city_id).chapters[index].get("id", "")) == str(chapter.get("id", "")):
			campaign_state["chapterIndex"] = index
			break
	world["campaignState"] = campaign_state
	var target_map: Dictionary = {}
	for group in chapter.get("lineGroups", []):
		for target_id_value in group.get("stationIds", []):
			var target_id := str(target_id_value)
			if target_map.has(target_id): continue
			var target := _find_city_station(city, target_id)
			if target.is_empty(): continue
			var player_id := "player_%s_%d" % [target_id, target_map.size()]
			world.stations.append({"id":player_id, "name":str(target.get("name", "车站")), "latlng":target.get("latlng", [0.0, 0.0]).duplicate(), "heading":90.0, "lengthM":118.788, "widthM":20.0, "depthM":-15.0, "vehicleId":"B-6", "routeIds":[], "existing":false})
			target_map[target_id] = player_id
	TrackNetwork.ensure_station_nodes(world)
	for group_index in range(chapter.get("lineGroups", []).size()):
		var group: Dictionary = chapter.lineGroups[group_index]
		var route_id := "test_route_%s_%d" % [city_id, group_index]
		var order: Array[String] = []
		for target_id in group.get("stationIds", []): order.append(str(target_map.get(str(target_id), "")))
		var route := {"id":route_id, "name":str(group.get("name", "线路")), "vehicleId":"B-6", "open":true, "stationOrder":order, "directions":[{"id":"forward", "stationIds":order.duplicate()}], "routeIds":[]}
		world.routes.append(route)
		for index in range(order.size() - 1):
			var from_id := order[index]
			var to_id := order[index + 1]
			var existing_edge: Dictionary = {}
			for edge in world.trackLinks:
				var a_id := str(edge.get("a", {}).get("stationId", ""))
				var b_id := str(edge.get("b", {}).get("stationId", ""))
				if (a_id == from_id and b_id == to_id) or (a_id == to_id and b_id == from_id): existing_edge = edge; break
			if existing_edge.is_empty():
				existing_edge = {"id":"edge_%s_%d_%d" % [city_id, group_index, index], "a":{"stationId":from_id, "side":"end"}, "b":{"stationId":to_id, "side":"start"}, "routeIds":[]}
				world.trackLinks.append(existing_edge)
			if not existing_edge.routeIds.has(route_id): existing_edge.routeIds.append(route_id)
	return world

func _find_city_station(city: Dictionary, station_id: String) -> Dictionary:
	for station in city.get("stations", []):
		if str(station.get("id", "")) == station_id: return station
	return {}

func _test_direction_and_open_requirements() -> void:
	var city := WorldData.city("shanghai")
	var chapter: Dictionary = Campaign.city_config("shanghai").chapters[0]
	var world := _world_for_chapter(city, chapter)
	var route: Dictionary = world.routes[0]
	var order: Array = route.stationOrder.duplicate()
	order.reverse()
	route.stationOrder = order
	route.directions = [{"id":"reverse", "stationIds":order.duplicate()}]
	_check(bool(Campaign.evaluate_chapter(world, city, chapter).get("complete", false)), "历史线路允许按真实双向线路的反方向复现")
	route.open = false
	_check(not bool(Campaign.evaluate_chapter(world, city, chapter).get("complete", false)), "要求开通的历史章节不能由暂停线路通过")
	route.open = true
	world.trackLinks.clear()
	_check(not bool(Campaign.evaluate_chapter(world, city, chapter).get("complete", false)), "只有正确站序、没有连续物理轨道不能通过章节")
	var fake_plan := {"id":"fake_ready", "dataStatus":"blueprint_ready", "exactAlignment":"corridor_only", "source":"https://example.invalid"}
	_check(not Campaign.future_data_ready(fake_plan), "只有把资料状态改成ready但没有目标几何也不能声称蓝图可复现")

func _test_future_blueprint_contract() -> void:
	var city := WorldData.city("shanghai")
	var chapter: Dictionary = Campaign.city_config("shanghai").chapters[0]
	var world := _world_for_chapter(city, chapter)
	var plan: Dictionary = chapter.duplicate(true)
	plan["id"] = "test-future-plan"
	plan["dataStatus"] = "blueprint_ready"
	plan["exactAlignment"] = "station_areas"
	_check(Campaign.future_data_ready(plan, city), "未来蓝图只有在含目标站区和有效地名引用时才算就绪")
	var blueprint := Campaign.future_blueprint_for(world, city, plan)
	_check(bool(blueprint.get("visible", false)) and not blueprint.get("stations", []).is_empty(), "已审核未来蓝图能生成地图站区与走廊")
	var invalid_plan: Dictionary = plan.duplicate(true)
	invalid_plan["lineGroups"] = [{"name":"错误引用", "stationIds":["unknown-a", "unknown-b"], "toleranceM":100}]
	_check(not Campaign.future_data_ready(invalid_plan, city), "未来蓝图引用未知站点时不能进入可验收状态")
	var end_state := world.duplicate(true)
	var state: Dictionary = end_state.get("campaignState", {})
	state["phase"] = "future"
	state["chapterIndex"] = Campaign.city_config("shanghai").chapters.size()
	end_state["campaignState"] = state
	var evaluation := Campaign.evaluate_future_plan(end_state, city, plan)
	_check(not bool(evaluation.get("complete", false)) and str(evaluation.get("issues", [""])[0]).contains("历史主线"), "历史资料未声明完整时不能提前评估远期并解锁自由阶段")

func _test_chengdu_expired_plan_is_not_future() -> void:
	var city := WorldData.city("chengdu")
	var world := WorldData.new_world("chengdu", "campaign")
	var future := Campaign.future_plans(world)
	for plan in future:
		_check(str(plan.get("id", "")) != "cd-phase3-2016-2020", "成都已过期第三期建设规划留在历史记录，不充当当前远期规划")
		_check(str(plan.get("id", "")) != "cd-2023-future", "已在2023年开通的19号线二期不冒充未来规划")
	var event_ids: Dictionary = {}
	for event in Campaign.city_config("chengdu").get("historicalEvents", []): event_ids[str(event.get("id", ""))] = true
	_check(event_ids.has("chengdu-event-2016-08-line1-phase3-revision"), "成都1号线三期已核实的方案调整进入历史时间线，并注明几何缺失")
	_check(not Campaign.history_complete(world) and not Campaign.future_complete(world), "成都资料包仍标记为部分整理，不会错误解锁自由阶段")

func _test_documented_plan_changes_are_not_fabricated_blueprints() -> void:
	var shenzhen_events: Array = Campaign.city_config("shenzhen").get("historicalEvents", [])
	var shenzhen_ids: Dictionary = {}
	for event in shenzhen_events: shenzhen_ids[str(event.get("id", ""))] = event
	_check(shenzhen_ids.has("shenzhen-event-1998-05-phase1-proposal"), "深圳1998年获批一期方案保留为可追溯历史事件")
	_check(shenzhen_ids.has("shenzhen-event-2000-05-line1-revision") and shenzhen_ids.has("shenzhen-event-2002-05-line1-revision"), "深圳1号线2000与2002年调整作为独立方案变更记录")
	var has_unverified_1998_blueprint := false
	for chapter in Campaign.city_config("shenzhen").get("chapters", []):
		if str(chapter.get("date", "")).begins_with("1998"): has_unverified_1998_blueprint = true
	_check(not has_unverified_1998_blueprint, "深圳初始方案几何未核验时不伪装成可玩蓝图")
	var guangzhou_ids: Dictionary = {}
	for event in Campaign.city_config("guangzhou").get("historicalEvents", []): guangzhou_ids[str(event.get("id", ""))] = event
	_check(guangzhou_ids.has("guangzhou-event-1978-first-network-plan") and guangzhou_ids.has("guangzhou-event-1979-preparatory-office"), "广州早期线网规划与筹建机构有独立历史节点")
	var beijing_ids: Dictionary = {}
	for event in Campaign.city_config("beijing").get("historicalEvents", []): beijing_ids[str(event.get("id", ""))] = event
	_check(beijing_ids.has("beijing-event-1965-01-one-ring-two-lines"), "北京早期一环两线三期方案进入时间线并保留未数字化说明")

func _test_historical_scope_and_precision() -> void:
	var beijing := Campaign.city_config("beijing")
	var chapters: Array = beijing.get("chapters", [])
	_check(chapters.size() >= 4, "北京样板区分建成、试运营、延至苹果园和正式开放节点")
	if chapters.size() >= 4:
		_check(str(chapters[0].get("date", "")) == "1969-10-01" and chapters[0].get("lineGroups", []).size() == 2, "北京1969年建成阶段区分西段和南段，不假装已经连续运营")
		_check(str(chapters[1].get("date", "")) == "1971-01-15", "北京1971年试运营作为独立历史节点")
		_check(str(chapters[2].get("date", "")) == "1973-04-23", "北京1973年延至苹果园作为独立历史节点")
		var names: Dictionary = chapters[1].get("lineGroups", [{}])[0].get("stationNames", {})
		_check(str(names.get("beijing-s60", "")) == "立新站", "历史章节保留立新站旧称并关联现代站点坐标")
	var city := WorldData.city("beijing")
	var sample := _world_for_chapter(city, chapters[1]) if chapters.size() > 1 else {}
	if not sample.is_empty():
		var blueprint := Campaign.blueprint_for(sample, city)
		var has_lixin_label := false
		for target in blueprint.get("stations", []):
			if str(target.get("id", "")) == "beijing-s60" and str(target.get("name", "")) == "立新站": has_lixin_label = true
		_check(has_lixin_label, "北京试运营蓝图显示当时的立新站名")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
