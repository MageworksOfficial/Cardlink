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
	deck.cards = [{"card_id": a.metadata.card_id, "quantity": 24}, {"card_id": b.metadata.card_id, "quantity": 24}]
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
	var extra: Node = table.extras
	table.token_art_directory = base.path_join("token_art")
	var thick: int = c.pile_view.stack_depth
	check(thick > 1 and c.pile_view.caption.text.contains("48"), "Pile thickness and count represent large deck")
	c.library_actions.draw_n("local", 42)
	check(c.pile_view.stack_depth < thick and c.pile_view.caption.text.contains("6"), "Pile thins when cards are drawn")
	var card: Control = c.card_by_id(c.model.players.local.hand[0])
	c.toggle_hand_reveal(card)
	c.move_card(card, "library")
	check(c.pile_view.back_image.texture == card.card_image.texture, "Revealed top shows face")
	c.shuffle_library()
	check(c.pile_view.back_image.texture == table.backs.texture(), "Shuffled hidden top shows back")
	c.open_inspection("opponent", "library", true)
	check(c.contents_list.item_count == 48 and c.contents_list.get_item_icon(0) != null, "Inspection gallery displays card images")
	check(c.contents_list.icon_mode == ItemList.ICON_MODE_TOP and c.contents_list.get_item_metadata(0) == c.model.players.opponent.library.order[0], "Gallery preserves library order")
	await process_frame
	await process_frame
	var scroll: ScrollBar = c.contents_list.get_v_scroll_bar()
	check(scroll.max_value > scroll.page, "Image gallery has scrollable overflow")
	scroll.value = scroll.max_value
	check(scroll.value > 0, "Image gallery scroll changes viewport")
	c.contents_list.select(0)
	c.contents_list.item_selected.emit(0)
	check(c.inspection_preview.texture != null, "Selecting gallery card enlarges preview")
	check(c.opponent_pile.back_image.texture != table.backs.texture(), "Intentional inspection learns top for this viewer until shuffle")
	c.close_inspection()
	check(c.contents_list.item_count == 0 and c.inspection_preview.texture == null and c.visibility.inspection_ids.is_empty(), "Closing inspection clears thumbnails preview and access")
	table.world._gui_input(press(Vector2(720, 320), MOUSE_BUTTON_RIGHT))
	check(extra.field_menu.visible, "Right-click empty field opens context menu")
	extra.field_menu.hide()
	check(table.controls.size.x < 240 and table.controls.size.y < 70, "Controls reduced to a small corner menu")
	extra.open_corner()
	check(extra.corner.item_count >= 9 and extra.corner.visible, "Corner menu exposes all fallback functions")
	extra.corner.hide()
	extra.field_action(0)
	check(extra.token_editor.visible, "Context Create Token opens editor")
	extra.token_editor.caption.text = "Wolf"
	extra.token_editor.power.text = "2"
	extra.token_editor.toughness.text = "3"
	extra.token_editor.owner_picker.select(1)
	extra.token_editor.controller.select(0)
	extra.token_editor.save_token()
	var token: Control = table.selected_card
	var token_id: String = token.state.match_instance_id
	check(token.state.is_token and token.state.owner_player_id == "opponent" and token.state.controller_player_id == "local", "Token creation preserves independent owner/controller")
	check(token.token_label.text.contains("2/3"), "Power/toughness appears on token")
	token._gui_input(press(Vector2(10, 10), MOUSE_BUTTON_LEFT, true))
	check(token.state.tapped,"Double-click token now quick-taps")
	token._gui_input(press(Vector2(10,10),MOUSE_BUTTON_RIGHT))
	for action: Button in table.controls.card_actions:
		if action.text == "Token Properties": action.pressed.emit()
	check(extra.token_editor.visible and extra.token_editor.editing_id == token_id, "Right-click Token Properties opens editor")
	extra.token_editor.caption.text = "Wolf Alpha"
	extra.token_editor.power.text = "4"
	extra.token_editor.controller.select(1)
	extra.token_editor.save_token()
	check(token.state.display_name == "Wolf Alpha" and token.state.custom_metadata.power == "4" and token.state.controller_player_id == "opponent", "Token properties edit name stats and controller")
	var art: String = base.path_join("token_source.png")
	image.save_png(art)
	var imported: Dictionary = preload("res://scripts/token_service.gd").import_art(art, table.token_art_directory)
	check(imported.has("path") and FileAccess.file_exists(imported.path), "Optional token art imported into managed storage")
	extra.token_editor.open_token(token)
	extra.token_editor.art_path = imported.path
	extra.token_editor.save_token()
	check(token.card_image.texture != null and token.state.image_path == imported.path, "Token Change Art displays chosen image")
	token.set_tapped(true)
	token.state.set_counter("Charge", 3)
	var duplicate: Control = c.library_actions.duplicate_token(token).card
	check(duplicate.state.match_instance_id != token_id and duplicate.state.display_name == token.state.display_name and duplicate.state.custom_metadata.power == "4" and duplicate.state.image_path == token.state.image_path and duplicate.tapped, "Duplicate token inherits properties with unique identity")
	for kind: String in ["graveyard", "exile", "hand", "library", "commander"]:
		var departing: Control = c.library_actions.duplicate_token(token).card
		var id: String = departing.state.match_instance_id
		c.move_card(departing, kind)
		check(c.card_by_id(id) == null and not c.pile.order.has(id), "Token disappears when moved to " + kind)
	var physical: Control = c.library_actions.duplicate_token(token).card
	var physical_id: String = physical.state.match_instance_id
	table.assign_zone(physical, c.zone_for("graveyard"))
	check(c.card_by_id(physical_id) == null, "Physical zone movement obeys token lifecycle")
	var indexed: Control = c.library_actions.duplicate_token(token).card
	var indexed_id: String = indexed.state.match_instance_id
	c.library_actions.put_nth(indexed, "local", 3)
	check(c.card_by_id(indexed_id) == null and not c.pile.order.has(indexed_id), "Indexed library insertion does not leave deleted token ID")
	extra.field_action(1)
	var counter: Control = extra.counters[0]
	check(counter.value == 1 and counter.label.text.contains("★ 1"), "Context creates standalone star counter")
	extra.counter_name.text = "Storm"
	extra.counter_value.value = 7
	extra.save_counter()
	check(counter.value == 7 and counter.caption == "Storm", "Counter value and label editable")
	for button: Node in extra.counter_window.find_children("*", "Button", true, false):
		if button.text == "+1":
			button.pressed.emit()
	check(counter.value == 8, "Counter increase button works")
	for button: Node in extra.counter_window.find_children("*", "Button", true, false):
		if button.text == "-1":
			button.pressed.emit()
	check(counter.value == 7, "Counter decrease button works")
	var temporary: Control = extra.create_counter(Vector2(200, 350))
	var temporary_id: String = temporary.instance_id
	extra.open_counter(temporary)
	for button: Node in extra.counter_window.find_children("*", "Button", true, false):
		if button.text == "Delete counter":
			button.pressed.emit()
	check(extra.counter_by_id(temporary_id) == null, "Counter delete button removes object")
	extra.counter_window.hide()
	counter._gui_input(press(Vector2(3, 3), MOUSE_BUTTON_LEFT))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(23, 13)
	var old_position: Vector2 = counter.position
	counter._gui_input(motion)
	check(counter.position == old_position + Vector2(20, 10), "Standalone counter drags")
	counter.dragging = false
	extra.close_all()
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	var old_pan: Vector2 = table.view.pan
	table.shortcuts.handle_key(key)
	check(table.view.pan == old_pan + Vector2(-40, 0), "Arrow key pans camera")
	key.shift_pressed = true
	table.shortcuts.handle_key(key)
	check(table.view.pan == old_pan + Vector2(-160, 0), "Shift arrow pans faster")
	var edit := LineEdit.new()
	main.add_child(edit)
	edit.grab_focus()
	old_pan = table.view.pan
	table.shortcuts.handle_key(key)
	check(table.view.pan == old_pan, "Typing focus blocks camera arrows")
	edit.release_focus()
	edit.queue_free()
	table.view.reset_view()
	check(table.view.zoom >= 0.4 and table.view.zoom <= 0.8 and table.view.pan.y == 65, "Reset View preserved")
	var d6: Dictionary = extra.tools.roll(1, 6)
	check(d6.payload.total >= 1 and d6.payload.total <= 6, "D6 rolls within bounds")
	var d20: Dictionary = extra.tools.roll(1, 20)
	check(d20.payload.total >= 1 and d20.payload.total <= 20, "D20 rolls within bounds")
	var dice: Dictionary = extra.tools.roll_text("3d6")
	check(dice.payload.values.size() == 3 and dice.payload.total >= 3 and dice.payload.total <= 18, "Custom dice produce individual values and total")
	for bad: String in ["0d6", "101d6", "2d1001", "-1d6", "2.5d6", "hello"]:
		check(extra.tools.roll_text(bad).has("error"), "Invalid dice rejected: " + bad)
	check(extra.tools.flip().payload.side in ["Heads", "Tails"], "Coin flip returns Heads or Tails")
	check(extra.tools.calculate("(40 - 3) * 2").value == 74, "Calculator evaluates arithmetic")
	check(extra.tools.calculate("5 / 2").value == 2.5, "Calculator supports fractional division")
	check(extra.tools.calculate("OS.execute(1)").has("error") and extra.tools.calculate("1 / 0").has("error"), "Calculator rejects code and division by zero")
	check(c.model.history.any(func(row: Dictionary) -> bool: return row.kind == "dice") and c.model.history.any(func(row: Dictionary) -> bool: return row.kind == "coin"), "Dice and coin results recorded in history")
	c.change_life("local", -3)
	check(c.model.history[-1].kind == "life" and c.model.history[-1].text.contains("40 → 37"), "Life changes recorded with old and new values")
	var hand_count: int = c.model.players.local.hand.size()
	c.end_turn()
	check(c.model.active_player == "opponent" and c.model.turn_number == 2, "End Turn switches active player and advances turn")
	check(c.model.history[-2].kind == "end_turn" and c.model.history[-1].kind == "turn", "End Turn records both transition events")
	check(token.tapped and c.model.players.local.hand.size() == hand_count, "End Turn does not untap or draw")
	c.end_turn()
	check(c.model.active_player == "local" and c.model.turn_number == 3, "Next individual turn returns to local player")
	extra.toggle_history()
	check(extra.history_window.visible and extra.history_text.text.contains("rolled D20"), "History panel displays human-readable events")
	extra.toggle_history()
	check(not extra.history_window.visible, "History collapses cleanly")
	card = c.card_by_id(c.model.players.local.hand[0])
	var revealed_id: String = card.state.match_instance_id
	c.toggle_hand_reveal(card)
	c.move_card(card, "library")
	var saved: Dictionary = table.persistence.capture_match()
	check(Snapshot.validate(saved).is_empty(), "New match state passes snapshot validation")
	table.persistence.matches = preload("res://scripts/match_save_storage.gd").new(base.path_join("matches"))
	var disk_save: Dictionary = table.persistence.save_match("Milestone 5.7 round trip")
	check(not disk_save.has("error") and FileAccess.file_exists(disk_save.path), "New match state saved to JSON on disk")
	var history_count: int = c.model.history.size()
	check(not table.persistence.load_match(disk_save.path).has("error"), "Match loads new state from disk")
	check(c.model.turn_number == 3 and c.model.active_player == "local" and c.model.history.size() == history_count, "Turn player and history restored exactly")
	check(extra.counters.size() == 1 and extra.counters[0].value == 7 and extra.counters[0].caption == "Storm", "Standalone counters restore values labels and positions")
	token = c.card_by_id(token_id)
	check(token != null and token.state.custom_metadata.power == "4" and token.state.display_name == "Wolf Alpha" and token.card_image.texture != null, "Token art name and stats survive restore")
	card = c.card_by_id(revealed_id)
	check(c.pile_view.back_image.texture == card.card_image.texture and card.state.custom_metadata.get("public_reveal", false), "Restore preserves revealed pile top and persistent reveal flag")
	c.move_card(card, "hand")
	check(card.state.visibility == "public", "Restored reveal still follows card across zones")
	var bad_save: Dictionary = saved.duplicate(true)
	bad_save.local_tabletop.counters.append(bad_save.local_tabletop.counters[0].duplicate(true))
	check(table.persistence.restore_match(bad_save).has("error") and extra.counters.size() == 1, "Malformed new state rejected before replacing match")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("local_tabletop")
	check(not table.persistence.restore_match(legacy).has("error") and c.model.turn_number == 1 and c.model.active_player == "local" and extra.counters.is_empty(), "Older saves load with default local state")
	table.persistence.restore_match(saved)
	if OS.get_cmdline_user_args().size() > 1:
		c.hand_open = false
		c.refresh()
		extra.create_counter(Vector2(600, 350), 7, "Storm")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone57_tabletop.png"))
		c.open_inspection("opponent", "library")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone57_gallery.png"))
		c.close_inspection()
		extra.toggle_history()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone57_history.png"))
		extra.close_all()
		extra.tools_window.popup_centered()
		extra.display_result(extra.tools.roll(1, 20))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone57_tools.png"))
		extra.close_all()
		extra.token_editor.open_token(c.card_by_id(token_id))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone57_token.png"))
		extra.close_all()
		table.view.zoom_by(0.4)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone57_zoom.png"))
	print("MILESTONE 5.7: %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
