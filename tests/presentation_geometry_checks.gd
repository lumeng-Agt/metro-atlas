extends SceneTree

const DisplayGeometry=preload("res://scripts/presentation_geometry.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)
func _initialize() -> void:
	# A 300 m L-shaped route: the train must turn at the real join, rather
	# than interpolate directly between the first and last station.
	var direction:Dictionary={"segments":[{"points":[[0,0],[0,100.0/111320.0]]},{"points":[[0,100.0/111320.0],[200.0/111132.0,100.0/111320.0]]}]}
	var before:=JSON.stringify(direction)
	var path:=DisplayGeometry.prepare(direction,0)
	check(path.points.size()==3,"duplicate join is collapsed without dropping the turn")
	check(absf(float(path.lengthM)-300)<0.01,"distance follows both legs")
	check(DisplayGeometry.sample(path,50).point.distance_to(Vector2(50,0))<0.01,"first leg keeps its confirmed direction")
	check(DisplayGeometry.sample(path,150).point.distance_to(Vector2(100,50))<0.01,"train turns at the actual joint")
	check(DisplayGeometry.sample(path,100).point.distance_to(Vector2(100,0))<0.01,"exact join is stable")
	check(DisplayGeometry.sample(path,-10).point.distance_to(Vector2.ZERO)<0.01,"negative display distance clamps to route start")
	check(DisplayGeometry.sample(path,999).point.distance_to(Vector2(100,200))<0.01,"distance beyond route clamps to end")
	var reverse:=DisplayGeometry.prepare({"segments":[{"points":[[200.0/111132.0,100.0/111320.0],[0,100.0/111320.0],[0,0]]}]},0)
	check(DisplayGeometry.sample(reverse,50).point.distance_to(Vector2(100,150))<0.01,"reverse direction uses its own ordered geometry")
	check(DisplayGeometry.sample(DisplayGeometry.prepare({"segments":[{"points":[[0,0],[0,0]]}]},0),0).is_empty(),"zero-length route does not invent a train position")
	check(DisplayGeometry.sample({},20).is_empty(),"empty geometry is safe")
	check(JSON.stringify(direction)==before,"display preparation does not change the confirmed route")
	var straight:=PackedVector2Array([Vector2(0,0),Vector2(25,0.1),Vector2(50,-0.1),Vector2(100,0)])
	check(DisplayGeometry.simplify(straight,0.35)==PackedVector2Array([Vector2(0,0),Vector2(100,0)]),"subpixel straight detail can be reduced for rendering")
	var turn:=PackedVector2Array([Vector2(0,0),Vector2(50,0),Vector2(100,0),Vector2(100,100)])
	check(DisplayGeometry.simplify(turn,0.35)==PackedVector2Array([Vector2(0,0),Vector2(100,0),Vector2(100,100)]),"a real corner is retained")
	var backtrack:=PackedVector2Array([Vector2(0,0),Vector2(150,0),Vector2(100,0)])
	check(DisplayGeometry.simplify(backtrack,0.35)==backtrack,"simplification cannot erase a reversal beyond the endpoint")
	check(DisplayGeometry.simplify(straight,0)==straight,"zero tolerance keeps the exact source")
	var batch:=DisplayGeometry.StrokeBatch.new()
	batch.line(PackedVector2Array([Vector2(1000,2000),Vector2(1100,2000)]),4,Color.RED,Vector2(1000,2000),1)
	check(batch.vertices.size()==18 and batch.colors.size()==18,"stroke mesh includes a core and transparent antialias edges")
	check(batch.vertices[0]==Vector3(0,-2,0) and batch.vertices[2]==Vector3(100,-2,0),"mesh anchor preserves endpoints and exact physical stroke width")
	check(batch.colors[0]==Color.RED and batch.colors[8].a==0,"feather fades only the outer edge")
	check(batch.mesh().get_surface_count()==1,"all confirmed segments can share one display surface")
	if failures.is_empty():print("PASS: %d presentation geometry checks"%checks)
	else:
		for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
