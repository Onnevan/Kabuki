class_name TransformGizmo
extends Node3D

enum Mode { MOVE, ROTATE, SCALE }
enum Axis { NONE=-1, X=0, Y=1, Z=2, ALL=3 }
var mode := Mode.MOVE
var target: Node3D
var parts: Array[Node3D] = []
var mats: Array[StandardMaterial3D] = []
var active_axis := Axis.NONE

func _ready() -> void:
	mats=[_mat(Color("#ff4d5a")),_mat(Color("#57d47b")),_mat(Color("#4f86ff"))]
	_rebuild(); visible=false

func _mat(c:Color)->StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=c;m.no_depth_test=true;return m
func _mesh(me:Mesh,ma:Material,axis:int)->MeshInstance3D:
	var n:=MeshInstance3D.new();n.mesh=me;n.material_override=ma;n.set_meta("axis",axis);add_child(n);parts.append(n);return n
func _clear()->void:
	for n in parts:
		if is_instance_valid(n):n.queue_free()
	parts.clear()
func _orient(axis:int,n:Node3D)->void:
	if axis==0:n.rotation.z=-PI/2.0
	elif axis==2:n.rotation.x=PI/2.0
func _rebuild()->void:
	_clear()
	if mode==Mode.MOVE:_build_move()
	elif mode==Mode.SCALE:_build_scale()
	else:_build_rotate()
func _build_move()->void:
	var center:=SphereMesh.new();center.radius=.075;center.height=.15
	_mesh(center,_mat(Color("#e8edf3")),Axis.ALL)
	for a in 3:
		var sh:=CylinderMesh.new();sh.top_radius=.014;sh.bottom_radius=.014;sh.height=.68
		var s:=_mesh(sh,mats[a],a);_orient(a,s)
		var co:=CylinderMesh.new();co.top_radius=0.;co.bottom_radius=.065;co.height=.18
		var h:=_mesh(co,mats[a],a);_orient(a,h)
		if a==0:s.position.x=.34;h.position.x=.77
		elif a==1:s.position.y=.34;h.position.y=.77
		else:s.position.z=.34;h.position.z=.77
func _build_scale()->void:
	var center:=BoxMesh.new();center.size=Vector3(.14,.14,.14)
	_mesh(center,_mat(Color("#e8edf3")),Axis.ALL)
	for a in 3:
		var sh:=CylinderMesh.new();sh.top_radius=.014;sh.bottom_radius=.014;sh.height=.68
		var s:=_mesh(sh,mats[a],a);_orient(a,s)
		var bo:=BoxMesh.new();bo.size=Vector3(.115,.115,.115)
		var h:=_mesh(bo,mats[a],a)
		if a==0:s.position.x=.34;h.position.x=.76
		elif a==1:s.position.y=.34;h.position.y=.76
		else:s.position.z=.34;h.position.z=.76
func _build_rotate()->void:
	var center:=SphereMesh.new();center.radius=.07;center.height=.14
	_mesh(center,_mat(Color("#e8edf3")),Axis.ALL)
	for a in 3:
		var t:=TorusMesh.new();t.inner_radius=.47;t.outer_radius=.505;t.rings=64;t.ring_segments=8
		var r:=_mesh(t,mats[a],a)
		if a==0:r.rotation.z=PI/2.
		elif a==2:r.rotation.x=PI/2.
func attach(n:Node3D)->void:target=n;visible=target!=null;_sync()
func set_mode(m:Mode)->void:
	if mode==m:return
	mode=m;_rebuild()
func axis_vector(a:int)->Vector3:
	return [Vector3.RIGHT,Vector3.UP,Vector3.BACK][a] if a>=0 and a<3 else Vector3.ZERO
func pick_axis(mouse:Vector2,camera:Camera3D)->int:
	if target==null:return Axis.NONE
	var origin:=camera.unproject_position(global_position)
	if origin.distance_to(mouse) < 12.0:
		active_axis=Axis.ALL
		return Axis.ALL
	var best:=Axis.NONE;var best_d:=18.0
	if mode==Mode.ROTATE:
		var radius_world:=.5*scale.x
		for a in 3:
			for j in 48:
				var ang:=TAU*float(j)/48.0
				var p:=global_position
				if a==0:p+=Vector3(0,cos(ang),sin(ang))*radius_world
				elif a==1:p+=Vector3(cos(ang),0,sin(ang))*radius_world
				else:p+=Vector3(cos(ang),sin(ang),0)*radius_world
				var d:=camera.unproject_position(p).distance_to(mouse)
				if d<best_d:best_d=d;best=a
	else:
		for a in 3:
			var end:=camera.unproject_position(global_position+axis_vector(a)*.82*scale.x)
			var d:=_point_segment_distance(mouse,origin,end)
			if d<best_d:best_d=d;best=a
	active_axis=best;return best
func _point_segment_distance(p:Vector2,a:Vector2,b:Vector2)->float:
	var ab:=b-a;var den:=ab.length_squared()
	if den<.001:return p.distance_to(a)
	var t:=clampf((p-a).dot(ab)/den,0.,1.);return p.distance_to(a+ab*t)
func _process(_d:float)->void:_sync()
func _sync()->void:
	if target==null or not is_instance_valid(target):visible=false;return
	visible=true;global_position=target.global_position;global_rotation=Vector3.ZERO
	var cam:=get_viewport().get_camera_3d()
	if cam:scale=Vector3.ONE*maxf(.10,cam.global_position.distance_to(global_position)*.105)
