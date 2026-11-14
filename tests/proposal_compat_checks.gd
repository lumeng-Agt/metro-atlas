extends SceneTree

## A save written before proposals existed, or one whose story state was
## repaired by hand, must still load and still accept a proposal. Nothing here
## may crash on a value of the wrong type.

const Story = preload("res://scripts/story_session.gd")
const App = preload("res://scripts/main.gd")
const Catalog = preload("res://scripts/campaign_system.gd")

var app: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		quit(2)
		return
	WorldData.load_assets()
	app = App.new()
	root.add_child(app)
	await process_frame
	await process_frame
	app._new_game("shenzhen", false)
	while app.saves_in_flight > 0:
		await process_frame

	# A save from before proposals has no key at all.
	_check(not app.world.storyState.has("proposals"), "a fresh save has no proposals key")
	_check(Story.proposal_for(app.world, "any") == {}, "proposal_for tolerates a missing key")
	var no_stage: Dictionary = app.world.duplicate(true)
	no_stage.storyState.erase("stage")
	_check(Story.proposal_for(no_stage, "any") == {}, "proposal_for tolerates a missing stage")

	# A corrupt value is read as empty rather than crashing.
	var corrupt: Dictionary = app.world.duplicate(true)
	corrupt.storyState["proposals"] = "broken"
	_check(Story.proposal_for(corrupt, "any") == {}, "proposal_for tolerates a corrupt proposals value")
	var corrupt_entry: Dictionary = app.world.duplicate(true)
	corrupt_entry.storyState["proposals"] = {"ch": "broken"}
	_check(Story.proposal_for(corrupt_entry, "ch") == {}, "proposal_for tolerates a corrupt chapter entry")

	# Submitting repairs the corrupt value instead of failing on it.
	var plans: Array = Catalog.playable_future_plans("shenzhen")
	app.world.storyState["phase"] = "future"
	app.world.storyState["chapterId"] = str(plans[0].get("id", ""))
	app.world.storyState["stage"] = "intro"
	app._begin_chapter()
	await process_frame
	app.world.storyState["proposals"] = "broken"
	var candidates: Array = app.proposal_candidates
	var submitted := Story.submit_proposal(app.world, [str(candidates[0].get("id", "")), str(candidates[1].get("id", ""))])
	_check(bool(submitted.get("ok", false)), "submitting repairs a corrupt proposals value")
	_check(app.world.storyState["proposals"] is Dictionary, "proposals is a dictionary again")
	_check(str(app.world.storyState.get("stage", "")) == "build", "the repair still opens construction")

	print("PASS: %d save compatibility checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
