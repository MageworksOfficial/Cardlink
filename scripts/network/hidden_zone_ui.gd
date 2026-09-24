extends Node
## Reuses the existing image inspection window without creating hidden card instances.
var service: Node
var prompt: ConfirmationDialog
var notice: AcceptDialog
var auto_approve: CheckBox
func _ready() -> void:
	prompt = ConfirmationDialog.new()
	prompt.exclusive = false
	prompt.title = "Hidden-zone inspection request"
	prompt.ok_button_text = "Allow"
	prompt.cancel_button_text = "Deny"
	prompt.confirmed.connect(func() -> void: service.respond(true))
	prompt.canceled.connect(func() -> void: service.respond(false))
	add_child(prompt)
	notice = AcceptDialog.new()
	notice.exclusive = false
	add_child(notice)
func attach() -> void:
	var controls: Node = service.controller().manager.controls
	var rows: Node = controls.panels.Hand.get_child(0).get_child(0).get_child(0)
	controls.button(rows,"Reveal Hand (current cards)",func() -> void: service.reveal_hand(true))
	controls.button(rows,"Hide Hand Again",func() -> void: service.reveal_hand(false))
	auto_approve = CheckBox.new()
	auto_approve.text = "Auto-approve hidden-zone inspection requests"
	auto_approve.button_pressed = service.auto_approve
	auto_approve.toggled.connect(service.set_auto_approve)
	rows.add_child(auto_approve)
	controls.button(rows,"Cancel Inspection Request",service.close_outgoing)
func ask(caption: String) -> void:
	prompt.dialog_text = caption
	prompt.popup_centered()
func tell(caption: String) -> void:
	notice.dialog_text = caption
	notice.popup_centered()
func show_rows() -> void:
	var c: Node = service.controller()
	if service.outgoing == null or service.outgoing.state != "approved": return
	if not c.remote_inspection:
		c.close_inspection()
		c.remote_inspection = true
		c.inspection_reveal_button.hide()
		c.contents_query.text = ""
		c.contents.title = "Opponent " + service.outgoing.zone + " · temporary access · close to finish"
		c.contents.popup_centered_clamped(Vector2i(680,570),0.9)
	refresh()
func refresh() -> void:
	var c: Node = service.controller()
	c.contents_list.clear()
	c.inspection_preview.texture = null
	if service.outgoing == null: return
	for i: int in service.outgoing.rows.size():
		var row: Dictionary = service.outgoing.rows[i]
		if not c.contents_query.text.is_empty() and not row.name.to_lower().contains(c.contents_query.text.to_lower()): continue
		c.contents_list.add_item("%d. %s" % [i+1,row.name],texture(row.art))
		c.contents_list.set_item_metadata(c.contents_list.item_count-1,row.id)
func texture(hash: String) -> Texture2D:
	var path: String = service.router.serializer.resolve_art(hash)
	if path.is_empty(): return null
	var image := Image.load_from_file(path)
	return null if image == null else ImageTexture.create_from_image(image)
func selected() -> String:
	var list: ItemList = service.controller().contents_list
	var indices: PackedInt32Array = list.get_selected_items()
	return "" if indices.is_empty() else str(list.get_item_metadata(indices[0]))
func preview(index: int) -> void:
	var c: Node = service.controller()
	if service.outgoing == null or index < 0 or index >= c.contents_list.item_count: return
	var id: String = str(c.contents_list.get_item_metadata(index))
	for row: Dictionary in service.outgoing.rows:
		if row.id == id: c.inspection_preview.texture = texture(row.art)
func clear() -> void:
	var c: Node = service.controller()
	c.remote_inspection = false
	c.inspection_reveal_button.show()
	c.contents_list.clear()
	c.inspection_preview.texture = null
	c.contents.hide()
	c.hide_preview()
