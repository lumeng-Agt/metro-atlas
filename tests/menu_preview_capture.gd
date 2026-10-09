extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var window_size := OS.get_environment("METRO_MENU_SIZE").split("x")
	root.size = Vector2i(int(window_size[0]), int(window_size[1])) if window_size.size() == 2 else Vector2i(1600, 980)
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for frame in range(4): await process_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("A rendered display server is required to capture the menu preview.")
		quit(1)
		return
	var image := viewport_texture.get_image()
	var card: Control = main.menu_layer.get_node("MenuCard")
	var content: Control = card.get_node("MenuBodyScroll/MenuContent")
	var screenshot_name := "menu-preview.png" if window_size.size() != 2 else "menu-preview-%s.png" % OS.get_environment("METRO_MENU_SIZE")
	var error := image.save_png("res://docs/" + screenshot_name)
	if error != OK:
		push_error("Could not save main menu preview: %s" % error)
		quit(1)
		return
	print("Saved main menu preview %dx%d; card=%s content=%s" % [image.get_width(), image.get_height(), str(card.size), str(content.size)])
	quit(0)
