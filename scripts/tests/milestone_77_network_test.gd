extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var base: String = args[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var a: Control = await create_client(base.path_join("a"),"Front",Color.BLUE)
	var b: Control = await create_client(base.path_join("b"),"PRIVATE_B",Color.GREEN)
	var ca: Node = a.tabletop.match_controller
	var cb: Node = b.tabletop.match_controller
	var front: Dictionary = ca.loader.load_records()[0].metadata
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var store = preload("res://scripts/card_storage.gd").new(base.path_join("a"))
	var back: Dictionary = store.save_asset(image.save_png_to_buffer())
	var faces: Array = preload("res://scripts/card_faces.gd").list(front)
	faces.append({"face_id":"back","face_index":1,"name":"PRIVATE_BACK","image_path":back.image_path,"image_hash":back.image_hash})
	var saved: Dictionary = preload("res://scripts/card_faces.gd").save(store.directory,front.name,faces,front)
	check(not saved.has("error"),"Host has a two-face definition")
	var guest_store = preload("res://scripts/card_storage.gd").new(base.path_join("b"))
	guest_store.save_card(FileAccess.get_file_as_bytes(front.image_path),"Front",Vector2i(750,1050))
	var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
	deck.cards = [{"card_id":front.card_id,"quantity":3}]
	ca.load_deck(deck,false)
	var ua: Node = a.get_node("Network")
	var ub: Node = b.get_node("Network")
	if "relay" in args:
		for panel: Node in [ua,ub]: panel.rooms.signaling.service_url = "http://127.0.0.1:18787"
	if "public" in args or "relay" in args:
		await ua.rooms.host_room("7.7 face host")
		if ua.network.server != null: ua.network.server.stop(); ua.network.server = null
		ub.rooms.config.set_value("internet","direct_attempt_seconds",0.3)
		await ub.rooms.join_room(ua.rooms.code,"7.7 face guest")
	else:
		var port: int = randi_range(33000,43000)
		ua.network.host_game(port,"Host","127.0.0.1")
		ub.network.join_game("127.0.0.1",port,"Guest")
	check(await wait_for(func() -> bool: return ua.network.session.state == "connected" and ub.network.session.state == "connected",20),"Two 7.7 clients connect")
	if failures: quit(1); return
	if "public" in args or "relay" in args:
		await create_timer(2).timeout
		check(ub.rooms.method == "Relay","Room test settled on relay")
	ua.gameplay.start(); ub.gameplay.start()
	check(await wait_for(func() -> bool: return ua.gameplay.card_sync.checked and ub.gameplay.card_sync.checked,15),"Multi-face availability handshake")
	if failures:
		print(ua.gameplay.card_sync.status," / ",ub.gameplay.card_sync.status," | ",ua.network.session.state," ",ub.network.session.state)
		print(wire)
		quit(1); return
	check(ub.gameplay.card_sync.need.images == [back.image_hash],"Guest requests only missing back image")
	ua.gameplay.card_sync.decide("sync")
	check(await wait_for(func() -> bool: return ua.gameplay.card_sync.status.begins_with("CARD SYNC COMPLETE") and ub.gameplay.card_sync.status.begins_with("CARD SYNC COMPLETE"),20),"Multi-face Card Sync completes")
	if failures: print(ua.gameplay.card_sync.status," / ",ub.gameplay.card_sync.status); quit(1); return
	check(ub.gameplay.card_sync.reports["2"].images == 1,"Only one image transferred to guest")
	check(ub.gameplay.card_sync.catalog.check(ub.gameplay.card_sync.required()).images.is_empty(),"Repeat availability requires no images")
	check(ub.gameplay.card_sync.catalog.check(ub.gameplay.card_sync.required()).definitions.is_empty(),"Repeat availability requires no duplicate definitions")
	ua.gameplay.card_sync.decide("start"); ub.gameplay.card_sync.decide("start")
	check(await wait_for(func() -> bool: return ua.gameplay.enabled and ub.gameplay.enabled),"Match starts")
	ca.draw_card()
	var card: Control = ca.card_by_id(ca.model.players.local.hand[0])
	var id: String = card.state.match_instance_id
	wire.clear()
	preload("res://scripts/usability/face_actions.gd").change(a.tabletop,card,1)
	await settle()
	check(not JSON.stringify(wire).contains("PRIVATE_BACK") and not JSON.stringify(wire).contains("face_index") and not JSON.stringify(wire).contains(id),"Private hand face change sends no identity/index/instance")
	preload("res://scripts/usability/face_actions.gd").change(a.tabletop,card,0)
	ca.move_card(card,"battlefield")
	card.set_tapped(true)
	card.state.counters = {"charge":4}
	card.update_counters()
	check(await wait_for(func() -> bool: return cb.card_by_id(id) != null and cb.card_by_id(id).state.tapped),"Front becomes public with same ID")
	var remote: Control = cb.card_by_id(id)
	await settle()
	check(remote.state.faces.size() == 2 and remote.state.active_face_index == 0,"Remote resolves available faces from approved local catalog")
	var logical: Vector2 = card.position
	wire.clear()
	preload("res://scripts/usability/face_actions.gd").change(a.tabletop,card,1)
	check(await wait_for(func() -> bool: return remote.state.active_face_index == 1 and remote.state.display_name == "PRIVATE_BACK"),"Host face change reaches guest")
	check(remote.card_image.texture != null and remote.card_image.texture.get_image().get_pixel(0,0).r>0.9,"Guest displays transferred alternate artwork")
	check(not JSON.stringify(wire).contains("image_path") and not JSON.stringify(wire).contains('"faces"'),"Public patch contains no alternate-face array or local paths")
	preload("res://scripts/usability/face_actions.gd").change(b.tabletop,remote,0)
	check(await wait_for(func() -> bool: return card.state.active_face_index == 0),"Guest changes host-owned card back")
	check(ca.card_by_id(id)==card and cb.card_by_id(id)==remote,"Both clients preserve card objects")
	check(card.position.distance_to(logical)<0.05,"Position survives within existing wire quantization")
	check(card.state.tapped and remote.state.tapped,"Tap survives both face changes")
	check(card.state.counters.get("charge")==4 and remote.state.counters.get("charge")==4,"Counters survive both face changes")
	check(card.state.owner_player_id=="local" and remote.state.owner_player_id=="opponent" and card.state.current_zone=="battlefield","Ownership and zone unchanged")
	check(preload("res://scripts/network/network_action.gd").snapshot(ua.gameplay.state),"Public snapshot validates active-face extension")
	preload("res://scripts/usability/face_actions.gd").change(a.tabletop,card,1)
	await settle()
	ub.gameplay.resync.request()
	await settle()
	check(cb.card_by_id(id).state.active_face_index==1,"Public resync preserves alternate face")
	ua.network.disconnect_session()
	check(await wait_for(func() -> bool: return ua.network.available() and ub.network.available()),"Disconnect retains local match")
	ua.gameplay.recovery.reconnect(); ub.gameplay.recovery.reconnect()
	check(await wait_for(func() -> bool: return ua.gameplay.enabled and ub.gameplay.enabled and not ua.gameplay.recovery.suspended and not ub.gameplay.recovery.suspended,25),"Authenticated reconnect succeeds")
	card = ca.card_by_id(id)
	check(cb.card_by_id(id)!=null and cb.card_by_id(id).state.active_face_index==1 and card.state.active_face_index==1,"Reconnect restores alternate face on same ID")
	ca.visibility.set_public_reveal(card.state,true)
	ca.move_card(card,"library",true,"local")
	await settle()
	check(cb.remote_library_knowledge.size()==1 and cb.opponent_pile.back_image.texture != b.tabletop.backs.texture(),"Revealed alternate library top remains visible")
	ca.library_actions.put_nth(card,"local",3)
	await settle()
	check(cb.remote_library_knowledge.has("2"),"Known alternate face follows third library position")
	ca.shuffle_library()
	await settle()
	check(cb.remote_library_knowledge.is_empty() and cb.opponent_pile.back_image.texture==b.tabletop.backs.texture(),"Shuffle clears known alternate face")
	ua.network.disconnect_session(); ub.network.disconnect_session()
	a.queue_free(); b.queue_free()
	await process_frame
	print("CARDLINK 7.7 NETWORK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
