extends RefCounted
## CPU image processing; independent of UI and GPU rendering.
const OUTPUT_SIZE := Vector2i(750, 1050)
const BACKGROUND := Color(0.09, 0.105, 0.13, 1.0)
const MAX_FILE_BYTES: int = 128 * 1024 * 1024
const MAX_PIXELS: int = 64 * 1024 * 1024
const MAX_DIMENSION: int = 16384

static func load_source(path: String) -> Dictionary:
	if not path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
		return {"error": "Choose a PNG, JPG, JPEG, or WebP image."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open the selected image: " + error_string(FileAccess.get_open_error())}
	var length: int = file.get_length()
	file.close()
	if length > MAX_FILE_BYTES:
		return {"error": "This file exceeds the 128 MB import limit."}
	var source := Image.new()
	var error: Error = source.load(path)
	if error != OK or source.is_empty():
		return {"error": "The selected image is unreadable or damaged."}
	if source.get_width() * source.get_height() > MAX_PIXELS:
		return {"error": "This image exceeds the 64 megapixel import limit."}
	if source.get_width() > MAX_DIMENSION or source.get_height() > MAX_DIMENSION:
		return {"error": "Image dimensions must not exceed 16384 pixels on either side."}
	source.convert(Image.FORMAT_RGBA8)
	return {"image": source}

static func low_resolution(source: Image, crop: Rect2) -> bool:
	return source.get_width() < OUTPUT_SIZE.x or source.get_height() < OUTPUT_SIZE.y or crop.size.x < OUTPUT_SIZE.x or crop.size.y < OUTPUT_SIZE.y

static func load_buffer(bytes: PackedByteArray, extension: String) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_FILE_BYTES:
		return {"error": "Empty or oversized image."}
	var dimensions: Vector2i = preload("res://scripts/archive_image_header.gd").dimensions(bytes, extension)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > MAX_DIMENSION or dimensions.y > MAX_DIMENSION or dimensions.x * dimensions.y > MAX_PIXELS:
		return {"error": "Invalid image header or image exceeds the supported dimensions."}
	var source := Image.new()
	var error: Error = ERR_FILE_UNRECOGNIZED
	match extension:
		"png": error = source.load_png_from_buffer(bytes)
		"jpg", "jpeg": error = source.load_jpg_from_buffer(bytes)
		"webp": error = source.load_webp_from_buffer(bytes)
	if error != OK or source.is_empty() or source.get_width() > MAX_DIMENSION or source.get_height() > MAX_DIMENSION or source.get_width() * source.get_height() > MAX_PIXELS:
		return {"error": "The image is corrupt or exceeds the pixel limit."}
	source.convert(Image.FORMAT_RGBA8)
	return {"image": source}

static func batch_crop(source: Image, fit: bool = false) -> Rect2:
	# Same centered Fit/Fill framing as CropPreview; no per-card dialog required.
	var width: float = maxf(source.get_width(), source.get_height() * 5.0 / 7.0) if fit else minf(source.get_width(), source.get_height() * 5.0 / 7.0)
	var extent := Vector2(width, width * 7.0 / 5.0)
	return Rect2(Vector2(source.get_size()) / 2.0 - extent / 2.0, extent)

static func normalize(source: Image, crop: Rect2) -> Image:
	if source == null or source.is_empty() or crop.size.x <= 0.0 or crop.size.y <= 0.0:
		return null
	if not is_equal_approx(crop.size.x / crop.size.y, 5.0 / 7.0):
		return null
	var result := Image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(BACKGROUND)
	# Sample the exact floating-point crop transform. Both axes use one scale,
	# so pan/zoom and letterboxing match the preview without stretching.
	var step: float = crop.size.x / float(OUTPUT_SIZE.x)
	var width: int = source.get_width()
	var height: int = source.get_height()
	for y: int in range(OUTPUT_SIZE.y):
		var sy: float = crop.position.y + (float(y) + 0.5) * step
		if sy < 0.0 or sy >= height:
			continue
		var py: float = clampf(sy - 0.5, 0.0, float(height - 1))
		var y0: int = int(floor(py))
		var y1: int = mini(y0 + 1, height - 1)
		var fy: float = py - y0
		for x: int in range(OUTPUT_SIZE.x):
			var sx: float = crop.position.x + (float(x) + 0.5) * step
			if sx < 0.0 or sx >= width:
				continue
			var px: float = clampf(sx - 0.5, 0.0, float(width - 1))
			var x0: int = int(floor(px))
			var x1: int = mini(x0 + 1, width - 1)
			var fx: float = px - x0
			var top: Color = source.get_pixel(x0, y0).lerp(source.get_pixel(x1, y0), fx)
			var bottom: Color = source.get_pixel(x0, y1).lerp(source.get_pixel(x1, y1), fx)
			result.set_pixel(x, y, BACKGROUND.blend(top.lerp(bottom, fy)))
	return result

