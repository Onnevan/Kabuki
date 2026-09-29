class_name RigRuntime
extends Node3D

var rig: RigData
var skeleton := Skeleton3D.new()
var bone_gizmos: Array[MeshInstance3D] = []
var bound_meshes: Dictionary = {}
var terminal_tip_valid := false
var terminal_tip := Vector3.ZERO

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
		_create_bone_gizmo(i,rest_in_rig.origin,parent_index)

func _create_bone_gizmo(index: int, head: Vector3, parent_index: int) -> void:
	# RigData stores one joint per bone origin. For a chain, bone N runs from
	# joint N to joint N+1; the final bone uses the explicitly tracked terminal tip.
	var tail := head + Vector3(0.0,0.45,0.0)
	if index + 1 < rig.bones.size():
		var next_rest: Transform3D = rig.bones[index + 1].get("rest",Transform3D.IDENTITY)
		tail = (global_transform.affine_inverse() * next_rest).origin
	elif terminal_tip_valid:
		tail = global_transform.affine_inverse() * terminal_tip
	var direction: Vector3 = tail - head
	var length: float = maxf(direction.length(),0.12)
	var radius: float = maxf(0.035,length*0.11)
	# Build the tapered bone directly along its real direction. This avoids the
	# ambiguous Quaternion orientation that could turn a flat 2D bone edge-on.
	var up: Vector3 = direction.normalized()
	var view_axis := Vector3(0,0,1)
	var side: Vector3 = up.cross(view_axis)
	if side.length_squared() < 0.000001: side = up.cross(Vector3.RIGHT)
	side = side.normalized() * radius
	var depth: Vector3 = up.cross(side).normalized() * radius * 0.55
	var verts := PackedVector3Array([
		head - side, head + side, head + depth, head - depth,
		tail
	])
	var indices := PackedInt32Array([
		0,1,4, 1,2,4, 2,3,4, 3,0,4,
		0,3,2, 0,2,1
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var gizmo := MeshInstance3D.new()
	gizmo.name = "_BoneGizmo_%d" % index
	gizmo.mesh = mesh
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

func set_terminal_tip(world_tip: Vector3) -> void:
	terminal_tip = world_tip
	terminal_tip_valid = true
	rebuild_bones()

func bind_mesh(mesh_instance: MeshInstance3D, weights_by_surface: Array) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null or rig == null: return false
	var source: Mesh = mesh_instance.mesh
	var skinned := ArrayMesh.new()
	for surface_index in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
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
	# Once artwork is bound, the armature becomes its spatial owner too.
	# Reparent with keep_global=true so binding never makes the artwork jump.
	if mesh_instance.get_parent() != self:
		mesh_instance.reparent(self,true)
	# Godot builds the Skin bind matrices from the Skeleton rest pose. This is
	# safer than manually composing mesh/skeleton spaces, especially after the
	# artwork has been reparented with keep_global=true.
	var skin: Skin = skeleton.create_skin_from_rest_transforms()
	mesh_instance.skin = skin
	# Skeleton paths are resolved from the MeshInstance. Both nodes currently
	# live under WorldRoot, so this is typically ../Armature/_Skeleton.
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	bound_meshes[mesh_instance.get_instance_id()] = mesh_instance
	return true

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
