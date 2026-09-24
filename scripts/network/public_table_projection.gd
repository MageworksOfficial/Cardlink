extends RefCounted
## Shared world zones and explicitly revealed hand slots, separate from local camera/UI.
var source: WeakRef
var serializer: RefCounted:
	get: return source.get_ref()
var textures: Dictionary = {}
func _init(owner: RefCounted) -> void: source = weakref(owner)
func zone_key(zone: Control) -> String:
	if zone.zone_type in ["graveyard","exile","commander"]:
		for existing: Control in serializer.router.table.zones:
			if existing.zone_type == zone.zone_type and existing.player_id == zone.player_id:
				if existing != zone: return zone.zone_id
				break
		return serializer.global_player(zone.player_id) + ":" + zone.zone_type
	return zone.zone_id
func prepare() -> void:
	var c: Node = serializer.router.table.match_controller
	if c.pile_view.position == Vector2(205,155): c.pile_view.position = Vector2(205,900)
	if c.opponent_pile.position == Vector2(900,70): c.opponent_pile.position = Vector2(205,256)
	for player: String in ["local","opponent"]:
		for kind: String in ["graveyard","exile","commander"]:
			var existed: bool = false
			for zone: Control in c.manager.zones:
				if zone.zone_type == kind and zone.player_id == player: existed = true
			var zone: Control = c.zone_for(kind,player)
			if not existed:
				zone.position = Vector2(1150 + ["graveyard","exile","commander"].find(kind)*180,850 if player == "local" else 236)
func zones() -> Dictionary:
	var table: Node = serializer.router.table
	var result: Dictionary = {}
	for zone: Control in table.zones:
		if zone.zone_type == "hand": continue
		var id: String = zone_key(zone)
		result[id] = {"id":id,"kind":zone.zone_type,"player":serializer.global_player(zone.player_id),"name":zone.display_name,"position":serializer.encode_position(zone.position,zone.size.y),"size":[zone.size.x,zone.size.y],"capacity":zone.capacity}
	for player: String in ["local","opponent"]:
		var pile: Control = table.match_controller.pile_view if player == "local" else table.match_controller.opponent_pile
		var id: String = serializer.global_player(player) + ":library"
		result[id] = {"id":id,"kind":"library","player":serializer.global_player(player),"name":"Library","position":serializer.encode_position(pile.position,pile.size.y),"size":[pile.size.x,pile.size.y],"capacity":0}
	return result
func find_zone(id: String) -> Control:
	for zone: Control in serializer.router.table.zones:
		if zone_key(zone) == id: return zone
	return null
func apply_zones() -> void:
	var table: Node = serializer.router.table
	for row: Dictionary in serializer.router.state.get("zones",{}).values():
		var player: String = serializer.local_player(row.player)
		if row.kind == "library":
			var pile: Control = table.match_controller.pile_view if player == "local" else table.match_controller.opponent_pile
			pile.position = serializer.decode_position(row.position,pile.size.y)
			continue
		var zone: Control = find_zone(row.id)
		if zone == null:
			zone = table.add_zone({"zone_id":row.id,"zone_type":row.kind,"player_id":player,"display_name":row.name})
		zone.player_id = player
		zone.capacity = int(row.capacity)
		zone.custom_minimum_size = Vector2(row.size[0],row.size[1])
		zone.size = zone.custom_minimum_size
		zone.position = serializer.decode_position(row.position,zone.size.y)
		zone.display_name = ("Your " if player == "local" else "Opponent ") + row.kind.capitalize() if row.kind in ["graveyard","exile","commander"] else row.name
		zone.update_title()
func own_hand() -> Array:
	var c: Node = serializer.router.table.match_controller
	var result: Array = []
	for slot: int in c.model.players.local.hand.size():
		var card: Control = c.card_by_id(c.model.players.local.hand[slot])
		if card == null or not card.state.custom_metadata.get("public_reveal",false): continue
		result.append({"slot":slot,"definition":card.state.card_definition_id,"name":card.state.display_name,"art":serializer.art_hash(card.state.image_path)})
	return result
func remote_hand() -> Dictionary:
	var router: Node = serializer.router
	var count: int = int(router.state.players[router.remote_id].hand)
	var faces: Array = []
	var names: Array = []
	faces.resize(count)
	names.resize(count)
	for row: Dictionary in router.state.get("hands",{}).get(router.remote_id,[]):
		if row.slot >= count: continue
		var path: String = serializer.resolve_art(row.art)
		if not path.is_empty() and not textures.has(row.art):
			var image := Image.new()
			if image.load(path) == OK: textures[row.art] = ImageTexture.create_from_image(image)
		faces[int(row.slot)] = textures.get(row.art)
		names[int(row.slot)] = row.name
	return {"faces":faces,"names":names}
