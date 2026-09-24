extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var cfg := ConfigFile.new()
	var ok: bool = cfg.load("res://config/network.cfg") == OK
	var expected: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	ok = ok and cfg.get_value("internet","service_url","MISSING") == expected
	var holder := Node.new()
	root.add_child(holder)
	var network := preload("res://scripts/network/network_manager.gd").new()
	holder.add_child(network)
	var rooms := preload("res://scripts/network/room_session.gd").new()
	rooms.network = network
	holder.add_child(rooms)
	ok = ok and rooms.signaling.service_url == expected and network.Codec.APP_VERSION == preload("res://scripts/frontend/app_info.gd").NETWORK_COMPATIBILITY
	print("PASS: Export contains service configuration and room client loads it" if ok else "FAIL: Export service configuration missing or incorrect")
	holder.queue_free()
	await process_frame
	quit(0 if ok else 1)
