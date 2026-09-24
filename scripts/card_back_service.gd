extends RefCounted
## Presentation preference; never read a card's identity to choose its back.
signal changed
var directory: String = "user://settings"
var selected_id: String = "cardlink"
var textures: Dictionary = {}
func _init(path: String = "user://settings") -> void:
	directory = path
	textures.cardlink = preload("res://assets/cardlink_back.svg")
	reload()
func reload() -> void:
	selected_id = "cardlink"
	var settings := ConfigFile.new()
	if settings.load(directory.path_join("card_backs.cfg")) == OK:
		var id: String = str(settings.get_value("backs", "default", "cardlink"))
		if id.begins_with("custom_") and id.length() == 71 and id.substr(7).is_valid_hex_number():
			var image := Image.new()
			if FileAccess.file_exists(directory.path_join(id + ".png")) and image.load(directory.path_join(id + ".png")) == OK:
				textures[id] = ImageTexture.create_from_image(image)
				selected_id = id
	changed.emit()
func texture(back_id: String = "") -> Texture2D:
	return textures.get(back_id if textures.has(back_id) else selected_id, textures.cardlink)
func save_choice(id: String) -> String:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "Cannot create settings directory."
	var settings := ConfigFile.new()
	settings.set_value("backs", "default", id)
	var path: String = directory.path_join("card_backs.cfg")
	if settings.save(path + ".tmp") != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return "Could not save card-back preference."
	selected_id = id
	changed.emit()
	return ""
func use_default() -> String:
	return save_choice("cardlink")
func import_custom(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 128 * 1024 * 1024:
		return "Cannot read image, or image exceeds 128 MB."
	file.close()
	var image := Image.new()
	if image.load(path) != OK or image.is_empty():
		return "Choose a readable PNG, JPG or WebP image."
	if image.get_width() * image.get_height() > 64000000:
		return "Image exceeds 64 megapixels."
	# Center crop to 5:7, then composite alpha onto an opaque back.
	var crop_width: int = mini(image.get_width(), floori(image.get_height() * 5.0 / 7.0))
	var crop_height: int = mini(image.get_height(), floori(crop_width * 7.0 / 5.0))
	if crop_width < 1 or crop_height < 1:
		return "Image dimensions are too small."
	image = image.get_region(Rect2i((image.get_width() - crop_width) / 2, (image.get_height() - crop_height) / 2, crop_width, crop_height))
	image.resize(500, 700, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	var opaque := Image.create(500, 700, false, Image.FORMAT_RGBA8)
	opaque.fill(Color("101b2d"))
	opaque.blend_rect(image, Rect2i(0, 0, 500, 700), Vector2i.ZERO)
	var bytes: PackedByteArray = opaque.save_png_to_buffer()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var id: String = "custom_" + hash.finish().hex_encode()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "Cannot create card-back storage."
	if opaque.save_png(directory.path_join(id + ".png")) != OK:
		return "Cannot save custom card back."
	textures[id] = ImageTexture.create_from_image(opaque)
	return save_choice(id)
