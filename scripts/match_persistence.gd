extends RefCounted
const Snapshot = preload("res://scripts/match_snapshot.gd")
const MatchSaves = preload("res://scripts/match_save_storage.gd")
const Layouts = preload("res://scripts/layout_preset_storage.gd")
var manager: Node
var matches = MatchSaves.new()
var layouts = Layouts.new()
func _init(table: Node) -> void:
	manager = table
func capture_match() -> Dictionary:
	return Snapshot.capture(manager)
func restore_match(data: Dictionary) -> Dictionary:
	if manager.match_controller.playtest.network_busy(): return {"error":"Leave the online match before loading a saved local table."}
	if manager.undo != null and not manager.undo.restoring: manager.undo.invalidate("Loaded a different table.")
	return Snapshot.restore(manager, data)
func save_match(caption: String, path: String = "") -> Dictionary:
	var data: Dictionary = capture_match()
	var error: String = Snapshot.validate(data)
	return {"error": error} if not error.is_empty() else matches.save_record(data, caption, path)
func load_match(path: String) -> Dictionary:
	var read: Dictionary = matches.read_record(path)
	return read if read.has("error") else restore_match(read.record.data)
func capture_layout() -> Dictionary:
	return manager.layout.capture()
func load_layout(data: Dictionary) -> Dictionary:
	return manager.layout.apply(data)
