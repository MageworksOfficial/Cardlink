extends RefCounted
## Storage writers (including archive workers) dispatch on the main thread.
## No card data travels on this bus; subscribers reload their own directory.
class Feed extends RefCounted:
	signal collection_changed(directory: String)
	var pending: Dictionary = {}
	func announce(directory: String) -> void:
		if pending.has(directory): return
		pending[directory] = true
		flush.call_deferred()
	func flush() -> void:
		var directories: Array = pending.keys()
		pending.clear()
		for directory: String in directories: collection_changed.emit(directory)
static var shared: Feed = Feed.new()
static func key(directory: String) -> String:
	return ProjectSettings.globalize_path(directory).simplify_path()
static func publish(directory: String) -> void:
	shared.call_deferred("announce",key(directory))
