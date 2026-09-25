extends RefCounted
static func build() -> Theme:
	var t:=Theme.new()
	t.default_font_size=14
	var panel:=StyleBoxFlat.new();panel.bg_color=Color("#171c22");panel.corner_radius_top_left=8;panel.corner_radius_top_right=8;panel.corner_radius_bottom_left=8;panel.corner_radius_bottom_right=8;panel.border_width_left=1;panel.border_width_top=1;panel.border_width_right=1;panel.border_width_bottom=1;panel.border_color=Color("#2a323d")
	t.set_stylebox("panel","PanelContainer",panel)
	var btn:=StyleBoxFlat.new();btn.bg_color=Color("#202731");btn.corner_radius_top_left=6;btn.corner_radius_top_right=6;btn.corner_radius_bottom_left=6;btn.corner_radius_bottom_right=6;btn.content_margin_left=10;btn.content_margin_right=10;btn.content_margin_top=7;btn.content_margin_bottom=7
	t.set_stylebox("normal","Button",btn)
	var hover: StyleBoxFlat = btn.duplicate() as StyleBoxFlat
	hover.bg_color=Color("#2b3542")
	t.set_stylebox("hover","Button",hover)
	var pressed: StyleBoxFlat = btn.duplicate() as StyleBoxFlat
	pressed.bg_color=Color("#1677e8")
	t.set_stylebox("pressed","Button",pressed)
	t.set_color("font_color","Button",Color("#e7edf5"));t.set_color("font_hover_color","Button",Color.WHITE)
	t.set_color("font_color","Label",Color("#d9e1eb"))
	t.set_color("font_color","CheckButton",Color("#d9e1eb"))
	t.set_color("font_selected_color","TabBar",Color("#5aa9ff"));t.set_color("font_unselected_color","TabBar",Color("#aeb8c5"))
	t.set_constant("h_separation","HBoxContainer",8);t.set_constant("v_separation","VBoxContainer",7)
	return t
