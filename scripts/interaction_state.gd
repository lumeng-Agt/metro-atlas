class_name InteractionState
extends RefCounted

var tool := "select"
var phase := "idle"
var selected_type := ""
var selected_id := ""
var snap_candidates: Array[Dictionary] = []
var error_message := ""
var draft: ConstructionDraft

func _init() -> void:
	draft = ConstructionDraft.new()

func set_tool(value: String) -> void:
	if tool == value:
		if value == "select":
			phase = "idle"
			error_message = ""
			snap_candidates.clear()
			draft.clear()
		return
	tool = value
	phase = "idle" if value == "select" else "active"
	error_message = ""
	snap_candidates.clear()
	if value == "select":
		draft.clear()

func select_object(kind: String, object_id: String) -> void:
	selected_type = kind
	selected_id = object_id

func clear_selection() -> void:
	selected_type = ""
	selected_id = ""
