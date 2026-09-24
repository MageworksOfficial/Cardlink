extends SceneTree
const Store = preload("res://scripts/card_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
const Decks = preload("res://scripts/deck_storage.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", caption)
func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, pressed: bool = true, ctrl: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = point
	e.button_index = button
	e.pressed = pressed
	e.ctrl_pressed = ctrl
	return e
func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e
func route(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var image := Image.create(750, 1050, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var store := Store.new(base.path_join("cards"))
	var a: Dictionary = store.save_card(image.save_png_to_buffer(), "Selection card", image.get_size())
	var deck: Dictionary = Decks.new_deck()
	deck.cards = [{"card_id": a.metadata.card_id, "quantity": 18}]
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var t: Node = main.tabletop
	var c: Node = t.match_controller
	c.loader = Loader.new(base.path_join("cards"))
	c.load_deck(deck, false)
	c.load_deck(deck, false, "opponent")
	var s: Control = t.selection
	var h: Node = t.shortcuts
	h.layout_button.pressed.emit()
	check(t.layout.edit_mode, "Upper-right Layout button enables editing")
	h._unhandled_key_input(key(KEY_L))
	check(not t.layout.edit_mode, "L disables Layout Mode")
	await process_frame
	check(h.layout_button.text == "Layout: Off [L]", "Layout state label is explicit")
	var one: Control = c.card_by_id(c.pile.order[0])
	var two: Control = c.card_by_id(c.pile.order[1])
	c.move_card(one, "battlefield")
	c.move_card(two, "battlefield")
	one.position = Vector2(300, 350)
	two.position = Vector2(440, 350)
	var counter: Control = t.extras.create_counter(Vector2(580, 350))
	t.world._gui_input(click(Vector2(280, 330)))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(680, 510)
	t.world._gui_input(motion)
	check(s.marquee and s.finish == motion.position, "Dragging empty field draws a selection rectangle")
	t.world._gui_input(click(motion.position, MOUSE_BUTTON_LEFT, false))
	check(s.ids.size() == 3 and s.ids.has(counter.instance_id), "Marquee selects two cards and a standalone counter")
	check(one.is_selected and two.is_selected, "Selected cards show highlights")
	var hand_position: Vector2 = c.hand.position
	var counter_position: Vector2 = counter.position
	t.view.zoom_by(0.5)
	one._gui_input(click(Vector2(10, 10)))
	motion.position = Vector2(50, 35)
	one._gui_input(motion)
	one._gui_input(click(Vector2(10, 10), MOUSE_BUTTON_LEFT, false))
	check(one.position == Vector2(340, 375) and two.position == Vector2(480, 375) and counter.position == counter_position + Vector2(40, 25), "Group drag preserves offsets at reduced zoom")
	check(c.hand.position == hand_position, "Group drag leaves fixed hand unchanged")
	one._gui_input(click(Vector2(5, 5), MOUSE_BUTTON_RIGHT))
	check(s.bulk.visible and not one.tapped, "Right-click selected group opens bulk menu without tapping")
	s.bulk.hide()
	two._gui_input(click(Vector2(10, 10), MOUSE_BUTTON_LEFT, true, true))
	check(not s.ids.has(two.state.match_instance_id), "Ctrl-click removes individual selection")
	two._gui_input(click(Vector2(10, 10), MOUSE_BUTTON_LEFT, true, true))
	check(s.ids.has(two.state.match_instance_id), "Ctrl-click adds individual selection")
	var pair: Array = [one.state.match_instance_id, two.state.match_instance_id]
	s.apply_batch("tap", pair)
	check(one.tapped and two.tapped, "Tap All")
	s.apply_batch("untap", pair)
	check(not one.tapped and not two.tapped, "Untap All")
	s.apply_batch("opponent", pair)
	check(one.state.controller_player_id == "opponent" and one.state.owner_player_id == "local", "Bulk controller change preserves ownership")
	s.apply_batch("graveyard", pair)
	check(one.state.current_zone == "graveyard" and two.state.current_zone == "graveyard", "Bulk graveyard move")
	s.apply_batch("exile", pair)
	check(one.state.current_zone == "exile" and two.state.current_zone == "exile", "Bulk exile move")
	s.apply_batch("hand", pair)
	check(one.state.current_zone == "hand" and two.state.current_zone == "hand", "Bulk hand move")
	c.move_card(one, "battlefield")
	c.move_card(two, "battlefield")
	s.apply_batch("top", pair)
	check(c.pile.order.slice(0, 2) == pair, "Bulk top preserves selected relative order")
	c.move_card(one, "battlefield")
	c.move_card(two, "battlefield")
	s.apply_batch("bottom", pair)
	check(c.pile.order.slice(c.pile.order.size() - 2) == pair, "Bulk bottom preserves selected relative order")
	c.move_card(one, "battlefield")
	t.select_card(one)
	h._unhandled_key_input(key(KEY_DELETE))
	check(one.state.current_zone == "graveyard" and one.state.zone_player_id == "local", "Delete normal card sends to owner's graveyard despite different controller")
	var token: Control = t.create_token("Wolf", "local", "local").card
	var token_id: String = token.state.match_instance_id
	t.select_card(token)
	h._unhandled_key_input(key(KEY_DELETE))
	check(c.card_by_id(token_id) == null, "Delete destroys token instance")
	var counter_id: String = counter.instance_id
	s.apply_batch("delete", [counter_id])
	check(t.extras.counter_by_id(counter_id) == null, "Delete removes standalone counter")
	check(c.loader.load_records().size() == 1 and FileAccess.file_exists(a.metadata_path), "Object deletion preserves card definition and image")
	c.move_card(one, "hand")
	c.toggle_hand_reveal(one)
	c.move_card(one, "library")
	check(c.pile_view.back_image.texture == one.card_image.texture, "Revealed top immediately shows card face")
	var n: int = c.pile.order.size()
	h._unhandled_key_input(key(KEY_D))
	check(c.pile.order.size() == n - 1 and one.state.current_zone == "hand", "D draws one local card")
	t.select_card(one)
	h._unhandled_key_input(key(KEY_F))
	check(one.state.current_zone == "graveyard", "F discards selected local-hand card")
	s.clear()
	h._unhandled_key_input(key(KEY_F))
	check(t.controls.status.text.contains("Select a card"), "F without selection safely shows status")
	var opponent_card: Control = c.card_by_id(c.model.players.opponent.library.order[0])
	c.move_card(opponent_card, "hand", true, "opponent")
	t.select_card(opponent_card)
	h._unhandled_key_input(key(KEY_F))
	check(opponent_card.state.current_zone == "hand", "F ignores opponent-hand selection")
	c.move_card(one, "library")
	h._unhandled_key_input(key(KEY_S))
	check(one.state.visibility == "owner_private" and not one.state.custom_metadata.has("public_reveal"), "S shuffles and hides public library cards")
	check(c.pile_view.back_image.texture == t.backs.texture(), "Hidden top displays configured card back")
	var line := LineEdit.new()
	main.add_child(line)
	line.grab_focus()
	await process_frame
	n = c.pile.order.size()
	var history_size: int = c.model.history.size()
	for code: Key in [KEY_D, KEY_S, KEY_L, KEY_F, KEY_DELETE]:
		h._unhandled_key_input(key(code))
	check(c.pile.order.size() == n and c.model.history.size() == history_size and not t.layout.edit_mode, "Text input blocks all shortcuts")
	line.release_focus()
	line.queue_free()
	var text := TextEdit.new()
	main.add_child(text)
	text.grab_focus()
	await process_frame
	check(h.blocked(), "Multiline text editing blocks shortcuts")
	text.release_focus()
	text.queue_free()
	c.open_inspection("local", "library")
	check(h.blocked(), "Open inspection blocks shortcuts")
	history_size = c.model.history.size()
	c.close_inspection()
	check(c.model.history.size() == history_size + 1 and c.model.history.back().kind == "search_shuffle", "Library search close shuffles exactly once and records history")
	c.close_inspection()
	check(c.model.history.size() == history_size + 1, "Repeated close cannot shuffle again")
	c.open_inspection("opponent", "library", true)
	c.close_inspection()
	check(c.model.history.back().text.contains("searched and shuffled") and opponent_card.state.current_zone == "hand", "Opponent library inspection shuffles only that library")
	var private: bool = true
	for id: String in c.model.players.opponent.library.order:
		private = private and c.card_by_id(id).state.visibility == "owner_private"
	check(private, "Search close restores library hidden information")
	var order: Array = c.pile.order.duplicate()
	history_size = c.model.history.size()
	c.review.open_review("local", 3, false)
	c.review.cancel()
	check(c.pile.order == order and c.model.history.size() == history_size, "Reveal Top N does not shuffle")
	c.review.open_review("local", 3, true)
	c.review.cancel()
	check(c.pile.order == order and c.model.history.size() == history_size, "Scry cancel does not shuffle")
	c.review.open_review("local", 3, true)
	c.review.top.reverse()
	var expected: Array = order.duplicate()
	for i: int in 3:
		expected[i] = c.review.top[i]
	c.review.confirm_review()
	check(c.pile.order == expected and c.model.history.size() == history_size, "Scry confirmation preserves chosen order without shuffle")
	h.open_help()
	check(h.help.visible and h.blocked(), "Controls help opens screen-fixed and blocks shortcuts")
	h.help.close_requested.emit()
	check(not h.help.visible, "Controls help closes cleanly")
	t.world._gui_input(click(Vector2(900, 550)))
	t.world._gui_input(click(Vector2(900, 550), MOUSE_BUTTON_LEFT, false))
	check(s.ids.is_empty() and t.selected_card == null, "Click empty field clears selection")
	c.move_card(one, "battlefield")
	c.move_card(two, "battlefield")
	one.position = Vector2(340, 380)
	two.position = Vector2(470, 380)
	# Injected pointer coordinates use a fixed camera; default-fit tested separately.
	t.view.zoom = 1.0
	t.view.pan = Vector2.ZERO
	t.view.apply_view()
	await process_frame
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(310, 375)
	route(motion)
	route(click(motion.position))
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(600, 540)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	route(motion)
	await process_frame
	check(s.marquee, "Real GUI empty-field drag reaches marquee handler")
	route(click(motion.position, MOUSE_BUTTON_LEFT, false))
	check(s.ids.has(one.state.match_instance_id) and s.ids.has(two.state.match_instance_id), "Real GUI marquee selects both cards")
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(355, 395)
	route(motion)
	route(click(motion.position))
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(370, 405)
	motion.relative = Vector2(15, 10)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	route(motion)
	route(click(motion.position, MOUSE_BUTTON_LEFT, false))
	check(one.position == Vector2(355, 390) and two.position == Vector2(485, 390), "Real GUI group drag moves both cards")
	check(not one.dragging and not two.dragging, "Group release clears drag state")
	check(not h.layout_button.get_global_rect().intersects(c.opponent_pile.get_global_rect()), "Upper-right Layout button avoids default opponent pile")
	var has_batch: bool = false
	var has_discard: bool = false
	var has_destroy: bool = false
	for entry: Dictionary in c.model.history:
		has_batch = has_batch or entry.kind == "batch"
		has_discard = has_discard or entry.kind == "discard"
		has_destroy = has_destroy or entry.kind == "token_destroyed"
	check(has_batch and has_discard and has_destroy, "History includes bulk actions, discard and token destruction")
	t.extras.token_editor.open_token(null)
	check(h.blocked(), "Token editor blocks shortcuts")
	t.extras.close_all()
	t.extras.tools_window.popup_centered()
	check(h.blocked(), "Dice/calculator panel blocks shortcuts")
	t.extras.close_all()
	if OS.get_cmdline_user_args().size() > 1:
		c.move_card(one, "battlefield")
		c.move_card(two, "battlefield")
		one.position = Vector2(340, 380)
		two.position = Vector2(470, 380)
		t.view.reset_view()
		s.select_rect(Rect2(300, 340, 300, 220))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("patch59.png"))
		h.open_help()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("patch59_controls.png"))
		h.help.hide()
	main.queue_free()
	await process_frame
	print("PATCH 5.9: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


