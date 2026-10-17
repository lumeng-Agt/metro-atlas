extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var window_size := OS.get_environment("METRO_MENU_SIZE").split("x")
	root.size = Vector2i(int(window_size[0]), int(window_size[1])) if window_size.size() == 2 else Vector2i(1600, 980)
	var main: Variant = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if OS.get_environment("METRO_MENU_NEW_CITY") == "1": main._show_new_city_menu()
	var menu_state_name := "new-city" if OS.get_environment("METRO_MENU_NEW_CITY") == "1" else "menu"
	for frame in range(4): await process_frame
	await create_timer(0.22).timeout
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("A rendered display server is required to capture the menu preview.")
		quit(1)
		return
	var image := viewport_texture.get_image()
	var card: Control = main.menu_layer.get_node("MenuCard")
	var content: Control = card.get_node("MenuBodyScroll/MenuContent")
	var image_prefix := "menu-preview" if menu_state_name == "menu" else "new-city"
	var screenshot_name := "%s.png" % image_prefix if window_size.size() != 2 else "%s-%s.png" % [image_prefix, OS.get_environment("METRO_MENU_SIZE")]
	var preview_prefix := OS.get_environment("METRO_PREVIEW_PREFIX").strip_edges()
	if not preview_prefix.is_empty(): screenshot_name = "%s-%s" % [preview_prefix, screenshot_name]
	var error := image.save_png("res://docs/" + screenshot_name)
	if error != OK:
		push_error("Could not save main menu preview: %s" % error)
		quit(1)
		return
	print("Saved main menu preview %dx%d; card=%s content=%s" % [image.get_width(), image.get_height(), str(card.size), str(content.size)])
	quit(0)
