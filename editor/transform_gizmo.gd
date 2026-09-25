class_name TransformGizmo
extends Node3D

enum Mode { MOVE, ROTATE, SCALE }
var mode := Mode.MOVE
var target: Node3D
var parts: Array[Node3D] = []
var mats: Array[StandardMaterial3D] = []

func _ready() -> void:
	mats = [_mat(Color(0.92,0.18,0.20)), _mat(Color(0.24,0.82,0.34)), _mat(Color(0.18,0.46,0.96))]
	_rebuild()
	visible = false

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	return m

func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new(); n.mesh = mesh; n.material_override = mat; add_child(n); parts.append(n); return n

func _clear() -> void:
	for n in parts:
		if is_instance_valid(n): n.queue_free()
	parts.clear()

func _axis_basis(axis: int, n: Node3D) -> void:
	if axis == 0: n.rotation.z = -PI/2.0
	elif axis == 2: n.rotation.x = PI/2.0

func _rebuild() -> void:
	_clear()
	if mode == Mode.MOVE: _build_move()
	elif mode == Mode.SCALE: _build_scale()
	else: _build_rotate()

func _build_move() -> void:
	for axis in 3:
		var shaft := CylinderMesh.new(); shaft.top_radius=0.018; shaft.bottom_radius=0.018; shaft.height=0.72
		var s := _mesh(shaft,mats[axis]); _axis_basis(axis,s)
		if axis==0:s.position.x=0.36
		elif axis==1:s.position.y=0.36
		else:s.position.z=0.36
		var cone:=CylinderMesh.new(); cone.top_radius=0.0; cone.bottom_radius=0.07; cone.height=0.18
		var h:=_mesh(cone,mats[axis]); _axis_basis(axis,h)
		if axis==0:h.position.x=0.81
		elif axis==1:h.position.y=0.81
		else:h.position.z=0.81

func _build_scale() -> void:
	for axis in 3:
		var shaft:=CylinderMesh.new(); shaft.top_radius=0.016; shaft.bottom_radius=0.016; shaft.height=0.72
		var s:=_mesh(shaft,mats[axis]); _axis_basis(axis,s)
		if axis==0:s.position.x=0.36
		elif axis==1:s.position.y=0.36
		else:s.position.z=0.36
		var cube:=BoxMesh.new(); cube.size=Vector3(0.12,0.12,0.12)
		var h:=_mesh(cube,mats[axis])
		if axis==0:h.position.x=0.78
		elif axis==1:h.position.y=0.78
		else:h.position.z=0.78

func _build_rotate() -> void:
	for axis in 3:
		var torus:=TorusMesh.new(); torus.inner_radius=0.47; torus.outer_radius=0.51; torus.rings=64; torus.ring_segments=8
		var r:=_mesh(torus,mats[axis])
		if axis==0:r.rotation.z=PI/2.0
		elif axis==2:r.rotation.x=PI/2.0

func attach(node: Node3D) -> void:
	target=node; visible=target!=null; _sync()

func set_mode(new_mode: Mode) -> void:
	if mode==new_mode:return
	mode=new_mode; _rebuild()

func _process(_delta: float) -> void:_sync()

func _sync() -> void:
	if target==null or not is_instance_valid(target):visible=false;return
	visible=true; global_position=target.global_position; global_rotation=Vector3.ZERO
	var cam:=get_viewport().get_camera_3d()
	if cam:
		var d:=cam.global_position.distance_to(global_position)
		scale=Vector3.ONE*maxf(0.10,d*0.105)
