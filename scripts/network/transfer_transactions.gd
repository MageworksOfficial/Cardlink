extends Node
## Two-phase holder transfer. Prepared receiver data is never a playable instance.
signal changed
var router: Node
var records: Dictionary = {}
var status: String = "No transfer recovery needed."
func c() -> Node: return router.table.match_controller
func _ready() -> void: router.network.transfer_received.connect(receive)
func say(text: String) -> void:
	status = text
	if router.table != null: router.table.controls.status.text = text
	changed.emit()
func usable() -> bool:
	return router.enabled and router.recovery.authenticated and router.network.session.state == "connected"
func send(kind: String, tx: String, data: Dictionary) -> bool:
	if not usable(): return false
	return router.network.send_message({"type":"transfer_tx","protocol":router.network.protocol_version,"session_id":router.network.session.session_id,"tx":tx,"kind":kind,"data":data})
func is_locked(id: String) -> bool:
	for row: Dictionary in records.values():
		if row.id == id and row.phase in ["prepared","unresolved"]: return true
	return false
func has_unfinished() -> bool:
	for row: Dictionary in records.values():
		if row.phase in ["prepared","unresolved"] or (row.side == "sender" and row.phase == "committed"): return true
	return false
func room() -> bool:
	while records.size() >= 256:
		var removed: bool = false
		for tx: String in records:
			if records[tx].phase in ["acknowledged","rolled_back"] or (records[tx].side == "receiver" and records[tx].phase == "committed"):
				records.erase(tx)
				removed = true
				break
		if not removed:
			say("Transfer journal is full. Finish recovery before transferring another card.")
			return false
	return true
func begin_transfer(card: Control, request: String) -> void:
	if not usable() or is_locked(card.state.match_instance_id) or not room(): return
	var data: Dictionary = router.serializer.public_card(card)
	data.definition = card.state.card_definition_id
	data.name = card.state.display_name
	data.art = router.serializer.art_hash(card.state.image_path)
	if card.state.faces.size()>1: data["face_index"] = card.state.active_face_index
	var tx: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var row: Dictionary = {"tx":tx,"id":data.id,"side":"sender","phase":"prepared","card":data,"revealed":bool(card.state.custom_metadata.get("public_reveal",false)),"request":request}
	records[tx] = row
	row["started"] = Time.get_ticks_msec()/1000.0
	say("Preparing private card transfer...")
	if not send("prepare",tx,{"request":request,"card":data,"revealed":row.revealed}):
		row.phase = "rolled_back"
		row.card = {}
		say("Transfer could not be sent. Original card retained.")
func unresolved(row: Dictionary, message: String) -> void:
	row.phase = "unresolved"
	say("Transfer paused: " + message + " No additional copy was created. Reconnect recovery needs attention.")
func commit_sender(row: Dictionary) -> void:
	if row.phase == "prepared":
		var card: Control = c().card_by_id(row.id)
		if card == null or card.state.current_zone not in ["hand","library"] or card.state.zone_player_id != "local":
			unresolved(row,"The original card no longer matches its prepared location.")
			return
		# Record the decision before removing the source or sending commit.
		row.phase = "committed"
		c().remove_card(card)
		c().refresh()
		router.scan()
	if row.phase in ["committed","acknowledged"]: send("commit",row.tx,{"id":row.id})
func commit_receiver(row: Dictionary) -> void:
	if row.phase == "committed":
		send("committed",row.tx,{"id":row.id})
		return # Even if subsequently moved away, never recreate a committed instance.
	if row.phase != "prepared": return
	if c().card_by_id(row.id) != null:
		unresolved(row,"An unexpected instance already exists at the destination.")
		return
	var data: Dictionary = row.card
	var state = preload("res://scripts/card_instance_state.gd").new()
	state.match_instance_id = row.id
	state.card_definition_id = data.definition
	state.display_name = data.name
	state.image_path = router.serializer.resolve_art(data.art)
	state.active_face_index = int(data.get("face_index",0))
	preload("res://scripts/card_faces.gd").resolve(state,c().loader.storage.directory)
	state.owner_player_id = router.serializer.local_player(data.owner)
	state.controller_player_id = router.serializer.local_player(data.controller)
	state.zone_player_id = "local"
	state.current_zone = "hand"
	state.visibility = "owner_private"
	state.counters = data.counters.duplicate(true)
	state.custom_metadata["power"] = data.power
	state.custom_metadata["toughness"] = data.toughness
	if row.revealed: c().visibility.set_public_reveal(state,true)
	router.table.restore_card(state.to_data())
	row.phase = "committed"
	row.card = {} # No second identity cache after the real instance is installed.
	c().refresh()
	router.scan()
	send("committed",row.tx,{"id":row.id})
	say("Private card transfer committed.")
func exchange_summary() -> void:
	var rows: Array = []
	for record: Dictionary in records.values():
		rows.append({"tx":record.tx,"id":record.id,"side":record.side,"phase":record.phase})
	send("summary","recovery",{"transactions":rows})
func reconcile(rows: Array) -> void:
	var peer: Dictionary = {}
	for row: Dictionary in rows: peer[row.tx] = row
	for tx: String in records:
		var own: Dictionary = records[tx]
		if own.phase in ["acknowledged","rolled_back"]: continue
		if not peer.has(tx):
			if own.phase == "prepared":
				own.phase = "rolled_back"
				own.card = {}
				send("rollback",tx,{"id":own.id})
				say("Unreceived private transfer cancelled safely. Original card retained.")
			elif own.side == "sender": unresolved(own,"The peer has no record of a committed transfer.")
			continue
		var other: Dictionary = peer[tx]
		if other.id != own.id or other.side == own.side:
			unresolved(own,"Transfer identifiers disagree.")
			continue
		if own.side == "sender":
			if own.phase in ["prepared","committed"] and other.phase in ["prepared","committed"]:
				commit_sender(own)
			elif other.phase == "rolled_back" and own.phase == "prepared":
				own.phase = "rolled_back"
				own.card = {}
			else: unresolved(own,"The two transaction decisions disagree.")
func receive(f: Dictionary) -> void:
	if not usable() or f.session_id != router.network.session.session_id: return
	var d: Dictionary = f.data
	if f.kind == "summary_request":
		exchange_summary()
		return
	if f.kind == "summary":
		reconcile(d.transactions)
		return
	if f.kind == "prepare":
		if records.has(f.tx):
			var prior: Dictionary = records[f.tx]
			if prior.id == d.card.id and prior.side == "receiver":
				if prior.phase == "prepared": send("prepared",f.tx,{"id":prior.id})
				elif prior.phase == "committed": send("committed",f.tx,{"id":prior.id})
			return
		var grant: RefCounted = router.hidden.outgoing
		if grant == null or grant.state != "approved" or grant.id != d.request or router.hidden.now() > grant.expires or not grant.rows.any(func(row: Dictionary) -> bool: return row.id == d.card.id): return
		if is_locked(d.card.id) or not room(): return
		var row: Dictionary = {"tx":f.tx,"id":d.card.id,"side":"receiver","phase":"prepared","card":d.card.duplicate(true),"revealed":d.revealed,"request":d.request}
		records[f.tx] = row
		row["started"] = Time.get_ticks_msec()/1000.0
		send("prepared",f.tx,{"id":row.id})
		return
	if not records.has(f.tx): return
	var row: Dictionary = records[f.tx]
	if d.id != row.id: return
	match f.kind:
		"prepared":
			if row.side == "sender": commit_sender(row)
		"commit":
			if row.side == "receiver": commit_receiver(row)
		"committed":
			if row.side == "sender" and row.phase in ["committed","acknowledged"]:
				row.phase = "acknowledged"
				row.card = {}
				if router.hidden.incoming != null: router.hidden.snapshot()
				say("Private card transfer committed.")
		"rollback":
			if row.phase == "prepared":
				row.phase = "rolled_back"
				row.card = {}
func _process(_delta: float) -> void:
	if router.table == null or not usable(): return
	for row: Dictionary in records.values():
		if row.phase != "prepared" and not (row.side == "sender" and row.phase == "committed"): continue
		var waited: float = Time.get_ticks_msec()/1000.0-float(row.get("started",Time.get_ticks_msec()/1000.0))
		if waited > 60:
			unresolved(row,"The other client did not confirm this transaction within 60 seconds.")
		elif waited > 20 and not row.get("queried",false):
			row["queried"] = true
			send("summary_request","recovery",{})
