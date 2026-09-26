class_name RuntimeObject
extends MeshInstance3D

var model: MotionObject
var texture: ImageTexture
var material: ShaderMaterial
var standard_material: StandardMaterial3D
var selected := false
var supports_effects := true

func setup(obj: MotionObject, img: Image) -> void:
	model = obj
	mesh = AlphaMeshBuilder.build(img)
	texture = ImageTexture.create_from_image(img)
	material = ShaderMaterial.new()
	material.shader = load("res://render/cutout_material.gdshader")
	material.set_shader_parameter("source_texture", texture)
	material.set_shader_parameter("tint", Color.WHITE)
	material.set_shader_parameter("roughness", 0.8)
	material.set_shader_parameter("metallic", 0.0)
	material.set_shader_parameter("two_sided", true)
	material_override = material
	name = obj.name

func setup_plane(obj: MotionObject) -> void:
	model = obj
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.0)
	mesh = plane
	standard_material = StandardMaterial3D.new()
	standard_material.albedo_color = Color(0.72, 0.76, 0.82, 1.0)
	standard_material.roughness = 0.8
	standard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = standard_material
	supports_effects = false
	name = obj.name

func set_selected(value: bool) -> void:
	selected = value
	if material:
		material.set_shader_parameter("selected", 1.0 if value else 0.0)

func set_material_color(value: Color) -> void:
	if material: material.set_shader_parameter("tint", value)
	elif standard_material: standard_material.albedo_color = value

func set_material_roughness(value: float) -> void:
	if material: material.set_shader_parameter("roughness", value)
	elif standard_material: standard_material.roughness = value

func set_material_metallic(value: float) -> void:
	if material: material.set_shader_parameter("metallic", value)
	elif standard_material: standard_material.metallic = value

func set_material_two_sided(enabled: bool) -> void:
	if material:
		material.set_shader_parameter("two_sided", enabled)
	elif standard_material:
		standard_material.cull_mode = BaseMaterial3D.CULL_DISABLED if enabled else BaseMaterial3D.CULL_BACK

func get_material_color() -> Color:
	if material:
		var value = material.get_shader_parameter("tint")
		return value as Color if value is Color else Color.WHITE
	if standard_material: return standard_material.albedo_color
	return Color.WHITE

func get_material_roughness() -> float:
	if material:
		var value = material.get_shader_parameter("roughness")
		return float(value) if value != null else 0.8
	if standard_material: return standard_material.roughness
	return 0.8

func get_material_metallic() -> float:
	if material:
		var value = material.get_shader_parameter("metallic")
		return float(value) if value != null else 0.0
	if standard_material: return standard_material.metallic
	return 0.0

func screen_radius(camera: Camera3D, viewport_size: Vector2i) -> float:
	if mesh == null: return 30.0
	var size := mesh.get_aabb().size
	var center := camera.unproject_position(global_position)
	var edge := camera.unproject_position(global_position + Vector3(maxf(size.x, size.y) * 0.5, 0, 0))
	return maxf(20.0, center.distance_to(edge))

func apply_frame(frame: int) -> void:
	position = ProjectStore.evaluate(model.id, "transform.position", frame, model.transform.origin)
	rotation = ProjectStore.evaluate(model.id, "transform.rotation", frame, rotation)
	scale = ProjectStore.evaluate(model.id, "transform.scale", frame, scale)
	if material == null or not supports_effects: return
	material.set_shader_parameter("opacity", ProjectStore.evaluate(model.id,"effects.opacity",frame,1.0))
	material.set_shader_parameter("blur", ProjectStore.evaluate(model.id,"effects.blur",frame,0.0))
	material.set_shader_parameter("glow", ProjectStore.evaluate(model.id,"effects.glow",frame,0.0))
	material.set_shader_parameter("exposure", ProjectStore.evaluate(model.id,"effects.exposure",frame,0.0))
	material.set_shader_parameter("saturation", ProjectStore.evaluate(model.id,"effects.saturation",frame,1.0))
