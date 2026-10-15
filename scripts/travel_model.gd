class_name TravelModel
extends RefCounted

const RAIL_GAME_TIME_FACTOR := 1.18
const DEFAULT_WALK_SPEED_KMH := 4.8
const CURVE_LATERAL_ACCELERATION_MPS2 := 0.65 # Game estimate, not a railway design standard.

static func rail_minutes(distance_m: float, speed_kmh: float, game_time_factor: float = RAIL_GAME_TIME_FACTOR) -> float:
	return maxf(0.0, distance_m) / 1000.0 / maxf(1.0, speed_kmh) * 60.0 * maxf(0.0, game_time_factor)

static func walk_minutes(distance_m: float, speed_kmh: float = DEFAULT_WALK_SPEED_KMH) -> float:
	return maxf(0.0, distance_m) / maxf(0.1, speed_kmh * 1000.0 / 60.0)

static func curve_speed_limit_kmh(radius_m: float, lateral_acceleration_mps2: float = CURVE_LATERAL_ACCELERATION_MPS2) -> float:
	if not is_finite(radius_m) or radius_m <= 0.0: return -1.0
	return sqrt(maxf(0.1, lateral_acceleration_mps2) * radius_m) * 3.6

static func rail_segment_minutes(distance_m: float, vehicle: Dictionary, dwell_minutes: float = 0.5, speed_limit_kmh: float = -1.0) -> float:
	var distance := maxf(0.0, distance_m)
	if distance <= 0.0:
		return 0.0
	var speed_kmh := float(vehicle.get("maxSpeedKmh", 80.0))
	if speed_limit_kmh > 0.0:
		speed_kmh = minf(speed_kmh, speed_limit_kmh)
	var speed := maxf(1.0, speed_kmh / 3.6)
	var acceleration := maxf(0.2, float(vehicle.get("accelerationMps2", 1.0)))
	var braking := maxf(0.2, float(vehicle.get("decelerationMps2", 1.1)))
	var accelerate_distance := speed * speed / (2.0 * acceleration)
	var brake_distance := speed * speed / (2.0 * braking)
	var seconds := 0.0
	if distance <= accelerate_distance + brake_distance:
		var peak_speed := sqrt(distance * 2.0 * acceleration * braking / (acceleration + braking))
		seconds = peak_speed / acceleration + peak_speed / braking
	else:
		seconds = speed / acceleration + speed / braking + (distance - accelerate_distance - brake_distance) / speed
	return seconds / 60.0 * RAIL_GAME_TIME_FACTOR + maxf(0.0, dwell_minutes)
