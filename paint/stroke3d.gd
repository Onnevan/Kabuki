class_name Stroke3D
extends MeshInstance3D

var points := PackedVector3Array()
var stroke_color := Color(0.08, 0.08, 0.08, 1.0)
var radius := 0.012
var sides := 6
var fill_enabled := false
var fill_color := Color(0.8, 0.25, 0.18, 0.55)
var closed := false
var stroke_id := ""

func set_points(value: PackedVector3Array) -> void:
	points = value.duplicate()
	rebuild()

func style_dict() -> Dictionary:
	return {"radius": radius, "color": stroke_color, "fill_enabled": fill_enabled, "fill_color": fill_color}

func add_point(p: Vector3) -> void:
	if not points.is_empty() and points[-1].distance_to(p) < 0.006:
		return
	points.append(p)
	rebuild()

func sculpt_screen(brush_pos: Vector2, camera: Camera3D, brush_radius_px: float, strength: float) -> bool:
	# Screen-space hit testing makes sculpt work even after points have been pushed
	# away from the original drawing plane.
	var local_direction := (global_transform.basis.inverse() * -camera.global_transform.basis.z).normalized()
	var changed := false
	for i in range(points.size()):
		var world_point := to_global(points[i])
		if camera.is_position_behind(world_point): continue
		var screen_point := camera.unproject_position(world_point)
		var distance_px := screen_point.distance_to(brush_pos)
		if distance_px > brush_radius_px: continue
		var falloff := 1.0 - distance_px / maxf(brush_radius_px, 1.0)
		falloff = falloff * falloff * (3.0 - 2.0 * falloff)
		points[i] += local_direction * strength * falloff
		changed = true
	if changed: rebuild()
	return changed

func rebuild() -> void:
	if points.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var direction := (points[1] - points[0]).normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.92:
		up = Vector3.RIGHT
	var side := direction.cross(up).normalized()
	up = side.cross(direction).normalized()
	for i in range(points.size() - 1):
		var p0 := points[i]
		var p1 := points[i + 1]
		var tangent := (p1 - p0).normalized()
		if tangent.length_squared() > 0.0:
			side = tangent.cross(up).normalized()
			if side.length_squared() < 0.001: side = Vector3.RIGHT
			up = side.cross(tangent).normalized()
		for j in range(sides):
			var a0 := TAU * float(j) / float(sides)
			var a1 := TAU * float(j + 1) / float(sides)
			var r0 := side * cos(a0) * radius + up * sin(a0) * radius
			var r1 := side * cos(a1) * radius + up * sin(a1) * radius
			_tri(st, p0 + r0, p1 + r0, p1 + r1)
			_tri(st, p0 + r0, p1 + r1, p0 + r1)
	if fill_enabled and points.size() >= 3:
		_add_fill(st)
	var result := st.commit()
	mesh = result
	var mat := StandardMaterial3D.new()
	mat.albedo_color = stroke_color
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n); st.add_vertex(a)
	st.set_normal(n); st.add_vertex(b)
	st.set_normal(n); st.add_vertex(c)

func _add_fill(st: SurfaceTool) -> void:
	var flat := PackedVector2Array()
	for p in points:
		flat.append(Vector2(p.x, p.y))
	var fill_indices := Geometry2D.triangulate_polygon(flat)
	for i in range(0, fill_indices.size(), 3):
		var a := points[fill_indices[i]]
		var b := points[fill_indices[i + 1]]
		var c := points[fill_indices[i + 2]]
		var n := (b - a).cross(c - a).normalized()
		st.set_color(fill_color); st.set_normal(n); st.add_vertex(a)
		st.set_color(fill_color); st.set_normal(n); st.add_vertex(b)
		st.set_color(fill_color); st.set_normal(n); st.add_vertex(c)
