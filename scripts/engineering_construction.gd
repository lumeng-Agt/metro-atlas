extends RefCounted

## Non-passenger construction uses actual nodes and edges. It never adds a
## station, a service, or a transfer to satisfy a zero-station project. Genuine
## new station bodies are separate, explicit station targets in the shared builder.
static func is_group(group:Dictionary) -> bool:
	return str(group.get("taskKind",""))=="engineering_track"

static func coverage_errors(group:Dictionary,expected:Dictionary) -> Array[String]:
	var errors:=definition_errors(group)
	if not errors.is_empty():return errors
	var new_stations:Array=group.get("newStationIds",[]).duplicate();new_stations.sort()
	var expected_new:Array=expected.get("newStationIds",[]).duplicate();expected_new.sort()
	if new_stations!=expected_new:errors.append("工程任务新增站体范围与独立目标不符。")
	if not is_group(group):errors.append("工程目标被替换成了客运线路任务。")
	var definitions:Dictionary={};var anchors:Array=[]
	for endpoint in expected.get("engineeringEndpoints",[]):
		definitions[str(endpoint.id)]=endpoint
		if endpoint.has("stationId") and not anchors.has(str(endpoint.stationId)):anchors.append(str(endpoint.stationId))
	var actual_anchors:Array=group.get("stationIds",[]).duplicate();anchors.sort();actual_anchors.sort()
	if actual_anchors!=anchors:errors.append("工程任务的既有接头范围不符；不得增设虚构车站。")
	if group.get("engineeringEndpoints",[]).size()!=definitions.size():errors.append("工程接口数量不符。")
	for endpoint in group.get("engineeringEndpoints",[]):
		var wanted:Dictionary=definitions.get(str(endpoint.get("id","")),{})
		if wanted.is_empty():errors.append("工程接口不在独立目标中。");continue
		for key in ["name","stationId","stationInstanceId","latlng","toleranceM","side","depthM"]:
			if endpoint.get(key)!=wanted.get(key):errors.append("工程接口「%s」的%s与独立目标不符。"%[str(wanted.get("name","接口")),key])
	var sections:Array=expected.get("engineeringSegments",[])
	if sections.size()!=group.get("engineeringSegments",[]).size():errors.append("工程区段数量不符。")
	for wanted in sections:
		var found:=false
		for section in group.get("engineeringSegments",[]):
			if str(section.get("fromId",""))==str(wanted.get("fromId","")) and str(section.get("toId",""))==str(wanted.get("toId","")):
				found=true
				if section.get("points",[])!=wanted.get("points",[]):errors.append("工程区段参考走廊与独立目标不符。")
				if section.get("corridorToleranceM")!=wanted.get("corridorToleranceM"):errors.append("工程走廊容差与独立目标不符。")
		if not found:errors.append("缺少独立目标中的工程区段。")
	return errors

static func definition_errors(group:Dictionary,known_station_ids:Array=[]) -> Array[String]:
	var errors:Array[String]=[];var ids:Dictionary={}
	if str(group.get("source","")).is_empty():errors.append("工程任务缺少范围来源。")
	if not group.get("engineeringEndpoints",[]) is Array or not group.get("engineeringSegments",[]) is Array:return ["工程接口和区间必须是列表。"]
	for station_id in group.get("stationIds",[]):
		if not known_station_ids.is_empty() and not known_station_ids.has(str(station_id)):errors.append("工程任务引用未知接头站区。")
	for endpoint in group.get("engineeringEndpoints",[]):
		if not endpoint is Dictionary:errors.append("工程接口格式无效。");continue
		var id:=str(endpoint.get("id",""))
		if id.is_empty() or ids.has(id):errors.append("工程接口编号为空或重复。")
		ids[id]=true
		if str(endpoint.get("name","")).is_empty():errors.append("工程接口缺少名称。")
		if endpoint.has("stationId"):
			if not known_station_ids.is_empty() and not known_station_ids.has(str(endpoint.stationId)):errors.append("工程接头引用未知车站。")
			if str(endpoint.get("stationInstanceId","")).is_empty():errors.append("工程接头必须指定线路站体。")
		else:
			var point:Variant=endpoint.get("latlng")
			if not _coordinate_valid(point):errors.append("工程接口坐标无效。")
			if not _positive_finite(endpoint.get("toleranceM")):errors.append("工程接口缺少有效位置容差。")
	var anchors:Array=[]
	for endpoint in group.get("engineeringEndpoints",[]):
		if endpoint is Dictionary and endpoint.has("stationId"):anchors.append(str(endpoint.stationId))
	for station_id in group.get("newStationIds",[]):
		if not anchors.has(str(station_id)):errors.append("工程新增站体必须对应明确客运站点，不能将接口当作车站。")
	if ids.size()<2 or group.get("engineeringSegments",[]).is_empty():errors.append("工程任务必须包含实际区间。")
	for segment in group.get("engineeringSegments",[]):
		if not segment is Dictionary:errors.append("工程区间格式无效。");continue
		if not ids.has(str(segment.get("fromId",""))) or not ids.has(str(segment.get("toId",""))) or str(segment.get("fromId",""))==str(segment.get("toId","")):errors.append("工程区间端点无效。")
		if not segment.get("points",[]) is Array:errors.append("工程走廊必须是坐标列表。");continue
		if segment.get("points",[]).size()<2:errors.append("工程区间缺少参考走廊。")
		if not _positive_finite(segment.get("corridorToleranceM")):errors.append("工程区间缺少有效走廊容差。")
		for point in segment.get("points",[]):
			if not _coordinate_valid(point):errors.append("工程走廊坐标无效。")
	return errors

static func _positive_finite(value:Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>0

static func _coordinate_valid(point:Variant) -> bool:
	if not point is Array or point.size()!=2:return false
	for value in point:
		if not (value is int or value is float) or not is_finite(float(value)):return false
	return absf(float(point[0]))<=90 and absf(float(point[1]))<=180

static func _station(world:Dictionary,endpoint:Dictionary) -> Dictionary:
	for station in world.get("stations",[]):
		if str(station.get("stationInstanceId",station.get("id","")))==str(endpoint.get("stationInstanceId","")):return station
	return {}

static func endpoint_point(world:Dictionary,endpoint:Dictionary) -> Array:
	if endpoint.has("stationId"):return _station(world,endpoint).get("latlng",[])
	return endpoint.get("latlng",[])

static func _resolve(world:Dictionary,endpoint:Dictionary,latitude:float,toward:Array=[]) -> Dictionary:
	if endpoint.has("stationId"):
		var station:=_station(world,endpoint)
		if station.is_empty():return {"error":"先建设「%s」的对应线路站体，再连接工程区间。"%str(endpoint.name)}
		var options:Array=[]
		for side in ["start","end"]:
			if str(endpoint.get("side","outward")) not in ["outward",side]:continue
			var node:=TrackNetwork.find_node(world,TrackNetwork.station_node_id(station,side))
			if not node.is_empty():options.append(node)
		if options.is_empty():return {"error":"「%s」接轨端不存在，请重新检查站体。"%str(endpoint.name)}
		if toward.size()==2:options.sort_custom(func(a:Dictionary,b:Dictionary):return Geo.local_m(a.latlng,latitude).distance_to(Geo.local_m(toward,latitude))<Geo.local_m(b.latlng,latitude).distance_to(Geo.local_m(toward,latitude)))
		return {"node":options[0]}
	var bound:Array=[];var nearby:Array=[]
	for node in world.get("trackNodes",[]):
		if not str(node.get("stationId","")).is_empty():continue
		if str(node.get("engineeringTargetId",""))==str(endpoint.id):bound.append(node)
		elif Geo.local_m(node.latlng,latitude).distance_to(Geo.local_m(endpoint.latlng,latitude))<=float(endpoint.toleranceM):nearby.append(node)
	if bound.size()>1 or (bound.is_empty() and nearby.size()>1):return {"error":"「%s」附近有多个轨道节点，请保留一个明确的接轨接口。"%str(endpoint.name)}
	var found:Array=bound if not bound.is_empty() else nearby
	if found.is_empty():return {"error":"尚未建设「%s」轨道接口；这里不需要车站。"%str(endpoint.name)}
	if Geo.local_m(found[0].latlng,latitude).distance_to(Geo.local_m(endpoint.latlng,latitude))>float(endpoint.toleranceM):return {"error":"「%s」轨道接口超出本期允许范围。"%str(endpoint.name)}
	return {"node":found[0]}

static func physical_path(world:Dictionary,index:Dictionary,from_id:String,to_id:String) -> Dictionary:
	if from_id==to_id:return {}
	var queue:Array=[from_id];var seen:Dictionary={from_id:true};var previous:Dictionary={};var cursor:=0
	while cursor<queue.size():
		var current:=str(queue[cursor]);cursor+=1
		if current==to_id:break
		for connection in index.get("adjacency",{}).get(current,[]):
			# A platform or a transfer cannot stand in for an engineering tunnel.
			if bool(connection.edge.get("platform",false)) or bool(connection.edge.get("transfer",false)):continue
			var next:=str(connection.to)
			if seen.has(next):continue
			seen[next]=true;previous[next]={"from":current,"connection":connection};queue.append(next)
	if not previous.has(to_id):return {}
	var edges:Array=[];var node:=to_id;var length:=0.0;var points:Array=[]
	while node!=from_id:
		var step:Dictionary=previous[node];edges.push_front(step.connection);node=str(step.from);length+=float(step.connection.lengthM)
	for connection in edges:
		var piece:=TrackNetwork.edge_points(connection.edge,world,float(index.refLat),24,index.nodesById)
		if not bool(connection.forward):piece.reverse()
		points.append_array(piece)
	return {"edges":edges,"points":points,"lengthM":length}

static func evaluate(world:Dictionary,group:Dictionary,index:Dictionary={}) -> Dictionary:
	var issues:Array=[];var paths:Array=[];var latitude:=float(WorldData.city(str(world.cityId)).center[0])
	var errors:=definition_errors(group)
	if not errors.is_empty():return {"complete":false,"issues":[{"text":"；".join(errors),"kind":"engineering"}],"paths":[]}
	if index.is_empty():index=TrackNetwork.build_path_index(world,latitude)
	var definitions:Dictionary={}
	for endpoint in group.engineeringEndpoints:definitions[str(endpoint.id)]=endpoint
	for segment in group.engineeringSegments:
		var a:Dictionary=definitions[str(segment.fromId)];var b:Dictionary=definitions[str(segment.toId)]
		var ra:=_resolve(world,a,latitude,endpoint_point(world,b));var rb:=_resolve(world,b,latitude,endpoint_point(world,a))
		var failure:=str(ra.get("error",rb.get("error","")))
		if failure.is_empty():
			var path:=physical_path(world,index,str(ra.node.id),str(rb.node.id))
			if path.is_empty():failure="工程区间尚未接通：%s—%s。"%[str(a.name),str(b.name)]
			elif ReferenceAlignment.corridor_issue(path.points,segment.points,latitude,float(segment.corridorToleranceM)):failure="%s—%s偏离本期工程走廊，请检查轨道走向。"%[str(a.name),str(b.name)]
			else:paths.append(path)
		if not failure.is_empty():issues.append({"text":failure,"kind":"engineering","latlng":endpoint_point(world,b)})
	return {"complete":issues.is_empty() and paths.size()==group.engineeringSegments.size(),"issues":issues,"paths":paths}

static func add_preview(candidate:Dictionary,group:Dictionary) -> Dictionary:
	var errors:=definition_errors(group)
	if not errors.is_empty():return {"issue":"；".join(errors)}
	var latitude:=float(WorldData.city(str(candidate.cityId)).center[0]);var definitions:Dictionary={}
	for endpoint in group.engineeringEndpoints:
		definitions[str(endpoint.id)]=endpoint
		if endpoint.has("stationId"):continue
		var resolved:=_resolve(candidate,endpoint,latitude)
		if resolved.has("node"):continue
		# Only absence permits creation. Duplicate or moved explicit bindings
		# require a player correction; the preview never moves existing nodes.
		if candidate.trackNodes.any(func(node:Dictionary):return str(node.get("engineeringTargetId",""))==str(endpoint.id)) or candidate.trackNodes.any(func(node:Dictionary):return str(node.get("stationId","")).is_empty() and Geo.local_m(node.latlng,latitude).distance_to(Geo.local_m(endpoint.latlng,latitude))<=float(endpoint.toleranceM)):return {"issue":str(resolved.error)}
		var node:=TrackNetwork.create_node(candidate,endpoint.latlng,float(endpoint.get("depthM",-15)))
		node["engineeringTargetId"]=str(endpoint.id);node["engineeringName"]=str(endpoint.name)
	for segment in group.engineeringSegments:
		var a:Dictionary=definitions[str(segment.fromId)];var b:Dictionary=definitions[str(segment.toId)]
		var ra:=_resolve(candidate,a,latitude,endpoint_point(candidate,b));var rb:=_resolve(candidate,b,latitude,endpoint_point(candidate,a))
		if ra.has("error") or rb.has("error"):return {"issue":str(ra.get("error",rb.get("error","工程接口无效。")))}
		var index:=TrackNetwork.build_path_index(candidate,latitude)
		if not physical_path(candidate,index,str(ra.node.id),str(rb.node.id)).is_empty():continue
		var points:Array=segment.points.duplicate(true);points[0]=ra.node.latlng.duplicate();points[-1]=rb.node.latlng.duplicate()
		candidate.trackEdges.append({"id":"engineering_%s_%d"%[str(group.get("taskId","")).sha256_text().substr(0,12),Time.get_ticks_usec()],"aNodeId":str(ra.node.id),"bNodeId":str(rb.node.id),"geometry":"reference_polyline","referencePoints":points,"referencePrecision":"approximate_corridor","engineeringTaskId":str(group.get("taskId","")),"source":str(group.source),"routeIds":[]})
	var checked:=evaluate(candidate,group)
	return {"issue":"" if bool(checked.complete) else str(checked.issues[0].text)}
