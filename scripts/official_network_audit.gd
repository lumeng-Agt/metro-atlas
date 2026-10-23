class_name OfficialNetworkAudit
extends RefCounted

const TARGET_PATH="res://data/official_targets_2026-10-01.json"

## Reads independent official station orders, then checks the built world.
## It never reads chapter groups to generate the expected answer.
static func project_errors(world:Dictionary,project:Dictionary) -> Array[String]:
	var errors:Array[String]=[]
	var latitude:=float(WorldData.city(str(world.cityId)).get("center",[0])[0])
	var path_index:=TrackNetwork.build_path_index(world,latitude)
	for expected in project.get("groups",[]):
		var wanted:Array=expected.get("stationNames",[]).duplicate()
		if wanted.is_empty():
			errors.append("%s: independent station order unavailable" % str(expected.id));continue
		if bool(expected.get("loop",false)):wanted.append(wanted[0])
		var line_id:=str(expected.get("historicalLineId",expected.id))
		var matched:=false
		for route in world.get("routes",[]):
			if str(route.get("historicalLineId",""))!=line_id:continue
			for direction in route.get("directions",[]):
				var ids:Array=direction.get("stationIds",[])
				var names:Array=[]
				for id in ids:names.append(str(WorldData.find_station(world,str(id)).get("name","")))
				for forbidden in expected.get("forbiddenStationNames",[]):
					if names.has(forbidden):errors.append("%s: superseded scope still serves %s" % [str(expected.id),str(forbidden)])
				for offset in range(maxi(0,names.size()-wanted.size()+1)):
					var reverse_wanted:=wanted.duplicate();reverse_wanted.reverse()
					if names.slice(offset,offset+wanted.size())!=wanted and not (bool(expected.get("allowReverse",false)) and names.slice(offset,offset+wanted.size())==reverse_wanted):continue
					matched=true
					var paths:Array=direction.get("edgePathsBySegment",[])
					if paths.size()!=ids.size()-1:
						errors.append("%s: segment count differs" % str(expected.id));continue
					var previous_end:="";var first_start:=""
					for i in range(offset,offset+wanted.size()):
						var body:=WorldData.find_station(world,str(ids[i]))
						var body_line:=str(body.get("stationLineId",line_id))
						var shared:Array=expected.get("sharedBodyLines",{}).get(str(names[i]),[])
						var permitted_shared:bool=(i==offset or i==offset+wanted.size()-1) and shared.has(body_line) and not str(expected.get("sharedBodyEvidence","")).is_empty()
						if body_line!=line_id and not permitted_shared:errors.append("%s: stop belongs to another physical line body: %s" % [str(expected.id),str(ids[i])])
					for i in range(offset,offset+wanted.size()-1):
						var path:=TrackNetwork.ordered_station_path(str(ids[i]),str(ids[i+1]),paths[i],world,latitude,path_index)
						if not bool(path.get("valid",false)):
							errors.append("%s: %s—%s: %s" % [str(expected.id),str(names[i]),str(names[i+1]),str(path.get("error","invalid path"))]);continue
						if previous_end==str(path.fromNodeId):errors.append("%s: implicit reversal at %s" % [str(expected.id),str(names[i])])
						if first_start.is_empty():first_start=str(path.fromNodeId)
						previous_end=str(path.toNodeId)
					if bool(expected.get("loop",false)) and first_start==previous_end:errors.append("%s: ring closes on its departure end" % str(expected.id))
		if not matched:errors.append("%s: actual built line does not contain the official ordered scope" % str(expected.id))
	for required_id in project.get("transfers",[]):
		var found:=false
		for connection in world.get("transferConnections",[]):
			if str(connection.get("id",""))!=str(required_id) or str(connection.get("status","active"))!="active":continue
			found=true
			var lines:Array=connection.get("lineIds",[])
			var bodies:Array=connection.get("stationInstanceIds",[])
			if lines.size()<2 or bodies.size()!=lines.size():
				errors.append("%s: invalid independent transfer pairing"%str(required_id));continue
			for i in range(lines.size()):
				var serves:=false
				var physical_id:=""
				for station in world.get("stations",[]):
					if str(station.get("stationInstanceId",station.get("id","")))==str(bodies[i]):physical_id=str(station.id);break
				for route in world.get("routes",[]):
					if str(route.get("historicalLineId",""))!=str(lines[i]):continue
					for direction in route.get("directions",[]):
						if not physical_id.is_empty() and direction.get("stationIds",[]).has(physical_id):serves=true
				if not serves:errors.append("%s: physical platform is not served by the paired line"%str(required_id))
		if not found:errors.append("%s: required active transfer missing"%str(required_id))
	return errors

static func current_project_errors(world:Dictionary,project_ids:Array) -> Array[String]:
	var targets:Variant=JSON.parse_string(FileAccess.get_file_as_string(TARGET_PATH))
	var errors:Array[String]=[]
	for project in targets.get("cities",{}).get(str(world.cityId),{}).get("projects",[]):
		if project_ids.has(str(project.id)):errors.append_array(project_errors(world,project))
	return errors

static func cutoff_errors(world:Dictionary) -> Array[String]:
	var targets:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TARGET_PATH))
	var city:Dictionary=targets.get("cities",{}).get(str(world.cityId),{})
	var network:Dictionary=city.get("cutoffNetwork",{})
	if network.is_empty():return ["independent cutoff network not yet available"]
	var errors:=project_errors(world,network)
	for expected in network.get("groups",[]):
		var line_id:=str(expected.id)
		var permitted:Array=expected.get("stationNames",[]).duplicate()
		# Later, independently documented extensions may coexist with the
		# historical checkpoint. They cannot legitimise arbitrary stray stops.
		for project in city.get("projects",[]):
			for future in project.get("groups",[]):
				if str(future.get("historicalLineId",future.id))==line_id:
					for name in future.get("stationNames",[]):
						if not permitted.has(name):permitted.append(name)
		for route in world.get("routes",[]):
			if str(route.get("historicalLineId",""))!=line_id:continue
			if route.get("directions",[]).size()!=1:errors.append("%s: cutoff service has extra disconnected directions"%line_id)
			for direction in route.get("directions",[]):
				var seen:Dictionary={}
				for id in direction.get("stationIds",[]):
					var name:=str(WorldData.find_station(world,str(id)).get("name",""))
					if not permitted.has(name):errors.append("%s: undocumented stop in saved service: %s"%[line_id,name])
					if seen.has(str(id)):errors.append("%s: duplicate platform in cutoff service: %s"%[line_id,name])
					seen[str(id)]=true
	return errors
