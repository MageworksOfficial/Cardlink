extends SceneTree
const Storage = preload("res://scripts/card_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
const Decks = preload("res://scripts/deck_storage.gd")
var failures: int = 0
var last_mouse: Vector2
func mouse_motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - last_mouse
	last_mouse = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, caption: String) -> void:
	print("PASS: " if value else "FAIL: ", caption)
	if not value:
		failures += 1
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://cache/milestone4/" + Crypto.new().generate_random_bytes(8).hex_encode()
	var cards_dir: String = base.path_join("cards")
	var decks_dir: String = base.path_join("decks")
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var store := Storage.new(cards_dir)
	var fixture := Image.create(750, 1050, false, Image.FORMAT_RGB8)
	fixture.fill(Color.CORNFLOWER_BLUE)
	store.save_card(fixture.save_png_to_buffer(), "Azure Guardian", Vector2i(750, 1050))
	fixture.fill(Color.CORAL)
	store.save_card(fixture.save_png_to_buffer(), "Coral Bard", Vector2i(750, 1050))
	var records: Array[Dictionary] = Loader.new(cards_dir).load_records()
	var first: String = records[0].metadata.card_id
	var second: String = records[1].metadata.card_id
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	await process_frame
	var table = main.tabletop
	var match_state = table.match_controller
	var builder = main.deck_builder
	builder.loader = Loader.new(cards_dir)
	builder.storage = Decks.new(decks_dir)
	match_state.loader = Loader.new(cards_dir)
	table.set_active(false)
	builder.open_builder()
	check(builder.visible and builder.catalog.item_count == 2, "Deck Builder opens and browses library")
	builder.query.text = "azure"
	builder.refresh_catalog()
	check(builder.catalog.item_count == 1, "Deck Builder searches library by name")
	builder.query.text = ""
	builder.refresh_catalog()
	builder.catalog.select(0)
	builder.add_selected()
	check(builder.deck.cards.size() == 1, "Add card from library")
	builder.set_quantity(0, 4)
	check(builder.deck.cards[0].quantity == 4 and builder.count.text.contains("4 cards"), "Quantities and deck total")
	builder.set_leader(0, true)
	builder.add_card(second if builder.deck.cards[0].card_id == first else first)
	builder.set_leader(1, true)
	check(builder.deck.leaders.size() == 2, "Multiple leader designation")
	builder.remove_selected()
	check(builder.deck.cards.size() == 1 and builder.deck.leaders.size() == 1, "Remove card and stale leader designation")
	builder.add_card(second if builder.deck.cards[0].card_id == first else first)
	builder.set_quantity(1, 3)
	builder.set_leader(1, true)
	builder.name_input.text = "Milestone Four"
	check(builder.save_current() and FileAccess.file_exists(builder.saved_path), "Save deck")
	var original: String = builder.saved_path
	var original_id: String = builder.deck.deck_id
	builder.new_deck()
	builder.deck_picker.select(0)
	builder.load_selected()
	check(builder.deck.deck_id == original_id and builder.deck.cards.size() == 2, "Load deck")
	builder.name_input.text = "Renamed deck"
	check(builder.save_current() and builder.deck.deck_name == "Renamed deck" and builder.saved_path == original, "Rename preserves ID and path")
	builder.name_input.text = "Unsaved name"
	builder.dirty = true
	builder.guard(func() -> void: pass)
	builder.discard_dialog.confirmed.emit()
	builder.discard_dialog.hide()
	check(builder.name_input.text == "Renamed deck" and not builder.dirty, "Discard restores last saved deck")
	builder.duplicate_current()
	check(builder.saved_path != original and builder.deck.deck_id != original_id and builder.storage.list_decks().size() == 2, "Duplicate creates independent saved deck")
	builder.request_delete()
	check(builder.delete_dialog.visible and FileAccess.file_exists(builder.saved_path), "Delete requires confirmation")
	builder.delete_dialog.confirmed.emit()
	builder.delete_dialog.hide()
	check(builder.storage.list_decks().size() == 1 and FileAccess.file_exists(original), "Confirmed delete removes only selected deck")
	builder.deck_picker.select(0)
	builder.load_selected()
	var deck: Dictionary = builder.deck.duplicate(true)
	builder.hide()
	table.set_active(true)
	check(table.cards[0].size == Vector2(100, 140), "Practical battlefield scale")
	table.view.zoom_by(1.2)
	check(is_equal_approx(table.world.scale.x, 1.2), "Zoom in")
	table.view.zoom_by(1.0 / 1.2)
	check(is_equal_approx(table.world.scale.x, 1.0), "Zoom out")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	table.view._input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(45, 20)
	table.view._input(motion)
	check(table.view.pan.is_equal_approx(Vector2(45, 20)), "Middle mouse pan")
	press.pressed = false
	table.view._input(press)
	table.view.reset_view()
	check(table.world.position.y == 65 and table.world.scale.x >= 0.4 and table.world.scale.x <= 0.8, "Reset view")
	var result: Dictionary = match_state.load_deck(deck, true)
	check(not result.has("error") and match_state.loaded_ids.size() == 7, "Saved deck creates seven match copies")
	check(match_state.pile.order.size() == 5 and match_state.count.text == "Library: 5", "Library excludes one copy of each of two leaders")
	var unique: Dictionary = {}
	var leader_count: int = 0
	for id: String in match_state.loaded_ids:
		unique[id] = true
		var card: Control = match_state.card_by_id(id)
		if card.state.current_zone == "commander":
			leader_count += 1
	check(unique.size() == 7 and leader_count == 2, "Unique match IDs and multiple leaders outside library")
	var before: Array = match_state.pile.order.duplicate()
	var changed: bool = false
	for iteration: int in 10:
		match_state.shuffle_library()
		changed = changed or before != match_state.pile.order
	var sorted_before: Array = before.duplicate()
	var sorted_after: Array = match_state.pile.order.duplicate()
	sorted_before.sort()
	sorted_after.sort()
	check(changed and sorted_before == sorted_after, "Shuffle changes order and preserves all instance IDs")
	var top_id: String = match_state.pile.order[0]
	match_state.reveal_top()
	check(match_state.review.visible and match_state.review.preview.texture != null and match_state.pile.order[0] == top_id, "Reveal top in temporary inspection without drawing")
	match_state.review.cancel()
	match_state.draw_card()
	var drawn: Control = match_state.card_by_id(top_id)
	check(match_state.pile.order.size() == 4 and drawn.state.current_zone == "hand" and not drawn.visible, "Draw removes top into hand")
	check(match_state.hand.row.get_child_count() == 1, "Drawn card displayed in compact hand")
	match_state.show_preview(drawn)
	check(match_state.preview.visible, "Hand hover preview")
	match_state.hide_preview()
	check(table.world._can_drop_data(Vector2.ZERO, {"cardlink_instance": top_id}), "Hand drag data accepted")
	table.world._drop_data(Vector2(350, 250), {"cardlink_instance": top_id})
	check(drawn.state.current_zone == "battlefield" and drawn.visible and match_state.hand.row.get_child_count() == 0, "Hand card plays onto tabletop")
	match_state.move_card(drawn, "hand")
	check(drawn.state.current_zone == "hand" and match_state.hand.row.get_child_count() == 1, "Battlefield card returns to hand")
	match_state.move_card(drawn, "library", true)
	check(match_state.pile.order[0] == top_id, "Top-of-library placement")
	match_state.move_card(drawn, "library", false)
	check(match_state.pile.order.back() == top_id and match_state.pile.order.count(top_id) == 1, "Bottom-of-library placement without duplicates")
	match_state.move_card(drawn, "graveyard")
	var previous: Control = table.find_zone(drawn.state.zone_id)
	check(drawn.state.current_zone == "graveyard" and previous.members.has(top_id), "Graveyard transition")
	match_state.move_card(drawn, "exile")
	check(drawn.state.current_zone == "exile" and not previous.members.has(top_id), "Exile transition clears previous membership")
	drawn.set_face_down(true)
	drawn._on_mouse_entered()
	check(drawn.card_back.visible and not drawn.hover_preview.visible, "Face down conceals art and hover")
	drawn.set_face_down(false)
	check(not drawn.card_back.visible, "Reveal restores art")
	match_state.open_contents()
	check(match_state.contents_list.item_count == match_state.pile.order.size(), "Local library contents viewer")
	match_state.contents_query.text = "no matching name"
	match_state.refresh_contents()
	check(match_state.contents_list.item_count == 0, "Library contents search")
	match_state.contents.hide()
	var bad: Dictionary = deck.duplicate(true)
	bad.cards[0].quantity = -1
	check(match_state.load_deck(bad, true).has("error"), "Reject invalid quantities")
	bad = deck.duplicate(true)
	bad.cards[0].card_id = "missing"
	bad.leaders = []
	check(match_state.load_deck(bad, true).has("error") and match_state.loaded_ids.size() == 7, "Missing definition preserves current match")
	bad = deck.duplicate(true)
	bad.leaders.append("missing_leader")
	check(match_state.load_deck(bad, true).has("error"), "Missing leader rejected safely")
	check(match_state.load_deck(Decks.new_deck(), true).has("error"), "Empty deck rejected safely")
	var file := FileAccess.open(decks_dir.path_join("malformed.json"), FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var saw_error: bool = false
	for row: Dictionary in builder.storage.list_decks():
		saw_error = saw_error or str(row.error).contains("Malformed")
	check(saw_error, "Malformed JSON reported without crashing")
	file = FileAccess.open(decks_dir.path_join("collision.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(deck))
	file.close()
	var collisions: int = 0
	for row: Dictionary in builder.storage.list_decks():
		if str(row.error).contains("Duplicate"):
			collisions += 1
	check(collisions == 2 and builder.storage.save_deck(deck, original).has("error"), "Duplicate deck IDs detected and overwrite prevented")
	check(builder.storage.save_deck(deck, base.path_join("escape.json")).has("error"), "Outside-storage path refused")
	var missing_asset: String = str(records[0].image_path)
	DirAccess.rename_absolute(missing_asset, missing_asset + ".hold")
	check(match_state.load_deck(deck, true).has("error") and match_state.loaded_ids.size() == 7, "Missing image preserves current match")
	DirAccess.rename_absolute(missing_asset + ".hold", missing_asset)
	check(not match_state.load_deck(deck, false).has("error") and match_state.pile.order.size() == 7, "Leaders may remain in main library")
	while not match_state.pile.order.is_empty():
		match_state.draw_card()
	match_state.draw_card()
	check(match_state.hand.row.get_child_count() == 7 and match_state.pile.order.is_empty(), "Repeated draws and empty-library handling")
	await process_frame
	await process_frame
	var hand_item: Control = match_state.hand.row.get_child(0)
	var actual_id: String = hand_item.instance_id
	var press_point: Vector2 = hand_item.get_global_rect().get_center()
	mouse_motion(press_point)
	mouse_button(press_point, true)
	mouse_motion(press_point + Vector2(25, -25), true)
	mouse_motion(Vector2(390, 280), true)
	mouse_button(Vector2(390, 280), false)
	await process_frame
	var actual: Control = match_state.card_by_id(actual_id)
	check(actual.state.current_zone == "battlefield" and actual.visible, "Injected GUI drag plays a hand card")
	table.view.zoom = 1.0
	table.view.pan = Vector2.ZERO
	table.view.apply_view()
	# Set a known visible location for the independent zoom interaction test.
	actual.position = Vector2(340, 210)
	table.view.zoom_by(1.2)
	await process_frame
	var old_position: Vector2 = actual.position
	press_point = actual.get_global_rect().get_center()
	mouse_motion(press_point)
	mouse_button(press_point, true)
	mouse_motion(press_point + Vector2(60, 30), true)
	mouse_button(press_point + Vector2(60, 30), false)
	check(actual.position.is_equal_approx(old_position + Vector2(50, 25)), "Card drag coordinates respect tabletop zoom")
	actual._on_mouse_entered()
	check(actual.hover_preview.get_global_rect().size.is_equal_approx(Vector2(375, 525)), "Hover remains large and independent of zoom")
	actual._on_mouse_exited()
	table.view.reset_view()
	var limited: Control = match_state.zone_for("commander")
	limited.capacity = 1
	var ids_before: Array = match_state.loaded_ids.duplicate()
	check(match_state.load_deck(deck, true).has("error") and match_state.loaded_ids == ids_before, "Leader capacity failure preserves current match")
	limited.capacity = 0
	var generic: Control = table.add_zone({"display_name": "Test deck", "zone_type": "deck", "position": Vector2(900, 200)})
	table.assign_zone(actual, generic)
	check(actual.state.current_zone == "library" and match_state.pile.order.has(actual_id) and not actual.visible, "Generic deck-zone action updates playable library")
	match_state.draw_card()
	check(actual.state.current_zone == "hand" and generic.members.is_empty(), "Drawing clears generic zone membership")
	check(table.controls.selected_label.text.contains("Hand"), "Selected-card label follows hand transition")
	for invalid: Variant in [0, 1.5, "2", true, 1001]:
		bad = deck.duplicate(true)
		bad.cards[0].quantity = invalid
		check(not Decks.validate(bad).is_empty(), "Invalid quantity rejected: " + str(invalid))
	builder.play_requested.emit(deck, true)
	check(main.replace_deck.visible and match_state.loaded_ids == ids_before, "Play signal requires confirmation before replacing match")
	main.replace_deck.confirmed.emit()
	main.replace_deck.hide()
	check(not builder.visible and table.active and match_state.pile.order.size() == 5 and match_state.loaded_ids != ids_before, "Confirmed Save and play integration loads fresh copies")
	if OS.get_cmdline_user_args().size() > 1:
		generic.hide()
		match_state.draw_card()
		match_state.draw_card()
		for card: Control in table.cards:
			if card.state.current_zone == "hand":
				match_state.move_card(card, "battlefield")
				card.position = Vector2(330, 160)
				break
		builder.storage.delete_deck(decks_dir.path_join("collision.json"))
		builder.storage.delete_deck(decks_dir.path_join("malformed.json"))
		root.size = Vector2i(1152, 648)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("tabletop_m4.png"))
		table.set_active(false)
		builder.open_builder()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("deck_builder_m4.png"))
	print("MILESTONE 4 COMPLETE: failures=", failures)
	quit(1 if failures else 0)
