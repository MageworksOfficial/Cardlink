extends RefCounted
const A = preload("res://scripts/network/network_action.gd")
const W = preload("res://scripts/network/card_sync_protocol.gd")
static func summary(row: Variant) -> bool:
	return A.keys(row,["tx","id","side","phase"]) and W.identifier(row.tx) and W.identifier(row.id) and row.side in ["sender","receiver"] and row.phase in ["prepared","committed","acknowledged","rolled_back","unresolved"]
static func valid(f: Dictionary) -> bool:
	if not A.keys(f,["type","protocol","session_id","tx","kind","data"]) or f.type != "transfer_tx" or not A.number(f.protocol,1,65535) or not W.identifier(f.session_id) or not W.identifier(f.tx): return false
	var d: Variant = f.data
	match f.kind:
		"summary_request": return A.keys(d,[])
		"prepare": return A.keys(d,["request","card","revealed"]) and W.identifier(d.request) and A.card(d.card) and d.revealed is bool
		"prepared", "commit", "committed", "rollback": return A.keys(d,["id"]) and W.identifier(d.id)
		"summary":
			if not A.keys(d,["transactions"]) or not d.transactions is Array or d.transactions.size() > 256: return false
			var ids: Dictionary = {}
			for row: Variant in d.transactions:
				if not summary(row) or ids.has(row.tx): return false
				ids[row.tx] = true
			return true
	return false
