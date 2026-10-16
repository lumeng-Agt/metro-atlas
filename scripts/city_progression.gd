class_name CityProgression
extends RefCounted

## Deterministic local campaign data. Demand modifiers are explicitly game settings.
const REPEAT_WEEK_MINUTES := 10080
const STAGES := [
	{"id":"neighborhood", "title":"周边扩建", "kind":"flow", "description":"补上这片居住区到附近目的地的完整出行。", "why":"比较站位和设站密度：覆盖变广可能增加停站时间。", "action":"接通后，让这组出行至少有一批乘客实际到达。"},
	{"id":"destination", "title":"重要目的地", "kind":"flow", "description":"把主要居住片区接入重要目的地或交通枢纽。", "why":"延长既有线、少停站或另建接驳线都可以，按完整旅程比较。", "action":"接通后，观察该需求组的实际到达。"},
	{"id":"transfer", "title":"换乘网络", "kind":"transfer", "description":"规划第二条走廊，并让一组实际出行通过两条运营线路。", "why":"相邻站体或轨道交叉不算换乘；两条已开通线路要停靠同一车站。", "action":"只有实际乘坐两条线路并到达，才计入成果。"},
	{"id":"peak", "title":"高峰优化", "kind":"operations", "description":"检查真实等待或拥挤；若没有明显瓶颈，就记录当前服务状态。", "why":"调短班距、补充有效路径或扩展线路；停运或让乘客放弃不算改善。", "action":"真实瓶颈改善并稳定观察一小时，或确认暂时没有明显问题。"}
]

const CITY_CONFIG := {
	"shanghai": {
		"flows": ["shanghai-tutorial-jingui>shanghai-d10", "shanghai-tutorial-jingui>shanghai-d22"],
		"events": [
			{"id":"housing_move_in", "kind":"permanent", "title":"金桂小区新住户入住", "pointId":"shanghai-tutorial-jingui", "announceOffset":120, "startOffset":180, "multiplier":1.30, "description":"金桂小区新增住户，游戏设定的相关出行需求增加。"},
			{"id":"job_expansion", "kind":"permanent", "title":"阳光科技广场扩招", "pointId":"shanghai-d6", "announceOffset":840, "startOffset":900, "multiplier":1.25, "description":"阳光科技广场就业需求增长，相关通勤需求增加。"},
			{"id":"yu_garden_festival", "kind":"temporary", "title":"豫园周末活动", "pointId":"shanghai-d25", "announceOffset":1500, "startOffset":1560, "duration":180, "repeat":REPEAT_WEEK_MINUTES, "multiplier":1.8, "description":"豫园临时活动带来额外客流，持续 3 个游戏小时，每 7 天按固定日程举办。"}
		]
	},
	"beijing": {
		"flows": ["beijing-d5>beijing-d10", "beijing-d5>beijing-d23"],
		"events": [
			{"id":"housing_move_in", "kind":"permanent", "title":"玲珑花园新住户入住", "pointId":"beijing-d5", "announceOffset":120, "startOffset":180, "multiplier":1.30, "description":"玲珑花园新增住户，游戏设定的相关出行需求增加。"},
			{"id":"job_expansion", "kind":"permanent", "title":"中国联通办公区扩招", "pointId":"beijing-d8", "announceOffset":840, "startOffset":900, "multiplier":1.25, "description":"中国联通办公区就业需求增长，相关通勤需求增加。"},
			{"id":"forbidden_city_event", "kind":"temporary", "title":"故宫特别开放日", "pointId":"beijing-d24", "announceOffset":1500, "startOffset":1560, "duration":180, "repeat":REPEAT_WEEK_MINUTES, "multiplier":1.8, "description":"故宫临时活动带来额外客流，持续 3 个游戏小时，每 7 天按固定日程举办。"}
		]
	},
	"guangzhou": {
		"flows": ["guangzhou-tutorial-zhongshan-housing>guangzhou-d10", "guangzhou-tutorial-zhongshan-housing>guangzhou-d22"],
		"events": [
			{"id":"housing_move_in", "kind":"permanent", "title":"中山四路住宅楼入住", "pointId":"guangzhou-tutorial-zhongshan-housing", "announceOffset":120, "startOffset":180, "multiplier":1.30, "description":"中山四路住宅楼新增住户，游戏设定的相关出行需求增加。"},
			{"id":"job_expansion", "kind":"permanent", "title":"手域互联网科技扩招", "pointId":"guangzhou-d6", "announceOffset":840, "startOffset":900, "multiplier":1.25, "description":"手域互联网科技就业需求增长，相关通勤需求增加。"},
			{"id":"chimelong_event", "kind":"temporary", "title":"长隆主题活动日", "pointId":"guangzhou-d24", "announceOffset":1500, "startOffset":1560, "duration":180, "repeat":REPEAT_WEEK_MINUTES, "multiplier":1.8, "description":"长隆临时活动带来额外客流，持续 3 个游戏小时，每 7 天按固定日程举办。"}
		]
	},
	"shenzhen": {
		"flows": ["shenzhen-tutorial-xililantian>shenzhen-d5", "shenzhen-tutorial-xililantian>shenzhen-d23"],
		"events": [
			{"id":"housing_move_in", "kind":"permanent", "title":"西丽蓝天新住户入住", "pointId":"shenzhen-tutorial-xililantian", "announceOffset":120, "startOffset":180, "multiplier":1.30, "description":"西丽蓝天新增住户，游戏设定的相关出行需求增加。"},
			{"id":"job_expansion", "kind":"permanent", "title":"软件产业基地扩招", "pointId":"shenzhen-d5", "announceOffset":840, "startOffset":900, "multiplier":1.25, "description":"软件产业基地就业需求增长，相关通勤需求增加。"},
			{"id":"happy_coast_event", "kind":"temporary", "title":"欢乐海岸主题活动", "pointId":"shenzhen-d7", "announceOffset":1500, "startOffset":1560, "duration":180, "repeat":REPEAT_WEEK_MINUTES, "multiplier":1.8, "description":"欢乐海岸临时活动带来额外客流，持续 3 个游戏小时，每 7 天按固定日程举办。"}
		]
	},
	"chengdu": {
		"flows": ["chengdu-tutorial-yulinmingju>chengdu-d5", "chengdu-tutorial-yulinmingju>chengdu-d18"],
		"events": [
			{"id":"housing_move_in", "kind":"permanent", "title":"玉林名居新住户入住", "pointId":"chengdu-tutorial-yulinmingju", "announceOffset":120, "startOffset":180, "multiplier":1.30, "description":"玉林名居新增住户，游戏设定的相关出行需求增加。"},
			{"id":"job_expansion", "kind":"permanent", "title":"金融城就业增长", "pointId":"chengdu-d3", "announceOffset":840, "startOffset":900, "multiplier":1.25, "description":"金融城就业需求增长，相关通勤需求增加。"},
			{"id":"chunxi_event", "kind":"temporary", "title":"春熙路周末活动", "pointId":"chengdu-d5", "announceOffset":1500, "startOffset":1560, "duration":180, "repeat":REPEAT_WEEK_MINUTES, "multiplier":1.8, "description":"春熙路临时活动带来额外客流，持续 3 个游戏小时，每 7 天按固定日程举办。"}
		]
	}
}

static func config(city_id: String) -> Dictionary:
	return CITY_CONFIG.get(city_id, CITY_CONFIG["shanghai"]).duplicate(true)

static func stages() -> Array:
	return STAGES.duplicate(true)

static func create_state(city_id: String) -> Dictionary:
	return {"version":1, "cityId":city_id, "started":false, "baseMinute":-1, "chapterIndex":0, "stageStartedMinute":-1, "baselineCompleted":0, "baselineCompletedByFlow":{}, "baselineTripMinutesByFlow":{}, "operationBaseline":{}, "announcedOccurrences":[], "permanentApplied":[], "activeTemporary":{}, "finishedOccurrences":[], "eventHistory":[], "completedStages":[], "lastEventMessage":""}

static func start(world: Dictionary, absolute_minute: int) -> void:
	var progression: Dictionary = world.get("cityProgression", create_state(str(world.get("cityId", "shanghai"))))
	if bool(progression.get("started", false)):
		world["cityProgression"] = progression
		return
	progression["started"] = true
	progression["baseMinute"] = absolute_minute
	progression["stageStartedMinute"] = absolute_minute
	progression["baselineCompleted"] = int(world.get("simulation", {}).get("completed", 0))
	progression["baselineCompletedByFlow"] = (world.get("simulation", {}).get("completedByFlow", {}) as Dictionary).duplicate(true)
	progression["baselineTripMinutesByFlow"] = (world.get("simulation", {}).get("tripMinutesByFlow", {}) as Dictionary).duplicate(true)
	world["cityProgression"] = progression

static func events_for_city(city_id: String) -> Array:
	return config(city_id).get("events", [])

static func validate_city(city_id: String, city_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var by_id: Dictionary = {}
	for point in city_data.get("demand", []): by_id[str(point.get("id", ""))] = point
	var cfg := config(city_id)
	for flow_id in cfg.get("flows", []):
		var parts := str(flow_id).split(">")
		if parts.size() != 2 or not by_id.has(parts[0]) or not by_id.has(parts[1]):
			errors.append("%s 的章节需求引用缺失：%s" % [city_id, flow_id])
			continue
		if not bool(by_id[parts[0]].get("verified", false)) or not bool(by_id[parts[1]].get("verified", false)):
			errors.append("%s 的章节目标含未核验地点：%s" % [city_id, flow_id])
	for event in cfg.get("events", []):
		var point_id := str(event.get("pointId", ""))
		if not by_id.has(point_id): errors.append("%s 的事件地点缺失：%s" % [city_id, point_id])
		elif not bool(by_id[point_id].get("verified", false)): errors.append("%s 的事件地点未核验：%s" % [city_id, point_id])
	return errors

static func advance_events(world: Dictionary, absolute_minute: int) -> Array[Dictionary]:
	var progression: Dictionary = world.get("cityProgression", create_state(str(world.get("cityId", "shanghai"))))
	if not bool(progression.get("started", false)):
		world["cityProgression"] = progression
		return []
	var base := int(progression.get("baseMinute", absolute_minute))
	var offset := absolute_minute - base
	var cfg := config(str(world.get("cityId", "shanghai")))
	var announced: Array = progression.get("announcedOccurrences", [])
	var permanent: Array = progression.get("permanentApplied", [])
	var active_temporary: Dictionary = progression.get("activeTemporary", {})
	var finished: Array = progression.get("finishedOccurrences", [])
	var history: Array = progression.get("eventHistory", [])
	var messages: Array[Dictionary] = []
	for raw_event in cfg.get("events", []):
		var event: Dictionary = raw_event
		var event_id := str(event.get("id", ""))
		if str(event.get("kind", "")) == "permanent":
			var key := event_id + "|0"
			if offset >= int(event.get("announceOffset", 0)) and not announced.has(key):
				announced.append(key)
				messages.append({"kind":"announcement", "eventId":event_id, "title":str(event.get("title", "城市变化")), "message":str(event.get("description", "")), "startsIn":maxi(0, int(event.get("startOffset", 0)) - offset)})
			if offset >= int(event.get("startOffset", 0)) and not permanent.has(event_id):
				permanent.append(event_id)
				history.append({"eventId":event_id, "occurrence":0, "status":"started", "minute":absolute_minute, "title":str(event.get("title", "城市变化"))})
				messages.append({"kind":"started", "eventId":event_id, "title":str(event.get("title", "城市变化")), "message":str(event.get("description", ""))})
		else:
			var first_start := int(event.get("startOffset", 0))
			var repeat_minutes := maxi(1, int(event.get("repeat", REPEAT_WEEK_MINUTES)))
			var duration := maxi(1, int(event.get("duration", 180)))
			var occurrence := floori(float(offset - first_start) / float(repeat_minutes)) if offset >= first_start else 0
			var occurrence_start := first_start + occurrence * repeat_minutes
			# Once this event has ended, announce the next fixed occurrence during
			# its lead-in window, before its actual start minute.
			if offset >= occurrence_start + duration:
				occurrence += 1
				occurrence_start += repeat_minutes
			var start_at := occurrence_start
			var key := "%s|%d" % [event_id, occurrence]
			var announce_at := start_at - (int(event.get("startOffset", 0)) - int(event.get("announceOffset", 0)))
			if offset >= announce_at and not announced.has(key):
				announced.append(key)
				messages.append({"kind":"announcement", "eventId":event_id, "title":str(event.get("title", "城市活动")), "message":str(event.get("description", "")), "startsIn":maxi(0, start_at - offset)})
			if offset >= start_at and offset < start_at + duration and not active_temporary.has(event_id):
				active_temporary[event_id] = {"occurrence":occurrence, "endMinute":base + start_at + duration}
				history.append({"eventId":event_id, "occurrence":occurrence, "status":"started", "minute":absolute_minute, "title":str(event.get("title", "城市活动"))})
				messages.append({"kind":"started", "eventId":event_id, "title":str(event.get("title", "城市活动")), "message":str(event.get("description", ""))})
			if active_temporary.has(event_id) and absolute_minute >= int(active_temporary[event_id].get("endMinute", absolute_minute + 1)):
				var active_record: Dictionary = active_temporary[event_id]
				var finished_key := "%s|%d" % [event_id, int(active_record.get("occurrence", 0))]
				active_temporary.erase(event_id)
				if not finished.has(finished_key):
					finished.append(finished_key)
					history.append({"eventId":event_id, "occurrence":int(active_record.get("occurrence", 0)), "status":"ended", "minute":absolute_minute, "title":str(event.get("title", "城市活动"))})
					messages.append({"kind":"ended", "eventId":event_id, "title":str(event.get("title", "城市活动")), "message":"活动客流已结束。"})
	while announced.size() > 100: announced.pop_front()
	while finished.size() > 100: finished.pop_front()
	while history.size() > 100: history.pop_front()
	progression["announcedOccurrences"] = announced
	progression["permanentApplied"] = permanent
	progression["activeTemporary"] = active_temporary
	progression["finishedOccurrences"] = finished
	progression["eventHistory"] = history
	progression["lastEventMessage"] = str(messages.back().get("message", "")) if not messages.is_empty() else str(progression.get("lastEventMessage", ""))
	world["cityProgression"] = progression
	return messages

static func active_event_ids(world: Dictionary) -> Array[String]:
	var progression: Dictionary = world.get("cityProgression", {})
	var ids: Array[String] = []
	for raw_id in progression.get("permanentApplied", []): ids.append(str(raw_id))
	for raw_id in progression.get("activeTemporary", {}).keys(): ids.append(str(raw_id))
	ids.sort()
	return ids

static func event_signature(world: Dictionary) -> String:
	return ",".join(active_event_ids(world))

static func multiplier_for_flow(world: Dictionary, flow: Dictionary) -> float:
	var point_ids := [str(flow.get("fromId", "")), str(flow.get("toId", ""))]
	var active := active_event_ids(world)
	var multiplier := 1.0
	for event in events_for_city(str(world.get("cityId", "shanghai"))):
		if not active.has(str(event.get("id", ""))): continue
		if point_ids.has(str(event.get("pointId", ""))): multiplier *= float(event.get("multiplier", 1.0))
	return multiplier

static func next_event(world: Dictionary, absolute_minute: int) -> Dictionary:
	var progression: Dictionary = world.get("cityProgression", {})
	if not bool(progression.get("started", false)): return {}
	var base := int(progression.get("baseMinute", absolute_minute))
	var best: Dictionary = {}
	var best_minute := 2147483647
	var offset := absolute_minute - base
	for event in events_for_city(str(world.get("cityId", "shanghai"))):
		var event_id := str(event.get("id", ""))
		var start_at := int(event.get("startOffset", 0))
		if str(event.get("kind", "")) == "temporary" and offset >= start_at:
			var repeat_minutes := maxi(1, int(event.get("repeat", REPEAT_WEEK_MINUTES)))
			start_at += (floori(float(offset - start_at) / float(repeat_minutes)) + 1) * repeat_minutes
		elif str(event.get("kind", "")) == "permanent" and progression.get("permanentApplied", []).has(event_id):
			continue
		var announce_at := start_at - maxi(0, int(event.get("startOffset", 0)) - int(event.get("announceOffset", 0)))
		var announce_minute := base + announce_at
		var absolute_start := base + start_at
		var candidate_minute := announce_minute if absolute_minute < announce_minute else absolute_start
		if candidate_minute >= absolute_minute and candidate_minute < best_minute:
			best_minute = candidate_minute
			best = event.duplicate(true)
			best["startMinute"] = absolute_start
			best["announceMinute"] = announce_minute
	return best

static func compare_flow_windows(world: Dictionary, flow_id: String, current_minute: int, window_minutes: int = 60) -> Dictionary:
	var sim: Dictionary = world.get("simulation", {})
	var buckets: Array = sim.get("statisticsBuckets", [])
	var bucket_width := 15
	var bucket_count := maxi(1, ceili(float(window_minutes) / float(bucket_width)))
	# The bucket at current_minute may have just started. Compare only complete
	# 15-minute buckets, ending with the most recently completed one.
	var current_end := floori(float(current_minute) / float(bucket_width)) * bucket_width - bucket_width
	var current_start := current_end - (bucket_count - 1) * bucket_width
	var previous_start := current_start - 1440
	if previous_start < 0:
		return {"available":false, "label":"暂无同一日内时段的先前样本；事件变化已单独记录，不与本时段混比。"}
	var before := _aggregate_window(buckets, flow_id, previous_start, bucket_count)
	var after := _aggregate_window(buckets, flow_id, current_start, bucket_count)
	if not bool(before.get("available", false)) or not bool(after.get("available", false)):
		return {"available":false, "label":"同一时段的可比样本尚不足；这里仅显示当前实际结果。"}
	if str(before.get("eventSignature", "")) != str(after.get("eventSignature", "")):
		return {"available":false, "label":"前后时段的城市事件状态不同，暂不归因比较；需求变化已独立记录。"}
	var before_attempted := int(before.get("attempted", 0))
	var after_attempted := int(after.get("attempted", 0))
	var before_completed := int(before.get("completed", 0))
	var after_completed := int(after.get("completed", 0))
	var before_minutes := float(before.get("tripMinutes", 0.0)) / maxf(1.0, float(before_completed))
	var after_minutes := float(after.get("tripMinutes", 0.0)) / maxf(1.0, float(after_completed))
	var label := "昨日同一时段对照（同需求组、同城市事件状态）：完成 %d → %d 人次，发起 %d → %d 人次" % [before_completed, after_completed, before_attempted, after_attempted]
	if before_completed > 0 and after_completed > 0:
		label += "；平均完整出行 %.1f → %.1f 分钟" % [before_minutes, after_minutes]
	else:
		label += "；至少一侧没有实际到达样本，不比较平均耗时"
	return {"available":true, "label":label, "before":before, "current":after, "sameEventState":true}

static func _aggregate_window(buckets: Array, flow_id: String, first_start: int, count: int) -> Dictionary:
	var bucket_by_start: Dictionary = {}
	for bucket in buckets:
		if bucket is Dictionary: bucket_by_start[int(bucket.get("startMinute", -1))] = bucket
	var aggregate := {"available":false, "attempted":0, "completed":0, "tripMinutes":0.0, "eventSignature":"", "buckets":0}
	var signature := ""
	for index in range(count):
		var start := first_start + index * 15
		if not bucket_by_start.has(start): return aggregate
		var bucket: Dictionary = bucket_by_start[start]
		if bool(bucket.get("mixedEventState", false)): return aggregate
		var bucket_signature := str(bucket.get("eventSignature", ""))
		if index == 0: signature = bucket_signature
		elif bucket_signature != signature: return aggregate
		aggregate["attempted"] = int(aggregate.attempted) + int(bucket.get("attemptedByFlow", {}).get(flow_id, 0))
		aggregate["completed"] = int(aggregate.completed) + int(bucket.get("completedByFlow", {}).get(flow_id, 0))
		aggregate["tripMinutes"] = float(aggregate.tripMinutes) + float(bucket.get("tripMinutesByFlow", {}).get(flow_id, 0.0))
		aggregate["buckets"] = index + 1
	aggregate["eventSignature"] = signature
	aggregate["available"] = true
	return aggregate

static func current_stage(world: Dictionary) -> Dictionary:
	var stages_data := stages()
	var index := clampi(int(world.get("cityProgression", {}).get("chapterIndex", 0)), 0, stages_data.size())
	return {} if index >= stages_data.size() else stages_data[index]

static func update_stage(world: Dictionary, flows: Array[Dictionary], absolute_minute: int) -> Dictionary:
	var progression: Dictionary = world.get("cityProgression", create_state(str(world.get("cityId", "shanghai"))))
	if not bool(progression.get("started", false)):
		world["cityProgression"] = progression
		return {"changed":false}
	var stages_data := stages()
	var index := int(progression.get("chapterIndex", 0))
	if index >= stages_data.size(): return {"changed":false}
	var stage: Dictionary = stages_data[index]
	var sim: Dictionary = world.get("simulation", {})
	var completed_by_flow: Dictionary = sim.get("completedByFlow", {})
	var completed := false
	var result := {"stageId":str(stage.get("id", "")), "title":str(stage.get("title", "")), "recordedAt":absolute_minute}
	match str(stage.get("kind", "")):
		"flow":
			var cfg := config(str(world.get("cityId", "shanghai")))
			var flow_index := 0 if index == 0 else 1
			var configured_flows: Array = cfg.get("flows", [])
			var flow_id := str(configured_flows[flow_index]) if configured_flows.size() > flow_index else ""
			var flow := _find_flow(flows, flow_id)
			var baseline := int(progression.get("baselineCompletedByFlow", {}).get(flow_id, 0))
			if bool(flow.get("valid", false)) and int(completed_by_flow.get(flow_id, 0)) > baseline:
				completed = true
				result["flowId"] = flow_id
				result["completed"] = int(completed_by_flow.get(flow_id, 0)) - baseline
				result["expectedPeoplePerDay"] = float(flow.get("peoplePerDay", 0.0))
				var minutes_now := float(sim.get("tripMinutesByFlow", {}).get(flow_id, 0.0))
				var minutes_before := float(progression.get("baselineTripMinutesByFlow", {}).get(flow_id, 0.0))
				result["actualAverageMinutes"] = maxf(0.0, minutes_now - minutes_before) / maxf(1.0, float(result["completed"]))
		"transfer":
			var baseline_map: Dictionary = progression.get("baselineCompletedByFlow", {})
			var best: Dictionary = {}
			for flow in flows:
				var flow_id := str(flow.get("id", ""))
				if not bool(flow.get("valid", false)) or flow.get("routeIds", []).size() < 2: continue
				if int(completed_by_flow.get(flow_id, 0)) <= int(baseline_map.get(flow_id, 0)): continue
				best = flow
				break
			if not best.is_empty():
				completed = true
				result["flowId"] = str(best.get("id", ""))
				result["routes"] = best.get("routeIds", []).duplicate()
				result["completed"] = int(completed_by_flow.get(str(best.id), 0)) - int(baseline_map.get(str(best.id), 0))
		"operations":
			var elapsed := absolute_minute - int(progression.get("stageStartedMinute", absolute_minute))
			var current_wait := 0
			var current_route := ""
			for route_id in sim.get("waitingByRoute", {}):
				var route := WorldData.find_route(world, str(route_id))
				if not bool(route.get("open", false)): continue
				if int(sim.waitingByRoute[route_id]) > current_wait:
					current_wait = int(sim.waitingByRoute[route_id]); current_route = str(route_id)
			var crowding := float(sim.get("peakCrowding", 0.0))
			var has_issue := current_wait >= 10 or crowding >= 0.85
			var baseline_operation: Dictionary = progression.get("operationBaseline", {})
			if has_issue and baseline_operation.is_empty():
				baseline_operation = {"waiting":current_wait, "crowding":crowding, "routeId":current_route, "startedAt":absolute_minute, "attempted":int(sim.get("attempted", 0)), "completed":int(sim.get("completed", 0)), "abandoned":int(sim.get("abandoned", 0)), "stableSince":-1}
				progression["operationBaseline"] = baseline_operation
			elif not baseline_operation.is_empty():
				var baseline_route := WorldData.find_route(world, str(baseline_operation.get("routeId", "")))
				var adequate_demand := int(sim.get("attempted", 0)) > int(baseline_operation.get("attempted", 0)) and int(sim.get("completed", 0)) > int(baseline_operation.get("completed", 0)) and bool(baseline_route.get("open", false))
				var improved := adequate_demand and (current_wait <= int(floor(float(baseline_operation.get("waiting", current_wait)) * 0.75)) or crowding <= float(baseline_operation.get("crowding", crowding)) * 0.75)
				if improved and int(baseline_operation.get("stableSince", -1)) < 0: baseline_operation["stableSince"] = absolute_minute
				elif not improved: baseline_operation["stableSince"] = -1
				if improved and absolute_minute - int(baseline_operation.get("stableSince", absolute_minute)) >= 60:
					completed = true
					result["improvement"] = true
					result["beforeWaiting"] = int(baseline_operation.get("waiting", 0))
					result["afterWaiting"] = current_wait
					result["routeId"] = str(baseline_operation.get("routeId", ""))
				progression["operationBaseline"] = baseline_operation
			elif not has_issue and elapsed >= 60:
				completed = true
				result["noCriticalIssue"] = true
				result["note"] = "观察期间没有持续排队或明显拥挤。"
	if not completed:
		world["cityProgression"] = progression
		return {"changed":false}
	var completed_stages: Array = progression.get("completedStages", [])
	completed_stages.append(result)
	while completed_stages.size() > 30: completed_stages.pop_front()
	progression["completedStages"] = completed_stages
	progression["chapterIndex"] = index + 1
	progression["stageStartedMinute"] = absolute_minute
	progression["baselineCompleted"] = int(sim.get("completed", 0))
	progression["baselineCompletedByFlow"] = completed_by_flow.duplicate(true)
	progression["baselineTripMinutesByFlow"] = (sim.get("tripMinutesByFlow", {}) as Dictionary).duplicate(true)
	progression["operationBaseline"] = {}
	world["cityProgression"] = progression
	return {"changed":true, "result":result, "finished":index + 1 >= stages_data.size(), "nextStage":current_stage(world)}

static func optional_goals(world: Dictionary, flows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var board: Dictionary = world.get("goalBoard", {})
	for goal in board.get("active", []):
		if str(goal.get("type", "")) == "operations": result.append(goal)
		elif result.size() < 2 and str(goal.get("type", "")) == "coverage": result.append(goal)
		if result.size() >= 2: break
	if result.size() >= 2: return result
	for flow in flows:
		if bool(flow.get("valid", false)): continue
		var id := str(flow.get("id", ""))
		if id.is_empty(): continue
		var already := false
		for item in result:
			if str(item.get("flowId", "")) == id: already = true
		if already: continue
		result.append({"id":"commission|" + id, "type":"coverage", "flowId":id, "title":"补上%s → %s" % [flow.get("from", "附近街区"), flow.get("to", "目的地")], "status":"build", "peoplePerDay":float(flow.get("peoplePerDay", 0.0))})
		if result.size() >= 2: break
	return result

static func _find_flow(flows: Array[Dictionary], flow_id: String) -> Dictionary:
	for flow in flows:
		if str(flow.get("id", "")) == flow_id: return flow
	return {}
