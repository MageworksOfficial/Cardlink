extends RefCounted
# A named ordinary attached counter. Zero is retained; no game rules are applied.
static func set_value(manager: Node, card: Control, value: int) -> void:
	if not is_instance_valid(card): return
	if manager.undo != null: manager.undo.begin("Loyalty counter")
	card.state.set_counter("Loyalty",clampi(value,0,1000000))
	card.update_counters()
	manager.match_controller.record_event("loyalty",manager.match_controller.actor_name()+" set Loyalty to "+str(card.state.counters.Loyalty))
	manager.controls.status.text="Loyalty: "+str(card.state.counters.Loyalty)
static func remove(manager: Node, card: Control) -> void:
	if not is_instance_valid(card): return
	manager.undo.begin("Remove Loyalty")
	card.state.counters.erase("Loyalty");card.update_counters()
	manager.match_controller.record_event("loyalty",manager.match_controller.actor_name()+" removed Loyalty.")
static func open(manager: Node) -> void:
	var card: Control=manager.selected_card
	if not is_instance_valid(card): return
	var dialog := Window.new();dialog.title="Loyalty";dialog.size=Vector2i(340,240);dialog.close_requested.connect(dialog.queue_free);manager.add_child(dialog)
	var rows := VBoxContainer.new();rows.position=Vector2(16,16);rows.size=Vector2(308,208);dialog.add_child(rows)
	var label := Label.new();label.text="LOYALTY · Manual counter";rows.add_child(label)
	var row := HBoxContainer.new();rows.add_child(row)
	var minus := Button.new();minus.text="−1";row.add_child(minus)
	var value := SpinBox.new();value.max_value=1000000;value.value=card.state.counters.get("Loyalty",0);value.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(value)
	var plus := Button.new();plus.text="+1";row.add_child(plus)
	minus.pressed.connect(func() -> void: value.value-=1)
	plus.pressed.connect(func() -> void: value.value+=1)
	value.value_changed.connect(func(n: float) -> void: set_value(manager,card,int(n)))
	var apply := Button.new();apply.text="Add / Set Loyalty";apply.pressed.connect(func() -> void: set_value(manager,card,int(value.value)));rows.add_child(apply)
	var remove_button := Button.new();remove_button.text="Remove Loyalty";rows.add_child(remove_button)
	remove_button.pressed.connect(func() -> void:
		remove(manager,card)
		dialog.queue_free())
	dialog.popup_centered()
