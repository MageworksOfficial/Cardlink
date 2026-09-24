extends Node
## Bounded local transactions. Never replay snapshots across a live connection.
signal committed
signal sound_event(kind: String)
var manager: Node
var entries: Array[Dictionary] = []
var before: Dictionary = {}
var description: String = "Table action"
var restoring: bool = false
var blocked_reason: String = ""
var barrier_generation: int = 0
var began_generation: int = 0
const LIMIT = 15
const MEMORY_LIMIT = 16 * 1024 * 1024
func available() -> bool:
	return not restoring and not manager.match_controller.playtest.network_busy()
func begin(label: String = "Table action") -> void:
	if restoring or manager.match_controller.batching: return
	if not available(): invalidate("Undo is available in disconnected local play only."); return
	if not before.is_empty(): return
	before = manager.persistence.capture_match()
	description = label
	began_generation = barrier_generation
func finish() -> void:
	if before.is_empty(): return
	var prior: Dictionary = before
	before = {}
	if not available() or began_generation != barrier_generation: return
	var after: Dictionary = manager.persistence.capture_match()
	if game_signature(prior) == game_signature(after): return
	committed.emit()
	if not reversible(prior,after): invalidate("That action cannot be undone safely."); return
	var bytes: int = JSON.stringify(prior).length()
	if bytes > MEMORY_LIMIT: invalidate("This table exceeds the local undo memory limit."); return
	entries.append({"label":description,"snapshot":prior,"bytes":bytes})
	var total: int = 0
	for row: Dictionary in entries: total += row.bytes
	while entries.size() > LIMIT or total > MEMORY_LIMIT: total -= entries.pop_front().bytes
	blocked_reason = ""
func game_signature(data: Dictionary) -> String:
	return JSON.stringify([data.cards,data.players,data.local_tabletop.get("counters",[]),data.local_tabletop.get("turn_number",1),data.local_tabletop.get("history",[])])
func reversible(a: Dictionary, b: Dictionary) -> bool:
	for i: int in a.players.size():
		if a.players[i].library_order != b.players[i].library_order or a.players[i].loaded_ids != b.players[i].loaded_ids: return false
	var old: Dictionary = {}
	for card: Dictionary in a.cards: old[card.match_instance_id] = card
	for card: Dictionary in b.cards:
		if not old.has(card.match_instance_id):
			if not card.get("is_token",false): return false
			continue
		var previous: Dictionary = old[card.match_instance_id]
		if previous.visibility != card.visibility or previous.face_down != card.face_down or previous.custom_metadata.get("library_known_to",[]) != card.custom_metadata.get("library_known_to",[]): return false
	for event: Dictionary in b.local_tabletop.get("history",[]).slice(a.local_tabletop.get("history",[]).size()):
		if event.kind in ["shuffle","search_shuffle","dice","coin","inspection","reveal","turn","end_turn"]: return false
	return true
func invalidate(reason: String = "Undo history cleared.") -> void:
	barrier_generation += 1
	entries.clear()
	before = {}
	blocked_reason = reason
func undo() -> void:
	finish()
	if not available() or entries.is_empty():
		manager.controls.status.text = blocked_reason if not blocked_reason.is_empty() else "Nothing to undo."
		return
	var row: Dictionary = entries.pop_back()
	restoring = true
	# Gameplay undo keeps the current local seat and camera.
	if manager.perspective != null:
		row.snapshot.local_tabletop["viewed_player"] = manager.perspective.viewed_player
		row.snapshot.layout.zoom = manager.view.zoom
		row.snapshot.layout.pan = [manager.view.pan.x,manager.view.pan.y]
	var result: Dictionary = manager.persistence.restore_match(row.snapshot)
	restoring = false
	manager.selection.clear()
	manager.controls.status.text = "Undo: "+row.label if not result.has("error") else "Undo could not restore this action."
	committed.emit()
func event(kind: String) -> void:
	if restoring: return
	if kind in ["shuffle","search_shuffle","dice","coin","inspection","reveal","turn","end_turn"]: invalidate("Undo stopped at "+kind.replace("_"," ")+".")
	sound_event.emit(kind) # Optional future audio adapter; no assets or sounds.
	committed.emit()
func _input(event: InputEvent) -> void:
	if not manager.active or restoring: return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.pressed: begin()
		else: finish.call_deferred()
