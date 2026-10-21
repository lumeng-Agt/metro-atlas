extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize():call_deferred("run")
func check(ok:bool,text:String):
	checks+=1
	if not ok:failures.append(text)
func run():
	if not SaveManager.using_explicit_data_dir():quit(2);return
	WorldData.load_assets()
	var app=preload("res://scripts/main.gd").new();root.add_child(app);await process_frame
	app._new_game("shanghai",false);app._begin_chapter()
	var complete:Dictionary=app._assist_candidate()
	check(complete.has("state"),"首章辅助夹具可创建")
	if not complete.has("state"):quit(1);return
	for key in ["stations","stationComplexes","transferConnections","trackNodes","trackEdges"]:app.world[key]=complete.state[key]
	var a:Dictionary={};var b:Dictionary={}
	for st in app.world.stations:
		if st.name=="漕宝路":a=st
		if st.name=="新龙华":b=st
	var a_nodes=[TrackNetwork.station_node_id(a,"start"),TrackNetwork.station_node_id(a,"end")]
	var b_nodes=[TrackNetwork.station_node_id(b,"start"),TrackNetwork.station_node_id(b,"end")]
	app.world.trackEdges=app.world.trackEdges.filter(func(e):return not ((a_nodes.has(e.aNodeId) and b_nodes.has(e.bNodeId)) or (a_nodes.has(e.bNodeId) and b_nodes.has(e.aNodeId))))
	var start:Dictionary=app._ref(a.latlng,"endpoint",a.id,"start")
	var finish:Dictionary=app._ref(b.latlng,"endpoint",b.id,"end")
	var initial:Dictionary=app.rules.track_preview(start,finish)
	check(absf(float(initial.lengthM)-1205)<2,"截图的漕宝路A—新龙华B约1205米")
	# A separate same-level track crosses the schematic segment. No shared node.
	var points:Array=initial.points;var lat:=float(WorldData.city("shanghai").center[0])
	var p:=Geo.local_m(points[15],lat);var q:=Geo.local_m(points[16],lat)
	var centre:=p.lerp(q,0.5);var normal:=(q-p).orthogonal().normalized()*200
	var c:=TrackNetwork.create_node(app.world,Geo.from_local(centre-normal,lat),-15)
	var d:=TrackNetwork.create_node(app.world,Geo.from_local(centre+normal,lat),-15)
	app.world.trackEdges.append({"id":"unconnected_crossing","aNodeId":c.id,"bNodeId":d.id,"geometry":"straight"})
	check(not str(app.rules.track_preview(start,finish).issue).is_empty(),"旧规则及高级编辑仍能发现同层交叉")
	var preview:Dictionary=app.rules.track_preview(start,finish,[],true)
	check(str(preview.issue).is_empty(),"历史未核验纵断面不以5米游戏预设阻止复现")
	check(not str(preview.get("advisory","")).is_empty(),"明确展示未核验和不自动接轨说明")
	check(preview.edge.get("verticalProfile","")=="unverified_historical","正式候选保存示意纵断面状态")
	check(preview.points==initial.points,"降低资料约束不改变线位")
	var opposite:Dictionary=app.rules.track_preview(finish,start,[],true)
	check(str(opposite.issue).is_empty(),"反向建设适用相同历史规则")
	var zero:Dictionary=app.rules.track_preview(start,start,[],true)
	check(not str(zero.issue).is_empty(),"历史模式不放行零长度")
	var free:=finish.duplicate(true);free.erase("stationId");free.erase("nodeId")
	check(not app.rules._historical_schematic_pair(start,free),"自由节点不冒用历史豁免")
	var nonadjacent:=app._ref(app.world.stations[0].latlng,"endpoint",app.world.stations[0].id,"start")
	check(not app.rules._historical_schematic_pair(nonadjacent,finish),"跨过历史站序的连接不冒用豁免")
	app._tool("track");app.map_view.track_start_ref=start;app.map_view.track_end_ref=finish;app._track_preview(finish)
	check(str(app.pending_track.issue).is_empty(),"真实界面预览使用历史规则")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,980);app.show_left=false;app.show_right=true;app._right();app._layout()
		app.map_view.center_on([31.157,121.424],15)
		var timeout:=Time.get_ticks_msec()+25000
		while (app.map_view._base_map_thread_busy or not app.map_view._base_map_pending_request.is_empty()) and Time.get_ticks_msec()<timeout:await process_frame
		for i in range(8):await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/ui-0.20.1-schematic.png")==OK,"原生界面截图写出")
	var before:int=app.world.trackEdges.size();var nodes:int=app.world.trackNodes.size()
	app._commit_track()
	check(app.world.trackEdges.size()==before+1,"真实确认可提交截图对应区间")
	check(app.world.trackNodes.size()==nodes,"交叉不会生成道岔或共享节点")
	var edge:Dictionary=app.world.trackEdges[-1]
	check(app.rules._physical_edge_geometry_issue(edge,app.world).is_empty(),"后续几何检查不重新套用已排除的纵断面门槛")
	check(SaveManager.validate(app.world).is_empty(),"正式规划可保存")
	app.history.undo();check(app.world.trackEdges.size()==before,"撤销恢复原规划")
	app.history.redo();check(app.world.trackEdges.size()==before+1,"重做恢复历史区间")
	var saved:=SaveManager.save_world(app.world)
	check(bool(saved.ok),"修复后存档写入成功")
	var loaded:=SaveManager.load_file(SaveManager.save_path(str(app.world.gameId)))
	check(bool(loaded.ok) and loaded.world.trackEdges[-1].get("verticalProfile","")=="unverified_historical","重载保留相同约束和几何")
	app.world.mode="workshop"
	check(not str(app.rules.track_preview(start,finish,[],true).issue).is_empty(),"旧作品与自由创作仍执行原始工程规则")
	app.queue_free();await process_frame
	print("Historical schematic regression: ",checks," checks, ",failures.size()," failures")
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
