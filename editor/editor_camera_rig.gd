class_name EditorCameraRig
extends Node3D

var camera: Camera3D
var pivot := Vector3.ZERO
var distance := 3.0
var yaw := 0.0
var pitch := 0.0

func setup(cam: Camera3D) -> void:
	camera = cam
	pivot = Vector3.ZERO
	distance = cam.position.length()
	_update_camera()

func orbit(delta: Vector2) -> void:
	yaw -= delta.x * 0.007
	pitch = clampf(pitch - delta.y * 0.007, -1.52, 1.52)
	_update_camera()

func pan(delta: Vector2) -> void:
	if camera == null: return
	var factor := distance * 0.0015
	pivot += camera.global_transform.basis.x * (-delta.x * factor)
	pivot += camera.global_transform.basis.y * (delta.y * factor)
	_update_camera()

func zoom(amount: float) -> void:
	distance = clampf(distance * (1.0 + amount * 0.1), 0.25, 100.0)
	_update_camera()

func frame_target(pos: Vector3) -> void:
	pivot = pos
	_update_camera()

func _update_camera() -> void:
	if camera == null: return
	var q := Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
	var offset := q * Vector3(0,0,distance)
	camera.global_position = pivot + offset
	camera.look_at(pivot, Vector3.UP)
