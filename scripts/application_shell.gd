extends Control
enum Mode { TITLE, ONLINE, OFFLINE_PLAYTEST }
var mode: Mode = Mode.TITLE
var table_selection: Control
var pending_table_mode: Mode = Mode.OFFLINE_PLAYTEST
var custom_table_selected: bool = false
var title_screen: Control
var table_scene: Control
var function_search: Node
var update_service: Node
var updater: Node
var entry_intent: int = 0
var entering: bool = false
var deck_workspace: Control
var privacy_path: String = "user://hidden_zone_settings.cfg"
var bindings = preload("res://scripts/usability/input_bindings.gd").new()
var table_preferences = preload("res://scripts/usability/table_preferences.gd").new()
var recovery: Node
var recovery_directory: String = "user://recovery"
var preferences = preload("res://scripts/frontend/player_preferences.gd").new()
var entry: Node
var presenter: Node
var shared_settings: Node
var departure: Node
var loading: Label
var return_dialog: ConfirmationDialog
var exit_dialog: ConfirmationDialog
func _ready() -> void:
	theme = preload("res://scripts/frontend/frontend_theme.gd").make_theme()
	title_screen = preload("res://scenes/title_screen.tscn").instantiate()
	add_child(title_screen)
	title_screen.online_requested.connect(choose_table.bind(Mode.ONLINE))
	title_screen.offline_requested.connect(choose_table.bind(Mode.OFFLINE_PLAYTEST))
	title_screen.exit_requested.connect(request_exit)
	return_dialog = ConfirmationDialog.new()
	return_dialog.title = "Return to title?"
	return_dialog.dialog_text = "Unsaved match progress will be lost. The current connection will close. Saved decks and your collection are kept."
	return_dialog.ok_button_text = "Return"
	pass # Departure service handles save/discard/cancel.
	add_child(return_dialog)
	exit_dialog = ConfirmationDialog.new()
	exit_dialog.dialog_text = "Exit CardLink? Unsaved match progress will be lost."
	pass # Departure service handles save/discard/cancel.
	add_child(exit_dialog)
	get_tree().auto_accept_quit = false
	entry = preload("res://scripts/frontend/match_entry.gd").new()
	entry.shell = self
	add_child(entry)
	presenter = preload("res://scripts/frontend/frontend_presenter.gd").new()
	presenter.shell = self
	add_child(presenter)
	shared_settings = preload("res://scripts/frontend/frontend_settings.gd").new()
	shared_settings.shell = self
	add_child(shared_settings)
	departure = preload("res://scripts/frontend/match_departure.gd").new()
	departure.shell = self
	add_child(departure)
	departure.build()
	function_search=preload("res://scripts/usability/function_search.gd").new()
	function_search.shell=self
	add_child(function_search)
	build_entry_controls()
	table_selection = preload("res://scripts/custom_table/table_selection.gd").new()
	add_child(table_selection)
	table_selection.hide()
	table_selection.chosen.connect(table_chosen)
	table_selection.back_requested.connect(func() -> void: table_selection.hide(); title_screen.show(); title_screen.focus_preferred())
	table_selection.settings_requested.connect(func() -> void: shared_settings.open())
	table_selection.exit_requested.connect(request_exit)
	loading = Label.new()
	loading.text = "Opening your table…"
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading.z_index = 500
	add_child(loading)
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.hide()
	recovery = preload("res://scripts/usability/recovery_service.gd").new()
	recovery.shell = self
	recovery.storage.directory = recovery_directory
	add_child(recovery)
	recovery.inspect.call_deferred()
	if update_service==null: update_service=preload("res://scripts/updater/update_service.gd").new()
	add_child(update_service)
	updater=preload("res://scripts/updater/update_ui.gd").new();updater.shell=self;updater.service=update_service;add_child(updater)
func choose_table(next: Mode) -> void:
	if entering or mode != Mode.TITLE: return
	entry_intent+=1
	var intent: int=entry_intent
	if next==Mode.ONLINE and updater!=null:
		if not await updater.allow_online(): return
		if entering or mode!=Mode.TITLE or intent!=entry_intent: return
	pending_table_mode = next
	entry.window.hide()
	title_screen.hide()
	table_selection.show()
	table_selection.first.grab_focus()
func table_chosen(custom: bool) -> void:
	custom_table_selected = custom
	table_selection.hide()
	title_screen.show()
	if custom:
		entry.pending_decks.clear()
		entry.pending_path = ""
		entry.setup_ready = false
		enter_mode(pending_table_mode)
	elif pending_table_mode == Mode.ONLINE: enter_mode(pending_table_mode)
	else: entry.offline()
func enter_mode(next: Mode) -> void:
	if entering or mode != Mode.TITLE or next == Mode.TITLE: return
	entry_intent+=1
	var intent: int=entry_intent
	if next==Mode.ONLINE and updater!=null:
		if not await updater.allow_online(): return
		if entering or mode!=Mode.TITLE or intent!=entry_intent: return
	entering = true
	shared_settings.welcome.hide()
	entry.window.hide()
	loading.show()
	await get_tree().process_frame
	await create_tween().tween_property(title_screen,"modulate:a",0.0,0.01 if bool(table_preferences.value("reduce_motion",false)) else 0.22).finished
	title_screen.hide()
	table_scene = preload("res://scenes/main.tscn").instantiate()
	table_scene.app_shell = self
	# main.tscn remains usable on its own for existing tests and development.
	if next == Mode.OFFLINE_PLAYTEST:
		var unused: Node = table_scene.get_node("Network")
		table_scene.remove_child(unused)
		unused.free()
	add_child(table_scene)
	for _i: int in 4: await get_tree().process_frame
	mode = next
	preferences.set_flag("last_offline",next == Mode.OFFLINE_PLAYTEST)
	var playtest: Node = table_scene.tabletop.match_controller.playtest
	playtest.mode_changed.connect(table_mode_changed)
	playtest.set_mode("local_playtest" if next == Mode.OFFLINE_PLAYTEST else "online")
	presenter.refresh()
	var c: Node = table_scene.tabletop.match_controller
	c.model.players.local.display_name = preferences.player_name()
	for player: String in ["local","opponent"]: c.model.players[player].life = entry.starting_life
	if next == Mode.OFFLINE_PLAYTEST and entry.setup_ready:
		for i: int in 2:
			var player: String = "local" if i == 0 else "opponent"
			c.model.players[player].display_name = entry.player_names[i]
			c.model.players[player].life = entry.player_lives[i]
	entry.setup_ready = false
	for player: String in ["local","opponent"]: table_scene.tabletop.battle.reset.start.life[player]=c.model.players[player].life
	c.refresh()
	if preferences.get_flag("hands_hidden"): table_scene.tabletop.shortcuts.toggle_hands()
	departure.path = ""
	departure.caption = "My Match"
	departure.mark_saved()
	if not entry.pending_path.is_empty():
		var read: Dictionary = entry.saves.read_record(entry.pending_path)
		if not read.has("error"):
			var data: Dictionary = read.record.data.duplicate(true)
			if not data.has("local_tabletop"): data.local_tabletop = {}
			data.local_tabletop.opponent_mode = "local_playtest"
			var restored: Dictionary = table_scene.tabletop.persistence.restore_match(data)
			table_scene.tabletop.controls.status.text = "Opened local copy." if not restored.has("error") else "Could not load this match; your saved file is unchanged."
			if int(restored.get("missing_images",0)) > 0: table_scene.tabletop.controls.status.text = "Opened with missing-image placeholders. Your saved file is unchanged."
			if not restored.has("error"):
				# Resume copies do not overwrite the original online snapshot.
				departure.caption = str(read.record.name) + " · Local copy"
				departure.mark_saved()
		entry.pending_path = ""
	for i: int in entry.pending_decks.size():
		if entry.pending_decks[i].is_empty(): continue
		var result: Dictionary = c.load_deck(entry.pending_decks[i],true,"local" if i == 0 else "opponent")
		if result.has("error"): table_scene.tabletop.controls.status.text = "Deck could not be loaded. Choose another deck from Menu → Deck / Library."
	entry.pending_decks.clear()
	if not entry.recovery_data.is_empty():
		var data: Dictionary = entry.recovery_data
		if not data.has("local_tabletop"): data.local_tabletop = {}
		data.local_tabletop.opponent_mode = "local_playtest"
		var result: Dictionary = table_scene.tabletop.persistence.restore_match(data)
		table_scene.tabletop.controls.status.text = "Recovered local copy; online peers were not reconnected." if not result.has("error") else "Recovery could not load. The original recovery copy is kept."
		recovery.preserve_failed = result.has("error")
		entry.recovery_data = {}
		departure.caption = "Recovered Match"
		departure.mark_saved()
		if int(result.get("missing_images",0)) > 0: table_scene.tabletop.controls.status.text += " Missing images use placeholders."
	var records: Control = table_scene.tabletop.controls.match_records
	records.record_saved.connect(func(path: String) -> void: departure.mark_saved(path))
	records.record_loaded.connect(func(path: String) -> void: departure.mark_saved(path))
	if custom_table_selected and not table_scene.tabletop.custom_table.enabled:
		table_scene.tabletop.custom_table.start_blank()
	if next == Mode.ONLINE: table_scene.open_network_panel()
	loading.hide()
	entering = false
	table_scene.tabletop.undo.invalidate()
	recovery.attach()
	presenter.refresh()
func table_mode_changed(value: String) -> void:
	if table_scene == null: return
	mode = Mode.OFFLINE_PLAYTEST if value == "local_playtest" else Mode.ONLINE
	if mode == Mode.ONLINE: table_scene.ensure_network()
	else:
		var network: Node = table_scene.get_node_or_null("Network")
		if network != null and network.network.available() and not network.rooms.active and not network.rooms.busy:
			table_scene.tabletop.match_controller.public_sync = null
			table_scene.remove_child(network)
			network.queue_free()
func request_return() -> void:
	if table_scene != null and not entering: departure.request("return")
func return_to_title() -> void:
	if entering: return
	dispose_table()
	mode = Mode.TITLE
	custom_table_selected = false
	table_selection.hide()
	title_screen.modulate.a = 0
	title_screen.show()
	create_tween().tween_property(title_screen,"modulate:a",1.0,0.01 if bool(table_preferences.value("reduce_motion",false)) else 0.22)
	entry.refresh_resume()
	title_screen.focus_preferred()
func dispose_table() -> void:
	if recovery != null and table_scene != null: recovery.discard()
	title_screen.settings.hide()
	shared_settings.helper.hide()
	if table_scene == null: return
	var network: Node = table_scene.get_node_or_null("Network")
	if network != null: network.rooms.cancel()
	table_scene.tabletop.match_controller.hand_window.restore_hand()
	table_scene.tabletop.set_active(false)
	table_scene.hide()
	table_scene.queue_free()
	table_scene = null
func request_exit() -> void:
	if entering: return
	if table_scene != null and not entering: departure.request("exit")
	else: exit_now()
func exit_now() -> void:
	dispose_table()
	get_tree().quit()
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: request_exit()

func build_entry_controls() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(385,320)
	row.size = Vector2(902,42)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_screen.composition.add_child(row)
	for item: Array in [["Deck Builder",open_deck_workspace],["New Match",entry.new_match],["Resume Match",entry.resume_match],["Controls",func() -> void: shared_settings.open_help()]]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(185,40)
		button.pressed.connect(item[1])
		row.add_child(button)
		if item[0] == "Resume Match": entry.resume_button = button
	entry.refresh_resume()

func open_deck_workspace() -> void:
	if entering or mode!=Mode.TITLE or is_instance_valid(deck_workspace): return
	shared_settings.welcome.hide();title_screen.hide()
	deck_workspace=preload("res://scripts/battle/deck_workspace.gd").new()
	add_child(deck_workspace)
	deck_workspace.closed.connect(func() -> void:
		deck_workspace.queue_free();deck_workspace=null
		title_screen.show();title_screen.focus_preferred())
