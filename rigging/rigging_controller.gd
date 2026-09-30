class_name RiggingController
extends RefCounted

# Canonical rigging domain. UI is intentionally kept out of this module.
var rigs: Dictionary = {} # rig id -> RigData

func clear() -> void:
	rigs.clear()

func create_rig(rig_id: String) -> RigData:
	var rig := RigData.new(rig_id)
	rigs[rig_id] = rig
	return rig

func set_parent(child: MotionObject, parent: MotionObject, child_node: Node3D, parent_node: Node3D, keep_global := true) -> bool:
	if child == null or parent == null or child_node == null or parent_node == null: return false
	if child.id == parent.id: return false
	var cursor: MotionObject = parent
	while cursor != null and not cursor.parent_id.is_empty():
		if cursor.parent_id == child.id: return false
		cursor = ProjectStore.objects.get(cursor.parent_id) as MotionObject
	var global_before: Transform3D = child_node.global_transform
	if child_node.get_parent() != parent_node:
		child_node.reparent(parent_node, keep_global)
	child.parent_id = parent.id
	child.transform = child_node.transform
	if keep_global:
		child_node.global_transform = global_before
		child.transform = child_node.transform
	return true

func set_pivot_keep_geometry(node: Node3D, new_global_pivot: Vector3) -> void:
	# Move the object origin while compensating direct Node3D children so the
	# visible result stays in place. Mesh pivot editing will later use the same
	# contract with vertex-space compensation.
	var delta_global: Vector3 = new_global_pivot - node.global_position
	var delta_local: Vector3 = node.global_basis.inverse() * delta_global
	for child in node.get_children():
		if child is Node3D:
			(child as Node3D).position -= delta_local
	node.global_position = new_global_pivot

func supports_mesh_binding(node: Node3D) -> bool:
	return node is MeshInstance3D and (node as MeshInstance3D).mesh != null

func auto_weight_vertices(mesh_instance: MeshInstance3D, bone_segments_local: Array) -> Array:
	# 2D skin solver inspired by common heat/topology workflows:
	# seed from distance to the full bone segment, then diffuse over triangle
	# adjacency, prune to four influences and normalize.
	var result: Array = []
	if mesh_instance == null or mesh_instance.mesh == null or bone_segments_local.is_empty(): return result
	var mesh: Mesh = mesh_instance.mesh
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var neighbors: Array = []
		neighbors.resize(vertices.size())
		for vi in range(vertices.size()): neighbors[vi] = {}
		if not indices.is_empty():
			for ti in range(0,indices.size(),3):
				if ti + 2 >= indices.size(): break
				var a: int = indices[ti]
				var b: int = indices[ti + 1]
				var c: int = indices[ti + 2]
				neighbors[a][b] = true; neighbors[a][c] = true
				neighbors[b][a] = true; neighbors[b][c] = true
				neighbors[c][a] = true; neighbors[c][b] = true
		var dense: Array = []
		for vertex in vertices:
			var row: PackedFloat32Array = PackedFloat32Array()
			row.resize(bone_segments_local.size())
			var sum: float = 0.0
			for bi in range(bone_segments_local.size()):
				var segment: Dictionary = bone_segments_local[bi]
				var a: Vector3 = segment.get("a",Vector3.ZERO)
				var b: Vector3 = segment.get("b",a)
				var d: float = _distance_to_segment(vertex,a,b)
				var influence: float = 1.0 / maxf(d * d,0.0004)
				row[bi] = influence
				sum += influence
			if sum > 0.0:
				for bi in range(row.size()): row[bi] /= sum
			dense.append(row)
		# Topology diffusion removes the Voronoi-like creases produced by pure
		# nearest-bone assignment while respecting disconnected mesh regions.
		for _pass in range(5):
			var next_dense: Array = []
			for vi in range(vertices.size()):
				var current: PackedFloat32Array = dense[vi]
				var smoothed: PackedFloat32Array = current.duplicate()
				var count: int = 1
				for ni in neighbors[vi].keys():
					var neighbor_row: PackedFloat32Array = dense[int(ni)]
					for bi in range(smoothed.size()): smoothed[bi] += neighbor_row[bi]
					count += 1
				for bi in range(smoothed.size()):
					var average: float = smoothed[bi] / float(count)
					smoothed[bi] = lerpf(current[bi],average,0.55)
				next_dense.append(smoothed)
			dense = next_dense
		var surface_weights: Array = []
		for row_value in dense:
			var row: PackedFloat32Array = row_value
			var ranked: Array = []
			for bi in range(row.size()):
				if row[bi] > 0.002: ranked.append({"bone":bi,"weight":float(row[bi])})
			ranked.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
			if ranked.size() > 4: ranked.resize(4)
			var total: float = 0.0
			for influence in ranked: total += float(influence["weight"])
			if total > 0.0:
				for influence in ranked: influence["weight"] = float(influence["weight"]) / total
			surface_weights.append(ranked)
		result.append(surface_weights)
	return result

func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq <= 0.000001: return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_sq,0.0,1.0)
	return point.distance_to(a + ab * t)
