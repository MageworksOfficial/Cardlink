extends Node
signal mode_changed(value: String)
var controller: Node
var mode: String = "online"
var hand_player: String = "local"
var mode_picker: OptionButton
var player_picker: OptionButton
var reset_dialog: ConfirmationDialog
func local_playtest() -> bool: return mode == "local_playtest"
func _ready() -> void:
	var rows: Node = controller.manager.controls.panels.Hand.get_child(0).get_child(0).get_child(0)
	mode_picker = OptionButton.new()
	mode_picker.add_item("Online Opponent")
	mode_picker.add_item("Local Playtest Opponent")
	mode_picker.item_selected.connect(func(index: int) -> void: set_mode("local_playtest" if index == 1 else "online"))
	rows.add_child(mode_picker)
	rows.move_child(mode_picker,0)
	player_picker = OptionButton.new()
	player_picker.add_item("Control your hand / library")
	player_picker.add_item("Control playtest opponent's hand / library")
	player_picker.item_selected.connect(func(index: int) -> void:
		hand_player = "opponent" if index == 1 and local_playtest() else "local"
		controller.manager.perspective.switch_to(hand_player))
	rows.add_child(player_picker)
	controller.button(rows,"Open Hand Window",func() -> void: controller.hand_window.open_hand())
	controller.button(rows,"Restore Hand to Main Window",func() -> void: controller.hand_window.restore_hand())
	controller.button(rows,"New Local Table…",func() -> void:
		if network_busy():
			controller.manager.controls.status.text = "Leave the online match before replacing local match copies."
			return
		reset_dialog.popup_centered())
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.dialog_text = "Clear this table's card copies, counters, life and history? Saved decks, card collection, settings and layout stay available."
	reset_dialog.confirmed.connect(new_table)
	add_child(reset_dialog)
	refresh()
func network_busy() -> bool:
	var panel: Node = controller.manager.get_parent().get_node_or_null("Network")
	if panel != null and (not panel.network.available() or panel.rooms.active or panel.rooms.busy): return true
	var r: Node = controller.public_sync
	return r != null and (r.enabled or not r.network.available() or not r.recovery.context.is_empty() or r.transactions.has_unfinished() or r.card_sync.pending)
func set_mode(value: String) -> bool:
	if value == mode: return true
	if network_busy():
		controller.manager.controls.status.text = "Leave the online match before changing opponent mode. Your match is preserved."
		refresh()
		return false
	if value == "online":
		for card: Control in controller.manager.cards:
			if card.state.owner_player_id == "opponent" or card.state.zone_player_id == "opponent":
				controller.manager.controls.status.text = "Use New Local Table (with confirmation) before bringing a two-deck playtest online."
				refresh()
				return false
	mode = value
	hand_player = "local"
	if controller.manager.perspective != null: controller.manager.perspective.switch_to("local",false)
	controller.remote_hand_count = -1
	controller.remote_library_count = -1
	controller.remote_library_knowledge.clear()
	controller.close_inspection()
	controller.review.cancel()
	refresh()
	controller.refresh()
	return true
func refresh() -> void:
	mode_changed.emit(mode)
	mode_picker.select(1 if local_playtest() else 0)
	player_picker.visible = local_playtest()
	player_picker.select(1 if hand_player == "opponent" else 0)
func new_table() -> void:
	if network_busy(): return
	controller.close_inspection()
	controller.review.cancel()
	for card: Control in controller.manager.cards.duplicate(): controller.remove_card(card)
	controller.model = preload("res://scripts/match_state.gd").new()
	if controller.manager.perspective != null: controller.manager.perspective.switch_to("local",false)
	controller.manager.extras.restore_counters([])
	controller.manager.extras.refresh_history()
	controller.remote_hand_count = -1
	controller.remote_library_count = -1
	controller.remote_library_knowledge.clear()
	controller.refresh()
