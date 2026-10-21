extends SceneTree
const Rules=preload("res://scripts/story_construction.gd")
const StorySession=preload("res://scripts/story_session.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _check(ok:bool,text:String) -> void:
	checks+=1
	if not ok:failures.append(text)
func _run() -> void:
	WorldData.load_assets()
	var world:=WorldData.new_world("shanghai","workshop")
	var a:=WorldData.create_station(world,[31.23,121.47],90)
	var b:=WorldData.create_station(world,Geo.offset(a.latlng,1000,90),90)
	var helper:=Rules.new();helper.world=world;helper.active_city_id="shanghai"
	var start:={"nodeId":TrackNetwork.station_node_id(a,"end"),"stationId":a.id,"side":"end","latlng":WorldData.station_endpoint(a,"end"),"depthM":-15}
	var finish:={"nodeId":TrackNetwork.station_node_id(b,"start"),"stationId":b.id,"side":"start","latlng":WorldData.station_endpoint(b,"start"),"depthM":-15}
	var preview:=helper.track_preview(start,finish)
	_check(str(preview.issue).is_empty(),"默认两站顺接可以提交")
	var edge:Dictionary=preview.edge;edge.id="original";world.trackEdges.append(edge)
	_check(helper._physical_edge_geometry_issue(edge,world).is_empty(),"预览和正式几何校验一致")
	_check(absf(TrackNetwork.edge_length_m(edge,world,31.23)-float(preview.lengthM))<1.0,"预览长度与保存几何一致")
	var before:=JSON.stringify(world)
	var moved:=a.duplicate(true);moved.latlng=Geo.offset(a.latlng,200,0)
	var movement:=helper._station_preview_analysis(moved,world)
	_check(str(movement.issue).is_empty(),"横移站端生成相切曲线")
	_check(JSON.stringify(world)==before,"移动预览不改正式规划")
	_check(helper._physical_edge_geometry_issue(movement.state.trackEdges[0],movement.state).is_empty(),"横移后实际两端方向有效")
	var rotated:=a.duplicate(true);rotated.heading=77.4
	var rotation:=helper._station_preview_analysis(rotated,world)
	_check(str(rotation.issue).is_empty(),"任意角度旋转可顺接")
	_check(float(rotation.state.stations[0].heading)==77.4,"不会强制15度取整")
	var collision:=a.duplicate(true);collision.latlng=b.latlng
	_check(not str(helper._station_preview_analysis(collision,world).issue).is_empty(),"站体重叠被阻止")
	var slope:=a.duplicate(true);slope.depthM=-60
	_check(not str(helper._station_preview_analysis(slope,world).issue).is_empty(),"移动深度后坡度超限被阻止")
	world.routes=[{"id":"line","stationOrder":[a.id,b.id],"directions":[{"stationIds":[a.id,b.id],"edgePathsBySegment":[[{"id":"original","forward":true}]]},{"stationIds":[b.id,a.id],"edgePathsBySegment":[[{"id":"original","forward":false}]]}]}]
	var history:=CommandHistory.new();history.attach(world)
	history.execute("拆分",func(state:Dictionary):helper._split_track_edge(state,"original",0.3,31.23))
	_check(world.trackEdges.size()==2,"轨道拆分为两段")
	var f:Array=world.routes[0].directions[0].edgePathsBySegment[0]
	var r:Array=world.routes[0].directions[1].edgePathsBySegment[0]
	_check(f.size()==2 and r.size()==2 and str(f[0].id)==str(r[1].id) and not bool(r[0].forward),"正反向引用随拆分整体替换")
	_check(SaveManager.validate(world).is_empty(),"拆分后引用可以保存")
	history.undo();_check(world.trackEdges.size()==1 and str(world.trackEdges[0].id)=="original","撤销恢复原区间和线路")
	history.redo();_check(world.trackEdges.size()==2,"拆分可以重做")
	var cross_world:=WorldData.new_world("shanghai","workshop")
	var origin:=Geo.local_m([31.23,121.47],31.23)
	var n1:=TrackNetwork.create_node(cross_world,Geo.from_local(origin+Vector2(-500,0),31.23),-10)
	var n2:=TrackNetwork.create_node(cross_world,Geo.from_local(origin+Vector2(500,0),31.23),-30)
	cross_world.trackEdges.append({"id":"ramp","aNodeId":n1.id,"bNodeId":n2.id,"geometry":"straight"})
	helper.world=cross_world
	var points:Array=[Geo.from_local(origin+Vector2(-250,-300),31.23),Geo.from_local(origin+Vector2(-250,300),31.23)]
	_check(not helper._track_crossing_conflict(points,{},-15,-15,31.23).is_empty(),"交点实际同高不能用平均深度放行")
	_check(helper._track_crossing_conflict(points,{},-25,-25,31.23).is_empty(),"交点实际高差足够允许通过")
	var campaign:=WorldData.new_world("guangzhou","campaign")
	campaign.storyState.chapterId="gz-line1-1997"
	var historical_group:Dictionary=StorySession.groups(campaign,true)[0]
	var historical_a:=WorldData.create_station(campaign,[23.0,113.0],90);historical_a.historicalId=str(historical_group.stationIds[0])
	var historical_b:=WorldData.create_station(campaign,[23.01,113.01],90);historical_b.historicalId=str(historical_group.stationIds[1])
	campaign.stations=[historical_a,historical_b]
	helper.world=campaign;helper.active_city_id="guangzhou"
	var historical_start:Dictionary={"nodeId":TrackNetwork.station_node_id(historical_a,"end"),"stationId":historical_a.id,"side":"end","latlng":WorldData.station_endpoint(historical_a,"end"),"depthM":-15}
	var historical_finish:Dictionary={"nodeId":TrackNetwork.station_node_id(historical_b,"start"),"stationId":historical_b.id,"side":"start","latlng":WorldData.station_endpoint(historical_b,"start"),"depthM":-15}
	var historical_preview:=helper.track_preview(historical_start,historical_finish,[],true)
	_check(str(historical_preview.get("issue","" )).is_empty() and str(historical_preview.get("advisory","" )).contains("未核验"),"历史目标区间不因缺失隧道深度而触发虚构的交叉高差门槛")
	if failures.is_empty():print("PASS: %d story geometry checks" % checks);quit(0)
	else:
		for error in failures:push_error(error)
		quit(1)
