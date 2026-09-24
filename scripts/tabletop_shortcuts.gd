extends Node
var manager: Node
var bindings: RefCounted
var dispatcher: RefCounted
var help_text: Label
var snap_button: Button
var layout_button: Button
var hands_button: Button
var playtest_button: Button
var quick_row: HBoxContainer
var hands_menu: PopupMenu
var help: Window
var mode_notice: AcceptDialog
var pending_online: bool = false
func _ready() -> void:
	var shell: Control = manager.get_parent().app_shell
	bindings = shell.bindings if shell != null else preload("res://scripts/usability/input_bindings.gd").new()
	dispatcher = preload("res://scripts/usability/table_actions.gd").new(manager)
	quick_row = HBoxContainer.new()
	quick_row.name = "QuickControls"
	quick_row.alignment = BoxContainer.ALIGNMENT_END
	quick_row.z_index = 205
	manager.get_parent().add_child(quick_row)
	quick_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	quick_row.offset_left = -625
	quick_row.offset_right = -8
	quick_row.offset_top = 12
	quick_row.offset_bottom = 48
	playtest_button = quick_button("Online [P]",toggle_playtest,"Switch between online opponent and local playtest opponent. Shortcut: P")
	hands_button = quick_button("Hands: Shown [X]",toggle_hands,"Show or hide both hands. Use the arrow for detached hand controls. Shortcut: X")
	quick_button("▾",open_hands,"Show, hide, or detach hand controls. Shortcut: X")
	hands_button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT: open_hands())
	layout_button = quick_button("Layout: Off [L]",toggle_layout,"Move major tabletop zones. Shortcut: L")
	snap_button = quick_button("Snap…",func() -> void: manager.controls.open_panel("Layout"),"Layout snapping and reset options")
	quick_button("Controls",open_help,"Quick mouse and keyboard controls.")
	quick_button("Menu",func() -> void: manager.extras.open_corner(),"Decks, tools, settings, and match options.")
	hands_menu = PopupMenu.new()
	for caption: String in ["Show Hands","Hide Hands","Open Detached Hand Window","Return Hand to Main Window","Choose Playtest Hand / Controls"]: hands_menu.add_item(caption)
	hands_menu.id_pressed.connect(hand_action)
	add_child(hands_menu)
	mode_notice = AcceptDialog.new()
	mode_notice.title = "Keep your current match"
	mode_notice.dialog_text = "Disconnect and finish or leave the shared match using Multiplayer / Network before switching modes. Your current match is preserved. Save it first if you want to return later."
	add_child(mode_notice)
	manager.match_controller.playtest.reset_dialog.confirmed.connect(func() -> void:
		if pending_online:
			pending_online = false
			manager.match_controller.playtest.set_mode("online"))
	manager.match_controller.playtest.reset_dialog.canceled.connect(func() -> void: pending_online = false)
	help = Window.new()
	help.visible = false
	help.title = "Tabletop Controls"
	help.size = Vector2i(570,490)
	help.transient = true
	help.close_requested.connect(help.hide)
	add_child(help)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	help_text = Label.new()
	help_text.text = bindings.help_text()
	help_text.add_theme_font_size_override("font_size",14)
	rows.add_child(help_text)
	bindings.changed.connect(func() -> void: help_text.text = bindings.help_text())
	manager.controls.button(rows,"Close",help.hide)

func _process(_delta: float) -> void:
	quick_row.visible = manager.active
	snap_button.visible = manager.layout.edit_mode
	playtest_button.text = ("Playtest" if manager.match_controller.playtest.local_playtest() else "Online") + " ["+bindings.caption("mode")+"]"
	layout_button.text = "Layout: %s [%s]" % ["On" if manager.layout.edit_mode else "Off",bindings.caption("layout")]
	layout_button.modulate = Color(1,0.85,0.35) if manager.layout.edit_mode else Color.WHITE
	hands_button.text = ("Hands: Hidden" if manager.match_controller.hands_hidden else "Hands: Shown")+" ["+bindings.caption("hands")+"]"
	playtest_button.tooltip_text = "Switch table mode · "+bindings.caption("mode")
	hands_button.tooltip_text = "Show/hide hands · "+bindings.caption("hands")
	layout_button.tooltip_text = "Move zones and UI anchors · "+bindings.caption("layout")
	if not manager.active: help.hide()
func quick_button(caption: String, action: Callable, hint: String) -> Button:
	var item: Button = manager.controls.button(quick_row,caption,action)
	item.focus_mode = Control.FOCUS_NONE
	item.tooltip_text = hint
	return item
func toggle_playtest() -> void:
	var mode: Node = manager.match_controller.playtest
	if mode.network_busy():
		mode_notice.popup_centered()
		return
	var next: String = "online" if mode.local_playtest() else "local_playtest"
	if mode.set_mode(next):
		manager.controls.status.text = "Playtest Mode Enabled" if next == "local_playtest" else "Online Mode Selected"
	elif next == "online":
		pending_online = true
		mode.reset_dialog.dialog_text = "Switch to Online with a new local table? Current table copies, life and history will be cleared. Save your match first to keep it. Saved decks, collection and layout remain available."
		mode.reset_dialog.popup_centered()
func toggle_layout() -> void:
	manager.layout.set_edit_mode(not manager.layout.edit_mode)
	manager.controls.status.text = "Layout Mode Enabled" if manager.layout.edit_mode else "Layout Mode Disabled"
func toggle_hands() -> void:
	var c: Node = manager.match_controller
	c.hands_hidden = not c.hands_hidden
	c.hand.visible = manager.active and not c.hands_hidden and c.hand_open
	c.opponent_hand.visible = manager.active and not c.hands_hidden
	c.hide_preview()
	if c.hand_window != null: c.hand_window.refresh()
	hands_button.text = "Hands: Hidden [X]" if c.hands_hidden else "Hands: Shown [X]"
	manager.controls.status.text = "Hands Hidden" if c.hands_hidden else "Hands Shown"
func open_hands() -> void:
	manager.controls.close_panels()
	hands_menu.position = Vector2i(hands_button.global_position + Vector2(0,hands_button.size.y))
	hands_menu.popup()
func hand_action(id: int) -> void:
	var c: Node = manager.match_controller
	match id:
		0:
			if c.hands_hidden: toggle_hands()
		1:
			if not c.hands_hidden: toggle_hands()
		2:
			if c.hands_hidden: toggle_hands()
			c.hand_window.open_hand()
		3: c.hand_window.restore_hand()
		4: manager.controls.open_panel("Hand")
func open_help() -> void:
	manager.controls.close_panels()
	manager.extras.close_all()
	help.popup_centered()
func has_window(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is Window and child.name == "PrivateHandWindow": continue
		if child is Window and child.visible: return true
		if has_window(child): return true
	return false
func blocked() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return not manager.active or focus is LineEdit or focus is TextEdit or has_window(manager.get_parent().app_shell if manager.get_parent().app_shell != null else manager.get_parent())
func _unhandled_key_input(event: InputEvent) -> void: handle_key(event)
func handle_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or blocked(): return
	var action: String = bindings.action_for(event)
	if action.is_empty() or (event.echo and not action.begins_with("pan_")): return
	dispatcher.execute(action,event)
	get_viewport().set_input_as_handled()
func discard() -> void:
	var card: Control = manager.selected_card
	if not is_instance_valid(card) or card.state.current_zone != "hand" or card.state.zone_player_id != manager.match_controller.active_hand_player():
		manager.controls.status.text = "Select a card in your hand to discard ["+bindings.caption("discard")+"]."
		return
	var id: String = card.state.match_instance_id
	var c: Node = manager.match_controller
	if c.move_card(card,"graveyard",true,card.state.owner_player_id):
		c.record_event("discard",c.model.players.local.display_name + " discarded a hand card",{"instance_id":id})
