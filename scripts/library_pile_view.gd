extends Button
## A visible pile; the ordered match IDs live in LibraryPile, not this view.
var controller: Node
var player_id: String = "local"
var back_image: TextureRect
var caption: Label
var stack_depth: int = 0
var click_pending: bool = false
var click_generation: int = 0
func _ready() -> void:
	position = Vector2(205, 155)
	size = Vector2(100, 140)
	tooltip_text = "Click to draw. Right-click for Library Actions. Drag in Edit Layout Mode."
	var back := StyleBoxFlat.new()
	back.bg_color = Color("263d65")
	back.border_color = Color("7793ba")
	back.set_border_width_all(3)
	back.set_corner_radius_all(8)
	add_theme_stylebox_override("normal", back)
	back_image = TextureRect.new()
	back_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back_image)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_outline_size", 5)
	add_child(caption)
func refresh() -> void:
	var order: Array = controller.model.players[player_id].library.order
	var count: int = controller.hidden_count(player_id, "library")
	stack_depth = mini(12, ceili(count / 8.0))
	back_image.texture = controller.manager.backs.texture()
	if count > 0:
		var rows: Array = controller.library_rows(player_id)
		if not rows.is_empty() and rows[0].known: back_image.texture = rows[0].texture
	back_image.visible = count > 0
	caption.text = "%d\ncards" % count
	var zoom: float = controller.manager.view.zoom if controller.manager.view != null else 1.0
	caption.add_theme_font_size_override("font_size", roundi(16.0 / minf(1.0, zoom)))
	queue_redraw()


var layout_dragging: bool = false
var layout_offset: Vector2
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		click_generation += 1
		click_pending = false
		layout_dragging = false
		controller.manager.controls.open_library_actions(player_id)
		accept_event()
		return
	if controller.manager.layout == null or not controller.manager.layout.edit_mode:
		layout_dragging = false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.double_click:
				click_generation += 1
				click_pending = false
				controller.manager.controls.open_library_actions(player_id)
			elif event.pressed:
				click_pending = true
			elif click_pending:
				click_pending = false
				delayed_draw()
			accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		layout_dragging = event.pressed
		layout_offset = event.position
		accept_event()
	elif event is InputEventMouseMotion and layout_dragging:
		position = controller.manager.organization.snap(position+get_transform().basis_xform(event.position-layout_offset),size)
		accept_event()
func delayed_draw() -> void:
	click_generation += 1
	var generation: int = click_generation
	var original_pile: RefCounted = controller.model.players[player_id].library
	var original_top: Array[String] = original_pile.peek(1)
	await get_tree().create_timer(0.5).timeout
	if generation != click_generation or not controller.manager.active or controller.manager.layout.edit_mode or controller.contents.visible or controller.review.visible:
		return
	if controller.manager.extras != null and controller.manager.extras.is_modal():
		return
	for popup: PopupPanel in controller.manager.controls.panels.values():
		if popup.visible:
			return
	if controller.model.players[player_id].library == original_pile and original_pile.peek(1) == original_top:
		controller.draw_card(player_id)

func _draw() -> void:
	for layer: int in range(stack_depth, 0, -1):
		var rect := Rect2(Vector2(layer * 1.5, layer * 2.0), size)
		draw_rect(rect, Color("bac4ca"))
		draw_rect(rect, Color("253843"), false, 1.5)
