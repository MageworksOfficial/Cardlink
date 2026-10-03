extends RefCounted
## Definition identity, ownership, control and zone holder are independent.
var faces: Array = []
var active_face_index: int = 0
var match_instance_id: String = "match_" + Crypto.new().generate_random_bytes(16).hex_encode()
var card_definition_id: String = ""
var definition_path: String = ""
var display_name: String = "Prototype card"
var image_path: String = ""
var position: Vector2 = Vector2.ZERO
var tapped: bool = false
var zone_id: String = ""
var current_zone: String = "battlefield"
var zone_player_id: String = "local"
var owner_player_id: String = "local"
var controller_player_id: String = "local"
# Compatibility alias for Milestone 4 callers.
var owner_id: String:
	get: return owner_player_id
	set(value): owner_player_id = value
var visibility: String = "public"
var face_down: bool = false
var identity_visible: bool = true
var is_token: bool = false
var custom_metadata: Dictionary = {}
var counters: Dictionary = {}
func change_counter(counter_name: String, amount: int) -> void:
	set_counter(counter_name, int(counters.get(counter_name.strip_edges(), 0)) + amount)
func set_counter(counter_name: String, value: int) -> void:
	var key: String = counter_name.strip_edges()
	if key.is_empty():
		return
	if key == "Loyalty":
		counters[key] = clampi(value,0,1000000)
	elif value <= 0:
		counters.erase(key)
	else:
		counters[key] = value
func to_data() -> Dictionary:
	return {"faces":faces.duplicate(true),"active_face_index":active_face_index,"match_instance_id": match_instance_id, "card_definition_id": card_definition_id,
		"definition_path": definition_path, "display_name": display_name, "image_path": image_path,
		"position": [position.x, position.y], "tapped": tapped, "zone_id": zone_id,
		"current_zone": current_zone, "zone_player_id": zone_player_id,
		"owner_player_id": owner_player_id, "controller_player_id": controller_player_id,
		"visibility": visibility, "face_down": face_down, "counters": counters.duplicate(true),
		"is_token": is_token, "custom_metadata": custom_metadata.duplicate(true)}
func restore(data: Dictionary) -> void:
	faces = data.get("faces",[]).duplicate(true)
	active_face_index = int(data.get("active_face_index",0))
	for field: String in ["match_instance_id", "card_definition_id", "definition_path", "display_name", "image_path", "zone_id", "current_zone", "zone_player_id", "owner_player_id", "controller_player_id", "visibility"]:
		set(field, data[field])
	position = Vector2(data.position[0], data.position[1])
	tapped = data.tapped
	face_down = data.face_down
	counters = data.counters.duplicate(true)
	is_token = data.is_token
	custom_metadata = data.get("custom_metadata", {}).duplicate(true)
