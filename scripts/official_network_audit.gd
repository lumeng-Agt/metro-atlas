class_name OfficialNetworkAudit
extends RefCounted

const TARGET_PATH="res://data/official_targets_2026-10-01.json"
const Engineering=preload("res://scripts/engineering_construction.gd")
const Reservation=preload("res://scripts/transfer_reservation.gd")
const SharedRunning=preload("res://scripts/shared_running_audit.gd")
static var _target_snapshot:Dictionary={}
static var _target_snapshot_sha256:=""

## Freeze one published content package for this session. A long replay must
## not compare its cached chapter data with a newer answer edited mid-run.
static func target_data() -> Dictionary:
	if _target_snapshot.is_empty():
		var source:=FileAccess.get_file_as_string(TARGET_PATH)
		var parsed:Variant=JSON.parse_string(source)
		if parsed is Dictionary:_target_snapshot=parsed
		_target_snapshot_sha256=source.sha256_text()
	return _target_snapshot

static func target_snapshot_sha256() -> String:
	target_data()
	return _target_snapshot_sha256

## Reads independent official station orders, then checks the built world.
## It never reads chapter groups to generate the expected answer.
static func project_errors(world:Dictionary,project:Dictionary) -> Array[String]:
	var errors:Array[String]=[]
	var latitude:=float(WorldData.city(str(world.cityId)).get("center",[0])[0])
	var path_index:=TrackNetwork.build_path_index(world,latitude)
	var requirements:Array=project.get("groups",[]).duplicate()
	requirements.append_array(project.get("existingScopes",[]))
	requirements.append_array(project.get("closedScopes",[]))
	# A full service snapshot is not merely a subsequence. Otherwise an
	# appended duplicate stop or an obsolete parallel direction can pass while
	# retaining exactly the bogus tail this audit is supposed to catch.
	if not bool(project.get("constructionOnly",false)):
		var complete_patterns:Dictionary={}
		for expected in requirements:
			if not bool(expected.get("fullServiceOrder",false)):continue
			var key:=str(expected.get("historicalLineId",expected.id))
			if not complete_patterns.has(key):complete_patterns[key]=[]
			var pattern:Array=expected.get("stationNames",[]).duplicate()
			if bool(expected.get("loop",false)) and not pattern.is_empty():pattern.append(pattern[0])
			complete_patterns[key].append(pattern)
			if bool(expected.get("allowReverse",false)):
				var reversed:=pattern.duplicate();reversed.reverse();complete_patterns[key].append(reversed)
		for route in world.get("routes",[]):
			var key:=str(route.get("historicalLineId",""))
			if not complete_patterns.has(key) or bool(route.get("retired",false)) or not bool(route.get("open",false)):continue
			for direction in route.get("directions",[]):
				# A later planning task may extend the same formal route with
				# built-only segments. They are construction, not current stops.
				for actual in open_service_patterns(world,route,direction):
					if not complete_patterns[key].has(actual):errors.append("%s: active full service contains an extra, missing or incorrectly ordered stop"%key)
	for expected in requirements:
		if str(expected.get("scopeType",""))=="engineering":
			var definition:Dictionary=expected.duplicate(true)
			definition["source"]=str(project.get("source",""))
			var checked:=Engineering.evaluate(world,definition,path_index)
			for issue in checked.issues:errors.append("%s: %s"%[str(expected.id),str(issue.get("text","工程未接通"))])
			continue
		var required_status:=str(expected.get("requiredServiceStatus",""))
		var construction_only:=bool(project.get("constructionOnly",false)) and not bool(expected.get("requireServiceOpen",false))
		var wanted:Array=expected.get("stationNames",[]).duplicate()
		if wanted.is_empty():
			errors.append("%s: independent station order unavailable" % str(expected.id));continue
		if bool(expected.get("loop",false)):wanted.append(wanted[0])
		var line_id:=str(expected.get("historicalLineId",expected.id))
		var matched:=false
		for route in world.get("routes",[]):
			if bool(route.get("retired",false)) or (required_status.is_empty() and not construction_only and not bool(route.get("open",true))):continue
			if str(route.get("historicalLineId",""))!=line_id:continue
			for direction in route.get("directions",[]):
				var ids:Array=direction.get("stationIds",[])
				var names:Array=[]
				for id in ids:
					var name:=str(WorldData.find_station(world,str(id)).get("name",""))
					# Future scheme labels must not rename an existing open station.
					# Only an independently sourced construction variant may supply
					# contextual names; historical/cutoff checks keep the real name.
					if construction_only and not str(route.get("constructionVariantId","")).is_empty() and not str(expected.get("stationNamingSource","")).is_empty() and str(route.get("plannedNameSource",""))==str(expected.stationNamingSource):name=str(route.get("plannedStationNames",{}).get(str(id),name))
					names.append(name)
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
						var required_instance:=str(expected.get("requiredStationInstances",{}).get(str(names[i]),""))
						if not required_instance.is_empty() and str(body.get("stationInstanceId",body.get("id","")))!=required_instance:errors.append("%s: documented physical body differs at %s"%[str(expected.id),str(names[i])])
						var body_line:=str(body.get("stationLineId",line_id))
						var shared:Array=expected.get("sharedBodyLines",{}).get(str(names[i]),[])
						var permitted_shared:bool=(i==offset or i==offset+wanted.size()-1) and shared.has(body_line) and not str(expected.get("sharedBodyEvidence","")).is_empty()
						var same_lineage:bool=expected.get("bodyLineAliases",[]).has(body_line) and not str(expected.get("bodyLineAliasEvidence","")).is_empty()
						if body_line!=line_id and not permitted_shared and not same_lineage:errors.append("%s: stop belongs to another physical line body: %s" % [str(expected.id),str(ids[i])])
					for i in range(offset,offset+wanted.size()-1):
						if not construction_only or not required_status.is_empty():
							var statuses:Array=direction.get("serviceStatusBySegment",[])
							var status:=str(statuses[i]) if statuses.size()==ids.size()-1 else str(route.get("serviceStatus","open" if bool(route.get("open",false)) else "built"))
							if not required_status.is_empty():
								if status!=required_status:errors.append("%s: expected %s segment: %s—%s, actual %s"%[str(expected.id),required_status,str(names[i]),str(names[i+1]),status])
							elif status not in ["open","trial"]:errors.append("%s: non-open historical segment: %s—%s"%[str(expected.id),str(names[i]),str(names[i+1])])
						var path:=TrackNetwork.ordered_station_path(str(ids[i]),str(ids[i+1]),paths[i],world,latitude,path_index)
						if not bool(path.get("valid",false)):
							errors.append("%s: %s—%s: %s" % [str(expected.id),str(names[i]),str(names[i+1]),str(path.get("error","invalid path"))]);continue
						if not str(expected.get("requiredPlanningCorridorId","")).is_empty():
							var corridor_error:=ReferenceAlignment.planning_corridor_issue(path.get("points",[]),str(expected.requiredPlanningCorridorId),latitude,float(expected.get("planningCorridorToleranceM",0)))
							if not corridor_error.is_empty():errors.append("%s: %s"%[str(expected.id),corridor_error])
						if previous_end==str(path.fromNodeId):errors.append("%s: implicit reversal at %s" % [str(expected.id),str(names[i])])
						if first_start.is_empty():first_start=str(path.fromNodeId)
						previous_end=str(path.toNodeId)
					if bool(expected.get("loop",false)) and first_start==previous_end:errors.append("%s: ring closes on its departure end" % str(expected.id))
		if not matched:errors.append("%s: actual built line does not contain the official ordered scope" % str(expected.id))
	for reserved in project.get("reservedTransfers",[]):
		var reserved_groups:Array=project.get("groups",[]).duplicate(true)
		for group in reserved_groups:
			if str(group.get("source","")).is_empty():group["source"]=str(project.get("source",""))
		var problems:=Reservation.errors(world,reserved,reserved_groups)
		errors.append_array(problems)
		if not Reservation.saved_matches(world,reserved):errors.append("%s: required reserved interchange missing or wrongly active"%str(reserved.get("id","")))
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
					if bool(route.get("retired",false)) or (not bool(project.get("constructionOnly",false)) and not bool(route.get("open",true))):continue
					if str(route.get("historicalLineId",""))!=str(lines[i]):continue
					for direction in route.get("directions",[]):
						if not physical_id.is_empty() and direction.get("stationIds",[]).has(physical_id):serves=true
				if not serves:errors.append("%s: physical platform is not served by the paired line"%str(required_id))
		if not found:errors.append("%s: required active transfer missing"%str(required_id))
	return errors

## Extract contiguous actually-open ranges, preserving station order. A future
## built-only extension must neither count as current operation nor hide a gap.
static func open_service_patterns(world:Dictionary,route:Dictionary,direction:Dictionary) -> Array:
	var ids:Array=direction.get("stationIds",[]);var statuses:Array=direction.get("serviceStatusBySegment",[])
	var patterns:Array=[];var current:Array=[]
	for i in range(maxi(0,ids.size()-1)):
		var status:=str(statuses[i]) if statuses.size()==ids.size()-1 else str(route.get("serviceStatus","open"))
		if status in ["open","trial"]:
			if current.is_empty():current.append(str(WorldData.find_station(world,str(ids[i])).get("name","")))
			current.append(str(WorldData.find_station(world,str(ids[i+1])).get("name","")))
		elif not current.is_empty():patterns.append(current);current=[]
	if not current.is_empty():patterns.append(current)
	return patterns

static func current_project_errors(world:Dictionary,project_ids:Array) -> Array[String]:
	var targets:Dictionary=target_data()
	var errors:Array[String]=[]
	for project in targets.get("cities",{}).get(str(world.cityId),{}).get("projects",[]):
		if project_ids.has(str(project.id)):errors.append_array(project_errors(world,project))
	return errors

## Check the real committed path at each independently documented opening,
## including extra future stops on a line whose period is already reviewed.
static func historical_chapter_errors(world:Dictionary,chapter_id:String,scope_only_for_backfill:bool=false) -> Array[String]:
	var targets:Dictionary=target_data()
	var milestones:Array=targets.get("cities",{}).get(str(world.cityId),{}).get("historicalMilestones",[])
	var current:Dictionary={}
	for milestone in milestones:
		if str(milestone.get("chapterId",""))==chapter_id:current=milestone;break
	if current.is_empty():return []
	var checked_target:=current
	if scope_only_for_backfill:
		var backfill:=backfill_requirements(current)
		if not bool(backfill.ok):return [str(backfill.error)]
		checked_target=backfill.target
	var errors:=project_errors(world,checked_target)
	# Compatibility backfills check the missing old task against construction
	# that legitimately already contains later milestones. They are not evidence
	# that a fresh chronological playthrough had no premature later stops.
	if scope_only_for_backfill:return errors
	var reviewed_lines:Dictionary={}
	for group in current.get("groups",[]):reviewed_lines[str(group.get("historicalLineId",group.id))]=true
	var permitted:=permitted_historical_stops(milestones,str(current.get("date","")))
	for route in world.get("routes",[]):
		if bool(route.get("retired",false)) or not bool(route.get("open",true)):continue
		var line_id:=str(route.get("historicalLineId",""))
		if not reviewed_lines.has(line_id):continue
		for direction in route.get("directions",[]):
			for id in direction.get("stationIds",[]):
				var name:=str(WorldData.find_station(world,str(id)).get("name",""))
				if not permitted.get(line_id,[]).has(name):errors.append("%s: future or undocumented stop at %s: %s"%[line_id,str(current.get("date","")),name])
	return errors

## A late save already contains subsequent infill. Recheck the independently
## specified missing construction, rather than demand the whole former service
## pattern without its legitimately later stops. Fresh-period audits still use
## the complete dated pattern and reject those stops.
static func backfill_requirements(milestone:Dictionary) -> Dictionary:
	var target:=milestone.duplicate(true)
	for group in target.get("groups",[]):
		if not group.has("constructionStationNames"):
			group["fullServiceOrder"]=false
			continue
		var complete:Array=group.get("stationNames",[]);var section:Array=group.constructionStationNames
		var contained:=false
		if section.size()>=2:
			for offset in range(maxi(0,complete.size()-section.size()+1)):
				if complete.slice(offset,offset+section.size())==section:contained=true;break
		if not bool(group.get("fullServiceOrder",false)) or not contained:return {"ok":false,"error":"%s: invalid independently defined backfill construction range"%str(group.get("id",""))}
		group.stationNames=section.duplicate()
		group["fullServiceOrder"]=false
		if section!=complete:
			group["loop"]=false
			# Only the explicitly reviewed old construction subsection is being
			# rechecked in this late save; legitimate later infill is retained.
	return {"ok":true,"target":target}

static func permitted_historical_stops(milestones:Array,date:String) -> Dictionary:
	var permitted:Dictionary={}
	var chronological:=milestones.duplicate()
	chronological.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.get("date",""))<str(b.get("date","")))
	for milestone in chronological:
		if str(milestone.get("date",""))>date:continue
		# All full patterns at a dated node describe the same snapshot. Clear
		# the old scope once per line, then union its branches. Clearing for
		# every branch incorrectly rejects the other branch's unique stations.
		var reset_lines:Dictionary={}
		var scopes:Array=milestone.get("groups",[]).duplicate()
		# Previously opened scopes are independent requirements too: they are
		# checked by project_errors, and must not be mistaken for future stops
		# when a later chapter adds only one end of the same line.
		scopes.append_array(milestone.get("existingScopes",[]))
		for group in scopes:
			var line_id:=str(group.get("historicalLineId",group.id))
			if bool(group.get("fullServiceOrder",false)) and not reset_lines.has(line_id):
				permitted[line_id]=[];reset_lines[line_id]=true
		for group in scopes:
			var line_id:=str(group.get("historicalLineId",group.id))
			if not permitted.has(line_id):permitted[line_id]=[]
			for name in group.get("stationNames",[]):
				if not permitted[line_id].has(name):permitted[line_id].append(name)
	return permitted

static func cutoff_errors(world:Dictionary) -> Array[String]:
	var targets:Dictionary=target_data()
	var city:Dictionary=targets.get("cities",{}).get(str(world.cityId),{})
	var network:Dictionary=city.get("cutoffNetwork",{})
	if network.is_empty():return ["independent cutoff network not yet available"]
	var errors:=project_errors(world,network)
	for relation in network.get("transferDefinitions",[]):errors.append_array(transfer_structure_errors(world,relation))
	errors.append_array(service_shape_errors(world,network,city.get("projects",[])))
	errors.append_array(SharedRunning.definition_errors(network))
	for shared in network.get("sharedRunningSections",[]):errors.append_array(SharedRunning.errors(world,shared))
	return errors

static func transfer_structure_errors(world:Dictionary,expected:Dictionary) -> Array[String]:
	var id:=str(expected.get("id",""))
	if id.is_empty() or not str(expected.get("source","")).begins_with("https://"):return ["independent transfer structure evidence missing"]
	var matches:Array=world.get("transferConnections",[]).filter(func(pair:Dictionary):return str(pair.get("id",""))==id and str(pair.get("status","active"))==str(expected.get("status","active")))
	if matches.size()!=1:return ["%s: required transfer structure missing or duplicated"%id]
	var pair:Dictionary=matches[0]
	for field in ["lineIds","stationInstanceIds"]:
		if pair.get(field,[])!=expected.get(field,[]):return ["%s: independent %s differs"%[id,field]]
	if CampaignSystem.canonical_station_complex(str(world.cityId),str(pair.get("complexId","")))!=CampaignSystem.canonical_station_complex(str(world.cityId),str(expected.get("complexId",""))) or str(pair.get("transferKind","interchange"))!=str(expected.get("transferKind","interchange")):return ["%s: expected %s transfer structure"%[id,str(expected.get("transferKind","interchange"))]]
	return []

static func service_shape_errors(world:Dictionary,network:Dictionary,projects:Array=[]) -> Array[String]:
	var errors:Array[String]=[]
	var checked_lines:Dictionary={}
	for expected in network.get("groups",[]):
		var line_id:=str(expected.get("historicalLineId",expected.id))
		if checked_lines.has(line_id):continue
		checked_lines[line_id]=true
		var permitted:Array=[]
		var patterns:Array=[]
		for scope in network.get("groups",[]):
			if str(scope.get("historicalLineId",scope.id))!=line_id:continue
			patterns.append(scope.get("stationNames",[]))
			for name in scope.get("stationNames",[]):
				if not permitted.has(name):permitted.append(name)
		# Later, independently documented extensions may coexist with the
		# historical checkpoint. They cannot legitimise arbitrary stray stops.
		for project in projects:
			for future in project.get("groups",[]):
				if str(future.get("historicalLineId",future.id))==line_id:
					for name in future.get("stationNames",[]):
						if not permitted.has(name):permitted.append(name)
		var required_direction_count:=patterns.size()
		for change in network.get("futureTopologyChanges",[]):
			if str(change.get("historicalLineId",""))!=line_id or str(change.get("kind",""))!="merge_cutoff_branches":continue
			if str(change.get("source","")).is_empty() or int(change.get("cutoffBranchCount",0))!=patterns.size() or int(change.get("resultBranchCount",0))!=1:continue
			for project in projects:
				if str(project.get("id",""))!=str(change.get("projectId","")) or str(project.get("reviewStatus",""))!="verified" or project.get("groups",[]).is_empty():continue
				# A claimed completion flag is insufficient: the connecting scope
				# and its required transfers must exist in the real saved world.
				if project_errors(world,project).is_empty():required_direction_count=1
		for route in world.get("routes",[]):
			if bool(route.get("retired",false)):continue
			if not str(route.get("constructionVariantId","")).is_empty():continue
			if str(route.get("historicalLineId",""))!=line_id:continue
			if route.get("directions",[]).size()!=required_direction_count:errors.append("%s: cutoff service direction count differs from documented branches"%line_id)
			for direction in route.get("directions",[]):
				var seen:Dictionary={}
				for id in direction.get("stationIds",[]):
					var name:=str(WorldData.find_station(world,str(id)).get("name",""))
					if not permitted.has(name):errors.append("%s: undocumented stop in saved service: %s"%[line_id,name])
					var is_ring_closure:bool=bool(expected.get("loop",false)) and id==direction.get("stationIds",[]).back() and id==direction.get("stationIds",[]).front() and seen.size()==direction.get("stationIds",[]).size()-1
					if seen.has(str(id)) and not is_ring_closure:errors.append("%s: duplicate platform in cutoff service: %s"%[line_id,name])
					seen[str(id)]=true
	return errors
