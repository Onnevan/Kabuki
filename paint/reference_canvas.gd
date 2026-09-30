class_name ReferenceCanvas
extends Node3D

# Spatial drawing coordinate system. This is deliberately NOT render geometry.
# Children (strokes, bitmap layers, etc.) live in local XY coordinates.
var model: MotionObject
var guide: MeshInstance3D
var guide_size := Vector2(1.6, 1.0)
var guide_visible := true
var flipbook_preview: MeshInstance3D
var flipbook_texture: ImageTexture
var flipbook_source_image: Image

func setup(obj: MotionObject) -> void:
	model = obj
	name = obj.name
	_build_guide()

func _build_guide() -> void:
	guide = MeshInstance3D.new()
	guide.name = "_ReferenceCanvasGuide"
	guide.mesh = _guide_mesh(guide_size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.20, 0.72, 1.0, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	guide.material_override = mat
	guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(guide)

func _guide_mesh(size: Vector2) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var vertices := PackedVector3Array([
		Vector3(-hx,-hy,0), Vector3(hx,-hy,0),
		Vector3(hx,-hy,0), Vector3(hx,hy,0),
		Vector3(hx,hy,0), Vector3(-hx,hy,0),
		Vector3(-hx,hy,0), Vector3(-hx,-hy,0),
		Vector3(-0.08,0,0), Vector3(0.08,0,0),
		Vector3(0,-0.08,0), Vector3(0,0.08,0)
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return result

func set_guide_visible(value: bool) -> void:
	guide_visible = value
	if guide: guide.visible = value

func content_bounds() -> AABB:
	var result := AABB()
	var first := true
	for child in get_children():
		if child == guide or not child is VisualInstance3D: continue
		var visual := child as VisualInstance3D
		if not visual.visible: continue
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var local_box := (child as MeshInstance3D).mesh.get_aabb()
			# Godot 4 removed AABB.transformed(). Transform the 8 corners into
			# reference-canvas local space and rebuild the enclosing AABB.
			var box := AABB(child.transform * local_box.get_endpoint(0), Vector3.ZERO)
			for corner in range(1, 8):
				box = box.expand(child.transform * local_box.get_endpoint(corner))
			result = box if first else result.merge(box)
			first = false
	return AABB(Vector3(-guide_size.x*.5,-guide_size.y*.5,0),Vector3(guide_size.x,guide_size.y,0.001)) if first else result


func show_flipbook_image(image: Image) -> void:
	if image == null or image.is_empty():
		if flipbook_preview: flipbook_preview.visible = false
		return
	if flipbook_preview == null:
		flipbook_preview = MeshInstance3D.new()
		flipbook_preview.name = "_BitmapFlipbook"
		# QuadMesh UV orientation is opposite to Control/Image coordinates.
		# Build the preview explicitly so drawings keep the same top/bottom
		# orientation in Drawing, Scene, Animation and Rigging.
		var hx: float = guide_size.x * 0.5
		var hy: float = guide_size.y * 0.5
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-hx, hy,0), Vector3(hx, hy,0), Vector3(hx,-hy,0),
			Vector3(-hx, hy,0), Vector3(hx,-hy,0), Vector3(-hx,-hy,0)
		])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
			Vector2(0,0),Vector2(1,0),Vector2(1,1),
			Vector2(0,0),Vector2(1,1),Vector2(0,1)
		])
		var quad := ArrayMesh.new()
		quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		flipbook_preview.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		flipbook_preview.material_override = mat
		flipbook_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flipbook_preview)
	# HOLD frames call this repeatedly with the exact same Image resource.
	# Avoid re-uploading unchanged pixels to the GPU every animation frame.
	if flipbook_source_image != image:
		flipbook_source_image = image
		if flipbook_texture == null:
			flipbook_texture = ImageTexture.create_from_image(image)
		else:
			if flipbook_texture.get_width() == image.get_width() and flipbook_texture.get_height() == image.get_height():
				flipbook_texture.update(image)
			else:
				flipbook_texture = ImageTexture.create_from_image(image)
	var material := flipbook_preview.material_override as StandardMaterial3D
	material.albedo_texture = flipbook_texture
	flipbook_preview.visible = true

func hide_flipbook_image() -> void:
	if flipbook_preview: flipbook_preview.visible = false
