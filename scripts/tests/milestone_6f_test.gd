extends SceneTree
var checks: int = 0
var failures: int = 0
var outbound: Array[Dictionary] = []
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", caption)
func wait_for(predicate: Callable, seconds: float = 12) -> bool:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if predicate.call():
			return true
		await process_frame
	return false
func make_client() -> Node:
	var holder := Node.new()
	root.add_child(holder)
	var network := preload("res://scripts/network/network_manager.gd").new()
	holder.add_child(network)
	var room := preload("res://scripts/network/room_session.gd").new()
	room.network = network
	holder.add_child(room)
	room.signaling.service_url = "http://127.0.0.1:8787"
	room.signaling.request_sent.connect(func(action: String, data: Dictionary) -> void: outbound.append({"action": action, "data": data}))
	return room
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	var host: Node = make_client()
	var guest: Node = make_client()
	await host.host_room("Host")
	check(host.active and host.valid_code(host.code), "Automatic host creates a short room code")
	check(host.diagnostics.service.contains("✓") and host.diagnostics.internet.contains("Local"), "Diagnostics honestly distinguish local service from internet reachability")
	var room_code: String = host.code
	var lookup: Dictionary = await guest.signaling.call_service("lookup", {"code": room_code})
	check(lookup.get("state") == "waiting", "Room lookup verifies waiting host")
	var missing: Dictionary = await guest.signaling.call_service("lookup", {"code": "AAAA-0000"})
	check(missing.get("error") == "room_not_found", "Missing room handled")
	await guest.join_room(room_code, "Guest")
	check(await wait_for(func() -> bool: return host.was_connected and guest.was_connected), "Room code connects both peers directly")
	check(host.method == "Direct" and guest.method == "Direct", "Direct path preferred when reachable")
	check(host.network.session.local_peer.player_id == "player_1" and guest.network.session.local_peer.player_id == "player_2", "Room flow preserves host and guest identities")
	var full: Dictionary = await guest.signaling.call_service("join", {"code": room_code, "protocol": 1, "app_version": preload("res://scripts/network/network_codec.gd").APP_VERSION})
	check(full.get("error") == "room_full", "Third player cannot claim full room")
	guest.cancel()
	check(await wait_for(func() -> bool: return not host.active), "Disconnect ends both room sessions")
	var closed: Dictionary = await guest.signaling.call_service("lookup", {"code": room_code})
	check(closed.get("error") == "room_closed", "Disconnect removes room availability")
	await wait_for(func() -> bool: return host.network.available() and guest.network.available())
	await host.host_room("Host")
	guest.network.protocol_version = 2
	await guest.join_room(host.code, "Guest")
	check(guest.status.contains("incompatible") and guest.status.contains("protocol 2") and guest.status.contains("Host:"), "Protocol mismatch displays both versions before connecting")
	guest.network.protocol_version = 1
	host.cancel()
	await wait_for(func() -> bool: return host.network.available() and guest.network.available())
	await host.host_room("Host")
	# Real blocked-direct simulation: close only the inbound listener, keeping rendezvous live.
	host.network.server.stop()
	host.network.server = null
	guest.config.set_value("internet", "direct_attempt_seconds", 0.3)
	await guest.join_room(host.code, "Guest")
	check(await wait_for(func() -> bool: return host.was_connected and guest.was_connected), "Blocked direct connection automatically establishes relay handshake")
	check(host.method == "Relay" and guest.method == "Relay" and guest.diagnostics.relay.contains("✓"), "Relay success reported only after real peer handshake")
	check(host.network.session.session_id == guest.network.session.session_id and not host.session_id.is_empty(), "Relay carries matching safe session identity")
	host.cancel()
	await wait_for(func() -> bool: return not guest.active and host.network.available() and guest.network.available())
	await host.host_room("Host")
	host.network.server.stop()
	host.network.server = null
	guest.config.set_value("internet", "relay_enabled", false)
	await guest.join_room(host.code, "Guest")
	check(guest.status.contains("Relay service unavailable") and not guest.was_connected, "Unavailable fallback never claims success")
	host.cancel()
	guest.config.set_value("internet", "relay_enabled", true)
	await wait_for(func() -> bool: return guest.network.available())
	guest.signaling.service_url = "http://127.0.0.1:8786"
	await guest.host_room("Guest")
	check(guest.status.contains("could not be reached"), "Service unavailable gives human-readable recovery message")
	guest.signaling.service_url = ""
	await guest.host_room("Guest")
	check(guest.status.contains("not configured"), "Undeployed build does not pretend public rooms work")
	guest.signaling.service_url = "http://127.0.0.1:8787"
	var invalid: Dictionary = await guest.signaling.call_service("create", {"hand": ["PRIVATE_CARD"]})
	check(invalid.get("error") == "invalid_request", "Client blocks private gameplay signaling payload")
	var safe: bool = true
	for record: Dictionary in outbound:
		safe = safe and not JSON.stringify(record).contains("PRIVATE_CARD") and guest.signaling.FIELDS.has(record.action)
	check(safe, "Captured signaling consists only of room negotiation metadata")
	check(not guest.valid_room({"addresses": ["invalid"]}), "Malformed service room rejected defensively")
	check(not guest.signaling.valid_payload("create", {"session_id": "a".repeat(32), "protocol": 1, "app_version": preload("res://scripts/network/network_codec.gd").APP_VERSION, "addresses": [{"hand": "PRIVATE"}], "port": 27860}), "Nested private data rejected before any HTTP request")
	host.get_parent().queue_free()
	guest.get_parent().queue_free()
	await process_frame
	for mode: String in ["direct", "relay"]:
		var directory: String = base.path_join(mode)
		DirAccess.make_dir_recursive_absolute(directory)
		var pids: Array[int] = []
		for role: String in ["host", "guest"]:
			pids.append(OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/room_client_worker.gd", "--log-file", directory.path_join(role + ".log"), "--", directory, role, mode, "0"]), false))
		var done: bool = await wait_for(func() -> bool: return FileAccess.file_exists(directory.path_join("host_result.json")) and FileAccess.file_exists(directory.path_join("guest_result.json")), 35)
		check(done, "Separate room-code clients finish: " + mode)
		if done:
			var a: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("host_result.json")))
			var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("guest_result.json")))
			check(a.connected and b.connected and a.method.to_lower() == mode and b.method.to_lower() == mode and a.session == b.session, "Separate clients connect using " + mode)
			check(a.local == "player_1" and b.local == "player_2" and a.disconnected and b.disconnected, "Separate room clients identify and disconnect: " + mode)
			check(a.unchanged and b.unchanged and a.safe and b.safe, "Loaded private decks stay local and unchanged: " + mode)
		for pid: int in pids:
			if pid > 0:
				await wait_for(func() -> bool: return not OS.is_process_running(pid), 2)
				if OS.is_process_running(pid):
					OS.kill(pid)
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	for _i: int in 4:
		await process_frame
	var panel: Node = main.get_node("Network")
	panel.open_panel()
	check(panel.room_code.visible and not panel.advanced.is_visible_in_tree(), "Room codes are primary; manual LAN is under Advanced")
	check(main.tabletop.shortcuts.blocked(), "Room-code text entry blocks tabletop hotkeys")
	panel.rooms.signaling.service_url = "http://127.0.0.1:8787"
	await panel.rooms.host_room("UI Host")
	check(panel.internet_status.text.contains(panel.rooms.code) and panel.internet_cancel.disabled == false, "Host panel shows room code and Cancel Host")
	if OS.get_cmdline_user_args().size() > 1:
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("rooms.png"))
	panel.rooms.cancel()
	await create_timer(0.4).timeout
	main.queue_free()
	await process_frame
	print("MILESTONE 6F: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
