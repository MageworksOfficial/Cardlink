extends "res://scripts/tests/start_save_state_test.gd"
var previous_code: String=""
func connect_clients(pa: Node,pb: Node,_port: int) -> void:
	var endpoint: String=OS.get_cmdline_user_args()[1]
	for panel: Node in [pa,pb]:
		panel.rooms.signaling.service_url=endpoint
		panel.rooms.config.set_value("internet","direct_attempt_seconds",0.1)
	await pa.rooms.host_room("Host")
	check(not pa.rooms.code.is_empty(),"Room code created: "+pa.rooms.status)
	if pa.rooms.code.is_empty(): print(pa.network.debug_log);quit(1);return
	check(previous_code.is_empty() or previous_code!=pa.rooms.code,"Fresh room code independent of saved transport")
	previous_code=pa.rooms.code
	if pa.network.server!=null: pa.network.server.stop();pa.network.server=null
	await pb.rooms.join_room(pa.rooms.code,"Guest")
	check(await wait_for(func() -> bool: return pa.network.session.state=="connected" and pb.network.session.state=="connected",20),"Both connect through room-code relay")
	check(pa.rooms.method=="Relay" and pb.rooms.method=="Relay","Forced real relay transport on both clients")
	check(pa.network.relay_save_capable and pb.network.relay_save_capable and pa.network.peer_save_capable(),"Relay and both peers advertise save capability")
func close_clients(pa: Node,pb: Node) -> void:
	pa.rooms.cancel();pb.rooms.cancel()
	pa.gameplay.recovery.leave();pb.gameplay.recovery.leave()
