extends RefCounted
const Library = preload("res://scripts/library_storage.gd")
static func normalized_name(value: String) -> String:
	return " ".join(value.strip_edges().split(" ", false)).to_lower()
static func key(name: String, hash: String) -> String:
	return JSON.stringify([normalized_name(name), hash])
static func digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
static func scan(directory: String) -> Dictionary:
	var storage := Library.new(directory)
	var records: Array[Dictionary] = []
	var ids: Dictionary = {}
	var signatures: Array = []
	var assets: Dictionary = {}
	var folder: String = directory.path_join("definitions")
	if DirAccess.dir_exists_absolute(folder):
		for filename: String in DirAccess.get_files_at(folder):
			if filename.get_extension().to_lower() != "json":
				continue
			var path: String = folder.path_join(filename)
			signatures.append([path, FileAccess.get_sha256(path)])
			var read: Dictionary = storage.read_definition(path)
			if read.has("error"):
				continue
			var meta: Dictionary = read.metadata
			if not meta.get("card_id") is String or not meta.get("name") is String or not meta.get("image_hash") is String or not meta.get("image_path") is String or meta.card_id.is_empty():
				continue
			ids[meta.card_id] = int(ids.get(meta.card_id, 0)) + 1
			var asset: String = meta.image_path
			if asset.contains("..") or asset.get_base_dir().simplify_path() != directory.simplify_path() or not FileAccess.file_exists(asset):
				continue
			if not assets.has(asset):
				assets[asset] = FileAccess.get_sha256(asset)
				signatures.append([asset, assets[asset]])
			if meta.image_hash != assets[asset] or meta.get("width") != 750 or meta.get("height") != 1050:
				continue
			if meta.has("faces"):
				if not preload("res://scripts/card_faces.gd").validate(meta.faces).is_empty(): continue
				var valid_faces: bool = true
				for face: Dictionary in meta.faces:
					var face_path: String = directory.path_join(face.image_hash+".png")
					var actual: String = FileAccess.get_sha256(face_path) if FileAccess.file_exists(face_path) else "missing"
					signatures.append([face_path,actual])
					if face.image_path != face_path or actual != face.image_hash: valid_faces = false
				if not valid_faces: continue
			records.append({"id": meta.card_id, "name": meta.name, "hash": meta.image_hash, "art_signature": preload("res://scripts/card_faces.gd").signature(meta.faces) if meta.has("faces") else meta.image_hash, "path": path})
	var by_key: Dictionary = {}
	var by_id: Dictionary = {}
	var by_name: Dictionary = {}
	for row: Dictionary in records:
		if ids[row.id] != 1:
			continue
		by_id[row.id] = row
		var identity: String = key(row.name, row.hash)
		if not by_key.has(identity):
			by_key[identity] = row
		by_name[normalized_name(row.name)] = true
	return {"by_key": by_key, "by_id": by_id, "by_name": by_name, "signature": digest(JSON.stringify(signatures).to_utf8_buffer())}
static func group(rows: Array) -> Array[Dictionary]:
	# A numbered suffix is a copy only when an unsuffixed base with identical art exists.
	var originals: Dictionary = {}
	for row: Dictionary in rows:
		originals[key(row.name, row.hash)] = row.name
	var copies := RegEx.new()
	copies.compile("^(.*?)(?: \\(([2-9][0-9]*|1[0-9]+)\\)|_([2-9][0-9]*|1[0-9]+))$")
	var result: Array[Dictionary] = []
	var indices: Dictionary = {}
	for source: Dictionary in rows:
		var row: Dictionary = source.duplicate()
		var found: RegExMatch = copies.search(row.name)
		if found != null and originals.has(key(found.get_string(1), row.hash)):
			row.name = originals[key(found.get_string(1), row.hash)]
		var identity: String = key(row.name, row.hash)
		if indices.has(identity):
			result[indices[identity]].quantity += 1
			result[indices[identity]].files.append(row.file)
		else:
			row["quantity"] = 1
			row["files"] = [row.file]
			indices[identity] = result.size()
			result.append(row)
	return result
static func deck_rows(deck: Dictionary, catalog: Dictionary) -> Array:
	var rows: Array = []
	for entry: Dictionary in deck.cards:
		var record: Dictionary = catalog.by_id.get(entry.card_id, {})
		if record.is_empty():
			var hint: Variant = deck.get("archive_import", {})
			if hint is Dictionary and hint.get("rows", []) is Array:
				for saved: Variant in hint.get("rows", []):
					if saved is Dictionary and saved.get("id") == entry.card_id:
						record = saved
		rows.append({"id": entry.card_id, "name": str(record.get("name", "Missing definition " + entry.card_id)), "hash": str(record.get("hash", "missing")), "art_signature": record.get("art_signature",record.get("hash","missing")), "quantity": int(entry.quantity)})
	return rows
static func by_name(rows: Array) -> Dictionary:
	var groups: Dictionary = {}
	for row: Dictionary in rows:
		var name: String = normalized_name(row.name)
		if not groups.has(name):
			groups[name] = {"name": row.name, "quantity": 0, "art": {}}
		groups[name].quantity += row.quantity
		var art: String = row.get("art_signature",row.hash)
		groups[name].art[art] = int(groups[name].art.get(art, 0)) + row.quantity
	return groups
static func compare(incoming: Array, previous: Array) -> Dictionary:
	var now: Dictionary = by_name(incoming)
	var old: Dictionary = by_name(previous)
	var result: Dictionary = {"added": [], "removed": [], "quantities": [], "artwork": [], "unchanged": []}
	for name: String in now:
		if not old.has(name):
			result.added.append("%s × %d" % [now[name].name, now[name].quantity])
			continue
		var a: Dictionary = now[name].art
		var b: Dictionary = old[name].art
		var same_art: bool = a.size() == b.size()
		for hash: String in a:
			same_art = same_art and b.has(hash)
		if not same_art:
			result.artwork.append(now[name].name)
		if now[name].quantity != old[name].quantity or (same_art and a != b):
			result.quantities.append("%s: %d → %d" % [now[name].name, old[name].quantity, now[name].quantity])
		if same_art and a == b:
			result.unchanged.append(now[name].name)
	for name: String in old:
		if not now.has(name):
			result.removed.append("%s × %d" % [old[name].name, old[name].quantity])
	return result
