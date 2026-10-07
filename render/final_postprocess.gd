class_name FinalPostProcess
extends TextureRect

var effect_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	effect_material = ShaderMaterial.new()
	effect_material.shader = load("res://render/final_postprocess.gdshader")
	material = effect_material

func set_source_texture(source: Texture2D) -> void:
	texture = source

func set_filters(values: Dictionary) -> void:
	if effect_material == null:
		return
	for key in values:
		effect_material.set_shader_parameter(StringName(key),values[key])
	queue_redraw()

func set_viewport_mask(enabled: bool, control_size: Vector2, radius: float = 16.0) -> void:
	if effect_material == null:
		return
	# Re-assert the post-process material in case an older UI setup replaced the
	# TextureRect material at runtime.
	if material != effect_material:
		material = effect_material
	effect_material.set_shader_parameter("rounded_mask_enabled",1.0 if enabled else 0.0)
	effect_material.set_shader_parameter("rounded_control_size",control_size)
	effect_material.set_shader_parameter("rounded_corner_radius",radius)
	queue_redraw()
