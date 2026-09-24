extends RefCounted
const Player = preload("res://scripts/player_state.gd")
var match_id: String = "session_" + Crypto.new().generate_random_bytes(16).hex_encode()
var local_player_id: String = "local"
var players: Dictionary = {"local": Player.new("local", "You"), "opponent": Player.new("opponent", "Opponent")}
var instances: Dictionary = {}
var turn_number: int = 1
var active_player: String = "local"
var history: Array[Dictionary] = []
func synchronize(cards: Array[Control]) -> void:
	var old_hands: Dictionary = {}
	for player: RefCounted in players.values():
		old_hands[player.player_id] = player.hand.duplicate()
	instances.clear()
	for player: RefCounted in players.values():
		player.hand.clear()
		player.graveyard.clear()
		player.exile.clear()
		player.leaders.clear()
		player.battlefield.clear()
	for card: Control in cards:
		var state: RefCounted = card.state
		instances[state.match_instance_id] = state
		var player: RefCounted = players.get(state.zone_player_id, players.local)
		var id: String = state.match_instance_id
		match state.current_zone:
			"hand": player.hand.append(id)
			"graveyard": player.graveyard.append(id)
			"exile": player.exile.append(id)
			"commander": player.leaders.append(id)
			"library": pass
			_: player.battlefield.append(id)
	for player: RefCounted in players.values():
		var ordered: Array[String] = []
		for id: String in old_hands[player.player_id]:
			if player.hand.has(id):
				ordered.append(id)
		for id: String in player.hand:
			if not ordered.has(id):
				ordered.append(id)
		player.hand = ordered
func player_view(viewer: String, visibility: RefCounted) -> Dictionary:
	var result: Dictionary = {"match_id": match_id, "players": {}, "cards": []}
	for player: RefCounted in players.values():
		var row: Dictionary = {"player_id": player.player_id, "display_name": player.display_name,
			"life": player.life, "hand_count": player.hand.size(), "library_count": player.library.order.size()}
		if viewer == player.player_id:
			row["hand"] = player.hand.duplicate()
			row["library_order"] = player.library.order.duplicate()
		result.players[player.player_id] = row
	for state: RefCounted in instances.values():
		if state.current_zone in ["hand", "library"] and not visibility.can_see(state, viewer):
			continue
		result.cards.append(visibility.card_view(state, viewer))
	return result

