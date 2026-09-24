extends "res://scripts/tests/card_sync_client_worker.gd"
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
	var sync: Node = ui.gameplay.card_sync
	var path: String = folder.path_join(role)
	var store = preload("res://scripts/card_storage.gd").new(path)
	var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
	if role == "host":
		for i: int in 11:
			var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
			image.fill(Color.from_hsv(float(i)/11,0.7,0.8))
			var record: Dictionary = store.save_card(image.save_png_to_buffer(),"Test Card %d" % i,image.get_size())
			deck.cards.append({"card_id":record.metadata.card_id,"quantity":1})
	c.loader = preload("res://scripts/library_loader.gd").new(path)
	if role == "host": c.load_deck(deck,false)
	n.message_sent.connect(func(message: Dictionary) -> void: messages.append(message))
	if role == "host":
		n.host_game(int(args[2]),"Host","127.0.0.1")
		marker("listening")
	else:
		await wait_for(func() -> bool: return exists("listening"))
		n.join_game("127.0.0.1",int(args[2]),"Guest")
	results.connected = await wait_for(func() -> bool: return n.session.state == "connected")
	ui.gameplay.start()
	results.manifests = await wait_for(func() -> bool: return sync.checked)
	results.initial_count = sync.inspect_required().available == (11 if role == "host" else 0) and sync.required().size() == 11
	if role == "guest":
		ui.sync_button.pressed.emit()
		results.immediate = sync.requested and ui.sync_button.disabled and sync.status.contains("Preparing")
		for i: int in 5: ui.sync_button.pressed.emit()
	else: results.immediate = true
	results.completed = await wait_for(func() -> bool: return sync.status.begins_with("CARD SYNC COMPLETE"))
	results.final_count = sync.inspect_required().available == 11 and sync.inspect_required().missing == 0
	results.steps = sync.reports.has("1") and sync.reports.has("2") and sync.reports["1"].images == 0 and sync.reports["2"].images == 11 and sync.reports["2"].definitions == 11
	results.start_enabled = not ui.start_match_button.disabled
	results.one_job = messages.filter(func(f: Dictionary) -> bool: return f.type == "card_sync" and f.kind == "begin").size() == (1 if role == "host" else 0)
	results.log_visible = not ui.sync_log.text.is_empty()
	if args.size() > 3 and args[3] == "capture":
		ui.open_panel()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(role + "-sync.png"))
	results.status = sync.status
	var file := FileAccess.open(folder.path_join(role + "_result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results))
	file.close()
	marker(role + "_done")
	await wait_for(func() -> bool: return exists(("guest" if role == "host" else "host") + "_done"))
	n.disconnect_session()
	await create_timer(0.2).timeout
	main.queue_free()
	await process_frame
	quit()
