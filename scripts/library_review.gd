extends Window
## A temporary review workspace; ordering changes commit once, or cancel untouched.
var controller: Node
var player_id: String
var original: Array[String] = []
var top: Array[String] = []
var bottom: Array[String] = []
var top_list: ItemList
var bottom_list: ItemList
var preview: TextureRect
var status: Label
var editing: bool = true
var surveil: bool = false
var destination_button: Button
var destination_caption: Label
var edit_controls: Array[Control] = []
var confirm_button: Button
func button(parent: Node, caption: String, callback: Callable, edit_only: bool = false) -> Button:
	var item := Button.new()
	item.text = caption
	item.pressed.connect(callback)
	parent.add_child(item)
	if edit_only:
		edit_controls.append(item)
	return item
func _ready() -> void:
	visible = false
	size = Vector2i(750, 460)
	close_requested.connect(cancel)
	visibility_changed.connect(func() -> void:
		if not visible:
			clear_private())
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rows)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(lists)
	var caption := Label.new()
	caption.text = "Keep on top — first row is the next draw"
	lists.add_child(caption)
	top_list = ItemList.new()
	top_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_child(top_list)
	top_list.item_selected.connect(func(index: int) -> void: inspect(top[index]))
	var actions := HBoxContainer.new()
	lists.add_child(actions)
	button(actions, "Up", reorder.bind(-1), true)
	button(actions, "Down", reorder.bind(1), true)
	destination_button=button(actions, "Move to bottom", to_bottom, true)
	caption = Label.new()
	destination_caption=caption
	caption.text = "Bottom — last row becomes bottommost"
	lists.add_child(caption)
	edit_controls.append(caption)
	bottom_list = ItemList.new()
	bottom_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_child(bottom_list)
	edit_controls.append(bottom_list)
	bottom_list.item_selected.connect(func(index: int) -> void: inspect(bottom[index]))
	var bottom_actions := HBoxContainer.new()
	lists.add_child(bottom_actions)
	button(bottom_actions, "Bottom up", reorder_bottom.bind(-1), true)
	button(bottom_actions, "Bottom down", reorder_bottom.bind(1), true)
	button(bottom_actions, "Return to top", to_top, true)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(210, 294)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(preview)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(status)
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	confirm_button = button(footer, "Confirm order", confirm_review)
	button(footer, "Cancel / Close", cancel)
func open_review(player: String, count: int, editable: bool = true, to_graveyard: bool = false) -> void:
	if controller.manager.undo != null: controller.manager.undo.invalidate("Scry / reveal cannot be undone.")
	if controller.online() and player != "local":
		controller.manager.controls.status.text = "Opponent hidden-zone access is reserved for Milestone 6C."
		return
	controller.close_inspection()
	controller.manager.controls.close_panels()
	clear_private()
	player_id = player
	editing = editable
	surveil=to_graveyard
	destination_button.text="Move to graveyard" if surveil else "Move to bottom"
	destination_caption.text="To graveyard" if surveil else "Bottom — last row becomes bottommost"
	original.assign(controller.model.players[player_id].library.order)
	top.assign(controller.model.players[player_id].library.peek(count))
	for id: String in top:
		var card: Control = controller.card_by_id(id)
		if card != null:
			controller.Knowledge.learn(card.state,"local")
			if not editable: controller.visibility.set_public_reveal(card.state,true)
	controller.refresh()
	title = (("Surveil" if surveil else "Scry") if editable else "Reveal top") + " %d · %s · temporary inspection" % [top.size(), player]
	for item: Control in edit_controls:
		item.visible = editable
	confirm_button.visible = editable
	status.text = "Changes apply only when confirmed. Cancel leaves the library untouched." if editable else "These identities appear only in this window. Close to end inspection."
	refresh_lists()
	popup_centered_clamped(Vector2i(750, 460), 0.9)
	if not top.is_empty():
		top_list.select(0)
		inspect(top[0])
func inspect(id: String) -> void:
	var card: Control = controller.card_by_id(id)
	preview.texture = card.hover_preview.texture if card != null else null
func refresh_lists() -> void:
	top_list.clear()
	bottom_list.clear()
	for ids: Array[String] in [top, bottom]:
		var list: ItemList = top_list if ids == top else bottom_list
		for id: String in ids:
			var card: Control = controller.card_by_id(id)
			list.add_item(card.state.display_name if card != null else "Missing card")
func reorder(delta: int) -> void:
	if not editing or top_list.get_selected_items().is_empty():
		return
	var index: int = top_list.get_selected_items()[0]
	var target: int = clampi(index + delta, 0, top.size() - 1)
	var id: String = top.pop_at(index)
	top.insert(target, id)
	refresh_lists()
	top_list.select(target)
func reorder_bottom(delta: int) -> void:
	if not editing or bottom_list.get_selected_items().is_empty():
		return
	var index: int = bottom_list.get_selected_items()[0]
	var target: int = clampi(index + delta, 0, bottom.size() - 1)
	var id: String = bottom.pop_at(index)
	bottom.insert(target, id)
	refresh_lists()
	bottom_list.select(target)
func to_bottom() -> void:
	if editing and not top_list.get_selected_items().is_empty():
		bottom.append(top.pop_at(top_list.get_selected_items()[0]))
		refresh_lists()
func to_top() -> void:
	if editing and not bottom_list.get_selected_items().is_empty():
		top.append(bottom.pop_at(bottom_list.get_selected_items()[0]))
		refresh_lists()
func confirm_review() -> void:
	if not editing:
		cancel()
		return
	if surveil and not bottom.is_empty():
		var zone: Control=controller.zone_for("graveyard",player_id)
		if zone.capacity>0 and zone.members.size()+bottom.size()>zone.capacity:
			status.text="Graveyard zone is full. No changes applied.";return
	if not controller.model.players[player_id].library.commit_top(original, top, bottom):
		status.text = "Library changed during review. Close and reopen Scry; no changes were applied."
		return
	if surveil:
		for id: String in bottom.duplicate(): controller.move_card(controller.card_by_id(id),"graveyard",true,player_id)
	controller.refresh()
	if surveil: controller.record_event("surveil",controller.model.players[player_id].display_name+" surveilled",{})
	controller.manager.controls.status.text = ("Surveil" if surveil else "Scry")+" order confirmed for " + player_id
	cancel()
func cancel() -> void:
	hide()
	clear_private()
func clear_private() -> void:
	original.clear()
	top.clear()
	bottom.clear()
	if top_list != null:
		top_list.clear()
		bottom_list.clear()
		preview.texture = null
