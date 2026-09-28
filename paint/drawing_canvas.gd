class_name DrawingCanvas
extends Control

signal bitmap_finished(image: Image)

const TOOL_BRUSH := 0
const TOOL_PENCIL := 1
const TOOL_ERASER := 2
const TOOL_LINE := 3
const TOOL_RECT := 4
const TOOL_ELLIPSE := 5
const TOOL_FILL := 6
const TOOL_SMUDGE := 7
const TOOL_LASSO_FILL := 8

var bitmap_mode := false
var brush_color := Color(0.08, 0.08, 0.08, 1.0)
var brush_size := 10.0
var tool: int = TOOL_BRUSH
var opacity := 1.0
var hardness := 0.78
var flow := 0.34
var spacing_ratio := 0.10
var brush_preset := 0
var pencil_texture := 0.22
var raster: Image
var stroke_start := Vector2.ZERO
var last_point := Vector2.ZERO
var painting := false
var raster_texture: ImageTexture
var canvas_rasters: Dictionary = {}
var active_canvas_id := ""
var lasso_points := PackedVector2Array()
var undo_stack: Array[Image] = []
var redo_stack: Array[Image] = []
const MAX_UNDO := 24

func switch_canvas(canvas_id: String) -> void:
	if canvas_id == active_canvas_id: return
	if not active_canvas_id.is_empty() and raster != null:
		canvas_rasters[active_canvas_id] = raster.duplicate()
	active_canvas_id = canvas_id
	raster = null
	raster_texture = null
	if canvas_rasters.has(canvas_id):
		raster = (canvas_rasters[canvas_id] as Image).duplicate()
		raster_texture = ImageTexture.create_from_image(raster)
	undo_stack.clear()
	redo_stack.clear()
	_ensure_raster()
	queue_redraw()

func committed_canvas_images() -> Dictionary:
	if not active_canvas_id.is_empty() and raster != null:
		canvas_rasters[active_canvas_id] = raster.duplicate()
	var result: Dictionary = {}
	for canvas_id in canvas_rasters:
		var image: Image = canvas_rasters[canvas_id]
		if not image.is_empty():
			result[canvas_id] = image.duplicate()
	return result

func clear_canvas_session(canvas_id: String) -> void:
	canvas_rasters.erase(canvas_id)
	if active_canvas_id == canvas_id:
		clear_canvas_without_history()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(false)
	clip_contents = true

func _ensure_raster() -> void:
	var w := maxi(1, int(size.x))
	var h := maxi(1, int(size.y))
	if raster == null or raster.get_width() != w or raster.get_height() != h:
		var next: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		next.fill(Color.TRANSPARENT)
		if raster != null:
			next.blit_rect(raster, Rect2i(Vector2i.ZERO, raster.get_size()), Vector2i.ZERO)
		raster = next
		raster_texture = ImageTexture.create_from_image(raster)
	elif raster_texture == null:
		raster_texture = ImageTexture.create_from_image(raster)

func _refresh_texture() -> void:
	if raster == null: return
	if raster_texture == null: raster_texture = ImageTexture.create_from_image(raster)
	else: raster_texture.update(raster)

func set_tool(value: int) -> void:
	tool = value
	if tool == TOOL_PENCIL and brush_preset < 4:
		set_brush_preset(4)

func set_brush_preset(value: int) -> void:
	brush_preset = value
	match brush_preset:
		0: hardness = 0.92; flow = 0.55; spacing_ratio = 0.08
		1: hardness = 0.42; flow = 0.20; spacing_ratio = 0.07
		2: hardness = 0.18; flow = 0.10; spacing_ratio = 0.06
		3: hardness = 0.72; flow = 0.28; spacing_ratio = 0.05
		4: hardness = 0.96; flow = 0.72; spacing_ratio = 0.045; pencil_texture = 0.34
		5: hardness = 0.88; flow = 0.48; spacing_ratio = 0.04; pencil_texture = 0.58

func clear_canvas_without_history() -> void:
	_ensure_raster()
	raster.fill(Color.TRANSPARENT)
	undo_stack.clear()
	redo_stack.clear()
	_refresh_texture()
	queue_redraw()

func clear_canvas() -> void:
	_ensure_raster()
	_push_undo()
	raster.fill(Color.TRANSPARENT)
	_refresh_texture()
	queue_redraw()

func _push_undo() -> void:
	if raster == null: return
	undo_stack.append(raster.duplicate())
	if undo_stack.size()>MAX_UNDO: undo_stack.pop_front()
	redo_stack.clear()

func undo_paint() -> void:
	if undo_stack.is_empty() or raster == null: return
	redo_stack.append(raster.duplicate())
	raster=undo_stack.pop_back()
	_refresh_texture(); queue_redraw()

func redo_paint() -> void:
	if redo_stack.is_empty() or raster == null: return
	undo_stack.append(raster.duplicate())
	raster=redo_stack.pop_back()
	_refresh_texture(); queue_redraw()

func finish_bitmap() -> void:
	_ensure_raster()
	bitmap_finished.emit(raster.duplicate())

func _gui_input(event: InputEvent) -> void:
	if not bitmap_mode: return
	_ensure_raster()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT: return
		if mb.pressed:
			_push_undo()
			painting = true
			stroke_start = mb.position
			last_point = mb.position
			if tool == TOOL_FILL:
				_flood_fill(Vector2i(mb.position), _paint_color()); painting = false
			elif tool == TOOL_LASSO_FILL:
				lasso_points = PackedVector2Array([mb.position])
			elif tool == TOOL_BRUSH or tool == TOOL_PENCIL or tool == TOOL_ERASER:
				_paint_segment(mb.position, mb.position)
		else:
			if painting and (tool == TOOL_LINE or tool == TOOL_RECT or tool == TOOL_ELLIPSE):
				_commit_shape(stroke_start, mb.position)
			elif painting and tool == TOOL_LASSO_FILL and lasso_points.size() >= 3:
				_fill_polygon(lasso_points, _paint_color())
			painting = false
			lasso_points.clear()
		queue_redraw()
		return
	if event is InputEventMouseMotion and painting:
		var mm := event as InputEventMouseMotion
		if tool == TOOL_BRUSH or tool == TOOL_PENCIL or tool == TOOL_ERASER:
			_paint_segment(last_point, mm.position)
		elif tool == TOOL_SMUDGE:
			_smudge_segment(last_point, mm.position)
		elif tool == TOOL_LASSO_FILL:
			if lasso_points.is_empty() or lasso_points[-1].distance_to(mm.position) >= 3.0:
				lasso_points.append(mm.position)
		last_point = mm.position
		queue_redraw()

func _draw() -> void:
	if not bitmap_mode: return
	_ensure_raster(); _refresh_texture()
	if raster_texture != null: draw_texture(raster_texture, Vector2.ZERO)
	if not painting: return
	var c := brush_color
	if tool == TOOL_LINE:
		draw_line(stroke_start, last_point, c, brush_size, true)
	elif tool == TOOL_RECT:
		draw_rect(_normalized_rect(stroke_start,last_point),c,false,brush_size)
	elif tool == TOOL_ELLIPSE:
		var rect := _normalized_rect(stroke_start,last_point)
		draw_arc(rect.get_center(),minf(rect.size.x,rect.size.y)*0.5,0,TAU,48,c,brush_size,true)
	elif tool == TOOL_LASSO_FILL and lasso_points.size() > 1:
		draw_polyline(lasso_points,c,2.0,true)

func _normalized_rect(a: Vector2,b: Vector2) -> Rect2:
	var tl := Vector2(minf(a.x,b.x),minf(a.y,b.y))
	var br := Vector2(maxf(a.x,b.x),maxf(a.y,b.y))
	return Rect2(tl,br-tl)

func _paint_color() -> Color:
	var c := brush_color
	c.a *= opacity
	return c

func _paint_segment(a: Vector2,b: Vector2) -> void:
	var dist := a.distance_to(b)
	var spacing := maxf(0.75,brush_size*spacing_ratio)
	var steps := maxi(1,ceili(dist/spacing))
	for i in range(steps+1):
		_stamp(a.lerp(b,float(i)/float(steps)))

func _stamp(p: Vector2) -> void:
	var radius := maxf(0.5,brush_size*0.5)
	var min_x := maxi(0,int(floor(p.x-radius-1.0)))
	var max_x := mini(raster.get_width()-1,int(ceil(p.x+radius+1.0)))
	var min_y := maxi(0,int(floor(p.y-radius-1.0)))
	var max_y := mini(raster.get_height()-1,int(ceil(p.y+radius+1.0)))
	for y in range(min_y,max_y+1):
		for x in range(min_x,max_x+1):
			var d := Vector2(x+0.5,y+0.5).distance_to(p)/radius
			if d > 1.0: continue
			if tool == TOOL_ERASER:
				var dst: Color = raster.get_pixel(x,y)
				var erase_amount := (1.0-smoothstep(0.35,1.0,d))*0.72
				dst.a *= 1.0-erase_amount
				raster.set_pixel(x,y,dst)
				continue
			var coverage := 1.0
			if tool == TOOL_BRUSH:
				coverage = (1.0-smoothstep(clampf(hardness,0.0,0.98),1.0,d))*flow
				if brush_preset == 3:
					var grain := fmod(float((x*73856093)^(y*19349663)),101.0)/101.0
					coverage *= 0.35+grain*0.9
			elif tool == TOOL_PENCIL:
				var fine := absf(sin(float(x*41+y*73))*9187.13)
				fine = fmod(fine,1.0)
				var coarse := absf(sin(float((x/3)*29+(y/3)*53))*4731.71)
				coarse = fmod(coarse,1.0)
				var tooth := smoothstep(0.22,0.78,fine*0.62+coarse*0.38)
				var edge := 1.0-smoothstep(0.72,1.0,d)
				var breakup := 1.0
				if d > 0.58:
					breakup = smoothstep(0.28,0.72,fmod(absf(sin(float(x*67+y*31))*6329.4),1.0))
				coverage = edge*breakup*lerpf(0.28,0.72,tooth)
				coverage *= 0.78 if brush_preset == 5 else 0.58
			_blend_pixel(x,y,_paint_color(),coverage)

func _blend_pixel(x: int,y: int,src: Color,coverage: float) -> void:
	var dst: Color = raster.get_pixel(x,y)
	var sa := clampf(src.a*coverage,0.0,1.0)
	var out_a := sa+dst.a*(1.0-sa)
	if out_a <= 0.0001: raster.set_pixel(x,y,Color.TRANSPARENT); return
	var rgb := (Vector3(src.r,src.g,src.b)*sa+Vector3(dst.r,dst.g,dst.b)*dst.a*(1.0-sa))/out_a
	raster.set_pixel(x,y,Color(rgb.x,rgb.y,rgb.z,out_a))

func _smudge_segment(a: Vector2,b: Vector2) -> void:
	var dist := a.distance_to(b)
	var steps := maxi(1,ceili(dist/maxf(1.0,brush_size*0.12)))
	for i in range(steps+1):
		var p := a.lerp(b,float(i)/float(steps))
		_smudge_stamp(p,(b-a).normalized())

func _smudge_stamp(p: Vector2,direction: Vector2) -> void:
	var radius := maxi(2,int(brush_size*0.5))
	var source_offset := Vector2i(roundi(-direction.x*radius*0.45),roundi(-direction.y*radius*0.45))
	var changes: Array[Dictionary] = []
	for y in range(-radius,radius+1):
		for x in range(-radius,radius+1):
			var d := Vector2(x,y).length()/float(radius)
			if d > 1.0: continue
			var dstp := Vector2i(roundi(p.x)+x,roundi(p.y)+y)
			var srcp := dstp+source_offset
			if not _inside(dstp) or not _inside(srcp): continue
			var amount := (1.0-smoothstep(0.2,1.0,d))*0.22
			var mixed := raster.get_pixelv(dstp).lerp(raster.get_pixelv(srcp),amount)
			changes.append({"p":dstp,"c":mixed})
	for change in changes:
		raster.set_pixelv(change["p"],change["c"])

func _inside(p: Vector2i) -> bool:
	return p.x>=0 and p.y>=0 and p.x<raster.get_width() and p.y<raster.get_height()

func _commit_shape(a: Vector2,b: Vector2) -> void:
	if tool == TOOL_LINE: _paint_segment(a,b); return
	var rect := _normalized_rect(a,b)
	var samples := maxi(24,int(rect.size.length()*0.8))
	if tool == TOOL_RECT:
		var tr := Vector2(rect.end.x,rect.position.y)
		var bl := Vector2(rect.position.x,rect.end.y)
		_paint_segment(rect.position,tr); _paint_segment(tr,rect.end)
		_paint_segment(rect.end,bl); _paint_segment(bl,rect.position)
	elif tool == TOOL_ELLIPSE:
		var center := rect.get_center(); var radii := rect.size*0.5
		var prev := center+Vector2(radii.x,0)
		for i in range(1,samples+1):
			var angle := TAU*float(i)/float(samples)
			var next := center+Vector2(cos(angle)*radii.x,sin(angle)*radii.y)
			_paint_segment(prev,next); prev=next

func _fill_polygon(poly: PackedVector2Array,color: Color) -> void:
	if poly.size()<3: return
	var min_x := raster.get_width()-1; var max_x := 0
	var min_y := raster.get_height()-1; var max_y := 0
	for p in poly:
		min_x=mini(min_x,int(floor(p.x))); max_x=maxi(max_x,int(ceil(p.x)))
		min_y=mini(min_y,int(floor(p.y))); max_y=maxi(max_y,int(ceil(p.y)))
	min_x=maxi(0,min_x); max_x=mini(raster.get_width()-1,max_x)
	min_y=maxi(0,min_y); max_y=mini(raster.get_height()-1,max_y)
	for y in range(min_y,max_y+1):
		for x in range(min_x,max_x+1):
			if Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5),poly):
				_blend_pixel(x,y,color,1.0)

func _flood_fill(seed: Vector2i,replacement: Color) -> void:
	if not _inside(seed): return
	var target: Color=raster.get_pixelv(seed)
	if target.is_equal_approx(replacement): return
	var stack: Array[Vector2i]=[seed]; var seen: Dictionary={}
	while not stack.is_empty():
		var p: Vector2i=stack.pop_back()
		if not _inside(p): continue
		var key: int=p.y*raster.get_width()+p.x
		if seen.has(key): continue
		seen[key]=true
		var c: Color=raster.get_pixelv(p)
		if absf(c.r-target.r)+absf(c.g-target.g)+absf(c.b-target.b)+absf(c.a-target.a)>0.12: continue
		raster.set_pixelv(p,replacement)
		stack.append(p+Vector2i.LEFT); stack.append(p+Vector2i.RIGHT)
		stack.append(p+Vector2i.UP); stack.append(p+Vector2i.DOWN)
