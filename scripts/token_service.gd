extends RefCounted
## Central lifecycle policy; custom formats can replace this predicate later.
static func expires_in(state: RefCounted, kind: String) -> bool:
	return state.is_token and kind in ["hand", "deck", "library", "graveyard", "exile", "commander"]
static func import_art(path: String, directory: String) -> Dictionary:
	var loaded: Dictionary = preload("res://scripts/card_image_processor.gd").load_source(path)
	if loaded.has("error"):
		return loaded
	var image: Image = loaded.image
	var scale_factor: float = minf(1.0, 1050.0 / maxf(image.get_width(), image.get_height()))
	image.resize(maxi(1, roundi(image.get_width() * scale_factor)), maxi(1, roundi(image.get_height() * scale_factor)))
	var bytes: PackedByteArray = image.save_png_to_buffer()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	# A separate managed art folder is not subject to orphan card-library cleanup.
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"error": "Cannot create token art storage."}
	var target: String = directory.path_join(hash.finish().hex_encode() + ".png")
	if not FileAccess.file_exists(target):
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return {"error": "Cannot save token art."}
		file.store_buffer(bytes)
	return {"path": target}
