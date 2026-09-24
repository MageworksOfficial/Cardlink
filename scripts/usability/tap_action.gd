extends RefCounted
static func toggle(manager: Node, card: Control) -> void:
	if not is_instance_valid(card): return
	manager.undo.begin("Tap / Untap")
	card.set_tapped(not card.state.tapped)
	manager.controls.status.text = "Card tapped" if card.state.tapped else "Card untapped"
	if manager.match_controller.online(): manager.match_controller.public_sync.scan()
	manager.undo.finish.call_deferred()
