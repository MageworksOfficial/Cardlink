extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var base: String=args[0]
	if args.size()<2: print("Supply isolated downloaded-card directory as second argument.");quit(1);return
	var source: String=args[1]
	# Reuse the exact stored test directory spelling (Windows arguments use backslashes).
	for file: String in DirAccess.get_files_at(source.path_join("definitions")):
		var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("definitions").path_join(file)))
		if metadata.get("source")=="scryfall": source=str(metadata.image_path).get_base_dir();break
	var a: Control=await create_client(base.path_join("a"),"Synthetic host",Color.BLUE)
	var b: Control=await create_client(base.path_join("b"),"Synthetic guest",Color.GREEN)
	var ca: Node=a.tabletop.match_controller
	var cb: Node=b.tabletop.match_controller
	ca.loader=preload("res://scripts/library_loader.gd").new(source)
	var deck: Dictionary=preload("res://scripts/deck_storage.gd").new_deck()
	for row: Dictionary in ca.loader.load_records():
		if row.metadata.get("source")=="scryfall":deck.cards.append({"card_id":row.metadata.card_id,"quantity":1})
	check(deck.cards.size()==2,"Uses two previously downloaded official card definitions without new provider requests")
	var loaded: Dictionary=ca.load_deck(deck,false)
	check(not loaded.has("error"),"Downloaded definitions load before connecting")
	if loaded.has("error"):
		print(loaded)
		for diagnostic: Dictionary in ca.loader.load_records(): print(diagnostic.name," ",diagnostic.errors)
		quit(1); return
	var ua: Node=a.get_node("Network");var ub: Node=b.get_node("Network")
	var port: int=randi_range(33000,43000)
	ua.network.host_game(port,"Host","127.0.0.1");ub.network.join_game("127.0.0.1",port,"Guest")
	check(await wait_for(func() -> bool:return ua.network.session.state=="connected" and ub.network.session.state=="connected",15),"Imported-card clients connect with unchanged protocol")
	ua.gameplay.start();ub.gameplay.start()
	check(await wait_for(func() -> bool:return ua.gameplay.card_sync.checked and ub.gameplay.card_sync.checked,20),"Ordinary Card Sync discovers imported face assets")
	for sync: Node in [ua.gameplay.card_sync,ub.gameplay.card_sync]:
		for row: Dictionary in sync.own:
			for hash_value: String in sync.catalog.images(row):
				check(sync.catalog.has_image(hash_value),"Source asset verified: "+row.name)
	ua.gameplay.card_sync.decide("sync")
	check(await wait_for(func() -> bool:return ua.gameplay.card_sync.status.begins_with("CARD SYNC COMPLETE") and ub.gameplay.card_sync.status.begins_with("CARD SYNC COMPLETE"),45),"Downloaded official images transfer through existing Card Sync")
	if failures:print(ua.gameplay.card_sync.status," / ",ub.gameplay.card_sync.status);quit(1);return
	check(ub.gameplay.card_sync.reports["2"].images==3,"One ordinary image plus both printed faces transfer")
	check(ub.gameplay.card_sync.catalog.check(ub.gameplay.card_sync.required()).images.is_empty(),"Imported image hashes reused after transfer")
	check(not JSON.stringify(wire).contains("source_images") and not JSON.stringify(wire).contains("scryfall.com"),"No provider metadata or requests added to multiplayer wire")
	ua.gameplay.card_sync.decide("start");ub.gameplay.card_sync.decide("start")
	check(await wait_for(func() -> bool:return ua.gameplay.enabled and ub.gameplay.enabled),"Imported deck starts normal shared play")
	ca.draw_card();var card: Control=ca.card_by_id(ca.model.players.local.hand[0]);ca.move_card(card,"battlefield")
	check(await wait_for(func() -> bool:return cb.card_by_id(card.state.match_instance_id)!=null),"Imported official card plays and synchronizes normally")
	ua.network.disconnect_session();ub.network.disconnect_session();a.queue_free();b.queue_free()
	await process_frame
	print("CARDLINK 7.8 CARD SYNC: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
