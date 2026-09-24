extends Node
signal changed
const Codec = preload("res://scripts/network/network_codec.gd")
const Diagnostics = preload("res://scripts/network/connection_diagnostics.gd")
var network: Node
var signaling: Node
var relay_connector: Node
var diagnostics = Diagnostics.new()
var config := ConfigFile.new()
var active: bool = false
var busy: bool = false
var generation: int = 0
var code: String = ""
var token: String = ""
var join_key: String = ""
var session_id: String = ""
var role: String = ""
var caption: String = ""
var status: String = "Host a room or enter your friend's room code."
var method: String = "None"
var room: Dictionary = {}
var clock: float = 0
var polling: bool = false
var relaying: bool = false
var was_connected: bool = false
var recovering: bool = false
var resuming: bool = false
var last_intent: String = "host"
var last_code: String = ""
func _ready() -> void:
	config.load("res://config/network.cfg")
	network.room_session = self
	signaling = preload("res://scripts/network/signaling_client.gd").new()
	signaling.service_url = str(config.get_value("internet", "service_url", ""))
	signaling.timeout_seconds = clampf(float(config.get_value("internet","connection_timeout",8.0)),2.0,30.0)
	add_child(signaling)
	relay_connector = preload("res://scripts/network/relay_connector.gd").new()
	relay_connector.timeout_seconds = clampf(float(config.get_value("internet","connection_timeout",15.0)),5.0,30.0)
	add_child(relay_connector)
func update(text: String) -> void:
	status = text
	changed.emit()
func valid_room(data: Dictionary) -> bool:
	for key: String in ["code", "session_id", "app_version", "state", "mode"]:
		if not data.get(key) is String or str(data[key]).length() > 48:
			return false
	if not valid_code(data.code) or data.session_id.length() != 32 or not data.session_id.is_valid_hex_number(false):
		return false
	if not data.get("addresses") is Array or data.addresses.size() > 8:
		return false
	for address: Variant in data.addresses:
		if not address is String or not address.is_valid_ip_address():
			return false
	for key: String in ["protocol", "port", "relay_port"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or value != floor(value) or value < 0 or value > 65535:
			return false
	return data.port >= 1024 and data.get("relay_tls") is bool and data.get("guest_joined") is bool and data.state in ["waiting", "connecting", "full"] and data.mode in ["direct", "relay"]
static func valid_code(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Z]{4}-[0-9]{4}$")
	return regex.search(value) != null
func preflight(name_text: String) -> bool:
	if active or busy or not network.available():
		return false
	if not Codec.safe_text(name_text.strip_edges(), 48):
		update("Enter a display name of 1–48 characters.")
		return false
	busy = true
	generation += 1
	var run: int = generation
	diagnostics = Diagnostics.new()
	update("Checking connection conditions…")
	var health: Dictionary = await signaling.call_service("health", {})
	if run != generation:
		return false
	if health.has("error"):
		fail(str(health.error))
		return false
	if health.get("service") != "cardlink-rendezvous" or health.get("api") != 1 or not health.get("relay_available") is bool:
		fail("invalid_response")
		return false
	diagnostics.internet = "Local test only" if signaling.service_url.begins_with("http://") else "✓ Service reachable"
	diagnostics.service = "✓ Available"
	diagnostics.room_service = "✓ Compatible endpoint"
	diagnostics.relay = "Available · not tested yet" if health.relay_available else "Unavailable"
	if health.get("protocol", network.protocol_version) != network.protocol_version:
		incompatible(health)
		return false
	if health.get("gameplay_relay") != true:
		fail("invalid_response")
		return false
	var probe_port: Variant = health.get("relay_port")
	var probe_host: Variant = health.get("relay_host", "")
	if not (probe_port is int or probe_port is float) or probe_port < 1024 or probe_port > 65535 or not probe_host is String or probe_host.length() > 253 or not health.get("relay_tls") is bool:
		fail("relay_unavailable")
		return false
	var probe_url: String = signaling.service_url if probe_host.is_empty() else ("https://" if health.relay_tls else "http://") + probe_host
	var relay_health: Dictionary = await relay_connector.connect_relay(probe_url,int(probe_port),health.relay_tls,"","",true)
	if run != generation: return false
	if relay_health.has("error"):
		fail("relay_unavailable")
		return false
	diagnostics.relay = "✓ Reachable · peer pairing not tested"
	caption = name_text.strip_edges()
	return true
func host_room(name_text: String) -> void:
	last_intent = "host"
	if not await preflight(name_text):
		return
	var run: int = generation
	role = "host"
	update("Creating a temporary room…")
	var probe := TCPServer.new()
	if probe.listen(0) != OK:
		fail("direct_unavailable")
		return
	var port: int = probe.get_local_port()
	probe.stop()
	if not network.host_game(port, caption):
		fail("direct_unavailable")
		return
	network.required_join_key = "pending"
	var addresses: Array[String] = []
	for address: String in IP.get_local_addresses():
		if not address.contains(":") and address != "127.0.0.1" and addresses.size() < 7:
			addresses.append(address)
	if signaling.service_url.begins_with("http://127.0.0.1:"):
		addresses.push_front("127.0.0.1")
	var result: Dictionary = await signaling.call_service("create", {"session_id": network.session.session_id, "protocol": network.protocol_version, "app_version": Codec.APP_VERSION, "addresses": addresses, "port": port})
	if run != generation:
		if result.get("code") is String and result.get("token") is String:
			await signaling.call_service("close", {"code": result.code, "token": result.token})
		return
	if not accept_room(result):
		return
	network.required_join_key = join_key
	method = "Waiting"
	update("Room %s · waiting for your friend." % code)
func join_room(code_text: String, name_text: String) -> void:
	last_intent = "join"
	var normalized: String = code_text.strip_edges().to_upper().replace(" ", "")
	if normalized.length() == 8: normalized = normalized.left(4)+"-"+normalized.right(4)
	last_code = normalized
	if not valid_code(normalized):
		update(Diagnostics.error_text("room_not_found"))
		return
	if not await preflight(name_text):
		return
	var run: int = generation
	role = "guest"
	update("Finding room…")
	var lookup: Dictionary = await signaling.call_service("lookup", {"code": normalized})
	if run != generation:
		return
	if lookup.has("error"):
		fail(str(lookup.error))
		return
	update("Host found · checking compatibility…")
	if lookup.get("protocol") != network.protocol_version or lookup.get("app_version") != Codec.APP_VERSION:
		incompatible(lookup)
		return
	var result: Dictionary = await signaling.call_service("join", {"code": normalized, "protocol": network.protocol_version, "app_version": Codec.APP_VERSION})
	if run != generation:
		if result.get("code") is String and result.get("token") is String:
			await signaling.call_service("close", {"code": result.code, "token": result.token})
		return
	if result.get("error") == "incompatible":
		incompatible(result)
		return
	if not accept_room(result):
		return
	update("Negotiating connection…")
	method = "Direct"
	update("Trying direct connection…")
	var endpoints: Array = room.addresses.duplicate()
	for address: String in endpoints:
		if run != generation or relaying:
			return
		network.cleanup()
		network.state("disconnected", "Trying the room host.")
		network.join_game(address, int(room.port), caption)
		network.required_join_key = join_key
		network.expected_session_id = session_id
		var deadline: int = Time.get_ticks_msec() + int(clampf(float(config.get_value("internet", "direct_attempt_seconds", 2.0)), 0.2, 4.0) * 1000)
		while active and run == generation and not relaying and Time.get_ticks_msec() < deadline:
			if network.session.state == "connected":
				connected()
				return
			if network.session.state == "error":
				break
			await get_tree().process_frame
	if run == generation and active and not relaying:
		diagnostics.direct = "Unavailable"
		update("Direct connection was blocked. Trying relay mode…")
		var fallback: Dictionary = await signaling.call_service("relay", {"code": code, "token": token})
		if run != generation:
			return
		if fallback.has("error"):
			fail(str(fallback.error))
		elif valid_room(fallback):
			room = fallback
			start_relay()
		else:
			fail("invalid_response")
func accept_room(result: Dictionary) -> bool:
	if result.has("error"):
		fail(str(result.error))
		return false
	if not valid_room(result):
		fail("invalid_response")
		return false
	for field: String in ["token", "join_key"]:
		if not result.get(field) is String or result[field].length() != 32 or not result[field].is_valid_hex_number(false):
			fail("invalid_response")
			return false
	room = result
	code = result.code
	token = result.token
	join_key = result.join_key
	session_id = result.session_id
	active = true
	diagnostics.room_service = "✓ Room verified"
	busy = false
	clock = 0
	was_connected = false
	return true
func _process(delta: float) -> void:
	if not active:
		return
	clock += delta
	if network.session.state == "connected" and not was_connected:
		connected()
	if was_connected and network.session.state in ["disconnected", "error"]:
		was_connected = false
		recovering = true
		relaying = false
		diagnostics.ready = "Connection lost"
		update("Connection lost. Match preserved. Choose Reconnect / Retry.")
	if clock > clampf(float(config.get_value("internet","heartbeat_interval",2.0)),1.0,10.0) and not polling:
		clock = 0
		heartbeat()
func heartbeat() -> void:
	polling = true
	var run: int = generation
	var result: Dictionary = await signaling.call_service("heartbeat", {"code": code, "token": token, "connected": network.session.state == "connected"})
	polling = false
	if run != generation or not active:
		return
	if result.has("error"):
		if result.error in ["room_closed", "host_offline", "room_not_found"]:
			fail(str(result.error))
			return
		diagnostics.service = "Unavailable"
		update("CardLink online service is currently unavailable. Retry, Advanced LAN Connection, or Cancel.")
		return
	if not valid_room(result):
		fail("invalid_response")
		return
	if result.session_id != session_id:
		network.cleanup()
		network.state("disconnected", "Recovering room connection.")
		session_id = result.session_id
		was_connected = false
		relaying = false
		recovering = true
	room = result
	if room.mode == "relay" and not relaying and not was_connected:
		start_relay()
func start_relay() -> void:
	if relaying or not active:
		return
	relaying = true
	var run: int = generation
	diagnostics.direct = "Unavailable"
	if not config.get_value("internet", "relay_enabled", true) or room.relay_port == 0:
		fail("relay_unavailable")
		return
	method = "Relay"
	update("Using relay fallback…")
	network.cleanup()
	network.state("connecting", "Connecting through the relay.")
	var relay_url: String = signaling.service_url
	var relay_host: String = str(room.get("relay_host", ""))
	if not relay_host.is_empty(): relay_url = ("https://" if room.relay_tls else "http://") + relay_host
	var result: Dictionary = await relay_connector.connect_relay(relay_url, int(room.relay_port), room.relay_tls, code, token)
	if run != generation or not active:
		if result.has("stream"):
			result.stream.disconnect_from_host()
		return
	if result.has("error"):
		fail("relay_unavailable")
		return
	network.adopt_stream(result.stream, role, caption, session_id, join_key)
func connected() -> void:
	was_connected = true
	recovering = false
	method = "Relay" if relaying else "Direct"
	diagnostics.direct = "✓ Connected" if not relaying else "Unavailable"
	if relaying:
		diagnostics.relay = "✓ Connected"
	diagnostics.ready = "✓ Connected"
	update("Connected · %s" % method)
func incompatible(other: Dictionary) -> void:
	var details: String = "Your build: %s / protocol %d. Host: %s / protocol %s. Both players need compatible builds." % [Codec.APP_VERSION, network.protocol_version, str(other.get("app_version", "unknown")).left(24), str(other.get("protocol", "unknown")).left(8)]
	cancel()
	update("Your CardLink versions are incompatible. " + details)
func fail(error: String) -> void:
	cancel()
	diagnostics.ready = "Unavailable"
	if error == "relay_unavailable":
		diagnostics.relay = "Unavailable"
	if error in ["service_unavailable", "not_configured"]:
		diagnostics.service = "Unavailable"
	update(Diagnostics.error_text(error))
func retry(name_text: String) -> void:
	if active:
		resume_connection()
	elif last_intent == "join":
		join_room(last_code, name_text)
	else:
		host_room(name_text)
func resume_connection() -> void:
	if not active or resuming: return
	resuming = true
	var run: int = generation
	network.cleanup()
	network.state("disconnected", "Reconnecting room…")
	was_connected = false
	relaying = false
	recovering = true
	var result: Dictionary = await signaling.call_service("resume", {"code":code,"token":token})
	resuming = false
	if run != generation: return
	if result.has("error") or not valid_room(result):
		update("Room recovery unavailable or expired. Keep both apps open; retry or create a new room with your friend.")
		return
	room = result
	session_id = room.session_id
	start_relay()
func cancel() -> void:
	generation += 1
	active = false
	recovering = false
	resuming = false
	busy = false
	was_connected = false
	relaying = false
	relay_connector.cancel()
	if not code.is_empty() and not token.is_empty():
		signaling.call_service("close", {"code": code, "token": token})
	code = ""
	token = ""
	join_key = ""
	session_id = ""
	room = {}
	method = "None"
	network.disconnect_session()
	diagnostics.ready = "Not connected"
	update("Room closed. Local play is available.")
