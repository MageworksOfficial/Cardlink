extends PanelContainer
const HandCard = preload("res://scripts/hand_card.gd")
var controller: Node
var row: Container
var label: Label
func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.106,0.145,0.188,0.5)
	add_theme_stylebox_override("panel", background)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -202
	offset_bottom = -62
	var column := VBoxContainer.new()
	add_child(column)
	label = Label.new()
	column.add_child(label)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(_anchor_input)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)
	row = preload("res://scripts/usability/hand_arrangement.gd").new()
	scroll.add_child(row)
func refresh() -> void:
	for item: Node in row.get_children():
		row.remove_child(item)
		item.queue_free()
	var count: int = 0
	for id: String in controller.model.players[controller.active_hand_player()].hand:
		var card: Control=controller.card_by_id(id)
		if card==null: continue
		if card.state.current_zone != "hand" or card.state.zone_player_id != controller.active_hand_player():
			continue
		count += 1
		var item := HandCard.new()
		item.controller = controller
		item.instance_id = card.state.match_instance_id
		item.publicly_revealed = controller.visibility.stable_visibility(card.state) == "public" and not card.state.face_down
		item.texture = card.card_image.texture if (controller.visibility.can_present(card.state, "local") or controller.playtest.local_playtest()) else preload("res://scripts/battle/deck_back.gd").for_card(card,controller.manager.backs)
		item.custom_minimum_size = Vector2(70, 98)
		item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.tooltip_text = card.state.display_name if (controller.visibility.can_present(card.state, "local") or controller.playtest.local_playtest()) else "Hidden card"
		item.mouse_entered.connect(func() -> void: controller.show_preview(card))
		item.mouse_exited.connect(controller.hide_preview)
		item.gui_input.connect(func(event: InputEvent) -> void:
			if controller.manager.selection!=null and controller.manager.selection.hand_input(card,item,event):
				item.accept_event()
				return
			if event is InputEventMouseButton and event.pressed:
				controller.manager.select_card(card)
				if event.button_index == MOUSE_BUTTON_RIGHT:
					controller.manager.controls.open_card_actions()
					controller.hide_preview())
		row.add_child(item)
	row.update_minimum_size()
	row.queue_sort()
	label.text = ("Player 2 hand: %d · Drag to play" if controller.active_hand_player() == "opponent" else "Your hand: %d · Drag to play · Ctrl-click to select · Right-click for actions") % count
	if controller.playtest.local_playtest(): label.text = controller.model.players[controller.active_hand_player()].display_name+" hand: "+str(count)+" · Drag to play · Ctrl-click to select · Right-click for actions"


var layout_dragging: bool = false
var layout_offset: Vector2
func _anchor_input(event: InputEvent) -> void:
	if controller.hand_window.detached or controller.manager.layout == null or not controller.manager.layout.edit_mode:
		layout_dragging = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		layout_dragging = event.pressed
		layout_offset = event.position
	elif event is InputEventMouseMotion and layout_dragging:
		position = controller.manager.organization.snap(position+event.position-layout_offset,size,true)
