extends "res://scripts/tests/milestone_74_test.gd"
func click(double: bool = false, pressed: bool = true, button: int = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.double_click = double
	e.position = Vector2(25,30)
	return e
func upright(item: Control) -> bool:
	var t: Transform2D = item.get_global_transform()
	return t.x.normalized().is_equal_approx(Vector2.RIGHT) and t.y.normalized().is_equal_approx(Vector2.DOWN)
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
	var seat: Node = t.perspective
	check(seat.viewed_player == "local" and not seat.flipped(),"Offline starts in Player 1 seat")
	check(app.bindings.keys.tap == KEY_Q and app.bindings.keys.perspective == KEY_V,"Q and V defaults available")
	var cfg := ConfigFile.new()
	cfg.set_value("keys","draw",KEY_Q)
	cfg.set_value("keys","shuffle",KEY_V)
	cfg.save(base.path_join("old_keys.cfg"))
	var migrated = preload("res://scripts/usability/input_bindings.gd").new(base.path_join("old_keys.cfg"))
	check(migrated.keys.draw == KEY_Q and migrated.keys.shuffle == KEY_V and migrated.keys.tap == 0 and migrated.keys.perspective == 0,"Existing Q/V assignments win over new defaults")
	var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var store = preload("res://scripts/card_storage.gd").new(base.path_join("cards"))
	store.save_card(image.save_png_to_buffer(),"Seat card",image.get_size())
	c.loader = preload("res://scripts/library_loader.gd").new(base.path_join("cards"))
	var record: Dictionary = c.loader.load_records()[0]
	var one: Control = t.spawn_definition(record).card
	var two: Control = t.spawn_definition(record).card
	one.position = Vector2(700,820)
	two.position = Vector2(1500,260)
	two.state.owner_player_id = "opponent"
	two.state.controller_player_id = "opponent"
	two.state.zone_player_id = "opponent"
	var one_id: String = one.state.match_instance_id
	var two_id: String = two.state.match_instance_id
	var releases: Array = []
	one.drag_finished.connect(func(_card: Control) -> void: releases.append(true))
	one._gui_input(click())
	one._gui_input(click(false,false))
	check(t.selected_card == one and not one.state.tapped,"Single click selects without tapping")
	check(releases.is_empty(),"Single click emits no fake movement commit")
	var before: Vector2 = one.position
	t.undo.invalidate()
	one._gui_input(click(true))
	one._gui_input(click(false,false))
	t.undo.finish()
	check(one.state.tapped and one.card_image.rotation_degrees == 90,"Double click taps visible art")
	check(one.position == before and one.rotation == 0,"Tap preserves root transform")
	check(not t.controls.panels.Card.visible and releases.is_empty(),"Double click avoids menus and duplicate movement")
	t.undo.undo()
	one = c.card_by_id(one_id)
	two = c.card_by_id(two_id)
	check(not one.state.tapped,"Offline Undo restores untapped state")
	one._gui_input(click(true))
	one._gui_input(click(true))
	check(not one.state.tapped,"Second double click untaps")
	one._gui_input(click(false,true,MOUSE_BUTTON_RIGHT))
	check(t.controls.panels.Card.visible,"Right click opens Card Actions")
	t.controls.close_panels()
	t.view.zoom_by(1.5)
	t.view.pan += Vector2(35,27)
	t.view.apply_view()
	one._gui_input(click(true))
	check(one.state.tapped and one.position == before,"Zoomed/panned tap preserves position")
	t.select_card(one)
	t.shortcuts.handle_key(key_event(KEY_Q))
	check(not one.state.tapped,"Q toggles selected card")
	app.bindings.assign("tap",KEY_J)
	t.shortcuts.handle_key(key_event(KEY_J))
	check(one.state.tapped and app.bindings.help_text().contains("J — Tap / Untap Selected"),"Tap rebind and dynamic help work")
	app.bindings.reset_all()
	one.set_tapped(false)
	one._gui_input(click())
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(55,45)
	one._gui_input(motion)
	one._gui_input(click(false,false))
	check(not one.state.tapped and one.position == before+Vector2(30,15),"Drag does not tap")
	one.position = before
	var hand_one: Control = t.spawn_definition(record).card
	var hand_two: Control = t.spawn_definition(record).card
	c.move_card(hand_one,"hand",true,"local")
	c.move_card(hand_two,"hand",true,"opponent")
	var token: Control = t.create_token("Wolf","local","local","","2","2").card
	var counter: Control = t.extras.create_counter(Vector2(1050,680),5,"Energy")
	c.refresh()
	var positions: Dictionary = {}
	for card: Control in t.cards: positions[card.state.match_instance_id] = card.position
	var zones: Dictionary = {}
	for zone: Control in t.zones: zones[zone.zone_id] = zone.position
	var turn: int = c.model.turn_number
	var zoom: float = t.view.zoom
	c.hand_window.open_hand()
	c.hand_window.window.position = Vector2i(150,120)
	c.hand_window.window.size = Vector2i(800,380)
	var window_id: int = c.hand_window.window.get_instance_id()
	c.end_turn()
	await create_timer(0.3).timeout
	check(c.model.active_player == "opponent" and c.model.turn_number == turn+1,"End Turn advances player/turn")
	check(seat.viewed_player == "opponent" and seat.flipped(),"End Turn switches to Player 2 seat")
	check(two.get_global_rect().get_center().y > one.get_global_rect().get_center().y,"Player 2 near and Player 1 far")
	check(c.opponent_pile.get_global_rect().position.y > c.pile_view.get_global_rect().position.y,"Libraries swap near/far")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(c.opponent_pile.get_global_rect().get_center()),"New near library remains on screen")
	check(is_equal_approx(t.view.zoom,zoom),"Switch preserves zoom")
	t.view.zoom = 2.0
	seat.center_view()
	var near_rect: Rect2 = c.opponent_pile.get_global_rect()
	check(near_rect.position.x >= 0 and near_rect.end.x <= root.size.x and near_rect.end.y < c.hand_window.main_layout.position.y,"Maximum zoom keeps the near library above fixed hand and on screen")
	t.view.zoom = zoom
	seat.center_view()
	check(upright(one) and upright(two) and upright(token) and upright(counter),"Cards tokens counters remain upright")
	var all_upright: bool = true
	for zone: Control in t.zones: all_upright = all_upright and upright(zone.title)
	check(all_upright and upright(c.pile_view.caption),"Zone/pile labels remain upright")
	check(upright(t.shortcuts.quick_row) and upright(c.hearts.hearts.local),"Screen UI and life remain upright")
	check(c.active_hand_player() == "opponent" and c.hand.row.get_child(0).instance_id == hand_two.state.match_instance_id,"Near hand switches to Player 2")
	check(c.opponent_hand.back_count == 1 and c.opponent_hand.label.text.contains(c.model.players.local.display_name),"Far hand represents Player 1")
	check(c.hand_window.window.get_instance_id() == window_id and c.hand_window.window.position == Vector2i(150,120) and c.hand_window.window.size == Vector2i(800,380),"Detached window instance and geometry preserved")
	check(c.hand_window.window.title.contains(c.model.players.opponent.display_name),"Detached window identifies viewed player")
	var unchanged: bool = true
	for card: Control in t.cards: unchanged = unchanged and card.position == positions[card.state.match_instance_id]
	for zone: Control in t.zones: unchanged = unchanged and zone.position == zones[zone.zone_id]
	check(unchanged,"Perspective leaves logical card/zone positions unchanged")
	one._gui_input(click(true))
	check(one.state.tapped and upright(one),"Either player's card taps from Player 2 seat")
	one._gui_input(click())
	one._gui_input(motion)
	one._gui_input(click(false,false))
	check(one.position.is_equal_approx(before-Vector2(30,15)),"Player 2 drag maps to neutral coordinates")
	one.position = before
	c.end_turn()
	check(seat.viewed_player == "local" and c.active_hand_player() == "local","Next End Turn returns to Player 1")
	c.hand_window.restore_hand()
	t.undo.finish()
	var history: int = c.model.history.size()
	var stack: int = t.undo.entries.size()
	turn = c.model.turn_number
	t.shortcuts.handle_key(key_event(KEY_V))
	check(seat.viewed_player == "opponent" and c.model.turn_number == turn and c.model.active_player == "local","V switches seat without ending turn")
	check(c.model.history.size() == history and t.undo.entries.size() == stack,"Perspective consumes no gameplay history/undo")
	app.table_preferences.put("auto_perspective",false)
	c.end_turn()
	c.end_turn()
	check(seat.viewed_player == "opponent" and c.model.active_player == "local","Auto-switch OFF keeps view while turns advance")
	check(not bool(preload("res://scripts/usability/table_preferences.gd").new(app.table_preferences.path).value("auto_perspective",true)),"Auto-switch persists as user preference")
	var snapshot: Dictionary = t.persistence.capture_match()
	check(snapshot.local_tabletop.viewed_player == "opponent" and snapshot.local_tabletop.active_player == "local","Save stores viewed seat independently")
	seat.switch_to("local",false)
	t.persistence.restore_match(snapshot)
	check(seat.viewed_player == "opponent" and c.model.active_player == "local" and c.card_by_id(one_id).state.tapped,"Save restores tap/turn/view")
	t.view.reset_view()
	check(seat.flipped() and is_equal_approx(t.world.rotation,PI),"Reset View preserves Player 2 seat")
	t.organization.reset_layout()
	check(seat.flipped() and upright(c.pile_view),"Reset Table Layout works from Player 2 seat")
	var zone: Control = c.zone_for("exile","opponent")
	zone.position = Vector2(400,300)
	var layout: Dictionary = t.layout.capture()
	seat.switch_to("local",false)
	t.layout.apply(layout)
	seat.switch_to("opponent",false)
	check(zone.position == Vector2(400,300) and upright(zone),"Custom layouts stay neutral")
	check(app.bindings.help_text().contains("Double click battlefield card — Tap / Untap") and app.bindings.help_text().contains("V — Switch Offline Perspective"),"Controls Help updated")
	app.bindings.assign("tap",KEY_G,true)
	check(app.bindings.keys.graveyard == 0 and app.bindings.keys.tap == KEY_G,"Conflict replacement preserved")
	app.bindings.reset_all()
	app.recovery.save_recovery()
	await screenshot(base,"player2")
	app.queue_free()
	await process_frame
	app = new_app(base)
	await process_frame
	app.recovery.recover()
	await wait_for(func() -> bool: return not app.entering and app.table_scene != null)
	t = app.table_scene.tabletop
	check(t.perspective.viewed_player == "opponent" and t.match_controller.model.active_player == "local","Recovery restores active/viewed sides separately")
	check(t.match_controller.card_by_id(one_id).state.tapped,"Recovery preserves tap state")
	check(not app.table_scene.has_node("Network"),"Recovery does not connect online")
	app.return_to_title()
	app.queue_free()
	await process_frame
	print("CARDLINK 7.5: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
