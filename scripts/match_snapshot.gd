extends RefCounted
const Layout = preload("res://scripts/layout_service.gd")
const MatchState = preload("res://scripts/match_state.gd")
const InstanceState = preload("res://scripts/card_instance_state.gd")
const Visibility = preload("res://scripts/visibility_service.gd")
static func capture(manager: Node) -> Dictionary:
	var controller: Node = manager.match_controller
	controller.model.synchronize(manager.cards)
	var players: Array[Dictionary] = []
	for player: RefCounted in controller.model.players.values():
		players.append(player.to_data())
	var cards: Array[Dictionary] = []
	for child: Node in manager.world.get_children():
		if not manager.cards.has(child):
			continue
		var row: Dictionary = child.state.to_data()
		row.position = [child.position.x, child.position.y]
		row.visibility = controller.visibility.stable_visibility(child.state)
		cards.append(row)
	var layout: Dictionary = manager.layout.capture()
	return {"schema_version": 1, "match_id": controller.model.match_id, "players": players,
		"cards": cards, "zones": layout.zones.duplicate(true), "layout": layout, "local_tabletop": preload("res://scripts/match_local_state.gd").capture(manager)}
static func validate(data: Dictionary) -> String:
	var local_error: String = preload("res://scripts/match_local_state.gd").validate(data.get("local_tabletop", {}))
	if not local_error.is_empty():
		return local_error
	if data.get("schema_version") != 1 or not data.get("match_id") is String or not data.get("players") is Array or data.players.size() != 2:
		return "Invalid match header or players."
	if not data.get("layout") is Dictionary:
		return "Missing match layout."
	var error: String = Layout.validate(data.layout)
	if not error.is_empty():
		return error
	if not data.get("zones") is Array:
		return "Invalid match zones."
	var zone_layout: Dictionary = data.layout.duplicate(true)
	zone_layout.zones = data.zones
	error = Layout.validate(zone_layout)
	if not error.is_empty():
		return error
	var zones: Dictionary = {}
	for zone: Dictionary in data.zones:
		zones[zone.zone_id] = zone
	if not data.get("cards") is Array or data.cards.size() > 5000:
		return "Invalid card list (limit 5000)."
	var cards: Dictionary = {}
	for card: Variant in data.cards:
		if not card is Dictionary:
			return "Invalid card object."
		for field: String in ["match_instance_id", "card_definition_id", "definition_path", "display_name", "image_path", "zone_id", "current_zone", "zone_player_id", "owner_player_id", "controller_player_id", "visibility"]:
			if not card.get(field) is String:
				return "Invalid card " + field
		var faces: Variant = card.get("faces",[])
		var index: Variant = card.get("active_face_index",0)
		if not faces is Array or (not faces.is_empty() and not preload("res://scripts/card_faces.gd").validate(faces).is_empty()): return "Invalid saved faces."
		if not Layout.number(index) or index != floor(index) or index < 0 or index >= maxi(1,faces.size()): return "Invalid active face."
		if card.match_instance_id.is_empty() or cards.has(card.match_instance_id):
			return "Duplicate or empty instance ID."
		if not card.owner_player_id in ["local", "opponent"] or not card.controller_player_id in ["local", "opponent"] or not card.zone_player_id in ["local", "opponent"]:
			return "Invalid player reference on card."
		if not card.visibility in Visibility.STATES or card.visibility == "temporarily_revealed":
			return "Temporary inspection access cannot be restored from disk."
		if not Layout.vector_valid(card.get("position")) or not card.get("tapped") is bool or not card.get("face_down") is bool or not card.get("is_token") is bool or not card.get("counters") is Dictionary or not card.get("custom_metadata", {}) is Dictionary:
			return "Invalid card state."
		var known: Variant = card.get("custom_metadata",{}).get("library_known_to",[])
		if not known is Array or known.size()>2: return "Invalid library knowledge viewers."
		for viewer: Variant in known:
			if not viewer in ["local","opponent"]: return "Invalid library knowledge viewer."
		for key: Variant in card.counters:
			if not key is String or key.is_empty() or not Layout.number(card.counters[key]) or card.counters[key] < 0 or card.counters[key] != floor(card.counters[key]):
				return "Invalid counter."
		if not card.zone_id.is_empty() and not zones.has(card.zone_id):
			return "Card refers to missing zone."
		if not card.zone_id.is_empty() and zones[card.zone_id].player_id != card.zone_player_id:
			return "Zone holder mismatch."
		cards[card.match_instance_id] = card
	var players: Dictionary = {}
	for player: Variant in data.players:
		if not player is Dictionary or not player.get("player_id") in ["local", "opponent"] or players.has(player.player_id) or not player.get("display_name") is String or not Layout.number(player.get("life")) or player.life != floor(player.life):
			return "Invalid or duplicate player."
		if player.has("deck_manifest"):
			if not player.deck_manifest is Array or player.deck_manifest.size() > 5000: return "Invalid saved deck manifest."
			for entry: Variant in player.deck_manifest:
				if not entry is Dictionary or not entry.get("id") is String or not entry.get("name") is String or not entry.get("hash") is String or not entry.get("tags") is Array: return "Invalid saved deck descriptor."
		players[player.player_id] = player
		var all: Dictionary = {}
		for field: String in ["library_order", "hand", "graveyard", "exile", "leaders", "battlefield", "loaded_ids"]:
			if not player.get(field) is Array:
				return "Missing player zone list."
			var seen: Dictionary = {}
			for id: Variant in player[field]:
				if not id is String or not cards.has(id) or seen.has(id):
					return "Invalid or duplicate zone member."
				seen[id] = true
				if field == "loaded_ids":
					continue
				var card: Dictionary = cards[id]
				var kind: String = {"library_order":"library", "leaders":"commander"}.get(field, field)
				if card.zone_player_id != player.player_id or (card.current_zone != kind and not (kind == "battlefield" and not card.current_zone in ["library", "hand", "graveyard", "exile", "commander"])) or all.has(id):
					return "Inconsistent zone membership."
				all[id] = true
		for card: Dictionary in cards.values():
			if card.zone_player_id == player.player_id and not all.has(card.match_instance_id):
				return "Missing card from player zone list."
		if not player.get("deck_name") is String:
			return "Invalid deck label."
	return ""
static func restore(manager: Node, data: Dictionary) -> Dictionary:
	var error: String = validate(data)
	if not error.is_empty():
		return {"error": error}
	# Complete structural validation before replacing anything.
	var controller: Node = manager.match_controller
	controller.close_inspection()
	controller.review.cancel()
	controller.batching = true
	for card: Control in manager.cards.duplicate():
		controller.remove_card(card)
	for zone: Control in manager.zones:
		zone.get_parent().remove_child(zone)
		zone.queue_free()
	manager.zones.clear()
	controller.model = MatchState.new()
	controller.model.match_id = data.match_id
	for saved: Dictionary in data.players:
		var player: RefCounted = controller.model.players[saved.player_id]
		player.display_name = saved.display_name
		player.life = int(saved.life)
		player.deck_name = saved.deck_name
		player.deck_manifest = saved.get("deck_manifest",[]).duplicate(true)
		player.library.order.assign(saved.library_order)
		player.loaded_ids.assign(saved.loaded_ids)
		player.hand.assign(saved.hand)
	for saved: Dictionary in data.zones:
		var row: Dictionary = saved.duplicate(true)
		row.position = Vector2(saved.position[0], saved.position[1])
		var zone: Control = manager.add_zone(row)
		zone.custom_minimum_size = Vector2(saved.size[0], saved.size[1])
		zone.size = zone.custom_minimum_size
	var missing: int = 0
	for saved: Dictionary in data.cards:
		var card: Control = manager.restore_card(saved)
		if not saved.image_path.is_empty() and card.card_image.texture == null:
			missing += 1
		var zone: Control = manager.find_zone(card.state.zone_id)
		if zone != null:
			zone.members.append(card.state.match_instance_id)
	for zone: Control in manager.zones:
		zone.update_title()
	manager.layout.apply(data.layout, false)
	manager.layout.set_edit_mode(false)
	manager.life = controller.model.players.local.life
	manager.controls.life_label.text = "Life: %d" % manager.life
	preload("res://scripts/match_local_state.gd").restore(manager, data.get("local_tabletop", {}))
	controller.batching = false
	controller.refresh()
	return {"restored": true, "missing_images": missing}

