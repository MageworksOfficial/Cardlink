extends RefCounted
## Atomic local records for matches/layouts. IDs, not display names, form paths.
const Storage = preload("res://scripts/card_storage.gd")
var directory: String
var kind: String
func _init(folder: String, record_kind: String) -> void:
	directory = folder
	kind = record_kind
func safe_path(path: String) -> bool:
	return not path.contains("..") and path.get_base_dir().simplify_path() == directory.simplify_path() and path.get_extension() == "json"
func read_record(path: String) -> Dictionary:
	if not safe_path(path):
		return {"error": "Path is outside " + kind + " storage."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "The saved file is missing or unreadable."}
	if file.get_length() > 64 * 1024 * 1024:
		return {"error": "Saved file exceeds the 64 MB limit."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "Malformed saved JSON."}
	var data: Dictionary = parser.data
	if data.get("kind") != kind or not data.get("record_id") is String or not data.get("name") is String or not data.get("data") is Dictionary:
		return {"error": "Invalid saved record."}
	if str(data.record_id) + ".json" != path.get_file():
		return {"error": "Saved file identity does not match its filename."}
	return {"record": data, "path": path}
func list_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for filename: String in DirAccess.get_files_at(directory):
		if filename.ends_with(".json"):
			var path: String = directory.path_join(filename)
			var read: Dictionary = read_record(path)
			result.append({"path": path, "name": str(read.get("record", {}).get("name", filename)),
				"error": read.get("error", ""), "record": read.get("record", {})})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return result
func save_record(data: Dictionary, caption: String, original_path: String = "") -> Dictionary:
	if caption.strip_edges().is_empty():
		return {"error": "Enter a name."}
	var id: String = kind + "_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var path: String = directory.path_join(id + ".json")
	if not original_path.is_empty():
		var old: Dictionary = read_record(original_path)
		if old.has("error"):
			return old
		id = old.record.record_id
		path = original_path
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"error": "Cannot create save directory."}
	var record: Dictionary = {"kind": kind, "record_id": id, "name": caption.strip_edges(),
		"saved_at": Time.get_datetime_string_from_system(true), "data": data}
	var error: Error = Storage.write_atomic(path, JSON.stringify(record, "\t").to_utf8_buffer())
	return {"path": path, "record": record} if error == OK else {"error": "Save failed: " + error_string(error)}
func rename_record(path: String, caption: String) -> Dictionary:
	var old: Dictionary = read_record(path)
	return old if old.has("error") else save_record(old.record.data, caption, path)
func duplicate_record(path: String, caption: String) -> Dictionary:
	var old: Dictionary = read_record(path)
	return old if old.has("error") else save_record(old.record.data, caption)
func delete_record(path: String) -> Dictionary:
	if not safe_path(path):
		return {"error": "Invalid save path."}
	var error: Error = DirAccess.remove_absolute(path)
	return {"deleted": true} if error == OK else {"error": "Cannot delete save: " + error_string(error)}
