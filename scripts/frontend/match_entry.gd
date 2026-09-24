extends Node
## Entry menus use the same validated, atomic match/deck storage as the tabletop.
var player_names: Array[String] = []
var player_lives: Array[int] = []
var setup_ready: bool = false
var shell: Control
var saves = preload("res://scripts/match_save_storage.gd").new()
var decks = preload("res://scripts/deck_storage.gd").new()
var window: Window
var rows: VBoxContainer
var resume_button: Button
var save_picker: OptionButton
var message: Label
var deck_pickers: Array[OptionButton] = []
var offline_summary: Label
var recovery_data: Dictionary = {}
var starting_life: int = 40
var deck_preferences = preload("res://scripts/usability/deck_preferences.gd").new()
var pending_path: String = ""
var pending_decks: Array[Dictionary] = []
func _ready() -> void:
	window = Window.new()
	window.theme = shell.theme
	window.visible = false
	window.size = Vector2i(600,550)
	window.close_requested.connect(window.hide)
	window.window_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"): window.hide())
	add_child(window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,18)
	window.add_child(margin)
	rows = VBoxContainer.new()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	scroll.add_child(rows)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preload("res://scripts/frontend/frontend_theme.gd").skin_window(window)
func clear(title: String) -> void:
	for child: Node in rows.get_children(): rows.remove_child(child); child.queue_free()
	window.title = title
	window.popup_centered_clamped(Vector2i(600,550),0.9)
func label(text: String) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(item)
	return item
func button(text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.pressed.connect(action)
	rows.add_child(item)
	return item
func refresh_resume() -> void:
	if resume_button != null: resume_button.disabled = saves.list_records().is_empty()
func new_match() -> void:
	setup_ready = false
	pending_path = ""
	pending_decks.clear()
	clear("New Match")
	label("Your cards. Your table. Choose how to play.")
	build_starting_life()
	button("Online · Play with a friend",func() -> void: start(shell.Mode.ONLINE))
	button("Offline Playtest · Control both players",offline)
	button("Back",window.hide)
func offline() -> void:
	deck_preferences = preload("res://scripts/usability/deck_preferences.gd").new(deck_preferences.path)
	pending_path = ""
	pending_decks.clear()
	clear("New Offline Playtest")
	label("One person controls both players. Choose your names, decks and starting life.")
	player_names = [shell.preferences.player_name(),"Player 2"]
	player_lives = [starting_life,starting_life]
	setup_ready = false
	deck_pickers.clear()
	for player: String in ["Player 1","Player 2"]:
		var slot: int = deck_pickers.size()
		label(player.to_upper())
		var name_field := LineEdit.new()
		name_field.max_length = 48
		name_field.placeholder_text = player+" name"
		name_field.text = player_names[slot]
		name_field.text_changed.connect(func(value: String) -> void: player_names[slot] = preload("res://scripts/frontend/player_preferences.gd").clean_name(value))
		rows.add_child(name_field)
		label("Deck")
		var picker := OptionButton.new()
		picker.add_item("No deck · Manual sandbox")
		picker.set_item_metadata(0,{})
		var choices: Array = decks.list_decks()
		choices.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return deck_preferences.rank(str(a.data.get("deck_id",""))) < deck_preferences.rank(str(b.data.get("deck_id",""))))
		for row: Dictionary in choices:
			if not str(row.error).is_empty(): continue
			picker.add_item(deck_preferences.caption(row.data))
			picker.set_item_metadata(picker.item_count-1,row.data)
		rows.add_child(picker)
		deck_pickers.append(picker)
		button("☆ Toggle favorite for "+player,func() -> void:
			var selected: Dictionary = picker.get_item_metadata(picker.selected)
			if not selected.is_empty():
				deck_preferences.toggle(selected.deck_id)
				picker.set_item_text(picker.selected,deck_preferences.caption(selected)))
		picker.item_selected.connect(func(_id: int) -> void: refresh_offline_summary())
		label("Starting life")
		var life := SpinBox.new()
		life.min_value = 1
		life.max_value = 1000000
		life.value = player_lives[slot]
		life.value_changed.connect(func(value: float) -> void: player_lives[slot] = int(value))
		rows.add_child(life)
	offline_summary = label("")
	refresh_offline_summary()
	button("Start Playtest",func() -> void:
		setup_ready = true
		for picker: OptionButton in deck_pickers: pending_decks.append(picker.get_item_metadata(picker.selected))
		start(shell.Mode.OFFLINE_PLAYTEST))
	button("Resume Playtest…",resume_match).disabled = saves.list_records().is_empty()
	button("Back",new_match)
func resume_match() -> void:
	setup_ready = false
	clear("Resume Match")
	label("Online saves open as a local offline copy. This does not reconnect a previous room or recover cards held only by your friend.")
	save_picker = OptionButton.new()
	save_picker.clip_text = true
	rows.add_child(save_picker)
	for row: Dictionary in saves.list_records():
		var data: Dictionary = row.record.get("data",{})
		var local_state: Variant = data.get("local_tabletop",{})
		var mode: String = "Online / older save · local copy"
		if local_state is Dictionary and local_state.get("opponent_mode","") == "local_playtest": mode = "Offline Playtest"
		var title: String = str(row.name).left(80) if str(row.error).is_empty() else "Unreadable save"
		save_picker.add_item("%s · %s · %s" % [title,mode,str(row.record.get("saved_at","Date unavailable")).replace("T"," ")])
		save_picker.set_item_metadata(save_picker.item_count-1,row.path)
	message = label("")
	button("Open Local Copy",resume_selected).disabled = save_picker.item_count == 0
	button("Cancel",window.hide)
func resume_selected() -> void:
	if save_picker.selected < 0: return
	pending_path = str(save_picker.get_item_metadata(save_picker.selected))
	var result: Dictionary = saves.read_record(pending_path)
	var error: String = str(result.get("error",""))
	if error.is_empty(): error = preload("res://scripts/match_snapshot.gd").validate(result.record.data)
	if not error.is_empty():
		message.text = "This match could not be opened. The saved file has been kept unchanged."
		pending_path = ""
		return
	pending_decks.clear()
	start(shell.Mode.OFFLINE_PLAYTEST)
func start(mode: int) -> void:
	window.hide()
	shell.enter_mode(mode)

func refresh_offline_summary() -> void:
	if not is_instance_valid(offline_summary): return
	var parts: PackedStringArray = []
	for i: int in deck_pickers.size():
		parts.append("Player %d: %s" % [i+1,"Deck ready to load" if deck_pickers[i].selected > 0 else "Manual sandbox"])
	offline_summary.text = " · ".join(parts)

func build_starting_life() -> void:
	label("Starting life · Presets or custom value")
	var row := HBoxContainer.new()
	rows.add_child(row)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 1000000
	amount.value = starting_life
	amount.value_changed.connect(func(value: float) -> void: starting_life = int(value))
	row.add_child(amount)
	for preset: int in [20,30,40]:
		var item := Button.new()
		item.text = str(preset)
		item.pressed.connect(func() -> void: amount.value = preset)
		row.add_child(item)
