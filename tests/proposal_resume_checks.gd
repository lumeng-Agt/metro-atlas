extends SceneTree

## A player who saves in the middle of drawing a proposal and comes back later
## must land in the same stage, with the same chapter, able to finish.

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
	var plans: Array = Catalog.playable_future_plans("shenzhen")
	var chapter_id := str(plans[0].get("id", ""))
	app.world.storyState["phase"] = "future"
	app.world.storyState["chapterId"] = chapter_id
	app.world.storyState["stage"] = "intro"
	app._begin_chapter()
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "the proposal stage opened")

	# Pick two stations, then save without submitting.
	app.proposal_picked = [str(app.proposal_candidates[0].get("id", "")), str(app.proposal_candidates[1].get("id", ""))]
	var saved: bool = await app._save()
	_check(saved, "saving during the proposal succeeds")

	# Come back the way the game does.
	var reloaded: Dictionary = SaveManager.load_last_game()
	_check(bool(reloaded.get("ok", false)), "the save loads")
	var world: Dictionary = reloaded.world
	_check(str(world.storyState.get("stage", "")) == "proposal", "the proposal stage survives a reload")
	_check(str(world.storyState.get("chapterId", "")) == chapter_id, "the same chapter comes back")
	_check(Story.proposal_for(world, chapter_id).is_empty(), "an unsubmitted pick is not recorded")

	app._enter(world)
	await process_frame
	_check(str(app.world.storyState.get("stage", "")) == "proposal", "the app re-enters in the proposal stage")
	_check(app.station_button.disabled, "construction is still closed after the reload")
	var candidates: Array = app.proposal_candidates
	var submitted := Story.submit_proposal(app.world, [str(candidates[0].get("id", "")), str(candidates[1].get("id", ""))])
	_check(bool(submitted.get("ok", false)), "a proposal can still be submitted after a reload")
	_check(str(app.world.storyState.get("stage", "")) == "build", "submitting after a reload opens construction")

	print("PASS: %d proposal resume checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
