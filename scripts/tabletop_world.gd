extends Control
const LOGICAL_SIZE := Vector2(2304, 1296)
var controller: Node
var table_color: Color = Color("152d40")
func _has_point(point: Vector2) -> bool:
	# Panning/zooming must not leave undroppable strips of empty battlefield.
	return get_viewport_rect().has_point(get_global_transform() * point)
func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("cardlink_instance") is String and controller.card_by_id(data.cardlink_instance) != null
func _drop_data(point: Vector2, data: Variant) -> void:
	var card: Control = controller.card_by_id(data.cardlink_instance)
	var ids: Array=controller.library_actions.hand_drag_ids(data.cardlink_instance)
	if ids.is_empty(): ids=[data.cardlink_instance]
	controller.library_actions.place_cards(ids,point-card.size/2,controller.library_actions.enter_face_down)

func _gui_input(event: InputEvent) -> void:
	if controller!=null and controller.manager.appearance!=null and controller.manager.appearance.input(event): accept_event();return
	if controller != null and controller.manager.selection != null and controller.manager.selection.field_input(event):
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and controller != null:
		controller.manager.extras.open_field(get_global_transform() * event.position)
		accept_event()
func _draw() -> void:
	var extent: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, extent), table_color)
	draw_rect(Rect2(0, 0, extent.x, 130), Color("142330"))
	draw_rect(Rect2(0, 1000, extent.x, 296), Color("162b32"))
	for x: int in range(0, int(extent.x), 100):
		draw_line(Vector2(x, 130), Vector2(x, extent.y), Color(0.4, 0.65, 0.7, 0.08))
	for y: int in range(130, int(extent.y), 100):
		draw_line(Vector2(0, y), Vector2(extent.x, y), Color(0.4, 0.65, 0.7, 0.08))
	draw_rect(Rect2(Vector2.ZERO, extent), Color("44626b"), false, 3)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(18, 30), "", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8098a5"))
	draw_string(font, Vector2(650, 160), "", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8098a5"))
	draw_string(font, Vector2(18, 1030), "", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8098a5"))
