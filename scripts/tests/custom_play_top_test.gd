extends SceneTree
var failures: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, caption: String) -> void:
	print(("PASS " if ok else "FAIL ")+caption)
	if not ok: failures+=1
func revealed(c: Node, id: String) -> bool: return c.card_by_id(id).state.custom_metadata.get("public_reveal",false)
func mark(c: Node, ids: Array) -> void:
	for id: String in ids: c.visibility.set_public_reveal(c.card_by_id(id).state,true)
func run() -> void:
	var app: Control=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app)
	for i: int in 10: await process_frame
	app.shared_settings.welcome.hide();app.choose_table(app.Mode.OFFLINE_PLAYTEST);app.table_chosen(true)
	for i: int in 40: await process_frame
	var b: Node=app.table_scene.tabletop.custom_table
	var c: Node=b.manager.match_controller
	var actions: RefCounted=b.manager.shortcuts.dispatcher
	actions.execute("shuffle")
	check(b.manager.controls.status.text.contains("No draw pile"),"S with no source is safe and informative")
	var a: Dictionary=b.add_component("deck","player_1")
	var z: Dictionary=b.add_component("deck","player_2")
	var shared: Dictionary=b.add_component("shared_deck")
	var image := Image.create(75,105,false,Image.FORMAT_RGB8);image.fill(Color.BLUE)
	var stored: Dictionary=b.assets.store(image.save_png_to_buffer())
	var record: Dictionary={"name":"PRIVATE TEST IDENTITY","image_path":b.assets.path(stored.hash),"metadata":{"card_id":"private_fixture"},"thumbnail":ImageTexture.create_from_image(image)}
	for pile: String in [a.id,z.id,shared.id]:
		for i: int in 3: b.put_card(b.manager.spawn_definition(record,false).card,pile)

	b.set_primary(a.id)
	var first: String=b.orders[a.id][0]
	c.library_actions.enter_face_down=true
	actions.execute("play_top")
	check(b.orders[a.id].size()==2 and c.card_by_id(first).state.current_zone=="battlefield","Custom Ctrl+D plays from active primary pile")
	check(c.card_by_id(first).state.face_down,"Custom top card enters face down")
	check(b.orders[z.id].size()==3,"Custom placement leaves other player's pile untouched")
	app.queue_free();await process_frame
	quit(0 if failures==0 else 1)
