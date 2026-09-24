extends Node
## Presentation adapter; reads existing session identity without changing wire state.
var shell: Control
var indicator: Label
var elapsed: float = 0.0
func _ready() -> void:
	indicator = Label.new()
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.add_theme_font_size_override("font_size",12)
	indicator.add_theme_color_override("font_color",Color("91cce8"))
	indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	indicator.z_index = 204
	shell.add_child(indicator)
	indicator.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	indicator.offset_left = -510
	indicator.offset_right = -12
	indicator.offset_top = 50
	indicator.offset_bottom = 68
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.3: return
	elapsed = 0
	refresh()
func refresh() -> void:
	indicator.visible = shell.table_scene != null and not shell.entering
	if not indicator.visible: return
	var table: Node = shell.table_scene.tabletop
	indicator.visible = table.active
	var c: Node = table.match_controller
	indicator.tooltip_text = "Player 1 deck: %s\nPlayer 2 deck: %s" % ["Loaded" if not c.model.players.local.loaded_ids.is_empty() else "Manual sandbox", "Loaded" if not c.model.players.opponent.loaded_ids.is_empty() else "Manual sandbox"]
	var panel: Node = shell.table_scene.get_node_or_null("Network")
	var local_name: String = c.model.players.local.display_name if c.playtest.local_playtest() else shell.preferences.player_name()
	var remote_name: String = c.model.players.opponent.display_name
	if remote_name in ["Opponent",""]: remote_name = "Player 2"
	indicator.text = "OFFLINE PLAYTEST"
	if not c.playtest.local_playtest():
		remote_name = "Opponent"
		indicator.text = "ONLINE · Not connected"
		if panel != null:
			var session: RefCounted = panel.network.session
			if not session.local_peer.display_name.is_empty(): local_name = session.local_peer.display_name
			if session.state == "connected":
				remote_name = session.remote_peer.display_name
				indicator.text = "ONLINE · Connected to " + remote_name.left(32)
			elif panel.rooms.busy: indicator.text = "ONLINE · Connecting…"
			elif panel.rooms.active: indicator.text = "ONLINE · Waiting for your friend"
	if c.model.players.local.display_name != local_name or c.model.players.opponent.display_name != remote_name:
		c.model.players.local.display_name = local_name
		c.model.players.opponent.display_name = remote_name
		table.refresh_match_summary()
		table.extras.refresh_history()
		c.hearts.refresh()
