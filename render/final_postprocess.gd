class_name FinalPostProcess
extends TextureRect

const StackPassShader = preload("res://render/compositor_stack_pass.gdshader")
const RoundedViewportShader = preload("res://render/rounded_viewport.gdshader")

var source_texture: Texture2D
var filter_values: Dictionary = {}
var effect_order: Array[String] = [
	"lens_aberration",
	"blur",
	"glow",
	"color",
	"vignette",
	"monochrome",
	"noise"
]

var fx_viewport: SubViewport
var base_rect: TextureRect
var pass_rects: Array[ColorRect] = []
var mask_material: ShaderMaterial
var rounded_mask_enabled := false
var rounded_control_size := Vector2(800.0,600.0)
var rounded_corner_radius := 16.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_create_fx_viewport()
	_rebuild_pipeline()
	_update_output_texture()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree():
		_resize_pipeline()

func _exit_tree() -> void:
	if fx_viewport != null and is_instance_valid(fx_viewport):
		fx_viewport.queue_free()

func _create_fx_viewport() -> void:
	if fx_viewport != null and is_instance_valid(fx_viewport):
		return
	fx_viewport = SubViewport.new()
	fx_viewport.name = "_CompositorStackViewport"
	fx_viewport.disable_3d = true
	fx_viewport.transparent_bg = false
	fx_viewport.handle_input_locally = false
	fx_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	fx_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(fx_viewport)

	base_rect = TextureRect.new()
	base_rect.name = "_Source"
	base_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base_rect.stretch_mode = TextureRect.STRETCH_SCALE
	base_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	base_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_viewport.add_child(base_rect)

func set_source_texture(source: Texture2D) -> void:
	source_texture = source
	if fx_viewport == null or not is_instance_valid(fx_viewport):
		_create_fx_viewport()
	if base_rect != null:
		base_rect.texture = source_texture
	_resize_pipeline()
	_update_output_texture()

func set_filters(values: Dictionary) -> void:
	filter_values = values.duplicate(true)
	_apply_uniforms()
	queue_redraw()

func set_effect_order(order: Array) -> void:
	var cleaned: Array[String] = []
	for value in order:
		var key := String(value)
		if ["lens_aberration","blur","glow","color","vignette","monochrome","noise"].has(key) and not cleaned.has(key):
			cleaned.append(key)
	for fallback in ["lens_aberration","blur","glow","color","vignette","monochrome","noise"]:
		if not cleaned.has(fallback):
			cleaned.append(fallback)
	if cleaned == effect_order and not pass_rects.is_empty():
		return
	effect_order = cleaned
	_rebuild_pipeline()

func get_effect_order() -> Array[String]:
	return effect_order.duplicate()

func set_viewport_mask(enabled: bool, control_size: Vector2, radius: float = 16.0) -> void:
	rounded_mask_enabled = enabled
	rounded_control_size = control_size
	rounded_corner_radius = radius
	if rounded_mask_enabled:
		if mask_material == null:
			mask_material = ShaderMaterial.new()
			mask_material.shader = RoundedViewportShader
		material = mask_material
		mask_material.set_shader_parameter("control_size",rounded_control_size)
		mask_material.set_shader_parameter("corner_radius",rounded_corner_radius)
	else:
		material = null
	queue_redraw()

func _clear_pass_nodes() -> void:
	if fx_viewport == null:
		return
	for child in fx_viewport.get_children():
		if child == base_rect:
			continue
		child.queue_free()
	pass_rects.clear()

func _append_effect_pass(effect_id: String, kind: int, blur_direction := Vector2(1.0,0.0)) -> void:
	var copy := BackBufferCopy.new()
	copy.name = "_Copy_" + effect_id + "_" + str(pass_rects.size())
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	fx_viewport.add_child(copy)

	var rect := ColorRect.new()
	rect.name = "_FX_" + effect_id + "_" + str(pass_rects.size())
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = StackPassShader
	mat.set_shader_parameter("effect_kind",kind)
	mat.set_shader_parameter("blur_direction",blur_direction)
	rect.material = mat
	fx_viewport.add_child(rect)
	pass_rects.append(rect)

func _rebuild_pipeline() -> void:
	if not is_inside_tree():
		return
	if fx_viewport == null or not is_instance_valid(fx_viewport):
		_create_fx_viewport()
	_clear_pass_nodes()
	for effect_id in effect_order:
		match effect_id:
			"lens_aberration":
				_append_effect_pass(effect_id,0)
			"blur":
				_append_effect_pass("blur_h",1,Vector2(1.0,0.0))
				_append_effect_pass("blur_v",2,Vector2(0.0,1.0))
			"glow":
				_append_effect_pass(effect_id,3)
			"color":
				_append_effect_pass(effect_id,4)
			"vignette":
				_append_effect_pass(effect_id,5)
			"monochrome":
				_append_effect_pass(effect_id,6)
			"noise":
				_append_effect_pass(effect_id,7)
	_resize_pipeline()
	_apply_uniforms()
	_update_output_texture()

func _pipeline_size() -> Vector2i:
	var sx := maxi(2,int(round(size.x)))
	var sy := maxi(2,int(round(size.y)))
	if source_texture != null and (sx <= 2 or sy <= 2):
		var source_size := source_texture.get_size()
		if source_size.x > 1 and source_size.y > 1:
			sx = int(source_size.x)
			sy = int(source_size.y)
	return Vector2i(sx,sy)

func _resize_pipeline() -> void:
	if fx_viewport == null or not is_instance_valid(fx_viewport):
		return
	var s := _pipeline_size()
	fx_viewport.size = s
	if base_rect != null:
		base_rect.position = Vector2.ZERO
		base_rect.size = Vector2(s.x,s.y)
	for rect in pass_rects:
		if rect == null or not is_instance_valid(rect):
			continue
		rect.position = Vector2.ZERO
		rect.size = Vector2(s.x,s.y)
	if rounded_mask_enabled and mask_material != null:
		rounded_control_size = Vector2(size.x,size.y)
		mask_material.set_shader_parameter("control_size",rounded_control_size)
		mask_material.set_shader_parameter("corner_radius",rounded_corner_radius)

func _apply_uniforms() -> void:
	for rect in pass_rects:
		if rect == null or not is_instance_valid(rect) or not rect.material is ShaderMaterial:
			continue
		var mat := rect.material as ShaderMaterial
		for key in filter_values:
			mat.set_shader_parameter(StringName(key),filter_values[key])
	queue_redraw()

func _update_output_texture() -> void:
	if fx_viewport == null or not is_instance_valid(fx_viewport):
		texture = source_texture
		return
	texture = fx_viewport.get_texture()
	queue_redraw()
