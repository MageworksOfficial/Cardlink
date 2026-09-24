extends SceneTree
## Two OS processes. Marker files coordinate tests, never gameplay state.
var results: Dictionary = {}
var messages: Array = []
var folder: String
var role: String
func _initialize() -> void: run.call_deferred()
func wait_for(predicate: Callable) -> bool:
	var end: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return false
func marker(name: String) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	file.store_string("ready")
func exists(name: String) -> bool: return FileAccess.file_exists(folder.path_join(name))
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
	var sync: Node = ui.gameplay
	var path: String = folder.path_join(role)
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE if role == "host" else Color.CORAL)
	var record: Dictionary = preload("res://scripts/card_storage.gd").new(path).save_card(image.save_png_to_buffer(), "Unique " + role + " card", image.get_size())
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
	sync.start()
	await wait_for(func() -> bool: return sync.card_sync.checked)
	sync.card_sync.decide("sync")
	results.asset_sync = await wait_for(func() -> bool: return sync.card_sync.status.begins_with("CARD SYNC COMPLETE"))
	if args.size() > 3 and args[3] == "capture":
		ui.open_panel()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(role + "-sync.png"))
		ui.window.hide()
	sync.card_sync.decide("start")
	results.shared = await wait_for(func() -> bool: return sync.enabled)
	c.library_actions.draw_n("local",7)
	results.counts = await wait_for(func() -> bool: return c.hidden_count("opponent","hand") == 7)
	var private_id: String = c.pile.order[0]
	var local_card: Control = c.card_by_id(c.model.players.local.hand[0])
	c.move_card(local_card,"battlefield")
	results.both_public = await wait_for(func() -> bool: return sync.state.cards.size() == 2)
	var opposite: Control
	for card: Control in main.tabletop.cards:
		if card.state.owner_player_id == "opponent" and card.state.current_zone == "battlefield": opposite = card
	results.art = opposite != null and opposite.card_image.texture != null
	results.perspective = opposite != null and local_card.position.y > opposite.position.y and opposite.rotation == 0
	if role == "guest" and opposite != null:
		opposite.position.x += 150
		opposite.set_tapped(true)
		c.change_life("opponent",-3)
		main.tabletop.create_token("Wolf","local","local","","2","2")
		main.tabletop.extras.tools.roll(1,20)
		c.end_turn()
	c.toggle_hand_reveal(c.card_by_id(c.model.players.local.hand[0]))
	results.actions = await wait_for(func() -> bool: return sync.state.cards.size() == 3 and sync.state.players.player_1.life == 37 and sync.state.turn.number == 2 and sync.state.history.any(func(event: Dictionary) -> bool: return event.kind == "dice"))
	await create_timer(0.7).timeout
	results.private_id_absent = not JSON.stringify(messages).contains(private_id)
	if args.size() > 3 and args[3] == "capture":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(role + ".png"))
	results.state = sync.state
	results.log = sync.log
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
