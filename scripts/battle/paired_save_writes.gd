extends RefCounted
## Only this transaction's newly created files are removed on cancellation.
var pending_path: String=""
var committed_path: String=""
var pending: RefCounted
func stage(storage: RefCounted,data: Dictionary,name: String) -> bool:
	pending=preload("res://scripts/named_json_storage.gd").new(storage.directory.path_join(".pending"),storage.kind)
	var result: Dictionary=pending.save_record(data,name)
	if result.has("error"): return false
	pending_path=result.path;return true
func commit(storage: RefCounted) -> bool:
	if pending_path.is_empty(): return false
	var read: Dictionary=pending.read_record(pending_path)
	if read.has("error"): return false
	var result: Dictionary=storage.save_record(read.record.data,read.record.name)
	if result.has("error"): return false
	committed_path=result.path;pending.delete_record(pending_path);pending_path="";return true
func abort(storage: RefCounted) -> void:
	if not pending_path.is_empty(): pending.delete_record(pending_path)
	if not committed_path.is_empty(): storage.delete_record(committed_path)
	pending_path="";committed_path=""
func finish() -> String:
	var result: String=committed_path;committed_path="";pending_path="";return result
