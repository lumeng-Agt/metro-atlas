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
				for offset in range(maxi(0,names.size()-wanted.size()+1)):
					if names.slice(offset,offset+wanted.size())!=wanted:continue
					matched=true
					var paths:Array=direction.get("edgePathsBySegment",[])
					if paths.size()!=ids.size()-1:
						errors.append("%s: segment count differs" % str(expected.id));continue
					var previous_end:="";var first_start:=""
					for i in range(offset,offset+wanted.size()-1):
						var from_station:=WorldData.find_station(world,str(ids[i]))
						if str(from_station.get("stationLineId",line_id))!=line_id:errors.append("%s: stop belongs to another physical line body: %s" % [str(expected.id),str(ids[i])])
						var path:=TrackNetwork.ordered_station_path(str(ids[i]),str(ids[i+1]),paths[i],world,latitude,path_index)
						if not bool(path.get("valid",false)):
							errors.append("%s: %s—%s: %s" % [str(expected.id),str(names[i]),str(names[i+1]),str(path.get("error","invalid path"))]);continue
						if previous_end==str(path.fromNodeId):errors.append("%s: implicit reversal at %s" % [str(expected.id),str(names[i])])
						if first_start.is_empty():first_start=str(path.fromNodeId)
						previous_end=str(path.toNodeId)
					if bool(expected.get("loop",false)) and first_start==previous_end:errors.append("%s: ring closes on its departure end" % str(expected.id))
		if not matched:errors.append("%s: actual built line does not contain the official ordered scope" % str(expected.id))
	return errors

static func current_project_errors(world:Dictionary,project_ids:Array) -> Array[String]:
	var targets:Variant=JSON.parse_string(FileAccess.get_file_as_string(TARGET_PATH))
	var errors:Array[String]=[]
	for project in targets.get("cities",{}).get(str(world.cityId),{}).get("projects",[]):
		if project_ids.has(str(project.id)):errors.append_array(project_errors(world,project))
	return errors
