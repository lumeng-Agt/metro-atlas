extends SceneTree

## Decision cards must be sourced, must not touch the world save, and must keep
## an older challenges.json readable.

const Story = preload("res://scripts/story_session.gd")
const DecisionSystem = preload("res://scripts/decision_system.gd")

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
	var cards: Array = DecisionSystem.all()
	_check(cards.size() >= 3, "decision catalogue ships at least three cards, got %d" % cards.size())
	for card in cards:
		var problems: Array = DecisionSystem.validate(card)
		_check(problems.is_empty(), "%s is well formed: %s" % [str(card.get("id", "")), ", ".join(problems)])
		_check(DecisionSystem.usable(card), "%s is usable" % str(card.get("id", "")))
		var chapter_id := str(card.get("chapterId", ""))
		var world := WorldData.new_world("shenzhen", "campaign")
		var config: Dictionary = Story.config(world)
		var found := {}
		for entry in config.get("chapters", []):
			if str(entry.get("id", "")) == chapter_id:
				found = entry
				break
		_check(not found.is_empty(), "%s points at an existing chapter" % chapter_id)
		_check(bool(found.get("eventOnly", false)), "%s is a source-only chapter" % chapter_id)
	# A card whose source is missing must not be shown.
	var broken: Dictionary = (cards[0] as Dictionary).duplicate(true)
	broken["sources"] = []
	_check(not DecisionSystem.usable(broken), "a card without a source is rejected")
	_check(not DecisionSystem.record("no-such-decision", "a").get("ok", false), "an unknown card cannot be recorded")
	# Recording keeps the answer out of the world save.
	var world := WorldData.new_world("shenzhen", "campaign")
	var before := JSON.stringify(world)
	var card: Dictionary = cards[0]
	var first := DecisionSystem.record(str(card.get("id", "")), str(card.get("actual", "")))
	_check(bool(first.get("ok", false)), "a sourced choice is recorded")
	_check(bool(first.get("matchesHistory", false)), "choosing the actual option matches history")
	_check(JSON.stringify(world) == before, "recording a decision does not touch the world save")
	_check(DecisionSystem.choice(str(card.get("id", ""))) == str(card.get("actual", "")), "the choice reads back")
	var again := DecisionSystem.record(str(card.get("id", "")), "b" if str(card.get("actual", "")) != "b" else "a")
	_check(bool(again.get("already", false)), "a second answer does not overwrite the first")
	_check(DecisionSystem.choice(str(card.get("id", ""))) == str(card.get("actual", "")), "the first answer survives")
	var summary := DecisionSystem.summary()
	_check(int(summary.get("answered", 0)) == 1, "summary counts answered cards")
	_check(int(summary.get("matched", 0)) == 1, "summary counts matching cards")
	# An older profile without the key still loads.
	var legacy := {"schemaVersion": ChallengeSession.VERSION, "daily": {}, "memory": {}, "location": []}
	var saved := ChallengeSession.save_profile(legacy)
	_check(bool(saved.get("ok", false)), "a legacy profile can be written")
	var loaded := ChallengeSession.load_profile()
	_check(not loaded.has("error"), "a legacy profile still loads")
	_check(DecisionSystem.choice(str(card.get("id", ""))).is_empty(), "a legacy profile reports no decision")
	print("PASS: %d decision checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
