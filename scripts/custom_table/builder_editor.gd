extends Node
## Local editor gestures commit through the existing validated component operations.
var builder: Node
var root_ui: Control
var drawer: PanelContainer
var templates: Window
var bar: HBoxContainer
var table_label: Label
var perspective_label: Label
var empty: PanelContainer
var selected: String = ""
var saved_fingerprint: String = ""
var pending_kind: String = ""
var ghost_position := Vector2.ZERO
var overlay: Control
var gesture: Dictionary = {}
var guides: Array[Vector2] = []
var context: PopupMenu
var toast: Label
var toast_until: int = 0
var last_mode: bool = false
var last_turn: String = ""
var initialized: bool = false
func _ready() -> void:
	root_ui = Control.new()
	root_ui.hide()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.z_index = 210
	builder.manager.get_parent().add_child(root_ui)
	bar = HBoxContainer.new()
	root_ui.add_child(bar)
	bar.position = Vector2(12,85)
	add_button(bar,"Table Builder",toggle_drawer).tooltip_text = "Add or edit components · Ctrl+F finds cards and functions"
	add_button(bar,"Save Table",func() -> void: builder.panel.template_form(false))
	add_button(bar,"My Tables",func() -> void: templates.open_manager())
	table_label = Label.new()
	table_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	table_label.custom_minimum_size.x = 150
	bar.add_child(table_label)
	perspective_label = Label.new()
	root_ui.add_child(perspective_label)
	perspective_label.position = Vector2(14,123)
	drawer = preload("res://scripts/custom_table/builder_drawer.gd").new()
	drawer.editor = self
	root_ui.add_child(drawer)
	drawer.hide()
	templates = preload("res://scripts/custom_table/template_manager.gd").new()
	templates.editor = self
	add_child(templates)
	context = PopupMenu.new()
	context.id_pressed.connect(context_action)
	add_child(context)
	empty = PanelContainer.new()
	root_ui.add_child(empty)
	var content := VBoxContainer.new()
	empty.add_child(content)
	var heading := Label.new()
	heading.text = "BUILD YOUR OWN TABLE"
	heading.add_theme_font_size_override("font_size",24)
	content.add_child(heading)
	var hint := Label.new()
	hint.text = "Add a Deck, Hand, Zone, Shared Pile or Board Image."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	add_button(content,"+ Add Component",open_drawer)
	add_button(content,"Start with Simple Table",func() -> void: recipe(false))
	add_button(content,"Start with Shared Deck Table",func() -> void: recipe(true))
	toast = Label.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_color_override("font_color",Color("7de5ff"))
	root_ui.add_child(toast)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 400
	builder.manager.world.add_child(overlay)
	overlay.draw.connect(draw_overlay)
	builder.structure_changed.connect(structure_updated)
	get_viewport().size_changed.connect(fit)
	initialized = true
	fit()
	mark_saved()
	refresh()
func add_button(parent: Node, caption: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size.y = 32
	b.pressed.connect(action)
	parent.add_child(b)
	return b
func fit() -> void:
	if not initialized: return
	var screen: Vector2 = get_viewport().get_visible_rect().size
	drawer.position = Vector2(10,151)
	drawer.size = Vector2(minf(330,screen.x*0.42),maxf(160,screen.y-235))
	empty.size = Vector2(minf(450,screen.x-40),240)
	empty.position = (screen-empty.size)/2
	toast.position = Vector2(360,123)
	toast.size.x = maxf(160,screen.x-380)
	toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	table_label.custom_minimum_size.x = clampf(screen.x-500,120,360)
func _process(_delta: float) -> void:
	if not initialized: return
	root_ui.visible = builder.enabled and builder.manager.active
	if not root_ui.visible: return
	var mode: bool = builder.manager.layout.edit_mode
	if mode != last_mode:
		mode_changed(mode)
	var c: Node = builder.manager.match_controller
	var viewed: String = builder.global_player(builder.manager.perspective.viewed_player)
	var active: String = builder.global_player(c.model.active_player)
	var text: String = "TURN: "+badge(active)
	if viewed != active: text = "Viewing "+badge(viewed)+"  ·  "+text+"  ·  D follows the turn"
	if text != last_turn:
		last_turn = text
		perspective_label.text = text
		perspective_label.add_theme_color_override("font_color",accent(active))
	toast.visible = Time.get_ticks_msec() < toast_until
func mode_changed(mode: bool) -> void:
	if not initialized: return
	last_mode = mode
	cancel_gesture()
	cancel_placement()
	if not mode: drawer.hide()
	refresh()
func fingerprint() -> String: return JSON.stringify(builder.document)
func dirty() -> bool: return fingerprint() != saved_fingerprint
func mark_saved() -> void:
	saved_fingerprint = fingerprint()
	if initialized: refresh()
func notify(message: String) -> void:
	toast.text = message
	toast_until = Time.get_ticks_msec()+4000
	builder.manager.controls.status.text = message
func refresh() -> void:
	if not initialized: return
	empty.visible = builder.enabled and builder.document.components.is_empty() and not drawer.visible and pending_kind.is_empty()
	table_label.text = "Table: "+str(builder.document.name)+(" *" if dirty() else "")
	table_label.tooltip_text = "* means unsaved table-layout changes"
	bar.get_child(1).visible = builder.manager.layout.edit_mode
	if drawer.visible: drawer.refresh()
	for view: Control in builder.views.values(): view.queue_redraw()
func structure_updated() -> void:
	if not builder.row(selected).is_empty(): pass
	else: selected = ""
	refresh()
func open_drawer() -> void:
	if not builder.enabled: return
	builder.manager.layout.set_edit_mode(true)
	drawer.show()
	refresh()
func toggle_drawer() -> void:
	if drawer.visible: drawer.hide(); refresh()
	else: open_drawer()
func focus_search() -> void:
	open_drawer()
	drawer.search.grab_focus()
	drawer.search.select_all()
func select_component(id: String) -> void:
	selected = id
	if builder.manager.layout.edit_mode: drawer.show()
	refresh()
func begin_placement(kind: String) -> void:
	builder.manager.layout.set_edit_mode(true)
	pending_kind = kind
	selected = ""
	drawer.hide()
	ghost_position = builder.manager.world.get_local_mouse_position()
	notify("Click to place · Escape to cancel")
	overlay.queue_redraw()
	refresh()
func cancel_placement() -> void:
	pending_kind = ""
	if overlay != null: overlay.queue_redraw()
	refresh()
func place_at(point: Vector2) -> Dictionary:
	if pending_kind.is_empty(): return {}
	var kind: String = pending_kind
	pending_kind = ""
	if kind == "token":
		builder.manager.extras.token_editor.open_token()
		notify("Name your token; then drag it into position.")
		refresh()
		return {}
	if kind == "counter":
		builder.manager.extras.open_counter(builder.manager.extras.create_counter(point))
		refresh()
		return {}
	var item: Dictionary = builder.add_component(kind,"player_1" if kind in ["deck","hand"] else "table")
	if item.has("error"): notify(item.error); return item
	builder.update_component(item.id,{"position":[point.x,point.y]})
	select_component(item.id)
	notify(item.name+" added.")
	overlay.queue_redraw()
	return builder.row(item.id)
func _input(event: InputEvent) -> void:
	if not initialized or not builder.enabled or not builder.manager.active: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not pending_kind.is_empty() or not gesture.is_empty():
			cancel_gesture(); cancel_placement(); get_viewport().set_input_as_handled()
	if not pending_kind.is_empty():
		if event is InputEventMouseMotion:
			ghost_position = builder.manager.world.get_local_mouse_position()
			overlay.queue_redraw()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.position.y > 151 and event.position.y < get_viewport().get_visible_rect().size.y-80:
				place_at(ghost_position)
				get_viewport().set_input_as_handled()
	if not gesture.is_empty():
		if event is InputEventMouseMotion: transform_to(builder.manager.world.get_local_mouse_position()); get_viewport().set_input_as_handled()
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			finish_gesture(); get_viewport().set_input_as_handled()
func begin_transform(id: String, point: Vector2, handle: Vector2 = Vector2.ZERO) -> void:
	select_component(id)
	var item: Dictionary = builder.row(id)
	if item.locked: notify("Component locked. Unlock it to move or resize."); return
	gesture = {"id":id,"mouse":point,"position":Vector2(item.position[0],item.position[1]),"size":Vector2(item.size[0],item.size[1]),"handle":handle}
func transform_to(point: Vector2) -> void:
	if gesture.is_empty(): return
	var view: Control = builder.views.get(gesture.id)
	if not is_instance_valid(view): cancel_gesture(); return
	var delta: Vector2 = point-gesture.mouse
	guides.clear()
	if gesture.handle == Vector2.ZERO:
		view.position = snap_position(gesture.position+delta,view.size,gesture.id)
	else:
		var a: Vector2 = gesture.position
		var b: Vector2 = a+gesture.size
		if gesture.handle.x < 0: a.x = minf(a.x+delta.x,b.x-80)
		else: b.x = maxf(b.x+delta.x,a.x+80)
		if gesture.handle.y < 0: a.y = minf(a.y+delta.y,b.y-80)
		else: b.y = maxf(b.y+delta.y,a.y+80)
		view.position = a.clamp(Vector2(-20000,-20000),Vector2(20000,20000))
		view.size = (b-a).clamp(Vector2(80,80),Vector2(8000,8000))
	view.queue_redraw()
	overlay.queue_redraw()
func snap_position(point: Vector2, extent: Vector2, ignore: String) -> Vector2:
	var result: Vector2 = point.snapped(Vector2(20,20))
	var xs: Array[float] = [float(builder.document.dimensions[0])/2]
	var ys: Array[float] = [float(builder.document.dimensions[1])/2]
	for item: Dictionary in builder.document.components:
		if item.id == ignore or item.hidden: continue
		for fraction: float in [0.0,0.5,1.0]:
			xs.append(item.position[0]+item.size[0]*fraction)
			ys.append(item.position[1]+item.size[1]*fraction)
	var threshold: float = 8.0/maxf(builder.manager.view.zoom,0.4)
	var best_x: float = threshold
	var best_y: float = threshold
	for fraction: float in [0.0,0.5,1.0]:
		for x: float in xs:
			var distance: float = absf(point.x+extent.x*fraction-x)
			if distance < best_x: best_x = distance; result.x = x-extent.x*fraction
		for y: float in ys:
			var distance: float = absf(point.y+extent.y*fraction-y)
			if distance < best_y: best_y = distance; result.y = y-extent.y*fraction
	guides = [Vector2(result.x,-1),Vector2(-1,result.y)]
	return result.clamp(Vector2(-20000,-20000),Vector2(20000,20000))
func finish_gesture() -> void:
	if gesture.is_empty(): return
	var id: String = gesture.id
	var view: Control = builder.views.get(id)
	gesture.clear()
	guides.clear()
	if is_instance_valid(view):
		if not builder.update_component(id,{"position":[view.position.x,view.position.y],"size":[view.size.x,view.size.y]}): view.refresh()
	overlay.queue_redraw()
func cancel_gesture() -> void:
	if not gesture.is_empty() and builder.views.has(gesture.id): builder.views[gesture.id].refresh()
	gesture.clear()
	guides.clear()
	if overlay != null: overlay.queue_redraw()
func draw_overlay() -> void:
	if not builder.manager.layout.edit_mode: return
	if not pending_kind.is_empty():
		var extent := Vector2(220,160)
		overlay.draw_rect(Rect2(ghost_position,extent),Color(0.1,0.7,0.9,0.22))
		overlay.draw_rect(Rect2(ghost_position,extent),Color.CYAN,false,3)
	for guide: Vector2 in guides:
		if guide.x >= 0: overlay.draw_line(Vector2(guide.x,0),Vector2(guide.x,builder.document.dimensions[1]),Color(0.2,0.9,1,0.5),2)
		else: overlay.draw_line(Vector2(0,guide.y),Vector2(builder.document.dimensions[0],guide.y),Color(0.2,0.9,1,0.5),2)
func duplicate_component(id: String, other_player: bool = false) -> Dictionary:
	var original: Dictionary = builder.row(id)
	if original.is_empty(): return {}
	var owner: String = original.owner
	if other_player and owner != "table": owner = "player_2" if owner == "player_1" else "player_1"
	var item: Dictionary = builder.add_component(original.kind,owner)
	if item.has("error"): notify(item.error); return item
	var changes: Dictionary = original.duplicate(true)
	changes.erase("id")
	changes.owner = owner
	changes.name = original.name+" Copy"
	changes.linked_pile = "" if original.linked_pile == id else original.linked_pile
	changes.position = [original.position[0]+60,original.position[1]+60]
	builder.update_component(item.id,changes)
	select_component(item.id)
	notify("Component duplicated — structure only.")
	return builder.row(item.id)
func lock_all(value: bool) -> void:
	for item: Dictionary in builder.document.components.duplicate(true): builder.update_component(item.id,{"locked":value})
	notify("All components locked." if value else "All components unlocked.")
func recipe(shared: bool) -> void:
	if not builder.document.components.is_empty(): notify("Recipes start on an empty table."); return
	for player: String in ["player_1","player_2"]:
		var x: float = 420 if player == "player_1" else 1600
		if not shared:
			var deck: Dictionary = builder.add_component("deck",player)
			builder.update_component(deck.id,{"name":badge(player)+" Main Deck","position":[x,300]})
			builder.set_primary(deck.id)
		var hand: Dictionary = builder.add_component("hand",player)
		builder.update_component(hand.id,{"name":badge(player)+" Hand","position":[x,700]})
	if shared:
		var deck: Dictionary = builder.add_component("shared_deck")
		builder.update_component(deck.id,{"position":[1000,350]})
		builder.set_primary(deck.id)
		var discard: Dictionary = builder.add_component("discard")
		builder.update_component(discard.id,{"name":"Shared Discard","position":[1250,350],"linked_pile":deck.id})
	var area: Dictionary = builder.add_component("shared_area")
	builder.update_component(area.id,{"name":"Shared Play Area","position":[750,650],"size":[650,400]})
	open_drawer()
	notify("Editable table created. Load your own cards into its piles.")
func context_menu(id: String) -> void:
	selected = id
	if builder.manager.layout.edit_mode: select_component(id)
	var item: Dictionary = builder.row(id)
	context.clear()
	if item.kind in ["deck","shared_deck"]:
		context.add_item(("✓ Primary Draw Pile" if item.linked_pile == id else ("Use as Shared Draw Source" if item.owner == "table" else "Set as Primary Draw Pile")),1)
		context.add_item("Draw to Active Player",2)
		context.add_item("Load Saved Deck",3)
		context.add_item("Shuffle",8)
		context.add_item("Change Deck Back",9)
	context.add_item("More / Properties",4)
	if builder.manager.layout.edit_mode:
		context.add_item("Unlock" if item.locked else "Lock",5)
		context.add_item("Duplicate Component",6)
		context.add_item("Remove Component",7)
	context.position = Vector2i(get_viewport().get_mouse_position())
	context.popup()
func context_action(action: int) -> void:
	var item: Dictionary = builder.row(selected)
	if item.is_empty(): return
	match action:
		1: builder.set_primary(selected); notify("Primary Draw set to "+item.name+".")
		2: builder.draw(selected,builder.global_player(builder.manager.match_controller.model.active_player))
		3: builder.panel.deck_list(selected); builder.panel.show_panel()
		4: builder.panel.open_component(selected)
		5: builder.update_component(selected,{"locked":not item.locked})
		6: duplicate_component(selected)
		7: drawer.remove_selected()
		8: builder.shuffle(selected)
		9: builder.manager.appearance.sleeves.open(selected)
static func badge(owner: String) -> String: return {"player_1":"P1","player_2":"P2","table":"SHARED"}.get(owner,owner)
static func accent(owner: String) -> Color: return Color({"player_1":"72c9ff","player_2":"e3adf3","table":"61ddd6"}.get(owner,"61ddd6"))
func _exit_tree() -> void:
	if is_instance_valid(root_ui): root_ui.queue_free()
	if is_instance_valid(overlay): overlay.queue_free()

