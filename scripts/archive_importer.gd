extends Window
signal imported(result: Dictionary)
const Service = preload("res://scripts/archive_import_service.gd")
var combine_pairs: CheckBox
var service: RefCounted = Service.new()
var worker: Thread
var job: String = ""
var plan: Dictionary = {}
var archive_path: String = ""
var picker: FileDialog
var summary: RichTextLabel
var name_input: LineEdit
var fit_mode: OptionButton
var target: OptionButton
var acknowledge: CheckBox
var progress: Label
var scan_button: Button
var choose_button: Button
var update_button: Button
var new_button: Button
var cancel_button: Button
var close_after_job: bool = false
func button(parent: Node, caption: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.pressed.connect(action)
	parent.add_child(control)
	return control
func _ready() -> void:
	title = "Import Archive Deck"
	size = Vector2i(830, 620)
	min_size = Vector2i(610, 450)
	visible = false
	exclusive = true
	close_requested.connect(cancel_import)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var rows := VBoxContainer.new()
	margin.add_child(rows)
	var choose_row := HBoxContainer.new()
	rows.add_child(choose_row)
	choose_button = button(choose_row, "Choose ZIP…", func() -> void: picker.popup_centered_ratio(0.8))
	fit_mode = OptionButton.new()
	fit_mode.add_item("Fill — center crop")
	fit_mode.add_item("Fit — keep whole image with padding")
	fit_mode.item_selected.connect(func(_index: int) -> void:
		plan = {}
		combine_pairs.set_pressed_no_signal(false)
		refresh_buttons()
		summary.text = "Framing changed. Preview again to compare the new normalized artwork.")
	choose_row.add_child(fit_mode)
	scan_button = button(choose_row, "Preview archive", start_preview)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Deck name"
	name_input.max_length = 180
	name_input.text_changed.connect(func(_value: String) -> void: refresh_buttons())
	rows.add_child(name_input)
	progress = Label.new()
	progress.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(progress)
	summary = RichTextLabel.new()
	summary.bbcode_enabled = false
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(summary)
	combine_pairs = CheckBox.new()
	combine_pairs.text = "Combine detected Front / Back pairs (unchecked = Keep Separate)"
	combine_pairs.toggled.connect(func(enabled: bool) -> void:
		if worker == null and not plan.is_empty():
			preload("res://scripts/archive_face_pairs.gd").configure(plan,service.cards.directory,enabled)
			show_plan())
	rows.add_child(combine_pairs)
	target = OptionButton.new()
	target.item_selected.connect(func(_index: int) -> void:
		if target.selected >= 0:
			name_input.text = plan.candidates[target.selected].deck.deck_name
		show_plan())
	rows.add_child(target)
	acknowledge = CheckBox.new()
	acknowledge.text = "I reviewed the unusual crops and skipped images listed above."
	acknowledge.toggled.connect(func(_value: bool) -> void: refresh_buttons())
	rows.add_child(acknowledge)
	var actions := HBoxContainer.new()
	rows.add_child(actions)
	cancel_button = button(actions, "Cancel", cancel_import)
	update_button = button(actions, "Update Existing Deck", func() -> void: start_commit(false))
	new_button = button(actions, "Import as New Deck", func() -> void: start_commit(true))
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.zip ; ZIP card archive"])
	picker.file_selected.connect(func(path: String) -> void:
		archive_path = path
		start_preview())
	add_child(picker)
	refresh_buttons()
func open_importer() -> void:
	if worker != null:
		return
	plan = {}
	combine_pairs.set_pressed_no_signal(false)
	archive_path = ""
	name_input.text = ""
	target.clear()
	acknowledge.hide()
	summary.text = "Choose a ZIP of PNG, JPG, JPEG or WebP images. Nested folders are included.\n\nPreview is read-only. Import commits only after you choose an action.\n\nRAR is deferred; convert RAR archives to ZIP before importing."
	progress.text = ""
	refresh_buttons()
	popup_centered_clamped(Vector2i(830, 620), 0.94)
func start_preview() -> void:
	if worker != null or archive_path.is_empty():
		return
	plan = {}
	combine_pairs.set_pressed_no_signal(false)
	target.clear()
	acknowledge.set_pressed_no_signal(false)
	acknowledge.hide()
	service.reset_job()
	job = "preview"
	worker = Thread.new()
	var error: Error = worker.start(service.preview.bind(archive_path, fit_mode.selected == 1))
	if error != OK:
		worker = null
		summary.text = "Could not start archive scan. Please try again."
	refresh_buttons()
func start_commit(as_new: bool) -> void:
	if worker != null or plan.is_empty() or name_input.text.strip_edges().is_empty() or (acknowledge.visible and not acknowledge.button_pressed):
		return
	if not as_new and target.selected < 0:
		return
	service.reset_job()
	job = "commit"
	worker = Thread.new()
	var error: Error = worker.start(service.commit.bind(plan, target.selected, as_new, name_input.text))
	if error != OK:
		worker = null
		summary.text = "Could not start import. Please try again."
	refresh_buttons()
func _process(_delta: float) -> void:
	if worker == null:
		return
	progress.text = service.progress_text()
	if worker.is_alive():
		return
	var result: Dictionary = worker.wait_to_finish()
	worker = null
	if result.has("error"):
		summary.text = str(result.error)
		for issue: String in result.get("failed", []):
			summary.text += "\n" + issue
		if result.has("unsupported"):
			summary.text += "\nUnsupported files: %d" % result.unsupported.size()
		plan = {}
		combine_pairs.set_pressed_no_signal(false)
	elif result.has("cancelled"):
		summary.text = "Import cancelled. No deck was changed."
		plan = {}
		combine_pairs.set_pressed_no_signal(false)
	elif job == "preview":
		plan = result
		name_input.text = plan.deck_name
		target.clear()
		for candidate: Dictionary in plan.candidates:
			target.add_item(candidate.deck.deck_name + " — " + str(candidate.deck.deck_id).right(8))
		target.select(0 if plan.candidates.size() == 1 else -1)
		if target.selected >= 0:
			name_input.text = plan.candidates[target.selected].deck.deck_name
		show_plan()
	else:
		plan = {}
		combine_pairs.set_pressed_no_signal(false)
		summary.text = "Imported %d card copies into '%s'.\n%d new definitions created; existing assets reused where identical.\n\nThe saved deck is available in Deck Builder and Menu → Library → Load Deck." % [result.copies, result.deck.deck_name, result.created_definitions]
		imported.emit(result)
	progress.text = ""
	refresh_buttons()
	if close_after_job:
		close_after_job = false
		hide()
func show_plan() -> void:
	if plan.is_empty():
		return
	var lines: PackedStringArray = ["Archive: " + str(plan.archive).get_file(), "Images found: %d · Usable copies: %d · Unique name/art pairs: %d" % [plan.images_found, plan.valid_images, plan.rows.size()], "New definitions: %d · Existing definitions: %d · Same-name changed art: %d" % [plan.stats.new, plan.stats.existing, plan.stats.changed], "Unsupported files: %d · Corrupt/skipped images: %d · Unusual ratios: %d" % [plan.unsupported.size(), plan.failed.size(), plan.warnings.size()], "Normalization: 750 × 1050, " + ("Fit with padding" if plan.fit else "center-crop Fill")]
	if plan.candidates.is_empty():
		lines.append("\nNo previously imported matching deck found. A new deck will be saved.")
	elif target.selected < 0:
		lines.append("\nMultiple matching decks. Choose which one to compare/update below, or import a new deck.")
	else:
		var candidate: Dictionary = plan.candidates[target.selected]
		lines.append("\nCompared with: " + candidate.deck.deck_name)
		for category: String in ["added", "removed", "quantities", "artwork", "unchanged"]:
			lines.append("%s (%d): %s" % [category.capitalize(), candidate.diff[category].size(), "; ".join(candidate.diff[category]) if not candidate.diff[category].is_empty() else "none"])
		lines.append("Updating keeps the deck ID/format. Unchanged definitions are reused; changed art gets a new definition. Unambiguous leader replacements are retained.")
	lines.append("\nIncoming cards:")
	var pairs: Array = preload("res://scripts/archive_face_pairs.gd").detect(plan.get("separate_rows",plan.rows))
	combine_pairs.visible = not pairs.is_empty()
	combine_pairs.disabled = worker != null
	if not pairs.is_empty(): lines.append("Possible multi-face cards: %d. Choose Combine above or Keep Separate. Same folder, exact Front/Back suffix, equal quantities only." % pairs.size())
	for row: Dictionary in plan.rows:
		lines.append("%d × %s [%s]" % [row.quantity, row.name, "new definition" if row.existing_id.is_empty() else "reuse existing"])
	for category: String in ["warnings", "failed", "unsupported"]:
		if not plan[category].is_empty():
			lines.append("\n" + category.capitalize() + ":")
			for issue: String in plan[category]:
				lines.append(issue)
	summary.text = "\n".join(lines)
	acknowledge.visible = not plan.warnings.is_empty() or not plan.failed.is_empty()
	refresh_buttons()
func refresh_buttons() -> void:
	if new_button == null:
		return
	var busy: bool = worker != null
	combine_pairs.disabled = busy
	combine_pairs.disabled = busy
	choose_button.disabled = busy
	scan_button.disabled = busy or archive_path.is_empty()
	fit_mode.disabled = busy
	name_input.editable = not busy
	target.disabled = busy or plan.get("candidates", []).is_empty()
	acknowledge.disabled = busy
	var ready: bool = not busy and not plan.is_empty() and not name_input.text.strip_edges().is_empty() and (not acknowledge.visible or acknowledge.button_pressed)
	new_button.disabled = not ready
	update_button.disabled = not ready or target.selected < 0 or plan.get("candidates", []).is_empty()
	cancel_button.text = "Cancel job" if busy else "Close / Cancel"
func cancel_import() -> void:
	if worker != null:
		service.cancel()
		close_after_job = true
		progress.text = "Cancelling after the current image…"
	else:
		plan = {}
		combine_pairs.set_pressed_no_signal(false)
		hide()
func _exit_tree() -> void:
	if worker != null:
		service.cancel()
		worker.wait_to_finish()
		worker = null
