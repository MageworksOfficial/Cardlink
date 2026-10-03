extends RefCounted
## Only decoded, bounded images enter this content-addressed store.
const MAX_BYTES = 8388608
var directory: String = "user://table_images"
var textures: Dictionary = {}
func path(hash: String) -> String:
	return directory.path_join(hash+".png") if preload("res://scripts/custom_table/table_document.gd").hash_id(hash,64) else ""
func ingest(file: String) -> Dictionary:
	if not file.get_extension().to_lower() in ["png","jpg","jpeg","webp"]: return {"error":"Choose a PNG, JPEG or WebP image."}
	var f := FileAccess.open(file,FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES: return {"error":"Choose an image smaller than 8 MB."}
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	# Read dimensions before allocating decoded pixels.
	var dimensions: Vector2i = preload("res://scripts/archive_image_header.gd").dimensions(bytes,file.get_extension().to_lower())
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > 4096 or dimensions.y > 4096: return {"error":"Image must be no larger than 4096 x 4096."}
	var image := Image.new()
	var error: Error = image.load(file)
	if error != OK or image.get_width() > 4096 or image.get_height() > 4096: return {"error":"Image must be readable and no larger than 4096 x 4096."}
	return store(image.save_png_to_buffer())
func store(bytes: PackedByteArray, expected: String = "") -> Dictionary:
	if bytes.size() > MAX_BYTES or bytes.size() < 24 or bytes.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]): return {"error":"Invalid board image."}
	var w: int = (int(bytes[16])<<24)|(int(bytes[17])<<16)|(int(bytes[18])<<8)|int(bytes[19])
	var h: int = (int(bytes[20])<<24)|(int(bytes[21])<<16)|(int(bytes[22])<<8)|int(bytes[23])
	if w < 1 or h < 1 or w > 4096 or h > 4096: return {"error":"Board image dimensions are out of range."}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var hash: String = ctx.finish().hex_encode()
	if not expected.is_empty() and hash != expected: return {"error":"Board image verification failed."}
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK: return {"error":"Board image is corrupt."}
	DirAccess.make_dir_recursive_absolute(directory)
	var target: String = path(hash)
	if not FileAccess.file_exists(target):
		var f := FileAccess.open(target+".tmp",FileAccess.WRITE)
		if f == null: return {"error":"Could not store board image."}
		f.store_buffer(bytes)
		f.close()
		if DirAccess.rename_absolute(target+".tmp",target) != OK: return {"error":"Could not finish storing board image."}
	return {"hash":hash}
func texture(hash: String) -> Texture2D:
	if hash.is_empty() or path(hash).is_empty() or not FileAccess.file_exists(path(hash)): return null
	if not textures.has(hash):
		var image := Image.new()
		if image.load(path(hash)) != OK: return null
		textures[hash] = ImageTexture.create_from_image(image)
	return textures[hash]
