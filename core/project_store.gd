extends Node

const FORMAT_VERSION := 1
var fps := 24
var duration_frames := 120
var current_frame := 0
var objects: Dictionary = {}
var channels: Dictionary = {}

signal frame_changed(frame: int)
signal object_added(object_id: String)
signal project_changed
signal key_changed(object_id: String, property_path: String, frame: int)

func add_object(obj: MotionObject) -> void:
	objects[obj.id] = obj
	object_added.emit(obj.id)
	project_changed.emit()

func set_frame(frame: int) -> void:
	current_frame = clampi(frame, 0, duration_frames)
	frame_changed.emit(current_frame)

func channel_key(object_id: String, property_path: String) -> String:
	return object_id + "::" + property_path

func set_key(object_id: String, property_path: String, frame: int, value: Variant, interpolation := "linear") -> void:
	var key := channel_key(object_id, property_path)
	if not channels.has(key): channels[key] = []
	var arr: Array = channels[key]
	for k in arr:
		if k.frame == frame:
			k.value = value; k.interpolation = interpolation; key_changed.emit(object_id, property_path, frame); project_changed.emit(); return
	arr.append({"frame": frame, "value": value, "interpolation": interpolation})
	arr.sort_custom(func(a, b): return a.frame < b.frame)
	key_changed.emit(object_id, property_path, frame)
	project_changed.emit()

func evaluate(object_id: String, property_path: String, frame: int, fallback: Variant) -> Variant:
	var arr: Array = channels.get(channel_key(object_id, property_path), [])
	if arr.is_empty(): return fallback
	var left = arr[0]
	var right = arr[-1]
	for k in arr:
		if k.frame <= frame: left = k
		if k.frame >= frame: right = k; break
	if left.frame == right.frame or left.interpolation == "hold": return left.value
	var t := float(frame - left.frame) / float(right.frame - left.frame)
	if left.interpolation == "ease": t = t * t * (3.0 - 2.0 * t)
	return _lerp_variant(left.value, right.value, t)

func _lerp_variant(a: Variant, b: Variant, t: float) -> Variant:
	if a is Vector3 and b is Vector3: return a.lerp(b, t)
	if a is float or a is int: return lerpf(float(a), float(b), t)
	return a

func get_key_frames(object_id: String, property_path: String) -> Array[int]:
	var result: Array[int] = []
	var arr: Array = channels.get(channel_key(object_id, property_path), [])
	for k in arr:
		result.append(int(k.frame))
	return result
