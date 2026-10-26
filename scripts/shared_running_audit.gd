class_name SharedRunningAudit
extends RefCounted
const Paths=preload("res://scripts/route_path.gd")

static func definition_errors(network:Dictionary) -> Array[String]:
	var result:Array[String]=[];var expected:Dictionary={}
	for item in network.get("sharedRunningEvidence",[]):
		var key:=str(item.get("physicalLineId",""))+"|"+str(item.get("serviceLineId",""))
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
	return result

static func _segment_paths(routes:Array,a:String,b:String) -> Array:
	var result:Array=[]
	for route in routes:
		for direction in route.get("directions",[]):
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
