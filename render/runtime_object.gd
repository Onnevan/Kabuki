class_name RuntimeObject
extends MeshInstance3D

var model: MotionObject
var texture: ImageTexture
var material: ShaderMaterial
var selected := false

func setup(obj: MotionObject, img: Image) -> void:
	model = obj
	mesh = AlphaMeshBuilder.build(img)
	texture = ImageTexture.create_from_image(img)
	material = ShaderMaterial.new()
	material.shader = load("res://render/cutout_material.gdshader")
	material.set_shader_parameter("source_texture", texture)
	material_override = material
	name = obj.name

func set_selected(value: bool) -> void:
	selected = value
	material.set_shader_parameter("selected", 1.0 if value else 0.0)

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
	material.set_shader_parameter("opacity", ProjectStore.evaluate(model.id,"effects.opacity",frame,1.0))
	material.set_shader_parameter("blur", ProjectStore.evaluate(model.id,"effects.blur",frame,0.0))
	material.set_shader_parameter("glow", ProjectStore.evaluate(model.id,"effects.glow",frame,0.0))
	material.set_shader_parameter("exposure", ProjectStore.evaluate(model.id,"effects.exposure",frame,0.0))
	material.set_shader_parameter("saturation", ProjectStore.evaluate(model.id,"effects.saturation",frame,1.0))
