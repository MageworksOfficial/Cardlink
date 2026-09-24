extends SceneTree
## Separate-process integration client. Fixture files are test coordination only.
var sent: Array[Dictionary] = []
func _initialize() -> void:
	run.call_deferred()
func wait_for(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false
func write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var directory: String = args[0]
	var role: String = args[1]
	var mode: String = args[2]
	var port: int = int(args[3])
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	for _frame: int in 4:
		await process_frame
	var ui: Node = main.get_node("Network")
	var n: Node = ui.network
	var cards_dir: String = directory.path_join(role + "_cards")
	var image := Image.create(750, 1050, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORAL)
	var definition: Dictionary = preload("res://scripts/card_storage.gd").new(cards_dir).save_card(image.save_png_to_buffer(), "PRIVATE_SENTINEL_" + role, image.get_size())
	var decks = preload("res://scripts/deck_storage.gd").new(directory.path_join(role + "_decks"))
	var deck: Dictionary = decks.new_deck()
	deck.cards = [{"card_id": definition.metadata.card_id, "quantity": 4}]
	var saved: Dictionary = decks.save_deck(deck)
	main.tabletop.match_controller.loader = preload("res://scripts/library_loader.gd").new(cards_dir)
	main.tabletop.match_controller.load_deck(deck, false)
	main.tabletop.match_controller.draw_card()
	var before: Dictionary = preload("res://scripts/match_snapshot.gd").capture(main.tabletop)
	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(saved.path)
	n.message_sent.connect(func(message: Dictionary) -> void: sent.append(message))
	var rooms: Node = ui.rooms
	var signaling: Array[Dictionary] = []
	rooms.signaling.service_url = "http://127.0.0.1:8787"
	rooms.config.set_value("internet", "direct_attempt_seconds", 0.3)
	rooms.signaling.request_sent.connect(func(action: String, data: Dictionary) -> void: signaling.append({"action": action, "data": data}))
	var marker: String = directory.path_join("room.json")
	if role == "host":
		await rooms.host_room("Test Host")
		if mode == "relay":
			n.server.stop()
			n.server = null
		write(marker, {"code": rooms.code})
	else:
		await wait_for(func() -> bool: return FileAccess.file_exists(marker))
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(marker))
		await rooms.join_room(data.code, "Test Guest")
	var connected: bool = await wait_for(func() -> bool: return rooms.was_connected, 15)
	var result: Dictionary = {"connected": connected, "method": rooms.method, "local": n.session.local_peer.player_id, "remote": n.session.remote_peer.player_id, "session": n.session.session_id}
	write(directory.path_join(role + "_connected.json"), result)
	var other: String = "guest" if role == "host" else "host"
	await wait_for(func() -> bool: return FileAccess.file_exists(directory.path_join(other + "_connected.json")))
	if role == "guest":
		rooms.cancel()
	result["disconnected"] = await wait_for(func() -> bool: return not rooms.active and n.session.state == "disconnected")
	result["unchanged"] = before == preload("res://scripts/match_snapshot.gd").capture(main.tabletop) and saved_bytes == FileAccess.get_file_as_bytes(saved.path)
	result["safe"] = not JSON.stringify(signaling).contains("PRIVATE_SENTINEL") and not JSON.stringify(sent).contains("PRIVATE_SENTINEL")
	write(directory.path_join(role + "_result.json"), result)
	main.queue_free()
	await process_frame
	quit()

