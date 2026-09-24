extends Node
## Permission and private transfer channel; never writes temporary identities to public state.
const Session = preload("res://scripts/network/hidden_zone_session.gd")
var router: Node
var incoming: RefCounted
var outgoing: RefCounted
var ui: Node
var auto_approve: bool = false
var settings_path: String = "user://hidden_zone_settings.cfg"
var transfers: Dictionary = {}
var received_transfers: Dictionary = {}
var hand_reveals: Dictionary = {}
var attached: bool = false
var snapshot_signature: String = ""
var inspection_poll: float = 0
func controller() -> Node: return router.table.match_controller
func now() -> float: return Time.get_ticks_msec() / 1000.0
func _ready() -> void:
	router.network.hidden_received.connect(receive)
	var settings := ConfigFile.new()
	if settings.load(settings_path) == OK: auto_approve = bool(settings.get_value("privacy","auto_approve",false))
	ui = preload("res://scripts/network/hidden_zone_ui.gd").new()
	ui.service = self
	add_child(ui)
func set_auto_approve(value: bool) -> void:
	auto_approve = value
	var settings := ConfigFile.new()
	settings.set_value("privacy","auto_approve",value)
	settings.save(settings_path)
func send(kind: String, id: String, data: Dictionary) -> bool:
	if not router.enabled or router.network.session.state != "connected": return false
	return router.network.send_message({"type":"hidden_zone","protocol":router.network.protocol_version,"session_id":router.network.session.session_id,"request_id":id,"kind":kind,"data":data})
func event(text: String) -> void:
	router.submit([{"kind":"history","data":{"id":Crypto.new().generate_random_bytes(16).hex_encode(),"kind":"inspection","actor":router.local_id,"text":text}}])
func player(id: String) -> String: return router.player_name(id)
func request(zone: String) -> void:
	if not router.enabled or not zone in ["hand","library"]: return
	close_outgoing()
	outgoing = Session.new()
	outgoing.id = Crypto.new().generate_random_bytes(16).hex_encode()
	outgoing.requester = router.local_id
	outgoing.target = router.remote_id
	outgoing.zone = zone
	outgoing.expires = now()+30
	if not send("request",outgoing.id,{"zone":zone}):
		close_outgoing(false)
		ui.tell("Inspection request could not be sent.")
	else: ui.tell("Waiting for " + player(router.remote_id) + " to allow inspection. This request expires in 30 seconds. Close inspection or use Cancel Request to cancel.")
func respond(allow: bool) -> void:
	if incoming == null or incoming.state != "requested": return
	ui.prompt.hide()
	if not allow:
		send("deny",incoming.id,{"reason":"The other player denied the " + incoming.zone + " inspection."})
		event(player(router.local_id) + " denied a " + incoming.zone + " inspection request.")
		close_incoming(false)
		return
	incoming.state = "approved"
	snapshot_signature = ""
	incoming.expires = now()+300
	controller().model.synchronize(router.table.cards)
	incoming.allowed.assign(controller().model.players.local.hand if incoming.zone == "hand" else controller().pile.order)
	if incoming.allowed.size() > 500:
		send("deny",incoming.id,{"reason":"This inspection exceeds the current 500-card safety limit."})
		close_incoming(false)
		return
	event(player(router.remote_id) + (" searched " if incoming.zone == "library" else " inspected ") + player(router.local_id) + "'s " + incoming.zone + ".")
	if not snapshot():
		send("deny",incoming.id,{"reason":"Inspection could not fit the safe message limit or the channel was unavailable."})
		close_incoming(false)
func snapshot() -> bool:
	if incoming == null or incoming.state != "approved": return false
	var c: Node = controller()
	c.model.synchronize(router.table.cards)
	var order: Array = c.model.players.local.hand if incoming.zone == "hand" else c.pile.order
	var rows: Array = []
	for id: String in order:
		if not id in incoming.allowed: continue
		var card: Control = c.card_by_id(id)
		if card == null: continue
		if incoming.zone == "library": c.Knowledge.learn(card.state,"opponent")
		var row: Dictionary = router.serializer.public_card(card)
		# Explicit authorization allows the identity even for face-down library cards.
		row.definition = card.state.card_definition_id
		row.name = card.state.display_name
		row.art = router.serializer.art_hash(card.state.image_path)
		rows.append(row)
	var signature: String = JSON.stringify(rows)
	if signature == snapshot_signature: return true
	snapshot_signature = signature
	return send("snapshot",incoming.id,{"zone":incoming.zone,"cards":rows})
func move_selected(destination: String, n: int = 1, bottom: bool = false) -> void:
	if outgoing == null or outgoing.state != "approved": return
	var id: String = ui.selected()
	if id.is_empty(): return
	send("move",outgoing.id,{"id":id,"destination":destination,"n":n,"bottom":bottom})
func apply_move(data: Dictionary) -> void:
	if incoming == null or incoming.state != "approved" or now() > incoming.expires or not data.id in incoming.allowed or router.transactions.is_locked(data.id): return
	var c: Node = controller()
	var card: Control = c.card_by_id(data.id)
	if card == null or card.state.current_zone != incoming.zone or card.state.zone_player_id != "local":
		snapshot()
		return
	if data.destination == "take":
		router.transactions.begin_transfer(card,incoming.id)
		return
	if data.destination == "library":
		# Owner executes indexed insertion locally, never sends a future shuffled order.
		c.move_card(card,"library",not data.bottom,"local",true)
		c.pile.insert_nth(data.id,int(data.n),data.bottom)
	else: c.move_card(card,data.destination,true,"local",true)
	c.refresh()
	router.scan()
	snapshot()
func close_outgoing(notify: bool = true) -> void:
	if outgoing != null:
		if notify: send("close",outgoing.id,{"reason":"Inspection closed."})
		outgoing.clear()
		outgoing = null
	if router.table != null: ui.clear()
	ui.notice.hide()
func close_incoming(shuffle: bool = true) -> void:
	if incoming == null: return
	var searched: bool = incoming.state == "approved" and incoming.zone == "library"
	incoming.clear()
	incoming = null
	snapshot_signature = ""
	transfers.clear()
	ui.prompt.hide()
	if searched and shuffle:
		controller().shuffle_library("local",true)
func reveal_hand(show: bool) -> void:
	var c: Node = controller()
	if show:
		for id: String in c.model.players.local.hand:
			var card: Control = c.card_by_id(id)
			if not hand_reveals.has(id): hand_reveals[id] = bool(card.state.custom_metadata.get("public_reveal",false))
			c.visibility.set_public_reveal(card.state,true)
	else:
		for id: String in hand_reveals:
			var card: Control = c.card_by_id(id)
			if card != null: c.visibility.set_public_reveal(card.state,hand_reveals[id])
		hand_reveals.clear()
	c.refresh()
	if router.enabled:
		router.scan()
		event(player(router.local_id) + (" revealed their current hand." if show else " hid their hand again."))
func receive(frame: Dictionary) -> void:
	if not router.enabled or frame.session_id != router.network.session.session_id: return
	var d: Dictionary = frame.data
	if frame.kind == "request":
		if incoming != null:
			send("deny",frame.request_id,{"reason":"Another inspection is already pending or active."})
			return
		incoming = Session.new()
		incoming.id = frame.request_id
		incoming.requester = router.remote_id
		incoming.target = router.local_id
		incoming.zone = d.zone
		incoming.expires = now()+30
		if auto_approve: respond(true)
		else: ui.ask(player(router.remote_id) + " wants to inspect your " + d.zone + ".")
		return
	if incoming != null and incoming.id == frame.request_id:
		match frame.kind:
			"close": close_incoming()
			"move": apply_move(d)
	if outgoing != null and outgoing.id == frame.request_id:
		match frame.kind:
			"deny", "close":
				close_outgoing(false)
				ui.tell(d.reason)
			"snapshot":
				if d.zone != outgoing.zone: return
				outgoing.state = "approved"
				outgoing.expires = now()+300
				outgoing.rows = d.cards.duplicate(true)
				ui.notice.hide()
				ui.show_rows()
func _process(_delta: float) -> void:
	if router.table == null or controller() == null: return
	if not attached:
		attached = true
		ui.attach()
	if not router.enabled or router.network.session.state != "connected":
		if outgoing != null: close_outgoing(false)
		if incoming != null: close_incoming(false)
		received_transfers.clear()
		return
	if outgoing != null and now() > outgoing.expires:
		close_outgoing()
		ui.tell("Inspection expired. Request access again if needed.")
	if incoming != null and now() > incoming.expires:
		send("close",incoming.id,{"reason":"Inspection expired."})
		close_incoming()
	inspection_poll += _delta
	if incoming != null and incoming.state == "approved" and inspection_poll > 0.3:
		inspection_poll = 0
		# Refresh only previously authorized cards; future draws are not added.
		if not snapshot(): close_incoming()
