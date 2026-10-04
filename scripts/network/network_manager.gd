extends Node
var room_session: Node
## TCP connection foundation. Intentionally has no reference to tabletop data.
signal battle_received(message: Dictionary)
var match_epoch: String = ""
var quiesced: bool = false
var reset_pending: bool = false
var remote_reset_pending: bool = false
var remote_battle: bool = false
var save_capable: bool = true
var relay_save_capable: bool = false
var remote_save_capable: bool = false
const SAVE_OFFER="53533303"
func peer_save_capable() -> bool:
	if room_session!=null and room_session.active:
		var caps: Variant=room_session.room.get("save_peers",{})
		return caps is Dictionary and caps.get("host",0)==3 and caps.get("guest",0)==3
	return remote_save_capable
signal recovery_received(message: Dictionary)
signal transfer_received(message: Dictionary)
signal hidden_received(message: Dictionary)
signal playtest_image_received(message: Dictionary)
signal table_received(message: Dictionary)
signal game_received(message: Dictionary)
signal card_sync_received(message: Dictionary)
signal changed
signal log_changed
signal message_sent(message: Dictionary)
const Codec = preload("res://scripts/network/network_codec.gd")
const Identity = preload("res://scripts/network/peer_identity.gd")
var session = preload("res://scripts/network/session_state.gd").new()
var debug_log: Array[String] = []
var last_address: String = "127.0.0.1"
var last_port: int = 27860
var remote_app_version: String = ""
var protocol_version: int = Codec.PROTOCOL
var server: TCPServer
var peer: RefCounted
var required_join_key: String = ""
var expected_session_id: String = ""
var incoming := PackedByteArray()
var outgoing := PackedByteArray()
var phase: String = ""
var elapsed: float = 0.0
var idle: float = 0.0
var heartbeat: float = 0.0
var closing: bool = false
var close_state: String = "disconnected"
var close_status: String = "Disconnected."
func log_event(text: String) -> void:
	debug_log.append(Time.get_time_string_from_system() + " | " + text)
	if debug_log.size() > 200:
		debug_log.pop_front()
	log_changed.emit()
func state(value: String, text: String) -> void:
	session.state = value
	if value == "connected":
		preload("res://scripts/frontend/player_preferences.gd").new().save_name(session.local_peer.display_name)
	session.status = text
	changed.emit()
func available() -> bool:
	return session.state in ["disconnected", "error"] and not closing
func valid_start(port: int, caption: String) -> bool:
	if not available():
		return false
	if port < 1024 or port > 65535 or not Codec.safe_text(caption.strip_edges(), 48):
		state("error", "Enter a name (1-48 characters) and a port from 1024 to 65535.")
		log_event("Connection error: invalid connection settings.")
		return false
	return true
func host_game(port: int = 27860, caption: String = "Host", bind_address: String = "*") -> bool:
	if not valid_start(port, caption):
		return false
	cleanup()
	last_port = port
	server = TCPServer.new()
	var error: Error = server.listen(port, bind_address)
	if error != OK:
		fail("Could not host on this port. It may already be in use.")
		return false
	session.local_peer = Identity.new("player_1", "host", caption.strip_edges())
	session.session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	state("hosting", "Hosting on port %d. Waiting for Player 2." % port)
	log_event("Hosting started on port %d." % port)
	return true
func join_game(address: String, port: int = 27860, caption: String = "Guest") -> bool:
	if not valid_start(port, caption):
		return false
	# Literal addresses avoid blocking DNS resolution on the UI thread.
	var target: String = address.strip_edges()
	if target == "localhost":
		target = "127.0.0.1"
	if not target.is_valid_ip_address():
		fail("Enter an IP address, or localhost for this PC.")
		return false
	cleanup()
	last_address = target
	last_port = port
	session.local_peer = Identity.new("player_2", "guest", caption.strip_edges())
	peer = StreamPeerTCP.new()
	phase = "welcome"
	state("connecting", "Connecting; waiting for the host handshake.")
	log_event("Join attempted on port %d." % port)
	if peer.connect_to_host(target, port) != OK:
		fail("Connection could not start. Check the address and port.")
		return false
	return true
func identity_message(kind: String) -> Dictionary:
	var message: Dictionary = {"type": kind, "protocol": protocol_version, "app_version": Codec.APP_VERSION,
		"player_id": session.local_peer.player_id, "role": session.local_peer.role,
		"display_name": session.local_peer.display_name, "session_id": session.session_id,"battle_version":1,"reset_pending":reset_pending}
	if kind == "hello" and not required_join_key.is_empty():
		message["join_key"] = required_join_key
	elif kind=="hello" and save_capable:
		# Legacy hosts allow but ignore optional join_key on unkeyed LAN sessions.
		message["join_key"]=SAVE_OFFER+Crypto.new().generate_random_bytes(12).hex_encode()
	return message
func epoch_message(message: Dictionary) -> bool:
	return message.get("type") in Codec.EPOCH_TYPES or (message.get("type")=="recovery" and message.get("kind") not in ["hello","challenge","proof"])
func send_message(message: Dictionary) -> bool:
	if epoch_message(message):
		if quiesced: return false
		message=message.duplicate(true)
		if not match_epoch.is_empty(): message["match_epoch"]=match_epoch
	var bytes: PackedByteArray = Codec.encode(message)
	if peer == null or bytes.is_empty() or outgoing.size() + bytes.size() > 1048576:
		return false
	outgoing.append_array(bytes)
	message_sent.emit(message.duplicate(true))
	return true
func control(kind: String) -> void:
	send_message({"type": kind, "protocol": protocol_version})
func _process(delta: float) -> void:
	if server != null and server.is_connection_available():
		var candidate: StreamPeerTCP = server.take_connection()
		if peer != null:
			candidate.disconnect_from_host()
			log_event("Extra peer refused: this session supports two clients.")
		else:
			peer = candidate
			peer.set_no_delay(true)
			phase = "hello"
			elapsed = 0
			log_event("Peer connected; checking handshake.")
			state("connecting", "Player 2 connected; checking protocol and identity.")
			send_message(identity_message("welcome"))
	if peer == null:
		return
	peer.poll()
	elapsed += delta
	if closing:
		flush_output()
		if elapsed > 0.25 or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			var final_state: String = close_state
			var final_status: String = close_status
			cleanup()
			state(final_state, final_status)
		return
	if peer.get_status() in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
		if session.state == "connected":
			remote_left()
		else:
			fail("Connection closed before the handshake completed. Check the host and port.")
		return
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if elapsed > 10:
			fail("Connection timed out. Check the host address, port and LAN firewall settings.")
		return
	flush_output()
	if peer == null:
		return
	read_input()
	if peer == null or closing:
		return
	if session.state != "connected":
		if elapsed > 10:
			fail("Handshake timed out. The other client did not complete the connection.")
	else:
		idle += delta
		heartbeat += delta
		if heartbeat > 3:
			heartbeat = 0
			control("ping")
		if idle > 15:
			fail("Connection lost: the other client stopped responding.")
func flush_output() -> void:
	if peer == null or outgoing.is_empty() or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var result: Array = peer.put_partial_data(outgoing)
	if result[0] != OK:
		if not closing:
			fail("Connection error while sending session information.")
		return
	outgoing = outgoing.slice(int(result[1]))
func read_input() -> void:
	var count: int = mini(peer.get_available_bytes(), 65536)
	if count > 0:
		var result: Array = peer.get_partial_data(count)
		if result[0] != OK:
			fail("Connection error while reading session information.")
			return
		incoming.append_array(result[1])
	for _i: int in 32:
		var end: int = incoming.find(10)
		if end < 0:
			break
		var packet: PackedByteArray = incoming.slice(0, end)
		incoming = incoming.slice(end + 1)
		var message: Dictionary = Codec.decode(packet)
		if message.is_empty():
			reject(false)
			return
		idle = 0
		receive(message)
		if peer == null or closing:
			return
	if incoming.size() > Codec.MAX_FRAME:
		reject(false)
func receive(message: Dictionary) -> void:
	if message.type == "reject":
		fail("Protocol mismatch: use compatible CardLink clients (local protocol %d)." % protocol_version if message.reason == "protocol_mismatch" else "The other client rejected an invalid handshake.")
		return
	if int(message.protocol) != protocol_version:
		reject(true)
		return
	if message.type == "bye":
		remote_left()
		return
	if session.state == "connected":
		if epoch_message(message) and (quiesced or message.get("match_epoch","")!=match_epoch): return
		if message.type == "battle":
			if remote_battle and message.session_id==session.session_id: battle_received.emit(message)
			return
		if message.type == "recovery":
			recovery_received.emit(message)
			return
		if message.type == "transfer_tx":
			transfer_received.emit(message)
			return
		if message.type == "hidden_zone":
			hidden_received.emit(message)
			return
		if message.type == "playtest_image":
			playtest_image_received.emit(message)
			return
		if message.type == "table_structure":
			table_received.emit(message)
			return
		if message.type == "card_sync":
			card_sync_received.emit(message)
			return
		if message.type == "game":
			game_received.emit(message)
			return
		if message.type == "ping":
			control("pong")
		elif message.type != "pong":
			reject(false)
		return
	if message.type != phase:
		reject(false)
		return
	if phase == "welcome":
		if not expected_session_id.is_empty() and message.session_id != expected_session_id:
			reject(false)
			return
		session.session_id = message.session_id
		remote_app_version = message.app_version
		remote_battle = message.get("battle_version",0)==1
		remote_reset_pending = message.get("reset_pending",false)
		session.remote_peer = Identity.new(message.player_id, message.role, message.display_name)
		log_event("Peer connected; host identity received.")
		send_message(identity_message("hello"))
		phase = "ready"
	elif phase == "hello":
		if not required_join_key.is_empty() and message.get("join_key") != required_join_key:
			reject(false)
			return
		if message.session_id != session.session_id:
			reject(false)
			return
		remote_app_version = message.app_version
		remote_battle = message.get("battle_version",0)==1
		remote_reset_pending = message.get("reset_pending",false)
		session.remote_peer = Identity.new(message.player_id, message.role, message.display_name)
		remote_save_capable=save_capable and required_join_key.is_empty() and str(message.get("join_key","")).begins_with(SAVE_OFFER)
		var ready: Dictionary={"type":"ready","protocol":protocol_version,"session_id":session.session_id}
		if remote_save_capable: ready["save_state_version"]=3
		send_message(ready)
		complete()
	elif phase == "ready":
		remote_save_capable=message.get("save_state_version",0)==3
		if message.session_id != session.session_id:
			reject(false)
			return
		complete()
func complete() -> void:
	phase = ""
	idle = 0
	heartbeat = 0
	state("connected", "Connected. Session metadata only; gameplay stays local.")
	log_event("Handshake completed: Player 1 (host) and Player 2 (guest).")
func reject(mismatch: bool) -> void:
	send_message({"type": "reject", "protocol": protocol_version, "reason": "protocol_mismatch" if mismatch else "invalid_message"})
	log_event("Protocol mismatch." if mismatch else "Invalid session message rejected.")
	begin_close("error", "Protocol mismatch. Both clients must use networking protocol %d." % protocol_version if mismatch else "Invalid session message. Connection closed safely.")
func disconnect_session() -> void:
	if peer != null:
		control("bye")
		begin_close("disconnected", "Disconnected. Local play is available.")
	else:
		state("disconnecting", "Disconnecting...")
		cleanup()
		state("disconnected", "Disconnected. Local play is available.")
	log_event("Local disconnect requested.")
func begin_close(final_state: String, text: String) -> void:
	closing = true
	close_state = final_state
	close_status = text
	elapsed = 0
	state("disconnecting", text)
func remote_left() -> void:
	log_event("Peer disconnected.")
	cleanup()
	state("disconnected", "The other player disconnected. Host or join to reconnect.")
func fail(text: String) -> void:
	log_event("Connection error: " + text)
	cleanup()
	state("error", text)
func adopt_stream(stream: RefCounted, role: String, caption: String, id: String, key: String) -> void:
	cleanup()
	peer = stream
	required_join_key = key
	expected_session_id = id
	session.session_id = id
	session.local_peer = Identity.new("player_1" if role == "host" else "player_2", role, caption)
	phase = "hello" if role == "host" else "welcome"
	state("connecting", "Relay paired; checking peer handshake.")
	if role == "host":
		send_message(identity_message("welcome"))
func cleanup() -> void:
	relay_save_capable=false
	remote_save_capable=false
	remote_battle=false
	remote_reset_pending=false
	remote_app_version = ""
	required_join_key = ""
	expected_session_id = ""
	if peer != null:
		peer.disconnect_from_host()
	peer = null
	if server != null:
		server.stop()
	server = null
	incoming.clear()
	outgoing.clear()
	phase = ""
	elapsed = 0
	idle = 0
	heartbeat = 0
	closing = false
	session.reset()
func _exit_tree() -> void:
	cleanup()
