class_name ProposalSession
extends RefCounted

## A planning chapter can open with a proposal stage: the player draws their
## own line from a stated goal before the published plan is revealed. The
## proposal never replaces construction, never bypasses the chapter checks and
## never writes into the world save's network. It records what the player drew
## so the comparison can quote it back, and the answer lives outside the save
## the same way a decision card answer does.
##
## Nothing here invents geography: the reference corridor is the published
## station order joined in order, and stations the record does not place are
## excluded rather than guessed.

const STAGE_INTRO := "intro"
const STAGE_PROPOSAL := "proposal"
const STAGE_BUILD := "build"
const STAGE_OUTCOME := "outcome"

## A proposal needs at least two stations to describe a direction at all.
const MIN_STATIONS := 2

static func stage(world: Dictionary) -> String:
	return str(world.get("storyState", {}).get("stage", STAGE_INTRO))

## Chapters that offer a proposal are the published planning projects that
## carry a buildable station order. A source-only chapter has no line to
## propose, an engineering-only project has no station sequence, and a
## historical chapter is a reconstruction rather than a choice: the record
## already fixes what was built, so offering a "proposal" there would suggest
## the player could have chosen otherwise.
static func eligible(chapter_row: Dictionary) -> bool:
	if chapter_row.is_empty():
		return false
	if bool(chapter_row.get("eventOnly", false)):
		return false
	# Planning projects carry a project id list or a future-plan status; a
	# historical chapter carries neither.
	var is_project := not (chapter_row.get("projectIds", []) as Array).is_empty()
	if not is_project:
		var status := str(chapter_row.get("status", ""))
		is_project = status in ["under_construction", "approved_project", "approved_network_plan", "official_plan", "public_consultation"]
	if not is_project:
		return false
	for group in chapter_row.get("lineGroups", []):
		if group is Dictionary and (group.get("stationIds", []) as Array).size() >= MIN_STATIONS:
			return true
	return false

static func record_key(chapter_id: String) -> String:
	return "proposal:%s" % chapter_id

## The goal text shown before the player draws. It is the chapter's own
## published purpose, never a restatement invented here.
static func goal_text(chapter_row: Dictionary) -> String:
	var story: Dictionary = chapter_row.get("story", {})
	var purpose := str(story.get("purpose", chapter_row.get("description", "")))
	if purpose.is_empty():
		purpose = "按公开站序建设本期线路。"
	return purpose

## Stations a proposal can snap to: the chapter's published order, each with
## the coordinate the record actually carries.
static func candidate_stations(world: Dictionary, chapter_row: Dictionary) -> Array:
	var refs: Dictionary = {}
	for station in WorldData.city(str(world.get("cityId", ""))).get("stations", []):
		refs[str(station.get("id", ""))] = station
	var rows: Array = []
	var seen: Dictionary = {}
	for group in chapter_row.get("lineGroups", []):
		if not group is Dictionary:
			continue
		var names: Dictionary = group.get("stationNames", {})
		for raw_id in group.get("stationIds", []):
			var id := str(raw_id)
			var reference_id := str((group.get("stationReferenceIds", {}) as Dictionary).get(id, id))
			if seen.has(reference_id) or not refs.has(reference_id):
				continue
			var station: Dictionary = refs[reference_id]
			var position: Variant = station.get("latlng", [])
			if not position is Array or position.size() < 2:
				continue
			seen[reference_id] = true
			rows.append({
				"id": id,
				"referenceId": reference_id,
				"name": str(names.get(id, station.get("name", id))),
				"latlng": position,
			})
	return rows

## A proposal is the ordered list of station ids the player picked. Keeping
## ids rather than free points means the comparison is about which published
## stations were served and in what order, which is exactly what the project
## record fixes.
static func sanitize(station_ids: Array, candidates: Array) -> Array:
	var allowed: Dictionary = {}
	for row in candidates:
		allowed[str(row.get("id", ""))] = true
	var result: Array = []
	for raw in station_ids:
		var id := str(raw)
		if not allowed.has(id) or result.has(id):
			continue
		result.append(id)
	return result

static func is_usable(station_ids: Array) -> bool:
	return station_ids.size() >= MIN_STATIONS

## Points of a proposal in the order the player set, for scoring.
static func proposal_line(station_ids: Array, candidates: Array) -> Array:
	var by_id: Dictionary = {}
	for row in candidates:
		by_id[str(row.get("id", ""))] = row.get("latlng", [])
	var line: Array = []
	for id in station_ids:
		if by_id.has(str(id)):
			line.append(by_id[str(id)])
	return line

## Published order of the chapter, as the reference the proposal is judged
## against.
static func published_order(candidates: Array) -> Array:
	return candidates.duplicate()

static func published_line(candidates: Array) -> Array:
	var line: Array = []
	for row in candidates:
		line.append(row.get("latlng", []))
	return line
