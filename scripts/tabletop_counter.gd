extends PanelContainer
signal properties_requested(counter: Control)
var instance_id: String = "counter_" + Crypto.new().generate_random_bytes(16).hex_encode()
var value: int = 1
var caption: String = ""
var selection: Control
var dragging: bool = false
var drag_offset: Vector2
var label: Label
func _ready() -> void:
	custom_minimum_size = Vector2(72, 44)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("283b50")
	style.border_color = Color("eac26b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	refresh()
func refresh() -> void:
	if label != null:
		label.text = "★ %d" % value + ("\n" + caption if not caption.is_empty() else "")
	tooltip_text = "Drag to move. Right-click or double-click to edit."
func _gui_input(event: InputEvent) -> void:
	if selection != null and selection.object_input(self, event):
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.pressed and (event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and event.double_click)):
			dragging = false
			properties_requested.emit(self)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			drag_offset = event.position
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		position += get_transform().basis_xform(event.position - drag_offset)
		accept_event()
func to_data() -> Dictionary:
	return {"instance_id": instance_id, "value": value, "label": caption, "position": [position.x, position.y]}
