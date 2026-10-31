extends Control
var map:MapView
var lines:Array=[]
var stations:Array=[]
var total_m:=0.0
var progress:=1.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func prepare(before:Dictionary,after:Dictionary,ref_lat:float) -> void:
	lines=[];stations=[];total_m=0
	var old_edges:={};var old_stations:={}
	for edge in TrackNetwork.all_physical_edges(before):old_edges[str(edge.id)]=edge
	for station in before.get("stations",[]):old_stations[str(station.id)]=station
	for edge in TrackNetwork.all_physical_edges(after):
		if old_edges.get(str(edge.id))==edge:continue
		var points:=TrackNetwork.edge_points(edge,after,ref_lat,32)
		if points.size()<2:continue
		var length:=0.0
		for index in range(1,points.size()):length+=Geo.local_m(points[index],ref_lat).distance_to(Geo.local_m(points[index-1],ref_lat))
		lines.append({"points":points,"lengthM":length});total_m+=length
	for station in after.get("stations",[]):
		if not old_stations.has(str(station.id)):stations.append(station)
	progress=0;queue_redraw()

func _draw() -> void:
	if not is_instance_valid(map) or progress>=1:return
	var budget:=total_m*clampf(progress,0,1)
	for line in lines:
		if budget<=0:break
		var source:Array=line.points
		var points:=PackedVector2Array([map._to_screen(source[0])])
		for index in range(1,source.size()):
			var length:=Geo.local_m(source[index],map.geometry_ref_lat).distance_to(Geo.local_m(source[index-1],map.geometry_ref_lat))
			if budget>=length:points.append(map._to_screen(source[index]));budget-=length
			else:
				points.append(map._to_screen(source[index-1]).lerp(map._to_screen(source[index]),budget/maxf(length,0.001)));budget=0;break
		if points.size()>1:draw_polyline(points,Color.WHITE,8,true);draw_polyline(points,Color("#36b6a3"),4,true)
	for index in range(stations.size()):
		if float(index+1)/maxi(1,stations.size())>progress:break
		var station:Dictionary=stations[index]
		var point:=map._to_screen(station.latlng)
		draw_circle(point,6,Color.WHITE);draw_circle(point,4,Color("#36b6a3"))
		draw_string(map.get_theme_default_font(),point+Vector2(9,-10),str(station.name),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("#203947"))
