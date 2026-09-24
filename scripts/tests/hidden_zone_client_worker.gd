extends "res://scripts/tests/card_sync_client_worker.gd"
func gate(stage: String) -> void:
	marker(role + "_" + stage)
	await wait_for(func() -> bool: return exists(("guest" if role == "host" else "host") + "_" + stage))
func run() -> void:
	var args := OS.get_cmdline_user_args()
	folder = args[0]
	role = args[1]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	for i: int in 5: await process_frame
	var c: Node = main.tabletop.match_controller
	var ui: Node = main.get_node("Network")
	var n: Node = ui.network
	var r: Node = ui.gameplay
	var h: Node = r.hidden
	h.auto_approve = false
	h.settings_path = folder.path_join(role + "-privacy.cfg")
	var path: String = folder.path_join(role)
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE if role == "host" else Color.CORAL)
	var record: Dictionary = preload("res://scripts/card_storage.gd").new(path).save_card(image.save_png_to_buffer(),"Private " + role,image.get_size())
	var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
	deck.cards = [{"card_id":record.metadata.card_id,"quantity":10}]
	c.loader = preload("res://scripts/library_loader.gd").new(path)
	c.load_deck(deck,false)
	n.message_sent.connect(func(message: Dictionary) -> void: messages.append(message))
	if role == "host":
		n.host_game(int(args[2]),"Host","127.0.0.1")
		marker("listening")
	else:
		await wait_for(func() -> bool: return exists("listening"))
		n.join_game("127.0.0.1",int(args[2]),"Guest")
	results.connected = await wait_for(func() -> bool: return n.session.state == "connected")
	r.start()
	await wait_for(func() -> bool: return r.card_sync.checked)
	if role == "guest": ui.sync_button.pressed.emit()
	results.assets = await wait_for(func() -> bool: return r.card_sync.status.begins_with("CARD SYNC COMPLETE"))
	r.card_sync.decide("start")
	results.shared = await wait_for(func() -> bool: return r.enabled)
	c.library_actions.draw_n("local",3)
	await gate("drawn")
	await create_timer(0.3).timeout
	results.normal_private = r.state.hands[r.remote_id].is_empty()
	await gate("normal_checked")
	h.reveal_hand(true)
	results.reveal = await wait_for(func() -> bool: return r.state.hands[r.remote_id].size() == 3)
	await gate("revealed")
	h.reveal_hand(false)
	results.hide = await wait_for(func() -> bool: return r.state.hands[r.remote_id].is_empty())
	await gate("hidden")
	var prior: int = messages.size()
	if role == "host":
		h.request("hand")
		await wait_for(func() -> bool: return h.outgoing == null)
	else:
		await wait_for(func() -> bool: return h.incoming != null)
		results.prompt = h.ui.prompt.visible
		h.respond(false)
	await gate("denied")
	results.denied_private = not messages.slice(prior).any(func(f: Dictionary) -> bool: return f.type == "hidden_zone" and f.kind in ["snapshot","transfer"])
	if role == "host":
		h.request("hand")
		results.gallery = await wait_for(func() -> bool: return c.remote_inspection and c.contents_list.item_count == 3)
		results.gallery_art = c.contents_list.get_item_icon(0) != null
		if args.size() > 3:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("approved-hand.png"))
		c.contents_list.select(0)
		h.move_selected("take")
		results.take = await wait_for(func() -> bool: return c.model.players.local.hand.size() == 4)
		c.close_inspection()
		results.clean = h.outgoing == null and c.contents_list.item_count == 0
	else:
		await wait_for(func() -> bool: return h.incoming != null)
		h.respond(true)
		results.take = await wait_for(func() -> bool: return c.model.players.local.hand.size() == 2)
		results.clean = await wait_for(func() -> bool: return h.incoming == null)
	await gate("taken")
	if role == "host":
		h.request("library")
		results.library = await wait_for(func() -> bool: return c.remote_inspection and c.contents_list.item_count == 7)
		c.close_inspection()
	else:
		await wait_for(func() -> bool: return h.incoming != null)
		h.respond(true)
		await wait_for(func() -> bool: return h.incoming == null)
	results.shuffle = await wait_for(func() -> bool: return r.state.history.any(func(e: Dictionary) -> bool: return e.kind == "search_shuffle"))
	await gate("searched")
	if role == "host":
		h.request("hand")
		await wait_for(func() -> bool: return c.remote_inspection)
		n.disconnect_session()
	else:
		await wait_for(func() -> bool: return h.incoming != null)
		h.respond(true)
	await wait_for(func() -> bool: return n.session.state == "disconnected")
	results.disconnect_cleanup = h.incoming == null and h.outgoing == null and not c.remote_inspection and not c.contents.visible
	var file := FileAccess.open(folder.path_join(role + "_result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results))
	file.close()
	await gate("done")
	main.queue_free()
	await process_frame
	quit()
