extends RefCounted
## Whitelist useful provider metadata; never store whole API responses as definitions.
static func compact(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.get("object", "card")!="card": return {}
	for key: String in ["id","name","set","collector_number"]:
		if not raw.get(key) is String or str(raw[key]).is_empty(): return {}
	var result: Dictionary = {}
	for key: String in ["id","name","oracle_id","set","set_name","collector_number","lang","released_at","scryfall_uri","layout"]:
		result[key] = str(raw.get(key,""))
	result["digital"] = bool(raw.get("digital",false))
	var faces: Array = []
	# Split/adventure cards can have logical faces but only one printed image.
	if raw.get("image_uris") is Dictionary:
		faces.append(face(raw.name,raw.image_uris))
	elif raw.get("card_faces") is Array:
		for item: Variant in raw.card_faces:
			if not item is Dictionary or not item.get("image_uris") is Dictionary: return {}
			faces.append(face(str(item.get("name",raw.name)),item.image_uris))
	if faces.is_empty() or faces.size()>16 or faces.any(func(f: Dictionary) -> bool:return f.image.is_empty()): return {}
	result["faces"] = faces
	return result
static func face(name: String, images: Dictionary) -> Dictionary:
	return {"name":name,"image":str(images.get("png",images.get("large",""))),"thumbnail":str(images.get("small",images.get("normal","")))}
static func same_name(card: Dictionary, name: String) -> bool:
	var wanted: String = name.strip_edges().to_lower()
	return str(card.get("name","")).to_lower()==wanted or str(card.get("name","")).split(" // ")[0].to_lower()==wanted
