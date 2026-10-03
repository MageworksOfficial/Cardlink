extends Node
const Pile = preload("res://scripts/library_pile.gd")
const DeckStorage = preload("res://scripts/deck_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
const Hand = preload("res://scripts/hand_ui.gd")
const MatchState = preload("res://scripts/match_state.gd")
const Visibility = preload("res://scripts/visibility_service.gd")
var manager: Node
var public_sync: Node
var playtest: Node
var hand_window: Node
var hearts: Node
const Knowledge = preload("res://scripts/library_knowledge.gd")
var knowledge_view: bool = false
var remote_library_knowledge: Dictionary = {}
func active_hand_player() -> String:
	return playtest.hand_player if playtest != null and playtest.local_playtest() else "local"
var preparing_match: bool = false
var remote_hand_count: int = -1
var remote_library_count: int = -1
func online() -> bool:
	return public_sync != null and public_sync.enabled
func hidden_count(player: String, kind: String) -> int:
	if player == "opponent" and (remote_hand_count if kind == "hand" else remote_library_count) >= 0:
		return remote_hand_count if kind == "hand" else remote_library_count
	return model.players[player].hand.size() if kind == "hand" else model.players[player].library.order.size()
var loader = Loader.new()
var model: MatchState = MatchState.new()
var visibility: Visibility = Visibility.new()
# Stable Milestone 4 aliases refer to the local player's state.
var pile:
	get: return model.players.local.library
var loaded_ids: Array[String]:
	get: return model.players.local.loaded_ids
var deck_name: String:
	get: return model.players.local.deck_name
	set(value): model.players.local.deck_name = value
var hand: PanelContainer
var toolbar: PanelContainer
var count: Label
var actions: OptionButton
var preview: TextureRect
var preview_layer: CanvasLayer
var contents: Window
var contents_list: ItemList
var contents_query: LineEdit
var inspection_preview: TextureRect
var inspection_reveal_button: Button
var remote_inspection: bool = false
var inspection_player: String = "local"
var inspection_zone: String = "library"
var inspection_reveal: bool = false
var transitioning: bool = false
var batching: bool = false
var pile_view: Button
var opponent_pile: Button
var hand_open: bool = true
var hands_hidden: bool = false
var opponent_hand: PanelContainer
var review: Window
var library_actions: RefCounted
func button(parent: Node, caption: String, callback: Callable) -> Button:
	var item := Button.new()
	item.text = caption
	item.pressed.connect(callback)
	parent.add_child(item)
	return item
func _ready() -> void:
	library_actions = preload("res://scripts/library_actions.gd").new(self)
	review = preload("res://scripts/library_review.gd").new()
	review.controller = self
	add_child(review)
	pile_view = preload("res://scripts/library_pile_view.gd").new()
	pile_view.controller = self
	manager.world.add_child(pile_view)
	opponent_pile = preload("res://scripts/library_pile_view.gd").new()
	opponent_pile.controller = self
	opponent_pile.player_id = "opponent"
	manager.world.add_child(opponent_pile)
	opponent_pile.position = Vector2(900, 70)
	hand = Hand.new()
	hand.controller = self
	manager.get_parent().add_child(hand)
	opponent_hand = preload("res://scripts/opponent_hand_ui.gd").new()
	manager.get_parent().add_child(opponent_hand)
	# Retain action selector/count interfaces for existing callers; the new
	# compact toolbar presents these actions contextually.
	toolbar = PanelContainer.new()
	manager.get_parent().add_child(toolbar)
	toolbar.hide()
	var rows := VBoxContainer.new()
	toolbar.add_child(rows)
	count = Label.new()
	rows.add_child(count)
	actions = OptionButton.new()
	for caption: String in ["Move to Hand", "Play to Battlefield", "Move to Graveyard", "Move to Exile", "Move to Leader zone", "Put on Top of Library", "Put on Bottom of Library", "Reveal", "Hide / Face Down"]:
		actions.add_item(caption)
	rows.add_child(actions)
	preview_layer = CanvasLayer.new()
	preview_layer.layer = 20
	add_child(preview_layer)
	preview = TextureRect.new()
	preview.size = Vector2(300, 420)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.add_child(preview)
	preview.hide()
	contents = Window.new()
	contents.title = "Inspect library"
	contents.size = Vector2i(680, 570)
	contents.visible = false
	contents.close_requested.connect(close_inspection)
	contents.visibility_changed.connect(func() -> void:
		if not contents.visible:
			end_inspection())
	add_child(contents)
	var list_rows := VBoxContainer.new()
	list_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contents.add_child(list_rows)
	contents_query = LineEdit.new()
	contents_query.placeholder_text = "Search inspected cards"
	contents_query.text_changed.connect(func(_text: String) -> void: refresh_contents())
	list_rows.add_child(contents_query)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_rows.add_child(body)
	contents_list = ItemList.new()
	contents_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents_list.icon_mode = ItemList.ICON_MODE_TOP
	contents_list.fixed_icon_size = Vector2i(84, 118)
	contents_list.fixed_column_width = 108
	contents_list.max_columns = 0
	contents_list.max_text_lines = 2
	contents_list.gui_input.connect(inspection_hover)
	contents_list.item_clicked.connect(public_gallery_click)
	body.add_child(contents_list)
	inspection_preview = TextureRect.new()
	inspection_preview.custom_minimum_size = Vector2(210, 294)
	inspection_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inspection_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(inspection_preview)
	contents_list.item_selected.connect(func(index: int) -> void:
		if remote_inspection:
			public_sync.hidden.ui.preview(index)
			return
		var card: Control = card_by_id(str(contents_list.get_item_metadata(index)))
		if card != null and (not knowledge_view or Knowledge.known(card.state,"local")): manager.select_card(card)
		inspection_preview.texture = inspection_texture(index,card))
	inspection_reveal_button = button(list_rows, "Reveal selected hidden card (until inspection closes)", reveal_inspected)
	button(list_rows, "Take selected into local hand", func() -> void:
		if remote_inspection:
			public_sync.hidden.move_selected("take")
			return
		var card: Control = inspected_card()
		if card != null:
			move_card(card, "hand", true, "local"))
	button(list_rows, "Put selected on this library's top", func() -> void:
		if remote_inspection:
			public_sync.hidden.move_selected("library",1,false)
			return
		var card: Control = inspected_card()
		if card != null:
			move_card(card, "library", true, inspection_player))
	button(list_rows, "Put selected on this library's bottom", func() -> void:
		if remote_inspection:
			public_sync.hidden.move_selected("library",1,true)
			return
		var card: Control = inspected_card()
		if card != null:
			move_card(card, "library", false, inspection_player))
	library_actions.placement_toggle(list_rows)
	var extra := HBoxContainer.new()
	list_rows.add_child(extra)
	for destination: String in ["battlefield","graveyard","exile"]:
		button(extra,destination.capitalize(),func() -> void:
			if remote_inspection:
				if destination=="battlefield" and library_actions.enter_face_down:
					manager.controls.status.text="Ask the player holding this private card to place it face down."
				else: public_sync.hidden.move_selected(destination)
			else:
				var card: Control = inspected_card()
				if card != null:
					if destination=="battlefield": library_actions.place_cards([card.state.match_instance_id],library_actions.beside_library(inspection_player),library_actions.enter_face_down)
					else: move_card(card,destination,true,inspection_player))
	var nth := SpinBox.new()
	nth.min_value = 1
	nth.max_value = 5001
	extra.add_child(nth)
	for bottom: bool in [false,true]:
		button(extra,"Nth bottom" if bottom else "Nth top",func() -> void:
			if remote_inspection: public_sync.hidden.move_selected("library",int(nth.value),bottom)
			else: library_actions.put_nth(inspected_card(),inspection_player,int(nth.value),bottom))
	button(list_rows, "Close inspection", close_inspection)
	playtest = preload("res://scripts/playtest_mode.gd").new()
	playtest.controller = self
	add_child(playtest)
	hand_window = preload("res://scripts/detached_hand_window.gd").new()
	hand_window.controller = self
	add_child(hand_window)
	hearts = preload("res://scripts/heart_life_controls.gd").new()
	hearts.controller = self
	add_child(hearts)
	refresh()
func card_by_id(id: String) -> Control:
	for card: Control in manager.cards:
		if card.state.match_instance_id == id:
			return card
	return null
func load_deck(deck: Dictionary, leaders_out: bool, player_id: String = "local") -> Dictionary:
	if manager.undo != null: manager.undo.invalidate("Loading a deck starts a new undo history.")
	if public_sync != null and public_sync.transactions.has_unfinished():
		return {"error":"Resolve the pending private card transfer before replacing decks."}
	if preparing_match:
		return {"error":"Finish or cancel Card Sync before replacing a loaded deck."}
	if online() and player_id != "local":
		return {"error":"Each connected player loads their own local deck."}
	if not model.players.has(player_id):
		return {"error": "Unknown player."}
	var error: String = DeckStorage.validate(deck)
	if not error.is_empty():
		return {"error": error}
	if deck.cards.is_empty():
		return {"error": "This deck is empty. Add cards before playing."}
	var definitions: Dictionary = {}
	var ambiguous: Dictionary = {}
	for record: Dictionary in loader.load_records():
		var id: String = str(record.metadata.get("card_id", ""))
		if definitions.has(id):
			ambiguous[id] = true
		definitions[id] = record
	for entry: Dictionary in deck.cards:
		if not definitions.has(entry.card_id) or ambiguous.has(entry.card_id):
			return {"error": "Missing or ambiguous definition: " + str(entry.card_id)}
		if definitions[entry.card_id].thumbnail == null:
			return {"error": "Missing or unreadable card image: " + str(entry.card_id)}
	var player: RefCounted = model.players[player_id]
	if leaders_out and not deck.leaders.is_empty():
		for zone: Control in manager.zones:
			if zone.zone_type != "commander" or zone.player_id != player_id:
				continue
			var retained: int = 0
			for id: String in zone.members:
				if not player.loaded_ids.has(id):
					retained += 1
			if zone.capacity > 0 and retained + deck.leaders.size() > zone.capacity:
				return {"error": "Existing Leader zone has insufficient capacity."}
			break
	var spawned: Array[Control] = []
	for entry: Dictionary in deck.cards:
		for i: int in int(entry.quantity):
			var result: Dictionary = manager.spawn_definition(definitions[entry.card_id], false)
			if result.has("error"):
				for card: Control in spawned:
					remove_card(card)
				return result
			spawned.append(result.card)
	close_inspection()
	review.cancel()
	for id: String in player.loaded_ids.duplicate():
		var old: Control = card_by_id(id)
		if old != null:
			remove_card(old)
	player.loaded_ids.clear()
	player.deck_back = deck.get("deck_back",{}).duplicate(true)
	batching = true
	var placed_leaders: Array[String] = []
	for card: Control in spawned:
		if deck.has("deck_back"): card.state.custom_metadata["deck_back"]=deck.deck_back.duplicate(true)
		card.state.owner_player_id = player_id
		card.state.controller_player_id = player_id
		player.loaded_ids.append(card.state.match_instance_id)
		var id: String = card.state.card_definition_id
		if leaders_out and deck.leaders.has(id) and not placed_leaders.has(id):
			placed_leaders.append(id)
			move_card(card, "commander", true, player_id)
		else:
			move_card(card, "library", false, player_id)
	player.deck_name = str(deck.deck_name)
	player.deck_manifest.clear()
	for entry: Dictionary in deck.cards:
		player.deck_manifest.append(preload("res://scripts/network/card_sync_catalog.gd").descriptor(definitions[entry.card_id].metadata))
	batching = false
	shuffle_library(player_id)
	manager.selected_card = null
	for card: Control in manager.cards:
		card.set_selected(false)
	refresh()
	preload("res://scripts/usability/deck_preferences.gd").new().used(str(deck.deck_id))
	if manager.battle!=null: manager.battle.reset.start.remember("standard",player_id,deck,leaders_out)
	return {"count": spawned.size()}
var search_player: String = ""
func destroy_token(card: Control) -> void:
	record_event("token_destroyed", actor_name() + " destroyed a token", {"instance_id": card.state.match_instance_id})
	remove_card(card)
func remove_card(card: Control) -> void:
	if manager.custom_table != null: manager.custom_table.detach(card)
	if manager.selection != null:
		manager.selection.ids.erase(card.state.match_instance_id)
	for player: RefCounted in model.players.values():
		player.library.order.erase(card.state.match_instance_id)
		player.loaded_ids.erase(card.state.match_instance_id)
	var zone: Control = manager.find_zone(card.state.zone_id)
	if zone != null:
		zone.members.erase(card.state.match_instance_id)
		zone.update_title()
	manager.cards.erase(card)
	if manager.selected_card == card:
		manager.selected_card = null
	card.get_parent().remove_child(card)
	card.queue_free()
func zone_for(kind: String, player_id: String = "local") -> Control:
	for zone: Control in manager.zones:
		if zone.zone_type == kind and zone.player_id == player_id:
			return zone
	var labels: Dictionary = {"graveyard": "Graveyard", "exile": "Exile", "commander": "Leaders"}
	var zone: Control = manager.add_zone({"zone_type": kind, "player_id": player_id,
		"display_name": ("Your " if player_id == "local" else "Opponent ") + str(labels.get(kind, kind)),
		"position": Vector2(470 + (manager.zones.size() % 3) * 155, 155 if player_id == "local" else 55)})
	zone.custom_minimum_size = Vector2(145, 210)
	zone.size = zone.custom_minimum_size
	return zone
func move_card(card: Control, kind: String, on_top: bool = true, player_id: String = "local", authorized: bool = false, enter_hidden: bool = false) -> bool:
	if manager.undo != null:
		manager.undo.begin("Move card")
		manager.undo.finish.call_deferred()
	if online() and is_instance_valid(card) and public_sync.transactions.is_locked(card.state.match_instance_id):
		manager.controls.status.text = "Waiting for the other client to acknowledge this private transfer."
		return false
	if online() and not authorized and is_instance_valid(card) and kind in ["hand", "library"]:
		player_id = "local" if card.state.zone_player_id == "local" and card.state.current_zone in ["hand","library"] else card.state.owner_player_id
		if player_id != "local" and kind == "library":
			public_sync.private_returns[card.state.match_instance_id] = on_top
	if not is_instance_valid(card) or not model.players.has(player_id):
		return false
	if preload("res://scripts/token_service.gd").expires_in(card.state, kind):
		destroy_token(card)
		refresh()
		return true
	if manager.custom_table != null: manager.custom_table.detach(card)
	var zone: Control = null
	if kind in ["graveyard", "exile", "commander"]:
		zone = zone_for(kind, player_id)
		if not zone.can_accept(card.state.match_instance_id):
			manager.controls.status.text = "Destination zone is full."
			return false
	if kind == "library" and not batching: Knowledge.entering(card.state,visibility)
	var publicly_revealed: bool = card.state.custom_metadata.get("public_reveal", false)
	transitioning = true
	manager.assign_zone(card, zone)
	transitioning = false
	for player: RefCounted in model.players.values():
		player.library.order.erase(card.state.match_instance_id)
	card.state.current_zone = kind
	card.state.zone_player_id = player_id
	# Ownership/control are deliberately not changed by moving a card.
	card.set_face_down(kind == "library" or (kind == "battlefield" and enter_hidden))
	card.state.visibility = "owner_private" if kind in ["library", "hand"] else "public"
	card.set_tapped(false)
	if publicly_revealed and not enter_hidden:
		visibility.set_public_reveal(card.state, true)
	if enter_hidden:
		visibility.set_public_reveal(card.state,false)
		card.set_face_down(true)
	if kind == "library":
		model.players[player_id].library.put(card.state.match_instance_id, on_top)
	elif kind == "battlefield":
		card.position = Vector2(700, 900) if online() else manager.world.get_global_transform().affine_inverse() * Vector2(330, 230)
		card.state.position = card.position
	elif zone != null:
		card.position += Vector2((zone.members.size() - 1) * 20, 0)
		card.state.position = card.position
	refresh()
	manager.controls.status.text = "Card moved to %s %s." % [player_id, kind.capitalize()]
	return true
func assigned_zone(card: Control, zone: Control) -> void:
	if transitioning:
		return
	if zone != null and zone.zone_type in ["deck","library"]: Knowledge.entering(card.state,visibility)
	var publicly_revealed: bool = card.state.custom_metadata.get("public_reveal", false)
	for player: RefCounted in model.players.values():
		player.library.order.erase(card.state.match_instance_id)
	var kind: String = "battlefield" if zone == null else zone.zone_type
	if zone != null:
		card.state.zone_player_id = zone.player_id
	card.state.current_zone = "library" if kind == "deck" else kind
	if kind == "deck":
		model.players[card.state.zone_player_id].library.put(card.state.match_instance_id, true)
		card.set_face_down(true)
	elif kind == "hand":
		card.set_face_down(false)
		card.set_tapped(false)
	card.state.visibility = "owner_private" if kind in ["deck", "hand"] else ("face_down_public" if card.state.face_down else "public")
	if publicly_revealed:
		visibility.set_public_reveal(card.state, true)
	refresh()
func toggle_hand_reveal(card: Control) -> void:
	if manager.undo != null: manager.undo.invalidate("Hidden-information access is not undoable.")
	if card == null or card.state.current_zone != "hand" or card.state.zone_player_id != active_hand_player():
		return
	visibility.set_public_reveal(card.state, visibility.stable_visibility(card.state) != "public")
	refresh()
func draw_card(player_id: String = "local") -> void:
	if online() and player_id != "local":
		manager.controls.status.text = "The other player draws locally; only counts are shared."
		return
	var order: Array = model.players[player_id].library.order
	if order.is_empty():
		manager.controls.status.text = "Library is empty."
		return
	move_card(card_by_id(order[0]), "hand", true, player_id)
func shuffle_library(player_id: String = "local", searched: bool = false) -> void:
	if online() and player_id != "local":
		manager.controls.status.text = "The other player shuffles their private library locally."
		return
	model.players[player_id].library.shuffle()
	for id: String in model.players[player_id].library.order:
		var card: Control = card_by_id(id)
		Knowledge.forget_on_shuffle(card.state)
		card.set_face_down(true)
		card.state.visibility = "owner_private"
	hide_preview()
	refresh()
	manager.controls.status.text = "Library shuffled."
	record_event("search_shuffle" if searched else "shuffle", model.players[player_id].display_name + (" searched and shuffled their library" if searched else " shuffled their library"), {"player_id": player_id})
func reveal_top(player_id: String = "local") -> void:
	if manager.undo != null: manager.undo.invalidate("Hidden-information access is not undoable.")
	review.open_review(player_id, 1, false)
func show_preview(card: Control) -> void:
	if card == null or not (visibility.can_present(card.state, "local") or (playtest != null and playtest.local_playtest() and card.state.current_zone == "hand")): 
		hide_preview()
		return
	if hand_window != null and hand_window.detached and card.state.current_zone == "hand":
		hand_window.preview.texture = card.hover_preview.texture
		return
	preview.texture = card.hover_preview.texture
	preview.position = Vector2(maxf(0, get_viewport().get_visible_rect().size.x - 320), 20)
	preview.show()
func hide_preview() -> void:
	if hand_window != null and hand_window.preview != null: hand_window.preview.texture = null
	if preview != null:
		preview.hide()
func change_controller(card: Control, player_id: String) -> void:
	if manager.undo != null:
		manager.undo.begin("Change controller")
		manager.undo.finish.call_deferred()
	if card != null and model.players.has(player_id):
		card.state.controller_player_id = player_id
		refresh()
func change_life(player_id: String, amount: int) -> void:
	if manager.undo != null:
		manager.undo.begin("Life change")
		manager.undo.finish.call_deferred()
	var previous: int = model.players[player_id].life
	model.players[player_id].life += amount
	record_event("life", "%s life: %d → %d" % [model.players[player_id].display_name, previous, model.players[player_id].life], {"player_id": player_id, "before": previous, "after": model.players[player_id].life})
	manager.life = model.players.local.life
	manager.controls.life_label.text = "Life: %d" % manager.life
	refresh()
func apply_action() -> void:
	var card: Control = manager.selected_card
	if card == null:
		manager.controls.status.text = "Select a card first."
		return
	var destinations: Array[String] = ["hand", "battlefield", "graveyard", "exile", "commander", "library", "library"]
	if actions.selected < destinations.size():
		move_card(card, destinations[actions.selected], actions.selected != 6)
	else:
		card.set_face_down(actions.selected == 8)
		card.state.visibility = "face_down_public" if actions.selected == 8 else "public"
		refresh()
		if actions.selected == 7:
			show_preview(card)
func open_contents() -> void:
	open_library_view("local")
func open_library_view(player_id: String = "local") -> void:
	close_inspection()
	review.cancel()
	knowledge_view = true
	inspection_player = player_id
	inspection_zone = "library"
	search_player = ""
	contents_query.text = ""
	contents.title = player_id.capitalize()+" library · known cards only · order preserved"
	inspection_reveal_button.visible = false
	refresh_contents()
	contents.popup_centered_clamped(Vector2i(680,570),0.9)
func open_inspection(player_id: String, kind: String, reveal: bool = false) -> void:
	if manager.undo != null: manager.undo.invalidate("Hidden-information access is not undoable.")
	knowledge_view = false
	inspection_reveal_button.visible = true
	if online() and player_id != "local":
		public_sync.hidden.request(kind)
		return
	if review != null:
		review.cancel()
	end_inspection()
	model.synchronize(manager.cards)
	inspection_player = player_id
	inspection_zone = kind
	search_player = player_id if kind == "library" else ""
	inspection_reveal = reveal
	var states: Array = []
	for card: Control in manager.cards:
		if card.state.zone_player_id == player_id and card.state.current_zone == kind:
			states.append(card.state)
	visibility.begin(states, reveal)
	if kind == "library":
		for state: RefCounted in states: Knowledge.learn(state,"local")
	contents_query.text = ""
	contents_list.get_v_scroll_bar().value = 0
	contents.title = ("Reveal " if reveal else "Search ") + player_id + " " + kind + " · " + ("shuffles on close" if kind == "library" else "temporary access")
	refresh_contents()
	contents.popup_centered_clamped(Vector2i(680, 570), 0.9)
	refresh()
func inspected_card() -> Control:
	var indices: PackedInt32Array = contents_list.get_selected_items()
	return null if indices.is_empty() else card_by_id(str(contents_list.get_item_metadata(indices[0])))
func reveal_inspected() -> void:
	if remote_inspection:
		return # Identity is already visible only in this authorized inspection.
	var card: Control = inspected_card()
	if card != null:
		visibility.begin([card.state], true)
		if card.state.current_zone == "library": Knowledge.learn(card.state,"local")
		inspection_preview.texture = card.hover_preview.texture
		refresh()
func close_inspection() -> void:
	if contents != null:
		contents.hide()
	end_inspection()
func end_inspection() -> void:
	if remote_inspection:
		public_sync.hidden.close_outgoing()
		return
	var searched: String = search_player
	search_player = "" # Clear before visibility signals; one shuffle per search.
	model.synchronize(manager.cards)
	visibility.end(model.instances)
	if contents_list != null:
		contents_list.clear()
	if inspection_preview != null:
		inspection_preview.texture = null
	hide_preview()
	if manager.selected_card != null and not visibility.can_present(manager.selected_card.state, "local"):
		manager.selected_card.set_selected(false)
		manager.selected_card = null
	if not searched.is_empty() and model.players.has(searched):
		shuffle_library(searched, true)
	refresh()
func refresh_contents() -> void:
	if remote_inspection:
		public_sync.hidden.ui.refresh()
		return
	contents_list.clear()
	if knowledge_view:
		for row: Dictionary in library_rows(inspection_player):
			if not contents_query.text.is_empty() and (not row.known or not str(row.name).to_lower().contains(contents_query.text.to_lower())): continue
			contents_list.add_item("%d. %s" % [row.slot+1,row.name],row.texture)
			contents_list.set_item_metadata(contents_list.item_count-1,row.id)
		return
	var player: RefCounted = model.players[inspection_player]
	var ids: Array = player.library.order if inspection_zone == "library" else player.hand if inspection_zone == "hand" else player.leaders if inspection_zone == "commander" else player.get(inspection_zone)
	for i: int in ids.size():
		var card: Control = card_by_id(ids[i])
		if card == null: continue
		var shown: bool = visibility.can_see(card.state,"local") if inspection_zone in ["hand","library"] else visibility.can_present(card.state,"local")
		if not contents_query.text.is_empty() and (not shown or not card.state.display_name.to_lower().contains(contents_query.text.to_lower())): continue
		contents_list.add_item("%d. %s" % [i+1,card.state.display_name if shown else "Hidden card"],card.card_image.texture if shown else preload("res://scripts/battle/deck_back.gd").for_card(card,manager.backs))
		contents_list.set_item_metadata(contents_list.item_count - 1, ids[i])
func refresh() -> void:
	if count == null or batching:
		return
	model.synchronize(manager.cards)
	pile_view.refresh()
	opponent_pile.refresh()
	count.text = "Library: %d" % pile.order.size()
	count.tooltip_text = deck_name
	for card: Control in manager.cards:
		card.state.identity_visible = visibility.can_present(card.state, "local")
		card.card_back.texture = preload("res://scripts/battle/deck_back.gd").for_card(card,manager.backs)
		card.card_back.visible = card.state.face_down or not card.state.identity_visible
		if card.state.is_token:
			card.update_token_display()
		if card.token_label != null:
			card.token_label.visible = card.state.identity_visible and not card.state.face_down and (card.state.is_token or card.card_image.texture == null)
		if not card.state.identity_visible:
			card.hover_preview.hide()
		card.visible = manager.active and card.state.current_zone not in ["library", "hand"]
	if manager.perspective != null: manager.perspective.apply()
	hand.refresh()
	if hand_window != null: hand_window.refresh()
	if hearts != null: hearts.refresh()
	var public_faces: Array = []
	var far_player: String = "local" if playtest.local_playtest() and active_hand_player() == "opponent" else "opponent"
	for id: String in model.players[far_player].hand:
		var card: Control = card_by_id(id)
		public_faces.append(card.card_image.texture if visibility.can_present(card.state, "local") or playtest.local_playtest() else null)
	if online():
		var presentation: Dictionary = public_sync.serializer.projection.remote_hand()
		opponent_hand.present(hidden_count("opponent", "hand"), manager.backs.texture(), presentation.faces, presentation.names, manager.deck_backs.hand_textures("opponent"))
	else:
		opponent_hand.present(hidden_count(far_player, "hand"), manager.backs.texture(), [] if remote_hand_count >= 0 else public_faces, [], manager.deck_backs.hand_textures(far_player))
		if playtest.local_playtest(): opponent_hand.label.text = model.players[far_player].display_name+" hand: "+str(hidden_count(far_player,"hand"))
	opponent_hand.visible = manager.active and not hands_hidden
	hand.visible = manager.active and not hands_hidden and hand_open and (not loaded_ids.is_empty() or hand.row.get_child_count() > 0)
	if contents.visible:
		refresh_contents()
	manager.controls.update_selection()
	if manager.has_method("refresh_match_summary"):
		manager.refresh_match_summary()
	if manager.custom_table != null: manager.custom_table.refresh_presentation()
func set_active(value: bool) -> void:
	pile_view.visible = value
	opponent_pile.visible = value
	toolbar.hide()
	if not value:
		close_inspection()
		review.cancel()
	hide_preview()
	refresh()




func actor_name() -> String:
	return model.players[model.active_player].display_name
func record_event(kind: String, message: String, payload: Dictionary = {}) -> Dictionary:
	if manager.battle!=null and manager.battle.reset.rebuilding: return {}
	if manager.undo != null: manager.undo.event(kind)
	if online() and not public_sync.applying:
		manager.battle.queue_event(kind,payload)
	var event: Dictionary = {"event_id": Crypto.new().generate_random_bytes(16).hex_encode(), "kind": kind, "actor": model.active_player, "turn": model.turn_number, "text": message, "payload": payload.duplicate(true)}
	model.history.append(event)
	if model.history.size() > 1000:
		model.history.pop_front()
	if manager.extras != null:
		manager.extras.refresh_history()
	return event
func end_turn() -> void:
	if online() and not public_sync.applying:
		public_sync.scan()
		public_sync.submit([{"kind":"end_turn", "data":{}}])
		return
	record_event("end_turn", actor_name() + " ended turn")
	model.active_player = "opponent" if model.active_player == "local" else "local"
	model.turn_number += 1
	record_event("turn", "Turn %d — %s" % [model.turn_number, actor_name()])
	if manager.perspective != null: manager.perspective.after_turn()
	manager.refresh_match_summary()

func inspection_hover(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or not contents.visible:
		return
	var index: int = contents_list.get_item_at_position(event.position, true)
	if index >= 0:
		if remote_inspection:
			public_sync.hidden.ui.preview(index)
			return
		var card: Control = card_by_id(str(contents_list.get_item_metadata(index)))
		inspection_preview.texture = inspection_texture(index,card)

func library_rows(player: String) -> Array:
	var rows: Array = []
	var order: Array = model.players[player].library.order
	for slot: int in hidden_count(player,"library"):
		var row: Dictionary = {"slot":slot,"id":"","name":"Hidden card","texture":manager.deck_backs.library_texture(player),"known":false}
		if player == "opponent" and remote_library_count >= 0:
			var memory: Dictionary = remote_library_knowledge.get(str(slot),{})
			if not memory.is_empty() and public_sync != null:
				row.id = memory.id
				row.name = memory.name
				row.known = true
				var path: String = public_sync.serializer.resolve_art(memory.art)
				if not path.is_empty():
					if not manager.texture_cache.has(path): manager.texture_cache[path] = ImageTexture.create_from_image(Image.load_from_file(path))
					row.texture = manager.texture_cache[path]
		elif slot < order.size():
			var card: Control = card_by_id(order[slot])
			if card != null:
				row.id = card.state.match_instance_id
				row.texture = preload("res://scripts/battle/deck_back.gd").for_card(card,manager.backs)
				row.known = Knowledge.known(card.state,"local")
				if row.known:
					row.name = card.state.display_name
					row.texture = card.card_image.texture
		rows.append(row)
	return rows
func inspection_texture(index: int, card: Control) -> Texture2D:
	if knowledge_view: return contents_list.get_item_icon(index)
	if card == null: return null
	var shown: bool = visibility.can_see(card.state,"local") if inspection_zone in ["hand","library"] else visibility.can_present(card.state,"local")
	return card.hover_preview.texture if shown else preload("res://scripts/battle/deck_back.gd").for_card(card,manager.backs)

func open_public_zone(player: String, kind: String) -> void:
	if kind not in ["graveyard","exile","commander"]: return
	close_inspection()
	review.cancel()
	model.synchronize(manager.cards)
	inspection_player = player
	inspection_zone = kind
	knowledge_view = false
	remote_inspection = false
	search_player = ""
	contents_query.text = ""
	inspection_reveal_button.hide()
	contents.title = model.players[player].display_name+" · "+kind.capitalize()
	refresh_contents()
	contents.popup_centered_clamped(Vector2i(680,570),0.9)
func public_gallery_click(index: int, _point: Vector2, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_RIGHT or not inspection_zone in ["graveyard","exile","commander"] or remote_inspection: return
	var card: Control = card_by_id(str(contents_list.get_item_metadata(index)))
	if card == null: return
	close_inspection()
	manager.select_card(card)
	manager.controls.open_card_actions()
