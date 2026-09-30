extends RefCounted

static func box(color:String, radius:int=8, border:String="", padding:float=9.0) -> StyleBoxFlat:
	var b:=StyleBoxFlat.new()
	b.bg_color=Color(color)
	b.corner_radius_top_left=radius; b.corner_radius_top_right=radius
	b.corner_radius_bottom_left=radius; b.corner_radius_bottom_right=radius
	b.content_margin_left=padding; b.content_margin_right=padding
	b.content_margin_top=7; b.content_margin_bottom=7
	if border!="":
		b.border_width_left=1; b.border_width_top=1; b.border_width_right=1; b.border_width_bottom=1
		b.border_color=Color(border)
	return b

static func build() -> Theme:
	var t:=Theme.new()
	t.default_font_size=13
	var text:=Color("#d9e2ec")
	var muted:=Color("#8f9dab")
	var accent:=Color("#4da3e6")
	t.set_color("font_color","Label",text)
	t.set_color("font_color","Button",text)
	t.set_color("font_hover_color","Button",Color.WHITE)
	t.set_color("font_pressed_color","Button",Color.WHITE)
	t.set_color("font_color","CheckButton",text)
	t.set_color("font_color","OptionButton",text)
	t.set_color("font_color","SpinBox",text)
	t.set_color("font_uneditable_color","LineEdit",muted)
	t.set_stylebox("normal","Button",box("#17212b",9,"#26333f",10))
	t.set_stylebox("hover","Button",box("#202e3a",9,"#3b5368",10))
	t.set_stylebox("pressed","Button",box("#246fA8",9,"#62b5f2",10))
	t.set_stylebox("focus","Button",box("#00000000",9,"#62b5f2",10))
	t.set_stylebox("normal","OptionButton",box("#17212b",9,"#26333f",10))
	t.set_stylebox("hover","OptionButton",box("#202e3a",9,"#3b5368",10))
	t.set_stylebox("normal","CheckButton",box("#17212b",9,"#26333f",9))
	t.set_stylebox("hover","CheckButton",box("#202e3a",9,"#3b5368",9))
	t.set_stylebox("panel","PanelContainer",box("#101820",12,"#22303b",10))
	t.set_stylebox("normal","LineEdit",box("#0c131a",8,"#263541",8))
	t.set_stylebox("normal","ItemList",box("#0c131a",10,"#202d38",8))
	t.set_color("font_selected_color","TabBar",Color("#8dccf7"))
	t.set_color("font_unselected_color","TabBar",Color("#9ba8b5"))
	t.set_stylebox("tab_selected","TabBar",box("#19354a",9,"#28516d",10))
	t.set_stylebox("tab_unselected","TabBar",box("#0c141b",9,"",10))
	t.set_stylebox("tab_hovered","TabBar",box("#15232e",9,"",10))
	t.set_color("font_color","TooltipLabel",text)
	t.set_constant("h_separation","HBoxContainer",7)
	t.set_constant("v_separation","VBoxContainer",7)
	return t
