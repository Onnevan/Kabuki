class_name SceneObjectController
extends RefCounted

# One authoritative scene/object index shared by every editor workspace.
var nodes: Dictionary = {} # object id -> Node3D

func register(obj: MotionObject, node: Node3D) -> void:
	ProjectStore.add_object(obj)
	nodes[obj.id] = node
	node.name = obj.name

func unregister(object_id: String) -> void:
	nodes.erase(object_id)
	ProjectStore.objects.erase(object_id)

func node(object_id: String) -> Node3D:
	return nodes.get(object_id) as Node3D

func rename(object_id: String, new_name: String) -> bool:
	var clean: String = new_name.strip_edges()
	if clean.is_empty() or not ProjectStore.objects.has(object_id): return false
	var obj: MotionObject = ProjectStore.objects[object_id]
	obj.name = clean
	if nodes.has(object_id): (nodes[object_id] as Node3D).name = clean
	ProjectStore.project_changed.emit()
	return true

func ordered_ids() -> Array[String]:
	var roots: Array[String] = []
	var children: Dictionary = {}
	for object_id in ProjectStore.objects:
		var obj: MotionObject = ProjectStore.objects[object_id]
		if not nodes.has(object_id): continue
		if obj.parent_id.is_empty() or not ProjectStore.objects.has(obj.parent_id):
			roots.append(object_id)
		else:
			if not children.has(obj.parent_id): children[obj.parent_id] = []
			children[obj.parent_id].append(object_id)
	roots.sort_custom(func(a: String,b: String): return (ProjectStore.objects[a] as MotionObject).name.naturalnocasecmp_to((ProjectStore.objects[b] as MotionObject).name) < 0)
	var result: Array[String] = []
	for root_id in roots: _append_tree(root_id,children,result)
	return result

func _append_tree(object_id: String, children: Dictionary, result: Array[String]) -> void:
	result.append(object_id)
	var branch: Array = children.get(object_id,[])
	branch.sort_custom(func(a: String,b: String): return (ProjectStore.objects[a] as MotionObject).name.naturalnocasecmp_to((ProjectStore.objects[b] as MotionObject).name) < 0)
	for child_id in branch: _append_tree(String(child_id),children,result)

func depth(object_id: String) -> int:
	var value := 0
	var cursor: MotionObject = ProjectStore.objects.get(object_id)
	while cursor != null and not cursor.parent_id.is_empty() and value < 64:
		value += 1
		cursor = ProjectStore.objects.get(cursor.parent_id) as MotionObject
	return value

func display_name(object_id: String) -> String:
	if not ProjectStore.objects.has(object_id): return object_id
	var obj: MotionObject = ProjectStore.objects[object_id]
	var prefix := ""
	match obj.technical_type:
		"rig": prefix = "♢ "
		"camera": prefix = "▣ "
		"light": prefix = "☼ "
		"reference_canvas": prefix = "▱ "
		"bitmap_layer": prefix = "▰ "
		_: prefix = "◇ "
	return "  ".repeat(depth(object_id)) + prefix + obj.name
