class_name EffectsEngine
extends ColorRect

var effect_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	effect_material = ShaderMaterial.new()
	effect_material.shader = load("res://render/glow_overlay.gdshader")
	material = effect_material

func set_source_texture(source: Texture2D) -> void:
	if effect_material == null: return
	effect_material.set_shader_parameter("source_texture",source)
	if source != null:
		var texture_size := source.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			effect_material.set_shader_parameter(
				"source_pixel_size",
				Vector2(1.0/texture_size.x,1.0/texture_size.y)
			)

func set_filters(values: Dictionary) -> void:
	if effect_material == null: return
	for key in values:
		effect_material.set_shader_parameter(StringName(key),values[key])
	queue_redraw()
