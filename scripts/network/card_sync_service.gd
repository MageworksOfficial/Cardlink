extends Node
## Pre-match, receiver-requested, acknowledged transfer. Guest -> Host, then Host -> Guest.
signal changed
signal asset_available(hash_value: String)
var background_mode: bool = false
var background_remote_signature: String = ""
var live_assets: Node
var work = preload("res://scripts/network/sync_progress.gd").new()
var validation: Thread
var validation_job: Dictionary = {}
var finishing_step: bool = false
var failed_assets: Array[String] = []
var last_pump_frame: int = -1
var step_sent: bool = false
const Wire = preload("res://scripts/network/card_sync_protocol.gd")
const Catalog = preload("res://scripts/network/card_sync_catalog.gd")
var guided_consent_required: bool = false
var preparation_authorized: bool = false
var last_failure: String = ""
var router: Node
var catalog: RefCounted
var own: Array = []
var remote: Array = []
var pending: bool = false
var have_remote: bool = false
var running: bool = false
var checked: bool = false
var requested: bool = false
var remote_availability: Dictionary = {}
var events: Array[String] = []
var step: int = 0
var run_id: String = ""
var choice: String = ""
var remote_choice: String = ""
var status: String = "Card Sync: not checked."
var reports: Dictionary = {}
var need: Dictionary = {}
var pending_definitions: Array = []
var accepted_images: Dictionary = {}
var need_received: bool = false
var incoming := PackedByteArray()
var incoming_hash: String = ""
var expected_bytes: int = 0
var received_bytes: int = 0
var queue: Array = []
var sending := PackedByteArray()
var sending_hash: String = ""
var sending_offset: int = 0
var waiting_ack: bool = false
var elapsed: float = 0
var sent_definitions: int = 0
var sent_images: int = 0
func _ready() -> void:
	router.network.card_sync_received.connect(receive)
	live_assets = preload("res://scripts/network/live_card_assets.gd").new()
	live_assets.service = self
	preload("res://scripts/collection_events.gd").shared.collection_changed.connect(collection_changed)
	add_child(live_assets)
func collection_changed(directory: String) -> void:
	if catalog == null or preload("res://scripts/collection_events.gd").key(catalog.directory) != directory or not pending or running or requested: return
	catalog.reload()
	# Deferred storage notifications also arrive after our own transfers.
	# Refresh only changed discovery, preserving a completed transfer summary.
	if inspect_required() != need: check_ready()
func host() -> bool: return router.is_host()
func note(message: String) -> void:
	events.append(message)
	if events.size() > 40: events.pop_front()
	changed.emit()
func say(message: String) -> void:
	if message != status: note(message)
	status = message
	changed.emit()
func send(kind: String, data: Variant, run: String = "") -> bool:
	var frame: Dictionary = {"type":"card_sync","protocol":router.network.protocol_version,"session_id":router.network.session.session_id,"run":run_id if run.is_empty() else run,"kind":kind,"data":data}
	if not router.network.send_message(frame):
		fail("Peer action channel could not send the Card Sync message.",false)
		return false
	return true
func begin() -> void:
	if router.enabled and not background_mode:
		say("Disconnect before preparing another shared match.")
		return
	if router.network.session.state != "connected":
		say("Connect first, then check cards.")
		return
	if router.network.remote_app_version != router.network.Codec.APP_VERSION:
		say("Card Sync could not start: update both clients to the same CardLink build; peer asset sync version is incompatible.")
		return
	if running or requested:
		say("Card Sync is already in progress.")
		return
	run_id = router.network.session.session_id
	catalog = Catalog.new(router.table.match_controller.loader.storage.directory)
	own = router.table.match_controller.model.players.local.deck_manifest.duplicate(true)
	if not Wire.manifest(own):
		say("Loaded deck manifest is invalid. Reload a deck before Card Sync.")
		return
	if own.is_empty() and router.table.match_controller.deck_name != "No deck loaded":
		say("This older match has no deck manifest. Reload its saved deck before Card Sync.")
		return
	pending = true
	router.table.match_controller.preparing_match = not background_mode
	choice = ""
	checked = false
	reports.clear()
	say("Checking card libraries... Waiting for the other player to choose Share Tabletop.")
	if not send("manifest",own): return
	check_ready()
func definition_key(row: Dictionary) -> String: return JSON.stringify(row).sha256_text()
func required() -> Array:
	# Deterministic union of both original deck manifests, not live match instances.
	var combined: Dictionary = {}
	for row: Dictionary in (remote if background_mode else own + remote):
		var pair: String = row.name.strip_edges().to_lower() + ":" + row.hash+JSON.stringify(row.get("faces",[]))
		if not combined.has(pair) or definition_key(row) < definition_key(combined[pair]): combined[pair] = row
	var result: Array = combined.values()
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return definition_key(a) < definition_key(b))
	return result
func inspect_required() -> Dictionary:
	var rows: Array = required()
	var result: Dictionary = catalog.check(rows)
	result.definitions = []
	for row: Dictionary in rows:
		if not catalog.equivalent(row): result.definitions.append(definition_key(row))
	return result
func check_ready() -> void:
	if not pending or not have_remote: return
	need = inspect_required()
	checked = not remote_availability.is_empty()
	if not send("availability",{"available":need.available,"missing":need.missing,"definitions":need.definitions.size(),"images":need.images.size()}): return
	show_availability()
func show_availability() -> void:
	if need.is_empty(): return
	if need.missing == 0:
		say("Card Sync: Ready\n%d / %d deck definitions available.\nChoose Start Match, or wait for your friend's card check." % [need.available,required().size()])
	else:
		say("WARNING\nSome cards required for this match were not found in your Card Library.\n%d / %d deck definitions available.\nChoose Sync Cards, Continue With Placeholders, or Cancel Match." % [need.available,required().size()])
func precondition() -> String:
	var net: Node = router.network
	if net.session.state != "connected": return "No active peer connection."
	if net.peer == null or net.closing or net.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: return "Peer action channel is not writable."
	if net.protocol_version != net.Codec.PROTOCOL or net.remote_app_version != net.Codec.APP_VERSION: return "Peer does not support this asset sync version. Update both clients to the same CardLink build."
	if not net.session.local_peer.role in ["host","guest"] or not net.session.remote_peer.role in ["host","guest"] or net.session.local_peer.role == net.session.remote_peer.role: return "Host/Guest roles are not known."
	if not pending: return "Match preparation has not been enabled. Both players must choose Share Tabletop."
	if catalog == null: return "Card Sync service is not initialized."
	if not Wire.manifest(own): return "Local deck manifest is invalid. Reload the deck."
	if not have_remote: return "%s deck manifest was not received. Ask the other player to choose Share Tabletop." % ("Guest" if host() else "Host")
	if not checked or remote_availability.is_empty(): return "Peer card availability was not received. Wait for both card checks, then retry."
	return ""
func decide(value: String) -> void:
	if running or requested:
		note("Card sync already in progress; duplicate request ignored.")
		return
	if value == "sync" and guided_consent_required and not preparation_authorized: return
	if value == "sync": say("Preparing card sync...")
	var error: String = precondition()
	if not error.is_empty():
		say("Card Sync could not start:\n" + error)
		return
	if value == "cancel":
		send("decision",{"choice":"cancel"})
		cancel()
		return
	if value == "start" and inspect_required().missing > 0:
		say("Cards are still missing. Choose Sync Cards or Continue With Placeholders.")
		return
	choice = value
	requested = value == "sync"
	elapsed = 0
	if requested: note("Card sync requested. Waiting for peer acknowledgement.")
	else: say("Waiting for the other player's match decision...")
	if not send("decision",{"choice":value}): return
	coordinate()
func coordinate() -> void:
	if not host() or running or choice.is_empty() or remote_choice.is_empty(): return
	if choice == "sync" or remote_choice == "sync":
		run_id = Crypto.new().generate_random_bytes(16).hex_encode()
		if send("begin",{}): start_transfer()
	else:
		if send("launch",{}): launch()
func start_transfer() -> void:
	if background_mode: work.begin(inspect_required(),remote_availability)
	failed_assets.clear()
	if guided_consent_required and not preparation_authorized: return
	last_failure = ""
	requested = false
	running = true
	step = 1
	reports.clear()
	received_bytes = 0
	clear_buffers()
	step_status()
	if host(): request_missing()
func step_status() -> void:
	say("Step %d of 2\nSyncing %s cards to %s...\nPlease wait." % [step,"Guest" if step == 1 else "Host","Host" if step == 1 else "Guest"])
func receiver() -> bool: return host() == (step == 1)
func request_missing() -> void:
	catalog.reload()
	need = inspect_required()
	pending_definitions.clear()
	sent_definitions = 0
	sent_images = 0
	# Each recipient controls whether it accepts missing cards.
	var accept: bool = choice == "sync"
	if not accept:
		need.definitions = []
		need.images = []
	note("%s: %d missing definitions, %d missing images." % ["Guest -> Host" if step == 1 else "Host -> Guest",need.definitions.size(),need.images.size()])
	send("need",{"step":step,"definitions":need.definitions if accept else [],"images":need.images if accept else []})
	elapsed = 0
func clear_buffers() -> void:
	finishing_step = false
	step_sent = false
	incoming.clear()
	incoming_hash = ""
	expected_bytes = 0
	sending.clear()
	sending_hash = ""
	queue.clear()
	accepted_images.clear()
	need_received = false
	waiting_ack = false
	elapsed = 0
func fail(message: String, notify_peer: bool = true) -> void:
	last_failure = message
	requested = false
	note("Card sync failed: " + message)
	running = false
	clear_buffers()
	choice = ""
	remote_choice = ""
	if notify_peer and router.network.session.state == "connected": send("error",{"message":message.left(200)})
	say("CARD SYNC INCOMPLETE\n" + message + "\nRetry Sync, Continue With Placeholders, or Cancel Match.")
func cancel_match() -> void:
	if pending: send("decision",{"choice":"cancel"})
	cancel()
func cancel() -> void:
	preparation_authorized = false
	requested = false
	remote_availability.clear()
	pending = false
	router.table.match_controller.preparing_match = false
	running = false
	checked = false
	have_remote = false
	remote.clear()
	choice = ""
	remote_choice = ""
	clear_buffers()
	say("Match preparation cancelled. Completed verified cards remain in your library.")
func launch() -> void:
	if guided_consent_required and choice not in ["start","placeholders"]: return
	if guided_consent_required and choice == "start" and inspect_required().missing > 0:
		fail("Required card assets changed before match verification.")
		return
	pending = false
	router.table.match_controller.preparing_match = false
	running = false
	clear_buffers()
	say("Card Sync: Ready" if inspect_required().missing == 0 else "Continuing with placeholders by choice.")
	router.start_public()
func receive(frame: Dictionary) -> void:
	if frame.session_id != router.network.session.session_id: return
	if frame.kind == "manifest":
		if (running or router.enabled) and not background_mode: return
		if background_mode and running:
			fail("Deck changed; rechecking selected cards.")
		if background_mode:
			var fingerprint: String = JSON.stringify(frame.data).sha256_text()
			if not background_remote_signature.is_empty() and background_remote_signature != fingerprint: work.reset()
			background_remote_signature = fingerprint
		remote = frame.data.duplicate(true)
		have_remote = true
		note("Manifest received from " + router.network.session.remote_peer.player_id + ".")
		check_ready()
		return
	if not pending: return
	if frame.kind == "availability":
		remote_availability = frame.data.duplicate(true)
		checked = have_remote and catalog != null and not need.is_empty()
		note("Peer availability received: %d available, %d missing definitions, %d missing images." % [frame.data.available,frame.data.definitions,frame.data.images])
		if not running and not requested and (not status.begins_with("CARD SYNC COMPLETE") or int(frame.data.missing) > 0 or int(need.get("missing",0)) > 0): show_availability()
		return
	if frame.kind == "begin":
		if host() or running or choice.is_empty(): return
		run_id = frame.run
		start_transfer()
		return
	if frame.run != run_id: return # Old chunks/acks cannot contaminate a retry.
	elapsed = 0
	var d: Variant = frame.data
	match frame.kind:
		"decision":
			if d.choice == "cancel": cancel()
			else:
				if running: return
				remote_choice = d.choice
				# Both peers have explicitly entered preparation. Either Sync button
				# starts the exchange; an explicit placeholder choice still opts out.
				if d.choice == "sync":
					var error: String = precondition()
					if not error.is_empty():
						fail(error)
						return
					if choice.is_empty() and not guided_consent_required:
						choice = "sync"
						requested = true
						say("Preparing card sync... Peer requested the exchange.")
						if not send("decision",{"choice":"sync"}): return
				coordinate()
		"launch":
			if not host() and not choice.is_empty(): launch()
		"error": fail(d.message,false)
		"need":
			if not running or receiver() or d.step != step or need_received: return
			note("%s: peer requests %d missing definitions, %d missing images." % ["Guest -> Host" if step == 1 else "Host -> Guest",d.definitions.size(),d.images.size()])
			need_received = true
			queue.clear()
			var by_id: Dictionary = {}
			var hashes: Dictionary = {}
			for row: Dictionary in (own if background_mode else required()):
				by_id[definition_key(row)] = row
				for hash: String in Catalog.images(row): hashes[hash] = true
			for id: String in d.definitions:
				if not by_id.has(id):
					fail("Peer requested a definition outside the loaded deck.")
					return
				queue.append({"kind":"definition","row":by_id[id]})
			for hash: String in d.images:
				if not hashes.has(hash):
					fail("Peer requested an image outside the loaded deck.")
					return
				queue.append({"kind":"image","hash":hash})
			pump()
		"definition":
			if not running or not receiver() or d.step != step or not definition_key(d.row) in need.definitions: return
			var expected: Dictionary = {}
			for row: Dictionary in required():
				if definition_key(row) == definition_key(d.row): expected = row
			if d.row != expected:
				fail("Metadata does not match the checked deck manifest.")
				return
			if not pending_definitions.any(func(row: Dictionary) -> bool: return definition_key(row) == definition_key(d.row)): pending_definitions.append(d.row)
		"image_begin":
			if not running or not receiver() or d.step != step: return
			if accepted_images.has(d.hash): return
			if not incoming_hash.is_empty() or not d.hash in need.images or received_bytes + int(d.bytes) > Wire.MAX_SESSION_BYTES:
				fail("Unexpected image or transfer exceeds limits.")
				return
			incoming_hash = d.hash
			expected_bytes = int(d.bytes)
			incoming.clear()
			send("ack",{"offset":0})
		"chunk":
			if not running or not receiver() or d.step != step or d.hash != incoming_hash: return
			if validation != null: return
			if d.offset < incoming.size(): # Duplicate packet: acknowledge, never append twice.
				send("ack",{"offset":incoming.size()})
				return
			var bytes: PackedByteArray = Marshalls.base64_to_raw(d.base64)
			if d.offset != incoming.size() or bytes.is_empty() or bytes.size() > Wire.CHUNK or incoming.size() + bytes.size() > expected_bytes:
				fail("Invalid, out-of-order, or oversized image chunk.")
				return
			incoming.append_array(bytes)
			if incoming.size() == expected_bytes:
				if background_mode:
					start_validation()
					return
				var error: String = catalog.store_image(incoming_hash,incoming)
				if not error.is_empty():
					fail(error)
					return
				accepted_images[incoming_hash] = true
				received_bytes += expected_bytes
				sent_images += 1
				if not send("ack",{"offset":expected_bytes}): return
				incoming_hash = ""
				incoming.clear()
			else:
				if not send("ack",{"offset":incoming.size()}): return
			say("Step %d of 2 — downloading images: %d / %d\nPlease wait." % [step,sent_images,need.images.size()])
		"ack":
			if not running or receiver() or not waiting_ack or d.offset != sending_offset: return
			waiting_ack = false
			say("Step %d of 2 — sending image: %d / %d bytes" % [step,sending_offset,sending.size()])
			if sending_offset >= sending.size():
				sending.clear()
				sending_hash = ""
			pump()
		"sent":
			if not running or not receiver() or d.step != step or not incoming_hash.is_empty(): return
			if background_mode:
				finishing_step = true
				return
			for row: Dictionary in pending_definitions:
				var error: String = catalog.store_definition(row)
				if not error.is_empty():
					fail(error)
					return
				sent_definitions += 1
				say("Step %d of 2 — receiving card %d / %d..." % [step,sent_definitions,pending_definitions.size()])
			catalog.reload()
			var available: Dictionary = inspect_required()
			var report: Dictionary = {"step":step,"missing":available.missing,"available":available.available,"definitions":sent_definitions,"images":sent_images,"reused":need.reused}
			reports[str(step)] = report
			if not send("report",report): return
			advance()
		"report":
			if not running or receiver() or d.step != step: return
			reports[str(step)] = d.duplicate(true)
			if background_mode: work.remote_finished(int(d.images)+int(d.definitions))
			advance()
func pump() -> void:
	if waiting_ack or not running or receiver() or step_sent or not need_received: return
	if background_mode:
		if last_pump_frame == Engine.get_process_frames() or router.network.outgoing.size() > 65536: return
		last_pump_frame = Engine.get_process_frames()
	if not sending_hash.is_empty():
		var bytes: PackedByteArray = sending.slice(sending_offset,mini(sending_offset+Wire.CHUNK,sending.size()))
		if not send("chunk",{"step":step,"hash":sending_hash,"offset":sending_offset,"base64":Marshalls.raw_to_base64(bytes)}): return
		sending_offset += bytes.size()
		waiting_ack = true
		return
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		if item.kind == "definition":
			if not send("definition",{"step":step,"row":item.row}): return
			if background_mode: return
		else:
			if not catalog.has_image(item.hash):
				if background_mode:
					failed_assets.append(item.hash)
					note("A selected-deck image is unavailable; continuing other cards.")
					return
				fail("Source gameplay asset is missing, damaged, or not normalized.")
				return
			sending = FileAccess.get_file_as_bytes(catalog.asset_path(item.hash))
			sending_hash = item.hash
			sending_offset = 0
			waiting_ack = true
			send("image_begin",{"step":step,"hash":item.hash,"bytes":sending.size()})
			return
	step_sent = true
	send("sent",{"step":step})
func advance() -> void:
	note(("Guest -> Host" if step == 1 else "Host -> Guest") + " complete.")
	clear_buffers()
	if step == 1:
		step = 2
		step_status()
		if not host(): request_missing()
	else:
		running = false
		choice = ""
		remote_choice = ""
		need = inspect_required()
		if background_mode:
			check_ready()
			work.finished = true
		var missing: int = reports["1"].missing + reports["2"].missing
		say(("CARD SYNC COMPLETE" if missing == 0 else "CARD SYNC INCOMPLETE") + "\nHost: %d / %d required deck definitions available\nGuest: %d / %d required deck definitions available\nTransferred: %d definitions, %d images\nReused: %d assets\nStill missing: %d\nChoose Start Match, Retry Sync, Continue With Placeholders, or Cancel Match." % [reports["1"].available,reports["1"].available+reports["1"].missing,reports["2"].available,reports["2"].available+reports["2"].missing,reports["1"].definitions+reports["2"].definitions,reports["1"].images+reports["2"].images,reports["1"].reused+reports["2"].reused,missing])
func _process(delta: float) -> void:
	poll_validation()
	if background_mode and finishing_step: finish_background_step()
	if background_mode and running and not receiver(): pump()
	if pending and router.network.session.state != "connected":
		cancel()
		say("Card Sync interrupted.\nConnection was lost.\nCompleted verified cards are preserved; reconnect and retry.")
	if running or requested:
		elapsed += delta
		if elapsed > 30: fail("Card Sync timed out; retry is available.")

func start_validation() -> void:
	# Initialize the shared read-only CRC table on the main thread before workers.
	Catalog.png_complete(PackedByteArray())
	validation_job = {"run":run_id,"hash":incoming_hash,"bytes":expected_bytes}
	var bytes: PackedByteArray = incoming.duplicate()
	var hash_value: String = incoming_hash
	var directory: String = catalog.directory
	validation = Thread.new()
	validation.start(func() -> String:
		var error: String = Catalog.validate_image(hash_value,bytes)
		if not error.is_empty(): return error
		var path: String = directory.path_join(hash_value+".png")
		if FileAccess.file_exists(path):
			return "" if FileAccess.get_sha256(path)==hash_value else "Existing asset is damaged; retained for review."
		if DirAccess.make_dir_recursive_absolute(directory) != OK: return "Cannot create storage."
		return "" if preload("res://scripts/card_storage.gd").write_atomic(path,bytes)==OK else "Cannot store verified image.")
func poll_validation() -> void:
	if validation == null or validation.is_alive(): return
	var error: String = validation.wait_to_finish()
	validation = null
	var job: Dictionary = validation_job
	validation_job = {}
	if error.is_empty(): asset_available.emit(job.hash)
	if not running or job.run != run_id or job.hash != incoming_hash: return
	received_bytes += int(job.bytes)
	if error.is_empty():
		accepted_images[job.hash] = true
		sent_images += 1
		work.complete("image:"+str(job.hash))
	else:
		failed_assets.append(job.hash)
		note("An image could not be verified; continuing other cards.")
	# ACK means this bounded frame was consumed, not that it was stored.
	# The final report counts only verified images/definitions.
	send("ack",{"offset":job.bytes})
	incoming_hash = ""
	incoming.clear()
	changed.emit()
func finish_background_step() -> void:
	if not running: finishing_step = false; return
	if not pending_definitions.is_empty():
		var row: Dictionary = pending_definitions.pop_front()
		var error: String = catalog.store_definition(row)
		if error.is_empty():
			sent_definitions += 1
			work.complete("definition:"+definition_key(row))
			asset_available.emit(row.hash)
		else: note("A definition still needs verified images; retry missing later.")
		return
	finishing_step = false
	catalog.reload()
	var available: Dictionary = inspect_required()
	var report: Dictionary = {"step":step,"missing":available.missing,"available":available.available,"definitions":sent_definitions,"images":sent_images,"reused":need.reused}
	reports[str(step)] = report
	if send("report",report): advance()
func _exit_tree() -> void:
	if validation != null:
		validation.wait_to_finish()
		validation = null
