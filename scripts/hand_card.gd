extends TextureRect
var instance_id: String
var controller: Node
var publicly_revealed: bool = false
func _ready() -> void:
	if publicly_revealed:
		var badge := EyeBadge.new()
		badge.name = "RevealBadge"
		badge.position = Vector2(48, 3)
		badge.size = Vector2(20, 16)
		badge.tooltip_text = "Opponent can currently see this card."
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(badge)
class EyeBadge extends Control:
	func _draw() -> void:
		draw_style_box(_background(), Rect2(Vector2.ZERO, size))
		var outline := PackedVector2Array([Vector2(2, 8), Vector2(6, 4), Vector2(14, 4), Vector2(18, 8), Vector2(14, 12), Vector2(6, 12), Vector2(2, 8)])
		draw_polyline(outline, Color.WHITE, 1.5, true)
		draw_circle(Vector2(10, 8), 2.5, Color.WHITE)
	func _background() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("102330")
		style.set_corner_radius_all(3)
		return style
func _process(_delta: float) -> void:
	queue_redraw()
func _draw() -> void:
	var selected: Control = controller.manager.selected_card
	if is_instance_valid(selected) and selected.state.match_instance_id == instance_id:
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color.GOLD, false, 3)
func _get_drag_data(_point: Vector2) -> Variant:
	if controller.hand_window != null and controller.hand_window.detached:
		return null
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(80, 112)
	set_drag_preview(icon)
	controller.hide_preview()
	return {"cardlink_instance": instance_id}
var held: bool = false
var press_point: Vector2
func _gui_input(event: InputEvent) -> void:
	if controller.hand_window == null or not controller.hand_window.detached: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		held = event.pressed
		press_point = event.position
	elif event is InputEventMouseMotion and held and event.button_mask & MOUSE_BUTTON_MASK_LEFT and event.position.distance_to(press_point)>8:
		controller.hand_window.begin_drag(instance_id)
		accept_event()
