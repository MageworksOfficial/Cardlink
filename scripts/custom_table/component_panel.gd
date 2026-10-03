extends Window
var builder: Node
var rows: VBoxContainer
var search: LineEdit
var list: VBoxContainer
var status: Label
var editing: String = ""
var pending_import: String = ""
var pending_remove: String = ""
var confirm: ConfirmationDialog
var picker: FileDialog
var purpose: String = ""
var include_images: bool = false
func _ready() -> void:
	theme = preload("res://scripts/frontend/frontend_theme.gd").make_theme()
	preload("res://scripts/frontend/frontend_theme.gd").skin_window(self)
	title = "Table Components"
	size = Vector2i(540,680)
	visible = false
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_selected.connect(selected_file)
	add_child(picker)
	confirm = ConfirmationDialog.new()
	add_child(confirm)
	confirm.confirmed.connect(func() -> void:
		if not pending_remove.is_empty():
			builder.remove_component(pending_remove,true)
			pending_remove = ""
			open_palette()
		elif not pending_import.is_empty():
			var result: Dictionary = builder.storage.import_file(pending_import)
			pending_import = ""
			if result.has("error"): status.text = result.error
			else:
				builder.apply_template(result.table)
				open_palette()
				builder.editor.mark_saved()
				builder.editor.notify("Template imported." if result.missing.is_empty() else "Board image missing. Choose a replacement in Board properties."))
	window_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"): hide())
func clear(caption: String) -> void:
	title = caption
	for child: Node in rows.get_children(): rows.remove_child(child); child.queue_free()
	status = null
func label(caption: String) -> Label:
	var item := Label.new()
	item.text = caption
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(item)
	return item
func button(caption: String, action: Callable, parent: Node = null) -> Button:
	var item := Button.new()
	item.text = caption
	item.pressed.connect(action)
	(parent if parent != null else rows).add_child(item)
	return item
func field(caption: String, value: String, limit: int = 80) -> LineEdit:
	label(caption)
	var item := LineEdit.new()
	item.text = value
	item.max_length = limit
	rows.add_child(item)
	return item
func select_field(caption: String, values: Array, current: String) -> OptionButton:
	label(caption)
	var option := OptionButton.new()
	for value: String in values:
		option.add_item({"player_1":"Player 1","player_2":"Player 2","table":"Shared / Table","public":"Public","private":"Private"}.get(value,value))
		option.set_item_metadata(option.item_count-1,value)
		if value == current: option.select(option.item_count-1)
	rows.add_child(option)
	return option
func spin(caption: String, value: float, low: float, high: float, step: float = 1) -> SpinBox:
	label(caption)
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.value = value
	rows.add_child(input)
	return input
func check(caption: String, value: bool) -> CheckBox:
	var item := CheckBox.new()
	item.text = caption
	item.button_pressed = value
	rows.add_child(item)
	return item
func show_panel() -> void: popup_centered_clamped(Vector2i(540,680),0.9)
func open_palette() -> void:
	hide()
	builder.editor.open_drawer()
	search = builder.editor.drawer.search
func open_component(id: String) -> void:
	var item: Dictionary = builder.row(id)
	if item.is_empty(): return
	editing = id
	clear(item.name)
	var name_input: LineEdit = field("Name",item.name)
	var owner: OptionButton = select_field("Owner",["table"] if item.kind == "shared_deck" else (["player_1","player_2"] if item.kind == "hand" else builder.Doc.OWNERS),item.owner)
	var visibility: OptionButton = select_field("Visibility",["public","private"],item.visibility)
	var x: SpinBox = spin("Position X",item.position[0],-20000,20000)
	var y: SpinBox = spin("Position Y",item.position[1],-20000,20000)
	var w: SpinBox = spin("Width",item.size[0],40,8000)
	var h: SpinBox = spin("Height",item.size[1],40,8000)
	var scale_input: SpinBox = spin("Scale",1.0,0.1,10.0,0.1)
	var rotation_input: SpinBox = spin("Rotation",item.rotation,-360,360)
	var opacity: SpinBox = spin("Opacity",item.opacity,0.05,1,0.05)
	var locked: CheckBox = check("Lock to Table",item.locked)
	var shown: CheckBox = check("Show component",not item.hidden)
	var text_input: LineEdit = field("Text",item.text,1000) if item.kind == "text" else null
	var linked: OptionButton = null
	if item.kind == "discard":
		linked = select_field("Associated deck",[""],"")
		linked.set_item_text(0,"None")
		for pile: Dictionary in builder.document.components:
			if pile.kind in ["deck","shared_deck"]:
				linked.add_item(pile.name)
				linked.set_item_metadata(linked.item_count-1,pile.id)
				if pile.id == item.linked_pile: linked.select(linked.item_count-1)
	button("Apply Properties",func() -> void:
		var changes: Dictionary = {"name":name_input.text,"owner":owner.get_selected_metadata(),"visibility":visibility.get_selected_metadata(),"position":[x.value,y.value],"size":[w.value*scale_input.value,h.value*scale_input.value],"rotation":rotation_input.value,"opacity":opacity.value,"locked":locked.button_pressed,"hidden":not shown.button_pressed}
		if text_input != null: changes.text = text_input.text
		if linked != null: changes.linked_pile = linked.get_selected_metadata()
		status.text = "Changes saved to the table." if builder.update_component(id,changes) else "Check the values and try again.")
	if item.kind == "board":
		button("Choose Replacement / Board Image",func() -> void: choose_file("board"))
		label("Board images stay behind cards.")
	if item.kind in ["deck","shared_deck"]:
		button("Set as Primary Draw Pile",func() -> void: builder.set_primary(id); builder.editor.notify("Primary Draw set."))
		button("Choose Card Back Image",func() -> void: choose_file("back"))
		button("Use Default Card Back",func() -> void: builder.update_component(id,{"back":""}))
		button("Load Saved Deck into This Pile",func() -> void: deck_list(id))
		button("Draw to Player 1",func() -> void: status.text = "Drawn." if builder.draw(id,"player_1") else "Pile empty or unavailable.")
		button("Draw to Player 2",func() -> void: status.text = "Drawn." if builder.draw(id,"player_2") else "Pile empty or unavailable.")
		button("Shuffle This Pile",func() -> void: builder.shuffle(id))
	button("Move Selected Card Here",func() -> void: status.text = "Card moved." if builder.put_card(builder.manager.selected_card,id) else "Select a card on the table first.")
	button("Remove Component",func() -> void:
		builder.editor.selected = id
		hide()
		builder.editor.drawer.remove_selected())
	button("Back to Components",open_palette)
	status = label("Right-click opens properties. In Layout Mode, drag to move. Resize above.")
	show_panel()
func deck_list(id: String) -> void:
	clear("Choose Deck for This Pile")
	var decks = preload("res://scripts/deck_storage.gd").new()
	for record: Dictionary in decks.list_decks():
		if not record.error.is_empty(): continue
		button(record.data.deck_name,func() -> void:
			var error: String = builder.load_deck(id,record.data)
			open_component(id)
			status.text = "Deck added as new match copies." if error.is_empty() else error)
	button("Back",func() -> void: open_component(id))
	status = label("Adds new copies without replacing other piles.")
func load_list() -> void:
	hide()
	builder.editor.templates.open_manager()
func template_form(exporting: bool) -> void:
	builder.capture_template_defaults()
	clear("Export Template" if exporting else "Save Table Template")
	var name_input: LineEdit = field("Template Name",builder.document.name)
	var description: LineEdit = field("Description",builder.document.description,1000)
	var author: LineEdit = field("Author (optional)",builder.document.author)
	var after: CheckBox = check("Export after saving",false)
	after.visible = not exporting
	var include: CheckBox = check("Include board and card-back images",false)
	include.visible = exporting
	label("Only include images you have permission to redistribute. Card collections are never packaged.")
	button("Export" if exporting else "Save Template",func() -> void:
		builder.document.name = name_input.text
		builder.document.description = description.text
		builder.document.author = author.text
		builder.editor.refresh()
		var error: String = builder.Doc.validate(builder.document)
		if not error.is_empty(): status.text = error; return
		if exporting:
			include_images = include.button_pressed
			choose_file("export")
		else:
			builder.editor.templates.request_save(builder.document,after.button_pressed))
	button("Back",open_palette)
	status = label("")
	show_panel()
func choose_file(action: String) -> void:
	purpose = action
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action == "export" else FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.cltemplate ; CardLink Table Template"]) if action in ["import","export"] else PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image"])
	if action == "export": picker.current_file = "My-Table.cltemplate"
	picker.popup_centered_ratio(0.8)
func selected_file(file: String) -> void:
	if purpose == "export":
		var result: Dictionary = builder.storage.export_file(builder.document,file,include_images)
		status.text = result.get("error","Template exported.")
	elif purpose == "import":
		var result: Dictionary = builder.storage.preview(file)
		if result.has("error"): status.text = result.error; return
		pending_import = file
		pending_remove = ""
		confirm.dialog_text = "%s\nBy: %s\n%s\n%d objects | Template version %d\nOptional images: %d included, %d missing\nImport this table? Existing pile cards return to the battlefield." % [result.table.name,result.table.author,result.table.description,result.table.components.size(),result.table.format,result.images.size(),result.missing.size()]
		confirm.popup_centered()
	else:
		var result: Dictionary = builder.assets.ingest(file)
		if result.has("error"): status.text = result.error; return
		builder.update_component(editing,{"asset" if purpose == "board" else "back":result.hash})
		status.text = "Image saved."
func onboarding() -> void:
	builder.editor.refresh()
