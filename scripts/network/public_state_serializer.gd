extends RefCounted
const SIZE = Vector2(2304, 1296)
var router: Node
var hashes: Dictionary = {}
var projection: RefCounted
func _init(owner: Node) -> void:
	router = owner
	projection = preload("res://scripts/network/public_table_projection.gd").new(self)
func global_player(local: String) -> String:
	return router.local_id if local == "local" else router.remote_id
func local_player(global: String) -> String:
	return "local" if global == router.local_id else "opponent"
func encode_position(point: Vector2, height: float = 140) -> Array:
	if router.local_id == "player_2": point.y = SIZE.y - point.y - height
	return [snappedf(point.x / SIZE.x, 0.00001), snappedf(point.y / SIZE.y, 0.00001)]
func decode_position(value: Array, height: float = 140) -> Vector2:
	var point := Vector2(value[0] * SIZE.x, value[1] * SIZE.y)
	if router.local_id == "player_2": point.y = SIZE.y - point.y - height
	return point
func art_hash(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path): return ""
	if not hashes.has(path): hashes[path] = FileAccess.get_sha256(path)
	return hashes[path]
func public_card(card: Control) -> Dictionary:
	var s: RefCounted = card.state
	var hidden: bool = s.face_down
	var art: String = art_hash(s.image_path)
	if art.is_empty() and s.active_face_index >= 0 and s.active_face_index < s.faces.size():
		art = str(s.faces[s.active_face_index].get("image_hash",""))
	if art.is_empty() and router.state.cards.has(s.match_instance_id):
		art = router.state.cards[s.match_instance_id].art
	var result: Dictionary = {"zone_ref": projection.zone_key(router.table.find_zone(s.zone_id)) if router.table.find_zone(s.zone_id) != null else "", "id": s.match_instance_id, "definition": "" if hidden else s.card_definition_id,
		"name": "Face-down card" if hidden else s.display_name, "art": "" if hidden else art,
		"owner": global_player(s.owner_player_id), "controller": global_player(s.controller_player_id), "holder": global_player(s.zone_player_id),
		"zone": s.current_zone if s.current_zone in ["battlefield", "graveyard", "exile", "commander", "custom", "custom_zone"] else "battlefield",
		"position": encode_position(card.position), "tapped": card.tapped, "face_down": hidden, "counters": s.counters.duplicate(true), "token": s.is_token,
		"power": "" if hidden else str(s.custom_metadata.get("power", "")), "toughness": "" if hidden else str(s.custom_metadata.get("toughness", ""))}
	if not hidden and s.faces.size()>1: result["face_index"] = s.active_face_index
	if s.custom_metadata.has("deck_back"): result["deck_back"]=s.custom_metadata.deck_back.duplicate(true)
	return result
func capture() -> Dictionary:
	var table: Node = router.table
	var c: Node = table.match_controller
	c.model.synchronize(table.cards)
	var result: Dictionary = {"cards": {}, "counters": {}, "players": {}, "order": [], "turn": {"number": c.model.turn_number, "active": global_player(c.model.active_player)}, "history": []}
	for card: Node in table.world.get_children():
		if not card in table.cards or card.state.current_zone in ["hand", "library", "custom_pile"]: continue
		# Do not publish the unimported Godot demonstration card.
		if card.state.card_definition_id.is_empty() and not card.state.is_token and not router.state.cards.has(card.state.match_instance_id): continue
		result.cards[card.state.match_instance_id] = public_card(card)
		result.order.append(card.state.match_instance_id)
	for item: Control in table.extras.counters:
		result.counters[item.instance_id] = {"id": item.instance_id, "position": encode_position(item.position, 44), "value": item.value, "label": item.caption}
	for id: String in ["local", "opponent"]:
		var player: RefCounted = c.model.players[id]
		result.players[global_player(id)] = {"life": player.life, "hand": player.hand.size(), "library": player.library.order.size()}
	result["zones"] = projection.zones()
	result["hands"] = router.state.get("hands", {"player_1":[],"player_2":[]}).duplicate(true)
	result.hands[router.local_id] = projection.own_hand()
	return result
func resolve_art(hash: String) -> String:
	if hash.is_empty(): return ""
	var catalog: RefCounted = router.card_sync.catalog
	if catalog != null and catalog.has_image(hash): return catalog.asset_path(hash)
	for directory: String in [router.table.match_controller.loader.storage.directory, router.table.token_art_directory]:
		var path: String = directory.path_join(hash + ".png")
		if FileAccess.file_exists(path) and art_hash(path) == hash: return path
	return ""
func apply_card(data: Dictionary) -> void:
	var table: Node = router.table
	var c: Node = table.match_controller
	var card: Control = c.card_by_id(data.id)
	var local_owner: bool = data.owner == router.local_id or data.holder == router.local_id
	if card == null:
		var state = preload("res://scripts/card_instance_state.gd").new()
		state.match_instance_id = data.id
		state.card_definition_id = data.definition
		state.display_name = data.name
		state.image_path = resolve_art(data.art)
		state.is_token = data.token
		card = table.restore_card(state.to_data())
	var s: RefCounted = card.state
	# The owner's local private identity survives a public face-down representation.
	if (not data.face_down or not local_owner) and not (local_owner and data.definition.is_empty() and (not data.token or data.name == "Face-down card")):
		s.card_definition_id = data.definition
		s.display_name = data.name
		s.image_path = resolve_art(data.art)
		s.active_face_index = int(data.get("face_index",0))
		preload("res://scripts/card_faces.gd").resolve(s,c.loader.storage.directory)
		if router.card_sync.background_mode: router.card_sync.live_assets.resolve_public(s,data)
		s.custom_metadata["power"] = data.power
		s.custom_metadata["toughness"] = data.toughness
		table.apply_card_art(card)
	if data.has("deck_back"): s.custom_metadata["deck_back"]=data.deck_back.duplicate(true)
	s.owner_player_id = local_player(data.owner)
	s.controller_player_id = local_player(data.controller)
	s.zone_player_id = local_player(data.holder)
	var zone: Control = projection.find_zone(data.get("zone_ref",""))
	if zone == null and data.zone in ["graveyard", "exile", "commander"]: zone = c.zone_for(data.zone,s.zone_player_id)
	c.transitioning = true
	table.assign_zone(card, zone, false)
	c.transitioning = false
	for player: RefCounted in c.model.players.values(): player.library.order.erase(data.id)
	s.current_zone = data.zone
	s.position = decode_position(data.position)
	card.position = s.position
	card.set_tapped(data.tapped)
	var intentional_reveal: bool = bool(s.custom_metadata.get("public_reveal",false))
	card.set_face_down(data.face_down)
	if intentional_reveal and not data.face_down: c.visibility.set_public_reveal(s,true)
	s.counters = data.counters.duplicate(true)
	card.update_counters()
	if not data.face_down and card.card_image.texture == null and not data.token:
		card.tooltip_text = data.name + " — Missing card asset. Use Sync Missing Cards; you can keep playing."
	else: card.tooltip_text = ""
func apply_all(card_ids: Variant = null, counter_ids: Variant = null, reorder: bool = true) -> void:
	var table: Node = router.table
	var c: Node = table.match_controller
	projection.apply_zones()
	for data: Dictionary in router.state.cards.values():
		if card_ids == null or data.id in card_ids: apply_card(data)
	for data: Dictionary in router.state.counters.values():
		if counter_ids != null and not data.id in counter_ids: continue
		var item: Control = table.extras.counter_by_id(data.id)
		if item == null:
			item = table.extras.create_counter(Vector2.ZERO)
			item.instance_id = data.id
		item.value = int(data.value)
		item.caption = data.label
		item.position = decode_position(data.position, 44)
		item.refresh()
	for id: String in router.state.order:
		if not reorder: break
		var card: Control = c.card_by_id(id)
		if card != null: table.bring_to_front(card)
	for player: String in router.state.players:
		c.model.players[local_player(player)].life = int(router.state.players[player].life)
	c.model.turn_number = int(router.state.turn.number)
	c.model.active_player = local_player(router.state.turn.active)
	c.model.history.clear()
	for item: Dictionary in router.state.history:
		c.model.history.append({"event_id": item.id, "kind": item.kind, "actor": local_player(item.actor), "turn": c.model.turn_number, "text": item.text, "payload": {}})
	table.life = c.model.players.local.life
	table.controls.life_label.text = "Life: %d" % table.life
	c.remote_hand_count = int(router.state.players[router.remote_id].hand)
	c.remote_library_count = int(router.state.players[router.remote_id].library)
	c.refresh()
	table.extras.refresh_history()
