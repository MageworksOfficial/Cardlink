extends Node
## Local contextual UI, kept separate from card controls and game state.
var manager: Node
var tools: RefCounted
var corner: PopupMenu
var field_menu: PopupMenu
var tools_window: Window
var history_window: Window
var counter_window: Window
var token_editor: Window
var history_text: RichTextLabel
var turn_label: Label
var result_label: Label
var dice_input: LineEdit
var calculator_input: LineEdit
var counter_name: LineEdit
var counter_value: SpinBox
var editing_counter: String = ""
var counters: Array[Control] = []
var field_point: Vector2 = Vector2(400, 250)
var toast: Label
var last_status: String = ""
var toast_remaining: float = 0.0
const FUNCTIONS = ["Table", "Search / Functions (Ctrl+F)", "Deck / Library", "Import / Collection", "Match", "Tools", "Settings", "Controls Help", "Multiplayer / Network", "Match History", "End Turn", "Switch Perspective", "Reset View", "Reset Table Layout", "Save Match", "Load Match", "Undo", "Table Components", "Return to Title", "Exit"]
func _ready() -> void:
	tools = preload("res://scripts/match_tools.gd").new(manager.match_controller)
	corner = PopupMenu.new()
	for caption: String in FUNCTIONS:
		corner.add_item(caption)
	corner.id_pressed.connect(func(id: int) -> void: choose(FUNCTIONS[id]))
	add_child(corner)
	field_menu = PopupMenu.new()
	for caption: String in ["Create Token", "Create Counter", "Add Custom Zone", "Reset View", "Tools", "Match History", "End Turn", "Add Table Component", "Battlefield Background", "Edit Background"]:
		field_menu.add_item(caption)
	field_menu.id_pressed.connect(field_action)
	add_child(field_menu)
	token_editor = preload("res://scripts/token_editor.gd").new()
	token_editor.manager = manager
	add_child(token_editor)
	build_tools()
	build_history()
	build_counter_editor()
	toast = Label.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 220
	toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast.offset_left = 14
	toast.offset_right = -115
	toast.offset_top = -35
	toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toast.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast.add_theme_constant_override("shadow_outline_size", 5)
	manager.get_parent().add_child(toast)
	toast.hide()
func _process(delta: float) -> void:
	if toast == null:
		return
	if manager.controls.status.text != last_status:
		last_status = manager.controls.status.text
		toast.text = last_status
		toast_remaining = 6.0
	toast_remaining -= delta
	toast.visible = manager.active and toast_remaining > 0.0
	toast.modulate.a = clampf(toast_remaining,0,1)
func make_window(caption: String, extent: Vector2i) -> Window:
	var window := Window.new()
	window.title = caption
	window.size = extent
	window.visible = false
	window.close_requested.connect(window.hide)
	add_child(window)
	return window
func rows(window: Window) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(column)
	return column
func add_button(parent: Node, caption: String, action: Callable) -> void:
	manager.controls.button(parent, caption, action)
func open_corner() -> void:
	manager.controls.close_panels()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	corner.position = Vector2i(maxf(0, screen.x - 220), 52)
	corner.popup()
func open_field(point: Vector2) -> void:
	if not manager.active:
		return
	manager.controls.close_panels()
	manager.match_controller.hide_preview()
	for card: Control in manager.cards:
		card.hover_preview.hide()
	field_point = manager.world.get_global_transform().affine_inverse() * point
	field_menu.position = Vector2i(point)
	field_menu.popup()
func field_action(id: int) -> void:
	match id:
		0: token_editor.open_token(null, field_point)
		1: open_counter(create_counter(field_point))
		2:
			if manager.custom_table != null and manager.custom_table.enabled:
				manager.custom_table.editor.begin_placement("zone")
				return
			manager.add_zone({"display_name": "Custom Zone", "zone_type": "custom_zone", "player_id": "local", "position": field_point})
		3: manager.view.reset_view()
		4: tools_window.popup_centered()
		5: toggle_history()
		6: manager.match_controller.end_turn()
		7: open_components()
		8: manager.appearance.open()
		9: manager.appearance.toggle_edit()
func choose(caption: String) -> void:
	match caption:
		"Table":
			var submenu:=PopupMenu.new();add_child(submenu);submenu.add_item("Battlefield Background");submenu.add_item("Edit Background");submenu.id_pressed.connect(func(id: int) -> void:
				if id==0: manager.appearance.open()
				else: manager.appearance.toggle_edit())
			submenu.popup_hide.connect(submenu.queue_free);submenu.position=corner.position;submenu.popup()
		"Search / Functions (Ctrl+F)":
			if manager.get_parent().app_shell!=null: manager.get_parent().app_shell.function_search.open.call_deferred()
		"Table Components": open_components()
		"Deck / Library": manager.controls.open_panel("Library")
		"Settings": manager.get_parent().app_shell.shared_settings.open() if manager.get_parent().app_shell != null else manager.controls.open_panel("Layout")
		"Controls Help": manager.shortcuts.open_help()
		"Import / Collection":
			manager.set_active(false)
			manager.get_parent().library.open_library()
		"Return to Title": manager.get_parent().return_to_title()
		"Exit":
			if manager.get_parent().app_shell != null:
				manager.get_parent().app_shell.request_exit()
				return
			var confirm := ConfirmationDialog.new()
			confirm.dialog_text = "Exit CardLink? Save your match first to keep table progress."
			confirm.confirmed.connect(func() -> void: get_tree().quit())
			confirm.canceled.connect(confirm.queue_free)
			add_child(confirm)
			confirm.popup_centered()
		"Multiplayer / Network": manager.get_parent().open_network_panel()
		"Token": token_editor.open_token(null, manager.world.get_global_transform().affine_inverse() * Vector2(400, 250))
		"Tools": tools_window.popup_centered()
		"Match History": toggle_history()
		"End Turn": manager.match_controller.end_turn()
		"Switch Perspective": manager.perspective.toggle()
		"Reset View": manager.view.reset_view()
		"Reset Table Layout": manager.organization.reset_layout()
		"Save Match", "Load Match":
			if manager.battle.connected(): manager.battle.saves.open(caption=="Load Match")
			else: manager.controls.open_panel("Match")
		"Undo": manager.undo.undo()
		_: manager.controls.open_panel(caption)
func open_components() -> void:
	if manager.custom_table != null and manager.custom_table.enabled: manager.custom_table.panel.open_palette()
	else: manager.controls.status.text = "Choose Build Your Own from the title screen to use Table Components."
func is_modal() -> bool:
	return corner.visible or field_menu.visible or tools_window.visible or history_window.visible or counter_window.visible or token_editor.visible
func close_all() -> void:
	for window: Window in [corner, field_menu, tools_window, history_window, counter_window, token_editor]:
		window.hide()
func build_tools() -> void:
	tools_window = make_window("Tools", Vector2i(420, 400))
	var column: VBoxContainer = rows(tools_window)
	add_button(column, "Roll D6", func() -> void: display_result(tools.roll(1, 6)))
	add_button(column, "Roll D20", func() -> void: display_result(tools.roll(1, 20)))
	dice_input = LineEdit.new()
	dice_input.placeholder_text = "Custom dice: 3d6 (max 100d1000)"
	dice_input.max_length = 16
	column.add_child(dice_input)
	add_button(column, "Roll custom dice", func() -> void: display_result(tools.roll_text(dice_input.text)))
	add_button(column, "Flip coin", func() -> void: display_result(tools.flip()))
	calculator_input = LineEdit.new()
	calculator_input.placeholder_text = "Calculator: (40 - 3) * 2"
	calculator_input.max_length = 200
	column.add_child(calculator_input)
	add_button(column, "Calculate", func() -> void:
		var result: Dictionary = tools.calculate(calculator_input.text)
		result_label.text = str(result.get("error", result.get("value", ""))))
	result_label = manager.controls.label(column, "Results are local. Rolls and flips appear in Match History.")
	result_label.max_lines_visible = 3
	result_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_button(column, "Close", tools_window.hide)
func display_result(result: Dictionary) -> void:
	result_label.text = str(result.get("error", result.get("text", "")))
	if result.get("payload", {}).has("values"):
		result_label.text += "\nDice: " + str(result.payload.values)
	result_label.tooltip_text = result_label.text
func build_history() -> void:
	history_window = make_window("Match History", Vector2i(520, 400))
	var column: VBoxContainer = rows(history_window)
	turn_label = manager.controls.label(column, "")
	add_button(column, "End Turn", func() -> void: manager.match_controller.end_turn())
	history_text = RichTextLabel.new()
	history_text.bbcode_enabled = false
	history_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_text.scroll_following = true
	column.add_child(history_text)
	add_button(column, "Collapse History", history_window.hide)
func toggle_history() -> void:
	if history_window.visible:
		history_window.hide()
	else:
		refresh_history()
		history_window.popup_centered()
func refresh_history() -> void:
	if history_text == null:
		return
	var model: RefCounted = manager.match_controller.model
	turn_label.text = "Turn %d â€” %s" % [model.turn_number, model.players[model.active_player].display_name]
	var lines: PackedStringArray = []
	for event: Dictionary in model.history:
		lines.append(event.text if event.kind == "turn" else "Turn %d Â· %s\n%s" % [event.turn, model.players[event.actor].display_name, event.text])
	history_text.text = "\n\n".join(lines)
func build_counter_editor() -> void:
	counter_window = make_window("Counter Properties", Vector2i(360, 260))
	var column: VBoxContainer = rows(counter_window)
	counter_name = LineEdit.new()
	counter_name.placeholder_text = "Optional counter label"
	counter_name.max_length = 80
	column.add_child(counter_name)
	counter_value = SpinBox.new()
	counter_value.min_value = -1000000
	counter_value.max_value = 1000000
	column.add_child(counter_value)
	add_button(column, "+1", func() -> void:
		counter_value.value += 1
		save_counter())
	add_button(column, "-1", func() -> void:
		counter_value.value -= 1
		save_counter())
	add_button(column, "Set value / label", save_counter)
	add_button(column, "Delete counter", func() -> void:
		manager.undo.begin("Delete counter")
		manager.undo.finish.call_deferred()
		var item: Control = counter_by_id(editing_counter)
		if item != null:
			counters.erase(item)
			item.get_parent().remove_child(item)
			item.queue_free()
		counter_window.hide())
	add_button(column, "Close", counter_window.hide)
func create_counter(point: Vector2, value: int = 1, caption: String = "") -> Control:
	if manager.undo != null:
		manager.undo.begin("Create counter")
		manager.undo.finish.call_deferred()
	if counters.size() >= 500:
		manager.controls.status.text = "This table already has 500 standalone counters."
		return null
	var item: Control = preload("res://scripts/tabletop_counter.gd").new()
	item.selection = manager.selection
	item.value = clampi(value, -1000000, 1000000)
	item.caption = caption
	item.position = point
	manager.world.add_child(item)
	item.properties_requested.connect(open_counter)
	counters.append(item)
	if manager.perspective != null: manager.perspective.project_item(item)
	return item
func counter_by_id(id: String) -> Control:
	for item: Control in counters:
		if item.instance_id == id:
			return item
	return null
func open_counter(item: Control) -> void:
	if item == null:
		return
	editing_counter = item.instance_id
	counter_name.text = item.caption
	counter_value.value = item.value
	counter_window.popup_centered()
func save_counter() -> void:
	if manager.undo != null:
		manager.undo.begin("Counter value")
		manager.undo.finish.call_deferred()
	var item: Control = counter_by_id(editing_counter)
	if item != null:
		item.caption = counter_name.text
		item.value = int(counter_value.value)
		item.refresh()
func capture_counters() -> Array:
	var data: Array = []
	for item: Control in counters:
		data.append(item.to_data())
	return data
func restore_counters(data: Array) -> void:
	close_all()
	for item: Control in counters:
		item.get_parent().remove_child(item)
		item.queue_free()
	counters.clear()
	for row: Dictionary in data:
		var item: Control = create_counter(Vector2(row.position[0], row.position[1]), int(row.value), row.label)
		item.instance_id = row.instance_id

