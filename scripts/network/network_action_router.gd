extends Node
## Host orders requests only. Public-object editing is shared by both players.
signal changed
const Action = preload("res://scripts/network/network_action.gd")
var library_memory: Node
var recovery: Node
var transactions: Node
var journal = preload("res://scripts/network/public_action_journal.gd").new()
var public_state_revision: int:
	get: return committed
var hidden: Node
var card_sync: Node
var network: Node
var table: Node
var serializer: RefCounted
var resync: RefCounted
var opted_in: bool = false
var remote_ready: bool = false
var enabled: bool = false
var applying: bool = false
var local_id: String = "player_1"
var remote_id: String = "player_2"
var baseline: Dictionary = {}
var private_returns: Dictionary = {}
var state: Dictionary = {"cards": {}, "counters": {}, "players": {"player_1": {"life":40,"hand":0,"library":0}, "player_2": {"life":40,"hand":0,"library":0}}, "order": [], "turn": {"number":1,"active":"player_1"}, "history": [], "zones":{}, "hands":{"player_1":[],"player_2":[]}}
var seen: Dictionary = {}
var request_sequence: int = 0
var remote_sequence: int = 0
var committed: int = 0
var timer: float = 0
var log: Array[String] = []
var status: String = "Public tabletop is off. Both players choose Share Tabletop to begin."
var session_id: String = ""
func _ready() -> void:
	serializer = preload("res://scripts/network/public_state_serializer.gd").new(self)
	resync = preload("res://scripts/network/public_resync_service.gd").new(self)
	network.game_received.connect(receive)
	card_sync = preload("res://scripts/network/card_sync_service.gd").new()
	card_sync.router = self
	add_child(card_sync)
	hidden = preload("res://scripts/network/hidden_zone_service.gd").new()
	hidden.router = self
	add_child(hidden)
	recovery = preload("res://scripts/network/reconnect_service.gd").new()
	recovery.router = self
	add_child(recovery)
	transactions = preload("res://scripts/network/transfer_transactions.gd").new()
	transactions.router = self
	add_child(transactions)
	library_memory = preload("res://scripts/network/library_knowledge_sync.gd").new()
	library_memory.router = self
	add_child(library_memory)
func is_host() -> bool:
	return network.session.local_peer.role == "host"
func log_safe(message: String) -> void:
	log.append(message)
	if log.size() > 200: log.pop_front()
	status = message
	changed.emit()
func start() -> void:
	if table != null and table.match_controller.playtest.local_playtest():
		log_safe("Choose Online Opponent before sharing a match.")
		return
	if recovery.suspended:
		recovery.say("Use Reconnect to resume this match, or Leave Match before preparing another.")
		return
	card_sync.begin()
func start_public() -> void:
	if network.session.state != "connected":
		log_safe("Connect first, then both players choose Share Tabletop.")
		return
	if enabled: return
	local_id = network.session.local_peer.player_id
	remote_id = network.session.remote_peer.player_id
	if session_id != network.session.session_id:
		committed = 0
		request_sequence = 0
		remote_sequence = 0
		seen.clear()
	session_id = network.session.session_id
	opted_in = true
	send_frame("offer", {})
	if remote_ready: send_frame("ready", {})
	log_safe("Waiting for the other player to share their public tabletop.")
func send_frame(mode: String, data: Dictionary) -> void:
	if recovery.suspended: return
	if network.session.state != "connected": return
	var frame: Dictionary = {"type":"game", "protocol": network.protocol_version, "session_id": network.session.session_id, "mode":mode,"sequence":committed,"data":data.duplicate(true)}
	if not network.send_message(frame): log_safe("Public message could not be queued. Request public resync.")
func _process(delta: float) -> void:
	if network.session.state != "connected":
		if enabled or opted_in:
			enabled = false
			opted_in = false
			remote_ready = false
			log_safe("Disconnected. The local match remains open; synchronization stopped.")
		return
	if table == null or not enabled or recovery.suspended: return
	timer += delta
	if timer >= 0.12:
		timer = 0
		scan()
func begin_host() -> void:
	if enabled: return
	enabled = true
	applying = true
	serializer.projection.prepare()
	state = serializer.capture()
	state.players[remote_id] = {"life": 40, "hand": 0, "library": 0}
	state.history = []
	state.turn = {"number": 1, "active": "player_1"}
	committed = 0
	request_sequence = 0
	remote_sequence = 0
	seen.clear()
	table.match_controller.public_sync = self
	table.view.zoom = 0.5
	table.view.pan = Vector2.ZERO
	table.view.apply_view()
	serializer.apply_all()
	baseline = serializer.capture()
	applying = false
	send_frame("resync", state)
	log_safe("Public tabletop shared. Hands and library order remain private.")
func receive(frame: Dictionary) -> void:
	if recovery.suspended: return
	if frame.session_id != network.session.session_id: return
	if table == null: return
	match frame.mode:
		"offer":
			remote_ready = true
			if opted_in: send_frame("ready", {})
			else: log_safe("Your friend wants to share the tabletop. Choose Share Tabletop to join.")
		"ready":
			remote_ready = true
			if opted_in and is_host(): begin_host()
		"resync":
			if not opted_in or is_host(): return
			if frame.sequence < committed:
				log_safe("Stale public resync ignored.")
				return
			var initial: bool = not enabled
			if initial: serializer.projection.prepare()
			var own: Dictionary = serializer.capture() if initial else {}
			enabled = true
			table.match_controller.public_sync = self
			resync.apply(frame.data, int(frame.sequence))
			if initial:
				request_sequence = 0
				table.view.zoom = 0.5
				table.view.pan = Vector2.ZERO
				table.view.apply_view()
				var ops: Array = []
				for row: Dictionary in own.cards.values():
					if not state.cards.has(row.id): ops.append({"kind":"card_create","data":row})
				for row: Dictionary in own.counters.values(): ops.append({"kind":"counter_set","data":row})
				ops.append({"kind":"counts", "data":{"player":local_id,"hand":own.players[local_id].hand,"library":own.players[local_id].library}})
				ops.append({"kind":"life", "data":{"player":local_id,"delta":own.players[local_id].life - state.players[local_id].life}})
				ops.append({"kind":"hand_public","data":{"player":local_id,"cards":own.hands[local_id]}})
				submit(ops)
		"request":
			if not enabled or not is_host() or frame.data.actor_player_id != remote_id: return
			scan()
			var action: Dictionary = frame.data
			if seen.has(action.action_id) or int(action.sequence) <= remote_sequence:
				recovery.send("action_ack",{"id":action.action_id,"revision":committed})
				log_safe("Duplicate action ignored.")
				return
			if int(action.sequence) != remote_sequence + 1:
				log_safe("Stale/out-of-order request rejected; public resync sent.")
				send_frame("resync", state)
				return
			remote_sequence += 1
			commit(action)
		"commit":
			if not enabled or is_host(): return
			if seen.has(frame.data.action_id):
				recovery.send("action_ack",{"id":frame.data.action_id,"revision":committed})
				log_safe("Duplicate action ignored.")
				return
			if int(frame.sequence) != committed + 1:
				log_safe("Stale/out-of-order commit; requesting public resync.")
				resync.request()
				return
			scan()
			committed = int(frame.sequence)
			seen[frame.data.action_id] = true
			while seen.size() > 512: seen.erase(seen.keys()[0])
			apply_action(frame.data)
			journal.remember(frame.data)
			journal.ack(frame.data.action_id,committed)
			recovery.send("action_ack",{"id":frame.data.action_id,"revision":committed})
			log_safe("Public action received · %d" % committed)
		"resync_request":
			if enabled and is_host():
				scan()
				send_frame("resync", state)
func submit(ops: Array) -> bool:
	if network.quiesced or not enabled or applying: return false
	if ops.is_empty(): return true
	# A rejected/unqueued action must never consume a sequence number.
	var next_sequence: int = request_sequence + 1
	var action: Dictionary = {"action_id": Crypto.new().generate_random_bytes(16).hex_encode(), "sequence":next_sequence,"actor_player_id":local_id,"action_type":"batch","payload":ops}
	if not Action.action(action):
		log_safe("Invalid local public action refused. Correct the last edit before retrying.")
		table.controls.status.text = status
		return false
	if is_host():
		request_sequence = next_sequence
		commit(action)
	else:
		if journal.pending.size() >= 256:
			log_safe("Waiting for pending actions to recover before accepting more.")
			return false
		var frame: Dictionary = {"type":"game", "protocol":network.protocol_version, "session_id":network.session.session_id, "mode":"request", "sequence":committed, "data":action}
		if not network.send_message(frame):
			log_safe("Public action could not be queued. It will be retried.")
			table.controls.status.text = status
			return false
		request_sequence = next_sequence
		journal.pending[action.action_id] = action.duplicate(true)
	log_safe("Public action sent | %d" % request_sequence)
	return true
func commit(action: Dictionary) -> void:
	if seen.has(action.action_id): return
	seen[action.action_id] = true
	committed += 1
	var result: Dictionary = action.duplicate(true)
	result.sequence = committed
	apply_action(result)
	journal.remember(result)
	while seen.size() > 512: seen.erase(seen.keys()[0])
	send_frame("commit", result)
func remove_counter(id: String) -> void:
	var item: Control = table.extras.counter_by_id(id)
	if item != null:
		table.extras.counters.erase(item)
		item.get_parent().remove_child(item)
		item.queue_free()
func history(kind: String, actor: String, text: String, id: String = "") -> void:
	state.history.append({"id": id if not id.is_empty() else "event_" + str(committed) + "_" + str(state.history.size()), "kind":kind,"actor":actor,"text":text})
	if state.history.size() > 200: state.history.pop_front()
func apply_action(action: Dictionary) -> void:
	applying = true
	var touched: Array = []
	var counters: Array = []
	var reorder: bool = false
	var actor: String = action.actor_player_id
	for op: Dictionary in action.payload:
		var data: Dictionary = op.data
		match op.kind:
			"card_create":
				if state.cards.has(data.id) or (not data.token and data.owner != actor and data.holder != actor): continue
				state.cards[data.id] = data.duplicate(true)
				state.order.append(data.id)
				touched.append(data.id)
				history("public_card", actor, player_name(actor) + (" created a token." if data.token else " played/revealed a public card."))
				log_safe("Public card promoted from private (or token created).")
			"card_update":
				if not state.cards.has(data.id): continue
				var prior: Dictionary = state.cards[data.id]
				for key: String in data:
					if key in ["id", "owner", "token"]: continue
					prior[key] = data[key]
				touched.append(data.id)
				if data.has("zone"): history("zone", actor, player_name(actor) + " moved a card to " + data.zone + ".")
			"card_remove":
				if not state.cards.has(data.id): continue
				var old: Dictionary = state.cards[data.id]
				var item: Control = table.match_controller.card_by_id(data.id)
				if item != null:
					if old.owner == local_id and data.destination in ["hand", "library"] and not old.token:
						if item.state.current_zone != data.destination:
							table.match_controller.move_card(item, data.destination, data.top, "local")
					elif item.state.current_zone != "custom_pile": table.match_controller.remove_card(item)
				state.cards.erase(data.id)
				state.order.erase(data.id)
				history("remove", actor, player_name(actor) + (" destroyed a token." if old.token else " removed a public card to " + data.destination + "."))
				log_safe("Public card removed; hidden identity is no longer replicated.")
			"zone_set": state.zones[data.id] = data.duplicate(true)
			"hand_public":
				if data.player == actor: state.hands[actor] = data.cards.duplicate(true)
			"counter_set":
				state.counters[data.id] = data.duplicate(true)
				counters.append(data.id)
			"counter_remove":
				state.counters.erase(data.id)
				remove_counter(data.id)
			"counts":
				if data.player != actor: continue
				state.players[data.player].hand = int(data.hand)
				state.players[data.player].library = int(data.library)
			"life":
				state.players[data.player].life = clampi(int(state.players[data.player].life + data.delta), -1000000, 1000000)
				history("life", actor, "%s life: %d" % [player_name(data.player), state.players[data.player].life])
			"end_turn":
				state.turn.number += 1
				state.turn.active = "player_2" if state.turn.active == "player_1" else "player_1"
				history("turn", actor, "Turn %d — %s" % [state.turn.number, player_name(state.turn.active)])
			"order":
				state.order.clear()
				for id: String in data.ids:
					if state.cards.has(id) and not state.order.has(id): state.order.append(id)
				for id: String in state.cards:
					if not state.order.has(id): state.order.append(id)
				reorder = true
			"history": history(data.kind, actor, data.text, data.id)
	serializer.apply_all(touched, counters, reorder)
	baseline = serializer.capture()
	applying = false
	publish_counts.call_deferred()
func publish_counts() -> void:
	if network.quiesced: return
	if not enabled or applying: return
	# The owner supplies identity when either peer turns an unknown face-down card up.
	for id: String in state.cards:
		var row: Dictionary = state.cards[id]
		if row.owner == local_id and not row.face_down and row.definition.is_empty() and (not row.token or row.name == "Face-down card"):
			var item: Control = table.match_controller.card_by_id(id)
			if item != null and (not item.state.card_definition_id.is_empty() or item.state.is_token):
				var actual: Dictionary = serializer.public_card(item)
				var patch: Dictionary = {"id":id,"definition":actual.definition,"name":actual.name,"art":actual.art,"power":actual.power,"toughness":actual.toughness}
				if actual.has("face_index"): patch["face_index"] = actual.face_index
				submit([{ "kind":"card_update", "data":patch}])
	var captured: Dictionary = serializer.capture()
	var own: Dictionary = captured.players[local_id]
	var ops: Array = []
	if own.hand != state.players[local_id].hand or own.library != state.players[local_id].library:
		ops.append({"kind":"counts", "data":{"player":local_id,"hand":own.hand,"library":own.library}})
	if JSON.parse_string(JSON.stringify(captured.hands[local_id])) != JSON.parse_string(JSON.stringify(state.hands[local_id])):
		ops.append({"kind":"hand_public","data":{"player":local_id,"cards":captured.hands[local_id]}})
	submit(ops)
func scan() -> void:
	if network.quiesced: return
	if not enabled or applying or baseline.is_empty(): return
	for card: Control in table.cards:
		if card.dragging: return
	for item: Control in table.extras.counters:
		if item.dragging: return
	if table.selection.moving: return
	for zone: Control in table.zones:
		if zone.dragging: return
	if table.match_controller.pile_view.layout_dragging or table.match_controller.opponent_pile.layout_dragging: return
	var current: Dictionary = serializer.capture()
	var ops: Array = []
	for id: String in current.zones:
		if not baseline.zones.has(id) or current.zones[id] != baseline.zones[id]: ops.append({"kind":"zone_set","data":current.zones[id]})
	if current.hands[local_id] != baseline.hands[local_id]:
		ops.append({"kind":"hand_public","data":{"player":local_id,"cards":current.hands[local_id]}})
	for id: String in current.cards:
		var row: Dictionary = current.cards[id]
		if not baseline.cards.has(id):
			ops.append({"kind":"card_create","data":row})
		elif row != baseline.cards[id]:
			var patch: Dictionary = {"id":id}
			for key: String in row:
				if row[key] != baseline.cards[id].get(key): patch[key] = row[key]
			ops.append({"kind":"card_update","data":patch})
	for id: String in baseline.cards:
		if current.cards.has(id): continue
		var card: Control = table.match_controller.card_by_id(id)
		var destination: String = card.state.current_zone if card != null and card.state.current_zone in ["hand", "library"] else "removed"
		var top: bool = true
		if card != null and destination == "library":
			top = bool(private_returns[id]) if private_returns.has(id) else table.match_controller.model.players[card.state.zone_player_id].library.order.find(id) == 0
		private_returns.erase(id)
		ops.append({"kind":"card_remove","data":{"id":id,"destination":destination,"owner":baseline.cards[id].owner,"top":top}})
	for id: String in current.counters:
		if not baseline.counters.has(id) or current.counters[id] != baseline.counters[id]: ops.append({"kind":"counter_set","data":current.counters[id]})
	for id: String in baseline.counters:
		if not current.counters.has(id): ops.append({"kind":"counter_remove","data":{"id":id}})
	if current.order != baseline.order: ops.append({"kind":"order","data":{"ids":current.order}})
	for id: String in Action.PLAYERS:
		if current.players[id].life != baseline.players[id].life:
			ops.append({"kind":"life","data":{"player":id,"delta":current.players[id].life - baseline.players[id].life}})
	var own: Dictionary = current.players[local_id]
	if own.hand != baseline.players[local_id].hand or own.library != baseline.players[local_id].library:
		ops.append({"kind":"counts","data":{"player":local_id,"hand":own.hand,"library":own.library}})
	var previous: Dictionary = baseline
	baseline = current
	if not submit(ops): baseline = previous
func capture_event(kind: String, payload: Dictionary) -> void:
	if network.quiesced: return
	if not enabled or applying: return
	var message: String = ""
	var actor: String = player_name(local_id)
	match kind:
		"loyalty": message = actor + " changed a Loyalty counter."
		"mill_bottom": message = actor + " milled %d cards from bottom." % int(payload.get("count",0))
		"face": message = actor + " changed a card face."
		"dice": message = "%s rolled %dD%d → %s (total %d)" % [actor, payload.get("count",0),payload.get("sides",0),str(payload.get("values",[])),payload.get("total",0)]
		"coin": message = actor + " flipped a coin → " + str(payload.get("side", ""))
		"shuffle", "search_shuffle": message = actor + " shuffled their library."
		"discard": message = actor + " discarded a card."
	if not message.is_empty():
		scan()
		submit([{"kind":"history","data":{"id":Crypto.new().generate_random_bytes(16).hex_encode(),"kind":kind,"actor":local_id,"text":message.left(500)}}])

func player_name(id: String) -> String:
	for peer: RefCounted in [network.session.local_peer,network.session.remote_peer]:
		if peer.player_id == id and not peer.display_name.is_empty(): return peer.display_name
	return id.replace("player_","Player ")
