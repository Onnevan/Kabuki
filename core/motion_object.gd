class_name MotionObject
extends RefCounted

# Stable application-level object. Godot Nodes are only runtime views of this data.
var id: String = ""
var name: String = "Object"
var technical_type: String = "generic"
var role: String = "prop"
var parent_id: String = ""
var tags: Array[String] = []
var transform := Transform3D.IDENTITY
var visible := true
var properties: Dictionary = {}
var components: Dictionary = {}

func _init(object_name := "Object", object_type := "generic", object_role := "prop") -> void:
	id = str(ResourceUID.create_id()) + "-" + str(Time.get_ticks_usec())
	name = object_name
	technical_type = object_type
	role = object_role
	components = {
		"transform": {}, "render": {}, "animation": {}, "hierarchy": {},
		"paint": {}, "effects": {}, "deform": {}, "character": {}
	}

func set_property_path(path: String, value: Variant) -> void:
	properties[path] = value

func get_property_path(path: String, fallback: Variant = null) -> Variant:
	return properties.get(path, fallback)

func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "technical_type": technical_type, "role": role,
		"parent_id": parent_id, "tags": tags, "visible": visible,
		"transform": {
			"origin": [transform.origin.x, transform.origin.y, transform.origin.z],
			"basis": [
				[transform.basis.x.x,transform.basis.x.y,transform.basis.x.z],
				[transform.basis.y.x,transform.basis.y.y,transform.basis.y.z],
				[transform.basis.z.x,transform.basis.z.y,transform.basis.z.z]
			]
		},
		"properties": properties, "components": components
	}


static func from_dict(data: Dictionary) -> MotionObject:
	var obj := MotionObject.new(
		String(data.get("name", "Object")),
		String(data.get("technical_type", "generic")),
		String(data.get("role", "prop"))
	)
	obj.id = String(data.get("id", obj.id))
	obj.parent_id = String(data.get("parent_id", ""))
	obj.visible = bool(data.get("visible", true))
	obj.properties = data.get("properties", {}).duplicate(true)
	obj.components = data.get("components", {}).duplicate(true)
	var raw_tags: Array = data.get("tags", [])
	obj.tags.clear()
	for tag in raw_tags: obj.tags.append(String(tag))
	var tr: Dictionary = data.get("transform", {})
	var origin: Array = tr.get("origin", [0.0,0.0,0.0])
	var basis_rows: Array = tr.get("basis", [])
	var basis := Basis.IDENTITY
	if basis_rows.size() == 3:
		basis = Basis(
			Vector3(float(basis_rows[0][0]),float(basis_rows[0][1]),float(basis_rows[0][2])),
			Vector3(float(basis_rows[1][0]),float(basis_rows[1][1]),float(basis_rows[1][2])),
			Vector3(float(basis_rows[2][0]),float(basis_rows[2][1]),float(basis_rows[2][2]))
		)
	obj.transform = Transform3D(basis, Vector3(float(origin[0]),float(origin[1]),float(origin[2])))
	return obj
