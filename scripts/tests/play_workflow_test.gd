extends SceneTree
const Store = preload("res://scripts/card_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
const Decks = preload("res://scripts/deck_storage.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", caption)
func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, pressed: bool = true, ctrl: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = point
	e.button_index = button
	e.pressed = pressed
	e.ctrl_pressed = ctrl
	return e
func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e
func route(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var image := Image.create(750, 1050, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var store := Store.new(base.path_join("cards"))
	var a: Dictionary = store.save_card(image.save_png_to_buffer(), "Selection card", image.get_size())
	var deck: Dictionary = Decks.new_deck()
	deck.cards = [{"card_id": a.metadata.card_id, "quantity": 18}]
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var t: Node = main.tabletop
	var c: Node = t.match_controller
	c.loader = Loader.new(base.path_join("cards"))
	c.load_deck(deck, false)
	c.load_deck(deck, false, "opponent")
	var s: Control = t.selection


	var one: Control=c.card_by_id(c.pile.order[0])
	var two: Control=c.card_by_id(c.pile.order[1])
	c.move_card(one,"hand");c.move_card(two,"hand")
	c.hand_open=true;c.refresh()
	s.toggle(one);s.toggle(two)
	var ids: Array=c.library_actions.hand_drag_ids(one.state.match_instance_id)
	check(ids.size()==2,"Selected hand drag contains both cards")
	c.library_actions.enter_face_down=true
	t.world._drop_data(Vector2(400,400),{"cardlink_instance":one.state.match_instance_id,"cardlink_instances":ids})
	check(one.state.current_zone=="battlefield" and two.state.current_zone=="battlefield","Group hand drop plays both cards")
	check(one.state.face_down and two.state.face_down,"Group hand drop enters face down")
	check(one.position!=two.position,"Played cards spread into separate positions")
	c.library_actions.enter_face_down=false
	var next: Control=c.card_by_id(c.pile.order[0])
	var before: int=c.pile.order.size()
	t.shortcuts.dispatcher.execute("play_top")
	check(c.pile.order.size()==before-1 and next.state.current_zone=="battlefield","Ctrl+D action places one top card")
	check(not next.state.face_down and next.position==c.library_actions.beside_library("local"),"Top card enters face up beside library")
	var binding:=InputEventKey.new();binding.keycode=KEY_D;binding.ctrl_pressed=true;binding.pressed=true
	check(t.shortcuts.bindings.action_for(binding)=="play_top","Ctrl+D resolves independently of D")
	var original: Array=c.pile.order.duplicate()
	c.review.open_review("local",3,true,true)
	c.review.top_list.select(1);c.review.to_bottom()
	c.review.confirm_review()
	check(c.card_by_id(original[1]).state.current_zone=="graveyard","Surveil moves chosen card to graveyard")
	check(c.pile.order[0]==original[0] and c.pile.order[1]==original[2] and c.pile.order.slice(2)==original.slice(3),"Surveil preserves kept and remaining library order")
	original=c.pile.order.duplicate()
	c.review.open_review("local",2,true,true);c.review.to_bottom();c.review.cancel()
	check(c.pile.order==original,"Cancel Surveil leaves library unchanged")
	c.review.open_review("local",2,true,true);c.draw_card();var changed: Array=c.pile.order.duplicate();c.review.confirm_review()
	check(c.pile.order==changed and c.review.visible,"Stale Surveil refuses to commit")
	c.review.cancel()
	c.move_card(one,"hand");c.move_card(two,"hand");c.refresh();s.clear();s.toggle(one);s.toggle(two)
	c.hand_window.open_hand();await process_frame
	c.hand_window.begin_drag(one.state.match_instance_id)
	check(s.ids.size()==2,"Detached drag keeps group selected")
	check(c.hand_window.drop_on_field(one.state.match_instance_id,Vector2(430,300)),"Detached hand group drops onto field")
	check(one.state.current_zone=="battlefield" and two.state.current_zone=="battlefield","Detached group drop plays both cards")
	c.hand_window.cancel_drag();c.hand_window.restore_hand()
	c.move_card(one,"library");c.visibility.set_public_reveal(one.state,true)
	c.library_actions.enter_face_down=true;c.library_actions.play_top("local")
	check(one.state.face_down and not one.state.custom_metadata.get("public_reveal",false),"Face-down entry overrides prior intentional reveal")
	var public_data: Dictionary=main.ensure_network().gameplay.serializer.public_card(one)
	check(public_data.name=="Face-down card" and public_data.art=="" and public_data.definition=="","Face-down public serialization contains no identity or art")
	main.queue_free();await process_frame
	print("PLAY WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
