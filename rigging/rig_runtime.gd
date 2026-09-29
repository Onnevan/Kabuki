class_name RigRuntime
extends Node3D

var rig: RigData
var skeleton := Skeleton3D.new()
var bone_gizmos: Array[MeshInstance3D] = []
var bound_meshes: Dictionary = {}

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
		var rest_local: Transform3D = global_transform.affine_inverse() * rest_global
		skeleton.set_bone_rest(i,rest_local)
		_create_bone_gizmo(i,rest_local.origin,parent_index)

func _create_bone_gizmo(index: int, head: Vector3, parent_index: int) -> void:
	var tail := head + Vector3(0.0,0.45,0.0)
	if parent_index >= 0 and parent_index < rig.bones.size():
		var parent_rest: Transform3D = rig.bones[parent_index].get("rest",Transform3D.IDENTITY)
		var parent_local: Vector3 = (global_transform.affine_inverse() * parent_rest).origin
		if not parent_local.is_equal_approx(head): tail = parent_local
	var direction: Vector3 = tail - head
	var length: float = maxf(direction.length(),0.12)
	# Tapered bone: broad at the parent/root end, narrow at the tip. This makes
	# chain direction immediately readable without technical bone widgets.
	var radius: float = maxf(0.035,length*0.11)
	var verts := PackedVector3Array([
		Vector3(-radius,0,0), Vector3(radius,0,0), Vector3(0,0,radius),
		Vector3(0,length,0)
	])
	var indices := PackedInt32Array([
		0,1,3, 1,2,3, 2,0,3, 0,2,1
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
	mat.albedo_color = Color(0.95,0.62,0.12,0.9)
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gizmo.material_override = mat
	gizmo.position = head
	if direction.length_squared() > 0.000001:
		gizmo.quaternion = Quaternion(Vector3.UP,direction.normalized())
	add_child(gizmo)
	bone_gizmos.append(gizmo)

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
	var skin := Skin.new()
	for i in range(rig.bones.size()):
		skin.add_bind(i,skeleton.get_bone_rest(i).affine_inverse())
	mesh_instance.skin = skin
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	bound_meshes[mesh_instance.get_instance_id()] = mesh_instance
	return true

func set_bone_pose(index: int, pose: Transform3D) -> void:
	if index < 0 or index >= skeleton.get_bone_count(): return
	skeleton.set_bone_pose(index,pose)
