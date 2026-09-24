extends "res://scripts/tests/milestone_6b_test.gd"
func double_click(card: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	event.position = Vector2(30,30)
	card._gui_input(event)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var base: String = args[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var a: Control = await create_client(base.path_join("a"),"PRIVATE_A",Color.BLUE)
	var b: Control = await create_client(base.path_join("b"),"PRIVATE_B",Color.RED)
	var ua: Node = a.get_node("Network")
	var ub: Node = b.get_node("Network")
	var ca: Node = a.tabletop.match_controller
	var cb: Node = b.tabletop.match_controller
	if "public" in args:
		await ua.rooms.host_room("7.5 tap test host")
		if ua.network.server != null:
			ua.network.server.stop()
			ua.network.server = null
		ub.rooms.config.set_value("internet","direct_attempt_seconds",0.3)
		await ub.rooms.join_room(ua.rooms.code,"7.5 tap test guest")
	else:
		var port: int = randi_range(33000,43000)
		ua.network.host_game(port,"Host","127.0.0.1")
		ub.network.join_game("127.0.0.1",port,"Guest")
	check(await wait_for(func() -> bool: return ua.network.session.state == "connected" and ub.network.session.state == "connected",20),"Two clients connect for tap regression")
	if failures: quit(1); return
	ua.gameplay.start()
	ub.gameplay.start()
	await wait_for(func() -> bool: return ua.gameplay.card_sync.checked and ub.gameplay.card_sync.checked)
	ua.gameplay.card_sync.decide("sync")
	check(await wait_for(func() -> bool: return ua.gameplay.card_sync.status.begins_with("CARD SYNC COMPLETE") and ub.gameplay.card_sync.status.begins_with("CARD SYNC COMPLETE"),20),"Card Sync still completes")
	ua.gameplay.card_sync.decide("start")
	ub.gameplay.card_sync.decide("start")
	check(await wait_for(func() -> bool: return ua.gameplay.enabled and ub.gameplay.enabled),"Shared public match starts")
	ca.draw_card()
	var card: Control = ca.card_by_id(ca.model.players.local.hand[0])
	var id: String = card.state.match_instance_id
	ca.move_card(card,"battlefield")
	check(await wait_for(func() -> bool: return cb.card_by_id(id) != null),"Played card arrives on other client")
	var remote: Control = cb.card_by_id(id)
	var logical: Vector2 = card.position
	double_click(card)
	check(card.state.tapped,"Player A tap is immediate")
	check(await wait_for(func() -> bool: return remote.state.tapped),"Player A double-click tap synchronizes")
	double_click(remote)
	check(not remote.state.tapped,"Player B can untap a card owned by Player A")
	check(await wait_for(func() -> bool: return not card.state.tapped),"Remote untap synchronizes back to A")
	check(card.position == logical and card.rotation == 0 and remote.rotation == 0,"Online quick taps never move/rotate card roots")
	var pan_a: Vector2 = a.tabletop.view.pan
	var pan_b: Vector2 = b.tabletop.view.pan
	var turn: int = ca.model.turn_number
	ca.end_turn()
	check(await wait_for(func() -> bool: return ca.model.turn_number == turn+1 and cb.model.turn_number == turn+1),"Online End Turn still synchronizes")
	check(a.tabletop.world.rotation == 0 and b.tabletop.world.rotation == 0 and a.tabletop.view.pan == pan_a and b.tabletop.view.pan == pan_b,"Online End Turn never flips either camera")
	a.tabletop.perspective.toggle()
	check(a.tabletop.perspective.viewed_player == "local","Manual seat switch safely ignores Online Mode")
	check(not a.tabletop.undo.available() and not b.tabletop.undo.available(),"Online undo remains disabled")
	check(ua.network.Codec.APP_VERSION == preload("res://scripts/frontend/app_info.gd").NETWORK_COMPATIBILITY,"Wire compatibility uses central requirement")
	check(not JSON.stringify(wire.filter(func(f: Dictionary) -> bool: return f.type != "card_sync")).contains("PRIVATE_B"),"Untouched private opponent deck identity is not exposed")
	if "public" in args: check(ub.rooms.method == "Relay","Tap synchronization uses public TLS relay")
	ua.network.disconnect_session()
	ub.network.disconnect_session()
	a.queue_free()
	b.queue_free()
	await process_frame
	print("CARDLINK 7.5 NETWORK: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
