extends "res://scripts/tests/milestone_6b_test.gd"
class TestShell extends "res://scripts/application_shell.gd":
	var exits: int = 0
	func exit_now() -> void: exits += 1
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	var app: Control = TestShell.new()
	app.preferences = preload("res://scripts/frontend/player_preferences.gd").new(base.path_join("profile.cfg"))
	app.preferences.set_flag("welcome_seen",true)
	app.privacy_path = base.path_join("privacy.cfg")
	app.recovery_directory = OS.get_cmdline_user_args()[0].path_join("recovery")
	root.add_child(app)
	app.entry.saves.directory = base.path_join("matches")
	app.entry.decks.directory = base.path_join("decks")
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.SKY_BLUE)
	var storage = preload("res://scripts/card_storage.gd").new(base.path_join("cards"))
	var record: Dictionary = storage.save_card(image.save_png_to_buffer(),"Resume fixture",image.get_size())
	var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
	deck.cards = [{"card_id":record.metadata.card_id,"quantity":3}]
	deck.deck_name = "Sample Deck"
	app.entry.decks.save_deck(deck)
	app.entry.offline()
	check(app.entry.deck_pickers[0].item_count == 2,"Saved decks appear in offline entry")
	for picker: OptionButton in app.entry.deck_pickers:
		picker.select(1)
		app.entry.pending_decks.append(picker.get_item_metadata(1))
	app.entry.start(app.Mode.OFFLINE_PLAYTEST)
	# Substitute isolated fixture storage before deferred table setup finishes.
	await wait_for(func() -> bool: return app.table_scene != null and app.table_scene.tabletop.match_controller != null)
	app.table_scene.tabletop.match_controller.loader = preload("res://scripts/library_loader.gd").new(base.path_join("cards"))
	await wait_for(func() -> bool: return not app.entering)
	var table: Node = app.table_scene.tabletop
	var c: Node = table.match_controller
	table.persistence.matches = app.entry.saves
	check(c.model.players.local.library.order.size() == 3 and c.model.players.opponent.library.order.size() == 3,"Entry loads both selected decks through existing loader")
	check(app.departure.dirty(),"Loading decks counts as meaningful unsaved progress")
	var snapshot: Dictionary = table.persistence.capture_match()
	snapshot.players[1].display_name = "Verox"
	snapshot.erase("local_tabletop")
	snapshot.cards[0].image_path = base.path_join("missing_image.png")
	var saved: Dictionary = app.entry.saves.save_record(snapshot,"Older Online Match")
	var original: String = FileAccess.get_file_as_string(saved.path)
	app.return_to_title()
	await process_frame
	app.entry.resume_match()
	app.entry.resume_selected()
	await wait_for(func() -> bool: return not app.entering and app.table_scene != null)
	table = app.table_scene.tabletop
	c = table.match_controller
	table.persistence.matches = app.entry.saves
	check(table.cards.size() == snapshot.cards.size() and not app.table_scene.has_node("Network"),"Older online save restores as offline local copy")
	check(table.controls.status.text.contains("placeholders"),"Missing image is explained and uses a placeholder")
	app.presenter.refresh()
	check(c.model.players.opponent.display_name == "Verox","Offline copy preserves saved opponent nickname")
	check(FileAccess.get_file_as_string(saved.path) == original,"Resume never rewrites source save")
	c.change_life("local",-1)
	app.request_exit()
	check(app.exit_dialog.visible and app.exits == 0,"Unsaved Exit offers save/discard/cancel")
	app.departure.save_name.text = ""
	app.exit_dialog.confirmed.emit()
	check(app.table_scene != null and app.exit_dialog.visible and app.exits == 0,"Failed save keeps match and exit prompt open")
	app.departure.save_name.text = "Recovered Copy"
	app.exit_dialog.confirmed.emit()
	check(app.exits == 1 and app.entry.saves.list_records().size() == 2,"Save & Exit writes a separate resumed copy")
	check(FileAccess.get_file_as_string(saved.path) == original,"Saving resumed copy preserves original online save")
	app.dispose_table()
	app.queue_free()
	await process_frame
	print("FRONTEND RESUME SAFETY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
