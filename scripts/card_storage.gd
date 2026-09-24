extends RefCounted
## Content-addressed PNG assets and one JSON file per definition.
const Metadata = preload("res://scripts/card_metadata.gd")
var directory: String = "user://cards"

func _init(storage_directory: String = "user://cards") -> void:
	directory = storage_directory

func save_asset(png: PackedByteArray) -> Dictionary:
	if png.is_empty():
		return {"error": "The normalized image could not be encoded."}
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(png)
	var image_hash: String = hashing.finish().hex_encode()
	var asset_path: String = directory.path_join(image_hash + ".png")
	var definitions: String = directory.path_join("definitions")
	var error: Error = DirAccess.make_dir_recursive_absolute(definitions)
	if error != OK:
		return {"error": "Cannot create card storage: " + error_string(error)}
	var reused: bool = FileAccess.file_exists(asset_path)
	if reused:
		if FileAccess.get_sha256(asset_path) != image_hash:
			return {"error": "An existing card asset is damaged. Import stopped without overwriting it."}
	else:
		error = write_atomic(asset_path, png)
		if error != OK:
			return {"error": "Cannot save card image: " + error_string(error)}
	return {"image_hash":image_hash,"image_path":asset_path,"reused":reused}

func save_card(png: PackedByteArray, card_name: String, source_size: Vector2i) -> Dictionary:
	var asset: Dictionary = save_asset(png)
	if asset.has("error"): return asset
	var image_hash: String = asset.image_hash
	var asset_path: String = asset.image_path
	var reused: bool = asset.reused
	var definitions: String = directory.path_join("definitions")
	var error: Error = OK
	var metadata: Dictionary = Metadata.create(card_name, image_hash, asset_path, source_size)
	var metadata_path: String = definitions.path_join(str(metadata["card_id"]) + ".json")
	while FileAccess.file_exists(metadata_path):
		metadata = Metadata.create(card_name, image_hash, asset_path, source_size)
		metadata_path = definitions.path_join(str(metadata["card_id"]) + ".json")
	error = write_atomic(metadata_path, JSON.stringify(metadata, "\t").to_utf8_buffer())
	if error != OK:
		# Keep a successfully saved content-addressed asset for retry/reuse.
		return {"error": "Cannot save card metadata: " + error_string(error)}
	return {"metadata": metadata, "metadata_path": metadata_path, "reused": reused}

static func write_atomic(path: String, bytes: PackedByteArray) -> Error:
	var temporary: String = path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error
