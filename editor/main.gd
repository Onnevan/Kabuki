extends Control

const KabukiThemeBuilder = preload("res://editor/kabuki_theme.gd")
const Stroke3DClass = preload("res://paint/stroke3d.gd")
const DrawingDataClass = preload("res://paint/drawing_data.gd")
const ReferenceCanvasClass = preload("res://paint/reference_canvas.gd")

@onready var viewport: SubViewport = %SceneViewport
@onready var world_root: Node3D = %WorldRoot
@onready var camera: Camera3D = %Camera3D
@onready var canvas: SubViewportContainer = %ViewportContainer
@onready var object_list: ItemList = %ObjectList
@onready var frame_slider: HSlider = %FrameSlider
@onready var frame_label: Label = %FrameLabel
@onready var timeline: FrameTimeline = %Timeline
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
var drag_offset := Vector3.ZERO
var last_mouse := Vector2.ZERO
var scene_nodes: Dictionary = {}
var wireframe_overlays: Array[MeshInstance3D] = []
var selected_scene_node: Node3D
var selected_object_id := ""
var drawing_3d_active := false
var drawing_sculpt_active := false
var drawing_erase_active := false
var active_stroke_3d: Stroke3D
var active_drawing_group: ReferenceCanvas
var active_drawing_id := ""
var drawing_session_index := 0
var drawing_data_by_object: Dictionary = {}
var sculpt_mode := "push"
var drawing_planes: Array[ReferenceCanvas] = []
var selected_stroke: Stroke3D
const DRAWING_PLANE_SPACING := 1.0
var projection_view_transform := Transform3D.IDENTITY
var projection_view_valid := false
var _pending_bitmap_image: Image
var _pending_bitmap_batch: Dictionary = {}
var static_bitmap_runtime: Dictionary = {} # canvas id -> tessellated RuntimeObject
var workspace_camera_states: Dictionary = {}
var current_project_path := ""
var render_camera_id := ""
var camera_view_active := false
var editor_view_before_camera: Dictionary = {}

func _ready() -> void:
	theme = KabukiThemeBuilder.build()
	ProjectStore.frame_changed.connect(_on_frame_changed)
	ProjectStore.key_changed.connect(timeline.refresh_keys)
	timeline.key_selected.connect(_on_timeline_key_selected)
	timeline.key_deselected.connect(_on_timeline_key_deselected)
	timeline.frame_requested.connect(_on_timeline_frame_requested)
	for label in ["Constant", "Linear", "Bezier", "Quadratic In", "Quadratic Out", "Quadratic In-Out", "Cubic In-Out", "Back", "Bounce", "Elastic"]:
		interpolation.add_item(label)
	interpolation.select(1)
	_setup_shading_menu()
	_setup_add_object_menu()
	_setup_property_panels()
	_on_auto_key_toggled(auto_key.button_pressed)
	camera_rig.setup(camera)
	workspace_camera_states["scene"] = camera_rig.get_state()
	gizmo.set_mode(active_tool)
	_setup_workspace_tabs()
	_setup_drawing_menus()
	%SaveProject.pressed.connect(_on_save_project_pressed)
	%LoadProject.pressed.connect(_on_load_project_pressed)
	%UndoPaint.pressed.connect(%DrawingCanvas.undo_paint)
	%RedoPaint.pressed.connect(%DrawingCanvas.redo_paint)
	%ViewX.pressed.connect(func(): _align_view_axis(Vector3.RIGHT, "X"))
	%ViewY.pressed.connect(func(): _align_view_axis(Vector3.UP, "Y"))
	%ViewZ.pressed.connect(func(): _align_view_axis(Vector3.BACK, "Z"))
	%ViewCamera.pressed.connect(_toggle_render_camera_view)
	%CameraFov.value_changed.connect(_on_camera_fov_changed)
	%CameraResX.value_changed.connect(_on_camera_resolution_changed)
	%CameraResY.value_changed.connect(_on_camera_resolution_changed)
	%CameraDofEnabled.toggled.connect(_on_camera_dof_changed)
	%CameraFocusDistance.value_changed.connect(_on_camera_dof_changed)
	%CameraAperture.value_changed.connect(_on_camera_dof_changed)
	%PlaneDelete.pressed.connect(_on_plane_delete)
	%ClipMode.clear()
	for clip_mode_name in ["Loop", "Ping-Pong", "Hold", "Reverse", "Once"]:
		%ClipMode.add_item(clip_mode_name)
	%ClipMode.item_selected.connect(_on_clip_mode_selected)
	%LocalDuration.value_changed.connect(_on_local_duration_changed)
	%SceneStart.value_changed.connect(_on_scene_start_changed)
	%TessellationDialog.confirmed.connect(_commit_pending_bitmap)
	%SculptMode.clear()
	for label in ["Push / Pull", "Move", "Pinch", "Smooth", "Inflate"]:
		%SculptMode.add_item(label)
	%SculptMode.select(0)
	_update_preview_mode()
	_on_frame_changed(0)
	_responsive_layout()
	resized.connect(_responsive_layout)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo: return
	if key_event.ctrl_pressed and key_event.keycode == KEY_Z:
		if key_event.shift_pressed: %DrawingCanvas.redo_paint()
		else: %DrawingCanvas.undo_paint()
		get_viewport().set_input_as_handled()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_Y:
		%DrawingCanvas.redo_paint()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if playing:
		accumulator += delta
		if accumulator >= 1.0 / ProjectStore.fps:
			accumulator = 0.0
			ProjectStore.set_frame((ProjectStore.current_frame + 1) % (ProjectStore.duration_frames + 1))

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
	ProjectStore.add_object(obj)
	scene_nodes[obj.id] = node
	node.name = obj.name
	object_list.add_item(obj.name)
	object_list.set_item_metadata(object_list.item_count - 1, obj.id)

func _refresh_scene_object_list() -> void:
	object_list.clear()
	# ProjectStore.objects is a Dictionary keyed by UUID. Iterating it directly
	# yields String IDs, not MotionObject instances.
	for object_id in ProjectStore.objects:
		var obj: MotionObject = ProjectStore.objects[object_id]
		if not scene_nodes.has(object_id): continue
		object_list.add_item(obj.name)
		object_list.set_item_metadata(object_list.item_count - 1, object_id)

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
	rig.global_transform = camera.global_transform
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
	# Camera body + forward frustum symbol. The editor camera never renders this
	# because it is ordinary scene geometry attached to the camera object.
	var body := MeshInstance3D.new()
	body.name = "_CameraGizmo"
	var box := BoxMesh.new()
	box.size = Vector3(0.28,0.18,0.18)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.18,0.72,1.0,1.0)
	body.material_override = mat
	rig.add_child(body)
	var lens := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.20,0.16,0.28)
	lens.mesh = prism
	lens.rotation_degrees.x = 90.0
	lens.position.z = -0.22
	lens.material_override = mat
	rig.add_child(lens)
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
		_sync_editor_view_to_render_camera()
		%ViewCamera.text = "▣ CAM ●"
		status.text = "Camera view · final render framing"
	else:
		camera_rig.set_state(editor_view_before_camera)
		%ViewCamera.text = "▣ CAM"
		status.text = "Perspective editor view"

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
	var cam := _scene_camera_node(selected_object_id)
	if cam: cam.fov = value
	if camera_view_active and selected_object_id == render_camera_id: camera.fov = value

func _on_camera_resolution_changed(_value: float) -> void:
	if selected_object_id.is_empty() or not ProjectStore.objects.has(selected_object_id): return
	var obj: MotionObject = ProjectStore.objects[selected_object_id]
	if obj.technical_type != "camera": return
	obj.properties["camera.resolution_x"] = int(%CameraResX.value)
	obj.properties["camera.resolution_y"] = int(%CameraResY.value)

func _on_camera_dof_changed(_value: Variant = null) -> void:
	if selected_object_id.is_empty() or not ProjectStore.objects.has(selected_object_id): return
	var obj: MotionObject = ProjectStore.objects[selected_object_id]
	if obj.technical_type != "camera": return
	obj.properties["camera.dof_enabled"] = %CameraDofEnabled.button_pressed
	obj.properties["camera.focus_distance"] = %CameraFocusDistance.value
	obj.properties["camera.aperture"] = %CameraAperture.value
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
	var path := current_project_path
	if path.is_empty(): path = "user://kabuki_project.kabuki"
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
	var path := current_project_path
	if path.is_empty(): path = "user://kabuki_project.kabuki"
	if not FileAccess.file_exists(path):
		status.text = "No saved project yet"
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return
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
	drawing_planes.clear()
	drawing_data_by_object.clear()
	static_bitmap_runtime.clear()
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
			drawing_planes.append(plane)
			var data: RefCounted = DrawingDataClass.new(obj.id)
			if drawings.has(obj.id): data.load_dict(drawings[obj.id])
			drawing_data_by_object[obj.id] = data
			for stroke_id in data.stroke_order:
				if not data.strokes.has(stroke_id): continue
				var rec: Dictionary = data.strokes[stroke_id]
				var stroke: Stroke3D = Stroke3DClass.new()
				stroke.stroke_id = stroke_id
				stroke.points = rec.get("points", PackedVector3Array())
				stroke.stroke_color = rec.get("color", Color.BLACK)
				stroke.radius = float(rec.get("radius", 0.012))
				stroke.fill_enabled = bool(rec.get("fill_enabled", false))
				stroke.fill_color = rec.get("fill_color", Color.TRANSPARENT)
				plane.add_child(stroke)
				stroke.rebuild()
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

func _select_scene_node(id: String, node: Node3D) -> void:
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
	if selected_scene_node is ReferenceCanvas:
		var reference_canvas := selected_scene_node as ReferenceCanvas
		if reference_canvas.model: reference_canvas.model.transform = reference_canvas.transform

func _on_object_selected(index: int) -> void:
	var id: String = object_list.get_item_metadata(index)
	for r in runtime_objects:
		if r.model.id == id: _select(r); return
	if scene_nodes.has(id):
		_select_scene_node(id, scene_nodes[id])

func _on_delete_pressed() -> void:
	if selected_scene_node == null: return
	if selected_scene_node is ReferenceCanvas:
		_delete_reference_canvas(selected_scene_node as ReferenceCanvas)
		return
	if selected != null:
		runtime_objects.erase(selected)
	if not selected_object_id.is_empty():
		ProjectStore.objects.erase(selected_object_id)
		scene_nodes.erase(selected_object_id)
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
	if selected: ProjectStore.set_key(selected.model.id,"transform.position",ProjectStore.current_frame,selected.position,_interp_name())

func _on_canvas_gui_input(event: InputEvent) -> void:
	if workspace == "drawing":
		# Navigation remains available while drawing: MMB orbit, Shift+MMB pan, wheel zoom.
		if event is InputEventMouseButton:
			last_mouse = event.position
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				camera_rig.zoom(-1.0); return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				camera_rig.zoom(1.0); return
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				if Input.is_key_pressed(KEY_SHIFT): panning = event.pressed
				else: orbiting = event.pressed
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if drawing_3d_active:
					if event.pressed: _begin_3d_stroke(event.position)
					else: _finish_3d_stroke()
					return
				elif drawing_erase_active:
					if event.pressed: _erase_drawing(event.position)
					return
				elif drawing_sculpt_active:
					if event.pressed:
						for child in active_drawing_group.get_children() if active_drawing_group else []:
							if child is Stroke3D: (child as Stroke3D).begin_sculpt(event.position)
						_sculpt_drawing(event.position)
					else:
						for child in active_drawing_group.get_children() if active_drawing_group else []:
							if child is Stroke3D: (child as Stroke3D).end_sculpt()
					return
		elif event is InputEventMouseMotion:
			if orbiting:
				camera_rig.orbit(event.relative); return
			elif panning:
				camera_rig.pan(event.relative); return
			elif drawing_3d_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_extend_3d_stroke(event.position); return
			elif drawing_erase_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_erase_drawing(event.position)
				return
			elif drawing_sculpt_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_sculpt_drawing(event.position); return
	if event is InputEventMouseButton:
		last_mouse = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: camera_rig.zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: camera_rig.zoom(1.0)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if Input.is_key_pressed(KEY_SHIFT): panning = event.pressed
			else: orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
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
				if dragging and auto_key.button_pressed: _key_transform()
				dragging = false; gizmo_axis = TransformGizmo.Axis.NONE
	elif event is InputEventMouseMotion:
		if orbiting: camera_rig.orbit(event.relative)
		elif panning: camera_rig.pan(event.relative)
		elif dragging and selected_scene_node:
			_apply_drag(event.relative, event.position)
		last_mouse = event.position

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

func _align_view_axis(axis: Vector3, label: String) -> void:
	camera_rig.align_axis(axis)
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

func _on_tool_move_pressed() -> void:
	active_tool = TransformGizmo.Mode.MOVE; gizmo.set_mode(active_tool); status.text = "Move tool"
func _on_tool_rotate_pressed() -> void:
	active_tool = TransformGizmo.Mode.ROTATE; gizmo.set_mode(active_tool); status.text = "Rotate tool"
func _on_tool_scale_pressed() -> void:
	active_tool = TransformGizmo.Mode.SCALE; gizmo.set_mode(active_tool); status.text = "Scale tool"
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
	for reference_canvas in drawing_planes:
		if not is_instance_valid(reference_canvas) or reference_canvas.model == null: continue
		reference_canvas.position = ProjectStore.evaluate(reference_canvas.model.id, "transform.position", frame, reference_canvas.model.transform.origin)
		reference_canvas.rotation = ProjectStore.evaluate(reference_canvas.model.id, "transform.rotation", frame, reference_canvas.rotation)
		reference_canvas.scale = ProjectStore.evaluate(reference_canvas.model.id, "transform.scale", frame, reference_canvas.scale)
	_apply_drawing_frame(frame)
	_refresh_drawing_timeline()

func _apply_drawing_frame(frame: int) -> void:
	for object_id in drawing_data_by_object.keys():
		if not scene_nodes.has(object_id): continue
		var group: Node3D = scene_nodes[object_id]
		var data: RefCounted = drawing_data_by_object[object_id]
		var evaluation_frame: int = data.local_frame if workspace == "drawing" and object_id == active_drawing_id else data.map_scene_frame(frame)
		var pose: Dictionary = data.call("flipbook_pose", evaluation_frame)
		# Bitmap drawings are cached as discrete images and played as a texture
		# sequence on the ReferenceCanvas plane. No tessellation is required.
		if group is ReferenceCanvas:
			var reference_canvas := group as ReferenceCanvas
			if %DrawingCanvas.is_animated_bitmap(object_id):
				# The active bitmap is already drawn by the full-size DrawingCanvas
				# editor overlay. Showing its 3D flipbook quad at the same time
				# produces a second, smaller copy at the ReferenceCanvas origin.
				var editing_active_bitmap: bool = workspace == "drawing" and object_id == active_drawing_id and %DrawingCanvas.bitmap_mode
				if editing_active_bitmap:
					reference_canvas.hide_flipbook_image()
				else:
					var bitmap_image: Image = %DrawingCanvas.flipbook_image(object_id, evaluation_frame)
					reference_canvas.show_flipbook_image(bitmap_image)
				if static_bitmap_runtime.has(object_id):
					var cached_static: RuntimeObject = static_bitmap_runtime[object_id]
					if is_instance_valid(cached_static): cached_static.visible = false
			else:
				reference_canvas.hide_flipbook_image()
				if static_bitmap_runtime.has(object_id):
					var cached_static: RuntimeObject = static_bitmap_runtime[object_id]
					if is_instance_valid(cached_static): cached_static.visible = true
		for child in group.get_children():
			if not child is Stroke3D: continue
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

func _active_drawing_data() -> RefCounted:
	if active_drawing_id.is_empty() or not drawing_data_by_object.has(active_drawing_id): return null
	return drawing_data_by_object[active_drawing_id]

func _drawing_edit_frame() -> int:
	var data: RefCounted = _active_drawing_data()
	if data == null: return ProjectStore.current_frame
	return int(data.local_frame) if workspace == "drawing" else ProjectStore.current_frame

func _sync_local_clip_ui() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	%LocalTimelineLabel.text = "LOCAL · " + active_drawing_group.name if active_drawing_group else "LOCAL"
	%LocalDuration.set_value_no_signal(data.local_duration)
	%SceneStart.set_value_no_signal(data.scene_start)
	var modes: Array[String] = ["loop","ping_pong","hold","reverse","once"]
	%ClipMode.select(maxi(0,modes.find(String(data.playback_mode))))
	timeline.frame_count = data.local_duration if workspace == "drawing" else 60
	timeline.set_frame(data.local_frame if workspace == "drawing" else ProjectStore.current_frame)
	timeline.queue_redraw()

func _on_clip_mode_selected(index: int) -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	var modes: Array[String] = ["loop","ping_pong","hold","reverse","once"]
	data.playback_mode = modes[clampi(index,0,modes.size()-1)]

func _on_local_duration_changed(value: float) -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
	data.local_duration = maxi(1,int(value))
	data.set_local_frame(data.local_frame)
	_sync_local_clip_ui()

func _on_scene_start_changed(value: float) -> void:
	var data: RefCounted = _active_drawing_data()
	if data != null: data.scene_start = maxi(0,int(value))

func _refresh_drawing_timeline() -> void:
	var data: RefCounted = _active_drawing_data()
	var frames: Array[int] = []
	if data != null:
		var raw_frames: Array = data.call("exposure_frames")
		for frame_value in raw_frames:
			frames.append(int(frame_value))
	if %DrawingCanvas.bitmap_mode:
		frames = %DrawingCanvas.flipbook_frames()
	timeline.set_drawing_exposures(frames)
	_sync_local_clip_ui()

func _on_drawing_new_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
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
	if data.duplicate_previous_exposure(_drawing_edit_frame()):
		_apply_drawing_frame(ProjectStore.current_frame)
		_refresh_drawing_timeline()
		status.text = "Drawing cel duplicated · frame %d" % ProjectStore.current_frame

func _on_drawing_delete_cel() -> void:
	var data: RefCounted = _active_drawing_data()
	if data == null: return
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
	status.text = "Onion skin prepared · preview pass next" if enabled else "Onion skin off"

func key_active_drawing_pose(interpolation := "hold") -> void:
	if active_drawing_id.is_empty() or not drawing_data_by_object.has(active_drawing_id): return
	var data: RefCounted = drawing_data_by_object[active_drawing_id]
	data.set_exposure(_drawing_edit_frame(), data.snapshot_pose(), interpolation)
	status.text = "Drawing pose keyed at frame %d" % ProjectStore.current_frame

func _on_timeline_frame_requested(frame: int) -> void:
	if workspace == "drawing":
		var data: RefCounted = _active_drawing_data()
		if data == null: return
		data.set_local_frame(frame)
		%DrawingCanvas.set_local_frame(data.local_frame)
		timeline.set_frame(data.local_frame)
		_apply_drawing_frame(ProjectStore.current_frame)
		_refresh_drawing_timeline()
		status.text = "Local frame %d · %s" % [data.local_frame, active_drawing_group.name if active_drawing_group else "Canvas"]
		return
	ProjectStore.set_frame(frame)

func _on_frame_slider_value_changed(value: float) -> void:
	if workspace == "drawing":
		var data: RefCounted = _active_drawing_data()
		if data != null:
			data.set_local_frame(int(value))
			%DrawingCanvas.set_local_frame(data.local_frame)
			timeline.set_frame(data.local_frame)
			_apply_drawing_frame(ProjectStore.current_frame)
			return
	ProjectStore.set_frame(int(value))
func _on_prev_pressed() -> void:
	if workspace == "drawing":
		var data: RefCounted = _active_drawing_data()
		if data != null:
			data.set_local_frame(data.local_frame-1); %DrawingCanvas.set_local_frame(data.local_frame); _sync_local_clip_ui(); _apply_drawing_frame(ProjectStore.current_frame); return
	ProjectStore.set_frame(ProjectStore.current_frame - 1)
func _on_next_pressed() -> void:
	if workspace == "drawing":
		var data: RefCounted = _active_drawing_data()
		if data != null:
			data.set_local_frame(data.local_frame+1); %DrawingCanvas.set_local_frame(data.local_frame); _sync_local_clip_ui(); _apply_drawing_frame(ProjectStore.current_frame); return
	ProjectStore.set_frame(ProjectStore.current_frame + 1)
func _on_play_pressed() -> void:
	playing = not playing; %PlayButton.text = "❚❚" if playing else "▶"
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

func _on_filter_changed(_value: float) -> void:
	effects_engine.set_glow(%Glow.value, %GlowThreshold.value, %GlowRadius.value)
	if selected == null: return
	selected.material.set_shader_parameter("blur", %Blur.value)
	selected.material.set_shader_parameter("exposure", %Exposure.value)
	selected.material.set_shader_parameter("saturation", %Saturation.value)

func _on_reset_filters_pressed() -> void:
	%Blur.value=0.0; %Glow.value=0.0; %GlowThreshold.value=0.7; %GlowRadius.value=3.0; %Exposure.value=0.0; %Saturation.value=1.0
	_on_filter_changed(0.0)

func _setup_workspace_tabs() -> void:
	while %WorkspaceTabs.tab_count > 0:
		%WorkspaceTabs.remove_tab(0)
	for label in ["SCENE", "ANIMATION", "DRAWING", "COMPOSITOR"]:
		%WorkspaceTabs.add_tab(label)
	%WorkspaceTabs.current_tab = 0

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
	var cel_popup: PopupMenu = %CelMenu.get_popup()
	cel_popup.clear()
	for label in ["New Empty Cel", "Duplicate Previous Cel", "Delete Cel", "Hold", "Morph"]:
		cel_popup.add_item(label)
	cel_popup.id_pressed.connect(_on_drawing_cel_menu)
	_update_drawing_tool_ui()

func _set_bitmap_tool(tool: int) -> void:
	_on_draw_bitmap_pressed()
	%DrawingCanvas.set_tool(tool)
	status.text = ["Brush", "Pencil", "Bitmap Eraser", "Line", "Rectangle", "Ellipse", "Fill", "Smudge", "Lasso Fill"][tool]
	_update_drawing_tool_ui()

func _update_drawing_tool_ui() -> void:
	var bitmap: bool = bool(%DrawingCanvas.bitmap_mode)
	for control in [%BitmapBrush,%BitmapPencil,%BitmapSmudge,%BitmapLassoFill,%BitmapEraser,%BitmapLine,%BitmapRect,%BitmapEllipse,%BitmapFillTool,%BitmapClear,%BitmapCommit,%BrushPreset,%BrushOpacity,%BrushHardness]:
		control.visible = bitmap
	%SculptMode.visible = drawing_sculpt_active
	%SculptStrength.visible = drawing_sculpt_active
	%Fill.visible = drawing_3d_active
	%FillColor.visible = drawing_3d_active

func _on_drawing_cel_menu(id: int) -> void:
	match id:
		0: _on_drawing_new_cel()
		1: _on_drawing_duplicate_cel()
		2: _on_drawing_delete_cel()
		3: _on_drawing_hold_cel()
		4: _on_drawing_morph_cel()

func _on_workspace_tab_changed(tab: int) -> void:
	var next_workspace: String = ["scene","animation","drawing","compositor"][tab]
	# Workspaces may have different overlays/panel geometry, but changing editor
	# must never silently change the user's 3D view.
	workspace_camera_states[workspace] = camera_rig.get_state()
	var leaving_drawing: bool = workspace == "drawing" and next_workspace != "drawing"
	if leaving_drawing:
		_finalize_static_bitmap_if_needed()
	workspace = next_workspace
	if workspace_camera_states.has(workspace):
		camera_rig.set_state(workspace_camera_states[workspace])
	else:
		workspace_camera_states[workspace] = camera_rig.get_state()
	%RightPanel.visible = workspace == "scene" or workspace == "drawing" or workspace == "compositor"
	%DrawingBar.visible = workspace == "drawing"
	%DrawingAnimBar.visible = workspace == "drawing"
	%DrawingPlanes.visible = workspace == "drawing"
	%ObjectList.visible = workspace != "drawing"
	%DrawingCanvas.visible = workspace == "drawing" and %DrawingCanvas.bitmap_mode
	%ViewportTop.visible = workspace != "drawing"
	%ToolRail.visible = workspace != "drawing"
	%Title.text = "OBJECTS" if workspace != "drawing" else "DRAWINGS"
	%Status.text = workspace.to_upper() + " workspace"
	%EditorTitle.text = workspace.to_upper() + " EDITOR"
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

func _on_draw_stroke3d_pressed() -> void:
	_capture_projection_view()
	drawing_3d_active = true
	drawing_sculpt_active = false
	drawing_erase_active = false
	%DrawingCanvas.bitmap_mode = false
	%DrawingCanvas.visible = false
	_update_drawing_tool_ui()
	status.text = "Spatial stroke · active reference canvas"

func _on_draw_bitmap_pressed() -> void:
	_capture_projection_view()
	var data: RefCounted = _active_drawing_data()
	if data != null: %DrawingCanvas.set_local_frame(data.local_frame)
	drawing_3d_active = false
	drawing_sculpt_active = false
	drawing_erase_active = false
	%DrawingCanvas.bitmap_mode = true
	%DrawingCanvas.visible = true
	%DrawingCanvas.queue_redraw()
	_update_drawing_tool_ui()
	status.text = "Bitmap paint · true raster layer on active reference canvas"

func _on_draw_sculpt_pressed() -> void:
	drawing_3d_active = false
	drawing_sculpt_active = true
	drawing_erase_active = false
	%DrawingCanvas.bitmap_mode = false
	%DrawingCanvas.visible = false
	_update_drawing_tool_ui()
	status.text = "Sculpt · drag to push strokes in depth · middle mouse orbits viewport"

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
					data.call("remove_stroke_from_pose", ProjectStore.current_frame, stroke.stroke_id)
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
	for child in active_drawing_group.get_children():
		if child is Stroke3D:
			var stroke := child as Stroke3D
			if stroke.sculpt_screen(pos, camera, radius_px, strength, sculpt_mode):
				changed = true
				if data and not stroke.stroke_id.is_empty():
					data.update_stroke_points(stroke.stroke_id, stroke.points)
	if changed and data:
		# Editing a drawing at a frame must create/update that frame's pose.
		# This prevents the evaluator from snapping the sculpt back to an older cel.
		data.set_exposure(ProjectStore.current_frame, data.snapshot_pose(), "linear" if auto_key.button_pressed else "hold")
		_refresh_drawing_timeline()

func _on_brush_size_changed(value: float) -> void:
	%DrawingCanvas.brush_size = value

func _on_brush_color_changed(value: Color) -> void:
	%DrawingCanvas.brush_color = value
	_apply_selected_stroke_style()

func _on_fill_color_changed(_value: Color) -> void:
	_apply_selected_stroke_style()

func _on_sculpt_mode_selected(index: int) -> void:
	var modes: Array[String] = ["push", "move", "pinch", "smooth", "inflate"]
	sculpt_mode = modes[clampi(index, 0, modes.size() - 1)]
	status.text = "Sculpt · " + %SculptMode.get_item_text(index)

func _apply_selected_stroke_style() -> void:
	# Color controls edit only the selected/last stroke. With no stroke selected
	# they are simply the style for the next stroke.
	if selected_stroke == null or not is_instance_valid(selected_stroke): return
	selected_stroke.set_style(%BrushColor.color, %Fill.button_pressed, %FillColor.color)
	var data: RefCounted = drawing_data_by_object.get(active_drawing_id)
	if data and not selected_stroke.stroke_id.is_empty():
		var record: Dictionary = data.strokes.get(selected_stroke.stroke_id, {})
		record["color"] = %BrushColor.color
		record["fill_enabled"] = %Fill.button_pressed
		record["fill_color"] = %FillColor.color

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
	_rebuild_static_bitmap_cache(active_drawing_group, active_drawing_id, image)
	%DrawingCanvas.mark_bitmap_clean(active_drawing_id)

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
	var local_corners := PackedVector3Array()
	var viewport_rect: Rect2 = %ViewportContainer.get_global_rect()
	var canvas_rect: Rect2 = %DrawingCanvas.get_global_rect()
	var global_corners: Array[Vector2] = [
		canvas_rect.position,
		Vector2(canvas_rect.end.x, canvas_rect.position.y),
		canvas_rect.end,
		Vector2(canvas_rect.position.x, canvas_rect.end.y)
	]
	for global_corner in global_corners:
		var viewport_corner: Vector2 = global_corner - viewport_rect.position
		var world_corner: Vector3 = _ray_to_drawing_plane(viewport_corner, target_canvas)
		local_corners.append(target_canvas.to_local(world_corner))
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
	var view_basis: Basis = camera.global_transform.basis.orthonormalized()
	var target_position: Vector3 = camera_rig.pivot
	# Paper-theatre stacking follows the CURRENT view normal. Canvases with
	# approximately the same orientation advance one spacing step toward camera.
	var stack_index: int = 0
	var new_normal: Vector3 = view_basis.z.normalized()
	for existing in drawing_planes:
		if not is_instance_valid(existing): continue
		var existing_normal: Vector3 = existing.global_transform.basis.z.normalized()
		if absf(existing_normal.dot(new_normal)) > 0.985:
			stack_index += 1
	target_position += -new_normal * DRAWING_PLANE_SPACING * float(stack_index)
	plane.global_transform = Transform3D(view_basis, target_position)
	drawing_planes.append(plane)
	plane.setup(obj)
	plane.set_guide_visible(workspace == "scene")
	_register_scene_object(obj, plane)
	drawing_data_by_object[obj.id] = DrawingDataClass.new(obj.id)
	obj.components["paint"] = {"drawing_data_id": drawing_data_by_object[obj.id].id, "animation_mode": "exposure_and_morph", "reference_canvas": true, "supports_strokes": true, "supports_bitmap": true}
	active_drawing_group = plane
	active_drawing_id = obj.id
	%DrawingCanvas.switch_canvas(active_drawing_id)
	selected_stroke = null
	_refresh_drawing_planes()
	_refresh_scene_object_list()
	_select_scene_node(active_drawing_id, active_drawing_group)
	%RightPanel.visible = true
	status.text = "Reference canvas created · drawing is projected onto its coordinates"

func _refresh_drawing_planes() -> void:
	%DrawingPlaneList.clear()
	for plane in drawing_planes:
		if not is_instance_valid(plane): continue
		%DrawingPlaneList.add_item("▱  " + plane.name)
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
	# Remove runtime children from global pick/render registries before freeing.
	for child in plane.get_children():
		if child is RuntimeObject:
			runtime_objects.erase(child as RuntimeObject)
	drawing_planes.erase(plane)
	if not id.is_empty():
		ProjectStore.objects.erase(id)
		scene_nodes.erase(id)
		drawing_data_by_object.erase(id)
		%DrawingCanvas.clear_canvas_session(id)
		static_bitmap_runtime.erase(id)
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

func _begin_3d_stroke(pos: Vector2) -> void:
	_ensure_drawing_group()
	var data: RefCounted = _active_drawing_data()
	var frame: int = _drawing_edit_frame()
	if data != null and not data.has_exposure(frame):
		data.ensure_flipbook_cel(frame)
		_apply_drawing_frame(ProjectStore.current_frame)
		_refresh_drawing_timeline()
	active_stroke_3d = Stroke3DClass.new()
	active_stroke_3d.stroke_color = %BrushColor.color
	active_stroke_3d.radius = %BrushSize.value * 0.0012
	active_stroke_3d.fill_enabled = %Fill.button_pressed
	active_stroke_3d.fill_color = %FillColor.color
	active_drawing_group.add_child(active_stroke_3d)
	var world_point := _ray_to_drawing_plane(pos, active_drawing_group)
	active_stroke_3d.add_point(active_drawing_group.to_local(world_point))

func _extend_3d_stroke(pos: Vector2) -> void:
	if active_stroke_3d and active_drawing_group:
		var world_point := _ray_to_drawing_plane(pos, active_drawing_group)
		active_stroke_3d.add_point(active_drawing_group.to_local(world_point))

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

func _responsive_layout() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 900.0 or h < 600.0: return
	var margin: float = 8.0
	var top_h: float = 50.0
	var status_h: float = 20.0
	var timeline_h: float = clampf(h * 0.245, 190.0, 300.0)
	var content_top: float = margin + top_h + 8.0
	var content_bottom: float = h - status_h - timeline_h - 12.0
	var content_h: float = maxf(260.0, content_bottom - content_top)
	var left_w: float = clampf(w * 0.205, 220.0, 330.0)
	var right_w: float = clampf(w * 0.22, 270.0, 360.0)
	var center_left: float = margin + left_w + 8.0
	var center_right: float = w - margin - right_w - 8.0

	%LeftPanel.position = Vector2(margin, content_top)
	%LeftPanel.size = Vector2(left_w, content_h)
	%RightPanel.position = Vector2(center_right + 8.0, content_top)
	%RightPanel.size = Vector2(right_w, content_h)

	%ViewportFrame.position = Vector2(center_left, content_top)
	%ViewportFrame.size = Vector2(maxf(320.0, center_right - center_left), content_h)
	%EffectsEngine.position = %ViewportFrame.position
	%EffectsEngine.size = %ViewportFrame.size

	%ViewportTop.position = %ViewportFrame.position + Vector2(12.0, 10.0)
	%ViewportTop.size = Vector2(maxf(100.0, %ViewportFrame.size.x - 24.0), 40.0)
	%ToolRail.position = %ViewportFrame.position + Vector2(12.0, 60.0)
	# Axis HUD is pinned to the viewport's top-right corner, independent of
	# window size and side-panel widths.
	var gizmo_size: Vector2 = %ViewGizmo.size
	if gizmo_size.x <= 1.0: gizmo_size.x = 98.0
	%ViewGizmo.position = %ViewportFrame.position + Vector2(%ViewportFrame.size.x - gizmo_size.x - 18.0, 60.0)
	%DrawingCanvas.position = %ViewportFrame.position
	%DrawingCanvas.size = %ViewportFrame.size
	%DrawingBar.position = %ViewportFrame.position + Vector2(12.0, 10.0)
	%DrawingBar.size = Vector2(maxf(100.0, %ViewportFrame.size.x - 24.0), 40.0)
	%DrawingAnimBar.position = %ViewportFrame.position + Vector2(12.0, 50.0)
	%DrawingAnimBar.size = Vector2(maxf(100.0, %ViewportFrame.size.x - 24.0), 36.0)

	%Bottom.position = Vector2(margin, content_bottom + 8.0)
	%Bottom.size = Vector2(w - margin * 2.0, timeline_h)
	%StatusBar.position = Vector2(12.0, h - status_h)
	%StatusBar.size = Vector2(w - 24.0, status_h)

	# ViewportContainer has stretch=true, so it owns SceneViewport sizing.
	# Setting SubViewport.size here causes a warning on every resize event.

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
