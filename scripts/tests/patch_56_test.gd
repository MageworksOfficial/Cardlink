extends SceneTree
const Store = preload("res://scripts/card_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
const Decks = preload("res://scripts/deck_storage.gd")
const Backs = preload("res://scripts/card_back_service.gd")
const Pile = preload("res://scripts/library_pile.gd")
const Snapshot = preload("res://scripts/match_snapshot.gd")
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, caption: String) -> void:
	checks += 1
	print("PASS: " if value else "FAIL: ", caption)
	if not value:
		failures += 1
func press(point: Vector2, which: MouseButton, double: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = which
	event.pressed = true
	event.double_click = double
	return event
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://cache/milestone55/" + Crypto.new().generate_random_bytes(8).hex_encode()
	var cards_dir: String = base.path_join("cards")
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var image := Image.create(750, 1050, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var store := Store.new(cards_dir)
	var a: Dictionary = store.save_card(image.save_png_to_buffer(), "Azure secret", image.get_size())
	image.fill(Color.CORAL)
	var b: Dictionary = store.save_card(image.save_png_to_buffer(), "Coral secret", image.get_size())
	var deck: Dictionary = Decks.new_deck()
	deck.cards = [{"card_id": a.metadata.card_id, "quantity": 6}, {"card_id": b.metadata.card_id, "quantity": 6}]
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var table = main.tabletop
	var c = table.match_controller
	c.loader = Loader.new(cards_dir)
	table.backs.directory = base.path_join("settings")
	table.backs.reload()
	check(table.backs.texture() != null and table.backs.selected_id == "cardlink", "Built-in original CardLink back loads")
	c.load_deck(deck, false)
	c.load_deck(deck, false, "opponent")
	c.library_actions.draw_n("local", 2)
	c.library_actions.draw_n("opponent", 2)
	var local: Control = c.card_by_id(c.model.players.local.hand[0])
	var other: Control = c.card_by_id(c.model.players.local.hand[1])
	c.hand.row.get_child(0).gui_input.emit(press(Vector2(10, 10), MOUSE_BUTTON_RIGHT))
	table.controls.context_actions.set_hidden(false)
	table.controls.close_panels()
	check(local.state.visibility == "public", "Right-click Reveal action reveals selected hand card")
	check(c.hand.row.get_child(0).has_node("RevealBadge"), "Revealed hand card has eye badge")
	check(c.hand.row.get_child(0).get_node("RevealBadge").tooltip_text == "Opponent can currently see this card.", "Eye badge explains public identity")
	check(c.hand.row.get_child(0).texture == local.card_image.texture and c.visibility.can_present(local.state, "local"), "Owner still sees full revealed face")
	check(other.state.visibility == "owner_private" and not c.hand.row.get_child(1).has_node("RevealBadge"), "Other hand cards remain private without badges")
	c.hand.row.get_child(0).gui_input.emit(press(Vector2(10, 10), MOUSE_BUTTON_RIGHT))
	table.controls.context_actions.set_hidden(true)
	table.controls.close_panels()
	check(local.state.visibility == "owner_private" and not c.hand.row.get_child(0).has_node("RevealBadge"), "Right-click Hide action removes public badge")
	check(c.hand.row.get_child(0).texture == local.card_image.texture, "Owner still sees hidden hand face")
	c.toggle_hand_reveal(local)
	c.move_card(local, "hand", true, "opponent")
	var slot: int = c.model.players.opponent.hand.find(local.state.match_instance_id)
	check(c.opponent_hand.cards_row.get_child(slot).texture == local.card_image.texture, "Opponent row shows individually public face")
	check(c.opponent_hand.cards_row.get_child(0).texture == table.backs.texture(), "Other opponent cards still show backs")
	c.open_inspection("opponent", "hand", true)
	check(c.opponent_hand.cards_row.get_child(0).texture == table.backs.texture(), "Temporary inspection cannot reveal other normal hand slots")
	c.close_inspection()
	c.library_actions.put_nth(local, "local", 3)
	check(c.pile.order[2] == local.state.match_instance_id and local.state.visibility == "public", "Third-from-top move preserves public reveal")
	check(c.visibility.can_see(local.state, "opponent"), "Opponent can access revealed library identity")
	var restored = load("res://scripts/card_instance_state.gd").new()
	restored.restore(local.state.to_data())
	check(restored.visibility == "public" and restored.custom_metadata.get("public_reveal", false), "Existing serialization preserves persistent reveal")
	c.move_card(local, "battlefield")
	c.move_card(local, "hand")
	check(local.state.visibility == "public" and c.hand.row.get_child(0).has_node("RevealBadge") == (c.hand.row.get_child(0).instance_id == local.state.match_instance_id), "Reveal survives battlefield and hand transitions")
	c.move_card(local, "library")
	c.toggle_hand_reveal(other)
	c.shuffle_library()
	var all_hidden: bool = true
	for id: String in c.pile.order:
		var state = c.card_by_id(id).state
		all_hidden = all_hidden and state.visibility == "owner_private" and not state.custom_metadata.has("public_reveal")
	check(all_hidden and not c.visibility.can_see(local.state, "opponent"), "Shuffle clears all library public reveals")
	check(other.state.visibility == "public", "Shuffle does not hide revealed cards outside library")
	c.move_card(local, "hand")
	check(local.state.visibility == "owner_private", "Drawing after shuffle does not resurrect reveal")
	c.move_card(other, "battlefield")
	other.set_face_down(true)
	c.move_card(other, "hand")
	check(other.state.visibility == "owner_private", "Explicit face-down action clears persistent reveal")
	if OS.get_cmdline_user_args().size() > 1:
		c.toggle_hand_reveal(local)
		var opponent: Control = c.card_by_id(c.model.players.opponent.hand[0])
		c.visibility.set_public_reveal(opponent.state, true)
		c.refresh()
		table.controls.close_panels()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("patch56_hand_reveal.png"))
	await process_frame
	await process_frame
	print("PATCH 5.6: %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
