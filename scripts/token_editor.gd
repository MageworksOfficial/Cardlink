extends Window
var manager: Node
var editing_id: String = ""
var spawn_position: Vector2
var art_path: String = ""
var caption: LineEdit
var power: LineEdit
var toughness: LineEdit
var owner_picker: OptionButton
var controller: OptionButton
var art_label: Label
var message: Label
var art_picker: FileDialog
var duplicate_button: Button
func _ready() -> void:
	visible = false
	size = Vector2i(420, 470)
	close_requested.connect(hide)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	caption = field(rows, "Token name")
	power = field(rows, "Power (optional, e.g. 2 or *)")
	toughness = field(rows, "Toughness (optional)")
	manager.controls.label(rows, "Owner")
	owner_picker = manager.controls.players(rows)
	manager.controls.label(rows, "Controller")
	controller = manager.controls.players(rows)
	art_label = manager.controls.label(rows, "No art")
	manager.controls.button(rows, "Change Art", func() -> void: art_picker.popup_centered_ratio(0.7))
	manager.controls.button(rows, "Use selected card art", func() -> void:
		var card: Control = manager.selected_card
		if card != null and manager.match_controller.visibility.can_present(card.state, "local"):
			art_path = card.state.image_path
			art_label.text = "Art selected"
			art_label.tooltip_text = art_path)
	manager.controls.button(rows, "Clear Art", func() -> void:
		art_path = ""
		art_label.text = "No art")
	manager.controls.button(rows, "Save Token", save_token)
	duplicate_button = manager.controls.button(rows, "Duplicate Token", func() -> void:
		var card: Control = manager.match_controller.card_by_id(editing_id)
		if card != null:
			manager.match_controller.library_actions.duplicate_token(card)
			hide())
	message = manager.controls.label(rows, "")
	manager.controls.button(rows, "Close", hide)
	art_picker = FileDialog.new()
	art_picker.access = FileDialog.ACCESS_FILESYSTEM
	art_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	art_picker.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	art_picker.file_selected.connect(func(path: String) -> void:
		var result: Dictionary = preload("res://scripts/token_service.gd").import_art(path, manager.token_art_directory)
		if result.has("error"):
			message.text = result.error
		else:
			art_path = result.path
			art_label.text = "Art selected"
			art_label.tooltip_text = art_path)
	add_child(art_picker)
func field(rows: Node, placeholder: String) -> LineEdit:
	manager.controls.label(rows, placeholder)
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.max_length = 120
	rows.add_child(input)
	return input
func open_token(card: Control = null, point: Vector2 = Vector2(400, 250)) -> void:
	editing_id = "" if card == null else card.state.match_instance_id
	spawn_position = point
	title = "Create Token" if card == null else "Token Properties"
	caption.text = "" if card == null else card.state.display_name
	power.text = "" if card == null else str(card.state.custom_metadata.get("power", ""))
	toughness.text = "" if card == null else str(card.state.custom_metadata.get("toughness", ""))
	art_path = "" if card == null else card.state.image_path
	art_label.text = "No art" if art_path.is_empty() else "Art selected"
	art_label.tooltip_text = art_path
	owner_picker.select(0 if card == null or card.state.owner_player_id == "local" else 1)
	owner_picker.disabled = card != null
	controller.select(0 if card == null or card.state.controller_player_id == "local" else 1)
	duplicate_button.visible = card != null
	message.text = ""
	popup_centered()
func save_token() -> void:
	if manager.undo != null:
		manager.undo.begin("Token properties")
		manager.undo.finish.call_deferred()
	var card: Control = manager.match_controller.card_by_id(editing_id)
	if not editing_id.is_empty() and card == null:
		message.text = "This token is no longer on the table."
		return
	if card == null:
		var result: Dictionary = manager.create_token(caption.text, str(owner_picker.get_selected_metadata()), str(controller.get_selected_metadata()), art_path, power.text, toughness.text)
		if result.has("error"):
			message.text = result.error
			return
		card = result.card
		card.position = spawn_position
		card.state.position = spawn_position
	else:
		card.state.display_name = caption.text.strip_edges() if not caption.text.strip_edges().is_empty() else "Token"
		card.state.custom_metadata["power"] = power.text.strip_edges()
		card.state.custom_metadata["toughness"] = toughness.text.strip_edges()
		card.state.controller_player_id = str(controller.get_selected_metadata())
		card.state.image_path = art_path
		manager.apply_card_art(card)
	manager.match_controller.refresh()
	hide()

