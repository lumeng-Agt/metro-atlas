extends Control

func _draw() -> void:
	var area := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	draw_rect(area, Color("#F0F1EB"), true)
	draw_rect(area, Color("#D6D8CE"), false, 1.2, true)
	var inner := area.grow(-20.0)
	var grid := Color("#D7DDD4", 0.78)
	for row in range(7):
		var y := inner.position.y + 22.0 + row * (inner.size.y - 44.0) / 6.0
		draw_line(Vector2(inner.position.x + 10, y), Vector2(inner.end.x - 10, y + 8.0 * sin(float(row))), grid, 1.0, true)
	for column in range(6):
		var x := inner.position.x + 16.0 + column * (inner.size.x - 32.0) / 5.0
		draw_line(Vector2(x, inner.position.y + 8), Vector2(x + 12.0 * cos(float(column)), inner.end.y - 8), grid, 1.0, true)

	var west := Vector2(inner.position.x + inner.size.x * 0.12, inner.position.y + inner.size.y * 0.75)
	var center := Vector2(inner.position.x + inner.size.x * 0.49, inner.position.y + inner.size.y * 0.48)
	var east := Vector2(inner.position.x + inner.size.x * 0.86, inner.position.y + inner.size.y * 0.23)
	var north := Vector2(inner.position.x + inner.size.x * 0.54, inner.position.y + inner.size.y * 0.12)
	var south := Vector2(inner.position.x + inner.size.x * 0.57, inner.position.y + inner.size.y * 0.87)
	var blue_line := PackedVector2Array([west, Vector2(center.x - 58, center.y + 42), center, Vector2(center.x + 54, center.y - 26), east])
	var green_line := PackedVector2Array([north, Vector2(north.x - 16, center.y - 6), center, Vector2(south.x + 8, center.y + 36), south])
	draw_polyline(blue_line, Color("#365F8C", 0.12), 13.0, true)
	draw_polyline(blue_line, Color("#5B82A8"), 5.0, true)
	draw_polyline(green_line, Color("#24745E", 0.12), 13.0, true)
	draw_polyline(green_line, Color("#24745E"), 5.0, true)
	for point in [west, center, east, north, south]:
		draw_circle(point, 10.0, Color("#24332F"))
		draw_circle(point, 6.0, Color("#FFFEFA"))
		draw_circle(point, 2.8, Color("#FFFEFA"))
	draw_circle(center, 15.0, Color("#B57A29", 0.17))
	draw_circle(center, 8.0, Color("#B57A29"))
	draw_circle(center, 3.0, Color("#24332F"))
