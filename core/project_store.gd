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
	var t: float = float(frame - left.frame) / float(right.frame - left.frame)
	t = _apply_interpolation(t, String(left.interpolation))
	return _lerp_variant(left.value, right.value, t)

func _apply_interpolation(t: float, mode: String) -> float:
	t = clampf(t, 0.0, 1.0)
	match mode:
		"constant", "hold":
			return 0.0
		"linear":
			return t
		"bezier", "ease":
			return t * t * (3.0 - 2.0 * t)
		"quadratic_in":
			return t * t
		"quadratic_out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"quadratic_in_out":
			return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
		"cubic_in_out":
			return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
		"back":
			var c1: float = 1.70158
			var c3: float = c1 + 1.0
			return c3 * t * t * t - c1 * t * t
		"bounce":
			return _bounce_out(t)
		"elastic":
			if is_zero_approx(t) or is_equal_approx(t, 1.0): return t
			var c4: float = (2.0 * PI) / 3.0
			return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0
		_:
			return t

func _bounce_out(t: float) -> float:
	var n1: float = 7.5625
	var d1: float = 2.75
	if t < 1.0 / d1:
		return n1 * t * t
	elif t < 2.0 / d1:
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elif t < 2.5 / d1:
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	t -= 2.625 / d1
	return n1 * t * t + 0.984375

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

func get_keys(object_id: String, property_path: String) -> Array:
	return channels.get(channel_key(object_id, property_path), [])

func move_key(object_id: String, property_path: String, old_frame: int, new_frame: int) -> void:
	var arr: Array = channels.get(channel_key(object_id, property_path), [])
	for k in arr:
		if int(k.frame) == old_frame:
			k.frame = clampi(new_frame, 0, duration_frames)
			break
	arr.sort_custom(func(a, b): return a.frame < b.frame)
	key_changed.emit(object_id, property_path, new_frame)
	project_changed.emit()

func set_key_interpolation(object_id: String, property_path: String, frame: int, interpolation: String) -> void:
	var arr: Array = channels.get(channel_key(object_id, property_path), [])
	for k in arr:
		if int(k.frame) == frame:
			k.interpolation = interpolation
			key_changed.emit(object_id, property_path, frame)
			project_changed.emit()
			return
