class_name UiPreferences
extends RefCounted

const PATH := "user://ui_preferences.cfg"
const SCALE_OPTIONS := [1.0, 1.25, 1.5, 1.75]

static func load_scale() -> float:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return 1.0
	var value := float(config.get_value("display", "ui_scale", 1.0))
	return value if SCALE_OPTIONS.has(value) else 1.0

static func save_scale(value: float) -> Error:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("display", "ui_scale", value)
	return config.save(PATH)

static func load_clean_map() -> bool:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return true
	return bool(config.get_value("map", "clean_style", true))

static func save_clean_map(value: bool) -> Error:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("map", "clean_style", value)
	return config.save(PATH)

static func load_onboarding_completed() -> bool:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return false
	return bool(config.get_value("onboarding", "completed_once", false))

static func save_onboarding_completed(value: bool) -> Error:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("onboarding", "completed_once", value)
	return config.save(PATH)
