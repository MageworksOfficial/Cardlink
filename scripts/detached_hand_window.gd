extends Node
## One view of the same hand. Screen-space drag commits one normal zone move.
var controller: Node
var window: Window
var rows: VBoxContainer
var preview: TextureRect
var detached: bool = false
var main_parent: Node
var main_layout: Dictionary = {}
var drag_id: String = ""
var drag_origin: Vector2
var field_id: String = ""
var last_position := Vector2i(100,100)
var ghost: TextureRect
var hand_ghost: TextureRect
var drag_hint: Label
var drag_phase: String = "idle"
var drag_steps: Array[String] = []
func _ready() -> void:
	window = Window.new()
	window.name = "PrivateHandWindow"
	window.title = "CardLink · Private Hand"
	window.visible = false
	window.force_native = true
	window.transient = false
	window.visible = false
	window.size = Vector2i(820,360)
	window.min_size = Vector2i(520,260)
	window.close_requested.connect(restore_hand)
	window.window_input.connect(window_input)
	add_child(window)
	rows = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(rows)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	controller.button(buttons,"Draw",func() -> void: controller.draw_card(controller.active_hand_player()))
	controller.button(buttons,"View Library",func() -> void: controller.open_library_view(controller.active_hand_player()))
	controller.button(buttons,"Selected → Hand",func() -> void: controller.move_card(controller.manager.selected_card,"hand",true,controller.active_hand_player()))
	controller.button(buttons,"Restore to Main Window",restore_hand)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(100,140)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(preview)
	ghost = TextureRect.new()
	ghost.size = Vector2(70,98)
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controller.preview_layer.add_child(ghost)
	ghost.hide()
	hand_ghost = TextureRect.new()
	hand_ghost.size = Vector2(70,98)
	hand_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	window.add_child(overlay)
	overlay.add_child(hand_ghost)
	hand_ghost.hide()
	drag_hint = Label.new()
	drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_hint.position = Vector2(12,window.size.y-30)
	overlay.add_child(drag_hint)
	drag_hint.hide()
	preload("res://scripts/frontend/frontend_theme.gd").skin_window(window)
func open_hand() -> void:
	if detached:
		window.show()
		return
	controller.manager.controls.close_panels()
	main_parent = controller.hand.get_parent()
	main_layout = {"position":controller.hand.position,"size":controller.hand.size}
	controller.hand.reparent(rows,false)
	controller.hand.custom_minimum_size.y = 130
	controller.hand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.move_child(controller.hand,1)
	detached = true
	window.position = last_position
	window.show()
	controller.refresh()
func restore_hand() -> void:
	if not detached: return
	cancel_drag()
	field_id = ""
	last_position = window.position
	window.hide()
	controller.hand.reparent(main_parent,false)
	controller.hand.custom_minimum_size.y = 0
	controller.hand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controller.hand.offset_top = -202
	controller.hand.offset_bottom = -62
	controller.hand.position = main_layout.position
	controller.hand.size = main_layout.size
	detached = false
	preview.texture = null
	controller.refresh()
func refresh() -> void:
	window.title = "CardLink · "+controller.model.players[controller.active_hand_player()].display_name+" Hand"
	if detached:
		window.visible = controller.manager.active and not controller.hands_hidden
		if not window.visible: cancel_drag()
func begin_drag(id: String) -> void:
	if not drag_id.is_empty(): return
	var card: Control = controller.card_by_id(id)
	if not detached or card == null or card.state.current_zone != "hand" or card.state.zone_player_id != controller.active_hand_player(): return
	drag_id = id
	drag_origin = Vector2(DisplayServer.mouse_get_position())
	if not controller.manager.selection.ids.has(id): controller.manager.select_card(card)
	controller.hide_preview()
	drag_steps.clear()
	set_drag_phase("drag_started")
	ghost.texture = card.card_image.texture
	hand_ghost.texture = card.card_image.texture
	set_drag_phase("drag_preview_active")
	drag_hint.text = "Dragging card · Release on battlefield · Esc cancels"
	drag_hint.show()
	update_drag_preview(drag_origin,window.get_window_id())
func drop_on_field(id: String, viewport_point: Vector2) -> bool:
	var card: Control = controller.card_by_id(id)
	if card == null or card.state.current_zone != "hand" or card.state.zone_player_id != controller.active_hand_player() or not controller.manager.view.over_field(viewport_point): return false
	return controller.library_actions.place_cards(controller.library_actions.hand_drag_ids(id),controller.manager.world.get_global_transform().affine_inverse()*viewport_point-card.size/2,controller.library_actions.enter_face_down)>0
func drop_to_hand(id: String) -> bool:
	var card: Control = controller.card_by_id(id)
	if card == null or card.state.current_zone != "battlefield" or (controller.online() and card.state.owner_player_id != "local"): return false
	card.dragging = false
	return controller.move_card(card,"hand",true,controller.active_hand_player())
func watch_field(card: Control) -> void:
	if detached: field_id = card.state.match_instance_id
func _process(_delta: float) -> void:
	if not detached or (drag_id.is_empty() and field_id.is_empty()): return
	var point := Vector2(DisplayServer.mouse_get_position())
	var target: int = DisplayServer.get_window_at_screen_position(Vector2i(point))
	update_drag_preview(point,target)
	# Commit only on an actual mouse release event, not transient focus/input loss.
	# Outside either window there is no valid destination; leave the card untouched.
func update_drag_preview(point: Vector2, target: int) -> void:
	var main: Window = controller.get_tree().root
	var card: Control = controller.card_by_id(drag_id)
	ghost.visible = card != null and target == main.get_window_id()
	hand_ghost.visible = card != null
	if card != null:
		ghost.texture = card.card_image.texture
		ghost.position = main.get_screen_transform().affine_inverse()*point-ghost.size/2
		hand_ghost.position = window.get_screen_transform().affine_inverse()*point-hand_ghost.size/2 if target == window.get_window_id() else Vector2(window.size.x-86,42)
		drag_hint.position.y = window.size.y-30
		ghost.modulate = Color.WHITE if controller.manager.view.over_field(main.get_screen_transform().affine_inverse()*point) else Color(1,0.6,0.6,0.8)
func _input(event: InputEvent) -> void:
	if not detached: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		cancel_drag()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var point := DisplayServer.mouse_get_position()
		finish_screen_drop(Vector2(point),DisplayServer.get_window_at_screen_position(point))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: cancel_drag()
func set_drag_phase(value: String) -> void:
	drag_phase = value
	drag_steps.append(value)
func cancel_drag() -> void:
	if not drag_id.is_empty(): set_drag_phase("canceled")
	drag_id = ""
	field_id = ""
	ghost.hide()
	if hand_ghost != null: hand_ghost.hide()
	if drag_hint != null: drag_hint.hide()
func finish_screen_drop(point: Vector2, target: int) -> void:
	var main: Window = controller.get_tree().root
	if not drag_id.is_empty() and point.distance_to(drag_origin)>8 and target == main.get_window_id():
		var local_point: Vector2 = main.get_screen_transform().affine_inverse()*point
		if controller.manager.view.over_field(local_point):
			set_drag_phase("drop_confirmed")
			if drop_on_field(drag_id,local_point): set_drag_phase("zone_transition_committed")
	elif not field_id.is_empty() and target == window.get_window_id():
		drop_to_hand(field_id)
	if not drag_id.is_empty() and drag_phase != "zone_transition_committed": set_drag_phase("canceled")
	drag_id = ""
	field_id = ""
	ghost.hide()
	hand_ghost.hide()
	drag_hint.hide()
func window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		cancel_drag()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var point := DisplayServer.mouse_get_position()
		finish_screen_drop(Vector2(point),DisplayServer.get_window_at_screen_position(point))
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		cancel_drag()
		return
	var focus: Control = window.gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	controller.manager.shortcuts.handle_key(event)
