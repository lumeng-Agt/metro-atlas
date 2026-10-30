extends Control
var map:MapView
var points:Array=[]
var elapsed:=0.0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
func pulse(coordinates:Array) -> void:
	if not UiPreferences.load_ui_motion_enabled():return
	points=coordinates.slice(0,12).duplicate(true);elapsed=0;set_process(true);queue_redraw()
func _process(delta:float) -> void:
	elapsed+=delta
	if elapsed>=0.45:points.clear();set_process(false)
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(map):return
	var t:=elapsed/0.45
	for coordinate in points:draw_arc(map._to_screen(coordinate),9+24*t,0,TAU,32,Color(0.3,0.9,0.75,1-t),3,true)
