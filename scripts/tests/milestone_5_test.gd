extends SceneTree
const Store = preload("res://scripts/card_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
const Decks = preload("res://scripts/deck_storage.gd")
const MatchSaves = preload("res://scripts/match_save_storage.gd")
const Layouts = preload("res://scripts/layout_preset_storage.gd")
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
func mouse(point: Vector2, down: bool, motion_event: bool = false) -> void:
	var event: InputEventMouse
	if motion_event:
		var move := InputEventMouseMotion.new()
		move.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event = move
	else:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = down
		event = press
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://cache/milestone5/" + Crypto.new().generate_random_bytes(8).hex_encode()
	var cards_dir: String = base.path_join("cards")
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var image := Image.create(750, 1050, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var store := Store.new(cards_dir)
	var a: Dictionary = store.save_card(image.save_png_to_buffer(), "Azure leader", image.get_size())
	image.fill(Color.CORAL)
	var b: Dictionary = store.save_card(image.save_png_to_buffer(), "Coral companion", image.get_size())
	var deck: Dictionary = Decks.new_deck()
	deck.deck_name = "Two-player fixture"
	deck.cards = [{"card_id":a.metadata.card_id, "quantity":3}, {"card_id":b.metadata.card_id, "quantity":2}]
	deck.leaders = [a.metadata.card_id]
	var decks := Decks.new(base.path_join("decks"))
	decks.save_deck(deck)
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var table = main.tabletop
	var c = table.match_controller
	c.loader = Loader.new(cards_dir)
	table.persistence.matches = MatchSaves.new(base.path_join("matches"))
	table.persistence.layouts = Layouts.new(base.path_join("layouts"))
	table.controls.match_records.storage = table.persistence.matches
	table.controls.layout_records.storage = table.persistence.layouts
	check(c.model.players.size() == 2 and c.model.players.local.player_id != c.model.players.opponent.player_id, "two distinct players")
	check(table.controls.size.y <= 70 and not c.toolbar.visible and not main.get_node("ImportCard").visible, "compact toolbar replaces permanent developer controls")
	check(table.controls.panels.size() == 9, "nine contextual primary panels")
	table.controls.open_panel("Card")
	check(table.controls.panels.Card.visible, "context panel opens")
	table.controls.open_panel("Life")
	check(not table.controls.panels.Card.visible and table.controls.panels.Life.visible, "only one contextual panel remains open")
	table.controls.close_panels()
	check(not table.layout.edit_mode, "Play Mode is the default")
	table.controls.deck_storage = decks
	table.controls.refresh_decks()
	table.controls.deck_picker.select(0)
	table.controls.request_deck()
	check(c.loaded_ids.size() == 5 and c.pile.order.size() == 4, "Load Deck action works without entering Deck Builder")
	check(c.model.players.local.leaders.size() == 1, "leader starts outside local library")
	table.controls.deck_target.select(1)
	table.controls.request_deck()
	check(c.model.players.opponent.loaded_ids.size() == 5 and c.model.players.opponent.library.order.size() == 4, "opponent deck loads independently")
	var ids: Dictionary = {}
	for card: Control in table.cards:
		ids[card.state.match_instance_id] = true
	check(ids.size() == table.cards.size(), "all copies have unique match instance IDs")
	var old_order: Array = c.pile.order.duplicate()
	c.shuffle_library()
	var sorted_before: Array = old_order.duplicate()
	var sorted_after: Array = c.pile.order.duplicate()
	sorted_before.sort()
	sorted_after.sort()
	check(sorted_before == sorted_after, "shuffle preserves library membership")
	c.draw_card()
	c.draw_card()
	c.draw_card("opponent")
	c.draw_card("opponent")
	check(c.hand.row.get_child_count() == 2 and c.model.players.opponent.hand.size() == 2, "only local hand cards appear in local private hand")
	check(table.summary_label.text.contains("Opponent hand: 2"), "opponent exposes hand count")
	var opp_id: String = c.model.players.opponent.hand[0]
	var opp: Control = c.card_by_id(opp_id)
	var projection: Dictionary = c.model.player_view("local", c.visibility)
	check(not projection.players.opponent.has("hand") and not projection.players.opponent.has("library_order"), "opponent view has no private zone order")
	check(not JSON.stringify(projection).contains(opp_id), "private opponent instance omitted from viewer projection")
	check(not opp.visible and not opp.state.identity_visible, "opponent hand cannot render or hover on battlefield")
	var local_id: String = c.model.players.local.hand[0]
	var local: Control = c.card_by_id(local_id)
	c.move_card(local, "battlefield")
	check(local.visible and local.state.visibility == "public", "local hand card plays publicly")
	local.set_tapped(true)
	local.state.set_counter("Counter", 3)
	local.update_counters()
	check(local.tapped and local.counter_label.text.contains("★ 3"), "tap and visible star counter")
	local.state.change_counter("Counter", -1)
	local.update_counters()
	check(local.state.counters.Counter == 2, "remove counter")
	local.state.set_counter("Counter", 5)
	check(local.state.counters.Counter == 5, "set counter value")
	var blank: Control = table.create_token("Spirit", "opponent", "local").card
	check(blank.state.is_token and blank.state.card_definition_id.is_empty() and blank.state.owner_player_id == "opponent" and blank.state.controller_player_id == "local", "blank token needs no definition and separates owner/control")
	var illustrated: Control = table.create_token("Copy token", "local", "local", local.state.image_path).card
	check(illustrated.card_image.texture != null and illustrated.state.match_instance_id != blank.state.match_instance_id, "token can use existing card image with unique identity")
	blank.state.set_counter("Counter", 3)
	blank.update_counters()
	blank.set_tapped(true)
	check(blank.tapped and blank.counter_label.text.contains("★ 3"), "token tap and counters")
	c.move_card(local, "graveyard")
	check(local.state.current_zone == "graveyard" and c.model.players.local.graveyard.has(local_id), "move to graveyard updates player state")
	c.move_card(local, "exile")
	check(c.model.players.local.exile.has(local_id) and not c.model.players.local.graveyard.has(local_id), "move to exile removes stale graveyard membership")
	c.move_card(opp, "battlefield", true, "opponent")
	table.select_card(opp)
	opp.set_tapped(true)
	check(opp.visible and opp.tapped and opp.state.owner_player_id == "opponent", "local player can manipulate opponent public card")
	c.change_controller(opp, "local")
	check(opp.state.controller_player_id == "local" and opp.state.owner_player_id == "opponent", "change controller never rewrites owner")
	c.move_card(opp, "library", true, "local")
	check(c.pile.order[0] == opp_id and opp.state.owner_player_id == "opponent", "opponent-owned card can be put on local library top")
	c.move_card(opp, "library", false, "opponent")
	check(c.model.players.opponent.library.order.back() == opp_id and not c.pile.order.has(opp_id), "move to opponent library bottom removes prior library reference")
	c.open_inspection("opponent", "hand")
	check(c.contents.visible and c.contents_list.item_count == 1, "Search Opponent Hand opens temporary panel")
	var hidden_id: String = c.model.players.opponent.hand[0]
	check(c.visibility.can_see(c.card_by_id(hidden_id).state, "local"), "search grants intentional local access")
	check(not c.visibility.can_see(c.card_by_id(hidden_id).state, "other"), "search access is not public")
	c.close_inspection()
	check(not c.visibility.can_see(c.card_by_id(hidden_id).state, "local") and c.contents_list.item_count == 0, "closing search revokes access and clears display")
	c.open_inspection("opponent", "hand", true)
	check(c.card_by_id(hidden_id).state.visibility == "temporarily_revealed", "Reveal Opponent Hand uses temporary visibility")
	c.close_inspection()
	check(c.card_by_id(hidden_id).state.visibility == "owner_private", "closing reveal restores private visibility")
	c.open_inspection("opponent", "library")
	check(c.contents_list.item_count == c.model.players.opponent.library.order.size(), "Search Opponent Library lists authorized order")
	c.contents_list.select(0)
	c.contents_list.item_selected.emit(0)
	var inspected: Control = c.inspected_card()
	c.reveal_inspected()
	check(inspected.state.visibility == "temporarily_revealed" and c.inspection_preview.texture != null, "reveal selected hidden card")
	var inspection_save: Dictionary = table.persistence.capture_match()
	var saved_private: bool = false
	for row: Dictionary in inspection_save.cards:
		if row.match_instance_id == inspected.state.match_instance_id:
			saved_private = row.visibility == "owner_private"
	check(saved_private and Snapshot.validate(inspection_save).is_empty(), "match snapshot excludes transient inspection grants")
	c.close_inspection()
	c.move_card(opp, "battlefield", true, "opponent")
	opp.set_face_down(true)
	c.refresh()
	var face_down: Dictionary = c.visibility.card_view(opp.state, "local")
	check(face_down.get("hidden", false) and not face_down.has("card_definition_id") and not face_down.has("image_path") and not face_down.has("display_name"), "face-down public projection redacts identity")
	opp._on_mouse_entered()
	check(not opp.hover_preview.visible, "face-down public card blocks hover identity")
	c.change_life("local", -4)
	c.change_life("opponent", 7)
	check(c.model.players.local.life == 36 and c.model.players.opponent.life == 47, "either player's life changes independently")

	var zone: Control = c.zone_for("graveyard")
	var start: Vector2 = zone.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 10)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(40, 30)
	zone._header_input(press)
	zone._header_input(move)
	check(zone.position == start, "Play Mode locks major zone objects")
	table.layout.set_edit_mode(true)
	zone._header_input(press)
	zone._header_input(move)
	check(zone.position == start + Vector2(30, 20), "Edit Layout permits zone movement")
	var pile_start: Vector2 = c.pile_view.position
	c.pile_view._gui_input(press)
	c.pile_view._gui_input(move)
	check(c.pile_view.position == pile_start + Vector2(30, 20), "Edit Layout permits library movement")
	var hand_start: Vector2 = c.hand.position
	c.hand._anchor_input(press)
	c.hand._anchor_input(move)
	check(c.hand.position == hand_start + Vector2(30, 20), "Edit Layout permits hand anchor movement")
	var life_start: Vector2 = table.life_display.position
	table.life_display.gui_input.emit(press)
	table.life_display.gui_input.emit(move)
	check(table.life_display.position == life_start + Vector2(30, 20), "Edit Layout permits life display movement")
	table.view.zoom_by(1.2)
	table.view.pan += Vector2(15, 20)
	table.view.apply_view()
	table.layout.ui_scale = 1.1
	var layout: Dictionary = table.layout.capture()
	check(Layouts != null and preload("res://scripts/layout_service.gd").validate(layout).is_empty(), "layout snapshot validates")
	var layout_save: Dictionary = table.persistence.layouts.save_record(layout, "My kitchen table")
	check(not layout_save.has("error"), "save layout under independent layout storage")
	table.view.reset_view()
	c.pile_view.position = Vector2.ZERO
	check(not table.layout.apply(table.persistence.layouts.read_record(layout_save.path).record.data).has("error") and c.pile_view.position == Vector2(layout.library_positions.local[0], layout.library_positions.local[1]), "layout load restores object placement")
	check(is_equal_approx(table.view.zoom, layout.zoom) and table.view.pan == Vector2(layout.pan[0], layout.pan[1]) and table.layout.ui_scale == 1.1, "layout restores zoom pan and UI scale")
	check(not table.persistence.layouts.rename_record(layout_save.path, "Renamed layout").has("error"), "rename layout")
	var copy: Dictionary = table.persistence.layouts.duplicate_record(layout_save.path, "Layout copy")
	check(not copy.has("error") and copy.path != layout_save.path, "duplicate layout creates independent ID")
	var panel = table.controls.layout_records
	panel.refresh()
	for i: int in panel.picker.item_count:
		if panel.picker.get_item_metadata(i) == copy.path:
			panel.picker.select(i)
	panel.request_delete()
	check(panel.confirm.visible and FileAccess.file_exists(copy.path), "layout deletion requires confirmation")
	panel.confirm.confirmed.emit()
	panel.confirm.hide()
	check(not FileAccess.file_exists(copy.path) and FileAccess.file_exists(layout_save.path), "confirmed deletion preserves other presets")
	for caption: String in ["Default", "Left-handed", "Right-handed", "Commander", "Custom"]:
		var preset: Dictionary = table.layout.built_in(caption)
		check(preload("res://scripts/layout_service.gd").validate(preset).is_empty(), caption + " preset validates")
	table.layout.apply(layout)
	table.layout.set_edit_mode(false)
	check(not zone.edit_enabled, "return to Play Mode locks layout again")
	# Save the complete state, then replace the whole app scene to prove disk restoration.
	local.set_tapped(true)
	local.state.set_counter("Counter", 4)
	local.update_counters()
	blank.position = Vector2(430, 310)
	blank.state.position = blank.position
	c.refresh()
	var snapshot: Dictionary = table.persistence.capture_match()
	check(Snapshot.validate(snapshot).is_empty(), "full two-player snapshot validates")
	var saved: Dictionary = table.persistence.save_match("Local simulated match")
	check(not saved.has("error") and FileAccess.file_exists(saved.path), "Save Match persists JSON")
	var local_order: Array = c.pile.order.duplicate()
	var opponent_order: Array = c.model.players.opponent.library.order.duplicate()
	var token_id: String = blank.state.match_instance_id
	var old_count: int = table.cards.size()
	var restore_path: String = saved.path
	var bad: Dictionary = snapshot.duplicate(true)
	bad.cards.append(bad.cards[0].duplicate(true))
	check(table.persistence.restore_match(bad).has("error") and table.cards.size() == old_count, "invalid duplicate-ID match does not alter current state")
	bad = snapshot.duplicate(true)
	bad.players[0].library_order.append("missing-instance")
	check(table.persistence.restore_match(bad).has("error") and table.cards.size() == old_count, "invalid library references rejected before mutation")
	check(table.persistence.matches.delete_record(base.path_join("../outside.json")).has("error"), "saved-record paths reject traversal")
	root.remove_child(main)
	main.queue_free()
	await process_frame
	main = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	table = main.tabletop
	c = table.match_controller
	c.loader = Loader.new(cards_dir)
	table.persistence.matches = MatchSaves.new(base.path_join("matches"))
	table.controls.match_records.storage = table.persistence.matches
	var restored: Dictionary = table.persistence.load_match(restore_path)
	check(not restored.has("error") and table.cards.size() == old_count, "fresh app scene loads complete saved match")
	check(c.pile.order == local_order and c.model.players.opponent.library.order == opponent_order, "both library orders restored exactly")
	check(c.model.players.local.life == 36 and c.model.players.opponent.life == 47, "both life totals restored")
	local = c.card_by_id(local_id)
	opp = c.card_by_id(opp_id)
	blank = c.card_by_id(token_id)
	check(local.tapped and local.state.counters.Counter == 4 and local.state.current_zone == "exile", "card zone tap and counters restored")
	check(opp.state.owner_player_id == "opponent" and opp.state.controller_player_id == "local", "ownership and control restored separately")
	check(opp.state.visibility == "face_down_public" and opp.card_back.visible, "face-down visibility restored")
	check(blank.state.is_token and blank.state.card_definition_id.is_empty() and blank.position == Vector2(430,310) and blank.state.counters.Counter == 3, "blank token identity position and counters restored")
	check(c.visibility.inspection_ids.is_empty() and not c.visibility.can_see(c.card_by_id(hidden_id).state, "local"), "restored match grants no temporary hidden access")
	check(table.layout.preset_name == layout.preset_name and is_equal_approx(table.view.zoom, layout.zoom), "match restores selected layout and camera")
	check(c.hand.row.get_child_count() == c.model.players.local.hand.size(), "restored local hand renders only local hand")
	var rename: Dictionary = table.persistence.matches.rename_record(restore_path, "Renamed match")
	check(not rename.has("error"), "rename match save")
	table.controls.match_records.refresh()
	for i: int in table.controls.match_records.picker.item_count:
		if table.controls.match_records.picker.get_item_metadata(i) == restore_path:
			table.controls.match_records.picker.select(i)
	table.controls.match_records.request_delete()
	check(table.controls.match_records.confirm.visible and FileAccess.file_exists(restore_path), "match save deletion requires confirmation")
	table.controls.match_records.confirm.get_cancel_button().pressed.emit()
	await process_frame
	check(FileAccess.file_exists(restore_path), "cancel match deletion preserves save")
	var invalid_layout: Dictionary = table.layout.capture()
	invalid_layout.zoom = -1
	check(not table.layout.apply(invalid_layout).is_empty(), "invalid layout rejected safely")
	var broken_path: String = base.path_join("matches/broken.json")
	var broken_file := FileAccess.open(broken_path, FileAccess.WRITE)
	broken_file.store_string("{ broken")
	broken_file.close()
	check(table.persistence.matches.read_record(broken_path).has("error"), "malformed match JSON handled safely")
	var missing: Dictionary = table.persistence.capture_match()
	missing.cards[0].image_path = cards_dir.path_join("absent.png")
	var missing_result: Dictionary = table.persistence.restore_match(missing)
	check(not missing_result.has("error") and missing_result.missing_images > 0, "missing match image restores remaining state")
	var placeholder: Control = c.card_by_id(missing.cards[0].match_instance_id)
	check(placeholder.token_label != null and placeholder.token_label.text.contains("Missing image"), "missing image has visible placeholder")
	table.persistence.load_match(restore_path)
	if OS.get_cmdline_user_args().size() > 1:
		table.view.reset_view()
		root.size = Vector2i(1152, 760)
		c.close_inspection()
		table.controls.close_panels()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone5_tabletop.png"))
		table.controls.open_panel("Library")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("milestone5_library_panel.png"))
	print("MILESTONE 5 COMPLETE: checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

