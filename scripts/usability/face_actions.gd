extends RefCounted
static func change(manager: Node, card: Control, index: int = -1) -> bool:
	if not is_instance_valid(card): return false
	var c: Node = manager.match_controller
	if not c.playtest.local_playtest() and not c.visibility.can_present(card.state,"local"): return false
	preload("res://scripts/card_faces.gd").resolve(card.state,c.loader.storage.directory)
	if card.state.faces.size() < 2:
		manager.controls.status.text = "This card has one available face."
		return false
	if index < 0: index = (card.state.active_face_index+1)%card.state.faces.size()
	if index >= card.state.faces.size() or index == card.state.active_face_index: return false
	manager.undo.begin("Change Card Face")
	preload("res://scripts/card_faces.gd").apply(card.state,index)
	manager.apply_card_art(card)
	# Deliberately no root transform or instance replacement. Instant swap respects Reduce Motion.
	c.refresh()
	c.record_event("face","Card changed face.",{})
	manager.controls.status.text = "Card face changed."
	if c.public_sync != null and c.public_sync.enabled: c.public_sync.scan()
	manager.undo.finish.call_deferred()
	return true
