extends VBoxContainer
signal record_saved(path: String)
signal record_loaded(path: String)
## Shared UI for local named layout/match records; never constructs file paths.
var storage: RefCounted
var capture_data: Callable
var apply_data: Callable
var validator: Callable
var confirm_load: bool = false
var picker: OptionButton
var name_edit: LineEdit
var message: Label
var confirm: ConfirmationDialog
var pending: Callable
func action(caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	add_child(button)
func _ready() -> void:
	picker = OptionButton.new()
	picker.item_selected.connect(func(_index: int) -> void:
		if picker.selected > 0:
			name_edit.text = picker.get_item_text(picker.selected))
	add_child(picker)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Save name"
	add_child(name_edit)
	action("Save current state (new or selected slot)", save_current)
	action("Load selected", request_load)
	action("Rename selected", func() -> void: finish(storage.rename_record(selected_path(), name_edit.text)))
	action("Duplicate selected", func() -> void: finish(storage.duplicate_record(selected_path(), name_edit.text)))
	action("Delete selected…", request_delete)
	action("Refresh saved list", refresh)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	confirm = ConfirmationDialog.new()
	confirm.confirmed.connect(func() -> void:
		if pending.is_valid():
			pending.call())
	add_child(confirm)
	refresh()
func selected_path() -> String:
	return str(picker.get_selected_metadata()) if picker.selected >= 0 else ""
func refresh() -> void:
	var old: String = selected_path()
	picker.clear()
	picker.add_item("New save")
	picker.set_item_metadata(0, "")
	for record: Dictionary in storage.list_records():
		picker.add_item(record.name + (" [unreadable]" if not str(record.error).is_empty() else ""))
		picker.set_item_metadata(picker.item_count - 1, record.path)
		if record.path == old:
			picker.select(picker.item_count - 1)
func finish(result: Dictionary) -> void:
	message.text = str(result.get("error", "Done."))
	refresh()
func save_current() -> void:
	var data: Dictionary = capture_data.call()
	if validator.is_valid():
		var error: String = validator.call(data)
		if not error.is_empty():
			message.text = error
			return
	var result: Dictionary = storage.save_record(data, name_edit.text, selected_path())
	finish(result)
	if result.has("path"):
		for i: int in picker.item_count:
			if picker.get_item_metadata(i) == result.path:
				picker.select(i)
func request_load() -> void:
	var result: Dictionary = storage.read_record(selected_path())
	if result.has("error"):
		finish(result)
		return
	var apply: Callable = func() -> void:
		var loaded: Dictionary = apply_data.call(result.record.data)
		message.text = str(loaded.get("error", "Loaded."))
		if not loaded.has("error"): record_loaded.emit(str(result.path))
		if int(loaded.get("missing_images", 0)) > 0:
			message.text = "Loaded with missing-image placeholders."
	if confirm_load:
		pending = apply
		confirm.dialog_text = "Replace the current local match with this saved match? Unsaved match changes will be lost."
		confirm.popup_centered(Vector2i(520, 180))
	else:
		apply.call()
func request_delete() -> void:
	var path: String = selected_path()
	if path.is_empty():
		message.text = "Select a saved file first."
		return
	pending = func() -> void: finish(storage.delete_record(path))
	confirm.dialog_text = "Delete this saved file? This cannot be undone."
	confirm.popup_centered(Vector2i(480, 160))
