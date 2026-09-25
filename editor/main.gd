extends Control

@onready var viewport: SubViewport = %SceneViewport
@onready var world_root: Node3D = %WorldRoot
@onready var camera: Camera3D = %Camera3D
@onready var canvas: SubViewportContainer = %ViewportContainer
@onready var object_list: ItemList = %ObjectList
@onready var frame_slider: HSlider = %FrameSlider
@onready var frame_label: Label = %FrameLabel
@onready var status: Label = %Status
@onready var auto_key: CheckButton = %AutoKey
@onready var interpolation: OptionButton = %Interpolation
var selected: RuntimeObject
var runtime_objects: Array[RuntimeObject] = []
var playing := false
var accumulator := 0.0
var dragging := false
var panning := false
var drag_offset := Vector3.ZERO
var last_mouse := Vector2.ZERO

func _ready() -> void:
	ProjectStore.frame_changed.connect(_on_frame_changed)
	interpolation.add_item("Hold"); interpolation.add_item("Linear"); interpolation.add_item("Ease"); interpolation.select(1)
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

func _on_object_selected(index: int) -> void:
	var id = object_list.get_item_metadata(index)
	for r in runtime_objects:
		if r.model.id == id: _select(r); return

func _on_delete_pressed() -> void:
	if selected == null: return
	var idx := runtime_objects.find(selected)
	if idx >= 0:
		runtime_objects.remove_at(idx); object_list.remove_item(idx)
	selected.queue_free(); selected = null; %SelectionLabel.text = "Nothing selected"

func _on_duplicate_pressed() -> void:
	status.text = "Duplicate is reserved for the next pass"

func _interp_name() -> String: return ["hold","linear","ease"][interpolation.selected]

func _key_position() -> void:
	if selected: ProjectStore.set_key(selected.model.id,"transform.position",ProjectStore.current_frame,selected.position,_interp_name())

func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		last_mouse = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: camera.position.z = maxf(0.5, camera.position.z - 0.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: camera.position.z += 0.25
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := _pick(event.position)
				if hit != null:
					_select(hit); dragging = true
					var world := _screen_to_plane(event.position, hit.position.z)
					drag_offset = hit.position - world
				else:
					selected = null
					for r in runtime_objects: r.set_selected(false)
					object_list.deselect_all(); %SelectionLabel.text = "Nothing selected"
			else:
				if dragging and auto_key.button_pressed: _key_position()
				dragging = false
	elif event is InputEventMouseMotion:
		if panning:
			camera.position.x -= event.relative.x * camera.position.z * 0.0015
			camera.position.y += event.relative.y * camera.position.z * 0.0015
		elif dragging and selected:
			selected.position = _screen_to_plane(event.position, selected.position.z) + drag_offset
			selected.model.transform.origin = selected.position
		last_mouse = event.position

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
	for r in runtime_objects: r.apply_frame(frame)

func _on_frame_slider_value_changed(value: float) -> void: ProjectStore.set_frame(int(value))
func _on_prev_pressed() -> void: ProjectStore.set_frame(ProjectStore.current_frame - 1)
func _on_next_pressed() -> void: ProjectStore.set_frame(ProjectStore.current_frame + 1)
func _on_play_pressed() -> void:
	playing = not playing; %PlayButton.text = "PAUSE" if playing else "PLAY"
func _on_key_pressed() -> void: _key_position()
