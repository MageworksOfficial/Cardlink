extends Window
var editor: Node
var rows: VBoxContainer
var confirmation: ConfirmationDialog
var overwrite: ConfirmationDialog
var pending_delete: String = ""
var pending_save: Dictionary = {}
var export_after: bool = false
var export_data: Dictionary = {}
var picker: FileDialog
var include_images: CheckBox
func _ready() -> void:
	theme = preload("res://scripts/frontend/frontend_theme.gd").make_theme()
	preload("res://scripts/frontend/frontend_theme.gd").skin_window(self)
	title = "My Tables"
	borderless = true
	window_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"): hide())
	size = Vector2i(620,560)
	visible = false
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Delete saved template?"
	confirmation.confirmed.connect(func() -> void:
		var error: String = editor.builder.storage.delete_template(pending_delete)
		editor.notify("Template deleted." if error.is_empty() else error)
		open_manager())
	add_child(confirmation)
	overwrite = ConfirmationDialog.new()
	overwrite.title = "Update existing template?"
	overwrite.dialog_text = "Update this saved table, or save a separate copy?"
	overwrite.ok_button_text = "Update"
	overwrite.add_button("Save Copy",false,"copy")
	overwrite.confirmed.connect(func() -> void: finish_save(false))
	overwrite.custom_action.connect(func(action: StringName) -> void:
		if action == "copy": overwrite.hide(); finish_save(true))
	add_child(overwrite)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.filters = PackedStringArray(["*.cltemplate ; CardLink Table Template"])
	picker.file_selected.connect(func(path: String) -> void:
		var result: Dictionary = editor.builder.storage.export_file(export_data,path,include_images.button_pressed)
		editor.notify(result.get("error","Template exported.")))
	add_child(picker)
func label(text: String) -> void:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(item)
func open_manager() -> void:
	for child: Node in rows.get_children(): rows.remove_child(child); child.queue_free()
	var header := HBoxContainer.new()
	rows.add_child(header)
	var heading := Label.new()
	heading.text = "MY TABLES"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	editor.add_button(header,"Close",hide)
	label("CardLink Standard · Built-in · Protected\nChoose CardLink Standard from New Match. It cannot be edited or deleted here.")
	include_images = CheckBox.new()
	include_images.text = "Include board / back images when exporting (optional)"
	rows.add_child(include_images)
	for record: Dictionary in editor.builder.storage.list_templates():
		var result: Dictionary = editor.builder.storage.preview(record.path)
		if result.has("error"): continue
		var data: Dictionary = result.table
		label("▧ "+data.name+"\n"+data.description+"\n"+(data.author if not data.author.is_empty() else "No author")+" · %d components" % data.components.size())
		var actions := HBoxContainer.new()
		rows.add_child(actions)
		editor.add_button(actions,"Load",func() -> void: load_table(data))
		editor.add_button(actions,"Edit",func() -> void: edit_metadata(data))
		editor.add_button(actions,"Duplicate",func() -> void:
			var copy: Dictionary = editor.builder.storage.duplicate_template(data)
			if copy.has("error"): editor.notify(copy.error)
			else: edit_metadata(copy.table))
		editor.add_button(actions,"Export",func() -> void: export_template(data))
		editor.add_button(actions,"Delete",func() -> void:
			pending_delete = data.id
			confirmation.dialog_text = "Delete “"+data.name+"”? Current match cards and image assets stay intact."
			confirmation.popup_centered())
	label("Templates contain arrangements, not your collection or private pile contents.")
	editor.add_button(rows,"Import Template…",func() -> void: hide(); editor.builder.panel.template_form(false); editor.builder.panel.choose_file("import"))
	editor.add_button(rows,"Close",hide)
	popup_centered_clamped(Vector2i(620,560),0.85)
func load_table(data: Dictionary) -> void:
	if editor.dirty() and not editor.builder.document.components.is_empty():
		var ask := ConfirmationDialog.new()
		ask.dialog_text = "Load this table and replace unsaved layout changes? Existing pile cards return to the battlefield."
		add_child(ask)
		ask.confirmed.connect(func() -> void: apply_loaded(data); ask.queue_free())
		ask.canceled.connect(ask.queue_free)
		ask.popup_centered()
	else: apply_loaded(data)
func apply_loaded(data: Dictionary) -> void:
	var error: String = editor.builder.apply_template(data)
	if not error.is_empty(): editor.notify(error); return
	editor.mark_saved()
	hide()
	editor.open_drawer()
	editor.notify("Template loaded.")
func edit_metadata(data: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Edit Table Details"
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var inputs: Array[LineEdit] = []
	for key: String in ["name","description","author"]:
		var field := LineEdit.new()
		field.text = data[key]
		field.placeholder_text = key.capitalize()
		field.max_length = 1000 if key == "description" else 80
		box.add_child(field)
		inputs.append(field)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var changed: Dictionary = data.duplicate(true)
		changed.name = inputs[0].text
		changed.description = inputs[1].text
		changed.author = inputs[2].text
		var result: Dictionary = editor.builder.storage.save(changed)
		editor.notify(result.get("error","Template details saved."))
		dialog.queue_free()
		open_manager())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(440,220))
func request_save(data: Dictionary, also_export: bool = false) -> void:
	editor.builder.panel.hide()
	pending_save = data.duplicate(true)
	export_after = also_export
	var error: String = editor.builder.Doc.validate(data)
	if not error.is_empty(): editor.notify(error); return
	if FileAccess.file_exists(editor.builder.storage.directory.path_join(data.id+".cltemplate")):
		# Dialog must remain reachable when the manager itself was not open.
		open_manager()
		overwrite.popup_centered()
	else: finish_save(false)
func finish_save(copy: bool) -> void:
	var data: Dictionary = pending_save.duplicate(true)
	if copy: data.id = editor.builder.Doc.fresh().id
	var result: Dictionary = editor.builder.storage.save(data)
	if result.has("error"): editor.notify(result.error); return
	editor.builder.document = data
	editor.builder.structure_changed.emit()
	editor.mark_saved()
	editor.notify("Template saved.")
	editor.builder.panel.hide()
	if export_after:
		open_manager()
		export_template(data)
	else: hide()
func export_template(data: Dictionary) -> void:
	export_data = data.duplicate(true)
	picker.current_file = data.name.validate_filename()+".cltemplate"
	picker.popup_centered_ratio(0.8)
