class_name EffectsEngine
extends Control

var glow_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://render/glow_overlay.gdshader")
	material = glow_material
	set_process(false)

func set_filters(values: Dictionary) -> void:
	if glow_material == null: return
	for key in values:
		glow_material.set_shader_parameter(StringName(key), values[key])
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
