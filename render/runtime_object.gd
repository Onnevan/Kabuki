class_name RuntimeObject
extends MeshInstance3D

var model: MotionObject
var texture: ImageTexture
var material: ShaderMaterial

func setup(obj: MotionObject, img: Image) -> void:
	model = obj
	mesh = AlphaMeshBuilder.build(img)
	texture = ImageTexture.create_from_image(img)
	material = ShaderMaterial.new()
	material.shader = load("res://render/cutout_material.gdshader")
	material.set_shader_parameter("source_texture", texture)
	material_override = material
	name = obj.name

func apply_frame(frame: int) -> void:
	position = ProjectStore.evaluate(model.id, "transform.position", frame, position)
	rotation = ProjectStore.evaluate(model.id, "transform.rotation", frame, rotation)
	scale = ProjectStore.evaluate(model.id, "transform.scale", frame, scale)
	material.set_shader_parameter("opacity", ProjectStore.evaluate(model.id,"effects.opacity",frame,1.0))
	material.set_shader_parameter("blur", ProjectStore.evaluate(model.id,"effects.blur",frame,0.0))
	material.set_shader_parameter("glow", ProjectStore.evaluate(model.id,"effects.glow",frame,0.0))
	material.set_shader_parameter("exposure", ProjectStore.evaluate(model.id,"effects.exposure",frame,0.0))
	material.set_shader_parameter("saturation", ProjectStore.evaluate(model.id,"effects.saturation",frame,1.0))
