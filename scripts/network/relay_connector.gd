extends Node
## Outbound-only relay connector. No inbound router configuration is needed.
var timeout_seconds: float = 15.0
var cancelled: bool = false
var current: RefCounted
func cancel() -> void:
	cancelled = true
	if current != null:
		current.disconnect_from_host()
	current = null
func connect_relay(url: String, port: int, secure: bool, code: String, token: String, probe: bool = false) -> Dictionary:
	cancelled = false
	var hostname: String = url.trim_prefix("https://").trim_prefix("http://").split("/")[0].split(":")[0]
	if not secure and not hostname in ["127.0.0.1", "localhost"]:
		return {"error": "relay_unavailable"}
	var address: String = hostname
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000)
	if not hostname.is_valid_ip_address():
		var lookup: int = IP.resolve_hostname_queue_item(hostname, IP.TYPE_IPV4)
		if lookup == IP.RESOLVER_INVALID_ID:
			return {"error": "relay_unavailable"}
		while IP.get_resolve_item_status(lookup) == IP.RESOLVER_STATUS_WAITING and Time.get_ticks_msec() < deadline and not cancelled:
			await get_tree().process_frame
		address = IP.get_resolve_item_address(lookup) if IP.get_resolve_item_status(lookup) == IP.RESOLVER_STATUS_DONE else ""
		IP.erase_resolve_item(lookup)
	if cancelled or address.is_empty():
		return {"error": "relay_unavailable"}
	var adapter = preload("res://scripts/network/relay_stream.gd").new()
	adapter.tcp = StreamPeerTCP.new()
	current = adapter
	if adapter.tcp.connect_to_host(address, port) != OK:
		cancel()
		return {"error": "relay_unavailable"}
	while Time.get_ticks_msec() < deadline and not cancelled:
		adapter.tcp.poll()
		if adapter.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		await get_tree().process_frame
	if cancelled or adapter.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		cancel()
		return {"error": "relay_unavailable"}
	if secure:
		adapter.tls = StreamPeerTLS.new()
		if adapter.tls.connect_to_stream(adapter.tcp, hostname) != OK:
			cancel()
			return {"error": "relay_unavailable"}
		while adapter.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline and not cancelled:
			adapter.poll()
			await get_tree().process_frame
	if cancelled or adapter.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		cancel()
		return {"error": "relay_unavailable"}
	var outgoing: PackedByteArray = (JSON.stringify({"probe":true} if probe else {"code": code, "token": token}) + "\n").to_utf8_buffer()
	var reply := PackedByteArray()
	while Time.get_ticks_msec() < deadline and not cancelled:
		adapter.poll()
		if adapter.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		if not outgoing.is_empty():
			var sent: Array = adapter.put_partial_data(outgoing)
			if sent[0] != OK:
				break
			outgoing = outgoing.slice(int(sent[1]))
		# Consume exactly the relay greeting, leaving peer handshake bytes untouched.
		while adapter.get_available_bytes() > 0 and reply.size() < 64:
			var received: Array = adapter.get_partial_data(1)
			if received[0] != OK or received[1].is_empty():
				break
			if received[1][0] == 10:
				if probe:
					var health: Variant = JSON.parse_string(reply.get_string_from_utf8())
					cancel()
					if health is Dictionary and health.get("relay") == true and health.get("protocol") == preload("res://scripts/network/network_codec.gd").PROTOCOL:
						return {"healthy":true}
					return {"error":"relay_unavailable"}
				if reply.get_string_from_utf8() == '{"paired":true}':
					current = null
					return {"stream": adapter}
				cancel()
				return {"error": "relay_unavailable"}
			reply.append(received[1][0])
		if reply.size() >= 64:
			break
		await get_tree().process_frame
	cancel()
	return {"error": "relay_unavailable"}
