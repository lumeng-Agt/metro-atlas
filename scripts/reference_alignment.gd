class_name ReferenceAlignment
extends RefCounted

## Source geometry is immutable; player track stores its own committed copy.
static var _data: Dictionary = {}
static var _pairs: Dictionary = {}
static func load_data() -> void:
	if not _data.is_empty():return
	var file:=FileAccess.open("res://data/reference_alignments.json",FileAccess.READ)
	if file==null:return
	var parsed:Variant=JSON.parse_string(file.get_as_text());file.close()
	if not parsed is Dictionary:return
	if str(parsed.get("coordinateSystem",""))!="EPSG:4326":push_error("参考资料坐标系不一致，拒绝直接叠加高德或其他坐标。");return
	_data=parsed
	for item in _data.get("alignments",[]):
		if str(item.get("coordinateSystem",""))!="EPSG:4326":push_error("区间坐标系不一致，已忽略。");continue
		_pairs[str(item.fromId)+"|"+str(item.toId)]=item

static func version() -> String:
	load_data();return str(_data.get("version","unavailable"))

static func station_reference(id:String) -> Dictionary:
	load_data();return _data.get("stationReferences",{}).get(id,{}).duplicate(true)

static func between(a:String,b:String) -> Dictionary:
	load_data()
	var direct:Dictionary=_pairs.get(a+"|"+b,{})
	if not direct.is_empty():return direct.duplicate(true)
	var reverse:Dictionary=_pairs.get(b+"|"+a,{})
	if reverse.is_empty():return {}
	var result:=reverse.duplicate(true);result.points.reverse();result.fromId=a;result.toId=b
	return result

static func heading(target_id:String,groups:Array,ref_lat:float) -> float:
	for group in groups:
		var ids:Array=group.get("stationIds",[]);var index:=ids.find(target_id)
		if index<0:continue
		var other:=index+1 if index+1<ids.size() else index-1
		if other<0:continue
		var alignment:=between(target_id,str(ids[other]));var points:Array=alignment.get("points",[])
		if points.size()<2:continue
		var origin:=Geo.local_m(points[0],ref_lat)
		for point in points.slice(1):
			var direction:=Geo.local_m(point,ref_lat)-origin
			if direction.length()>35:return fposmod(90-rad_to_deg(direction.angle()),180)
	return -1

static func label_for(data:Dictionary) -> String:
	if data.is_empty():return "示意资料 · 连续线位待核验"
	return "核验线位" if str(data.get("precision",""))=="verified_alignment" else "近似走廊 · OSM轨道 / 历史与高德对照待核验"

static func preview(alignment:Dictionary,start:Dictionary,finish:Dictionary,state:Dictionary,ref_lat:float) -> Dictionary:
	var source:Array=alignment.get("points",[])
	if source.size()<2:return {"issue":"本区间尚无连续参考线位。请在高级编辑中使用示意连接，或查看资料缺口。"}
	var a:=Geo.local_m(start.latlng,ref_lat);var b:=Geo.local_m(finish.latlng,ref_lat)
	var local:Array[Vector2]=[]
	for p in source:local.append(Geo.local_m(p,ref_lat))
	# Keep the middle of the source corridor. Only the terminal connections are
	# adapted to the placed station; tangent continuity has explicit handles.
	var first:=0;var last:=local.size()-1
	while first<last-1 and local[first].distance_to(a)<100:first+=1
	while last>first+1 and local[last].distance_to(b)<100:last-=1
	var middle:Array[Vector2]=local.slice(first,last+1)
	if middle.size()<2:return {"issue":"参考区间过短，无法保留连续走向；请核对站位。"}
	var station_a:=WorldData.find_station(state,str(start.get("stationId","")))
	var station_b:=WorldData.find_station(state,str(finish.get("stationId","")))
	var ta:=WorldData.station_outward(station_a,str(start.get("side","end")))
	var tb:=WorldData.station_outward(station_b,str(finish.get("side","start")))
	if ta.dot((middle[mini(8,middle.size()-1)]-a).normalized())< -0.8 or tb.dot((middle[maxi(0,middle.size()-9)]-b).normalized())< -0.8:return {"issue":"所选站端背向本区间。请选择车站另一端，或调整站体朝向。"}
	if a.distance_to(middle[0])>400 or b.distance_to(middle[-1])>400:return {"issue":"车站与参考线位距离过大，请调整到目标站区。"}
	var result:Array=[]
	var near_a:=(middle[1]-middle[0]).normalized();var near_b:=(middle[-1]-middle[-2]).normalized()
	_append_curve(result,a,a+ta*minf(55,a.distance_to(middle[0])*0.35),middle[0]-near_a*25,middle[0],ref_lat)
	for p in middle.slice(1,-1):result.append(Geo.from_local(p,ref_lat))
	_append_curve(result,middle[-1],middle[-1]+near_b*25,b+tb*minf(55,b.distance_to(middle[-1])*0.35),b,ref_lat)
	result[0]=start.latlng.duplicate();result[-1]=finish.latlng.duplicate()
	var length:=0.0
	for i in range(result.size()-1):length+=Geo.local_m(result[i],ref_lat).distance_to(Geo.local_m(result[i+1],ref_lat))
	return {"edge":{"id":"preview","aNodeId":str(start.get("nodeId","")),"bNodeId":str(finish.get("nodeId","")),"geometry":"reference_polyline","referencePoints":result,"referenceAlignmentId":str(alignment.id),"referenceVersion":version(),"referencePrecision":str(alignment.get("precision","approximate_corridor")),"routeIds":[],"depthM":start.get("depthM",-15)},"points":result,"lengthM":length,"issue":"","referenceLabel":label_for(alignment),"revision":int(state.get("revision",0))}

static func sides(a:Dictionary,b:Dictionary,alignment:Dictionary,lat:float) -> Array:
	var points:Array=alignment.get("points",[])
	if points.size()<2:return []
	var forward:=Geo.local_m(points[mini(points.size()-1,8)],lat)-Geo.local_m(points[0],lat)
	var backward:=Geo.local_m(points[maxi(0,points.size()-9)],lat)-Geo.local_m(points[-1],lat)
	return ["end" if WorldData.station_outward(a,"end").dot(forward)>0 else "start","end" if WorldData.station_outward(b,"end").dot(backward)>0 else "start"]

static func _append_curve(out:Array,a:Vector2,b:Vector2,c:Vector2,d:Vector2,lat:float) -> void:
	for i in range(13):
		var t:=float(i)/12;var u:=1-t
		out.append(Geo.from_local(a*u*u*u+b*3*u*u*t+c*3*u*t*t+d*t*t*t,lat))

static func corridor_issue(points:Array,reference:Array,ref_lat:float,tolerance:float=80) -> bool:
	if points.size()<2 or reference.size()<2:return false
	# Test in both directions: excursions and shortcuts are both disallowed.
	for pair in [[points,reference],[reference,points]]:
		for point in pair[0]:
			var p:=Geo.local_m(point,ref_lat);var nearest:=INF
			for i in range(pair[1].size()-1):nearest=minf(nearest,p.distance_to(Geometry2D.get_closest_point_to_segment(p,Geo.local_m(pair[1][i],ref_lat),Geo.local_m(pair[1][i+1],ref_lat))))
			if nearest>tolerance:return true
	return false
