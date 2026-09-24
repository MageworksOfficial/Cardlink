extends "res://scripts/tests/milestone_75_test.gd"
func route(point: Vector2, pressed: bool = false, release: bool = false, double: bool = false) -> void:
	if pressed or release:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.double_click = double
		root.push_input(event,true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event,true)
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var app: Control = new_app(base)
	await process_frame
	app.entry.start(app.Mode.OFFLINE_PLAYTEST)
	await wait_for(func() -> bool: return not app.entering and app.table_scene != null)
	var t: Node = app.table_scene.tabletop
	var c: Node = t.match_controller
	# Keep test gestures clear of graveyard/exile token-destruction zones.
	for zone: Control in t.zones: zone.position = Vector2(2100,1200)
	var one: Control = t.create_token("First","local","local").card
	var two: Control = t.create_token("Second","opponent","opponent").card
	one.position = Vector2(1700,850)
	two.position = Vector2(1530,850)
	t.perspective.switch_to("opponent",false)
	t.view.zoom = 1.0
	t.view.pan = Vector2.ZERO
	t.view.apply_view()
	await process_frame
	await process_frame
	route(Vector2(480,280))
	route(Vector2(480,280),true)
	route(Vector2(800,470))
	route(Vector2(800,470),false,true)
	check(t.selection.ids.size() == 2,"Real Player 2 marquee selects both upright objects")
	var pos_one: Vector2 = one.position
	var pos_two: Vector2 = two.position
	var point: Vector2 = one.get_global_rect().get_center()
	route(point)
	route(point,true)
	route(point+Vector2(30,20))
	route(point+Vector2(30,20),false,true)
	check(one.position.is_equal_approx(pos_one-Vector2(30,20)) and two.position.is_equal_approx(pos_two-Vector2(30,20)),"Real Player 2 group drag moves neutral positions correctly")
	check(not one.state.tapped and not two.state.tapped,"Group release does not tap")
	t.selection.clear()
	point = one.get_global_rect().get_center()
	route(point)
	route(point,true,false,true)
	route(point,false,true)
	check(one.state.tapped,"Real Player 2 double click reaches tapped hit test")
	point = one.get_global_rect().get_center()
	route(point,true,false,true)
	route(point,false,true)
	check(not one.state.tapped,"Real Player 2 second double click untaps")
	var zone: Control = c.zone_for("exile","opponent")
	zone.position = Vector2(1200,950)
	t.perspective.apply()
	t.layout.set_edit_mode(true)
	await process_frame
	var neutral: Vector2 = zone.position
	point = zone.title.get_global_rect().get_center()
	route(point)
	route(point,true)
	route(point+Vector2(20,15))
	route(point+Vector2(20,15),false,true)
	check(zone.position.is_equal_approx(neutral-Vector2(20,15)),"Real Player 2 Layout drag preserves neutral direction")
	t.layout.set_edit_mode(false)
	c.hand_window.open_hand()
	var hand_card: Control = t.create_token("Drop test","opponent","opponent").card
	# Normal card state is used here so entering hand does not destroy a token.
	hand_card.state.is_token = false
	c.move_card(hand_card,"hand",true,"opponent")
	var id: String = hand_card.state.match_instance_id
	check(c.hand_window.drop_on_field(id,Vector2(500,400)),"Detached Player 2 hand drops onto battlefield")
	check(hand_card.get_global_rect().get_center().is_equal_approx(Vector2(500,400)),"Cross-window drop lands under pointer in opposite seat")
	check(c.hand_window.drop_to_hand(id) and hand_card.state.zone_player_id == "opponent","Cross-window return targets viewed Player 2 hand")
	c.hand_window.restore_hand()
	app.table_preferences.put("reduce_motion",true)
	t.perspective.toggle()
	check(t.world.modulate.a == 1.0,"Reduce Motion skips fade")
	app.return_to_title()
	app.queue_free()
	await process_frame
	print("CARDLINK 7.5 GESTURES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
