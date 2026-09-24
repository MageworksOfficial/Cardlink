extends RefCounted
const SafeStorage = preload("res://scripts/library_storage.gd")
var storage: SafeStorage
func _init(directory: String = "user://cards") -> void:
	storage = SafeStorage.new(directory)
func load_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var ids: Dictionary = {}
	var definitions: String = storage.directory.path_join("definitions")
	if not DirAccess.dir_exists_absolute(definitions):
		return records
	for filename: String in DirAccess.get_files_at(definitions):
		if filename.get_extension().to_lower() != "json":
			continue
		var path: String = definitions.path_join(filename)
		var result: Dictionary = storage.read_definition(path)
		var metadata: Dictionary = result.get("metadata", {})
		var errors: Array[String] = []
		if result.has("error"):
			errors.append(result["error"])
		var card_name: String = metadata.get("name", "") if metadata.get("name") is String else ""
		if card_name.strip_edges().is_empty():
			card_name = "Unnamed card · " + filename.get_basename().left(12)
			errors.append("Missing name; enter one below.")
		var identifier: String = metadata.get("card_id", "") if metadata.get("card_id") is String else ""
		if identifier.is_empty():
			errors.append("Missing card ID.")
		var tags: Array[String] = []
		if metadata.get("tags", []) is Array:
			for value: Variant in metadata.get("tags", []):
				if value is String and not value.strip_edges().is_empty() and not tags.has(value.strip_edges()):
					tags.append(value.strip_edges())
		else:
			errors.append("Invalid tags; save tags to repair.")
		var image_path: String = metadata.get("image_path", "") if metadata.get("image_path") is String else ""
		var texture: Texture2D
		if image_path.get_base_dir().simplify_path() != storage.directory.simplify_path() or image_path.contains("..") or not FileAccess.file_exists(image_path):
			errors.append("Image missing.")
		else:
			var image := Image.new()
			if image.load(image_path) == OK:
				image.resize(180, 252, Image.INTERPOLATE_BILINEAR)
				texture = ImageTexture.create_from_image(image)
			else:
				errors.append("Image cannot be decoded.")
		var record: Dictionary = {"path": path, "metadata": metadata, "name": card_name, "tags": tags, "image_path": image_path, "thumbnail": texture, "errors": errors, "editable": not result.has("error"), "newest": FileAccess.get_modified_time(path)}
		var created: Variant = metadata.get("created_at")
		if created is String and valid_datetime(created):
			record["newest"] = Time.get_unix_time_from_datetime_string(created)
		records.append(record)
		if not identifier.is_empty():
			if not ids.has(identifier):
				ids[identifier] = []
			ids[identifier].append(record)
	for identifier: String in ids:
		if ids[identifier].size() > 1:
			for record: Dictionary in ids[identifier]:
				record["errors"].append("Duplicate card ID; this entry is identified by its JSON filename.")
	return records
static func filtered(records: Array[Dictionary], query: String, tag: String, newest: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		if not query.is_empty() and not str(record["name"]).to_lower().contains(query.to_lower()):
			continue
		if not tag.is_empty() and not record["tags"].has(tag):
			continue
		result.append(record)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if newest and a["newest"] != b["newest"]:
			return a["newest"] > b["newest"]
		if str(a["name"]).to_lower() == str(b["name"]).to_lower():
			return a["path"] < b["path"]
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return result

static func valid_datetime(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$")
	if pattern.search(value) == null:
		return false
	var year: int = int(value.substr(0, 4))
	var month: int = int(value.substr(5, 2))
	var day: int = int(value.substr(8, 2))
	if year < 1 or month < 1 or month > 12:
		return false
	var days: Array[int] = [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day >= 1 and day <= days[month - 1] and int(value.substr(11, 2)) < 24 and int(value.substr(14, 2)) < 60 and int(value.substr(17, 2)) < 60

