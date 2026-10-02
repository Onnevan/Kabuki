extends Control

const KABUKI_VERSION := "0.1"
const UI_SCALE_STEPS: Array[float] = [1.0,1.25,1.5,1.75,2.0]
var ui_scale_mode := "auto"
var ui_scale := 1.0

const KabukiThemeBuilder = preload("res://editor/kabuki_theme.gd")
const Stroke3DClass = preload("res://paint/stroke3d.gd")
const DrawingDataClass = preload("res://paint/drawing_data.gd")
const ReferenceCanvasClass = preload("res://paint/reference_canvas.gd")
const DrawingControllerClass = preload("res://drawing/drawing_controller.gd")
const RiggingControllerClass = preload("res://rigging/rigging_controller.gd")
const RigRuntimeClass = preload("res://rigging/rig_runtime.gd")
const SceneObjectControllerClass = preload("res://editor/scene_object_controller.gd")
const EyeIcon = preload("res://assets/icons/lucide/eye.svg")
const EyeOffIcon = preload("res://assets/icons/lucide/eye-off.svg")
const ToolSizeIcon = preload("res://assets/icons/lucide/circle.svg")
const ToolOpacityIcon = preload("res://assets/icons/lucide/wine.svg")
const ToolStrengthIcon = preload("res://assets/icons/lucide/blend.svg")
const ToolToleranceIcon = preload("res://assets/icons/lucide/paint-bucket.svg")
const ToolAngleIcon = preload("res://assets/icons/lucide/rotate-cw.svg")

@onready var viewport: SubViewport = %SceneViewport
@onready var world_root: Node3D = %WorldRoot
@onready var camera: Camera3D = %Camera3D
@onready var canvas: SubViewportContainer = %ViewportContainer
@onready var object_list: ItemList = %ObjectList
@onready var frame_slider: HSlider = %FrameSlider
@onready var frame_label: Label = %FrameLabel
@onready var timeline: FrameTimeline = %Timeline
@onready var local_drawing_timeline: FrameTimeline = %LocalDrawingTimeline
@onready var status: Label = %Status
@onready var auto_key: CheckButton = %AutoKey
@onready var interpolation: OptionButton = %Interpolation
@onready var gizmo: TransformGizmo = %TransformGizmo
@onready var camera_rig: EditorCameraRig = %EditorCameraRig
@onready var world_grid: WorldGrid = %WorldGrid
@onready var effects_engine: EffectsEngine = %EffectsEngine
var selected: RuntimeObject
var runtime_objects: Array[RuntimeObject] = []
var playing := false
var accumulator := 0.0
var dragging := false
var panning := false
var orbiting := false
var active_tool := TransformGizmo.Mode.MOVE
var gizmo_axis := TransformGizmo.Axis.NONE
var transform_start := Transform3D.IDENTITY
var drag_start_mouse := Vector2.ZERO
var workspace := "scene"
var render_preview := false
var local_playing := false
var local_play_accumulator := 0.0
var local_play_direction := 1
var local_hold_counter := 0
var render_in_progress := false
var drag_offset := Vector3.ZERO
var last_mouse := Vector2.ZERO
var scene_object_controller: RefCounted = SceneObjectControllerClass.new()
var scene_nodes: Dictionary:
	get: return scene_object_controller.nodes
var wireframe_overlays: Array[MeshInstance3D] = []
var selected_scene_node: Node3D
var selected_object_id := ""
var selected_bone_index: int = -1
var direct_bone_drag := false
var bone_edit_proxy: Node3D
var ik_target_proxy: Node3D
var ik_drag_active := false
var drawing_3d_active := false
var stroke_brush_preset := "clean"
var stroke_start_cap := "flat"
var stroke_end_cap := "flat"
var world_mode := "solid"
var world_image_mode := "camera"
var drawing_sculpt_active := false
var drawing_erase_active := false
var active_stroke_3d: Stroke3D
var active_drawing_group: ReferenceCanvas
var active_drawing_id := ""
var drawing_session_index := 0
var drawing_controller: RefCounted = DrawingControllerClass.new()
var rigging_controller: RefCounted = RiggingControllerClass.new()
var active_rig_id := ""
var active_rig_runtime: Node3D
var pending_parent_child_id := ""
var rig_bone_draw_active := false
var rig_bone_draw_parent := -1
var rig_bone_draw_depth_point := Vector3.ZERO
var rig_bone_root_set := false
var rig_bone_last_point := Vector3.ZERO
var rig_target_object_id := ""
var rig_chain_count := 0
var pending_chain_parent := -1
var drawing_content_layers: Dictionary = {}
var drawing_data_by_object: Dictionary:
	get: return drawing_controller.data_by_object
var vector_onion_roots: Dictionary = {}
var sculpt_mode := "push"
var gp_opacity := 1.0
var current_stylus_pressure := 1.0
var vector_undo_history: Dictionary = {}
var vector_redo_history: Dictionary = {}
const MAX_VECTOR_UNDO := 48
var tool_feedback_active := false
var tool_feedback_kind := ""
var tool_feedback_value := 0.0
var drawing_planes: Array[ReferenceCanvas]:
	get: return drawing_controller.reference_canvases
var selected_stroke: Stroke3D
const DRAWING_PLANE_SPACING := 1.0
var projection_view_transform := Transform3D.IDENTITY
var projection_view_valid := false
var _pending_bitmap_image: Image
var _pending_bitmap_batch: Dictionary = {}
var static_bitmap_runtime: Dictionary:
	get: return drawing_controller.static_bitmap_runtime
var workspace_camera_states: Dictionary = {}
var current_project_path := ""
var render_camera_id := ""
var camera_view_active := false
var editor_view_before_camera: Dictionary = {}
var transform_space: int = 0 # 0 global, 1 local
var active_color_target := "line"
var gp_line_color := Color(0.08,0.08,0.08,1.0)
var gp_fill_color := Color(0.8,0.25,0.18,0.55)
var gp_fill_color_b := Color(0.95,0.75,0.2,0.55)
var bitmap_color := Color(0.08,0.08,0.08,1.0)
var drawing_palette: Array[Color] = [
	Color("#111318"), Color("#FFFFFF"), Color("#E94B4B"), Color("#F39C3D"),
	Color("#F1D04B"), Color("#58B368"), Color("#35A7A0"), Color("#3F8FE5"),
	Color("#6757D9"), Color("#B65BD6"), Color("#E65C9C"), Color("#8A5A44"),
	Color("#59636E"), Color("#A9B2BC"), Color("#DCE2E8"), Color("#F2B8A2")
]
var gradient_drag_handle := 0
var gradient_handle_a := Vector2.ZERO
var gradient_handle_b := Vector2.ZERO

func _ready() -> void:
	_apply_ui_scale(_detect_ui_scale())
	var brand: Label = get_node("TopBar/Brand") as Label
	if brand != null:
		brand.text = "KABUKI  " + KABUKI_VERSION
	%FillMode.add_item("Solid")
	%FillMode.add_item("Gradient")
	%FillMode.item_selected.connect(_on_fill_mode_selected)
	%FillColorB.color_changed.connect(_on_fill_gradient_changed)
	%FillGradientAngle.value_changed.connect(_on_fill_gradient_changed)
	%BrushColor.pressed.connect(func(): _set_active_color_target("line"))
	%StrokeClean.pressed.connect(func(): _set_stroke_brush_preset("clean"))
	%StrokeInk.pressed.connect(func(): _set_stroke_brush_preset("ink"))
	%StrokeDry.pressed.connect(func(): _set_stroke_brush_preset("dry"))
	%StrokeRough.pressed.connect(func(): _set_stroke_brush_preset("rough"))
	%BrushMenuButton.pressed.connect(_toggle_brush_preset_popup)
	for label in ["Flat","Round","Point"]:
		%StartCap.add_item(label)
		%EndCap.add_item(label)
	%StartCap.item_selected.connect(func(i): stroke_start_cap = ["flat","round","point"][i])
	%EndCap.item_selected.connect(func(i): stroke_end_cap = ["flat","round","point"][i])
	_setup_world_controls()
	%FillColor.pressed.connect(func(): _set_active_color_target("fill_a"))
	%FillColorB.pressed.connect(func(): _set_active_color_target("fill_b"))
	%GradientGuide.draw.connect(_draw_gradient_guide)
	_setup_drawing_palette()
	gp_line_color = %BrushColor.color
	gp_fill_color = %FillColor.color
	gp_fill_color_b = %FillColorB.color
	bitmap_color = %ActiveColor.color
	%ActiveColor.color_changed.connect(_on_bitmap_color_changed)
	_setup_color_swatches()
	_refresh_gradient_preview()
	theme = KabukiThemeBuilder.build()
	%ObjectList.gui_input.connect(_on_object_list_gui_input)
	%DrawingPlaneList.gui_input.connect(_on_drawing_plane_list_gui_input)
	ProjectStore.frame_changed.connect(_on_frame_changed)
	ProjectStore.key_changed.connect(timeline.refresh_keys)
	timeline.key_selected.connect(_on_timeline_key_selected)
	timeline.key_deselected.connect(_on_timeline_key_deselected)
	timeline.frame_requested.connect(_on_timeline_frame_requested)
	local_drawing_timeline.set_drawing_only_mode(true)
	local_drawing_timeline.frame_requested.connect(_on_local_timeline_frame_requested)
	for label in ["Constant", "Linear", "Bezier", "Quadratic In", "Quadratic Out", "Quadratic In-Out", "Cubic In-Out", "Back", "Bounce", "Elastic"]:
		interpolation.add_item(label)
	interpolation.select(2)
	_setup_shading_menu()
	_setup_viewport_controls()
	_setup_add_object_menu()
	_setup_property_panels()
	_on_auto_key_toggled(auto_key.button_pressed)
	camera_rig.setup(camera)
	workspace_camera_states["scene"] = camera_rig.get_state()
	gizmo.set_mode(active_tool)
	_sync_transform_tool_buttons()
	_setup_workspace_tabs()
	_setup_drawing_menus()
	_setup_rigging_workspace()
	%IKSolver.pressed.connect(_on_add_ik_solver)
	%RemoveIK.pressed.connect(_on_remove_ik_solver)
	%IKChainLength.value_changed.connect(_on_ik_settings_changed)
	%IKInfluence.value_changed.connect(_on_ik_settings_changed)
	%IKGuide.draw.connect(_draw_ik_guide)
	%SaveProject.pressed.connect(_on_save_project_pressed)
	%SaveProjectAs.pressed.connect(_on_save_project_as_pressed)
	%LoadProject.pressed.connect(_on_load_project_pressed)
	%UndoPaint.pressed.connect(_undo_drawing)
	%RedoPaint.pressed.connect(_redo_drawing)
	%ViewX.pressed.connect(func(): _align_view_axis(Vector3.RIGHT, "X"))
	%ViewY.pressed.connect(func(): _align_view_axis(Vector3.UP, "Y"))
	%ViewZ.pressed.connect(func(): _align_view_axis(Vector3.BACK, "Z"))
	%ViewCamera.pressed.connect(_toggle_render_camera_view)
	%CanvasAxisX.pressed.connect(func(): _set_active_canvas_axis("X"))
	%CanvasAxisY.pressed.connect(func(): _set_active_canvas_axis("Y"))
	%CanvasAxisZ.pressed.connect(func(): _set_active_canvas_axis("Z"))
	%CameraFov.value_changed.connect(_on_camera_fov_changed)
	%CameraResX.value_changed.connect(_on_camera_resolution_changed)
	%CameraResY.value_changed.connect(_on_camera_resolution_changed)
	%CameraDofEnabled.toggled.connect(_on_camera_dof_changed)
	%CameraFocusDistance.value_changed.connect(_on_camera_dof_changed)
	%CameraAperture.value_changed.connect(_on_camera_dof_changed)
	%PlaneDelete.pressed.connect(_on_plane_delete)
	%ClipMode.clear()
	for clip_mode_name in ["Loop", "Ping-Pong", "Hold", "Loop + Hold"]:
		%ClipMode.add_item(clip_mode_name)
	%ClipMode.item_selected.connect(_on_clip_mode_selected)
	%LocalPlay.pressed.connect(_on_local_play_pressed)
	%RenderAnimation.pressed.connect(_on_render_animation_pressed)
	%RenderOutputDialog.dir_selected.connect(_on_render_output_dir_selected)
	%LocalDuration.value_changed.connect(_on_local_duration_changed)
	%LocalPlaybackStart.value_changed.connect(_on_local_playback_start_changed)
	%LocalPlaybackEnd.value_changed.connect(_on_local_playback_end_changed)
	%SceneStart.value_changed.connect(_on_scene_start_changed)
	%HoldFrames.value_changed.connect(_on_hold_frames_changed)
	%TimelineDuration.value_changed.connect(_on_timeline_duration_changed)
	%PlaybackStart.value_changed.connect(_on_playback_start_changed)
	%PlaybackEnd.value_changed.connect(_on_playback_end_changed)
	%ZoomIn.pressed.connect(func(): timeline.zoom_at(0.8,float(timeline.current_frame)))
	%ZoomOut.pressed.connect(func(): timeline.zoom_at(1.25,float(timeline.current_frame)))
	%TimelineDuration.set_value_no_signal(ProjectStore.duration_frames)
	%PlaybackStart.set_value_no_signal(ProjectStore.playback_start)
	%PlaybackEnd.set_value_no_signal(ProjectStore.playback_end)
	timeline.set_timeline_range(ProjectStore.duration_frames,ProjectStore.playback_start,ProjectStore.playback_end)
	%TessellationDialog.confirmed.connect(_commit_pending_bitmap)
	%SculptMode.clear()
	for label in ["Push / Pull", "Move", "Pinch", "Smooth", "Inflate"]:
		%SculptMode.add_item(label)
	%SculptMode.select(0)
	%SculptMode.item_selected.connect(_on_sculpt_mode_selected)
	_update_preview_mode()
	_on_frame_changed(0)
	_responsive_layout()
	resized.connect(_responsive_layout)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo: return
	if workspace == "rigging" and rig_bone_draw_active and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER):
		_finish_rig_bone_drawing()
		return
	if workspace == "rigging" and rig_bone_draw_active and key_event.keycode == KEY_ESCAPE:
		rig_bone_draw_parent = -1
		rig_bone_root_set = false
		status.text = "New bone chain · click its root point"
		return
	if key_event.ctrl_pressed and key_event.keycode == KEY_Z:
		if key_event.shift_pressed: _redo_drawing()
		else: _undo_drawing()
		get_viewport().set_input_as_handled()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_Y:
		_redo_drawing()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if playing:
		accumulator += delta
		if accumulator >= 1.0 / ProjectStore.fps:
			accumulator = 0.0
			# Transport is always scene/global. Drawing clips evaluate their
			# local frame from scene time; they do not own the main transport.
			var next_frame: int = ProjectStore.current_frame + 1
			if next_frame > ProjectStore.playback_end: next_frame = ProjectStore.playback_start
			ProjectStore.set_frame(next_frame)
	if local_playing:
		_process_local_playback(delta)

func _setup_viewport_controls() -> void:
	%ProjectionMode.clear()
	%ProjectionMode.add_item("Perspective")
	%ProjectionMode.add_item("Orthographic")
	%ProjectionMode.select(0 if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 1)
	%ProjectionMode.item_selected.connect(_on_projection_mode_selected)
	%TransformSpace.clear()
	%TransformSpace.add_item("Global")
	%TransformSpace.add_item("Local")
	%TransformSpace.select(transform_space)
	%TransformSpace.item_selected.connect(_on_transform_space_selected)

func _on_projection_mode_selected(index: int) -> void:
	if index == 0:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		status.text = "Perspective view"
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		status.text = "Orthographic view"

func _on_transform_space_selected(index: int) -> void:
	transform_space = index
	status.text = "Local transform orientation" if transform_space == 1 else "Global transform orientation"
	if selected_scene_node != null and is_instance_valid(selected_scene_node):
		gizmo.attach(selected_scene_node if transform_space == 1 else selected_scene_node)
	# TransformGizmo reads this flag when drawing and dragging axes.
	gizmo.set_orientation_local(transform_space == 1)

func _setup_shading_menu() -> void:
	%ShadingMode.clear()
	%ShadingMode.add_item("Solid")
	%ShadingMode.add_item("Wireframe")
	%ShadingMode.select(0)
	%ShadingMode.item_selected.connect(_on_shading_mode_selected)

func _on_shading_mode_selected(index: int) -> void:
	var wire := index == 1
	_set_wireframe_overlays(wire)
	for runtime in runtime_objects:
		runtime.visible = not wire
	status.text = "Wireframe · actual mesh topology" if wire else "Solid viewport"

func _set_wireframe_overlays(enabled: bool) -> void:
	for overlay in wireframe_overlays:
		if is_instance_valid(overlay): overlay.queue_free()
	wireframe_overlays.clear()
	if not enabled: return
	for runtime in runtime_objects:
		if runtime.mesh == null: continue
		var overlay := MeshInstance3D.new()
		overlay.mesh = _build_wire_mesh(runtime.mesh)
		if overlay.mesh == null: continue
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.04, 0.08, 0.11, 1.0)
		mat.no_depth_test = true
		overlay.material_override = mat
		overlay.position.z = 0.002
		world_root.add_child(overlay)
		overlay.global_transform = runtime.global_transform
		wireframe_overlays.append(overlay)

func _build_wire_mesh(source: Mesh) -> ArrayMesh:
	var line_vertices := PackedVector3Array()
	var seen: Dictionary = {}
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(0, vertices.size() - 2, 3):
				_add_triangle_edges(line_vertices, seen, vertices, i, i + 1, i + 2)
		else:
			for i in range(0, indices.size() - 2, 3):
				_add_triangle_edges(line_vertices, seen, vertices, indices[i], indices[i + 1], indices[i + 2])
	if line_vertices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = line_vertices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return result

func _add_triangle_edges(out: PackedVector3Array, seen: Dictionary, vertices: PackedVector3Array, a: int, b: int, c: int) -> void:
	_add_wire_edge(out, seen, vertices, a, b)
	_add_wire_edge(out, seen, vertices, b, c)
	_add_wire_edge(out, seen, vertices, c, a)

func _add_wire_edge(out: PackedVector3Array, seen: Dictionary, vertices: PackedVector3Array, a: int, b: int) -> void:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var key := "%d:%d" % [lo, hi]
	if seen.has(key): return
	seen[key] = true
	out.append(vertices[a])
	out.append(vertices[b])

func _setup_add_object_menu() -> void:
	var popup: PopupMenu = %AddObj.get_popup()
	for label in ["Plane", "Sound", "Camera", "Light", "Drawing"]:
		popup.add_item(label)
	popup.id_pressed.connect(_on_add_object_type)

func _setup_property_panels() -> void:
	%LightType.clear()
	for label in ["Directional", "Point", "Spot"]:
		%LightType.add_item(label)
	%ObjectProperties.visible = false
	%LightProperties.visible = false
	%CameraProperties.visible = false

func _register_scene_object(obj: MotionObject, node: Node3D) -> void:
	scene_object_controller.register(obj,node)
	_refresh_scene_object_list()

func _refresh_scene_object_list() -> void:
	object_list.clear()
	for object_id in scene_object_controller.ordered_ids():
		var obj: MotionObject = ProjectStore.objects.get(object_id)
		var visibility_icon: Texture2D = EyeIcon if obj == null or obj.visible else EyeOffIcon
		object_list.add_item(scene_object_controller.display_name(object_id),visibility_icon)
		object_list.set_item_metadata(object_list.item_count - 1, object_id)
		if object_id == selected_object_id: object_list.select(object_list.item_count - 1)
		if obj != null and obj.technical_type == "rig" and rigging_controller.rigs.has(object_id):
			var rig: RefCounted = rigging_controller.rigs[object_id]
			for bone_index in range(rig.bones.size()):
				var bone: Dictionary = rig.bones[bone_index]
				var parent_index: int = int(bone.get("parent",-1))
				var bone_depth: int = 1
				var cursor: int = parent_index
				while cursor >= 0 and cursor < rig.bones.size():
					bone_depth += 1
					cursor = int(rig.bones[cursor].get("parent",-1))
				object_list.add_item("  ".repeat(bone_depth) + "◇ " + String(bone.get("name","Bone")))
				object_list.set_item_metadata(object_list.item_count - 1,"bone::%s::%d" % [object_id,bone_index])

func _set_visual_visibility_recursive(node: Node, visible_state: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = visible_state
	for child in node.get_children():
		_set_visual_visibility_recursive(child,visible_state)

func _object_effectively_visible(object_id: String) -> bool:
	var cursor_id := object_id
	var guard := 0
	while not cursor_id.is_empty() and ProjectStore.objects.has(cursor_id) and guard < 64:
		var cursor: MotionObject = ProjectStore.objects[cursor_id]
		if not cursor.visible: return false
		cursor_id = cursor.parent_id
		guard += 1
	return true

func _apply_object_visibility(object_id: String) -> void:
	if not ProjectStore.objects.has(object_id): return
	var obj: MotionObject = ProjectStore.objects[object_id]
	if not scene_nodes.has(object_id): return
	var node: Node3D = scene_nodes[object_id]
	if not _object_effectively_visible(object_id):
		_set_visual_visibility_recursive(node,false)
		return
	# Restore through normal evaluation so animated stroke/cel visibility is not
	# flattened when an object is made visible again.
	if node is ReferenceCanvas:
		(node as ReferenceCanvas).set_guide_visible(workspace == "scene")
		drawing_controller.invalidate(object_id)
		_apply_drawing_frame(ProjectStore.current_frame)
	else:
		_set_visual_visibility_recursive(node,true)

func _set_object_visible(object_id: String, visible_state: bool) -> void:
	if not ProjectStore.objects.has(object_id): return
	var obj: MotionObject = ProjectStore.objects[object_id]
	obj.visible = visible_state
	# Re-evaluate the whole hierarchy because parent visibility affects children,
	# while each child keeps its own visibility toggle for later restoration.
	for affected_id in scene_nodes.keys():
		_apply_object_visibility(String(affected_id))
	ProjectStore.project_changed.emit()
	_refresh_scene_object_list()
	_refresh_drawing_planes()
	status.text = ("%s visible" if visible_state else "%s hidden") % obj.name

func _toggle_object_visibility(object_id: String) -> void:
	if not ProjectStore.objects.has(object_id): return
	var obj: MotionObject = ProjectStore.objects[object_id]
	_set_object_visible(object_id,not obj.visible)

func _visibility_icon_hit(list: ItemList,event: InputEvent) -> int:
	if not event is InputEventMouseButton: return -1
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed: return -1
	if mb.position.x > 34.0: return -1
	return list.get_item_at_position(mb.position,true)

func _on_object_list_gui_input(event: InputEvent) -> void:
	var index := _visibility_icon_hit(object_list,event)
	if index < 0: return
	var object_id: String = String(object_list.get_item_metadata(index))
	if object_id.begins_with("bone::"): return
	_toggle_object_visibility(object_id)
	object_list.accept_event()

func _on_drawing_plane_list_gui_input(event: InputEvent) -> void:
	var list: ItemList = %DrawingPlaneList
	var index := _visibility_icon_hit(list,event)
	if index < 0: return
	var plane: ReferenceCanvas = list.get_item_metadata(index)
	if plane == null: return
	var object_id := _reference_canvas_id(plane)
	if object_id.is_empty(): return
	_toggle_object_visibility(object_id)
	list.accept_event()

func _on_add_object_type(id: int) -> void:
	match id:
		0: _create_plane()
		1: _create_sound()
		2: _create_camera()
		3: _create_light()
		4: _create_drawing()

func _create_plane() -> void:
	var obj := MotionObject.new("Plane", "plane", "prop")
	var runtime := RuntimeObject.new()
	world_root.add_child(runtime)
	runtime.setup_plane(obj)
	_register_scene_object(obj, runtime)
	runtime_objects.append(runtime)
	_select(runtime)
	status.text = "Plane created"
	if %ShadingMode.selected == 1: _set_wireframe_overlays(true)

func _create_sound() -> void:
	var obj := MotionObject.new("Sound", "audio_clip", "audio")
	var anchor := Node3D.new()
	world_root.add_child(anchor)
	_register_scene_object(obj, anchor)
	status.text = "Sound object created · audio asset loading comes next"

func _create_camera() -> void:
	var obj := MotionObject.new("Camera", "camera", "camera")
	obj.properties["camera.fov"] = 70.0
	obj.properties["camera.resolution_x"] = 1920
	obj.properties["camera.resolution_y"] = 1080
	obj.properties["camera.dof_enabled"] = false
	obj.properties["camera.focus_distance"] = 3.0
	obj.properties["camera.aperture"] = 0.2
	var rig := _build_scene_camera(obj)
	# The camera rig must belong to the SubViewport scene tree. Previously it
	# was registered in scene_nodes but never parented under WorldRoot, which
	# is why only the separate TransformGizmo was visible.
	world_root.add_child(rig)
	# Do not spawn the scene camera exactly on top of the editor camera: from
	# that viewpoint its gizmo is behind/around the viewer and appears missing.
	# Put it at the current orbit pivot, preserving the current viewing direction.
	rig.global_transform = camera.global_transform
	rig.global_position = camera_rig.pivot
	obj.transform = rig.transform
	if render_camera_id.is_empty(): render_camera_id = obj.id
	_register_scene_object(obj, rig)
	_select_scene_node(obj.id, rig)
	status.text = "Camera created · CAM enters final render view"

func _build_scene_camera(obj: MotionObject) -> Node3D:
	var rig := Node3D.new()
	rig.name = obj.name
	var scene_camera := Camera3D.new()
	scene_camera.name = "_RenderCamera"
	scene_camera.fov = float(obj.properties.get("camera.fov", 70.0))
	scene_camera.current = false
	rig.add_child(scene_camera)

	var gizmo := MeshInstance3D.new()
	gizmo.name = "_CameraGizmo"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92,0.94,0.98,1.0)
	mat.no_depth_test = true
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var hx: float = 0.28
	var hy: float = 0.18
	var z: float = 0.0
	var corners := [
		Vector3(-hx,-hy,z),Vector3(hx,-hy,z),
		Vector3(hx,hy,z),Vector3(-hx,hy,z)
	]
	for i in 4:
		im.surface_add_vertex(corners[i])
		im.surface_add_vertex(corners[(i + 1) % 4])
	var forward_z: float = -0.75
	var forward_corners := [
		Vector3(-0.46,-0.30,forward_z),Vector3(0.46,-0.30,forward_z),
		Vector3(0.46,0.30,forward_z),Vector3(-0.46,0.30,forward_z)
	]
	var apex := Vector3.ZERO
	for i in 4:
		im.surface_add_vertex(apex)
		im.surface_add_vertex(forward_corners[i])
		im.surface_add_vertex(forward_corners[i])
		im.surface_add_vertex(forward_corners[(i + 1) % 4])
	im.surface_add_vertex(Vector3(-0.09,hy,z))
	im.surface_add_vertex(Vector3(0.0,hy + 0.14,z))
	im.surface_add_vertex(Vector3(0.0,hy + 0.14,z))
	im.surface_add_vertex(Vector3(0.09,hy,z))
	im.surface_end()
	gizmo.mesh = im
	gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(gizmo)
	return rig

func _scene_camera_node(camera_id: String) -> Camera3D:
	if not scene_nodes.has(camera_id): return null
	var rig: Node3D = scene_nodes[camera_id]
	return rig.get_node_or_null("_RenderCamera") as Camera3D

func _toggle_render_camera_view() -> void:
	if render_camera_id.is_empty() or not scene_nodes.has(render_camera_id):
		status.text = "Create a scene camera first"
		return
	camera_view_active = not camera_view_active
	if camera_view_active:
		editor_view_before_camera = camera_rig.get_state()
		_set_render_camera_gizmo_visible(false)
		_sync_editor_view_to_render_camera()
		_update_camera_frame_overlay()
		%ViewCamera.text = "▣ CAM ●"
		status.text = "Camera view · final render framing"
	else:
		_set_render_camera_gizmo_visible(true)
		%CameraFrame.visible = false
		camera_rig.set_state(editor_view_before_camera)
		%ViewCamera.text = "▣ CAM"
		status.text = "Perspective editor view"

func _update_camera_frame_overlay() -> void:
	if not camera_view_active or render_camera_id.is_empty() or not ProjectStore.objects.has(render_camera_id):
		%CameraFrame.visible = false
		return
	var obj: MotionObject = ProjectStore.objects[render_camera_id]
	var rx: float = maxf(1.0,float(obj.properties.get("camera.resolution_x",1920)))
	var ry: float = maxf(1.0,float(obj.properties.get("camera.resolution_y",1080)))
	var viewport_rect: Rect2 = %ViewportFrame.get_global_rect()
	var available := viewport_rect.size
	var target_aspect: float = rx / ry
	var frame_size := Vector2(available.x, available.x / target_aspect)
	if frame_size.y > available.y:
		frame_size = Vector2(available.y * target_aspect, available.y)
	var local_pos := (available - frame_size) * 0.5
	%CameraFrame.position = viewport_rect.position + local_pos
	%CameraFrame.size = frame_size
	%CameraFrame.visible = true
	var thickness := 2.0
	var top: ColorRect = %CameraFrame.get_node("Top")
	var bottom: ColorRect = %CameraFrame.get_node("Bottom")
	var left: ColorRect = %CameraFrame.get_node("Left")
	var right: ColorRect = %CameraFrame.get_node("Right")
	top.position = Vector2.ZERO; top.size = Vector2(frame_size.x,thickness)
	bottom.position = Vector2(0,frame_size.y-thickness); bottom.size = Vector2(frame_size.x,thickness)
	left.position = Vector2.ZERO; left.size = Vector2(thickness,frame_size.y)
	right.position = Vector2(frame_size.x-thickness,0); right.size = Vector2(thickness,frame_size.y)

func _set_render_camera_gizmo_visible(enabled: bool) -> void:
	if render_camera_id.is_empty() or not scene_nodes.has(render_camera_id): return
	var rig: Node3D = scene_nodes[render_camera_id]
	var camera_symbol := rig.get_node_or_null("_CameraGizmo")
	if camera_symbol: camera_symbol.visible = enabled
	# Transform gizmo must also disappear in camera view, otherwise its axes sit
	# in the framing view even though the camera object itself is hidden.
	if selected_object_id == render_camera_id:
		gizmo.visible = enabled

func _sync_editor_view_to_render_camera() -> void:
	if not scene_nodes.has(render_camera_id): return
	var rig: Node3D = scene_nodes[render_camera_id]
	var render_cam := _scene_camera_node(render_camera_id)
	if render_cam == null: return
	# The viewport keeps using the editor Camera3D for navigation/picking, but
	# adopts the render camera transform and lens while CAM view is active.
	camera.global_transform = render_cam.global_transform
	camera.fov = render_cam.fov
	camera_rig.sync_from_camera_transform(camera.global_transform)

func _on_camera_fov_changed(value: float) -> void:
	if selected_object_id.is_empty() or not ProjectStore.objects.has(selected_object_id): return
	var obj: MotionObject = ProjectStore.objects[selected_object_id]
	if obj.technical_type != "camera": return
	obj.properties["camera.fov"] = value
	if auto_key.button_pressed:
		ProjectStore.set_key(selected_object_id,"camera.fov",ProjectStore.current_frame,value,_interp_name())
	var cam := _scene_camera_node(selected_object_id)
	if cam: cam.fov = value
	if camera_view_active and selected_object_id == render_camera_id: camera.fov = value

func _on_camera_resolution_changed(_value: float) -> void:
	if selected_object_id.is_empty() or not ProjectStore.objects.has(selected_object_id): return
	var obj: MotionObject = ProjectStore.objects[selected_object_id]
	if obj.technical_type != "camera": return
	obj.properties["camera.resolution_x"] = int(%CameraResX.value)
	obj.properties["camera.resolution_y"] = int(%CameraResY.value)
	if camera_view_active and selected_object_id == render_camera_id: _update_camera_frame_overlay()

func _on_camera_dof_changed(_value: Variant = null) -> void:
	if selected_object_id.is_empty() or not ProjectStore.objects.has(selected_object_id): return
	var obj: MotionObject = ProjectStore.objects[selected_object_id]
	if obj.technical_type != "camera": return
	obj.properties["camera.dof_enabled"] = %CameraDofEnabled.button_pressed
	obj.properties["camera.focus_distance"] = %CameraFocusDistance.value
	obj.properties["camera.aperture"] = %CameraAperture.value
	if auto_key.button_pressed:
		ProjectStore.set_key(selected_object_id,"camera.focus_distance",ProjectStore.current_frame,%CameraFocusDistance.value,_interp_name())
		ProjectStore.set_key(selected_object_id,"camera.aperture",ProjectStore.current_frame,%CameraAperture.value,_interp_name())
	var cam := _scene_camera_node(selected_object_id)
	if cam:
		cam.attributes = CameraAttributesPractical.new()
		var attrs := cam.attributes as CameraAttributesPractical
		attrs.dof_blur_far_enabled = %CameraDofEnabled.button_pressed
		attrs.dof_blur_near_enabled = %CameraDofEnabled.button_pressed
		attrs.dof_blur_far_distance = %CameraFocusDistance.value
		attrs.dof_blur_near_distance = %CameraFocusDistance.value
		attrs.dof_blur_amount = %CameraAperture.value

func _create_light() -> void:
	var obj := MotionObject.new("Light", "light", "light")
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	light.light_energy = 1.0
	world_root.add_child(light)
	_register_scene_object(obj, light)
	_select_scene_node(obj.id, light)
	status.text = "Directional light created"

func _create_drawing() -> void:
	var obj := MotionObject.new("Drawing", "drawing", "prop")
	var anchor := Node3D.new()
	world_root.add_child(anchor)
	_register_scene_object(obj, anchor)
	status.text = "Drawing object created · stroke engine comes in Drawing workspace"

func _on_save_project_pressed() -> void:
	if current_project_path.is_empty():
		_on_save_project_as_pressed()
		return
	_save_project_to(current_project_path)

func _on_save_project_as_pressed() -> void:
	if not current_project_path.is_empty():
		%SaveProjectDialog.current_path = current_project_path
		%SaveProjectDialog.current_file = current_project_path.get_file()
	%SaveProjectDialog.popup_centered_ratio(0.72)

func _on_save_project_file_selected(path: String) -> void:
	var save_path := path
	var ext := save_path.get_extension().to_lower()
	if ext != "kab":
		save_path = save_path.get_basename() + ".kab"
	_save_project_to(save_path)

func _save_project_to(path: String) -> void:
	var drawing_payload: Dictionary = {}
	for object_id in drawing_data_by_object:
		var data: RefCounted = drawing_data_by_object[object_id]
		drawing_payload[object_id] = data.to_dict()
	var payload := {
		"project": ProjectStore.to_dict(),
		"drawings": drawing_payload,
		"bitmap_cels": %DrawingCanvas.export_bitmap_cels()
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status.text = "Could not save project"
		return
	file.store_string(JSON.stringify(payload))
	current_project_path = path
	%ProjectName.text = path.get_file()
	status.text = "Project saved · " + path.get_file()

func _on_load_project_pressed() -> void:
	%ProjectFileDialog.popup_centered_ratio(0.72)

func _on_project_file_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		status.text = "Project file not found"
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		status.text = "Could not open project"
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		status.text = "Invalid KABUKI project"
		return
	_load_project_payload(parsed as Dictionary, path)

func _clear_runtime_project() -> void:
	for child in world_root.get_children():
		if child == camera_rig or child == gizmo or child == world_grid: continue
		child.queue_free()
	runtime_objects.clear()
	scene_nodes.clear()
	drawing_controller.clear()
	vector_onion_roots.clear()
	active_drawing_group = null
	active_drawing_id = ""
	selected = null
	selected_scene_node = null
	selected_object_id = ""
	gizmo.attach(null)

func _load_project_payload(payload: Dictionary, path: String) -> void:
	_clear_runtime_project()
	if not ProjectStore.load_dict(payload.get("project", {})):
		status.text = "Unsupported KABUKI project"
		return
	%DrawingCanvas.import_bitmap_cels(payload.get("bitmap_cels", {}))
	var drawings: Dictionary = payload.get("drawings", {})
	# Rebuild reference canvases first; their children are reconstructed below.
	for object_id in ProjectStore.objects:
		var obj: MotionObject = ProjectStore.objects[object_id]
		if obj.technical_type == "reference_canvas":
			var plane: ReferenceCanvas = ReferenceCanvasClass.new()
			world_root.add_child(plane)
			plane.setup(obj)
			plane.transform = obj.transform
			plane.set_guide_visible(workspace == "scene")
			scene_nodes[obj.id] = plane
			var data: DrawingData = DrawingDataClass.new(obj.id)
			if drawings.has(obj.id): data.load_dict(drawings[obj.id])
			drawing_controller.register_canvas(obj.id, plane, data)
			for stroke_id in data.stroke_order:
				if not data.strokes.has(stroke_id): continue
				var rec: Dictionary = data.strokes[stroke_id]
				var stroke: Stroke3D = Stroke3DClass.new()
				stroke.stroke_id = stroke_id
				stroke.points = rec.get("points", PackedVector3Array())
				stroke.stroke_color = rec.get("color", Color.BLACK)
				stroke.radius = float(rec.get("radius", 0.012))
				stroke.set_pressure_data(rec.get("point_size_pressure",[]),rec.get("point_opacity_pressure",[]))
				stroke.brush_preset = String(rec.get("brush_preset", "clean"))
				stroke.width_variation = float(rec.get("width_variation", 0.0))
				stroke.width_frequency = float(rec.get("width_frequency", 1.0))
				stroke.brush_seed = int(rec.get("brush_seed", 1))
				stroke.start_cap = String(rec.get("start_cap", "flat"))
				stroke.end_cap = String(rec.get("end_cap", "flat"))
				stroke.fill_enabled = bool(rec.get("fill_enabled", false))
				stroke.fill_color = rec.get("fill_color", Color.TRANSPARENT)
				plane.add_child(stroke)
				stroke.rebuild()
	# Rebuild non-drawing scene anchors.
	for object_id in ProjectStore.objects:
		if scene_nodes.has(object_id): continue
		var obj: MotionObject = ProjectStore.objects[object_id]
		if obj.technical_type == "camera":
			var camera_rig_node := _build_scene_camera(obj)
			world_root.add_child(camera_rig_node)
			camera_rig_node.transform = obj.transform
			scene_nodes[obj.id] = camera_rig_node
			if render_camera_id.is_empty(): render_camera_id = obj.id
		elif obj.technical_type == "light":
			var loaded_light := DirectionalLight3D.new()
			world_root.add_child(loaded_light)
			loaded_light.transform = obj.transform
			scene_nodes[obj.id] = loaded_light
	for loaded_object_id in scene_nodes.keys():
		_apply_object_visibility(String(loaded_object_id))
	_refresh_scene_object_list()
	_refresh_drawing_planes()
	_apply_drawing_frame(ProjectStore.current_frame)
	current_project_path = path
	%ProjectName.text = path.get_file()
	status.text = "Project loaded · " + path.get_file()

func _on_import_pressed() -> void: %FileDialog.popup_centered_ratio(0.7)

func _on_file_selected(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty(): status.text = "Could not load image"; return
	var obj := MotionObject.new(path.get_file(), "image_mesh", "prop")
	ProjectStore.add_object(obj)
	var runtime := RuntimeObject.new()
	world_root.add_child(runtime); runtime.setup(obj, img)
	runtime.position = Vector3(runtime_objects.size() * 0.12, 0, 0)
	runtime.model.transform.origin = runtime.position
	runtime_objects.append(runtime)
	object_list.add_item(obj.name)
	object_list.set_item_metadata(object_list.item_count - 1, obj.id)
	_select(runtime)
	status.text = "Imported %s" % obj.name
	if %ShadingMode.selected == 1: _set_wireframe_overlays(true)

func _select(obj: RuntimeObject) -> void:
	selected = obj
	selected_scene_node = obj
	selected_object_id = obj.model.id
	for r in runtime_objects: r.set_selected(r == selected)
	for i in object_list.item_count:
		if object_list.get_item_metadata(i) == obj.model.id:
			object_list.select(i); break
	%SelectionLabel.text = obj.model.name
	_show_transform(obj)
	%ObjectProperties.visible = true
	%LightProperties.visible = false
	%MaterialColor.color = obj.get_material_color()
	%MaterialRoughness.value = obj.get_material_roughness()
	%MaterialMetallic.value = obj.get_material_metallic()
	gizmo.attach(obj)
	timeline.set_object(obj.model.id)
	_sync_animation_canvas_editor()

func _select_scene_node(id: String, node: Node3D) -> void:
	if workspace == "rigging" and not pending_parent_child_id.is_empty() and id != pending_parent_child_id:
		if _try_complete_rig_parenting(id): return
	selected = null
	selected_scene_node = node
	selected_object_id = id
	for r in runtime_objects: r.set_selected(false)
	for i in object_list.item_count:
		if object_list.get_item_metadata(i) == id:
			object_list.select(i); break
	%SelectionLabel.text = node.name
	_show_transform(node)
	gizmo.attach(node)
	# Drawing is a canvas-locked 2D editor: keep the canvas selected internally
	# but never show its 3D transform manipulator over the artwork.
	gizmo.visible = workspace != "drawing" and workspace != "rigging" and workspace != "animation"
	timeline.set_object(id)
	%ObjectProperties.visible = node is MeshInstance3D
	%LightProperties.visible = node is Light3D
	var selected_model: MotionObject = ProjectStore.objects.get(id)
	var is_camera: bool = selected_model != null and selected_model.technical_type == "camera"
	%CameraProperties.visible = is_camera
	if is_camera:
		render_camera_id = id
		%CameraFov.set_value_no_signal(float(selected_model.properties.get("camera.fov",70.0)))
		%CameraResX.set_value_no_signal(float(selected_model.properties.get("camera.resolution_x",1920)))
		%CameraResY.set_value_no_signal(float(selected_model.properties.get("camera.resolution_y",1080)))
		%CameraDofEnabled.set_pressed_no_signal(bool(selected_model.properties.get("camera.dof_enabled",false)))
		%CameraFocusDistance.set_value_no_signal(float(selected_model.properties.get("camera.focus_distance",3.0)))
		%CameraAperture.set_value_no_signal(float(selected_model.properties.get("camera.aperture",0.2)))
	if node is Light3D:
		var light := node as Light3D
		%LightEnergy.value = light.light_energy
		%LightColor.color = light.light_color
		%LightShadow.button_pressed = light.shadow_enabled
		%LightType.select(0 if light is DirectionalLight3D else (1 if light is OmniLight3D else 2))
	_sync_animation_canvas_editor()

func _selected_is_reference_canvas() -> bool:
	return not selected_object_id.is_empty() and scene_nodes.has(selected_object_id) and scene_nodes[selected_object_id] is ReferenceCanvas and drawing_data_by_object.has(selected_object_id)

func _sync_animation_canvas_editor() -> void:
	var show_local: bool = workspace == "drawing" or (workspace == "animation" and _selected_is_reference_canvas())
	%DrawingAnimBar.visible = show_local
	%LocalDrawingTimeline.visible = show_local
	if workspace == "animation":
		%OnionSkin.visible = false
		%CelMenu.visible = show_local
	else:
		%OnionSkin.visible = true
		%CelMenu.visible = true
	if not show_local:
		return
	if workspace == "animation" and _selected_is_reference_canvas():
		active_drawing_id = selected_object_id
		active_drawing_group = scene_nodes[selected_object_id] as ReferenceCanvas
		%DrawingCanvas.switch_canvas(active_drawing_id)
	_refresh_drawing_timeline()

func _show_transform(node: Node3D) -> void:
	%PosX.set_value_no_signal(node.position.x); %PosY.set_value_no_signal(node.position.y); %PosZ.set_value_no_signal(node.position.z)
	%RotX.set_value_no_signal(node.rotation_degrees.x); %RotY.set_value_no_signal(node.rotation_degrees.y); %RotZ.set_value_no_signal(node.rotation_degrees.z)
	%SclX.set_value_no_signal(node.scale.x); %SclY.set_value_no_signal(node.scale.y); %SclZ.set_value_no_signal(node.scale.z)

func _process_transform_fields() -> void:
	if selected_scene_node == null: return
	var pos := Vector3(%PosX.value, %PosY.value, %PosZ.value)
	var rot := Vector3(%RotX.value, %RotY.value, %RotZ.value)
	var scl := Vector3(%SclX.value, %SclY.value, %SclZ.value)
	if not selected_scene_node.position.is_equal_approx(pos): selected_scene_node.position = pos
	if not selected_scene_node.rotation_degrees.is_equal_approx(rot): selected_scene_node.rotation_degrees = rot
	if not selected_scene_node.scale.is_equal_approx(scl): selected_scene_node.scale = scl
	if not selected_object_id.is_empty() and ProjectStore.objects.has(selected_object_id):
		var field_model: MotionObject = ProjectStore.objects[selected_object_id]
		field_model.transform = selected_scene_node.transform
		if auto_key.button_pressed:
			_key_transform()
		if field_model.technical_type == "camera" and camera_view_active and selected_object_id == render_camera_id:
			_sync_editor_view_to_render_camera()

func _on_object_selected(index: int) -> void:
	var id: String = object_list.get_item_metadata(index)
	if id.begins_with("bone::"):
		_select_rig_bone(id)
		return
	if active_rig_runtime != null:
		active_rig_runtime.clear_weight_debug()
	if workspace == "rigging" and not pending_parent_child_id.is_empty():
		if _try_complete_rig_parenting(id): return
	for r in runtime_objects:
		if r.model.id == id: _select(r); return
	if scene_nodes.has(id):
		_select_scene_node(id, scene_nodes[id])

func _pick_rig_bone_at_screen(mouse: Vector2) -> String:
	# Rigging/Animation are puppet-first workspaces. Pick the CURRENT posed
	# skeleton with a deliberately generous hit area before considering artwork.
	if active_rig_id.is_empty() or active_rig_runtime == null: return ""
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null: return ""
	var best_index: int = -1
	var best_distance: float = 34.0
	for bone_index in range(rig.bones.size()):
		var head_in_rig: Vector3 = active_rig_runtime.skeleton.get_bone_global_pose(bone_index).origin
		var tail_in_rig: Vector3 = head_in_rig + Vector3(0.0,0.45,0.0)
		var found_child: bool = false
		for child_index in range(rig.bones.size()):
			if int(rig.bones[child_index].get("parent",-1)) == bone_index:
				tail_in_rig = active_rig_runtime.skeleton.get_bone_global_pose(child_index).origin
				found_child = true
				break
		if not found_child:
			var rest_global: Transform3D = active_rig_runtime.skeleton.get_bone_global_rest(bone_index)
			var pose_global: Transform3D = active_rig_runtime.skeleton.get_bone_global_pose(bone_index)
			var rest_tail_world: Vector3 = active_rig_runtime.terminal_tips[bone_index] if active_rig_runtime.terminal_tips.has(bone_index) else (active_rig_runtime.global_transform * (rest_global.origin + Vector3(0.0,0.45,0.0)))
			var rest_tail_in_rig: Vector3 = active_rig_runtime.global_transform.affine_inverse() * rest_tail_world
			tail_in_rig = pose_global * (rest_global.affine_inverse() * rest_tail_in_rig)
		var head_world: Vector3 = active_rig_runtime.global_transform * head_in_rig
		var tail_world: Vector3 = active_rig_runtime.global_transform * tail_in_rig
		if camera.is_position_behind(head_world) and camera.is_position_behind(tail_world): continue
		var screen_a: Vector2 = camera.unproject_position(head_world)
		var screen_b: Vector2 = camera.unproject_position(tail_world)
		var segment: Vector2 = screen_b - screen_a
		var distance: float = mouse.distance_to(screen_a)
		if segment.length_squared() > 0.001:
			var t: float = clampf((mouse-screen_a).dot(segment)/segment.length_squared(),0.0,1.0)
			distance = mouse.distance_to(screen_a+segment*t)
		if distance < best_distance:
			best_distance = distance
			best_index = bone_index
	return "bone::%s::%d" % [active_rig_id,best_index] if best_index >= 0 else ""

func _select_rig_bone(virtual_id: String) -> void:
	var parts: PackedStringArray = virtual_id.split("::")
	if parts.size() < 3: return
	var rig_id: String = parts[1]
	var bone_index: int = int(parts[2])
	if not rigging_controller.rigs.has(rig_id): return
	var rig: RefCounted = rigging_controller.rigs[rig_id]
	if bone_index < 0 or bone_index >= rig.bones.size(): return
	active_rig_id = rig_id
	active_rig_runtime = scene_nodes.get(rig_id) as Node3D
	selected = null
	selected_object_id = virtual_id
	selected_bone_index = bone_index
	if bone_edit_proxy != null and is_instance_valid(bone_edit_proxy):
		bone_edit_proxy.queue_free()
	bone_edit_proxy = Node3D.new()
	bone_edit_proxy.name = "_BoneEditProxy"
	active_rig_runtime.add_child(bone_edit_proxy)
	# Selection must start from the CURRENT evaluated pose, never from REST.
	# Otherwise every new drag visually jumps the edit handle back to bind pose.
	bone_edit_proxy.transform = active_rig_runtime.skeleton.get_bone_global_pose(bone_index)
	selected_scene_node = bone_edit_proxy
	var bone_name: String = String(rig.bones[bone_index].get("name","Bone"))
	%SelectionLabel.text = bone_name
	_refresh_bone_inspector()
	timeline.set_bone_object(rig_id,bone_index,bone_name)
	gizmo.attach(bone_edit_proxy)
	gizmo.set_mode(TransformGizmo.Mode.ROTATE)
	active_tool = TransformGizmo.Mode.ROTATE
	# Vertex-weight inspection belongs exclusively to the Rigging workspace.
	if active_rig_runtime != null:
		active_rig_runtime.clear_weight_debug()
		if workspace == "rigging":
			for object_id in rig.bindings:
				if not scene_nodes.has(object_id): continue
				var mesh_node: Node3D = scene_nodes[object_id]
				if not mesh_node is MeshInstance3D: continue
				var binding: Dictionary = rig.bindings[object_id]
				var weights: Array = binding.get("bone_weights",[])
				active_rig_runtime.show_weight_debug(mesh_node as MeshInstance3D,weights,bone_index)
	gizmo.visible = workspace != "rigging" and workspace != "animation"
	status.text = "Bone selected · drag directly to pose"

func _draw_ik_guide() -> void:
	if workspace != "rigging" or active_rig_runtime == null or selected_bone_index < 0: return
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null or not rig.ik_constraints.has(selected_bone_index): return
	var data: Dictionary = rig.ik_constraints[selected_bone_index]
	var target_local: Vector3 = data.get("target",Vector3.ZERO)
	var target_world: Vector3 = active_rig_runtime.global_transform * target_local
	var bone_world: Vector3 = active_rig_runtime.global_transform * active_rig_runtime._current_bone_tip(selected_bone_index)
	var a: Vector2 = camera.unproject_position(bone_world)
	var b: Vector2 = camera.unproject_position(target_world)
	var delta: Vector2 = b-a
	var length: float = delta.length()
	if length > 1.0:
		var dir := delta/length
		var d: float = 0.0
		while d < length:
			%IKGuide.draw_line(a+dir*d,a+dir*minf(d+5.0,length),Color(0.55,0.78,0.95,0.8),1.5)
			d += 10.0
	var s := 8.0
	%IKGuide.draw_line(b-Vector2(s,0),b+Vector2(s,0),Color(0.65,0.86,1.0),2.0)
	%IKGuide.draw_line(b-Vector2(0,s),b+Vector2(0,s),Color(0.65,0.86,1.0),2.0)
	%IKGuide.draw_circle(b,4.0,Color(0.65,0.86,1.0),false,2.0)

func _refresh_bone_inspector() -> void:
	%BoneProperties.visible = selected_bone_index >= 0 and not active_rig_id.is_empty()
	if not %BoneProperties.visible: return
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null: return
	var has_ik: bool = rig.ik_constraints.has(selected_bone_index)
	%IKOptions.visible = has_ik
	%IKSolver.visible = not has_ik
	if has_ik:
		var data: Dictionary = rig.ik_constraints[selected_bone_index]
		%IKChainLength.value = int(data.get("chain_length",2))
		%IKInfluence.value = float(data.get("influence",1.0))

func _on_add_ik_solver() -> void:
	if selected_bone_index < 0 or active_rig_runtime == null: return
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null: return
	var target: Vector3 = active_rig_runtime._current_bone_tip(selected_bone_index)
	rig.ik_constraints[selected_bone_index] = {"chain_length":2,"influence":1.0,"target":target}
	%IKGuide.visible = true
	%IKGuide.queue_redraw()
	_refresh_bone_inspector()
	_apply_selected_ik()
	status.text = "IK Solver added · move the selected bone handle to position the target"

func _on_remove_ik_solver() -> void:
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null: return
	rig.ik_constraints.erase(selected_bone_index)
	%IKGuide.visible = false
	%IKGuide.queue_redraw()
	_refresh_bone_inspector()
	status.text = "IK Solver removed"

func _on_ik_settings_changed(_value: float) -> void:
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null or not rig.ik_constraints.has(selected_bone_index): return
	var data: Dictionary = rig.ik_constraints[selected_bone_index]
	data["chain_length"] = int(%IKChainLength.value)
	data["influence"] = float(%IKInfluence.value)
	rig.ik_constraints[selected_bone_index] = data
	_apply_selected_ik()

func _apply_selected_ik() -> void:
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null or active_rig_runtime == null or not rig.ik_constraints.has(selected_bone_index): return
	var data: Dictionary = rig.ik_constraints[selected_bone_index]
	active_rig_runtime.solve_ik(selected_bone_index,data.get("target",Vector3.ZERO),int(data.get("chain_length",2)),float(data.get("influence",1.0)))
	%IKGuide.queue_redraw()

func _on_delete_pressed() -> void:
	if selected_scene_node == null: return
	if selected_scene_node is ReferenceCanvas:
		_delete_reference_canvas(selected_scene_node as ReferenceCanvas)
		return
	if selected != null:
		runtime_objects.erase(selected)
	if not selected_object_id.is_empty():
		scene_object_controller.unregister(selected_object_id)
	selected_scene_node.queue_free()
	selected = null; selected_scene_node = null; selected_object_id = ""
	gizmo.attach(null); timeline.set_object(""); %SelectionLabel.text = "Nothing selected"
	_refresh_scene_object_list()
	status.text = "Object deleted"

func _on_duplicate_pressed() -> void:
	if selected_scene_node == null: return
	if selected_scene_node is ReferenceCanvas:
		_on_plane_duplicate()
		return
	if selected is RuntimeObject and selected.model != null:
		var source := selected as RuntimeObject
		var obj := MotionObject.new(source.model.name + " Copy", source.model.technical_type, source.model.role)
		var copy := RuntimeObject.new()
		world_root.add_child(copy)
		copy.mesh = source.mesh
		copy.texture = source.texture
		copy.material = source.material.duplicate() as ShaderMaterial if source.material else null
		copy.standard_material = source.standard_material.duplicate() as StandardMaterial3D if source.standard_material else null
		copy.material_override = copy.material if copy.material else copy.standard_material
		copy.transform = source.transform
		copy.position += Vector3(0.12,0.0,0.0)
		copy.model = obj
		_register_scene_object(obj,copy)
		runtime_objects.append(copy)
		_select(copy)
		status.text = "Object duplicated"
		return
	status.text = "This object type cannot be duplicated yet"

func _interp_name() -> String:
	var modes: Array[String] = ["constant","linear","bezier","quadratic_in","quadratic_out","quadratic_in_out","cubic_in_out","back","bounce","elastic"]
	return modes[clampi(interpolation.selected, 0, modes.size() - 1)]

func _on_interpolation_item_selected(_index: int) -> void:
	timeline.set_selected_interpolation(_interp_name())

func _key_position() -> void:
	if selected_scene_node == null or selected_object_id.is_empty(): return
	ProjectStore.set_key(selected_object_id,"transform.position",ProjectStore.current_frame,selected_scene_node.position,_interp_name())

func _commit_camera_view_navigation() -> void:
	if not camera_view_active or render_camera_id.is_empty() or not scene_nodes.has(render_camera_id): return
	var rig: Node3D = scene_nodes[render_camera_id]
	var render_cam := _scene_camera_node(render_camera_id)
	if render_cam == null: return
	# In CAM mode the editor camera is the navigation proxy. Commit its exact
	# transform back to the scene camera so leaving CAM preserves the framing.
	rig.global_transform = camera.global_transform
	render_cam.transform = Transform3D.IDENTITY
	if ProjectStore.objects.has(render_camera_id):
		var model: MotionObject = ProjectStore.objects[render_camera_id]
		model.transform = rig.transform
	_show_transform(rig)
	if auto_key.button_pressed:
		ProjectStore.set_key(render_camera_id,"transform.position",ProjectStore.current_frame,rig.position,_interp_name())
		ProjectStore.set_key(render_camera_id,"transform.rotation",ProjectStore.current_frame,rig.rotation,_interp_name())
		ProjectStore.set_key(render_camera_id,"transform.scale",ProjectStore.current_frame,rig.scale,_interp_name())

func _navigate_orbit(delta: Vector2) -> void:
	camera_rig.orbit(delta)
	_commit_camera_view_navigation()

func _navigate_pan(delta: Vector2) -> void:
	camera_rig.pan(delta)
	_commit_camera_view_navigation()

func _navigate_zoom(amount: float) -> void:
	if workspace == "drawing" and not drawing_sculpt_active and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Orthographic cameras do not zoom by changing distance. Adjust the
		# orthographic view height so artwork, bitmap and canvas scale together.
		var factor: float = 0.88 if amount < 0.0 else 1.0 / 0.88
		var min_size: float = 0.05
		var max_size: float = 200.0
		if active_drawing_group != null and is_instance_valid(active_drawing_group):
			min_size = maxf(0.05,active_drawing_group.guide_size.y * 0.02)
			max_size = maxf(active_drawing_group.guide_size.y * 20.0,2.0)
		camera.size = clampf(camera.size * factor,min_size,max_size)
		return
	camera_rig.zoom(amount)
	_commit_camera_view_navigation()

func _on_canvas_gui_input(event: InputEvent) -> void:
	if workspace == "drawing":
		if event is InputEventScreenDrag:
			var screen_drag := event as InputEventScreenDrag
			current_stylus_pressure = _stylus_pressure_or_full(screen_drag.pressure)
		if %DrawingCanvas.bitmap_mode:
			%DrawingCanvas.input_pressure = current_stylus_pressure
		if _gradient_guide_input(event): return
		# Normal Drawing is a canvas-locked 2D editor. Sculpt is the exception:
		# it operates in a freely navigable 3D view so stroke depth is visible.
		if not drawing_sculpt_active and camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		if event is InputEventMouseButton:
			last_mouse = event.position
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_navigate_zoom(-1.0); return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_navigate_zoom(1.0); return
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				if drawing_sculpt_active:
					if Input.is_key_pressed(KEY_SHIFT):
						panning = event.pressed
						orbiting = false
					else:
						orbiting = event.pressed
						panning = false
				else:
					panning = event.pressed
					orbiting = false
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if workspace == "rigging" and rig_bone_draw_active:
					if event.pressed: _add_rig_bone_point(event.position)
					return
				if drawing_3d_active:
					if event.pressed: _begin_3d_stroke(event.position)
					else: _finish_3d_stroke()
					return
				elif drawing_erase_active:
					if event.pressed:
						_push_vector_undo()
						_erase_drawing(event.position)
					return
				elif drawing_sculpt_active:
					if event.pressed:
						_push_vector_undo()
						for child in active_drawing_group.get_children() if active_drawing_group else []:
							if child is Stroke3D: (child as Stroke3D).begin_sculpt(event.position,camera,maxf(12.0,%BrushSize.value*2.5))
						_sculpt_drawing(event.position)
					else:
						for child in active_drawing_group.get_children() if active_drawing_group else []:
							if child is Stroke3D: (child as Stroke3D).end_sculpt()
					return
		elif event is InputEventMouseMotion:
			last_mouse = event.position
			var drawing_motion := event as InputEventMouseMotion
			current_stylus_pressure = _stylus_pressure_or_full(drawing_motion.pressure)
			if %DrawingCanvas.bitmap_mode:
				%DrawingCanvas.input_pressure = current_stylus_pressure
			if orbiting:
				_navigate_orbit(event.relative); return
			elif panning:
				_navigate_pan(event.relative); return
			elif drawing_3d_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_extend_3d_stroke(event.position); return
			elif drawing_erase_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_erase_drawing(event.position)
				return
			elif drawing_sculpt_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_sculpt_drawing(event.position); return
	if event is InputEventMouseButton:
		last_mouse = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: _navigate_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: _navigate_zoom(1.0)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if Input.is_key_pressed(KEY_SHIFT): panning = event.pressed
			else: orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if workspace == "rigging" and rig_bone_draw_active:
				if event.pressed: _add_rig_bone_point(event.position)
				return
			if event.pressed:
				# RIGGING is bone-first: viewport clicks try visible bones before
				# artwork. This avoids selecting the skinned mesh while posing.
				if (workspace == "rigging" or workspace == "animation") and not rig_bone_draw_active:
					var picked_bone: String = _pick_rig_bone_at_screen(event.position)
					if not picked_bone.is_empty():
						_select_rig_bone(picked_bone)
						_begin_direct_bone_drag(event.position)
						return
				gizmo_axis = gizmo.pick_axis(event.position, camera) if selected_scene_node else TransformGizmo.Axis.NONE
				if gizmo_axis != TransformGizmo.Axis.NONE:
					dragging = true; transform_start = selected_scene_node.transform; drag_start_mouse = event.position
					return
				var hit := _pick(event.position)
				if hit != null:
					_select(hit); dragging = true
					var world := _screen_to_view_plane(event.position, hit.global_position)
					drag_offset = hit.global_position - world
				else:
					var scene_hit := _pick_scene_anchor(event.position)
					if scene_hit != null:
						var scene_hit_id: String = _scene_node_id(scene_hit)
						_select_scene_node(scene_hit_id, scene_hit)
						dragging = true
						transform_start = scene_hit.transform
						drag_start_mouse = event.position
						return
					var canvas_hit := _pick_reference_canvas(event.position)
					if canvas_hit != null:
						_select_scene_node(_reference_canvas_id(canvas_hit), canvas_hit)
						active_drawing_group = canvas_hit
						active_drawing_id = selected_object_id
						return
					selected = null; selected_scene_node = null; selected_object_id = ""; gizmo.attach(null)
					for r in runtime_objects: r.set_selected(false)
					object_list.deselect_all(); timeline.set_object(""); %SelectionLabel.text = "Nothing selected"
			else:
				if direct_bone_drag:
					if auto_key.button_pressed:
						if ik_drag_active:
							_key_selected_ik_target()
						elif workspace == "animation":
							_key_bone_pose()
					direct_bone_drag = false
					ik_drag_active = false
				elif dragging and auto_key.button_pressed:
					_key_transform()
				dragging = false; gizmo_axis = TransformGizmo.Axis.NONE
	elif event is InputEventMouseMotion:
		if orbiting: _navigate_orbit(event.relative)
		elif panning: _navigate_pan(event.relative)
		elif direct_bone_drag and selected_scene_node:
			_apply_direct_bone_drag(event.position)
		elif dragging and selected_scene_node:
			_apply_drag(event.relative, event.position)
		last_mouse = event.position

func _begin_direct_bone_drag(mouse_pos: Vector2) -> void:
	if bone_edit_proxy == null or not is_instance_valid(bone_edit_proxy): return
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig != null and rig.ik_constraints.has(selected_bone_index):
		ik_drag_active = true
		direct_bone_drag = true
		dragging = false
		drag_start_mouse = mouse_pos
		return
	direct_bone_drag = true
	dragging = false
	gizmo_axis = TransformGizmo.Axis.NONE
	transform_start = bone_edit_proxy.transform
	drag_start_mouse = mouse_pos
	# Direct manipulation is the primary puppet interaction. The technical
	# transform gizmo remains available, but is not required.
	gizmo.visible = false

func _apply_direct_bone_drag(mouse_pos: Vector2) -> void:
	if bone_edit_proxy == null or active_rig_runtime == null or selected_bone_index < 0: return
	if ik_drag_active:
		var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
		if rig != null and rig.ik_constraints.has(selected_bone_index):
			var data: Dictionary = rig.ik_constraints[selected_bone_index]
			var current_target: Vector3 = data.get("target",active_rig_runtime._current_bone_tip(selected_bone_index))
			var world_target: Vector3 = active_rig_runtime.global_transform * current_target
			var new_world: Vector3 = _screen_to_view_plane(mouse_pos,world_target)
			data["target"] = active_rig_runtime.global_transform.affine_inverse() * new_world
			rig.ik_constraints[selected_bone_index] = data
			_apply_selected_ik()
			%IKGuide.queue_redraw()
			return
	var pivot_world: Vector3 = active_rig_runtime.global_transform * transform_start.origin
	var pivot_screen: Vector2 = camera.unproject_position(pivot_world)
	var start_vec: Vector2 = drag_start_mouse - pivot_screen
	var current_vec: Vector2 = mouse_pos - pivot_screen
	if start_vec.length_squared() < 4.0 or current_vec.length_squared() < 4.0: return
	var angle: float = start_vec.angle_to(current_vec)
	bone_edit_proxy.transform = transform_start
	bone_edit_proxy.rotate(camera.global_transform.basis.z.normalized(),angle)
	_sync_selected_scene_transform()

func _bone_channel_path(bone_index: int, component: String) -> String:
	return "rig.bone.%d.%s" % [bone_index,component]

func _ik_target_channel_path(bone_index: int) -> String:
	return "rig.ik_control.%d.position" % bone_index

func _key_selected_ik_target() -> void:
	if active_rig_id.is_empty() or selected_bone_index < 0: return
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null or not rig.ik_constraints.has(selected_bone_index): return
	var data: Dictionary = rig.ik_constraints[selected_bone_index]
	var target: Vector3 = data.get("target",Vector3.ZERO)
	ProjectStore.set_key(active_rig_id,_ik_target_channel_path(selected_bone_index),ProjectStore.current_frame,target,_interp_name())
	timeline.set_ik_object(active_rig_id,selected_bone_index,String(rig.bones[selected_bone_index].get("name","Bone"))+" · IK")
	timeline.refresh_keys()
	status.text = "IK target keyed · frame %d" % ProjectStore.current_frame

func _key_bone_pose() -> void:
	if active_rig_id.is_empty() or active_rig_runtime == null or selected_bone_index < 0: return
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if rig == null: return
	var pose_global: Transform3D = active_rig_runtime.skeleton.get_bone_global_pose(selected_bone_index)
	var parent_index: int = int(rig.bones[selected_bone_index].get("parent",-1))
	var pose_local: Transform3D = pose_global
	if parent_index >= 0:
		var parent_global: Transform3D = active_rig_runtime.skeleton.get_bone_global_pose(parent_index)
		pose_local = parent_global.affine_inverse() * pose_global
	var interpolation_name: String = _interp_name()
	# Bone animation uses explicit components, just like native skeleton tracks.
	# This also fits KABUKI's generic "every property is a channel" model.
	ProjectStore.set_key(active_rig_id,_bone_channel_path(selected_bone_index,"position"),ProjectStore.current_frame,pose_local.origin,interpolation_name)
	ProjectStore.set_key(active_rig_id,_bone_channel_path(selected_bone_index,"rotation"),ProjectStore.current_frame,pose_local.basis.get_rotation_quaternion(),interpolation_name)
	ProjectStore.set_key(active_rig_id,_bone_channel_path(selected_bone_index,"scale"),ProjectStore.current_frame,pose_local.basis.get_scale(),interpolation_name)
	timeline.set_bone_object(active_rig_id,selected_bone_index,String(rig.bones[selected_bone_index].get("name","Bone")))
	status.text = "Bone pose keyed · frame %d" % ProjectStore.current_frame

func _evaluate_rig_animation(frame: int) -> void:
	for rig_id_value in rigging_controller.rigs.keys():
		var rig_id: String = String(rig_id_value)
		if not scene_nodes.has(rig_id): continue
		var runtime: Node3D = scene_nodes[rig_id]
		if not runtime is RigRuntime: continue
		var rig: RefCounted = rigging_controller.rigs[rig_id]
		for bone_index in range(rig.bones.size()):
			var rest: Transform3D = runtime.skeleton.get_bone_rest(bone_index)
			var position_value: Variant = ProjectStore.evaluate(rig_id,_bone_channel_path(bone_index,"position"),frame,rest.origin)
			var rotation_value: Variant = ProjectStore.evaluate(rig_id,_bone_channel_path(bone_index,"rotation"),frame,rest.basis.get_rotation_quaternion())
			var scale_value: Variant = ProjectStore.evaluate(rig_id,_bone_channel_path(bone_index,"scale"),frame,rest.basis.get_scale())
			if position_value is Vector3 and rotation_value is Quaternion and scale_value is Vector3:
				var evaluated := Transform3D(Basis(rotation_value).scaled(scale_value),position_value)
				runtime.set_bone_pose(bone_index,evaluated)
		for ik_key in rig.ik_constraints.keys():
			var ik_bone: int = int(ik_key)
			var ik_data: Dictionary = rig.ik_constraints[ik_key]
			var fallback_target: Vector3 = ik_data.get("target",Vector3.ZERO)
			var target_value: Variant = ProjectStore.evaluate(rig_id,_ik_target_channel_path(ik_bone),frame,fallback_target)
			if target_value is Vector3:
				ik_data["target"] = target_value
				rig.ik_constraints[ik_key] = ik_data
				runtime.solve_ik(ik_bone,target_value,int(ik_data.get("chain_length",2)),float(ik_data.get("influence",1.0)))
	if selected_object_id.begins_with("bone::") and bone_edit_proxy != null and is_instance_valid(bone_edit_proxy) and active_rig_runtime != null and selected_bone_index >= 0:
		bone_edit_proxy.transform = active_rig_runtime.skeleton.get_bone_global_pose(selected_bone_index)

func _apply_drag(relative: Vector2, mouse_pos: Vector2) -> void:
	var target := selected_scene_node
	if target == null: return
	if gizmo_axis != TransformGizmo.Axis.NONE:
		var total := mouse_pos - drag_start_mouse
		if gizmo_axis == TransformGizmo.Axis.ALL:
			if active_tool == TransformGizmo.Mode.MOVE:
				target.global_position = _screen_to_view_plane(mouse_pos, transform_start.origin)
			elif active_tool == TransformGizmo.Mode.ROTATE:
				target.transform = transform_start
				target.rotate(camera.global_transform.basis.z.normalized(), total.x * 0.012)
			elif active_tool == TransformGizmo.Mode.SCALE:
				target.transform = transform_start
				target.scale = transform_start.basis.get_scale() * maxf(0.03, 1.0 + (total.x - total.y) * 0.01)
			_refresh_transform_readout()
			_sync_selected_scene_transform()
			return
		var axis := gizmo.axis_vector(gizmo_axis)
		var amount := (total.x - total.y) * 0.006 * camera_rig.distance
		if active_tool == TransformGizmo.Mode.MOVE:
			target.position = transform_start.origin + axis * amount
		elif active_tool == TransformGizmo.Mode.ROTATE:
			target.transform = transform_start
			target.rotate(axis, (total.x - total.y) * 0.012)
		elif active_tool == TransformGizmo.Mode.SCALE:
			target.transform = transform_start
			var sc := target.scale
			var factor := maxf(0.03, 1.0 + (total.x - total.y) * 0.01)
			if gizmo_axis == 0: sc.x *= factor
			elif gizmo_axis == 1: sc.y *= factor
			else: sc.z *= factor
			target.scale = sc
		_refresh_transform_readout()
		_sync_selected_scene_transform()

func _sync_selected_scene_transform() -> void:
	if selected_scene_node == null: return
	if selected_object_id.begins_with("bone::") and active_rig_runtime != null and selected_bone_index >= 0:
		var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
		if rig == null or selected_bone_index >= rig.bones.size(): return
		var pose_global_in_rig: Transform3D = selected_scene_node.transform
		var parent_index: int = int(rig.bones[selected_bone_index].get("parent",-1))
		var pose_local: Transform3D = pose_global_in_rig
		if parent_index >= 0:
			var parent_global: Transform3D = active_rig_runtime.skeleton.get_bone_global_pose(parent_index)
			pose_local = parent_global.affine_inverse() * pose_global_in_rig
		active_rig_runtime.set_bone_pose(selected_bone_index,pose_local)
		active_rig_runtime.clear_weight_debug()
		status.text = "Bone pose · drag rotation gizmo to test deformation"
		return
	if selected:
		selected.model.transform = selected.transform
	elif not selected_object_id.is_empty() and ProjectStore.objects.has(selected_object_id):
		var transformed_model: MotionObject = ProjectStore.objects[selected_object_id]
		transformed_model.transform = selected_scene_node.transform
		if transformed_model.technical_type == "camera" and camera_view_active and selected_object_id == render_camera_id:
			_sync_editor_view_to_render_camera()
	elif selected_scene_node is ReferenceCanvas:
		var reference_canvas := selected_scene_node as ReferenceCanvas
		if reference_canvas.model:
			reference_canvas.model.transform = reference_canvas.transform

func _screen_to_view_plane(pos: Vector2, point: Vector3) -> Vector3:
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var normal := -camera.global_transform.basis.z
	var denom := dir.dot(normal)
	if absf(denom) < 0.0001: return point
	var t := (point - origin).dot(normal) / denom
	return origin + dir * t

func _canvas_basis_for_axis(axis_name: String) -> Basis:
	match axis_name:
		"X":
			# local XY -> world YZ, local Z (canvas normal) -> world +X
			return Basis(Vector3(0,1,0),Vector3(0,0,1),Vector3(1,0,0))
		"Y":
			# local XY -> world XZ, normal -> world +Y
			return Basis(Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,1,0))
		_:
			return Basis.IDENTITY

func _canvas_axis_from_plane(plane: ReferenceCanvas) -> String:
	var normal: Vector3 = plane.global_transform.basis.z.normalized()
	var ax := absf(normal.x)
	var ay := absf(normal.y)
	var az := absf(normal.z)
	if ax >= ay and ax >= az: return "X"
	if ay >= ax and ay >= az: return "Y"
	return "Z"

func _sync_canvas_axis_buttons() -> void:
	if active_drawing_group == null or not is_instance_valid(active_drawing_group): return
	var axis_name := _canvas_axis_from_plane(active_drawing_group)
	%CanvasAxisX.set_pressed_no_signal(axis_name == "X")
	%CanvasAxisY.set_pressed_no_signal(axis_name == "Y")
	%CanvasAxisZ.set_pressed_no_signal(axis_name == "Z")

func _set_active_canvas_axis(axis_name: String) -> void:
	if active_drawing_group == null or not is_instance_valid(active_drawing_group): return
	var origin := active_drawing_group.global_position
	active_drawing_group.global_transform = Transform3D(_canvas_basis_for_axis(axis_name),origin)
	_sync_canvas_axis_buttons()
	_lock_drawing_view_to_canvas()
	status.text = "Canvas plane · normal " + axis_name

func _lock_drawing_view_to_canvas() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	orbiting = false
	# ReferenceCanvas local XY is the drawing surface. Match the editor camera
	# to its world orientation and look perpendicular to local Z.
	if active_drawing_group != null and is_instance_valid(active_drawing_group):
		var canvas_xform: Transform3D = active_drawing_group.global_transform
		var distance: float = maxf(2.0,(camera.global_position-active_drawing_group.global_position).length())
		var view_basis: Basis = canvas_xform.basis.orthonormalized()
		var normal: Vector3 = view_basis.z.normalized()
		camera.global_transform = Transform3D(view_basis,active_drawing_group.global_position+normal*distance)
		camera.look_at(active_drawing_group.global_position,view_basis.y.normalized())
		# In orthographic mode camera distance does not define framing. Match the
		# ReferenceCanvas height explicitly so screen-space drawing coordinates map
		# 1:1 onto its local XY plane instead of inheriting an arbitrary ortho size.
		camera.size = active_drawing_group.guide_size.y
		# Let the rig adopt this exact camera transform so pan/zoom continue from it.
		camera_rig.align_transform(camera.global_transform)
	_capture_projection_view()

func _align_view_axis(axis: Vector3, label: String) -> void:
	camera_rig.align_axis(axis)
	if workspace == "drawing":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_capture_projection_view()
	status.text = "View aligned to " + label

func _capture_projection_view() -> void:
	projection_view_transform = camera.global_transform
	projection_view_valid = true

func _restore_projection_view() -> void:
	if not projection_view_valid:
		status.text = "No drawing projection view saved yet"
		return
	camera_rig.align_transform(projection_view_transform)
	status.text = "Drawing projection view restored"

func _sync_transform_tool_buttons() -> void:
	var move_button := get_node_or_null("ToolRail/MoveTool") as Button
	var rotate_button := get_node_or_null("ToolRail/RotateTool") as Button
	var scale_button := get_node_or_null("ToolRail/ScaleTool") as Button
	if move_button: move_button.button_pressed = active_tool == TransformGizmo.Mode.MOVE
	if rotate_button: rotate_button.button_pressed = active_tool == TransformGizmo.Mode.ROTATE
	if scale_button: scale_button.button_pressed = active_tool == TransformGizmo.Mode.SCALE

func _on_tool_move_pressed() -> void:
	active_tool = TransformGizmo.Mode.MOVE; gizmo.set_mode(active_tool); _sync_transform_tool_buttons(); status.text = "Move tool"
func _on_tool_rotate_pressed() -> void:
	active_tool = TransformGizmo.Mode.ROTATE; gizmo.set_mode(active_tool); _sync_transform_tool_buttons(); status.text = "Rotate tool"
func _on_tool_scale_pressed() -> void:
	active_tool = TransformGizmo.Mode.SCALE; gizmo.set_mode(active_tool); _sync_transform_tool_buttons(); status.text = "Scale tool"
func _on_frame_selected_pressed() -> void:
	if selected_scene_node: camera_rig.frame_target(selected_scene_node.global_position)

func _on_grid_toggled(enabled: bool) -> void:
	world_grid.visible = enabled

func _key_transform() -> void:
	if selected_scene_node == null or selected_object_id.is_empty(): return
	ProjectStore.set_key(selected_object_id,"transform.position",ProjectStore.current_frame,selected_scene_node.position,_interp_name())
	ProjectStore.set_key(selected_object_id,"transform.rotation",ProjectStore.current_frame,selected_scene_node.rotation,_interp_name())
	ProjectStore.set_key(selected_object_id,"transform.scale",ProjectStore.current_frame,selected_scene_node.scale,_interp_name())

func _pick(pos: Vector2) -> RuntimeObject:
	var best: RuntimeObject = null
	var best_d := 999999.0
	for i in range(runtime_objects.size()-1,-1,-1):
		var r: RuntimeObject = runtime_objects[i]
		if not is_instance_valid(r):
			runtime_objects.remove_at(i)
			continue
		var sp := camera.unproject_position(r.global_position)
		var radius := maxf(28.0, r.screen_radius(camera, viewport.size))
		var d := sp.distance_to(pos)
		if d <= radius and d < best_d: best = r; best_d = d
	return best

func _scene_node_id(node: Node3D) -> String:
	for object_id in scene_nodes:
		if scene_nodes[object_id] == node: return String(object_id)
	return ""

func _pick_scene_anchor(pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := 28.0
	for object_id in scene_nodes:
		var node: Node3D = scene_nodes[object_id]
		if not is_instance_valid(node) or node is ReferenceCanvas: continue
		var model: MotionObject = ProjectStore.objects.get(object_id)
		if model == null: continue
		# Camera/light/audio anchors are not RuntimeObjects, so they need their
		# own editor picking path.
		if model.technical_type not in ["camera","light","audio_clip","drawing"]: continue
		if camera.is_position_behind(node.global_position): continue
		var screen_pos := camera.unproject_position(node.global_position)
		var d := screen_pos.distance_to(pos)
		if d < best_d:
			best = node
			best_d = d
	return best

func _pick_reference_canvas(pos: Vector2) -> ReferenceCanvas:
	var best: ReferenceCanvas = null
	var best_d := 18.0
	for reference_canvas in drawing_planes:
		if not is_instance_valid(reference_canvas): continue
		var center := camera.unproject_position(reference_canvas.global_position)
		# Guides are reference frames, so picking near their projected center/cross
		# is enough and does not require collision/render geometry.
		var d := center.distance_to(pos)
		if d < best_d:
			best = reference_canvas
			best_d = d
	return best

func _reference_canvas_id(reference_canvas: ReferenceCanvas) -> String:
	for object_id in scene_nodes:
		if scene_nodes[object_id] == reference_canvas: return object_id
	return ""

func _screen_to_plane(pos: Vector2, z_plane: float) -> Vector3:
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	if absf(dir.z) < 0.0001: return Vector3.ZERO
	var t := (z_plane - origin.z) / dir.z
	return origin + dir * t

func _on_frame_changed(frame: int) -> void:
	frame_label.text = "%03d" % frame
	frame_slider.set_value_no_signal(frame)
	timeline.set_frame(frame)
	for r in runtime_objects: r.apply_frame(frame)
	_evaluate_rig_animation(frame)
	# Generic scene anchors (camera, lights, audio...) also live on the global
	# timeline. RuntimeObject already evaluates itself above.
	for object_id in scene_nodes:
		var node: Node3D = scene_nodes[object_id]
		if not is_instance_valid(node) or node is RuntimeObject or node is ReferenceCanvas: continue
		if not ProjectStore.objects.has(object_id): continue
		var model: MotionObject = ProjectStore.objects[object_id]
		node.position = ProjectStore.evaluate(object_id, "transform.position", frame, model.transform.origin)
		node.rotation = ProjectStore.evaluate(object_id, "transform.rotation", frame, model.transform.basis.get_euler())
		node.scale = ProjectStore.evaluate(object_id, "transform.scale", frame, model.transform.basis.get_scale())
		if model.technical_type == "camera":
			var scene_cam := _scene_camera_node(object_id)
			if scene_cam:
				scene_cam.fov = float(ProjectStore.evaluate(object_id, "camera.fov", frame, model.properties.get("camera.fov",70.0)))
				var attrs := scene_cam.attributes as CameraAttributesPractical
				if attrs:
					attrs.dof_blur_far_distance = float(ProjectStore.evaluate(object_id, "camera.focus_distance", frame, model.properties.get("camera.focus_distance",3.0)))
					attrs.dof_blur_near_distance = attrs.dof_blur_far_distance
					attrs.dof_blur_amount = float(ProjectStore.evaluate(object_id, "camera.aperture", frame, model.properties.get("camera.aperture",0.2)))
			if camera_view_active and object_id == render_camera_id: _sync_editor_view_to_render_camera()
	for reference_canvas in drawing_planes:
		if not is_instance_valid(reference_canvas) or reference_canvas.model == null: continue
		reference_canvas.position = ProjectStore.evaluate(reference_canvas.model.id, "transform.position", frame, reference_canvas.model.transform.origin)
		reference_canvas.rotation = ProjectStore.evaluate(reference_canvas.model.id, "transform.rotation", frame, reference_canvas.rotation)
		reference_canvas.scale = ProjectStore.evaluate(reference_canvas.model.id, "transform.scale", frame, reference_canvas.scale)
	_apply_drawing_frame(frame)
	# Timeline exposure markers only change when editing cels, not while merely
	# playing/scrubbing frames. Avoid rebuilding them every playback tick.

func _apply_drawing_frame(frame: int) -> void:
	for object_id in drawing_data_by_object.keys():
		if not scene_nodes.has(object_id): continue
		var model: MotionObject = ProjectStore.objects.get(object_id)
		var group: Node3D = scene_nodes[object_id]
		if model != null and not model.visible:
			_set_visual_visibility_recursive(group,false)
			continue
		var data: RefCounted = drawing_data_by_object[object_id]
		var evaluation_frame: int = drawing_controller.local_frame(object_id, frame, workspace == "drawing" and object_id == active_drawing_id)
		var pose: Dictionary = drawing_controller.pose(object_id, evaluation_frame)
		var same_drawing_frame: bool = not drawing_controller.needs_pose_update(object_id, evaluation_frame)
		# Bitmap drawings are cached as discrete images and played as a texture
		# sequence on the ReferenceCanvas plane. No tessellation is required.
		if group is ReferenceCanvas:
			var reference_canvas := group as ReferenceCanvas
			var has_bitmap: bool = %DrawingCanvas.has_flipbook(object_id)
			if has_bitmap:
				# Every persisted bitmap cel has a scene representation. A single
				# static cel must remain visible when the bitmap editor overlay is hidden.
				var editing_active_bitmap: bool = workspace == "drawing" and object_id == active_drawing_id and %DrawingCanvas.bitmap_mode
				var static_is_current: bool = static_bitmap_runtime.has(object_id) and not %DrawingCanvas.is_bitmap_dirty(object_id) and %DrawingCanvas.keyed_cel_count(object_id) <= 1
				if editing_active_bitmap:
					reference_canvas.hide_flipbook_image()
				elif static_is_current:
					reference_canvas.hide_flipbook_image()
				else:
					var bitmap_image: Image = %DrawingCanvas.flipbook_image(object_id, evaluation_frame)
					reference_canvas.show_flipbook_image(bitmap_image)
				if static_bitmap_runtime.has(object_id):
					var cached_static: RuntimeObject = static_bitmap_runtime[object_id]
					if is_instance_valid(cached_static): cached_static.visible = static_is_current and not editing_active_bitmap
			else:
				reference_canvas.hide_flipbook_image()
				if static_bitmap_runtime.has(object_id):
					var cached_static: RuntimeObject = static_bitmap_runtime[object_id]
					if is_instance_valid(cached_static): cached_static.visible = true
		# HOLD/flipbook playback often maps several scene frames to the same local
		# cel. Its stroke geometry and visibility are already correct, so avoid
		# walking every Stroke3D child until the evaluated local frame changes.
		var editing_active_vector: bool = workspace == "drawing" and object_id == active_drawing_id and not %DrawingCanvas.bitmap_mode
		if same_drawing_frame and not editing_active_vector: continue
		for child in group.get_children():
			if not child is Stroke3D: continue
			if child.has_meta("onion_ghost") and bool(child.get_meta("onion_ghost")): continue
			var stroke := child as Stroke3D
			if stroke.stroke_id.is_empty(): continue
			if not pose.has(stroke.stroke_id):
				stroke.visible = false
				continue
			var state: Dictionary = pose[stroke.stroke_id]
			stroke.visible = bool(state.get("visible", true))
			if data.strokes.has(stroke.stroke_id):
				var record: Dictionary = data.strokes[stroke.stroke_id]
				stroke.stroke_color = record.get("color", stroke.stroke_color)
				stroke.fill_enabled = bool(record.get("fill_enabled", stroke.fill_enabled))
				stroke.fill_color = record.get("fill_color", stroke.fill_color)
			stroke.set_points(state.get("points", stroke.points))
		if editing_active_vector:
			_refresh_vector_onion_skin(group,data,evaluation_frame)

func _active_drawing_data() -> RefCounted:
	if active_drawing_id.is_empty(): return null
	return drawing_controller.active_data(active_drawing_id)

func _drawing_edit_frame() -> int:
	var data: RefCounted = _active_drawing_data()
	if data == null: return ProjectStore.current_frame
	return int(data.local_frame) if workspace == "drawing" else ProjectStore.current_frame

func _sync_local_clip_ui() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	%LocalTimelineLabel.text = "LOCAL · " + active_drawing_group.name if active_drawing_group else "LOCAL"
	%LocalDuration.set_value_no_signal(data.local_duration)
	%LocalPlaybackStart.set_value_no_signal(data.local_playback_start)
	%LocalPlaybackEnd.set_value_no_signal(data.local_playback_end)
	%SceneStart.set_value_no_signal(data.scene_start)
	%HoldFrames.set_value_no_signal(data.hold_frames)
	var modes: Array[String] = ["loop","ping_pong","hold","loop_hold"]
	%ClipMode.select(maxi(0,modes.find(String(data.playback_mode))))
	var show_hold: bool = String(data.playback_mode) == "loop_hold"
	%HoldFramesLabel.visible = show_hold
	%HoldFrames.visible = show_hold
	# The bottom Animation timeline is always the scene/global timeline.
	# Drawing has its own LOCAL clip controls above it; never repurpose the
	# shared global timeline for a canvas clip.
	timeline.set_timeline_range(ProjectStore.duration_frames,ProjectStore.playback_start,ProjectStore.playback_end)
	timeline.set_frame(ProjectStore.current_frame)
	timeline.queue_redraw()

func _on_clip_mode_selected(index: int) -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	var modes: Array[String] = ["loop","ping_pong","hold","loop_hold"]
	data.playback_mode = modes[clampi(index,0,modes.size()-1)]
	var show_hold: bool = data.playback_mode == "loop_hold"
	%HoldFramesLabel.visible = show_hold
	%HoldFrames.visible = show_hold

func _on_local_duration_changed(value: float) -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	data.set_local_duration(maxi(1,int(value)))
	_sync_local_clip_ui()

func _on_local_playback_start_changed(value: float) -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	data.set_local_playback_range(int(value),maxi(int(value),int(data.local_playback_end)))
	_sync_local_clip_ui()

func _on_local_playback_end_changed(value: float) -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	data.set_local_playback_range(int(data.local_playback_start),int(value))
	_sync_local_clip_ui()

func _on_timeline_duration_changed(value: float) -> void:
	ProjectStore.duration_frames=maxi(1,int(value))
	ProjectStore.playback_start=clampi(ProjectStore.playback_start,0,ProjectStore.duration_frames)
	ProjectStore.playback_end=clampi(ProjectStore.playback_end,ProjectStore.playback_start,ProjectStore.duration_frames)
	%PlaybackStart.set_value_no_signal(ProjectStore.playback_start)
	%PlaybackEnd.set_value_no_signal(ProjectStore.playback_end)
	timeline.set_timeline_range(ProjectStore.duration_frames,ProjectStore.playback_start,ProjectStore.playback_end)
	ProjectStore.project_changed.emit()

func _on_playback_start_changed(value: float) -> void:
	ProjectStore.playback_start=clampi(int(value),0,ProjectStore.duration_frames)
	ProjectStore.playback_end=maxi(ProjectStore.playback_end,ProjectStore.playback_start)
	%PlaybackEnd.set_value_no_signal(ProjectStore.playback_end)
	timeline.set_timeline_range(ProjectStore.duration_frames,ProjectStore.playback_start,ProjectStore.playback_end)
	ProjectStore.project_changed.emit()

func _on_playback_end_changed(value: float) -> void:
	ProjectStore.playback_end=clampi(int(value),ProjectStore.playback_start,ProjectStore.duration_frames)
	timeline.set_timeline_range(ProjectStore.duration_frames,ProjectStore.playback_start,ProjectStore.playback_end)
	ProjectStore.project_changed.emit()

func _on_scene_start_changed(value: float) -> void:
	var data: RefCounted = _active_drawing_data()
	if data != null: data.scene_start = maxi(0,int(value))

func _on_hold_frames_changed(value: float) -> void:
	var data: RefCounted = _active_drawing_data()
	if data != null:
		data.hold_frames = maxi(0,int(value))

func _refresh_drawing_timeline() -> void:
	var data: RefCounted = _active_drawing_data()
	var frames: Array[int] = []
	if data != null:
		var raw_frames: Array = data.call("exposure_frames")
		for frame_value in raw_frames:
			frames.append(int(frame_value))
	if %DrawingCanvas.bitmap_mode:
		frames = %DrawingCanvas.flipbook_frames()
	if data != null:
		local_drawing_timeline.set_timeline_range(maxi(1,int(data.local_duration)-1),int(data.local_playback_start),int(data.local_playback_end))
		local_drawing_timeline.set_frame(int(data.local_frame))
		local_drawing_timeline.set_drawing_exposures(frames)
	_sync_local_clip_ui()

func _on_drawing_new_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	_push_vector_undo()
	var empty_pose: Dictionary = {}
	for stroke_id in data.stroke_order:
		empty_pose[stroke_id] = {"points": (data.strokes[stroke_id]["points"] as PackedVector3Array).duplicate(), "visible": false}
	data.ensure_flipbook_cel(_drawing_edit_frame())
	data.set_exposure(_drawing_edit_frame(), empty_pose, "hold")
	_apply_drawing_frame(ProjectStore.current_frame)
	_refresh_drawing_timeline()
	status.text = "Empty drawing cel · local frame %d" % _drawing_edit_frame()

func _on_drawing_duplicate_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	_push_vector_undo()
	if data.duplicate_previous_exposure(_drawing_edit_frame()):
		_apply_drawing_frame(ProjectStore.current_frame)
		_refresh_drawing_timeline()
		status.text = "Drawing cel duplicated · frame %d" % ProjectStore.current_frame

func _on_drawing_delete_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	_push_vector_undo()
	data.remove_exposure(_drawing_edit_frame())
	_apply_drawing_frame(ProjectStore.current_frame)
	_refresh_drawing_timeline()
	status.text = "Drawing cel deleted · frame %d" % ProjectStore.current_frame

func _on_drawing_hold_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	if not data.has_exposure(_drawing_edit_frame()):
		data.set_exposure(_drawing_edit_frame(), data.snapshot_pose(), "hold")
	data.set_exposure_interpolation(_drawing_edit_frame(), "hold")
	_refresh_drawing_timeline()
	status.text = "Cel interpolation · HOLD"

func _on_drawing_morph_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	if not data.has_exposure(ProjectStore.current_frame):
		data.set_exposure(_drawing_edit_frame(), data.snapshot_pose(), "linear")
	data.set_exposure_interpolation(_drawing_edit_frame(), "linear")
	_refresh_drawing_timeline()
	status.text = "Cel interpolation · MORPH"

func _on_onion_skin_toggled(enabled: bool) -> void:
	%DrawingCanvas.set_onion_skin_enabled(enabled)
	_apply_drawing_frame(ProjectStore.current_frame)
	if not enabled:
		for object_id in vector_onion_roots.keys():
			var root = vector_onion_roots[object_id]
			if is_instance_valid(root):
				root.visible = false
				_clear_vector_onion_root(root)
	status.text = "Onion skin on" if enabled else "Onion skin off"

func _vector_onion_root(group: Node3D,object_id: String) -> Node3D:
	if vector_onion_roots.has(object_id):
		var existing = vector_onion_roots[object_id]
		if is_instance_valid(existing): return existing
	var root := Node3D.new()
	root.name = "__VectorOnionSkin"
	group.add_child(root)
	vector_onion_roots[object_id] = root
	return root

func _clear_vector_onion_root(root: Node3D) -> void:
	# Ghosts are transient editor-only geometry. Remove them synchronously so a
	# frame change can never render both the stale and newly generated copies.
	for child in root.get_children():
		root.remove_child(child)
		child.free()

func _add_vector_onion_pose(root: Node3D,data: RefCounted,pose: Dictionary,tint: Color) -> void:
	for stroke_id in pose:
		if not data.strokes.has(stroke_id): continue
		var state: Dictionary = pose[stroke_id]
		if not bool(state.get("visible",false)): continue
		var record: Dictionary = data.strokes[stroke_id]
		var ghost: Stroke3D = Stroke3DClass.new()
		ghost.name = "__OnionGhost_" + String(stroke_id)
		ghost.set_meta("onion_ghost",true)
		ghost.points = state.get("points",PackedVector3Array())
		ghost.radius = float(record.get("radius",0.012))
		ghost.set_pressure_data(record.get("point_size_pressure",[]),record.get("point_opacity_pressure",[]))
		ghost.brush_preset = String(record.get("brush_preset","clean"))
		ghost.width_variation = float(record.get("width_variation",0.0))
		ghost.width_frequency = float(record.get("width_frequency",1.0))
		ghost.brush_seed = int(record.get("brush_seed",1))
		ghost.start_cap = String(record.get("start_cap","flat"))
		ghost.end_cap = String(record.get("end_cap","flat"))
		ghost.stroke_color = tint
		ghost.fill_enabled = bool(record.get("fill_enabled",false))
		var fill_tint := tint
		fill_tint.a = minf(fill_tint.a,0.12)
		ghost.fill_color = fill_tint
		ghost.fill_mode = "solid"
		root.add_child(ghost)
		ghost.rebuild()

func _refresh_vector_onion_skin(group: Node3D,data: RefCounted,frame: int) -> void:
	var root := _vector_onion_root(group,active_drawing_id)
	# Always clear first. Hidden stale ghosts must never survive a frame change.
	root.visible = false
	_clear_vector_onion_root(root)
	if not %OnionSkin.button_pressed or workspace != "drawing":
		return
	root.visible = true
	var previous_frame: int = data.previous_exposure_frame(frame)
	var next_frame: int = data.next_exposure_frame(frame)
	if previous_frame >= 0:
		_add_vector_onion_pose(root,data,data.cel_pose(previous_frame),Color(1.0,0.24,0.24,0.28))
	if next_frame >= 0:
		_add_vector_onion_pose(root,data,data.cel_pose(next_frame),Color(0.25,0.55,1.0,0.24))

func key_active_drawing_pose(interpolation := "hold") -> void:
	if active_drawing_id.is_empty() or not drawing_data_by_object.has(active_drawing_id): return
	var data: RefCounted = drawing_data_by_object[active_drawing_id]
	data.set_exposure(_drawing_edit_frame(), data.snapshot_pose(), interpolation)
	status.text = "Drawing pose keyed at frame %d" % ProjectStore.current_frame

func _on_timeline_frame_requested(frame: int) -> void:
	# The bottom timeline always scrubs scene time, including while Drawing is open.
	ProjectStore.set_frame(frame)

func _on_local_timeline_frame_requested(frame: int) -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	data.set_local_frame(frame)
	%DrawingCanvas.set_local_frame(data.local_frame)
	local_drawing_timeline.set_frame(data.local_frame)
	_apply_drawing_frame(ProjectStore.current_frame)
	status.text = "Local frame %d · %s" % [data.local_frame,active_drawing_group.name if active_drawing_group else "Canvas"]

func _on_frame_slider_value_changed(value: float) -> void:
	# Global frame control remains global in every workspace.
	ProjectStore.set_frame(int(value))
func _on_prev_pressed() -> void:
	ProjectStore.set_frame(ProjectStore.current_frame - 1)
func _on_next_pressed() -> void:
	ProjectStore.set_frame(ProjectStore.current_frame + 1)
func _on_play_pressed() -> void:
	playing = not playing
	if playing and local_playing:
		_stop_local_playback()
	%PlayButton.text = ""
	%PlayButton.icon = load("res://assets/icons/lucide/pause.svg") if playing else load("res://assets/icons/lucide/play-nav.svg")
func _on_local_play_pressed() -> void:
	if workspace != "drawing": return
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	local_playing = not local_playing
	if local_playing:
		playing = false
		%PlayButton.icon = load("res://assets/icons/lucide/play-nav.svg")
		local_play_accumulator = 0.0
		local_hold_counter = 0
		var start_frame := int(data.local_playback_start)
		var end_frame := int(data.local_playback_end)
		if int(data.local_frame) < start_frame or int(data.local_frame) > end_frame:
			data.set_local_frame(start_frame)
		local_play_direction = -1 if int(data.local_frame) >= end_frame and String(data.playback_mode) == "ping_pong" else 1
		%LocalPlay.icon = load("res://assets/icons/lucide/pause.svg")
	else:
		_stop_local_playback()

func _stop_local_playback() -> void:
	local_playing = false
	local_play_accumulator = 0.0
	local_hold_counter = 0
	if has_node("%LocalPlay"):
		%LocalPlay.icon = load("res://assets/icons/lucide/play-nav.svg")

func _process_local_playback(delta: float) -> void:
	if workspace != "drawing":
		_stop_local_playback()
		return
	var data: RefCounted = _active_drawing_data()
	if data == null:
		_stop_local_playback()
		return
	var speed: float = maxf(0.01,float(data.playback_speed))
	local_play_accumulator += delta*speed
	var step_time := 1.0/maxf(1.0,float(ProjectStore.fps))
	while local_play_accumulator >= step_time and local_playing:
		local_play_accumulator -= step_time
		var start_frame := int(data.local_playback_start)
		var end_frame := int(data.local_playback_end)
		var current := int(data.local_frame)
		var next_local := current
		match String(data.playback_mode):
			"ping_pong":
				next_local = current+local_play_direction
				if next_local > end_frame:
					local_play_direction = -1
					next_local = maxi(start_frame,end_frame-1)
				elif next_local < start_frame:
					local_play_direction = 1
					next_local = mini(end_frame,start_frame+1)
			"hold":
				if current >= end_frame:
					_stop_local_playback()
					break
				next_local = mini(current+1,end_frame)
			"loop_hold":
				if current >= end_frame:
					if local_hold_counter < int(data.hold_frames):
						local_hold_counter += 1
						next_local = end_frame
					else:
						local_hold_counter = 0
						next_local = start_frame
				else:
					next_local = current+1
			_:
				next_local = current+1
				if next_local > end_frame: next_local = start_frame
		data.set_local_frame(next_local)
		%DrawingCanvas.set_local_frame(data.local_frame)
		local_drawing_timeline.set_frame(data.local_frame)
		_apply_drawing_frame(ProjectStore.current_frame)

func _on_key_pressed() -> void:
	if workspace == "drawing":
		_key_active_flipbook_cel()
	else:
		_key_transform()
	_flash_key_button()

func _key_active_flipbook_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	if %DrawingCanvas.bitmap_mode:
		%DrawingCanvas.key_current_cel()
		data.ensure_flipbook_cel(_drawing_edit_frame())
		if %DrawingCanvas.is_animated_bitmap(active_drawing_id) and static_bitmap_runtime.has(active_drawing_id):
			var old_static: RuntimeObject = static_bitmap_runtime[active_drawing_id]
			if is_instance_valid(old_static): old_static.visible = false
		_refresh_drawing_timeline()
		status.text = "Bitmap flipbook cel keyed · local frame %d" % _drawing_edit_frame()
		return
	var frame: int = _drawing_edit_frame()
	# A flipbook key stores ONLY the authored cel at this local frame. Never
	# snapshot runtime visibility, because that may currently be a held older cel.
	var pose: Dictionary = data.current_cel_pose(frame)
	if pose.is_empty():
		pose = {}
		for stroke_id in data.stroke_order:
			var record: Dictionary = data.strokes[stroke_id]
			pose[stroke_id] = {
				"points": (record["points"] as PackedVector3Array).duplicate(),
				"visible": false
			}
	data.set_exposure(frame, pose, "hold")
	_apply_drawing_frame(ProjectStore.current_frame)
	_refresh_drawing_timeline()
	status.text = "Flipbook cel keyed · local frame %d" % frame

func _push_vector_undo() -> void:
	if active_drawing_id.is_empty(): return
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	var stack: Array = vector_undo_history.get(active_drawing_id,[])
	stack.append(data.to_dict().duplicate(true))
	while stack.size() > MAX_VECTOR_UNDO:
		stack.pop_front()
	vector_undo_history[active_drawing_id] = stack
	vector_redo_history[active_drawing_id] = []

func _undo_drawing() -> void:
	if workspace == "drawing" and not %DrawingCanvas.bitmap_mode:
		_undo_vector_drawing()
	else:
		%DrawingCanvas.undo_paint()
		if workspace == "drawing":
			_refresh_drawing_timeline()

func _redo_drawing() -> void:
	if workspace == "drawing" and not %DrawingCanvas.bitmap_mode:
		_redo_vector_drawing()
	else:
		%DrawingCanvas.redo_paint()
		if workspace == "drawing":
			_refresh_drawing_timeline()

func _undo_vector_drawing() -> void:
	if active_drawing_id.is_empty(): return
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	var undo_stack: Array = vector_undo_history.get(active_drawing_id,[])
	if undo_stack.is_empty(): return
	var redo_stack: Array = vector_redo_history.get(active_drawing_id,[])
	redo_stack.append(data.to_dict().duplicate(true))
	vector_redo_history[active_drawing_id] = redo_stack
	var state: Dictionary = undo_stack.pop_back()
	vector_undo_history[active_drawing_id] = undo_stack
	_restore_vector_drawing_state(active_drawing_id,state)
	status.text = "Undo drawing"

func _redo_vector_drawing() -> void:
	if active_drawing_id.is_empty(): return
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	var redo_stack: Array = vector_redo_history.get(active_drawing_id,[])
	if redo_stack.is_empty(): return
	var undo_stack: Array = vector_undo_history.get(active_drawing_id,[])
	undo_stack.append(data.to_dict().duplicate(true))
	vector_undo_history[active_drawing_id] = undo_stack
	var state: Dictionary = redo_stack.pop_back()
	vector_redo_history[active_drawing_id] = redo_stack
	_restore_vector_drawing_state(active_drawing_id,state)
	status.text = "Redo drawing"

func _restore_vector_drawing_state(canvas_id: String, state: Dictionary) -> void:
	if not drawing_data_by_object.has(canvas_id) or not scene_nodes.has(canvas_id): return
	var data: RefCounted = drawing_data_by_object[canvas_id]
	var group := scene_nodes[canvas_id] as ReferenceCanvas
	if group == null: return
	data.load_dict(state)
	drawing_controller.invalidate(canvas_id)
	selected_stroke = null
	for child in group.get_children():
		if child is Stroke3D:
			group.remove_child(child)
			child.queue_free()
	for stroke_id in data.stroke_order:
		if not data.strokes.has(stroke_id): continue
		var rec: Dictionary = data.strokes[stroke_id]
		var stroke: Stroke3D = Stroke3DClass.new()
		stroke.stroke_id = stroke_id
		stroke.points = rec.get("points",PackedVector3Array())
		stroke.stroke_color = rec.get("color",Color.BLACK)
		stroke.radius = float(rec.get("radius",0.012))
		stroke.set_pressure_data(rec.get("point_size_pressure",[]),rec.get("point_opacity_pressure",[]))
		stroke.brush_preset = String(rec.get("brush_preset","clean"))
		stroke.width_variation = float(rec.get("width_variation",0.0))
		stroke.width_frequency = float(rec.get("width_frequency",1.0))
		stroke.brush_seed = int(rec.get("brush_seed",1))
		stroke.start_cap = String(rec.get("start_cap","flat"))
		stroke.end_cap = String(rec.get("end_cap","flat"))
		stroke.fill_enabled = bool(rec.get("fill_enabled",false))
		stroke.fill_color = rec.get("fill_color",Color.TRANSPARENT)
		stroke.fill_mode = String(rec.get("fill_mode","solid"))
		stroke.fill_color_b = rec.get("fill_color_b",Color.TRANSPARENT)
		stroke.fill_gradient_angle = float(rec.get("fill_gradient_angle",0.0))
		group.add_child(stroke)
		stroke.rebuild()
	_apply_drawing_frame(ProjectStore.current_frame)
	_refresh_drawing_timeline()
	_refresh_vector_onion_skin(group,data,_drawing_edit_frame())

func _on_render_animation_pressed() -> void:
	if render_in_progress: return
	if render_camera_id.is_empty() or not scene_nodes.has(render_camera_id):
		status.text = "Render animation · create or select a scene camera first"
		return
	%RenderOutputDialog.popup_centered_ratio(0.65)

func _on_render_output_dir_selected(path: String) -> void:
	if render_in_progress: return
	call_deferred("_render_animation_png_sequence",path)

func _render_animation_png_sequence(output_dir: String) -> void:
	if render_in_progress: return
	if render_camera_id.is_empty() or not scene_nodes.has(render_camera_id): return
	var render_cam := _scene_camera_node(render_camera_id)
	if render_cam == null:
		status.text = "Render animation · camera unavailable"
		return
	var camera_obj: MotionObject = ProjectStore.objects.get(render_camera_id)
	if camera_obj == null: return

	render_in_progress = true
	playing = false
	_stop_local_playback()
	%RenderAnimation.disabled = true

	var previous_frame := ProjectStore.current_frame
	var previous_viewport_size := viewport.size
	var previous_stretch := canvas.stretch
	var previous_editor_current: bool = camera.current
	var previous_render_current: bool = render_cam.current
	var previous_grid_visible: bool = world_grid.visible
	var previous_gizmo_visible: bool = gizmo.visible
	var previous_view_gizmo_visible: bool = bool(%ViewGizmo.visible)
	var previous_camera_frame_visible: bool = bool(%CameraFrame.visible)
	var previous_ik_visible: bool = bool(%IKGuide.visible)
	var previous_gradient_visible: bool = bool(%GradientGuide.visible)

	var rx := maxi(64,int(camera_obj.properties.get("camera.resolution_x",1920)))
	var ry := maxi(64,int(camera_obj.properties.get("camera.resolution_y",1080)))
	canvas.stretch = false
	viewport.size = Vector2i(rx,ry)
	camera.current = false
	render_cam.current = true
	world_grid.visible = false
	gizmo.visible = false
	%ViewGizmo.visible = false
	%CameraFrame.visible = false
	%IKGuide.visible = false
	%GradientGuide.visible = false
	for reference_canvas in drawing_planes:
		if is_instance_valid(reference_canvas):
			reference_canvas.set_guide_visible(false)
	_set_render_camera_gizmo_visible(false)

	var start_frame := int(ProjectStore.playback_start)
	var end_frame := int(ProjectStore.playback_end)
	var total := maxi(1,end_frame-start_frame+1)
	var base_name := "kabuki"
	if not current_project_path.is_empty():
		base_name = current_project_path.get_file().get_basename()
	var failed := false

	for frame in range(start_frame,end_frame+1):
		status.text = "Rendering %d / %d · frame %d" % [frame-start_frame+1,total,frame]
		ProjectStore.set_frame(frame)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			failed = true
			break
		var filename := "%s_%05d.png" % [base_name,frame]
		var err := image.save_png(output_dir.path_join(filename))
		if err != OK:
			failed = true
			break

	render_cam.current = previous_render_current
	camera.current = previous_editor_current
	canvas.stretch = previous_stretch
	viewport.size = previous_viewport_size
	ProjectStore.set_frame(previous_frame)
	world_grid.visible = previous_grid_visible
	gizmo.visible = previous_gizmo_visible
	%ViewGizmo.visible = previous_view_gizmo_visible
	%CameraFrame.visible = previous_camera_frame_visible
	%IKGuide.visible = previous_ik_visible
	%GradientGuide.visible = previous_gradient_visible
	if not camera_view_active:
		_set_render_camera_gizmo_visible(true)
	%RenderAnimation.disabled = false
	render_in_progress = false
	status.text = "Render failed" if failed else "Animation rendered · %d PNG frames · %dx%d" % [total,rx,ry]

func _on_material_color_changed(value: Color) -> void:
	if selected: selected.set_material_color(value)

func _on_material_roughness_changed(value: float) -> void:
	if selected: selected.set_material_roughness(value)

func _on_material_metallic_changed(value: float) -> void:
	if selected: selected.set_material_metallic(value)

func _on_material_two_sided_toggled(enabled: bool) -> void:
	if selected: selected.set_material_two_sided(enabled)

func _on_light_energy_changed(value: float) -> void:
	if selected_scene_node is Light3D: (selected_scene_node as Light3D).light_energy = value

func _on_light_color_changed(value: Color) -> void:
	if selected_scene_node is Light3D: (selected_scene_node as Light3D).light_color = value

func _on_light_shadow_toggled(enabled: bool) -> void:
	if selected_scene_node is Light3D: (selected_scene_node as Light3D).shadow_enabled = enabled

func _on_light_type_selected(index: int) -> void:
	if not (selected_scene_node is Light3D): return
	var old_light := selected_scene_node as Light3D
	var replacement: Light3D
	if index == 0: replacement = DirectionalLight3D.new()
	elif index == 1: replacement = OmniLight3D.new()
	else: replacement = SpotLight3D.new()
	replacement.name = old_light.name
	replacement.transform = old_light.transform
	replacement.light_color = old_light.light_color
	replacement.light_energy = old_light.light_energy
	replacement.shadow_enabled = old_light.shadow_enabled
	world_root.add_child(replacement)
	scene_nodes[selected_object_id] = replacement
	old_light.queue_free()
	selected_scene_node = replacement
	_show_transform(replacement)
	status.text = "Light type: " + ["Directional", "Point", "Spot"][index]

func _apply_global_filters() -> void:
	effects_engine.set_filters({
		"blur": %Blur.value,
		"glow_strength": %Glow.value,
		"glow_threshold": %GlowThreshold.value,
		"glow_radius": %GlowRadius.value,
		"exposure": %Exposure.value,
		"saturation": %Saturation.value,
		"contrast": %Contrast.value,
		"temperature": %Temperature.value,
		"color_tint": %Tint.value,
		"vignette": %Vignette.value,
		"chromatic_aberration": %ChromaticAberration.value,
		"monochrome": 1.0 if %Monochrome.button_pressed else 0.0
	})

func _on_filter_changed(_value: float) -> void:
	_apply_global_filters()

func _on_monochrome_toggled(_enabled: bool) -> void:
	_apply_global_filters()

func _on_reset_filters_pressed() -> void:
	%Blur.value=0.0
	%Glow.value=0.0
	%GlowThreshold.value=0.7
	%GlowRadius.value=3.0
	%Exposure.value=0.0
	%Saturation.value=1.0
	%Contrast.value=1.0
	%Temperature.value=0.0
	%Tint.value=0.0
	%Vignette.value=0.0
	%ChromaticAberration.value=0.0
	%Monochrome.set_pressed_no_signal(false)
	_apply_global_filters()

func _setup_workspace_tabs() -> void:
	while %WorkspaceTabs.tab_count > 0:
		%WorkspaceTabs.remove_tab(0)
	var labels: Array[String] = ["SCENE", "ANIMATION", "DRAWING", "RIGGING", "COMPOSITOR"]
	var icon_paths: Array[String] = [
		"res://assets/icons/lucide/grid-3x3-nav.svg",
		"res://assets/icons/lucide/play-nav.svg",
		"res://assets/icons/lucide/pencil-nav.svg",
		"res://assets/icons/lucide/move-nav.svg",
		"res://assets/icons/lucide/blend-nav.svg"
	]
	for i in range(labels.size()):
		var icon: Texture2D = load(icon_paths[i]) as Texture2D
		# add_tab(title, icon) is more reliable here than assigning the icon
		# after the tab has already been laid out.
		%WorkspaceTabs.add_tab(labels[i],icon)
	%WorkspaceTabs.current_tab = 0
	%WorkspaceTabs.tab_changed.connect(_on_workspace_tab_changed)

func _setup_rigging_workspace() -> void:
	%PickRigParent.pressed.connect(_on_pick_rig_parent)
	%CancelRigParent.pressed.connect(_cancel_rig_parenting)
	%ClearRigParent.pressed.connect(_on_clear_rig_parent)
	%PivotHere.pressed.connect(_on_pivot_here)
	%CreateSkeleton.pressed.connect(_on_create_skeleton)
	%AddBone.pressed.connect(_request_new_rig_chain)
	%AutoWeights.pressed.connect(_on_auto_weights)
	%RigFinishDialog.confirmed.connect(_confirm_finish_skeleton)
	%RigFinishDialog.canceled.connect(_request_new_rig_chain)
	%RigParentDialog.confirmed.connect(_confirm_new_rig_chain)
	_refresh_rig_parent_choices()

func _refresh_rig_parent_choices() -> void:
	if pending_parent_child_id.is_empty():
		%RigSelectionHint.text = "Select child, then PICK PARENT"
	else:
		var child: MotionObject = ProjectStore.objects.get(pending_parent_child_id)
		%RigSelectionHint.text = "Child: %s\nNow select the parent object" % (child.name if child != null else "Object")
	%CancelRigParent.visible = not pending_parent_child_id.is_empty()

func _on_pick_rig_parent() -> void:
	if selected_object_id.is_empty() or not ProjectStore.objects.has(selected_object_id): return
	pending_parent_child_id = selected_object_id
	_refresh_rig_parent_choices()
	status.text = "Select the parent object from OBJECTS"

func _cancel_rig_parenting() -> void:
	pending_parent_child_id = ""
	_refresh_rig_parent_choices()
	status.text = "Parenting cancelled"

func _try_complete_rig_parenting(parent_id: String) -> bool:
	if pending_parent_child_id.is_empty() or parent_id == pending_parent_child_id: return false
	if not ProjectStore.objects.has(pending_parent_child_id) or not ProjectStore.objects.has(parent_id): return false
	if not scene_nodes.has(pending_parent_child_id) or not scene_nodes.has(parent_id): return false
	var child_model: MotionObject = ProjectStore.objects[pending_parent_child_id]
	var parent_model: MotionObject = ProjectStore.objects[parent_id]
	var child_node: Node3D = scene_nodes[pending_parent_child_id]
	var parent_node: Node3D = scene_nodes[parent_id]
	if not rigging_controller.set_parent(child_model,parent_model,child_node,parent_node,true): return false
	pending_parent_child_id = ""
	_refresh_scene_object_list()
	_refresh_rig_parent_choices()
	_select_scene_node(child_model.id,child_node)
	status.text = child_model.name + " parented to " + parent_model.name
	return true

func _on_clear_rig_parent() -> void:
	if selected_object_id.is_empty() or selected_scene_node == null: return
	var obj: MotionObject = ProjectStore.objects.get(selected_object_id)
	if obj == null: return
	var global_before: Transform3D = selected_scene_node.global_transform
	selected_scene_node.reparent(world_root, true)
	selected_scene_node.global_transform = global_before
	obj.parent_id = ""
	obj.transform = selected_scene_node.transform
	_refresh_scene_object_list()
	status.text = obj.name + " parent cleared"

func _on_pivot_here() -> void:
	if selected_scene_node == null: return
	rigging_controller.set_pivot_keep_geometry(selected_scene_node, camera_rig.pivot)
	if ProjectStore.objects.has(selected_object_id):
		var obj: MotionObject = ProjectStore.objects[selected_object_id]
		obj.transform = selected_scene_node.transform
	_show_transform(selected_scene_node)
	status.text = "Pivot moved to view cursor"

func _ensure_active_rig() -> RefCounted:
	if active_rig_id.is_empty():
		active_rig_id = "rig-" + str(ResourceUID.create_id())
		var created: RefCounted = rigging_controller.create_rig(active_rig_id)
		var rig_obj := MotionObject.new("Armature", "rig", "character")
		rig_obj.id = active_rig_id
		rig_obj.components["deform"]["rig_id"] = active_rig_id
		active_rig_runtime = RigRuntimeClass.new()
		world_root.add_child(active_rig_runtime)
		active_rig_runtime.setup(created)
		scene_object_controller.register(rig_obj,active_rig_runtime)
		_refresh_scene_object_list()
		return created
	var existing: RefCounted = rigging_controller.rigs.get(active_rig_id)
	if active_rig_runtime == null and existing != null:
		active_rig_runtime = RigRuntimeClass.new()
		world_root.add_child(active_rig_runtime)
		active_rig_runtime.setup(existing)
	return existing

func _on_create_skeleton() -> void:
	if selected_object_id.is_empty() or selected_scene_node == null:
		status.text = "Select a drawing first"
		return
	# A Canvas is only the spatial reference. Rigging belongs to its tessellated
	# drawing child. Accepting a selected Canvas here is just a convenience:
	# resolve its single static drawing child, then make that child the target.
	if selected_scene_node is ReferenceCanvas:
		var canvas_id: String = selected_object_id
		if static_bitmap_runtime.has(canvas_id):
			var drawing_runtime: RuntimeObject = static_bitmap_runtime[canvas_id]
			if is_instance_valid(drawing_runtime) and drawing_runtime.model != null:
				_select(drawing_runtime)
	if not selected_scene_node is MeshInstance3D:
		status.text = "Select a tessellated drawing"
		return
	var selected_model: MotionObject = ProjectStore.objects.get(selected_object_id)
	if selected_model == null or selected_model.technical_type != "bitmap_layer":
		status.text = "Select a tessellated drawing"
		return
	rig_target_object_id = selected_object_id
	%AddBone.visible = true
	%ChainStatus.visible = true
	%CreateSkeleton.visible = false
	_on_add_rig_bone()

func _request_new_rig_chain() -> void:
	var rig: RefCounted = _ensure_active_rig()
	%RigParentChoice.clear()
	%RigParentChoice.add_item("Independent / Root")
	%RigParentChoice.set_item_metadata(0,-1)
	for bone_index in range(rig.bones.size()):
		var bone: Dictionary = rig.bones[bone_index]
		%RigParentChoice.add_item(String(bone.get("name","Bone %02d" % (bone_index+1))))
		%RigParentChoice.set_item_metadata(%RigParentChoice.item_count-1,bone_index)
	%RigParentDialog.dialog_text = "Choose the bone that will parent the first bone of the new chain."
	%RigParentDialog.popup_centered()

func _confirm_new_rig_chain() -> void:
	pending_chain_parent = int(%RigParentChoice.get_item_metadata(%RigParentChoice.selected))
	_on_add_rig_bone()

func _on_add_rig_bone() -> void:
	var rig: RefCounted = _ensure_active_rig()
	rig_chain_count += 1
	%ChainStatus.visible = true
	%ChainStatus.text = "Chain %d · drawing…" % rig_chain_count
	%AddBone.visible = true
	%AddBone.disabled = true
	rig_bone_draw_active = true
	rig_bone_draw_parent = pending_chain_parent
	pending_chain_parent = -1
	rig_bone_root_set = false
	rig_bone_draw_depth_point = selected_scene_node.global_position if selected_scene_node != null else camera_rig.pivot
	status.text = "Chain %d · click the root point first" % rig_chain_count

func _add_rig_bone_point(screen_pos: Vector2) -> void:
	if not rig_bone_draw_active: return
	var rig: RefCounted = _ensure_active_rig()
	var world_point: Vector3 = _screen_to_view_plane(screen_pos,rig_bone_draw_depth_point)
	if not rig_bone_root_set:
		rig_bone_root_set = true
		rig_bone_last_point = world_point
		rig_bone_draw_depth_point = world_point
		status.text = "Root set · click the next joint"
		return
	var rest := Transform3D.IDENTITY
	rest.origin = rig_bone_last_point
	var index: int = rig.add_bone("Bone %02d" % (rig.bones.size() + 1),rig_bone_draw_parent,rest)
	rig_bone_draw_parent = index
	rig_bone_last_point = world_point
	rig_bone_draw_depth_point = world_point
	if active_rig_runtime != null:
		active_rig_runtime.rebuild_bones()
		active_rig_runtime.set_terminal_tip(index,world_point)
	status.text = "Bone %02d · click next joint · Enter to finish" % (index + 1)

func _finish_rig_bone_drawing() -> void:
	if not rig_bone_draw_active: return
	rig_bone_draw_active = false
	rig_bone_draw_parent = -1
	rig_bone_root_set = false
	var rig: RefCounted = rigging_controller.rigs.get(active_rig_id)
	var bone_count: int = rig.bones.size() if rig != null else 0
	%RigFinishDialog.dialog_text = "Chain %d finished · %d bones total.\n\nAdd another independent chain, or finish the skeleton and calculate automatic weights." % [rig_chain_count,bone_count]
	%AddBone.disabled = false
	%ChainStatus.text = "Chain %d finished · %d bones total" % [rig_chain_count,bone_count]
	%RigFinishDialog.popup_centered()
	status.text = "Chain %d finished · add another chain or finish skeleton" % rig_chain_count

func _confirm_finish_skeleton() -> void:
	if rig_target_object_id.is_empty() or not scene_nodes.has(rig_target_object_id):
		status.text = "Skeleton finished"
		rig_chain_count = 0
		return
	var target: Node3D = scene_nodes[rig_target_object_id]
	var target_model: MotionObject = ProjectStore.objects.get(rig_target_object_id)
	var rig_model: MotionObject = ProjectStore.objects.get(active_rig_id)
	if target_model != null and rig_model != null and active_rig_runtime != null:
		rigging_controller.set_parent(target_model,rig_model,target,active_rig_runtime,true)
		_refresh_scene_object_list()
		_select_scene_node(rig_target_object_id,target)
		_on_auto_weights()
	rig_target_object_id = ""
	rig_chain_count = 0
	%AddBone.visible = false
	%ChainStatus.visible = false
	%CreateSkeleton.visible = true

func _on_auto_weights() -> void:
	if not selected_scene_node is MeshInstance3D:
		status.text = "Select a tessellated mesh or plane for Auto Weights"
		return
	var rig: RefCounted = _ensure_active_rig()
	if rig.bones.is_empty():
		status.text = "Create at least one bone first"
		return
	# Compute weights in the same Armature coordinate space used by Skin and
	# Skeleton. Convert a temporary copy of the source mesh to that space first;
	# bind_mesh will bake the identical transform into the real artwork.
	var mesh_node := selected_scene_node as MeshInstance3D
	var original_mesh: Mesh = mesh_node.mesh
	var original_transform: Transform3D = mesh_node.transform
	var weight_mesh := ArrayMesh.new()
	for surface_index in range(original_mesh.get_surface_count()):
		var arrays: Array = original_mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vi in range(vertices.size()): vertices[vi] = original_transform * vertices[vi]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		weight_mesh.add_surface_from_arrays(original_mesh.surface_get_primitive_type(surface_index),arrays)
	var weight_proxy := MeshInstance3D.new()
	weight_proxy.mesh = weight_mesh
	var segments: Array = []
	for bone_index in range(rig.bones.size()):
		var bone: Dictionary = rig.bones[bone_index]
		var rest: Transform3D = bone.get("rest",Transform3D.IDENTITY)
		var head: Vector3 = active_rig_runtime.global_transform.affine_inverse() * rest.origin
		var tail: Vector3 = head + Vector3(0.0,0.45,0.0)
		var child_found := false
		for child_index in range(rig.bones.size()):
			if int(rig.bones[child_index].get("parent",-1)) == bone_index:
				var child_rest: Transform3D = rig.bones[child_index].get("rest",Transform3D.IDENTITY)
				tail = active_rig_runtime.global_transform.affine_inverse() * child_rest.origin
				child_found = true
				break
		if not child_found and active_rig_runtime.terminal_tips.has(bone_index):
			tail = active_rig_runtime.global_transform.affine_inverse() * (active_rig_runtime.terminal_tips[bone_index] as Vector3)
		segments.append({"a":head,"b":tail})
	var weights: Array = rigging_controller.auto_weight_vertices(weight_proxy,segments)
	rig.bindings[selected_object_id] = {"bone_weights": weights, "auto_bound": true}
	var obj: MotionObject = ProjectStore.objects.get(selected_object_id)
	if obj != null: obj.components["deform"]["rig_id"] = active_rig_id
	if active_rig_runtime != null and active_rig_runtime.bind_mesh(selected_scene_node as MeshInstance3D, weights):
		status.text = "Automatic weights assigned · mesh skinned"
	else:
		status.text = "Automatic weights assigned"

func _setup_drawing_menus() -> void:
	# Primary modes/tools are direct icon buttons. Dropdowns are reserved for
	# subtools such as Sculpt Mode and cel operations.
	%StrokeTool.pressed.connect(_on_draw_stroke3d_pressed)
	%BitmapTool.pressed.connect(_on_draw_bitmap_pressed)
	%EraseTool.pressed.connect(_on_draw_eraser_pressed)
	%SculptTool.pressed.connect(_on_draw_sculpt_pressed)
	%BitmapBrush.pressed.connect(func(): _set_bitmap_tool(0))
	%BitmapPencil.pressed.connect(func(): _set_bitmap_tool(1))
	%BitmapEraser.pressed.connect(func(): _set_bitmap_tool(2))
	%BitmapSmudge.pressed.connect(func(): _set_bitmap_tool(7))
	%BitmapLassoFill.pressed.connect(func(): _set_bitmap_tool(8))
	%LassoFillMode.clear()
	%LassoFillMode.add_item("Solid")
	%LassoFillMode.add_item("Gradient")
	%LassoFillMode.item_selected.connect(func(index: int): %DrawingCanvas.set_lasso_fill_mode(index); _update_drawing_tool_ui())
	%LassoColorA.color_changed.connect(%DrawingCanvas.set_lasso_color_a)
	%LassoColorB.color_changed.connect(%DrawingCanvas.set_lasso_color_b)
	%LassoGradientAngle.value_changed.connect(%DrawingCanvas.set_lasso_gradient_angle)
	%BitmapLine.pressed.connect(func(): _set_bitmap_tool(3))
	%BitmapRect.pressed.connect(func(): _set_bitmap_tool(4))
	%BitmapEllipse.pressed.connect(func(): _set_bitmap_tool(5))
	%BitmapFillTool.pressed.connect(func(): _set_bitmap_tool(6))
	%BitmapClear.pressed.connect(%DrawingCanvas.clear_canvas)
	%BitmapCommit.visible = false
	%DrawingCanvas.bitmap_stroke_started.connect(_on_bitmap_flipbook_stroke_started)
	%BrushPreset.clear()
	for preset_name in ["Ink", "Soft", "Airbrush", "Chalk", "Graphite HB", "Graphite 4B"]:
		%BrushPreset.add_item(preset_name)
	%BrushPreset.item_selected.connect(func(index: int): %DrawingCanvas.set_brush_preset(index))
	%BrushOpacity.value_changed.connect(func(value: float): %DrawingCanvas.opacity = value)
	%BrushHardness.value_changed.connect(func(value: float): %DrawingCanvas.hardness = value)
	%PrimarySlider.value_changed.connect(_on_primary_tool_param_changed)
	%SecondarySlider.value_changed.connect(_on_secondary_tool_param_changed)
	%PrimarySlider.drag_started.connect(func(): _begin_tool_feedback("primary"))
	%PrimarySlider.drag_ended.connect(func(_changed): _end_tool_feedback())
	%SecondarySlider.drag_started.connect(func(): _begin_tool_feedback("secondary"))
	%SecondarySlider.drag_ended.connect(func(_changed): _end_tool_feedback())
	%ToolFeedbackOverlay.draw.connect(_draw_tool_feedback)
	%DrawingCanvas.fill_tolerance = %FillTolerance.value
	var cel_popup: PopupMenu = %CelMenu.get_popup()
	cel_popup.clear()
	for label in ["New Empty Cel", "Duplicate Previous Cel", "Delete Cel", "Hold", "Morph"]:
		cel_popup.add_item(label)
	cel_popup.id_pressed.connect(_on_drawing_cel_menu)
	_update_drawing_tool_ui()

func _on_fill_tolerance_changed(value: float) -> void:
	%DrawingCanvas.fill_tolerance = clampf(value,0.0,1.0)
	status.text = "Fill tolerance · %d%%" % roundi(value*100.0)

func _set_bitmap_tool(tool: int) -> void:
	if not %DrawingCanvas.bitmap_mode:
		_on_draw_bitmap_pressed()
	%DrawingCanvas.set_tool(tool)
	%DrawingCanvas.brush_color = bitmap_color
	%DrawingCanvas.opacity = %BrushOpacity.value
	%DrawingCanvas.brush_size = %BrushSize.value
	var bitmap_buttons: Array[Button] = [%BitmapBrush,%BitmapPencil,%BitmapEraser,%BitmapLine,%BitmapRect,%BitmapEllipse,%BitmapFillTool,%BitmapSmudge,%BitmapLassoFill]
	for button in bitmap_buttons:
		button.set_pressed_no_signal(false)
	if tool >= 0 and tool < bitmap_buttons.size():
		bitmap_buttons[tool].set_pressed_no_signal(true)
	status.text = ["Brush", "Pencil", "Bitmap Eraser", "Line", "Rectangle", "Ellipse", "Fill", "Smudge", "Lasso Fill"][tool]
	_update_drawing_tool_ui()
	_sync_tool_param_sliders()

func _setup_world_controls() -> void:
	for label in ["Solid","Gradient","Image"]: %WorldMode.add_item(label)
	for label in ["Vertical","Horizontal","Radial"]: %WorldGradientMapping.add_item(label)
	for label in ["Camera","Equirectangular 360"]: %WorldImageMode.add_item(label)
	%WorldMode.item_selected.connect(_on_world_mode_selected)
	%WorldColor.color_changed.connect(func(_color): _refresh_world())
	%GradientA.color_changed.connect(func(_color): _refresh_world())
	%GradientB.color_changed.connect(func(_color): _refresh_world())
	%WorldGradientMapping.item_selected.connect(func(_i): _refresh_world())
	%WorldImageMode.item_selected.connect(func(i): world_image_mode = "camera" if i == 0 else "equirect"; _refresh_world())
	%WorldImageLoad.pressed.connect(_on_world_image_load)
	_refresh_world()

func _on_world_mode_selected(index: int) -> void:
	world_mode = ["solid","gradient","image"][index]
	%WorldColor.visible = world_mode == "solid"
	%WorldGradientBox.visible = world_mode == "gradient"
	%WorldImageBox.visible = world_mode == "image"
	_refresh_world()

func _refresh_world() -> void:
	var env := Environment.new()
	if world_mode == "solid":
		env.background_mode = Environment.BG_COLOR
		env.background_color = %WorldColor.color
	elif world_mode == "gradient":
		# Procedural sky gives a true 3D world gradient and remains camera independent.
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = %GradientA.color
		sky_mat.sky_horizon_color = %GradientB.color
		sky_mat.ground_horizon_color = %GradientB.color
		sky_mat.ground_bottom_color = %GradientA.color
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
	%WorldEnvironment.environment = env
	%WorldBackdrop.visible = world_mode == "image" and world_image_mode == "camera"

func _on_world_image_load() -> void:
	%FileDialog.set_meta("world_image_request", true)
	%FileDialog.popup_centered_ratio(0.7)

func _set_stroke_brush_preset(preset: String) -> void:
	stroke_brush_preset = preset
	var buttons: Dictionary = {
		"clean": %StrokeClean,
		"ink": %StrokeInk,
		"dry": %StrokeDry,
		"rough": %StrokeRough
	}
	for key in buttons:
		(buttons[key] as Button).button_pressed = String(key) == preset
	status.text = "Vector brush · " + preset.capitalize()

func _apply_stroke_brush(stroke: Stroke3D) -> void:
	stroke.brush_preset = stroke_brush_preset
	stroke.start_cap = stroke_start_cap
	stroke.end_cap = stroke_end_cap
	match stroke_brush_preset:
		"ink":
			stroke.width_variation = 0.22
			stroke.width_frequency = 2.2
		"dry":
			stroke.width_variation = 0.38
			stroke.width_frequency = 4.0
		"rough":
			stroke.width_variation = 0.58
			stroke.width_frequency = 6.2
		_:
			stroke.width_variation = 0.0
			stroke.width_frequency = 1.0
	# Stable for the life of this stroke, different for each newly drawn stroke.
	stroke.brush_seed = int(Time.get_ticks_usec() % 2147483647)

func _tool_param_profile() -> Dictionary:
	if drawing_sculpt_active:
		return {"primary":"SIZE","primary_min":1.0,"primary_max":500.0,"primary_step":1.0,"primary_value":%BrushSize.value,
			"secondary":"STRENGTH","secondary_min":-1.0,"secondary_max":1.0,"secondary_step":0.01,"secondary_value":%SculptStrength.value}
	if drawing_erase_active:
		# Vector eraser removes complete strokes; it has no meaningful opacity/
		# strength parameter, so never expose a slider that does nothing.
		return {"primary":"SIZE","primary_min":1.0,"primary_max":500.0,"primary_step":1.0,"primary_value":%BrushSize.value,
			"secondary":"—","secondary_min":0.0,"secondary_max":1.0,"secondary_step":0.01,"secondary_value":0.0,"secondary_enabled":false}
	if drawing_3d_active:
		return {"primary":"SIZE","primary_min":1.0,"primary_max":500.0,"primary_step":1.0,"primary_value":%BrushSize.value,
			"secondary":"OPACITY","secondary_min":0.0,"secondary_max":1.0,"secondary_step":0.01,"secondary_value":gp_opacity}
	if %DrawingCanvas.bitmap_mode:
		var tool: int = int(%DrawingCanvas.tool)
		if tool == 6:
			return {"primary":"TOLERANCE","primary_min":0.0,"primary_max":1.0,"primary_step":0.01,"primary_value":%FillTolerance.value,
				"secondary":"OPACITY","secondary_min":0.0,"secondary_max":1.0,"secondary_step":0.01,"secondary_value":%BrushOpacity.value}
		if tool == 7:
			return {"primary":"SIZE","primary_min":1.0,"primary_max":500.0,"primary_step":1.0,"primary_value":%BrushSize.value,
				"secondary":"STRENGTH","secondary_min":0.0,"secondary_max":1.0,"secondary_step":0.01,"secondary_value":%BrushOpacity.value}
		if tool == 8:
			if %LassoFillMode.selected == 1:
				return {"primary":"OPACITY","primary_min":0.0,"primary_max":1.0,"primary_step":0.01,"primary_value":%BrushOpacity.value,
					"secondary":"ANGLE","secondary_min":-180.0,"secondary_max":180.0,"secondary_step":1.0,"secondary_value":%LassoGradientAngle.value}
			return {"primary":"OPACITY","primary_min":0.0,"primary_max":1.0,"primary_step":0.01,"primary_value":%BrushOpacity.value,
				"secondary":"—","secondary_min":0.0,"secondary_max":1.0,"secondary_step":0.01,"secondary_value":0.0,"secondary_enabled":false}
		return {"primary":"SIZE","primary_min":1.0,"primary_max":500.0,"primary_step":1.0,"primary_value":%BrushSize.value,
			"secondary":"OPACITY","secondary_min":0.0,"secondary_max":1.0,"secondary_step":0.01,"secondary_value":%BrushOpacity.value}
	return {}

func _sync_tool_param_sliders() -> void:
	var profile: Dictionary = _tool_param_profile()
	var active: bool = workspace == "drawing" and not profile.is_empty()
	%ToolParamSurface.visible = active
	if not active: return
	var primary_kind := String(profile["primary"])
	%PrimaryIcon.texture = _tool_param_icon(primary_kind)
	%PrimaryIcon.tooltip_text = primary_kind.capitalize()
	_configure_tool_slider(%PrimarySlider, primary_kind, profile, "primary")
	var secondary_enabled: bool = bool(profile.get("secondary_enabled",true))
	var secondary_kind := String(profile["secondary"])
	%SecondaryIcon.visible = secondary_enabled
	%SecondarySlider.visible = secondary_enabled
	%SecondarySlider.editable = secondary_enabled
	if secondary_enabled:
		%SecondaryIcon.texture = _tool_param_icon(secondary_kind)
		%SecondaryIcon.tooltip_text = secondary_kind.capitalize()
		_configure_tool_slider(%SecondarySlider, secondary_kind, profile, "secondary")

func _configure_tool_slider(slider: Range, kind: String, profile: Dictionary, prefix: String) -> void:
	var parameter_min := float(profile[prefix + "_min"])
	var parameter_max := float(profile[prefix + "_max"])
	var parameter_step := float(profile[prefix + "_step"])
	var parameter_value := float(profile[prefix + "_value"])
	if kind == "SIZE":
		# Size uses a logarithmic/exponential response: roughly half of the
		# physical slider travel is devoted to the commonly used 1-22 px range.
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.001
		slider.set_value_no_signal(_size_to_slider(parameter_value,parameter_min,parameter_max))
	else:
		slider.min_value = parameter_min
		slider.max_value = parameter_max
		slider.step = parameter_step
		slider.set_value_no_signal(parameter_value)

func _size_from_slider(slider_value: float, minimum: float, maximum: float) -> float:
	if maximum <= minimum or minimum <= 0.0: return minimum
	var t := clampf(slider_value,0.0,1.0)
	return minimum * pow(maximum / minimum,t)

func _size_to_slider(size_value: float, minimum: float, maximum: float) -> float:
	if maximum <= minimum or minimum <= 0.0: return 0.0
	var clamped_size := clampf(size_value,minimum,maximum)
	return log(clamped_size / minimum) / log(maximum / minimum)

func _tool_slider_parameter_value(which: String, profile: Dictionary) -> float:
	var kind := String(profile["primary"] if which == "primary" else profile["secondary"])
	var slider: Range = %PrimarySlider if which == "primary" else %SecondarySlider
	if kind == "SIZE":
		var prefix := "primary" if which == "primary" else "secondary"
		return _size_from_slider(float(slider.value),float(profile[prefix + "_min"]),float(profile[prefix + "_max"]))
	return float(slider.value)

func _tool_param_icon(kind: String) -> Texture2D:
	match kind:
		"SIZE":
			return ToolSizeIcon
		"OPACITY":
			return ToolOpacityIcon
		"STRENGTH":
			return ToolStrengthIcon
		"TOLERANCE":
			return ToolToleranceIcon
		"ANGLE":
			return ToolAngleIcon
	return ToolSizeIcon

func _on_primary_tool_param_changed(value: float) -> void:
	var profile: Dictionary = _tool_param_profile()
	if profile.is_empty(): return
	var kind := String(profile["primary"])
	var parameter_value := value
	if kind == "SIZE":
		parameter_value = _size_from_slider(value,float(profile["primary_min"]),float(profile["primary_max"]))
	match kind:
		"SIZE":
			%BrushSize.set_value_no_signal(parameter_value)
			_on_brush_size_changed(parameter_value)
		"TOLERANCE":
			%FillTolerance.set_value_no_signal(value)
			_on_fill_tolerance_changed(value)
		"OPACITY":
			%BrushOpacity.set_value_no_signal(value)
			%DrawingCanvas.opacity = value
	if tool_feedback_active:
		tool_feedback_value = parameter_value
		%ToolFeedbackOverlay.queue_redraw()

func _on_secondary_tool_param_changed(value: float) -> void:
	var profile: Dictionary = _tool_param_profile()
	if profile.is_empty(): return
	var kind := String(profile["secondary"])
	match kind:
		"OPACITY":
			if drawing_3d_active:
				gp_opacity = value
				_apply_selected_stroke_style()
			else:
				%BrushOpacity.set_value_no_signal(value)
				%DrawingCanvas.opacity = value
		"STRENGTH":
			if drawing_sculpt_active:
				%SculptStrength.set_value_no_signal(value)
			else:
				%BrushOpacity.set_value_no_signal(value)
				%DrawingCanvas.opacity = value
		"ANGLE":
			%LassoGradientAngle.set_value_no_signal(value)
			%DrawingCanvas.set_lasso_gradient_angle(value)
	if tool_feedback_active:
		tool_feedback_value = value
		%ToolFeedbackOverlay.queue_redraw()

func _begin_tool_feedback(which: String) -> void:
	var profile: Dictionary = _tool_param_profile()
	if profile.is_empty(): return
	if which == "secondary" and not bool(profile.get("secondary_enabled",true)): return
	tool_feedback_active = true
	tool_feedback_kind = String(profile["primary"] if which == "primary" else profile["secondary"])
	tool_feedback_value = _tool_slider_parameter_value(which,profile)
	%ToolFeedbackOverlay.visible = true
	%ToolFeedbackOverlay.queue_redraw()

func _end_tool_feedback() -> void:
	tool_feedback_active = false
	%ToolFeedbackOverlay.visible = false

func _draw_tool_feedback() -> void:
	if not tool_feedback_active: return
	var overlay: Control = %ToolFeedbackOverlay
	# Slider feedback is deliberately stable and independent from cursor position.
	var center := overlay.size * 0.5
	var radius := 56.0
	var alpha := 0.32
	match tool_feedback_kind:
		"SIZE":
			radius = clampf(tool_feedback_value * 0.5,4.0,minf(overlay.size.x,overlay.size.y)*0.42)
		"OPACITY","STRENGTH":
			alpha = clampf(absf(tool_feedback_value),0.05,1.0)
		"TOLERANCE":
			radius = lerpf(24.0,minf(overlay.size.x,overlay.size.y)*0.35,clampf(tool_feedback_value,0.0,1.0))
			alpha = 0.22
		"ANGLE":
			var dir := Vector2.RIGHT.rotated(deg_to_rad(tool_feedback_value))
			overlay.draw_line(center-dir*70.0,center+dir*70.0,Color(1,1,1,0.9),3.0)
			return
	overlay.draw_circle(center,radius,Color(0.3,0.65,1.0,alpha))
	overlay.draw_arc(center,radius,0.0,TAU,64,Color(1,1,1,0.95),2.0)

func _update_drawing_tool_ui() -> void:
	var bitmap: bool = bool(%DrawingCanvas.bitmap_mode)
	var current_tool: int = int(%DrawingCanvas.tool)
	# Tool buttons stay grouped; parameter controls are contextual instead of
	# forming one long undifferentiated strip.
	for control in [%BitmapBrush,%BitmapPencil,%BitmapSmudge,%BitmapLassoFill,%BitmapEraser,%BitmapLine,%BitmapRect,%BitmapEllipse,%BitmapFillTool]:
		control.visible = bitmap
	%StrokeTool.button_pressed = drawing_3d_active
	%BrushMenuSurface.visible = workspace == "drawing" and drawing_3d_active
	# BitmapTool is a mode-entry button, not a second active drawing tool.
	# The selected state belongs exclusively to the active bitmap subtool.
	%BitmapTool.button_pressed = false
	%EraseTool.button_pressed = drawing_erase_active
	%SculptTool.button_pressed = drawing_sculpt_active
	var bitmap_buttons: Array[Button] = [%BitmapBrush,%BitmapPencil,%BitmapEraser,%BitmapLine,%BitmapRect,%BitmapEllipse,%BitmapFillTool,%BitmapSmudge,%BitmapLassoFill]
	for button in bitmap_buttons:
		button.button_pressed = false
	if bitmap and current_tool >= 0 and current_tool < bitmap_buttons.size():
		bitmap_buttons[current_tool].button_pressed = true

	# Destructive/action controls belong to context, not the primary tool rail.
	# Clear is an action, not a drawing tool. Show it only when bitmap editing
	# has context; keep the rail itself visually consistent.
	%BitmapClear.visible = bitmap
	%BitmapCommit.visible = false
	var size_active: bool = bitmap and (current_tool == 0 or current_tool == 1 or current_tool == 2 or current_tool == 3 or current_tool == 4 or current_tool == 5 or current_tool == 7)
	var opacity_active: bool = bitmap and current_tool >= 0 and current_tool <= 8
	var brush_active: bool = bitmap and (current_tool == 0 or current_tool == 1 or current_tool == 2)
	var lasso_active: bool = bitmap and current_tool == 8
	var gradient_active: bool = lasso_active and %LassoFillMode.selected == 1
	%BrushSizeLabel.visible = false
	%BrushSize.visible = false
	%BrushPreset.visible = brush_active and current_tool != 2
	%BrushOpacityLabel.visible = false
	%BrushOpacity.visible = false
	%BrushHardness.visible = brush_active and current_tool == 0
	var fill_active: bool = bitmap and current_tool == 6
	%FillToleranceLabel.visible = false
	%FillTolerance.visible = false
	%BrushColor.visible = drawing_3d_active or (bitmap and (current_tool == 0 or current_tool == 1 or current_tool == 3 or current_tool == 4 or current_tool == 5 or current_tool == 6))
	%ActiveColorLabel.visible = not drawing_3d_active
	%ActiveColor.visible = not drawing_3d_active
	%LassoFillMode.visible = lasso_active
	%LassoColorALabel.visible = lasso_active
	%LassoColorA.visible = lasso_active
	%LassoColorBLabel.visible = gradient_active
	%LassoColorB.visible = gradient_active
	%LassoAngleLabel.visible = gradient_active
	%LassoGradientAngle.visible = gradient_active
	%SculptMode.visible = drawing_sculpt_active
	%SculptStrength.visible = false
	%Fill.visible = drawing_3d_active
	%FillColor.visible = drawing_3d_active
	%StartCap.visible = drawing_3d_active
	%EndCap.visible = drawing_3d_active
	%CapSeparator.visible = drawing_3d_active
	# Floating chrome is content-sized. Never leave an empty or stretched bar.
	var context_controls: Array[Control] = [%BitmapClear,%LassoFillMode,%LassoColorALabel,%LassoColorA,%LassoColorBLabel,%LassoColorB,%LassoAngleLabel,%LassoGradientAngle,%SculptMode,%SculptStrength,%BrushSizeLabel,%BrushSize,%BrushPreset,%BrushOpacityLabel,%BrushOpacity,%BrushHardness,%FillToleranceLabel,%FillTolerance,%BrushColor,%Fill,%FillColor]
	var has_context: bool = false
	for control: Control in context_controls:
		if control.visible:
			has_context = true
			break
	%DrawingContextSurface.visible = workspace == "drawing" and has_context
	%DrawingBar.visible = %DrawingContextSurface.visible
	# The right-hand parameter bank is the canonical Size/Opacity/Strength/etc.
	# control surface for every drawing tool.
	_sync_tool_param_sliders()
	call_deferred("_fit_drawing_floating_chrome")

func _fit_drawing_floating_chrome() -> void:
	if workspace != "drawing": return
	if %DrawingContextSurface.visible:
		var wanted: Vector2 = %DrawingBar.get_combined_minimum_size()
		var max_w: float = maxf(220.0,%ViewportFrame.size.x-150.0)
		var hud_w: float = minf(max_w,wanted.x+28.0)
		%DrawingContextSurface.size = Vector2(hud_w,maxf(54.0,wanted.y+18.0))
		%DrawingBar.size = Vector2(maxf(1.0,hud_w-28.0),maxf(36.0,wanted.y))
	# Tool rail hugs the visible tool buttons instead of spanning the viewport.
	var rail_wanted: Vector2 = %DrawingToolRail.get_combined_minimum_size()
	%DrawingToolSurface.size = Vector2(maxf(62.0,rail_wanted.x+18.0),maxf(1.0,rail_wanted.y+20.0))
	%DrawingToolRail.size = rail_wanted
	# Local animation strip also hugs its controls.
	if %DrawingAnimBar.visible:
		var anim_wanted: Vector2 = %DrawingAnimBar.get_combined_minimum_size()
		%DrawingAnimBar.size = anim_wanted

func _on_drawing_cel_menu(id: int) -> void:
	match id:
		0: _on_drawing_new_cel()
		1: _on_drawing_duplicate_cel()
		2: _on_drawing_delete_cel()
		3: _on_drawing_hold_cel()
		4: _on_drawing_morph_cel()

func _on_workspace_tab_changed(tab: int) -> void:
	var next_workspace: String = ["scene","animation","drawing","rigging","compositor"][tab]
	# Workspaces may have different overlays/panel geometry, but changing editor
	# must never silently change the user's 3D view.
	workspace_camera_states[workspace] = camera_rig.get_state()
	var leaving_drawing: bool = workspace == "drawing" and next_workspace != "drawing"
	if leaving_drawing:
		if %DrawingCanvas.bitmap_mode and not active_drawing_id.is_empty():
			%DrawingCanvas.key_current_cel()
			_ensure_drawing_content_layer("bitmap")
		_finalize_static_bitmap_if_needed()
	workspace = next_workspace
	# Never carry the vertex-weight overlay out of Rigging.
	if workspace != "rigging" and active_rig_runtime != null:
		active_rig_runtime.clear_weight_debug()
	if workspace == "drawing" and drawing_planes.is_empty():
		_on_add_drawing_plane()
	if workspace_camera_states.has(workspace):
		camera_rig.set_state(workspace_camera_states[workspace])
	else:
		workspace_camera_states[workspace] = camera_rig.get_state()
	if workspace == "drawing":
		# Drawing is a true 2D editor onto the selected ReferenceCanvas.
		# Always look straight at that canvas after restoring workspace state.
		_lock_drawing_view_to_canvas()
	else:
		# Orthographic projection belongs only to the 2D Drawing editor.
		# Scene/Animation/Rigging must use perspective so camera dolly changes
		# the apparent size of actual scene geometry.
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	%RightPanel.visible = workspace == "scene" or workspace == "drawing" or workspace == "rigging" or workspace == "compositor"
	_sync_animation_canvas_editor()
	%DrawingToolSurface.visible = workspace == "drawing"
	%DrawingToolRail.visible = workspace == "drawing"
	%DrawingPlaneSurface.visible = workspace == "drawing"
	gizmo.visible = workspace != "drawing" and workspace != "rigging" and workspace != "animation" and selected_scene_node != null
	# Drawing manipulators are editor overlays, never scene content. Scene and
	# every other workspace expose only their own gizmos/overlays.
	var drawing_overlay_visible: bool = workspace == "drawing"
	%GradientGuide.visible = drawing_overlay_visible and drawing_3d_active and %FillMode.selected == 1
	if not drawing_overlay_visible:
		gradient_drag_handle = 0
	%GradientGuide.queue_redraw()
	_update_drawing_tool_ui()
	%DrawingPlanes.visible = workspace == "drawing"
	%ObjectList.visible = workspace != "drawing"
	%RiggingPanel.visible = workspace == "rigging"
	if workspace == "rigging": _refresh_rig_parent_choices()
	%DrawingCanvas.visible = workspace == "drawing" and %DrawingCanvas.bitmap_mode
	%ViewportTop.visible = workspace != "drawing"
	# The axis/camera view gizmo belongs to spatial scene navigation. Drawing is
	# canvas-locked 2D, and Animation should focus on posing/timing rather than
	# exposing scene-view orientation controls.
	%ViewGizmo.visible = workspace != "drawing" and workspace != "animation"
	%ToolRail.visible = workspace != "drawing"
	%Title.text = "DRAWINGS" if workspace == "drawing" else ("ANIMATABLES" if workspace == "animation" else "OBJECTS")
	%Status.text = workspace.to_upper() + " workspace"
	%EditorTitle.text = workspace.to_upper() + " EDITOR"
	# Drawing temporarily presents the active canvas' local clip range in the
	# shared timeline widget. Every other workspace must immediately restore
	# the scene timeline; local clip duration must never become scene duration.
	if workspace == "drawing":
		_sync_local_clip_ui()
	else:
		# Restore both the global timeline model AND its controls. Local clip
		# widgets must never leak their duration/range into Scene.
		%TimelineDuration.set_value_no_signal(ProjectStore.duration_frames)
		%PlaybackStart.set_value_no_signal(ProjectStore.playback_start)
		%PlaybackEnd.set_value_no_signal(ProjectStore.playback_end)
		timeline.set_timeline_range(ProjectStore.duration_frames,ProjectStore.playback_start,ProjectStore.playback_end)
		timeline.set_frame(ProjectStore.current_frame)
		timeline.set_drawing_exposures([])
		timeline.queue_redraw()
	for reference_canvas in drawing_planes:
		if is_instance_valid(reference_canvas):
			reference_canvas.set_guide_visible(workspace == "scene")
	_refresh_scene_object_list()
	_apply_drawing_frame(ProjectStore.current_frame)
	if workspace == "drawing" and active_drawing_group != null:
		_select_scene_node(active_drawing_id, active_drawing_group)
	if workspace == "compositor":
		%LookTitle.text = "◇  EFFECT STACK  ·  Scene Output"
	else:
		%LookTitle.text = "◇  LOOK / FILTERS"

func _canvas_has_vector_content(canvas_id: String) -> bool:
	var data: RefCounted = drawing_data_by_object.get(canvas_id)
	return data != null and data.stroke_order.size() > 0

func _canvas_has_bitmap_content(canvas_id: String) -> bool:
	return not canvas_id.is_empty() and %DrawingCanvas.has_flipbook(canvas_id)

func _persist_active_bitmap_editor() -> void:
	if active_drawing_id.is_empty() or not %DrawingCanvas.bitmap_mode: return
	%DrawingCanvas.key_current_cel()
	_ensure_drawing_content_layer("bitmap")
	%DrawingCanvas.bitmap_mode = false
	%DrawingCanvas.visible = false
	_apply_drawing_frame(ProjectStore.current_frame)

func _create_companion_canvas_for_engine(engine: String, source: ReferenceCanvas) -> void:
	if source == null or not is_instance_valid(source):
		_on_add_drawing_plane()
		return
	var source_transform: Transform3D = source.global_transform
	var source_name: String = source.name
	_on_add_drawing_plane()
	if active_drawing_group == null: return
	var normal: Vector3 = source_transform.basis.z.normalized()
	active_drawing_group.global_transform = Transform3D(source_transform.basis,source_transform.origin-normal*DRAWING_PLANE_SPACING)
	var model: MotionObject = ProjectStore.objects.get(active_drawing_id)
	if model != null:
		model.transform = active_drawing_group.transform
		active_drawing_group.name = source_name + (" · Bitmap" if engine == "bitmap" else " · Grease Pencil")
		model.name = active_drawing_group.name
	_refresh_drawing_planes()
	_refresh_scene_object_list()

func _on_draw_stroke3d_pressed() -> void:
	_lock_drawing_view_to_canvas()
	var source_canvas: ReferenceCanvas = active_drawing_group
	var switching_from_bitmap: bool = %DrawingCanvas.bitmap_mode
	if switching_from_bitmap:
		_persist_active_bitmap_editor()
	if _canvas_has_bitmap_content(active_drawing_id) and not _canvas_has_vector_content(active_drawing_id):
		_create_companion_canvas_for_engine("vector",source_canvas)
	drawing_3d_active = true
	drawing_sculpt_active = false
	drawing_erase_active = false
	%DrawingCanvas.bitmap_mode = false
	%DrawingCanvas.visible = false
	_ensure_drawing_content_layer("vector")
	_apply_drawing_frame(ProjectStore.current_frame)
	_update_drawing_tool_ui()
	active_color_target = "line"
	status.text = "Grease Pencil · vector canvas active"

func _on_draw_bitmap_pressed() -> void:
	_lock_drawing_view_to_canvas()
	var source_canvas: ReferenceCanvas = active_drawing_group
	if not %DrawingCanvas.bitmap_mode and _canvas_has_vector_content(active_drawing_id) and not _canvas_has_bitmap_content(active_drawing_id):
		_create_companion_canvas_for_engine("bitmap",source_canvas)
	if active_drawing_id.is_empty():
		_ensure_drawing_group()
	if not active_drawing_id.is_empty():
		%DrawingCanvas.switch_canvas(active_drawing_id)
	var data: RefCounted = _active_drawing_data()
	if data != null:
		%DrawingCanvas.set_local_frame(data.local_frame)
		data.ensure_flipbook_cel(_drawing_edit_frame())
	_ensure_drawing_content_layer("bitmap")
	if not %DrawingCanvas.has_keyed_cel(_drawing_edit_frame()):
		%DrawingCanvas.begin_new_flipbook_cel()
		%DrawingCanvas.key_current_cel()
	drawing_3d_active = false
	drawing_sculpt_active = false
	drawing_erase_active = false
	%DrawingCanvas.brush_color = bitmap_color
	%DrawingCanvas.opacity = %BrushOpacity.value
	%DrawingCanvas.brush_size = %BrushSize.value
	%GradientGuide.visible = false
	gradient_drag_handle = 0
	%DrawingCanvas.bitmap_mode = true
	%DrawingCanvas.visible = true
	%DrawingCanvas.queue_redraw()
	_refresh_drawing_timeline()
	_update_drawing_tool_ui()
	active_color_target = "bitmap"
	%ActiveColor.set_block_signals(true)
	%ActiveColor.color = bitmap_color
	%ActiveColor.set_block_signals(false)
	%DrawingCanvas.brush_color = bitmap_color
	_paint_color_swatch(%ActiveColor,bitmap_color)
	status.text = "Bitmap paint · persistent raster cel on active canvas"

func _on_draw_sculpt_pressed() -> void:
	drawing_3d_active = false
	drawing_sculpt_active = true
	drawing_erase_active = false
	%DrawingCanvas.bitmap_mode = false
	%DrawingCanvas.visible = false
	# Sculpt needs a genuine spatial view. Start from the current frontal canvas
	# framing, then switch to perspective and let the camera rig orbit freely.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera_rig.align_transform(camera.global_transform)
	orbiting = false
	panning = false
	_update_drawing_tool_ui()
	status.text = "Sculpt · 3D view · MMB orbit · Shift+MMB pan · wheel zoom"

func _on_draw_eraser_pressed() -> void:
	drawing_3d_active = false
	drawing_sculpt_active = false
	drawing_erase_active = true
	%DrawingCanvas.bitmap_mode = false
	%DrawingCanvas.visible = false
	_update_drawing_tool_ui()
	status.text = "Stroke eraser · drag across spatial strokes"

func _erase_drawing(pos: Vector2) -> void:
	if active_drawing_group == null or not is_instance_valid(active_drawing_group): return
	var radius_px := maxf(10.0, %BrushSize.value * 2.5)
	var data: RefCounted = drawing_data_by_object.get(active_drawing_id)
	var changed := false
	for child in active_drawing_group.get_children():
		if not child is Stroke3D: continue
		var stroke := child as Stroke3D
		if not stroke.visible: continue
		for point in stroke.points:
			var world_point := stroke.to_global(point)
			if camera.is_position_behind(world_point): continue
			if camera.unproject_position(world_point).distance_to(pos) <= radius_px:
				stroke.visible = false
				if data and not stroke.stroke_id.is_empty():
					data.call("remove_stroke_from_pose", _drawing_edit_frame(), stroke.stroke_id)
				changed = true
				break
	if changed:
		_refresh_drawing_timeline()

func _sculpt_drawing(pos: Vector2) -> void:
	if active_drawing_group == null or not is_instance_valid(active_drawing_group): return
	var radius_px := maxf(12.0, %BrushSize.value * 2.5)
	var strength: float = float(%SculptStrength.value)
	var changed := false
	var data: RefCounted = drawing_data_by_object.get(active_drawing_id)
	var frame := _drawing_edit_frame()
	var frame_pose: Dictionary = {}
	if data:
		frame_pose = data.cel_pose(frame)
		if frame_pose.is_empty():
			frame_pose = data.flipbook_pose(frame)
			if frame_pose.is_empty():
				frame_pose = data.snapshot_pose()
	for child in active_drawing_group.get_children():
		if child is Stroke3D:
			var stroke := child as Stroke3D
			if stroke.sculpt_screen(pos, camera, radius_px, strength, sculpt_mode):
				changed = true
				if data and not stroke.stroke_id.is_empty():
					var state: Dictionary = frame_pose.get(stroke.stroke_id,{})
					state["points"] = stroke.points.duplicate()
					state["visible"] = bool(state.get("visible",true))
					frame_pose[stroke.stroke_id] = state
	if changed and data:
		# Sculpt edits only the active drawing keyframe. Canonical stroke data is
		# intentionally left untouched so other cels keep their own geometry.
		data.set_exposure(frame, frame_pose, "linear" if auto_key.button_pressed else "hold")
		drawing_controller.invalidate(active_drawing_id)
		_refresh_drawing_timeline()

func _on_brush_size_changed(value: float) -> void:
	%DrawingCanvas.brush_size = value

func _swatch_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1,1,1,0.24)
	return style

func _paint_color_swatch(button: ColorPickerButton, color: Color) -> void:
	button.custom_minimum_size = Vector2(32,32)
	button.color = color
	# ColorPickerButton's native preview is only a thin inset strip. Replacing
	# the button style makes the entire 32x32 chip the color preview.
	button.add_theme_stylebox_override("normal",_swatch_style(color))
	button.add_theme_stylebox_override("hover",_swatch_style(color.lightened(0.08)))
	button.add_theme_stylebox_override("pressed",_swatch_style(color.darkened(0.08)))
	button.add_theme_icon_override("bg",ImageTexture.new())

func _setup_color_swatches() -> void:
	_paint_color_swatch(%BrushColor,%BrushColor.color)
	_paint_color_swatch(%FillColor,%FillColor.color)
	_paint_color_swatch(%FillColorB,%FillColorB.color)
	_paint_color_swatch(%ActiveColor,%ActiveColor.color)

func _refresh_color_swatches() -> void:
	_paint_color_swatch(%BrushColor,%BrushColor.color)
	_paint_color_swatch(%FillColor,%FillColor.color)
	_paint_color_swatch(%FillColorB,%FillColorB.color)
	_paint_color_swatch(%ActiveColor,%ActiveColor.color)

func _refresh_gradient_preview() -> void:
	var image := Image.create(96,32,false,Image.FORMAT_RGBA8)
	var color_a: Color = %FillColor.color
	var color_b: Color = %FillColorB.color
	for x in range(96):
		var t := float(x) / 95.0
		var color := color_a.lerp(color_b,t)
		for y in range(32):
			image.set_pixel(x,y,color)
	%GradientPreview.texture = ImageTexture.create_from_image(image)

func _setup_drawing_palette() -> void:
	for child in %PaletteGrid.get_children():
		child.queue_free()
	for palette_color in drawing_palette:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(32,32)
		var style := StyleBoxFlat.new()
		style.bg_color = palette_color
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3
		swatch.add_theme_stylebox_override("normal",style)
		swatch.tooltip_text = palette_color.to_html()
		swatch.pressed.connect(func(): _apply_palette_color(palette_color))
		%PaletteGrid.add_child(swatch)

func _set_active_color_target(target: String) -> void:
	active_color_target = target
	%ActiveColor.set_block_signals(true)
	match target:
		"fill_a": %ActiveColor.color = gp_fill_color
		"fill_b": %ActiveColor.color = gp_fill_color_b
		"line": %ActiveColor.color = gp_line_color
		_: %ActiveColor.color = bitmap_color
	%ActiveColor.set_block_signals(false)
	_paint_color_swatch(%ActiveColor,%ActiveColor.color)
	%PalettePopup.popup(Rect2i(Vector2i(%ActiveColor.global_position)+Vector2i(0,36),Vector2i(300,118)))

func _apply_palette_color(color: Color) -> void:
	match active_color_target:
		"fill_a":
			gp_fill_color = color
			%FillColor.color = color
		"fill_b":
			gp_fill_color_b = color
			%FillColorB.color = color
		"line":
			gp_line_color = color
			%BrushColor.color = color
		_:
			bitmap_color = color
			%ActiveColor.set_block_signals(true)
			%ActiveColor.color = color
			%ActiveColor.set_block_signals(false)
			%DrawingCanvas.brush_color = bitmap_color
			_paint_color_swatch(%ActiveColor,bitmap_color)
	%PalettePopup.hide()

func _on_bitmap_color_changed(color: Color) -> void:
	if active_color_target != "bitmap": return
	bitmap_color = color
	%DrawingCanvas.brush_color = bitmap_color
	_paint_color_swatch(%ActiveColor,bitmap_color)

func _reset_gradient_handles() -> void:
	var viewport_control: Control = %ViewportContainer as Control
	var rect: Rect2 = viewport_control.get_global_rect()
	var center: Vector2 = rect.position - %GradientGuide.global_position + rect.size * 0.5
	gradient_handle_a = center - Vector2(80,0)
	gradient_handle_b = center + Vector2(80,0)
	%GradientGuide.queue_redraw()

func _draw_gradient_guide() -> void:
	if not %GradientGuide.visible: return
	var a: Vector2 = gradient_handle_a
	var b: Vector2 = gradient_handle_b
	%GradientGuide.draw_dashed_line(a,b,Color(1,1,1,0.9),2.0,8.0)
	%GradientGuide.draw_circle(a,8.0,%FillColor.color)
	%GradientGuide.draw_circle(b,8.0,%FillColorB.color)
	%GradientGuide.draw_arc(a,10.0,0,TAU,24,Color(0.1,0.1,0.1,1),2.0)
	%GradientGuide.draw_arc(b,10.0,0,TAU,24,Color(0.1,0.1,0.1,1),2.0)

func _gradient_guide_input(event: InputEvent) -> bool:
	if not %GradientGuide.visible: return false
	var viewport_control: Control = %ViewportContainer as Control
	var guide_control: Control = %GradientGuide as Control
	var event_pos: Vector2
	if event is InputEventMouseButton:
		event_pos = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion:
		event_pos = (event as InputEventMouseMotion).position
	else:
		return false
	var guide_pos: Vector2 = event_pos + viewport_control.global_position - guide_control.global_position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if guide_pos.distance_to(gradient_handle_a) < 22.0: gradient_drag_handle = 1
			elif guide_pos.distance_to(gradient_handle_b) < 22.0: gradient_drag_handle = 2
			else: return false
		else:
			if gradient_drag_handle == 0: return false
			gradient_drag_handle = 0
		return true
	if event is InputEventMouseMotion and gradient_drag_handle != 0:
		if gradient_drag_handle == 1: gradient_handle_a = guide_pos
		else: gradient_handle_b = guide_pos
		var d: Vector2 = gradient_handle_b-gradient_handle_a
		%FillGradientAngle.value = rad_to_deg(atan2(d.y,d.x))
		%GradientGuide.queue_redraw()
		_apply_selected_stroke_style()
		return true
	return false

func _on_brush_color_changed(value: Color) -> void:
	gp_line_color = value
	_paint_color_swatch(%BrushColor,value)
	_apply_selected_stroke_style()

func _on_fill_color_changed(value: Color) -> void:
	gp_fill_color = value
	_paint_color_swatch(%FillColor,value)
	_refresh_gradient_preview()
	_apply_selected_stroke_style()

func _on_fill_mode_selected(index: int) -> void:
	var gradient := index == 1
	%FillColorB.visible = gradient
	%GradientPreview.visible = gradient
	%FillGradientAngle.visible = false
	%GradientGuide.visible = gradient and workspace == "drawing" and drawing_3d_active
	if gradient and gradient_handle_a == Vector2.ZERO:
		_reset_gradient_handles()
	%GradientGuide.queue_redraw()
	_apply_selected_stroke_style()

func _on_fill_gradient_changed(_value) -> void:
	gp_fill_color_b = %FillColorB.color
	_refresh_color_swatches()
	_refresh_gradient_preview()
	_apply_selected_stroke_style()

func _on_sculpt_mode_selected(index: int) -> void:
	var modes: Array[String] = ["push", "move", "pinch", "smooth", "inflate"]
	sculpt_mode = modes[clampi(index, 0, modes.size() - 1)]
	status.text = "Sculpt · " + %SculptMode.get_item_text(index)

func _apply_selected_stroke_style() -> void:
	# Color controls edit only the selected/last stroke. With no stroke selected
	# they are simply the style for the next stroke.
	if selected_stroke == null or not is_instance_valid(selected_stroke): return
	var line_with_opacity := gp_line_color
	line_with_opacity.a *= gp_opacity
	var fill_with_opacity := gp_fill_color
	fill_with_opacity.a *= gp_opacity
	var fill_b_with_opacity := gp_fill_color_b
	fill_b_with_opacity.a *= gp_opacity
	selected_stroke.set_style(line_with_opacity, %Fill.button_pressed, fill_with_opacity, "gradient" if %FillMode.selected == 1 else "solid", fill_b_with_opacity, float(%FillGradientAngle.value))
	var data: RefCounted = drawing_data_by_object.get(active_drawing_id)
	if data and not selected_stroke.stroke_id.is_empty():
		var record: Dictionary = data.strokes.get(selected_stroke.stroke_id, {})
		record["color"] = line_with_opacity
		record["fill_enabled"] = %Fill.button_pressed
		record["fill_color"] = fill_with_opacity
		record["fill_mode"] = "gradient" if %FillMode.selected == 1 else "solid"
		record["fill_color_b"] = fill_b_with_opacity
		record["fill_gradient_angle"] = float(%FillGradientAngle.value)

func _apply_active_drawing_style() -> void:
	_apply_selected_stroke_style()

func _finalize_static_bitmap_if_needed() -> void:
	if active_drawing_id.is_empty() or active_drawing_group == null: return
	if not %DrawingCanvas.bitmap_mode: return
	# One/no keyed image is a static bitmap: generate/update its tessellated
	# render cache automatically when leaving Drawing. Two or more cels switch
	# representation to a quad texture sequence instead.
	if %DrawingCanvas.is_animated_bitmap(active_drawing_id):
		if static_bitmap_runtime.has(active_drawing_id):
			var old_static: RuntimeObject = static_bitmap_runtime[active_drawing_id]
			if is_instance_valid(old_static): old_static.visible = false
		return
	if not %DrawingCanvas.is_bitmap_dirty(active_drawing_id) and static_bitmap_runtime.has(active_drawing_id): return
	var image: Image = %DrawingCanvas.current_source_image(active_drawing_id)
	if image == null or image.is_empty(): return
	# Tessellation is a destructive render-cache rebuild. Never do it silently:
	# let the artist choose density when leaving Drawing, as in the original workflow.
	_pending_bitmap_batch.clear()
	_pending_bitmap_batch[active_drawing_id] = image
	%TessellationDialog.dialog_text = "Choose tessellation density for this drawing."
	%TessellationDialog.popup_centered()

func _rebuild_static_bitmap_cache(target_canvas: ReferenceCanvas, canvas_id: String, image: Image) -> void:
	if static_bitmap_runtime.has(canvas_id):
		var old_runtime: RuntimeObject = static_bitmap_runtime[canvas_id]
		if is_instance_valid(old_runtime):
			runtime_objects.erase(old_runtime)
			old_runtime.queue_free()
	var obj := MotionObject.new("Static Bitmap", "bitmap_layer", "drawing")
	obj.parent_id = canvas_id
	ProjectStore.add_object(obj)
	var runtime := RuntimeObject.new()
	target_canvas.add_child(runtime)
	_register_scene_object(obj,runtime)
	# Static bitmap uses the canvas itself as its spatial support.
	var hx: float = target_canvas.guide_size.x * 0.5
	var hy: float = target_canvas.guide_size.y * 0.5
	var corners := PackedVector3Array([
		Vector3(-hx,-hy,0), Vector3(hx,-hy,0),
		Vector3(hx,hy,0), Vector3(-hx,hy,0)
	])
	runtime.setup_bitmap(obj, image, corners, int(%TessellationSamples.value))
	runtime_objects.append(runtime)
	static_bitmap_runtime[canvas_id] = runtime

func _on_bitmap_flipbook_stroke_started() -> void:
	_ensure_drawing_content_layer("bitmap")
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	# Starting to paint on a held frame creates a new replacement cel immediately.
	data.ensure_flipbook_cel(_drawing_edit_frame())
	_refresh_drawing_timeline()

func _on_bitmap_finished(_image: Image) -> void:
	_ensure_drawing_group()
	_pending_bitmap_batch = %DrawingCanvas.committed_canvas_images()
	if _pending_bitmap_batch.is_empty(): return
	%TessellationDialog.dialog_text = "Choose tessellation density for all painted canvases."
	%TessellationDialog.popup_centered()
	return

func _commit_pending_bitmap() -> void:
	if _pending_bitmap_batch.is_empty(): return
	var batch: Dictionary = _pending_bitmap_batch.duplicate()
	_pending_bitmap_batch.clear()
	for canvas_id in batch:
		if not scene_nodes.has(canvas_id): continue
		var target_canvas := scene_nodes[canvas_id] as ReferenceCanvas
		if target_canvas == null or not is_instance_valid(target_canvas): continue
		var image: Image = batch[canvas_id]
		_commit_bitmap_to_canvas(target_canvas, String(canvas_id), image)
		%DrawingCanvas.clear_canvas_session(String(canvas_id))
	%DrawingCanvas.visible = false
	%DrawingCanvas.bitmap_mode = false
	status.text = "Bitmap meshes created for all painted canvases"

func _commit_bitmap_to_canvas(target_canvas: ReferenceCanvas, canvas_id: String, image: Image) -> void:
	var obj := MotionObject.new("Bitmap Layer", "bitmap_layer", "drawing")
	obj.parent_id = canvas_id
	ProjectStore.add_object(obj)
	var runtime := RuntimeObject.new()
	target_canvas.add_child(runtime)
	_register_scene_object(obj,runtime)
	# Bitmap painting fills the ReferenceCanvas itself. Do not derive its corners
	# from Control/global screen coordinates: UI chrome and viewport offsets make
	# that projection differ from the vector stroke camera coordinates.
	var hx: float = target_canvas.guide_size.x * 0.5
	var hy: float = target_canvas.guide_size.y * 0.5
	var local_corners := PackedVector3Array([
		Vector3(-hx,-hy,0), Vector3(hx,-hy,0),
		Vector3(hx,hy,0), Vector3(-hx,hy,0)
	])
	runtime.setup_bitmap(obj, image, local_corners, int(%TessellationSamples.value))
	runtime_objects.append(runtime)

func _ray_to_drawing_plane(screen_pos: Vector2, plane: Node3D) -> Vector3:
	# Reference canvases are mathematical XY planes. They have no rendered
	# geometry; strokes/images are projected onto this coordinate system.
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var plane_normal := plane.global_transform.basis.z.normalized()
	var denom := ray_dir.dot(plane_normal)
	if absf(denom) < 0.00001:
		return plane.global_position
	var distance := (plane.global_position - ray_origin).dot(plane_normal) / denom
	return ray_origin + ray_dir * distance

func _sync_drawing_plane_depths() -> void:
	# Reference canvases are spatial work planes, not a forced Z stack.
	# Their transform is defined by the view/projection used when created.
	pass

func _on_add_drawing_plane() -> void:
	drawing_session_index += 1
	var obj := MotionObject.new("Canvas %02d" % drawing_session_index, "reference_canvas", "drawing")
	var plane: ReferenceCanvas = ReferenceCanvasClass.new()
	world_root.add_child(plane)
	# A new reference canvas belongs to the CURRENT drawing projection.
	# Default/front view produces an XY canvas (normal Z). If the user snaps
	# to Z/top before creating it, the canvas becomes a floor (XZ), etc.
	# New canvases use one of the three global orthographic drawing planes.
	# Z/XY is the default; arbitrary camera perspective never becomes canvas orientation.
	var view_basis: Basis = _canvas_basis_for_axis("Z")
	var target_position: Vector3 = camera_rig.pivot
	var stack_index: int = 0
	var new_normal: Vector3 = view_basis.z.normalized()
	for existing in drawing_planes:
		if not is_instance_valid(existing): continue
		var existing_normal: Vector3 = existing.global_transform.basis.z.normalized()
		if absf(existing_normal.dot(new_normal)) > 0.985:
			stack_index += 1
	target_position += -new_normal * DRAWING_PLANE_SPACING * float(stack_index)
	plane.global_transform = Transform3D(view_basis, target_position)
	plane.setup(obj)
	plane.set_guide_visible(workspace == "scene")
	_register_scene_object(obj, plane)
	var drawing_data: DrawingData = DrawingDataClass.new(obj.id)
	drawing_controller.register_canvas(obj.id, plane, drawing_data)
	obj.components["paint"] = {"drawing_data_id": drawing_data.id, "animation_mode": "exposure_and_morph", "reference_canvas": true, "supports_strokes": true, "supports_bitmap": true}
	active_drawing_group = plane
	active_drawing_id = obj.id
	%DrawingCanvas.switch_canvas(active_drawing_id)
	selected_stroke = null
	_refresh_drawing_planes()
	_refresh_scene_object_list()
	_select_scene_node(active_drawing_id, active_drawing_group)
	_sync_canvas_axis_buttons()
	if workspace == "drawing":
		_lock_drawing_view_to_canvas()
	%RightPanel.visible = true
	status.text = "Reference canvas created · drawing is projected onto its coordinates"

func _refresh_drawing_planes() -> void:
	%DrawingPlaneList.clear()
	for plane in drawing_planes:
		if not is_instance_valid(plane): continue
		var canvas_id: String = _reference_canvas_id(plane)
		var model: MotionObject = ProjectStore.objects.get(canvas_id)
		var visibility_icon: Texture2D = EyeIcon if model == null or model.visible else EyeOffIcon
		%DrawingPlaneList.add_item("▱  " + plane.name,visibility_icon)
		%DrawingPlaneList.set_item_metadata(%DrawingPlaneList.item_count - 1, plane)

func _on_drawing_plane_selected(index: int) -> void:
	var plane: ReferenceCanvas = %DrawingPlaneList.get_item_metadata(index)
	if plane == null: return
	active_drawing_group = plane
	selected_stroke = null
	for id in scene_nodes:
		if scene_nodes[id] == plane:
			active_drawing_id = id
			break
	_select_scene_node(active_drawing_id, plane)
	%DrawingCanvas.switch_canvas(active_drawing_id)
	_sync_local_clip_ui()
	_sync_canvas_axis_buttons()
	if workspace == "drawing":
		_lock_drawing_view_to_canvas()
	%RightPanel.visible = true
	_refresh_drawing_timeline()
	status.text = "Active reference canvas · " + plane.name

func _move_active_plane(step: int) -> void:
	if active_drawing_group == null: return
	var idx := drawing_planes.find(active_drawing_group)
	var target: int = clampi(idx + step, 0, drawing_planes.size() - 1)
	if idx < 0 or idx == target: return
	var tmp := drawing_planes[idx]
	drawing_planes[idx] = drawing_planes[target]
	drawing_planes[target] = tmp
	_refresh_drawing_planes()
	%DrawingPlaneList.select(target)

func _on_plane_up() -> void: _move_active_plane(-1)
func _on_plane_down() -> void: _move_active_plane(1)

func _on_plane_delete() -> void:
	if active_drawing_group == null: return
	_delete_reference_canvas(active_drawing_group)

func _delete_reference_canvas(plane: ReferenceCanvas) -> void:
	var id := _reference_canvas_id(plane)
	# Remove runtime children and their logical MotionObjects before freeing the
	# canvas. Otherwise the Outliner keeps orphan Bitmap/VectorDrawing entries
	# whose scene_nodes point to nodes that have already been freed.
	var child_object_ids: Array[String] = []
	if not id.is_empty():
		for object_id_value in ProjectStore.objects.keys():
			var object_id: String = String(object_id_value)
			var child_model: MotionObject = ProjectStore.objects[object_id]
			if child_model != null and child_model.parent_id == id:
				child_object_ids.append(object_id)
	for child in plane.get_children():
		if child is RuntimeObject:
			runtime_objects.erase(child as RuntimeObject)
	for child_id in child_object_ids:
		scene_nodes.erase(child_id)
		ProjectStore.objects.erase(child_id)
	if not id.is_empty():
		static_bitmap_runtime.erase(id)
		drawing_content_layers.erase(id)
		ProjectStore.objects.erase(id)
		scene_nodes.erase(id)
		drawing_controller.unregister_canvas(id, plane)
		%DrawingCanvas.clear_canvas_session(id)
	plane.queue_free()
	active_drawing_group = drawing_planes[-1] if not drawing_planes.is_empty() else null
	active_drawing_id = _reference_canvas_id(active_drawing_group) if active_drawing_group else ""
	selected = null
	selected_scene_node = active_drawing_group
	selected_object_id = active_drawing_id
	gizmo.attach(active_drawing_group)
	_refresh_drawing_planes()
	_refresh_scene_object_list()
	_refresh_drawing_timeline()
	status.text = "Reference canvas deleted"

func _on_plane_duplicate() -> void:
	if active_drawing_group == null: return
	var source := active_drawing_group
	_on_add_drawing_plane()
	active_drawing_group.name = source.name + " Copy"
	for child in source.get_children():
		if child is Stroke3D:
			var src := child as Stroke3D
			var copy := Stroke3DClass.new()
			copy.points = src.points.duplicate()
			copy.stroke_color = src.stroke_color
			copy.radius = src.radius
			copy.point_size_pressure = src.point_size_pressure.duplicate()
			copy.point_opacity_pressure = src.point_opacity_pressure.duplicate()
			copy.brush_preset = src.brush_preset
			copy.width_variation = src.width_variation
			copy.width_frequency = src.width_frequency
			copy.brush_seed = src.brush_seed
			copy.start_cap = src.start_cap
			copy.end_cap = src.end_cap
			copy.fill_enabled = src.fill_enabled
			copy.fill_color = src.fill_color
			active_drawing_group.add_child(copy)
			copy.rebuild()
			var data: RefCounted = drawing_data_by_object.get(active_drawing_id)
			copy.stroke_id = data.add_stroke(copy.points, copy.style_dict())
			data.add_stroke_to_cel(_drawing_edit_frame(), copy.stroke_id)
	_refresh_drawing_planes()

func _ensure_drawing_group() -> void:
	if active_drawing_group != null and is_instance_valid(active_drawing_group): return
	_on_add_drawing_plane()

func _on_new_drawing_pressed() -> void:
	_on_add_drawing_plane()

func _ensure_drawing_content_layer(kind: String) -> void:
	_ensure_drawing_group()
	if active_drawing_id.is_empty(): return
	if not drawing_content_layers.has(active_drawing_id):
		drawing_content_layers[active_drawing_id] = {}
	var layers: Dictionary = drawing_content_layers[active_drawing_id]
	if layers.has(kind): return
	var layer_name := "Bitmap 01" if kind == "bitmap" else "VectorDrawing 01"
	var technical_type := "bitmap_drawing" if kind == "bitmap" else "vector_drawing"
	var layer_obj := MotionObject.new(layer_name, technical_type, "drawing")
	layer_obj.parent_id = active_drawing_id
	ProjectStore.add_object(layer_obj)
	layers[kind] = layer_obj.id
	drawing_content_layers[active_drawing_id] = layers
	_refresh_scene_object_list()

func _stylus_pressure_or_full(value: float) -> float:
	# Mouse devices report 0.0. Treat them as full pressure so the existing
	# desktop mouse behaviour remains unchanged.
	return clampf(value,0.0,1.0) if value > 0.0 else 1.0

func _begin_3d_stroke(pos: Vector2) -> void:
	_ensure_drawing_group()
	_push_vector_undo()
	_ensure_drawing_content_layer("vector")
	var data: RefCounted = _active_drawing_data()
	var frame: int = _drawing_edit_frame()
	if data != null and not data.has_exposure(frame):
		data.ensure_flipbook_cel(frame)
		_apply_drawing_frame(ProjectStore.current_frame)
		_refresh_drawing_timeline()
	active_stroke_3d = Stroke3DClass.new()
	active_stroke_3d.stroke_color = Color(gp_line_color.r,gp_line_color.g,gp_line_color.b,gp_line_color.a*gp_opacity)
	active_stroke_3d.radius = %BrushSize.value * 0.0012
	_apply_stroke_brush(active_stroke_3d)
	active_stroke_3d.fill_enabled = %Fill.button_pressed
	active_stroke_3d.fill_color = Color(gp_fill_color.r,gp_fill_color.g,gp_fill_color.b,gp_fill_color.a*gp_opacity)
	active_stroke_3d.fill_mode = "gradient" if %FillMode.selected == 1 else "solid"
	active_stroke_3d.fill_color_b = Color(gp_fill_color_b.r,gp_fill_color_b.g,gp_fill_color_b.b,gp_fill_color_b.a*gp_opacity)
	active_stroke_3d.fill_gradient_angle = float(%FillGradientAngle.value)
	active_drawing_group.add_child(active_stroke_3d)
	var world_point := _ray_to_drawing_plane(pos, active_drawing_group)
	active_stroke_3d.add_point(active_drawing_group.to_local(world_point),current_stylus_pressure,current_stylus_pressure)

func _extend_3d_stroke(pos: Vector2) -> void:
	if active_stroke_3d and active_drawing_group:
		var world_point := _ray_to_drawing_plane(pos, active_drawing_group)
		active_stroke_3d.add_point(active_drawing_group.to_local(world_point),current_stylus_pressure,current_stylus_pressure)

func _finish_3d_stroke() -> void:
	if active_stroke_3d == null: return
	active_stroke_3d.name = "Stroke %02d" % active_drawing_group.get_child_count()
	var data: RefCounted = drawing_data_by_object.get(active_drawing_id)
	if data:
		active_stroke_3d.stroke_id = data.add_stroke(active_stroke_3d.points, active_stroke_3d.style_dict())
		# The cel owns its strokes explicitly. Runtime visibility from a held
		# previous cel is never sampled when authoring a new frame.
		data.add_stroke_to_cel(_drawing_edit_frame(), active_stroke_3d.stroke_id)
		_apply_drawing_frame(ProjectStore.current_frame)
	selected_stroke = active_stroke_3d
	active_stroke_3d = null
	_select_scene_node(active_drawing_id, active_drawing_group)
	%RightPanel.visible = true
	_refresh_drawing_timeline()

func _on_fill_toggled(enabled: bool) -> void:
	_apply_selected_stroke_style()
	status.text = "Stroke fill enabled" if enabled else "Stroke fill disabled"

func _on_preview_mode_toggled(render_mode: bool) -> void:
	render_preview = render_mode
	_update_preview_mode()

func _update_preview_mode() -> void:
	%PreviewMode.text = "◉  RENDER" if render_preview else "◐  PREVIEW"
	for r in runtime_objects:
		if r.material:
			r.material.set_shader_parameter("render_quality", 1.0 if render_preview else 0.0)

	# Render preview is a clean image-only view. Editor aids never belong in it.
	if render_preview:
		world_grid.visible = false
		gizmo.visible = false
		%ViewGizmo.visible = false
		%CameraFrame.visible = false
		%IKGuide.visible = false
		%GradientGuide.visible = false
		for reference_canvas in drawing_planes:
			if is_instance_valid(reference_canvas):
				reference_canvas.set_guide_visible(false)
		_set_render_camera_gizmo_visible(false)
	else:
		world_grid.visible = %GridToggle.button_pressed
		gizmo.visible = workspace != "drawing" and workspace != "rigging" and workspace != "animation" and selected_scene_node != null
		%ViewGizmo.visible = workspace != "drawing" and workspace != "animation"
		for reference_canvas in drawing_planes:
			if is_instance_valid(reference_canvas):
				reference_canvas.set_guide_visible(workspace == "scene")
		if camera_view_active:
			_update_camera_frame_overlay()
			_set_render_camera_gizmo_visible(false)
		else:
			%CameraFrame.visible = false

func _on_auto_key_toggled(enabled: bool) -> void:
	%AutoKey.text = "● AUTO" if enabled else "○ AUTO"
	%AutoKey.add_theme_color_override("font_color", Color("#ff3030") if enabled else Color("#dce5ef"))
	%AutoKey.add_theme_color_override("font_hover_color", Color("#ff3030") if enabled else Color.WHITE)
	%AutoKey.add_theme_color_override("font_pressed_color", Color("#ff3030") if enabled else Color.WHITE)
	%AutoKey.add_theme_color_override("font_focus_color", Color("#ff3030") if enabled else Color("#dce5ef"))

func _flash_key_button() -> void:
	%Key.text = "● KEY"

func _refresh_transform_readout() -> void:
	if selected_scene_node == null: return
	_show_transform(selected_scene_node)

func _detect_ui_scale() -> float:
	# Keep desktop at the design scale. Mobile/tablet scaling is handled
	# separately so Windows DPI settings cannot unexpectedly enlarge Kabuki.
	if OS.has_feature("mobile"):
		var screen: int = DisplayServer.window_get_current_screen()
		var dpi: int = DisplayServer.screen_get_dpi(screen)
		if dpi >= 260: return 2.0
		if dpi >= 210: return 1.75
		if dpi >= 175: return 1.5
		if dpi >= 145: return 1.25
	return 1.5

func _apply_ui_scale(value: float) -> void:
	ui_scale = clampf(value,1.0,2.0)
	var window := get_window()
	if window != null:
		# Godot scales the complete 2D UI in one pass: controls, fonts, icons,
		# margins and touch targets all keep their designed proportions.
		window.content_scale_factor = ui_scale
	call_deferred("_responsive_layout")

func set_ui_scale_mode(mode: String) -> void:
	ui_scale_mode = mode
	if mode == "auto":
		_apply_ui_scale(_detect_ui_scale())
	else:
		_apply_ui_scale(clampf(float(mode),1.0,2.0))

func _toggle_brush_preset_popup() -> void:
	var button_rect: Rect2 = %BrushMenuButton.get_global_rect()
	%BrushPresetPopup.position = Vector2i(int(button_rect.position.x),int(button_rect.end.y+6.0))
	var wanted: Vector2 = %BrushPresetBar.get_combined_minimum_size()
	%BrushPresetPopup.size = Vector2i(int(wanted.x+16.0),int(wanted.y+16.0))
	%BrushPresetPopup.popup()

func _position_brush_menu() -> void:
	if not %BrushMenuSurface.visible: return
	# Separate floating property card, immediately after the drawing context card.
	%BrushMenuSurface.position = %DrawingContextSurface.position + Vector2(%DrawingContextSurface.size.x+10.0,0.0)
	%BrushMenuSurface.size = Vector2(126.0,%DrawingContextSurface.size.y)

func _responsive_layout() -> void:
	var w: float=size.x
	var h: float=size.y
	if w<900.0 or h<600.0: return
	# Reference-design proportions: the shell is intentionally substantial.
	# At high resolutions controls must not collapse into desktop-sized chrome.
	var outer: float=14.0
	var gap: float=14.0
	var top_h: float=72.0
	var status_h: float=18.0
	var timeline_h: float=clampf(h*0.275,230.0,390.0)
	var content_top: float=outer+top_h+gap
	var content_bottom: float=h-status_h-timeline_h-gap
	var content_h: float=maxf(260.0,content_bottom-content_top)
	var left_w: float=clampf(w*0.165,250.0,340.0)
	var right_w: float=clampf(w*0.19,290.0,380.0)
	var center_left: float=outer+left_w+gap
	var center_right: float=w-outer-right_w-gap

	var top_bar: HBoxContainer = get_node("TopBar") as HBoxContainer
	if top_bar != null:
		top_bar.position=Vector2(outer,10.0)
		top_bar.size=Vector2(w-outer*2.0,46.0)

	%LeftPanel.position=Vector2(outer,content_top)
	%LeftPanel.size=Vector2(left_w,content_h)
	%RightPanel.position=Vector2(center_right+gap,content_top)
	%RightPanel.size=Vector2(right_w,content_h)
	%ViewportFrame.position=Vector2(center_left,content_top)
	%ViewportFrame.size=Vector2(maxf(360.0,center_right-center_left),content_h)
	%EffectsEngine.position=%ViewportFrame.position
	%EffectsEngine.size=%ViewportFrame.size

	%ViewportTop.position=%ViewportFrame.position+Vector2(22.0,20.0)
	%ViewportTop.size=Vector2(maxf(100.0,%ViewportFrame.size.x-44.0),48.0)
	%ToolRail.position=%ViewportFrame.position+Vector2(22.0,82.0)
	var gizmo_size: Vector2=%ViewGizmo.size
	if gizmo_size.x<=1.0: gizmo_size.x=108.0
	%ViewGizmo.position=%ViewportFrame.position+Vector2(%ViewportFrame.size.x-gizmo_size.x-24.0,82.0)
	if camera_view_active: _update_camera_frame_overlay()
	%DrawingCanvas.position=%ViewportFrame.position
	%DrawingCanvas.size=%ViewportFrame.size

	# Drawing follows the approved mockup: a chunky floating rail and one
	# purposeful context card, never a thin full-width toolbar.
	var rail_h: float=minf(660.0,%ViewportFrame.size.y-52.0)
	%DrawingToolSurface.position=%ViewportFrame.position+Vector2(20.0,20.0)
	%DrawingToolSurface.size=Vector2(68.0,rail_h)
	%DrawingToolRail.position=%DrawingToolSurface.position+Vector2(9.0,10.0)
	%DrawingToolRail.size=Vector2(50.0,maxf(100.0,rail_h-20.0))
	var hud_w: float=minf(760.0,maxf(340.0,%ViewportFrame.size.x-156.0))
	%DrawingContextSurface.position=%ViewportFrame.position+Vector2(104.0,20.0)
	%DrawingContextSurface.size=Vector2(hud_w,58.0)
	# Independent floating card on the same HUD row, immediately after
	# the main LINE/FILL/COLOR property card. Position it even while hidden:
	# tool-state changes can make it visible after this layout pass.
	%BrushMenuSurface.position=Vector2(
		%DrawingContextSurface.position.x+%DrawingContextSurface.size.x+10.0,
		%DrawingContextSurface.position.y
	)
	%BrushMenuSurface.size=Vector2(126.0,58.0)
	%DrawingBar.position=Vector2(14.0,9.0)
	%DrawingBar.size=Vector2(hud_w-28.0,40.0)
	# Plane controls share the Drawing HUD row but anchor independently to the
	# viewport's right edge. Never position them relative to the application root.
	var plane_w: float = 272.0
	%DrawingPlaneSurface.position=%ViewportFrame.position+Vector2(%ViewportFrame.size.x-plane_w-16.0,20.0)
	%DrawingPlaneSurface.size=Vector2(plane_w,58.0)
	var param_w: float = 44.0
	var param_h: float = minf(430.0,%ViewportFrame.size.y-210.0)
	var param_right_margin: float = 14.0
	%ToolParamSurface.position=%ViewportFrame.position+Vector2(%ViewportFrame.size.x-param_w-param_right_margin,96.0)
	%ToolParamSurface.size=Vector2(param_w,param_h)
	%ToolFeedbackOverlay.position=%ViewportFrame.position
	%ToolFeedbackOverlay.size=%ViewportFrame.size
	var local_timeline_h: float = 112.0
	%LocalDrawingTimeline.position=%ViewportFrame.position+Vector2(106.0,%ViewportFrame.size.y-local_timeline_h-64.0)
	%LocalDrawingTimeline.size=Vector2(maxf(260.0,%ViewportFrame.size.x-156.0),local_timeline_h)
	%DrawingAnimBar.position=%ViewportFrame.position+Vector2(106.0,%ViewportFrame.size.y-58.0)
	%DrawingAnimBar.size=Vector2(minf(720.0,%ViewportFrame.size.x-156.0),42.0)

	%Bottom.position=Vector2(outer,content_bottom+gap)
	%Bottom.size=Vector2(w-outer*2.0,timeline_h)
	%StatusBar.position=Vector2(outer,h-status_h)
	%StatusBar.size=Vector2(w-outer*2.0,status_h)


func _on_timeline_key_selected(path: String, frame: int, mode: String) -> void:
	%KeyInterpolationPanel.visible = true
	%SelectedKeyInfo.text = "%s  ·  Frame %d  ·  %s" % [path.get_slice(".", 1).capitalize(), frame, mode.capitalize()]

func _on_timeline_key_deselected() -> void:
	%KeyInterpolationPanel.visible = false

func _apply_selected_key_interpolation(mode: String) -> void:
	timeline.set_selected_interpolation(mode)
	var label: String = mode.replace("_", " ").capitalize()
	%SelectedKeyInfo.text = "Selected key  ·  " + label

func _on_key_interp_constant() -> void: _apply_selected_key_interpolation("constant")
func _on_key_interp_linear() -> void: _apply_selected_key_interpolation("linear")
func _on_key_interp_bezier() -> void: _apply_selected_key_interpolation("bezier")
func _on_key_interp_quadratic_in() -> void: _apply_selected_key_interpolation("quadratic_in")
func _on_key_interp_quadratic_out() -> void: _apply_selected_key_interpolation("quadratic_out")
func _on_key_interp_quadratic_in_out() -> void: _apply_selected_key_interpolation("quadratic_in_out")
func _on_key_interp_cubic_in_out() -> void: _apply_selected_key_interpolation("cubic_in_out")
func _on_key_interp_back() -> void: _apply_selected_key_interpolation("back")
func _on_key_interp_bounce() -> void: _apply_selected_key_interpolation("bounce")
func _on_key_interp_elastic() -> void: _apply_selected_key_interpolation("elastic")
