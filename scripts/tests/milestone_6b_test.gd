extends SceneTree
var checks: int = 0
var failures: int = 0
var wire: Array[Dictionary] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", caption)
func wait_for(predicate: Callable, seconds: float = 5) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return false
func settle() -> void: await create_timer(0.4).timeout
func create_client(path: String, name_text: String, color: Color, multichunk: bool = false) -> Control:
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	for _i: int in 4: await process_frame
	var image := Image.create(750, 1050, false, Image.FORMAT_RGBA8)
	image.fill(color)
	if multichunk:
		var noise := Image.create_from_data(750,64,false,Image.FORMAT_RGBA8,Crypto.new().generate_random_bytes(750*64*4))
		image.blit_rect(noise,Rect2i(0,0,750,64),Vector2i.ZERO)
	var store = preload("res://scripts/card_storage.gd").new(path)
	var record: Dictionary = store.save_card(image.save_png_to_buffer(), name_text, image.get_size())
	var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
	deck.cards = [{"card_id":record.metadata.card_id,"quantity":10}]
	main.tabletop.match_controller.loader = preload("res://scripts/library_loader.gd").new(path)
	main.tabletop.match_controller.load_deck(deck, false)
	main.get_node("Network").network.message_sent.connect(func(message: Dictionary) -> void: wire.append(message))
	return main
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var a: Control = await create_client(base.path_join("a"), "PRIVATE_A_NAME", Color.CORNFLOWER_BLUE)
	var b: Control = await create_client(base.path_join("b"), "PRIVATE_B_NAME", Color.CORAL)
	var na: Node = a.get_node("Network").network
	var nb: Node = b.get_node("Network").network
	var ra: Node = a.get_node("Network").gameplay
	var rb: Node = b.get_node("Network").gameplay
	var ca: Node = a.tabletop.match_controller
	var cb: Node = b.tabletop.match_controller
	var port: int = randi_range(33000, 43000)
	na.host_game(port,"Host","127.0.0.1")
	nb.join_game("127.0.0.1",port,"Guest")
	check(await wait_for(func() -> bool: return na.session.state == "connected" and nb.session.state == "connected"), "Host and guest connect")
	ra.start()
	rb.start()
	await wait_for(func() -> bool: return ra.card_sync.checked and rb.card_sync.checked)
	ra.card_sync.decide("placeholders")
	rb.card_sync.decide("placeholders")
	check(await wait_for(func() -> bool: return ra.enabled and rb.enabled), "Both opt in to shared public tabletop")
	ca.library_actions.draw_n("local",7)
	cb.library_actions.draw_n("local",7)
	await settle()
	check(ca.hidden_count("opponent","hand") == 7 and cb.hidden_count("opponent","hand") == 7, "Both opponent hand counts are seven")
	check(ca.hidden_count("opponent","library") == 3 and cb.hidden_count("opponent","library") == 3, "Both opponent library counts are three")
	check(ca.opponent_hand.cards_row.get_child_count() == 7 and cb.opponent_hand.cards_row.get_child_count() == 7, "Both opponents render seven backs")
	var initial: String = JSON.stringify(wire.filter(func(frame: Dictionary) -> bool: return frame.type != "card_sync"))
	check(not initial.contains("PRIVATE_A_NAME") and not initial.contains("PRIVATE_B_NAME"), "Private names do not enter initial sync or draws")
	check(not initial.contains(ca.model.players.local.hand[0]) and not initial.contains(cb.pile.order[0]), "Private instance IDs and library order stay local")
	var card: Control = ca.card_by_id(ca.model.players.local.hand[0])
	var id: String = card.state.match_instance_id
	ca.move_card(card,"battlefield")
	card.position = Vector2(400,900)
	await settle()
	var remote: Control = cb.card_by_id(id)
	check(remote != null and remote.state.card_definition_id == card.state.card_definition_id, "Playing a card promotes the original instance and definition IDs")
	if remote == null:
		print("ROUTER A ",ra.log," B ",rb.log)
		quit(1)
		return
	check(remote.state.owner_player_id == "opponent" and card.state.owner_player_id == "local", "Ownership is mapped to each local perspective")
	check(absf(remote.position.y - (1296 - card.position.y - 140)) < 0.1, "Guest renders opposite side using neutral world coordinates")
	check(remote.rotation == 0 and remote.card_image.rotation == 0, "Card faces stay upright on both clients")
	check(remote.card_image.texture == null and remote.token_label != null, "Missing shared artwork uses a labeled placeholder without file transfer")
	remote.position += Vector2(100,20)
	await settle()
	check(absf(card.position.x - 500) < 0.1 and absf(card.position.y - 880) < 0.1, "Guest can drag the host-owned public card")
	remote.set_tapped(true)
	await settle()
	check(card.tapped and remote.tapped, "Tap synchronizes")
	card.set_tapped(false)
	card.state.set_counter("charge",3)
	card.update_counters()
	await settle()
	check(not remote.tapped and remote.state.counters.get("charge") == 3, "Untap and attached counters synchronize")
	cb.change_controller(remote,"local")
	await settle()
	check(card.state.controller_player_id == "opponent" and card.state.owner_player_id == "local", "Controller changes independently of ownership")
	cb.move_card(remote,"graveyard",true,"opponent")
	await settle()
	check(card.state.current_zone == "graveyard" and remote.state.current_zone == "graveyard", "Public graveyard movement synchronizes")
	ca.move_card(card,"exile")
	await settle()
	check(remote.state.current_zone == "exile", "Public exile movement synchronizes")
	ca.move_card(card,"commander")
	await settle()
	check(remote.state.current_zone == "commander", "Public leader movement synchronizes")
	card.set_face_down(true)
	await settle()
	check(remote.state.face_down and remote.card_back.visible, "Face-down public state synchronizes without identity")
	card.set_face_down(false)
	await settle()
	check(not remote.state.face_down and remote.state.display_name == card.state.display_name, "Revealing public card restores identity")
	ca.change_life("local",-3)
	cb.change_life("local",-2)
	await settle()
	check(ca.model.players.local.life == 37 and cb.model.players.opponent.life == 37 and cb.model.players.local.life == 38 and ca.model.players.opponent.life == 38, "Both life totals synchronize")
	var token: Control = a.tabletop.create_token("Wolf","local","local","","2","2").card
	var token_id: String = token.state.match_instance_id
	await settle()
	check(cb.card_by_id(token_id) != null and cb.card_by_id(token_id).state.custom_metadata.power == "2", "Token creation preserves shared ID and stats")
	var duplicate: Control = cb.library_actions.duplicate_token(cb.card_by_id(token_id)).card
	var duplicate_id: String = duplicate.state.match_instance_id
	await settle()
	check(ca.card_by_id(duplicate_id) != null and duplicate_id != token_id, "Token duplicate uses one new shared instance ID")
	duplicate.state.display_name = "Big Wolf"
	duplicate.state.custom_metadata.power = "4"
	duplicate.state.custom_metadata.toughness = "5"
	await settle()
	check(ca.card_by_id(duplicate_id).state.display_name == "Big Wolf" and ca.card_by_id(duplicate_id).state.custom_metadata.toughness == "5", "Token property edits synchronize")
	cb.move_card(duplicate,"exile")
	await settle()
	check(ca.card_by_id(duplicate_id) == null and cb.card_by_id(duplicate_id) == null, "Token destruction synchronizes")
	var counter: Control = b.tabletop.extras.create_counter(Vector2(700,800),3,"Quest")
	var counter_id: String = counter.instance_id
	await settle()
	check(a.tabletop.extras.counter_by_id(counter_id) != null, "Standalone counter creation synchronizes")
	counter.value = 8
	counter.caption = "Charge"
	counter.position += Vector2(50,10)
	counter.refresh()
	await settle()
	check(a.tabletop.extras.counter_by_id(counter_id).value == 8 and a.tabletop.extras.counter_by_id(counter_id).caption == "Charge", "Counter movement/value/label synchronize")
	b.tabletop.selection.apply_batch("delete",[counter_id])
	await settle()
	check(a.tabletop.extras.counter_by_id(counter_id) == null, "Counter deletion synchronizes")
	ca.move_card(card,"battlefield")
	await settle()
	a.tabletop.selection.apply_batch("tap",[id,token_id])
	await settle()
	check(cb.card_by_id(id).tapped and cb.card_by_id(token_id).tapped, "Bulk selection actions synchronize")
	cb.move_card(cb.card_by_id(id),"hand",true,"opponent")
	await settle()
	check(card.state.current_zone == "hand" and cb.card_by_id(id) == null, "Public card returns to owner hand and disappears remotely")
	check(cb.hidden_count("opponent","hand") == ca.model.players.local.hand.size(), "Returning public card updates private count")
	a.tabletop.select_card(card)
	a.tabletop.shortcuts.discard()
	await settle()
	check(cb.card_by_id(id) != null and cb.card_by_id(id).state.current_zone == "graveyard", "Discard exposes the original card in public graveyard")
	var wire_start: int = wire.size()
	var private_id: String = ca.pile.order[0]
	ca.draw_card()
	ca.shuffle_library()
	await settle()
	var draw_wire: String = JSON.stringify(wire.slice(wire_start))
	check(not draw_wire.contains(private_id) and not draw_wire.contains("library_order"), "Draw and shuffle send counts/events, never hidden IDs or order")
	cb.end_turn()
	await settle()
	check(ca.model.turn_number == cb.model.turn_number and ca.model.turn_number == 2 and ca.model.active_player == "opponent" and cb.model.active_player == "local", "End Turn synchronizes turn number and locally mapped active player")
	var roll: Dictionary = b.tabletop.extras.tools.roll(2,6)
	var flip: Dictionary = b.tabletop.extras.tools.flip()
	await settle()
	check(ra.state.history == rb.state.history and JSON.stringify(ra.state.history).contains(str(roll.payload.values)) and JSON.stringify(ra.state.history).contains(flip.payload.side), "Dice/coin roll once and meaningful history converges")
	var same: bool = JSON.parse_string(JSON.stringify(ra.state)) == JSON.parse_string(JSON.stringify(rb.state))
	if not same:
		FileAccess.open(base.path_join("state_a.json"), FileAccess.WRITE).store_string(JSON.stringify(ra.state))
		FileAccess.open(base.path_join("state_b.json"), FileAccess.WRITE).store_string(JSON.stringify(rb.state))
	check(same, "Both public state models converge")
	card.set_face_down(true)
	await settle()
	cb.card_by_id(id).set_face_down(false)
	await settle()
	check(cb.card_by_id(id).state.card_definition_id == card.state.card_definition_id and not card.state.face_down, "Guest can reveal an owner-held face-down public identity")
	cb.move_card(cb.card_by_id(id),"library",false,"opponent")
	await settle()
	check(ca.pile.order.back() == id and cb.card_by_id(id) == null and cb.hidden_count("opponent","library") == ca.pile.order.size(), "Remote bottom-of-library return preserves identity privately and updates count")
	ca.move_card(card,"battlefield")
	await settle()
	ca.library_actions.put_nth(card,"local",2)
	await settle()
	check(ca.pile.order[1] == id and cb.card_by_id(id) == null, "Local indexed library placement is not reapplied as top/bottom by sync")
	ca.move_card(card,"battlefield")
	await settle()
	ca.change_life("local",-1)
	cb.change_life("opponent",-2)
	await settle()
	check(ca.model.players.local.life == 34 and cb.model.players.opponent.life == 34, "Concurrent changes to the same life total are additive")
	var malformed: Dictionary = ra.state.duplicate(true)
	malformed["private_hand"] = ["secret"]
	check(not preload("res://scripts/network/network_action.gd").snapshot(malformed), "Resync schema rejects private-zone fields")
	var private_order: Array = cb.pile.order.duplicate()
	cb.card_by_id(id).position = Vector2(12,34)
	rb.baseline = rb.serializer.capture() # Deliberate silent render desync, not a user action.
	rb.resync.request()
	await settle()
	check(rb.serializer.public_card(cb.card_by_id(id)).position == ra.state.cards[id].position and cb.pile.order == private_order, "Public resync repairs mismatch without touching private library order")
	var duplicate_frame: Dictionary = {}
	for message: Dictionary in wire:
		if message.get("mode") == "commit": duplicate_frame = message
	var sequence: int = rb.committed
	rb.receive(duplicate_frame)
	check(rb.committed == sequence and rb.log.back().contains("Duplicate"), "Duplicate committed action ignored")
	var safe: bool = true
	for message: Dictionary in wire:
		if message.get("type") == "game": safe = safe and preload("res://scripts/network/network_action.gd").frame(message)
	check(safe and not JSON.stringify(wire).contains("image_path") and not JSON.stringify(wire).contains("definition_path"), "All gameplay frames validate and contain no local paths or image bytes")
	na.disconnect_session()
	await settle()
	check(not ra.enabled and not rb.enabled and ca.card_by_id(id) != null, "Disconnect stops sync and keeps local match open")
	a.queue_free()
	b.queue_free()
	await process_frame
	print("MILESTONE 6B: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
