extends RefCounted
var manager: Node
func _init(table: Node) -> void: manager = table
func selected_cards() -> Array[String]:
	var ids: Array[String] = manager.selection.ids.duplicate()
	if ids.is_empty() and is_instance_valid(manager.selected_card): ids.append(manager.selected_card.state.match_instance_id)
	return ids
func execute(action: String, event: InputEventKey = null) -> void:
	var c: Node = manager.match_controller
	var local: String = c.active_hand_player()
	if action == "perspective": manager.perspective.toggle(); return
	if action == "undo": manager.undo.undo(); return
	manager.undo.begin(str(manager.shortcuts.bindings.ACTIONS.get(action,[action])[0]))
	match action:
		"untap_all": manager.lab.untap_all()
		"reset_match": manager.battle.reset.open()
		"background_edit": manager.appearance.toggle_edit()
		"play_top": c.library_actions.play_active()
		"card_face":
			for id: String in selected_cards(): preload("res://scripts/usability/face_actions.gd").change(manager,c.card_by_id(id))
		"tap":
			for id: String in selected_cards(): manager.toggle_tap(c.card_by_id(id))
		"draw":
			if manager.custom_table != null and manager.custom_table.enabled: manager.custom_table.draw_active()
			else: c.draw_card(local)
		"discard": manager.shortcuts.discard()
		"shuffle":
			if manager.custom_table != null and manager.custom_table.enabled: manager.custom_table.shuffle_active()
			else: c.shuffle_library(local)
		"table_builder":
			if manager.custom_table != null and manager.custom_table.enabled: manager.custom_table.editor.toggle_drawer()
		"hands": manager.shortcuts.toggle_hands()
		"layout": manager.shortcuts.toggle_layout()
		"mode": manager.shortcuts.toggle_playtest()
		"delete":
			var ids: Array[String] = selected_cards()
			for id: String in ids:
				var card: Control = c.card_by_id(id)
				if card != null and card.state.current_zone == "hand": c.move_card(card,"graveyard",true,card.state.owner_player_id)
			manager.selection.apply_batch("delete",ids)
		"reset_view": manager.view.reset_view()
		"center_view": manager.view.center_local()
		"token":
			if is_instance_valid(manager.selected_card):
				var result: Dictionary = c.library_actions.duplicate_token(manager.selected_card)
				if result.has("error"): manager.controls.status.text = result.error
			else: manager.extras.choose("Token")
		"counter":
			if is_instance_valid(manager.selected_card): manager.controls.open_panel("Counter")
			elif manager.selection.ids.size() == 1 and manager.extras.counter_by_id(manager.selection.ids[0]) != null: manager.extras.open_counter(manager.extras.counter_by_id(manager.selection.ids[0]))
			else: manager.extras.open_counter(manager.extras.create_counter(manager.world.get_global_transform().affine_inverse()*manager.get_viewport().get_visible_rect().size/2))
		"graveyard", "exile":
			var ids: Array[String] = selected_cards()
			if ids.is_empty(): c.open_public_zone(local,action)
			else:
				for id: String in ids:
					var card: Control = c.card_by_id(id)
					if card != null and card.state.current_zone == "hand": c.move_card(card,action,true,card.state.owner_player_id)
				manager.selection.apply_batch(action,ids)
		"hand":
			if c.hands_hidden: manager.shortcuts.toggle_hands()
			c.hand_open = true
			c.refresh()
			if c.hand_window.detached: c.hand_window.open_hand()
			else: manager.controls.open_panel("Hand")
		"library": c.open_library_view(local)
		"history": manager.extras.toggle_history()
		"end_turn": c.end_turn()
		"save": manager.controls.open_panel("Match")
		"pan_left", "pan_right", "pan_up", "pan_down":
			var direction: Vector2 = {"pan_left":Vector2.RIGHT,"pan_right":Vector2.LEFT,"pan_up":Vector2.DOWN,"pan_down":Vector2.UP}[action]
			manager.view.pan += direction*(120 if event != null and event.shift_pressed else 40)
			manager.view.apply_view()
	manager.undo.finish.call_deferred()
