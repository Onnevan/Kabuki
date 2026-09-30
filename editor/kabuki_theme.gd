extends RefCounted
static func box(color:String, radius:int=6, border:String="") -> StyleBoxFlat:
	var b:=StyleBoxFlat.new(); b.bg_color=Color(color)
	b.corner_radius_top_left=radius;b.corner_radius_top_right=radius;b.corner_radius_bottom_left=radius;b.corner_radius_bottom_right=radius
	b.content_margin_left=10;b.content_margin_right=10;b.content_margin_top=7;b.content_margin_bottom=7
	if border!="":
		b.border_width_left=1;b.border_width_top=1;b.border_width_right=1;b.border_width_bottom=1;b.border_color=Color(border)
	return b
static func build() -> Theme:
	var t:=Theme.new();t.default_font_size=13
	t.set_color("font_color","Label",Color("#dce5ef"));t.set_color("font_color","Button",Color("#dce5ef"));t.set_color("font_color","CheckButton",Color("#dce5ef"))
	t.set_stylebox("normal","Button",box("#1b2530",7,"#263442"));t.set_stylebox("hover","Button",box("#253545",7,"#38506a"));t.set_stylebox("pressed","Button",box("#236da8",7,"#56a9e8"))
	t.set_stylebox("normal","CheckButton",box("#202a36",6,"#2b3744"));t.set_stylebox("hover","CheckButton",box("#2a3949",6,"#3c4d60"))
	t.set_stylebox("panel","PanelContainer",box("#121a22",9,"#22303d"))
	t.set_stylebox("normal","LineEdit",box("#0e151c",7,"#263541"));t.set_stylebox("normal","ItemList",box("#0f161d",7,"#22303d"))
	t.set_color("font_selected_color","TabBar",Color("#73bdf4"));t.set_color("font_unselected_color","TabBar",Color("#b7c1cd"))
	t.set_stylebox("tab_selected","TabBar",box("#18334a",6));t.set_stylebox("tab_unselected","TabBar",box("#0d141b",6))
	t.set_constant("h_separation","HBoxContainer",8);t.set_constant("v_separation","VBoxContainer",7)
	return t
