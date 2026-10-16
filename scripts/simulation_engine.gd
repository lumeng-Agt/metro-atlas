class_name SimulationEngine
extends RefCounted

const MAX_WAIT_MINUTES := 30
const JourneyModelScript = preload("res://scripts/journey_model.gd")
const RoutePathScript = preload("res://scripts/route_path.gd")
const ServiceScheduleScript = preload("res://scripts/service_schedule.gd")
static var _route_cache_key := ""
static var _route_cache: Dictionary = {}

static func invalidate_route_cache() -> void:
	_route_cache_key = ""
	_route_cache.clear()

static func reconcile_passengers(state: Dictionary, flows: Array[Dictionary]) -> void:
	var sim: Dictionary = state.get("simulation", {})
	var batches: Array = sim.get("passengerBatches", [])
	var revision := int(state.get("revision", 0))
	var ref_lat := float(WorldData.city(str(state.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0])
	var network := JourneyModelScript.build_network(state, ref_lat)
	for raw_batch in batches:
		if not raw_batch is Dictionary: continue
		var batch: Dictionary = raw_batch
		if int(batch.get("plannedRevision", -1)) == revision: continue
		var flow := _find_flow(flows, str(batch.get("flowId", "")))
		var now_seconds := int(sim.get("elapsedSeconds", int(sim.get("elapsedMinutes", sim.get("minute", 420))) * 60))
		if str(batch.get("status", "")) in ["replan", "disrupted"]:
			_replan_batch(state, batch, flow, now_seconds, network, ref_lat)
			continue
		if str(batch.get("status", "")) == "riding":
			var flow_journey: Dictionary = flow.get("journey", {})
			var next_fingerprint := _journey_fingerprint(flow_journey.get("steps", [])) if bool(flow.get("valid", false)) else ""
			batch.replanAfterArrival = str(batch.get("journeyFingerprint", "")) != next_fingerprint
			batch.plannedRevision = revision
			continue
		_replan_batch(state, batch, flow, now_seconds, network, ref_lat)
	sim["passengerBatches"] = batches
	state["simulation"] = sim

static func reconcile_train_trips(state: Dictionary) -> int:
	var sim: Dictionary = state.get("simulation", {})
	var trips: Array = sim.get("trainTrips", [])
	var batches: Array = sim.get("passengerBatches", [])
	var capacity_loads: Dictionary = sim.get("capacityLoads", {})
	var edges_by_id: Dictionary = {}
	for edge in TrackNetwork.all_physical_edges(state): edges_by_id[str(edge.get("id", ""))] = edge
	var surviving: Array = []
	var canceled: Dictionary = {}
	for raw_trip in trips:
		if not raw_trip is Dictionary: continue
		var trip: Dictionary = raw_trip
		var invalid := false
		var signatures: Dictionary = trip.get("edgeSignatures", {})
		for edge_id in signatures:
			if not edges_by_id.has(str(edge_id)) or _edge_signature(state, edges_by_id[str(edge_id)]) != str(signatures[edge_id]):
				invalid = true
				break
		var route := WorldData.find_route(state, str(trip.get("routeId", "")))
		if route.is_empty() or not bool(route.get("open", false)): invalid = true
		if not invalid:
			var ref_lat := float(WorldData.city(str(state.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0])
			var current_path: Dictionary = RoutePathScript.for_route(route, state, ref_lat)
			var current_direction: Dictionary = _find_direction(current_path, str(trip.get("directionId", "")))
			var old_direction: Dictionary = trip.get("directionSnapshot", {})
			if current_direction.is_empty() or _direction_fingerprint(current_direction) != _direction_fingerprint(old_direction):
				invalid = true
		if not invalid:
			surviving.append(trip)
			continue
		var trip_id := str(trip.get("id", ""))
		var stop_index := int(trip.get("currentStopIndex", 0))
		var stop_records: Array = trip.get("stationTimetable", [])
		var last_station := str(stop_records[stop_index].get("stationId", "")) if stop_index >= 0 and stop_index < stop_records.size() else ""
		canceled[trip_id] = last_station
		_clear_trip_loads(capacity_loads, trip_id)
	for raw_batch in batches:
		if not raw_batch is Dictionary: continue
		var batch: Dictionary = raw_batch
		var trip_id := str(batch.get("trainTripId", ""))
		if not canceled.has(trip_id): continue
		var last_station := str(canceled[trip_id])
		if last_station.is_empty(): last_station = str(batch.get("lastValidStationId", ""))
		batch["status"] = "replan"
		batch["lastValidStationId"] = last_station
		batch["trainTripId"] = ""
		batch["capacityLoadKeys"] = []
		batch["nextEventSeconds"] = now_seconds(state)
		batch["plannedRevision"] = -1
	sim["trainTrips"] = surviving
	sim["passengerBatches"] = batches
	sim["capacityLoads"] = capacity_loads
	state["simulation"] = sim
	return canceled.size()

static func now_seconds(state: Dictionary) -> int:
	var sim: Dictionary = state.get("simulation", {})
	return int(sim.get("elapsedSeconds", int(sim.get("elapsedMinutes", sim.get("minute", 420))) * 60))

static func _edge_signature(state: Dictionary, edge: Dictionary) -> String:
	var points: Array = []
	if edge.has("aNodeId"):
		var a := TrackNetwork.find_node(state, str(edge.get("aNodeId", "")))
		var b := TrackNetwork.find_node(state, str(edge.get("bNodeId", "")))
		points = [a.get("latlng", []), b.get("latlng", [])]
	else:
		var a_station := WorldData.find_station(state, str(edge.get("a", {}).get("stationId", "")))
		var b_station := WorldData.find_station(state, str(edge.get("b", {}).get("stationId", "")))
		points = [a_station.get("latlng", []), b_station.get("latlng", [])]
	return JSON.stringify([edge, points])

static func step_one_minute(state: Dictionary, flows: Array[Dictionary], peak_multiplier: float) -> Dictionary:
	var sim: Dictionary = state.get("simulation", {})
	var start_seconds := int(sim.get("elapsedSeconds", int(sim.get("elapsedMinutes", sim.get("minute", 420))) * 60))
	var end_seconds := start_seconds + 60
	var paths := _get_route_paths(state)
	var event_totals := {"completed": 0, "abandoned": 0, "boarded": 0, "departed": 0, "tripMinutesAdded": 0.0, "completedByFlow": {}, "tripMinutesByFlow": {}, "peakCrowding": 0.0, "peakCrowdedRoute": "", "crowdedLinks": {}, "journeyRecords": []}
	var flow_remainders: Dictionary = sim.get("flowRemainders", {})
	var arrivals_by_flow: Dictionary = {}
	var attempted_by_flow: Dictionary = {}
	var attempted := 0
	var unreachable := 0
	_ensure_dispatch_schedules(sim, state, paths, start_seconds)
	_advance_interval(state, flows, paths, start_seconds, end_seconds, event_totals)
	var minute_of_day := posmod(floori(float(end_seconds) / 60.0), 1440)
	var hour := minute_of_day / 60
	var survivors: Array = sim.get("passengerBatches", [])
	for flow in flows:
		var flow_id := str(flow.get("id", ""))
		var expected := float(flow.get("peoplePerDay", 0.0)) / 960.0 * float(flow.get("peakMultiplier", peak_multiplier))
		var accumulated := float(flow_remainders.get(flow_id, 0.0)) + expected
		var count := int(floor(accumulated))
		flow_remainders[flow_id] = accumulated - count
		if count <= 0: continue
		attempted += count
		arrivals_by_flow[flow_id] = count
		attempted_by_flow[flow_id] = count
		if not bool(flow.get("valid", false)):
			unreachable += count
			continue
		var journey: Dictionary = flow.get("journey", {})
		var steps: Array = journey.get("steps", [])
		if steps.is_empty():
			unreachable += count
			continue
		var batch := {"id": "%s@%d" % [flow_id, end_seconds], "flowId": flow_id, "count": count, "bornAtSeconds": end_seconds, "bornAt": floori(float(end_seconds) / 60.0), "stepIndex": 0, "status": "", "nextEventSeconds": end_seconds, "waitStartedSeconds": -1.0, "steps": steps.duplicate(true), "journeyFingerprint": _journey_fingerprint(steps), "originLatLng": flow.get("originLatLng", []), "destinationLatLng": flow.get("destinationLatLng", []), "lastValidStationId": str(journey.get("originStationId", "")), "plannedRevision": int(state.get("revision", 0)), "everBoarded": false, "interruptedRecorded": false, "events": [{"type": "departure", "timeSeconds": end_seconds}]}
		_activate_current_step(batch, batch.steps, end_seconds)
		if str(batch.get("status", "")) == "completed":
			_add_completion(event_totals, batch, end_seconds)
		else:
			survivors.append(batch)
	sim["elapsedSeconds"] = end_seconds
	sim["elapsedMinutes"] = floori(float(end_seconds) / 60.0)
	sim["minute"] = posmod(int(sim.elapsedMinutes), 1440)
	sim["passengerBatches"] = survivors
	sim["flowRemainders"] = flow_remainders
	sim["attempted"] = int(sim.get("attempted", 0)) + attempted
	sim["unreachable"] = int(sim.get("unreachable", 0)) + unreachable
	sim["departed"] = int(sim.get("departed", 0)) + int(event_totals.departed)
	sim["boarded"] = int(sim.get("boarded", 0)) + int(event_totals.boarded)
	sim["served"] = int(sim.get("served", 0)) + int(event_totals.boarded)
	sim["completed"] = int(sim.get("completed", 0)) + int(event_totals.completed)
	sim["abandoned"] = int(sim.get("abandoned", 0)) + int(event_totals.abandoned)
	sim["tripMinutesTotal"] = float(sim.get("tripMinutesTotal", 0.0)) + float(event_totals.tripMinutesAdded)
	sim["waiting"] = _count_status(survivors, "waiting")
	sim["inTransit"] = _count_status(survivors, "walking") + _count_status(survivors, "transferring") + _count_status(survivors, "riding")
	sim["peakCrowding"] = float(event_totals.peakCrowding)
	sim["crowdedLinks"] = event_totals.crowdedLinks
	sim["lastArrivalsByFlow"] = arrivals_by_flow
	sim["lastCompletedByFlow"] = event_totals.completedByFlow
	sim["lastAbandoned"] = int(event_totals.abandoned)
	sim["attemptedByFlow"] = _accumulate_counts(sim.get("attemptedByFlow", {}), attempted_by_flow)
	sim["completedByFlow"] = _accumulate_counts(sim.get("completedByFlow", {}), event_totals.completedByFlow)
	sim["tripMinutesByFlow"] = _accumulate_floats(sim.get("tripMinutesByFlow", {}), event_totals.tripMinutesByFlow)
	var journey_records: Array = sim.get("journeyRecords", [])
	for record in event_totals.journeyRecords:
		journey_records.append(record)
	while journey_records.size() > 1000: journey_records.pop_front()
	sim["journeyRecords"] = journey_records
	var flow_samples: Dictionary = sim.get("flowSamples", {})
	var sample_ids: Dictionary = {}
	for flow_id in arrivals_by_flow: sample_ids[flow_id] = true
	for flow_id in event_totals.completedByFlow: sample_ids[flow_id] = true
	for flow_id in event_totals.tripMinutesByFlow: sample_ids[flow_id] = true
	for flow_id in sample_ids:
		var samples: Array = flow_samples.get(str(flow_id), [])
		samples.append({"minute": int(sim.elapsedMinutes), "attempted": int(arrivals_by_flow.get(flow_id, 0)), "completed": int(event_totals.completedByFlow.get(flow_id, 0)), "tripMinutes": float(event_totals.tripMinutesByFlow.get(flow_id, 0.0))})
		flow_samples[str(flow_id)] = samples
	for flow_id in flow_samples:
		var samples: Array = flow_samples[flow_id]
		while not samples.is_empty() and int(samples[0].get("minute", sim.elapsedMinutes)) <= int(sim.elapsedMinutes) - 60: samples.pop_front()
	sim["flowSamples"] = flow_samples
	var statistics_buckets: Array = sim.get("statisticsBuckets", [])
	var bucket_start := floori(float(sim.elapsedMinutes) / 15.0) * 15
	var bucket: Dictionary = {}
	if not statistics_buckets.is_empty() and int(statistics_buckets.back().get("startMinute", -1)) == bucket_start:
		bucket = statistics_buckets.back()
	else:
		bucket = {"startMinute": bucket_start, "attemptedByFlow": {}, "completedByFlow": {}, "tripMinutesByFlow": {}, "eventSignature": str(sim.get("currentEventSignature", "")), "mixedEventState": false}
		statistics_buckets.append(bucket)
	var bucket_signature := str(bucket.get("eventSignature", ""))
	var current_signature := str(sim.get("currentEventSignature", ""))
	if bucket_signature != current_signature: bucket["mixedEventState"] = true
	for flow_id in arrivals_by_flow: bucket.attemptedByFlow[str(flow_id)] = int(bucket.attemptedByFlow.get(str(flow_id), 0)) + int(arrivals_by_flow[flow_id])
	for flow_id in event_totals.completedByFlow: bucket.completedByFlow[str(flow_id)] = int(bucket.completedByFlow.get(str(flow_id), 0)) + int(event_totals.completedByFlow[flow_id])
	for flow_id in event_totals.tripMinutesByFlow: bucket.tripMinutesByFlow[str(flow_id)] = float(bucket.tripMinutesByFlow.get(str(flow_id), 0.0)) + float(event_totals.tripMinutesByFlow[flow_id])
	while not statistics_buckets.is_empty() and int(statistics_buckets.front().get("startMinute", bucket_start)) < int(sim.elapsedMinutes) - 10080: statistics_buckets.pop_front()
	sim["statisticsBuckets"] = statistics_buckets
	var waiting_by_route: Dictionary = {}
	for batch in survivors:
		if str(batch.get("status", "")) != "waiting": continue
		var steps: Array = batch.get("steps", [])
		var index := int(batch.get("stepIndex", 0))
		if index < steps.size() and str(steps[index].get("type", "")) == "wait": index += 1
		if index >= steps.size() or str(steps[index].get("type", "")) != "rail": continue
		var route_id := str(steps[index].get("routeId", ""))
		waiting_by_route[route_id] = int(waiting_by_route.get(route_id, 0)) + int(batch.get("count", 0))
	sim["waitingByRoute"] = waiting_by_route
	var crowding_samples: Array = sim.get("crowdingSamples", [])
	crowding_samples.append({"value": float(event_totals.peakCrowding), "routeId": str(event_totals.peakCrowdedRoute)})
	while crowding_samples.size() > 60: crowding_samples.pop_front()
	sim["crowdingSamples"] = crowding_samples
	var rolling_peak := 0.0
	var rolling_peak_route := ""
	for sample in crowding_samples:
		var value := float(sample.get("value", 0.0)) if sample is Dictionary else float(sample)
		if value > rolling_peak:
			rolling_peak = value
			rolling_peak_route = str(sample.get("routeId", "")) if sample is Dictionary else ""
	sim["peakCrowding"] = rolling_peak
	sim["peakCrowdedRoute"] = rolling_peak_route
	state["simulation"] = sim
	return {"arrivalsByFlow": arrivals_by_flow, "completedByFlow": event_totals.completedByFlow, "tripMinutesByFlow": event_totals.tripMinutesByFlow, "journeyRecords": event_totals.journeyRecords, "attempted": attempted, "unreachable": unreachable, "boarded": int(event_totals.boarded), "departed": int(event_totals.departed), "completed": int(event_totals.completed), "abandoned": int(event_totals.abandoned), "tripMinutesAdded": float(event_totals.tripMinutesAdded), "peakCrowding": float(event_totals.peakCrowding), "waitingByRoute": waiting_by_route}

static func _ensure_dispatch_schedules(sim: Dictionary, state: Dictionary, paths: Dictionary, now_seconds: int) -> void:
	var schedules: Dictionary = sim.get("nextDepartureSeconds", {})
	for route in state.get("routes", []):
		if not bool(route.get("open", false)): continue
		var path: Dictionary = paths.get(str(route.get("id", "")), {})
		if not bool(path.get("valid", false)): continue
		for direction in path.get("directions", []):
			var key := "%s|%s" % [str(route.get("id", "")), str(direction.get("id", "forward"))]
			if schedules.has(key): continue
			var service_start := int(route.get("serviceStartMinute", floori(float(now_seconds) / 60.0))) * 60
			schedules[key] = maxi(now_seconds, service_start)
	sim["nextDepartureSeconds"] = schedules

static func reschedule_route(state: Dictionary, route_id: String) -> void:
	var sim: Dictionary = state.get("simulation", {})
	var schedules: Dictionary = sim.get("nextDepartureSeconds", {})
	var now_seconds := int(sim.get("elapsedSeconds", int(sim.get("elapsedMinutes", 420)) * 60))
	var route := WorldData.find_route(state, route_id)
	if route.is_empty(): return
	var path := RoutePathScript.for_route(route, state, float(WorldData.city(str(state.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0]))
	var next_seconds := ServiceScheduleScript.headway_minutes(route, now_seconds) * 60
	for direction in path.get("directions", []): schedules["%s|%s" % [route_id, str(direction.get("id", "forward"))]] = now_seconds + next_seconds
	sim["nextDepartureSeconds"] = schedules
	state["simulation"] = sim

static func _advance_interval(state: Dictionary, flows: Array[Dictionary], paths: Dictionary, start_seconds: int, end_seconds: int, totals: Dictionary) -> void:
	var sim: Dictionary = state.get("simulation", {})
	var ref_lat := float(WorldData.city(str(state.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0])
	var journey_network := JourneyModelScript.build_network(state, ref_lat)
	var batches: Array = sim.get("passengerBatches", [])
	var trips: Array = sim.get("trainTrips", [])
	var capacity_loads: Dictionary = sim.get("capacityLoads", {})
	var schedules: Dictionary = sim.get("nextDepartureSeconds", {})
	var specs: Dictionary = {}
	var routes_by_id: Dictionary = {}
	for route in state.get("routes", []):
		if not bool(route.get("open", false)): continue
		var route_id := str(route.get("id", ""))
		routes_by_id[route_id] = route
		for direction in paths.get(route_id, {}).get("directions", []):
			var key := "%s|%s" % [route_id, str(direction.get("id", "forward"))]
			specs[key] = {"routeId": route_id, "route": route, "direction": direction, "capacity": int(WorldData.vehicle(str(route.get("vehicleId", "B-6"))).get("capacity", 1800))}
	var now := float(start_seconds)
	var event_count := 0
	while now <= float(end_seconds) + 0.0001 and event_count < 10000:
		var next_time := float(end_seconds)
		for key in specs:
			var scheduled := float(schedules.get(str(key), INF))
			if scheduled >= now - 0.0001: next_time = minf(next_time, scheduled)
		var next_schedule_boundary := INF
		for route_id in routes_by_id:
			var route: Dictionary = routes_by_id[route_id]
			if str(ServiceScheduleScript.ensure_profile(route).get("mode", "uniform")) != "time_of_day": continue
			var boundary := float(ServiceScheduleScript.next_boundary_after(int(floor(now + 0.0001))))
			if boundary <= float(end_seconds) + 0.0001:
				next_schedule_boundary = minf(next_schedule_boundary, boundary)
				next_time = minf(next_time, boundary)
		var trip_event_records: Array[Dictionary] = []
		for trip in trips:
			if bool(trip.get("_simRemove", false)): continue
			var event_time := float(trip.get("nextEventSeconds", INF))
			if str(trip.get("phase", "")) in ["moving", "dwell"] and event_time >= now - 0.0001:
				next_time = minf(next_time, event_time)
				trip_event_records.append({"trip": trip, "time": event_time})
		var batch_event_records: Array[Dictionary] = []
		var riders_by_trip: Dictionary = {}
		var waiters_by_platform: Dictionary = {}
		for batch in batches:
			if bool(batch.get("_simRemove", false)): continue
			var status := str(batch.get("status", ""))
			var event_time := float(batch.get("nextEventSeconds", INF))
			if status == "waiting":
				event_time = float(batch.get("waitStartedSeconds", now)) + MAX_WAIT_MINUTES * 60.0
				var platform_key := _waiting_platform_key(batch)
				if not platform_key.is_empty(): _queue_waiting_batch(waiters_by_platform, platform_key, batch)
			elif status == "riding":
				var trip_id := str(batch.get("trainTripId", ""))
				if not riders_by_trip.has(trip_id): riders_by_trip[trip_id] = []
				var trip_riders: Array = riders_by_trip[trip_id]
				trip_riders.append(batch)
			if status in ["walking", "transferring", "waiting"] and event_time >= now - 0.0001:
				next_time = minf(next_time, event_time)
				batch_event_records.append({"batch": batch, "time": event_time})
		if next_time > float(end_seconds) + 0.0001: break
		now = maxf(now, next_time)
		event_count += 1
		var due_arrivals: Array[Dictionary] = []
		var due_dwell_trips: Array[Dictionary] = []
		for event_record in trip_event_records:
			if float(event_record.get("time", INF)) > now + 0.0001: continue
			var event_trip: Dictionary = event_record.get("trip", {})
			if str(event_trip.get("phase", "")) == "moving": due_arrivals.append(event_trip)
			elif str(event_trip.get("phase", "")) == "dwell": due_dwell_trips.append(event_trip)
		var due_batches: Array[Dictionary] = []
		for event_record in batch_event_records:
			if float(event_record.get("time", INF)) <= now + 0.0001:
				var event_batch: Dictionary = event_record.get("batch", {})
				if not bool(event_batch.get("_simRemove", false)): due_batches.append(event_batch)
		var due_dispatches: Array[String] = []
		for key in specs:
			if float(schedules.get(str(key), INF)) <= now + 0.0001: due_dispatches.append(str(key))
		# 1. Arrivals happen first. Riders alight and free their exact train's seats.
		for trip in due_arrivals:
			if str(trip.get("phase", "")) != "moving": continue
			var arrived_index := int(trip.get("nextStopIndex", -1))
			trip["currentStopIndex"] = arrived_index
			trip["phase"] = "dwell"
			var stop_records: Array = trip.get("stationTimetable", [])
			if arrived_index < 0 or arrived_index >= stop_records.size(): continue
			var stop: Dictionary = stop_records[arrived_index]
			trip["nextEventSeconds"] = float(stop.get("departureSeconds", now))
			var riders: Array = riders_by_trip.get(str(trip.get("id", "")), [])
			for raw_rider in riders:
				if not raw_rider is Dictionary: continue
				var batch: Dictionary = raw_rider
				if str(batch.get("status", "")) != "riding" or str(batch.get("trainTripId", "")) != str(trip.get("id", "")): continue
				_append_batch_event(batch, "train_arrive", now, {"routeId": str(trip.get("routeId", "")), "directionId": str(trip.get("directionId", "")), "stationId": str(stop.get("stationId", "")), "tripId": str(trip.get("id", ""))})
				_release_passed_capacity(sim, capacity_loads, batch, trip, arrived_index)
				batch["lastValidStationId"] = str(stop.get("stationId", ""))
				if int(batch.get("alightStopIndex", -1)) != arrived_index and not bool(batch.get("replanAfterArrival", false)):
					var rider_steps: Array = batch.get("steps", [])
					var rider_step_index := int(batch.get("stepIndex", 0))
					if rider_step_index < rider_steps.size() and str(rider_steps[rider_step_index].get("type", "")) == "rail":
						var next_keys := _capacity_keys_for_step_at_stop(trip, rider_steps[rider_step_index], arrived_index)
						batch["capacityLoadKeys"] = next_keys
						for next_key in next_keys:
							capacity_loads[next_key] = int(capacity_loads.get(next_key, 0)) + int(batch.get("count", 0))
							_change_trip_load(sim, str(trip.get("id", "")), next_key, int(batch.get("count", 0)))
					continue
				_release_batch_capacity(sim, capacity_loads, batch)
				batch["trainTripId"] = ""
				batch["capacityLoadKeys"] = []
				if bool(batch.get("replanAfterArrival", false)):
					_replan_batch(state, batch, _find_flow(flows, str(batch.get("flowId", ""))), int(now), journey_network, ref_lat)
				else:
					batch["stepIndex"] = int(batch.get("stepIndex", 0)) + 1
					_activate_current_step(batch, batch.get("steps", []), now)
				if str(batch.get("status", "")) == "completed":
					_add_completion(totals, batch, now)
					batch["_simRemove"] = true
				elif str(batch.get("status", "")) == "waiting":
					var platform_key := _waiting_platform_key(batch)
					if not platform_key.is_empty(): _queue_waiting_batch(waiters_by_platform, platform_key, batch)
			# Boarding starts on arrival during the dwell, while departure remains
			# scheduled at the later timetable time.
			if not due_dwell_trips.has(trip): due_dwell_trips.append(trip)
		# 2. Finish all walks and transfers at this instant before boarding queues.
		for batch in due_batches:
			var status := str(batch.get("status", ""))
			if status == "waiting" and now - float(batch.get("waitStartedSeconds", now)) >= MAX_WAIT_MINUTES * 60.0 - 0.0001:
				totals["abandoned"] = int(totals.get("abandoned", 0)) + int(batch.get("count", 0))
				batch["_simRemove"] = true
				continue
			if status in ["walking", "transferring"] and float(batch.get("nextEventSeconds", INF)) <= now + 0.0001:
				_append_batch_event(batch, "step_complete", now, {"stepIndex": int(batch.get("stepIndex", 0)), "stepType": status})
				batch["stepIndex"] = int(batch.get("stepIndex", 0)) + 1
				_activate_current_step(batch, batch.get("steps", []), now)
				if str(batch.get("status", "")) == "completed":
					_add_completion(totals, batch, now)
					batch["_simRemove"] = true
				elif str(batch.get("status", "")) == "waiting":
					var platform_key := _waiting_platform_key(batch)
					if not platform_key.is_empty(): _queue_waiting_batch(waiters_by_platform, platform_key, batch)
		# Scheduled dispatches enter the origin platform after alighting and walking events.
		for key in due_dispatches:
			var spec: Dictionary = specs[key]
			var departure_seconds := float(schedules.get(str(key), INF))
			if departure_seconds > now + 0.0001: continue
			var direction: Dictionary = spec.get("direction", {})
			var trip := _make_train_trip_seconds(str(spec.get("routeId", "")), direction, int(round(departure_seconds)))
			trip["capacity"] = int(spec.get("capacity", 1800))
			trip["edgeSignatures"] = _direction_edge_signatures(state, direction)
			trip["phase"] = "dwell"
			trip["currentStopIndex"] = 0
			trip["nextEventSeconds"] = departure_seconds
			trips.append(trip)
			var service_route: Dictionary = spec.get("route", {})
			schedules[str(key)] = departure_seconds + ServiceScheduleScript.headway_minutes(service_route, int(round(departure_seconds))) * 60
			due_dwell_trips.append(trip)
		# A departure scheduled exactly on the boundary remains valid. All other
		# pending departures are re-anchored to the new interval without catch-up.
		if is_equal_approx(now, next_schedule_boundary):
			for key in specs:
				var boundary_spec: Dictionary = specs[key]
				var boundary_route: Dictionary = boundary_spec.get("route", {})
				if str(ServiceScheduleScript.ensure_profile(boundary_route).get("mode", "uniform")) != "time_of_day": continue
				if float(ServiceScheduleScript.next_boundary_after(int(floor(now - 0.0001)))) != now: continue
				if float(schedules.get(str(key), INF)) > now + 0.0001:
					schedules[str(key)] = int(now) + ServiceScheduleScript.headway_minutes(boundary_route, int(now)) * 60
		# 3. Board in arrival order. Each batch only uses the remaining seats of this trip.
		for trip in due_dwell_trips:
			if str(trip.get("phase", "")) != "dwell" or float(trip.get("nextEventSeconds", now)) < now - 0.0001: continue
			var stop_index := int(trip.get("currentStopIndex", -1))
			var stop_records: Array = trip.get("stationTimetable", [])
			if stop_index < 0 or stop_index >= stop_records.size(): continue
			var station_id := str(stop_records[stop_index].get("stationId", ""))
			var queue_key := _waiting_platform_key_for_trip(trip, station_id, stop_index)
			var boarding_queue: Array = waiters_by_platform.get(queue_key, [])
			var batch_index := 0
			while batch_index < boarding_queue.size():
				var batch: Dictionary = boarding_queue[batch_index]
				if bool(batch.get("_simRemove", false)) or str(batch.get("status", "")) != "waiting":
					batch_index += 1
					continue
				var journey_steps: Array = batch.get("steps", [])
				var step_index := int(batch.get("stepIndex", 0))
				if step_index < journey_steps.size() and str(journey_steps[step_index].get("type", "")) == "wait": step_index += 1
				if step_index >= journey_steps.size():
					batch_index += 1
					continue
				var rail_step: Dictionary = journey_steps[step_index]
				if str(rail_step.get("type", "")) != "rail":
					batch_index += 1
					continue
				if str(rail_step.get("routeId", "")) != str(trip.get("routeId", "")) or str(rail_step.get("directionId", "")) != str(trip.get("directionId", "")):
					batch_index += 1
					continue
				if str(rail_step.get("fromStationId", "")) != station_id or int(rail_step.get("fromStopIndex", stop_index)) != stop_index:
					batch_index += 1
					continue
				var load_keys := _capacity_keys_for_step_at_stop(trip, rail_step, stop_index)
				var capacity := maxi(1, int(trip.get("capacity", 1800)))
				var available := capacity
				for load_key in load_keys: available = mini(available, maxi(0, capacity - int(capacity_loads.get(load_key, 0))))
				if available <= 0:
					batch_index += 1
					continue
				var count := int(batch.get("count", 0))
				var board_count := mini(count, available)
				var rider := batch.duplicate(true)
				_append_batch_event(rider, "train_board", now, {"routeId": str(trip.get("routeId", "")), "directionId": str(trip.get("directionId", "")), "stationId": station_id, "tripId": str(trip.get("id", "")), "fromStopIndex": stop_index, "toStopIndex": int(rail_step.get("toStopIndex", stop_index + 1))})
				rider["count"] = board_count
				rider["status"] = "riding"
				rider["stepIndex"] = step_index
				rider["trainTripId"] = str(trip.get("id", ""))
				rider["boardedAtSeconds"] = now
				rider["fromStopIndex"] = stop_index
				rider["alightStopIndex"] = int(rail_step.get("toStopIndex", stop_index + 1))
				rider["capacityLoadKeys"] = load_keys.duplicate()
				rider["waitStartedSeconds"] = -1.0
				if not bool(batch.get("everBoarded", false)): totals["departed"] = int(totals.get("departed", 0)) + board_count
				rider["everBoarded"] = true
				for load_key in load_keys:
					capacity_loads[load_key] = int(capacity_loads.get(load_key, 0)) + board_count
					_change_trip_load({"trainTrips": trips}, str(trip.get("id", "")), load_key, board_count)
					var occupancy := float(capacity_loads[load_key]) / float(capacity)
					if occupancy > float(totals.get("peakCrowding", 0.0)):
						totals["peakCrowding"] = occupancy
						totals["peakCrowdedRoute"] = str(trip.get("routeId", ""))
					if occupancy >= 0.85: totals.crowdedLinks[load_key] = occupancy
				totals["boarded"] = int(totals.get("boarded", 0)) + board_count
				if board_count < count:
					batch["count"] = count - board_count
					batch["stepIndex"] = step_index - 1 if step_index > int(batch.get("stepIndex", 0)) else step_index
					batch["waitStartedSeconds"] = float(batch.get("waitStartedSeconds", now))
				else:
					batch["_simRemove"] = true
				# The boarded share advances independently; the unboarded share remains queued.
				batch = rider
				batch["status"] = "riding"
				batch["nextEventSeconds"] = -1.0
				# Full batches are represented directly in the survivor list.
				batches.append(batch)
				if board_count < count: batch_index += 1
		# 4. Trains leave after queues at the platform have had this event to board.
		for trip in due_dwell_trips:
			if str(trip.get("phase", "")) != "dwell" or float(trip.get("nextEventSeconds", INF)) > now + 0.0001: continue
			var stop_index := int(trip.get("currentStopIndex", -1))
			var stop_records: Array = trip.get("stationTimetable", [])
			if stop_index < 0 or stop_index >= stop_records.size():
				_clear_trip_loads(capacity_loads, str(trip.get("id", "")))
				trip["_simRemove"] = true
				continue
			if stop_index >= stop_records.size() - 1:
				_clear_trip_loads(capacity_loads, str(trip.get("id", "")))
				trip["_simRemove"] = true
				continue
			var direction: Dictionary = trip.get("directionSnapshot", {})
			var segments: Array = direction.get("segments", [])
			if stop_index >= segments.size():
				_clear_trip_loads(capacity_loads, str(trip.get("id", "")))
				trip["_simRemove"] = true
				continue
			var segment: Dictionary = segments[stop_index]
			trip["phase"] = "moving"
			trip["nextStopIndex"] = stop_index + 1
			trip["nextEventSeconds"] = float(stop_records[stop_index].get("departureSeconds", now)) + float(segment.get("movingMinutes", segment.get("travelMinutes", 0.0))) * 60.0
		if now >= float(end_seconds) - 0.0001: break
		if event_count >= 10000: push_error("模拟事件过多，已在安全上限停止本分钟推进")
	var retained_batches: Array = []
	for batch in batches:
		if not bool(batch.get("_simRemove", false)):
			batch.erase("_simRemove")
			retained_batches.append(batch)
	var retained_trips: Array = []
	for trip in trips:
		if not bool(trip.get("_simRemove", false)):
			trip.erase("_simRemove")
			retained_trips.append(trip)
	batches = retained_batches
	trips = retained_trips
	for trip in trips:
		trip["elapsedSeconds"] = maxf(0.0, float(end_seconds) - float(trip.get("departureSeconds", end_seconds)))
		trip["elapsedMinutes"] = float(trip.elapsedSeconds) / 60.0
	sim["passengerBatches"] = batches
	sim["trainTrips"] = trips
	sim["capacityLoads"] = capacity_loads
	sim["nextDepartureSeconds"] = schedules
	sim["trainTripsInitialized"] = true
	state["simulation"] = sim

static func _waiting_platform_key(batch: Dictionary) -> String:
	var steps: Array = batch.get("steps", [])
	var step_index := int(batch.get("stepIndex", 0))
	if step_index < steps.size() and str(steps[step_index].get("type", "")) == "wait": step_index += 1
	if step_index < 0 or step_index >= steps.size(): return ""
	var rail_step: Dictionary = steps[step_index]
	if str(rail_step.get("type", "")) != "rail": return ""
	return _waiting_platform_key_for_values(str(rail_step.get("routeId", "")), str(rail_step.get("directionId", "forward")), str(rail_step.get("fromStationId", "")), int(rail_step.get("fromStopIndex", 0)))

static func _waiting_platform_key_for_trip(trip: Dictionary, station_id: String, stop_index: int) -> String:
	return _waiting_platform_key_for_values(str(trip.get("routeId", "")), str(trip.get("directionId", "forward")), station_id, stop_index)

static func _waiting_platform_key_for_values(route_id: String, direction_id: String, station_id: String, stop_index: int) -> String:
	return "%s|%s|%s|%d" % [route_id, direction_id, station_id, stop_index]

static func _queue_waiting_batch(waiters_by_platform: Dictionary, platform_key: String, batch: Dictionary) -> void:
	if not waiters_by_platform.has(platform_key): waiters_by_platform[platform_key] = []
	var queue: Array = waiters_by_platform[platform_key]
	queue.append(batch)

static func _activate_current_step(batch: Dictionary, steps: Array, now_seconds: float) -> void:
	while int(batch.get("stepIndex", 0)) < steps.size():
		var index := int(batch.get("stepIndex", 0))
		var step: Dictionary = steps[index]
		var type := str(step.get("type", ""))
		if type in ["wait", "rail"]:
			batch["status"] = "waiting"
			batch["waitStartedSeconds"] = now_seconds
			batch["queueOrder"] = int(batch.get("queueOrder", 0)) + 1
			batch["nextEventSeconds"] = -1.0
			return
		var duration_minutes := float(step.get("minutes", 0.0))
		if duration_minutes <= 0.0:
			batch["stepIndex"] = index + 1
			continue
		batch["status"] = "transferring" if type == "transfer" else "walking"
		batch["nextEventSeconds"] = now_seconds + duration_minutes * 60.0
		return
	batch["status"] = "completed"
	batch["completedAtSeconds"] = now_seconds

static func _capacity_keys_for_step_at_stop(trip: Dictionary, rail_step: Dictionary, stop_index: int) -> Array[String]:
	var result: Array[String] = []
	var segments: Array = rail_step.get("segments", [])
	for segment in segments:
		if int(segment.get("fromStopIndex", -1)) != stop_index or int(segment.get("toStopIndex", -1)) != stop_index + 1: continue
		var directions: Dictionary = {}
		for direction in segment.get("linkDirections", []):
			if direction is Dictionary: directions[str(direction.get("id", ""))] = "fwd" if bool(direction.get("forward", true)) else "rev"
		var link_ids: Array = segment.get("linkIds", [])
		if link_ids.is_empty(): link_ids = ["station:%s" % str(segment.get("fromStationId", ""))]
		for link_id in link_ids:
			var key := "%s|%s|%s" % [str(trip.get("id", "")), str(link_id), str(directions.get(str(link_id), "na"))]
			if not result.has(key): result.append(key)
		return result
	return result

static func _capacity_keys_for_segment(trip: Dictionary, segment_index: int) -> Array[String]:
	var result: Array[String] = []
	var segments: Array = trip.get("directionSnapshot", {}).get("segments", [])
	if segment_index < 0 or segment_index >= segments.size(): return result
	var segment: Dictionary = segments[segment_index]
	var directions: Dictionary = {}
	for direction in segment.get("linkDirections", []):
		if direction is Dictionary:
			directions[str(direction.get("id", ""))] = "fwd" if bool(direction.get("forward", true)) else "rev"
	for raw_link_id in segment.get("linkIds", []):
		var link_id := str(raw_link_id)
		result.append("%s|%s|%s" % [str(trip.get("id", "")), link_id, str(directions.get(link_id, "na"))])
	return result

static func _release_passed_capacity(sim: Dictionary, capacity_loads: Dictionary, batch: Dictionary, trip: Dictionary, arrived_stop_index: int) -> void:
	var passed_keys := _capacity_keys_for_segment(trip, arrived_stop_index - 1)
	var held_keys: Array = batch.get("capacityLoadKeys", [])
	var count := int(batch.get("count", 0))
	var trip_id := str(trip.get("id", ""))
	for raw_key in passed_keys:
		var key := str(raw_key)
		if not held_keys.has(key): continue
		var remaining := maxi(0, int(capacity_loads.get(key, 0)) - count)
		if remaining <= 0: capacity_loads.erase(key)
		else: capacity_loads[key] = remaining
		_change_trip_load(sim, trip_id, key, -count)
		held_keys.erase(key)
	batch["capacityLoadKeys"] = held_keys

static func _direction_edge_signatures(state: Dictionary, direction: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var edge_by_id: Dictionary = {}
	for edge in TrackNetwork.all_physical_edges(state): edge_by_id[str(edge.get("id", ""))] = edge
	for segment in direction.get("segments", []):
		for raw_id in segment.get("linkIds", []):
			var edge_id := str(raw_id)
			if edge_by_id.has(edge_id): result[edge_id] = _edge_signature(state, edge_by_id[edge_id])
	return result

static func _direction_fingerprint(direction: Dictionary) -> String:
	var segments: Array = []
	for segment in direction.get("segments", []):
		segments.append([str(segment.get("fromStationId", "")), str(segment.get("toStationId", "")), segment.get("linkDirections", [])])
	return JSON.stringify(segments)

static func _add_completion(totals: Dictionary, batch: Dictionary, now_seconds: float) -> void:
	var count := int(batch.get("count", 0))
	var flow_id := str(batch.get("flowId", ""))
	var duration_minutes := maxf(0.0, (now_seconds - float(batch.get("bornAtSeconds", now_seconds))) / 60.0)
	totals["completed"] = int(totals.get("completed", 0)) + count
	totals["completedByFlow"][flow_id] = int(totals.completedByFlow.get(flow_id, 0)) + count
	var trip_minutes := duration_minutes * float(count)
	totals["tripMinutesAdded"] = float(totals.get("tripMinutesAdded", 0.0)) + trip_minutes
	totals["tripMinutesByFlow"][flow_id] = float(totals.tripMinutesByFlow.get(flow_id, 0.0)) + trip_minutes
	var record_key := "%s|%d|%d" % [str(batch.get("id", flow_id)), int(round(now_seconds)), count]
	if _is_sampled_journey_record(record_key):
		var steps: Array = batch.get("steps", [])
		var summary: Array[String] = []
		for step in steps:
			if not step is Dictionary: continue
			var type := str(step.get("type", ""))
			if type == "rail": summary.append("乘车 %s → %s" % [str(step.get("fromStationId", "")), str(step.get("toStationId", ""))])
			elif type in ["walk", "access"]: summary.append("步行 %.0f 米" % float(step.get("distanceM", 0.0)))
			elif type == "transfer": summary.append("换乘步行 %.0f 分钟" % float(step.get("minutes", 0.0)))
		var records: Array = totals.get("journeyRecords", [])
		records.append({"id": record_key, "flowId": flow_id, "count": count, "departureSeconds": int(batch.get("bornAtSeconds", now_seconds)), "arrivalSeconds": int(round(now_seconds)), "durationMinutes": duration_minutes, "steps": steps.duplicate(true), "summary": summary, "events": batch.get("events", []).duplicate(true) if batch.get("events", []) is Array else []})
		totals["journeyRecords"] = records

static func _append_batch_event(batch: Dictionary, event_type: String, at_seconds: float, details: Dictionary = {}) -> void:
	var events: Array = batch.get("events", [])
	if events.size() >= 96: return
	var event := {"type": event_type, "timeSeconds": int(round(at_seconds))}
	for key in details: event[key] = details[key]
	events.append(event)
	batch["events"] = events

static func _is_sampled_journey_record(record_key: String) -> bool:
	# Stable across platforms and Godot builds; retain roughly one batch in four.
	var hash_value := 17
	for index in range(record_key.length()):
		hash_value = posmod(hash_value * 31 + record_key.unicode_at(index), 100)
	return hash_value < 25

static func _accumulate_counts(current: Variant, added: Dictionary) -> Dictionary:
	var result: Dictionary = current.duplicate()
	for key in added: result[key] = int(result.get(key, 0)) + int(added[key])
	return result

static func _accumulate_floats(current: Variant, added: Dictionary) -> Dictionary:
	var result: Dictionary = current.duplicate()
	for key in added: result[key] = float(result.get(key, 0.0)) + float(added[key])
	return result

static func _journey_fingerprint(steps: Array) -> String:
	var identity: Array = []
	for step in steps:
		var type := str(step.get("type", ""))
		if type == "rail":
			identity.append(["rail", str(step.get("routeId", "")), str(step.get("directionId", "")), str(step.get("fromStationId", "")), str(step.get("toStationId", "")), step.get("linkDirections", [])])
		elif type == "transfer":
			identity.append(["transfer", str(step.get("stationId", "")), str(step.get("fromRouteId", "")), str(step.get("toRouteId", ""))])
		elif type == "walk":
			identity.append(["walk", str(step.get("stationId", "")), str(step.get("place", ""))])
	return JSON.stringify(identity)

static func _step_one_minute_legacy(state: Dictionary, flows: Array[Dictionary], peak_multiplier: float) -> Dictionary:
	var sim: Dictionary = state.get("simulation", {})
	var route_paths := _get_route_paths(state)
	var absolute_minute := int(sim.get("elapsedMinutes", sim.get("minute", 420))) + 1
	sim["elapsedMinutes"] = absolute_minute
	sim["minute"] = posmod(absolute_minute, 1440)
	var capacity_loads: Dictionary = sim.get("capacityLoads", {})
	var remainders: Dictionary = sim.get("flowRemainders", {})
	var batches: Array = sim.get("passengerBatches", [])
	var arrivals_by_flow: Dictionary = {}
	var completed_by_flow: Dictionary = {}
	var trip_minutes_by_flow: Dictionary = {}
	var attempted := 0
	var unreachable := 0
	var boarded := 0
	var departed := 0
	var completed := 0
	var abandoned_now := 0
	var trip_minutes_added := 0.0
	var peak_crowding := 0.0
	var peak_crowded_route := ""
	var crowded_links: Dictionary = {}
	_update_train_trips(sim, state, route_paths, absolute_minute, capacity_loads)
	var hour := int(sim.minute) / 60
	for flow in flows:
		var flow_id := str(flow.get("id", ""))
		var expected := float(flow.get("peoplePerDay", 0.0)) / (16.0 * 60.0) * float(flow.get("peakMultiplier", peak_multiplier))
		var accumulated := float(remainders.get(flow_id, 0.0)) + expected
		var count := int(floor(accumulated))
		remainders[flow_id] = accumulated - count
		if count <= 0: continue
		attempted += count
		arrivals_by_flow[flow_id] = count
		if not bool(flow.get("valid", false)):
			unreachable += count
			continue
		var journey: Dictionary = flow.get("journey", {})
		var steps: Array = journey.get("steps", [])
		if steps.is_empty():
			unreachable += count
			continue
		var batch := {"id": "%s@%d" % [flow_id, absolute_minute], "flowId": flow_id, "count": count, "bornAt": absolute_minute, "stepIndex": 0, "status": "", "remainingMinutes": 0.0, "waitedMinutes": 0, "steps": steps.duplicate(true), "originLatLng": flow.get("originLatLng", []), "destinationLatLng": flow.get("destinationLatLng", []), "lastValidStationId": str(journey.get("originStationId", "")), "plannedRevision": int(state.get("revision", 0)), "everBoarded": false, "interruptedRecorded": false}
		_enter_current_step(batch, batch.steps, absolute_minute)
		if str(batch.get("status", "")) == "completed":
			completed += count
			completed_by_flow[flow_id] = int(completed_by_flow.get(flow_id, 0)) + count
		else:
			batches.append(batch)
	# Advance existing walking and onboard batches by one game minute.
	var survivors: Array = []
	for raw_batch in batches:
		if not raw_batch is Dictionary: continue
		var batch: Dictionary = raw_batch
		var status := str(batch.get("status", ""))
		var count := int(batch.get("count", 0))
		if count <= 0: continue
		if int(batch.get("bornAt", absolute_minute)) >= absolute_minute:
			survivors.append(batch)
			continue
		var flow := _find_flow(flows, str(batch.get("flowId", "")))
		var steps: Array = batch.get("steps", flow.get("journey", {}).get("steps", []))
		if status == "disrupted":
			survivors.append(batch)
			continue
		if status == "waiting":
			batch.waitedMinutes = int(batch.get("waitedMinutes", 0)) + 1
			if int(batch.waitedMinutes) > MAX_WAIT_MINUTES:
				abandoned_now += count
				continue
			var current_index := int(batch.get("stepIndex", 0))
			var wait_step: Dictionary = steps[current_index] if current_index < steps.size() else {}
			var rail_index := current_index + 1 if str(wait_step.get("type", "")) == "wait" else current_index
			var rail_step: Dictionary = steps[rail_index] if rail_index < steps.size() else {}
			var route_id := str(rail_step.get("routeId", wait_step.get("routeId", "")))
			var direction_id := str(rail_step.get("directionId", "forward"))
			var route := WorldData.find_route(state, route_id)
			if route.is_empty() or not bool(route.get("open", false)) or not bool(flow.get("valid", false)):
				var ref_lat := float(WorldData.city(str(state.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0])
				var network := JourneyModelScript.build_network(state, ref_lat)
				_replan_batch(state, batch, flow, absolute_minute, network, ref_lat)
				survivors.append(batch)
				continue
			if str(rail_step.get("type", "")) != "rail":
				abandoned_now += count
				continue
			var boarding_station_id := str(rail_step.get("fromStationId", wait_step.get("stationId", "")))
			var boarding_trip := _find_boarding_train(sim, route_id, direction_id, boarding_station_id)
			if boarding_trip.is_empty():
				survivors.append(batch)
				continue
			var profile := WorldData.vehicle(str(route.get("vehicleId", "B-6")))
			var capacity := maxi(1, int(profile.get("capacity", 1800)))
			var link_keys: Array[String] = []
			var train_key := str(boarding_trip.get("id", ""))
			var link_direction_by_id: Dictionary = {}
			for direction_record in rail_step.get("linkDirections", []):
				if direction_record is Dictionary: link_direction_by_id[str(direction_record.get("id", ""))] = "fwd" if bool(direction_record.get("forward", true)) else "rev"
			var available := capacity
			for raw_link_id in rail_step.get("linkIds", []):
				var link_id := str(raw_link_id)
				var load_key := "%s|%s|%s" % [train_key, link_id, str(link_direction_by_id.get(link_id, "na"))]
				if not link_keys.has(load_key): link_keys.append(load_key)
				available = mini(available, maxi(0, capacity - int(capacity_loads.get(load_key, 0))))
			if available <= 0:
				survivors.append(batch)
				continue
			var boarded_count := mini(count, available)
			for load_key in link_keys:
				capacity_loads[load_key] = int(capacity_loads.get(load_key, 0)) + boarded_count
				_change_trip_load(sim, train_key, load_key, boarded_count)
				var occupancy := float(capacity_loads[load_key]) / float(capacity)
				if occupancy > peak_crowding:
					peak_crowding = occupancy
					peak_crowded_route = route_id
				if occupancy >= 0.85: crowded_links[load_key] = occupancy
			boarded += boarded_count
			var rider := batch.duplicate(true)
			rider.count = boarded_count
			rider.stepIndex = rail_index
			rider.status = "riding"
			rider.remainingMinutes = maxf(1.0, float(rail_step.get("minutes", 1.0)))
			rider.trainTripId = train_key
			rider.capacityLoadKeys = link_keys.duplicate()
			rider.waitedMinutes = 0
			rider.lastValidStationId = str(rail_step.get("fromStationId", wait_step.get("stationId", "")))
			if not bool(batch.get("everBoarded", false)): departed += boarded_count
			rider.everBoarded = true
			if boarded_count < count:
				batch.count = count - boarded_count
				survivors.append(batch)
			survivors.append(rider)
			continue
		if status in ["walking", "transferring", "riding"]:
			batch.remainingMinutes = float(batch.get("remainingMinutes", 0.0)) - 1.0
			if float(batch.remainingMinutes) <= 0.0:
				if status == "riding":
					_release_batch_capacity(sim, capacity_loads, batch)
					var completed_segment_index := int(batch.get("stepIndex", 0))
					var completed_segment: Dictionary = steps[completed_segment_index] if completed_segment_index < steps.size() else {}
					batch.lastValidStationId = str(completed_segment.get("toStationId", batch.get("lastValidStationId", "")))
					if bool(batch.get("replanAfterArrival", false)):
						var ref_lat := float(WorldData.city(str(state.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0])
						var network := JourneyModelScript.build_network(state, ref_lat)
						batch.replanAfterArrival = false
						_replan_batch(state, batch, flow, absolute_minute, network, ref_lat)
						survivors.append(batch)
						continue
				if status == "riding": batch.stepIndex = int(batch.get("stepIndex", 0)) + 1
				else: batch.stepIndex = int(batch.get("stepIndex", 0)) + 1
				_enter_current_step(batch, steps, absolute_minute)
				if str(batch.get("status", "")) == "completed":
					completed += count
					completed_by_flow[str(batch.get("flowId", ""))] = int(completed_by_flow.get(str(batch.get("flowId", "")), 0)) + count
					var flow_trip_minutes := float(maxi(1, absolute_minute - int(batch.get("bornAt", absolute_minute)))) * count
					trip_minutes_added += flow_trip_minutes
					trip_minutes_by_flow[str(batch.get("flowId", ""))] = float(trip_minutes_by_flow.get(str(batch.get("flowId", "")), 0.0)) + flow_trip_minutes
					continue
		survivors.append(batch)
	sim["passengerBatches"] = survivors
	sim["flowRemainders"] = remainders
	sim["capacityLoads"] = capacity_loads
	sim["attempted"] = int(sim.get("attempted", 0)) + attempted
	sim["unreachable"] = int(sim.get("unreachable", 0)) + unreachable
	sim["departed"] = int(sim.get("departed", 0)) + departed
	sim["boarded"] = int(sim.get("boarded", 0)) + boarded
	sim["served"] = int(sim.get("served", 0)) + boarded
	sim["completed"] = int(sim.get("completed", 0)) + completed
	sim["tripMinutesTotal"] = float(sim.get("tripMinutesTotal", 0.0)) + trip_minutes_added
	sim["abandoned"] = int(sim.get("abandoned", 0)) + abandoned_now
	sim["waiting"] = _count_status(survivors, "waiting")
	sim["inTransit"] = _count_status(survivors, "walking") + _count_status(survivors, "transferring") + _count_status(survivors, "riding")
	sim["peakCrowding"] = peak_crowding
	sim["crowdedLinks"] = crowded_links
	sim["lastArrivalsByFlow"] = arrivals_by_flow
	sim["lastCompletedByFlow"] = completed_by_flow
	sim["lastAbandoned"] = abandoned_now
	var attempted_by_flow: Dictionary = sim.get("attemptedByFlow", {})
	var cumulative_completed_by_flow: Dictionary = sim.get("completedByFlow", {})
	var cumulative_trip_minutes_by_flow: Dictionary = sim.get("tripMinutesByFlow", {})
	for flow_id in arrivals_by_flow:
		attempted_by_flow[flow_id] = int(attempted_by_flow.get(flow_id, 0)) + int(arrivals_by_flow[flow_id])
	for flow_id in completed_by_flow:
		cumulative_completed_by_flow[flow_id] = int(cumulative_completed_by_flow.get(flow_id, 0)) + int(completed_by_flow[flow_id])
	for flow_id in trip_minutes_by_flow:
		cumulative_trip_minutes_by_flow[flow_id] = float(cumulative_trip_minutes_by_flow.get(flow_id, 0.0)) + float(trip_minutes_by_flow[flow_id])
	sim["attemptedByFlow"] = attempted_by_flow
	sim["completedByFlow"] = cumulative_completed_by_flow
	sim["tripMinutesByFlow"] = cumulative_trip_minutes_by_flow
	var flow_samples: Dictionary = sim.get("flowSamples", {})
	var sample_ids: Dictionary = {}
	for flow_id in arrivals_by_flow: sample_ids[flow_id] = true
	for flow_id in completed_by_flow: sample_ids[flow_id] = true
	for flow_id in trip_minutes_by_flow: sample_ids[flow_id] = true
	for flow_id in sample_ids:
		var samples: Array = flow_samples.get(str(flow_id), [])
		samples.append({"minute": absolute_minute, "attempted": int(arrivals_by_flow.get(flow_id, 0)), "completed": int(completed_by_flow.get(flow_id, 0)), "tripMinutes": float(trip_minutes_by_flow.get(flow_id, 0.0))})
		flow_samples[str(flow_id)] = samples
	for flow_id in flow_samples:
		var samples: Array = flow_samples[flow_id]
		while not samples.is_empty() and int(samples[0].get("minute", absolute_minute)) <= absolute_minute - 60: samples.pop_front()
	sim["flowSamples"] = flow_samples
	var waiting_by_route: Dictionary = {}
	for batch in survivors:
		if str(batch.get("status", "")) != "waiting": continue
		var flow := _find_flow(flows, str(batch.get("flowId", "")))
		var steps: Array = flow.get("journey", {}).get("steps", [])
		var index := int(batch.get("stepIndex", 0))
		if index < steps.size() and str(steps[index].get("type", "")) == "wait": index += 1
		if index >= steps.size() or str(steps[index].get("type", "")) != "rail": continue
		var route_id := str(steps[index].get("routeId", ""))
		waiting_by_route[route_id] = int(waiting_by_route.get(route_id, 0)) + int(batch.get("count", 0))
	sim["waitingByRoute"] = waiting_by_route
	var crowding_samples: Array = sim.get("crowdingSamples", [])
	crowding_samples.append({"value": peak_crowding, "routeId": peak_crowded_route})
	while crowding_samples.size() > 60: crowding_samples.pop_front()
	sim["crowdingSamples"] = crowding_samples
	var rolling_peak := 0.0
	var rolling_peak_route := ""
	for sample in crowding_samples:
		var value := float(sample.get("value", 0.0)) if sample is Dictionary else float(sample)
		if value > rolling_peak:
			rolling_peak = value
			rolling_peak_route = str(sample.get("routeId", "")) if sample is Dictionary else ""
	sim["peakCrowding"] = rolling_peak
	sim["peakCrowdedRoute"] = rolling_peak_route
	state["simulation"] = sim
	return {"arrivalsByFlow": arrivals_by_flow, "completedByFlow": completed_by_flow, "tripMinutesByFlow": trip_minutes_by_flow, "attempted": attempted, "unreachable": unreachable, "boarded": boarded, "departed": departed, "completed": completed, "abandoned": abandoned_now, "tripMinutesAdded": trip_minutes_added, "peakCrowding": peak_crowding, "waitingByRoute": waiting_by_route}

static func _enter_current_step(batch: Dictionary, steps: Array, absolute_minute: int) -> void:
	while int(batch.get("stepIndex", 0)) < steps.size():
		var index := int(batch.get("stepIndex", 0))
		var step: Dictionary = steps[index]
		var type := str(step.get("type", ""))
		if type == "wait":
			batch.status = "waiting"
			batch.waitedMinutes = int(batch.get("waitedMinutes", 0))
			batch.remainingMinutes = 0.0
			return
		if type == "rail":
			batch.status = "waiting"
			batch.waitedMinutes = int(batch.get("waitedMinutes", 0))
			batch.remainingMinutes = 0.0
			return
		var duration := float(step.get("minutes", 0.0))
		if duration <= 0.0:
			batch.stepIndex = index + 1
			continue
		batch.status = "transferring" if type == "transfer" else "walking"
		batch.remainingMinutes = duration
		return
	batch.status = "completed"
	batch.completedAt = absolute_minute

static func _replan_batch(state: Dictionary, batch: Dictionary, flow: Dictionary, absolute_seconds: int, network: Dictionary, ref_lat: float) -> bool:
	var origin: Dictionary = {}
	if bool(batch.get("everBoarded", false)):
		var station := WorldData.find_station(state, str(batch.get("lastValidStationId", "")))
		if not station.is_empty(): origin = {"id": "current:%s" % str(batch.get("id", "")), "latlng": station.get("latlng", [])}
	if origin.is_empty(): origin = {"id": "origin:%s" % str(batch.get("id", "")), "latlng": batch.get("originLatLng", [])}
	var destination := {"id": "destination:%s" % str(batch.get("id", "")), "latlng": batch.get("destinationLatLng", [])}
	var journey := JourneyModelScript.find_journey(origin, destination, state, network, ref_lat)
	batch.plannedRevision = int(state.get("revision", 0))
	batch.replanAfterArrival = false
	if not bool(journey.get("valid", false)):
		_mark_interrupted(state.get("simulation", {}), batch)
		batch.status = "interrupted"
		batch.remainingMinutes = 0.0
		batch.nextEventSeconds = -1.0
		return false
	batch.steps = journey.get("steps", []).duplicate(true)
	batch["journeyFingerprint"] = _journey_fingerprint(batch.steps)
	batch.stepIndex = 0
	batch.remainingMinutes = 0.0
	batch.nextEventSeconds = float(absolute_seconds)
	batch.bornAtSeconds = float(batch.get("bornAtSeconds", int(batch.get("bornAt", 420)) * 60))
	batch.waitedMinutes = 0
	batch.status = ""
	_activate_current_step(batch, batch.steps, float(absolute_seconds))
	return true

static func _mark_interrupted(sim: Dictionary, batch: Dictionary) -> void:
	if bool(batch.get("interruptedRecorded", false)): return
	sim["interrupted"] = int(sim.get("interrupted", 0)) + int(batch.get("count", 0))
	batch.interruptedRecorded = true

static func _find_flow(flows: Array[Dictionary], flow_id: String) -> Dictionary:
	for flow in flows:
		if str(flow.get("id", "")) == flow_id: return flow
	return {}

static func _count_status(batches: Array, status: String) -> int:
	var total := 0
	for batch in batches:
		if str(batch.get("status", "")) == status: total += int(batch.get("count", 0))
	return total

static func _get_route_paths(state: Dictionary) -> Dictionary:
	var identity_parts: PackedStringArray = [str(state.get("cityId", "")), str(state.get("revision", 0))]
	for route in state.get("routes", []): identity_parts.append("r:%s:%s" % [str(route.get("id", "")), str(route.get("open", false))])
	for edge in TrackNetwork.all_physical_edges(state): identity_parts.append("e:%s" % str(edge.get("id", "")))
	var cache_key := "|".join(identity_parts)
	if cache_key == _route_cache_key: return _route_cache
	_route_cache_key = cache_key
	_route_cache.clear()
	var ref_lat := float(WorldData.city(str(state.get("cityId", "shanghai"))).get("center", [31.23, 121.47])[0])
	for route in state.get("routes", []):
		if not bool(route.get("open", false)): continue
		_route_cache[str(route.get("id", ""))] = RoutePathScript.for_route(route, state, ref_lat)
	return _route_cache

static func _update_train_trips(sim: Dictionary, state: Dictionary, route_paths: Dictionary, absolute_minute: int, capacity_loads: Dictionary) -> void:
	var active: Array = sim.get("trainTrips", [])
	var survivors: Array = []
	for raw_trip in active:
		if not raw_trip is Dictionary: continue
		var trip: Dictionary = raw_trip
		var route_id := str(trip.get("routeId", ""))
		var route := WorldData.find_route(state, route_id)
		var path: Dictionary = route_paths.get(route_id, {})
		var direction := _find_direction(path, str(trip.get("directionId", "")))
		if route.is_empty() or not bool(route.get("open", false)) or direction.is_empty():
			_clear_trip_loads(capacity_loads, str(trip.get("id", "")))
			continue
		trip["elapsedMinutes"] = float(trip.get("elapsedMinutes", 0.0)) + 1.0
		if float(trip.elapsedMinutes) >= float(direction.get("travelMinutes", 0.0)):
			_clear_trip_loads(capacity_loads, str(trip.get("id", "")))
			continue
		survivors.append(trip)
	if not bool(sim.get("trainTripsInitialized", false)):
		for route in state.get("routes", []):
			if not bool(route.get("open", false)): continue
			var route_id := str(route.get("id", ""))
			var path: Dictionary = route_paths.get(route_id, {})
			if not bool(path.get("valid", false)): continue
			var headway := maxi(1, int(round(float(route.get("headway", 3.0)))))
			for direction in path.get("directions", []):
				var duration := float(direction.get("travelMinutes", 0.0))
				if duration <= 0.0: continue
				var direction_id := str(direction.get("id", "forward"))
				var oldest_departure := maxi(int(route.get("serviceStartMinute", 0)), absolute_minute - ceili(duration))
				for departure in range(oldest_departure, absolute_minute):
					if posmod(departure, headway) != 0: continue
					var age := absolute_minute - departure
					if age >= duration: continue
					var trip_id := "%s|%s|%d" % [route_id, direction_id, departure]
					if not _has_trip_in_list(survivors, trip_id): survivors.append(_make_train_trip(route_id, direction, departure, float(age)))
		sim["trainTripsInitialized"] = true
	for route in state.get("routes", []):
		if not bool(route.get("open", false)): continue
		var route_id := str(route.get("id", ""))
		var path: Dictionary = route_paths.get(route_id, {})
		if not bool(path.get("valid", false)): continue
		var headway := maxi(1, int(round(float(route.get("headway", 3.0)))))
		if posmod(absolute_minute, headway) != 0: continue
		for direction in path.get("directions", []):
			var duration := float(direction.get("travelMinutes", 0.0))
			if duration <= 0.0: continue
			var direction_id := str(direction.get("id", "forward"))
			var trip_id := "%s|%s|%d" % [route_id, direction_id, absolute_minute]
			var already_exists := false
			for trip in survivors:
				if str(trip.get("id", "")) == trip_id: already_exists = true; break
			if not already_exists: survivors.append(_make_train_trip(route_id, direction, absolute_minute, 0.0))
	sim["trainTrips"] = survivors

static func _make_train_trip(route_id: String, direction: Dictionary, departure_minute: int, elapsed_minutes: float) -> Dictionary:
	var direction_id := str(direction.get("id", "forward"))
	var trip_id := "%s|%s|%d" % [route_id, direction_id, departure_minute]
	var timetable: Array[Dictionary] = []
	var segments: Array = direction.get("segments", [])
	if not segments.is_empty():
		var first: Dictionary = segments[0]
		timetable.append({"stationId": str(first.get("fromStationId", "")), "arrivalOffsetMinutes": 0.0, "departureOffsetMinutes": 0.0})
	for segment in segments:
		var offset := float(segment.get("stationOffsetMinutes", 0.0))
		var moving := float(segment.get("movingMinutes", segment.get("travelMinutes", 0.0)))
		var arrival_offset := offset + moving
		var departure_offset := offset + float(segment.get("travelMinutes", moving))
		if not timetable.is_empty():
			var previous_stop: Dictionary = timetable.back()
			previous_stop["departureOffsetMinutes"] = maxf(float(previous_stop.get("arrivalOffsetMinutes", 0.0)), offset)
		timetable.append({"stationId": str(segment.get("toStationId", "")), "arrivalOffsetMinutes": arrival_offset, "departureOffsetMinutes": departure_offset})
	if not timetable.is_empty(): timetable.back()["departureOffsetMinutes"] = timetable.back().get("arrivalOffsetMinutes", 0.0)
	for stop in timetable:
		stop["arrivalMinute"] = float(departure_minute) + float(stop.get("arrivalOffsetMinutes", 0.0))
		stop["departureMinute"] = float(departure_minute) + float(stop.get("departureOffsetMinutes", 0.0))
	return {"id": trip_id, "routeId": route_id, "directionId": direction_id, "departureMinute": departure_minute, "elapsedMinutes": elapsed_minutes, "stationTimetable": timetable, "loadByEdge": {}}

static func _make_train_trip_seconds(route_id: String, direction: Dictionary, departure_seconds: int) -> Dictionary:
	var direction_id := str(direction.get("id", "forward"))
	var trip_id := "%s|%s|%d" % [route_id, direction_id, departure_seconds]
	var stops: Array[Dictionary] = []
	var segments: Array = direction.get("segments", [])
	if not segments.is_empty():
		var first: Dictionary = segments[0]
		stops.append({"stationId": str(first.get("fromStationId", "")), "stationIndex": 0, "arrivalOffsetMinutes": 0.0, "departureOffsetMinutes": 0.0, "arrivalSeconds": departure_seconds, "departureSeconds": departure_seconds})
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]
		var previous: Dictionary = stops.back()
		var depart_offset := float(previous.get("departureOffsetMinutes", 0.0))
		var arrival_offset := depart_offset + float(segment.get("movingMinutes", segment.get("travelMinutes", 0.0)))
		var dwell := float(segment.get("dwellMinutes", 0.0))
		stops.append({"stationId": str(segment.get("toStationId", "")), "stationIndex": index + 1, "arrivalOffsetMinutes": arrival_offset, "departureOffsetMinutes": arrival_offset + dwell, "arrivalSeconds": departure_seconds + roundi(arrival_offset * 60.0), "departureSeconds": departure_seconds + roundi((arrival_offset + dwell) * 60.0)})
	return {"id": trip_id, "routeId": route_id, "directionId": direction_id, "departureSeconds": departure_seconds, "elapsedSeconds": 0.0, "elapsedMinutes": 0.0, "directionSnapshot": direction.duplicate(true), "stationTimetable": stops, "currentStopIndex": 0, "nextStopIndex": -1, "phase": "dwell", "nextEventSeconds": float(departure_seconds), "capacity": 1800, "loadByEdge": {}}

static func _find_boarding_train(sim: Dictionary, route_id: String, direction_id: String, station_id: String) -> Dictionary:
	# Boarding must follow the active train's own stop timetable. Reconstructing a
	# departure key from a rounded station offset could leave riders waiting even
	# while a train was visibly at the platform.
	for raw_trip in sim.get("trainTrips", []):
		if not raw_trip is Dictionary: continue
		var trip: Dictionary = raw_trip
		if str(trip.get("routeId", "")) != route_id or str(trip.get("directionId", "")) != direction_id: continue
		var elapsed := float(trip.get("elapsedMinutes", 0.0))
		for raw_stop in trip.get("stationTimetable", []):
			if not raw_stop is Dictionary: continue
			var stop: Dictionary = raw_stop
			if str(stop.get("stationId", "")) != station_id: continue
			var arrival_offset := float(stop.get("arrivalOffsetMinutes", float(stop.get("arrivalMinute", trip.get("departureMinute", 0.0))) - float(trip.get("departureMinute", 0.0))))
			var departure_offset := float(stop.get("departureOffsetMinutes", float(stop.get("departureMinute", trip.get("departureMinute", 0.0))) - float(trip.get("departureMinute", 0.0))))
			var first_service_tick := ceili(arrival_offset - 0.0001)
			var last_service_tick := ceili(departure_offset - 0.0001)
			if elapsed + 0.0001 >= float(first_service_tick) and elapsed <= float(last_service_tick) + 0.0001:
				return trip
	return {}

static func _change_trip_load(sim: Dictionary, trip_id: String, edge_key: String, delta: int) -> void:
	for raw_trip in sim.get("trainTrips", []):
		if str(raw_trip.get("id", "")) != trip_id: continue
		var loads: Dictionary = raw_trip.get("loadByEdge", {})
		loads[edge_key] = maxi(0, int(loads.get(edge_key, 0)) + delta)
		raw_trip["loadByEdge"] = loads
		return

static func _release_batch_capacity(sim: Dictionary, capacity_loads: Dictionary, batch: Dictionary) -> void:
	var trip_id := str(batch.get("trainTripId", ""))
	var count := int(batch.get("count", 0))
	for raw_key in batch.get("capacityLoadKeys", []):
		var key := str(raw_key)
		var remaining := maxi(0, int(capacity_loads.get(key, 0)) - count)
		if remaining == 0: capacity_loads.erase(key)
		else: capacity_loads[key] = remaining
		if not trip_id.is_empty(): _change_trip_load(sim, trip_id, key, -count)

static func _has_trip_in_list(trips: Array, trip_id: String) -> bool:
	for trip in trips:
		if str(trip.get("id", "")) == trip_id: return true
	return false

static func _clear_trip_loads(capacity_loads: Dictionary, trip_id: String) -> void:
	var prefix := trip_id + "|"
	for key in capacity_loads.keys():
		if str(key).begins_with(prefix): capacity_loads.erase(key)

static func _find_direction(path: Dictionary, direction_id: String) -> Dictionary:
	for direction in path.get("directions", []):
		if str(direction.get("id", "")) == direction_id: return direction
	return {}
