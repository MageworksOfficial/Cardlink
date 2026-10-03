extends RefCounted
## Uses the normal CardLink library; all paths are generated locally.
const Wire = preload("res://scripts/network/card_sync_protocol.gd")
const Storage = preload("res://scripts/card_storage.gd")
var directory: String
var records: Array[Dictionary] = []
var verified: Dictionary = {}
func _init(path: String = "user://cards") -> void:
	directory = path
	reload()
func reload() -> void:
	records.clear()
	var folder: String = directory.path_join("definitions")
	for file: String in DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(folder) else PackedStringArray():
		if file.get_extension() != "json": continue
		var row: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file)))
		if row is Dictionary: records.append(row)
static func descriptor(metadata: Dictionary) -> Dictionary:
	var tags: Array = []
	if metadata.get("tags") is Array:
		for tag: Variant in metadata.tags:
			if tag is String and tags.size() < 24: tags.append(tag.left(48))
	var result: Dictionary = {"id":metadata.get("card_id",""),"name":metadata.get("name",""),"hash":metadata.get("image_hash",""),"tags":tags}
	var faces: Array = preload("res://scripts/card_faces.gd").list(metadata)
	if faces.size()>1:
		result["faces"] = []
		for face: Dictionary in faces: result.faces.append({"name":face.name,"hash":face.image_hash})
	return result
static func images(row: Dictionary) -> Array:
	var result: Array = [row.hash]
	for face: Dictionary in row.get("faces",[]):
		if not face.hash in result: result.append(face.hash)
	return result
func asset_path(hash: String) -> String:
	var canonical: String = directory.path_join(hash + ".png")
	if FileAccess.file_exists(canonical): return canonical
	# Legacy collections can retain a different local filename. Reuse only a
	# bounded, hash-verified image referenced inside this collection directory.
	for record: Dictionary in records:
		var candidates: Array = [record]
		if record.get("faces") is Array: candidates.append_array(record.faces)
		for face: Variant in candidates:
			if not face is Dictionary or face.get("image_hash") != hash or not face.get("image_path") is String: continue
			var path: String = face.image_path
			if path.contains("..") or ProjectSettings.globalize_path(path).get_base_dir().simplify_path() != ProjectSettings.globalize_path(directory).simplify_path(): continue
			var file := FileAccess.open(path,FileAccess.READ)
			if file == null: continue
			var length: int = file.get_length()
			file.close()
			if length <= Wire.MAX_IMAGE and FileAccess.get_sha256(path) == hash: return path
	return canonical
func has_image(hash: String) -> bool:
	if not Wire.hash_ok(hash): return false
	var path: String = asset_path(hash)
	if not FileAccess.file_exists(path): return false
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return false
	var length: int = file.get_length()
	file.close()
	if length > Wire.MAX_IMAGE: return false
	var stamp: String = path + ":" + str(FileAccess.get_modified_time(path)) + ":" + str(length)
	if verified.get(hash) == stamp: return true
	if FileAccess.get_sha256(path) != hash: return false
	# Existing content-addressed assets were validated by import/receive. Recheck their hash/header natively.
	var header_file := FileAccess.open(path,FileAccess.READ)
	if header_file == null: return false
	var header: PackedByteArray = header_file.get_buffer(33)
	header_file.close()
	if preload("res://scripts/archive_image_header.gd").dimensions(header,"png") != Vector2i(750,1050): return false
	verified[hash] = stamp
	return true
static func validate_image(hash: String, bytes: PackedByteArray) -> String:
	if not Wire.hash_ok(hash) or bytes.size() < 24 or bytes.size() > Wire.MAX_IMAGE: return "Invalid image size/hash."
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	if hasher.finish().hex_encode() != hash: return "Image hash mismatch."
	# Check PNG header and dimensions before invoking the image decoder.
	if bytes.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]) or bytes.slice(12,16).get_string_from_ascii() != "IHDR": return "Only normalized PNG gameplay assets are accepted."
	var width: int = (bytes[16]<<24) | (bytes[17]<<16) | (bytes[18]<<8) | bytes[19]
	var height: int = (bytes[20]<<24) | (bytes[21]<<16) | (bytes[22]<<8) | bytes[23]
	if width != 750 or height != 1050: return "Expected normalized 750 x 1050 gameplay image."
	if not png_complete(bytes): return "Corrupt or incomplete PNG gameplay image."
	var decoded: Dictionary = preload("res://scripts/card_image_processor.gd").load_buffer(bytes,"png")
	if decoded.has("error"): return "Corrupt gameplay image."
	return ""
func equivalent(row: Dictionary) -> bool:
	for m: Dictionary in records:
		if m.get("image_hash") == row.hash and str(m.get("name","")).strip_edges().to_lower() == row.name.strip_edges().to_lower() and descriptor(m).get("faces",[]) == row.get("faces",[]): return true
	return false
func check(manifest: Array) -> Dictionary:
	var result: Dictionary = {"definitions":[],"images":[],"missing":0,"available":0,"reused":0}
	var reused_hashes: Dictionary = {}
	for row: Dictionary in manifest:
		var image: bool = images(row).all(func(hash: String) -> bool: return has_image(hash))
		var definition_ok: bool = equivalent(row)
		if not definition_ok: result.definitions.append(row.id)
		for hash: String in images(row):
			if not has_image(hash) and not hash in result.images: result.images.append(hash)
		if definition_ok and image: result.available += 1
		else: result.missing += 1
		if image and not reused_hashes.has(row.hash):
			result.reused += 1
			reused_hashes[row.hash] = true
	return result
func store_image(hash: String, bytes: PackedByteArray) -> String:
	var error: String = validate_image(hash,bytes)
	if not error.is_empty(): return error
	if has_image(hash): return ""
	if FileAccess.file_exists(asset_path(hash)): return "Existing asset is damaged; not overwriting it silently."
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return "Cannot create card storage."
	return "" if Storage.write_atomic(asset_path(hash),bytes) == OK else "Cannot save verified image."
func store_definition(row: Dictionary) -> String:
	if not Wire.definition(row) or not images(row).all(func(hash: String) -> bool: return has_image(hash)): return "Definition requires a verified local gameplay image."
	if equivalent(row): return ""
	var id: String = row.id
	# Keep an existing conflicting ID/art untouched. Equivalent definitions reuse the existing local ID.
	for m: Dictionary in records:
		if m.get("card_id") == id:
			id = "peer_" + JSON.stringify(row).sha256_text().left(32)
	var folder: String = directory.path_join("definitions")
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return "Cannot create definition storage."
	var path: String = folder.path_join(id + ".json")
	if FileAccess.file_exists(path): return "Conflicting definition preserved; import refused."
	var m: Dictionary = preload("res://scripts/card_metadata.gd").create(row.name,row.hash,asset_path(row.hash),Vector2i(750,1050))
	if row.has("faces"):
		m["faces"] = []
		for i: int in row.faces.size():
			m.faces.append({"face_id":"face_"+str(i),"face_index":i,"name":row.faces[i].name,"image_hash":row.faces[i].hash,"image_path":asset_path(row.faces[i].hash)})
	m.card_id = id
	m.tags = row.tags.duplicate()
	m.received_from_peer = true
	m.peer_definition_id = row.id
	if Storage.write_atomic(path,JSON.stringify(m,"\t").to_utf8_buffer()) != OK: return "Cannot save definition."
	records.append(m)
	return ""

static var crc_table: PackedInt64Array = []
static func png_complete(bytes: PackedByteArray) -> bool:
	if crc_table.is_empty():
		for i: int in 256:
			var value: int = i
			for bit: int in 8: value = (value >> 1) ^ (0xedb88320 if value & 1 else 0)
			crc_table.append(value)
	var offset: int = 8
	var has_data: bool = false
	while offset + 12 <= bytes.size():
		var length: int = preload("res://scripts/archive_image_header.gd").be32(bytes,offset)
		if length > bytes.size() - offset - 12: return false
		var crc: int = 0xffffffff
		for i: int in range(offset+4,offset+8+length): crc = crc_table[(crc ^ bytes[i]) & 255] ^ (crc >> 8)
		if (crc ^ 0xffffffff) != preload("res://scripts/archive_image_header.gd").be32(bytes,offset+8+length): return false
		var kind: String = bytes.slice(offset+4,offset+8).get_string_from_ascii()
		if kind == "IDAT": has_data = true
		offset += length + 12
		if kind == "IEND": return has_data and length == 0 and offset == bytes.size()
	return false
