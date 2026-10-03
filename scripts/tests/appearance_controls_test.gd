extends "res://scripts/tests/milestone_6b_test.gd"
func click(point: Vector2, down: bool=true) -> InputEventMouseButton:
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=point;return e
func run() -> void:
	var base: String=OS.get_cmdline_user_args()[0]
	var app: Control=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app)
	for i: int in 10: await process_frame
	app.shared_settings.welcome.hide();await app.enter_mode(app.Mode.OFFLINE_PLAYTEST)
	for i: int in 10: await process_frame
	var m: Node=app.table_scene.tabletop;var a: Node=m.appearance
	app.function_search.build_entries()
	for query: String in ["sleeve","back cover","playmat","floor image"]:
		app.function_search.query.text=query;app.function_search.filter_entries();check(app.function_search.results.item_count>0,"Function alias: "+query)
	var key:=InputEventKey.new();key.keycode=KEY_B;key.ctrl_pressed=true;key.pressed=true
	m.layout.set_edit_mode(true);m.shortcuts.handle_key(key);check(a.editing,"Ctrl+B enables background editing")
	var config: Dictionary=a.Config.defaults();config.type="color";config.color="#112233";config.size=[500,300];config.position=[100,100];config.locked=false;a.apply(config)
	a.input(click(Vector2(200,200)));var motion:=InputEventMouseMotion.new();motion.position=Vector2(240,230);a.input(motion);a.input(click(motion.position,false))
	check(a.layer.position==Vector2(140,130),"World-space background dragging")
	a.input(click(Vector2(640,430)));motion.position=Vector2(740,490);a.input(motion);a.input(click(motion.position,false))
	check(a.layer.size==Vector2(600,360),"Corner resize preserves aspect")
	var original: Dictionary=a.background.duplicate(true);m.view.zoom_by(0.5);m.view.pan+=Vector2(35,24);m.view.apply_view();m.perspective.switch_to("opponent",false,false)
	check(a.background==original,"Zoom/pan/perspective preserve neutral background transform")
	m.perspective.switch_to("local",false,false)
	config=a.background.duplicate(true);config.locked=true;a.apply(config)
	check(not a.input(click(Vector2(200,200))),"Locked background ignores pointer drag")
	m.layout.set_edit_mode(false);await process_frame
	check(not a.editing and a.layer.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Play mode protects normal card interaction")
	a.reset_background();check(a.background.type=="default","Reset background restores default")
	var missing: Dictionary=a.Config.defaults();missing.type="image";missing.asset="a".repeat(64);a.apply(missing)
	check(a.assets.texture(missing.asset)==null and a.background.color=="#152d40","Missing background uses fallback color")
	var b: Node=m.custom_table;b.start_blank();var pile: Dictionary=b.add_component("deck","player_1")
	var back: Dictionary={"type":"color","color":"#56318c","preset":"","asset":""}
	check(a.sleeves.apply_back(pile.id,back) and m.deck_backs.pile_config(pile.id)==back,"Custom empty pile match-only back")
	b.editor.context_menu(pile.id);check(b.editor.context.get_item_index(9)>=0,"Custom pile context contains Change Deck Back");b.editor.context.hide()
	a.sleeves.open();check(a.sleeves.picker.visible,"Single custom pile opens picker")
	a.sleeves.picker.hide()
	var image:=Image.create(75,105,false,Image.FORMAT_RGBA8);image.fill(Color.CORAL)
	var cards=preload("res://scripts/card_storage.gd").new(base.path_join("cards"));var stored: Dictionary=cards.save_card(image.save_png_to_buffer(),"Sleeve Fixture",image.get_size())
	m.match_controller.loader=preload("res://scripts/library_loader.gd").new(base.path_join("cards"))
	var deck: Dictionary=preload("res://scripts/deck_storage.gd").new_deck();deck.cards=[{"card_id":stored.metadata.card_id,"quantity":2}]
	m.controls.deck_storage.directory=base.path_join("decks");var saved: Dictionary=m.controls.deck_storage.save_deck(deck)
	check(b.load_deck(pile.id,deck).is_empty(),"Custom pile loads identified saved deck")
	var card: Control=m.match_controller.card_by_id(b.orders[pile.id][0]);m.match_controller.move_card(card,"battlefield")
	check(a.sleeves.apply_back(pile.id,back,true),"Save With Deck works for a custom pile")
	check(card.state.custom_metadata.deck_back==back,"Custom sleeve follows an already-played card")
	check(JSON.parse_string(FileAccess.get_file_as_string(saved.path)).deck_back==back,"Custom pile sleeve saved persistently")
	image.save_png(base.path_join("sleeve.png"));var imported: Dictionary=preload("res://scripts/battle/deck_back.gd").import_image(base.path_join("sleeve.png"))
	var image_back: Dictionary={"type":"image","color":"#56318c","preset":"","asset":imported.hash}
	check(a.sleeves.apply_back(pile.id,image_back) and card.state.custom_metadata.deck_back==image_back,"In-match custom image uses managed back asset")
	var second: Dictionary=b.add_component("deck","player_2");a.sleeves.open();check(not a.sleeves.picker.visible,"Multiple custom piles do not guess")
	app.queue_free();await process_frame
	print("APPEARANCE CONTROLS: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
