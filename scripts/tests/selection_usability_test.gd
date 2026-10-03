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
	var three: Control=c.card_by_id(c.pile.order[2])
	c.move_card(one,"battlefield")
	c.move_card(two,"hand")
	c.move_card(three,"hand")
	c.hand_open=true
	c.refresh()
	await process_frame
	one._gui_input(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	var item: Control=c.hand.row.get_child(0)
	item.gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	check(s.ids.size()==2,"Ctrl-click combines battlefield and hand selections")
	item.gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	check(s.ids.size()==1,"Ctrl-click removes only selected hand card")
	item.gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	c.hand.row.get_child(1).gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	check(s.ids.size()==3,"Multiple hand cards join same selection")
	c.refresh()
	await process_frame
	check(s.ids.size()==3,"Selection survives hand rebuild and frame pruning")
	item=c.hand.row.get_child(0)
	item._gui_input(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	check(item._get_drag_data(Vector2.ZERO)==null,"Modifier click does not start a hand drag")
	item.gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_RIGHT))
	check(s.bulk.visible and s.ids.size()==3,"Hand right-click opens bulk actions without clearing selection")
	s.bulk.hide()
	for zoom: float in [0.4,1.0,2.0]:
		t.view.zoom=zoom
		t.view.apply_view()
		s.open_bulk(one,Vector2(10,10))
		await process_frame
		check(s.bulk.get_parent()==t.controls and s.bulk.size.x>=340 and s.bulk.get_theme_font_size("font_size")==18,"Readable fixed bulk menu at zoom "+str(zoom))
		s.bulk.hide()
	s.apply_batch("graveyard",s.ids.duplicate())
	check(one.state.current_zone=="graveyard" and two.state.current_zone=="graveyard" and three.state.current_zone=="graveyard","Mixed hand/field bulk graveyard moves all selected cards")
	check(c.hand.row.get_child_count()==0,"Bulk move refreshes hand")
	c.move_card(two,"hand")
	c.move_card(three,"hand")
	c.hand_window.open_hand()
	await process_frame
	c.hand.row.get_child(0).gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	c.hand.row.get_child(1).gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_LEFT,true,true))
	check(s.ids.size()==2,"Detached hand supports Ctrl-click multiselect")
	c.hand.row.get_child(0).gui_input.emit(click(Vector2(10,10),MOUSE_BUTTON_RIGHT))
	check(s.bulk.visible and s.ids.size()==2,"Detached hand opens same readable bulk menu")
	s.bulk.hide()
	c.hand_window.restore_hand()
	c.move_card(one,"battlefield")
	s.toggle(one)
	t.view.zoom=0.4
	t.view.apply_view()
	s.open_bulk(one,Vector2(10,10))
	if DisplayServer.get_name()!="headless":
		await process_frame
		await process_frame
		s.bulk.popup()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("selection-menu.png"))
	s.bulk.hide()
	main.queue_free()
	await process_frame
	print("SELECTION UX: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
