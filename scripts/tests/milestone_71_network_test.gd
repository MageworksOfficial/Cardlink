extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var base: String = args[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var a: Control = await create_client(base.path_join("a"),"Allowed knowledge A",Color.BLUE)
	var b: Control = await create_client(base.path_join("b"),"Private library B",Color.RED)
	var ua: Node = a.get_node("Network")
	var ub: Node = b.get_node("Network")
	var ra: Node = ua.gameplay
	var rb: Node = ub.gameplay
	var ca: Node = a.tabletop.match_controller
	var cb: Node = b.tabletop.match_controller
	if "public" in args:
		await ua.rooms.host_room("7.1 knowledge test host")
		if ua.rooms.network.server != null:
			ua.rooms.network.server.stop()
			ua.rooms.network.server = null
		ub.rooms.config.set_value("internet","direct_attempt_seconds",0.3)
		await ub.rooms.join_room(ua.rooms.code,"7.1 knowledge test guest")
	else:
		var port: int = randi_range(33000,43000)
		ua.network.host_game(port,"Host","127.0.0.1")
		ub.network.join_game("127.0.0.1",port,"Guest")
	check(await wait_for(func() -> bool: return ua.network.session.state=="connected" and ub.network.session.state=="connected",20),"Online connection preserved")
	if failures>0:
		print(ua.rooms.status," / ",ub.rooms.status)
		quit(1)
		return
	ra.start()
	rb.start()
	await wait_for(func() -> bool: return ra.card_sync.checked and rb.card_sync.checked)
	ra.card_sync.decide("sync")
	check(await wait_for(func() -> bool: return ra.card_sync.status.begins_with("CARD SYNC COMPLETE") and rb.card_sync.status.begins_with("CARD SYNC COMPLETE"),20),"Existing Card Sync works")
	ra.card_sync.decide("start")
	rb.card_sync.decide("start")
	check(await wait_for(func() -> bool: return ra.enabled and rb.enabled and ra.recovery.authenticated and rb.recovery.authenticated),"Shared match and recovery identity preserved")
	await settle()
	check(not ca.playtest.set_mode("local_playtest") and ca.playtest.mode=="online","Unsafe online-to-playtest switch preserves active match")
	check(cb.remote_library_knowledge.is_empty(),"Unknown library sends no card identities")
	ca.review.open_review("local",2,true)
	var known: String = ca.review.top[0]
	var unknown: String = ca.pile.order[5]
	ca.review.cancel()
	await settle()
	check(ca.Knowledge.known(ca.card_by_id(known).state,"local") and cb.remote_library_knowledge.is_empty(),"Scry knowledge is viewer-sensitive and not sent to opponent")
	ca.review.open_review("local",1,false)
	ca.review.cancel()
	await settle()
	check(cb.remote_library_knowledge.size()==1 and cb.remote_library_knowledge.get("0",{}).get("id")==known,"Only explicitly revealed library identity is shared")
	check(cb.opponent_pile.back_image.texture!=b.tabletop.backs.texture(),"Opponent sees the known top face")
	var card: Control = ca.card_by_id(known)
	ca.library_actions.put_nth(card,"local",3)
	await settle()
	check(cb.remote_library_knowledge.has("2") and cb.library_rows("opponent")[2].known and not cb.library_rows("opponent")[0].known,"Known identity follows third position; unknown top stays back")
	ca.library_actions.put_nth(card,"local",1,true)
	await settle()
	check(cb.library_rows("opponent").back().known and cb.remote_library_knowledge.size()==1,"Only the known bottom position synchronizes")
	var memory_frames: Array = wire.filter(func(f: Dictionary) -> bool: return f.type=="hidden_zone" and f.request_id.begins_with("library_memory_"))
	check(not JSON.stringify(memory_frames).contains(unknown),"Knowledge messages never contain unknown instance IDs/order")
	cb.open_library_view("opponent")
	check(cb.contents_list.item_count==10 and cb.contents_list.get_item_icon(0)==b.tabletop.backs.texture(),"Remote normal viewer shows ordered hidden backs and allowed face")
	cb.close_inspection()
	ca.draw_card()
	await settle()
	var private_hand_id: String = ca.model.players.local.hand[0]
	var wire_before: int = wire.size()
	ca.hand_window.open_hand()
	ca.hand_window.restore_hand()
	check(wire.size()==wire_before and cb.opponent_hand.cards_row.get_child_count()==1,"Detach/restore is local-only UI; hand remains one hidden back")
	check(not JSON.stringify(wire.slice(wire_before)).contains(private_hand_id),"Detaching sends no hidden hand identity")
	a.tabletop.match_controller.hearts.hearts.local.get_parent().get_child(2).pressed.emit()
	await settle()
	check(cb.model.players.opponent.life==41,"Heart life change uses existing public sync")
	ua.network.disconnect_session()
	check(await wait_for(func() -> bool: return ua.network.available() and ub.network.available()),"Disconnect preserves local match")
	if "public" in args:
		ra.recovery.reconnect()
		rb.recovery.reconnect()
	else:
		ra.recovery.reconnect()
		rb.recovery.reconnect()
	check(await wait_for(func() -> bool: return ra.enabled and rb.enabled and not ra.recovery.suspended and not rb.recovery.suspended,25),"Authenticated reconnect restores shared match")
	await settle()
	check(cb.remote_library_knowledge.size()==1 and cb.library_rows("opponent").back().known,"Reconnect restores only permitted library knowledge")
	ca.shuffle_library()
	await settle()
	check(cb.remote_library_knowledge.is_empty() and cb.opponent_pile.back_image.texture==b.tabletop.backs.texture(),"Shuffle clears opponent knowledge and pile face")
	check(ca.library_rows("local").all(func(row: Dictionary) -> bool: return not row.known),"Shuffle also clears owner-only Scry knowledge")
	ra.hidden.auto_approve = true
	rb.hidden.request("library")
	check(await wait_for(func() -> bool: return cb.remote_inspection),"Approved Search Library still opens")
	await settle()
	check(cb.remote_library_knowledge.size()==ca.pile.order.size(),"Approved inspection records only authorized library identities")
	cb.close_inspection()
	check(await wait_for(func() -> bool: return cb.remote_library_knowledge.is_empty()),"Closing unrestricted search shuffles and clears all shared knowledge")
	if "public" in args:
		check(ua.rooms.method=="Relay" and ub.rooms.method=="Relay","7.1 knowledge uses existing public relay without server changes")
		ua.rooms.cancel()
		ub.rooms.cancel()
	else:
		ua.network.disconnect_session()
		ub.network.disconnect_session()
	await create_timer(0.5).timeout
	a.queue_free()
	b.queue_free()
	await process_frame
	print("CARDLINK 7.1 NETWORK: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
