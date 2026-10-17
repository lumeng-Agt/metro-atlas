class_name StoryTutorial
extends RefCounted

## Operation teaching is scoped to the first chapter, never to every story.
static func is_first(world: Dictionary) -> bool:
	if str(world.get("mode", "")) != "campaign": return false
	var first_id:=CampaignSystem.first_chapter_id(str(world.get("cityId", "")))
	if first_id.is_empty(): return false
	var state: Dictionary = world.get("storyState", {})
	return str(state.get("phase", "history")) == "history" and (str(state.get("chapterId", "")) == first_id or (str(state.get("chapterId", "")).is_empty() and int(state.get("chapterIndex", 0)) == 0))

static func active(world: Dictionary) -> bool:
	var state:Dictionary=world.get("storyState",{})
	return bool(state.get("tutorialEnabled", false)) and str(state.get("tutorialStatus", "active")) == "active" and str(state.get("stage", "")) != "outcome" and is_first(world)

static func configure(world: Dictionary, enabled: bool) -> void:
	world.storyState["tutorialEnabled"] = enabled and is_first(world)
	world.storyState["tutorialStatus"] = "active" if enabled and is_first(world) else "skipped"
	world.storyState["learnedTools"] = not enabled

static func finish(world: Dictionary) -> bool:
	if not active(world): return false
	world.storyState["tutorialEnabled"] = false
	world.storyState["tutorialStatus"] = "completed"
	world.storyState["learnedTools"] = true
	return true

static func skip(world: Dictionary) -> void:
	world.storyState["tutorialEnabled"] = false
	world.storyState["tutorialStatus"] = "skipped"
	world.storyState["learnedTools"] = true
