extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize():call_deferred("run")
func check(ok:bool,text:String):
	checks+=1
	if not ok:failures.append(text)
func run():
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets();ReferenceAlignment.load_data()
	check(ReferenceAlignment._data.get("coordinateSystem","")=="EPSG:4326","本地几何坐标系明确")
	for item in ReferenceAlignment._data.get("alignments",[]):
		check(item.points.size()>2,"区间具有连续几何")
		check(item.has("sourceWayIds") and not item.sourceWayIds.is_empty(),"每段有原始轨道引用")
		check(str(item.get("amapReview",""))=="pending" and item.sourceAccuracyM==null,"未核验不冒充高德对照或测绘精度")
		var reverse:=ReferenceAlignment.between(str(item.toId),str(item.fromId))
		check(reverse.points[0]==item.points[-1],"反向取用保留相同几何")
	var reference:={"id":"fixture","points":[[31.0,121.0],[31.002,121.0],[31.004,121.001],[31.008,121.001],[31.01,121.0]]}
	var world:=WorldData.new_world("shanghai","campaign")
	var a:={"id":"a","historicalId":"a","latlng":[31.0,121.0],"heading":0,"lengthM":100,"widthM":20,"depthM":-15}
	var b:={"id":"b","historicalId":"b","latlng":[31.01,121.0],"heading":0,"lengthM":100,"widthM":20,"depthM":-15}
	world.stations=[a,b];TrackNetwork.ensure_station_nodes(world)
	var start:={"nodeId":TrackNetwork.station_node_id(a,"end"),"stationId":"a","side":"end","latlng":WorldData.station_endpoint(a,"end"),"depthM":-15}
	var finish:={"nodeId":TrackNetwork.station_node_id(b,"start"),"stationId":"b","side":"start","latlng":WorldData.station_endpoint(b,"start"),"depthM":-15}
	var preview:=ReferenceAlignment.preview(reference,start,finish,world,31)
	check(str(preview.get("issue",""))=="","多弯连续参考可预览")
	if preview.has("edge"):
		var edge:Dictionary=preview.edge;edge.id="fixture-edge";world.trackEdges.append(edge)
		check(TrackNetwork.edge_points(edge,world,31)==preview.points,"正式与预览几何一致")
		var length:=TrackNetwork.edge_length_m(edge,world,31)
		var rules:=StoryConstruction.new();rules.world=world
		var node:=rules._split_track_edge(world,str(edge.id),0.37,31)
		check(not node.is_empty() and world.trackEdges.size()==2,"参考折线支持沿程拆分")
		var after:=0.0
		for piece in world.trackEdges:after+=TrackNetwork.edge_length_m(piece,world,31)
		check(absf(after-length)<1,"拆分不改变总长与折线走向")
	check(ReferenceAlignment.corridor_issue([[31.0,121.0],[31.01,121.0]],reference.points,31,50),"双向走廊检查拒绝切掉弯道的捷径")
	var old:=WorldData.new_world("shanghai","campaign");old.schemaVersion=19
	var content:=JSON.stringify(old);var path:=SaveManager.root_path().path_join("original19.json")
	SaveManager._write_atomic(path,content);var loaded:=SaveManager.load_file(path)
	check(bool(loaded.get("ok",false)),"19格式可经统一入口迁移")
	if bool(loaded.get("ok",false)):
		check(int(loaded.world.schemaVersion)==WorldData.SAVE_VERSION and loaded.world.gameId==old.gameId,"迁移保留游戏身份并升级至当前存档格式")
		check(loaded.world.stations==old.stations and loaded.world.history==old.history,"迁移不移站不改历史")
	check(FileAccess.file_exists(SaveManager.root_path().path_join("originals/v19_%s.json" % content.sha256_text())),"19原档按内容独立备份")
	var bad:=WorldData.new_world("shanghai","campaign");bad.schemaVersion=WorldData.SAVE_VERSION+1
	check(not SaveManager.validate(bad).is_empty(),"未知新版本拒绝")
	var app:=preload("res://scripts/main.gd").new();root.add_child(app);await process_frame
	app._new_game("shanghai",false);app._begin_chapter();app._tool("track")
	app.map_view.track_start_ref={"latlng":[31,121]};app._check()
	check(app.tool=="select" and app.map_view.track_start_ref.is_empty(),"铺轨状态检查章节会退出草稿，展示结果不被工具页覆盖")
	check(not app.evaluation.is_empty(),"真实检查结果保持在详情中")
	app._new_game("shanghai",false);app._begin_chapter()
	var completed:Dictionary=app._assist_candidate()
	if completed.has("state"):
		for key in ["stations","trackNodes","trackEdges"]:app.world[key]=completed.state[key]
		var original:Dictionary=app.world.stations[0]
		var changed:=original.duplicate(true);changed.latlng=Geo.offset(original.latlng,3,270)
		app.rules.world=app.world
		var draft:=app.rules._station_preview_analysis(changed,app.world)
		check(str(draft.issue).is_empty(),"小幅移站能同步调整参考折线接头")
		check(app.world.stations[0].latlng==original.latlng,"接头预览不修改正式站位")
	else:check(false,"移站夹具可创建")
	app.queue_free();await process_frame
	print("0.20 reference / migration checks: ",checks," failures: ",failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
