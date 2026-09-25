class_name TransformGizmo
extends Node3D

enum Mode { MOVE, ROTATE, SCALE }
var mode := Mode.MOVE
var target: Node3D
var handles: Array[MeshInstance3D] = []
var axis_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	_build()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	return m

func _build() -> void:
	axis_materials = [_mat(Color(0.95,0.2,0.2)), _mat(Color(0.25,0.9,0.35)), _mat(Color(0.25,0.5,1.0))]
	for i in 3:
		var h := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.045,0.045,0.8)
		h.mesh = box
		h.material_override = axis_materials[i]
		add_child(h); handles.append(h)
		if i == 0: h.rotation.z = -PI/2.0; h.position.x = 0.4
		elif i == 1: h.position.y = 0.4
		else: h.rotation.x = PI/2.0; h.position.z = 0.4
	visible = false

func attach(node: Node3D) -> void:
	target = node
	visible = target != null
	_sync()

func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	# Simple universal axes for now; interaction semantics change by mode.
	for h in handles: h.visible = true

func _process(_delta: float) -> void: _sync()

func _sync() -> void:
	if target == null or not is_instance_valid(target): visible = false; return
	global_position = target.global_position
	global_rotation = Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := cam.global_position.distance_to(global_position)
		scale = Vector3.ONE * maxf(0.12, d * 0.12)
