extends "res://scripts/tests/milestone_6b_test.gd"
func mouse(button: int, double: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.double_click = double
	event.position = Vector2(10,10)
	return event
func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption: return node
	for child: Node in node.get_children():
		var found: Button = find_button(child,caption)
		if found != null: return found
	return null
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var main: Control = await create_client(base.path_join("cards"),"Drag fixture",Color.CORNFLOWER_BLUE)
	var table: Node = main.tabletop
	var c: Node = table.match_controller
	var shortcuts: Node = table.shortcuts
	var count: int = c.pile.order.size()
	c.pile_view._gui_input(mouse(MOUSE_BUTTON_RIGHT))
	check(table.controls.panels.Library.visible,"Right click library opens actions immediately")
	await create_timer(0.6).timeout
	check(c.pile.order.size()==count,"Right click library never draws")
	table.controls.close_panels()
	c.draw_card("local")
	var id: String = c.model.players.local.hand[0]
	var card: Control = c.card_by_id(id)
	c.hand.row.get_child(0).gui_input.emit(mouse(MOUSE_BUTTON_RIGHT))
	check(table.controls.panels.Card.visible and not card.state.custom_metadata.get("public_reveal",false),"Right click hand opens actions without revealing")
	find_button(table.controls.panels.Card,"Reveal").pressed.emit()
	check(card.state.custom_metadata.get("public_reveal",false),"Hand Reveal action retains public visibility/eye badge state")
	find_button(table.controls.panels.Card,"Hide / Face Down").pressed.emit()
	check(not card.state.custom_metadata.get("public_reveal",false),"Hand Hide action clears public reveal")
	table.controls.close_panels()
	c.move_card(card,"battlefield")
	card._gui_input(mouse(MOUSE_BUTTON_RIGHT))
	check(table.controls.panels.Card.visible and not card.tapped,"Right click battlefield card opens actions without tapping")
	find_button(table.controls.panels.Card,"Tap / Untap").pressed.emit()
	check(card.tapped,"Tap remains an explicit context action")
	check(find_button(table.controls.panels.Card,"Delete")!=null,"Card actions include safe Delete")
	table.controls.close_panels()
	var token: Control = table.create_token("Test token","local","local","").card
	token._gui_input(mouse(MOUSE_BUTTON_RIGHT))
	check(table.controls.panels.Card.visible and not table.extras.token_editor.visible,"Right click token opens actions")
	table.controls.close_panels()
	token._gui_input(mouse(MOUSE_BUTTON_LEFT,true))
	check(token.state.tapped,"Double click token quick-taps")
	token._gui_input(mouse(MOUSE_BUTTON_RIGHT))
	find_button(table.controls.panels.Card,"Token Properties").pressed.emit()
	check(table.extras.token_editor.visible,"Right-click Token Properties opens editor")
	table.extras.close_all()
	var counter: Control = table.extras.create_counter(Vector2(750,350))
	counter._gui_input(mouse(MOUSE_BUTTON_RIGHT))
	check(table.extras.counter_window.visible and find_button(table.extras.counter_window,"Delete counter")!=null,"Right click counter opens editable value/name/delete controls")
	table.extras.close_all()
	table.world._gui_input(mouse(MOUSE_BUTTON_RIGHT))
	check(table.extras.field_menu.visible,"Right click empty field preserves table actions")
	table.extras.close_all()
	check(shortcuts.quick_row.visible and shortcuts.playtest_button.visible and shortcuts.hands_button.visible,"Global quick controls are visible")
	shortcuts.playtest_button.pressed.emit()
	check(c.playtest.local_playtest(),"Playtest button enables offline opponent")
	shortcuts.handle_key(key(KEY_P))
	check(c.playtest.mode=="online","P toggles back to Online using existing mode system")
	shortcuts.hands_button.pressed.emit()
	check(c.hands_hidden and not c.hand.visible and not c.opponent_hand.visible,"Hands button hides both presentations")
	shortcuts.handle_key(key(KEY_X))
	check(not c.hands_hidden and c.opponent_hand.visible,"X restores hands")
	shortcuts.layout_button.pressed.emit()
	check(table.layout.edit_mode,"Layout button toggles mode")
	shortcuts.handle_key(key(KEY_L))
	check(not table.layout.edit_mode,"L restores Layout Off")
	var typing := LineEdit.new()
	main.add_child(typing)
	typing.grab_focus()
	for code: int in [KEY_P,KEY_X,KEY_L]: shortcuts.handle_key(key(code))
	check(c.playtest.mode=="online" and not c.hands_hidden and not table.layout.edit_mode,"Typing blocks P/X/L")
	typing.release_focus()
	typing.queue_free()
	c.move_card(card,"hand")
	shortcuts.hand_action(2)
	var hand_window: Node = c.hand_window
	hand_window.set_process(false)
	check(hand_window.detached and hand_window.window.visible,"Hands menu directly opens detached window")
	var total: int = table.cards.size()
	var hand_count: int = c.model.players.local.hand.size()
	var source: Control = c.hand.row.get_child(0)
	source._gui_input(mouse(MOUSE_BUTTON_LEFT))
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(35,35)
	source._gui_input(motion)
	check(hand_window.drag_phase=="drag_preview_active" and hand_window.hand_ghost.visible,"Hand motion starts internal drag with visible preview")
	check(card.state.current_zone=="hand" and source.visible and c.model.players.local.hand.size()==hand_count,"Drag start retains original hand state and visual")
	var point: Vector2 = root.get_screen_transform()*Vector2(420,440)
	hand_window.update_drag_preview(point,root.get_window_id())
	check(hand_window.ghost.visible and hand_window.hand_ghost.visible and hand_window.drag_hint.visible,"Cross-window preview plus persistent source indicator stay visible")
	if "capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("drag_table.png"))
		hand_window.window.get_texture().get_image().save_png(base.path_join("drag_hand.png"))
	hand_window.finish_screen_drop(point,-1)
	check(card.state.current_zone=="hand" and hand_window.drag_phase=="canceled" and not hand_window.ghost.visible,"Invalid/outside drop cancels without state change")
	hand_window.begin_drag(id)
	hand_window.window_input(key(KEY_ESCAPE))
	check(card.state.current_zone=="hand" and hand_window.drag_id.is_empty(),"Escape cancels without state change")
	hand_window.begin_drag(id)
	hand_window.drag_origin = Vector2.ZERO
	hand_window.finish_screen_drop(point,root.get_window_id())
	check(hand_window.drag_steps==["drag_started","drag_preview_active","drop_confirmed","zone_transition_committed"],"Successful drop follows transaction phases")
	check(card.state.current_zone=="battlefield" and c.model.players.local.hand.size()==hand_count-1,"Card leaves hand only after valid commit")
	check(table.cards.size()==total and c.card_by_id(id)==card,"Drop preserves exactly one Match Instance ID")
	hand_window.finish_screen_drop(point,root.get_window_id())
	check(table.cards.size()==total,"Repeated release cannot duplicate card")
	shortcuts.hand_action(3)
	check(not hand_window.detached and c.hand.get_parent()==main,"Hands menu returns same hand to main window")
	shortcuts.open_help()
	check(shortcuts.help.visible,"Updated Controls help opens")
	shortcuts.help.hide()
	c.playtest.set_mode("local_playtest")
	table.create_token("Other side","opponent","opponent","")
	var before_switch: int = table.cards.size()
	shortcuts.toggle_playtest()
	check(c.playtest.reset_dialog.visible and c.playtest.local_playtest() and table.cards.size()==before_switch,"Unsafe return to Online asks before clearing playtest copies")
	c.playtest.reset_dialog.canceled.emit()
	c.playtest.reset_dialog.hide()
	check(table.cards.size()==before_switch and c.playtest.local_playtest(),"Cancel mode change preserves both sides")
	shortcuts.toggle_playtest()
	c.playtest.reset_dialog.confirmed.emit()
	c.playtest.reset_dialog.hide()
	check(c.playtest.mode=="online" and table.cards.is_empty(),"Confirmed new table safely switches to Online")
	main.queue_free()
	await process_frame
	print("CARDLINK 7.1.1: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
