extends RefCounted
## Data-only table format. Contains no card definitions, scripts or private pile order.
const VERSION = 1
const LIMIT = 128
const TYPES = ["deck", "shared_deck", "hand", "discard", "zone", "leader", "board", "text", "shared_area"]
const OWNERS = ["player_1", "player_2", "table"]
const FIELDS = ["id", "kind", "name", "owner", "visibility", "position", "size", "hidden", "locked", "rotation", "opacity", "asset", "back", "linked_pile", "text"]
static func fresh() -> Dictionary:
	return {"format":VERSION,"id":Crypto.new().generate_random_bytes(16).hex_encode(),"name":"My Table","description":"","author":"","dimensions":[3200,2000],"components":[]}
static func component(kind: String, owner: String = "table") -> Dictionary:
	return {"id":Crypto.new().generate_random_bytes(16).hex_encode(),"kind":kind,"name":labels().get(kind,kind),"owner":("table" if kind == "shared_deck" else owner),"visibility":("private" if kind in ["deck","shared_deck","hand"] else "public"),"position":[500,350],"size":([420,200] if kind in ["board","shared_area","hand"] else ([260,360] if kind in ["deck","shared_deck","discard"] else [180,220])),"hidden":false,"locked":kind == "board","rotation":0,"opacity":1.0,"asset":"","back":"","linked_pile":"","text":""}
static func labels() -> Dictionary:
	return {"deck":"Deck / Pile","shared_deck":"Shared Deck","hand":"Hand","discard":"Discard Pile","zone":"Custom Zone","leader":"Leader Zone","board":"Board / Floor Image","text":"Text Label","shared_area":"Shared Area"}
static func matches(row: Dictionary, query: String) -> bool:
	var aliases: Dictionary = {"deck":"library auxiliary sideboard extra cards", "shared_deck":"deck library central table draw pile", "discard":"grave graveyard shared discard", "board":"floor playmat map image", "zone":"bench prize reserve market", "leader":"commander", "hand":"player cards"}
	return query.strip_edges().is_empty() or (str(row.get("name",""))+" "+str(row.get("kind",""))+" "+str(aliases.get(row.get("kind"),""))).to_lower().contains(query.strip_edges().to_lower())
static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= low and value <= high
static func text(value: Variant, limit: int) -> bool:
	if not value is String or value.length() > limit: return false
	for i: int in value.length():
		if value.unicode_at(i) == 0: return false
	return true
static func hash_id(value: Variant, length: int, empty: bool = false) -> bool:
	return value is String and ((empty and value.is_empty()) or (value.length() == length and value.is_valid_hex_number(false) and value == value.to_lower()))
static func pair(value: Variant, low: float, high: float) -> bool:
	return value is Array and value.size() == 2 and number(value[0],low,high) and number(value[1],low,high)
static func validate(data: Variant) -> String:
	if not data is Dictionary or data.size() not in [7,8,9] or data.get("format") != VERSION: return "Unsupported table template version."
	for key: String in ["format","id","name","description","author","dimensions","components"]:
		if not data.has(key): return "Incomplete table template."
	if not hash_id(data.id,32) or not text(data.name,80) or data.name.strip_edges().is_empty() or not text(data.description,1000) or not text(data.author,80) or not pair(data.dimensions,800,10000): return "Invalid table description or dimensions."
	if not data.components is Array or data.components.size() > LIMIT: return "Too many table objects (maximum 128)."
	for key: String in data:
		if not key in ["format","id","name","description","author","dimensions","components","defaults","background"]: return "Unknown template field."
	if data.has("background") and not preload("res://scripts/appearance/background_config.gd").valid(data.background): return "Invalid battlefield background."
	var defaults: Variant = data.get("defaults",[])
	if not defaults is Array or defaults.size() + data.components.size() > LIMIT: return "Too many template objects."
	for item: Variant in defaults:
		if not item is Dictionary or item.size() != 8: return "Invalid default object."
		for key: String in ["kind","name","position","value","power","toughness","owner","controller"]:
			if not item.has(key): return "Incomplete default object."
		if item.kind not in ["token","counter"] or not text(item.name,80) or not pair(item.position,-20000,20000) or not number(item.value,-1000000,1000000) or item.value != floor(item.value) or not text(item.power,32) or not text(item.toughness,32) or item.owner not in ["player_1","player_2"] or item.controller not in ["player_1","player_2"]: return "Invalid default object values."
	var ids: Dictionary = {}
	for row: Variant in data.components:
		if not row is Dictionary or row.size() != FIELDS.size(): return "Invalid table component."
		for key: String in FIELDS:
			if not row.has(key): return "Incomplete table component."
		if not hash_id(row.id,32) or ids.has(row.id) or not row.kind in TYPES or not text(row.name,80) or row.name.strip_edges().is_empty() or not row.owner in OWNERS or not row.visibility in ["public","private"]: return "Invalid component identity."
		if row.kind == "shared_deck" and row.owner != "table": return "Shared decks must belong to the table."
		if row.kind == "hand" and row.owner == "table": return "Choose Player 1 or Player 2 for a hand."
		if not pair(row.position,-20000,20000) or not pair(row.size,40,8000) or not number(row.rotation,-360,360) or not number(row.opacity,0.05,1): return "Invalid component position, size or appearance."
		if not row.hidden is bool or not row.locked is bool or not hash_id(row.asset,64,true) or not hash_id(row.back,64,true) or not hash_id(row.linked_pile,32,true) or not text(row.text,1000): return "Invalid component settings."
		ids[row.id] = row
	for row: Dictionary in data.components:
		if not row.linked_pile.is_empty() and (not ids.has(row.linked_pile) or not ids[row.linked_pile].kind in ["deck","shared_deck"]): return "A linked deck is missing."
	return ""
static func find(data: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in data.components:
		if row.id == id: return row
	return {}
