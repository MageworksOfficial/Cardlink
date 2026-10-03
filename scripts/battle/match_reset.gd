extends RefCounted
## Bilateral rematch coordinator. Only public projections cross the wire.
var session: Node
var start: RefCounted
var phase: String = ""
var id: String = ""
var rebuilding: bool = false
var guarded: bool = false
var checkpoint: bool = false
var deadline: int = 0
var backup: Dictionary = {}
var own: Dictionary = {}
var paused_window: Window
var paused_label: Label
var prompt: ConfirmationDialog
func _init(owner: Node) -> void:
	session=owner;start=preload("res://scripts/battle/starting_match.gd").new(self)
func tell(text: String) -> void:
	session.tell(text)
	if is_instance_valid(paused_label) and paused_window.visible: paused_label.text=text
func dialog(title: String,text: String,yes: String,callback: Callable,no: String="Cancel",cancel: Callable=Callable()) -> void:
	if is_instance_valid(prompt): prompt.hide();prompt.queue_free()
	prompt=ConfirmationDialog.new();prompt.title=title;prompt.dialog_text=text;prompt.ok_button_text=yes;prompt.cancel_button_text=no
	prompt.confirmed.connect(callback)
	if cancel.is_valid(): prompt.canceled.connect(cancel)
	session.add_child(prompt);prompt.popup_centered(Vector2i(480,160))
func empty_warning() -> String:
	return "\nThis manual/older match has no recorded starting decks; the table will be empty." if start.sources.is_empty() and not session.manager.cards.is_empty() else ""
func open() -> void:
	if not phase.is_empty(): tell("Waiting for the reset to finish.");return
	if session.connected(): dialog("Reset Match?","Restart this game while keeping both players connected?"+empty_warning(),"Request Reset",request)
	elif guarded: tell("Reconnect both players and approve a new reset before continuing.")
	else: dialog("Reset Match?","Restart this game using its starting decks?"+empty_warning(),"Reset",offline)
func offline() -> void:
	var error: String=start.preflight()
	if not error.is_empty(): tell(error);return
	var prior: Dictionary=session.manager.persistence.capture_match()
	error=start.rebuild()
	if not error.is_empty(): preload("res://scripts/match_snapshot.gd").restore(session.manager,prior);tell(error);return
	tell("Match reset complete.")
func eligible() -> bool:
	return session.connected() and session.network.remote_battle and (session.router.enabled or (guarded and session.router.recovery.authenticated))
func request() -> void:
	if not eligible(): tell("Both players need the Battle Feedback update and a shared match before resetting.");return
	var error: String=start.preflight()
	if not error.is_empty(): tell(error);return
	id=Crypto.new().generate_random_bytes(16).hex_encode();phase="asked";deadline=Time.get_ticks_msec()+60000
	if not session.send("reset_request",{"id":id}): phase="";tell("Reset request could not be sent.");return
	tell("Reset requested. Waiting for "+session.network.session.remote_peer.display_name+"…")
func accept() -> void:
	if_prompt_hide()
	if phase!="received": return
	var error: String=start.preflight()
	if not error.is_empty(): decline();tell(error);return
	phase="accepted"
	if session.router.is_host(): prepare_host()
	else: session.send("reset_accept",{"id":id})
func decline() -> void:
	if_prompt_hide()
	if phase!="received": return
	session.send("reset_decline",{"id":id});phase="";tell("Reset declined.")
func freeze() -> String:
	var error: String=start.preflight()
	if not error.is_empty(): return error
	checkpoint=true;session.network.reset_pending=true;session.network.quiesced=true
	var r: Node=session.router
	r.hidden.close_incoming(false);r.hidden.close_outgoing(false)
	backup=session.manager.persistence.capture_match()
	session.manager.controls.close_panels();session.manager.set_active(false)
	tell("Starting new match…")
	error=start.rebuild()
	if error.is_empty(): own=r.serializer.capture()
	return error
func prepare_host() -> void:
	phase="preparing";deadline=Time.get_ticks_msec()+30000
	var error: String=freeze()
	if not error.is_empty(): abort(error);return
	if not session.send("reset_prepare",{"id":id}): guard()
func merge(remote: Dictionary) -> Dictionary:
	var result: Dictionary=own.duplicate(true)
	var r: Node=session.router
	# The remote peer supplies only its own public starting pieces/counts.
	result.players[r.remote_id]=remote.players[r.remote_id].duplicate(true)
	result.hands={"player_1":[],"player_2":[]};result.history=[];result.counters={}
	result.turn={"number":1,"active":"player_1"}
	for key: String in remote.cards:
		if remote.cards[key].owner!=r.remote_id or result.cards.has(key): continue
		result.cards[key]=remote.cards[key].duplicate(true);result.order.append(key)
	for key: String in remote.zones:
		if not result.zones.has(key): result.zones[key]=remote.zones[key].duplicate(true)
	return result
func commit(value: Dictionary) -> void:
	var r: Node=session.router
	session.network.match_epoch=id
	r.journal=preload("res://scripts/network/public_action_journal.gd").new()
	r.request_sequence=0;r.remote_sequence=0;r.committed=0;r.seen.clear();r.private_returns.clear()
	r.hidden.transfers.clear();r.hidden.received_transfers.clear();r.hidden.hand_reveals.clear()
	r.transactions.records.clear();r.library_memory.signature=""
	r.session_id=session.network.session.session_id
	r.resync.apply(value,0)
	session.backs.clear()
func finish() -> void:
	var r: Node=session.router
	r.enabled=true;r.opted_in=true;r.remote_ready=true
	r.recovery.suspended=false;r.recovery.reconnecting=false;r.recovery.transport=session.network.session.session_id
	r.baseline=r.serializer.capture()
	guarded=false;phase="";backup.clear()
	if is_instance_valid(paused_window): paused_window.hide()
	session.network.quiesced=false;session.manager.set_active(true)
	session.manager.match_controller.refresh();session.manager.custom_table.pile_sync.counts();tell("Match reset complete. Both players are still connected.")
func guard() -> void:
	guarded=true;checkpoint=true;phase="";backup.clear()
	if is_instance_valid(prompt): prompt.hide()
	if session.network!=null: session.network.reset_pending=true;session.network.quiesced=true
	session.manager.set_active(false)
	if session.router!=null: session.router.enabled=false
	tell("Reset paused. Reconnect both players, then approve Reset Match again.")
	show_pause()
func abort(message: String) -> void:
	if session.connected(): session.send("reset_cancel",{"id":id})
	if not backup.is_empty():
		rebuilding=true;preload("res://scripts/match_snapshot.gd").restore(session.manager,backup);rebuilding=false
	backup.clear();phase="";checkpoint=false
	if session.network!=null: session.network.reset_pending=false;session.network.quiesced=false
	session.manager.set_active(true);tell(message)
func poll() -> void:
	if session.network==null: return
	if not session.connected():
		if checkpoint: guard()
		elif not phase.is_empty(): phase="";tell("Reset canceled because the connection closed.");if_prompt_hide()
	elif not phase.is_empty() and Time.get_ticks_msec()>deadline:
		if checkpoint: guard()
		else: session.send("reset_cancel",{"id":id});phase="";tell("Reset request expired.");if_prompt_hide()
func if_prompt_hide() -> void:
	if is_instance_valid(prompt): prompt.hide()
func receive(kind: String,d: Dictionary) -> void:
	if session.router.recovery.suspended and not session.router.recovery.authenticated: return
	if not eligible() and not checkpoint: return
	if kind=="reset_request":
		if phase=="asked":
			if session.router.is_host(): session.send("reset_request",{"id":id});return
			id=d.id;phase="received";accept();return
		if not phase.is_empty(): return
		id=d.id;phase="received";deadline=Time.get_ticks_msec()+60000
		dialog("Reset Match Request",session.network.session.remote_peer.display_name+" wants to restart the match."+empty_warning(),"Accept",accept,"Decline",decline);return
	if d.id!=id: return
	match kind:
		"reset_accept":
			if session.router.is_host() and phase=="asked": prepare_host()
		"reset_decline":
			if phase=="asked": phase="";tell("Reset declined.")
		"reset_prepare":
			if session.router.is_host() or phase!="accepted": return
			phase="preparing";deadline=Time.get_ticks_msec()+30000
			var error: String=freeze()
			if not error.is_empty(): abort(error);return
			session.send("reset_prepared",{"id":id,"state":own})
		"reset_prepared":
			if not session.router.is_host() or phase!="preparing": return
			var value: Dictionary=merge(d.state)
			if not preload("res://scripts/network/network_action.gd").snapshot(value): abort("Starting table is too large to reset online.");return
			phase="committing";commit(value);session.send("reset_commit",{"id":id,"state":value})
		"reset_commit":
			if session.router.is_host() or phase!="preparing": return
			phase="committing";commit(d.state);session.send("reset_committed",{"id":id})
		"reset_committed":
			if session.router.is_host() and phase=="committing": phase="starting";session.send("reset_go",{"id":id})
		"reset_go":
			if not session.router.is_host() and phase=="committing": phase="starting";session.send("reset_started",{"id":id})
		"reset_started":
			if session.router.is_host() and phase=="starting": finish();session.send("reset_done",{"id":id})
		"reset_done":
			if not session.router.is_host() and phase=="starting": finish();session.send("reset_finished",{"id":id})
		"reset_finished":
			if session.router.is_host() and checkpoint and phase.is_empty(): checkpoint=false;session.network.reset_pending=false;session.send("reset_stable",{"id":id})
		"reset_stable":
			if not session.router.is_host() and checkpoint and phase.is_empty(): checkpoint=false;session.network.reset_pending=false
		"reset_cancel":
			if phase in ["asked","received","accepted","preparing"]: abort("Reset canceled.");if_prompt_hide()
			elif not phase.is_empty(): guard()

func show_pause() -> void:
	if not is_instance_valid(paused_window):
		paused_window=Window.new();paused_window.title="Reset paused";paused_window.visible=false;session.add_child(paused_window)
		var rows := VBoxContainer.new();rows.position=Vector2(16,16);rows.size=Vector2(448,155);paused_window.add_child(rows)
		paused_label=Label.new();paused_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rows.add_child(paused_label)
		var reconnect := Button.new();reconnect.text="Reconnect";rows.add_child(reconnect);reconnect.pressed.connect(func() -> void: session.router.recovery.reconnect())
		var again := Button.new();again.text="Request Reset Again";rows.add_child(again);again.pressed.connect(func() -> void: request())
	paused_label.text="The reset was interrupted. Both players must reconnect, then approve a new reset. Your saved decks and collection are safe."
	if not paused_window.visible: paused_window.popup_centered(Vector2i(480,200))

func leave() -> void:
	phase="";guarded=false;checkpoint=false;backup.clear()
	if_prompt_hide()
	if is_instance_valid(paused_window): paused_window.hide()
	session.manager.set_active(true)
