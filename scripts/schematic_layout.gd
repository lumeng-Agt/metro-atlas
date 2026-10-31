class_name SchematicLayout
extends RefCounted

## Topology is copied from validated paths, never inferred from crossings.
static func build(world:Dictionary,bounds:Vector2) -> Dictionary:
	return _build(_snapshot(world),bounds)

static func _snapshot(world:Dictionary) -> Dictionary:
	var result:={"cityId":world.get("cityId","shanghai")}
	for key in ["stations","routes","trackNodes","trackEdges","trackLinks","transferConnections"]:result[key]=world.get(key,[]).duplicate(true)
	return result

static func _build(world:Dictionary,bounds:Vector2) -> Dictionary:
	if not bounds.is_finite() or bounds.x<160 or bounds.y<160:return {"ok":false,"kind":"bounds","reason":"线路图画布过小，请扩大窗口或查看地理视图。"}
	var positions:={};var names:={};var strokes:Array=[];var transfers:Array=[]
	var stations:Dictionary={};var by_instance:Dictionary={}
	for station in world.get("stations",[]):
		stations[str(station.id)]=station;by_instance[str(station.get("stationInstanceId",station.id))]=str(station.id)
	var ref_lat:=float(WorldData.city(str(world.get("cityId","shanghai"))).get("center",[31,121])[0])
	var path_index:=TrackNetwork.build_path_index(world,ref_lat)
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for route in world.get("routes",[]):
		if bool(route.get("retired",false)):continue
		var path:=RoutePath.for_route(route,world,ref_lat,path_index)
		if not path.get("valid",false):return {"ok":false,"kind":"path","reason":"线路%s路径尚未接通：%s"%[str(route.get("name",route.get("id",""))),str(path.get("errors",[]))]}
		for direction in path.get("directions",[]):
			var ids:Array=direction.get("stationIds",[]).duplicate()
			strokes.append({"ids":ids,"color":route.get("color","#248eaa"),"name":route.get("name",""),"planned":not bool(route.get("open",false))})
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
		if pair.size()==2:
			var a:=str(by_instance.get(str(pair[0]),str(pair[0])));var b:=str(by_instance.get(str(pair[1]),str(pair[1])))
			if positions.has(a) and positions.has(b):transfers.append([a,b])
	var labels:={};var cells:Dictionary={};var same_label:Dictionary={};var offset_cache:Dictionary={}
	for pair in transfers:
		if names[pair[0]]==names[pair[1]]:
			var a:=str(pair[0]);var b:=str(pair[1])
			while same_label.has(a):a=str(same_label[a])
			while same_label.has(b):b=str(same_label[b])
			if a!=b:same_label[b if a<b else a]=a if a<b else b
	var ids:Array=positions.keys();ids.sort()
	for id in ids:
		if same_label.has(id):continue
		var width:=float(str(names[id]).length()*17+8);var placed:=false
		if not offset_cache.has(width):offset_cache[width]=_label_offsets(width)
		for offset in offset_cache[width]:
			var box:=Rect2(positions[id]+offset,Vector2(width,27))
			if not Rect2(Vector2.ZERO,bounds).encloses(box) or _overlaps(cells,box):continue
			labels[id]=box.position;_occupy(cells,box);placed=true;break
		if not placed:return {"ok":false,"kind":"label","reason":"站名%s在%s附近暂时无法避让。"%[str(names[id]),str(positions[id])]}
	return {"ok":true,"positions":positions,"names":names,"labels":labels,"strokes":strokes,"transfers":transfers,"bounds":bounds}

static func fit(world:Dictionary,preferred:Vector2) -> Dictionary:
	var last_reason:=""
	var detached:=_snapshot(world)
	for factor in [1.0,2.0,3.0,4.0]:
		var result:=_build(detached,preferred*factor)
		if result.get("ok",false):return result
		if result.get("kind","")=="path":return result
		last_reason=str(result.get("reason",""))
	return {"ok":false,"reason":"线路图仍有无法避让的标签，请使用地理视图核对。"+last_reason}

static func _label_offsets(width:float) -> Array[Vector2]:
	var result:Array[Vector2]=[Vector2(12,-28),Vector2(12,9),Vector2(-width-12,-28),Vector2(-width-12,9)]
	for ring in range(1,20):
		for x in range(-ring,ring+1):
			for y in [-ring,ring]:result.append(Vector2(x*32-width*0.5,y*30-13))
		for y in range(-ring+1,ring):
			for x in [-ring,ring]:result.append(Vector2(x*32-width*0.5,y*30-13))
	return result

static func _cell_keys(box:Rect2) -> Array[Vector2i]:
	var keys:Array[Vector2i]=[]
	for x in range(floori(box.position.x/64),floori(box.end.x/64)+1):
		for y in range(floori(box.position.y/64),floori(box.end.y/64)+1):keys.append(Vector2i(x,y))
	return keys

static func _overlaps(cells:Dictionary,box:Rect2) -> bool:
	for key in _cell_keys(box):
		for other in cells.get(key,[]):
			if box.intersects(other):return true
	return false

static func _occupy(cells:Dictionary,box:Rect2) -> void:
	for key in _cell_keys(box):
		if not cells.has(key):cells[key]=[]
		cells[key].append(box)
