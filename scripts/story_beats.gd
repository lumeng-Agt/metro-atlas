class_name StoryBeats
extends RefCounted

const Story = preload("res://scripts/story_session.gd")

static func entries(world: Dictionary) -> Array:
	return Story.chapter(world).get("story", {}).get("beats", [])

static func find(world: Dictionary, id: String) -> Dictionary:
	for beat in entries(world):
		if str(beat.id) == id: return beat
	return {}

static func eligible(world: Dictionary, event: String, historical_ids: Array) -> Dictionary:
	if str(world.get("mode", "")) != "campaign" or str(world.get("storyState", {}).get("stage", "intro")) != "build": return {}
	var read: Dictionary = world.storyState.get("beatRead", {})
	for beat in entries(world):
		if read.has(str(beat.id)) or not beat.get("triggers", []).has(event): continue
		if int(world.get("storyPlan", {}).get("planIndex", 0)) < int(beat.get("minimumPlanIndex", 0)): continue
		if beat.get("stationIds", []).any(func(id: String): return historical_ids.has(id)): return beat
	return {}

static func mark_read(world: Dictionary, id: String) -> void:
	if find(world, id).is_empty(): return
	if not world.storyState.has("beatRead"): world.storyState["beatRead"] = {}
	world.storyState.beatRead[id] = true

static func markers(world: Dictionary) -> Array:
	var result: Array = []
	for beat in entries(world):
		if beat.get("stationIds", []).is_empty(): continue
		for target in Story.targets(world, true):
			if str(target.id) == str(beat.stationIds[0]):
				result.append({"id":str(beat.id),"latlng":target.latlng,"title":str(beat.title),"read":world.storyState.get("beatRead", {}).has(str(beat.id))});break
	return result
