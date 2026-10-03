extends "res://scripts/tests/milestone_6b_test.gd"
func agree(a: Node,b: Node,ids: Array) -> bool:
	for id: String in ids:
		if a.state.cards.has(id):
			if not b.state.cards.has(id): return false
			var ac: Control=a.table.match_controller.card_by_id(id);var bc: Control=b.table.match_controller.card_by_id(id)
			if ac==null or bc==null: return false
			var ap: Array=a.serializer.encode_position(ac.position);var bp: Array=b.serializer.encode_position(bc.position)
			if absf(ap[0]-bp[0])>0.00002 or absf(ap[1]-bp[1])>0.00002: return false
		else:
			var ac: Control=a.table.extras.counter_by_id(id);var bc: Control=b.table.extras.counter_by_id(id)
			if ac==null or bc==null: return false
			var ap: Array=a.serializer.encode_position(ac.position,44);var bp: Array=b.serializer.encode_position(bc.position,44)
			if absf(ap[0]-bp[0])>0.00002 or absf(ap[1]-bp[1])>0.00002: return false
	return true
func run() -> void:
	var base: String=OS.get_cmdline_user_args()[0]
	root.size=Vector2i(1152,760);root.gui_embed_subwindows=true
	var a: Control=await create_client(base.path_join("a"),"ARRANGE_PRIVATE_A",Color.CORAL)
	var b: Control=await create_client(base.path_join("b"),"ARRANGE_PRIVATE_B",Color.SKY_BLUE)
	var na: Node=a.get_node("Network").network;var nb: Node=b.get_node("Network").network
	var ra: Node=a.get_node("Network").gameplay;var rb: Node=b.get_node("Network").gameplay
	var ma: Node=a.tabletop;var mb: Node=b.tabletop;var ca: Node=ma.match_controller;var cb: Node=mb.match_controller
	var port: int=randi_range(33000,43000)
	check(na.host_game(port,"Arrange Host","127.0.0.1") and nb.join_game("127.0.0.1",port,"Arrange Guest"),"Two local clients start connection")
	check(await wait_for(func() -> bool: return na.session.state=="connected" and nb.session.state=="connected"),"Handshake completed")
	ra.start_public();rb.start_public();check(await wait_for(func() -> bool: return ra.enabled and rb.enabled),"Public match ready")
	var ids: Array[String]=[]
	var hidden: Control=ca.card_by_id(ca.pile.order[0]);hidden.set_face_down(true);ca.move_card(hidden,"battlefield",true,"local",true,true)
	# Set face down after placement too; no yields before public capture.
	hidden.set_face_down(true);ids.append(hidden.state.match_instance_id)
	for i: int in 23:
		var token: Control=ma.create_token("Arrange token "+str(i),"local","local","","2","2").card
		token.position=Vector2(300+i*4,500+i*2);token.state.position=token.position;ids.append(token.state.match_instance_id)
	var counter: Control=ma.extras.create_counter(Vector2(600,500),3,"Public");ids.append(counter.instance_id)
	await settle();await settle()
	check(agree(ra,rb,ids),"25 mixed public objects exist on both clients")
	var hidden_remote: Control=cb.card_by_id(hidden.state.match_instance_id)
	check(hidden_remote!=null and hidden_remote.state.face_down and hidden_remote.state.card_definition_id.is_empty(),"Hidden public object has no remote identity")
	for custom: bool in [false,true]:
		if custom:
			ma.custom_table.enabled=true;mb.custom_table.enabled=true
		for mode: int in [0,1,2,5]:
			ma.selection.ids.assign(ids);wire.clear();ma.selection.arrange.apply(mode)
			await settle();await settle()
			check(agree(ra,rb,ids),"Host arrangement converges: %s / custom=%s" % [ma.selection.arrange.Layout.MODES[mode],custom])
			check(ma.selection.ids.size()==25 and hidden.state.face_down and hidden_remote.state.face_down,"Online selection and face-down state preserved")
			var safe: bool=true
			for frame: Dictionary in wire:
				if frame.get("type")=="game" and frame.get("mode") in ["request","commit"]:
					for op: Dictionary in frame.data.payload:
						if op.kind=="card_update":
							for field: String in op.data: safe=safe and field in ["id","position"]
						safe=safe and not op.kind in ["card_create","card_remove"]
			check(safe and not JSON.stringify(wire).contains("ARRANGE_PRIVATE"),"Movement uses existing public positions only, without private identities")
			check(ra.log.all(func(line: String) -> bool: return not line.contains("refused")) and rb.log.all(func(line: String) -> bool: return not line.contains("refused")),"Existing validators accept move batches")
	mb.selection.ids.assign(ids);mb.selection.arrange.apply(3);await settle();await settle()
	check(agree(ra,rb,ids),"Guest can arrange host-owned objects using normal shared control")
	check(ra.state.order==rb.state.order,"Public z-order remains identical")
	var private_id: String=ca.pile.order[0]
	check(cb.card_by_id(private_id)==null and not JSON.stringify(wire).contains(private_id),"Remaining private library IDs never exposed")
	check(not ma.undo.available() and not mb.undo.available(),"Online snapshot Undo stays disabled")
	ma.selection.ids.assign(ids)
	var before: Vector2=hidden.position
	na.quiesced=true;ma.selection.arrange.apply(0)
	check(hidden.position==before,"Quiesced connection blocks arrangement atomically")
	na.quiesced=false
	ma.selection.ids.clear()
	for i: int in 201: ma.selection.ids.append("dummy_"+str(i))
	check(ma.selection.arrange.reason().contains("200"),"Online batch cap is explicit and bounded")
	ma.selection.ids.assign(ids)
	hidden.scale=Vector2(500,1);before=hidden.position
	ma.selection.arrange.apply(2)
	check(hidden.position==before and ma.controls.status.text.contains("online table limits"),"Out-of-wire-bounds formation rejected before any movement")
	hidden.scale=Vector2.ONE
	na.disconnect_session();await settle();a.queue_free();b.queue_free();await process_frame
	print("ARRANGE NETWORK: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
