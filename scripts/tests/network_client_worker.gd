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
	ui.display_name.text = "Test " + role
	ui.port.value = port
	if mode == "mismatch" and role == "guest":
		n.protocol_version = 2
	var results: Array[Dictionary] = []
	for round_number: int in (2 if mode == "guest_leaves" else 1):
		var marker: String = directory.path_join("ready_%d" % round_number)
		if role == "host":
			ui.host_button.pressed.emit()
			write(marker, {"ready": n.session.state == "hosting"})
		else:
			await wait_for(func() -> bool: return FileAccess.file_exists(marker))
			ui.join_button.pressed.emit()
		if mode == "mismatch":
			var rejected: bool = await wait_for(func() -> bool: return n.session.state == "error")
			results.append({"rejected": rejected, "status": n.session.status, "reset": n.session.session_id.is_empty() and n.session.remote_peer.player_id.is_empty()})
			break
		var connected: bool = await wait_for(func() -> bool: return n.session.state == "connected")
		var result: Dictionary = {"connected": connected, "local": n.session.local_peer.player_id, "remote": n.session.remote_peer.player_id, "role": n.session.local_peer.role, "session": n.session.session_id}
		write(directory.path_join(role + "_connected_%d" % round_number), result)
		var other: String = "guest" if role == "host" else "host"
		await wait_for(func() -> bool: return FileAccess.file_exists(directory.path_join(other + "_connected_%d" % round_number)))
		if (mode == "host_leaves" and role == "host") or (mode == "guest_leaves" and role == "guest"):
			ui.disconnect_button.pressed.emit()
		result["disconnected"] = await wait_for(func() -> bool: return n.session.state == "disconnected")
		result["reset"] = n.session.session_id.is_empty() and n.session.remote_peer.player_id.is_empty()
		result["local_usable"] = main.tabletop.active and main.tabletop.cards.size() > 0
		results.append(result)
	var unchanged: bool = before == preload("res://scripts/match_snapshot.gd").capture(main.tabletop) and saved_bytes == FileAccess.get_file_as_bytes(saved.path) and FileAccess.file_exists(definition.metadata_path)
	write(directory.path_join(role + "_result.json"), {"rounds": results, "sent": sent, "log": n.debug_log, "local_unchanged": unchanged})
	main.queue_free()
	await process_frame
	quit()
