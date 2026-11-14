extends SceneTree

## The proposal stage must open before construction, must never write into the
## network, and must not let a chapter be confirmed while the player is still
## drawing. A skipped proposal leaves the chapter exactly as it was.

const Story = preload("res://scripts/story_session.gd")
const ProposalSession = preload("res://scripts/proposal_session.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _first_planning_chapter(world: Dictionary) -> Dictionary:
	var config: Dictionary = Story.config(world)
	for entry in config.get("futurePlans", []):
		if ProposalSession.eligible(entry):
			return entry
	return {}

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		quit(2)
		return
	WorldData.load_assets()
	var world := WorldData.new_world("shenzhen", "campaign")
	var chapter := _first_planning_chapter(world)
	_check(not chapter.is_empty(), "a planning chapter offers a proposal")
	if chapter.is_empty():
		print("FAIL: no eligible planning chapter")
		quit(1)
		return
	# Move the world onto that chapter.
	world.storyState["phase"] = "future"
	world.storyState["chapterId"] = str(chapter.get("id", ""))
	world.storyState["stage"] = "intro"
	var candidates := ProposalSession.candidate_stations(world, chapter)
	_check(candidates.size() >= ProposalSession.MIN_STATIONS, "the chapter carries a station order, got %d" % candidates.size())
	var with_coords := 0
	for row in candidates:
		var position: Variant = row.get("latlng", [])
		if position is Array and position.size() >= 2:
			with_coords += 1
	_check(with_coords == candidates.size(), "every candidate station has a coordinate: %d/%d" % [with_coords, candidates.size()])
	# A source-only chapter has nothing to propose.
	var event_only := {"eventOnly": true, "lineGroups": [{"stationIds": ["a", "b"]}]}
	_check(not ProposalSession.eligible(event_only), "a source-only chapter offers no proposal")
	# The proposal stage opens and the network is untouched.
	var before := JSON.stringify(world.get("stations", [])) + JSON.stringify(world.get("routes", []))
	var opened := Story.begin_proposal(world, int(world.get("revision", 0)))
	_check(bool(opened.get("ok", false)), "the proposal stage opens: %s" % str(opened.get("error", "")))
	_check(ProposalSession.stage(world) == ProposalSession.STAGE_PROPOSAL, "the chapter is in the proposal stage")
	_check(not str(opened.get("goal", "")).is_empty(), "the proposal states a goal")
	var after := JSON.stringify(world.get("stations", [])) + JSON.stringify(world.get("routes", []))
	_check(before == after, "opening a proposal does not touch the network")
	# A chapter cannot be confirmed while drawing.
	var blocked := Story.commit_chapter(world, int(world.get("revision", 0)))
	_check(not bool(blocked.get("ok", false)), "a chapter cannot be confirmed during a proposal")
	# Too few stations is rejected.
	var too_few := Story.submit_proposal(world, [str(candidates[0].get("id", ""))])
	_check(not bool(too_few.get("ok", false)), "a single station is not a proposal")
	# A real proposal is recorded and construction opens.
	var picked: Array = []
	for row in candidates:
		picked.append(str(row.get("id", "")))
	var submitted := Story.submit_proposal(world, picked)
	_check(bool(submitted.get("ok", false)), "a proposal with every station is accepted: %s" % str(submitted.get("error", "")))
	_check(ProposalSession.stage(world) == ProposalSession.STAGE_BUILD, "submitting a proposal opens construction")
	var recorded := Story.proposal_for(world, str(chapter.get("id", "")))
	_check(not recorded.is_empty(), "the proposal is recorded")
	_check((recorded.get("stationIds", []) as Array).size() == picked.size(), "the recorded proposal keeps every station")
	_check(not str(recorded.get("submittedAt", "")).is_empty(), "the proposal is dated")
	var after_submit := JSON.stringify(world.get("stations", [])) + JSON.stringify(world.get("routes", []))
	_check(before == after_submit, "submitting a proposal does not touch the network")
	# Duplicates and unknown ids are dropped rather than trusted.
	var messy: Array = [picked[0], picked[0], "no-such-station", picked[1]]
	var cleaned := ProposalSession.sanitize(messy, candidates)
	_check(cleaned.size() == 2, "duplicates and unknown stations are dropped, got %d" % cleaned.size())
	# Skipping leaves no proposal behind.
	var second := WorldData.new_world("shenzhen", "campaign")
	second.storyState["phase"] = "future"
	second.storyState["chapterId"] = str(chapter.get("id", ""))
	second.storyState["stage"] = "intro"
	Story.begin_proposal(second, int(second.get("revision", 0)))
	var skipped := Story.skip_proposal(second)
	_check(bool(skipped.get("ok", false)), "a proposal can be skipped")
	_check(ProposalSession.stage(second) == ProposalSession.STAGE_BUILD, "skipping opens construction")
	_check(Story.proposal_for(second, str(chapter.get("id", ""))).is_empty(), "skipping records no proposal")
	# An older save without the proposals key still reads.
	var legacy := WorldData.new_world("shenzhen", "campaign")
	legacy.storyState.erase("proposals")
	_check(Story.proposal_for(legacy, "any").is_empty(), "a save without proposals reads as no proposal")
	print("PASS: %d proposal checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
