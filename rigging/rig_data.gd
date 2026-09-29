class_name RigData
extends RefCounted

var id: String = ""
var bones: Array[Dictionary] = []
var bindings: Dictionary = {} # object id -> {bone_weights:Array, auto_bound:bool}

func _init(rig_id: String = "") -> void:
	id = rig_id

func add_bone(name: String, parent_index: int = -1, rest: Transform3D = Transform3D.IDENTITY) -> int:
	bones.append({"name": name, "parent": parent_index, "rest": rest})
	return bones.size() - 1

func to_dict() -> Dictionary:
	return {"id": id, "bones": bones.duplicate(true), "bindings": bindings.duplicate(true)}
