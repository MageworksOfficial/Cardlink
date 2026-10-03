extends PanelContainer
signal archive_requested
signal import_requested
var custom_import_button: Button
var online_search_button: Button
signal back_requested
signal play_requested(deck: Dictionary, leaders_out: bool)
const Storage = preload("res://scripts/deck_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
var storage = Storage.new()
var loader = Loader.new()
var deck: Dictionary = Storage.new_deck()
var saved_path: String = ""
var records: Array[Dictionary] = []
var saved: Array[Dictionary] = []
var deck_picker: OptionButton
var name_input: LineEdit
var format_input: LineEdit
var query: LineEdit
var catalog: ItemList
var entries: ItemList
var quantity: SpinBox
var leader: CheckBox
var leaders_out: CheckBox
var count: Label
var status: Label
var preview_id: String = ""
var preview_face: int = 0
var face_button: Button
var preview: TextureRect
var delete_dialog: ConfirmationDialog
var discard_dialog: ConfirmationDialog
var pending: Callable
var dirty: bool = false
var standalone: bool = false
var back_picker: Window
var updating: bool = false
var clean_deck: Dictionary = deck.duplicate(true)
var clean_path: String = ""
func button(parent: Node, caption: String, callback: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.pressed.connect(callback)
	parent.add_child(control)
	return control
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17202c")
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	add_child(rows)
	var optional := GridContainer.new()
	optional.columns = 3
	rows.add_child(optional)
	var title := Label.new(); title.text="DECK BUILDER"; optional.add_child(title)
	custom_import_button = button(optional,"+ Import Custom Card",func() -> void: import_requested.emit())
	custom_import_button.tooltip_text = "Import a card image from your computer."
	online_search_button = button(optional,"Online Card Search",func() -> void: preload("res://scripts/integrations/integration_hub.gd").open(self,0))
	online_search_button.tooltip_text = "Search an optional online card provider."
	button(optional,"Import ZIP Deck",func() -> void: archive_requested.emit()).tooltip_text = "Create a deck from a folder/archive of card images."
	button(optional,"Import Decklist",func() -> void: preload("res://scripts/integrations/integration_hub.gd").open(self,1)).tooltip_text = "Build a deck from a pasted card list."
	back_picker = preload("res://scripts/battle/deck_back_picker.gd").new()
	add_child(back_picker)
	back_picker.chosen.connect(func(value: Dictionary) -> void: deck["deck_back"]=value;dirty=true;status.text="Deck back selected. Save the deck to keep it.")
	button(optional,"Deck Back…",func() -> void: back_picker.open(deck.get("deck_back",{})))
	var back_help := Label.new()
	back_help.text = "Deck Back sets hidden appearance for the whole deck. Next Face previews alternate card faces."
	back_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(back_help)
	var top := HBoxContainer.new()
	rows.add_child(top)
	button(top, "Back to Title" if standalone else "Tabletop", func() -> void: guard(func() -> void: back_requested.emit()))
	button(top, "New deck", func() -> void: guard(new_deck))
	deck_picker = OptionButton.new()
	deck_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(deck_picker)
	button(top,"☆ Favorite",toggle_favorite)
	button(top, "Load", func() -> void: guard(load_selected))
	button(top, "Refresh", refresh_saved)
	button(top, "Delete…", request_delete)
	var details := HBoxContainer.new()
	rows.add_child(details)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Deck name (edit to rename, then Save)"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(name_input)
	format_input = LineEdit.new()
	format_input.placeholder_text = "Format ID"
	format_input.custom_minimum_size.x = 180
	details.add_child(format_input)
	button(details, "Save / Rename", save_current)
	button(details, "Duplicate", duplicate_current)
	name_input.text_changed.connect(func(_text: String) -> void: dirty = true)
	format_input.text_changed.connect(func(_text: String) -> void: dirty = true)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	query = LineEdit.new()
	query.placeholder_text = "Search Card Library"
	query.text_changed.connect(func(_text: String) -> void: refresh_catalog())
	var available_label := Label.new()
	available_label.text = "AVAILABLE CARDS"
	left.add_child(available_label)
	left.add_child(query)
	catalog = ItemList.new()
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.custom_minimum_size.x = 240
	left.add_child(catalog)
	catalog.item_selected.connect(func(index: int) -> void: show_preview(str(catalog.get_item_metadata(index))))
	catalog.item_activated.connect(func(_index: int) -> void: add_selected())
	button(left, "Add selected card", add_selected)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var current_label := Label.new()
	current_label.text = "CURRENT DECK"
	right.add_child(current_label)
	count = Label.new()
	right.add_child(count)
	entries = ItemList.new()
	entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries.custom_minimum_size.x = 260
	right.add_child(entries)
	entries.item_selected.connect(select_entry)
	var edit := HBoxContainer.new()
	right.add_child(edit)
	quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 1000
	edit.add_child(quantity)
	quantity.value_changed.connect(func(value: float) -> void:
		if not updating and entries.get_selected_items().size() > 0:
			set_quantity(entries.get_selected_items()[0], int(value)))
	leader = CheckBox.new()
	leader.text = "Leader"
	edit.add_child(leader)
	leader.toggled.connect(func(value: bool) -> void:
		if not updating and entries.get_selected_items().size() > 0:
			set_leader(entries.get_selected_items()[0], value))
	button(edit, "Remove", remove_selected)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(200, 280)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var face_column := VBoxContainer.new()
	columns.add_child(face_column)
	face_column.add_child(preview)
	face_button = button(face_column,"Next Face",func() -> void: show_face(preview_face+1))
	var play := HBoxContainer.new()
	rows.add_child(play)
	play.visible = not standalone
	leaders_out = CheckBox.new()
	leaders_out.text = "Start leaders outside library (one copy of each)"
	leaders_out.button_pressed = true
	play.add_child(leaders_out)
	button(play, "Save & play deck", func() -> void:
		if save_current():
			play_requested.emit(deck.duplicate(true), leaders_out.button_pressed))
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(status)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete saved deck?"
	add_child(delete_dialog)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.dialog_text = "Discard unsaved deck changes?"
	add_child(discard_dialog)
	discard_dialog.confirmed.connect(func() -> void:
		deck = clean_deck.duplicate(true)
		saved_path = clean_path
		sync_fields()
		dirty = false
		pending.call())
	sync_fields()
	preload("res://scripts/collection_events.gd").shared.collection_changed.connect(collection_updated)
	hide()
func guard(action: Callable) -> void:
	if dirty:
		pending = action
		discard_dialog.popup_centered()
	else:
		action.call()
func open_builder() -> void:
	records = loader.load_records()
	refresh_catalog()
	refresh_saved()
	refresh_entries()
	show()
func new_deck() -> void:
	deck = Storage.new_deck()
	saved_path = ""
	clean_deck = deck.duplicate(true)
	clean_path = ""
	dirty = false
	sync_fields()
func sync_fields() -> void:
	name_input.text = str(deck.deck_name)
	format_input.text = str(deck.format_id)
	refresh_entries()
func record_for(id: String) -> Dictionary:
	var found: Dictionary = {}
	for record: Dictionary in records:
		if str(record.metadata.get("card_id", "")) == id:
			if not found.is_empty():
				return {}
			found = record
	return found
func show_preview(id: String) -> void:
	preview_id = id
	show_face(0)
func refresh_catalog() -> void:
	catalog.clear()
	for record: Dictionary in Loader.filtered(records, query.text, "", false):
		var id: String = str(record.metadata.get("card_id", ""))
		catalog.add_item(str(record.name) + (" · %d Faces" % preload("res://scripts/card_faces.gd").list(record.metadata).size() if preload("res://scripts/card_faces.gd").list(record.metadata).size()>1 else "") + (" [unavailable]" if record_for(id).is_empty() or record.thumbnail == null else ""))
		catalog.set_item_metadata(catalog.item_count - 1, id)
func add_selected() -> void:
	if catalog.get_selected_items().is_empty():
		return
	var id: String = str(catalog.get_item_metadata(catalog.get_selected_items()[0]))
	if record_for(id).is_empty() or record_for(id).get("thumbnail") == null:
		status.text = "This card has a missing image or ambiguous/missing definition ID."
		return
	add_card(id)
func add_card(id: String) -> void:
	for i: int in deck.cards.size():
		if deck.cards[i].card_id == id:
			set_quantity(i, int(deck.cards[i].quantity) + 1)
			return
	deck.cards.append({"card_id": id, "quantity": 1})
	dirty = true
	refresh_entries(deck.cards.size() - 1)
func set_quantity(index: int, value: int) -> void:
	deck.cards[index].quantity = clampi(value, 1, 1000)
	dirty = true
	refresh_entries(index)
func set_leader(index: int, value: bool) -> void:
	var id: String = deck.cards[index].card_id
	deck.leaders.erase(id)
	if value:
		deck.leaders.append(id)
	dirty = true
	refresh_entries(index)
func remove_selected() -> void:
	if entries.get_selected_items().is_empty():
		return
	var index: int = entries.get_selected_items()[0]
	deck.leaders.erase(deck.cards[index].card_id)
	deck.cards.remove_at(index)
	dirty = true
	refresh_entries()
func refresh_entries(selected_index: int = -1) -> void:
	entries.clear()
	var total: int = 0
	for entry: Dictionary in deck.cards:
		total += int(entry.quantity)
		var record: Dictionary = record_for(entry.card_id)
		var caption: String = str(record.get("name", "Missing/ambiguous: " + str(entry.card_id)))
		entries.add_item("%d × %s%s" % [entry.quantity, caption, " [Leader]" if deck.leaders.has(entry.card_id) else ""])
	count.text = "Deck: %d cards · %d leaders" % [total, deck.leaders.size()]
	quantity.editable = selected_index >= 0
	leader.disabled = selected_index < 0
	if selected_index >= 0 and selected_index < entries.item_count:
		entries.select(selected_index)
		select_entry(selected_index)
func select_entry(index: int) -> void:
	updating = true
	quantity.editable = true
	leader.disabled = false
	quantity.value = int(deck.cards[index].quantity)
	leader.button_pressed = deck.leaders.has(deck.cards[index].card_id)
	show_preview(deck.cards[index].card_id)
	updating = false
func refresh_saved() -> void:
	var prior_path: String = str(saved[deck_picker.selected].path) if deck_picker.selected >= 0 and deck_picker.selected < saved.size() else saved_path
	saved = storage.list_decks()
	deck_picker.clear()
	for row: Dictionary in saved:
		deck_picker.add_item(str(row.data.get("deck_name", row.path.get_file())) + (" [error]" if not str(row.error).is_empty() else ""))
		if row.path == prior_path:
			deck_picker.select(deck_picker.item_count - 1)
func load_selected() -> void:
	if deck_picker.selected < 0:
		return
	var path: String = saved[deck_picker.selected].path
	for row: Dictionary in storage.list_decks():
		if row.path == path:
			if not str(row.error).is_empty():
				status.text = row.error
				return
			deck = row.data.duplicate(true)
			saved_path = path
			clean_deck = deck.duplicate(true)
			clean_path = path
			dirty = false
			sync_fields()
			status.text = "Loaded " + str(deck.deck_name)
			return
	status.text = "Deck no longer exists. Refresh the list."
func save_current() -> bool:
	deck.deck_name = name_input.text.strip_edges()
	deck.format_id = format_input.text.strip_edges()
	var result: Dictionary = storage.save_deck(deck, saved_path)
	if result.has("error"):
		status.text = result.error
		return false
	saved_path = result.path
	clean_deck = deck.duplicate(true)
	clean_path = saved_path
	dirty = false
	deck_picker.select(-1)
	refresh_saved()
	status.text = "Saved " + str(deck.deck_name)
	return true
func duplicate_current() -> void:
	deck = deck.duplicate(true)
	deck.deck_id = Storage.new_deck().deck_id
	deck.deck_name = name_input.text.strip_edges() + " copy"
	deck.format_id = format_input.text.strip_edges()
	saved_path = ""
	sync_fields()
	dirty = true
	save_current()
func request_delete() -> void:
	if deck_picker.selected < 0:
		return
	var path: String = saved[deck_picker.selected].path
	delete_dialog.dialog_text = "Delete %s? Card definitions and images will remain." % path.get_file()
	for connection: Dictionary in delete_dialog.confirmed.get_connections():
		delete_dialog.confirmed.disconnect(connection.callable)
	delete_dialog.confirmed.connect(func() -> void:
		var error: String = storage.delete_deck(path)
		status.text = "Deck deleted." if error.is_empty() else error
		if error.is_empty() and saved_path == path:
			new_deck()
		refresh_saved())
	delete_dialog.popup_centered()

func toggle_favorite() -> void:
	if saved_path.is_empty():
		status.text = "Save this deck before marking it as a favorite."
		return
	var prefs = preload("res://scripts/usability/deck_preferences.gd").new()
	prefs.toggle(str(deck.deck_id))
	status.text = "Favorite saved." if prefs.favorites.has(deck.deck_id) else "Favorite removed."

func show_face(index: int) -> void:
	var record: Dictionary = record_for(preview_id)
	var faces: Array = preload("res://scripts/card_faces.gd").list(record.get("metadata",{}))
	face_button.visible = faces.size()>1
	preview.texture = null
	if faces.is_empty(): return
	preview_face = index%faces.size()
	face_button.text = "Face %d / %d · Next Face" % [preview_face+1,faces.size()]
	var path: String = str(faces[preview_face].get("image_path",""))
	if path.get_base_dir().simplify_path() != loader.storage.directory.simplify_path() or path.contains(".."): return
	var image := Image.new()
	if FileAccess.file_exists(path) and image.load(path) == OK: preview.texture = ImageTexture.create_from_image(image)

func collection_updated(directory: String) -> void:
	if directory != preload("res://scripts/collection_events.gd").key(loader.storage.directory): return
	var chosen: Array[String] = []
	for index: int in catalog.get_selected_items(): chosen.append(str(catalog.get_item_metadata(index)))
	var scroll_value: float = catalog.get_v_scroll_bar().value
	records = loader.load_records()
	refresh_catalog()
	for index: int in catalog.item_count:
		if str(catalog.get_item_metadata(index)) in chosen: catalog.select(index,false)
	catalog.get_v_scroll_bar().set_deferred("value",scroll_value)
	# Refresh labels only, preserving current deck, fields, quantities and selection.
	for i: int in mini(deck.cards.size(),entries.item_count):
		var entry: Dictionary = deck.cards[i]
		var record: Dictionary = record_for(entry.card_id)
		entries.set_item_text(i,"%d × %s%s" % [entry.quantity,str(record.get("name","Missing/ambiguous: "+str(entry.card_id)))," [Leader]" if deck.leaders.has(entry.card_id) else ""])
	if not preview_id.is_empty(): show_face(preview_face)
func add_imported_card(id: String) -> bool:
	collection_updated(preload("res://scripts/collection_events.gd").key(loader.storage.directory))
	var record: Dictionary = record_for(id)
	if record.is_empty() or record.get("thumbnail") == null:
		status.text = "Imported definition is unavailable in this collection."
		return false
	add_card(id)
	status.text = "Card added to current deck."
	return true
