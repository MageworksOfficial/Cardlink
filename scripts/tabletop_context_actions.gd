extends RefCounted
## Context-only controls; the permanent toolbar retains its nine entry points.
var controls: Control
var card_n: SpinBox
var library_n: SpinBox
var back_picker: FileDialog
func _init(owner: Control) -> void:
	controls = owner
func number(parent: Node, caption: String) -> SpinBox:
	controls.label(parent, caption)
	var input := SpinBox.new()
	input.min_value = 1
	input.max_value = 5000
	input.value = 1
	parent.add_child(input)
	return input
func card_button(rows: Node, caption: String, callback: Callable) -> void:
	controls.card_actions.append(controls.button(rows, caption, callback))
func build_card(rows: Node, target: OptionButton) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	rows.add_child(grid)
	card_button(grid, "Tap / Untap", func() -> void:
		var card: Control = controls.manager.selected_card
		if card != null:
			controls.manager.toggle_tap(card))
	card_button(grid, "Token Properties", func() -> void:
		var card: Control = controls.manager.selected_card
		if card != null and card.state.is_token and controls.manager.match_controller.visibility.can_present(card.state,"local"):
			controls.close_panels()
			controls.manager.extras.token_editor.open_token(card))
	card_button(grid, "Change Face / Next Face", func() -> void: preload("res://scripts/usability/face_actions.gd").change(controls.manager,controls.manager.selected_card))
	card_button(grid, "Change Controller", func() -> void: controls.manager.match_controller.change_controller(controls.manager.selected_card, str(target.get_selected_metadata())))
	for entry: Array in [["Move to Hand", "hand"], ["Move to Graveyard", "graveyard"], ["Move to Exile", "exile"], ["Move to Commander / Leader", "commander"], ["Put on Top of Library", "library"], ["Put on Bottom of Library", "bottom"], ["Play to Battlefield", "battlefield"]]:
		card_button(grid, entry[0], move_selected.bind(str(entry[1]), target))
	card_button(grid, "Duplicate as Token", func() -> void:
		var result: Dictionary = controls.manager.match_controller.library_actions.duplicate_token(controls.manager.selected_card)
		controls.status.text = str(result.get("error", "Token copy created.")))
	card_button(grid, "Delete", func() -> void:
		var card: Control = controls.manager.selected_card
		if is_instance_valid(card):
			var c: Node = controls.manager.match_controller
			var id: String = card.state.match_instance_id
			if c.move_card(card,"graveyard",true,card.state.owner_player_id):
				c.record_event("delete","Card deleted (normal cards go to owner's graveyard)",{"instance_id":id})
		controls.close_panels())
	card_button(grid, "Reveal", set_hidden.bind(false))
	card_button(grid, "Hide / Face Down", set_hidden.bind(true))
	card_n = number(rows, "Library position N (1 = nearest end; out-of-range goes to far end)")
	var insertion := HBoxContainer.new()
	rows.add_child(insertion)
	card_button(insertion, "Put N from Top", func() -> void:
		controls.manager.match_controller.library_actions.put_nth(controls.manager.selected_card, str(target.get_selected_metadata()), int(card_n.value)))
	card_button(insertion, "Put N from Bottom", func() -> void:
		controls.manager.match_controller.library_actions.put_nth(controls.manager.selected_card, str(target.get_selected_metadata()), int(card_n.value), true))
	var counters := HBoxContainer.new()
	rows.add_child(counters)
	card_button(counters, "Add Counter", controls.manager.change_counter.bind(1))
	card_button(counters, "Remove Counter", controls.manager.change_counter.bind(-1))
	card_button(rows, "Counters → Loyalty…", func() -> void: preload("res://scripts/battle/loyalty.gd").open(controls.manager))
	card_button(rows, "Counter type / Set value…", controls.open_panel.bind("Counter"))
func move_selected(kind: String, target: OptionButton) -> void:
	controls.manager.match_controller.move_card(controls.manager.selected_card, "library" if kind == "bottom" else kind, kind != "bottom", str(target.get_selected_metadata()))
func set_hidden(hidden: bool) -> void:
	if controls.manager.undo != null: controls.manager.undo.invalidate("Reveal / hide is not undoable.")
	var card: Control = controls.manager.selected_card
	if card == null:
		return
	if card.state.current_zone in ["hand","library"]:
		controls.manager.match_controller.visibility.set_public_reveal(card.state,not hidden)
	else:
		card.set_face_down(hidden)
	controls.manager.match_controller.refresh()
func build_library(rows: Node, target: OptionButton) -> void:
	controls.button(rows,"Change Deck Back",func() -> void: controls.manager.appearance.sleeves.open(str(target.get_selected_metadata())))
	library_n = number(rows, "Number of cards / Position N")
	(func() -> void: controls.manager.match_controller.library_actions.placement_toggle(rows)).call_deferred()
	var grid := GridContainer.new()
	grid.columns = 3
	rows.add_child(grid)
	controls.button(grid,"Top N → Battlefield",func() -> void: controls.manager.match_controller.library_actions.play_top(str(target.get_selected_metadata()),int(library_n.value)))
	controls.button(grid, "Draw 1", func() -> void: controls.manager.match_controller.draw_card(str(target.get_selected_metadata())))
	controls.button(grid,"PLAYTEST Look Top N",func() -> void: controls.manager.lab.begin(str(target.get_selected_metadata()),int(library_n.value),false))
	controls.button(grid,"PLAYTEST Review Top N (public)",func() -> void: controls.manager.lab.begin(str(target.get_selected_metadata()),int(library_n.value),true))
	controls.button(grid,"PLAYTEST Reveal Until...",func() -> void: controls.manager.lab.begin(str(target.get_selected_metadata()),1,true,true))
	controls.button(grid,"PLAYTEST Exile Top N",func() -> void: controls.manager.match_controller.library_actions.move_top_n(str(target.get_selected_metadata()),int(library_n.value),"exile"))
	controls.button(grid, "Draw N", func() -> void: controls.manager.match_controller.library_actions.draw_n(str(target.get_selected_metadata()), int(library_n.value)))
	controls.button(grid, "Shuffle", func() -> void: controls.manager.match_controller.shuffle_library(str(target.get_selected_metadata())))
	controls.button(grid, "Reveal Top", func() -> void: controls.manager.match_controller.reveal_top(str(target.get_selected_metadata())))
	controls.button(grid, "Reveal Top N…", func() -> void: controls.manager.match_controller.review.open_review(str(target.get_selected_metadata()), int(library_n.value), false))
	controls.button(grid, "View Library · known cards", func() -> void:
		controls.close_panels()
		controls.manager.match_controller.open_library_view(str(target.get_selected_metadata())))
	controls.button(grid, "Search Library…", func() -> void: controls.inspect(str(target.get_selected_metadata()), "library"))
	controls.button(grid, "Mill N", func() -> void: controls.manager.match_controller.library_actions.mill_n(str(target.get_selected_metadata()), int(library_n.value)))
	controls.button(grid, "Mill N from Bottom", func() -> void: controls.manager.match_controller.library_actions.mill_bottom(str(target.get_selected_metadata()), int(library_n.value)))
	controls.button(grid, "Scry N…", func() -> void: controls.manager.match_controller.review.open_review(str(target.get_selected_metadata()), int(library_n.value), true))
	controls.button(grid,"Surveil N…",func() -> void: controls.manager.match_controller.review.open_review(str(target.get_selected_metadata()),int(library_n.value),true,true))
	controls.label(rows, "Selected card → this library")
	var insertions := GridContainer.new()
	insertions.columns = 2
	rows.add_child(insertions)
	card_button(insertions, "Put on top", func() -> void: controls.manager.match_controller.library_actions.put_nth(controls.manager.selected_card, str(target.get_selected_metadata()), 1))
	card_button(insertions, "Put on bottom", func() -> void: controls.manager.match_controller.library_actions.put_nth(controls.manager.selected_card, str(target.get_selected_metadata()), 1, true))
	card_button(insertions, "Put N from top", func() -> void: controls.manager.match_controller.library_actions.put_nth(controls.manager.selected_card, str(target.get_selected_metadata()), int(library_n.value)))
	card_button(insertions, "Put N from bottom", func() -> void: controls.manager.match_controller.library_actions.put_nth(controls.manager.selected_card, str(target.get_selected_metadata()), int(library_n.value), true))
func build_backs(rows: Node) -> void:
	controls.label(rows, "Card backs — custom art is center-cropped to 5:7 and saved locally")
	back_picker = FileDialog.new()
	back_picker.title = "Choose your card back"
	back_picker.access = FileDialog.ACCESS_FILESYSTEM
	back_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	back_picker.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Card back image"])
	controls.add_child(back_picker)
	back_picker.file_selected.connect(func(path: String) -> void:
		var error: String = controls.manager.backs.import_custom(path)
		controls.status.text = "Custom card back saved." if error.is_empty() else error)
	controls.button(rows, "Choose custom card back…", func() -> void:
		controls.close_panels()
		back_picker.popup_centered_ratio(0.8))
	controls.button(rows, "Use default CardLink back", func() -> void:
		var error: String = controls.manager.backs.use_default()
		controls.status.text = "Default card back saved." if error.is_empty() else error)
