extends SceneTree
var failures: int = 0
func check(value: bool, caption: String) -> void:
	print(("PASS " if value else "FAIL ")+caption)
	if not value: failures += 1
func _initialize() -> void: run.call_deferred()
func wait_time(seconds: float) -> void: await create_timer(seconds).timeout
func run() -> void:
	var apps: Array = []
	for i: int in 2:
		var app: Control = load("res://scenes/application_shell.tscn").instantiate()
		root.add_child(app)
		await wait_time(0.1)
		app.shared_settings.welcome.hide()
		app.custom_table_selected = i == 0
		await app.enter_mode(app.Mode.ONLINE)
		app.table_scene.get_node("Network").window.hide()
		app.table_scene.tabletop.custom_table.panel.hide()
		apps.append(app)
	var host: Node = apps[0].table_scene.get_node("Network").network
	var guest: Node = apps[1].table_scene.get_node("Network").network
	var a: Node = apps[0].table_scene.tabletop.custom_table
	var b: Node = apps[1].table_scene.tabletop.custom_table
	a.assets.directory = "user://host_boards"
	b.assets.directory = "user://guest_boards"
	var deck: Dictionary = a.add_component("shared_deck")
	a.add_component("hand","player_1")
	a.add_component("hand","player_2")
	var board: Dictionary = a.add_component("board")
	var image := Image.create(90,100,false,Image.FORMAT_RGB8)
	image.fill(Color(Time.get_ticks_msec()%255/255.0,0.2,0.5))
	var stored: Dictionary = a.assets.store(image.save_png_to_buffer())
	a.update_component(board.id,{"asset":stored.hash})
	var card_image := Image.create(750,1050,false,Image.FORMAT_RGB8)
	card_image.fill(Color.CORAL)
	var art: Dictionary = a.assets.store(card_image.save_png_to_buffer())
	var record: Dictionary = {"name":"Shared private sample","image_path":a.assets.path(art.hash),"metadata":{"card_id":"shared_sample"},"thumbnail":ImageTexture.create_from_image(card_image)}
	for i: int in 3:
		a.put_card(a.manager.spawn_definition(record,false).card,deck.id)
	check(host.host_game(29881,"Host","127.0.0.1"),"host local connection")
	check(guest.join_game("127.0.0.1",29881,"Guest"),"join local connection")
	await wait_time(2)
	check(host.session.state == "connected" and guest.session.state == "connected","two clients connected")
	check(b.enabled and b.document.components.size() == 4,"guest receives host table")
	check(b.row(deck.id).owner == "table","shared deck remains table owned")
	check(FileAccess.file_exists(b.assets.path(stored.hash)),"required board transferred and hash verified")
	b.update_component(deck.id,{"name":"Shared Draw Pile"})
	await wait_time(0.5)
	check(a.row(deck.id).name == "Shared Draw Pile","guest component edit reaches host")
	apps[0].table_scene.get_node("Network").gameplay.start_public()
	apps[1].table_scene.get_node("Network").gameplay.start_public()
	await wait_time(1)
	check(a.manager.match_controller.online() and b.manager.match_controller.online(),"custom public match starts")
	var remaining_id: String = a.orders[deck.id][2]
	check(a.draw(deck.id,"player_1"),"host draws shared card")
	check(b.draw(deck.id,"player_2"),"guest requests shared draw")
	await wait_time(1)
	check(a.manager.match_controller.model.players.local.hand.size() == 1,"host private hand contains its draw")
	check(b.manager.match_controller.model.players.local.hand.size() == 1,"guest private hand contains its draw")
	check(a.orders.get(deck.id,[]).size() == 1,"shared pile decremented exactly twice")
	check(b.manager.match_controller.card_by_id(remaining_id) == null,"remaining shared identity not replicated")
	check(b.pile_sync.remote_counts.get(deck.id) == 1,"remote pile count agrees")
	var discard: Dictionary = a.add_component("discard")
	await wait_time(0.3)
	var drawn: Control = b.manager.match_controller.card_by_id(b.manager.match_controller.model.players.local.hand[0])
	b.manager.match_controller.move_card(drawn,"battlefield")
	await wait_time(0.3)
	check(b.put_card(drawn,discard.id),"guest places public card into shared discard")
	await wait_time(0.5)
	check(a.orders.get(discard.id,[]).size() == 1 and b.orders.get(discard.id,[]).size() == 1,"shared discard membership agrees")
	var Doc = load("res://scripts/custom_table/table_document.gd")
	var protocol = load("res://scripts/custom_table/table_protocol.gd")
	var frame: Dictionary = {"type":"table_structure","protocol":1,"session_id":host.session.session_id,"kind":"table","data":{"table":a.document}}
	check(protocol.valid(frame),"bounded table envelope accepted")
	frame.data["library_order"] = ["private"]
	check(not protocol.valid(frame),"private extras rejected")
	var invalid: Dictionary = Doc.fresh()
	invalid.format = 99
	check(not Doc.validate(invalid).is_empty(),"incompatible template version rejected")
	host.disconnect_session()
	await wait_time(0.4)
	for app: Node in apps: app.dispose_table(); app.queue_free()
	await wait_time(0.2)
	print("CUSTOM NETWORK FAILURES: ",failures)
	quit(0 if failures == 0 else 1)
