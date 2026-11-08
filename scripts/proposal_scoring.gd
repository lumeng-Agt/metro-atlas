class_name ProposalScoring
extends RefCounted

## Scores a player's own line against a published project.
##
## The projects in this release are corridor_only: the record fixes which
## stations a project serves and in what order, not an exact alignment. So the
## reference corridor is the station sequence joined in order, and the score
## only measures corridor agreement, station coverage and required
## interchanges. It never claims surveying accuracy, and it never touches
## passenger demand, ridership or operations.

const CORRIDOR_POINTS := 60.0
const STATION_POINTS := 30.0
const TRANSFER_POINTS := 10.0

const GRADE_EXCELLENT := 85.0
const GRADE_PASS := 60.0

## Distance within which a point counts as served by the player's line.
static func tolerance_m(group: Dictionary) -> float:
	var value := float(group.get("toleranceM", 500))
	return value if value > 0 else 500.0

static func _nearest_m(point: Array, line: Array, ref_lat: float) -> float:
	if line.size() < 2:
		return INF
	var p := Geo.local_m(point, ref_lat)
	var nearest := INF
	for i in range(line.size() - 1):
		var a := Geo.local_m(line[i], ref_lat)
		var b := Geo.local_m(line[i + 1], ref_lat)
		nearest = minf(nearest, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return nearest

## The published corridor is the station sequence joined in order.
static func corridor_from_stations(stations: Array) -> Array:
	var line: Array = []
	for station in stations:
		var position: Variant = station.get("latlng", [])
		if position is Array and position.size() >= 2:
			line.append(position)
	return line

## Fraction of the reference corridor that the player's line comes near.
static func corridor_coverage(player: Array, reference: Array, ref_lat: float, tolerance: float) -> float:
	if player.size() < 2 or reference.size() < 2:
		return 0.0
	var covered := 0
	for point in reference:
		if _nearest_m(point, player, ref_lat) <= tolerance:
			covered += 1
	return float(covered) / float(reference.size())

## Fraction of the project's stations that the player's line serves.
static func station_coverage(player: Array, stations: Array, ref_lat: float, tolerance: float) -> Dictionary:
	if player.size() < 2 or stations.is_empty():
		return {"covered": 0, "total": stations.size(), "ratio": 0.0, "missed": []}
	var covered := 0
	var missed: Array = []
	for station in stations:
		var position: Variant = station.get("latlng", [])
		if not position is Array or position.size() < 2:
			continue
		if _nearest_m(position, player, ref_lat) <= tolerance:
			covered += 1
		else:
			missed.append(str(station.get("name", station.get("id", ""))))
	return {"covered": covered, "total": stations.size(), "ratio": float(covered) / float(max(1, stations.size())), "missed": missed}

static func grade(score: float) -> String:
	if score >= GRADE_EXCELLENT:
		return "贴合公开方案"
	if score >= GRADE_PASS:
		return "走向基本一致"
	return "偏离较多"

## Compare a player-drawn line with a project.
##
## player: polyline of [lat, lng] points.
## group: one lineGroups entry from the campaign data (supplies the tolerance).
## stations: the project's stations in published order, each with latlng/name.
## transfer_names: interchanges the project has to make.
static func evaluate(player: Array, group: Dictionary, stations: Array, transfer_names: Array = [], ref_lat: float = 22.55) -> Dictionary:
	var tolerance := tolerance_m(group)
	var reference := corridor_from_stations(stations)
	var corridor := corridor_coverage(player, reference, ref_lat, tolerance)
	var coverage := station_coverage(player, stations, ref_lat, tolerance)
	var hit: Array = []
	var missed_transfers: Array = []
	for name in transfer_names:
		var found := false
		for station in stations:
			if str(station.get("name", "")) != str(name):
				continue
			var position: Variant = station.get("latlng", [])
			if position is Array and position.size() >= 2 and _nearest_m(position, player, ref_lat) <= tolerance:
				found = true
			break
		if found:
			hit.append(name)
		else:
			missed_transfers.append(name)
	# A line that is not a line earns nothing, including the interchange share.
	var valid := player.size() >= 2
	var transfer_ratio := 0.0
	if valid:
		transfer_ratio = 1.0 if transfer_names.is_empty() else float(hit.size()) / float(transfer_names.size())
	var score := corridor * CORRIDOR_POINTS + float(coverage.ratio) * STATION_POINTS + transfer_ratio * TRANSFER_POINTS
	return {
		"score": roundi(score),
		"grade": grade(score),
		"corridorRatio": corridor,
		"stationCovered": int(coverage.covered),
		"stationTotal": int(coverage.total),
		"missedStations": coverage.missed,
		"transfersHit": hit,
		"transfersMissed": missed_transfers,
		"toleranceM": tolerance,
		"stationTotalWithCoordinates": int(coverage.total),
		"notice": "按公开站序与走廊比对，不代表测绘精度，也不评估客流。",
	}
