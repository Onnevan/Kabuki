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

func auto_weight_vertices(mesh_instance: MeshInstance3D, bone_origins_local: PackedVector3Array) -> Array:
	# First useful automatic assignment: nearest two bones with inverse-distance
	# weights. The representation is renderer-independent and can later feed a
	# Godot Skin/Skeleton3D or our own deformation backend.
	var result: Array = []
	if mesh_instance == null or mesh_instance.mesh == null or bone_origins_local.is_empty(): return result
	var mesh: Mesh = mesh_instance.mesh
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_weights: Array = []
		for vertex in vertices:
			var nearest: int = -1
			var second: int = -1
			var d0: float = INF
			var d1: float = INF
			for bone_index in range(bone_origins_local.size()):
				var d: float = vertex.distance_squared_to(bone_origins_local[bone_index])
				if d < d0:
					d1 = d0; second = nearest
					d0 = d; nearest = bone_index
				elif d < d1:
					d1 = d; second = bone_index
			var influences: Array = []
			if nearest >= 0:
				if second < 0 or d0 <= 0.000001:
					influences.append({"bone": nearest, "weight": 1.0})
				else:
					var w0: float = 1.0 / maxf(sqrt(d0), 0.0001)
					var w1: float = 1.0 / maxf(sqrt(d1), 0.0001)
					var total: float = w0 + w1
					influences.append({"bone": nearest, "weight": w0 / total})
					influences.append({"bone": second, "weight": w1 / total})
			surface_weights.append(influences)
		result.append(surface_weights)
	return result
