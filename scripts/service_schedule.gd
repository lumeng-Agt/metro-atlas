class_name ServiceSchedule
extends RefCounted

const DAY_SECONDS := 86400
const AM_START := 7 * 3600
const AM_END := 10 * 3600
const PM_START := 16 * 3600
const PM_END := 19 * 3600

static func ensure_profile(route: Dictionary) -> Dictionary:
	var profile: Dictionary = route.get("serviceSchedule", {})
	if profile.is_empty():
		var inherited := maxi(1, int(route.get("headway", 3)))
		profile = {"mode": "uniform", "peakAM": inherited, "peakPM": inherited, "offPeak": inherited}
		route["serviceSchedule"] = profile
	return profile

static func headway_minutes(route: Dictionary, absolute_seconds: int) -> int:
	var profile := ensure_profile(route)
	if str(profile.get("mode", "uniform")) != "time_of_day":
		return maxi(1, int(route.get("headway", 3)))
	var day_seconds := posmod(absolute_seconds, DAY_SECONDS)
	if day_seconds >= AM_START and day_seconds < AM_END:
		return clampi(int(profile.get("peakAM", route.get("headway", 3))), 1, 60)
	if day_seconds >= PM_START and day_seconds < PM_END:
		return clampi(int(profile.get("peakPM", route.get("headway", 3))), 1, 60)
	return clampi(int(profile.get("offPeak", route.get("headway", 3))), 1, 60)

static func next_boundary_after(absolute_seconds: int) -> int:
	var day_start := floori(float(absolute_seconds) / float(DAY_SECONDS)) * DAY_SECONDS
	var boundaries := [AM_START, AM_END, PM_START, PM_END]
	for boundary in boundaries:
		var candidate: int = int(day_start) + int(boundary)
		if candidate > absolute_seconds:
			return candidate
	return int(day_start) + DAY_SECONDS + AM_START

static func set_mode(route: Dictionary, mode: String) -> void:
	var profile := ensure_profile(route)
	if mode == "time_of_day":
		var inherited := maxi(1, int(route.get("headway", 3)))
		profile["peakAM"] = int(profile.get("peakAM", inherited))
		profile["peakPM"] = int(profile.get("peakPM", inherited))
		profile["offPeak"] = int(profile.get("offPeak", inherited))
	profile["mode"] = "time_of_day" if mode == "time_of_day" else "uniform"
	route["serviceSchedule"] = profile

static func set_headway(route: Dictionary, period: String, minutes: int) -> void:
	var profile := ensure_profile(route)
	var value := clampi(minutes, 1, 60)
	if period == "uniform":
		route["headway"] = value
		for key in ["peakAM", "peakPM", "offPeak"]: profile[key] = value
	else:
		profile[period] = value
	route["serviceSchedule"] = profile
