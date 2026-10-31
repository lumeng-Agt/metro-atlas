class_name StorySaveCoordinator
extends Node

## Snapshots are owned by one writer. A later request replaces only the queued
## snapshot, never the running one; every waiting caller receives its outcome.
signal finished
var _thread:Thread
var _active:Dictionary={}
var _pending:Dictionary={}
var _results:Dictionary={}
var _next_ticket:=0
var last_metrics:Dictionary={}

func request(world:Dictionary,change_serial:int) -> int:
	_next_ticket+=1
	var ticket:=_next_ticket
	var started:=Time.get_ticks_usec()
	var snapshot:Dictionary=_capture_checkpoint(world)
	var item:Dictionary={"snapshot":snapshot,"gameId":str(world.get("gameId","")),"changeSerial":change_serial,"revision":int(world.get("revision",0)),"tickets":[ticket],"snapshotMs":(Time.get_ticks_usec()-started)/1000.0}
	if not _pending.is_empty():
		# Sessions can change only after their leaving save completes.
		if str(_pending.gameId)!=str(item.gameId):
			_results[ticket]={"ok":false,"error":"上一局的保存尚未完成。","gameId":item.gameId,"changeSerial":change_serial}
			return ticket
		item.tickets.append_array(_pending.tickets)
	_pending=item
	_start_next()
	return ticket

static func _capture_checkpoint(world:Dictionary) -> Dictionary:
	# Completed milestone records, the baseline and command entries are owned
	# immutable values: confirmation replaces the baseline, history changes list
	# membership, and undo/redo restore deep copies. Copy those outer containers
	# but retain their completed values. Everything currently editable is still
	# copied here, synchronously, before the writer starts. This is a consistent
	# checkpoint, without repeatedly cloning the city's entire history on the UI
	# thread. Archive writers must replace a value, never edit its descendants.
	var snapshot:Dictionary={}
	for key in world:
		var value:Variant=world[key]
		if key=="milestoneBaseline":
			snapshot[key]=value
		elif key=="storyState" and value is Dictionary:
			var state:Dictionary={}
			for field in value:
				var child:Variant=value[field]
				state[field]=child.duplicate(field!="milestones") if child is Array or child is Dictionary else child
			snapshot[key]=state
		elif key=="history" and value is Dictionary:
			var history:Dictionary={}
			for field in value:
				var child:Variant=value[field]
				history[field]=child.duplicate(field not in ["undo","redo"]) if child is Array or child is Dictionary else child
			snapshot[key]=history
		else:
			snapshot[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	return snapshot

func wait_for(ticket:int) -> Dictionary:
	while not _results.has(ticket):await finished
	var result:Dictionary=_results[ticket]
	_results.erase(ticket)
	return result

func _start_next() -> void:
	if not _active.is_empty() or _pending.is_empty():return
	_active=_pending;_pending={}
	_thread=Thread.new()
	var snapshot:Dictionary=_active.snapshot
	var error:=_thread.start(func() -> Dictionary:
		var started:=Time.get_ticks_usec()
		var result:Dictionary=SaveManager.save_world(snapshot)
		result["workerMs"]=(Time.get_ticks_usec()-started)/1000.0
		result["savedAt"]=str(snapshot.get("savedAt",""))
		return result)
	if error!=OK:
		_thread=null
		_finish({"ok":false,"error":"无法启动保存，请重试。"})

func _process(_delta:float) -> void:
	if _thread!=null and not _active.is_empty() and not _thread.is_alive():
		var result:Dictionary=_thread.wait_to_finish()
		_thread=null
		_finish(result)
	_start_next()

func _finish(result:Dictionary) -> void:
	result["gameId"]=_active.gameId
	result["changeSerial"]=_active.changeSerial
	result["revision"]=_active.revision
	result["snapshotMs"]=_active.snapshotMs
	last_metrics=result.duplicate(true)
	for ticket in _active.tickets:_results[int(ticket)]=result.duplicate(true)
	_active={}
	finished.emit()

func _exit_tree() -> void:
	# Normal exits await all requests. Still join a running writer if the host
	# tears down the scene externally, rather than abandoning a temp-file swap.
	if _thread!=null and _thread.is_started():_thread.wait_to_finish()
	if not _pending.is_empty():SaveManager.save_world(_pending.snapshot)
