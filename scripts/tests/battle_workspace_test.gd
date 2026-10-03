extends SceneTree
var failures: int=0
func _initialize() -> void: run.call_deferred()
func check(v: bool,s: String) -> void:
	print(("PASS " if v else "FAIL ")+s)
	if not v: failures+=1
func settle() -> void:
	for i: int in 10: await process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(label+".png"))
func run() -> void:
	root.size=Vector2i(1152,760);root.gui_embed_subwindows=true
	var app: Control=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app);await settle();app.shared_settings.welcome.hide()
	await capture("title")
	app.open_deck_workspace();await settle()
	var w: Control=app.deck_workspace
	check(app.table_scene==null and w.deck_builder.standalone,"title Deck Builder without match")
	await capture("deck-workspace")
	var d: Control=w.deck_builder
	d.custom_import_button.pressed.emit();await settle()
	var importer: Window=w.get_node("CardImporter")
	check(importer.visible,"standalone Add Custom Card opens importer")
	var image := Image.create(750,1050,false,Image.FORMAT_RGB8);image.fill(Color.SEA_GREEN);image.save_png("user://Battle Fixture.png")
	importer.select_file("user://Battle Fixture.png");await importer.confirm_crop();await settle();importer.followup.pressed.emit();importer.hide()
	check(d.deck.cards.size()==1,"standalone import adds to current deck")
	d.name_input.text="Battle title fixture";d.save_current()
	check(d.saved.size()==1,"standalone deck saved")
	d.back_picker.open({});d.back_picker.color.color=Color("aabbcc");d.back_picker.color.color_changed.emit(Color("aabbcc"));await capture("back-picker");d.back_picker.chosen.emit(d.back_picker.config);d.back_picker.hide();d.save_current()
	check(d.deck.deck_back.color=="#aabbcc" and d.storage.list_decks()[0].data.deck_back.color=="#aabbcc","picker saved with deck")
	d.online_search_button.pressed.emit();await settle()
	var hub: Node=root.get_node("OptionalCardCatalog")
	check(hub.window.visible and hub.context_owner.get_ref()==d,"standalone existing Scryfall workflow opens")
	hub.window.hide();w.closed.emit();await settle()
	check(app.table_scene==null and not is_instance_valid(w),"return to title no leftover match")
	await app.enter_mode(app.Mode.OFFLINE_PLAYTEST);await settle()
	var m: Node=app.table_scene.tabletop
	var deck: Dictionary=m.controls.deck_storage.list_decks()[0].data
	var b: Node=m.custom_table;b.start_blank()
	var first: Dictionary=b.add_component("deck","player_1");var second: Dictionary=b.add_component("deck","player_1")
	check(b.load_deck(first.id,deck).is_empty(),"first custom pile loads saved back")
	var purple: Dictionary=deck.duplicate(true);purple.deck_back={"type":"preset","color":"#7645ac","preset":"Purple","asset":""}
	b.load_deck(second.id,purple)
	check(m.deck_backs.piles[first.id]!=m.deck_backs.piles[second.id],"multiple custom piles retain distinct backs")
	var structure: Dictionary=b.document.duplicate(true)
	b.draw(first.id,"player_1");m.create_token("Temporary","local","local");m.extras.create_counter(Vector2.ZERO)
	m.battle.reset.offline()
	check(b.document==structure and b.orders[first.id].size()==1 and b.orders[second.id].size()==1,"custom reset restores decks and preserves table structure")
	check(m.match_controller.model.players.local.hand.is_empty() and m.extras.counters.is_empty(),"custom reset clears hand and loose counters")
	if DisplayServer.get_name()!="headless":
		var object: Control=m.match_controller.card_by_id(b.orders[first.id][0]);m.match_controller.move_card(object,"battlefield");m.select_card(object)
		preload("res://scripts/battle/loyalty.gd").open(m);await settle();await capture("loyalty")
		for child: Node in m.get_children():
			if child is Window and child.title=="Loyalty": child.hide();child.queue_free()
		m.battle.reset.open();await settle();await capture("reset-confirmation");m.battle.reset.prompt.hide()
	app.dispose_table();app.queue_free();hub.queue_free();await settle()
	print("BATTLE WORKSPACE FAILURES ",failures);quit(0 if failures==0 else 1)
