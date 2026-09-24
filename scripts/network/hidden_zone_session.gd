extends RefCounted
## Ephemeral permission. Never included in public resync or match saves.
var id: String = ""
var requester: String = ""
var target: String = ""
var zone: String = "hand"
var state: String = "requested"
var expires: float = 0
var allowed: Array[String] = []
var rows: Array = []
func clear() -> void:
	state = "closed"
	allowed.clear()
	rows.clear()
