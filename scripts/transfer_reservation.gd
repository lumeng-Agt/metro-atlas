class_name TransferReservation
extends RefCounted

const Engineering=preload("res://scripts/engineering_construction.gd")
const Paths=preload("res://scripts/route_path.gd")

## A sourced future interface is never an active passenger interchange. Each
## body must belong to its line and connect to actual track. Engineering-only
## fragments need their independently defined paths, not a fictitious service.
static func errors(world:Dictionary,pair:Dictionary,engineering_groups:Array=[]) -> Array[String]:
	var result:Array[String]=[]
	var lines:Array=pair.get("lineIds",[]);var instances:Array=pair.get("stationInstanceIds",[])
	if str(pair.get("status",""))!="reserved" or lines.size()!=2 or instances.size()!=2 or lines[0]==lines[1] or instances[0]==instances[1]:return ["预留换乘必须对应两条线路的两个独立站体。"]
	if not str(pair.get("source","")).begins_with("https://") or not str(pair.get("reservationEvidence","")).begins_with("https://"):return ["预留换乘缺少明确的规划依据。"]
	var complex_id:=CampaignSystem.canonical_station_complex(str(world.get("cityId","")),str(pair.get("complexId","")))
	var latitude:=float(WorldData.city(str(world.get("cityId",""))).get("center",[0])[0])
	var path_index:=TrackNetwork.build_path_index(world,latitude)
	for index in range(2):
		var station:Dictionary={}
		for body in world.get("stations",[]):
			if str(body.get("stationInstanceId",body.get("id","")))==str(instances[index]):station=body;break
		if station.is_empty() or str(station.get("stationLineId",""))!=str(lines[index]) or CampaignSystem.canonical_station_complex(str(world.get("cityId","")),str(station.get("stationComplexId",station.get("historicalId",""))))!=complex_id:
			result.append("预留联系缺少对应线路的独立站体：%s。"%str(lines[index]));continue
		var connected:=false
		for group in engineering_groups:
			if str(group.get("historicalLineId",""))!=str(lines[index]) or not Engineering.is_group(group):continue
			var endpoint_matches:bool=group.get("engineeringEndpoints",[]).any(func(endpoint:Dictionary):return str(endpoint.get("stationInstanceId",endpoint.get("stationId","")))==str(instances[index]))
			if endpoint_matches and bool(Engineering.evaluate(world,group,path_index).get("complete",false)):connected=true;break
		if not connected:
			for route in world.get("routes",[]):
				if bool(route.get("retired",false)) or str(route.get("historicalLineId",""))!=str(lines[index]):continue
				var contains_body:bool=route.get("directions",[]).any(func(direction:Dictionary):return direction.get("stationIds",[]).has(str(station.id)))
				if contains_body and bool(Paths.for_route(route,world,latitude,path_index).get("valid",false)):connected=true;break
		if not connected:result.append("预留站体尚未接入本线的实际轨道：%s。"%str(station.get("name",lines[index])))
	return result

static func saved_matches(world:Dictionary,pair:Dictionary) -> bool:
	for connection in world.get("transferConnections",[]):
		if str(connection.get("id",""))!=str(pair.get("id","")) or str(connection.get("status",""))!="reserved":continue
		if connection.get("lineIds",[])==pair.get("lineIds",[]) and connection.get("stationInstanceIds",[])==pair.get("stationInstanceIds",[]) and str(connection.get("reservationEvidence",""))==str(pair.get("reservationEvidence","")):return true
	return false
