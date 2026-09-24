extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.gui_embed_subwindows = true
	var a: Control = await create_client(base.path_join("a"),"Host Card",Color.BLUE)
	var b: Control = await create_client(base.path_join("b"),"Guest Card",Color.RED)
	var ua: Node = a.get_node("Network")
	var ub: Node = b.get_node("Network")
	var sa: Node = ua.gameplay.card_sync
	var sb: Node = ub.gameplay.card_sync
	ub.sync_button.pressed.emit()
	check(sb.status.contains("No active peer connection"),"Actual button handler gives useful no-peer error")
	var port: int = randi_range(33000,43000)
	ua.network.host_game(port,"Host","127.0.0.1")
	ub.network.join_game("127.0.0.1",port,"Guest")
	check(await wait_for(func() -> bool: return ua.network.session.state == "connected" and ub.network.session.state == "connected"),"Two clients connected")
	ub.sync_button.pressed.emit()
	check(sb.status.contains("Both players must choose Share Tabletop"),"Preparation required explicitly")
	ub.gameplay.start()
	ub.sync_button.pressed.emit()
	check(sb.status.contains("Host deck manifest was not received"),"Missing manifest reported")
	ua.gameplay.start()
	check(await wait_for(func() -> bool: return sa.checked and sb.checked),"Both availability manifests received")
	var version: String = ub.network.remote_app_version
	ub.network.remote_app_version = "6B"
	ub.sync_button.pressed.emit()
	check(sb.status.contains("Update both clients"),"Incompatible peer gives actionable version error")
	ub.network.remote_app_version = version
	var availability: Dictionary = sb.remote_availability
	sb.remote_availability = {}
	ub.sync_button.pressed.emit()
	check(sb.status.contains("availability was not received"),"Missing availability reported")
	sb.remote_availability = availability
	ub.sync_button.pressed.emit()
	check(sb.requested and ub.sync_button.disabled and sb.status.contains("Preparing"),"One guest click immediately prepares and disables button")
	for i: int in 5: ub.sync_button.pressed.emit()
	check(await wait_for(func() -> bool: return sa.status.begins_with("CARD SYNC COMPLETE") and sb.status.begins_with("CARD SYNC COMPLETE"),15),"Guest-only click completes both transfer directions")
	check(wire.filter(func(f: Dictionary) -> bool: return f.type == "card_sync" and f.kind == "begin").size() == 1,"Repeated clicks create only one transfer job")
	check(sa.reports["1"].images == 1 and sa.reports["2"].images == 1,"Both directions transfer real missing images")
	check(not ub.start_match_button.disabled and sb.inspect_required().missing == 0,"Availability updates and Start Match enabled")
	check(ub.sync_log.text.contains("Step 1") and ub.sync_log.text.contains("Step 2") and ub.sync_log.text.contains("complete"),"Visible log shows both steps and completion")
	ua.sync_button.pressed.emit()
	check(await wait_for(func() -> bool: return sa.status.begins_with("CARD SYNC COMPLETE") and not sa.requested and not sa.running,15),"Host-only click also completes")
	# Simulate a peer that stops acknowledging without waiting 30 wall-clock seconds.
	ub.sync_button.pressed.emit()
	sb._process(31)
	check(sb.status.contains("timed out") and not ub.sync_button.disabled,"Bounded timeout restores Retry")
	await settle()
	ub.sync_button.pressed.emit()
	check(await wait_for(func() -> bool: return sa.status.begins_with("CARD SYNC COMPLETE") and sb.status.begins_with("CARD SYNC COMPLETE"),15),"Retry works after timeout")
	ua.network.disconnect_session()
	await settle()
	a.queue_free()
	b.queue_free()
	await process_frame
	print("SYNC ACTIVATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
