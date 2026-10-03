extends Node
## Authenticated in-process rejoin. Public sequencing is deterministic, not gameplay ownership.
signal changed
var router: Node
var context: Dictionary = {}
var suspended: bool = false
var authenticated: bool = false
var reconnecting: bool = false
var challenge: String = ""
var client_nonce: String = ""
var transport: String = ""
var deadline: float = 0
var checking_until: float = 0
var retry_at: float = 0
var status: String = "Reconnect becomes available after starting a shared match."
func now() -> float: return Time.get_ticks_msec()/1000.0
func say(text: String) -> void:
	status = text
	if router.table != null and router.table.controls != null: router.table.controls.status.text = text
	changed.emit()
func _ready() -> void: router.network.recovery_received.connect(receive)
func send(kind: String, data: Dictionary) -> bool:
	if router.network.session.state != "connected": return false
	return router.network.send_message({"type":"recovery","protocol":router.network.protocol_version,"session_id":router.network.session.session_id,"kind":kind,"data":data})
func save_context(match_id: String, secret: String) -> void:
	context = {"match":match_id,"secret":secret,"role":router.network.session.local_peer.role,"player":router.local_id,"remote":router.remote_id,"name":router.network.session.local_peer.display_name,"address":router.network.last_address,"port":router.network.last_port}
	authenticated = true
	transport = router.network.session.session_id
	say("Match connection ready.")
func proof(nonce: String, role: String) -> String:
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA256,str(context.secret).to_utf8_buffer())
	h.update((str(context.match)+":"+router.network.session.session_id+":"+nonce+":"+role).to_utf8_buffer())
	return h.finish().hex_encode()
func verifies(received: String, expected: String) -> bool:
	if received.length() != expected.length(): return false
	var difference: int = 0
	for i: int in expected.length(): difference |= received.unicode_at(i) ^ expected.unicode_at(i)
	return difference == 0
func reconnect() -> void:
	if context.is_empty():
		say("Unable to reconnect: this match no longer has a saved session identity.")
		return
	if not router.network.available():
		say("Close the current connection before retrying.")
		return
	suspended = true
	authenticated = false
	reconnecting = true
	deadline = now()+30
	transport = ""
	say("Attempting reconnect... Both players choose Reconnect; host first.")
	if router.network.room_session != null and router.network.room_session.active:
		router.network.room_session.resume_connection()
		return
	if context.role == "host": router.network.host_game(int(context.port),context.name)
	else: router.network.join_game(context.address,int(context.port),context.name)
func continue_offline() -> void:
	reconnecting = false
	authenticated = false
	suspended = true
	router.enabled = false
	if not router.network.available(): router.network.disconnect_session()
	say("Offline match preserved. Reconnect restores the last ordered public board; offline public edits are not merged. Private cards stay local.")
func leave() -> void:
	if router.transactions.has_unfinished():
		say("A card transfer needs recovery. Reconnect to resolve it before leaving; local cards are preserved.")
		return
	continue_offline()
	context.clear()
	router.network.match_epoch="";router.network.reset_pending=false;router.network.quiesced=false
	if router.table!=null and router.table.battle!=null: router.table.battle.reset.leave()
	suspended = false
	say("Left multiplayer. Local match remains open.")
func fail(message: String) -> void:
	send("error",{"message":message.left(200)})
	reconnecting = false
	authenticated = false
	suspended = true
	router.enabled = false
	say("Unable to reconnect. " + message + " Retry, Continue Offline, or Leave Match.")
	router.network.disconnect_session()
func check_identity() -> bool:
	return not context.is_empty() and router.network.remote_app_version == router.network.Codec.APP_VERSION and router.network.protocol_version == router.network.Codec.PROTOCOL and router.network.session.local_peer.role == context.role and router.network.session.local_peer.player_id == context.player and router.network.session.remote_peer.player_id == context.remote
func receive(f: Dictionary) -> void:
	if f.session_id != router.network.session.session_id: return
	var d: Dictionary = f.data
	if f.kind == "error" and suspended:
		reconnecting = false
		authenticated = false
		router.enabled = false
		say("Unable to reconnect. " + d.message)
		router.network.disconnect_session()
		return
	if f.kind == "seed":
		if not router.is_host() and router.enabled and context.is_empty(): save_context(d.match,d.secret)
		return
	if f.kind in ["hello","challenge","proof"]:
		if not suspended or not check_identity() or d.match != context.match:
			fail("Session or player identity does not match.")
			return
		if f.kind == "hello" and context.role == "host":
			if not verifies(d.proof,proof(d.nonce,"guest_hello")):
				fail("The peer could not prove its saved identity.")
				return
			client_nonce = d.nonce
			challenge = Crypto.new().generate_random_bytes(32).hex_encode()
			send("challenge",{"match":context.match,"nonce":challenge,"proof":proof(client_nonce+":"+challenge,"host"),"revision":router.committed})
		elif f.kind == "challenge" and context.role == "guest":
			if client_nonce.is_empty() or not verifies(d.proof,proof(client_nonce+":"+d.nonce,"host")):
				fail("The host could not prove its saved identity.")
				return
			authenticated = true
			say("Reconnected. Checking match state...")
			if reset_guarded(): router.table.battle.reset.guard();reconnecting=false
			send("proof",{"match":context.match,"nonce":d.nonce,"proof":proof(client_nonce+":"+d.nonce,"guest"),"revision":router.committed})
		elif f.kind == "proof" and context.role == "host":
			if d.nonce != challenge or not verifies(d.proof,proof(client_nonce+":"+challenge,"guest")) or (int(d.revision) > router.committed and not reset_guarded()):
				fail("Saved peer identity or public revision could not be verified.")
				return
			authenticated = true
			if reset_guarded():
				router.table.battle.reset.guard();reconnecting=false;say("Reconnected. Both players must approve Reset Match again.");return
			router.enabled = true
			router.opted_in = true
			router.session_id = router.network.session.session_id
			# Restore canonical physical objects before any new scan can publish offline edits.
			router.resync.apply(router.state,router.committed)
			say("Synchronizing public tabletop...")
			if not send("snapshot",{"revision":router.committed,"state":router.state}): fail("Public state could not fit or be sent safely.")
		return
	if not authenticated or context.is_empty() or reset_guarded(): return
	match f.kind:
		"snapshot":
			if router.is_host() or int(d.revision) < router.committed: return
			router.enabled = true
			router.opted_in = true
			router.session_id = router.network.session.session_id
			router.resync.apply(d.state,int(d.revision))
			finish()
			send("restored",{"revision":router.committed})
			resend_pending()
		"restored":
			if router.is_host(): finish()
		"check":
			if router.is_host():
				router.scan()
				send("snapshot",{"revision":router.committed,"state":router.state})
		"action_ack": router.journal.ack(d.id,int(d.revision))
		"error": say(d.message)
func finish() -> void:
	checking_until = 0
	suspended = false
	reconnecting = false
	transport = router.network.session.session_id
	router.baseline = router.serializer.capture()
	router.transactions.exchange_summary()
	router.publish_counts.call_deferred()
	say("Match restored.")
func resend_pending() -> void:
	retry_at = now()+1
	var actions: Array = router.journal.pending.values()
	actions.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.sequence < b.sequence)
	for action: Dictionary in actions.slice(0,4):
		if router.network.outgoing.size() > 524288: break
		router.send_frame("request",action)
func manual_resync() -> void:
	if not router.enabled or not authenticated: return
	say("Checking match state...")
	checking_until = now()+10
	if router.is_host():
		router.scan()
		if not send("snapshot",{"revision":router.committed,"state":router.state}): say("Unable to send public state. Retry public resync.")
	else:
		if not send("check",{"revision":router.committed}): say("Unable to request public state. Retry public resync.")
func _process(_delta: float) -> void:
	if router.table == null: return
	if router.network.session.state != "connected":
		if authenticated:
			authenticated = false
			suspended = not context.is_empty()
			router.enabled = false
			say("Connection lost. Local match preserved. Choose Reconnect or Continue Offline.")
		if reconnecting and now() > deadline: fail("The other client did not return within 30 seconds.")
		return
	if router.enabled and context.is_empty() and router.is_host():
		save_context(router.network.session.session_id,Crypto.new().generate_random_bytes(32).hex_encode())
		send("seed",{"match":context.match,"secret":context.secret})
	if suspended and transport != router.network.session.session_id:
		transport = router.network.session.session_id
		deadline = now()+30
		reconnecting = true
		if not check_identity():
			fail("Session role, protocol, or player identity changed.")
			return
		if context.role == "guest":
			client_nonce = Crypto.new().generate_random_bytes(32).hex_encode()
			send("hello",{"match":context.match,"nonce":client_nonce,"proof":proof(client_nonce,"guest_hello"),"revision":router.committed})
	if reconnecting and now() > deadline: fail("Match recovery timed out.")
	if authenticated and not suspended and not router.journal.pending.is_empty() and now() > retry_at: resend_pending()
	if checking_until > 0 and now() > checking_until:
		checking_until = 0
		say("Public resync did not finish in time. Retry or reconnect; local state is preserved.")

func reset_guarded() -> bool:
	return router.table!=null and router.table.battle!=null and (router.table.battle.reset.guarded or router.network.remote_reset_pending)
