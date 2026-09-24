extends "res://scripts/tests/milestone_6b_test.gd"
const Catalog = preload("res://scripts/network/card_sync_catalog.gd")
var inject_interruption: int = 0
var duplicate_chunk_sent: bool = false
const Wire = preload("res://scripts/network/card_sync_protocol.gd")
func hash_bytes(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var a: Control = await create_client(base.path_join("a"),"Host Custom",Color.CORNFLOWER_BLUE)
	var b: Control = await create_client(base.path_join("b"),"Guest Custom",Color.CORAL,true)
	var ca: Node = a.tabletop.match_controller
	var cb: Node = b.tabletop.match_controller
	var ra: Node = a.get_node("Network").gameplay
	var rb: Node = b.get_node("Network").gameplay
	var sa: Node = ra.card_sync
	var sb: Node = rb.card_sync
	var na: Node = ra.network
	var nb: Node = rb.network
	ca.library_actions.draw_n("local",3)
	cb.library_actions.draw_n("local",3)
	var hand_before: Array = ca.model.players.local.hand.duplicate()
	var library_before: Array = ca.pile.order.duplicate()
	var port: int = randi_range(33000,43000)
	na.host_game(port,"Host","127.0.0.1")
	nb.join_game("127.0.0.1",port,"Guest")
	check(await wait_for(func() -> bool: return na.session.state == "connected" and nb.session.state == "connected"),"Connect two isolated card libraries")
	ra.start()
	rb.start()
	check(await wait_for(func() -> bool: return sa.checked and sb.checked),"Both deck manifests checked before sharing")
	check(not ra.enabled and not rb.enabled and sa.status.contains("WARNING") and sb.status.contains("WARNING"),"Missing cards warn and block silent match start")
	nb.message_sent.connect(func(frame: Dictionary) -> void:
		if frame.type == "card_sync" and frame.kind == "chunk":
			if inject_interruption == 0:
				inject_interruption = 1
				sa.fail("Test interruption before image completion.")
			elif inject_interruption == 1:
				inject_interruption = 2
				nb.disconnect_session()
			elif not duplicate_chunk_sent:
				duplicate_chunk_sent = true
				nb.send_message(frame))
	sa.decide("sync")
	sb.decide("sync")
	check(await wait_for(func() -> bool: return sa.status.begins_with("CARD SYNC INCOMPLETE") and sb.status.begins_with("CARD SYNC INCOMPLETE")),"Interrupted transfer reports incomplete on both clients")
	check(sa.catalog.records.size() == 1 and sa.incoming.is_empty() and sa.catalog.has_image(sa.own[0].hash),"No partial definition is committed; verified existing assets survive")
	sa.decide("sync")
	sb.decide("sync")
	check(await wait_for(func() -> bool: return na.session.state == "disconnected" and nb.session.state == "disconnected"),"Actual disconnect safely stops an in-progress transfer")
	check(sa.status.contains("Connection was lost") and sb.status.contains("Connection was lost"),"Both clients show Card Sync interrupted on connection loss")
	na.host_game(port,"Host","127.0.0.1")
	nb.join_game("127.0.0.1",port,"Guest")
	await wait_for(func() -> bool: return na.session.state == "connected" and nb.session.state == "connected")
	ra.start()
	rb.start()
	await wait_for(func() -> bool: return sa.checked and sb.checked)
	sa.decide("sync")
	sb.decide("sync")
	check(await wait_for(func() -> bool: return sa.status.begins_with("CARD SYNC COMPLETE") and sb.status.begins_with("CARD SYNC COMPLETE"),15),"Two-step Guest-to-Host then Host-to-Guest completes")
	if sa.running or not sa.status.begins_with("CARD SYNC COMPLETE"):
		for f: Dictionary in wire:
			if f.type == "card_sync" and preload("res://scripts/network/network_codec.gd").decode(JSON.stringify(f).to_utf8_buffer()).is_empty(): print("BAD ROUNDTRIP ",f.kind)
		print("HOST ",sa.status," GUEST ",sb.status," NETWORK ",na.debug_log,nb.debug_log)
		quit(1)
		return
	check(duplicate_chunk_sent and sa.reports["1"].images == 1 and sa.reports["2"].images == 1,"Both directions transfer only their missing image")
	check(sa.catalog.records.size() == 2 and sb.catalog.records.size() == 2,"Received definitions join normal Card Library")
	var last_step: int = 0
	var ordered: bool = true
	var private_safe: bool = true
	for frame: Dictionary in wire:
		if frame.type != "card_sync": continue
		var text: String = JSON.stringify(frame)
		for id: String in hand_before + library_before:
			if text.contains(id): private_safe = false
		if frame.kind in ["definition","image_begin","chunk"]:
			ordered = ordered and int(frame.data.step) >= last_step
			last_step = int(frame.data.step)
	check(ordered and last_step == 2,"Step 2 starts only after Step 1; no simultaneous directions")
	check(private_safe and ca.pile.order == library_before and ca.model.players.local.hand == hand_before,"Manifest/asset exchange contains no live hand IDs, drawn copies or library order")
	var packets_before: int = wire.size()
	sa.decide("sync")
	sb.decide("sync")
	await settle()
	check(await wait_for(func() -> bool: return not sa.running and not sb.running),"Repeated sync completes")
	var repeated: Array = wire.slice(packets_before).filter(func(f: Dictionary) -> bool: return f.type == "card_sync" and f.kind in ["image_begin","chunk","definition"])
	check(repeated.is_empty() and sa.catalog.records.size() == 2 and sb.catalog.records.size() == 2,"All cards already present: no transfer or collection growth")
	var received_id: String = sb.own[0].id
	DirAccess.remove_absolute(sa.catalog.directory.path_join("definitions").path_join(received_id+".json"))
	sa.catalog.reload()
	sa.decide("sync")
	sb.decide("sync")
	await settle()
	check(await wait_for(func() -> bool: return not sa.running and not sb.running) and sa.reports["1"].definitions == 1 and sa.reports["1"].images == 0,"Metadata-only transfer across the real connection")
	DirAccess.remove_absolute(sa.catalog.asset_path(sb.own[0].hash))
	sa.decide("sync")
	sb.decide("sync")
	await settle()
	check(await wait_for(func() -> bool: return not sa.running and not sb.running) and sa.reports["1"].definitions == 0 and sa.reports["1"].images == 1,"Image-only transfer across the real connection")
	check(ca.loader.load_records().size() == 2,"Received cards are discoverable by the existing library loader")
	DirAccess.remove_absolute(sa.catalog.asset_path(sa.own[0].hash))
	sa.decide("sync")
	sb.decide("sync")
	await settle()
	check(await wait_for(func() -> bool: return not sa.running and not sb.running) and sa.catalog.has_image(sa.own[0].hash),"Combined deck check repairs a missing own-deck image from the peer's collection")
	sa.decide("start")
	sb.decide("start")
	check(await wait_for(func() -> bool: return ra.enabled and rb.enabled),"Start Match after completed card check")
	if not ra.enabled or not rb.enabled:
		print("START HOST ",sa.status," GUEST ",sb.status," ROUTERS ",ra.log,rb.log," NETWORK ",na.debug_log,nb.debug_log)
		print("STATE ",ra.state)
		quit(1)
		return
	await settle()
	var card: Control = ca.card_by_id(ca.model.players.local.hand[0])
	ca.toggle_hand_reveal(card)
	await settle()
	check(cb.opponent_hand.public_textures.size() == 3 and cb.opponent_hand.public_textures[0] != null,"Explicitly revealed hand slot has real remote art")
	check(cb.opponent_hand.public_textures[1] == null and cb.opponent_hand.public_textures[2] == null,"Neighboring hand slots remain backs")
	check(cb.opponent_hand.cards_row.get_child(0).get_child_count() == 1,"Remote known slot has eye badge")
	ca.toggle_hand_reveal(card)
	await settle()
	check(cb.opponent_hand.public_textures[0] == null and cb.opponent_hand.cards_row.get_child(0).get_child_count() == 0,"Hide removes only the revealed face/badge")
	ca.pile_view.position += Vector2(200,100)
	await settle()
	check(cb.opponent_pile.position.distance_to(rb.serializer.decode_position(ra.state.zones["player_1:library"].position,140)) < 0.1,"Library pile move maps to opponent world position")
	ca.move_card(card,"battlefield")
	await settle()
	var id: String = card.state.match_instance_id
	check(cb.card_by_id(id).card_image.texture != null,"Synced asset replaces prior missing-image fallback")
	for kind: String in ["graveyard","exile","commander"]:
		var zone: Control = ca.zone_for(kind,"local")
		zone.move_to(zone.position + Vector2(90,20))
		await settle()
		var remote_zone: Control = cb.zone_for(kind,"opponent")
		check(remote_zone.position.distance_to(rb.serializer.decode_position(ra.state.zones["player_1:"+kind].position,zone.size.y)) < 0.1,kind+" zone position synchronizes")
		ca.move_card(card,kind)
		await settle()
		var remote_card: Control = cb.card_by_id(id)
		check(Rect2(remote_zone.position,remote_zone.size).has_point(remote_card.position + remote_card.size/2) and remote_card.state.zone_id == remote_zone.zone_id,kind+" transition lands inside the correct remote zone")
		check(remote_card.rotation == 0 and remote_card.card_image.rotation == 0,"Public-zone art stays upright: "+kind)
	var custom: Control = a.tabletop.add_zone({"zone_type":"custom","display_name":"Public Reserve","position":Vector2(800,700)})
	await settle()
	check(rb.serializer.projection.find_zone(custom.zone_id) != null,"Custom public gameplay zone is shared")
	a.tabletop.assign_zone(card,custom)
	await settle()
	check(cb.card_by_id(id).state.zone_id == custom.zone_id,"Public custom-zone membership uses the same shared ID")
	ca.move_card(card,"hand")
	ca.toggle_hand_reveal(card)
	await settle()
	ca.move_card(card,"battlefield")
	await settle()
	cb.move_card(cb.card_by_id(id),"hand",true,"opponent")
	await settle()
	check(cb.opponent_hand.public_textures.any(func(face: Variant) -> bool: return face != null),"Revealed status survives a remote return to the owner's hand")
	var stable_sequence: int = ra.committed
	await settle()
	check(ra.committed == stable_sequence,"Known hand state settles without a repeat-action loop")
	await catalog_checks(base,ca)
	na.disconnect_session()
	await settle()
	a.queue_free()
	b.queue_free()
	await process_frame
	print("PATCH 6B.1: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
func catalog_checks(base: String, c: Node) -> void:
	var row: Dictionary = c.model.players.local.deck_manifest[0]
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(c.loader.storage.directory.path_join(row.hash+".png"))
	var cat = Catalog.new(base.path_join("catalog"))
	check(cat.store_image(row.hash,bytes).is_empty(),"Receiver validates and atomically stores normalized PNG")
	var first: Dictionary = cat.check([row])
	check(first.images.is_empty() and first.definitions == [row.id],"Image already present: only metadata requested")
	check(cat.store_definition(row).is_empty(),"Missing metadata written only after verified image exists")
	var definition_path: String = cat.directory.path_join("definitions").path_join(row.id+".json")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(definition_path))
	check(saved.received_from_peer and saved.width == 750 and saved.height == 1050,"Received card uses standard metadata with internal peer tag")
	DirAccess.remove_absolute(cat.asset_path(row.hash))
	var missing: Dictionary = cat.check([row])
	check(missing.definitions.is_empty() and missing.images == [row.hash],"Definition exists, image missing: request image only")
	check(cat.store_image(row.hash,bytes).is_empty() and cat.check([row]).missing == 0,"Image-only repair restores definition availability")
	var alias: Dictionary = row.duplicate(true)
	alias.id = "different_valid_id"
	check(cat.store_definition(alias).is_empty() and cat.records.size() == 1,"Equivalent name/hash reuses definition despite differing peer ID")
	var conflict: Dictionary = row.duplicate(true)
	conflict.name = "Different card using same ID"
	check(cat.store_definition(conflict).is_empty() and cat.records.size() == 2 and cat.records[0].name == row.name,"Conflicting ID/name gets safe separate definition; original preserved")
	check(not cat.store_image("a".repeat(64),bytes).is_empty(),"Hash mismatch rejected")
	var damaged: PackedByteArray = bytes.slice(0,32)
	check(not cat.store_image(hash_bytes(damaged),damaged).is_empty(),"Corrupt PNG rejected despite matching hash")
	var traversal: Dictionary = row.duplicate(true)
	traversal.id = "../escape"
	check(not Wire.definition(traversal),"Remote path traversal metadata rejected")
	var extra: Dictionary = row.duplicate(true)
	extra.image_path = "C:/arbitrary"
	check(not Wire.definition(extra),"Remote filesystem paths not accepted")
	check(not Wire.valid({"type":"card_sync","protocol":1,"session_id":"a","run":"a","kind":"image_begin","data":{"step":1,"hash":row.hash,"bytes":Wire.MAX_IMAGE+1}}),"Oversized image rejected before allocation")
