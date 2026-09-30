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
	# Channels are kept sorted. Binary search avoids scanning every key for
	# every animated property on every playback frame.
	var lo: int = 0
	var hi: int = arr.size() - 1
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		var mf: int = int(arr[mid].frame)
		if mf <= frame:
			left = arr[mid]
			lo = mid + 1
		else:
			right = arr[mid]
			hi = mid - 1
	if int(left.frame) < frame and lo < arr.size(): right = arr[lo]
	elif int(left.frame) >= frame: right = left
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
	if a is Vector3 and b is Vector3: return a.lerp(b,t)
	if a is Transform3D and b is Transform3D:
		var ta: Transform3D = a
		var tb: Transform3D = b
		var qa: Quaternion = ta.basis.get_rotation_quaternion()
		var qb: Quaternion = tb.basis.get_rotation_quaternion()
		var scale: Vector3 = ta.basis.get_scale().lerp(tb.basis.get_scale(),t)
		var rotation: Quaternion = qa.slerp(qb,t)
		return Transform3D(Basis(rotation).scaled(scale),ta.origin.lerp(tb.origin,t))
	if a is Color and b is Color: return a.lerp(b,t)
	if a is Vector2 and b is Vector2: return a.lerp(b,t)
	if a is float or a is int: return lerpf(float(a),float(b),t)
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

func get_object_key_frames(object_id: String) -> Array[int]:
	var seen: Dictionary = {}
	for key in channels:
		var prefix := object_id + "::"
		if not String(key).begins_with(prefix): continue
		for k in channels[key]:
			seen[int(k.frame)] = true
	var result: Array[int] = []
	for frame in seen.keys(): result.append(int(frame))
	result.sort()
	return result

func delete_key(object_id: String, property_path: String, frame: int) -> void:
	var key := channel_key(object_id, property_path)
	if not channels.has(key): return
	var arr: Array = channels[key]
	for i in range(arr.size()-1,-1,-1):
		if int(arr[i].frame) == frame: arr.remove_at(i)
	key_changed.emit(object_id,property_path,frame); project_changed.emit()

func move_object_keys_at_frame(object_id: String, old_frame: int, new_frame: int) -> void:
	var prefix := object_id + "::"
	var target := clampi(new_frame,0,duration_frames)
	for key in channels:
		if not String(key).begins_with(prefix): continue
		var arr: Array = channels[key]
		for k in arr:
			if int(k.frame) == old_frame: k.frame = target
		arr.sort_custom(func(a,b): return int(a.frame) < int(b.frame))
	key_changed.emit(object_id,"*",target); project_changed.emit()

func copy_keys(object_id: String, refs: Array) -> Array:
	var result: Array = []
	for ref in refs:
		var path := String(ref.get("path",""))
		var frame := int(ref.get("frame",-1))
		if path == "*":
			var prefix := object_id + "::"
			for key in channels:
				if not String(key).begins_with(prefix): continue
				var property_path := String(key).trim_prefix(prefix)
				for k in channels[key]:
					if int(k.frame) == frame:
						result.append({"path":property_path,"frame":frame,"value":k.value,"interpolation":k.interpolation})
		else:
			for k in get_keys(object_id,path):
				if int(k.frame) == frame:
					result.append({"path":path,"frame":frame,"value":k.value,"interpolation":k.interpolation})
	return result

func paste_keys(object_id: String, copied: Array, target_frame: int) -> void:
	if copied.is_empty(): return
	var min_frame := 2147483647
	for item in copied: min_frame = mini(min_frame,int(item.frame))
	for item in copied:
		var frame := target_frame + int(item.frame) - min_frame
		set_key(object_id,String(item.path),clampi(frame,0,duration_frames),item.value,String(item.interpolation))

func set_key_interpolation(object_id: String, property_path: String, frame: int, interpolation: String) -> void:
	var arr: Array = channels.get(channel_key(object_id, property_path), [])
	for k in arr:
		if int(k.frame) == frame:
			k.interpolation = interpolation
			key_changed.emit(object_id, property_path, frame)
			project_changed.emit()
			return


func clear_project() -> void:
	objects.clear()
	channels.clear()
	current_frame = 0
	project_changed.emit()
	frame_changed.emit(current_frame)

func to_dict() -> Dictionary:
	var serialized_objects: Array = []
	for object_id in objects:
		var obj: MotionObject = objects[object_id]
		serialized_objects.append(obj.to_dict())
	return {
		"format": "kabuki_project",
		"version": FORMAT_VERSION,
		"fps": fps,
		"duration_frames": duration_frames,
		"current_frame": current_frame,
		"objects": serialized_objects,
		"channels": channels.duplicate(true)
	}

func load_dict(data: Dictionary) -> bool:
	if String(data.get("format", "")) != "kabuki_project": return false
	var version: int = int(data.get("version", 0))
	if version < 1 or version > FORMAT_VERSION: return false
	objects.clear()
	channels = data.get("channels", {}).duplicate(true)
	fps = int(data.get("fps", 24))
	duration_frames = int(data.get("duration_frames", 120))
	current_frame = clampi(int(data.get("current_frame", 0)), 0, duration_frames)
	for raw in data.get("objects", []):
		var obj := MotionObject.from_dict(raw)
		objects[obj.id] = obj
	project_changed.emit()
	frame_changed.emit(current_frame)
	return true
