extends "res://scripts/tests/milestone_6b_test.gd"
class TestShell extends "res://scripts/application_shell.gd":
	var exits: int = 0
	func exit_now() -> void: exits += 1
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var app: Control = TestShell.new()
	app.preferences = preload("res://scripts/frontend/player_preferences.gd").new(base.path_join("profile.cfg"))
	app.privacy_path = base.path_join("privacy.cfg")
	app.recovery_directory = OS.get_cmdline_user_args()[0].path_join("recovery")
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	app.entry.deck_preferences = preload("res://scripts/usability/deck_preferences.gd").new(base.path_join("recent_decks.cfg"))
	app.entry.saves.directory = base.path_join("matches")
	app.entry.decks.directory = base.path_join("decks")
	app.entry.refresh_resume()
	check(app.mode == app.Mode.TITLE and app.table_scene == null,"Title loads before any table or networking")
	check(app.updater.button.text.begins_with(preload("res://scripts/frontend/app_info.gd").LABEL),"Title version comes from central source")
	check(app.entry.resume_button.disabled,"Resume is disabled with no saves")
	check(app.shared_settings.welcome.visible,"First-run help opens")
	await capture(base,"welcome_73")
	app.shared_settings.no_again.button_pressed = true
	app.shared_settings.welcome.confirmed.emit()
	app.shared_settings.welcome.hide()
	var prefs = preload("res://scripts/frontend/player_preferences.gd").new(app.preferences.path)
	check(prefs.get_flag("welcome_seen") and prefs.get_flag("hide_welcome"),"Got it and Don't show again persist")
	app.shared_settings.open()
	check(app.title_screen.settings.visible,"Title opens shared Settings")
	await capture(base,"settings_73")
	app.shared_settings.name_edit.text = "Lewis"
	app.shared_settings.save()
	prefs = preload("res://scripts/frontend/player_preferences.gd").new(app.preferences.path)
	check(prefs.player_name() == "Lewis","Player name survives fresh preferences instance")
	check(prefs.clean_name(" \n\t ") == "CardLink Player" and prefs.clean_name("x".repeat(100)).length() == 48,"Names sanitize and fall back safely")
	app.title_screen.close_settings()
	app.shared_settings.helper.popup_centered()
	check(app.shared_settings.helper.visible,"Title controls help opens")
	app.shared_settings.helper.hide()
	if "capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("title_73.png"))
	app.entry.new_match()
	check(app.entry.window.visible and app.entry.window.title == "New Match","New Match offers mode selection")
	app.entry.offline()
	await capture(base,"offline_entry_73")
	check(app.entry.deck_pickers.size() == 2 and app.entry.deck_pickers[0].item_count == 1,"Offline offers optional decks for both players")
	app.entry.start(app.Mode.OFFLINE_PLAYTEST)
	check(await wait_for(func() -> bool: return not app.entering and app.table_scene != null),"Offline transition finishes")
	var table: Node = app.table_scene.tabletop
	var c: Node = table.match_controller
	table.persistence.matches = app.entry.saves
	check(not app.table_scene.has_node("Network"),"Offline entry creates no network service")
	check(c.model.players.local.display_name == "Lewis","Local history identity uses profile")
	check(app.presenter.indicator.text == "OFFLINE PLAYTEST","Offline status indicator")
	await capture(base,"table_73")
	check(not app.departure.dirty(),"Fresh empty table has no unsaved match changes")
	table.view.zoom_by(1.2)
	check(not app.departure.dirty(),"Camera-only changes do not force a save prompt")
	table.extras.choose("Settings")
	check(app.title_screen.settings.visible,"In-game menu opens same Settings window")
	app.title_screen.close_settings()
	table.shortcuts.open_help()
	check(table.shortcuts.help.visible,"Table controls help works")
	table.shortcuts.help.hide()
	c.change_life("local",-3)
	check(c.model.history.back().text.contains("Lewis"),"Life history includes chosen name")
	check(app.departure.dirty(),"Life changes mark match dirty")
	app.request_return()
	check(app.return_dialog.visible and app.table_scene != null,"Unsaved return offers save/discard/cancel")
	await capture(base,"save_return_73")
	app.return_dialog.hide()
	check(c.model.players.local.life == 37,"Cancel retains match")
	app.request_return()
	app.departure.save_name.text = "Professor Playtest"
	app.return_dialog.confirmed.emit()
	await process_frame
	check(app.table_scene == null and app.title_screen.visible,"Save & Return reaches title")
	check(app.entry.saves.list_records().size() == 1 and not app.entry.resume_button.disabled,"Save is available to Resume")
	app.entry.resume_match()
	check(app.entry.save_picker.get_item_text(0).contains("Professor Playtest") and not app.entry.save_picker.get_item_text(0).contains(base),"Resume shows name/mode/date without file paths")
	app.entry.resume_selected()
	await wait_for(func() -> bool: return not app.entering and app.table_scene != null)
	table = app.table_scene.tabletop
	c = table.match_controller
	table.persistence.matches = app.entry.saves
	check(c.model.players.local.life == 37 and not app.table_scene.has_node("Network"),"Resume restores saved match safely offline")
	app.request_return()
	await process_frame
	check(app.table_scene == null,"Unchanged resumed match returns without confirmation")
	# Invalid save data is handled in the browser without entering a table.
	var malformed: Dictionary = app.entry.saves.save_record({"local_tabletop":"invalid"},"Broken test")
	app.entry.resume_match()
	for i: int in app.entry.save_picker.item_count:
		if app.entry.save_picker.get_item_metadata(i) == malformed.path: app.entry.save_picker.select(i)
	app.entry.resume_selected()
	check(app.table_scene == null and not app.entry.message.text.is_empty(),"Malformed save fails gracefully and stays in browser")
	app.entry.window.hide()
	app.entry.new_match()
	app.entry.start(app.Mode.ONLINE)
	await wait_for(func() -> bool: return not app.entering and app.table_scene != null)
	var panel: Node = app.table_scene.get_node("Network")
	check(panel.window.visible and panel.network.available(),"Online opens Host/Join without connecting automatically")
	# Real settings are used by production; inject the isolated test profile for this session.
	panel.display_name.text = "Lewis"
	check(panel.network.Codec.APP_VERSION == preload("res://scripts/frontend/app_info.gd").NETWORK_COMPATIBILITY,"Presentation version does not break wire compatibility")
	check(not panel.advanced.get_parent().visible,"LAN and raw diagnostics remain under Advanced")
	panel.window.hide()
	var peer = preload("res://scripts/network/peer_identity.gd")
	panel.network.session.local_peer = peer.new("player_1","host","Lewis")
	panel.network.session.remote_peer = peer.new("player_2","guest","Verox")
	panel.network.session.state = "connected"
	app.presenter.refresh()
	check(app.presenter.indicator.text.contains("Verox"),"Online status uses remote name")
	check(app.table_scene.tabletop.match_controller.model.players.opponent.display_name == "Verox","Opponent life/turn model uses remote name")
	await capture(base,"online_table_73")
	check(panel.gameplay.player_name("player_2") == "Verox" and panel.gameplay.hidden.player("player_2") == "Verox","Public history and consent use handshake names")
	panel.network.session.state = "disconnected"
	app.return_to_title()
	await process_frame
	# Recreate a shell with saved preferences: no first-run prompt on restart.
	var second: Control = TestShell.new()
	second.preferences = preload("res://scripts/frontend/player_preferences.gd").new(app.preferences.path)
	second.privacy_path = app.privacy_path
	root.add_child(second)
	await process_frame
	check(not second.shared_settings.welcome.visible and second.preferences.player_name() == "Lewis","Restart restores profile and suppresses first-run help")
	second.queue_free()
	await process_frame
	app.request_exit()
	check(app.exits == 1,"Title Exit closes directly")
	app.queue_free()
	await process_frame
	print("CARDLINK 7.3: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func capture(base: String, caption: String) -> void:
	if not "capture" in OS.get_cmdline_user_args(): return
	await create_timer(0.16).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(base.path_join(caption+".png"))

