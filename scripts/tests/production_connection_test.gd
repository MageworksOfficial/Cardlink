extends SceneTree
const URL = "https://35-208-120-243.sslip.io:8787"
const HOST = "35-208-120-243.sslip.io"
var failures: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, caption: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+caption)
	if not ok: failures += 1
func client() -> Node:
	var holder := Node.new()
	root.add_child(holder)
	var net := preload("res://scripts/network/network_manager.gd").new()
	holder.add_child(net)
	var room := preload("res://scripts/network/room_session.gd").new()
	room.network = net
	holder.add_child(room)
	return room
func run() -> void:
	var host: Node = client()
	var guest: Node = client()
	check(host.signaling.service_url == URL and guest.signaling.service_url == URL,"Export defaults to live public service")
	check(host.config.get_value("internet","relay_host","") == HOST and host.config.get_value("internet","relay_port",0) == 8788,"Export contains production relay endpoint")
	var health: Dictionary = await host.signaling.call_service("health",{})
	check(not health.has("error"),"Trusted HTTPS health reachable")
	if not health.has("error"):
		check(health.get("relay_host") == HOST and health.get("relay_port") == 8788 and health.get("relay_tls") == true,"Service relay diagnostics match public host and TLS port")
	await host.host_room("Production connection check")
	check(host.active and host.valid_code(host.code),"Host Game creates a public room code")
	if host.active:
		check(host.diagnostics.relay.contains("✓"),"Verified public TLS relay probe succeeds")
		var found: Dictionary = await guest.signaling.call_service("lookup",{"code":host.code})
		check(found.get("code") == host.code,"Join client finds the public room")
		# Make direct unavailable in this test only, proving the public TLS relay path.
		host.network.server.stop()
		host.network.server = null
		guest.config.set_value("internet","direct_attempt_seconds",0.3)
		await guest.join_room(host.code,"Production guest check")
		var until: int = Time.get_ticks_msec()+25000
		while Time.get_ticks_msec()<until and not (host.was_connected and guest.was_connected): await process_frame
		check(host.was_connected and guest.was_connected and host.method == "Relay" and guest.method == "Relay","Export connects both clients over public relay without direct/Tailscale path")
		host.cancel()
		await create_timer(1).timeout
	else:
		print("Connection stopped safely: "+host.status)
	guest.cancel()
	host.get_parent().queue_free()
	guest.get_parent().queue_free()
	await process_frame
	print("Production connection failures: ",failures)
	quit(0 if failures == 0 else 1)
