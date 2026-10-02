class_name Stroke3D
extends MeshInstance3D

var points := PackedVector3Array()
var stroke_color := Color(0.08, 0.08, 0.08, 1.0)
var radius := 0.012
var sides := 10
var brush_preset := "clean"
var width_variation := 0.0
var width_frequency := 1.0
var brush_seed := 1
var start_cap := "flat"
var end_cap := "flat"
var fill_enabled := false
var fill_color := Color(0.8, 0.25, 0.18, 0.55)
var fill_mode := "solid"
var fill_color_b := Color(0.95, 0.75, 0.2, 0.55)
var fill_gradient_angle := 0.0
var closed := false
var stroke_id := ""
var _sculpt_last_mouse := Vector2.ZERO
var _sculpt_has_last := false

func set_points(value: PackedVector3Array) -> void:
	# Playback frequently evaluates the same held cel for many consecutive
	# frames. Rebuilding SurfaceTool geometry when the points are unchanged is
	# one of the most expensive operations in the drawing path.
	if _points_equal(points, value): return
	points = value.duplicate()
	rebuild()

func _points_equal(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size(): return false
	for i in range(a.size()):
		if not a[i].is_equal_approx(b[i]): return false
	return true

func style_dict() -> Dictionary:
	return {"radius": radius, "color": stroke_color, "fill_enabled": fill_enabled, "fill_color": fill_color, "fill_mode": fill_mode, "fill_color_b": fill_color_b, "fill_gradient_angle": fill_gradient_angle, "brush_preset": brush_preset, "width_variation": width_variation, "width_frequency": width_frequency, "brush_seed": brush_seed, "start_cap": start_cap, "end_cap": end_cap}

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
	if points.is_empty(): return false

	# Convert screen-space interaction into a stable local-space scale.
	# A 100 px brush should produce a clearly visible deformation regardless of zoom.
	var reference_world := global_position
	if not camera.is_position_behind(reference_world):
		var a := camera.project_position(brush_pos, camera.global_position.distance_to(reference_world))
		var b := camera.project_position(brush_pos + Vector2(maxf(1.0,brush_radius_px),0.0), camera.global_position.distance_to(reference_world))
		var world_radius := a.distance_to(b)
		if world_radius <= 0.00001: world_radius = maxf(0.001,brush_radius_px * 0.002)
	else:
		var world_radius := maxf(0.001,brush_radius_px * 0.002)

	var changed := false
	var original := points.duplicate()
	var abs_strength := absf(strength)
	var normalized_strength := clampf(abs_strength / 0.08,0.0,2.0)

	for i in range(points.size()):
		var world_point := to_global(original[i])
		if camera.is_position_behind(world_point): continue
		var screen_point := camera.unproject_position(world_point)
		var distance_px := screen_point.distance_to(brush_pos)
		if distance_px > brush_radius_px: continue

		var falloff := 1.0 - distance_px / maxf(brush_radius_px,1.0)
		# Smoothstep falloff: strong center, soft edge.
		falloff = falloff * falloff * (3.0 - 2.0 * falloff)

		match mode:
			"move":
				if drag.length_squared() > 0.0:
					var screen_delta := (local_right * drag.x - local_up * drag.y)
					var local_per_px := world_radius / maxf(brush_radius_px,1.0)
					points[i] += screen_delta * local_per_px * normalized_strength * falloff

			"pinch":
				var depth := camera.global_position.distance_to(world_point)
				var target_world := camera.project_position(brush_pos,depth)
				var target_local := to_local(target_world)
				var amount := clampf(normalized_strength * 0.22 * falloff,0.0,0.9)
				points[i] = points[i].lerp(target_local,amount)

			"smooth":
				if i > 0 and i < original.size()-1:
					var avg := (original[i-1] + original[i+1]) * 0.5
					var amount := clampf(normalized_strength * 0.38 * falloff,0.0,0.95)
					points[i] = points[i].lerp(avg,amount)

			"inflate":
				var tangent := Vector3.RIGHT
				if i > 0 and i < original.size()-1:
					tangent = (original[i+1]-original[i-1]).normalized()
				elif i+1 < original.size():
					tangent = (original[i+1]-original[i]).normalized()
				elif i > 0:
					tangent = (original[i]-original[i-1]).normalized()
				var outward := tangent.cross(local_view).normalized()
				var radial_sign := 1.0 if screen_point.x >= brush_pos.x else -1.0
				points[i] += outward * radial_sign * world_radius * 0.18 * normalized_strength * falloff * signf(strength if not is_zero_approx(strength) else 1.0)

			_:
				points[i] += local_view * world_radius * 0.15 * normalized_strength * falloff * signf(strength if not is_zero_approx(strength) else 1.0)

		changed = true

	if changed: rebuild()
	return changed

func set_style(line_color: Color, use_fill: bool, new_fill_color: Color, new_fill_mode := "solid", new_fill_color_b := Color(0.95,0.75,0.2,0.55), new_gradient_angle := 0.0) -> void:
	if stroke_color == line_color and fill_enabled == use_fill and fill_color == new_fill_color and fill_mode == new_fill_mode and fill_color_b == new_fill_color_b and is_equal_approx(fill_gradient_angle,new_gradient_angle): return
	stroke_color = line_color
	fill_enabled = use_fill
	fill_color = new_fill_color
	fill_mode = new_fill_mode
	fill_color_b = new_fill_color_b
	fill_gradient_angle = new_gradient_angle
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
	# Drawing colors should be WYSIWYG and must not be darkened by scene lighting.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _smoothed_points() -> PackedVector3Array:
	if points.size() < 3:
		return points.duplicate()
	# Catmull-Rom keeps the stroke passing through the artist's sampled points,
	# while adding enough intermediate samples for a continuous silhouette.
	var out := PackedVector3Array()
	var subdivisions := 3
	for i in range(points.size() - 1):
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, points.size() - 1)]
		for step in range(subdivisions):
			var t: float = float(step) / float(subdivisions)
			var t2 := t * t
			var t3 := t2 * t
			var p: Vector3 = 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0*p0 - 5.0*p1 + 4.0*p2 - p3) * t2 + (-p0 + 3.0*p1 - 3.0*p2 + p3) * t3)
			if out.is_empty() or out[-1].distance_squared_to(p) > 0.0000001:
				out.append(p)
	out.append(points[-1])
	return out

func _radius_at(index: int, count: int) -> float:
	if width_variation <= 0.0001 or count <= 1: return radius
	var t := float(index) / float(count - 1)
	# Two smooth harmonics produce coherent ink wobble rather than per-point jitter.
	var phase := float(brush_seed % 997) * 0.017
	var wave := sin(t * TAU * width_frequency + phase) * 0.68
	wave += sin(t * TAU * width_frequency * 0.47 + phase * 1.91) * 0.32
	return radius * maxf(0.18, 1.0 + wave * width_variation)

func _build_line_surface(result: ArrayMesh) -> void:
	var curve_points := _smoothed_points()
	if curve_points.size() < 2: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Build one continuous tube. A parallel-transport-like frame carries the
	# previous ring orientation forward, avoiding the per-segment frame resets
	# that made the old stroke look like disconnected quadrangles.
	var tangents := PackedVector3Array()
	for i in range(curve_points.size()):
		var tangent: Vector3
		if i == 0:
			tangent = (curve_points[1] - curve_points[0]).normalized()
		elif i == curve_points.size() - 1:
			tangent = (curve_points[-1] - curve_points[-2]).normalized()
		else:
			tangent = (curve_points[i + 1] - curve_points[i - 1]).normalized()
		tangents.append(tangent)
	var ref := Vector3(0,0,1)
	if absf(tangents[0].dot(ref)) > 0.95: ref = Vector3.UP
	var side := tangents[0].cross(ref).normalized()
	if side.length_squared() < 0.0001: side = Vector3.RIGHT
	var up := side.cross(tangents[0]).normalized()
	var ring_side: Array[Vector3] = []
	var ring_up: Array[Vector3] = []
	for i in range(curve_points.size()):
		if i > 0:
			side = (side - tangents[i] * side.dot(tangents[i])).normalized()
			if side.length_squared() < 0.0001:
				side = tangents[i].cross(up).normalized()
			up = side.cross(tangents[i]).normalized()
		ring_side.append(side)
		ring_up.append(up)
	for i in range(curve_points.size() - 1):
		for j in range(sides):
			var a0 := TAU * float(j) / float(sides)
			var a1 := TAU * float(j + 1) / float(sides)
			var radius_a := _radius_at(i, curve_points.size())
			var radius_b := _radius_at(i + 1, curve_points.size())
			var r00: Vector3 = ring_side[i] * cos(a0) * radius_a + ring_up[i] * sin(a0) * radius_a
			var r01: Vector3 = ring_side[i] * cos(a1) * radius_a + ring_up[i] * sin(a1) * radius_a
			var r10: Vector3 = ring_side[i + 1] * cos(a0) * radius_b + ring_up[i + 1] * sin(a0) * radius_b
			var r11: Vector3 = ring_side[i + 1] * cos(a1) * radius_b + ring_up[i + 1] * sin(a1) * radius_b
			_tri(st, curve_points[i] + r00, curve_points[i + 1] + r10, curve_points[i + 1] + r11)
			_tri(st, curve_points[i] + r00, curve_points[i + 1] + r11, curve_points[i] + r01)
	var start_center := curve_points[0]
	var end_center := curve_points[-1]
	var start_radius := _radius_at(0, curve_points.size())
	var end_radius := _radius_at(curve_points.size() - 1, curve_points.size())
	var start_tip := start_center - tangents[0] * start_radius * (1.8 if start_cap == "point" else 0.65)
	var end_tip := end_center + tangents[-1] * end_radius * (1.8 if end_cap == "point" else 0.65)
	for j in range(sides):
		var a0 := TAU * float(j) / float(sides)
		var a1 := TAU * float(j + 1) / float(sides)
		var s0: Vector3 = ring_side[0] * cos(a0) * start_radius + ring_up[0] * sin(a0) * start_radius
		var s1: Vector3 = ring_side[0] * cos(a1) * start_radius + ring_up[0] * sin(a1) * start_radius
		var e0: Vector3 = ring_side[-1] * cos(a0) * end_radius + ring_up[-1] * sin(a0) * end_radius
		var e1: Vector3 = ring_side[-1] * cos(a1) * end_radius + ring_up[-1] * sin(a1) * end_radius
		var sc := start_tip if start_cap == "point" else start_center
		var ec := end_tip if end_cap == "point" else end_center
		_tri(st, sc, start_center + s1, start_center + s0)
		_tri(st, ec, end_center + e0, end_center + e1)
		if start_cap == "round":
			var half := start_center - tangents[0] * start_radius * 0.55
			_tri(st, half, start_center + s1, start_center + s0)
		if end_cap == "round":
			var half_end := end_center + tangents[-1] * end_radius * 0.55
			_tri(st, half_end, end_center + e0, end_center + e1)
	st.commit(result)
	result.surface_set_material(result.get_surface_count() - 1, _base_material(stroke_color))

func _build_fill_surface(result: ArrayMesh) -> void:
	var flat := PackedVector2Array()
	for p in points: flat.append(Vector2(p.x, p.y))
	var fill_indices := Geometry2D.triangulate_polygon(flat)
	if fill_indices.size() < 3: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var min_proj := INF
	var max_proj := -INF
	var angle := deg_to_rad(fill_gradient_angle)
	var gradient_dir := Vector2(cos(angle), sin(angle))
	for p in points:
		var projection := Vector2(p.x,p.y).dot(gradient_dir)
		min_proj = minf(min_proj,projection)
		max_proj = maxf(max_proj,projection)
	var span := maxf(max_proj-min_proj,0.00001)
	for i in range(0, fill_indices.size(), 3):
		for index_offset in range(3):
			var p: Vector3 = points[fill_indices[i+index_offset]]
			if fill_mode == "gradient":
				var t := clampf((Vector2(p.x,p.y).dot(gradient_dir)-min_proj)/span,0.0,1.0)
				st.set_color(fill_color.lerp(fill_color_b,t))
			else:
				st.set_color(Color.WHITE)
			st.add_vertex(p)
	st.commit(result)
	var material := _base_material(Color.WHITE if fill_mode == "gradient" else fill_color)
	if fill_mode == "gradient":
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.surface_set_material(result.get_surface_count() - 1, material)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n); st.add_vertex(a)
	st.set_normal(n); st.add_vertex(b)
	st.set_normal(n); st.add_vertex(c)
