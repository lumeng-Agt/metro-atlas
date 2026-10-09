class_name TravelModel
extends RefCounted

const RAIL_GAME_TIME_FACTOR := 1.18
const DEFAULT_WALK_SPEED_KMH := 4.8

static func rail_minutes(distance_m: float, speed_kmh: float, game_time_factor: float = RAIL_GAME_TIME_FACTOR) -> float:
	return maxf(0.0, distance_m) / 1000.0 / maxf(1.0, speed_kmh) * 60.0 * maxf(0.0, game_time_factor)

static func walk_minutes(distance_m: float, speed_kmh: float = DEFAULT_WALK_SPEED_KMH) -> float:
	return maxf(0.0, distance_m) / maxf(0.1, speed_kmh * 1000.0 / 60.0)
