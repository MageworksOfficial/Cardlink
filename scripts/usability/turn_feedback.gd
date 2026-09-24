extends Node
## A screen-fixed, input-transparent cue. Viewed seat and active turn can differ.
var manager: Node
var label: Label
var fade: Tween
func _ready() -> void:
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color",Color("8beaff"))
	label.add_theme_font_size_override("font_size",24)
	label.add_theme_color_override("font_shadow_color",Color("06111d"))
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	label.z_index = 210
	manager.get_parent().add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -280
	label.offset_right = 280
	label.offset_top = 105
	label.offset_bottom = 170
	label.hide()
func show_turn(viewed: String) -> void:
	if not manager.match_controller.playtest.local_playtest(): return
	if fade != null: fade.kill()
	var active: String = manager.match_controller.model.active_player
	label.text = "PLAYER %d TURN" % (1 if active == "local" else 2)
	if viewed != active: label.text += "\nViewing Player %d side" % (1 if viewed == "local" else 2)
	label.modulate.a = 1
	label.show()
	fade = create_tween()
	fade.tween_interval(1.1)
	if not bool(manager.table_preferences.value("reduce_motion",false)): fade.tween_property(label,"modulate:a",0.0,0.25)
	fade.tween_callback(label.hide)
