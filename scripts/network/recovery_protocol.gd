extends RefCounted
const A = preload("res://scripts/network/network_action.gd")
const W = preload("res://scripts/network/card_sync_protocol.gd")
static func valid(f: Dictionary) -> bool:
	if not A.keys(f,["type","protocol","session_id","kind","data"]) or f.type != "recovery" or not A.number(f.protocol,1,65535) or not W.identifier(f.session_id): return false
	var d: Variant = f.data
	match f.kind:
		"seed": return A.keys(d,["match","secret"]) and W.identifier(d.match) and W.hash_ok(d.secret)
		"hello", "challenge", "proof": return A.keys(d,["match","nonce","proof","revision"]) and W.identifier(d.match) and W.hash_ok(d.nonce) and W.hash_ok(d.proof) and A.number(d.revision,0,1000000000)
		"restored", "check": return A.keys(d,["revision"]) and A.number(d.revision,0,1000000000)
		"action_ack": return A.keys(d,["id","revision"]) and W.identifier(d.id) and A.number(d.revision,0,1000000000)
		"snapshot": return A.keys(d,["revision","state"]) and A.number(d.revision,0,1000000000) and A.snapshot(d.state)
		"error": return A.keys(d,["message"]) and A.text(d.message,200)
	return false
