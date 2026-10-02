class_name EffectsEngine
extends TextureRect

var effect_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	effect_material = ShaderMaterial.new()
	effect_material.shader = load("res://render/glow_overlay.gdshader")
	material = effect_material

func set_source_texture(source: Texture2D) -> void:
	texture = source

func set_filters(values: Dictionary) -> void:
	if effect_material == null: return
	for key in values:
		effect_material.set_shader_parameter(StringName(key),values[key])
	queue_redraw()
