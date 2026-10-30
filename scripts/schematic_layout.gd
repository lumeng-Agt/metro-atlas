class_name SchematicLayout
extends RefCounted

## Topology is copied from validated paths, never inferred from crossings.
static func build(world:Dictionary,bounds:Vector2) -> Dictionary:
	var positions:={};var names:={};var strokes:Array=[];var transfers:Array=[]
	var stations:Dictionary={}
	for station in world.get("stations",[]):stations[str(station.id)]=station
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for route in world.get("routes",[]):
		if bool(route.get("retired",false)):continue
		var path:=RoutePath.for_route(route,world,float(WorldData.city(str(world.get("cityId","shanghai"))).get("center",[31,121])[0]))
		if not path.get("valid",false):return {"ok":false,"reason":"存在线路路径尚未接通，请使用地理视图核对。"}
		for direction in path.get("directions",[]):
			var ids:Array=direction.get("stationIds",[]).duplicate()
			strokes.append({"ids":ids,"color":route.get("color","#248eaa"),"name":route.get("name","")})
			for id in ids:
				if not stations.has(str(id)):return {"ok":false,"reason":"线路引用的站体不存在。"}
				var station:Dictionary=stations[str(id)]
				var point:=Geo.project(station.latlng,12)
				positions[str(id)]=point;names[str(id)]=str(station.name);low=low.min(point);high=high.max(point)
	if positions.is_empty():return {"ok":false,"reason":"尚无已确认线路，可继续查看地理路网。"}
	var span:=high-low;var scale:=minf((bounds.x-160)/maxf(1,span.x),(bounds.y-160)/maxf(1,span.y))
	for id in positions:positions[id]=(positions[id]-(low+high)*0.5)*scale+bounds*0.5
	for transfer in world.get("transferConnections",[]):
		if transfer.get("status","")!="active":continue
		var pair:Array=transfer.get("stationInstanceIds",[])
		if pair.size()==2 and positions.has(str(pair[0])) and positions.has(str(pair[1])):transfers.append(pair.duplicate())
	var labels:={};var occupied:Array[Rect2]=[]
	var ids:Array=positions.keys();ids.sort()
	for id in ids:
		var width:=minf(260,str(names[id]).length()*17+8);var placed:=false
		for offset in [Vector2(12,-28),Vector2(12,9),Vector2(-width-12,-28),Vector2(-width-12,9),Vector2(-width*0.5,-50),Vector2(-width*0.5,28)]:
			var box:=Rect2(positions[id]+offset,Vector2(width,27))
			if not Rect2(Vector2.ZERO,bounds).encloses(box):continue
			var collision:=false
			for prior in occupied:
				if prior.intersects(box):collision=true;break
			if collision:continue
			labels[id]=box.position;occupied.append(box);placed=true;break
		if not placed:return {"ok":false,"reason":"当前范围站名过密，地理视图能更清楚地显示这段路网。"}
	return {"ok":true,"positions":positions,"names":names,"labels":labels,"strokes":strokes,"transfers":transfers}
