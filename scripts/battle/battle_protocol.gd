extends RefCounted
const A = preload("res://scripts/network/network_action.gd")
const B = preload("res://scripts/battle/deck_back.gd")
static func identifier(v: Variant) -> bool: return v is String and v.length()==32 and v.is_valid_hex_number(false)
static func back(v: Variant) -> bool: return v is Dictionary and (v.is_empty() or B.valid(v))
static func cosmetics(d: Variant) -> bool:
	if not A.keys(d,["library","hand","piles"]) or not back(d.library) or not d.hand is Array or d.hand.size()>1000 or not d.piles is Dictionary or d.piles.size()>128: return false
	for value: Variant in d.hand:
		if not back(value): return false
	for key: Variant in d.piles:
		if not A.text(key,80) or not back(d.piles[key]): return false
	return true
static func clean_name(value: String) -> bool:
	for i: int in value.length():
		if value.unicode_at(i)<32 or value.unicode_at(i)==127: return false
	return true
static func chunk(v: Variant) -> bool:
	if not v is String or v.is_empty() or v.length()>43692 or v.length()%4!=0: return false
	var regex := RegEx.new();regex.compile("^[A-Za-z0-9+/]*={0,2}$")
	return regex.search(v)!=null and Marshalls.base64_to_raw(v).size()<=32768
static func valid(f: Dictionary) -> bool:
	if not A.keys(f,["type","protocol","session_id","kind","data"]) or f.type!="battle" or f.protocol!=1 or not identifier(f.session_id): return false
	var d: Variant=f.data
	if f.kind is String and f.kind.begins_with("state_"): return preload("res://scripts/battle/online_state_protocol.gd").valid(f.kind,d)
	match f.kind:
		"background","background_edit": return preload("res://scripts/appearance/background_config.gd").valid(d)
		"background_need": return A.keys(d,["hash"]) and preload("res://scripts/network/card_sync_protocol.gd").hash_ok(d.hash)
		"background_chunk": return A.keys(d,["hash","total","offset","bytes"]) and preload("res://scripts/network/card_sync_protocol.gd").hash_ok(d.hash) and A.number(d.total,1,8388608) and d.total==floor(d.total) and A.number(d.offset,0,8388608) and d.offset==floor(d.offset) and chunk(d.bytes)
		"sleeve_request": return A.keys(d,["target","back"]) and (d.target=="local" or identifier(d.target)) and d.back is Dictionary and B.valid(d.back)
		"backs": return cosmetics(d)
		"nickname": return A.keys(d,["name"]) and d.name is String and not d.name.strip_edges().is_empty() and d.name.length()<=48 and clean_name(d.name)
		"back_need": return A.keys(d,["hash"]) and preload("res://scripts/network/card_sync_protocol.gd").hash_ok(d.hash)
		"back_chunk": return A.keys(d,["hash","total","offset","bytes"]) and preload("res://scripts/network/card_sync_protocol.gd").hash_ok(d.hash) and A.number(d.total,1,B.MAX_BYTES) and d.total==floor(d.total) and A.number(d.offset,0,B.MAX_BYTES) and d.offset==floor(d.offset) and chunk(d.bytes)
		"reset_request","reset_accept","reset_decline","reset_prepare","reset_committed","reset_go","reset_started","reset_cancel","reset_done","reset_finished","reset_stable": return A.keys(d,["id"]) and identifier(d.id)
		"reset_prepared","reset_commit": return A.keys(d,["id","state"]) and identifier(d.id) and A.snapshot(d.state)
	return false
