class_name EffectsEngine
extends TextureRect

var glow_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://render/glow_overlay.gdshader")
	material = glow_material

func set_source_texture(source: Texture2D) -> void:
	texture = source

func set_filters(values: Dictionary) -> void:
	if glow_material == null: return
	for key in values:
		glow_material.set_shader_parameter(StringName(key), values[key])
	queue_redraw()
