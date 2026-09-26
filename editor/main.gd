extends Control

const KabukiThemeBuilder = preload("res://editor/kabuki_theme.gd")

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

func _ready() -> void:
	theme = KabukiThemeBuilder.build()
	ProjectStore.frame_changed.connect(_on_frame_changed)
	ProjectStore.key_changed.connect(timeline.refresh_keys)
	timeline.key_selected.connect(_on_timeline_key_selected)
	timeline.key_deselected.connect(_on_timeline_key_deselected)
	for label in ["Constant", "Linear", "Bezier", "Quadratic In", "Quadratic Out", "Quadratic In-Out", "Cubic In-Out", "Back", "Bounce", "Elastic"]:
		interpolation.add_item(label)
	interpolation.select(1)
	_setup_shading_menu()
	_setup_add_object_menu()
	_setup_property_panels()
	_on_auto_key_toggled(auto_key.button_pressed)
	camera_rig.setup(camera)
	gizmo.set_mode(active_tool)
	_setup_workspace_tabs()
	_update_preview_mode()
	_on_frame_changed(0)
	_responsive_layout()
	resized.connect(_responsive_layout)

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

func _register_scene_object(obj: MotionObject, node: Node3D) -> void:
	ProjectStore.add_object(obj)
	scene_nodes[obj.id] = node
	node.name = obj.name
	object_list.add_item(obj.name)
	object_list.set_item_metadata(object_list.item_count - 1, obj.id)

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
	var cam := Camera3D.new()
	cam.current = false
	cam.position = camera.global_position
	cam.rotation = camera.global_rotation
	world_root.add_child(cam)
	_register_scene_object(obj, cam)
	status.text = "Camera created · scene camera switching is not active yet"

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

func _on_object_selected(index: int) -> void:
	var id: String = object_list.get_item_metadata(index)
	for r in runtime_objects:
		if r.model.id == id: _select(r); return
	if scene_nodes.has(id):
		_select_scene_node(id, scene_nodes[id])

func _on_delete_pressed() -> void:
	if selected == null: return
	var idx := runtime_objects.find(selected)
	if idx >= 0:
		runtime_objects.remove_at(idx); object_list.remove_item(idx)
	selected.queue_free(); selected = null; gizmo.attach(null); timeline.set_object(""); %SelectionLabel.text = "Nothing selected"

func _on_duplicate_pressed() -> void:
	status.text = "Duplicate is reserved for the next pass"

func _interp_name() -> String:
	var modes: Array[String] = ["constant","linear","bezier","quadratic_in","quadratic_out","quadratic_in_out","cubic_in_out","back","bounce","elastic"]
	return modes[clampi(interpolation.selected, 0, modes.size() - 1)]

func _on_interpolation_item_selected(_index: int) -> void:
	timeline.set_selected_interpolation(_interp_name())

func _key_position() -> void:
	if selected: ProjectStore.set_key(selected.model.id,"transform.position",ProjectStore.current_frame,selected.position,_interp_name())

func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		last_mouse = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: camera_rig.zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: camera_rig.zoom(1.0)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if Input.is_key_pressed(KEY_SHIFT): panning = event.pressed
			else: orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				gizmo_axis = gizmo.pick_axis(event.position, camera) if selected else TransformGizmo.Axis.NONE
				if gizmo_axis != TransformGizmo.Axis.NONE:
					dragging = true; transform_start = selected.transform; drag_start_mouse = event.position
					return
				var hit := _pick(event.position)
				if hit != null:
					_select(hit); dragging = true
					var world := _screen_to_view_plane(event.position, hit.global_position)
					drag_offset = hit.global_position - world
				else:
					selected = null; gizmo.attach(null)
					for r in runtime_objects: r.set_selected(false)
					object_list.deselect_all(); timeline.set_object(""); %SelectionLabel.text = "Nothing selected"
			else:
				if dragging and auto_key.button_pressed: _key_transform()
				dragging = false; gizmo_axis = TransformGizmo.Axis.NONE
	elif event is InputEventMouseMotion:
		if orbiting: camera_rig.orbit(event.relative)
		elif panning: camera_rig.pan(event.relative)
		elif dragging and selected:
			_apply_drag(event.relative, event.position)
		last_mouse = event.position

func _apply_drag(relative: Vector2, mouse_pos: Vector2) -> void:
	if selected == null: return
	if gizmo_axis != TransformGizmo.Axis.NONE:
		var total := mouse_pos - drag_start_mouse
		if gizmo_axis == TransformGizmo.Axis.ALL:
			if active_tool == TransformGizmo.Mode.MOVE:
				selected.global_position = _screen_to_view_plane(mouse_pos, transform_start.origin)
				selected.model.transform.origin = selected.position
			elif active_tool == TransformGizmo.Mode.ROTATE:
				selected.transform = transform_start
				selected.rotate(camera.global_transform.basis.z.normalized(), total.x * 0.012)
			elif active_tool == TransformGizmo.Mode.SCALE:
				selected.transform = transform_start
				var uniform_factor := maxf(0.03, 1.0 + (total.x - total.y) * 0.01)
				selected.scale = transform_start.basis.get_scale() * uniform_factor
			_refresh_transform_readout()
			return
		var axis := gizmo.axis_vector(gizmo_axis)
		var amount := (total.x - total.y) * 0.006 * camera_rig.distance
		if active_tool == TransformGizmo.Mode.MOVE:
			selected.position = transform_start.origin + axis * amount
			selected.model.transform.origin = selected.position
		elif active_tool == TransformGizmo.Mode.ROTATE:
			selected.transform = transform_start
			selected.rotate(axis, (total.x - total.y) * 0.012)
			_refresh_transform_readout()
		elif active_tool == TransformGizmo.Mode.SCALE:
			selected.transform = transform_start
			var sc := selected.scale
			var factor := maxf(0.03, 1.0 + (total.x - total.y) * 0.01)
			if gizmo_axis == 0: sc.x *= factor
			elif gizmo_axis == 1: sc.y *= factor
			else: sc.z *= factor
			selected.scale = sc
			_refresh_transform_readout()
	elif active_tool == TransformGizmo.Mode.MOVE:
		selected.global_position = _screen_to_view_plane(mouse_pos, selected.global_position) + drag_offset
		selected.model.transform.origin = selected.position

func _screen_to_view_plane(pos: Vector2, point: Vector3) -> Vector3:
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var normal := -camera.global_transform.basis.z
	var denom := dir.dot(normal)
	if absf(denom) < 0.0001: return point
	var t := (point - origin).dot(normal) / denom
	return origin + dir * t

func _on_tool_move_pressed() -> void:
	active_tool = TransformGizmo.Mode.MOVE; gizmo.set_mode(active_tool); status.text = "Move tool"
func _on_tool_rotate_pressed() -> void:
	active_tool = TransformGizmo.Mode.ROTATE; gizmo.set_mode(active_tool); status.text = "Rotate tool"
func _on_tool_scale_pressed() -> void:
	active_tool = TransformGizmo.Mode.SCALE; gizmo.set_mode(active_tool); status.text = "Scale tool"
func _on_frame_selected_pressed() -> void:
	if selected: camera_rig.frame_target(selected.global_position)

func _on_grid_toggled(enabled: bool) -> void:
	world_grid.visible = enabled

func _key_transform() -> void:
	if selected == null: return
	ProjectStore.set_key(selected.model.id,"transform.position",ProjectStore.current_frame,selected.position,_interp_name())
	ProjectStore.set_key(selected.model.id,"transform.rotation",ProjectStore.current_frame,selected.rotation,_interp_name())
	ProjectStore.set_key(selected.model.id,"transform.scale",ProjectStore.current_frame,selected.scale,_interp_name())

func _pick(pos: Vector2) -> RuntimeObject:
	var best: RuntimeObject = null
	var best_d := 999999.0
	for r in runtime_objects:
		var sp := camera.unproject_position(r.global_position)
		var radius := maxf(28.0, r.screen_radius(camera, viewport.size))
		var d := sp.distance_to(pos)
		if d <= radius and d < best_d: best = r; best_d = d
	return best

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

func _on_frame_slider_value_changed(value: float) -> void: ProjectStore.set_frame(int(value))
func _on_prev_pressed() -> void: ProjectStore.set_frame(ProjectStore.current_frame - 1)
func _on_next_pressed() -> void: ProjectStore.set_frame(ProjectStore.current_frame + 1)
func _on_play_pressed() -> void:
	playing = not playing; %PlayButton.text = "❚❚" if playing else "▶"
func _on_key_pressed() -> void:
	_key_transform()
	_flash_key_button()

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

func _on_workspace_tab_changed(tab: int) -> void:
	workspace = ["scene","animation","drawing","compositor"][tab]
	%RightPanel.visible = workspace == "scene" or workspace == "compositor"
	%Title.text = "OBJECTS" if workspace != "drawing" else "DRAWINGS"
	%Status.text = workspace.to_upper() + " workspace"
	if workspace == "compositor":
		%LookTitle.text = "◇  EFFECT STACK  ·  Scene Output"
	else:
		%LookTitle.text = "◇  LOOK / FILTERS"

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
