class_name DrawingCanvas
extends Control

signal bitmap_finished(image: Image)

var bitmap_mode := false
var brush_color := Color(0.08, 0.08, 0.08, 1.0)
var brush_size := 10.0
var strokes: Array[PackedVector2Array] = []
var current := PackedVector2Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(false)

func clear_canvas() -> void:
	strokes.clear()
	current = PackedVector2Array()
	queue_redraw()

func finish_bitmap() -> void:
	var image := Image.create(maxi(1, int(size.x)), maxi(1, int(size.y)), false, Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	for stroke in strokes:
		_raster_stroke(image, stroke)
	if current.size() > 1:
		_raster_stroke(image, current)
	bitmap_finished.emit(image)

func _gui_input(event: InputEvent) -> void:
	if not bitmap_mode: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			current = PackedVector2Array([event.position])
		else:
			if current.size() > 1: strokes.append(current)
			current = PackedVector2Array()
			queue_redraw()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if current.is_empty() or current[-1].distance_to(event.position) > 2.0:
			current.append(event.position)
			queue_redraw()

func _draw() -> void:
	if not bitmap_mode: return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.94,0.94,0.94,1.0))
	for stroke in strokes:
		if stroke.size() > 1: draw_polyline(stroke, brush_color, brush_size, true)
	if current.size() > 1: draw_polyline(current, brush_color, brush_size, true)

func _raster_stroke(image: Image, stroke: PackedVector2Array) -> void:
	for i in range(stroke.size() - 1):
		var a := stroke[i]
		var b := stroke[i + 1]
		var length := maxi(1, int(a.distance_to(b)))
		for k in range(length + 1):
			var p := a.lerp(b, float(k) / float(length))
			_stamp(image, Vector2i(int(p.x), int(p.y)))

func _stamp(image: Image, p: Vector2i) -> void:
	var r := maxi(1, int(brush_size * 0.5))
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x*x + y*y > r*r: continue
			var q := p + Vector2i(x,y)
			if q.x >= 0 and q.y >= 0 and q.x < image.get_width() and q.y < image.get_height():
				image.set_pixelv(q, brush_color)
