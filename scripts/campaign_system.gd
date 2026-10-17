class_name CampaignSystem
extends RefCounted

const CATALOG_PATH := "res://data/campaigns.json"
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

static func content_version() -> String:
	if _catalog.is_empty():load_catalog()
	return str(_catalog.get("contentVersion","unknown"))

static func city_config(city_id: String) -> Dictionary:
	if _catalog.is_empty(): load_catalog()
	return _catalog.get("cities", {}).get(city_id, {}).duplicate(true)

static func future_data_ready(plan: Dictionary, city_data: Dictionary = {}) -> bool:
	# Only plans with a locally audited blueprint may be marked reproduced.
	# Official document links alone are not enough to claim a route was built.
	if str(plan.get("dataStatus", "not_digitized")) != "blueprint_ready": return false
	if str(plan.get("exactAlignment", "not_available")) not in ["station_areas", "corridor_only","verified_alignment"]: return false
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
		if str(plan.get("exactAlignment",""))=="verified_alignment" and group_value.get("alignment",[]).size()<2:return false
		for station_id in station_ids:
			if not known_stations.is_empty() and not known_stations.has(str(station_id)): return false
	return true

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
			if str(chapter.get("precision", "")) not in ["station_areas", "corridor", "schematic","verified_alignment"]: errors.append("%s 缺少有效的线位精度等级" % chapter_id)
			var story:Dictionary=chapter.get("story",{})
			for field in ["opening","purpose","outcome"]:
				if str(story.get(field,"")).is_empty():errors.append("%s 缺少故事内容：%s" % [chapter_id,field])
			if story.get("steps",[]).is_empty():errors.append("%s 缺少可操作故事步骤" % chapter_id)
			var plan_ids:Dictionary={};var previous_date:=""
			for version in story.get("planVersions",[]):
				var plan_id:=str(version.get("id",""));var date:=str(version.get("date",""))
				if plan_id.is_empty() or plan_ids.has(plan_id):errors.append("%s 方案版本编号为空或重复" % chapter_id)
				plan_ids[plan_id]=true
				if date.is_empty() or date>chapter_date or (not previous_date.is_empty() and date<previous_date):errors.append("%s 方案版本日期错误" % chapter_id)
				previous_date=date
				if str(version.get("source","")).is_empty() or str(version.get("description","")).is_empty():errors.append("%s 方案缺少来源或变化说明" % chapter_id)
				for group in version.get("lineGroups",[]):
					for id in group.get("stationIds",[]):
						if not station_ids.has(str(id)):errors.append("%s 方案引用未知站点" % chapter_id)
			for group in chapter.get("lineGroups", []):
				if str(chapter.get("precision",""))=="verified_alignment" and group.get("alignment",[]).size()<2:errors.append("%s 声称精确线位但缺少中心线" % chapter_id)
				if group.get("stationIds", []).size() < 2: errors.append("%s 目标线路少于两站" % chapter_id)
				if float(group.get("toleranceM", 0.0)) <= 0.0: errors.append("%s 目标站缺少正的容差" % chapter_id)
				var group_targets: Dictionary = {}
				for station_id in group.get("stationIds", []):
					if not station_ids.has(str(station_id)): errors.append("%s 引用了未知目标站：%s" % [chapter_id, str(station_id)])
					if group_targets.has(str(station_id)): errors.append("%s 在同一线路组重复引用目标站：%s" % [chapter_id, str(station_id)])
					group_targets[str(station_id)] = true
			for connection in chapter.get("requiredConnections",[]):
				if not station_ids.has(str(connection.get("fromId",""))) or not station_ids.has(str(connection.get("toId",""))) or str(connection.get("source","")).is_empty():errors.append("%s 建设段连接缺少站点引用或来源" % chapter_id)
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
