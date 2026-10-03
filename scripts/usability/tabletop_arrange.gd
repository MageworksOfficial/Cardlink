extends RefCounted
## Uses the existing transient selection and public movement scanner.
const Layout = preload("res://scripts/usability/arrange_layout.gd")
const Action = preload("res://scripts/network/network_action.gd")
var selection: Control
var menu: PopupMenu
func _init(owner: Control) -> void: selection = owner
func setup() -> void:
	menu = PopupMenu.new(); menu.name = "Arrange"
	menu.min_size = Vector2i(290,0)
	menu.add_theme_font_size_override("font_size",18)
	menu.add_theme_constant_override("v_separation",10)
	selection.bulk.add_child(menu)
	for caption: String in Layout.MODES: menu.add_item(caption)
	menu.id_pressed.connect(apply)
	selection.bulk.add_submenu_item("Arrange", "Arrange", 100)
func reason() -> String:
	var m: Node = selection.manager
	if not m.active or selection.moving: return "Finish the current action before arranging."
	if selection.ids.size() < 2: return "Select multiple battlefield objects first."
	if m.match_controller.online() and selection.ids.size() > 200: return "Arrange up to 200 objects at a time online."
	for id: String in selection.ids:
		var item: Control = selection.resolve(id)
		if not selection.eligible(item): return "Select multiple battlefield objects first. Hand and hidden-pile cards cannot be arranged."
		if item in m.cards:
			if not item.state.current_zone in ["battlefield","custom","custom_zone"]: return "Arrange supports battlefield objects only. Remove zone or hand cards from the selection."
		elif not item in m.extras.counters: return "Arrange supports cards, tokens and standalone counters only."
		if item.dragging: return "Finish dragging before arranging."
	return ""
func update_menu() -> void:
	var index: int = selection.bulk.get_item_index(100)
	var message: String = reason()
	selection.bulk.set_item_disabled(index,not message.is_empty())
	selection.bulk.set_item_tooltip(index,message)
func open() -> void:
	var m: Node = selection.manager
	var message: String = reason()
	if not message.is_empty(): m.controls.status.text = message; return
	m.controls.close_panels(); m.match_controller.hide_preview()
	var screen: Vector2 = m.get_viewport().get_visible_rect().size
	menu.reset_size()
	menu.position = Vector2i((screen-Vector2(menu.size))/2)
	menu.popup()
func apply(mode: int) -> void:
	var m: Node = selection.manager
	var message: String = reason()
	if not message.is_empty(): m.controls.status.text = message; return
	var items: Array[Control] = []
	for id: String in selection.ids: items.append(selection.resolve(id))
	items.sort_custom(func(a: Control,b: Control) -> bool:
		return a.get_index() < b.get_index() if a.z_index == b.z_index else a.z_index < b.z_index)
	var rects: Array = []
	for item: Control in items: rects.append(selection.bounds(item))
	var targets: Array[Vector2] = Layout.positions(rects,mode,Rect2(Vector2.ZERO,m.world.size))
	if targets.size() != items.size(): return
	for i: int in items.size(): targets[i] -= rects[i].position-items[i].position
	# Refuse the whole operation if it would exceed the unchanged wire bounds.
	var router: Node = m.match_controller.public_sync
	if m.match_controller.online():
		if router.network.quiesced or router.recovery.suspended or router.journal.pending.size() >= 256:
			m.controls.status.text = "Wait for the connection to recover before arranging."
			return
		for i: int in items.size():
			if not Action.position(router.serializer.encode_position(targets[i],140 if items[i] in m.cards else 44)):
				m.controls.status.text = "This arrangement exceeds online table limits. Select fewer objects."
				return
	# Complete synchronously; the existing scanner sends a single bounded move batch.
	m.undo.begin("Arrange: "+Layout.MODES[mode])
	for i: int in items.size():
		items[i].position = targets[i]
		if items[i] in m.cards: items[i].state.position = targets[i]
	selection.paint()
	if m.match_controller.online(): router.scan()
	m.undo.finish()
	m.controls.status.text = "Arranged %d objects: %s" % [items.size(),Layout.MODES[mode]]
