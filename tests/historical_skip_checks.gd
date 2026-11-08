extends SceneTree

## Skipping the opening run of source-only chapters must confirm each one
## through the normal path and stop at the first chapter that asks for
## construction. It must never skip a chapter that has work in it.

const Story = preload("res://scripts/story_session.gd")

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
	var world := WorldData.new_world("shenzhen", "campaign")
	var run := Story.historical_run_length(world)
	_check(run >= 2, "Shenzhen opens with a run of source-only chapters, got %d" % run)
	var before := (world.storyState.completedChapterIds as Array).size()
	var result := Story.skip_historical_run(world)
	_check(bool(result.get("ok", false)), "the opening run is confirmed: %s" % str(result.get("error", "")))
	var confirmed: Array = result.get("confirmed", [])
	_check(confirmed.size() == run, "every chapter in the run is confirmed, got %d of %d" % [confirmed.size(), run])
	_check((world.storyState.completedChapterIds as Array).size() == before + run, "each confirmed chapter is recorded")
	for chapter_id in confirmed:
		_check((world.storyState.completedChapterIds as Array).has(str(chapter_id)), "%s is in the completed list" % str(chapter_id))
	_check(not bool(result.get("eventOnly", true)), "it stops at a chapter that needs construction")
	var stopped := Story.chapter(world)
	_check(not bool(stopped.get("eventOnly", true)), "the current chapter is a construction chapter")
	_check(Story.historical_run_length(world) == 0, "no source-only run remains at the stop point")
	# The save must still validate after the bulk confirm.
	_check(SaveManager.validate(world).is_empty(), "the world validates after a bulk confirm")
	# A construction chapter is never skipped.
	var second := WorldData.new_world("shenzhen", "campaign")
	Story.skip_historical_run(second)
	var guarded := Story.skip_historical_run(second)
	_check(bool(guarded.get("ok", false)), "a second call on a construction chapter is a no-op")
	_check((guarded.get("confirmed", []) as Array).is_empty(), "a construction chapter is not confirmed by the skip")
	print("PASS: %d skip checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
