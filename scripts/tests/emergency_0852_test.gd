extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
 var base: String=OS.get_cmdline_user_args()[0]
 root.size=Vector2i(1152,760);root.gui_embed_subwindows=true
 var keys=preload("res://scripts/usability/input_bindings.gd").new(base.path_join("new.cfg"))
 check(keys.keys.tap==KEY_T and keys.keys.token==KEY_Q and keys.keys.undo==(KEY_Z|KEY_MASK_CTRL),"New T/Q/Undo defaults")
 var config:=ConfigFile.new();config.set_value("keys","tap",KEY_Q);config.set_value("keys","token",KEY_T);config.save(base.path_join("old.cfg"))
 keys=preload("res://scripts/usability/input_bindings.gd").new(base.path_join("old.cfg"))
 check(keys.keys.tap==KEY_T and keys.keys.token==KEY_Q,"Migrate stock old pair")
 config.set_value("keys","tap",KEY_K);config.save(base.path_join("custom.cfg"))
 keys=preload("res://scripts/usability/input_bindings.gd").new(base.path_join("custom.cfg"))
 check(keys.keys.tap==KEY_K and keys.keys.token==KEY_T,"Keep deliberate custom bindings")
 var a: Control=await create_client(base.path_join("a"),"Alpha",Color.CORAL)
 var b: Control=await create_client(base.path_join("b"),"Beta",Color.SKY_BLUE)
 var ra: Node=a.get_node("Network").gameplay;var rb: Node=b.get_node("Network").gameplay
 var own_record: Dictionary=a.tabletop.match_controller.loader.load_records()[0].metadata
 var alias: String=base.path_join("a/legacy-art.png")
 check(DirAccess.rename_absolute(own_record.image_path,alias)==OK,"Fixture uses alternate local image filename")
 own_record.image_path=alias
 preload("res://scripts/card_storage.gd").write_atomic(base.path_join("a/definitions").path_join(own_record.card_id+".json"),JSON.stringify(own_record).to_utf8_buffer())
 var catalog=preload("res://scripts/network/card_sync_catalog.gd").new(base.path_join("a"))
 check(catalog.has_image(own_record.image_hash) and catalog.asset_path(own_record.image_hash)==alias,"Hash-matching legacy filename is reusable")
 var port: int=randi_range(35000,48000)
 ra.network.host_game(port,"Host","127.0.0.1");rb.network.join_game("127.0.0.1",port,"Guest")
 check(await wait_for(func() -> bool:return ra.network.session.state=="connected" and rb.network.session.state=="connected"),"Connected")
 ra.card_sync.background_mode=true;rb.card_sync.background_mode=true;ra.start();rb.start()
 check(await wait_for(func() -> bool:return ra.card_sync.checked and rb.card_sync.checked),"Discovered")
 check(ra.card_sync.inspect_required().missing==1 and rb.card_sync.inspect_required().missing==1,"Both missing opposite definition")
 ra.card_sync.decide("sync");rb.card_sync.decide("sync")
 check(await wait_for(func() -> bool:return not ra.card_sync.running and not rb.card_sync.running and ra.card_sync.inspect_required().missing==0 and rb.card_sync.inspect_required().missing==0,15),"Both sync")
 var remote: Dictionary=ra.card_sync.remote[0]
 var path: String=base.path_join("a/definitions").path_join(remote.id+".json")
 check(FileAccess.file_exists(path),"Peer definition stored")
 preload("res://scripts/library_storage.gd").new(base.path_join("a")).delete_definition(path)
 check(await wait_for(func()->bool:return ra.card_sync.need.get("missing",0)==1),"Collection deletion invalidates discovery cache")
 check(ra.card_sync.inspect_required().images.is_empty(),"Existing artwork reused after definition deletion")
 check(ra.card_sync.catalog.store_definition(remote).is_empty(),"Restore definition with existing artwork")
 preload("res://scripts/collection_events.gd").publish(base.path_join("a"))
 check(await wait_for(func()->bool:return ra.card_sync.need.get("missing",1)==0),"Collection import refreshes readiness")
 ra.start_public();rb.start_public()
 check(await wait_for(func()->bool:return ra.enabled and rb.enabled),"Public session begins")
 var sequence: int=rb.request_sequence
 check(not rb.submit([{"kind":"counter_set","data":{"id":"bounded","position":[0,0],"value":1000001,"label":"Invalid"}}]),"Invalid update refused")
 check(rb.request_sequence==sequence,"Rejection consumes no sequence")
 b.tabletop.match_controller.change_life("local",-2)
 check(await wait_for(func()->bool:return ra.state.players.player_2.life==38),"Next valid action reaches host")
 var original: Dictionary=a.tabletop.battle.reset.start.sources[0].deck.duplicate(true)
 original["deck_back"]={"type":"color","color":"#551188","preset":"","asset":""}
 var builder: Control=a.deck_builder
 builder.loader=preload("res://scripts/library_loader.gd").new(base.path_join("a"))
 builder.storage=preload("res://scripts/deck_storage.gd").new(base.path_join("decks"))
 builder.open_builder();builder.deck=original;builder.sync_fields()
 check(builder.save_current(),"Deck with back saves")
 builder.load_selected()
 check(builder.deck.deck_back==original.deck_back,"Deck back survives reload")
 builder.entries.select(0);builder.select_entry(0)
 check(builder.preview.texture!=null and not builder.preview_id.is_empty(),"Backed card stays selectable with face preview")
 await process_frame
 var back_button: Button
 for node: Node in builder.find_children("*","Button",true,false):
  if node.text.begins_with("Deck Back"):back_button=node
 check(back_button!=null and back_button.get_global_rect().end.x<=root.size.x,"Deck Back button fits standard window")
 ra.network.disconnect_session();await settle();a.queue_free();b.queue_free();await process_frame
 print("HOTFIX 0852: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
