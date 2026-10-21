extends SceneTree

const Story = preload("res://scripts/story_session.gd")
const Catalog = preload("res://scripts/campaign_system.gd")
const App = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not SaveManager.using_explicit_data_dir():
		push_error("isolated --data-dir required")
		quit(2)
		return
	WorldData.load_assets()
	var app := App.new()
	root.add_child(app)
	await process_frame
	var city_ids := ["shenzhen", "shanghai", "beijing", "guangzhou", "chengdu"]
	var selected_city := OS.get_environment("METRO_REPLAY_CITY")
	if not selected_city.is_empty(): city_ids = [selected_city]
	var stop_after_index := int(OS.get_environment("METRO_REPLAY_STOP_AFTER_INDEX")) if not OS.get_environment("METRO_REPLAY_STOP_AFTER_INDEX").is_empty() else -1
	var replay_from_saved := OS.get_environment("METRO_REPLAY_FROM_SAVED") == "1"
	var failures := 0
	for city_id in city_ids:
		var failures_before_city := failures
		var chapters: Array = Catalog.city_config(city_id).get("chapters", [])
		if replay_from_saved and city_id == "guangzhou":
			var saved_history: Dictionary = SaveManager.load_last_game()
			if not bool(saved_history.get("ok", false)):
				print("REPLAY_LOAD_SAVED_HISTORY_FAIL ", saved_history.get("error", "")); quit(3); return
			app._enter(saved_history.world)
			chapters = []
			print("REPLAY_LOADED_HISTORY ", saved_history.world.get("gameId", ""), " phase=", saved_history.world.get("storyState", {}).get("phase", ""))
		else:
			app._new_game(city_id, false)
			app.world.storyState.learnedTools = true
		print("REPLAY_START ", city_id, " chapters=", chapters.size())
		for index in range(chapters.size()):
			var chapter: Dictionary = chapters[index]
			print("REPLAY_CHAPTER_START ", city_id, " ", index + 1, "/", chapters.size(), " ", chapter.get("date", ""), " ", chapter.get("id", ""))
			app.world.storyState.chapterIndex = index
			app.world.storyState.chapterId = str(chapter.get("id", ""))
			app.world.storyState.stage = "build"
			app.world.storyState.phase = "history"
			app.world.storyPlan = {"planIndex": 0, "pathChoices": {}, "reorganizationAccepted": false}
			var versions: Array = chapter.get("story", {}).get("planVersions", [])
			if not versions.is_empty(): app.world.storyPlan.planIndex = versions.size() - 1
			if bool(chapter.get("requiresLineReorganization", false)): app.world.storyPlan.reorganizationAccepted = true
			var groups: Array = Story.groups(app.world, true)
			if groups.is_empty():
				var event_result := Story.commit_chapter(app.world, int(app.world.revision))
				if not bool(event_result.get("ok", false)):
					print("REPLAY_FAIL ", city_id, " ", index, " ", chapter.get("id"), " event: ", event_result.get("error", "")); failures += 1; break
				Story.next_chapter(app.world)
				continue
			app.map_view.set_context(WorldData.city(city_id), app.world)
			var preview: Dictionary = app._assist_candidate()
			print("REPLAY_PREVIEW_DONE ", city_id, " ", index + 1, "/", chapters.size())
			if not preview.has("state"):
				print("REPLAY_FAIL ", city_id, " ", index, " ", chapter.get("id"), " preview: ", preview.get("issue", "no state"))
				failures += 1; break
			for key in ["stations", "stationComplexes", "transferConnections", "trackNodes", "trackEdges"]: app.world[key] = preview.state.get(key, []).duplicate(true)
			app.world.storyPlan["pathChoices"] = preview.state.get("storyPlan", {}).get("pathChoices", {}).duplicate(true)
			var transition_failed:=false
			# Most construction chapters have no service-range change. Avoid a full
			# graph evaluation before task confirmation in those chapters.
			if not chapter.get("serviceTransitions",[]).is_empty():
				var transition_evaluation:Dictionary=Story.evaluate(app.world)
				for proposal in transition_evaluation.get("serviceTransitions",[]):
					if Story._has_service_range(app.world,str(proposal.get("id",""))):continue
					var transition_result:Dictionary=app._commit_service_transition(proposal,int(app.world.revision),transition_evaluation)
					if not bool(transition_result.get("ok",false)):
						print("REPLAY_FAIL ",city_id," ",index," ",chapter.get("id")," service transition: ",transition_result.get("error",""));failures+=1;transition_failed=true;break
			if transition_failed:break
			var task_failed := false
			for group_index in range(groups.size()):
				var group: Dictionary = groups[group_index]
				var task_id := Story.task_id(chapter, group, group_index)
				print("REPLAY_TASK_CONFIRM_START ", city_id, " ", index + 1, "/", chapters.size(), " ", group_index + 1, "/", groups.size(), " ", task_id)
				var task_evaluation:Dictionary=Story.evaluate(app.world,task_id)
				var confirmed: Dictionary = Story.confirm_task(app.world, task_id, int(app.world.revision),task_evaluation)
				if not bool(confirmed.get("ok", false)):
					print("REPLAY_FAIL ", city_id, " ", index, " ", chapter.get("id"), " task=", task_id, " confirm: ", confirmed.get("error", ""), " issues=", JSON.stringify(Story.evaluate(app.world, task_id).get("issues", [])))
					failures += 1; task_failed = true; break
			if task_failed: break
			var evaluated: Dictionary = Story.evaluate(app.world)
			for transfer in evaluated.get("requiredTransfers", []):
				if app._transfer_connected(transfer): continue
				var connection: Dictionary = {"id": str(transfer.get("id", "")), "name": str(transfer.get("name", "换乘")), "complexId": str(transfer.get("complexId", "")), "stationInstanceIds": transfer.get("stationInstanceIds", []).duplicate(), "lineIds": transfer.get("lineIds", []).duplicate(), "status": "active", "precision": str(transfer.get("precision", "schematic")), "source": str(transfer.get("source", "")), "effectiveDate": str(chapter.get("date", ""))}
				var transfer_result: Dictionary = app._commit_transfer_connection(transfer, connection, int(app.world.revision), evaluated)
				if not bool(transfer_result.get("ok", false)):
					print("REPLAY_FAIL ", city_id, " ", index, " ", chapter.get("id"), " transfer: ", transfer_result.get("error", ""), " definition=", JSON.stringify(transfer), " status=", app._transfer_status_lines(transfer))
					failures += 1; task_failed = true; break
			if task_failed: break
			for proposal in evaluated.get("serviceTransitions", []):
				if Story._has_service_range(app.world, str(proposal.id)): continue
				var service_result: Dictionary = app._commit_service_transition(proposal, int(app.world.revision))
				if not bool(service_result.get("ok", false)):
					print("REPLAY_FAIL ", city_id, " ", index, " ", chapter.get("id"), " service transition: ", service_result.get("error", "")); failures += 1; task_failed = true; break
			if task_failed: break
			evaluated = Story.evaluate(app.world)
			if not bool(evaluated.get("complete", false)):
				print("REPLAY_FAIL ", city_id, " ", index, " ", chapter.get("id"), " evaluate: ", JSON.stringify(evaluated.get("issues", [])))
				for transfer in evaluated.get("requiredTransfers", []):
					print("  TRANSFER_DEF ", transfer)
					for instance_index in range(transfer.get("stationInstanceIds", []).size()):
						var transfer_instance := str(transfer.stationInstanceIds[instance_index]); var transfer_line := str(transfer.lineIds[instance_index])
						for station in app.world.stations:
							if str(station.get("stationInstanceId", station.get("id", ""))) == transfer_instance: print("  TRANSFER_STATION ", station)
						for route in app.world.routes:
							if str(route.get("historicalLineId", "")) == transfer_line: print("  TRANSFER_ROUTE ", transfer_line, " stations=", route.get("stationOrder", []))
				failures += 1; break
			var committed := Story.commit_chapter(app.world, int(app.world.revision),evaluated)
			if not bool(committed.get("ok", false)):
				print("REPLAY_FAIL ", city_id, " ", index, " ", chapter.get("id"), " commit: ", committed.get("error", "")); failures += 1; break
			Story.next_chapter(app.world)
			if stop_after_index >= 0 and index >= stop_after_index:break
			if index % 5 == 0: print("REPLAY_PROGRESS ", city_id, " ", index + 1, "/", chapters.size())
		# Future-plan replay applies to every city so a newly added project
		# chapter cannot ship unverified just because it is not Guangzhou.
		if OS.get_environment("METRO_REPLAY_FUTURE") == "1" and failures == failures_before_city:
			var history_save: Dictionary = SaveManager.save_world(app.world)
			if bool(history_save.get("ok", false)): print("REPLAY_HISTORY_CHECKPOINT ", history_save.get("path", ""))
			else: print("REPLAY_HISTORY_CHECKPOINT_FAIL ", history_save.get("error", ""))
			var future_plans: Array = Catalog.playable_future_plans(city_id)
			print("REPLAY_FUTURE_START ", city_id, " plans=", future_plans.size())
			for plan_index in range(future_plans.size()):
				var plan: Dictionary = future_plans[plan_index]
				app.world.storyState.phase = "future"
				app.world.storyState.chapterIndex = plan_index
				app.world.storyState.chapterId = str(plan.get("id", ""))
				app.world.storyState.stage = "build"
				app.map_view.set_context(WorldData.city(city_id), app.world)
				var future_preview: Dictionary = app._assist_candidate()
				if not future_preview.has("state"):
					print("REPLAY_FUTURE_FAIL ", plan.get("id"), " preview: ", future_preview.get("issue", "no state")); failures += 1; break
				for key in ["stations", "stationComplexes", "transferConnections", "trackNodes", "trackEdges"]: app.world[key] = future_preview.state.get(key, []).duplicate(true)
				app.world.storyPlan["pathChoices"] = future_preview.state.get("storyPlan", {}).get("pathChoices", {}).duplicate(true)
				var future_groups: Array = Story.groups(app.world, true)
				var future_task_failed := false
				for group_index in range(future_groups.size()):
					var group: Dictionary = future_groups[group_index]
					var id := Story.task_id(plan, group, group_index)
					var task_eval: Dictionary = Story.evaluate(app.world, id)
					var task_result: Dictionary = Story.confirm_task(app.world, id, int(app.world.revision), task_eval)
					if not bool(task_result.get("ok", false)):
						print("REPLAY_FUTURE_FAIL ", plan.get("id"), " task=", id, " confirm: ", task_result.get("error", ""), " issues=", JSON.stringify(Story.evaluate(app.world, id).get("issues", []))); failures += 1; future_task_failed = true; break
				if future_task_failed: break
				var future_eval: Dictionary = Story.evaluate(app.world)
				for transfer in future_eval.get("requiredTransfers", []):
					if app._transfer_connected(transfer): continue
					var connection: Dictionary = {"id": str(transfer.get("id", "")), "name": str(transfer.get("name", "换乘")), "complexId": str(transfer.get("complexId", "")), "stationInstanceIds": transfer.get("stationInstanceIds", []).duplicate(), "lineIds": transfer.get("lineIds", []).duplicate(), "status": "active", "precision": str(transfer.get("precision", "schematic")), "source": str(transfer.get("source", "")), "effectiveDate": str(plan.get("date", ""))}
					var transfer_result: Dictionary = app._commit_transfer_connection(transfer, connection, int(app.world.revision), future_eval)
					if not bool(transfer_result.get("ok", false)):
						print("REPLAY_FUTURE_FAIL ", plan.get("id"), " transfer=", transfer.get("id"), " error=", transfer_result.get("error", ""), " status=", app._transfer_status_lines(transfer, Story.evaluate(app.world)))
						for body_index in range(transfer.get("stationInstanceIds", []).size()):
							var wanted_instance := str(transfer.stationInstanceIds[body_index]); var wanted_line := str(transfer.lineIds[body_index])
							for station in app.world.get("stations", []):
								if str(station.get("stationInstanceId", station.get("id", ""))) == wanted_instance: print("  FUTURE_TRANSFER_BODY ", wanted_instance, " line=", wanted_line, " station=", station.get("id", ""))
							for route in app.world.get("routes", []):
								if str(route.get("historicalLineId", "")) == wanted_line: print("  FUTURE_TRANSFER_ROUTE ", wanted_line, " ids=", route.get("stationOrder", []))
						failures += 1; future_task_failed = true; break
				if future_task_failed: break
				future_eval = Story.evaluate(app.world)
				if not bool(future_eval.get("complete", false)):
					print("REPLAY_FUTURE_FAIL ", plan.get("id"), " evaluation: ", JSON.stringify(future_eval.get("issues", []))); failures += 1; break
				var future_commit: Dictionary = Story.commit_chapter(app.world, int(app.world.revision), future_eval)
				if not bool(future_commit.get("ok", false)):
					print("REPLAY_FUTURE_FAIL ", plan.get("id"), " commit: ", future_commit.get("error", "")); failures += 1; break
				Story.next_chapter(app.world)
				print("REPLAY_FUTURE_OK ", city_id, " ", plan.get("id"), " stations=", app.world.stations.size(), " edges=", app.world.trackEdges.size(), " transfers=", app.world.transferConnections.size())
		if failures == failures_before_city and (stop_after_index < 0 or stop_after_index >= chapters.size() - 1):
			var saved_counts := {
				"stations": app.world.stations.size(),
				"stationComplexes": app.world.stationComplexes.size(),
				"transferConnections": app.world.transferConnections.size(),
				"trackNodes": app.world.trackNodes.size(),
				"trackEdges": app.world.trackEdges.size(),
				"routes": app.world.routes.size(),
				"serviceRanges": app.world.serviceRanges.size(),
				"completedChapterIds": app.world.storyState.completedChapterIds.size()
			}
			var save_result: Dictionary = SaveManager.save_world(app.world)
			if not bool(save_result.get("ok", false)):
				print("REPLAY_FAIL ", city_id, " save: ", save_result.get("error", "unknown"))
				failures += 1
			else:
				var reload_result: Dictionary = SaveManager.load_file(str(save_result.get("path", "")))
				if not bool(reload_result.get("ok", false)):
					print("REPLAY_FAIL ", city_id, " reload: ", reload_result.get("error", "unknown"))
					failures += 1
				else:
					var reloaded: Dictionary = reload_result.world
					var mismatch := false
					var invalid := SaveManager.validate(reloaded)
					if not invalid.is_empty():
						print("REPLAY_FAIL ", city_id, " reload validation: ", invalid)
						mismatch = true
					for key in saved_counts:
						var actual: int = reloaded.get(key, reloaded.get("storyState", {}).get(key, [])).size()
						if actual != int(saved_counts[key]):
							print("REPLAY_FAIL ", city_id, " roundtrip count ", key, " expected=", saved_counts[key], " actual=", actual)
							mismatch = true
					for key in ["stations", "stationComplexes", "transferConnections", "trackNodes", "trackEdges", "routes", "serviceRanges", "completedChapterIds"]:
						var before: Variant = app.world.storyState.get(key, []) if key == "completedChapterIds" else app.world.get(key, [])
						var after: Variant = reloaded.get("storyState", {}).get(key, []) if key == "completedChapterIds" else reloaded.get(key, [])
						# Compare the values the save format can actually represent. JSON reads
						# numeric values back as floats, so comparing the live in-memory
						# arrays directly reports false differences for otherwise identical
						# station and track objects.
						var persisted_before: Variant = JSON.parse_string(JSON.stringify(before))
						if persisted_before != after:
							print("REPLAY_FAIL ", city_id, " roundtrip contents differ: ", key)
							mismatch = true
					if mismatch: failures += 1
					else: print("REPLAY_SAVE_ROUNDTRIP_OK ", city_id, " counts=", JSON.stringify(saved_counts))
		print("REPLAY_CITY_DONE ", city_id, " stations=", app.world.stations.size(), " edges=", app.world.trackEdges.size(), " routes=", app.world.routes.size(), " phase=", app.world.storyState.phase)
	print("REPLAY_FAILURES ", failures)
	quit(0 if failures == 0 else 1)
