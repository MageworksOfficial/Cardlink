extends RefCounted
## One card definition, independent of any future match instance.

static func create(card_name: String, image_hash: String, image_path: String, source_size: Vector2i) -> Dictionary:
	var identifier: String = Crypto.new().generate_random_bytes(16).hex_encode()
	return {
		"schema_version": 1,
		"card_id": identifier,
		"name": card_name.strip_edges() if not card_name.strip_edges().is_empty() else "Untitled Card",
		"image_hash": image_hash,
		"image_path": image_path,
		"width": 750,
		"height": 1050,
		"source_width": source_size.x,
		"source_height": source_size.y,
		"created_at": Time.get_datetime_string_from_system(true),
		"tags": []
	}
