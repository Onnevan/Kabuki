class_name DrawingCanvas
extends Control

signal bitmap_finished(image: Image)

enum Tool { BRUSH, PENCIL, ERASER, LINE, RECT, ELLIPSE, FILL }

var bitmap_mode := false
var brush_color := Color(0.08, 0.08, 0.08, 1.0)
var brush_size := 10.0
var tool: int = Tool.BRUSH
var opacity := 1.0
var hardness := 0.78
var raster: Image
var stroke_start := Vector2.ZERO
var last_point := Vector2.ZERO
var painting := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(false)

func _ensure_raster() -> void:
	var w := maxi(1, int(size.x))
	var h := maxi(1, int(size.y))
	if raster == null or raster.get_width() != w or raster.get_height() != h:
		var next := Image.create(w, h, false, Image.FORMAT_RGBA8)
		next.fill(Color.TRANSPARENT)
		if raster != null:
			next.blit_rect(raster, Rect2i(Vector2i.ZERO, raster.get_size()), Vector2i.ZERO)
		raster = next

func set_tool(value: int) -> void:
	tool = value

func clear_canvas() -> void:
	_ensure_raster()
	raster.fill(Color.TRANSPARENT)
	queue_redraw()

func finish_bitmap() -> void:
	_ensure_raster()
	bitmap_finished.emit(raster.duplicate())

func _gui_input(event: InputEvent) -> void:
	if not bitmap_mode: return
	_ensure_raster()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			painting = true
			stroke_start = event.position
			last_point = event.position
			if tool == Tool.FILL:
				_flood_fill(Vector2i(event.position), _paint_color())
				painting = false
			elif tool in [Tool.BRUSH, Tool.PENCIL, Tool.ERASER]:
				_paint_segment(event.position, event.position)
		else:
			if painting and tool in [Tool.LINE, Tool.RECT, Tool.ELLIPSE]:
				_commit_shape(stroke_start, event.position)
			painting = false
		queue_redraw()
	elif event is InputEventMouseMotion and painting:
		if tool in [Tool.BRUSH, Tool.PENCIL, Tool.ERASER]:
			_paint_segment(last_point, event.position)
			last_point = event.position
		queue_redraw()
		else:
			last_point = event.position
			queue_redraw()

func _draw() -> void:
	if not bitmap_mode: return
	_ensure_raster()
	var tex := ImageTexture.create_from_image(raster)
	draw_texture(tex, Vector2.ZERO)
	if painting:
		var c := brush_color
		if tool == Tool.LINE:
			draw_line(stroke_start, last_point, c, brush_size, true)
		elif tool == Tool.RECT:
			draw_rect(_normalized_rect(stroke_start, last_point), c, false, brush_size)
		elif tool == Tool.ELLIPSE:
			var rect := _normalized_rect(stroke_start, last_point)
			draw_arc(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.5, 0, TAU, 48, c, brush_size, true)

func _normalized_rect(a: Vector2, b: Vector2) -> Rect2:
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var bottom_right := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(top_left, bottom_right - top_left)

func _paint_color() -> Color:
	var c := brush_color
	c.a *= opacity
	return c

func _paint_segment(a: Vector2, b: Vector2) -> void:
	var distance := a.distance_to(b)
	var spacing := maxf(1.0, brush_size * 0.16)
	var steps := maxi(1, ceili(distance / spacing))
	for i in range(steps + 1):
		_stamp(a.lerp(b, float(i) / float(steps)))

func _stamp(p: Vector2) -> void:
	var radius := maxf(0.5, brush_size * 0.5)
	var min_x := maxi(0, int(floor(p.x - radius - 1.0)))
	var max_x := mini(raster.get_width() - 1, int(ceil(p.x + radius + 1.0)))
	var min_y := maxi(0, int(floor(p.y - radius - 1.0)))
	var max_y := mini(raster.get_height() - 1, int(ceil(p.y + radius + 1.0)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(p) / radius
			if d > 1.0: continue
			if tool == Tool.ERASER:
				var dst := raster.get_pixel(x,y)
				dst.a *= smoothstep(0.0, 1.0, d)
				raster.set_pixel(x,y,dst)
				continue
			var alpha := 1.0
			if tool == Tool.BRUSH:
				var edge_start := clampf(hardness, 0.0, 0.98)
				alpha = 1.0 - smoothstep(edge_start, 1.0, d)
			elif tool == Tool.PENCIL:
				alpha = 1.0 if d <= 1.0 else 0.0
			_blend_pixel(x, y, _paint_color(), alpha)

func _blend_pixel(x: int, y: int, src: Color, coverage: float) -> void:
	var dst := raster.get_pixel(x,y)
	var sa := clampf(src.a * coverage, 0.0, 1.0)
	var out_a := sa + dst.a * (1.0 - sa)
	if out_a <= 0.0001:
		raster.set_pixel(x,y,Color.TRANSPARENT)
		return
	var rgb := (Vector3(src.r,src.g,src.b) * sa + Vector3(dst.r,dst.g,dst.b) * dst.a * (1.0-sa)) / out_a
	raster.set_pixel(x,y,Color(rgb.x,rgb.y,rgb.z,out_a))

func _commit_shape(a: Vector2, b: Vector2) -> void:
	if tool == Tool.LINE:
		_paint_segment(a,b)
		return
	var rect := _normalized_rect(a, b)
	var samples := maxi(24, int(rect.size.length() * 0.8))
	if tool == Tool.RECT:
		_paint_segment(rect.position, Vector2(rect.end.x,rect.position.y))
		_paint_segment(Vector2(rect.end.x,rect.position.y), rect.end)
		_paint_segment(rect.end, Vector2(rect.position.x,rect.end.y))
		_paint_segment(Vector2(rect.position.x,rect.end.y), rect.position)
	elif tool == Tool.ELLIPSE:
		var center := rect.get_center()
		var radii := rect.size * 0.5
		var prev := center + Vector2(radii.x,0)
		for i in range(1,samples+1):
			var angle := TAU * float(i) / float(samples)
			var next := center + Vector2(cos(angle)*radii.x,sin(angle)*radii.y)
			_paint_segment(prev,next)
			prev = next

func _flood_fill(seed: Vector2i, replacement: Color) -> void:
	if seed.x < 0 or seed.y < 0 or seed.x >= raster.get_width() or seed.y >= raster.get_height(): return
	var target := raster.get_pixelv(seed)
	if target.is_equal_approx(replacement): return
	var stack: Array[Vector2i] = [seed]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var p := stack.pop_back()
		var key := p.y * raster.get_width() + p.x
		if seen.has(key): continue
		seen[key] = true
		if p.x < 0 or p.y < 0 or p.x >= raster.get_width() or p.y >= raster.get_height(): continue
		var c := raster.get_pixelv(p)
		if absf(c.r-target.r)+absf(c.g-target.g)+absf(c.b-target.b)+absf(c.a-target.a) > 0.12: continue
		raster.set_pixelv(p,replacement)
		stack.append(p+Vector2i.LEFT); stack.append(p+Vector2i.RIGHT)
		stack.append(p+Vector2i.UP); stack.append(p+Vector2i.DOWN)
