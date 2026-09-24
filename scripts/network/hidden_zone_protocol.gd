extends RefCounted
const A = preload("res://scripts/network/network_action.gd")
const W = preload("res://scripts/network/card_sync_protocol.gd")
static func valid(f: Dictionary) -> bool:
	if not A.keys(f,["type","protocol","session_id","request_id","kind","data"]) or f.type != "hidden_zone" or not A.number(f.protocol,1,65535) or not W.identifier(f.request_id) or not A.text(f.session_id,32): return false
	var d: Variant = f.data
	match f.kind:
		"request": return A.keys(d,["zone"]) and d.zone in ["hand","library"]
		"deny", "close": return A.keys(d,["reason"]) and A.text(d.reason,160)
		"snapshot":
			if not A.keys(d,["zone","cards"]) or not d.zone in ["hand","library"] or not d.cards is Array or d.cards.size() > 500: return false
			var ids: Dictionary = {}
			for row: Variant in d.cards:
				if not A.card(row) or ids.has(row.id): return false
				ids[row.id] = true
			return true
		"move": return A.keys(d,["id","destination","n","bottom"]) and W.identifier(d.id) and d.destination in ["take","hand","battlefield","graveyard","exile","library"] and A.number(d.n,1,5001) and d.n == floor(d.n) and d.bottom is bool
		"transfer": return A.keys(d,["card","revealed"]) and A.card(d.card) and d.revealed is bool
		"ack": return A.keys(d,["id"]) and W.identifier(d.id)
	return false
