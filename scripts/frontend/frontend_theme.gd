extends RefCounted
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("15334a") if state == "normal" else Color("204b66")
		if state == "focus": style.bg_color = Color(0,0,0,0)
		style.border_color = Color("7cbcd7") if state == "focus" else Color("376580")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		theme.set_stylebox(state,"Button",style)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.035,0.075,0.115,0.94)
	panel.border_color = Color("376580")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	theme.set_stylebox("panel","AcceptDialog",panel)
	theme.set_stylebox("embedded_border","Window",panel)
	return theme

static func skin_window(window: Window) -> void:
	if window.has_meta("cardlink_skin"): return
	window.set_meta("cardlink_skin",true)
	var background := Panel.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -100
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.075,0.115,0.96)
	style.border_color = Color("376580")
	style.set_border_width_all(1)
	background.add_theme_stylebox_override("panel",style)
	window.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
