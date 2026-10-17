extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		push_error("Save-center checks require an isolated --data-dir.")
		quit(2)
		return
	WorldData.load_assets()
	var state := WorldData.new_world("shanghai", "blank")
	var saved := SaveManager.save_world(state)
	var manual := SaveManager.save_manual_snapshot(state, "长名称测试 · 跨城区通勤与枢纽接驳二期建设方案")
	_check(bool(saved.get("ok", false)) and bool(manual.get("ok", false)), "隔离自动与命名存档可以建立")
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var sizes := [Vector2i(1366, 768), Vector2i(1600, 980), Vector2i(1920, 1080)]
	var scales := [1.0, 1.25, 1.5, 1.75]
	if OS.get_environment("METRO_SAVE_LAYOUT_QUICK") == "1":
		sizes = [Vector2i(1600, 980)]
		scales = [1.0]
	for window_size in sizes:
		root.size = window_size
		for scale in scales:
			main._apply_ui_scale(scale)
			await process_frame
			for tab in ["automatic", "manual"]:
				main._show_save_center(tab)
				for frame in range(6): await process_frame
				var dialog: AcceptDialog
				for child in main.get_children():
					if child is AcceptDialog and child.title == "存档中心": dialog = child
				var context := "%dx%d %d%% %s" % [window_size.x, window_size.y, roundi(scale * 100.0), tab]
				_check(dialog != null, context + " 窗口存在")
				if dialog == null: continue
				_check(Rect2(Vector2.ZERO, Vector2(window_size)).encloses(Rect2(Vector2(dialog.position), Vector2(dialog.size))), context + " 窗口完整位于视口内，实际 %s %s" % [dialog.position, dialog.size])
				for action_name in ["立即保存", "新建命名存档", "导出 JSON"]:
					var action := _find_button(dialog, action_name)
					_check(action != null and action.disabled, context + " 未进入城市时禁用 " + action_name)
				var actions := dialog.find_child("SaveCenterActions", true, false) as Control
				var outer_scroll := dialog.find_child("SaveCenterScroll", true, false) as ScrollContainer
				_check(actions != null and outer_scroll != null and actions.get_global_rect().end.y <= outer_scroll.get_global_rect().end.y + 1.0, context + " 底部存档操作完整可见")
				var page := dialog.find_child("AutomaticSaves" if tab == "automatic" else "ManualSaves", true, false) as ScrollContainer
				_check(page != null and page.get_child_count() > 0 and page.size.x > 200.0, context + " 列表获得可用宽度")
				if page != null and page.get_child_count() > 0:
					var rows: Control = page.get_child(0)
					_check(rows.size.x >= page.size.x - 32.0 * scale, context + " 列表填满分页宽度，实际 %s / %s" % [rows.size, page.size])
					if rows.size.y > page.size.y:
						var scrollbar := page.get_v_scroll_bar()
						_check(scrollbar.visible and scrollbar.size.x >= 8.0, context + " 超出列表时显示可辨认的滚动条，实际 " + str(scrollbar.size))
						_check(rows.get_global_rect().end.x <= scrollbar.get_global_rect().position.x + 1.0, context + " 滚动条不覆盖载入按钮")
						page.scroll_vertical = 100000
						await process_frame
						_check(page.scroll_vertical > 0 and rows.get_global_rect().end.y <= page.get_global_rect().end.y + 1.0, context + " 可以滚动查看最后一项存档")
						page.scroll_vertical = 0
						await process_frame
					for row in rows.get_children():
						if not row is HBoxContainer: continue
						var label: Label = row.get_child(0)
						var button: Button = row.get_child(1)
						_check(row.size.x >= page.size.x - 32.0 * scale, context + " 存档行填满列表宽度")
						_check(label.size.x >= 120.0 * scale, context + " 说明获得可读宽度，实际 " + str(label.size))
						_check(button.size.y <= 64.0 * scale, context + " 载入按钮不会被说明拉成长条，实际 " + str(button.size))
						_check(label.get_global_rect().end.x <= button.get_global_rect().position.x + 1.0, context + " 说明与载入按钮不重叠")
				if OS.get_environment("METRO_SAVE_LAYOUT_CAPTURE") == "1" and ((window_size == Vector2i(1600, 980) and scale == 1.0) or (window_size == Vector2i(1366, 768) and scale == 1.75)):
					await create_timer(0.22).timeout
					await RenderingServer.frame_post_draw
					var suffix := "%dx%d%s" % [window_size.x, window_size.y, "-175" if scale == 1.75 else ""]
					var path := "res://docs/redesign-save-center-%s-%s.png" % [tab, suffix]
					if tab == "manual" and scale == 1.0: path = "res://docs/redesign-save-center-preview-1600x980.png"
					var image_error := root.get_texture().get_image().save_png(path)
					_check(image_error == OK, "存档中心截图保存 " + path)
				dialog.queue_free()
				await process_frame
	# Importing from the main menu has no current city to save first.
	main._show_save_center()
	var import_dialog: AcceptDialog
	for child in main.get_children():
		if child is AcceptDialog and child.title == "存档中心": import_dialog = child
	var import_button := _find_button(import_dialog, "导入 JSON") if import_dialog != null else null
	_check(import_button != null and not import_button.disabled, "未进入城市时仍允许从存档中心导入")
	if import_button != null: import_button.pressed.emit()
	_check(import_dialog != null and not import_dialog.visible, "打开导入窗口前立即解除存档中心的模态占用")
	await process_frame
	var file_picker: FileDialog
	for child in root.get_children():
		if child is FileDialog: file_picker = child
	_check(file_picker != null, "存档中心打开JSON文件选择窗口")
	if file_picker != null: file_picker.file_selected.emit(SaveManager.save_path("shanghai", "blank"))
	await process_frame
	_check(not main.world.is_empty() and not main.save_failed and bool(main.world.get("simulation", {}).get("paused", false)), "主菜单导入不会被空会话保存阻止，且导入后暂停")
	main._show_save_center("manual")
	var naming_source: AcceptDialog
	for child in main.get_children():
		if child is AcceptDialog and child.title == "存档中心": naming_source = child
	var name_button := _find_button(naming_source, "新建命名存档") if naming_source != null else null
	if name_button != null: name_button.pressed.emit()
	_check(naming_source != null and not naming_source.visible, "打开命名窗口前解除存档中心的模态占用")
	var naming_dialog: ConfirmationDialog
	for child in main.get_children():
		if child is ConfirmationDialog and child.title == "新建手动存档": naming_dialog = child
	_check(naming_dialog != null and naming_dialog.visible, "进入城市后可从存档中心打开命名窗口")
	if naming_dialog != null:
		naming_dialog.hide()
		naming_dialog.queue_free()
	await process_frame
	main.queue_free()
	await process_frame
	if bool(manual.get("ok", false)): SaveManager.delete_manual_snapshot(str(manual.get("path", "")))
	if failures.is_empty():
		print("PASS: %d save-center layout checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null
