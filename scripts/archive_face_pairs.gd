extends RefCounted
const Catalog = preload("res://scripts/archive_catalog.gd")
static func signature(faces: Array) -> String:
	var keys: Array = []
	for face: Dictionary in faces: keys.append([face.name,face.get("image_hash",face.get("hash",""))])
	return JSON.stringify(keys).sha256_text()
static func detect(rows: Array) -> Array:
	var pattern := RegEx.new()
	pattern.compile("(?i)^(.*?)(?: - |_)\\s*(front|back)$")
	var groups: Dictionary = {}
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		var match_name: RegExMatch = pattern.search(row.name)
		if match_name == null or match_name.get_string(1).strip_edges().is_empty(): continue
		var folder: String = str(row.files[0]).get_base_dir()
		if not row.files.all(func(file: String) -> bool: return file.get_base_dir()==folder): continue
		var key: String = folder+"/"+match_name.get_string(1).to_lower()
		if not groups.has(key): groups[key] = []
		groups[key].append({"index":i,"side":match_name.get_string(2).to_lower(),"name":match_name.get_string(1).strip_edges()})
	var pairs: Array = []
	for group: Array in groups.values():
		if group.size()!=2 or group[0].side == group[1].side: continue
		var front: Dictionary = group[0] if group[0].side == "front" else group[1]
		var back: Dictionary = group[1] if group[0].side == "front" else group[0]
		if rows[front.index].quantity != rows[back.index].quantity: continue
		pairs.append({"front":front.index,"back":back.index,"name":front.name})
	return pairs
static func configure(plan: Dictionary, directory: String, enabled: bool) -> void:
	if not plan.has("separate_rows"): plan["separate_rows"] = plan.rows.duplicate(true)
	plan.rows = plan.separate_rows.duplicate(true)
	if enabled:
		var replacements: Dictionary = {}
		var skip: Array = []
		for pair: Dictionary in detect(plan.rows):
			var front: Dictionary = plan.rows[pair.front]
			var back: Dictionary = plan.rows[pair.back]
			var joined: Dictionary = front.duplicate()
			joined.name = pair.name
			joined["face_rows"] = [front,back]
			joined["art_signature"] = signature([front,back])
			joined.existing_id = ""
			replacements[pair.front] = joined
			skip.append(pair.back)
		var combined: Array = []
		for i: int in plan.rows.size():
			if not i in skip: combined.append(replacements.get(i,plan.rows[i]))
		plan.rows = combined
	var catalog: Dictionary = Catalog.scan(directory)
	plan.stats = {"new":0,"existing":0,"changed":0}
	for row: Dictionary in plan.rows:
		if row.has("face_rows"):
			for existing: Dictionary in catalog.by_id.values():
				if Catalog.normalized_name(existing.name)==Catalog.normalized_name(row.name) and existing.get("art_signature","")==row.art_signature: row.existing_id = existing.id; break
		if not row.existing_id.is_empty(): plan.stats.existing += 1
		else:
			plan.stats.new += 1
			if catalog.by_name.has(Catalog.normalized_name(row.name)): plan.stats.changed += 1
	for candidate: Dictionary in plan.candidates: candidate.diff = Catalog.compare(plan.rows,candidate.previous)
static func save_row(cards: RefCounted, row: Dictionary) -> Dictionary:
	if not row.has("face_rows"): return cards.save_card(row.png,row.name,row.source_size)
	var faces: Array = []
	for source: Dictionary in row.face_rows:
		if Catalog.digest(source.png) != source.hash: return {"error":"Face preview changed; scan again."}
		var saved: Dictionary = cards.save_asset(source.png)
		if saved.has("error"): return saved
		faces.append({"face_id":"face_"+str(faces.size()),"face_index":faces.size(),"name":source.name,"image_path":saved.image_path,"image_hash":saved.image_hash})
	return preload("res://scripts/card_faces.gd").save(cards.directory,row.name,faces)
