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
	var standard: Control=b.manager.spawn_definition(record,false).card
	c.move_card(standard,"library",true,"local")
	var standard_order: Array=c.model.players.local.library.order.duplicate()
	var a_id: String=b.orders[a.id][0];var z_id: String=b.orders[z.id][0];var shared_id: String=b.orders[shared.id][0]
	mark(c,[a_id,z_id,shared_id,standard.state.match_instance_id])
	check(b.primary_for("player_1")==a.id,"Single owned pile is safe fallback")
	b.set_primary(a.id);b.set_primary(z.id);actions.execute("shuffle")
	check(not revealed(c,a_id) and revealed(c,z_id) and revealed(c,shared_id),"S shuffles only P1 primary and clears its reveal")
	check(c.model.players.local.library.order==standard_order and revealed(c,standard.state.match_instance_id),"Custom S never shuffles Standard library")
	mark(c,[a_id]);actions.execute("perspective");actions.execute("shuffle")
	check(c.model.active_player=="local" and not revealed(c,a_id) and revealed(c,z_id),"V changes view; S still follows P1 turn")
	mark(c,[a_id]);actions.execute("end_turn");actions.execute("shuffle")
	check(c.model.active_player=="opponent" and not revealed(c,z_id) and revealed(c,a_id),"N then S shuffles P2 primary")
	b.set_primary(shared.id);mark(c,[a_id,z_id,shared_id]);actions.execute("shuffle")
	check(not revealed(c,shared_id) and revealed(c,a_id) and revealed(c,z_id),"Explicit Shared Draw source shuffles only shared pile")
	var extra: Dictionary=b.add_component("deck","player_2")
	for row: Dictionary in b.document.components: row.linked_pile=""
	var before: int=c.model.history.size();actions.execute("shuffle")
	check(b.primary_for("player_2").is_empty() and c.model.history.size()==before and b.manager.controls.status.text.contains("Choose a pile to shuffle"),"Ambiguous source never guesses or records a shuffle")
	check(not b.draw_active() and b.manager.controls.status.text.contains("Choose a pile to draw"),"D shares the same ambiguity guard")
	b.editor.context_menu(a.id);b.editor.context.hide();b.editor.context_action(8)
	check(not revealed(c,a_id) and revealed(c,z_id),"Context Shuffle targets exact pile independent of turn")
	b.set_primary(extra.id);check(b.shuffle_active(),"Assigned empty pile can shuffle safely")
	var private_leak: bool=false
	for event: Dictionary in c.model.history:
		if event.kind=="shuffle" and (str(event).contains("PRIVATE TEST IDENTITY") or str(event).contains(a_id)): private_leak=true
	check(not private_leak,"Shuffle history contains no hidden identities or order")
	app.dispose_table();app.queue_free()
	for i: int in 8: await process_frame
	print("QOL SHUFFLE FAILURES: ",failures);quit(0 if failures==0 else 1)
