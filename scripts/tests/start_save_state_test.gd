extends "res://scripts/tests/milestone_6b_test.gd"
const Data=preload("res://scripts/battle/online_state_data.gd")
const Capsule=preload("res://scripts/battle/save_state_capsule.gd")
const Fingerprint=preload("res://scripts/battle/deck_fingerprint.gd")
const Start=preload("res://scripts/battle/start_match_control.gd")
func connect_clients(pa: Node,pb: Node,port: int) -> void:
	pa.network.host_game(port,"Host","127.0.0.1");pb.network.join_game("127.0.0.1",port,"Guest")
func close_clients(pa: Node,pb: Node) -> void:
	pa.gameplay.recovery.leave();pb.gameplay.recovery.leave()
func run() -> void:
	var base: String=OS.get_cmdline_user_args()[0]
	root.size=Vector2i(1400,900);root.gui_embed_subwindows=true
	for flags: Array in [[false,false],[true,false],[false,true],[true,true]]:
		var row: Dictionary=Start.presentation(flags[0],flags[1],false,false)
		check(row.text=="START MATCH" and row.ready==(flags[0] and flags[1]),"Start readiness "+str(flags))
	check(Start.presentation(true,true,true,false).text=="MATCH ACTIVE","Active start state")
	check(not Start.presentation(true,true,false,true).ready,"Duplicate start is disabled while starting")
	var key: PackedByteArray=Crypto.new().generate_random_bytes(64)
	var sealed: Dictionary=Capsule.seal({"secret":"PRIVATE_HAND_TEST","order":["D","A","E"]},key)
	check(Capsule.open(sealed,key).data.order==["D","A","E"],"Authenticated private capsule round trip")
	check(not JSON.stringify(sealed).contains("PRIVATE_HAND_TEST"),"Sealed capsule has no plaintext identity")
	check(Capsule.open(sealed,Crypto.new().generate_random_bytes(64)).has("error"),"Wrong private key rejected")
	sealed.mac="0".repeat(64);check(Capsule.open(sealed,key).has("error"),"Tampered capsule rejected")
	var a: Control=await create_client(base.path_join("a"),"PRIVATE_HOST",Color.CORAL)
	var b: Control=await create_client(base.path_join("b"),"PRIVATE_GUEST",Color.SKY_BLUE)
	var pa: Node=a.get_node("Network");var pb: Node=b.get_node("Network")
	var na: Node=pa.network;var nb: Node=pb.network;var ra: Node=pa.gameplay;var rb: Node=pb.gameplay
	var ma: Node=a.tabletop;var mb: Node=b.tabletop;var ca: Node=ma.match_controller;var cb: Node=mb.match_controller
	var sa: Node=ma.battle.saves;var sb: Node=mb.battle.saves
	sb.storage=preload("res://scripts/named_json_storage.gd").new(base.path_join("guest_saves"),"online_state")
	sa.storage=preload("res://scripts/named_json_storage.gd").new(base.path_join("saves"),"online_state")
	# Exercise saved multi-face instances against existing local definitions.
	var meta: Dictionary=ca.loader.load_records()[0].metadata
	var art:=Image.create(750,1050,false,Image.FORMAT_RGBA8);art.fill(Color.PURPLE)
	var art_store=preload("res://scripts/card_storage.gd").new(base.path_join("a"))
	var back_art: Dictionary=art_store.save_asset(art.save_png_to_buffer())
	var faces: Array=preload("res://scripts/card_faces.gd").list(meta)
	faces.append({"face_id":"back","face_index":1,"name":"HOST_SECOND_FACE","image_path":back_art.image_path,"image_hash":back_art.image_hash})
	preload("res://scripts/card_faces.gd").save(art_store.directory,meta.name,faces,meta)
	ca.load_deck(ma.battle.reset.start.sources[0].deck.duplicate(true),false)
	var p1: String=sa.fingerprint();var p2: String=sb.fingerprint()
	check(p1.length()==64 and p2.length()==64 and p1!=p2,"Both functional source fingerprints available")
	var source: Dictionary=ma.battle.reset.start.sources[0]
	source.deck.deck_name="Renamed";source.deck.deck_id="copy"
	check(sa.fingerprint()==p1,"Deck rename/local deck ID excluded")
	source.deck.cards[0].quantity+=1;check(sa.fingerprint()!=p1,"Quantity change invalidates fingerprint");source.deck.cards[0].quantity-=1
	check(Data.mismatch(false,true).contains("Player 1") and Data.mismatch(true,false).contains("Player 2") and Data.mismatch(false,false).begins_with("Both"),"Specific mismatch errors")
	var port: int=randi_range(33000,43000)
	await connect_clients(pa,pb,port)
	check(await wait_for(func() -> bool: return na.session.state=="connected" and nb.session.state=="connected"),"Two clients connect locally")
	ra.card_sync.begin();rb.card_sync.begin()
	check(await wait_for(func() -> bool: return ra.card_sync.checked and rb.card_sync.checked),"Deck readiness exchanged")
	ma.shortcuts.start_match_button._process(0.1)
	check(ma.shortcuts.start_match_button.gold and not ma.shortcuts.start_match_button.disabled,"Top bar ready button is gold/enabled")
	ma.table_preferences.put("reduce_motion",true);ma.shortcuts.start_match_button._process(0.1)
	check(ma.shortcuts.start_match_button.gold and not ma.shortcuts.start_match_button.pulsing,"Reduce Motion retains static gold")
	# Let existing sync provide both loaded-deck assets, never use save as a deck package.
	ra.card_sync.decide("sync");rb.card_sync.decide("sync")
	check(await wait_for(func() -> bool: return not ra.card_sync.running and not rb.card_sync.running and ra.card_sync.reports.size()==2,15),"Card Sync completes before save setup")
	pa.preparation.start_match();pb.preparation.start_match()
	check(await wait_for(func() -> bool: return ra.enabled and rb.enabled,10),"Both clients initialize through existing authority")
	ma.shortcuts.start_match_button._process(0.1)
	check(ma.shortcuts.start_match_button.text=="MATCH ACTIVE","Active label after initialization")
	var mid: String=ca.model.match_id;pa.preparation.start_match();pa.preparation.start_match()
	check(ca.model.match_id==mid,"Repeated Start Match does not rebuild")
	ca.library_actions.draw_n("local",3);cb.library_actions.draw_n("local",2)
	var card: Control=ca.card_by_id(ca.model.players.local.hand[0]);ca.move_card(card,"battlefield");card.set_tapped(true);card.state.set_counter("Loyalty",5);card.state.set_counter("charge",2);card.position=Vector2(450,800)
	preload("res://scripts/usability/face_actions.gd").change(ma,card,1)
	var down: Control=cb.card_by_id(cb.model.players.local.hand[0]);cb.move_card(down,"battlefield");down.set_face_down(true)
	ca.move_card(ca.card_by_id(ca.pile.order[0]),"graveyard");ca.move_card(ca.card_by_id(ca.pile.order[0]),"exile");ca.move_card(ca.card_by_id(ca.pile.order[0]),"commander")
	ma.create_token("Save Token","local","local","","2","3");ma.extras.create_counter(Vector2(600,400),7,"Saved Counter")
	ca.change_life("local",-7);cb.change_life("local",-9);ca.end_turn();ca.pile.order.reverse()
	ma.deck_backs.piles["local"]={"type":"color","color":"#2468b4","preset":"","asset":""}
	var background: Dictionary=ma.appearance.background.duplicate(true);background.opacity=0.55;ma.appearance.apply(background,false)
	await settle();await settle()
	var saved_backs: Dictionary=ma.deck_backs.piles.duplicate(true)
	var saved_background: Dictionary=ma.appearance.background.duplicate(true)
	var saved_down_id: String=down.state.match_instance_id
	var saved_card_id: String=card.state.match_instance_id
	var ha: Array=ca.model.players.local.hand.duplicate();var hb: Array=cb.model.players.local.hand.duplicate();var oa: Array=ca.pile.order.duplicate();var ob: Array=cb.pile.order.duplicate()
	var texts: String=""
	for item: Node in ma.shortcuts.quick_row.get_children():
		if item is Button: texts+=item.text
	check(not texts.contains("â") and not texts.contains("�"),"Top HUD has no broken hand glyph")
	check(ma.shortcuts.quick_row.get_child_count()==7,"Extra hand dropdown button removed")
	ma.shortcuts.toggle_hands();check(ca.hands_hidden,"Hands toggle hides hands");ma.shortcuts.toggle_hands();check(not ca.hands_hidden,"Hands toggle restores hands")
	sa.save("Saved two-player table")
	check(await wait_for(func() -> bool: return sb.phase=="save_offer"),"Host Save requires guest approval")
	check(sb.prompt.title=="SAVE MATCH REQUEST","Save approval modal displayed")
	sb.decline_save();await settle()
	check(sa.storage.list_records().is_empty() and sb.storage.list_records().is_empty(),"Declined Save writes neither record")
	check(ca.pile.order==oa and cb.pile.order==ob and sa.status=="Save Match request declined.","Save decline leaves gameplay untouched")
	sb.save("Guest decline test");await wait_for(func() -> bool: return sa.phase=="save_offer");sa.decline_save();await settle()
	check(sa.storage.list_records().is_empty() and sb.storage.list_records().is_empty() and sb.status=="Save Match request declined.","Host can decline guest Save without writing")
	sa.save("bad\nname");check(sa.phase.is_empty(),"Control characters in save name rejected locally")
	wire.clear();sa.save("Saved two-player table")
	await wait_for(func() -> bool: return sb.phase=="save_offer");sb.accept_save()
	check(await wait_for(func() -> bool: return not sa.last_path.is_empty() and not sb.last_path.is_empty(),15),"Both clients write paired saves")
	if sa.last_path.is_empty() or sb.last_path.is_empty(): print(sa.status," / ",sb.status);quit(1);return
	check(sa.status=="Match Saved" and sb.status=="Match Saved","Both see Match Saved after both writes")
	var first_id: String=sa.storage.read_record(sa.last_path).record.data.shared.save_state_id
	sb.save("Saved two-player table")
	check(await wait_for(func() -> bool: return sa.phase=="save_offer"),"Guest Save requires host approval")
	sa.accept_save();check(await wait_for(func() -> bool: return sa.phase.is_empty() and sb.phase.is_empty()),"Guest-requested Save completes")
	var saved: Dictionary=sa.storage.read_record(sa.last_path).record.data
	var guest_saved: Dictionary=sb.storage.read_record(sb.last_path).record.data
	check(Data.validate(saved).is_empty() and Data.validate(guest_saved).is_empty(),"Both versioned paired records validate")
	check(saved.shared==guest_saved.shared and saved.shared.save_state_id!=first_id,"Shared metadata/ID match; duplicate names create separate checkpoints")
	check(sa.storage.list_records().size()==2 and sb.storage.list_records().size()==2,"Both local save libraries contain both records")
	sa.open(true);sb.open(true);check(sa.picker.item_count==2 and sb.picker.item_count==2,"Both Load Match lists show the saves");sa.window.hide();sb.window.hide()
	var own_a: Dictionary=Capsule.open(saved.private_capsule,sa.secret()).data
	var own_b: Dictionary=Capsule.open(guest_saved.private_capsule,sb.secret()).data
	check(own_a.local_tabletop.reset_start.is_empty() and own_a.players[0].deck_manifest.is_empty(),"Save omits source deck recipes/manifests")
	check(not JSON.stringify(own_a).contains(hb[0]) and not JSON.stringify(own_a).contains(ob[0]),"Host local private portion excludes guest hand and hidden library")
	check(not JSON.stringify(own_b).contains(ha[0]) and not JSON.stringify(own_b).contains(oa[0]),"Guest local private portion excludes host hand and hidden library")
	check(not JSON.stringify(wire).contains(hb[0]) and not JSON.stringify(wire).contains(ob[0]) and not JSON.stringify(wire).contains(ha[0]) and not JSON.stringify(wire).contains(oa[0]),"Save wire carries no private hand or ordered-library IDs")
	check(not JSON.stringify(wire).contains("private_capsule"),"Private capsules are never transmitted")
	var host_path: String=sa.last_path;var guest_path: String=sb.last_path
	var guest_directory: String=sb.storage.directory
	var blocked: String=base.path_join("not_a_directory");var blocker:=FileAccess.open(blocked,FileAccess.WRITE);blocker.store_string("test");blocker.close()
	sb.storage.directory=blocked;sa.save("Fail safely");await wait_for(func() -> bool: return sb.phase=="save_offer");sb.accept_save()
	check(await wait_for(func() -> bool: return sa.phase.is_empty() and sb.phase.is_empty()),"Failed local write cancels both sides")
	check(sa.status=="Match could not be saved on both players' computers." and sb.status==sa.status,"Both see synchronized write failure, never success")
	sb.storage.directory=guest_directory
	check(sa.storage.list_records().size()==2 and sb.storage.list_records().size()==2,"No false completed pair remains after write failure")
	var host_directory: String=sa.storage.directory
	sa.storage.directory=blocked;sb.save("Host write failure");await wait_for(func() -> bool: return sa.phase=="save_offer");sa.accept_save()
	check(await wait_for(func() -> bool: return sa.phase.is_empty() and sb.phase.is_empty()),"Host write failure cancels guest request")
	check(sa.status==sb.status and sa.status.contains("could not be saved on both"),"Host failure reports synchronized error")
	sa.storage.directory=host_directory
	check(sa.storage.list_records().size()==2 and sb.storage.list_records().size()==2,"Host write failure leaves no false pair")
	sa.last_path=host_path;sb.last_path=guest_path
	var bad: Dictionary=saved.duplicate(true);bad.version=1;check(Data.validate(bad).contains("older development"),"Older development saves explicitly unsupported")
	ca.library_actions.draw_n("local",1);cb.library_actions.draw_n("local",1);ca.change_life("local",5);await settle()
	sa.load_file(sa.last_path)
	check(await wait_for(func() -> bool: return sb.phase=="load_offer"),"Guest receives Load Match approval")
	var prior: Array=ca.pile.order.duplicate();sb.decline();await settle()
	check(ca.pile.order==prior and sa.phase.is_empty(),"Decline leaves match untouched")
	sa.load_file(sa.last_path);await wait_for(func() -> bool: return sb.phase=="load_offer");sb.accept()
	check(await wait_for(func() -> bool: return sa.phase.is_empty() and sb.phase.is_empty(),10),"Bilateral restore commits and settles")
	check(ca.model.players.local.hand==ha and cb.model.players.local.hand==hb,"Both private hands restored")
	check(ca.pile.order==oa and cb.pile.order==ob,"Both exact library orders restored")
	check(ca.model.players.local.life==33 and cb.model.players.local.life==31,"Both life totals restored")
	card=ca.card_by_id(saved_card_id)
	check(card.tapped and card.state.counters.get("Loyalty")==5 and card.state.counters.get("charge")==2,"Tap, attached counters and loyalty restored")
	check(ca.model.players.local.graveyard.size()==1 and ca.model.players.local.exile.size()==1 and ca.model.players.local.leaders.size()==1,"Graveyard exile leader zones restored")
	check(ma.extras.counters.size()==1 and ma.extras.counters[0].value==7,"Standalone counter restored")
	check(ma.cards.filter(func(x: Control) -> bool: return x.state.is_token).size()==1,"Token restored exactly once")
	check(na.match_epoch==nb.match_epoch and not na.match_epoch.is_empty(),"New shared generation installed")
	check(ra.state==rb.state,"Public state agrees")
	var count: int=ma.cards.size();sa.receive("state_accept",{"id":sa.id,"epoch":sa.transaction_epoch});sb.receive("state_commit",{"id":sb.id,"epoch":sb.transaction_epoch})
	check(ma.cards.size()==count,"Duplicate commit ignored")

	check(ca.model.turn_number==2 and cb.model.turn_number==2 and ca.model.active_player=="opponent","Turn and active player restored")
	check(ca.model.players.local.loaded_ids.size()==10 and cb.model.players.local.loaded_ids.size()==10,"Duplicate source-card instance counts preserved")
	check(cb.card_by_id(saved_down_id).state.face_down and ca.card_by_id(saved_down_id).state.card_definition_id.is_empty(),"Face-down identity remains only on its owning client")
	check(card.state.active_face_index==1 and card.state.faces.size()==2,"Multi-face active face restored from loaded definition")
	check(ma.deck_backs.piles==saved_backs,"Saved deck back selection restored")
	check(JSON.parse_string(JSON.stringify(ma.appearance.background))==JSON.parse_string(JSON.stringify(saved_background)),"Saved background appearance restored")
	check(card.position.distance_to(Vector2(450,800))<0.1,"Battlefield position restored")
	var old_public: String=JSON.stringify(rb.state)
	nb.receive({"type":"game","protocol":1,"session_id":nb.session.session_id,"match_epoch":"f".repeat(32),"mode":"resync","sequence":999,"data":saved.public})
	check(JSON.stringify(rb.state)==old_public,"Stale pre-load epoch cannot overwrite restored public state")
	for changes: Array in [[true,false],[false,true],[true,true]]:
		if changes[0]: ma.battle.reset.start.sources[0].deck.cards[0].quantity+=1
		if changes[1]: mb.battle.reset.start.sources[0].deck.cards[0].quantity+=1
		sa.load_file(sa.last_path);await wait_for(func() -> bool: return sa.phase.is_empty())
		check(sa.status==Data.mismatch(not changes[0],not changes[1]),"Incompatible loaded decks blocked: "+str(changes))
		check(ca.pile.order==oa and cb.pile.order==ob,"Mismatch leaves both libraries untouched")
		if changes[0]: ma.battle.reset.start.sources[0].deck.cards[0].quantity-=1
		if changes[1]: mb.battle.reset.start.sources[0].deck.cards[0].quantity-=1
	var damaged: String=sa.storage.directory.path_join("online_state_bad.json")
	var ff:=FileAccess.open(damaged,FileAccess.WRITE);ff.store_string("{broken");ff.close()
	sa.load_file(damaged);check(sa.status.contains("Malformed"),"Corrupt JSON fails without replacing state")
	bad=saved.duplicate(true);bad.shared.fingerprints=[];check(not Data.validate(bad).is_empty(),"Malformed fingerprint container safely rejected")
	var malformed: Dictionary=saved.duplicate(true);malformed.shared=[]
	var malformed_row: Dictionary=sa.storage.save_record(malformed,"Invalid shared metadata")
	sa.refresh();check(sa.picker.item_count>0,"Save list tolerates malformed shared metadata");sa.storage.delete_record(malformed_row.path)
	bad=saved.duplicate(true);bad.shared.roles={"player_1":sb.identity(),"player_2":sa.identity()}
	var opposite: Dictionary=sa.storage.save_record(bad,"Opposite roles")
	sa.load_file(opposite.path)
	check(sa.phase.is_empty() and sa.status.contains("original Host/Guest roles"),"Opposite role identity rejected before transaction")
	check(ca.pile.order==oa and cb.pile.order==ob,"Role mismatch leaves both private libraries intact")
	bad=saved.duplicate(true);bad.private_capsule.mac="0".repeat(64)
	var corrupt: Dictionary=sa.storage.save_record(bad,"Bad capsule")
	sa.load_file(corrupt.path);await wait_for(func() -> bool: return sa.phase.is_empty())
	check(sa.status.contains("private save key") or sa.status.contains("damaged"),"Local paired record rejects corrupted authenticated capsule")
	check(ca.pile.order==oa and cb.pile.order==ob,"Capsule rejection leaves current state intact")
	check(not preload("res://scripts/battle/online_state_protocol.gd").valid("state_probe",{"id":"bad","epoch":""}),"Malformed transaction identifier rejected")
	check(not Capsule.valid({"iv":"a".repeat(32),"mac":"b".repeat(64),"cipher":"a".repeat(350000)}),"Oversized private envelope rejected")
	sb.storage.delete_record(guest_path)
	sa.load_file(host_path);await wait_for(func() -> bool: return sa.phase.is_empty())
	check(sa.status=="The other player does not have the matching save state.","Missing paired record blocks restoration")
	check(ca.pile.order==oa and cb.pile.order==ob,"Missing pair leaves current match unchanged")
	var repaired: Dictionary=sb.storage.save_record(guest_saved,"Restored test fixture");sb.last_path=repaired.path
	# Later session: reload the existing original decks, not pieces from the save.
	var deck_a: Dictionary=ma.battle.reset.start.sources[0].deck.duplicate(true)
	var deck_b: Dictionary=mb.battle.reset.start.sources[0].deck.duplicate(true)
	close_clients(pa,pb);await settle()
	ca.load_deck(deck_a,false);cb.load_deck(deck_b,false)
	await connect_clients(pa,pb,port)
	check(await wait_for(func() -> bool: return na.session.state=="connected" and nb.session.state=="connected"),"Reconnect in a new transport with original loaded decks")
	ra.card_sync.begin();rb.card_sync.begin();await wait_for(func() -> bool: return ra.card_sync.checked and rb.card_sync.checked)
	sa.load_file(sa.last_path)
	check(await wait_for(func() -> bool: return sb.phase=="load_offer"),"New session can request restore before Start Match")
	sb.accept();check(await wait_for(func() -> bool: return sa.phase.is_empty() and sb.phase.is_empty()),"New session restore finishes")
	check(ra.state==rb.state and ca.pile.order==oa and cb.pile.order==ob,"New transport restores public state and original saved private orders")
	check(not ca.model.players.local.deck_manifest.is_empty() and not cb.model.players.local.deck_manifest.is_empty(),"Loaded source manifests remain available for Card Sync/rematch")
	na.disconnect_session();await settle();a.queue_free();b.queue_free();await process_frame
	print("START/SAVE STATE: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
