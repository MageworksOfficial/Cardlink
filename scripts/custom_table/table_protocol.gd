extends RefCounted
const Doc = preload("res://scripts/custom_table/table_document.gd")
static func valid(message: Dictionary) -> bool:
	if message.size() != 5 or message.get("type") != "table_structure" or message.get("protocol") != 1 or not Doc.hash_id(message.get("session_id"),32) or not message.get("data") is Dictionary: return false
	var data: Dictionary = message.data
	match message.get("kind"):
		"members":
			if data.size() != 2 or not Doc.hash_id(data.get("id"),32) or not data.get("cards") is Array or data.cards.size() > 500: return false
			for id: Variant in data.cards:
				if not preload("res://scripts/network/card_sync_protocol.gd").identifier(id): return false
			return true
		"count": return data.size() == 2 and Doc.hash_id(data.get("id"),32) and Doc.number(data.get("count"),0,5000) and data.count == floor(data.count)
		"draw": return data.size() == 2 and Doc.hash_id(data.get("id"),32) and data.get("player") in ["player_1","player_2"]
		"shuffle": return data.size() == 1 and Doc.hash_id(data.get("id"),32)
		"place": return data.size() == 2 and Doc.hash_id(data.get("id"),32) and preload("res://scripts/network/card_sync_protocol.gd").identifier(data.get("card"))
		"draw_offer": return data.size() == 2 and Doc.hash_id(data.get("id"),32) and data.get("request") is String and data.request.begins_with("table_") and Doc.hash_id(data.request.substr(6),32)
		"table", "edit": return data.size() == 1 and data.has("table") and Doc.validate(data.table).is_empty()
		"need": return data.size() == 1 and Doc.hash_id(data.get("hash"),64)
		"image": return data.size() == 4 and Doc.hash_id(data.get("hash"),64) and Doc.number(data.get("offset"),0,8388608) and data.offset == floor(data.offset) and Doc.number(data.get("total"),24,8388608) and data.total == floor(data.total) and data.get("bytes") is String and data.bytes.length() <= 43692
	return false
