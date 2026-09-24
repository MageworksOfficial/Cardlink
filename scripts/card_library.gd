extends PanelContainer
signal back_requested
signal archive_requested
signal import_requested
signal place_requested(record: Dictionary)
const Loader = preload("res://scripts/library_loader.gd")
const Editor = preload("res://scripts/library_metadata_editor.gd")
const Thumbnail = preload("res://ui/library_thumbnail.tscn")
var face_tools: RefCounted
var loader: Loader = Loader.new()
var records: Array[Dictionary] = []
var displayed: Array[Dictionary] = []
var selected_path: String = ""
var pending_delete: String = ""
var query: LineEdit
var tag_filter: OptionButton
var sort_order: OptionButton
var grid: GridContainer
var preview: TextureRect
var preview_placeholder: Label
var editor: Editor
var details: Label
var status: Label
var delete_button: Button
var place_button: Button
var delete_dialog: ConfirmationDialog
var cleanup_dialog: ConfirmationDialog
var scroll: ScrollContainer

func action(parent: Node, caption: String, callback: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.pressed.connect(callback)
	parent.add_child(control)
	return control
func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.11, 0.12, 0.14, 1.0)
	add_theme_stylebox_override("panel", background)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	action(toolbar, "← Tabletop", func() -> void: back_requested.emit())
	var title := Label.new()
	title.text = "Card Library"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	action(toolbar, "Import Card", func() -> void: import_requested.emit())
	action(toolbar, "Import ZIP Deck", func() -> void: archive_requested.emit())
	action(toolbar, "Refresh", refresh)
	action(toolbar, "Clean unused images…", request_cleanup)
	var optional := HBoxContainer.new()
	layout.add_child(optional)
	action(optional, "Online Search / MTG Catalog", func() -> void: preload("res://scripts/integrations/integration_hub.gd").open(self,0))
	action(optional, "Import Decklist", func() -> void: preload("res://scripts/integrations/integration_hub.gd").open(self,1))
	var filters := HBoxContainer.new()
	layout.add_child(filters)
	query = LineEdit.new()
	query.placeholder_text = "Search card names…"
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query.text_changed.connect(func(_value: String) -> void: rebuild_grid())
	filters.add_child(query)
	tag_filter = OptionButton.new()
	tag_filter.custom_minimum_size.x = 170
	tag_filter.item_selected.connect(func(_index: int) -> void: rebuild_grid())
	filters.add_child(tag_filter)
	sort_order = OptionButton.new()
	sort_order.add_item("Name A–Z")
	sort_order.add_item("Newest first")
	sort_order.item_selected.connect(func(_index: int) -> void: rebuild_grid())
	filters.add_child(sort_order)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	layout.add_child(body)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	scroll.resized.connect(resize_grid)
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 330
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(300, 420)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	side.add_child(preview)
	preview_placeholder = Label.new()
	preview_placeholder.text = "Select a card to preview"
	preview_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.add_child(preview_placeholder)
	face_tools = preload("res://scripts/library_face_tools.gd").new(self,side)
	editor = Editor.new()
	side.add_child(editor)
	editor.save_requested.connect(save_metadata)
	place_button = action(side, "Place copy on tabletop", place_selected)
	delete_button = action(side, "Delete definition…", request_delete)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(details)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete card definition?"
	delete_dialog.confirmed.connect(confirm_delete)
	add_child(delete_dialog)
	cleanup_dialog = ConfirmationDialog.new()
	cleanup_dialog.title = "Clean unused images?"
	cleanup_dialog.confirmed.connect(confirm_cleanup)
	add_child(cleanup_dialog)
	select_record("")

func open_library() -> void:
	show()
	refresh()
func refresh() -> void:
	var old_tag: String = str(tag_filter.get_selected_metadata()) if tag_filter.selected >= 0 else ""
	records = loader.load_records()
	tag_filter.clear()
	tag_filter.add_item("All tags")
	tag_filter.set_item_metadata(0, "")
	var tags: Array[String] = []
	for record: Dictionary in records:
		for tag: String in record["tags"]:
			if not tags.has(tag):
				tags.append(tag)
	tags.sort()
	for tag: String in tags:
		tag_filter.add_item(tag)
		tag_filter.set_item_metadata(tag_filter.item_count - 1, tag)
		if tag == old_tag:
			tag_filter.select(tag_filter.item_count - 1)
	rebuild_grid()
func resize_grid() -> void:
	grid.columns = maxi(1, int((scroll.size.x - 16) / 164))
func rebuild_grid() -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var tag: String = str(tag_filter.get_selected_metadata()) if tag_filter.selected >= 0 else ""
	displayed = Loader.filtered(records, query.text, tag, sort_order.selected == 1)
	var selection_visible: bool = false
	for record: Dictionary in displayed:
		var item = Thumbnail.instantiate()
		grid.add_child(item)
		item.configure(record, record["path"] == selected_path)
		item.pressed.connect(select_record.bind(record["path"]))
		selection_visible = selection_visible or record["path"] == selected_path
	resize_grid()
	select_record(selected_path if selection_visible else "")
	status.text = "%d of %d definitions" % [displayed.size(), records.size()]
	if records.is_empty():
		status.text = "Your library is empty. Import a card to get started."
	elif displayed.is_empty():
		status.text = "No matching cards. Clear the search or choose All tags."
func select_record(path: String) -> void:
	selected_path = path
	var record: Dictionary = {}
	for candidate: Dictionary in records:
		if candidate["path"] == path:
			record = candidate
	preview.texture = null
	if not record.is_empty() and record["thumbnail"] != null:
		var image := Image.new()
		if FileAccess.file_exists(record["image_path"]) and image.load(record["image_path"]) == OK:
			preview.texture = ImageTexture.create_from_image(image)
	preview_placeholder.visible = preview.texture == null
	preview_placeholder.text = "Select a card to preview" if record.is_empty() else "Image unavailable"
	face_tools.select(record)
	editor.show_record(record)
	delete_button.disabled = record.is_empty()
	place_button.disabled = record.is_empty() or record.get("thumbnail") == null or str(record.get("metadata", {}).get("card_id", "")).is_empty()
	details.text = "" if record.is_empty() else "\n".join(record["errors"]) + "\nDefinition file: " + path.get_file()
	for child: Node in grid.get_children():
		child.set_pressed_no_signal(child.record_path == path)
func save_metadata(card_name: String, tags: Array[String]) -> void:
	if selected_path.is_empty():
		return
	var result: Dictionary = loader.storage.update_metadata(selected_path, card_name, tags)
	if result.has("error"):
		status.text = result["error"]
	else:
		refresh()
		status.text = "Name and tags saved."
func request_delete() -> void:
	if selected_path.is_empty():
		return
	pending_delete = selected_path
	delete_dialog.dialog_text = "Delete this definition?\n%s\nImage assets will be retained. This cannot be undone." % selected_path.get_file()
	delete_dialog.popup_centered(Vector2i(520, 180))
func confirm_delete() -> void:
	var result: Dictionary = loader.storage.delete_definition(pending_delete)
	pending_delete = ""
	refresh()
	status.text = result.get("error", "Definition deleted. Image assets retained; use cleanup separately if desired.")
func request_cleanup() -> void:
	var scan: Dictionary = loader.storage.cleanup_candidates()
	if scan.has("error"):
		status.text = scan["error"]
		return
	cleanup_dialog.dialog_text = "Remove %d unreferenced image assets?\nOnly owned SHA-256 PNG files are eligible. References are rechecked at confirmation. This cannot be undone." % scan["paths"].size()
	cleanup_dialog.popup_centered(Vector2i(520, 180))
func confirm_cleanup() -> void:
	var result: Dictionary = loader.storage.cleanup_unused()
	refresh()
	status.text = result.get("error", "Removed %d unused image assets." % result.get("removed", 0))


func place_selected() -> void:
	for record: Dictionary in records:
		if record["path"] == selected_path:
			place_requested.emit(record)
			return
