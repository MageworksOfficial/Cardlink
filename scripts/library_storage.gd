extends RefCounted
## Record identity is its exact file path, never a possibly duplicated card ID.
const Storage = preload("res://scripts/card_storage.gd")
var directory: String
func _init(path: String = "user://cards") -> void:
	directory = path
func definition_path_allowed(path: String) -> bool:
	return path.get_base_dir().simplify_path() == directory.path_join("definitions").simplify_path() and path.get_extension().to_lower() == "json" and not path.contains("..")
func read_definition(path: String) -> Dictionary:
	if not definition_path_allowed(path):
		return {"error": "Definition path is outside this library."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Definition is missing or unreadable."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "Malformed JSON definition."}
	return {"metadata": parser.data}
func update_metadata(path: String, card_name: String, tags: Array[String]) -> Dictionary:
	if card_name.strip_edges().is_empty():
		return {"error": "Enter a card name before saving."}
	var result: Dictionary = read_definition(path)
	if result.has("error"):
		return result
	var metadata: Dictionary = result["metadata"]
	metadata["name"] = card_name.strip_edges()
	metadata["tags"] = tags
	var error: Error = Storage.write_atomic(path, JSON.stringify(metadata, "\t").to_utf8_buffer())
	return {"error": "Cannot save metadata: " + error_string(error)} if error != OK else {"metadata": metadata}
func delete_definition(path: String) -> Dictionary:
	if not definition_path_allowed(path):
		return {"error": "Definition path is outside this library."}
	var error: Error = DirAccess.remove_absolute(path)
	if error == OK: preload("res://scripts/collection_events.gd").publish(directory)
	return {"error": "Cannot delete definition: " + error_string(error)} if error != OK else {"deleted": true}
func cleanup_candidates() -> Dictionary:
	# Unknown references block cleanup; rescan again at confirmation time.
	var definitions: String = directory.path_join("definitions")
	if not DirAccess.dir_exists_absolute(definitions):
		return {"error": "Definitions folder is missing; cannot prove assets are unused."}
	var folder := DirAccess.open(definitions)
	if folder == null:
		return {"error": "Cannot read definitions; cleanup is blocked."}
	var references: Dictionary = {}
	for filename: String in folder.get_files():
		if filename.get_extension().to_lower() != "json":
			continue
		var result: Dictionary = read_definition(definitions.path_join(filename))
		if result.has("error"):
			return {"error": "Cleanup blocked by unreadable or malformed definition: " + filename}
		var metadata: Dictionary = result["metadata"]
		if not metadata.get("image_path") is String or str(metadata.get("image_path", "")).is_empty():
			return {"error": "Cleanup blocked by an unknown image reference: " + filename}
		if metadata.has("faces"):
			if not preload("res://scripts/card_faces.gd").validate(metadata.faces).is_empty(): return {"error":"Cleanup blocked by invalid face references."}
			for face: Dictionary in metadata.faces:
				references[ProjectSettings.globalize_path(face.image_path).simplify_path().to_lower()] = true
				references[ProjectSettings.globalize_path(directory.path_join(face.image_hash+".png")).simplify_path().to_lower()] = true
		references[ProjectSettings.globalize_path(str(metadata["image_path"])).simplify_path().to_lower()] = true
		if metadata.get("image_hash") is String:
			references[ProjectSettings.globalize_path(directory.path_join(str(metadata["image_hash"]) + ".png")).simplify_path().to_lower()] = true
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{64}\\.png$")
	var candidates: Array[String] = []
	for filename: String in DirAccess.get_files_at(directory):
		var path: String = directory.path_join(filename)
		if pattern.search(filename) != null and not references.has(ProjectSettings.globalize_path(path).simplify_path().to_lower()):
			candidates.append(path)
	return {"paths": candidates}
func cleanup_unused() -> Dictionary:
	var scan: Dictionary = cleanup_candidates()
	if scan.has("error"):
		return scan
	var removed: int = 0
	for path: String in scan["paths"]:
		var error: Error = DirAccess.remove_absolute(path)
		if error != OK:
			return {"error": "Removed %d assets; cannot remove %s: %s" % [removed, path.get_file(), error_string(error)]}
		removed += 1
	return {"removed": removed}
