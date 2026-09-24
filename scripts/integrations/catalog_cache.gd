extends RefCounted
const Storage = preload("res://scripts/card_storage.gd")
var directory: String
const MAX_BYTES = 32 * 1024 * 1024
const MAX_ENTRIES = 256
const TTL = 86400
func _init(path: String = "user://integrations/scryfall/cache") -> void: directory = path
func path_for(key: String) -> String: return directory.path_join(key.sha256_text()+".cache")
func get_bytes(key: String) -> PackedByteArray:
	var path: String = path_for(key)
	if not FileAccess.file_exists(path): return PackedByteArray()
	if Time.get_unix_time_from_system()-FileAccess.get_modified_time(path)>TTL: return PackedByteArray()
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>4*1024*1024: return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)
func put_bytes(key: String, bytes: PackedByteArray) -> void:
	if bytes.size()>4*1024*1024: return
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return
	Storage.write_atomic(path_for(key),bytes)
	prune()
func prune() -> void:
	if not DirAccess.dir_exists_absolute(directory): return
	var files: Array = []
	var total: int = 0
	for name: String in DirAccess.get_files_at(directory):
		if name.get_extension()!="cache": continue
		var path: String = directory.path_join(name)
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null: continue
		var bytes: int = file.get_length()
		files.append({"path":path,"time":FileAccess.get_modified_time(path),"size":bytes})
		total += bytes
	files.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.time<b.time)
	while not files.is_empty() and (files.size()>MAX_ENTRIES or total>MAX_BYTES or Time.get_unix_time_from_system()-files[0].time>TTL):
		var row: Dictionary = files.pop_front()
		total -= int(row.size)
		DirAccess.remove_absolute(row.path)
func clear() -> void:
	if not DirAccess.dir_exists_absolute(directory): return
	for name: String in DirAccess.get_files_at(directory):
		if name.get_extension()=="cache": DirAccess.remove_absolute(directory.path_join(name))
