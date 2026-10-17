class_name UiPreferences
extends RefCounted

const SCALE_OPTIONS := [1.0, 1.25, 1.5, 1.75]

static func path() -> String:
	var data_root:=SaveManager.root_path()
	if data_root.is_empty():return ""
	var preferred := data_root.path_join("ui_preferences.cfg")
	if not SaveManager.using_explicit_data_dir() and not FileAccess.file_exists(preferred):
		var legacy := ConfigFile.new()
		if legacy.load("user://ui_preferences.cfg") == OK:
			var parent := ProjectSettings.globalize_path(preferred.get_base_dir())
			DirAccess.make_dir_recursive_absolute(parent)
			legacy.save(preferred)
	return preferred

static func load_scale() -> float:
	var config := ConfigFile.new()
	if config.load(path()) != OK:
		return 1.0
	var value := float(config.get_value("display", "ui_scale", 1.0))
	return value if SCALE_OPTIONS.has(value) else 1.0

static func save_scale(value: float) -> Error:
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("display", "ui_scale", value)
	return config.save(target)

static func load_ui_motion_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(path()) != OK: return true
	return bool(config.get_value("display", "ui_motion_enabled", true))

static func save_ui_motion_enabled(value: bool) -> Error:
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("display", "ui_motion_enabled", value)
	return config.save(target)

static func load_road_names() -> bool:
	var config := ConfigFile.new()
	if config.load(path()) != OK: return true
	return bool(config.get_value("map", "show_road_names", true))

static func save_road_names(value: bool) -> Error:
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("map", "show_road_names", value)
	return config.save(target)

static func load_feedback_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(path()) != OK: return true
	return bool(config.get_value("audio", "feedback_enabled", true))

static func save_feedback_enabled(value: bool) -> Error:
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("audio", "feedback_enabled", value)
	return config.save(target)

static func load_feedback_volume() -> float:
	var config := ConfigFile.new()
	if config.load(path()) != OK: return 0.35
	return clampf(float(config.get_value("audio", "feedback_volume", 0.35)), 0.0, 1.0)

static func save_feedback_volume(value: float) -> Error:
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("audio", "feedback_volume", clampf(value, 0.0, 1.0))
	return config.save(target)

static func load_onboarding_completed() -> bool:
	var config := ConfigFile.new()
	if config.load(path()) != OK:
		return false
	return bool(config.get_value("story_tutorial", "completed_once", false))

static func save_onboarding_completed(value: bool) -> Error:
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("story_tutorial", "completed_once", value)
	return config.save(target)

static func load_timed_autosave_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(path()) != OK: return true
	return bool(config.get_value("saving", "timed_autosave_enabled", true))

static func save_timed_autosave_enabled(value: bool) -> Error:
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("saving", "timed_autosave_enabled", value)
	return config.save(target)

static func load_timed_autosave_interval() -> int:
	var config := ConfigFile.new()
	if config.load(path()) != OK: return 5
	var value := int(config.get_value("saving", "timed_autosave_interval_minutes", 5))
	return value if [2, 5, 10, 15].has(value) else 5

static func save_timed_autosave_interval(value: int) -> Error:
	if not [2, 5, 10, 15].has(value): return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	config.load(target)
	config.set_value("saving", "timed_autosave_interval_minutes", value)
	return config.save(target)
