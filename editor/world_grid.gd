class_name WorldGrid
extends MeshInstance3D

func _ready() -> void:
	var im := ImmediateMesh.new()
	mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var extent := 10
	for i in range(-extent, extent + 1):
		var major := i == 0
		var c := Color(0.34,0.36,0.40,0.72) if major else Color(0.20,0.22,0.25,0.48)
		im.surface_set_color(c); im.surface_add_vertex(Vector3(float(i),0,-extent))
		im.surface_set_color(c); im.surface_add_vertex(Vector3(float(i),0,extent))
		im.surface_set_color(c); im.surface_add_vertex(Vector3(-extent,0,float(i)))
		im.surface_set_color(c); im.surface_add_vertex(Vector3(extent,0,float(i)))
	im.surface_end()
