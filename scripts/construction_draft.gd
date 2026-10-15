class_name ConstructionDraft
extends RefCounted

var kind := ""
var object_id := ""
var base_revision := -1
var preview: Dictionary = {}
var linked_geometry: Dictionary = {}
var affected_route_ids: Array[String] = []
var issue := ""
var notice := ""
var valid := false

func begin(draft_kind: String, target_id: String, revision: int, value: Dictionary) -> void:
	kind = draft_kind
	object_id = target_id
	base_revision = revision
	preview = value.duplicate(true)
	linked_geometry.clear()
	affected_route_ids.clear()
	issue = ""
	notice = ""
	valid = false

func update(value: Dictionary, linked: Dictionary, problem: String, changed_routes: Array = [], message: String = "") -> void:
	preview = value.duplicate(true)
	linked_geometry = linked.duplicate(true)
	issue = problem
	notice = message
	valid = issue.is_empty()
	affected_route_ids.clear()
	for route_id in changed_routes:
		if not affected_route_ids.has(str(route_id)):
			affected_route_ids.append(str(route_id))

func is_current(revision: int) -> bool:
	return not kind.is_empty() and base_revision == revision

func clear() -> void:
	kind = ""
	object_id = ""
	base_revision = -1
	preview.clear()
	linked_geometry.clear()
	affected_route_ids.clear()
	issue = ""
	notice = ""
	valid = false
