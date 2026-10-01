class_name RigRuntime
extends Node3D

var rig: RigData
var skeleton := Skeleton3D.new()
var bone_gizmos: Array[MeshInstance3D] = []
var bound_meshes: Dictionary = {}
var terminal_tips: Dictionary = {}
var weight_debug_overlays: Array[MeshInstance3D] = []

func setup(value: RigData) -> void:
	rig = value
	skeleton.name = "_Skeleton"
	add_child(skeleton)
	rebuild_bones()

func rebuild_bones() -> void:
	for gizmo in bone_gizmos:
		if is_instance_valid(gizmo): gizmo.queue_free()
	bone_gizmos.clear()
	skeleton.clear_bones()
	for i in range(rig.bones.size()):
		var record: Dictionary = rig.bones[i]
		skeleton.add_bone(String(record.get("name","Bone")))
		var parent_index: int = int(record.get("parent",-1))
		if parent_index >= 0: skeleton.set_bone_parent(i,parent_index)
		var rest_global: Transform3D = record.get("rest",Transform3D.IDENTITY)
		var rest_in_rig: Transform3D = global_transform.affine_inverse() * rest_global
		var rest_local: Transform3D = rest_in_rig
		if parent_index >= 0:
			var parent_global: Transform3D = rig.bones[parent_index].get("rest",Transform3D.IDENTITY)
			var parent_in_rig: Transform3D = global_transform.affine_inverse() * parent_global
			rest_local = parent_in_rig.affine_inverse() * rest_in_rig
		skeleton.set_bone_rest(i,rest_local)
		# Godot 4 bone poses are absolute local transforms, not offsets from rest.
		# A newly-created bone otherwise keeps the default identity pose, so the
		# Skin evaluates pose * inverse(rest) immediately and displaces artwork
		# even before the user poses a bone. Initialize pose exactly to REST.
		skeleton.set_bone_pose(i,rest_local)
		_create_bone_gizmo(i,rest_in_rig.origin,parent_index)

func _create_bone_gizmo(index: int, head: Vector3, _parent_index: int) -> void:
	var tail: Vector3 = _rest_tail_in_rig(index,head)
	var gizmo := MeshInstance3D.new()
	gizmo.name = "_BoneGizmo_%d" % index
	gizmo.mesh = _bone_mesh(head,tail)
	gizmo.set_meta("bone_index",index)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.22,0.62,1.0,0.95)
	mat.no_depth_test = true
	mat.render_priority = 120
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gizmo.material_override = mat
	gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gizmo)
	bone_gizmos.append(gizmo)

func _rest_tail_in_rig(index: int, head: Vector3) -> Vector3:
	for child_index in range(rig.bones.size()):
		if int(rig.bones[child_index].get("parent",-1)) == index:
			var child_rest: Transform3D = rig.bones[child_index].get("rest",Transform3D.IDENTITY)
			return (global_transform.affine_inverse() * child_rest).origin
	if terminal_tips.has(index):
		return global_transform.affine_inverse() * (terminal_tips[index] as Vector3)
	return head + Vector3(0.0,0.45,0.0)

func _bone_mesh(head: Vector3, tail: Vector3) -> ArrayMesh:
	var direction: Vector3 = tail - head
	var length: float = maxf(direction.length(),0.12)
	var radius: float = maxf(0.035,length*0.11)
	var up: Vector3 = direction.normalized() if direction.length_squared() > 0.000001 else Vector3.UP
	var view_axis := Vector3(0,0,1)
	var side: Vector3 = up.cross(view_axis)
	if side.length_squared() < 0.000001: side = up.cross(Vector3.RIGHT)
	side = side.normalized() * radius
	var depth: Vector3 = up.cross(side).normalized() * radius * 0.55
	var verts := PackedVector3Array([head-side,head+side,head+depth,head-depth,tail])
	var indices := PackedInt32Array([0,1,4,1,2,4,2,3,4,3,0,4,0,3,2,0,2,1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _process(_delta: float) -> void:
	_update_bone_gizmos_from_pose()

func _update_bone_gizmos_from_pose() -> void:
	if skeleton == null or rig == null: return
	for i in range(mini(bone_gizmos.size(),skeleton.get_bone_count())):
		var gizmo: MeshInstance3D = bone_gizmos[i]
		if not is_instance_valid(gizmo): continue
		var pose_global: Transform3D = skeleton.get_bone_global_pose(i)
		var head: Vector3 = pose_global.origin
		var tail: Vector3
		var child_found: bool = false
		for child_index in range(rig.bones.size()):
			if int(rig.bones[child_index].get("parent",-1)) == i:
				tail = skeleton.get_bone_global_pose(child_index).origin
				child_found = true
				break
		if not child_found:
			var rest_global: Transform3D = skeleton.get_bone_global_rest(i)
			var rest_tail: Vector3 = _rest_tail_in_rig(i,rest_global.origin)
			var local_tail: Vector3 = rest_global.affine_inverse() * rest_tail
			tail = pose_global * local_tail
		gizmo.mesh = _bone_mesh(head,tail)

func set_terminal_tip(bone_index: int, world_tip: Vector3) -> void:
	if bone_index < 0: return
	terminal_tips[bone_index] = world_tip
	rebuild_bones()

func clear_terminal_tip(bone_index: int = -1) -> void:
	if bone_index >= 0:
		terminal_tips.erase(bone_index)
	rebuild_bones()

func bind_mesh(mesh_instance: MeshInstance3D, weights_by_surface: Array) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null or rig == null: return false
	clear_weight_debug()
	# Binding is an atomic operation: first move the artwork under the Armature,
	# then bake that local transform into its vertices. From this point onward
	# artwork, Skin and Skeleton all live in the SAME RigRuntime coordinate space.
	if mesh_instance.get_parent() != self:
		mesh_instance.reparent(self,true)
	var artwork_transform: Transform3D = mesh_instance.transform
	var source: Mesh = mesh_instance.mesh
	var skinned := ArrayMesh.new()
	for surface_index in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vi in range(vertices.size()):
			vertices[vi] = artwork_transform * vertices[vi]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if not normals.is_empty():
				var normal_basis: Basis = artwork_transform.basis.inverse().transposed()
				for ni in range(normals.size()): normals[ni] = (normal_basis * normals[ni]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vertices.size()*4)
		weights.resize(vertices.size()*4)
		var surface_weights: Array = weights_by_surface[surface_index] if surface_index < weights_by_surface.size() else []
		for vi in range(vertices.size()):
			var influences: Array = surface_weights[vi] if vi < surface_weights.size() else []
			for slot in range(4):
				var offset: int = vi*4+slot
				if slot < influences.size():
					bones[offset] = int(influences[slot].get("bone",0))
					weights[offset] = float(influences[slot].get("weight",0.0))
				else:
					bones[offset] = 0
					weights[offset] = 0.0
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		skinned.add_surface_from_arrays(source.surface_get_primitive_type(surface_index),arrays)
	mesh_instance.mesh = skinned
	mesh_instance.transform = Transform3D.IDENTITY
	# Let Skeleton3D build the inverse bind matrices from the exact rest
	# transforms it evaluates. Now that pose is initialized to rest, this avoids
	# maintaining a second hand-written interpretation of Godot's bone space.
	var skin: Skin = skeleton.create_skin_from_rest_transforms()
	mesh_instance.skin = skin
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	bound_meshes[mesh_instance.get_instance_id()] = mesh_instance
	return true

func show_weight_debug(mesh_instance: MeshInstance3D, weights_by_surface: Array, bone_index: int = 0) -> void:
	clear_weight_debug()
	if mesh_instance == null or mesh_instance.mesh == null: return
	# Weight inspection must be the SAME skinned mesh in its current pose.
	# Duplicating an unskinned debug mesh made the artwork snap visually back
	# to REST whenever a bone was selected.
	var source: Mesh = mesh_instance.mesh
	var debug_mesh := ArrayMesh.new()
	for surface_index in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		var surface_weights: Array = weights_by_surface[surface_index] if surface_index < weights_by_surface.size() else []
		for vi in range(vertices.size()):
			var weight: float = 0.0
			var influences: Array = surface_weights[vi] if vi < surface_weights.size() else []
			for influence in influences:
				if int(influence.get("bone",-1)) == bone_index:
					weight = float(influence.get("weight",0.0))
					break
			colors[vi] = _weight_debug_color(weight)
		arrays[Mesh.ARRAY_COLOR] = colors
		# Keep ARRAY_BONES and ARRAY_WEIGHTS intact: the overlay must evaluate
		# through the same Skeleton3D/Skin as the visible artwork.
		debug_mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface_index),arrays)
	var overlay := MeshInstance3D.new()
	overlay.mesh = debug_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 110
	overlay.material_override = mat
	add_child(overlay)
	overlay.transform = mesh_instance.transform
	overlay.skin = mesh_instance.skin
	overlay.skeleton = overlay.get_path_to(skeleton)
	overlay.position += Vector3(0.0,0.0,0.01)
	weight_debug_overlays.append(overlay)
	mesh_instance.visible = false

func clear_weight_debug() -> void:
	for mesh in bound_meshes.values():
		if is_instance_valid(mesh): (mesh as MeshInstance3D).visible = true
	for overlay in weight_debug_overlays:
		if is_instance_valid(overlay): overlay.queue_free()
	weight_debug_overlays.clear()

func _weight_debug_color(weight: float) -> Color:
	var w: float = clampf(weight,0.0,1.0)
	if w <= 0.0: return Color(0.02,0.02,0.03,1.0)
	if w < 0.5: return Color(0.0,w * 2.0,1.0,1.0)
	return Color((w - 0.5) * 2.0,1.0,2.0 - w * 2.0,1.0)

func solve_ik(end_bone: int, target_in_rig: Vector3, chain_length: int = 2, influence: float = 1.0) -> void:
	if rig == null or end_bone < 0 or end_bone >= rig.bones.size(): return
	var chain: Array[int] = []
	var cursor: int = end_bone
	while cursor >= 0 and chain.size() < chain_length:
		chain.append(cursor)
		cursor = int(rig.bones[cursor].get("parent",-1))
	if chain.size() < 2: return
	var tip: Vector3 = _current_bone_tip(end_bone)
	for iteration in range(12):
		for ci in range(1,chain.size()):
			var joint_index: int = chain[ci]
			var joint_global: Transform3D = skeleton.get_bone_global_pose(joint_index)
			var joint: Vector3 = joint_global.origin
			var to_tip := Vector2(tip.x-joint.x,tip.y-joint.y)
			var to_target := Vector2(target_in_rig.x-joint.x,target_in_rig.y-joint.y)
			if to_tip.length_squared() < 0.000001 or to_target.length_squared() < 0.000001: continue
			var angle: float = to_tip.angle_to(to_target) * clampf(influence,0.0,1.0)
			var local_pose: Transform3D = skeleton.get_bone_pose(joint_index)
			local_pose.basis = local_pose.basis.rotated(Vector3(0,0,1),angle)
			skeleton.set_bone_pose(joint_index,local_pose)
			tip = _current_bone_tip(end_bone)
		if Vector2(tip.x-target_in_rig.x,tip.y-target_in_rig.y).length() < 0.002: break

func _current_bone_tip(bone_index: int) -> Vector3:
	for child_index in range(rig.bones.size()):
		if int(rig.bones[child_index].get("parent",-1)) == bone_index:
			return skeleton.get_bone_global_pose(child_index).origin
	var pose_global: Transform3D = skeleton.get_bone_global_pose(bone_index)
	var rest_global: Transform3D = skeleton.get_bone_global_rest(bone_index)
	var rest_tip: Vector3 = _rest_tail_in_rig(bone_index,rest_global.origin)
	return pose_global * (rest_global.affine_inverse() * rest_tip)

func set_bone_pose(index: int, pose: Transform3D) -> void:
	if index < 0 or index >= skeleton.get_bone_count(): return
	skeleton.set_bone_pose(index,pose)

func move_armature(delta: Transform3D) -> void:
	# Moving the armature object is an object-level operation. A skinned mesh is
	# not its child, so mirror the object transform to bound artwork; posing
	# individual bones remains Skeleton3D deformation.
	global_transform = delta
	for mesh in bound_meshes.values():
		if is_instance_valid(mesh): (mesh as MeshInstance3D).global_transform = delta
