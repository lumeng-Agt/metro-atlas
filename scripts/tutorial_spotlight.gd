extends Control

## Click-through tutorial overlay. It highlights the real control or map object
## supplied by the owning scene; it never receives or simulates input.
var active := false
var target_rect := Rect2()
var target_shape := "rect"
var message := ""
var font: Font
var font_size := 18

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 4096
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()

func set_focus(rect: Rect2, prompt: String, shape: String = "rect", face: Font = null, size_px: int = 18) -> void:
	var next_active := rect.size.x > 0.0 and rect.size.y > 0.0 and not prompt.is_empty()
	var changed := active != next_active or target_rect != rect or target_shape != shape or message != prompt or font != face or font_size != size_px
	active = next_active
	target_rect = rect
	target_shape = shape
	message = prompt
	font = face
	font_size = size_px
	if changed: queue_redraw()

func clear_focus() -> void:
	if not active: return
	active = false
	message = ""
	queue_redraw()

func _draw() -> void:
	if not active: return
	var bounds := Rect2(Vector2.ZERO, size)
	var hole := target_rect.grow(9.0)
	var shade := Color(0.16, 0.20, 0.18, 0.32)
	var clipped := hole.intersection(bounds)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		draw_rect(bounds, shade)
		return
	# Four panels create a real transparent window around the target. Because
	# this control ignores mouse input, clicks still reach the original control.
	draw_rect(Rect2(Vector2.ZERO, Vector2(bounds.size.x, clipped.position.y)), shade)
	draw_rect(Rect2(Vector2(0, clipped.end.y), Vector2(bounds.size.x, maxf(0.0, bounds.end.y - clipped.end.y))), shade)
	draw_rect(Rect2(Vector2(0, clipped.position.y), Vector2(clipped.position.x, clipped.size.y)), shade)
	draw_rect(Rect2(Vector2(clipped.end.x, clipped.position.y), Vector2(maxf(0.0, bounds.end.x - clipped.end.x), clipped.size.y)), shade)
	if target_shape == "circle":
		var radius := maxf(target_rect.size.x, target_rect.size.y) * 0.5 + 11.0
		draw_arc(target_rect.get_center(), radius, 0.0, TAU, 48, Color("#24745E"), 3.0, true)
		draw_arc(target_rect.get_center(), radius + 4.0, 0.0, TAU, 48, Color("#24745E", 0.32), 1.0, true)
	else:
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color("#E6F1EB", 0.72)
		outline.border_color = Color("#24745E", 0.98)
		outline.set_border_width_all(3)
		outline.set_corner_radius_all(9)
		outline.shadow_color = Color(0.12, 0.30, 0.23, 0.18)
		outline.shadow_size = 5
		draw_style_box(outline, clipped)
	_draw_callout(bounds, hole)

func _draw_callout(bounds: Rect2, hole: Rect2) -> void:
	var callout_font := font if font != null else ThemeDB.fallback_font
	if callout_font == null: return
	var scaled_font_size := maxi(16, font_size)
	var width := minf(410.0, maxf(230.0, bounds.size.x - 28.0))
	var height := 58.0
	var gap := 16.0
	var center := hole.get_center()
	var candidates: Array[Rect2] = []
	if center.y > bounds.size.y * 0.58:
		candidates.append(Rect2(Vector2(clampf(center.x - width * 0.5, 14.0, bounds.size.x - width - 14.0), hole.position.y - height - gap), Vector2(width, height)))
	if center.x < bounds.size.x * 0.56:
		candidates.append(Rect2(Vector2(hole.end.x + gap, clampf(center.y - height * 0.5, 14.0, bounds.size.y - height - 14.0)), Vector2(width, height)))
	candidates.append(Rect2(Vector2(hole.position.x - width - gap, clampf(center.y - height * 0.5, 14.0, bounds.size.y - height - 14.0)), Vector2(width, height)))
	candidates.append(Rect2(Vector2(clampf(center.x - width * 0.5, 14.0, bounds.size.x - width - 14.0), hole.end.y + gap), Vector2(width, height)))
	var bubble: Rect2 = candidates.back()
	for candidate: Rect2 in candidates:
		if candidate.position.x >= 8.0 and candidate.position.y >= 8.0 and candidate.end.x <= bounds.end.x - 8.0 and candidate.end.y <= bounds.end.y - 8.0 and not candidate.intersects(hole):
			bubble = candidate
			break
	# Keep the message on screen even when the target is close to an edge.
	bubble.position.x = clampf(bubble.position.x, 8.0, maxf(8.0, bounds.size.x - bubble.size.x - 8.0))
	bubble.position.y = clampf(bubble.position.y, 8.0, maxf(8.0, bounds.size.y - bubble.size.y - 8.0))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#FFFEFA")
	panel.border_color = Color("#B7CEC2")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(12)
	panel.shadow_color = Color(0.14, 0.17, 0.14, 0.14)
	panel.shadow_size = 8
	draw_style_box(panel, bubble)
	var text_width := maxf(20.0, bubble.size.x - 28.0)
	var text_size: Vector2 = callout_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, scaled_font_size)
	var text_x: float = bubble.position.x + 14.0
	var text_y: float = bubble.position.y + (bubble.size.y + text_size.y) * 0.5 - 3.0
	draw_string(callout_font, Vector2(text_x, text_y), message, HORIZONTAL_ALIGNMENT_LEFT, text_width, scaled_font_size, Color("#24332F"))
	var start: Vector2 = bubble.get_center()
	if center.y > bubble.end.y: start = Vector2(clampf(center.x, bubble.position.x + 18.0, bubble.end.x - 18.0), bubble.end.y)
	elif center.y < bubble.position.y: start = Vector2(clampf(center.x, bubble.position.x + 18.0, bubble.end.x - 18.0), bubble.position.y)
	elif center.x > bubble.end.x: start = Vector2(bubble.end.x, clampf(center.y, bubble.position.y + 12.0, bubble.end.y - 12.0))
	else: start = Vector2(bubble.position.x, clampf(center.y, bubble.position.y + 12.0, bubble.end.y - 12.0))
	var direction: Vector2 = (center - start).normalized()
	var tip: Vector2 = center - direction * 12.0
	draw_line(start, tip, Color("#24745E"), 2.0, true)
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([center, tip - direction * 10.0 + normal * 6.0, tip - direction * 10.0 - normal * 6.0]), Color("#24745E"))
