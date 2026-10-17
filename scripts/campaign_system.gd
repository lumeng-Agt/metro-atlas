class_name CampaignSystem
extends RefCounted

const CATALOG_PATH := "res://data/campaigns.json"
const STATION_TOLERANCE_M := 150.0
const RoutePathScript = preload("res://scripts/route_path.gd")
static var _catalog: Dictionary = {}
static var _known_station_ids_by_city: Dictionary = {}

static func load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		_catalog = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_catalog = parsed if parsed is Dictionary else {}

static func cutoff_date() -> String:
	return str(_catalog.get("cutoffDate", "2026-10-01"))

static func city_config(city_id: String) -> Dictionary:
	if _catalog.is_empty(): load_catalog()
	return _catalog.get("cities", {}).get(city_id, {}).duplicate(true)

static func create_state(city_id: String) -> Dictionary:
	return {"catalogVersion": int(_catalog.get("schemaVersion", 1)), "cityId": city_id, "phase": "history", "chapterIndex": 0, "completedChapterIds": [], "reviewedFutureIds": [], "activeFuturePlanId": "", "freeUnlocked": false, "assistUsedChapterIds": [], "lastEvaluatedRevision": -1}

static func future_plans(world: Dictionary) -> Array[Dictionary]:
	var config := city_config(str(world.get("cityId", "")))
	var result: Array[Dictionary] = []
	for plan in config.get("futurePlans", []):
		if plan is Dictionary:
			var entry: Dictionary = plan.duplicate(true)
			entry["cityId"] = str(world.get("cityId", ""))
			result.append(entry)
	return result

static func history_complete(world: Dictionary) -> bool:
	var config := city_config(str(world.get("cityId", "")))
	return remaining_history_chapters(world) == 0 and str(config.get("historyStatus", "partial")) == "complete"

static func future_plan_by_id(world: Dictionary, plan_id: String) -> Dictionary:
	for plan in future_plans(world):
		if str(plan.get("id", "")) == plan_id: return plan
	return {}

static func future_data_ready(plan: Dictionary, city_data: Dictionary = {}) -> bool:
	# Only plans with a locally audited blueprint may be marked reproduced.
	# Official document links alone are not enough to claim a route was built.
	if str(plan.get("dataStatus", "not_digitized")) != "blueprint_ready": return false
	if str(plan.get("exactAlignment", "not_available")) not in ["station_areas", "corridor_only"]: return false
	var groups: Variant = plan.get("lineGroups", [])
	if not groups is Array or groups.is_empty(): return false
	var known_stations: Dictionary = {}
	if not city_data.is_empty():
		for station in city_data.get("stations", []): known_stations[str(station.get("id", ""))] = true
	else:
		known_stations = _known_station_ids_by_city.get(str(plan.get("cityId", "")), {})
	for group_value in groups:
		if not group_value is Dictionary: return false
		var station_ids: Variant = group_value.get("stationIds", [])
		if not station_ids is Array or station_ids.size() < 2: return false
		if float(group_value.get("toleranceM", 0.0)) <= 0.0: return false
		for station_id in station_ids:
			if not known_stations.is_empty() and not known_stations.has(str(station_id)): return false
	return true

static func evaluate_future_plan(world: Dictionary, city_data: Dictionary, plan: Dictionary) -> Dictionary:
	if not history_complete(world):
		return {"complete": false, "issues": ["本城历史主线尚未完整整理，远期章节暂未开放。"], "planningRevision": int(world.get("revision", 0))}
	if not future_data_ready(plan, city_data):
		return {"complete": false, "issues": ["该规划还没有通过核验的站点／走廊蓝图，当前只能查看来源，不能判定复现。"], "planningRevision": int(world.get("revision", 0))}
	var chapter := plan.duplicate(true)
	chapter["phase"] = "future"
	chapter["requireOpen"] = bool(plan.get("requireOpen", true))
	return evaluate_chapter(world, city_data, chapter)

static func future_blueprint_for(world: Dictionary, city_data: Dictionary, plan: Dictionary) -> Dictionary:
	if bool(world.get("onboarding", {}).get("active", false)) or not future_data_ready(plan, city_data): return empty_blueprint()
	return _blueprint_for_definition(world, city_data, plan)

static func mark_future_plan_complete(world: Dictionary, plan_id: String) -> bool:
	if str(world.get("campaignState", {}).get("phase", "")) != "future": return false
	var state: Dictionary = world.get("campaignState", {})
	var plan := future_plan_by_id(world, plan_id)
	if plan.is_empty() or not future_data_ready(plan): return false
	var reviewed: Array = state.get("reviewedFutureIds", []).duplicate()
	if not reviewed.has(plan_id): reviewed.append(plan_id)
	state["reviewedFutureIds"] = reviewed
	state["activeFuturePlanId"] = ""
	world["campaignState"] = state
	if future_complete(world):
		state["freeUnlocked"] = true
		state["phase"] = "free"
		world["campaignState"] = state
	return true

static func future_complete(world: Dictionary) -> bool:
	if not history_complete(world): return false
	var state: Dictionary = world.get("campaignState", {})
	var plans := future_plans(world)
	for plan in plans:
		if bool(plan.get("required", true)):
			if not future_data_ready(plan): return false
	var completed: Array = state.get("reviewedFutureIds", [])
	for plan in plans:
		if bool(plan.get("required", true)) and not completed.has(str(plan.get("id", ""))): return false
	return true

static func current_chapter(world: Dictionary) -> Dictionary:
	var state: Dictionary = world.get("campaignState", {})
	var config := city_config(str(world.get("cityId", "")))
	if str(state.get("phase", "history")) != "history": return {}
	var chapters: Array = config.get("chapters", [])
	var index := int(state.get("chapterIndex", 0))
	return chapters[index].duplicate(true) if index >= 0 and index < chapters.size() else {}

static func remaining_history_chapters(world: Dictionary) -> int:
	var config := city_config(str(world.get("cityId", "")))
	return maxi(0, config.get("chapters", []).size() - int(world.get("campaignState", {}).get("chapterIndex", 0)))

static func current_year(world: Dictionary) -> int:
	var chapter := current_chapter(world)
	if chapter.is_empty(): return 0
	return int(str(chapter.get("date", "0")).substr(0, 4))

static func _station_reference_map(city_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for station in city_data.get("stations", []):
		var station_id := str(station.get("id", ""))
		if not station_id.is_empty(): result[station_id] = station
	return result

static func _match_target_stations(world: Dictionary, city_data: Dictionary, target_ids: Array, tolerance_override: float = -1.0, station_name_overrides: Dictionary = {}) -> Dictionary:
	var station_refs := _station_reference_map(city_data)
	var used: Dictionary = {}
	var matched: Array[Dictionary] = []
	var missing: Array[Dictionary] = []
	var reference_lat := float(city_data.get("center", [31.23, 121.47])[0])
	for target_id_value in target_ids:
		var target_id := str(target_id_value)
		var target: Dictionary = station_refs.get(target_id, {})
		if target.is_empty():
			missing.append({"targetId": target_id, "name": str(station_name_overrides.get(target_id, target_id)), "reason": "资料包缺少站点坐标"})
			continue
		var tolerance := tolerance_override if tolerance_override > 0.0 else STATION_TOLERANCE_M
		var best: Dictionary = {}
		var best_distance := INF
		for station in world.get("stations", []):
			if bool(station.get("existing", false)): continue
			var player_id := str(station.get("id", ""))
			if used.has(player_id): continue
			var distance := Geo.local_m(station.get("latlng", [0, 0]), reference_lat).distance_to(Geo.local_m(target.get("latlng", [0, 0]), reference_lat))
			if distance < best_distance:
				best_distance = distance
				best = station
		if best.is_empty() or best_distance > tolerance:
			missing.append({"targetId": target_id, "name": str(station_name_overrides.get(target_id, target.get("name", target_id))), "reason": "未找到容差范围内的站点", "distanceM": best_distance if not best.is_empty() else -1.0, "toleranceM": tolerance})
		else:
			var player_id := str(best.get("id", ""))
			used[player_id] = true
			matched.append({"targetId": target_id, "playerStationId": player_id, "name": str(station_name_overrides.get(target_id, target.get("name", "车站"))), "latlng": target.get("latlng", []), "distanceM": best_distance, "toleranceM": tolerance})
	return {"complete": missing.is_empty() and matched.size() == target_ids.size(), "matched": matched, "missing": missing, "targetCount": target_ids.size()}

static func _ordered_subsequence(route: Dictionary, matched_ids: Array[String]) -> bool:
	var order: Array = route.get("stationOrder", [])
	if matched_ids.is_empty() or order.is_empty(): return false
	var reversed_ids: Array = []
	for index in range(matched_ids.size() - 1, -1, -1): reversed_ids.append(matched_ids[index])
	return _subsequence_matches(order, matched_ids) or _subsequence_matches(order, reversed_ids)

static func _subsequence_matches(order: Array, wanted: Array) -> bool:
	var cursor := 0
	for station_id in order:
		if cursor < wanted.size() and str(station_id) == str(wanted[cursor]): cursor += 1
	return cursor == wanted.size()

static func evaluate_chapter(world: Dictionary, city_data: Dictionary, chapter: Dictionary) -> Dictionary:
	var issues: Array[String] = []
	var group_results: Array[Dictionary] = []
	var used_routes: Dictionary = {}
	for group in chapter.get("lineGroups", []):
		var group_dict: Dictionary = group
		var station_result := _match_target_stations(world, city_data, group_dict.get("stationIds", []), float(group_dict.get("toleranceM", STATION_TOLERANCE_M)), group_dict.get("stationNames", {}))
		var matched_ids: Array[String] = []
		for station_match in station_result.get("matched", []): matched_ids.append(str(station_match.get("playerStationId", "")))
		var matching_routes: Array[Dictionary] = []
		var invalid_path_route_names: Array[String] = []
		var reference_lat := float(city_data.get("center", [31.23, 121.47])[0])
		for route in world.get("routes", []):
			if used_routes.has(str(route.get("id", ""))): continue
			if not _ordered_subsequence(route, matched_ids): continue
			var route_path := RoutePathScript.for_route(route, world, reference_lat)
			if bool(route_path.get("valid", false)):
				matching_routes.append(route)
			else:
				invalid_path_route_names.append(str(route.get("name", "线路")))
		var route_match: Dictionary = matching_routes[0] if not matching_routes.is_empty() else {}
		if not bool(station_result.get("complete", false)):
			for missing_item in station_result.get("missing", []):
				issues.append("%s：%s（%s）" % [str(group_dict.get("name", "线路")), str(missing_item.get("name", "目标站")), str(missing_item.get("reason", "未完成"))])
		elif route_match.is_empty():
			if not invalid_path_route_names.is_empty():
				issues.append("%s：线路%s的物理轨道尚未形成连续、可运营的路径。" % [str(group_dict.get("name", "线路")), "、".join(invalid_path_route_names)])
			else:
				issues.append("%s：需要有一条线路按目标顺序停靠全部站点，并保持区间连续。" % str(group_dict.get("name", "线路")))
		elif bool(chapter.get("requireOpen", true)) and not bool(route_match.get("open", false)):
			issues.append("%s：路径已建立，请在线路详情检查并开通。" % str(group_dict.get("name", "线路")))
		else:
			used_routes[str(route_match.get("id", ""))] = true
		group_results.append({"name": str(group_dict.get("name", "线路")), "stationResult": station_result, "routeId": str(route_match.get("id", "")), "routeName": str(route_match.get("name", "")), "routeOpen": bool(route_match.get("open", false)), "valid": bool(station_result.get("complete", false)) and not route_match.is_empty() and (not bool(chapter.get("requireOpen", true)) or bool(route_match.get("open", false)))})
	return {"complete": issues.is_empty() and group_results.size() == chapter.get("lineGroups", []).size(), "issues": issues, "groups": group_results, "chapterId": str(chapter.get("id", "")), "planningRevision": int(world.get("revision", 0))}

static func blueprint_for(world: Dictionary, city_data: Dictionary) -> Dictionary:
	if bool(world.get("onboarding", {}).get("active", false)):
		return empty_blueprint()
	var phase := str(world.get("campaignState", {}).get("phase", "history"))
	if phase == "history":
		var chapter := current_chapter(world)
		if chapter.is_empty(): return empty_blueprint()
		return _blueprint_for_definition(world, city_data, chapter)
	if phase == "future":
		var state: Dictionary = world.get("campaignState", {})
		var selected_id := str(state.get("activeFuturePlanId", ""))
		var plan := future_plan_by_id(world, selected_id) if not selected_id.is_empty() else {}
		if plan.is_empty() or not future_data_ready(plan, city_data):
			for candidate in future_plans(world):
				if future_data_ready(candidate, city_data) and not state.get("reviewedFutureIds", []).has(str(candidate.get("id", ""))):
					plan = candidate
					break
		if plan.is_empty(): return empty_blueprint()
		return future_blueprint_for(world, city_data, plan)
	return empty_blueprint()

static func empty_blueprint() -> Dictionary:
	return {"visible": false, "stations": [], "corridors": [], "title": ""}

static func _blueprint_for_definition(world: Dictionary, city_data: Dictionary, chapter: Dictionary) -> Dictionary:
	var stations_by_id := _station_reference_map(city_data)
	var stations: Array[Dictionary] = []
	var corridors: Array[Dictionary] = []
	for group in chapter.get("lineGroups", []):
		var group_dict: Dictionary = group
		var station_result := _match_target_stations(world, city_data, group_dict.get("stationIds", []), float(group_dict.get("toleranceM", STATION_TOLERANCE_M)), group_dict.get("stationNames", {}))
		var matched_by_target: Dictionary = {}
		for item in station_result.get("matched", []): matched_by_target[str(item.get("targetId", ""))] = item
		var corridor_points: Array = []
		var corridor_targets: Array[Dictionary] = []
		for target_id_value in group_dict.get("stationIds", []):
			var target_id := str(target_id_value)
			var target: Dictionary = stations_by_id.get(target_id, {})
			if target.is_empty(): continue
			var latlng: Array = target.get("latlng", [])
			if latlng.size() < 2: continue
			var match: Dictionary = matched_by_target.get(target_id, {})
			var point := {"id": target_id, "name": str(group_dict.get("stationNames", {}).get(target_id, target.get("name", "車站"))), "latlng": latlng, "toleranceM": float(group_dict.get("toleranceM", STATION_TOLERANCE_M)), "built": not match.is_empty(), "distanceM": float(match.get("distanceM", -1.0)), "precision": str(chapter.get("precision", "corridor"))}
			stations.append(point)
			corridor_targets.append(point)
			corridor_points.append(latlng)
		corridors.append({"id": str(group_dict.get("name", "")), "name": str(group_dict.get("name", "")), "points": corridor_points, "targets": corridor_targets, "precision": str(chapter.get("precision", "corridor"))})
	return {"visible": true, "stations": stations, "corridors": corridors, "title": str(chapter.get("title", "历史蓝图")), "date": str(chapter.get("date", "")), "precision": str(chapter.get("precision", "corridor")), "notice": "现代地理参考底图；站位为容差参考，虚线为站区间示意，不是工程线位。"}

static func validate_catalog(city_data_list: Array) -> Array[String]:
	if _catalog.is_empty(): load_catalog()
	var errors: Array[String] = []
	var city_ids: Dictionary = {}
	_known_station_ids_by_city.clear()
	for city in city_data_list:
		var city_id := str(city.get("id", ""))
		city_ids[city_id] = city
		var station_id_map: Dictionary = {}
		for station in city.get("stations", []): station_id_map[str(station.get("id", ""))] = true
		_known_station_ids_by_city[city_id] = station_id_map
	for city_id in _catalog.get("cities", {}):
		if not city_ids.has(str(city_id)):
			errors.append("历史资料包引用未知城市：%s" % str(city_id))
			continue
		var city_config_value: Dictionary = _catalog.cities[city_id]
		if str(city_config_value.get("historyStatus", "")) not in ["partial", "complete"]: errors.append("%s 缺少历史资料覆盖状态" % str(city_id))
		if str(city_config_value.get("futureStatus", "")) not in ["not_digitized", "partial", "complete"]: errors.append("%s 缺少远期资料状态" % str(city_id))
		if str(city_config_value.get("coverageNote", "")).is_empty(): errors.append("%s 缺少历史资料范围说明" % str(city_id))
		var station_ids := {}
		for station in city_ids[str(city_id)].get("stations", []): station_ids[str(station.get("id", ""))] = true
		var seen_chapters: Dictionary = {}
		var last_chapter_date := ""
		for chapter in _catalog.cities[city_id].get("chapters", []):
			var chapter_id := str(chapter.get("id", ""))
			if chapter_id.is_empty() or seen_chapters.has(chapter_id): errors.append("%s 历史章节编号无效或重复" % str(city_id))
			seen_chapters[chapter_id] = true
			var chapter_date := str(chapter.get("date", ""))
			if chapter_date.is_empty() or chapter_date > cutoff_date(): errors.append("%s 章节日期无效或晚于资料截止日期" % chapter_id)
			if not last_chapter_date.is_empty() and chapter_date < last_chapter_date: errors.append("%s 历史章节未按日期排序" % chapter_id)
			last_chapter_date = chapter_date
			if str(chapter.get("source", "")).is_empty(): errors.append("%s 缺少来源" % chapter_id)
			if str(chapter.get("sourceTitle", "")).is_empty(): errors.append("%s 缺少来源标题" % chapter_id)
			if str(chapter.get("sourceCheckedAt", "")).is_empty(): errors.append("%s 缺少来源核验日期" % chapter_id)
			if str(chapter.get("sourceType", "")).is_empty(): errors.append("%s 缺少来源类型" % chapter_id)
			if str(chapter.get("status", "")).is_empty(): errors.append("%s 缺少历史实施状态" % chapter_id)
			if str(chapter.get("alignmentNote", "")).is_empty(): errors.append("%s 缺少线位精度说明" % chapter_id)
			if str(chapter.get("precision", "")) not in ["station_areas", "corridor", "schematic"]: errors.append("%s 缺少有效的线位精度等级" % chapter_id)
			for group in chapter.get("lineGroups", []):
				if group.get("stationIds", []).size() < 2: errors.append("%s 目标线路少于两站" % chapter_id)
				if float(group.get("toleranceM", 0.0)) <= 0.0: errors.append("%s 目标站缺少正的容差" % chapter_id)
				var group_targets: Dictionary = {}
				for station_id in group.get("stationIds", []):
					if not station_ids.has(str(station_id)): errors.append("%s 引用了未知目标站：%s" % [chapter_id, str(station_id)])
					if group_targets.has(str(station_id)): errors.append("%s 在同一线路组重复引用目标站：%s" % [chapter_id, str(station_id)])
					group_targets[str(station_id)] = true
		var last_event_date := ""
		for event in city_config_value.get("historicalEvents", []):
			var event_date := str(event.get("date", ""))
			if event_date.is_empty() or event_date > cutoff_date(): errors.append("%s 历史事件日期无效或晚于资料截止日期" % str(event.get("title", city_id)))
			if not last_event_date.is_empty() and event_date < last_event_date: errors.append("%s 历史事件未按日期排序" % str(city_id))
			last_event_date = event_date
			if str(event.get("id", "")).is_empty(): errors.append("%s 历史事件缺少稳定编号" % str(event.get("title", city_id)))
			if str(event.get("source", "")).is_empty() or str(event.get("sourceTitle", "")).is_empty(): errors.append("%s 历史事件缺少可追溯来源" % str(event.get("title", city_id)))
			if str(event.get("sourceCheckedAt", "")).is_empty() or str(event.get("scope", "")).is_empty() or str(event.get("status", "")).is_empty() or str(event.get("sourceType", "")).is_empty(): errors.append("%s 缺少核验日期、范围、来源类型或实施状态" % str(event.get("title", city_id)))
			if not event.has("sourcePublicationDate"): errors.append("%s 未明确记录来源公开日期是否已核实" % str(event.get("title", city_id)))
		for future in _catalog.cities[city_id].get("futurePlans", []):
			if str(future.get("date", "")) > cutoff_date(): errors.append("%s 远期资料晚于资料截止日期" % str(future.get("id", city_id)))
			if str(future.get("source", "")).is_empty(): errors.append("%s 远期资料缺少来源" % str(future.get("id", city_id)))
			if str(future.get("sourceCheckedAt", "")).is_empty(): errors.append("%s 远期资料缺少核验日期" % str(future.get("id", city_id)))
			if str(future.get("sourceTitle", "")).is_empty(): errors.append("%s 远期资料缺少来源标题" % str(future.get("id", city_id)))
			if str(future.get("status", "")).is_empty() or str(future.get("sourceType", "")).is_empty(): errors.append("%s 远期条目缺少实施状态或来源类型" % str(future.get("id", city_id)))
			if not future.has("required"): errors.append("%s 未说明是否阻塞自由阶段" % str(future.get("id", city_id)))
			if str(future.get("dataStatus", "")) == "blueprint_ready" and not future_data_ready(future, city_ids[str(city_id)]): errors.append("%s 声称蓝图已就绪但缺少有效目标几何或站点引用" % str(future.get("id", city_id)))
	return errors
