class_name SharedRunningAudit
extends RefCounted
const Paths=preload("res://scripts/route_path.gd")

static func definition_errors(network:Dictionary) -> Array[String]:
	var result:Array[String]=[];var expected:Dictionary={}
	for item in network.get("sharedRunningEvidence",[]):
		var key:=str(item.get("physicalLineId",""))+"|"+str(item.get("serviceLineId",""))
		if str(item.get("sharing",""))=="directional":
			var directional:Array=[]
			for section in network.get("sharedRunningSections",[]):
				if str(section.get("physicalLineId",""))+"|"+str(section.get("serviceLineId",""))!=key:continue
				for rule in section.get("directionalStationRules",[]):
					if str(rule.get("stationName",""))==str(item.get("stationName","")):directional.append(rule)
			if directional.size()!=1 or str(directional[0].get("sharedPatternId",""))!=str(item.get("sharedPatternId","")) or str(directional[0].get("independentPatternId",""))!=str(item.get("independentPatternId","")) or not str(directional[0].get("source","")).begins_with("https://"):result.append("方向性共轨资料缺少对应的完整站台要求。")
			continue
		if not expected.has(key):expected[key]=[]
		if not expected[key].has(str(item.get("stationName",""))):expected[key].append(str(item.get("stationName","")))
	for key in expected:
		var matching:Array=network.get("sharedRunningSections",[]).filter(func(rule:Dictionary):return str(rule.get("physicalLineId",""))+"|"+str(rule.get("serviceLineId",""))==str(key))
		if matching.size()!=1:result.append("共线资料没有对应的唯一实体范围要求。");continue
		var rule:Dictionary=matching[0];var names:Array=rule.get("stationNames",[])
		if names.size()!=expected[key].size() or not names.all(func(name:Variant):return expected[key].has(str(name))) or not expected[key].all(func(name:Variant):return names.has(name)) or not str(rule.get("source","")).begins_with("https://"):result.append("共线检查遗漏了已核对站点或缺少来源。")
	return result

## Independent physical-sharing requirement. A train calling at a similarly
## named parallel body, or taking copied parallel rails, is not shared running.
static func errors(world:Dictionary,rule:Dictionary) -> Array[String]:
	var result:Array[String]=[]
	var owner:=str(rule.get("physicalLineId",""));var service:=str(rule.get("serviceLineId",""));var names:Array=rule.get("stationNames",[])
	if owner.is_empty() or service.is_empty() or owner==service or names.size()<2 or not str(rule.get("source","")).begins_with("https://"):return ["共线运行缺少独立线路、站序或来源。"]
	var ids:Array[String]=[]
	for name in names:
		var bodies:Array=world.get("stations",[]).filter(func(s:Dictionary):return str(s.get("name",""))==str(name) and str(s.get("stationLineId",""))==owner)
		if bodies.size()!=1:result.append("共线站%s缺少唯一的所属线路实体。"%str(name));continue
		ids.append(str(bodies[0].id))
	if ids.size()!=names.size():return result
	for connection in world.get("transferConnections",[]):
		if str(connection.get("status","active"))!="active" or not connection.get("lineIds",[]).has(owner) or not connection.get("lineIds",[]).has(service):continue
		var at_shared:=false
		for instance in connection.get("stationInstanceIds",[]):
			var body:=WorldData.find_station(world,_body_id(world,str(instance)))
			if names.has(str(body.get("name",""))):at_shared=true
		if at_shared:result.append("真实共轨站仍保留两座独立站体之间的错误步行换乘。")
	var latitude:=float(WorldData.city(str(world.get("cityId",""))).get("center",[0])[0])
	var index:=TrackNetwork.build_path_index(world,latitude)
	var owner_routes:Array=[];var service_routes:Array=[]
	for route in world.get("routes",[]):
		var line:=str(route.get("historicalLineId",""))
		if line not in [owner,service] or bool(route.get("retired",false)) or not bool(route.get("open",false)):continue
		if not bool(Paths.for_route(route,world,latitude,index).get("valid",false)):continue
		if line==owner:owner_routes.append(route)
		else:service_routes.append(route)
	for position in range(ids.size()-1):
		var own_paths:=_segment_paths(owner_routes,ids[position],ids[position+1])
		var shared_paths:=_segment_paths(service_routes,ids[position],ids[position+1])
		if own_paths.is_empty() or shared_paths.is_empty() or not own_paths.any(func(path:Array):return shared_paths.has(path)):
			result.append("%s—%s没有由两条服务共同使用同一站体和实体轨道。"%[str(names[position]),str(names[position+1])])
	for directional in rule.get("directionalStationRules",[]):result.append_array(_directional_errors(world,directional,owner_routes,service_routes))
	return result

static func _directional_errors(world:Dictionary,rule:Dictionary,owner_routes:Array,service_routes:Array) -> Array[String]:
	var result:Array[String]=[]
	var shared_id:=_body_id(world,str(rule.get("sharedStationInstanceId","")))
	var own_id:=_body_id(world,str(rule.get("independentStationInstanceId","")))
	var neighbor:=""
	for route in owner_routes:
		for direction in route.get("directions",[]):
			for id in direction.get("stationIds",[]):
				if str(WorldData.find_station(world,str(id)).get("name",""))==str(rule.get("precedingStationName","")):neighbor=str(id)
	if shared_id.is_empty() or own_id.is_empty() or shared_id==own_id or neighbor.is_empty() or not str(rule.get("source","")).begins_with("https://"):return ["方向性共轨缺少独立站台、相邻站体或来源。"]
	var owner_paths:=_segment_paths(owner_routes,neighbor,shared_id)
	var inner_paths:=_segment_paths(service_routes,neighbor,shared_id,str(rule.get("sharedPatternId","")))
	var outer_paths:=_segment_paths(service_routes,neighbor,own_id,str(rule.get("independentPatternId","")))
	if owner_paths.is_empty() or inner_paths.is_empty() or not owner_paths.any(func(path:Array):return inner_paths.has(path)):result.append("指定方向没有使用实际共用站台及同一实体轨道。")
	if outer_paths.is_empty():result.append("独立方向缺少其专用站台和接轨路径。")
	if service_routes.any(func(route:Dictionary):return route.get("directions",[]).any(func(direction:Dictionary):return str(direction.get("servicePatternId",""))==str(rule.get("independentPatternId","")) and direction.get("stationIds",[]).has(shared_id))):result.append("独立方向仍错误停靠共用站台。")
	return result

static func _body_id(world:Dictionary,instance:String) -> String:
	for station in world.get("stations",[]):
		if str(station.get("stationInstanceId",station.get("id","")))==instance:return str(station.id)
	return ""

static func _segment_paths(routes:Array,a:String,b:String,pattern:String="") -> Array:
	var result:Array=[]
	for route in routes:
		for direction in route.get("directions",[]):
			if not pattern.is_empty() and str(direction.get("servicePatternId",""))!=pattern:continue
			var ids:Array=direction.get("stationIds",[]);var paths:Array=direction.get("edgePathsBySegment",[])
			for position in range(ids.size()-1):
				if position>=paths.size():continue
				var reverse:bool=ids[position]==b and ids[position+1]==a
				if not reverse and not (ids[position]==a and ids[position+1]==b):continue
				var refs:Array=paths[position].duplicate(true)
				if reverse:refs.reverse()
				var normalized:Array=[]
				for ref in refs:normalized.append({"id":str(ref.get("id","")),"forward":not bool(ref.get("forward",true)) if reverse else bool(ref.get("forward",true))})
				if not normalized.is_empty():result.append(normalized)
	return result
