extends Control
var layout:Dictionary={}
var font:Font
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#f0f3f5"))
	if not layout.get("ok",false):return
	var sections:={}
	for stroke in layout.strokes:
		for index in range(stroke.ids.size()-1):
			var a:=str(stroke.ids[index]);var b:=str(stroke.ids[index+1])
			var key:="%s|%s"%[a,b] if a<b else "%s|%s"%[b,a]
			if not sections.has(key):sections[key]={"a":layout.positions[a],"b":layout.positions[b],"colors":[],"openColors":{}}
			if not sections[key].colors.has(str(stroke.color)):sections[key].colors.append(str(stroke.color))
			if not bool(stroke.get("planned",false)):sections[key].openColors[str(stroke.color)]=true
	for section in sections.values():
		var normal:Vector2=(section.b-section.a).normalized().orthogonal()
		for index in range(section.colors.size()):
			var offset:=normal*(float(index)-float(section.colors.size()-1)*0.5)*3
			if section.openColors.has(section.colors[index]):draw_line(section.a+offset,section.b+offset,Color(section.colors[index]),3 if section.colors.size()>1 else 5,true)
			else:draw_dashed_line(section.a+offset,section.b+offset,Color(section.colors[index]),3,8,true)
	for pair in layout.transfers:
		draw_dashed_line(layout.positions[str(pair[0])],layout.positions[str(pair[1])],Color("#223745"),3,5,true)
		draw_arc(layout.positions[str(pair[0])],9,0,TAU,24,Color("#223745"),2,true)
	for id in layout.positions:
		draw_circle(layout.positions[id],5,Color.WHITE);draw_arc(layout.positions[id],5,0,TAU,20,Color("#223745"),2,true)
	for id in layout.labels:
		var point:Vector2=layout.positions[id];var label_position:Vector2=layout.labels[id]
		if point.distance_to(label_position)>70:draw_line(point,label_position+Vector2(0,13),Color("#9daeb8"),1,true)
		draw_string(font,layout.labels[id]+Vector2(0,21),layout.names[id],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("#223745"))
