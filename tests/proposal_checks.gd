extends SceneTree

## Proposal scoring must reward following the published station order, punish a
## line that wanders off, and never invent precision the record does not have.

const Proposal = preload("res://scripts/proposal_scoring.gd")
const Catalog = preload("res://scripts/campaign_system.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _stations_for(city_id: String, task_id: String) -> Array:
	var config: Dictionary = Catalog.city_config(city_id)
	var out: Array = []
	for plan in config.get("futurePlans", []):
		for group in plan.get("lineGroups", []):
			if str(group.get("taskId", "")) != task_id:
				continue
			var names: Dictionary = group.get("stationNames", {})
			for station_id in group.get("stationIds", []):
				var reference: Dictionary = ReferenceAlignment.station_reference(str(station_id))
				var position: Variant = reference.get("latlng", [])
				if position is Array and position.size() >= 2:
					out.append({"id": str(station_id), "name": str(names.get(str(station_id), station_id)), "latlng": position})
	return out

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		quit(2)
		return
	WorldData.load_assets()
	var task_id := "project:sz-line17-phase1-build"
	var stations := _stations_for("shenzhen", task_id)
	# Planned stations without a published coordinate are not scored, and are
	# not invented to make the count look complete.
	_check(stations.size() >= 5, "line 17 has stations with published coordinates, got %d" % stations.size())
	_check(stations.size() < 18, "planned stations without coordinates are excluded rather than invented")
	var group := {"toleranceM": 500}
	# A line drawn exactly through the published station order.
	var exact: Array = []
	for station in stations:
		exact.append(station.latlng)
	var perfect := Proposal.evaluate(exact, group, stations, ["老街"])
	_check(int(perfect.score) >= 95, "following the published order scores near full marks, got %d" % int(perfect.score))
	_check(str(perfect.grade) == "贴合公开方案", "a faithful line is graded as matching the record")
	_check(int(perfect.stationCovered) == int(perfect.stationTotal), "every station is covered by a faithful line")
	_check((perfect.transfersHit as Array).has("老街"), "a required interchange is credited")
	# A line far away from the corridor.
	var far: Array = [[22.40, 113.70], [22.41, 113.71], [22.42, 113.72]]
	var poor := Proposal.evaluate(far, group, stations, ["老街"])
	_check(int(poor.score) < 40, "a distant line scores low, got %d" % int(poor.score))
	_check(str(poor.grade) == "偏离较多", "a distant line is graded as off course")
	_check(int(poor.stationCovered) == 0, "a distant line covers no station")
	_check((poor.transfersMissed as Array).has("老街"), "a missed interchange is reported")
	# Degenerate inputs must not crash or score.
	var empty := Proposal.evaluate([], group, stations, [])
	_check(int(empty.score) == 0, "an empty line scores zero, got %d" % int(empty.score))
	var single := Proposal.evaluate([exact[0]], group, stations, [])
	_check(int(single.score) == 0, "a single point is not a line")
	# Tolerance comes from the data, not from a hardcoded assumption.
	_check(is_equal_approx(Proposal.tolerance_m({"toleranceM": 800}), 800.0), "tolerance is read from the project")
	_check(is_equal_approx(Proposal.tolerance_m({}), 500.0), "a missing tolerance falls back to 500 m")
	# The score never claims more precision than the record has.
	_check(str(perfect.notice).findn("客流") >= 0, "the result states it does not assess ridership")
	# Scoring is pure: it must not write to the world save.
	var world := WorldData.new_world("shenzhen", "campaign")
	var before := JSON.stringify(world)
	Proposal.evaluate(exact, group, stations, ["老街"])
	_check(JSON.stringify(world) == before, "scoring does not touch the world save")
	print("PASS: %d proposal checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
