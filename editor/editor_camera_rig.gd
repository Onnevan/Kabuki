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


func align_axis(axis: Vector3, up := Vector3.UP) -> void:
	if camera == null: return
	var dir := axis.normalized()
	camera.global_position = pivot + dir * distance
	var safe_up := up
	if absf(dir.dot(safe_up)) > 0.98:
		safe_up = Vector3(0,0,-1)
	camera.look_at(pivot, safe_up)
	_sync_angles_from_camera()

func align_transform(view_transform: Transform3D) -> void:
	if camera == null: return
	# Preserve editor orbit distance but restore the saved view direction.
	var forward := -view_transform.basis.z.normalized()
	var up := view_transform.basis.y.normalized()
	camera.global_position = pivot - forward * distance
	camera.look_at(pivot, up)
	_sync_angles_from_camera()

func _sync_angles_from_camera() -> void:
	var offset := camera.global_position - pivot
	if offset.length_squared() < 0.000001: return
	var dir := offset.normalized()
	yaw = atan2(dir.x, dir.z)
	pitch = asin(clampf(dir.y, -1.0, 1.0))


func get_state() -> Dictionary:
	return {
		"pivot": pivot,
		"distance": distance,
		"yaw": yaw,
		"pitch": pitch
	}

func set_state(state: Dictionary) -> void:
	pivot = state.get("pivot", pivot)
	distance = float(state.get("distance", distance))
	yaw = float(state.get("yaw", yaw))
	pitch = float(state.get("pitch", pitch))
	_update_camera()


func sync_from_camera_transform(value: Transform3D) -> void:
	if camera == null: return
	camera.global_transform = value
	var forward := -value.basis.z.normalized()
	pivot = value.origin + forward * distance
	_sync_angles_from_camera()
