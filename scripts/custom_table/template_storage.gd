extends RefCounted
const Doc = preload("res://scripts/custom_table/table_document.gd")
var directory: String = "user://templates"
var assets = preload("res://scripts/custom_table/table_assets.gd").new()
func save(data: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(directory)
	return export_file(data,directory.path_join(str(data.get("id","invalid"))+".cltemplate"),false)
func export_file(data: Dictionary, target: String, include_images: bool) -> Dictionary:
	var error: String = Doc.validate(data)
	if not error.is_empty(): return {"error":error}
	var images: Dictionary = {}
	if include_images:
		var bg: String=data.get("background",{}).get("asset","")
		if not bg.is_empty() and FileAccess.file_exists(assets.path(bg)): images[bg]=Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(assets.path(bg)))
		for row: Dictionary in data.components:
			for key: String in ["asset","back"]:
				var hash: String = row[key]
				if not hash.is_empty() and FileAccess.file_exists(assets.path(hash)):
					images[hash] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(assets.path(hash)))
	var payload: String = JSON.stringify({"table":data,"images":images},"\t")
	if payload.to_utf8_buffer().size() > 16777216: return {"error":"Template package is too large (maximum 16 MB)."}
	var file := FileAccess.open(target+".tmp",FileAccess.WRITE)
	if file == null: return {"error":"Could not write the template."}
	file.store_string(payload)
	file.close()
	if DirAccess.rename_absolute(target+".tmp",target) != OK: return {"error":"Could not finish saving the template."}
	return {"path":target}
func preview(file: String) -> Dictionary:
	var f := FileAccess.open(file,FileAccess.READ)
	if f == null or f.get_length() > 16777216: return {"error":"Template cannot be read or is too large."}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not json.data is Dictionary: return {"error":"Malformed template file."}
	var pack: Dictionary = json.data
	if pack.size() != 2 or not pack.has("table") or not pack.get("images") is Dictionary or pack.images.size() > 128: return {"error":"Invalid template package."}
	var error: String = Doc.validate(pack.table)
	if not error.is_empty(): return {"error":error}
	var needed: Dictionary = {}
	var bg: String=pack.table.get("background",{}).get("asset","")
	if not bg.is_empty(): needed[bg]=true
	for row: Dictionary in pack.table.components:
		for key: String in ["asset","back"]:
			if not row[key].is_empty(): needed[row[key]] = true
	for hash: Variant in pack.images:
		if not Doc.hash_id(hash,64) or not needed.has(hash) or not pack.images[hash] is String or pack.images[hash].length() > 11184812: return {"error":"Invalid optional image."}
	var missing: Array = []
	for hash: String in needed:
		if not pack.images.has(hash) and not FileAccess.file_exists(assets.path(hash)): missing.append(hash)
	return {"table":pack.table,"images":pack.images,"missing":missing}
func import_file(file: String) -> Dictionary:
	var result: Dictionary = preview(file)
	if result.has("error"): return result
	# Validate all embedded bytes before storing any image or template.
	for hash: String in result.images:
		var bytes: PackedByteArray = Marshalls.base64_to_raw(result.images[hash])
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(bytes)
		if bytes.size() > assets.MAX_BYTES or ctx.finish().hex_encode() != hash: return {"error":"An included image failed verification."}
	for hash: String in result.images:
		var stored: Dictionary = assets.store(Marshalls.base64_to_raw(result.images[hash]),hash)
		if stored.has("error"): return stored
	var saved: Dictionary = save(result.table)
	return saved if saved.has("error") else result
func list_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(directory): return result
	for file: String in DirAccess.get_files_at(directory):
		if not file.ends_with(".cltemplate"): continue
		var data: Dictionary = preview(directory.path_join(file))
		if not data.has("error"): result.append({"path":directory.path_join(file),"name":data.table.name})
	return result

func duplicate_template(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy.id = Doc.fresh().id
	copy.name = str(copy.name).left(74)+" Copy"
	var result: Dictionary = save(copy)
	return result if result.has("error") else {"table":copy,"path":result.path}
func delete_template(id: String) -> String:
	if not Doc.hash_id(id,32): return "Built-in or invalid templates cannot be deleted."
	var path: String = directory.path_join(id+".cltemplate")
	if not FileAccess.file_exists(path): return "Template not found."
	return "" if DirAccess.remove_absolute(path) == OK else "Could not delete template."
