extends RefCounted
## Public-only schemas. No filesystem paths, image bytes, hands or library arrays.
const PLAYERS = ["player_1", "player_2"]
const CARD_FIELDS = ["zone_ref", "id", "definition", "name", "art", "owner", "controller", "holder", "zone", "position", "tapped", "face_down", "counters", "token", "power", "toughness"]
static func text(value: Variant, limit: int = 160) -> bool:
	return value is String and value.length() <= limit
static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high
static func keys(data: Variant, allowed: Array, required: bool = true) -> bool:
	if not data is Dictionary or (required and data.size() != allowed.size()):
		return false
	for field: Variant in data:
		if not field is String or not field in allowed:
			return false
	return true
static func position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0], -10, 10) and number(value[1], -10, 10)
static func card(data: Variant, partial: bool = false) -> bool:
	if not keys(data, CARD_FIELDS + ["face_index"], false) or (not partial and not CARD_FIELDS.all(func(key: String) -> bool: return data.has(key))) or not text(data.get("id"), 80) or data.id.is_empty():
		return false
	for field: String in data:
		var value: Variant = data[field]
		match field:
			"owner", "controller", "holder":
				if not value in PLAYERS: return false
			"zone":
				if not value in ["battlefield", "graveyard", "exile", "commander", "custom", "custom_zone"]: return false
			"position":
				if not position(value): return false
			"tapped", "face_down", "token":
				if not value is bool: return false
			"counters":
				if not value is Dictionary or value.size() > 24: return false
				for name: Variant in value:
					if not text(name, 48) or not number(value[name], 0, 1000000): return false
			"face_index":
				if not number(value,0,15) or value != floor(value): return false
			"art":
				if not value is String or (not value.is_empty() and (value.length() != 64 or not value.is_valid_hex_number(false))): return false
			_:
				if not text(value): return false
	if not partial and data.token and not data.zone in ["battlefield", "custom", "custom_zone"]: return false
	return true
static func counter(data: Variant) -> bool:
	return keys(data, ["id", "position", "value", "label"]) and text(data.id, 80) and not data.id.is_empty() and position(data.position) and number(data.value, -1000000, 1000000) and text(data.label, 80)
static func event(data: Variant) -> bool:
	return keys(data, ["id", "kind", "actor", "text"]) and text(data.id, 80) and text(data.kind, 32) and data.actor in PLAYERS and text(data.text, 500)
static func operation(op: Variant) -> bool:
	if not keys(op, ["kind", "data"]): return false
	var data: Variant = op.data
	match op.kind:
		"card_create": return card(data)
		"card_update": return card(data, true)
		"card_remove": return keys(data, ["id", "destination", "owner", "top"]) and text(data.id, 80) and data.destination in ["hand", "library", "removed"] and data.owner in PLAYERS and data.top is bool
		"zone_set": return zone(data)
		"hand_public": return keys(data,["player","cards"]) and data.player in PLAYERS and hand(data.cards)
		"counter_set": return counter(data)
		"counter_remove": return keys(data, ["id"]) and text(data.id, 80)
		"counts": return keys(data, ["player", "hand", "library"]) and data.player in PLAYERS and number(data.hand, 0, 1000) and number(data.library, 0, 5000)
		"life": return keys(data, ["player", "delta"]) and data.player in PLAYERS and number(data.delta, -1000000, 1000000)
		"end_turn": return keys(data, [])
		"order":
			if not keys(data, ["ids"]) or not data.ids is Array or data.ids.size() > 500: return false
			for id: Variant in data.ids:
				if not text(id, 80): return false
			return true
		"history": return event(data)
	return false
static func action(value: Variant) -> bool:
	if not keys(value, ["action_id", "sequence", "actor_player_id", "action_type", "payload"]): return false
	if not text(value.action_id, 80) or value.action_id.is_empty() or not number(value.sequence, 1, 1000000000) or value.sequence != floor(value.sequence) or not value.actor_player_id in PLAYERS or value.action_type != "batch": return false
	if not value.payload is Array or value.payload.size() > 500: return false
	for op: Variant in value.payload:
		if not operation(op): return false
	return true
static func snapshot(value: Variant) -> bool:
	if not keys(value, ["cards", "counters", "players", "order", "turn", "history", "zones", "hands"]): return false
	if not value.zones is Dictionary or value.zones.size() > 100 or not keys(value.hands,PLAYERS): return false
	for id: Variant in value.zones:
		if not zone(value.zones[id]) or id != value.zones[id].id: return false
	for id: String in PLAYERS:
		if not hand(value.hands[id]): return false
	if not value.cards is Dictionary or value.cards.size() > 500 or not value.counters is Dictionary or value.counters.size() > 500: return false
	for id: Variant in value.cards:
		if not card(value.cards[id]) or id != value.cards[id].id: return false
	for id: Variant in value.counters:
		if not counter(value.counters[id]) or id != value.counters[id].id: return false
	if not keys(value.players, PLAYERS): return false
	for id: String in PLAYERS:
		var p: Variant = value.players[id]
		if not keys(p, ["life", "hand", "library"]) or not number(p.life, -1000000, 1000000) or not number(p.hand, 0, 1000) or not number(p.library, 0, 5000): return false
	if not keys(value.turn, ["number", "active"]) or not number(value.turn.number, 1, 1000000000) or not value.turn.active in PLAYERS: return false
	if not operation({"kind": "order", "data": {"ids": value.order}}) or not value.history is Array or value.history.size() > 200: return false
	for item: Variant in value.history:
		if not event(item): return false
	return true
static func frame(value: Dictionary) -> bool:
	if not keys(value, ["type", "protocol", "session_id", "mode", "sequence", "data"]) or value.type != "game" or not number(value.protocol, 1, 65535) or not text(value.session_id, 32) or not number(value.sequence, 0, 1000000000) or value.sequence != floor(value.sequence): return false
	match value.mode:
		"offer", "ready", "resync_request": return keys(value.data, [])
		"request", "commit": return action(value.data)
		"resync": return snapshot(value.data)
	return false

static func zone(data: Variant) -> bool:
	return keys(data,["id","kind","player","name","position","size","capacity"]) and text(data.id,80) and data.kind in ["library","deck","graveyard","exile","commander","battlefield","custom","custom_zone"] and data.player in PLAYERS and text(data.name,160) and position(data.position) and data.size is Array and data.size.size() == 2 and number(data.size[0],20,2304) and number(data.size[1],20,1296) and number(data.capacity,0,5000)
static func hand(data: Variant) -> bool:
	if not data is Array or data.size() > 1000: return false
	var slots: Dictionary = {}
	for row: Variant in data:
		if not keys(row,["slot","definition","name","art"]) or not number(row.slot,0,999) or row.slot != floor(row.slot) or slots.has(row.slot) or not text(row.definition,160) or not text(row.name,160) or not row.art is String or (not row.art.is_empty() and (row.art.length() != 64 or not row.art.is_valid_hex_number(false))): return false
		slots[row.slot] = true
	return true
