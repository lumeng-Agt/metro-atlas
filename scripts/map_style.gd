class_name MetroMapStyle
extends RefCounted

## Geographic transit-map palette. All local/cached rendering uses these tokens.
const ID := "transit-2026-10"
const CANVAS := Color("#e9edf1")
const WATER := Color("#add5ef")
const WATER_EDGE := Color("#88bddf")
const PARK := Color("#c8e2ba")
const PARK_EDGE := Color("#b1cfa1")
const BUILDING := Color("#d6dbe1")
const BUILDING_EDGE := Color("#b9c2cb")
const LANDMARK := Color("#ccd6e1")
const LANDMARK_EDGE := Color("#a3b3c4")
const ROAD_EDGE := Color("#bdc7d0")
const ROAD := Color("#ffffff")
const MAJOR_ROAD := Color("#fff5d7")
const ROAD_TEXT := Color("#485967")
const LANDMARK_TEXT := Color("#41566c")
const BLUEPRINT := Color("#1976bd")
const PREVIOUS_PLAN := Color("#8c829a")

static func road_width(kind: String, zoom: int) -> float:
	match kind:
		"road_major": return 3.0 if zoom < 13 else 6.0
		"road_primary": return 3.0 if zoom < 15 else 4.8
		"road_secondary": return 3.2
	return 1.6

static func road_visible(kind: String, zoom: int) -> bool:
	return zoom >= int({"road_major":10,"road_primary":13,"road_secondary":15,"road_local":16,"water_line":11}.get(kind, 0))

static func label_visible(kind: String, zoom: int) -> bool:
	return zoom >= (13 if kind == "road_major" else 14 if kind in ["road_primary","building_major"] else 15)
