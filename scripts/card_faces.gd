extends RefCounted
## Local definition adapter. Paths never enter public face-change messages.
const MAX_FACES = 16
static func signature(faces: Array) -> String:
	var keys: Array = []
	for face: Dictionary in faces: keys.append([face.name,face.get("image_hash",face.get("hash",""))])
	return JSON.stringify(keys).sha256_text()
static func list(metadata: Dictionary) -> Array:
	if metadata.has("faces"): return metadata.faces.duplicate(true) if validate(metadata.faces).is_empty() else []
	return [{"face_id":"front","face_index":0,"name":metadata.get("name","Card"),"image_path":metadata.get("image_path",""),"image_hash":metadata.get("image_hash","")}]
static func validate(faces: Variant) -> String:
	if not faces is Array or faces.is_empty() or faces.size() > MAX_FACES: return "A card needs 1–16 faces."
	var ids: Dictionary = {}
	for i: int in faces.size():
		var face: Variant = faces[i]
		if not face is Dictionary: return "Invalid face."
		for key: String in ["face_id","name","image_path","image_hash"]:
			if not face.get(key) is String: return "Invalid face " + key
		if face.face_id.is_empty() or ids.has(face.face_id) or face.name.strip_edges().is_empty() or face.name.length()>160: return "Invalid or duplicate face identity."
		if not preload("res://scripts/network/card_sync_protocol.gd").hash_ok(face.image_hash): return "Invalid face image hash."
		if face.get("face_index",i) != i: return "Invalid face order."
		ids[face.face_id] = true
	return ""
static func apply(state: RefCounted, index: int) -> bool:
	if index < 0 or index >= state.faces.size(): return false
	state.active_face_index = index
	state.display_name = state.faces[index].name
	state.image_path = state.faces[index].image_path
	return true
static func from_definition(state: RefCounted, metadata: Dictionary) -> void:
	state.faces = list(metadata)
	if not validate(state.faces).is_empty(): state.faces = []
	if not state.faces.is_empty(): apply(state,clampi(state.active_face_index,0,state.faces.size()-1))
static func save(directory: String, name: String, faces: Array, original: Dictionary = {}) -> Dictionary:
	var error: String = validate(faces)
	if not error.is_empty(): return {"error":error}
	for face: Dictionary in faces:
		if face.image_path != directory.path_join(face.image_hash+".png") or not FileAccess.file_exists(face.image_path) or FileAccess.get_sha256(face.image_path) != face.image_hash: return {"error":"Face requires a verified image in this library."}
	var metadata: Dictionary = original.duplicate(true) if not original.is_empty() else preload("res://scripts/card_metadata.gd").create(name,faces[0].image_hash,faces[0].image_path,Vector2i(750,1050))
	metadata.name = name.strip_edges() if not name.strip_edges().is_empty() else faces[0].name
	metadata.faces = faces.duplicate(true)
	metadata.image_path = faces[0].image_path
	metadata.image_hash = faces[0].image_hash
	var path: String = directory.path_join("definitions").path_join(str(metadata.card_id)+".json")
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return {"error":"Cannot create definition folder."}
	if preload("res://scripts/card_storage.gd").write_atomic(path,JSON.stringify(metadata,"\t").to_utf8_buffer()) != OK: return {"error":"Cannot save multi-face definition."}
	return {"metadata":metadata,"metadata_path":path,"reused":true}
static func resolve(state: RefCounted, directory: String) -> void:
	# Populate available faces from the locally approved Card Sync catalog only.
	if not state.faces.is_empty(): return
	var folder: String = directory.path_join("definitions")
	if not DirAccess.dir_exists_absolute(folder): return
	var candidates: Array = []
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() != "json": continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file)))
		if not data is Dictionary: continue
		var faces: Array = list(data)
		if not validate(faces).is_empty(): continue
		if not faces.any(func(face: Dictionary) -> bool: return face.image_path == state.image_path): continue
		var rank: int = 0 if data.get("peer_definition_id","") == state.card_definition_id else 1 if data.get("card_id","") == state.card_definition_id else 2 if faces.size()>1 else 3
		candidates.append({"rank":rank,"faces":faces})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.rank<b.rank)
	if not candidates.is_empty(): state.faces = candidates[0].faces
