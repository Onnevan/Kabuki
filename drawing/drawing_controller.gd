class_name DrawingController
extends RefCounted

# Drawing-domain coordinator. It deliberately owns canonical drawing/runtime
# registries and evaluation caches, while editor/main.gd remains responsible
# for widgets, input routing and workspace presentation.
var data_by_object: Dictionary = {}
var reference_canvases: Array[ReferenceCanvas] = []
var static_bitmap_runtime: Dictionary = {}
var evaluation_cache: Dictionary = {}

func clear() -> void:
	data_by_object.clear()
	reference_canvases.clear()
	static_bitmap_runtime.clear()
	evaluation_cache.clear()

func register_canvas(object_id: String, canvas: ReferenceCanvas, data: DrawingData) -> void:
	if not reference_canvases.has(canvas): reference_canvases.append(canvas)
	data_by_object[object_id] = data
	invalidate(object_id)

func unregister_canvas(object_id: String, canvas: ReferenceCanvas) -> void:
	reference_canvases.erase(canvas)
	data_by_object.erase(object_id)
	static_bitmap_runtime.erase(object_id)
	evaluation_cache.erase(object_id)

func data(object_id: String) -> DrawingData:
	return data_by_object.get(object_id) as DrawingData

func invalidate(object_id: String = "") -> void:
	if object_id.is_empty(): evaluation_cache.clear()
	else: evaluation_cache.erase(object_id)

func local_frame(object_id: String, scene_frame: int, use_edit_frame: bool) -> int:
	var drawing: DrawingData = data(object_id)
	if drawing == null: return scene_frame
	return drawing.local_frame if use_edit_frame else drawing.map_scene_frame(scene_frame)

func needs_pose_update(object_id: String, local_frame_value: int) -> bool:
	var previous: int = int(evaluation_cache.get(object_id, -2147483648))
	evaluation_cache[object_id] = local_frame_value
	return previous != local_frame_value

func pose(object_id: String, local_frame_value: int) -> Dictionary:
	var drawing: DrawingData = data(object_id)
	return drawing.flipbook_pose(local_frame_value) if drawing != null else {}

func active_data(object_id: String) -> DrawingData:
	return data(object_id)
