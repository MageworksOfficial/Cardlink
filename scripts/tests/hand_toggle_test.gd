extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
	var a: Control = await create_client(OS.get_cmdline_user_args()[0],"Hand Toggle",Color.CORAL)
	var c: Node = a.tabletop.match_controller
	var shortcuts: Node = a.tabletop.shortcuts
	c.draw_card()
	var selected: Control = c.card_by_id(c.model.players.local.hand[0])
	a.tabletop.select_card(selected)
	var before: String = JSON.stringify(selected.state.to_data())
	var messages: int = wire.size()
	shortcuts.hands_button.pressed.emit()
	check(not c.hand.visible and not c.opponent_hand.visible,"Button hides both hand panels")
	shortcuts.hands_button.pressed.emit()
	check(c.hand.visible and c.opponent_hand.visible,"Button restores both hand panels")
	var key := InputEventKey.new()
	key.keycode = KEY_X
	key.pressed = true
	shortcuts._unhandled_key_input(key)
	check(c.hands_hidden,"X hides hands")
	shortcuts._unhandled_key_input(key)
	check(not c.hands_hidden,"X restores hands")
	check(before == JSON.stringify(selected.state.to_data()) and a.tabletop.selected_card == selected,"State and selected card preserved")
	check(wire.size() == messages,"Toggle sends no network message")
	var field := LineEdit.new()
	a.add_child(field)
	field.grab_focus()
	shortcuts._unhandled_key_input(key)
	check(not c.hands_hidden,"Typing X does not toggle hands")
	a.queue_free()
	await process_frame
	print("HAND TOGGLE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
