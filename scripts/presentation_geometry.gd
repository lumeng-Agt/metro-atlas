class_name PresentationGeometry
extends RefCounted

class StrokeBatch extends RefCounted:
	var vertices:=PackedVector3Array()
	var colors:=PackedColorArray()
	func triangle(a:Vector2,b:Vector2,c:Vector2,color:Color) -> void:
		vertices.append(Vector3(a.x,a.y,0));vertices.append(Vector3(b.x,b.y,0));vertices.append(Vector3(c.x,c.y,0))
		colors.append(color);colors.append(color);colors.append(color)
	func colored_triangle(a:Vector2,b:Vector2,c:Vector2,ca:Color,cb:Color,cc:Color) -> void:
		vertices.append(Vector3(a.x,a.y,0));vertices.append(Vector3(b.x,b.y,0));vertices.append(Vector3(c.x,c.y,0))
		colors.append(ca);colors.append(cb);colors.append(cc)
	func line(points:PackedVector2Array,width:float,color:Color,anchor:Vector2,feather:float=0) -> void:
		for index in range(1,points.size()):
			var a:=points[index-1]-anchor;var b:=points[index]-anchor
			var delta:=b-a
			if delta.length_squared()<0.000001:continue
			var normal:=Vector2(-delta.y,delta.x).normalized()*width*0.5
			triangle(a-normal,a+normal,b-normal,color);triangle(b-normal,a+normal,b+normal,color)
			if feather>0:
				var outer:=normal.normalized()*(width*0.5+feather)
				var transparent:=Color(color,color.a*0.0)
				colored_triangle(a-normal,b-normal,a-outer,color,color,transparent)
				colored_triangle(a-outer,b-normal,b-outer,transparent,color,transparent)
				colored_triangle(a+normal,a+outer,b+normal,color,transparent,color)
				colored_triangle(a+outer,b+outer,b+normal,transparent,transparent,color)
	func mesh() -> ArrayMesh:
		var result:=ArrayMesh.new()
		if vertices.is_empty():return result
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		return result

## Display-only distance lookup over the exact confirmed route geometry.
## Built once with the route cache; no scheduling or authoritative state.
static func prepare(direction:Dictionary,ref_lat:float) -> Dictionary:
	var points:=PackedVector2Array();var distances:=PackedFloat64Array();var total:=0.0
	for segment in direction.get("segments",[]):
		for geographic in segment.get("points",[]):
			var point:=Geo.local_m(geographic,ref_lat)
			if not points.is_empty():
				var length:=points[-1].distance_to(point)
				if length<=0.001:continue
				total+=length
			points.append(point);distances.append(total)
	return {"points":points,"distances":distances,"lengthM":total}

static func sample(path:Dictionary,distance:float) -> Dictionary:
	var points:PackedVector2Array=path.get("points",PackedVector2Array())
	var distances:PackedFloat64Array=path.get("distances",PackedFloat64Array())
	if points.size()<2 or distances.size()!=points.size() or float(path.get("lengthM",0))<=0:return {}
	var position:=clampf(distance,0,float(path.lengthM))
	var end:=clampi(distances.bsearch(position),1,points.size()-1)
	var span:=distances[end]-distances[end-1]
	return {"point":points[end-1].lerp(points[end],(position-distances[end-1])/maxf(span,0.001)),"from":points[end-1],"to":points[end]}

## Display-only reduction with a maximum perpendicular deviation. Endpoints,
## turns and backtracking survive; construction, picking and train distances
## continue to read the original geometry.
static func simplify(points:PackedVector2Array,tolerance:float) -> PackedVector2Array:
	if points.size()<3 or tolerance<=0:return points
	var keep:=PackedByteArray();keep.resize(points.size());keep[0]=1;keep[-1]=1
	var pending:Array[Vector2i]=[Vector2i(0,points.size()-1)]
	while not pending.is_empty():
		var span:=pending.pop_back() as Vector2i
		var a:=points[span.x];var delta:=points[span.y]-a
		var denominator:=delta.length_squared()
		var largest:=tolerance*tolerance;var split:=-1
		for index in range(span.x+1,span.y):
			var t:=clampf((points[index]-a).dot(delta)/denominator,0,1) if denominator>0 else 0.0
			var error:=points[index].distance_squared_to(a+delta*t)
			if error>largest:largest=error;split=index
		if split<0:continue
		keep[split]=1;pending.append(Vector2i(span.x,split));pending.append(Vector2i(split,span.y))
	var result:=PackedVector2Array()
	for index in range(points.size()):
		if keep[index]:result.append(points[index])
	return result
