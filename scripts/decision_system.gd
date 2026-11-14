class_name DecisionSystem
extends RefCounted

## Historical decisions shown before a source-only chapter. The cards never
## change construction: they ask what the player would have chosen, record the
## answer outside the world save, and reveal what the official record says.
## Every card ships with a dated official source; nothing here is inferred.

const PATH := "res://data/decisions.json"
const PROFILE_KEY := "decisions"

static var _catalog: Dictionary = {}

static func load_catalog() -> void:
	_catalog = {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if value is Dictionary:
		_catalog = value

static func version() -> String:
	return str(_catalog.get("version", "unknown"))

static func all() -> Array:
	return _catalog.get("decisions", [])

static func for_chapter(chapter_id: String) -> Dictionary:
	for entry in all():
		if str(entry.get("chapterId", "")) == chapter_id:
			return entry
	return {}

static func for_id(decision_id: String) -> Dictionary:
	for entry in all():
		if str(entry.get("id", "")) == decision_id:
			return entry
	return {}

## A card is either a historical decision (shown before a source-only chapter)
## or a planning decision (shown before a planning chapter's proposal). The
## kind decides where the card appears; both need a dated official source.
const KIND_HISTORICAL := "historical"
const KIND_PLANNING := "planning"

static func kind(entry: Dictionary) -> String:
	var value := str(entry.get("kind", KIND_HISTORICAL))
	return value if value in [KIND_HISTORICAL, KIND_PLANNING] else KIND_HISTORICAL

static func planning_for_chapter(chapter_id: String) -> Dictionary:
	for entry in all():
		if kind(entry) != KIND_PLANNING:
			continue
		if str(entry.get("chapterId", "")) == chapter_id:
			return entry
	return {}

## Problems that would make a card untrustworthy. A card without a dated
## official source is not shown at all.
static func validate(entry: Dictionary) -> Array:
	var problems: Array = []
	if str(entry.get("id", "")).is_empty():
		problems.append("missing id")
	if str(entry.get("chapterId", "")).is_empty():
		problems.append("missing chapterId")
	var card_kind := str(entry.get("kind", KIND_HISTORICAL))
	if not card_kind in [KIND_HISTORICAL, KIND_PLANNING]:
		problems.append("unknown kind")
	var options: Array = entry.get("options", [])
	if options.size() < 2:
		problems.append("needs at least two options")
	var ids: Array = []
	for option in options:
		var option_id := str(option.get("id", ""))
		if option_id.is_empty():
			problems.append("option without id")
		ids.append(option_id)
	if not ids.has(str(entry.get("actual", ""))):
		problems.append("actual choice is not one of the options")
	var sources: Array = entry.get("sources", [])
	if sources.is_empty():
		problems.append("missing source")
	for source in sources:
		if str(source.get("url", "")).is_empty() or str(source.get("checkedAt", "")).is_empty():
			problems.append("source needs url and checkedAt")
	if str(entry.get("reveal", "")).is_empty():
		problems.append("missing reveal")
	return problems

static func usable(entry: Dictionary) -> bool:
	return not entry.is_empty() and validate(entry).is_empty()

static func option(entry: Dictionary, option_id: String) -> Dictionary:
	for item in entry.get("options", []):
		if str(item.get("id", "")) == option_id:
			return item
	return {}

## Answers live beside the challenge profile, never inside the world save, so a
## decision cannot alter construction or replay state.
static func record(decision_id: String, option_id: String) -> Dictionary:
	var entry := for_id(decision_id)
	if not usable(entry):
		return {"ok": false, "error": "这张决策卡缺少可核验来源，未记录。"}
	if option(entry, option_id).is_empty():
		return {"ok": false, "error": "选项无效。"}
	var profile := ChallengeSession.load_profile()
	if profile.has("error"):
		return {"ok": false, "error": str(profile.error)}
	var decisions: Dictionary = profile.get(PROFILE_KEY, {})
	if not decisions is Dictionary:
		decisions = {}
	if decisions.has(decision_id):
		return {"ok": true, "already": true, "choice": str(decisions[decision_id].get("choice", ""))}
	decisions[decision_id] = {"choice": option_id, "date": Time.get_datetime_string_from_system(false, true), "catalogVersion": version()}
	profile[PROFILE_KEY] = decisions
	var saved := ChallengeSession.save_profile(profile)
	if not bool(saved.get("ok", false)):
		return saved
	return {"ok": true, "already": false, "choice": option_id, "matchesHistory": option_id == str(entry.get("actual", ""))}

static func choice(decision_id: String) -> String:
	var profile := ChallengeSession.load_profile()
	if profile.has("error"):
		return ""
	var decisions: Dictionary = profile.get(PROFILE_KEY, {})
	if not decisions is Dictionary:
		return ""
	return str(decisions.get(decision_id, {}).get("choice", ""))

## How many answered cards match the official record. Used on the outcome page;
## it is a reading check, not a score on construction.
static func summary() -> Dictionary:
	var answered := 0
	var matched := 0
	for entry in all():
		var picked := choice(str(entry.get("id", "")))
		if picked.is_empty():
			continue
		answered += 1
		if picked == str(entry.get("actual", "")):
			matched += 1
	return {"answered": answered, "matched": matched, "total": all().size()}
