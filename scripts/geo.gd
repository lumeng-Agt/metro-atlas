class_name Geo
extends RefCounted

const TILE_SIZE := 256.0

static func project(latlng: Array, zoom: int) -> Vector2:
	var lat := clampf(float(latlng[0]), -85.0511, 85.0511)
	var lon := float(latlng[1])
	var n := pow(2.0, zoom) * TILE_SIZE
	var x := (lon + 180.0) / 360.0 * n
	var rad := deg_to_rad(lat)
	var y := (1.0 - log(tan(rad) + 1.0 / cos(rad)) / PI) * 0.5 * n
	return Vector2(x, y)

static func unproject(point: Vector2, zoom: int) -> Array:
	var n := pow(2.0, zoom) * TILE_SIZE
	var lon := point.x / n * 360.0 - 180.0
	var y := PI * (1.0 - 2.0 * point.y / n)
	var lat := rad_to_deg(atan(sinh(y)))
	return [lat, lon]

static func local_m(latlng: Array, ref_lat: float) -> Vector2:
	return Vector2(float(latlng[1]) * 111320.0 * cos(deg_to_rad(ref_lat)), float(latlng[0]) * 111132.0)

static func from_local(point: Vector2, ref_lat: float) -> Array:
	return [point.y / 111132.0, point.x / (111320.0 * cos(deg_to_rad(ref_lat)))]

static func offset(latlng: Array, distance_m: float, bearing_deg: float) -> Array:
	var bearing := deg_to_rad(bearing_deg)
	var north := cos(bearing) * distance_m
	var east := sin(bearing) * distance_m
	var lat := float(latlng[0]) + north / 111132.0
	var lon := float(latlng[1]) + east / (111320.0 * cos(deg_to_rad(float(latlng[0]))))
	return [lat, lon]

static func meters_per_pixel(lat: float, zoom: int) -> float:
	return 156543.03392 * cos(deg_to_rad(lat)) / pow(2.0, zoom)
