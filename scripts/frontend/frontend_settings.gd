extends Node
var shell: Control
var name_edit: LineEdit
var auto_approve: CheckBox
var hide_hands: CheckBox
var layout_button: Button
var helper: Window
var settings_content: Control
var controls_text: Label
var key_bindings: Window
var welcome: AcceptDialog
var no_again: CheckBox
func _ready() -> void:
	var title: Control = shell.title_screen
	var settings: Window = title.settings
	settings.reparent(shell)
	settings.title = "Settings"
	settings.size = Vector2i(480,580)
	var rows: VBoxContainer = settings.get_child(0)
	rows.size = Vector2(440,540)
	name_edit = LineEdit.new()
	name_edit.max_length = 48
	name_edit.placeholder_text = "Player name"
	name_edit.text = shell.preferences.player_name()
	rows.add_child(name_edit)
	rows.move_child(name_edit,0)
	name_edit.text_submitted.connect(func(_value: String) -> void: save())
	auto_approve = CheckBox.new()
	auto_approve.text = "Auto-approve hidden-zone requests"
	rows.add_child(auto_approve)
	rows.move_child(auto_approve,1)
	var privacy := ConfigFile.new()
	privacy.load(shell.privacy_path)
	auto_approve.button_pressed = bool(privacy.get_value("privacy","auto_approve",false))
	hide_hands = CheckBox.new()
	hide_hands.text = "Start with hands hidden"
	hide_hands.button_pressed = shell.preferences.get_flag("hands_hidden")
	rows.add_child(hide_hands)
	rows.move_child(hide_hands,2)
	var save_button := Button.new()
	save_button.text = "Save preferences"
	save_button.pressed.connect(save)
	rows.add_child(save_button)
	rows.move_child(save_button,3)
	layout_button = Button.new()
	layout_button.text = "Table layout & display..."
	layout_button.tooltip_text = "Layout presets and UI text scale are available inside a table."
	layout_button.pressed.connect(func() -> void:
		title.close_settings()
		if shell.table_scene != null: shell.table_scene.tabletop.controls.open_panel("Layout"))
	rows.add_child(layout_button)
	rows.move_child(layout_button,rows.get_child_count()-2)
	var profile_label := Label.new()
	profile_label.text = "Player name"
	rows.add_child(profile_label)
	rows.move_child(profile_label,0)
	title.settings_status.text = "Card back"
	title.backs.changed.connect(func() -> void:
		if shell.table_scene != null: shell.table_scene.tabletop.backs.reload())
	key_bindings = preload("res://scripts/usability/key_bindings_ui.gd").new()
	key_bindings.bindings = shell.bindings
	shell.add_child(key_bindings)
	var key_button := Button.new()
	key_button.text = "Key Bindings..."
	key_button.pressed.connect(func() -> void: key_bindings.popup_centered_clamped(Vector2i(640,560),0.95))
	rows.add_child(key_button)
	var integrations := Button.new()
	integrations.text="Integrations / Optional Catalog..."
	integrations.pressed.connect(func() -> void: preload("res://scripts/integrations/integration_hub.gd").open(shell,2))
	rows.add_child(integrations)
	var about_button := Button.new()
	about_button.text = "About CardLink / Beta Information…"
	about_button.pressed.connect(func() -> void: preload("res://scripts/frontend/about_cardlink.gd").open(shell))
	rows.add_child(about_button)
	var update_button:=Button.new();update_button.text="Check for Updates"
	update_button.pressed.connect(func() -> void:
		if shell.updater!=null:
			title.close_settings();shell.updater.open();shell.update_service.check_now())
	rows.add_child(update_button)
	shell.table_preferences.build(rows,Callable())
	var scroll := ScrollContainer.new()
	settings.add_child(scroll)
	settings_content = scroll
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 14
	scroll.offset_top = 14
	scroll.offset_right = -14
	scroll.offset_bottom = -14
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.reparent(scroll)
	rows.position = Vector2.ZERO
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helper = Window.new()
	helper.visible = false
	helper.title = "Controls"
	helper.size = Vector2i(640,570)
	helper.close_requested.connect(helper.hide)
	shell.add_child(helper)
	var help_scroll := ScrollContainer.new()
	helper.add_child(help_scroll)
	help_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var help_rows := VBoxContainer.new()
	help_scroll.add_child(help_rows)
	controls_text = Label.new()
	controls_text.text = shell.bindings.help_text()
	help_rows.add_child(controls_text)
	shell.bindings.changed.connect(func() -> void: controls_text.text = shell.bindings.help_text())
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(helper.hide)
	help_rows.add_child(close_button)
	welcome = AcceptDialog.new()
	welcome.title = "Welcome to CardLink"
	welcome.dialog_text = "Import custom cards. Build or load a deck.\nRight-click cards for actions and libraries for deck tools.\nPlay online with a friend, or try both sides offline.\n\nYour table, your rules."
	welcome.ok_button_text = "Got it"
	var welcome_rows := VBoxContainer.new()
	welcome.add_child(welcome_rows)
	var introduction := Label.new()
	introduction.text = "Welcome to CardLink\nLeft drag - Move | Right click - Actions\n"+shell.bindings.caption("draw")+" - Draw | "+shell.bindings.caption("shuffle")+" - Shuffle\n"+shell.bindings.caption("hands")+" - Hands | "+shell.bindings.caption("layout")+" - Layout | "+shell.bindings.caption("end_turn")+" - End Turn\nFull Controls and Key Bindings are in Settings."
	welcome.dialog_text = ""
	welcome_rows.add_child(introduction)
	no_again = CheckBox.new()
	no_again.text = "Don't show again"
	welcome_rows.add_child(no_again)
	shell.add_child(welcome)
	welcome.canceled.connect(func() -> void: shell.preferences.set_flag("welcome_seen",true))
	welcome.confirmed.connect(func() -> void:
		shell.preferences.set_flag("welcome_seen",true)
		shell.preferences.set_flag("hide_welcome",no_again.button_pressed))
	if not shell.preferences.get_flag("welcome_seen") and not shell.preferences.get_flag("hide_welcome"):
		welcome.popup_centered.call_deferred(Vector2i(540,250))
	for surface: Window in [settings,helper,key_bindings,welcome]: preload("res://scripts/frontend/frontend_theme.gd").skin_window(surface)
func open() -> void:
	layout_button.disabled = shell.table_scene == null
	name_edit.text = shell.preferences.player_name()
	var panel: Node = shell.table_scene.get_node_or_null("Network") if shell.table_scene != null else null
	if panel != null:
		auto_approve.set_pressed_no_signal(panel.gameplay.hidden.auto_approve)
	name_edit.editable = panel == null or panel.network.available()
	name_edit.tooltip_text = "Disconnect before changing your session name." if not name_edit.editable else "Your display name | up to 48 characters"
	shell.title_screen.backs.reload()
	shell.title_screen.back_preview.texture = shell.title_screen.backs.texture()
	shell.title_screen.settings.popup_centered_clamped(Vector2i(480,580),0.95)
	var content: Control = settings_content
	if bool(shell.table_preferences.value("reduce_motion",false)):
		content.modulate.a = 1
		return
	content.modulate.a = 0
	create_tween().tween_property(content,"modulate:a",1.0,0.1)
func save() -> void:
	var error: Error = shell.preferences.save_name(name_edit.text)
	if error == OK: error = shell.preferences.set_flag("hands_hidden",hide_hands.button_pressed)
	var privacy := ConfigFile.new()
	privacy.load(shell.privacy_path)
	privacy.set_value("privacy","auto_approve",auto_approve.button_pressed)
	if error == OK: error = privacy.save(shell.privacy_path)
	name_edit.text = shell.preferences.player_name()
	if shell.table_scene != null:
		shell.table_scene.tabletop.battle.nickname(shell.preferences.player_name())
		var c: Node = shell.table_scene.tabletop.match_controller
		if c.hands_hidden != hide_hands.button_pressed: shell.table_scene.tabletop.shortcuts.toggle_hands()
		var panel: Node = shell.table_scene.get_node_or_null("Network")
		if panel != null:
			if panel.network.available(): panel.display_name.text = shell.preferences.player_name()
			panel.gameplay.hidden.set_auto_approve(auto_approve.button_pressed)
			panel.gameplay.hidden.ui.auto_approve.set_pressed_no_signal(auto_approve.button_pressed)
	shell.title_screen.settings_status.text = "Preferences saved." if error == OK else "Could not save preferences. Please try again."
	shell.presenter.refresh()

func open_help() -> void:
	controls_text.text = shell.bindings.help_text()
	helper.popup_centered_clamped(Vector2i(640,570),0.95)
