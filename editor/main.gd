extends Control

@onready var viewport: SubViewport = %SceneViewport
@onready var world_root: Node3D = %WorldRoot
@onready var frame_label: Label = %FrameLabel
@onready var status: Label = %Status
@onready var selected_label: Label = %SelectedLabel
@onready var blur_slider: HSlider = %BlurSlider
@onready var glow_slider: HSlider = %GlowSlider
@onready var exposure_slider: HSlider = %ExposureSlider
@onready var saturation_slider: HSlider = %SaturationSlider
@onready var interpolation: OptionButton = %Interpolation
var selected: RuntimeObject
var playing := false
var accumulator := 0.0

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

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("frame_prev"): ProjectStore.set_frame(ProjectStore.current_frame - 1)
	if event.is_action_pressed("frame_next"): ProjectStore.set_frame(ProjectStore.current_frame + 1)

func _on_import_pressed() -> void:
	%FileDialog.popup_centered_ratio(0.7)

func _on_file_selected(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty(): status.text = "Could not load image"; return
	var obj := MotionObject.new(path.get_file(), "image_mesh", "prop")
	ProjectStore.add_object(obj)
	var runtime := RuntimeObject.new(); world_root.add_child(runtime); runtime.setup(obj, img)
	runtime.position = Vector3(0,0,0)
	selected = runtime
	selected_label.text = obj.name + "  [ImageMesh / Prop]"
	status.text = "Imported → alpha sampled → Delaunay mesh generated"
	_sync_controls()

func _interp_name() -> String:
	return ["hold","linear","ease"][interpolation.selected]

func _on_key_position_pressed() -> void:
	if selected == null: return
	ProjectStore.set_key(selected.model.id,"transform.position",ProjectStore.current_frame,selected.position,_interp_name())
	status.text = "Position key @ frame %d" % ProjectStore.current_frame

func _on_effect_changed(value: float, path: String) -> void:
	if selected == null: return
	selected.material.set_shader_parameter(path.trim_prefix("effects."), value)
	selected.model.set_property_path(path,value)

func _on_key_effects_pressed() -> void:
	if selected == null: return
	for pair in [["effects.blur",blur_slider.value],["effects.glow",glow_slider.value],["effects.exposure",exposure_slider.value],["effects.saturation",saturation_slider.value]]:
		ProjectStore.set_key(selected.model.id,pair[0],ProjectStore.current_frame,pair[1],_interp_name())
	status.text = "Effect keys @ frame %d" % ProjectStore.current_frame

func _on_frame_changed(frame: int) -> void:
	frame_label.text = "Frame %03d / %03d" % [frame,ProjectStore.duration_frames]
	%FrameSlider.value = frame
	for n in world_root.get_children():
		if n is RuntimeObject: n.apply_frame(frame)
	_sync_controls()

func _sync_controls() -> void:
	if selected == null: return
	blur_slider.value = selected.material.get_shader_parameter("blur")
	glow_slider.value = selected.material.get_shader_parameter("glow")
	exposure_slider.value = selected.material.get_shader_parameter("exposure")
	saturation_slider.value = selected.material.get_shader_parameter("saturation")

func _on_frame_slider_value_changed(value: float) -> void: ProjectStore.set_frame(int(value))
func _on_prev_pressed() -> void: ProjectStore.set_frame(ProjectStore.current_frame-1)
func _on_next_pressed() -> void: ProjectStore.set_frame(ProjectStore.current_frame+1)
func _on_play_pressed() -> void: playing = not playing; %PlayButton.text = "Pause" if playing else "Play"

func _on_nudge_pressed(axis: Vector3) -> void:
	if selected == null: return
	selected.position += axis * 0.1
	selected.model.transform.origin = selected.position
