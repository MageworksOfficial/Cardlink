extends PanelContainer
signal context_requested(zone: Control)
var layout_service: RefCounted
signal moved(zone: Control, delta: Vector2)
var zone_id: String = "zone_" + Crypto.new().generate_random_bytes(16).hex_encode()
var display_name: String = "Custom Zone"
var zone_type: String = "custom"
var capacity: int = 0
var player_id: String = "local"
var edit_enabled: bool = false
var members: Array[String] = []
var dragging: bool = false
var drag_offset: Vector2
var title: Label
func _ready() -> void:
	custom_minimum_size = Vector2(290, 410)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.16, 0.19, 0.65)
	style.border_color = Color(0.35, 0.58, 0.63)
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	var header := PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.custom_minimum_size.y = 36
	header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.gui_input.connect(_header_input)
	add_child(header)
	title = Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = "Drag this header to move the zone and its cards"
	header.add_child(title)
	update_title()
func configure(data: Dictionary) -> void:
	zone_id = str(data.get("zone_id", zone_id))
	player_id = str(data.get("player_id", "local"))
	display_name = str(data.get("display_name", "Custom Zone"))
	zone_type = str(data.get("zone_type", "custom"))
	capacity = maxi(0, int(data.get("capacity", 0)))
	position = data.get("position", Vector2(400, 110))
	if is_node_ready():
		update_title()
func update_title() -> void:
	title.add_theme_font_size_override("font_size",roundi(12/maxf(0.4,get_global_transform().get_scale().x)))
	title.tooltip_text = display_name
	var caption: String = "Leader" if zone_type == "commander" else zone_type.capitalize() if zone_type in ["graveyard","exile","commander"] else display_name
	title.text = "%s · %d%s" % [caption, members.size(), "/%d" % capacity if capacity > 0 else ""]
func _header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit(self)
		accept_event()
		return
	if not edit_enabled:
		dragging = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		drag_offset = event.position
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		move_to(layout_service.snap(position+get_transform().basis_xform(event.position-drag_offset),size) if layout_service != null else position+get_transform().basis_xform(event.position-drag_offset))
		accept_event()
func move_to(point: Vector2) -> void:
	var delta: Vector2 = point - position
	position = point
	moved.emit(self, delta)
func can_accept(instance_id: String) -> bool:
	return members.has(instance_id) or capacity == 0 or members.size() < capacity
func to_data() -> Dictionary:
	return {"zone_id": zone_id, "display_name": display_name, "zone_type": zone_type, "position": position, "capacity": capacity, "player_id": player_id}



