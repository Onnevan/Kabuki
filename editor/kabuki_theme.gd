extends RefCounted

# KABUKI UI tokens. Keep visual decisions centralized here.
const BG := "#0A0F14"
const PANEL := "#101820"
const PANEL_RAISED := "#151F29"
const CONTROL := "#18232D"
const CONTROL_HOVER := "#21313E"
const STROKE := "#263541"
const STROKE_SOFT := "#1B2832"
const TEXT := "#D9E3EC"
const MUTED := "#8493A1"
const ACCENT := "#3698D8"
const ACCENT_HOVER := "#45A9E9"

static func box(color:String,radius:int=10,border:String="",padding:float=10.0) -> StyleBoxFlat:
	var b:=StyleBoxFlat.new()
	b.bg_color=Color(color)
	b.corner_radius_top_left=radius; b.corner_radius_top_right=radius
	b.corner_radius_bottom_left=radius; b.corner_radius_bottom_right=radius
	b.content_margin_left=padding; b.content_margin_right=padding
	b.content_margin_top=8; b.content_margin_bottom=8
	if border!="":
		b.border_width_left=1; b.border_width_top=1; b.border_width_right=1; b.border_width_bottom=1
		b.border_color=Color(border)
	return b

static func build() -> Theme:
	var t:=Theme.new()
	t.default_font_size=15
	var text:=Color(TEXT); var muted:=Color(MUTED)
	for kind in ["Label","Button","CheckButton","OptionButton","SpinBox","MenuButton"]:
		t.set_color("font_color",kind,text)
	t.set_color("font_hover_color","Button",Color.WHITE)
	t.set_color("font_pressed_color","Button",Color.WHITE)
	t.set_color("font_uneditable_color","LineEdit",muted)
	t.set_stylebox("normal","Button",box(CONTROL,12,STROKE_SOFT,13))
	t.set_stylebox("hover","Button",box(CONTROL_HOVER,12,STROKE,13))
	t.set_stylebox("pressed","Button",box(ACCENT,12,ACCENT_HOVER,13))
	t.set_stylebox("focus","Button",box("#00000000",12,ACCENT,13))
	t.set_stylebox("normal","OptionButton",box(CONTROL,12,STROKE_SOFT,13))
	t.set_stylebox("hover","OptionButton",box(CONTROL_HOVER,12,STROKE,13))
	t.set_stylebox("normal","MenuButton",box(CONTROL,12,STROKE_SOFT,13))
	t.set_stylebox("hover","MenuButton",box(CONTROL_HOVER,12,STROKE,13))
	t.set_stylebox("normal","CheckButton",box("#121C25",12,STROKE_SOFT,12))
	t.set_stylebox("hover","CheckButton",box(CONTROL_HOVER,12,STROKE,12))
	t.set_stylebox("pressed","CheckButton",box(ACCENT,12,ACCENT_HOVER,12))
	t.set_stylebox("panel","PanelContainer",box(PANEL,16,"#1B2A35",14))
	t.set_stylebox("normal","LineEdit",box("#0D151D",10,"#1D2B36",10))
	t.set_stylebox("normal","ItemList",box("#0D151D",12,"",12))
	t.set_stylebox("focus","ItemList",box("#0C131A",12,"",10))
	t.set_stylebox("selected","ItemList",box("#17364A",8,"",8))
	t.set_stylebox("selected_focus","ItemList",box("#17364A",8,"#285B78",8))
	t.set_color("font_selected_color","TabBar",Color("#A7DAFA"))
	t.set_color("font_unselected_color","TabBar",Color("#8C9AA7"))
	t.set_stylebox("tab_selected","TabBar",box("#173D56",12,"#2D6C91",14))
	t.set_stylebox("tab_unselected","TabBar",box("#0B1218",12,"",14))
	t.set_stylebox("tab_hovered","TabBar",box(PANEL_RAISED,12,"",14))
	t.set_color("font_color","TooltipLabel",text)
	t.set_stylebox("panel","TooltipPanel",box("#18232DEB",9,STROKE,8))
	t.set_constant("h_separation","HBoxContainer",12)
	t.set_constant("v_separation","VBoxContainer",12)
	t.set_constant("outline_size","Label",0)
	t.set_font_size("font_size","Button",14)
	t.set_font_size("font_size","OptionButton",14)
	t.set_font_size("font_size","CheckButton",14)
	t.set_font_size("font_size","LineEdit",14)
	return t
