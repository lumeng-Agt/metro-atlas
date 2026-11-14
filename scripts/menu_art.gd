extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 10.0 or h <= 10.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#EFEFE7"), true)

	var minor_color := Color("#E2E1D8", 0.75)
	var major_color := Color("#D2D1C6", 0.85)
	var step := 32.0
	var cols := int(ceil(w / step))
	var rows := int(ceil(h / step))
	for c in range(cols + 1):
		var x := float(c) * step
		var is_major := (c % 5) == 0
		draw_line(Vector2(x, 0), Vector2(x, h), major_color if is_major else minor_color, 1.0)
	for r in range(rows + 1):
		var y := float(r) * step
		var is_major := (r % 5) == 0
		draw_line(Vector2(0, y), Vector2(w, y), major_color if is_major else minor_color, 1.0)

	# Registration marks on major intersections
	var cross_color := Color("#B8B7AC", 0.9)
	for c in range(0, cols + 1, 5):
		for r in range(0, rows + 1, 5):
			var pt := Vector2(float(c) * step, float(r) * step)
			draw_line(pt - Vector2(5, 0), pt + Vector2(5, 0), cross_color, 1.2)
			draw_line(pt - Vector2(0, 5), pt + Vector2(0, 5), cross_color, 1.2)

	# Octilinear transit schematic lines framing the canvas
	var line_green := PackedVector2Array([
		Vector2(0, h * 0.78),
		Vector2(w * 0.16, h * 0.78),
		Vector2(w * 0.30, h * 0.56),
		Vector2(w * 0.70, h * 0.56),
		Vector2(w * 0.84, h * 0.34),
		Vector2(w, h * 0.34)
	])
	var line_blue := PackedVector2Array([
		Vector2(w * 0.14, 0),
		Vector2(w * 0.14, h * 0.28),
		Vector2(w * 0.28, h * 0.50),
		Vector2(w * 0.72, h * 0.50),
		Vector2(w * 0.86, h * 0.72),
		Vector2(w * 0.86, h)
	])
	var line_red := PackedVector2Array([
		Vector2(0, h * 0.22),
		Vector2(w * 0.22, h * 0.22),
		Vector2(w * 0.38, h * 0.38),
		Vector2(w * 0.62, h * 0.38),
		Vector2(w * 0.78, h * 0.22),
		Vector2(w, h * 0.22)
	])

	draw_polyline(line_green, Color("#1B5E4F", 0.08), 14.0, true)
	draw_polyline(line_green, Color("#1B5E4F", 0.22), 4.5, true)
	draw_polyline(line_blue, Color("#2B6CB0", 0.07), 14.0, true)
	draw_polyline(line_blue, Color("#2B6CB0", 0.20), 4.5, true)
	draw_polyline(line_red, Color("#C4553B", 0.06), 12.0, true)
	draw_polyline(line_red, Color("#C4553B", 0.18), 3.5, true)

	for station in [
		Vector2(w * 0.16, h * 0.78),
		Vector2(w * 0.84, h * 0.34),
		Vector2(w * 0.14, h * 0.28),
		Vector2(w * 0.86, h * 0.72),
		Vector2(w * 0.22, h * 0.22),
		Vector2(w * 0.78, h * 0.22)
	]:
		draw_circle(station, 8.0, Color("#1B5E4F", 0.28))
		draw_circle(station, 4.5, Color("#EFEFE7"))

	# Outer engineering sheet frame rule
	var frame_rect := Rect2(Vector2(16, 16), size - Vector2(32, 32))
	draw_rect(frame_rect, Color("#C2C1B6", 0.8), false, 1.0)
