extends RefCounted
## Inspection grants are session-local; never serialize this service.
const STATES: Array[String] = ["owner_private", "public", "face_down_public", "temporarily_revealed"]
var inspection_ids: Array[String] = []
var previous_visibility: Dictionary = {}
func can_present(state: RefCounted, viewer: String) -> bool:
	# Inspection grants are restricted to inspection UI, never normal surfaces.
	if state.face_down or state.current_zone == "library":
		return false
	var stable: String = stable_visibility(state)
	return stable == "public" or (stable == "owner_private" and state.zone_player_id == viewer)
func set_public_reveal(state: RefCounted, revealed: bool) -> void:
	# Persist the intentional reveal using the existing serialized card metadata.
	previous_visibility.erase(state.match_instance_id)
	if revealed:
		if state.current_zone == "library":
			preload("res://scripts/library_knowledge.gd").learn(state,"local")
			preload("res://scripts/library_knowledge.gd").learn(state,"opponent")
		state.custom_metadata["public_reveal"] = true
		state.face_down = false
		state.visibility = "public"
	else:
		state.custom_metadata.erase("public_reveal")
		state.visibility = "owner_private" if state.current_zone in ["hand", "library"] else "face_down_public"
func can_see(state: RefCounted, viewer: String) -> bool:
	if inspection_ids.has(state.match_instance_id) and viewer == "local":
		return true
	if state.visibility in ["public", "temporarily_revealed"]:
		return true
	if state.visibility == "face_down_public":
		return false
	# Hidden-zone holder determines access after transfers between players.
	return state.zone_player_id == viewer
func begin(states: Array, reveal: bool = false) -> void:
	for state: RefCounted in states:
		if not inspection_ids.has(state.match_instance_id):
			inspection_ids.append(state.match_instance_id)
		if reveal and not previous_visibility.has(state.match_instance_id):
			previous_visibility[state.match_instance_id] = state.visibility
			state.visibility = "temporarily_revealed"
func end(instances: Dictionary) -> void:
	for id: String in previous_visibility:
		if instances.has(id) and instances[id].visibility == "temporarily_revealed":
			instances[id].visibility = previous_visibility[id]
	inspection_ids.clear()
	previous_visibility.clear()
func stable_visibility(state: RefCounted) -> String:
	return str(previous_visibility.get(state.match_instance_id, "owner_private")) if state.visibility == "temporarily_revealed" else state.visibility
func card_view(state: RefCounted, viewer: String) -> Dictionary:
	if can_see(state, viewer):
		return state.to_data()
	# A face-down public object exposes physical state but never its identity.
	return {"match_instance_id": state.match_instance_id, "owner_player_id": state.owner_player_id,
		"controller_player_id": state.controller_player_id, "current_zone": state.current_zone,
		"zone_player_id": state.zone_player_id, "visibility": state.visibility,
		"position": [state.position.x, state.position.y], "tapped": state.tapped,
		"counters": state.counters.duplicate(true), "hidden": true}

