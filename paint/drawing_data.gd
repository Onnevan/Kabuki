class_name DrawingData
extends RefCounted

# Canonical, renderer-independent Grease-Pencil-style drawing data.
# Runtime Stroke3D nodes are views of this data, never the source of truth.

var id: String = ""
var object_id: String = ""
var strokes: Dictionary = {}
var stroke_order: Array[String] = []
var exposures: Array[Dictionary] = []
var cel_strokes: Dictionary = {} # local frame -> Array[String], explicit flipbook ownership
var next_stroke_index := 1
# Every Reference Canvas owns a local clip timeline. Scene time maps into it.
var local_frame := 0
var local_duration := 24
var local_playback_start := 0
var local_playback_end := 23
var scene_start := 0
var playback_mode := "loop" # once, loop, ping_pong, hold, reverse
var playback_speed := 1.0

func map_scene_frame(scene_frame: int) -> int:
	var duration: int = maxi(1, local_duration)
	var elapsed: int = maxi(0, scene_frame - scene_start)
	var scaled: int = int(floor(float(elapsed) * playback_speed))
	match playback_mode:
		"loop":
			return scaled % duration
		"ping_pong":
			if duration <= 1: return 0
			var period: int = (duration - 1) * 2
			var phase: int = scaled % period
			return phase if phase < duration else period - phase
		"reverse":
			return maxi(0, duration - 1 - (scaled % duration))
		"hold":
			return mini(scaled, duration - 1)
		"once":
			return mini(scaled, duration - 1)
	return scaled % duration

func set_local_frame(frame: int) -> void:
	local_frame = clampi(frame, 0, maxi(0, local_duration - 1))

func set_local_duration(frames: int) -> void:
	local_duration = maxi(1, frames)
	local_playback_start = clampi(local_playback_start, 0, local_duration - 1)
	local_playback_end = clampi(local_playback_end, local_playback_start, local_duration - 1)
	set_local_frame(local_frame)

func set_local_playback_range(start_frame: int, end_frame: int) -> void:
	local_playback_start = clampi(start_frame, 0, local_duration - 1)
	local_playback_end = clampi(end_frame, local_playback_start, local_duration - 1)

func _init(owner_object_id := "") -> void:
	id = str(ResourceUID.create_id()) + "-" + str(Time.get_ticks_usec())
	object_id = owner_object_id

func add_stroke(points: PackedVector3Array, style: Dictionary = {}) -> String:
	var stroke_id := "stroke_%04d" % next_stroke_index
	next_stroke_index += 1
	strokes[stroke_id] = {
		"id": stroke_id,
		"points": points.duplicate(),
		"radius": float(style.get("radius", 0.012)),
		"color": style.get("color", Color(0.08,0.08,0.08,1.0)),
		"fill_enabled": bool(style.get("fill_enabled", false)),
		"fill_color": style.get("fill_color", Color(0.8,0.25,0.18,0.55)),
		"visible": true
	}
	stroke_order.append(stroke_id)
	return stroke_id

func update_stroke_points(stroke_id: String, points: PackedVector3Array) -> void:
	if strokes.has(stroke_id):
		strokes[stroke_id]["points"] = points.duplicate()

func snapshot_pose(visible_ids: Array[String] = [], force_filter := false) -> Dictionary:
	var pose: Dictionary = {}
	var filter_visibility := force_filter or not visible_ids.is_empty()
	for stroke_id in stroke_order:
		if not strokes.has(stroke_id): continue
		var stroke: Dictionary = strokes[stroke_id]
		pose[stroke_id] = {
			"points": (stroke["points"] as PackedVector3Array).duplicate(),
			"visible": visible_ids.has(stroke_id) if filter_visibility else bool(stroke.get("visible", true))
		}
	return pose

func set_exposure(frame: int, pose: Dictionary, interpolation := "hold") -> void:
	for exposure in exposures:
		if int(exposure["frame"]) == frame:
			exposure["pose"] = pose.duplicate(true)
			exposure["interpolation"] = interpolation
			return
	exposures.append({"frame": frame, "pose": pose.duplicate(true), "interpolation": interpolation})
	exposures.sort_custom(func(a, b): return int(a["frame"]) < int(b["frame"]))

func evaluate_pose(frame: int) -> Dictionary:
	if exposures.is_empty(): return snapshot_pose()
	var left: Dictionary = exposures[0]
	var right: Dictionary = exposures[-1]
	for exposure in exposures:
		if int(exposure["frame"]) <= frame: left = exposure
		if int(exposure["frame"]) >= frame:
			right = exposure
			break
	if int(left["frame"]) == int(right["frame"]) or String(left.get("interpolation","hold")) == "hold":
		return (left["pose"] as Dictionary).duplicate(true)
	var span := float(int(right["frame"]) - int(left["frame"]))
	var t := float(frame - int(left["frame"])) / maxf(span, 1.0)
	return _interpolate_pose(left["pose"], right["pose"], t)

func _interpolate_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var result: Dictionary = {}
	for stroke_id in stroke_order:
		if not a.has(stroke_id) or not b.has(stroke_id):
			result[stroke_id] = (a.get(stroke_id, b.get(stroke_id, {})) as Dictionary).duplicate(true)
			continue
		var sa: Dictionary = a[stroke_id]
		var sb: Dictionary = b[stroke_id]
		var pa: PackedVector3Array = sa.get("points", PackedVector3Array())
		var pb: PackedVector3Array = sb.get("points", PackedVector3Array())
		# Point morphing is valid only while topology matches. Otherwise use exposure semantics.
		if pa.size() != pb.size():
			result[stroke_id] = sa.duplicate(true)
			continue
		var points := PackedVector3Array()
		points.resize(pa.size())
		for i in range(pa.size()): points[i] = pa[i].lerp(pb[i], t)
		result[stroke_id] = {"points": points, "visible": bool(sa.get("visible", true))}
	return result

func exposure_frames() -> Array[int]:
	var result: Array[int] = []
	for exposure in exposures: result.append(int(exposure["frame"]))
	return result

func has_exposure(frame: int) -> bool:
	for exposure in exposures:
		if int(exposure["frame"]) == frame: return true
	return false

func move_exposure(old_frame: int, new_frame: int) -> void:
	var target := clampi(new_frame,0,maxi(0,local_duration-1))
	for exposure in exposures:
		if int(exposure["frame"]) == old_frame:
			exposure["frame"] = target
			break
	if cel_strokes.has(old_frame):
		var members: Array = cel_strokes[old_frame]
		cel_strokes.erase(old_frame)
		cel_strokes[target] = members
	exposures.sort_custom(func(a,b): return int(a["frame"]) < int(b["frame"]))

func copy_exposures(frames: Array[int]) -> Array:
	var result: Array = []
	for frame in frames:
		for exposure in exposures:
			if int(exposure["frame"]) == frame:
				result.append(exposure.duplicate(true))
				break
	return result

func paste_exposures(copied: Array, target_frame: int) -> void:
	if copied.is_empty(): return
	var first := 2147483647
	for exposure in copied: first = mini(first,int(exposure["frame"]))
	for exposure in copied:
		var nf := clampi(target_frame+int(exposure["frame"])-first,0,maxi(0,local_duration-1))
		set_exposure(nf,(exposure["pose"] as Dictionary).duplicate(true),String(exposure.get("interpolation","hold")))

func remove_exposure(frame: int) -> void:
	cel_strokes.erase(frame)
	for i in range(exposures.size() - 1, -1, -1):
		if int(exposures[i]["frame"]) == frame:
			exposures.remove_at(i)
			return

func duplicate_previous_exposure(frame: int) -> bool:
	if exposures.is_empty(): return false
	var source: Dictionary = {}
	for exposure in exposures:
		if int(exposure["frame"]) <= frame: source = exposure
		else: break
	if source.is_empty(): source = exposures[0]
	set_exposure(frame, (source["pose"] as Dictionary).duplicate(true), String(source.get("interpolation","hold")))
	return true

func set_exposure_interpolation(frame: int, interpolation: String) -> void:
	for exposure in exposures:
		if int(exposure["frame"]) == frame:
			exposure["interpolation"] = interpolation
			return

func remove_stroke_from_pose(frame: int, stroke_id: String) -> void:
	var pose := evaluate_pose(frame)
	if pose.has(stroke_id):
		pose[stroke_id]["visible"] = false
	set_exposure(frame, pose, "hold")

func replacement_pose(stroke_id: String) -> Dictionary:
	# Traditional drawing semantics: a newly drawn cel replaces the previous cel.
	var ids: Array[String] = [stroke_id]
	return snapshot_pose(ids, true)

func current_cel_pose(frame: int) -> Dictionary:
	for exposure in exposures:
		if int(exposure["frame"]) == frame:
			return (exposure["pose"] as Dictionary).duplicate(true)
	return {}

func ensure_flipbook_cel(frame: int) -> void:
	if not cel_strokes.has(frame):
		cel_strokes[frame] = []
	if not has_exposure(frame):
		set_exposure(frame, snapshot_pose([], true), "hold")

func add_stroke_to_cel(frame: int, stroke_id: String) -> void:
	# A cel owns a discrete set of strokes. Strokes from other cels can never
	# leak into this frame, regardless of runtime visibility or HOLD evaluation.
	ensure_flipbook_cel(frame)
	var members: Array = cel_strokes[frame]
	if not members.has(stroke_id):
		members.append(stroke_id)
	cel_strokes[frame] = members
	var pose: Dictionary = snapshot_pose([], true)
	for member_id in members:
		var id: String = String(member_id)
		if not strokes.has(id): continue
		var stroke: Dictionary = strokes[id]
		pose[id] = {
			"points": (stroke["points"] as PackedVector3Array).duplicate(),
			"visible": true
		}
	set_exposure(frame, pose, "hold")

func flipbook_pose(frame: int) -> Dictionary:
	# Playback holds the most recent authored cel, but each cel remains discrete.
	if exposures.is_empty(): return {}
	var source_frame: int = -1
	for exposure in exposures:
		var ef: int = int(exposure["frame"])
		if ef <= frame: source_frame = ef
		else: break
	if source_frame < 0: source_frame = int(exposures[0]["frame"])
	if cel_strokes.has(source_frame):
		var pose: Dictionary = snapshot_pose([], true)
		for member_id in cel_strokes[source_frame]:
			var id: String = String(member_id)
			if not strokes.has(id): continue
			var stroke: Dictionary = strokes[id]
			pose[id] = {"points": (stroke["points"] as PackedVector3Array).duplicate(), "visible": true}
		return pose
	return current_cel_pose(source_frame)


func to_dict() -> Dictionary:
	var serialized_strokes: Dictionary = {}
	for stroke_id in strokes:
		var src: Dictionary = strokes[stroke_id]
		var pts: Array = []
		for p in src.get("points", PackedVector3Array()):
			pts.append([p.x,p.y,p.z])
		var rec := src.duplicate(true)
		rec["points"] = pts
		serialized_strokes[stroke_id] = rec
	return {
		"id": id, "object_id": object_id,
		"strokes": serialized_strokes, "stroke_order": stroke_order.duplicate(),
		"exposures": exposures.duplicate(true), "cel_strokes": cel_strokes.duplicate(true),
		"next_stroke_index": next_stroke_index,
		"local_frame": local_frame, "local_duration": local_duration,
		"scene_start": scene_start, "playback_mode": playback_mode,
		"playback_speed": playback_speed
	}

func load_dict(data: Dictionary) -> void:
	id = String(data.get("id", id))
	object_id = String(data.get("object_id", object_id))
	strokes.clear()
	var raw_strokes: Dictionary = data.get("strokes", {})
	for stroke_id in raw_strokes:
		var rec: Dictionary = raw_strokes[stroke_id].duplicate(true)
		var pts := PackedVector3Array()
		for p in rec.get("points", []):
			pts.append(Vector3(float(p[0]),float(p[1]),float(p[2])))
		rec["points"] = pts
		strokes[String(stroke_id)] = rec
	stroke_order.clear()
	for stroke_id in data.get("stroke_order", []): stroke_order.append(String(stroke_id))
	exposures = data.get("exposures", []).duplicate(true)
	cel_strokes = data.get("cel_strokes", {}).duplicate(true)
	next_stroke_index = int(data.get("next_stroke_index", strokes.size()))
	local_frame = int(data.get("local_frame", 0))
	local_duration = int(data.get("local_duration", 24))
	scene_start = int(data.get("scene_start", 0))
	playback_mode = String(data.get("playback_mode", "loop"))
	playback_speed = float(data.get("playback_speed", 1.0))
