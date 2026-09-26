class_name DrawingData
extends RefCounted

# Canonical, renderer-independent Grease-Pencil-style drawing data.
# Runtime Stroke3D nodes are views of this data, never the source of truth.

var id: String = ""
var object_id: String = ""
var strokes: Dictionary = {}
var stroke_order: Array[String] = []
var exposures: Array[Dictionary] = []
var next_stroke_index := 1

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

func snapshot_pose() -> Dictionary:
	var pose: Dictionary = {}
	for stroke_id in stroke_order:
		if not strokes.has(stroke_id): continue
		var stroke: Dictionary = strokes[stroke_id]
		pose[stroke_id] = {
			"points": (stroke["points"] as PackedVector3Array).duplicate(),
			"visible": bool(stroke.get("visible", true))
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
