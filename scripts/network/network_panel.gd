extends Node
## UI adapter depends only on the connection manager, never the match model.
var preparation: Node
var network_tools: VBoxContainer
var recovery_notice: VBoxContainer
var connection_buttons: HBoxContainer
var rooms: Node
var internet_status: Label
var room_code: LineEdit
var diagnostics_label: Label
var advanced: VBoxContainer
var internet_host: Button
var internet_join: Button
var internet_cancel: Button
var gameplay: Node
var gameplay_status: Label
var sync_button: Button
var start_match_button: Button
var sync_log: RichTextLabel
var starting_life: SpinBox
var readiness: Label
var prep_box: VBoxContainer
var network: Node
var window: Window
var address: LineEdit
var port: SpinBox
var display_name: LineEdit
var status: Label
var identities: Label
var session_label: Label
var log_view: RichTextLabel
var host_button: Button
var join_button: Button
var disconnect_button: Button
func _ready() -> void:
	network = preload("res://scripts/network/network_manager.gd").new()
	add_child(network)
	rooms = preload("res://scripts/network/room_session.gd").new()
	rooms.network = network
	add_child(rooms)
	window = Window.new()
	window.title = "Online Match"
	window.visible = false
	window.size = Vector2i(560, 680)
	window.transient = true
	window.close_requested.connect(window.hide)
	add_child(window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	window.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	label(rows, "Connect → Choose a deck → Start playing\nYour live hand and library order remain private.")
	display_name = LineEdit.new()
	display_name.placeholder_text = "Your display name"
	display_name.text = preload("res://scripts/frontend/player_preferences.gd").new().player_name()
	display_name.max_length = 48
	rows.add_child(display_name)
	prep_box = VBoxContainer.new()
	rows.add_child(prep_box)
	prep_box.hide()
	readiness = label(prep_box,"Choose a deck from Menu → Deck / Library, or play an empty sandbox.")
	room_code = LineEdit.new()
	room_code.placeholder_text = "Room code · ABCD-1234"
	room_code.max_length = 9
	rows.add_child(room_code)
	var internet_buttons := HBoxContainer.new()
	connection_buttons = internet_buttons
	rows.add_child(internet_buttons)
	internet_host = button(internet_buttons, "Host Game", func() -> void: connect_if_online(func() -> void: rooms.host_room(display_name.text)))
	internet_join = button(internet_buttons, "Join Game", func() -> void: connect_if_online(func() -> void: rooms.join_room(room_code.text, display_name.text)))
	internet_cancel = button(internet_buttons, "Cancel Host / Disconnect", rooms.cancel)
	internet_status = label(rows, "")
	var retry_connection: Button = button(rows, "Retry connection", func() -> void: connect_if_online(func() -> void: rooms.retry(display_name.text)))
	button(rows, "Copy room code", func() -> void: DisplayServer.clipboard_set(rooms.code))
	diagnostics_label = label(rows, "")
	var details := VBoxContainer.new()
	network_tools = details
	button(rows, "Advanced Network Tools", func() -> void: details.visible = not details.visible)
	rows.add_child(details)
	details.hide()
	retry_connection.reparent(details)
	recovery_notice = VBoxContainer.new()
	rows.add_child(recovery_notice)
	recovery_notice.hide()
	label(recovery_notice,"CONNECTION LOST\nReconnect to continue. Your local cards are preserved.")
	button(recovery_notice,"Retry Now",simple_reconnect)
	button(recovery_notice,"Continue Offline",func() -> void: gameplay.recovery.continue_offline(); window.hide())
	button(recovery_notice,"Leave Match",func() -> void: gameplay.recovery.leave(); window.hide())
	diagnostics_label.reparent(details)
	label(details, "Service URL is set in config/network.cfg.\nDirect TCP first; outbound TCP/TLS relay fallback.\nSTUN / WebRTC provider is not installed in this build.")
	advanced = VBoxContainer.new()
	details.add_child(advanced)
	label(advanced, "Advanced LAN · IP and port")
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.max_length = 64
	advanced.add_child(address)
	var port_row := HBoxContainer.new()
	advanced.add_child(port_row)
	var port_label: Label = label(port_row, "TCP port")
	port_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 27860
	port.custom_minimum_size.x = 120
	port_row.add_child(port)
	var buttons := HBoxContainer.new()
	advanced.add_child(buttons)
	host_button = button(buttons, "Host Game", func() -> void: connect_if_online(func() -> void: network.host_game(int(port.value), display_name.text)))
	join_button = button(buttons, "Join Game", func() -> void: connect_if_online(func() -> void: network.join_game(address.text, int(port.value), display_name.text)))
	disconnect_button = button(buttons, "Disconnect", network.disconnect_session)
	status = label(details, "")
	identities = label(details, "")
	session_label = label(details, "")
	label(details, "Connection log · no card or deck information")
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = false
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size.y = 120
	log_view.scroll_following = true
	details.add_child(log_view)
	button(rows, "Close panel (keep connection)", window.hide)
	rooms.changed.connect(refresh)
	network.changed.connect(refresh)
	network.log_changed.connect(func() -> void: log_view.text = "\n".join(network.debug_log))
	gameplay = preload("res://scripts/network/network_action_router.gd").new()
	gameplay.network = network
	add_child(gameplay)
	setup_gameplay.call_deferred()
	gameplay_status = label(details, "Public tabletop is off.")
	button(details, "Share Tabletop (both players)", gameplay.start)
	button(details, "Resync public tabletop", func() -> void: gameplay.resync.request())
	gameplay.changed.connect(func() -> void: gameplay_status.text = gameplay.status)
	var sync_status: Label = label(details, "Card Sync: not checked.")
	gameplay.card_sync.changed.connect(func() -> void:
		refresh_sync_buttons()
		sync_status.text = gameplay.card_sync.status
		if gameplay.card_sync.pending or gameplay.card_sync.status.begins_with("Card Sync interrupted"): prep_box.show())
	sync_button = button(details, "Sync Cards / Retry Sync", func() -> void:
		if preparation.auto_setup: preparation.retry()
		else: gameplay.card_sync.decide("sync"))
	button(details, "Continue With Placeholders", func() -> void: preparation.placeholders())
	label(details,"My starting life (manual; each player chooses)")
	starting_life = SpinBox.new()
	starting_life.min_value = 1
	starting_life.max_value = 1000000
	starting_life.value = 40
	details.add_child(starting_life)
	button(details,"Apply my starting life",apply_starting_life)
	preparation = preload("res://scripts/network/online_preparation.gd").new()
	preparation.panel = self
	add_child(preparation)
	preparation.choose = button(prep_box, "Choose / Load Deck", func() -> void: window.hide(); get_parent().open_deck_builder())
	start_match_button = button(prep_box, "START MATCH", func() -> void:
		if preparation.auto_setup: preparation.start_match()
		else: apply_starting_life(); gameplay.card_sync.decide("start"))
	preparation.build_ui(prep_box)
	sync_log = RichTextLabel.new()
	sync_log.bbcode_enabled = false
	sync_log.custom_minimum_size.y = 100
	sync_log.scroll_following = true
	details.add_child(sync_log)
	var recovery_box := VBoxContainer.new()
	details.add_child(recovery_box)
	var recovery_status: Label = label(recovery_box, gameplay.recovery.status)
	gameplay.recovery.changed.connect(func() -> void: recovery_status.text = gameplay.recovery.status)
	var transfer_status: Label = label(recovery_box, gameplay.transactions.status)
	gameplay.transactions.changed.connect(func() -> void: transfer_status.text = gameplay.transactions.status)
	button(recovery_box,"Reconnect / Retry",gameplay.recovery.reconnect)
	button(recovery_box,"Continue Offline",gameplay.recovery.continue_offline)
	button(recovery_box,"Leave Match",gameplay.recovery.leave)
	refresh_sync_buttons()
	refresh()
func refresh_sync_buttons() -> void:
	if sync_button == null or start_match_button == null: return
	var sync: Node = gameplay.card_sync
	sync_button.disabled = sync.running or sync.requested
	sync_button.text = "Syncing Cards..." if sync_button.disabled else "Sync Cards / Retry Sync"
	if sync.status.begins_with("CARD SYNC COMPLETE"): sync_button.text = "Card Sync Complete / Check Again"
	if preparation != null and preparation.auto_setup:
		start_match_button.disabled = not preparation.can_start()
	else:
		start_match_button.disabled = not sync.checked or sync.running or sync.requested or sync.catalog == null
		if not start_match_button.disabled: start_match_button.disabled = sync.inspect_required().missing > 0
	if sync_log != null: sync_log.text = "\n".join(sync.events)
func setup_gameplay() -> void:
	gameplay.table = get_parent().tabletop
	if get_parent().app_shell != null: starting_life.value = get_parent().app_shell.entry.starting_life
	network.changed.connect(func() -> void:
		if gameplay.table.undo != null: gameplay.table.undo.invalidate("Connection changed; undo history cleared."))
func label(parent: Node, text: String) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item
func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.pressed.connect(action)
	parent.add_child(item)
	return item
func refresh() -> void:
	var s: RefCounted = network.session
	if internet_status == null:
		return
	internet_status.text = rooms.status
	if s.state == "connected": internet_status.text = "Connected"
	connection_buttons.visible = s.state != "connected"
	display_name.visible = s.state != "connected"
	room_code.visible = s.state != "connected"
	if rooms.busy: internet_status.text += " · Please wait…"
	diagnostics_label.text = rooms.diagnostics.text()
	internet_host.disabled = rooms.active or rooms.busy or not network.available()
	internet_join.disabled = internet_host.disabled
	internet_cancel.disabled = not rooms.active and not rooms.busy
	room_code.editable = not rooms.active and not rooms.busy
	prep_box.visible = s.state == "connected" or (gameplay != null and gameplay.card_sync.status.begins_with("Card Sync interrupted"))
	status.text = "%s — %s" % [s.state.capitalize(), s.status]
	identities.text = "You: %s\nFriend: %s" % [display_name.text if s.local_peer.display_name.is_empty() else s.local_peer.display_name, "Waiting for connection" if s.remote_peer.display_name.is_empty() else s.remote_peer.display_name]
	if not s.local_peer.player_id.is_empty(): identities.text += "\n" + s.local_peer.player_id.replace("player_","Player ") + " · " + s.local_peer.role.capitalize()
	session_label.text = "Protocol %d · CardLink %s\nSession: %s" % [network.protocol_version, network.Codec.APP_VERSION, s.session_id if not s.session_id.is_empty() else "None"]
	host_button.disabled = rooms.active or rooms.busy or not network.available()
	join_button.disabled = host_button.disabled
	disconnect_button.disabled = s.state == "disconnected" or s.state == "disconnecting"
	display_name.editable = network.available()
	address.editable = network.available()
	port.editable = network.available()
func open_panel() -> void:
	refresh()
	window.popup_centered_clamped(Vector2i(560, 680), 0.9)

func connect_if_online(action: Callable) -> void:
	if gameplay != null and gameplay.table != null and gameplay.table.match_controller.playtest.local_playtest():
		internet_status.text = "Choose Online Opponent in Menu → Hand before connecting."
		return
	action.call()

func _process(_delta: float) -> void:
	refresh_sync_buttons()
	if recovery_notice != null and gameplay != null:
		recovery_notice.visible = gameplay.recovery.suspended or (preparation != null and not preparation.session.is_empty() and network.session.state != "connected")
	if readiness == null or not window.visible or gameplay == null or gameplay.table == null: return
	var c: Node = gameplay.table.match_controller
	var local: RefCounted = c.model.players.local
	var remote_ready: bool = c.hidden_count("opponent","library") + c.hidden_count("opponent","hand") > 0
	readiness.text = "You: %s · Opponent: %s\nYour Deck: %s\nOpponent Deck: %s" % ["Connected" if network.session.state == "connected" else "Waiting", "Connected" if network.session.state == "connected" else "Waiting", c.deck_name if not local.loaded_ids.is_empty() else "Choose Deck", "Ready" if remote_ready or not gameplay.card_sync.remote.is_empty() else "Waiting"]

func apply_starting_life() -> void:
	if gameplay.table == null: return
	var c: Node = gameplay.table.match_controller
	c.change_life("local",int(starting_life.value)-c.model.players.local.life)

func simple_reconnect() -> void:
	if not gameplay.recovery.context.is_empty(): gameplay.recovery.reconnect()
	elif rooms.active or not rooms.last_code.is_empty(): rooms.retry(display_name.text)
	elif network.available():
		if preparation.role == "host": network.host_game(network.last_port,display_name.text)
		else: network.join_game(network.last_address,network.last_port,display_name.text)
