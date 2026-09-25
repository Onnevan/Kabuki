class_name FrameTimeline
extends Control

var frame_count := 60
var current_frame := 0
var object_id := ""
var scrubbing := false
var expanded := [false, false, false]
var selected_key_path := ""
var selected_key_frame := -1
var dragging_key := false
signal key_selected(path: String, frame: int, interpolation: String)
signal key_deselected
const LANE_X := 210.0
const HEADER_H := 28.0
const CHANNELS: Array[String] = ["transform.position","transform.rotation","transform.scale"]
const LABELS: Array[String] = ["Position","Rotation","Scale"]
const COLORS: Array[Color] = [Color("#ff745f"),Color("#b779ff"),Color("#71d67b")]

func _ready()->void:
	custom_minimum_size=Vector2(0,170)
	mouse_filter=Control.MOUSE_FILTER_PASS

func set_frame(f:int)->void: current_frame=f;queue_redraw()
func set_object(id:String)->void: object_id=id;selected_key_frame=-1;selected_key_path="";key_deselected.emit();queue_redraw()
func refresh_keys(_a:String="",_b:String="",_c:int=0)->void: queue_redraw()

func _keys(path:String)->Array:
	if object_id.is_empty(): return []
	return ProjectStore.get_keys(object_id,path)

func _row_y(index:int)->float:
	var y:=HEADER_H+32.0
	for i in range(index):
		y+=28.0
		if expanded[i]: y+=58.0
	return y

func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#11171e"))
	draw_rect(Rect2(0,0,LANE_X,size.y),Color("#18212b"))
	var usable:=maxf(1.0,size.x-LANE_X-12.0)
	var step:=usable/float(frame_count)
	for f in range(frame_count+1):
		var x:=LANE_X+float(f)*step
		var major:=f%5==0
		draw_line(Vector2(x,HEADER_H if major else HEADER_H-5),Vector2(x,size.y),Color("#34414f",0.7 if major else 0.24),1)
		if major: draw_string(get_theme_default_font(),Vector2(x+3,18),str(f),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#aeb9c6"))
	draw_string(get_theme_default_font(),Vector2(16,20),("▼ " if expanded.has(true) else "▶ ")+"Selected Object",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#dbe4ef"))
	for row in range(3):
		var y:=_row_y(row)
		draw_rect(Rect2(0,y-20,LANE_X,27),Color("#202b36"))
		draw_string(get_theme_default_font(),Vector2(14,y),("▼ " if expanded[row] else "▶ ")+LABELS[row],HORIZONTAL_ALIGNMENT_LEFT,-1,13,COLORS[row])
		draw_line(Vector2(0,y+8),Vector2(size.x,y+8),Color("#28333f"),1)
		for k in _keys(CHANNELS[row]):
			var kf:=int(k.frame)
			var x:=LANE_X+float(kf)*step
			var p:=PackedVector2Array([Vector2(x,y-7),Vector2(x+6,y-1),Vector2(x,y+5),Vector2(x-6,y-1)])
			draw_colored_polygon(p,Color.WHITE if selected_key_path==CHANNELS[row] and selected_key_frame==kf else COLORS[row])
		if expanded[row]: _draw_curve(row,y+12.0,step)
	var px:=LANE_X+float(current_frame)*step
	draw_line(Vector2(px,HEADER_H-2),Vector2(px,size.y),Color("#238cff"),3)
	draw_circle(Vector2(px,HEADER_H-4),7,Color("#238cff"))

func _component(v:Variant,index:int)->float:
	if v is Vector3: return [v.x,v.y,v.z][index]
	return float(v) if v is float or v is int else 0.0

func _curve_t(t: float, mode: String) -> float:
	t = clampf(t, 0.0, 1.0)
	match mode:
		"constant", "hold": return 0.0
		"linear": return t
		"bezier", "ease": return t * t * (3.0 - 2.0 * t)
		"quadratic_in": return t * t
		"quadratic_out": return 1.0 - (1.0 - t) * (1.0 - t)
		"quadratic_in_out": return 2.0*t*t if t < 0.5 else 1.0 - pow(-2.0*t+2.0,2.0)/2.0
		"cubic_in_out": return 4.0*t*t*t if t < 0.5 else 1.0 - pow(-2.0*t+2.0,3.0)/2.0
		"back":
			var c1: float = 1.70158
			var c3: float = c1 + 1.0
			return c3*t*t*t-c1*t*t
		"bounce": return _curve_bounce_out(t)
		"elastic":
			if is_zero_approx(t) or is_equal_approx(t,1.0): return t
			var c4: float = (2.0*PI)/3.0
			return pow(2.0,-10.0*t)*sin((t*10.0-0.75)*c4)+1.0
	return t

func _curve_bounce_out(t: float) -> float:
	var n1: float=7.5625
	var d1: float=2.75
	if t < 1.0/d1: return n1*t*t
	if t < 2.0/d1:
		t-=1.5/d1
		return n1*t*t+0.75
	if t < 2.5/d1:
		t-=2.25/d1
		return n1*t*t+0.9375
	t-=2.625/d1
	return n1*t*t+0.984375

func _draw_curve(row:int,top:float,step:float)->void:
	var ks:=_keys(CHANNELS[row])
	draw_rect(Rect2(LANE_X,top,size.x-LANE_X,54),Color("#0d1319"))
	if ks.is_empty(): return
	var component_colors: Array[Color] = [Color("#ff6257"),Color("#63d17a"),Color("#4a9cff")]
	for component in range(3):
		var values:Array[float]=[]
		for k in ks: values.append(_component(k.value,component))
		var lo:float=float(values.min())
		var hi:float=float(values.max())
		var span:float=maxf(0.001,hi-lo)
		var pts:=PackedVector2Array()
		if ks.size()==1:
			var sx:float=LANE_X+float(ks[0].frame)*step
			var sy:float=top+44.0-(values[0]-lo)/span*36.0
			pts.append(Vector2(sx,sy))
		else:
			for seg in range(ks.size()-1):
				var a=ks[seg]
				var b=ks[seg+1]
				var samples:int=maxi(2,int(b.frame)-int(a.frame))
				for sample in range(samples+1):
					if seg>0 and sample==0: continue
					var t:float=float(sample)/float(samples)
					var eased:float=_curve_t(t,String(a.interpolation))
					var frame_f:float=lerpf(float(a.frame),float(b.frame),t)
					var value_f:float=lerpf(_component(a.value,component),_component(b.value,component),eased)
					var x:float=LANE_X+frame_f*step
					var yy:float=top+44.0-(value_f-lo)/span*36.0
					pts.append(Vector2(x,yy))
		if pts.size()>1: draw_polyline(pts,component_colors[component],1.5,true)
		for k in ks:
			var kx:float=LANE_X+float(k.frame)*step
			var ky:float=top+44.0-(_component(k.value,component)-lo)/span*36.0
			draw_circle(Vector2(kx,ky),2.5,component_colors[component])
	draw_string(get_theme_default_font(),Vector2(16,top+34),"X   Y   Z   · curve",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#8291a3"))

func _frame_from_x(x:float)->int:
	var usable:=maxf(1.0,size.x-LANE_X-12.0)
	return clampi(roundi((x-LANE_X)/usable*frame_count),0,frame_count)

func _hit_key(pos:Vector2)->Dictionary:
	var usable:=maxf(1.0,size.x-LANE_X-12.0);var step:=usable/float(frame_count)
	for row in range(3):
		var y:=_row_y(row)
		for k in _keys(CHANNELS[row]):
			var x:=LANE_X+float(k.frame)*step
			if pos.distance_to(Vector2(x,y-1))<9.0:return {"path":CHANNELS[row],"frame":int(k.frame)}
	return {}

func _gui_input(e:InputEvent)->void:
	if e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT:
		if e.pressed:
			if e.position.x<LANE_X:
				for row in range(3):
					var y:=_row_y(row)
					if absf(e.position.y-y)<16.0:
						expanded[row]=not expanded[row];custom_minimum_size.y=170.0+58.0*expanded.count(true);queue_redraw();accept_event();return
			var hit:=_hit_key(e.position)
			if not hit.is_empty():
				selected_key_path=hit.path;selected_key_frame=hit.frame;dragging_key=true
				key_selected.emit(selected_key_path, selected_key_frame, get_selected_interpolation())
				queue_redraw();accept_event();return
			if e.position.x>=LANE_X:
				scrubbing=true;ProjectStore.set_frame(_frame_from_x(e.position.x));accept_event()
		else:
			scrubbing=false;dragging_key=false
	elif e is InputEventMouseMotion:
		if dragging_key and selected_key_frame>=0:
			var nf:=_frame_from_x(e.position.x)
			if nf!=selected_key_frame:
				ProjectStore.move_key(object_id,selected_key_path,selected_key_frame,nf);selected_key_frame=nf;queue_redraw()
			accept_event()
		elif scrubbing:
			ProjectStore.set_frame(_frame_from_x(e.position.x));accept_event()

func get_selected_interpolation() -> String:
	if selected_key_frame < 0 or selected_key_path.is_empty(): return ""
	for k in _keys(selected_key_path):
		if int(k.frame) == selected_key_frame:
			return String(k.interpolation)
	return ""

func set_selected_interpolation(name:String)->void:
	if selected_key_frame>=0 and not selected_key_path.is_empty():
		ProjectStore.set_key_interpolation(object_id,selected_key_path,selected_key_frame,name)
		key_selected.emit(selected_key_path, selected_key_frame, name)
		queue_redraw()
