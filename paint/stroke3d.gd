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
var _sculpt_last_mouse := Vector2.ZERO
var _sculpt_has_last := false

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

func begin_sculpt(mouse_pos: Vector2) -> void:
	_sculpt_last_mouse = mouse_pos
	_sculpt_has_last = true

func end_sculpt() -> void:
	_sculpt_has_last = false

func sculpt_screen(brush_pos: Vector2, camera: Camera3D, brush_radius_px: float, strength: float, mode: String) -> bool:
	var local_view := (global_transform.basis.inverse() * -camera.global_transform.basis.z).normalized()
	var local_right := (global_transform.basis.inverse() * camera.global_transform.basis.x).normalized()
	var local_up := (global_transform.basis.inverse() * camera.global_transform.basis.y).normalized()
	var drag := brush_pos - _sculpt_last_mouse if _sculpt_has_last else Vector2.ZERO
	_sculpt_last_mouse = brush_pos
	_sculpt_has_last = true
	var changed := false
	var original := points.duplicate()
	for i in range(points.size()):
		var world_point := to_global(original[i])
		if camera.is_position_behind(world_point): continue
		var screen_point := camera.unproject_position(world_point)
		var distance_px := screen_point.distance_to(brush_pos)
		if distance_px > brush_radius_px: continue
		var falloff := 1.0 - distance_px / maxf(brush_radius_px, 1.0)
		falloff = falloff * falloff * (3.0 - 2.0 * falloff)
		match mode:
			"move":
				points[i] += (local_right * drag.x - local_up * drag.y) * strength * 0.035 * falloff
			"pinch":
				var target_world := camera.project_ray_origin(brush_pos) + camera.project_ray_normal(brush_pos) * camera.project_ray_origin(brush_pos).distance_to(world_point)
				var target_local := to_local(target_world)
				points[i] = points[i].lerp(target_local, clampf(absf(strength) * 3.0 * falloff, 0.0, 0.75))
			"smooth":
				if i > 0 and i < original.size() - 1:
					var avg := (original[i - 1] + original[i + 1]) * 0.5
					points[i] = points[i].lerp(avg, clampf(absf(strength) * 5.0 * falloff, 0.0, 0.85))
			"inflate":
				var tangent := Vector3.RIGHT
				if i > 0 and i < original.size() - 1: tangent = (original[i + 1] - original[i - 1]).normalized()
				elif i + 1 < original.size(): tangent = (original[i + 1] - original[i]).normalized()
				var outward := tangent.cross(local_view).normalized()
				var sign_dir := 1.0 if screen_point.x >= brush_pos.x else -1.0
				points[i] += outward * sign_dir * strength * falloff
			_:
				points[i] += local_view * strength * falloff
		changed = true
	if changed: rebuild()
	return changed

func set_style(line_color: Color, use_fill: bool, new_fill_color: Color) -> void:
	stroke_color = line_color
	fill_enabled = use_fill
	fill_color = new_fill_color
	rebuild()

func rebuild() -> void:
	if points.size() < 2:
		return
	var result := ArrayMesh.new()
	_build_line_surface(result)
	if fill_enabled and points.size() >= 3:
		_build_fill_surface(result)
	mesh = result

func _base_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _build_line_surface(result: ArrayMesh) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var direction := (points[1] - points[0]).normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.92: up = Vector3.RIGHT
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
	st.commit(result)
	result.surface_set_material(result.get_surface_count() - 1, _base_material(stroke_color))

func _build_fill_surface(result: ArrayMesh) -> void:
	var flat := PackedVector2Array()
	for p in points: flat.append(Vector2(p.x, p.y))
	var fill_indices := Geometry2D.triangulate_polygon(flat)
	if fill_indices.size() < 3: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, fill_indices.size(), 3):
		var a := points[fill_indices[i]]
		var b := points[fill_indices[i + 1]]
		var c := points[fill_indices[i + 2]]
		_tri(st, a, b, c)
	st.commit(result)
	result.surface_set_material(result.get_surface_count() - 1, _base_material(fill_color))

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n); st.add_vertex(a)
	st.set_normal(n); st.add_vertex(b)
	st.set_normal(n); st.add_vertex(c)
