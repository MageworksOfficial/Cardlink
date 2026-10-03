extends Control
signal selected(card: Control)
signal drag_started(card: Control)
signal drag_finished(card: Control)
signal actions_requested(card: Control)
signal properties_requested(card: Control)
signal quick_tap_requested(card: Control)
var drag_moved: bool = false
const InstanceState = preload("res://scripts/card_instance_state.gd")
var state: InstanceState = InstanceState.new()
var selection: Control
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var tapped: bool = false
var is_selected: bool = false
var counter_label: Label
var card_back: TextureRect
var token_label: Label
@onready var card_image: TextureRect = $CardImage
@onready var hover_preview: TextureRect = $HoverPreview
func _ready() -> void:
	card_image.pivot_offset = card_image.size / 2.0
	hover_preview.visible = false
	hover_preview.z_index = 100
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	counter_label = Label.new()
	counter_label.position = Vector2(4, 4)
	counter_label.size = Vector2(242, 60)
	counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counter_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	counter_label.add_theme_constant_override("shadow_outline_size", 5)
	add_child(counter_label)
	state.position = position
	card_back = TextureRect.new()
	card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_image.add_child(card_back)
	card_back.hide()
	if state.is_token:
		token_label = Label.new()
		token_label.text = state.display_name
		token_label.position = Vector2(4, 50)
		token_label.size = Vector2(92, 70)
		token_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		token_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token_label.add_theme_color_override("font_color", Color.BLACK)
		add_child(token_label)
func set_face_down(value: bool) -> void:
	state.face_down = value
	state.custom_metadata.erase("public_reveal")
	state.visibility = "owner_private" if state.current_zone in ["hand", "library"] else ("face_down_public" if value else "public")
	card_back.visible = value
	hover_preview.hide()
func _gui_input(event: InputEvent) -> void:
	if selection != null and selection.object_input(self, event):
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
			dragging = false
			hover_preview.hide()
			selected.emit(self)
			if state.current_zone in ["battlefield","custom","custom_zone"]: quick_tap_requested.emit(self)
			else: actions_requested.emit(self)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				selected.emit(self)
				drag_moved = false
				dragging = true
				drag_offset = event.position
				hover_preview.visible = false
			else:
				if dragging:
					dragging = false
					state.position = position
					if drag_moved: drag_finished.emit(self)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			selected.emit(self)
			dragging = false
			hover_preview.hide()
			actions_requested.emit(self)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		if not drag_moved and (event.position-drag_offset).length()*get_global_transform().x.length() < 4: return
		if not drag_moved: drag_started.emit(self)
		drag_moved = true
		position += get_transform().basis_xform(event.position - drag_offset)
		state.position = position
		accept_event()
func set_tapped(value: bool) -> void:
	tapped = value
	state.tapped = value
	card_image.rotation_degrees = 90.0 if tapped else 0.0
	queue_redraw()
func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()
func _draw() -> void:
	if is_instance_valid(card_image) and card_image.texture == null:
		draw_set_transform_matrix(card_image.get_transform())
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.86, 0.7))
	if is_selected and is_instance_valid(card_image):
		draw_set_transform_matrix(card_image.get_transform())
		draw_rect(Rect2(Vector2(-3, -3), card_image.size + Vector2(6, 6)), Color(1, 0.8, 0.2), false, 3 / maxf(0.4,get_global_transform().x.length()))
func update_counters() -> void:
	var lines: Array[String] = []
	for key: String in state.counters:
		lines.append("%s: %d" % [key, state.counters[key]])
	var total: int = 0
	for value: int in state.counters.values():
		total += value
	counter_label.text = ("★ %d
" % total + "\n".join(lines)) if not state.counters.is_empty() else ""
func _on_mouse_entered() -> void:
	if not dragging and not state.face_down and state.identity_visible:
		var viewport_size: Vector2 = get_viewport_rect().size
		hover_preview.scale = Vector2.ONE / get_global_transform().get_scale()
		hover_preview.global_position = Vector2(clampf(global_position.x + size.x * get_global_transform().get_scale().x + 20, 0, maxf(0, viewport_size.x - hover_preview.size.x)), clampf(global_position.y, 0, maxf(0, viewport_size.y - hover_preview.size.y)))
		hover_preview.visible = true
func _on_mouse_exited() -> void:
	hover_preview.visible = false
func _has_point(point: Vector2) -> bool:
	var visual := get_node("CardImage") as Control
	return Rect2(Vector2.ZERO, visual.size).has_point(visual.get_transform().affine_inverse() * point)



func show_placeholder() -> void:
	if token_label == null:
		token_label = Label.new()
		token_label.position = Vector2(4, 45)
		token_label.size = Vector2(92, 90)
		token_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		token_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token_label.add_theme_color_override("font_color", Color.BLACK)
		add_child(token_label)
	token_label.text = state.display_name if state.is_token else "Missing image\n" + state.display_name
	queue_redraw()

func update_token_display() -> void:
	if token_label == null:
		return
	var power: String = str(state.custom_metadata.get("power", ""))
	var toughness: String = str(state.custom_metadata.get("toughness", ""))
	token_label.text = state.display_name + ("\n%s/%s" % [power if not power.is_empty() else "-", toughness if not toughness.is_empty() else "-"] if not power.is_empty() or not toughness.is_empty() else "")
	token_label.add_theme_color_override("font_color", Color.WHITE)
	token_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	token_label.add_theme_constant_override("shadow_outline_size", 4)
