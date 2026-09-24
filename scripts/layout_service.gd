extends RefCounted
var manager: Node
var edit_mode: bool = false
var preset_name: String = "Default"
var ui_scale: float = 1.0
func _init(table: Node) -> void:
	manager = table
func set_edit_mode(value: bool) -> void:
	edit_mode = value
	if manager.controls.edit_button != null:
		manager.controls.edit_button.set_pressed_no_signal(value)
	for zone: Control in manager.zones:
		zone.edit_enabled = value
		zone.dragging = false
	manager.controls.status.text = "Edit Layout: drag zone headers, piles, hand title, or life display." if value else "Play Mode: layout locked; cards remain playable."
func capture() -> Dictionary:
	if manager.perspective != null: manager.perspective.read_heart_positions()
	var zones: Array[Dictionary] = []
	for zone: Control in manager.zones:
		var row: Dictionary = zone.to_data()
		row.position = [zone.position.x, zone.position.y]
		row["size"] = [zone.size.x, zone.size.y]
		zones.append(row)
	var heart_positions: Dictionary = {}
	for player: String in manager.match_controller.hearts.hearts:
		heart_positions[player] = vector_data(manager.perspective.heart_position(player) if manager.perspective != null else manager.match_controller.hearts.hearts[player].get_parent().position)
	var match_ui: Node = manager.match_controller
	return {"schema_version": 1, "heart_positions":heart_positions, "preset_name": preset_name, "zones": zones,
		"library_positions": {"local": vector_data(match_ui.pile_view.position), "opponent": vector_data(match_ui.opponent_pile.position)},
		"hand_position": vector_data(match_ui.hand_window.main_layout.position if match_ui.hand_window.detached else match_ui.hand.position), "hand_size": vector_data(match_ui.hand_window.main_layout.size if match_ui.hand_window.detached else match_ui.hand.size),
		"life_position": vector_data(manager.life_display.position),
		"zoom": manager.view.zoom, "pan": vector_data(manager.view.pan), "ui_scale": ui_scale}
static func vector_data(point: Vector2) -> Array:
	return [point.x, point.y]
static func vector_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0]) and number(value[1]) and absf(value[0]) <= 1000000 and absf(value[1]) <= 1000000
static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
static func validate(data: Dictionary) -> String:
	if data.get("schema_version") != 1 or not data.get("preset_name") is String:
		return "Unsupported layout format."
	for field: String in ["hand_position", "hand_size", "life_position", "pan"]:
		if not vector_valid(data.get(field)):
			return "Invalid layout " + field
	if not number(data.get("zoom")) or data.zoom < 0.4 or data.zoom > 2.0 or not number(data.get("ui_scale")) or data.ui_scale < 0.75 or data.ui_scale > 1.5:
		return "Invalid layout zoom or UI scale."
	if data.hand_size[0] < 100 or data.hand_size[1] < 60:
		return "Invalid hand area size."
	if not data.get("library_positions") is Dictionary:
		return "Missing library positions."
	for id: String in ["local", "opponent"]:
		if not vector_valid(data.library_positions.get(id)):
			return "Invalid library position."
	if not data.get("zones") is Array or data.zones.size() > 200:
		return "Invalid layout zones."
	if not data.get("heart_positions",{}) is Dictionary: return "Invalid life anchors."
	for player: Variant in data.get("heart_positions",{}):
		if player not in ["local","opponent"] or not vector_valid(data.heart_positions[player]): return "Invalid life anchor."
	var ids: Dictionary = {}
	for zone: Variant in data.zones:
		if not zone is Dictionary:
			return "Invalid zone."
		for field: String in ["zone_id", "display_name", "zone_type", "player_id"]:
			if not zone.get(field) is String or str(zone[field]).is_empty():
				return "Invalid zone " + field
		if ids.has(zone.zone_id) or not zone.player_id in ["local", "opponent"]:
			return "Duplicate zone or invalid player."
		ids[zone.zone_id] = true
		if not vector_valid(zone.get("position")) or not vector_valid(zone.get("size")) or zone.size[0] < 40 or zone.size[1] < 40:
			return "Invalid zone geometry."
		if not number(zone.get("capacity")) or zone.capacity < 0 or zone.capacity != floor(zone.capacity):
			return "Invalid zone capacity."
	return ""
func apply(data: Dictionary, include_zones: bool = true) -> Dictionary:
	var error: String = validate(data)
	if not error.is_empty():
		return {"error": error}
	preset_name = data.preset_name
	if include_zones:
		for saved: Dictionary in data.zones:
			var zone: Control = manager.find_zone(saved.zone_id)
			if zone == null:
				# Presets match same-role zones when applied to a different match.
				for candidate: Control in manager.zones:
					if candidate.player_id == saved.player_id and candidate.zone_type == saved.zone_type and (saved.zone_type != "custom" or candidate.display_name == saved.display_name):
						zone = candidate
						break
			if zone == null:
				var create: Dictionary = saved.duplicate(true)
				create.position = Vector2(saved.position[0], saved.position[1])
				zone = manager.add_zone(create)
			zone.move_to(Vector2(saved.position[0], saved.position[1]))
			zone.custom_minimum_size = Vector2(saved.size[0], saved.size[1])
			zone.size = zone.custom_minimum_size
	var c: Node = manager.match_controller
	c.pile_view.position = Vector2(data.library_positions.local[0], data.library_positions.local[1])
	c.opponent_pile.position = Vector2(data.library_positions.opponent[0], data.library_positions.opponent[1])
	if c.hand_window.detached:
		c.hand_window.main_layout = {"position":Vector2(data.hand_position[0],data.hand_position[1]),"size":Vector2(data.hand_size[0],data.hand_size[1])}
	else:
		c.hand.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		c.hand.position = Vector2(data.hand_position[0], data.hand_position[1])
		c.hand.size = Vector2(data.hand_size[0], data.hand_size[1])
	for player: String in data.get("heart_positions",{}):
		c.hearts.hearts[player].get_parent().position = Vector2(data.heart_positions[player][0],data.heart_positions[player][1])
		if manager.perspective != null: manager.perspective.heart_anchors[player] = c.hearts.hearts[player].get_parent().position
	manager.life_display.position = Vector2(data.life_position[0], data.life_position[1])
	manager.view.zoom = data.zoom
	manager.view.pan = Vector2(data.pan[0], data.pan[1])
	manager.view.apply_view()
	ui_scale = data.ui_scale
	manager.controls.add_theme_font_size_override("font_size", roundi(14 * ui_scale))
	manager.controls.refresh_zones()
	return {"applied": true}
func built_in(caption: String) -> Dictionary:
	var result: Dictionary = capture()
	result.preset_name = caption
	result.zoom = 1.0
	result.pan = [0, 0]
	result.ui_scale = 1.0
	var view_size: Vector2 = manager.get_viewport().get_visible_rect().size
	var left_handed: bool = caption == "Left-handed"
	result.library_positions = {"local": [view_size.x - 135 if left_handed else 30, 300], "opponent": [30 if left_handed else view_size.x - 135, 75]}
	result.hand_position = [0, view_size.y - 202]
	result.hand_size = [view_size.x, 140]
	result.life_position = [maxf(10, view_size.x - 330), 80]
	result.zones = []
	for player_id: String in ["local", "opponent"]:
		var kinds: Array[String] = ["graveyard", "exile"]
		if caption == "Commander":
			kinds.append("commander")
		for i: int in kinds.size():
			var x: float = 160 + i * 160
			if left_handed:
				x = view_size.x - 305 - i * 160
			result.zones.append({"zone_id": player_id + "_" + kinds[i], "display_name": ("Your " if player_id == "local" else "Opponent ") + kinds[i].capitalize(),
				"zone_type": kinds[i], "player_id": player_id, "capacity": 0, "position": [x, 300 if player_id == "local" else 75], "size": [145, 160]})
	return result


