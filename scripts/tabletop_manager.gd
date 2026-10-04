extends Node
const CardScene = preload("res://scenes/card.tscn")
const ZoneScene = preload("res://scenes/tabletop_zone.tscn")
const Controls = preload("res://scripts/tabletop_controls.gd")
var deck_preferences = preload("res://scripts/usability/deck_preferences.gd").new()
var lab: Node
var temporary_images: Node
var appearance: Node
var battle: Node
var deck_backs: Node
var custom_table: Node
var perspective: Node
var organization: RefCounted
var table_preferences = preload("res://scripts/usability/table_preferences.gd").new()
var undo: Node
var cards: Array[Control] = []
var zones: Array[Control] = []
var selected_card: Control
var zone_layer: Control
var controls: Controls
var selection: Control
var shortcuts: Node
var extras: Node
var token_art_directory: String = "user://token_art"
var life: int = 40
var drag_origins: Dictionary = {}
var active: bool = true
var backdrop: ColorRect
var world: Control
var view: Node
var match_controller: Node
var texture_cache: Dictionary = {}
var layout: RefCounted
var persistence: RefCounted
var life_display: PanelContainer
var summary_label: Label
var life_dragging: bool = false
var life_drag_offset: Vector2
var backs = preload("res://scripts/card_back_service.gd").new()
func _ready() -> void:
	world = Control.new()
	world.set_script(preload("res://scripts/tabletop_world.gd"))
	world.name = "TabletopWorld"
	world.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	world.size = world.LOGICAL_SIZE
	world.mouse_filter = Control.MOUSE_FILTER_PASS
	get_parent().add_child.call_deferred(world)
	zone_layer = Control.new()
	zone_layer.name = "Zones"
	zone_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.add_child(zone_layer)
	setup.call_deferred()
func setup() -> void:
	if get_parent().app_shell != null:
		table_preferences = get_parent().app_shell.table_preferences
		deck_preferences = get_parent().app_shell.entry.deck_preferences
	backdrop = ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().add_child(backdrop)
	get_parent().move_child(backdrop,0)
	get_parent().move_child(world, 1)
	controls = Controls.new()
	controls.manager = self
	get_parent().add_child(controls)
	var prototype: Control = get_parent().get_node_or_null("Card")
	if prototype != null:
		prototype.reparent(world)
		prototype.position = Vector2(70,155)
		register_card(prototype)
	view = preload("res://scripts/tabletop_view.gd").new()
	view.manager = self
	add_child(view)
	deck_backs = preload("res://scripts/battle/back_presentation.gd").new()
	deck_backs.manager = self
	add_child(deck_backs)
	match_controller = preload("res://scripts/match_controller.gd").new()
	match_controller.manager = self
	add_child(match_controller)
	backs.changed.connect(match_controller.refresh)
	world.controller = match_controller
	layout = preload("res://scripts/layout_service.gd").new(self)
	organization = preload("res://scripts/usability/table_organization.gd").new(self)
	persistence = preload("res://scripts/match_persistence.gd").new(self)
	extras = preload("res://scripts/tabletop_extras.gd").new()
	extras.manager = self
	add_child(extras)
	selection = preload("res://scripts/tabletop_selection.gd").new()
	selection.manager = self
	world.add_child(selection)
	for card: Control in cards:
		card.selection = selection
	shortcuts = preload("res://scripts/tabletop_shortcuts.gd").new()
	shortcuts.manager = self
	add_child(shortcuts)
	setup_summary()
	undo = preload("res://scripts/usability/manual_undo.gd").new()
	undo.manager = self
	add_child(undo)
	perspective = preload("res://scripts/usability/offline_perspective.gd").new()
	perspective.manager = self
	add_child(perspective)
	custom_table = preload("res://scripts/custom_table/table_builder.gd").new()
	custom_table.manager = self
	add_child(custom_table)
	battle=preload("res://scripts/battle/battle_session.gd").new()
	battle.manager=self
	add_child(battle)
	appearance=preload("res://scripts/appearance/table_appearance.gd").new();appearance.manager=self;add_child(appearance)
	lab=preload("res://scripts/playtest_lab/review_tray.gd").new();lab.manager=self;add_child(lab)
	temporary_images=preload("res://scripts/playtest_lab/temporary_images.gd").new();temporary_images.manager=self;add_child(temporary_images)
	organization.reset_layout()
	var feedback := preload("res://scripts/usability/table_feedback.gd").new()
	feedback.manager = self
	add_child(feedback)
	table_preferences.changed.connect(apply_table_preferences)
	apply_table_preferences()
	match_controller.refresh()
	get_parent().move_child(controls, get_parent().get_child_count() - 1)
	# The library is the final GUI surface; the tabletop controls stay beneath it.
	get_parent().move_child(get_parent().library, get_parent().get_child_count() - 1)
func register_card(card: Control) -> void:
	card.selection = selection
	card.quick_tap_requested.connect(toggle_tap)
	if card.state.image_path.is_empty() and not card.state.is_token and card.card_image.texture != null:
		card.state.image_path = card.card_image.texture.resource_path
	card.size = Vector2(100, 140)
	card.card_image.pivot_offset = card.size / 2
	cards.append(card)
	card.card_back.texture = preload("res://scripts/battle/deck_back.gd").for_card(card,backs)
	card.actions_requested.connect(func(item: Control) -> void:
		select_card(item)
		controls.open_card_actions())
	card.properties_requested.connect(func(item: Control) -> void:
		select_card(item)
		if item.state.is_token and match_controller.visibility.can_present(item.state,"local"):
			controls.close_panels()
			extras.token_editor.open_token(item))
	card.selected.connect(select_card)
	card.drag_started.connect(func(item: Control) -> void:
		drag_origins[item.state.match_instance_id] = item.position
		if match_controller != null and match_controller.hand_window != null: match_controller.hand_window.watch_field(item))
	card.drag_finished.connect(finish_drag)
func spawn_definition(record: Dictionary, select: bool = true) -> Dictionary:
	var metadata: Dictionary = record.get("metadata", {})
	var path: String = str(record.get("image_path", ""))
	if record.get("thumbnail") == null or str(metadata.get("card_id", "")).is_empty() or not FileAccess.file_exists(path):
		return {"error": "This definition needs a valid card ID and image before it can be placed."}
	if not texture_cache.has(path):
		var image := Image.new()
		if image.load(path) != OK:
			return {"error": "The card image cannot be loaded."}
		texture_cache[path] = ImageTexture.create_from_image(image)
	var card: Control = CardScene.instantiate()
	card.state.card_definition_id = str(metadata["card_id"])
	card.state.definition_path = str(record.get("path", ""))
	card.state.display_name = str(record.get("name", "Card"))
	card.state.image_path = path
	preload("res://scripts/card_faces.gd").from_definition(card.state,metadata)
	card.position = Vector2(330 + (cards.size() % 5) * 42, 155 + (cards.size() % 4) * 22)
	world.add_child(card)
	var texture: Texture2D = texture_cache[path]
	card.card_image.texture = texture
	card.hover_preview.texture = texture
	if texture == null:
		card.show_placeholder()
	register_card(card)
	if select:
		select_card(card)
	return {"card": card}
func select_card(card: Control) -> void:
	selected_card = card
	for item: Control in cards:
		item.set_selected(item == card)
		if item != card:
			item.hover_preview.hide()
	if selection != null:
		selection.set_single(card)
	controls.update_selection()
	# GUI picking follows sibling order. Defer reordering until input dispatch ends.
	if is_instance_valid(card):
		bring_instance_to_front.call_deferred(card.state.match_instance_id)
func bring_instance_to_front(instance_id: String) -> void:
	# Match replacement may free the selected Control before deferred GUI work runs.
	for card: Control in cards:
		if card.state.match_instance_id == instance_id:
			bring_to_front(card)
			return
func bring_to_front(card: Control) -> void:
	if not is_instance_valid(card) or not cards.has(card):
		return
	var highest: int = card.get_index()
	for item: Control in cards:
		highest = maxi(highest, item.get_index())
	world.move_child(card, highest)
func send_to_back() -> void:
	if not is_instance_valid(selected_card):
		return
	var lowest: int = selected_card.get_index()
	for item: Control in cards:
		lowest = mini(lowest, item.get_index())
	world.move_child(selected_card, lowest)
func add_zone(data: Dictionary) -> Control:
	var zone: Control = ZoneScene.instantiate()
	zone.configure(data)
	zone.edit_enabled = layout.edit_mode if layout != null else false
	zone_layer.add_child(zone)
	zones.append(zone)
	zone.moved.connect(_zone_moved)
	zone.layout_service = organization
	zone.context_requested.connect(func(item: Control) -> void: match_controller.open_public_zone(item.player_id,item.zone_type))
	controls.refresh_zones()
	return zone
func _zone_moved(zone: Control, delta: Vector2) -> void:
	for card: Control in cards:
		if card.state.zone_id == zone.zone_id:
			card.position += delta
			card.state.position = card.position
func find_zone(identifier: String) -> Control:
	for zone: Control in zones:
		if zone.zone_id == identifier:
			return zone
	return null
func assign_zone(card: Control, zone: Control, reposition: bool = true) -> bool:
	if zone != null and preload("res://scripts/token_service.gd").expires_in(card.state, zone.zone_type):
		match_controller.destroy_token(card)
		match_controller.refresh()
		return true
	if zone != null and not zone.can_accept(card.state.match_instance_id):
		controls.status.text = "That zone is at its chosen capacity. Card stays in its previous zone."
		return false
	var previous: Control = find_zone(card.state.zone_id)
	if previous != null:
		previous.members.erase(card.state.match_instance_id)
		previous.update_title()
	card.state.zone_id = "" if zone == null else zone.zone_id
	if zone != null:
		if not zone.members.has(card.state.match_instance_id):
			zone.members.append(card.state.match_instance_id)
		zone.update_title()
		if reposition:
			card.position = zone.position + Vector2(20, 44)
	card.state.position = card.position
	if match_controller != null:
		match_controller.assigned_zone(card, zone)
	controls.update_selection()
	controls.status.text = "Card moved to %s." % ("the free table" if zone == null else zone.display_name)
	return true
func move_selected_to_zone() -> void:
	if selected_card == null:
		return
	var identifier: String = str(controls.destination.get_selected_metadata())
	assign_zone(selected_card, find_zone(identifier))
func finish_drag(card: Control) -> void:
	var target: Control
	var center: Vector2 = card.position + card.size / 2
	for zone: Control in zones:
		if Rect2(zone.position, zone.size).has_point(center):
			target = zone
	if not assign_zone(card, target, false):
		card.position = drag_origins.get(card.state.match_instance_id, card.state.position)
		card.state.position = card.position
	drag_origins.erase(card.state.match_instance_id)
func change_life(amount: int) -> void:
	match_controller.change_life("local", amount)
func change_counter(amount: int) -> void:
	if self.undo != null:
		self.undo.begin("Card counter")
		self.undo.finish.call_deferred()
	if selected_card == null:
		return
	selected_card.state.change_counter(controls.counter_name.text, amount)
	selected_card.update_counters()
	controls.update_selection()
func set_active(value: bool) -> void:
	if not value and selection != null:
		selection.clear()
	active = value
	if extras != null:
		for item: Control in extras.counters:
			item.visible = value
		if not value:
			extras.close_all()
	zone_layer.visible = value
	controls.visible = value
	if life_display != null:
		life_display.hide()
	if not value and controls.has_method("close_panels"):
		controls.close_panels()
	for zone: Control in zones:
		zone.dragging = false
	for card: Control in cards:
		card.visible = value
		card.dragging = false
		card.hover_preview.hide()
	if match_controller != null:
		match_controller.set_active(value)



func setup_summary() -> void:
	life_display = PanelContainer.new()
	life_display.position = Vector2(790, 80)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.1, 0.95)
	style.set_content_margin_all(8)
	life_display.add_theme_stylebox_override("panel", style)
	summary_label = Label.new()
	summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	life_display.add_child(summary_label)
	life_display.gui_input.connect(func(event: InputEvent) -> void:
		if not layout.edit_mode:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			life_dragging = event.pressed
			life_drag_offset = event.position
		elif event is InputEventMouseMotion and life_dragging:
			life_display.position += event.position - life_drag_offset)
	get_parent().add_child(life_display)
	get_parent().move_child(get_parent().library, get_parent().get_child_count() - 1)
func refresh_match_summary() -> void:
	if life_display != null: life_display.hide()
	if summary_label == null:
		return
	var local: RefCounted = match_controller.model.players.local
	var opponent: RefCounted = match_controller.model.players.opponent
	summary_label.text = "%s: %d life  ·  %s: %d life\nOpponent hand: %d  ·  Library: %d" % [local.display_name.left(20), local.life, opponent.display_name.left(20), opponent.life, match_controller.hidden_count("opponent", "hand"), match_controller.hidden_count("opponent", "library")]
	summary_label.text += "\nTurn %d · %s" % [match_controller.model.turn_number, match_controller.actor_name()]
func restore_card(data: Dictionary) -> Control:
	var card: Control = CardScene.instantiate()
	card.state.restore(data)
	card.position = card.state.position
	world.add_child(card)
	apply_card_art(card)
	register_card(card)
	var saved_metadata: Dictionary = card.state.custom_metadata.duplicate(true)
	card.set_tapped(data.tapped)
	card.set_face_down(data.face_down)
	card.state.custom_metadata = saved_metadata
	card.state.visibility = data.visibility
	card.update_counters()
	return card
func apply_card_art(card: Control) -> void:
	var path: String = card.state.image_path
	var texture: Texture2D
	var allowed: bool = path == "res://icon.svg" or path.get_base_dir().simplify_path() == match_controller.loader.storage.directory.simplify_path() or (card.state.is_token and path.get_base_dir().simplify_path() == token_art_directory.simplify_path())
	if allowed and not path.contains("..") and FileAccess.file_exists(path):
		if path == "res://icon.svg":
			texture = load(path) as Texture2D
		elif texture_cache.has(path):
			texture = texture_cache[path]
		else:
			var image := Image.new()
			if image.load(path) == OK:
				texture = ImageTexture.create_from_image(image)
				texture_cache[path] = texture
	card.card_image.texture = texture
	card.hover_preview.texture = texture
	if texture == null:
		card.show_placeholder()
	card.queue_redraw()
func create_token(caption: String, owner: String, controller: String, image_path: String = "", power: String = "", toughness: String = "") -> Dictionary:
	if not match_controller.model.players.has(owner) or not match_controller.model.players.has(controller):
		return {"error": "Unknown token player."}
	if undo != null:
		undo.begin("Create token")
		undo.finish.call_deferred()
	var state: RefCounted = preload("res://scripts/token_state.gd").new()
	state.display_name = caption.strip_edges() if not caption.strip_edges().is_empty() else "Token"
	state.owner_player_id = owner
	state.controller_player_id = controller
	state.zone_player_id = controller
	state.image_path = image_path
	state.custom_metadata["power"] = power.strip_edges()
	state.custom_metadata["toughness"] = toughness.strip_edges()
	state.position = world.get_global_transform().affine_inverse() * Vector2(400, 250)
	var card: Control = restore_card(state.to_data())
	select_card(card)
	match_controller.refresh()
	return {"card": card}



func apply_table_preferences() -> void:
	for hand: PanelContainer in [match_controller.hand,match_controller.opponent_hand]:
		var style: StyleBoxFlat = hand.get_theme_stylebox("panel")
		style.bg_color.a = clampf(float(table_preferences.value("hand_opacity",0.5)),0.2,1.0)
	world.table_color = table_preferences.THEMES.get(str(table_preferences.value("theme","CardLink Blue")),Color("152d40"))
	world.queue_redraw()
	backdrop.color = world.table_color.darkened(0.3)
	match_controller.hand.row.configure(str(table_preferences.value("hand_layout","Straight")),float(table_preferences.value("hand_scale",1.0)))
	if not match_controller.hand_window.detached:
		var old_height: float = match_controller.hand.size.y
		match_controller.hand.size.y = organization.hand_height()
		match_controller.hand.position.y -= match_controller.hand.size.y-old_height
	match_controller.opponent_hand.layout_mode_id = str(table_preferences.value("opponent_layout","Straight"))
	match_controller.opponent_hand.arrange()
	match_controller.refresh()

func toggle_tap(card: Control) -> void:
	preload("res://scripts/usability/tap_action.gd").toggle(self,card)
