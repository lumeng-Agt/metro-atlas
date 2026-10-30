extends Control
var layout:Dictionary={}
var font:Font
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#f0f3f5"))
	if not layout.get("ok",false):return
	for stroke in layout.strokes:
		var points:=PackedVector2Array()
		for id in stroke.ids:points.append(layout.positions[str(id)])
		if points.size()>1:draw_polyline(points,Color(str(stroke.color)),5,true)
	for pair in layout.transfers:
		draw_dashed_line(layout.positions[str(pair[0])],layout.positions[str(pair[1])],Color("#223745"),3,5,true)
	for id in layout.positions:
		draw_circle(layout.positions[id],5,Color.WHITE);draw_arc(layout.positions[id],5,0,TAU,20,Color("#223745"),2,true)
		draw_string(font,layout.labels[id]+Vector2(0,21),layout.names[id],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("#223745"))
