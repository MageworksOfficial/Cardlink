extends RefCounted
## Sandbox operations share one zone-move path and one ordered pile API.
var controller: Node
func _init(owner: Node) -> void:
	controller = owner
func put_nth(card: Control, player: String, n: int, from_bottom: bool = false) -> bool:
	if card == null or n < 1 or not controller.model.players.has(player):
		return false
	if controller.online():
		player = "local" if card.state.zone_player_id == "local" and card.state.current_zone in ["hand","library"] else card.state.owner_player_id
		if player != "local":
			controller.manager.controls.status.text = "Use Top/Bottom for a remote owner; private indexed placement comes later."
			return false
	if not controller.move_card(card, "library", true, player):
		return false
	if not controller.manager.cards.has(card):
		return true
	controller.model.players[player].library.insert_nth(card.state.match_instance_id, n, from_bottom)
	controller.refresh()
	return true
func draw_n(player: String, n: int) -> int:
	return move_top_n(player, n, "hand")
func mill_n(player: String, n: int) -> int:
	return move_top_n(player, n, "graveyard")
func move_top_n(player: String, n: int, kind: String) -> int:
	if not controller.model.players.has(player) or n < 1:
		return 0
	if controller.online() and player != "local": return 0
	var ids: Array[String] = controller.model.players[player].library.peek(n)
	var moved: int = 0
	controller.batching = true
	for id: String in ids:
		if not controller.move_card(controller.card_by_id(id), kind, true, player):
			break
		moved += 1
	controller.batching = false
	controller.refresh()
	controller.manager.controls.status.text = "%d card(s) moved to %s %s." % [moved, player, kind]
	return moved
func duplicate_token(source: Control) -> Dictionary:
	if source == null:
		return {"error": "Select a card first."}
	# A deliberate copy action may preserve hidden identity internally, never expose it.
	var result: Dictionary = controller.manager.create_token(source.state.display_name, source.state.owner_player_id, source.state.controller_player_id, source.state.image_path)
	if result.has("card"):
		var token: Control = result.card
		token.state.custom_metadata = source.state.custom_metadata.duplicate(true)
		token.state.counters = source.state.counters.duplicate(true)
		token.set_tapped(source.state.tapped)
		token.update_counters()
		token.position = source.position + Vector2(24, 24)
		token.state.position = token.position
		token.set_face_down(source.state.face_down or not controller.visibility.can_present(source.state, "local"))
		controller.refresh()
	return result
