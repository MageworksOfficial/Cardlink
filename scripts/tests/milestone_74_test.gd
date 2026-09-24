extends "res://scripts/tests/milestone_6b_test.gd"
class TestShell extends "res://scripts/application_shell.gd":
	func exit_now() -> void: dispose_table()
func new_app(base: String) -> Control:
	var app: Control = TestShell.new()
	app.preferences = preload("res://scripts/frontend/player_preferences.gd").new(base.path_join("profile.cfg"))
	app.preferences.set_flag("welcome_seen",true)
	app.bindings = preload("res://scripts/usability/input_bindings.gd").new(base.path_join("bindings.cfg"))
	app.table_preferences = preload("res://scripts/usability/table_preferences.gd").new(base.path_join("table.cfg"))
	app.recovery_directory = base.path_join("recovery")
	app.privacy_path = base.path_join("privacy.cfg")
	root.add_child(app)
	app.entry.saves.directory = base.path_join("matches")
	app.entry.decks.directory = base.path_join("decks")
	app.entry.deck_preferences = preload("res://scripts/usability/deck_preferences.gd").new(base.path_join("deck_prefs.cfg"))
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return app
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var app: Control = new_app(base)
	await process_frame
	check(app.bindings.caption("draw") == "D","Central defaults load")
	app.shared_settings.key_bindings.popup_centered()
	check(app.shared_settings.key_bindings.visible,"Key Bindings screen opens")
	var keys: Window = app.shared_settings.key_bindings
	keys.propose("draw",KEY_G)
	check(keys.conflict_dialog.visible and keys.conflict_dialog.dialog_text.contains("Graveyard"),"Duplicate key warns with action name")
	keys.conflict_dialog.canceled.emit()
	keys.conflict_dialog.hide()
	check(app.bindings.keys.draw == KEY_D and app.bindings.keys.graveyard == KEY_G,"Cancel keeps original mappings")
	keys.propose("draw",KEY_G)
	keys.conflict_dialog.confirmed.emit()
	keys.conflict_dialog.hide()
	check(app.bindings.keys.draw == KEY_G and app.bindings.keys.graveyard == 0,"Replace Existing clears conflicting action")
	var restored = preload("res://scripts/usability/input_bindings.gd").new(app.bindings.path)
	check(restored.keys.draw == KEY_G,"Rebindings persist across reload")
	check(app.shared_settings.controls_text.text.contains("G — Draw"),"Controls Help updates immediately")
	keys.propose("draw",KEY_D)
	check(app.bindings.keys.draw == KEY_D,"Reset individual binding")
	app.bindings.assign("shuffle",0)
	check(app.bindings.caption("shuffle") == "Unbound","Clear binding")
	app.bindings.reset_all()
	check(app.bindings.keys.shuffle == KEY_S and app.bindings.keys.graveyard == KEY_G,"Reset All restores defaults")
	keys.capture_key("draw")
	var capture := InputEventKey.new()
	capture.keycode = KEY_J
	capture.pressed = true
	keys.handle_key(capture)
	check(app.bindings.keys.draw == KEY_J,"Key capture accepts physical key events")
	app.bindings.reset_all()
	keys.close()
	app.shared_settings.open()
	check(app.title_screen.settings.visible,"Scrollable Settings opens without errors")
	await screenshot(base,"settings")
	app.title_screen.settings.hide()
	app.entry.offline()
	check(app.entry.deck_pickers.size() == 2,"Pre-match setup includes two decks")
	await screenshot(base,"setup")
	app.entry.window.hide()
	app.entry.starting_life = 30
	app.entry.start(app.Mode.OFFLINE_PLAYTEST)
	check(await wait_for(func() -> bool: return not app.entering and app.table_scene != null),"Offline entry still works")
	var table: Node = app.table_scene.tabletop
	var c: Node = table.match_controller
	table.persistence.matches = app.entry.saves
	check(table.cards.is_empty(),"Clean startup has no Godot prototype/test objects")
	check(table.zones.size() == 6,"Both sides have graveyard exile and leader zones")
	check(c.pile_view.position.y > c.opponent_pile.position.y,"Local side is nearest; opponent mirrored")
	check(c.model.players.local.life == 30 and c.model.players.opponent.life == 30,"Starting life config applies to both offline players")
	check(not table.life_display.visible,"Oversized debug player summary stays hidden")
	var zone: Control = c.zone_for("graveyard","local")
	var original: Vector2 = zone.position
	zone.position = Vector2(500,500)
	table.view.zoom_by(1.2)
	table.view.reset_view()
	check(zone.position == Vector2(500,500),"Reset View changes only camera")
	table.organization.reset_layout()
	check(zone.position == original,"Reset Table Layout restores zone arrangement")
	table.layout.set_edit_mode(true)
	table.organization.snap_grid = true
	check(table.organization.snap(Vector2(43,67),Vector2(100,100)) == Vector2(40,60),"Grid snapping aligns layout objects")
	table.organization.snap_grid = false
	table.organization.snap_edge = true
	check(table.organization.snap(Vector2(45,600),Vector2(100,100)).x == 20,"Edge snapping aligns to margin")
	table.layout.set_edit_mode(false)
	check(table.organization.snap(Vector2(43,67),Vector2(100,100)) == Vector2(43,67),"Snapping is disabled in normal gameplay")
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.SKY_BLUE)
	var store = preload("res://scripts/card_storage.gd").new(base.path_join("cards"))
	store.save_card(image.save_png_to_buffer(),"Blue test card",image.get_size())
	c.loader = preload("res://scripts/library_loader.gd").new(base.path_join("cards"))
	var record: Dictionary = c.loader.load_records()[0]
	var card: Control = table.spawn_definition(record).card
	var id: String = card.state.match_instance_id
	var second: Control = table.spawn_definition(record).card
	card.position = Vector2(600,600)
	second.position = Vector2(740,600)
	table.selection.select_rect(Rect2(590,590,280,160))
	check(table.selection.ids.size() == 2,"Marquee selects multiple cards")
	check(card.is_selected and second.is_selected,"Every selected card highlights")
	await process_frame
	for node: Node in table.get_children():
		if node.get_script() == preload("res://scripts/usability/table_feedback.gd"):
			check(node.selected.text == "2 selected","Multi-selection count is visible")
	var positions: Array = [card.position,second.position]
	table.organization.reset_layout()
	check(card.position == positions[0] and second.position == positions[1],"Layout reset leaves card positions untouched")
	table.shortcuts.dispatcher.execute("graveyard")
	await process_frame
	check(c.model.players.local.graveyard.size() == 2,"Context-aware G moves selected cards to graveyard")
	table.shortcuts.dispatcher.execute("graveyard")
	check(c.contents.visible and c.contents_list.item_count == 2,"G without selection opens image gallery")
	c.contents_query.text = "Blue"
	c.refresh_contents()
	check(c.contents_list.get_item_icon(0) != null,"Public zone gallery uses card art")
	c.close_inspection()
	table.select_card(card)
	table.shortcuts.dispatcher.execute("exile")
	await process_frame
	check(card.state.current_zone == "exile","Context-aware E moves selected card")
	table.shortcuts.dispatcher.execute("exile")
	check(c.contents_list.item_count == 1,"E opens Exile gallery")
	c.close_inspection()
	# Undo is a bounded disconnected transaction, preserving private information barriers.
	table.undo.invalidate()
	table.undo.begin("Life change")
	c.change_life("local",-5)
	table.undo.finish()
	table.undo.undo()
	check(c.model.players.local.life == 30,"Undo restores life change")
	card = c.card_by_id(id)
	var original_point: Vector2 = card.position
	table.undo.begin("Move card")
	card.position += Vector2(50,40)
	card.state.position = card.position
	table.undo.finish()
	table.undo.undo()
	card = c.card_by_id(id)
	check(card.position == original_point,"Undo restores card movement")
	table.undo.begin("Life")
	c.change_life("local",-1)
	table.undo.finish()
	c.shuffle_library()
	check(table.undo.entries.is_empty(),"Shuffle clears undo and cannot be crossed")
	for i: int in 20:
		table.undo.begin("Life")
		c.change_life("local",1)
		table.undo.finish()
	check(table.undo.entries.size() == 15,"Undo history is bounded")
	card = c.card_by_id(id)
	c.move_card(card,"hand")
	for mode: String in ["Straight","Overlap","Fan"]:
		app.table_preferences.put("hand_layout",mode)
		await process_frame
		check(c.hand.row.mode == mode and c.hand.row.get_child_count() == 1,"Hand presentation: "+mode)
	app.table_preferences.put("hand_scale",1.2)
	await process_frame
	check(is_equal_approx(c.hand.row.card_scale,1.2),"Hand card scale applies")
	for mode: String in ["Straight","Overlap","Compact"]:
		app.table_preferences.put("opponent_layout",mode)
		check(c.opponent_hand.layout_mode_id == mode,"Opponent layout: "+mode)
	app.table_preferences.put("theme","Green Felt")
	check(table.world.table_color == Color("173c2f"),"Code-generated table themes apply")
	var prefs = preload("res://scripts/usability/deck_preferences.gd").new(base.path_join("recent.cfg"))
	for i: int in 12: prefs.used("deck"+str(i))
	check(prefs.recent.size() == 8 and prefs.recent[0] == "deck11","Recent decks are bounded references")
	prefs.toggle("deck11")
	check(preload("res://scripts/usability/deck_preferences.gd").new(prefs.path).favorites.has("deck11"),"Favorite deck persists")
	var another = preload("res://scripts/usability/deck_preferences.gd").new(prefs.path)
	another.toggle("deck10")
	prefs.used("deck8")
	check(preload("res://scripts/usability/deck_preferences.gd").new(prefs.path).favorites.has("deck10"),"Loading a deck preserves favorites changed by another UI")
	table.controls.open_panel("Counter")
	var key := InputEventKey.new()
	key.keycode = KEY_N
	key.pressed = true
	var turn: int = c.model.turn_number
	table.shortcuts.handle_key(key)
	check(c.model.turn_number == turn,"Hotkeys do not fire through modal editors")
	table.controls.close_panels()
	table.shortcuts.handle_key(key)
	check(c.model.turn_number == turn+1,"N ends turn through existing action")
	await extended_checks(app,table,c,base)
	var saved: Dictionary = table.persistence.save_match("Manual untouched")
	var original_save: String = FileAccess.get_file_as_string(saved.path)
	app.recovery.save_recovery()
	check(not app.recovery.saved_path.is_empty(),"Dedicated recovery snapshot is written")
	check(FileAccess.get_file_as_string(saved.path) == original_save,"Autosave leaves named saves intact")
	app.recovery.timer.wait_time = 0.05
	app.recovery.timer.start()
	c.change_life("local",1)
	await create_timer(0.15).timeout
	app.recovery.timer.stop()
	var recovery_record: Dictionary = app.recovery.storage.read_record(app.recovery.saved_path).record.data
	check(recovery_record.players[0].life == c.model.players.local.life,"Periodic timer saves current state")
	check(recovery_record.recovery_metadata.source_opponent_mode == "local_playtest","Recovery records original mode metadata")
	var recovered_life: int = c.model.players.local.life
	var recovered_cards: int = table.cards.size()
	var recovered_counters: int = table.extras.counters.size()
	var recovered_hand: Array = c.model.players.local.hand.duplicate()
	app.queue_free() # Simulate interrupted process: no intentional departure cleanup.
	await process_frame
	app = new_app(base)
	await process_frame
	check(app.recovery.prompt.visible,"Next launch offers recovery")
	app.dispose_table()
	check(not app.recovery.storage.list_records().is_empty(),"Leaving title never discards an unhandled recovery copy")
	app.recovery.recover()
	await wait_for(func() -> bool: return not app.entering and app.table_scene != null)
	check(app.table_scene.tabletop.match_controller.model.players.local.life == recovered_life,"Recovery restores table state")
	check(app.table_scene.tabletop.cards.size() == recovered_cards,"Recovery restores normal cards and tokens")
	check(app.table_scene.tabletop.extras.counters.size() == recovered_counters,"Recovery restores standalone counters")
	check(app.table_scene.tabletop.match_controller.model.players.local.hand == recovered_hand,"Recovery preserves hand instance identities")
	check(not app.table_scene.has_node("Network"),"Recovery never automatically connects online")
	app.return_to_title()
	check(app.recovery.storage.list_records().is_empty(),"Intentional departure clears recovery copy")
	app.queue_free()
	await process_frame
	print("CARDLINK 7.4: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func screenshot(base: String, name: String) -> void:
	if not OS.get_cmdline_user_args().has("capture"): return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(base.path_join(name+".png"))
func key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
func extended_checks(app: Control, table: Node, c: Node, base: String) -> void:
	app.shared_settings.open()
	check(table.shortcuts.blocked(),"Settings suppresses tabletop shortcuts")
	app.title_screen.settings.hide()
	var edit := LineEdit.new()
	app.table_scene.add_child(edit)
	edit.grab_focus()
	var turn: int = c.model.turn_number
	table.shortcuts.handle_key(key_event(KEY_N))
	check(c.model.turn_number == turn,"Typing blocks new shortcuts")
	edit.release_focus()
	edit.queue_free()
	var layout: bool = table.layout.edit_mode
	table.shortcuts.handle_key(key_event(KEY_L))
	check(table.layout.edit_mode != layout,"L dispatches through central bindings")
	table.shortcuts.handle_key(key_event(KEY_L))
	var zoom: float = table.view.zoom
	table.shortcuts.handle_key(key_event(KEY_SPACE))
	check(table.view.zoom >= 0.7,"Space centers local side")
	table.shortcuts.handle_key(key_event(KEY_R))
	check(is_equal_approx(table.view.zoom,zoom),"R resets useful default view")
	table.selection.clear()
	table.shortcuts.handle_key(key_event(KEY_C))
	check(table.extras.counters.size() == 1 and table.extras.counter_window.visible,"C creates a standalone counter when nothing selected")
	table.extras.counter_value.value = 8
	table.extras.save_counter()
	table.extras.counter_window.hide()
	await process_frame
	table.undo.invalidate()
	var counter: Control = table.extras.counters[0]
	table.extras.open_counter(counter)
	table.extras.counter_value.value = 12
	table.extras.save_counter()
	table.extras.counter_window.hide()
	table.undo.finish()
	table.undo.undo()
	check(table.extras.counters[0].value == 8,"Undo restores standalone counter edit")
	table.selection.clear()
	table.undo.invalidate()
	table.shortcuts.handle_key(key_event(KEY_T))
	check(table.extras.token_editor.visible,"T opens Create Token with no selection")
	var editor: Window = table.extras.token_editor
	editor.caption.text = "Classroom Wolf"
	editor.power.text = "2"
	editor.toughness.text = "2"
	editor.save_token()
	table.undo.finish()
	check(table.selected_card.state.is_token,"Token editor creates a token")
	var token_id: String = table.selected_card.state.match_instance_id
	table.undo.undo()
	check(c.card_by_id(token_id) == null,"Undo removes newly created token")
	var token: Control = table.create_token("Wolf","local","local","","2","2").card
	table.undo.finish()
	table.select_card(token)
	table.shortcuts.handle_key(key_event(KEY_C))
	check(table.controls.panels.Counter.visible,"C opens attached counter actions when a card is selected")
	table.controls.close_panels()
	var before_count: int = table.cards.size()
	table.shortcuts.handle_key(key_event(KEY_T))
	check(table.cards.size() == before_count+1 and table.selected_card.state.match_instance_id != token.state.match_instance_id,"T duplicates selected token with unique identity")
	table.shortcuts.handle_key(key_event(KEY_DELETE))
	check(table.cards.size() == before_count,"Delete destroys selected token")
	table.selection.clear()
	table.shortcuts.handle_key(key_event(KEY_H))
	check(c.hand_open and not c.hands_hidden,"H opens hand")
	table.controls.close_panels()
	table.shortcuts.handle_key(key_event(KEY_B))
	check(c.contents.visible and c.knowledge_view,"B opens known-library viewer")
	c.close_inspection()
	table.shortcuts.handle_key(key_event(KEY_M))
	check(table.extras.history_window.visible,"M opens history")
	table.extras.close_all()
	var save_key := key_event(KEY_S)
	save_key.ctrl_pressed = true
	table.shortcuts.handle_key(save_key)
	check(table.controls.panels.Match.visible,"Ctrl+S opens match save controls")
	table.controls.close_panels()
	var card: Control = c.card_by_id(c.model.players.local.hand[0])
	var id: String = card.state.match_instance_id
	c.move_card(card,"graveyard")
	card.state.face_down = true
	card.state.visibility = "face_down_public"
	c.open_public_zone("local","graveyard")
	var hidden_index: int = -1
	for i: int in c.contents_list.item_count:
		if c.contents_list.get_item_metadata(i) == id: hidden_index = i
	check(hidden_index >= 0 and c.contents_list.get_item_text(hidden_index).contains("Hidden card"),"Public gallery masks face-down identities")
	c.contents_query.text = "Blue"
	c.refresh_contents()
	var leaked: bool = false
	for i: int in c.contents_list.item_count: leaked = leaked or c.contents_list.get_item_metadata(i) == id
	check(not leaked,"Gallery search does not disclose hidden names")
	c.close_inspection()
	card.state.face_down = false
	card.state.visibility = "public"
	c.move_card(card,"hand")
	table.undo.invalidate()
	c.change_life("local",-1)
	table.undo.finish()
	c.toggle_hand_reveal(card)
	check(table.undo.entries.is_empty(),"Reveal is an undo barrier")
	c.change_life("local",-1)
	table.undo.finish()
	table.extras.tools.roll(1,6)
	check(table.undo.entries.is_empty(),"Dice results cannot be crossed by undo")
	var anchor: Control = c.hearts.hearts.local.get_parent()
	anchor.position = Vector2(33,500)
	var layout_data: Dictionary = table.layout.capture()
	anchor.position = Vector2(99,499)
	table.layout.apply(layout_data)
	check(anchor.position == Vector2(33,500),"Layout presets preserve compact life anchors")
	c.hearts.editing = "local"
	c.hearts.life_input.value = 27
	c.hearts.life_editor.confirmed.emit()
	check(c.model.players.local.life == 27,"Direct life editing uses existing state path")
	table.organization.reset_layout()
	table.select_card(token)
	table.controls.status.text = "Token created"
	table.extras._process(0)
	check(table.extras.toast.visible and table.extras.toast.text == "Token created","Status messages appear without modal")
	table.extras._process(6.1)
	check(not table.extras.toast.visible,"Status messages expire")
	app.shared_settings.no_again.button_pressed = true
	app.shared_settings.welcome.confirmed.emit()
	check(app.preferences.get_flag("hide_welcome"),"Don't show again persists")
	await screenshot(base,"table")
	app.shared_settings.key_bindings.popup_centered()
	await screenshot(base,"bindings")
	app.shared_settings.key_bindings.close()
