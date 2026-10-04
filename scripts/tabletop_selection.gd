extends Control
## Transient selection uses match IDs; never card-definition IDs or UI anchors.
var manager: Node
var ids: Array[String] = []
var marquee: bool = false
var start: Vector2
var finish: Vector2
var additive: bool = false
var moving: bool = false
var origins: Dictionary = {}
var drag_start: Vector2
var arrange: RefCounted
var bulk: PopupMenu
const ACTIONS = ["graveyard", "exile", "hand", "top", "bottom", "local", "opponent", "tap", "untap", "delete"]
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	bulk = PopupMenu.new()
	# Screen-fixed parent: embedded popups must not inherit battlefield zoom.
	manager.controls.add_child(bulk)
	bulk.min_size=Vector2i(380,0)
	bulk.add_theme_font_size_override("font_size",18)
	bulk.add_theme_constant_override("v_separation",10)
	for caption: String in ["Move All to Owner's Graveyard", "Move All to Owner's Exile", "Move All to Owner's Hand", "Put All on Owner's Library Top", "Put All on Owner's Library Bottom", "Controller: Local player", "Controller: Opponent", "Tap All", "Untap All", "Delete (cards â†’ owner's graveyard)"]:
		bulk.add_item(caption)
	bulk.id_pressed.connect(func(index: int) -> void:
		if index >= 0 and index < ACTIONS.size(): apply_batch(ACTIONS[index], ids.duplicate()))
	arrange = preload("res://scripts/usability/tabletop_arrange.gd").new(self)
	arrange.setup()
func object_id(item: Control) -> String:
	return item.state.match_instance_id if item in manager.cards else item.instance_id
func resolve(id: String) -> Control:
	var card: Control = manager.match_controller.card_by_id(id)
	return card if card != null else manager.extras.counter_by_id(id)
func eligible(item: Control) -> bool:
	return is_instance_valid(item) and item.visible and (not item in manager.cards or not item.state.current_zone in ["hand", "library"])
func selectable(item: Control) -> bool:
	if not is_instance_valid(item): return false
	if item in manager.cards and item.state.current_zone=="hand":
		var c: Node=manager.match_controller
		return manager.active and item.state.zone_player_id==c.active_hand_player() and not c.hands_hidden and c.hand_open
	return eligible(item)
func toggle(item: Control) -> void:
	if not selectable(item): return
	var id: String=object_id(item)
	if ids.has(id): ids.erase(id)
	else: ids.append(id)
	manager.selected_card=null
	paint();manager.controls.update_selection()
func open_bulk(source: Control, point: Vector2) -> void:
	if manager.lab!=null and ids.any(func(id: String) -> bool: return id in manager.lab.ids()):
		manager.lab.open();manager.lab.menu(ids.duplicate());return
	arrange.update_menu()
	manager.controls.close_panels()
	manager.match_controller.hide_preview()
	# Translate through desktop coordinates for a detached hand window too.
	var position_in_root: Vector2=manager.get_viewport().get_screen_transform().affine_inverse() * (source.get_screen_transform() * point)
	bulk.reset_size()
	bulk.size.x=maxi(380,bulk.size.x)
	var extent: Vector2=manager.get_viewport().get_visible_rect().size
	bulk.position=Vector2i(position_in_root.clamp(Vector2.ZERO,(extent-Vector2(bulk.size)).max(Vector2.ZERO)))
	bulk.popup()
func hand_input(card: Control, source: Control, event: InputEvent) -> bool:
	if not event is InputEventMouseButton or not event.pressed: return false
	var id: String=card.state.match_instance_id
	if event.button_index==MOUSE_BUTTON_LEFT and (event.ctrl_pressed or event.shift_pressed):
		toggle(card);return true
	if ids.has(id) and ids.size()>1:
		if event.button_index==MOUSE_BUTTON_RIGHT: open_bulk(source,event.position);return true
		if event.button_index==MOUSE_BUTTON_LEFT: return true
	return false
func set_single(card: Control) -> void:
	ids.clear()
	if selectable(card):
		ids.append(object_id(card))
	paint()
func clear() -> void:
	ids.clear()
	manager.selected_card = null
	paint()
	manager.controls.update_selection()
func paint() -> void:
	for card: Control in manager.cards:
		card.set_selected(ids.has(card.state.match_instance_id) or card == manager.selected_card)
	queue_redraw()
func _process(_delta: float) -> void:
	var kept: Array[String] = []
	for id: String in ids:
		if selectable(resolve(id)):
			kept.append(id)
	if kept != ids:
		ids = kept
		paint()
	visible = manager.active
	if not visible:
		marquee = false
		moving = false
		bulk.hide()
		arrange.menu.hide()
	queue_redraw()
func bounds(item: Control) -> Rect2:
	if item in manager.cards:
		return item.get_transform() * (item.card_image.get_transform() * Rect2(Vector2.ZERO, item.card_image.size))
	return Rect2(item.position, item.size)
func _draw() -> void:
	if marquee:
		var rect := Rect2(start, finish - start).abs()
		draw_rect(rect, Color(0.3, 0.8, 1, 0.16))
		draw_rect(rect, Color.CYAN, false, 2 / manager.view.zoom)
	for id: String in ids:
		var item: Control = resolve(id)
		if eligible(item) and not item in manager.cards:
			draw_rect(bounds(item).grow(3), Color.GOLD, false, 3 / manager.view.zoom)
func field_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			marquee = true
			start = event.position
			finish = start
			additive = event.ctrl_pressed or event.shift_pressed
			if not additive:
				clear()
		else:
			if marquee:
				finish = event.position
				select_rect(Rect2(start, finish - start).abs(), additive)
			marquee = false
		queue_redraw()
		return true
	if event is InputEventMouseMotion and marquee:
		finish = event.position
		queue_redraw()
		return true
	return false
func select_rect(rect: Rect2, append: bool = false) -> void:
	if not append:
		clear()
	if rect.size.length() < 4:
		return
	for item: Control in manager.cards + manager.extras.counters:
		if eligible(item) and rect.intersects(bounds(item)) and not ids.has(object_id(item)):
			ids.append(object_id(item))
	paint()
func object_input(item: Control, event: InputEvent) -> bool:
	var id: String = object_id(item)
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and manager.lab!=null and id in manager.lab.ids():
		manager.lab.open();manager.lab.menu(ids.duplicate() if ids.has(id) else [id]);return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and ids.has(id) and ids.size() > 1:
			open_bulk(item,event.position)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and not event.double_click:
			if event.ctrl_pressed or event.shift_pressed:
				toggle(item)
				return true
			if ids.has(id) and ids.size() > 1:
				moving = true
				drag_start = item.get_transform() * event.position
				origins.clear()
				for member: String in ids:
					var selected: Control = resolve(member)
					if eligible(selected):
						origins[member] = selected.position
						selected.dragging = true
						if selected in manager.cards:
							selected.hover_preview.hide()
							manager.drag_origins[member] = selected.position
				return true
			if not item in manager.cards:
				clear()
				ids.append(id)
				paint()
	if moving:
		if event is InputEventMouseMotion:
			move_group(item.get_transform() * event.position - drag_start)
			return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			moving = false
			for member: String in origins:
				var item_control: Control = resolve(member)
				if is_instance_valid(item_control):
					item_control.dragging = false
				var card: Control = manager.match_controller.card_by_id(member)
				if card != null:
					manager.finish_drag(card)
			origins.clear()
			return true
	return false
func move_group(delta: Vector2) -> void:
	for id: String in origins:
		var item: Control = resolve(id)
		if eligible(item):
			item.position = origins[id] + delta
			if item in manager.cards:
				item.state.position = item.position
	queue_redraw()
func apply_batch(action: String, instance_ids: Array) -> void:
	# A plain action + ID array is suitable for future public action serialization.
	var c: Node = manager.match_controller
	var ordered: Array = instance_ids.duplicate()
	if action == "top":
		ordered.reverse()
	var applied: Array[String] = []
	for id: String in ordered:
		var item: Control = resolve(id)
		if not selectable(item):
			continue
		if not item in manager.cards:
			if action == "delete":
				manager.extras.counters.erase(item)
				item.get_parent().remove_child(item)
				item.queue_free()
				applied.append(id)
			continue
		var owner: String = item.state.owner_player_id
		var success: bool = true
		match action:
			"graveyard", "exile", "hand": success = c.move_card(item, action, true, owner)
			"top", "bottom": success = c.move_card(item, "library", action == "top", owner)
			"delete": success = c.move_card(item, "graveyard", true, owner)
			"tap", "untap": item.set_tapped(action == "tap")
			"local", "opponent": c.change_controller(item, action)
			_: success = false
		if success:
			applied.append(id)
	if not applied.is_empty():
		var descriptions: Dictionary = {"graveyard": "moved to graveyard", "exile": "moved to exile", "hand": "moved to hand", "top": "put on library top", "bottom": "put on library bottom", "delete": "deleted (normal cards to owner's graveyard)", "tap": "tapped", "untap": "untapped", "local": "changed controller to Local player", "opponent": "changed controller to Opponent"}
		c.record_event("batch", "%s: %d selected objects %s" % [c.actor_name(), applied.size(), descriptions[action]], {"action": action, "instance_ids": applied})
		manager.controls.status.text = "%d selected objects updated." % applied.size()
	clear()
	c.refresh()
