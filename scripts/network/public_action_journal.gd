extends RefCounted
## Session-local bounded delivery state. Hidden identities are never stored here.
const LIMIT = 256
var pending: Dictionary = {}
var recent: Dictionary = {}
var acknowledged_revision: int = 0
func remember(action: Dictionary) -> void:
	recent[action.action_id] = action.duplicate(true)
	while recent.size() > LIMIT: recent.erase(recent.keys()[0])
func ack(id: String, revision: int) -> void:
	pending.erase(id)
	acknowledged_revision = maxi(acknowledged_revision,revision)
