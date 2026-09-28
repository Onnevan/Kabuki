class_name AlphaMeshBuilder
extends RefCounted

# Deformation-ready alpha mesher. It crops transparent margins, samples the
# visible silhouette with Poisson-like blue-noise spacing, adds a denser alpha
# boundary, Delaunay-triangulates, then rejects triangles outside the alpha mask.
static func alpha_bounds(image: Image, alpha_threshold := 0.08) -> Rect2i:
	var min_x := image.get_width(); var min_y := image.get_height()
	var max_x := -1; var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a >= alpha_threshold:
				min_x=mini(min_x,x); min_y=mini(min_y,y)
				max_x=maxi(max_x,x); max_y=maxi(max_y,y)
	if max_x < min_x: return Rect2i()
	return Rect2i(min_x,min_y,max_x-min_x+1,max_y-min_y+1)

static func build(image: Image, alpha_threshold := 0.08, target_samples := 1100) -> ArrayMesh:
	var bounds := alpha_bounds(image,alpha_threshold)
	if bounds.size.x <= 0 or bounds.size.y <= 0: return ArrayMesh.new()
	var area := maxi(1,bounds.size.x*bounds.size.y)
	var radius := maxf(2.0,sqrt(float(area)/float(target_samples))*0.82)
	var cell := radius/1.41421356
	var grid: Dictionary={}
	var pts := PackedVector2Array()
	var candidates: Array[Vector2]=[]
	# Deterministic jittered candidates approximate Poisson disk without random
	# frame-to-frame topology changes.
	var stride := maxi(2,int(floor(radius*0.72)))
	for y in range(bounds.position.y,bounds.end.y,stride):
		for x in range(bounds.position.x,bounds.end.x,stride):
			var hx := fmod(sin(float(x*127+y*311))*43758.5453,1.0)
			var hy := fmod(sin(float(x*269+y*183))*24634.6345,1.0)
			var p := Vector2(clampf(x+absf(hx)*stride,bounds.position.x,bounds.end.x-1),clampf(y+absf(hy)*stride,bounds.position.y,bounds.end.y-1))
			if image.get_pixel(clampi(int(p.x),0,image.get_width()-1),clampi(int(p.y),0,image.get_height()-1)).a>=alpha_threshold:
				candidates.append(p)
	for p in candidates:
		var gx:=int(floor(p.x/cell)); var gy:=int(floor(p.y/cell)); var ok:=true
		for yy in range(gy-2,gy+3):
			for xx in range(gx-2,gx+3):
				var key:=Vector2i(xx,yy)
				if grid.has(key) and p.distance_to(pts[int(grid[key])])<radius: ok=false; break
			if not ok: break
		if ok:
			grid[Vector2i(gx,gy)]=pts.size(); pts.append(p)
	# Boundary samples preserve the silhouette independently of interior density.
	var edge_step:=maxi(1,int(radius*0.45))
	for y in range(bounds.position.y,bounds.end.y,edge_step):
		for x in range(bounds.position.x,bounds.end.x,edge_step):
			if image.get_pixel(x,y).a<alpha_threshold: continue
			var edge:=x<=bounds.position.x or y<=bounds.position.y or x>=bounds.end.x-1 or y>=bounds.end.y-1
			if not edge:
				edge=image.get_pixel(maxi(0,x-edge_step),y).a<alpha_threshold or image.get_pixel(mini(image.get_width()-1,x+edge_step),y).a<alpha_threshold or image.get_pixel(x,maxi(0,y-edge_step)).a<alpha_threshold or image.get_pixel(x,mini(image.get_height()-1,y+edge_step)).a<alpha_threshold
			if edge: pts.append(Vector2(x,y))
	if pts.size()<3: return ArrayMesh.new()
	var indices:=Geometry2D.triangulate_delaunay(pts)
	var verts:=PackedVector3Array(); var uvs:=PackedVector2Array(); var normals:=PackedVector3Array(); var out_idx:=PackedInt32Array()
	var h:=float(image.get_height()); var w:=float(image.get_width())
	for p in pts:
		verts.append(Vector3((p.x-w*0.5)/h,-(p.y-h*0.5)/h,0.0))
		uvs.append(Vector2(p.x/w,p.y/h)); normals.append(Vector3(0,0,1))
	for i in range(0,indices.size(),3):
		var a:=pts[indices[i]]; var b:=pts[indices[i+1]]; var c:=pts[indices[i+2]]
		var q:=(a+b+c)/3.0
		if image.get_pixel(clampi(int(q.x),0,image.get_width()-1),clampi(int(q.y),0,image.get_height()-1)).a<alpha_threshold: continue
		var ia:int=indices[i]; var ib:int=indices[i+1]; var ic:int=indices[i+2]
		if (pts[ib]-pts[ia]).cross(pts[ic]-pts[ia])>0.0:
			var tmp:=ib; ib=ic; ic=tmp
		out_idx.append(ia); out_idx.append(ib); out_idx.append(ic)
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=out_idx
	var mesh:=ArrayMesh.new()
	if out_idx.size()>=3: mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
