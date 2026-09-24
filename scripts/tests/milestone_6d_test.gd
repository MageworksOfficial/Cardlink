extends "res://scripts/tests/milestone_6b_test.gd"
var ra: Node
var rb: Node
var drop_kind: String = ""
var dropped: bool = false
func same(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))
func rejoin() -> bool:
	ra.recovery.reconnect()
	rb.recovery.reconnect()
	return await wait_for(func() -> bool: return ra.enabled and rb.enabled and not ra.recovery.suspended and not rb.recovery.suspended and ra.recovery.status == "Match restored." and rb.recovery.status == "Match restored.",10)
func disconnect_pair() -> void:
	ra.network.disconnect_session()
	await wait_for(func() -> bool: return ra.network.available() and rb.network.available())
	await settle()
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.gui_embed_subwindows = true
	var a: Control = await create_client(base.path_join("a"),"HOST_PRIVATE",Color.BLUE)
	var b: Control = await create_client(base.path_join("b"),"GUEST_PRIVATE",Color.RED)
	ra = a.get_node("Network").gameplay
	rb = b.get_node("Network").gameplay
	var ca: Node = a.tabletop.match_controller
	var cb: Node = b.tabletop.match_controller
	var port: int = randi_range(33000,43000)
	ra.network.host_game(port,"Host","127.0.0.1")
	rb.network.join_game("127.0.0.1",port,"Guest")
	await wait_for(func() -> bool: return ra.network.session.state == "connected" and rb.network.session.state == "connected")
	ra.start()
	rb.start()
	await wait_for(func() -> bool: return ra.card_sync.checked and rb.card_sync.checked)
	ra.card_sync.decide("sync")
	await wait_for(func() -> bool: return ra.card_sync.status.begins_with("CARD SYNC COMPLETE") and rb.card_sync.status.begins_with("CARD SYNC COMPLETE"),15)
	ra.card_sync.decide("start")
	rb.card_sync.decide("start")
	check(await wait_for(func() -> bool: return ra.recovery.authenticated and rb.recovery.authenticated),"Both clients retain safe session rejoin identity")
	var match_id: String = ra.recovery.context.match
	ca.library_actions.draw_n("local",3)
	cb.library_actions.draw_n("local",6)
	await settle()
	var private_id: String = cb.model.players.local.hand[0]
	var camera: Vector2 = a.tabletop.view.pan
	await disconnect_pair()
	check(ca.model.players.local.hand.size() == 3 and cb.model.players.local.hand.size() == 6,"Disconnect preserves both private hands")
	check(await rejoin(),"Reconnect restores same match")
	check(ra.recovery.context.match == match_id and rb.recovery.context.match == match_id,"Match session identity survives new transport")
	check(a.tabletop.view.pan == camera,"Reconnect preserves local camera")
	var card: Control = ca.card_by_id(ca.model.players.local.hand[0])
	ca.move_card(card,"battlefield")
	await settle()
	var id: String = card.state.match_instance_id
	# Drop all queued host commits, leaving the host's ordered state ahead of Guest.
	var old_processing: bool = ra.network.is_processing()
	ra.network.set_process(false)
	card.position += Vector2(77,33)
	ca.change_life("local",-4)
	a.tabletop.create_token("Test Token","local","local","","2","2")
	var counter: Control = a.tabletop.extras.create_counter(Vector2(300,400))
	counter.value = 7
	counter.refresh()
	var zone: Control = ca.zone_for("graveyard","local")
	zone.position += Vector2(40,20)
	ra.scan()
	ca.end_turn()
	ra.network.outgoing.clear()
	ra.network.set_process(old_processing)
	await disconnect_pair()
	check(await rejoin(),"Reconnect repairs missed public actions")
	check(same(rb.state.cards[id].position,ra.state.cards[id].position),"Missed card position restored")
	check(rb.state.players.player_1.life == 36,"Missed life change restored")
	check(rb.state.cards.size() == ra.state.cards.size(),"Token appears once")
	check(rb.state.counters[counter.instance_id].value == 7,"Standalone counter update restored")
	check(same(rb.state.zones,ra.state.zones),"Zone placement restored")
	check(same(rb.state.turn,ra.state.turn),"Turn and active player restored")
	check(rb.committed == ra.committed,"Public revisions agree")
	check(not JSON.stringify(ra.state).contains(private_id),"Public recovery excludes hidden instance identities")
	var history_count: int = rb.state.history.size()
	ra.resync.request()
	await settle()
	check(rb.state.history.size() == history_count and rb.state.cards.size() == ra.state.cards.size(),"Manual resync does not duplicate history or tokens")
	# Resent action ID/sequence is acknowledged, not applied twice.
	cb.change_life("local",-2)
	rb.scan()
	var pending: Dictionary = rb.journal.pending.values().back().duplicate(true)
	await settle()
	var life: int = ra.state.players.player_2.life
	rb.send_frame("request",pending)
	await settle()
	check(ra.state.players.player_2.life == life and rb.journal.pending.is_empty(),"Repeated public action is idempotent and acknowledged")
	rb.hidden.auto_approve = true
	ra.hidden.request("hand")
	await wait_for(func() -> bool: return ca.remote_inspection)
	await disconnect_pair()
	check(not ca.contents.visible and ra.hidden.outgoing == null and rb.hidden.incoming == null,"Disconnect revokes temporary hidden access")
	check(await rejoin() and ra.hidden.outgoing == null,"Reconnect never restores old inspection grants")
	for net: Node in [ra.network,rb.network]:
		net.message_sent.connect(func(frame: Dictionary) -> void:
			if not dropped and not drop_kind.is_empty() and frame.type == "transfer_tx" and frame.kind == drop_kind:
				dropped = true
				net.outgoing.clear()
				net.disconnect_session())
	for phase: String in ["prepare","prepared","commit","committed"]:
		ra.hidden.request("hand")
		await wait_for(func() -> bool: return ca.remote_inspection)
		ca.contents_list.select(0)
		var transfer_id: String = str(ca.contents_list.get_item_metadata(0))
		drop_kind = phase
		dropped = false
		ra.hidden.move_selected("take")
		await wait_for(func() -> bool: return dropped and ra.network.available() and rb.network.available())
		await settle()
		check(dropped,"Interrupted at transaction phase: " + phase)
		drop_kind = ""
		check(await rejoin(),"Authenticated recovery at phase: " + phase)
		await settle()
		var copies: int = int(ca.card_by_id(transfer_id) != null) + int(cb.card_by_id(transfer_id) != null)
		check(copies == 1,"Exactly one playable copy after " + phase + " interruption")
		check(not ra.transactions.has_unfinished() and not rb.transactions.has_unfinished(),"Transaction resolves after " + phase)
	var committed_tx: Dictionary = {}
	for row: Dictionary in ra.transactions.records.values():
		if row.side == "receiver" and row.phase == "committed": committed_tx = row
	var hand_count: int = ca.model.players.local.hand.size()
	rb.transactions.send("commit",committed_tx.tx,{"id":committed_tx.id})
	await settle()
	check(ca.model.players.local.hand.size() == hand_count,"Duplicate transfer commit never recreates a card")
	await disconnect_pair()
	ra.recovery.continue_offline()
	check(ca.model.players.local.hand.size() == hand_count,"Continue Offline preserves private state")
	check(await rejoin(),"Offline match requires and completes resync")
	var expected_life: int = ra.state.players.player_2.life-3
	rb.network.set_process(false)
	cb.change_life("local",-3)
	rb.scan()
	rb.network.outgoing.clear()
	rb.network.set_process(true)
	await disconnect_pair()
	check(await rejoin(),"Rejoin with an unacknowledged guest action")
	check(await wait_for(func() -> bool: return ra.state.players.player_2.life == expected_life and rb.journal.pending.is_empty()),"Unacknowledged action is resent and applied exactly once")
	var journal = preload("res://scripts/network/public_action_journal.gd").new()
	for i: int in 300: journal.remember({"action_id":str(i)})
	check(journal.recent.size() == 256,"Recent public action journal is bounded")
	var summaries: Array = wire.filter(func(f: Dictionary) -> bool: return f.type == "transfer_tx" and f.kind == "summary")
	check(not JSON.stringify(summaries).contains("GUEST_PRIVATE") and not JSON.stringify(summaries).contains("definition"),"Reconciliation summaries contain no card definitions or hidden names")
	var pause_record: Dictionary = {"id":"test_pause","phase":"prepared"}
	ra.transactions.unresolved(pause_record,"Test mismatch")
	check(pause_record.phase == "unresolved" and ra.transactions.status.contains("paused"),"Unresolvable transaction warns instead of creating or deleting cards")
	# A wrong possession proof cannot silently turn into a fresh shared match.
	await disconnect_pair()
	var secret: String = rb.recovery.context.secret
	rb.recovery.context.secret = "0".repeat(64)
	ra.recovery.reconnect()
	rb.recovery.reconnect()
	await wait_for(func() -> bool: return rb.recovery.status.contains("Unable to reconnect"))
	check(not rb.enabled and rb.recovery.status.contains("identity"),"Wrong reconnect credential rejected")
	rb.recovery.context.secret = secret
	ra.network.disconnect_session()
	rb.network.disconnect_session()
	await settle()
	a.queue_free()
	b.queue_free()
	await process_frame
	print("MILESTONE 6D: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
