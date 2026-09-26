class_name AlphaMeshBuilder
extends RefCounted

# Prototype silhouette mesher: samples opaque pixels + boundary candidates, then uses
# Godot's Delaunay triangulation and rejects triangles whose centroid is transparent.
# This gives deformation-ready geometry without exposing mesh editing to the user.
static func build(image: Image, alpha_threshold := 0.08, target_samples := 900) -> ArrayMesh:
	var w := image.get_width(); var h := image.get_height()
	var area: int = maxi(1, w * h)
	var step := maxi(2, int(sqrt(float(area) / float(target_samples))))
	var pts := PackedVector2Array()
	for y in range(0, h, step):
		for x in range(0, w, step):
			if image.get_pixel(x, y).a >= alpha_threshold:
				pts.append(Vector2(clampi(x + int(sin(float(x * 7 + y * 3)) * step * 0.32), 0, w - 1), clampi(y + int(sin(float(x * 5 + y * 11)) * step * 0.32), 0, h - 1)))
	var bstep: int = maxi(1, int(step / 2))
	for y in range(0, h, bstep):
		for x in range(0, w, bstep):
			if image.get_pixel(x, y).a < alpha_threshold: continue
			var edge := x == 0 or y == 0 or x >= w-1 or y >= h-1
			if not edge:
				edge = image.get_pixel(maxi(0,x-bstep), y).a < alpha_threshold or image.get_pixel(mini(w-1,x+bstep), y).a < alpha_threshold or image.get_pixel(x, maxi(0,y-bstep)).a < alpha_threshold or image.get_pixel(x, mini(h-1,y+bstep)).a < alpha_threshold
			if edge: pts.append(Vector2(x, y))
	if pts.size() < 3: return ArrayMesh.new()
	var indices := Geometry2D.triangulate_delaunay(pts)
	var verts := PackedVector3Array(); var uvs := PackedVector2Array(); var out_idx := PackedInt32Array()
	for p in pts:
		verts.append(Vector3((p.x - w*0.5)/float(h), -(p.y-h*0.5)/float(h), 0.0))
		uvs.append(Vector2(p.x/float(w), p.y/float(h)))
	for i in range(0, indices.size(), 3):
		var a := pts[indices[i]]; var b := pts[indices[i+1]]; var c := pts[indices[i+2]]
		var q := (a+b+c)/3.0
		if image.get_pixel(clampi(int(q.x),0,w-1), clampi(int(q.y),0,h-1)).a >= alpha_threshold:
			out_idx.append(indices[i]); out_idx.append(indices[i+1]); out_idx.append(indices[i+2])
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = out_idx
	var mesh := ArrayMesh.new()
	if out_idx.size() >= 3: mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
