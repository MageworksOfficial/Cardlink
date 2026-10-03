extends Node
## Private pile authority follows the component holder, not card ownership.
## Remote draws use the existing acknowledged private-transfer journal.
var builder: Node
var network: Node
var grants: Dictionary = {}
var remote_counts: Dictionary = {}
var applying: bool = false
var public_members: Dictionary = {}
func publish_members(id: String) -> void:
	var row: Dictionary = builder.row(id)
	if connected() and not row.is_empty() and row.visibility == "public" and not row.kind in ["deck","shared_deck","hand"]:
		public_members[id] = builder.orders.get(id,[]).duplicate()
		send("members",{"id":id,"cards":public_members[id]})
func apply_members() -> void:
	for card: Control in builder.manager.cards:
		var old: String = card.state.custom_metadata.get("table_component","")
		if public_members.has(old) and not card.state.match_instance_id in public_members[old]:
			card.state.custom_metadata.erase("table_component")
			if builder.orders.has(old): builder.orders[old].erase(card.state.match_instance_id)
	for id: String in public_members:
		if builder.row(id).is_empty(): continue
		for card_id: String in public_members[id]:
			var card: Control = builder.manager.match_controller.card_by_id(card_id)
			if card != null and card.state.current_zone == "battlefield":
				card.state.custom_metadata["table_component"] = id
				if not builder.orders.has(id): builder.orders[id] = []
				if not builder.orders[id].has(card_id): builder.orders[id].append(card_id)
func connected() -> bool:
	return network != null and is_instance_valid(network) and network.session.state == "connected"
func local_id() -> String: return network.session.local_peer.player_id if connected() else "player_1"
func custodian(row: Dictionary) -> String: return "player_1" if row.owner == "table" else row.owner
func owns(row: Dictionary) -> bool: return not connected() or custodian(row) == local_id()
func send(kind: String, data: Dictionary) -> bool:
	return connected() and network.send_message({"type":"table_structure","protocol":1,"session_id":network.session.session_id,"kind":kind,"data":data})
func counts() -> void:
	if not connected(): return
	for row: Dictionary in builder.document.components:
		if row.kind in ["deck","shared_deck"] and owns(row): send("count",{"id":row.id,"count":builder.orders.get(row.id,[]).size()})
func draw(id: String, player: String) -> bool:
	var row: Dictionary = builder.row(id)
	if row.is_empty() or not row.kind in ["deck","shared_deck"]: return false
	if not owns(row): return send("draw",{"id":id,"player":player})
	var order: Array = builder.orders.get(id,[])
	if order.is_empty(): return false
	var c: Node = builder.manager.match_controller
	var card: Control = c.card_by_id(order[0])
	if card == null or not c.online(): return false
	if player == local_id():
		builder.detach(card)
		var result: bool = c.move_card(card,"hand",true,"local",true)
		counts()
		return result
	if not c.public_sync.transactions.usable() or c.public_sync.transactions.is_locked(card.state.match_instance_id): return false
	var request: String = "table_"+Crypto.new().generate_random_bytes(16).hex_encode()
	if not send("draw_offer",{"id":id,"request":request}): return false
	# Offer and prepare are ordered on the same reliable connection.
	c.public_sync.transactions.begin_transfer(card,request)
	return true
func permits(request: String) -> bool:
	if not grants.has(request): return false
	if Time.get_ticks_msec() > grants[request]: grants.erase(request); return false
	return true
func receive(message: Dictionary) -> void:
	if not connected() or message.session_id != network.session.session_id: return
	var data: Dictionary = message.data
	var row: Dictionary = builder.row(str(data.get("id","")))
	if row.is_empty(): return
	match message.kind:
		"members":
			if row.visibility != "public" or row.kind in ["deck","shared_deck","hand"]: return
			public_members[row.id] = data.cards
			apply_members()
			builder.refresh_presentation()
		"count":
			if owns(row) or not row.kind in ["deck","shared_deck"]: return
			remote_counts[row.id] = int(data.count)
			builder.refresh_presentation()
		"draw":
			if owns(row): draw(row.id,data.player)
		"draw_offer":
			if owns(row) or not row.kind in ["deck","shared_deck"] or grants.size() >= 256: return
			grants[data.request] = Time.get_ticks_msec()+60000
		"shuffle":
			if owns(row): builder.shuffle(row.id)
		"place":
			if not owns(row): return
			var c: Node = builder.manager.match_controller
			var card: Control = c.card_by_id(data.card)
			if card != null and c.online() and c.public_sync.state.cards.has(data.card):
				applying = true
				builder.put_card(card,row.id)
				applying = false
