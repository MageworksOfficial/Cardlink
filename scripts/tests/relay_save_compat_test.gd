extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args();var base: String=args[0]
	var a: Control=await create_client(base.path_join("a"),"A",Color.RED)
	var b: Control=await create_client(base.path_join("b"),"B",Color.BLUE)
	var pa: Node=a.get_node("Network");var pb: Node=b.get_node("Network")
	var old_relay: bool=args[2]!="3"
	if not old_relay: pb.network.save_capable=false
	for panel: Node in [pa,pb]:
		panel.rooms.signaling.service_url=args[1];panel.rooms.config.set_value("internet","direct_attempt_seconds",0.2)
	await pa.rooms.host_room("Host")
	if pa.network.server!=null: pa.network.server.stop();pa.network.server=null
	await pb.rooms.join_room(pa.rooms.code,"Guest")
	check(await wait_for(func() -> bool: return pa.network.session.state=="connected" and pb.network.session.state=="connected",20),"Legacy combination connects normally")
	pa.gameplay.start();pb.gameplay.start()
	await wait_for(func() -> bool: return pa.gameplay.card_sync.checked and pb.gameplay.card_sync.checked)
	pa.gameplay.card_sync.decide("placeholders");pb.gameplay.card_sync.decide("placeholders")
	check(await wait_for(func() -> bool: return pa.gameplay.enabled and pb.gameplay.enabled),"Legacy combination starts normal gameplay")
	wire.clear();var saves: Node=a.tabletop.battle.saves
	saves.save("Should be blocked")
	check(saves.phase.is_empty() and saves.last_path.is_empty(),"Unsupported save stopped before transaction")
	check(saves.status.contains("updated CardLink server") if old_relay else saves.status.contains("Both players must"),"Clear compatibility message")
	check(wire.filter(func(v: Dictionary) -> bool: return str(v.get("kind","")).begins_with("state_")).is_empty(),"No unknown save frames sent")
	a.tabletop.match_controller.draw_card();await settle()
	check(a.tabletop.match_controller.model.players.local.hand.size()==1 and b.tabletop.match_controller.hidden_count("opponent","hand")==1,"Normal draw/private hand count still synchronizes")
	check(pa.network.session.state=="connected" and pb.network.session.state=="connected","Compatibility rejection does not disconnect")
	pa.rooms.cancel();pb.rooms.cancel();a.queue_free();b.queue_free();await process_frame
	print("RELAY COMPAT: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
