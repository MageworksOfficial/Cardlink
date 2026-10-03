extends SceneTree
var failures: int = 0
func check(ok: bool, caption: String) -> void:
	print(("PASS " if ok else "FAIL ")+caption)
	if not ok: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var app: Control = load("res://scenes/application_shell.tscn").instantiate()
	root.add_child(app)
	for i: int in 10: await process_frame
	app.shared_settings.welcome.hide()
	app.choose_table(app.Mode.OFFLINE_PLAYTEST)
	app.table_chosen(true)
	for i: int in 40: await process_frame
	var b: Node = app.table_scene.tabletop.custom_table
	b.panel.hide()
	var c: Node = b.manager.match_controller
	var a: Dictionary = b.add_component("deck","player_1")
	var z: Dictionary = b.add_component("deck","player_2")
	var shared: Dictionary = b.add_component("shared_deck")
	b.set_primary(a.id)
	b.set_primary(z.id)
	var image := Image.create(75,105,false,Image.FORMAT_RGB8)
	image.fill(Color.BLUE)
	var stored: Dictionary = b.assets.store(image.save_png_to_buffer())
	var record: Dictionary = {"name":"Fixture","image_path":b.assets.path(stored.hash),"metadata":{"card_id":"draw_fixture"},"thumbnail":ImageTexture.create_from_image(image)}
	for pile: String in [a.id,z.id,shared.id]:
		for i: int in 4: b.put_card(b.manager.spawn_definition(record,false).card,pile)
	var actions: RefCounted = b.manager.shortcuts.dispatcher
	actions.execute("draw")
	check(c.model.players.local.hand.size() == 1 and b.orders[a.id].size() == 3,"D draws active P1 custom pile")
	actions.execute("end_turn")
	check(c.model.active_player == "opponent","N changes active player")
	actions.execute("draw")
	check(c.model.players.opponent.hand.size() == 1 and b.orders[z.id].size() == 3,"D draws active P2 custom pile")
	b.manager.perspective.switch_to("local",false,false)
	check(c.model.active_player == "opponent","perspective switch does not change turn")
	actions.execute("perspective")
	check(c.model.active_player == "opponent","V changes only perspective")
	b.manager.perspective.switch_to("local",false,false)
	actions.execute("draw")
	check(c.model.players.opponent.hand.size() == 2,"D follows turn despite opposite perspective")
	b.set_primary(shared.id)
	actions.execute("draw")
	check(c.model.players.opponent.hand.size() == 3 and b.orders[shared.id].size() == 3,"shared draw routes to active P2")
	actions.execute("end_turn")
	actions.execute("draw")
	check(c.model.players.local.hand.size() == 2 and b.orders[shared.id].size() == 2,"shared draw follows turn to P1")
	app.dispose_table()
	app.queue_free()
	for i: int in 8: await process_frame
	quit(0 if failures == 0 else 1)

