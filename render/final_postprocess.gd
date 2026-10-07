class_name FinalPostProcess
extends TextureRect

const EffectPassShader = preload("res://render/effect_pass.gdshader")

var effect_material: ShaderMaterial
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
var _passes: Array[SubViewport] = []
var _pass_rects: Array[TextureRect] = []
var _pass_effects: Array[String] = []
var _pass_kinds: Array[int] = []
var _pipeline_dirty := true
var _pipeline_host: Node

func _exit_tree() -> void:
	_clear_pipeline()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	effect_material = ShaderMaterial.new()
	effect_material.shader = load("res://render/final_postprocess.gdshader")
	# The display shader is now only the final presentation/mask stage. Actual
	# effects are processed as independent passes in the ordered stack.
	_neutralize_display_material()
	material = effect_material
	call_deferred("_rebuild_pipeline")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree():
		_resize_pipeline()

func _neutralize_display_material() -> void:
	if effect_material == null:
		return
	var neutral := {
		"blur": 0.0,
		"glow_strength": 0.0,
		"glow_threshold": 0.7,
		"glow_radius": 3.0,
		"exposure": 0.0,
		"saturation": 1.0,
		"contrast": 1.0,
		"temperature": 0.0,
		"color_tint": 0.0,
		"vignette": 0.0,
		"chromatic_aberration": 0.0,
		"monochrome": 0.0,
		"noise_amount": 0.0,
		"noise_seed": 0.0,
		"noise_colored": 0.0
	}
	for key in neutral:
		effect_material.set_shader_parameter(StringName(key),neutral[key])

func set_source_texture(source: Texture2D) -> void:
	source_texture = source
	if _pipeline_dirty or _passes.is_empty():
		_rebuild_pipeline()
	else:
		_refresh_pipeline_sources()

func set_filters(values: Dictionary) -> void:
	filter_values = values.duplicate(true)
	_apply_filter_values()
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
	if cleaned == effect_order and not _pipeline_dirty:
		return
	effect_order = cleaned
	_pipeline_dirty = true
	_rebuild_pipeline()

func get_effect_order() -> Array[String]:
	return effect_order.duplicate()

func set_viewport_mask(enabled: bool, control_size: Vector2, radius: float = 16.0) -> void:
	if effect_material == null:
		return
	if material != effect_material:
		material = effect_material
	effect_material.set_shader_parameter("rounded_mask_enabled",1.0 if enabled else 0.0)
	effect_material.set_shader_parameter("rounded_control_size",control_size)
	effect_material.set_shader_parameter("rounded_corner_radius",radius)
	queue_redraw()

func _effect_kind(effect_name: String, blur_vertical: bool = false) -> int:
	match effect_name:
		"blur": return 1 if blur_vertical else 0
		"glow": return 2
		"color": return 3
		"vignette": return 4
		"lens_aberration": return 5
		"monochrome": return 6
		"noise": return 7
		_: return 8

func _clear_pipeline() -> void:
	for pass_viewport in _passes:
		if pass_viewport != null and is_instance_valid(pass_viewport):
			pass_viewport.queue_free()
	_passes.clear()
	_pass_rects.clear()
	_pass_effects.clear()
	_pass_kinds.clear()

func _append_pass(effect_name: String, kind: int) -> void:
	var pass_viewport := SubViewport.new()
	pass_viewport.name = "_FX_" + effect_name + "_" + str(_passes.size())
	pass_viewport.disable_3d = true
	pass_viewport.handle_input_locally = false
	pass_viewport.transparent_bg = false
	pass_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Keep render targets OUTSIDE this TextureRect. Making a viewport whose
	# texture feeds a CanvasItem a child of that same CanvasItem creates a fragile
	# dependency/visibility cycle and can leave the pass texture blank.
	_pipeline_host = get_parent()
	if _pipeline_host == null:
		_pipeline_host = get_tree().current_scene
	_pipeline_host.add_child(pass_viewport)

	var rect := TextureRect.new()
	rect.name = "_Pass"
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = EffectPassShader
	mat.set_shader_parameter("effect_kind",kind)
	if kind == 0:
		mat.set_shader_parameter("blur_direction",Vector2(1.0,0.0))
	elif kind == 1:
		mat.set_shader_parameter("blur_direction",Vector2(0.0,1.0))
	rect.material = mat
	pass_viewport.add_child(rect)

	_passes.append(pass_viewport)
	_pass_rects.append(rect)
	_pass_effects.append(effect_name)
	_pass_kinds.append(kind)

func _rebuild_pipeline() -> void:
	if not is_inside_tree():
		_pipeline_dirty = true
		return
	_clear_pipeline()
	for effect_name in effect_order:
		if effect_name == "blur":
			_append_pass("blur",0)
			_append_pass("blur",1)
		else:
			_append_pass(effect_name,_effect_kind(effect_name))
	_pipeline_dirty = false
	_resize_pipeline()
	_refresh_pipeline_sources()
	_apply_filter_values()

func _pipeline_size() -> Vector2i:
	var sx := maxi(2,int(round(size.x)))
	var sy := maxi(2,int(round(size.y)))
	if source_texture != null:
		var ts := source_texture.get_size()
		if ts.x > 1 and ts.y > 1 and (size.x <= 2.0 or size.y <= 2.0):
			sx = int(ts.x)
			sy = int(ts.y)
	return Vector2i(sx,sy)

func _resize_pipeline() -> void:
	var s := _pipeline_size()
	for i in range(_passes.size()):
		var pass_viewport := _passes[i]
		var rect := _pass_rects[i]
		if pass_viewport == null or rect == null:
			continue
		pass_viewport.size = s
		rect.position = Vector2.ZERO
		rect.size = Vector2(s.x,s.y)
		pass_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _refresh_pipeline_sources() -> void:
	if _passes.is_empty():
		texture = source_texture
		return
	var previous: Texture2D = source_texture
	for i in range(_pass_rects.size()):
		_pass_rects[i].texture = previous
		_passes[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS
		previous = _passes[i].get_texture()
	texture = previous
	queue_redraw()

func _apply_filter_values() -> void:
	for i in range(_pass_rects.size()):
		var rect := _pass_rects[i]
		if rect == null or not rect.material is ShaderMaterial:
			continue
		var mat := rect.material as ShaderMaterial
		for key in filter_values:
			mat.set_shader_parameter(StringName(key),filter_values[key])
	queue_redraw()
