extends Node
## Uses the existing strictly validated authorized-identity snapshot envelope.
## Only allowed rows are sent; zone_ref is a bounded known slot, never a hidden order.
var router: Node
var signature: String = ""
var clock: float = 0
var connected_before: bool = false
const Knowledge = preload("res://scripts/library_knowledge.gd")
const PREFIX = "library_memory_"
func _ready() -> void: router.network.hidden_received.connect(receive)
func payload() -> Array:
	var c: Node = router.table.match_controller
	var rows: Array = []
	for index: int in c.pile.order.size():
		var card: Control = c.card_by_id(c.pile.order[index])
		if card == null or not Knowledge.known(card.state,"opponent"): continue
		var row: Dictionary = router.serializer.public_card(card)
		row.definition = card.state.card_definition_id
		row.name = card.state.display_name
		row.art = router.serializer.art_hash(card.state.image_path)
		row.face_down = false
		row.counters = {}
		row.position = [0,0]
		row.power = ""
		row.toughness = ""
		row.zone_ref = "known_slot_"+str(index)
		rows.append(row)
		if rows.size() == 500: break
	return rows
func publish() -> void:
	if router.table == null or not router.enabled or router.recovery.suspended or router.network.session.state != "connected": return
	var rows: Array = payload()
	var key: String = router.network.session.session_id+JSON.stringify(rows)
	if key == signature: return
	if router.network.send_message({"type":"hidden_zone","protocol":router.network.protocol_version,"session_id":router.network.session.session_id,"request_id":PREFIX+router.local_id,"kind":"snapshot","data":{"zone":"library","cards":rows}}): signature = key
func receive(frame: Dictionary) -> void:
	if router.table == null or not router.enabled or router.recovery.suspended or frame.session_id != router.network.session.session_id or frame.request_id != PREFIX+router.remote_id or frame.kind != "snapshot" or frame.data.zone != "library": return
	var allowed: Dictionary = {}
	for row: Dictionary in frame.data.cards:
		if row.holder != router.remote_id or not str(row.zone_ref).begins_with("known_slot_"): return
		var slot: String = str(row.zone_ref).trim_prefix("known_slot_")
		if not slot.is_valid_int() or int(slot)<0 or int(slot)>4999 or allowed.has(slot): return
		allowed[slot] = row.duplicate(true)
	var c: Node = router.table.match_controller
	c.remote_library_knowledge = allowed
	c.refresh()
func _process(delta: float) -> void:
	if router.table == null: return
	var connected: bool = router.enabled and router.network.session.state == "connected" and not router.recovery.suspended
	if not connected:
		signature = ""
		if connected_before:
			router.table.match_controller.remote_library_knowledge.clear()
			router.table.match_controller.refresh()
		connected_before = false
		return
	connected_before = true
	clock += delta
	if clock >= 0.2:
		clock = 0
		publish()
