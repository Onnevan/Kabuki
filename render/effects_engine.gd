class_name EffectsEngine
extends Control

var stack: Array[Dictionary] = [
	{"id":"glow", "enabled":true, "strength":0.0, "threshold":0.7, "radius":3.0}
]
var glow_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://render/glow_overlay.gdshader")
	material = glow_material
	_sync()

func set_glow(strength: float, threshold: float, radius: float) -> void:
	stack[0].strength = strength
	stack[0].threshold = threshold
	stack[0].radius = radius
	_sync()

func set_effect_enabled(id: String, enabled: bool) -> void:
	for effect in stack:
		if effect.id == id:
			effect.enabled = enabled
			break
	_sync()

func _sync() -> void:
	if glow_material == null: return
	var effect: Dictionary = stack[0]
	glow_material.set_shader_parameter("strength", float(effect.strength) if bool(effect.enabled) else 0.0)
	glow_material.set_shader_parameter("threshold", float(effect.threshold))
	glow_material.set_shader_parameter("radius", float(effect.radius))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
