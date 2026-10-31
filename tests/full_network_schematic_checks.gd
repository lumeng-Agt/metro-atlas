extends SceneTree
const Layout=preload("res://scripts/schematic_layout.gd")
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var fixture_root:="D:/gam1/testdata/gameplay-verify/run-20261029-202922"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--fixture-root="):fixture_root=str(arg).trim_prefix("--fixture-root=")
	for city_id in ["shenzhen","shanghai","beijing","guangzhou","chengdu"]:
		var folder:=fixture_root.path_join(city_id+"-fresh/games")
		var games:=DirAccess.get_directories_at(folder)
		if games.size()!=1:failures.append(city_id+": fixture missing or ambiguous");continue
		var source:=folder.path_join(games[0]).path_join("current.json")
		var loaded:=SaveManager.load_file(source)
		if not loaded.get("ok",false):failures.append(city_id+": source invalid");continue
		var world:Dictionary=loaded.world
		var original:=JSON.stringify(world)
		var start:=Time.get_ticks_usec()
		var result:=Layout.fit(world,Vector2(1400,800))
		var elapsed:=(Time.get_ticks_usec()-start)/1000.0
		if not result.get("ok",false):failures.append(city_id+": "+str(result.get("reason","")));continue
		if JSON.stringify(world)!=original:failures.append(city_id+": layout changed formal world")
		var served:={}
		for stroke in result.strokes:
			for id in stroke.ids:served[str(id)]=true
		if served.size()!=result.positions.size():failures.append(city_id+": missing served station body")
		var body_ids:={}
		for station in world.stations:body_ids[str(station.get("stationInstanceId",station.id))]=str(station.id)
		var expected_transfers:=0
		for connection in world.transferConnections:
			var pair:Array=connection.get("stationInstanceIds",[])
			if connection.get("status","")!="active" or pair.size()!=2:continue
			if served.has(str(body_ids.get(str(pair[0]),pair[0]))) and served.has(str(body_ids.get(str(pair[1]),pair[1]))):expected_transfers+=1
		if result.transfers.size()!=expected_transfers:failures.append(city_id+": explicit interchange omitted")
		var boxes:Array[Rect2]=[]
		for id in result.labels:
			var box:=Rect2(result.labels[id],Vector2(str(result.names[id]).length()*17+8,27))
			if not Rect2(Vector2.ZERO,result.bounds).encloses(box):failures.append(city_id+": label outside canvas")
			for other in boxes:
				if box.intersects(other):failures.append(city_id+": overlapping labels")
			boxes.append(box)
		print("SCHEMATIC ",city_id," bodies=",served.size()," labels=",result.labels.size()," transfers=",result.transfers.size()," canvas=",result.bounds," ms=",elapsed)
	for failure in failures:push_error(failure)
	print("PASS: five full-network schematics" if failures.is_empty() else "FAIL: full-network schematics")
	quit(0 if failures.is_empty() else 1)
