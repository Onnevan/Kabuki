class_name FrameTimeline
extends Control
var frame_count := 60
var current_frame := 0
var object_id := ""
var scrubbing := false
func _ready() -> void:
	custom_minimum_size = Vector2(0, 170)
	mouse_filter = Control.MOUSE_FILTER_PASS
func set_frame(f:int)->void:
	current_frame=f;queue_redraw()
func set_object(id: String) -> void:
	object_id = id
	queue_redraw()
func refresh_keys(_object_id: String = "", _property_path: String = "", _frame: int = 0) -> void:
	queue_redraw()
func _channel_frames(path: String) -> Array[int]:
	if object_id.is_empty(): return []
	return ProjectStore.get_key_frames(object_id, path)
func _draw()->void:
	var bg:=Color("#11171e");draw_rect(Rect2(Vector2.ZERO,size),bg)
	var header_h:=28.0;var lane_x:=210.0
	draw_rect(Rect2(0,0,lane_x,size.y),Color("#18212b"))
	draw_line(Vector2(lane_x,0),Vector2(lane_x,size.y),Color("#34414f"),1)
	var usable:=maxf(1.0,size.x-lane_x-12.0)
	var step:=usable/float(frame_count)
	for f in range(frame_count+1):
		var x:=lane_x+float(f)*step
		var major:=f%5==0
		draw_line(Vector2(x,header_h if major else header_h-5),Vector2(x,size.y),Color("#34414f",0.72 if major else 0.28),1)
		if major: draw_string(get_theme_default_font(),Vector2(x+3,18),str(f),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#aeb9c6"))
	var rows=["Cajetin","  Position","  Rotation","  Scale"]
	for i in rows.size():
		var y:=header_h+20.0+float(i)*28.0
		if i==0: draw_rect(Rect2(0,y-18,lane_x,27),Color("#24374b"))
		draw_string(get_theme_default_font(),Vector2(16,y),rows[i],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#dbe4ef"))
		draw_line(Vector2(0,y+9),Vector2(size.x,y+9),Color("#28333f"),1)
	var paths: Array[String] = ["transform.position", "transform.rotation", "transform.scale"]
	var key_colors: Array[Color] = [Color("#ff745f"), Color("#b779ff"), Color("#71d67b")]
	for row in range(1,4):
		for k in _channel_frames(paths[row - 1]):
			var x:=lane_x+float(k)*step
			var y:=header_h+20.0+float(row)*28.0-5
			var c: Color = key_colors[row - 1]
			var p:=PackedVector2Array([Vector2(x,y-6),Vector2(x+6,y),Vector2(x,y+6),Vector2(x-6,y)])
			draw_colored_polygon(p,c)
	var px:=lane_x+float(current_frame)*step
	draw_line(Vector2(px,header_h-2),Vector2(px,size.y),Color("#238cff"),3)
	draw_circle(Vector2(px,header_h-4),7,Color("#238cff"))
func _frame_from_x(x: float) -> int:
	var lane_x := 210.0
	var usable := maxf(1.0, size.x - lane_x - 12.0)
	return clampi(roundi((x - lane_x) / usable * frame_count), 0, frame_count)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and e.position.x >= 210.0:
			scrubbing = true
			ProjectStore.set_frame(_frame_from_x(e.position.x))
			accept_event()
		elif not e.pressed and scrubbing:
			scrubbing = false
			accept_event()
	elif e is InputEventMouseMotion and scrubbing:
		ProjectStore.set_frame(_frame_from_x(e.position.x))
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		scrubbing = false
