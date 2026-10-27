extends SceneTree
## Load-time repair of superseded save records. Each case builds the exact
## shape the old builds produced, then checks the repair and checks that a
## healthy network is left completely untouched.

var failures:=0

func _initialize() -> void:call_deferred("_run")

func _check(ok:bool,label:String) -> void:
	if ok:print("PASS ",label)
	else:failures+=1;print("FAIL ",label)

func _station(id:String,hist:String,line:String,lat:float) -> Dictionary:
	return {"id":id,"stationInstanceId":id,"historicalId":hist,"stationLineId":line,"name":id,"latlng":[lat,121.0],"endpointNodes":{"A":"node_%s_a"%id,"B":"node_%s_b"%id}}

func _world(stations:Array,edges:Array,routes:Array) -> Dictionary:
	var nodes:Array=[]
	for station in stations:
		for side in ["A","B"]:
			nodes.append({"id":str(station.endpointNodes[side]),"latlng":station.latlng.duplicate(),"stationId":str(station.id),"side":side})
	return {"cityId":"shanghai","stations":stations,"trackNodes":nodes,"trackEdges":edges,"routes":routes,"transferConnections":[],"stationComplexes":[]}

func _edge(id:String,from:String,to:String,route:String) -> Dictionary:
	return {"id":id,"aNodeId":from,"bNodeId":to,"routeIds":[route],"depthM":-15.0,"distanceM":800.0,"referencePoints":[]}

func _route(id:String,line:String,ids:Array,paths:Array) -> Dictionary:
	return {"id":id,"historicalLineId":line,"stationOrder":ids.duplicate(),"open":true,"directions":[{"id":"forward","stationIds":ids,"edgePathsBySegment":paths}]}

func _seg(ids:Array) -> Array:
	var out:Array=[]
	for id in ids:out.append({"id":str(id),"forward":true})
	return out

func _run() -> void:
	_check_healthy_untouched()
	_check_out_and_back_collapsed()
	_check_ring_untouched()
	_check_parallel_section_deduplicated()
	if failures==0:print("LEGACY_REPAIR_OK")
	else:print("LEGACY_REPAIR_FAILURES ",failures)
	quit(0 if failures==0 else 1)

func _check_healthy_untouched() -> void:
	var stations:Array=[_station("st-a","s-a","line1",31.0),_station("st-b","s-b","line1",31.01),_station("st-c","s-c","line1",31.02)]
	var edges:Array=[_edge("e1","node_st-a_b","node_st-b_a","line1"),_edge("e2","node_st-b_b","node_st-c_a","line1")]
	var routes:Array=[_route("r1","line1",["st-a","st-b","st-c"],[_seg(["e1"]),_seg(["e2"])])]
	var world:=_world(stations,edges,routes)
	var changed:=SaveManager._repair_legacy_network(world)
	_check(not changed,"healthy network is not rewritten")
	_check(int(world.stations.size())==3 and int(world.trackEdges.size())==2,"healthy network keeps every station and section")

func _check_out_and_back_collapsed() -> void:
	var stations:Array=[_station("st-a","s-a","line1",31.0),_station("st-b","s-b","line1",31.01),_station("st-c","s-c","line1",31.02)]
	var edges:Array=[_edge("e1","node_st-a_b","node_st-b_a","line1"),_edge("e2","node_st-b_b","node_st-c_a","line1")]
	# Out to C and back: the return leg runs over the very same sections.
	var routes:Array=[_route("r1","line1",["st-a","st-b","st-c","st-b","st-a"],[_seg(["e1"]),_seg(["e2"]),_seg(["e2"]),_seg(["e1"])])]
	var world:=_world(stations,edges,routes)
	var changed:=SaveManager._repair_legacy_network(world)
	var direction:Dictionary=world.routes[0].directions[0]
	_check(changed,"out-and-back direction is repaired")
	_check(direction.stationIds==["st-a","st-b","st-c"],"out-and-back keeps only the outbound half")
	_check(direction.edgePathsBySegment.size()==2,"out-and-back keeps the matching sections")
	_check(world.routes[0].stationOrder==["st-a","st-b","st-c"],"station order follows the repaired direction")

func _check_ring_untouched() -> void:
	var stations:Array=[_station("st-a","s-a","line9",31.0),_station("st-b","s-b","line9",31.01),_station("st-c","s-c","line9",31.02)]
	var edges:Array=[_edge("e1","node_st-a_b","node_st-b_a","line9"),_edge("e2","node_st-b_b","node_st-c_a","line9"),_edge("e3","node_st-c_b","node_st-a_a","line9")]
	var routes:Array=[_route("r9","line9",["st-a","st-b","st-c","st-a"],[_seg(["e1"]),_seg(["e2"]),_seg(["e3"])])]
	var world:=_world(stations,edges,routes)
	var changed:=SaveManager._repair_legacy_network(world)
	_check(not changed,"a closed ring is not mistaken for an out-and-back")
	_check(int(world.routes[0].directions[0].stationIds.size())==4,"ring keeps its closing station")

func _check_parallel_section_deduplicated() -> void:
	# The turning station already carries one neighbour on end A, so a second
	# section to the other neighbour must use end B instead of stacking.
	var stations:Array=[_station("st-x","s-x","line2",31.0),_station("st-y","s-y","line2",31.01),_station("st-z","s-z","line2",31.02)]
	var edges:Array=[
		_edge("e-in","node_st-x_a","node_st-y_b","line2"),
		_edge("e-dup","node_st-x_a","node_st-z_b","line2"),
		_edge("e-ok","node_st-x_b","node_st-z_b","line2")]
	var routes:Array=[_route("r2","line2",["st-y","st-x","st-z"],[_seg(["e-in"]),_seg(["e-dup"])])]
	var world:=_world(stations,edges,routes)
	var changed:=SaveManager._repair_legacy_network(world)
	var kept_ids:Array=[]
	for edge in world.trackEdges:kept_ids.append(str(edge.id))
	_check(changed,"a duplicated section between one station pair is repaired")
	_check(kept_ids.has("e-ok") and not kept_ids.has("e-dup"),"the section using the free platform end is kept")
	_check(world.routes[0].directions[0].edgePathsBySegment[1][0].id=="e-ok","the stored segment now points at the kept section")
