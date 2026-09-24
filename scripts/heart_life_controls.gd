extends Node
var controller: Node
var hearts: Dictionary = {}
var life_editor: AcceptDialog
var life_input: SpinBox
var editing: String = "local"
func _ready() -> void:
	life_editor = AcceptDialog.new()
	life_editor.title = "Set Life"
	life_editor.dialog_text = ""
	life_input = SpinBox.new()
	life_input.min_value = -1000000
	life_input.max_value = 1000000
	life_editor.add_child(life_input)
	life_editor.confirmed.connect(func() -> void: controller.change_life(editing,int(life_input.value)-controller.model.players[editing].life))
	add_child(life_editor)
	for player: String in ["local", "opponent"]:
		var row := HBoxContainer.new()
		row.name = "HeartLife_"+player
		row.z_index = 190
		controller.manager.get_parent().add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		row.position = Vector2(200,12)
		if player == "local":
			row.anchor_top = 1.0
			row.anchor_bottom = 1.0
			row.offset_left = 12
			row.offset_top = -250
			row.offset_right = 152
			row.offset_bottom = -214
		controller.button(row,"−",func() -> void: controller.change_life(player,-1))
		var heart := Label.new()
		heart.add_theme_font_size_override("font_size",22)
		heart.add_theme_color_override("font_color",Color("ff9baf"))
		row.add_child(heart)
		heart.mouse_filter = Control.MOUSE_FILTER_PASS
		heart.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not controller.manager.layout.edit_mode:
				editing = player
				life_input.value = controller.model.players[player].life
				life_editor.popup_centered(Vector2i(240,120)))
		var dragging: Dictionary = {"active":false,"offset":Vector2.ZERO}
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(func(event: InputEvent) -> void:
			if not controller.manager.layout.edit_mode: return
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				dragging.active = event.pressed
				dragging.offset = event.position
			elif event is InputEventMouseMotion and dragging.active:
				controller.manager.perspective.move_heart(player,controller.manager.organization.snap(row.position+event.position-dragging.offset,row.size,true)))
		controller.button(row,"+",func() -> void: controller.change_life(player,1))
		hearts[player] = heart
	refresh()
func refresh() -> void:
	for player: String in hearts:
		hearts[player].add_theme_color_override("font_color",Color("8beaff") if controller.model.active_player == player else Color("ff9baf"))
		hearts[player].text = "♥ %d" % controller.model.players[player].life
		hearts[player].tooltip_text = controller.model.players[player].display_name + " · Click life to set a value"
		hearts[player].text = ("● " if controller.model.active_player == player else "") + controller.model.players[player].display_name.left(16) + "  " + hearts[player].text
		if controller.playtest.local_playtest(): hearts[player].text = ("P1" if player == "local" else "P2")+(" TURN · " if controller.model.active_player == player else " · ")+hearts[player].text
		hearts[player].get_parent().visible = controller.manager.active
