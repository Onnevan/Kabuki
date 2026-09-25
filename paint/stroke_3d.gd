class_name Stroke3DData
extends RefCounted

# Native core primitive reserved for the Paint Engine.
var id := str(ResourceUID.create_id())
var points: Array[Dictionary] = [] # position, pressure, tilt, time, optional SurfaceBinding
var width := 0.01
var color := Color.WHITE
var opacity := 1.0
var texture_id := ""
var profile := "ribbon" # ribbon, round, flat, textured
var closed := false

func add_point(position: Vector3, pressure := 1.0, tilt := Vector2.ZERO, timestamp := 0.0, binding := {}) -> void:
	points.append({"position":position,"pressure":pressure,"tilt":tilt,"time":timestamp,"binding":binding})
