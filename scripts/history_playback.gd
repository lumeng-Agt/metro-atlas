class_name HistoryPlayback
extends RefCounted

## Read-only reconstruction. Unconfirmed current construction is never a seed.
static func build(source: Dictionary) -> Dictionary:
	var milestones: Array = source.get("storyState", {}).get("milestones", [])
	var seed: Dictionary = source.get("milestoneBaseline", {}).duplicate(true)
	var frames: Array[Dictionary] = []
	var warning := ""
	if seed.is_empty() or milestones.is_empty():
		return {"frames": frames, "warning": "暂无可回放的已确认通车里程碑。"}
	var next_dates := {"history":"9999-99-99","future":"9999-99-99"}
	var future_ids:={}
	for plan in CampaignSystem.city_config(str(source.get("cityId",""))).get("futurePlans",[]):future_ids[str(plan.get("id",""))]=true
	for index in range(milestones.size()-1, -1, -1):
		var milestone: Dictionary = milestones[index]
		var date := str(milestone.get("date", ""))
		var planning:=str(milestone.get("phase","history"))=="future" or future_ids.has(str(milestone.get("chapterId",""))) or date > "2026-10-01"
		var lane:="future" if planning else "history"
		if date > str(next_dates[lane]):
			warning = "早期记录存在结构修订，仅回放后续连续里程碑。"
			break
		var diff: Dictionary = milestone.get("planningDiff", {})
		if not _matches(seed, diff):
			warning = "更早记录缺少差量数据，回放将从首个完整节点开始。"
			break
		var state := seed.duplicate(true)
		state.merge({"cityId": source.get("cityId", ""), "mode": "work", "revision": index+1}, true)
		frames.push_front({"date": date, "title": milestone.get("title", "历史节点"), "source": milestone.get("source", ""), "chapterId": milestone.get("chapterId", ""), "world": state, "planning": planning})
		var history := CommandHistory.new()
		history.attach(seed)
		history._apply_diff(diff, false)
		next_dates[lane] = date
	return {"frames": frames, "initialWorld":seed.duplicate(true), "warning": warning, "cityId": source.get("cityId", ""), "cityName": source.get("cityName", "")}

static func _matches(state: Dictionary, diff: Dictionary) -> bool:
	if not diff.get("fields", {}) is Dictionary: return false
	for key in diff.get("fields", {}):
		if not CommandHistory.PLANNING_KEYS.has(key): return false
		var change: Dictionary = diff.fields[key]
		if str(change.get("type", "")) == "identified_array":
			var by_id := {}
			var order:Array=[]
			for item in state.get(key, []):
				by_id[str(item.get("id", ""))] = item;order.append(str(item.get("id","")))
			if order!=change.get("afterOrder",[]):return false
			for id in change.get("items", {}):
				if by_id.get(str(id)) != change.items[id].get("after"): return false
		else:
			if state.get(key) != change.get("after"): return false
	return true

static func frame_index(seconds: float, duration: float, count: int) -> int:
	return clampi(int(floor(maxf(seconds, 0.0) / maxf(duration, 0.001) * count)), 0, maxi(0, count-1))
