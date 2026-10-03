extends Node
## Neutral coordinates never change. Rotate the world, counter-rotate each item
## around its center, and keep all screen-space UI outside that projection.
var manager: Node
var viewed_player: String = "local"
var heart_anchors: Dictionary = {}
var transition: Tween
var feedback: Node
func _ready() -> void:
	feedback = preload("res://scripts/usability/turn_feedback.gd").new()
	feedback.manager = manager
	add_child(feedback)
func offline() -> bool: return manager.match_controller.playtest.local_playtest()
func flipped() -> bool: return offline() and viewed_player == "opponent"
func other(player: String) -> String: return "opponent" if player == "local" else "local"
func capture_heart_anchors() -> void:
	for player: String in manager.match_controller.hearts.hearts:
		heart_anchors[player] = manager.match_controller.hearts.hearts[player].get_parent().position
func heart_position(player: String) -> Vector2:
	return heart_anchors.get(player,manager.match_controller.hearts.hearts[player].get_parent().position)
func move_heart(player: String, point: Vector2) -> void:
	heart_anchors[other(player) if flipped() else player] = point
	apply()
func project_item(item: Control) -> void:
	if not item.has_meta("seat_projection"):
		item.set_meta("seat_projection",true)
		item.resized.connect(project_item.bind(item))
	item.pivot_offset = item.size/2
	item.rotation = PI if flipped() else 0.0
func apply() -> void:
	manager.world.pivot_offset = Vector2.ZERO
	manager.world.rotation = PI if flipped() else 0.0
	manager.world.position = manager.view.pan + (manager.world.size*manager.view.zoom if flipped() else Vector2.ZERO)
	var c: Node = manager.match_controller
	for item: Control in manager.cards + manager.zones + manager.extras.counters + [c.pile_view,c.opponent_pile]: project_item(item)
	for player: String in c.hearts.hearts:
		if not heart_anchors.is_empty(): c.hearts.hearts[player].get_parent().position = heart_position(other(player) if flipped() else player)
func switch_to(player: String, animate: bool = true, center: bool = true) -> void:
	if not offline(): player = "local"
	if player not in ["local","opponent"]: return
	var c: Node = manager.match_controller
	# A seat change cancels gestures, not game state or selection.
	c.hand_window.cancel_drag()
	for card: Control in manager.cards:
		card.dragging = false
		card.hover_preview.hide()
	for counter: Control in manager.extras.counters: counter.dragging = false
	for zone: Control in manager.zones: zone.dragging = false
	for pile: Control in [c.pile_view,c.opponent_pile]:
		pile.layout_dragging = false
		pile.click_pending = false
		pile.click_generation += 1
	manager.drag_origins.clear()
	manager.selection.moving = false
	manager.selection.marquee = false
	manager.selection.origins.clear()
	manager.view.panning = false
	c.hide_preview()
	viewed_player = player
	c.playtest.hand_player = player
	c.playtest.player_picker.select(1 if player == "opponent" else 0)
	if transition != null: transition.kill()
	manager.world.modulate.a = 1.0
	apply()
	if center: center_view()
	c.refresh()
	manager.controls.status.text = "Viewing %s side · %s's turn" % [c.model.players[player].display_name,c.actor_name()]
	# A brief fade avoids spinning any readable content. Reduce Motion skips it.
	if animate and not bool(manager.table_preferences.value("reduce_motion",false)):
		manager.world.modulate.a = 0.35
		transition = create_tween()
		transition.tween_property(manager.world,"modulate:a",1.0,0.25)
	if animate and offline(): feedback.show_turn(viewed_player)
	manager.undo.committed.emit() # Recovery checkpoint; no gameplay undo/history entry.
func toggle() -> void:
	if not offline():
		manager.controls.status.text = "Switch Perspective is available in Offline Playtest."
		return
	switch_to(other(viewed_player))
func after_turn() -> void:
	if offline() and bool(manager.table_preferences.value("auto_perspective",true)):
		switch_to(manager.match_controller.model.active_player)
	else:
		manager.match_controller.refresh()
		manager.controls.status.text = "%s Turn" % manager.match_controller.actor_name()
		if offline(): feedback.show_turn(viewed_player)
func center_view() -> void:
	var c: Node = manager.match_controller
	var pile: Control = c.pile_view if viewed_player == "local" else c.opponent_pile
	var projected: Vector2 = manager.world.LOGICAL_SIZE-pile.position-pile.size/2 if flipped() else pile.position+pile.size/2
	var screen: Vector2 = manager.get_viewport().get_visible_rect().size
	# Center horizontally, place the near player's edge above their fixed hand.
	var hand_y: float = c.hand_window.main_layout.position.y if c.hand_window.detached else c.hand.position.y
	var pan_x: float = (screen.x-manager.world.LOGICAL_SIZE.x*manager.view.zoom)/2
	var margin: float = pile.size.x*manager.view.zoom/2+24
	var pile_x: float = projected.x*manager.view.zoom+pan_x
	pan_x += clampf(pile_x,margin,screen.x-margin)-pile_x
	manager.view.pan = Vector2(pan_x,maxf(80,hand_y-pile.size.y*manager.view.zoom/2-24)-projected.y*manager.view.zoom)
	manager.view.apply_view()

func read_heart_positions() -> void:
	var updated: Dictionary = {}
	for player: String in manager.match_controller.hearts.hearts:
		updated[other(player) if flipped() else player] = manager.match_controller.hearts.hearts[player].get_parent().position
	heart_anchors = updated
