extends Window
var bindings: RefCounted
var rows: VBoxContainer
var labels: Dictionary = {}
var pending: String = ""
var pending_key: int = 0
var conflict_dialog: ConfirmationDialog
var notice: Label
func _ready() -> void:
	title = "Key Bindings"
	visible = false
	size = Vector2i(640,560)
	close_requested.connect(close)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	notice = Label.new()
	notice.text = "Choose a binding, then press a key. Escape cancels capture."
	column.add_child(notice)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for id: String in bindings.ACTIONS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := Label.new()
		label.text = bindings.ACTIONS[id][0]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		labels[id] = button(row,bindings.caption(id),func() -> void: capture_key(id))
		labels[id].custom_minimum_size.x = 115
		button(row,"Clear",func() -> void: bindings.assign(id,0))
		button(row,"Default",func() -> void: propose(id,bindings.ACTIONS[id][1]))
	button(column,"Reset All to Defaults",bindings.reset_all)
	button(column,"Close",close)
	conflict_dialog = ConfirmationDialog.new()
	conflict_dialog.ok_button_text = "Replace Existing"
	conflict_dialog.confirmed.connect(func() -> void:
		bindings.assign(pending,pending_key,true)
		pending = ""
		refresh())
	conflict_dialog.canceled.connect(func() -> void: pending = ""; refresh())
	add_child(conflict_dialog)
	window_input.connect(handle_key)
	bindings.changed.connect(refresh)
func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.pressed.connect(action)
	parent.add_child(item)
	return item
func capture_key(id: String) -> void:
	pending = id
	notice.text = "Press a key… " + str(bindings.ACTIONS[id][0])
func handle_key(event: InputEvent) -> void:
	if pending.is_empty() or conflict_dialog.visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE: pending = ""; refresh(); return
	if event.keycode in [KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META]: return
	propose(pending,event.get_keycode_with_modifiers())
	set_input_as_handled()
func propose(id: String, code: int) -> void:
	pending = id
	pending_key = code
	var other: String = bindings.conflict(id,code)
	if not other.is_empty():
		conflict_dialog.dialog_text = "This key is already assigned to:\n"+str(bindings.ACTIONS[other][0])
		conflict_dialog.popup_centered()
	else:
		bindings.assign(id,code)
		pending = ""
		refresh()
func refresh() -> void:
	for id: String in labels: labels[id].text = bindings.caption(id)
	notice.text = "Choose a binding, then press a key. Escape cancels capture."
func close() -> void:
	pending = ""
	conflict_dialog.hide()
	hide()
