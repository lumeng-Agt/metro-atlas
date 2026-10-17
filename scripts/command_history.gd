class_name CommandHistory
extends RefCounted

signal changed

var world: Dictionary
var max_steps := 200
const PLANNING_KEYS := ["stations", "routes", "trackLinks", "trackNodes", "trackEdges", "depots", "fleetMode", "planningPhases", "currentPlanningPhaseId", "storyPlan"]

func attach(state: Dictionary) -> void:
	world = state
	if not world.has("history"): world.history = {"undo": [], "redo": []}

func execute(label: String, mutation: Callable, affected_fields: Array = []) -> bool:
	if world.is_empty(): return false
	var before := _capture_planning(affected_fields)
	mutation.call(world)
	if _planning_equal(before, world): return false
	var after := _capture_planning(affected_fields)
	var step := {"label": label, "diff": _build_diff(before, after)}
	var history: Dictionary = world.history
	var undo: Array = history.get("undo", [])
	undo.append(step)
	while undo.size() > max_steps: undo.pop_front()
	history["undo"] = undo
	history["redo"] = []
	world["revision"] = int(world.get("revision", 0)) + 1
	changed.emit()
	return true

func undo() -> String:
	var h: Dictionary = world.get("history", {})
	var undo_items: Array = h.get("undo", [])
	if undo_items.is_empty(): return ""
	var step: Dictionary = undo_items.pop_back()
	var redo_items: Array = h.get("redo", [])
	if step.has("diff"):
		redo_items.append(step.duplicate(true))
		_apply_diff(step.diff, false)
	else:
		# Legacy full snapshots remain usable until their history is migrated.
		redo_items.append({"label": step.get("label", "规划修改"), "snapshot": _capture_planning()})
		_restore_planning(step.get("snapshot", {}))
	h["redo"] = redo_items
	h["undo"] = undo_items
	world["history"] = h
	world["revision"] = int(world.get("revision", 0)) + 1
	changed.emit()
	return str(step.get("label", "规划修改"))

func redo() -> String:
	var h: Dictionary = world.get("history", {})
	var redo_items: Array = h.get("redo", [])
	if redo_items.is_empty(): return ""
	var step: Dictionary = redo_items.pop_back()
	var undo_items: Array = h.get("undo", [])
	if step.has("diff"):
		undo_items.append(step.duplicate(true))
		_apply_diff(step.diff, true)
	else:
		undo_items.append({"label": step.get("label", "规划修改"), "snapshot": _capture_planning()})
		_restore_planning(step.get("snapshot", {}))
	while undo_items.size() > max_steps: undo_items.pop_front()
	h["undo"] = undo_items
	h["redo"] = redo_items
	world["history"] = h
	world["revision"] = int(world.get("revision", 0)) + 1
	changed.emit()
	return str(step.get("label", "规划修改"))

func undo_label() -> String:
	var items: Array = world.get("history", {}).get("undo", [])
	return str(items.back().get("label", "")) if not items.is_empty() else ""

func redo_label() -> String:
	var items: Array = world.get("history", {}).get("redo", [])
	return str(items.back().get("label", "")) if not items.is_empty() else ""

func _planning_equal(before: Dictionary, after: Dictionary) -> bool:
	for key in before:
		if JSON.stringify(before.get(key)) != JSON.stringify(after.get(key)): return false
	return true

func _capture_planning(affected_fields: Array = []) -> Dictionary:
	var snapshot := {}
	for key in (PLANNING_KEYS if affected_fields.is_empty() else affected_fields):
		if not PLANNING_KEYS.has(key): continue
		var value: Variant = world.get(key, [])
		snapshot[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return snapshot

func _build_diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var fields: Dictionary = {}
	for key in PLANNING_KEYS:
		var old_value: Variant = before.get(key)
		var new_value: Variant = after.get(key)
		if old_value is Array and new_value is Array and _has_stable_ids(old_value) and _has_stable_ids(new_value):
			var old_by_id := _array_by_id(old_value)
			var new_by_id := _array_by_id(new_value)
			var item_changes: Dictionary = {}
			var ids: Dictionary = {}
			for id in old_by_id: ids[id] = true
			for id in new_by_id: ids[id] = true
			for id in ids:
				if JSON.stringify(old_by_id.get(id)) == JSON.stringify(new_by_id.get(id)): continue
				item_changes[id] = {"before": old_by_id.get(id), "after": new_by_id.get(id)}
			var old_order := _array_ids(old_value)
			var new_order := _array_ids(new_value)
			if not item_changes.is_empty() or old_order != new_order:
				fields[key] = {"type": "identified_array", "beforeOrder": old_order, "afterOrder": new_order, "items": item_changes}
		elif JSON.stringify(old_value) != JSON.stringify(new_value):
			fields[key] = {"type": "value", "before": old_value, "after": new_value}
	return {"fields": fields}

func _apply_diff(diff: Dictionary, use_after: bool) -> void:
	var fields: Dictionary = diff.get("fields", {})
	for key in fields:
		if not PLANNING_KEYS.has(key): continue
		var change: Dictionary = fields[key]
		if str(change.get("type", "")) != "identified_array":
			var value: Variant = change.get("after") if use_after else change.get("before")
			world[key] = value.duplicate(true) if value is Array or value is Dictionary else value
			continue
		var current: Array = world.get(key, [])
		var by_id := _array_by_id(current)
		var item_changes: Dictionary = change.get("items", {})
		for id in item_changes:
			var item_change: Dictionary = item_changes[id]
			var target: Variant = item_change.get("after") if use_after else item_change.get("before")
			if target == null: by_id.erase(str(id))
			else: by_id[str(id)] = target.duplicate(true)
		var target_order: Array = change.get("afterOrder", []) if use_after else change.get("beforeOrder", [])
		var rebuilt: Array = []
		for id in target_order:
			if by_id.has(str(id)): rebuilt.append(by_id[str(id)])
		for id in by_id:
			if not target_order.has(str(id)): rebuilt.append(by_id[id])
		world[key] = rebuilt

func _has_stable_ids(items: Array) -> bool:
	for item in items:
		if not item is Dictionary or str(item.get("id", "")).is_empty(): return false
	return true

func _array_by_id(items: Array) -> Dictionary:
	var result: Dictionary = {}
	for item in items:
		if item is Dictionary: result[str(item.get("id", ""))] = item
	return result

func _array_ids(items: Array) -> Array[String]:
	var result: Array[String] = []
	for item in items:
		if item is Dictionary: result.append(str(item.get("id", "")))
	return result

func _restore_planning(snapshot: Dictionary) -> void:
	for key in PLANNING_KEYS:
		if snapshot.has(key): world[key] = snapshot[key].duplicate(true) if snapshot[key] is Array or snapshot[key] is Dictionary else snapshot[key]
