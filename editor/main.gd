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

func _ready() -> void:
	theme = KabukiThemeBuilder.build()
	ProjectStore.frame_changed.connect(_on_frame_changed)
	interpolation.add_item("Hold"); interpolation.add_item("Linear"); interpolation.add_item("Ease"); interpolation.select(1)
	camera_rig.setup(camera)
	gizmo.set_mode(active_tool)
	_setup_workspace_tabs()
	_update_preview_mode()
	_on_frame_changed(0)

func _process(delta: float) -> void:
	if playing:
		accumulator += delta
		if accumulator >= 1.0 / ProjectStore.fps:
			accumulator = 0.0
			ProjectStore.set_frame((ProjectStore.current_frame + 1) % (ProjectStore.duration_frames + 1))

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

func _select(obj: RuntimeObject) -> void:
	selected = obj
	for r in runtime_objects: r.set_selected(r == selected)
	for i in object_list.item_count:
		if object_list.get_item_metadata(i) == obj.model.id:
			object_list.select(i); break
	%SelectionLabel.text = obj.model.name
	%PosValue.text = "X %.2f   Y %.2f   Z %.2f" % [obj.position.x,obj.position.y,obj.position.z]
	%RotValue.text = "X %.1f   Y %.1f   Z %.1f" % [rad_to_deg(obj.rotation.x),rad_to_deg(obj.rotation.y),rad_to_deg(obj.rotation.z)]
	%ScaleValue.text = "X %.2f   Y %.2f   Z %.2f" % [obj.scale.x,obj.scale.y,obj.scale.z]
	gizmo.attach(obj)

func _on_object_selected(index: int) -> void:
	var id = object_list.get_item_metadata(index)
	for r in runtime_objects:
		if r.model.id == id: _select(r); return

func _on_delete_pressed() -> void:
	if selected == null: return
	var idx := runtime_objects.find(selected)
	if idx >= 0:
		runtime_objects.remove_at(idx); object_list.remove_item(idx)
	selected.queue_free(); selected = null; gizmo.attach(null); %SelectionLabel.text = "Nothing selected"

func _on_duplicate_pressed() -> void:
	status.text = "Duplicate is reserved for the next pass"

func _interp_name() -> String: return ["hold","linear","ease"][interpolation.selected]

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
					object_list.deselect_all(); %SelectionLabel.text = "Nothing selected"
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

func _on_filter_changed(_value: float) -> void:
	if selected == null: return
	selected.material.set_shader_parameter("blur", %Blur.value)
	selected.material.set_shader_parameter("glow", %Glow.value)
	selected.material.set_shader_parameter("exposure", %Exposure.value)
	selected.material.set_shader_parameter("saturation", %Saturation.value)

func _on_reset_filters_pressed() -> void:
	%Blur.value=0.0; %Glow.value=0.0; %Exposure.value=0.0; %Saturation.value=1.0
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

func _on_preview_mode_toggled(render_mode: bool) -> void:
	render_preview = render_mode
	_update_preview_mode()

func _update_preview_mode() -> void:
	%PreviewMode.text = "◉  RENDER" if render_preview else "◐  PREVIEW"
	for r in runtime_objects:
		if r.material:
			r.material.set_shader_parameter("render_quality", 1.0 if render_preview else 0.0)

func _on_auto_key_toggled(enabled: bool) -> void:
	%AutoKey.text = "●" if enabled else "○"

func _flash_key_button() -> void:
	%Key.text = "● KEY"

func _refresh_transform_readout() -> void:
	if selected == null: return
	%PosValue.text = "X %.2f   Y %.2f   Z %.2f" % [selected.position.x,selected.position.y,selected.position.z]
	%RotValue.text = "X %.1f   Y %.1f   Z %.1f" % [rad_to_deg(selected.rotation.x),rad_to_deg(selected.rotation.y),rad_to_deg(selected.rotation.z)]
	%ScaleValue.text = "X %.2f   Y %.2f   Z %.2f" % [selected.scale.x,selected.scale.y,selected.scale.z]
