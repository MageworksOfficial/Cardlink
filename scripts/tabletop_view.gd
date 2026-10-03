extends Node
## Apply one transform to tabletop surfaces, leaving toolbar and hand fixed.
var manager: Node
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var panning: bool = false
func zoom_by(factor: float, anchor: Vector2 = Vector2.INF) -> void:
	var center: Vector2 = get_viewport().get_visible_rect().size / 2 if anchor == Vector2.INF else anchor
	var next: float = clampf(zoom * factor, 0.4, 2.0)
	pan = center - (center - pan) * next / zoom
	zoom = next
	apply_view()
func reset_view() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	zoom = clampf(minf(screen.x/2304.0,(screen.y-190)/1296.0),0.4,0.8)
	pan = Vector2((screen.x-2304*zoom)/2,65)
	apply_view()
func apply_view() -> void:
	manager.world.scale = Vector2.ONE * zoom
	manager.world.position = pan
	if manager.perspective != null: manager.perspective.apply()
	if manager.match_controller != null:
		manager.match_controller.pile_view.refresh()
		manager.match_controller.opponent_pile.refresh()
	for zone: Control in manager.zones: zone.update_title()
	if manager.custom_table != null: manager.custom_table.refresh_presentation()
	for card: Control in manager.cards:
		card.hover_preview.hide()
func over_field(point: Vector2) -> bool:
	if manager.shortcuts != null and (manager.shortcuts.has_window(manager.get_parent()) or manager.shortcuts.quick_row.get_global_rect().has_point(point)):
		return false
	if manager.extras != null and manager.extras.is_modal():
		return false
	if manager.controls != null:
		for popup: PopupPanel in manager.controls.panels.values():
			if popup.visible:
				return false
		if manager.controls.get_global_rect().has_point(point):
			return false
	if manager.match_controller != null:
		var c: Node = manager.match_controller
		if c.hearts != null:
			for heart: Label in c.hearts.hearts.values():
				if heart.get_parent().visible and heart.get_parent().get_global_rect().has_point(point): return false
		if c.contents.visible or (c.review != null and c.review.visible):
			return false
		for surface: Control in [c.hand, c.opponent_hand, manager.life_display]:
			if surface == c.hand and c.hand_window != null and c.hand_window.detached: continue
			if surface != null and surface.visible and surface.get_global_rect().has_point(point):
				return false
	return true
func _input(event: InputEvent) -> void:
	if not manager.active:
		panning = false
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and over_field(event.position):
		zoom_by(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, event.position)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		panning = event.pressed and over_field(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and panning:
		pan += event.relative
		apply_view()
		get_viewport().set_input_as_handled()


func center_local() -> void:
	if manager.perspective != null and manager.perspective.offline():
		zoom = maxf(zoom,0.7)
		manager.perspective.center_view()
		return
	zoom = maxf(zoom,0.7)
	pan = get_viewport().get_visible_rect().size*Vector2(0.5,0.48)-Vector2(1152,900)*zoom
	apply_view()
