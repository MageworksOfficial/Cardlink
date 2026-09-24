extends RefCounted
## Persistent per-viewer memory, carried by the existing instance metadata.
const FIELD = "library_known_to"
static func known(state: RefCounted, viewer: String) -> bool:
	var viewers: Variant = state.custom_metadata.get(FIELD, [])
	return bool(state.custom_metadata.get("public_reveal", false)) or (viewers is Array and viewer in viewers)
static func learn(state: RefCounted, viewer: String) -> void:
	if not viewer in ["local", "opponent"]: return
	var viewers: Array = state.custom_metadata.get(FIELD, []).duplicate()
	if not viewer in viewers: viewers.append(viewer)
	state.custom_metadata[FIELD] = viewers
static func forget_on_shuffle(state: RefCounted) -> void:
	state.custom_metadata.erase(FIELD)
	state.custom_metadata.erase("public_reveal")
static func entering(state: RefCounted, visibility: RefCounted) -> void:
	if state.current_zone == "library": return
	if bool(state.custom_metadata.get("public_reveal",false)) or (state.current_zone != "hand" and not state.face_down and visibility.stable_visibility(state) == "public"):
		learn(state,"local")
		learn(state,"opponent")
	elif state.current_zone == "hand":
		learn(state,state.zone_player_id)
