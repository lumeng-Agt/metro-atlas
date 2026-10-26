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
	# Future road-corridor references are a separate source class. They are
	# never relabelled as surveyed track or allowed to overwrite a rail pair.
	var planning_path:="res://data/planning_corridors.json"
	if FileAccess.file_exists(planning_path):
		var planning:Variant=JSON.parse_string(FileAccess.get_file_as_string(planning_path))
		if not planning is Dictionary or str(planning.get("coordinateSystem",""))!="EPSG:4326":push_error("规划走廊坐标系不一致，未载入。");return
		_data["planningAlignments"]=[]
		for item in planning.get("alignments",[]):
			if str(item.get("sourceKind",""))!="official_road_corridor" or str(item.get("appliesTo",""))!="planned_construction" or str(item.get("coordinateSystem",""))!="EPSG:4326" or not str(item.get("source","")).begins_with("https://") or item.get("sourceRoadWayIds",[]).is_empty() or item.get("points",[]).size()<3:
				push_error("规划走廊缺少独立来源、道路参照或连续几何，未载入。");continue
			var pair:=str(item.get("fromId",""))+"|"+str(item.get("toId",""))
			var reverse_pair:=str(item.get("toId",""))+"|"+str(item.get("fromId",""))
			if _pairs.has(pair) or _pairs.has(reverse_pair):push_error("规划走廊不能覆盖已有轨道参考。");continue
			var reference:Dictionary=item.duplicate(true);reference["referenceVersion"]=str(planning.get("version",""))
			_pairs[pair]=reference;_data.planningAlignments.append(reference)

static func version() -> String:
	load_data();return str(_data.get("version","unavailable"))

static func station_reference(id:String) -> Dictionary:
	load_data();return _data.get("stationReferences",{}).get(id,{}).duplicate(true)

static func planning_corridor(id:String) -> Dictionary:
	load_data()
	for item in _data.get("planningAlignments",[]):
		if str(item.get("id",""))==id:return item.duplicate(true)
	return {}

static func planning_corridor_issue(points:Array,id:String,ref_lat:float,tolerance:float) -> String:
	var reference:=planning_corridor(id)
	if reference.is_empty() or reference.get("points",[]).size()<3 or tolerance<=0:return "本区间规划走廊资料缺失，请重新载入资料包。"
	if points.size()<2:return "本区间尚无可核对的实际轨道几何。"
	if corridor_issue(points,reference.points,ref_lat,tolerance):return "区间偏离公开道路走廊或跳过必经走向，请查看支线参考。"
	return ""

static func between(a:String,b:String) -> Dictionary:
	load_data()
	var direct:Dictionary=_pairs.get(a+"|"+b,{})
	if not direct.is_empty():return direct.duplicate(true)
	var reverse:Dictionary=_pairs.get(b+"|"+a,{})
	if reverse.is_empty():return {}
	var result:=reverse.duplicate(true);result.points.reverse();result.fromId=a;result.toId=b
	return result

static func for_stations(a:Dictionary,b:Dictionary) -> Dictionary:
	# A physical station's geographic reference can differ from the shared
	# complex centre, notably an elevated infill next to an underground line.
	var starts:Array=[];var finishes:Array=[]
	for key in ["referenceId","stationInstanceId","historicalId"]:
		var start:=str(a.get(key,""));var finish:=str(b.get(key,""))
		if not start.is_empty() and not starts.has(start):starts.append(start)
		if not finish.is_empty() and not finishes.has(finish):finishes.append(finish)
	# Old saves lack referenceId. Resolve each endpoint separately so an old
	# terminal and a new line-specific infill still use the same source as the
	# assisted builder, rather than falling back to a free-hand curve.
	for start in starts:
		for finish in finishes:
			var ref:=between(str(start),str(finish))
			if not ref.is_empty():return ref
	return {}

static func heading(target_id:String,groups:Array,ref_lat:float,line_id:String="") -> float:
	for group in groups:
		if not line_id.is_empty() and str(group.get("historicalLineId",""))!=line_id:continue
		var ids:Array=[]
		for id in group.get("stationIds",[]):ids.append(str(group.get("stationReferenceIds",{}).get(str(id),id)))
		var index:=ids.find(target_id)
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
	if str(data.get("sourceKind",""))=="official_road_corridor":return "规划道路走廊 · 近似示意，非施工线位"
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
	return {"edge":{"id":"preview","aNodeId":str(start.get("nodeId","")),"bNodeId":str(finish.get("nodeId","")),"geometry":"reference_polyline","referencePoints":result,"referenceAlignmentId":str(alignment.id),"referenceVersion":str(alignment.get("referenceVersion",version())),"referencePrecision":str(alignment.get("precision","approximate_corridor")),"routeIds":[],"depthM":start.get("depthM",-15)},"points":result,"lengthM":length,"issue":"","referenceLabel":label_for(alignment),"revision":int(state.get("revision",0))}

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
