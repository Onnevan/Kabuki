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
		"transform": {"origin": [transform.origin.x, transform.origin.y, transform.origin.z]},
		"properties": properties, "components": components
	}
