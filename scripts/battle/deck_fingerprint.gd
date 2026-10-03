extends RefCounted
## Functional identity excludes mutable match state, paths and deck labels/IDs.
static func definition(meta: Dictionary) -> String:
	var faces: Array=[]
	for face: Dictionary in meta.get("faces",[]): faces.append([str(face.get("name",meta.get("name",""))),str(face.get("image_hash",""))])
	if faces.is_empty(): faces.append([str(meta.get("name","")),str(meta.get("image_hash",""))])
	var tags: Array=meta.get("tags",[]).duplicate();tags.sort()
	return JSON.stringify([str(meta.get("name","")),faces,tags]).sha256_text()
static func calculate(sources: Array, records: Array) -> Dictionary:
	var by_id: Dictionary={}
	for r: Dictionary in records:
		var id: String=str(r.metadata.get("card_id",""))
		if by_id.has(id): return {"error":"Duplicate card definition ID."}
		by_id[id]=r.metadata
	var recipes: Array=[]
	for source: Dictionary in sources:
		if source.kind!="standard" or source.target!="local": continue
		var entries: Dictionary={};var leaders: Array=[]
		for row: Dictionary in source.deck.cards:
			if not by_id.has(row.card_id): return {"error":"A source deck definition is missing."}
			var key: String=definition(by_id[row.card_id])
			entries[key]=int(entries.get(key,0))+int(row.quantity)
		for id: String in source.deck.leaders:
			if not by_id.has(id): return {"error":"A leader definition is missing."}
			leaders.append(definition(by_id[id]))
		leaders.sort()
		var keys: Array=entries.keys();keys.sort();var cards: Array=[]
		for key: String in keys: cards.append([key,entries[key]])
		if not cards.is_empty(): recipes.append([cards,leaders,source.leaders])
	if recipes.size()!=1: return {"error":"Load one valid source deck before saving or restoring an online match."}
	return {"fingerprint":JSON.stringify(recipes).sha256_text()}
