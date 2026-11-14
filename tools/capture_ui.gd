extends SceneTree
## UI 截图工具：驱动真实界面到指定状态并输出 PNG，供审查使用。
##
## 用法（非 headless，必须有 GPU 渲染）：
##   Godot_v4.7.2-stable_win64_console.exe --path <repo> \
##     --script res://tools/capture_ui.gd -- \
##     --data-dir=<isolated dir> --scene=<menu|workbench|station|saves> \
##     --size=1600x980 --out=<dir>
##
## 说明：本工具由内部接口驱动界面到目标状态，不冒充鼠标键盘试玩。
## 输出的 PNG 用于视觉审查，不作为"真人操作已验证"的证据。

const App = preload("res://scripts/main.gd")

var _out_dir := "res://docs/screenshots"
var _scene := "workbench"
var _size := Vector2i(1600, 980)

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--%s=" % name):
			return s.substr(name.length() + 3)
	return fallback

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		push_error("必须提供隔离的 --data-dir，避免污染真实存档。")
		quit(2)
		return

	_scene = _arg("scene", "workbench")
	_out_dir = _arg("out", "res://docs/screenshots")
	var size_arg := _arg("size", "1600x980")
	var parts := size_arg.split("x")
	if parts.size() == 2:
		_size = Vector2i(int(parts[0]), int(parts[1]))

	if DisplayServer.get_name() == "headless":
		push_error("headless 模式无法截图；请去掉 --headless。")
		quit(3)
		return

	DirAccess.make_dir_recursive_absolute(_out_dir)
	WorldData.load_assets()

	var app: Control = App.new()
	root.add_child(app)
	root.size = _size
	await process_frame

	await _goto(app, _scene)

	# 等底图线程与布局稳定，再抓帧，避免截到半成品。
	var deadline := Time.get_ticks_msec() + 25000
	while app.map_view != null and (app.map_view._base_map_thread_busy or not app.map_view._base_map_pending_request.is_empty()) \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	for _i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw

	var path := _out_dir.path_join("ui-%s-%dx%d.png" % [_scene, _size.x, _size.y])
	var err := root.get_texture().get_image().save_png(path)
	if err == OK:
		print("CAPTURED %s" % ProjectSettings.globalize_path(path))
	else:
		push_error("截图写出失败: %s" % error_string(err))

	app.queue_free()
	await process_frame
	quit(0 if err == OK else 1)

func _goto(app: Control, scene: String) -> void:
	match scene:
		"menu":
			await process_frame
		"workbench":
			app._new_game("shanghai", false)
			await _settle(app)
			app._begin_chapter()
			await _settle(app)
		"station":
			app._new_game("shanghai", false)
			await _settle(app)
			app._begin_chapter()
			await _settle(app)
			app.show_left = false
			app.show_right = true
			app._layout()
			await _settle(app)
		"saves":
			app._new_game("shanghai", false)
			await _settle(app)
			app._open_saves()
			await _settle(app)
		_:
			push_warning("未知 scene=%s，停留在菜单" % scene)

func _settle(app: Control) -> void:
	while app.saves_in_flight > 0:
		await process_frame
	for _i in range(3):
		await process_frame
