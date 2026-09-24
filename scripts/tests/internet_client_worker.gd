extends "res://scripts/tests/card_sync_client_worker.gd"
var interrupt_ack: bool = false
var fault_phase: String = "committed"
func gate(stage: String) -> void:
	marker(role+"_"+stage)
	await wait_for(func() -> bool: return exists(("guest" if role == "host" else "host")+"_"+stage))
func resume(r: Node, stage: String) -> bool:
	if role == "host":
		r.recovery.reconnect()
		marker(stage+"_listening")
	else:
		await wait_for(func() -> bool: return exists(stage+"_listening"))
		r.recovery.reconnect()
	return await wait_for(func() -> bool: return r.enabled and not r.recovery.suspended and r.recovery.status == "Match restored.")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	folder = args[0]
	role = args[1]
	for arg: String in args:
		if arg.begins_with("fault="): fault_phase = arg.trim_prefix("fault=")
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	for i: int in 5: await process_frame
	var c: Node = main.tabletop.match_controller
	var ui: Node = main.get_node("Network")
	var n: Node = ui.network
	var r: Node = ui.gameplay
	r.hidden.auto_approve = true
	var path: String = folder.path_join(role)
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE if role == "host" else Color.CORAL)
	var record: Dictionary = preload("res://scripts/card_storage.gd").new(path).save_card(image.save_png_to_buffer(),"Private "+role,image.get_size())
	var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
	deck.cards = [{"card_id":record.metadata.card_id,"quantity":10}]
	c.loader = preload("res://scripts/library_loader.gd").new(path)
	c.load_deck(deck,false)
	n.message_sent.connect(func(message: Dictionary) -> void:
		messages.append(message)
		if interrupt_ack and message.type == "transfer_tx" and message.kind == fault_phase:
			interrupt_ack = false
			n.outgoing.clear()
			n.disconnect_session())
	if role == "host":
		ui.rooms.signaling.service_url = "http://127.0.0.1:"+args[2]
		await ui.rooms.host_room("Host")
		var file := FileAccess.open(folder.path_join("code"),FileAccess.WRITE)
		file.store_string(ui.rooms.code)
		file.close()
		marker("listening")
	else:
		await wait_for(func() -> bool: return exists("listening"))
		ui.rooms.signaling.service_url = "http://127.0.0.1:"+args[2]
		await ui.rooms.join_room(FileAccess.get_file_as_string(folder.path_join("code")),"Guest")
	results.connected = await wait_for(func() -> bool: return n.session.state == "connected")
	results.connection_method = ui.rooms.method == ("Direct" if "direct" in args else "Relay")
	r.start()
	await wait_for(func() -> bool: return r.card_sync.checked)
	if role == "guest": r.card_sync.decide("sync")
	results.assets = await wait_for(func() -> bool: return r.card_sync.status.begins_with("CARD SYNC COMPLETE"))
	r.card_sync.decide("start")
	results.shared = await wait_for(func() -> bool: return r.enabled and r.recovery.authenticated)
	var match_id: String = r.recovery.context.match
	c.library_actions.draw_n("local",4)
	var private_id: String = c.pile.order[0]
	var card: Control = c.card_by_id(c.model.players.local.hand[0])
	c.move_card(card,"battlefield")
	await wait_for(func() -> bool: return r.state.cards.size() == 2)
	await gate("played")
	if role == "host":
		n.set_process(false)
		card.position += Vector2(65,22)
		card.set_tapped(true)
		card.state.set_counter("shield",2)
		card.update_counters()
		c.change_life("local",-5)
		main.tabletop.create_token("Wolf","local","local","","2","2")
		var item: Control = main.tabletop.extras.create_counter(Vector2(450,300))
		item.value = 9
		item.refresh()
		r.scan()
		c.end_turn()
		n.outgoing.clear()
		n.set_process(true)
		n.disconnect_session()
	await wait_for(func() -> bool: return n.available())
	await gate("lost")
	results.reconnect = await resume(r,"board")
	results.recovery_uses_relay = ui.rooms.method == "Relay"
	await gate("restored")
	await create_timer(0.4).timeout
	results.same_match = r.recovery.context.match == match_id
	results.public_repaired = r.state.players.player_1.life == 35 and r.state.cards.size() == 3 and r.state.counters.size() == 1 and r.state.turn.number == 2
	results.private_preserved = c.model.players.local.hand.size() == 3
	results.privacy = not JSON.stringify(messages.filter(func(f: Dictionary) -> bool: return f.type in ["recovery","transfer_tx"])).contains(private_id)
	await gate("board_checked")
	if role == "host":
		r.hidden.request("hand")
		await wait_for(func() -> bool: return c.remote_inspection)
		c.contents_list.select(0)
		r.hidden.move_selected("take")
		results.normal_transfer = await wait_for(func() -> bool: return c.model.players.local.hand.size() == 4)
		c.close_inspection()
	else: results.normal_transfer = await wait_for(func() -> bool: return c.model.players.local.hand.size() == 2)
	await gate("normal_transfer")
	await wait_for(func() -> bool: return not r.transactions.has_unfinished())
	interrupt_ack = true
	await gate("fault_ready")
	if role == "host":
		r.hidden.request("hand")
		await wait_for(func() -> bool: return c.remote_inspection)
		c.contents_list.select(0)
		r.hidden.move_selected("take")
	await wait_for(func() -> bool: return n.available())
	interrupt_ack = false
	await gate("transfer_lost")
	results.transfer_reconnect = await resume(r,"transfer")
	await gate("transaction_restored")
	await create_timer(0.5).timeout
	var expected_hand: int = (4 if role == "host" else 2) if fault_phase == "prepare" else (5 if role == "host" else 1)
	results.exactly_once = c.model.players.local.hand.size() == expected_hand and not r.transactions.has_unfinished()
	results.permissions_cleared = not c.remote_inspection and r.hidden.outgoing == null and r.hidden.incoming == null
	results.upright = card.rotation == 0 and is_equal_approx(card.card_image.rotation_degrees,90.0 if card.tapped else 0.0)
	if role == "host": r.resync.request()
	await gate("manual")
	await create_timer(0.4).timeout
	results.state = r.state
	results.revision = r.committed
	if "capture" in args:
		ui.open_panel()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(role+"-recovered.png"))
	var file := FileAccess.open(folder.path_join(role+"_result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results))
	file.close()
	await gate("done")
	n.disconnect_session()
	await create_timer(0.2).timeout
	main.queue_free()
	await process_frame
	quit()
