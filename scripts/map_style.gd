class_name MetroMapStyle
extends RefCounted

## Geographic transit-map palette. All local/cached rendering uses these tokens.
## The canvas is warm drafting paper: the basemap stays low-contrast so the lines
## the player builds are the only thing that reads at full strength.
const ID := "transit-2026-atlas-c"
const CANVAS := Color("#F5F3EC")
const WATER := Color("#C8DBE8")
const WATER_EDGE := Color("#B2C7D6")
const PARK := Color("#ECEFEA")
const PARK_EDGE := Color("#DFE3DC")
const BUILDING := Color("#ECEAE4")
const BUILDING_EDGE := Color("#E0DDD6")
const LANDMARK := Color("#DFE3E8")
const LANDMARK_EDGE := Color("#C6CDD6")
const ROAD_EDGE := Color("#EAE7DE")
const ROAD := Color("#FAF9F5")
const MAJOR_ROAD := Color("#DDD8CC")
const ROAD_TEXT := Color("#849098")
const LANDMARK_TEXT := Color("#60707C")
const BLUEPRINT := Color("#1B5E4F")
const PREVIOUS_PLAN := Color("#9A98A0")

static func road_width(kind: String, zoom: int) -> float:
	match kind:
		"road_major": return 3.0 if zoom < 13 else 6.0
		"road_primary": return 3.0 if zoom < 15 else 4.8
		"road_secondary": return 3.2
	return 1.6

static func road_visible(kind: String, zoom: int) -> bool:
	return zoom >= int({"road_major":10,"road_primary":13,"road_secondary":15,"road_local":16,"water_line":14}.get(kind, 0))

static func label_visible(kind: String, zoom: int) -> bool:
	return zoom >= (13 if kind == "road_major" else 14 if kind in ["road_primary","building_major"] else 15)
