extends RefCounted
## Definition references only. Paths are validated and duplicate IDs never overwrite.
var directory: String
func _init(path: String = "user://decks") -> void:
	directory = path
static func new_deck() -> Dictionary:
	return {"deck_id": "deck_" + Crypto.new().generate_random_bytes(16).hex_encode(), "deck_name": "New deck", "format_id": "custom", "cards": [], "leaders": []}
static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "Deck must be a JSON object."
	for field: String in ["deck_id", "deck_name", "format_id"]:
		if not value.get(field) is String or str(value[field]).strip_edges().is_empty():
			return "Missing or invalid " + field
	var id: String = value.deck_id
	if not id.is_valid_filename() or id.contains("..") or id.contains("/") or id.contains("\\"):
		return "Invalid deck ID."
	if not value.get("cards") is Array or not value.get("leaders") is Array:
		return "Cards and leaders must be arrays."
	var seen: Dictionary = {}
	var total: int = 0
	for entry: Variant in value.cards:
		if not entry is Dictionary or not entry.get("card_id") is String or str(entry.card_id).is_empty():
			return "Invalid card reference."
		var quantity: Variant = entry.get("quantity")
		if not (quantity is int or quantity is float) or not is_finite(float(quantity)) or float(quantity) != floor(float(quantity)) or float(quantity) < 1 or float(quantity) > 1000:
			return "Quantities must be whole numbers from 1 to 1000."
		if seen.has(entry.card_id):
			return "Duplicate card row; use quantity instead."
		seen[entry.card_id] = true
		total += int(quantity)
	if total > 2000:
		return "Local performance limit: 2000 copies per deck."
	var leaders: Dictionary = {}
	for id_value: Variant in value.leaders:
		if not id_value is String or not seen.has(id_value) or leaders.has(id_value):
			return "Each leader must be a unique card reference included in the deck."
		leaders[id_value] = true
	return ""
func list_decks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Dictionary = {}
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for filename: String in DirAccess.get_files_at(directory):
		if filename.get_extension().to_lower() != "json":
			continue
		var path: String = directory.path_join(filename)
		var parser := JSON.new()
		var file := FileAccess.open(path, FileAccess.READ)
		var error: String = "Cannot read deck."
		var data: Dictionary = {}
		if file != null:
			if parser.parse(file.get_as_text()) == OK:
				error = validate(parser.data)
				if parser.data is Dictionary:
					data = parser.data
			else:
				error = "Malformed JSON: " + parser.get_error_message()
		var row: Dictionary = {"path": path, "data": data, "error": error}
		result.append(row)
		var id: String = str(data.get("deck_id", ""))
		if not id.is_empty():
			if not ids.has(id):
				ids[id] = []
			ids[id].append(row)
	for id: String in ids:
		if ids[id].size() > 1:
			for row: Dictionary in ids[id]:
				row.error = "Duplicate deck ID; resolve the duplicate files before loading or saving."
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.data.get("deck_name", a.path)).naturalnocasecmp_to(str(b.data.get("deck_name", b.path))) < 0)
	return result
func save_deck(data: Dictionary, original_path: String = "") -> Dictionary:
	var error: String = validate(data)
	if not error.is_empty():
		return {"error": error}
	var path: String = directory.path_join(str(data.deck_id) + ".json") if original_path.is_empty() else original_path
	if not safe_path(path):
		return {"error": "Deck path is outside storage."}
	for row: Dictionary in list_decks():
		if str(row.data.get("deck_id", "")) == data.deck_id and row.path != original_path:
			return {"error": "Duplicate deck ID; save refused."}
	if not original_path.is_empty():
		if not FileAccess.file_exists(original_path):
			return {"error": "Original deck was removed; create a duplicate to save a new file."}
		var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(original_path))
		if not current is Dictionary or current.get("deck_id") != data.deck_id:
			return {"error": "Original deck identity changed; refresh before saving."}
	elif FileAccess.file_exists(path):
		return {"error": "Deck file already exists."}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"error": "Cannot create deck directory."}
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot write deck."}
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		return {"error": "Cannot finish saving deck; original retained."}
	return {"path": path}
func safe_path(path: String) -> bool:
	return not path.contains("..") and path.get_base_dir().simplify_path() == directory.simplify_path() and path.get_extension().to_lower() == "json"
func delete_deck(path: String) -> String:
	if not safe_path(path):
		return "Invalid deck path."
	return "" if DirAccess.remove_absolute(path) == OK else "Could not delete deck."
