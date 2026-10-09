class_name CommandHistory
extends RefCounted

signal changed

var world: Dictionary
var max_steps := 200

func attach(state: Dictionary) -> void:
	world = state
	if not world.has("history"): world.history = {"undo": [], "redo": []}

func execute(label: String, mutation: Callable) -> bool:
	if world.is_empty(): return false
	var before: Dictionary = _capture_planning()
	mutation.call(world)
	if _planning_equal(before, world): return false
	var history: Dictionary = world.history
	var undo: Array = history.get("undo", [])
	undo.append({"label": label, "snapshot": before})
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
	redo_items.append({"label": step.get("label", "规划修改"), "snapshot": _capture_planning()})
	h["redo"] = redo_items
	h["undo"] = undo_items
	world["history"] = h
	_restore_planning(step.get("snapshot", {}))
	world["revision"] = int(world.get("revision", 0)) + 1
	changed.emit()
	return str(step.get("label", "规划修改"))

func redo() -> String:
	var h: Dictionary = world.get("history", {})
	var redo_items: Array = h.get("redo", [])
	if redo_items.is_empty(): return ""
	var step: Dictionary = redo_items.pop_back()
	var undo_items: Array = h.get("undo", [])
	undo_items.append({"label": step.get("label", "规划修改"), "snapshot": _capture_planning()})
	while undo_items.size() > max_steps: undo_items.pop_front()
	h["undo"] = undo_items
	h["redo"] = redo_items
	world["history"] = h
	_restore_planning(step.get("snapshot", {}))
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
	for key in ["stations", "routes", "trackLinks", "depots", "fleetMode"]:
		if JSON.stringify(before.get(key)) != JSON.stringify(after.get(key)): return false
	return true

func _capture_planning() -> Dictionary:
	var snapshot := {}
	for key in ["stations", "routes", "trackLinks", "depots", "fleetMode"]:
		snapshot[key] = world.get(key, []).duplicate(true) if world.get(key) is Array else world.get(key)
	return snapshot

func _restore_planning(snapshot: Dictionary) -> void:
	for key in ["stations", "routes", "trackLinks", "depots", "fleetMode"]:
		if snapshot.has(key): world[key] = snapshot[key].duplicate(true) if snapshot[key] is Array else snapshot[key]
