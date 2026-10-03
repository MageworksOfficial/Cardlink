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
	app.shared_settings.welcome.hide()
	app.entry.deck_preferences = preload("res://scripts/usability/deck_preferences.gd").new(base.path_join("recent_decks.cfg"))
	app.entry.saves.directory = base.path_join("matches")
	var title: Control = app.title_screen
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://scenes/application_shell.tscn","Production starts with entry scene")
	check(app.mode==app.Mode.TITLE and app.table_scene==null,"Title launches before gameplay or networking")
	check(title.background.texture!=null and title.title_art.texture!=null,"Supplied background and title load")
	check(title.buttons.size()==4 and title.buttons.all(func(b: Button) -> bool: return b.artwork!=null),"Four separate clickable artwork controls")
	check(not title.background.texture.resource_path.contains("reference"),"Flattened reference is never production UI")
	for extent: Vector2i in [Vector2i(1152,760),Vector2i(1672,941),Vector2i(1920,1080),Vector2i(800,600)]:
		root.size = extent
		await process_frame
		await process_frame
		title.arrange()
		check(is_equal_approx(title.composition.scale.x,title.composition.scale.y) and title.buttons.all(func(b: Button) -> bool: return Rect2(Vector2.ZERO,title.size).encloses(b.get_global_rect())),"Uniform usable layout at "+str(extent))
		if "capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(base.path_join("title_%dx%d.png" % [extent.x,extent.y]))
	root.size = Vector2i(1152,760)
	await process_frame
	title.buttons[2].pressed.emit()
	check(title.settings.visible and title.back_preview.texture!=null,"Settings opens existing card-back preference")
	title.close_settings()
	check(not title.settings.visible and title.buttons[2].has_focus(),"Settings closes and returns focus")
	title.open_settings()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	title.settings.window_input.emit(escape)
	check(not title.settings.visible,"Escape closes Settings")
	title.backs.directory = base.path_join("settings")
	title.backs.reload()
	var custom := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	custom.fill(Color.DARK_BLUE)
	var custom_path: String = base.path_join("test_back.png")
	custom.save_png(custom_path)
	title.picker.file_selected.emit(custom_path)
	check(title.backs.selected_id.begins_with("custom_") and title.settings_status.text=="Card back saved.","Settings uses existing custom-back import and persistence")
	title.buttons[3].pressed.emit()
	check(app.exits==1,"Exit button reaches clean application exit handler")
	title.buttons[0].grab_focus()
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	Input.parse_input_event(right)
	Input.flush_buffered_events()
	check(title.buttons[1].has_focus(),"Arrow key moves focus between mode panels")
	check(title.buttons[1].has_focus() and not title.buttons[1].focus_neighbor_left.is_empty(),"Mode buttons support keyboard/controller focus")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	Input.flush_buffered_events()
	var release: InputEventKey = enter.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	check(app.table_selection.visible,"Enter opens table choice")
	app.table_chosen(false)
	check(app.entry.window.visible,"Standard opens focused Offline setup")
	app.entry.start(app.Mode.OFFLINE_PLAYTEST)
	check(await wait_for(func() -> bool: return app.mode==app.Mode.OFFLINE_PLAYTEST and not app.entering),"Enter activates focused Offline mode")
	if app.table_scene==null: quit(1); return
	var main: Control = app.table_scene
	var c: Node = main.tabletop.match_controller
	main.tabletop.persistence.matches = app.entry.saves
	check(c.playtest.local_playtest() and not main.has_node("Network"),"Offline creates no networking node or server client")
	check(c.model.players.has("local") and c.model.players.has("opponent"),"Both independent players exist offline")
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.SEA_GREEN)
	var store = preload("res://scripts/card_storage.gd").new(base.path_join("cards"))
	var record: Dictionary = store.save_card(image.save_png_to_buffer(),"Offline fixture",image.get_size())
	c.loader = preload("res://scripts/library_loader.gd").new(base.path_join("cards"))
	var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
	deck.cards = [{"card_id":record.metadata.card_id,"quantity":5}]
	c.load_deck(deck,false,"local")
	c.load_deck(deck,false,"opponent")
	c.draw_card("local")
	c.draw_card("opponent")
	check(c.model.players.local.hand.size()==1 and c.model.players.opponent.hand.size()==1,"Both offline decks draw independently")
	c.playtest.player_picker.item_selected.emit(1)
	check(c.active_hand_player()=="opponent" and c.hand.row.get_child_count()==1,"User controls opposite hand locally")
	c.open_inspection("opponent","library",true)
	check(c.contents_list.item_count==4,"Offline opponent search works locally")
	c.close_inspection()
	main.open_network_panel()
	check(not main.has_node("Network"),"Offline network menu does not initialize networking")
	main.tabletop.extras.choose("Return to Title")
	check(app.return_dialog.visible and app.table_scene==main,"Returning active table asks first")
	app.return_dialog.canceled.emit()
	app.return_dialog.hide()
	check(app.table_scene==main and c.model.players.local.hand.size()==1,"Canceled return preserves match")
	app.request_exit()
	check(app.exit_dialog.visible and app.exits==1,"Exit during active match asks first")
	app.exit_dialog.hide()
	app.request_return()
	app.return_dialog.custom_action.emit("discard")
	app.return_dialog.hide()
	await process_frame
	check(app.mode==app.Mode.TITLE and app.table_scene==null and title.visible,"Confirmed return clears table and shows title")
	title.buttons[0].pressed.emit()
	app.table_chosen(false)
	check(await wait_for(func() -> bool: return app.mode==app.Mode.ONLINE and not app.entering),"Online artwork enters existing mode")
	main = app.table_scene
	var network: Node = main.get_node("Network")
	check(network.window.visible and network.network.session.state=="disconnected","Existing room-code panel opens without automatic connection")
	check(network.rooms.signaling.service_url=="https://35-208-120-243.sslip.io:8787","Public service configuration preserved")
	network.window.hide()
	network.network.host_game(randi_range(33000,43000),"Mode guard","127.0.0.1")
	main.tabletop.shortcuts.toggle_playtest()
	check(app.mode==app.Mode.ONLINE and main.tabletop.shortcuts.mode_notice.visible,"Active connection blocks unsafe playtest switch")
	main.tabletop.shortcuts.mode_notice.hide()
	network.network.disconnect_session()
	await settle()
	main.tabletop.shortcuts.toggle_playtest()
	check(app.mode==app.Mode.OFFLINE_PLAYTEST and not main.has_node("Network"),"Existing P toggle updates explicit application mode and removes idle network")
	app.return_to_title()
	await process_frame
	app.queue_free()
	await process_frame
	print("CARDLINK 7.2: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
