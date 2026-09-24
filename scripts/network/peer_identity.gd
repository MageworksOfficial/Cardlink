extends RefCounted
## Connection identity only. Never implies ownership or gameplay authority.
var player_id: String = ""
var role: String = ""
var display_name: String = ""
func _init(id: String = "", side: String = "", caption: String = "") -> void:
	player_id = id
	role = side
	display_name = caption
func label() -> String:
	return "Not assigned" if player_id.is_empty() else "%s · %s · %s" % [player_id.replace("player_", "Player "), role.capitalize(), display_name]
