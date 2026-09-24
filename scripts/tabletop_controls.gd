extends PanelContainer
const RecordPanel = preload("res://scripts/saved_record_panel.gd")
const Snapshot = preload("res://scripts/match_snapshot.gd")
const LayoutService = preload("res://scripts/layout_service.gd")
const DeckStorage = preload("res://scripts/deck_storage.gd")
var manager: Node
var destination: OptionButton
var life_label: Label
var counter_name: LineEdit
var status: Label
var selected_label: Label
var zone_type: OptionButton
var zone_name: LineEdit
var zone_capacity: SpinBox
var zone_player: OptionButton
var card_actions: Array[Button] = []
var panels: Dictionary = {}
var deck_storage = DeckStorage.new()
var deck_picker: OptionButton
var deck_target: OptionButton
var leaders_out: CheckBox
var deck_confirm: ConfirmationDialog
var deck_pending: Dictionary
var deck_pending_player: String
var counter_value: SpinBox
var edit_button: CheckButton
var hand_toggle: CheckButton
var layout_records: VBoxContainer
var match_records: VBoxContainer
var context_actions: RefCounted
var card_target: OptionButton
func button(parent: Node, caption: String, callback: Callable) -> Button:
	var item := Button.new()
	item.text = caption
	item.pressed.connect(callback)
	parent.add_child(item)
	return item
func players(parent: Node) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item("Local player")
	picker.set_item_metadata(0, "local")
	picker.add_item("Simulated opponent")
	picker.set_item_metadata(1, "opponent")
	parent.add_child(picker)
	return picker
func label(parent: Node, text: String) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item
func panel(caption: String) -> VBoxContainer:
	var popup := PopupPanel.new()
	popup.name = caption + "Panel"
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.07, 0.10, 0.14, 1.0)
	popup.add_theme_stylebox_override("panel", surface)
	add_child(popup)
	panels[caption] = popup
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	popup.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(490, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	label(rows, caption + " Actions" if caption in ["Card", "Library"] else caption)
	button(rows, "Close", popup.hide)
	return rows
func close_panels() -> void:
	for popup: PopupPanel in panels.values():
		popup.hide()
func open_panel(caption: String) -> void:
	var was_visible: bool = panels[caption].visible
	close_panels()
	if was_visible:
		return
	if caption == "Library":
		refresh_decks()
	if caption == "Match" and match_records != null:
		match_records.refresh()
	if caption == "Layout" and layout_records != null:
		layout_records.refresh()
	panels[caption].get_child(0).get_child(0).scroll_vertical = 0
	var screen: Vector2 = get_viewport_rect().size
	panels[caption].popup(Rect2i(20, maxi(10, int(screen.y) - 480), 530, mini(400, int(screen.y) - 90)))
func _ready() -> void:
	context_actions = preload("res://scripts/tabletop_context_actions.gd").new(self)
	name = "TabletopControls"
	z_index = 200
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -196
	offset_top = -48
	offset_right = -8
	offset_bottom = -8
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.045, 0.065, 0.09)
	background.content_margin_left = 10
	background.content_margin_right = 10
	background.content_margin_top = 4
	background.content_margin_bottom = 4
	add_theme_stylebox_override("panel", background)
	var rows := VBoxContainer.new()
	add_child(rows)
	var bar := HBoxContainer.new()
	rows.add_child(bar)
	for caption: String in ["Hand", "Library", "Zones", "Card", "Token", "Counter", "Life", "Match", "Layout"]:
		button(bar, caption, open_panel.bind(caption))
	status = Label.new()
	status.text = "Play Mode · Cards are freely movable. Open Layout to edit the table."
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(status)
	bar.hide()
	status.hide()
	var corner_buttons := HBoxContainer.new()
	rows.add_child(corner_buttons)
	corner_buttons.hide()
	background.bg_color.a = 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_card_panel()
	build_zone_panel()
	build_counter_panel()
	build_life_panel()
	build_hand_panel()
	build_token_panel()
	build_library_panel()
	panel("Match")
	panel("Layout")
	build_persistence.call_deferred()
	refresh_zones()
	update_selection()
func build_card_panel() -> void:
	var rows: VBoxContainer = panel("Card")
	selected_label = label(rows, "Select a card")
	label(rows, "Target player for moves and control")
	var target: OptionButton = players(rows)
	card_target = target
	context_actions.build_card(rows, target)
	var stacking := HBoxContainer.new()
	rows.add_child(stacking)
	card_actions.append(button(stacking, "Bring to front", func() -> void: manager.bring_to_front(manager.selected_card)))
	card_actions.append(button(stacking, "Send to back", manager.send_to_back))
	destination = OptionButton.new()
	rows.add_child(destination)
	card_actions.append(button(rows, "Move to physical zone", manager.move_selected_to_zone))
func open_card_actions() -> void:
	if manager.selected_card == null:
		return
	card_target.select(0 if manager.selected_card.state.zone_player_id == "local" else 1)
	close_panels()
	open_panel("Card")
func open_library_actions(player_id: String) -> void:
	deck_target.select(0 if player_id == "local" else 1)
	close_panels()
	open_panel("Library")
func build_zone_panel() -> void:
	var rows: VBoxContainer = panel("Zones")
	label(rows, "Create and drag major objects in Edit Layout mode. Cards remain playable in either mode.")
	zone_player = players(rows)
	zone_type = OptionButton.new()
	for caption: String in ["Deck", "Hand", "Graveyard", "Exile", "Commander", "Custom Zone"]:
		zone_type.add_item(caption)
	rows.add_child(zone_type)
	zone_name = LineEdit.new()
	zone_name.placeholder_text = "Optional zone name"
	rows.add_child(zone_name)
	label(rows, "Capacity (0 = unlimited)")
	zone_capacity = SpinBox.new()
	zone_capacity.max_value = 9999
	rows.add_child(zone_capacity)
	button(rows, "Add zone", create_zone)
func build_counter_panel() -> void:
	var rows: VBoxContainer = panel("Counter")
	button(rows, "Create standalone counter", func() -> void:
		close_panels()
		manager.extras.open_counter(manager.extras.create_counter(manager.world.get_global_transform().affine_inverse() * Vector2(400, 250))))
	label(rows, "Counters attached to the selected card")
	counter_name = LineEdit.new()
	counter_name.text = "Counter"
	counter_name.placeholder_text = "Counter type"
	rows.add_child(counter_name)
	counter_value = SpinBox.new()
	counter_value.max_value = 1000000
	rows.add_child(counter_value)
	card_actions.append(button(rows, "Set value", func() -> void:
		manager.selected_card.state.set_counter(counter_name.text, int(counter_value.value))
		manager.selected_card.update_counters()))
	card_actions.append(button(rows, "Add counter", manager.change_counter.bind(1)))
	card_actions.append(button(rows, "Remove counter", manager.change_counter.bind(-1)))
func build_life_panel() -> void:
	var rows: VBoxContainer = panel("Life")
	var target: OptionButton = players(rows)
	label(rows, "Local player total (both totals also appear on the table):")
	life_label = label(rows, "Life: 40")
	label(rows, "Either player's life may be changed. No legality checks.")
	button(rows, "− Life", func() -> void: manager.match_controller.change_life(str(target.get_selected_metadata()), -1))
	button(rows, "+ Life", func() -> void: manager.match_controller.change_life(str(target.get_selected_metadata()), 1))
func build_hand_panel() -> void:
	var rows: VBoxContainer = panel("Hand")
	hand_toggle = CheckButton.new()
	hand_toggle.text = "Show local private hand"
	hand_toggle.button_pressed = true
	hand_toggle.toggled.connect(func(value: bool) -> void:
		manager.match_controller.hand_open = value
		manager.match_controller.refresh())
	rows.add_child(hand_toggle)
	button(rows, "Search own hand", func() -> void: inspect("local", "hand"))
	button(rows, "Search Opponent Hand", func() -> void: inspect("opponent", "hand"))
	button(rows, "Reveal Opponent Hand (temporary)", func() -> void: inspect("opponent", "hand", true))
func inspect(player_id: String, kind: String, reveal: bool = false) -> void:
	close_panels()
	manager.match_controller.open_inspection(player_id, kind, reveal)
func build_token_panel() -> void:
	var rows: VBoxContainer = panel("Token")
	button(rows, "Create Token", func() -> void:
		close_panels()
		manager.extras.choose("Token"))
func build_library_panel() -> void:
	var rows: VBoxContainer = panel("Library")
	label(rows, "Target library")
	deck_target = players(rows)
	context_actions.build_library(rows, deck_target)
	label(rows, "Load an existing saved deck for the selected player")
	deck_picker = OptionButton.new()
	rows.add_child(deck_picker)
	leaders_out = CheckBox.new()
	leaders_out.text = "Place leaders outside library"
	leaders_out.button_pressed = true
	rows.add_child(leaders_out)
	button(rows, "Load Deck", request_deck)
	button(rows, "Import ZIP Deck…", func() -> void: manager.get_parent().open_archive_importer())
	button(rows, "Search own library", func() -> void: inspect("local", "library"))
	button(rows, "Search Opponent Library", func() -> void: inspect("opponent", "library"))
	button(rows, "Card Library / Import images", func() -> void:
		close_panels()
		manager.get_parent().open_library())
	button(rows, "Deck Builder", func() -> void:
		close_panels()
		manager.get_parent().open_deck_builder())
	deck_confirm = ConfirmationDialog.new()
	deck_confirm.dialog_text = "Replace this player's currently loaded deck copies? Other player's cards and unrelated tabletop cards remain."
	deck_confirm.confirmed.connect(play_pending_deck)
	add_child(deck_confirm)
func refresh_decks() -> void:
	deck_picker.clear()
	var prefs = preload("res://scripts/usability/deck_preferences.gd").new()
	var recent_decks: Array = deck_storage.list_decks()
	recent_decks.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return prefs.rank(str(a.data.get("deck_id",""))) < prefs.rank(str(b.data.get("deck_id",""))))
	for record: Dictionary in recent_decks:
		deck_picker.add_item(prefs.caption(record.data) if str(record.error).is_empty() else str(record.data.get("deck_name", record.path.get_file())) + (" [invalid]" if not str(record.error).is_empty() else ""))
		deck_picker.set_item_metadata(deck_picker.item_count - 1, record)
func request_deck() -> void:
	if deck_picker.selected < 0:
		status.text = "No saved decks. Create one in Deck Builder."
		return
	var row: Dictionary = deck_picker.get_selected_metadata()
	if not str(row.error).is_empty():
		status.text = row.error
		return
	deck_pending = row.data
	deck_pending_player = str(deck_target.get_selected_metadata())
	if not manager.match_controller.model.players[deck_pending_player].loaded_ids.is_empty():
		deck_confirm.popup_centered()
	else:
		play_pending_deck()
func play_pending_deck() -> void:
	var result: Dictionary = manager.match_controller.load_deck(deck_pending, leaders_out.button_pressed, deck_pending_player)
	status.text = str(result.get("error", "Deck loaded. Shuffle and draw from Library."))
func build_persistence() -> void:
	var match_rows: VBoxContainer = panels.Match.get_child(0).get_child(0).get_child(0)
	label(match_rows, "Local trusted-host saves include both players' hidden information.")
	match_records = RecordPanel.new()
	match_records.storage = manager.persistence.matches
	match_records.capture_data = manager.persistence.capture_match
	match_records.apply_data = manager.persistence.restore_match
	match_records.validator = Snapshot.validate
	match_records.confirm_load = true
	match_rows.add_child(match_records)
	var layout_rows: VBoxContainer = panels.Layout.get_child(0).get_child(0).get_child(0)
	edit_button = CheckButton.new()
	edit_button.text = "Edit Layout Mode"
	edit_button.toggled.connect(func(value: bool) -> void: manager.layout.set_edit_mode(value))
	layout_rows.add_child(edit_button)
	var presets := OptionButton.new()
	for caption: String in ["Default", "Left-handed", "Right-handed", "Commander", "Custom"]:
		presets.add_item(caption)
	layout_rows.add_child(presets)
	button(layout_rows, "Apply built-in preset", func() -> void:
		manager.layout.apply(manager.layout.built_in(presets.get_item_text(presets.selected))))
	button(layout_rows, "Zoom in", func() -> void: manager.view.zoom_by(1.2))
	button(layout_rows, "Zoom out", func() -> void: manager.view.zoom_by(1.0 / 1.2))
	button(layout_rows, "Reset pan / zoom", manager.view.reset_view)
	context_actions.build_backs(layout_rows)
	manager.organization.build_controls(layout_rows)
	label(layout_rows, "UI text scale")
	var scale_input := SpinBox.new()
	scale_input.min_value = 0.75
	scale_input.max_value = 1.5
	scale_input.step = 0.05
	scale_input.value = 1.0
	scale_input.value_changed.connect(func(value: float) -> void:
		manager.layout.ui_scale = value
		add_theme_font_size_override("font_size", roundi(14 * value)))
	layout_rows.add_child(scale_input)
	layout_records = RecordPanel.new()
	layout_records.storage = manager.persistence.layouts
	layout_records.capture_data = manager.persistence.capture_layout
	layout_records.apply_data = manager.persistence.load_layout
	layout_records.validator = LayoutService.validate
	layout_rows.add_child(layout_records)
func create_zone() -> void:
	if not manager.layout.edit_mode:
		status.text = "Enable Edit Layout Mode before adding zones."
		return
	var caption: String = zone_type.get_item_text(zone_type.selected)
	manager.add_zone({"display_name": zone_name.text.strip_edges() if not zone_name.text.strip_edges().is_empty() else caption,
		"zone_type": caption.to_lower().replace(" ", "_"), "player_id": str(zone_player.get_selected_metadata()),
		"capacity": int(zone_capacity.value), "position": Vector2(430, 200)})
	status.text = "Zone added. Drag its header in Edit Layout Mode."
func refresh_zones() -> void:
	if destination == null:
		return
	destination.clear()
	destination.add_item("No zone / free table")
	destination.set_item_metadata(0, "")
	for zone: Control in manager.zones:
		destination.add_item(zone.display_name)
		destination.set_item_metadata(destination.item_count - 1, zone.zone_id)
func update_selection() -> void:
	if selected_label == null:
		return
	var card: Control = manager.selected_card
	for item: Button in card_actions:
		item.disabled = card == null
		if item.text == "Token Properties": item.visible = card != null and card.state.is_token and manager.match_controller != null and manager.match_controller.visibility.can_present(card.state,"local")
	if card == null:
		selected_label.text = "No card selected · Place cards from Card Library"
		selected_label.tooltip_text = ""
		return
	var allowed: bool = manager.match_controller == null or manager.match_controller.visibility.can_present(card.state, "local")
	var zone: Control = manager.find_zone(card.state.zone_id)
	selected_label.text = "%s · %s" % [card.state.display_name if allowed else "Hidden card", card.state.current_zone.capitalize() if zone == null else zone.display_name]
	selected_label.tooltip_text = "Definition: %s\nInstance: %s\nOwner: %s · Controller: %s" % [card.state.card_definition_id if allowed else "Hidden", card.state.match_instance_id, card.state.owner_player_id, card.state.controller_player_id]


