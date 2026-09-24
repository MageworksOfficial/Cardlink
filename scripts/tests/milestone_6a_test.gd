extends SceneTree
const Network = preload("res://scripts/network/network_manager.gd")
const Codec = preload("res://scripts/network/network_codec.gd")
var checks: int = 0
var failures: int = 0
var sent: Array[Dictionary] = []
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", caption)
func wait_for(predicate: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false
func read(path: String) -> Dictionary:
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result if result is Dictionary else {}
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	var host := Network.new()
	var guest := Network.new()
	root.add_child(host)
	root.add_child(guest)
	host.message_sent.connect(func(message: Dictionary) -> void: sent.append(message))
	guest.message_sent.connect(func(message: Dictionary) -> void: sent.append(message))
	check(host.session.state == "disconnected" and host.peer == null, "Network module initializes without opening sockets")
	var port: int = 32000 + randi_range(0, 10000)
	check(not host.host_game(0, "Host") and host.session.state == "error", "Invalid port rejected without crashing")
	check(not guest.join_game("bad address", port, "Guest"), "Invalid address rejected without blocking DNS")
	check(host.host_game(port, "Host", "127.0.0.1") and host.session.state == "hosting", "Host starts TCP listener")
	check(host.session.local_peer.player_id == "player_1" and host.session.local_peer.role == "host", "Host is Player 1")
	var occupied := Network.new()
	root.add_child(occupied)
	check(not occupied.host_game(port, "Other", "127.0.0.1") and occupied.session.state == "error", "Occupied port fails safely")
	check(guest.join_game("127.0.0.1", port, "Guest"), "Guest starts connection")
	check(await wait_for(func() -> bool: return host.session.state == "connected" and guest.session.state == "connected"), "Both clients complete handshake over actual TCP")
	check(guest.session.local_peer.player_id == "player_2" and guest.session.local_peer.role == "guest", "Guest is Player 2")
	check(host.session.remote_peer.player_id == "player_2" and guest.session.remote_peer.player_id == "player_1", "Both clients know the other player's identity")
	check(host.session.session_id == guest.session.session_id and host.session.session_id.length() == 32, "Both clients share a random session ID")
	check(host.session.remote_peer.display_name == "Guest" and guest.session.remote_peer.display_name == "Host", "Display names survive handshake")
	var extra := StreamPeerTCP.new()
	extra.connect_to_host("127.0.0.1", port)
	await create_timer(0.2).timeout
	extra.poll()
	check(host.session.state == "connected" and host.session.remote_peer.display_name == "Guest", "Third connection cannot replace established guest")
	extra.disconnect_from_host()
	check(not host.send_message({"type": "ready", "protocol": 1, "session_id": host.session.session_id, "hand": ["PRIVATE"]}), "Outbound serializer rejects private and unknown fields")
	check(Codec.decode('{"type":"snapshot","deck":["PRIVATE"]}'.to_utf8_buffer()).is_empty(), "Unknown network message rejected")
	check(Codec.decode('not json'.to_utf8_buffer()).is_empty(), "Malformed JSON rejected")
	check(Codec.decode('[]'.to_utf8_buffer()).is_empty(), "Non-object payload rejected")
	check(Codec.decode(PackedByteArray([255, 254, 192])).is_empty(), "Invalid UTF-8 rejected without decoder errors")
	check(Codec.decode('x'.repeat(2049).to_utf8_buffer()).is_empty(), "Oversized frame rejected")
	check(Codec.encode({"type": "bye", "protocol": 1.5}).is_empty(), "Fractional protocol rejected")
	var identity: Dictionary = host.identity_message("welcome")
	identity.role = "guest"
	check(Codec.encode(identity).is_empty(), "Role spoofing rejected")
	guest.disconnect_session()
	check(await wait_for(func() -> bool: return host.session.state == "disconnected" and guest.session.state == "disconnected"), "Guest disconnect cleans up both clients")
	check(host.session.session_id.is_empty() and guest.session.remote_peer.player_id.is_empty() and host.server == null, "Disconnect clears session, peer identity and listener")
	host.host_game(port, "Host", "127.0.0.1")
	guest.join_game("localhost", port, "Guest")
	check(await wait_for(func() -> bool: return host.session.state == "connected" and guest.session.state == "connected"), "Both clients reconnect after disconnect")
	host.disconnect_session()
	check(await wait_for(func() -> bool: return host.session.state == "disconnected" and guest.session.state == "disconnected"), "Host disconnect cleans up both clients")
	host.host_game(port, "Host", "127.0.0.1")
	guest.protocol_version = 2
	guest.join_game("127.0.0.1", port, "Guest")
	check(await wait_for(func() -> bool: return host.session.state == "error" and guest.session.state == "error"), "Incompatible protocol rejected by both clients")
	check(host.session.status.contains("Protocol mismatch") and guest.session.status.contains("Protocol mismatch"), "Mismatch status explains compatibility requirement")
	check(host.peer == null and guest.peer == null and guest.session.session_id.is_empty(), "Mismatch closes sockets and resets session")
	guest.protocol_version = 1
	guest.join_game("127.0.0.1", port, "Guest")
	check(await wait_for(func() -> bool: return guest.session.state == "error", 12), "Unavailable host produces useful connection error")
	host.host_game(port, "Host", "127.0.0.1")
	var raw := StreamPeerTCP.new()
	raw.connect_to_host("127.0.0.1", port)
	await wait_for(func() -> bool: raw.poll(); return raw.get_status() == StreamPeerTCP.STATUS_CONNECTED)
	raw.put_data('{"type":"hello","hand":["PRIVATE_SENTINEL"]}\n'.to_utf8_buffer())
	check(await wait_for(func() -> bool: return host.session.state == "error"), "Malformed peer handshake closes safely")
	check(not "\n".join(host.debug_log).contains("PRIVATE_SENTINEL"), "Rejected payload is never copied to debug log")
	raw.disconnect_from_host()
	var safe: bool = true
	for message: Dictionary in sent:
		safe = safe and Codec.valid(message) and not JSON.stringify(message).contains("PRIVATE")
	check(safe, "All outbound traffic is limited to allowed session/control metadata")
	host.queue_free()
	guest.queue_free()
	occupied.queue_free()
	await process_frame
	for mode: String in ["guest_leaves", "host_leaves", "mismatch"]:
		var directory: String = base.path_join(mode)
		DirAccess.make_dir_recursive_absolute(directory)
		var children: Array[int] = []
		for role: String in ["host", "guest"]:
			var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/network_client_worker.gd", "--log-file", directory.path_join(role + ".log"), "--", directory, role, mode, str(port + 1)])
			children.append(OS.create_process(OS.get_executable_path(), args, false))
		var finished: bool = await wait_for(func() -> bool: return FileAccess.file_exists(directory.path_join("host_result.json")) and FileAccess.file_exists(directory.path_join("guest_result.json")), 25)
		check(finished, "Two separate CardLink processes finish: " + mode)
		if finished:
			var a: Dictionary = read(directory.path_join("host_result.json"))
			var b: Dictionary = read(directory.path_join("guest_result.json"))
			check(a.local_unchanged and b.local_unchanged, "Private hand/library, tabletop and saved deck remain unchanged: " + mode)
			for i: int in a.rounds.size():
				if mode == "mismatch":
					check(a.rounds[i].rejected and b.rounds[i].rejected and a.rounds[i].reset and b.rounds[i].reset, "Separate clients reject protocol mismatch and reset")
				else:
					check(a.rounds[i].connected and b.rounds[i].connected and a.rounds[i].local == "player_1" and b.rounds[i].local == "player_2" and a.rounds[i].remote == "player_2" and b.rounds[i].remote == "player_1" and a.rounds[i].session == b.rounds[i].session, "Separate clients agree on roles and session: %s round %d" % [mode, i + 1])
					check(a.rounds[i].disconnected and b.rounds[i].disconnected and a.rounds[i].reset and b.rounds[i].reset and a.rounds[i].local_usable and b.rounds[i].local_usable, "Separate clients disconnect and retain local tabletop: %s round %d" % [mode, i + 1])
			var private_safe: bool = true
			for message: Dictionary in a.sent + b.sent:
				private_safe = private_safe and Codec.valid(message) and not JSON.stringify(message).contains("PRIVATE_SENTINEL")
			check(private_safe, "Separate-process transmitted messages obey metadata-only schema: " + mode)
		for pid: int in children:
			if pid > 0:
				await wait_for(func() -> bool: return not OS.is_process_running(pid), 2)
				if OS.is_process_running(pid):
					OS.kill(pid)
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	for _frame: int in 4:
		await process_frame
	var panel: Node = main.get_node("Network")
	main.tabletop.extras.choose("Multiplayer / Network")
	check(panel.window.visible and panel.status.text.contains("Disconnected"), "Menu opens Network panel with disconnected status")
	check(main.tabletop.shortcuts.blocked(), "Network text entry blocks tabletop hotkeys")
	panel.port.value = port
	panel.host_button.pressed.emit()
	check(panel.status.text.contains("Hosting") and panel.identities.text.contains("Player 1") and panel.join_button.disabled, "Panel reflects hosting identity and locks connection settings")
	if OS.get_cmdline_user_args().size() > 1:
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("network_panel.png"))
	panel.disconnect_button.pressed.emit()
	check(panel.network.session.state == "disconnected" and panel.host_button.disabled == false, "Panel disconnect stops idle hosting and permits restart")
	panel.window.close_requested.emit()
	check(not panel.window.visible and main.tabletop.active, "Network panel closes leaving local play usable")
	main.queue_free()
	await process_frame
	print("MILESTONE 6A: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
