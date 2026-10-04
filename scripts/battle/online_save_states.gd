extends Node
## Paired local checkpoints. No private save payload is sent to the other client.
const Data=preload("res://scripts/battle/online_state_data.gd")
const Fingerprint=preload("res://scripts/battle/deck_fingerprint.gd")
const Capsule=preload("res://scripts/battle/save_state_capsule.gd")
const Protocol=preload("res://scripts/battle/online_state_protocol.gd")
var battle: Node
var storage=preload("res://scripts/named_json_storage.gd").new("user://online_match_states","online_state")
var writes=preload("res://scripts/battle/paired_save_writes.gd").new()
var phase: String=""
var transaction_epoch: String=""
var retired: Array[String]=[]
var id: String=""
var deadline: int=0
var staged: Dictionary={}
var file: Dictionary={}
var public: Dictionary={}
var backup: Dictionary={}
var caption: String=""
var last_path: String=""
var status: String=""
var committed: bool=false
var window: Window
var picker: OptionButton
var name_edit: LineEdit
var label: Label
var prompt: ConfirmationDialog
func r() -> Node: return battle.router
func m() -> Node: return battle.manager
func n() -> Node: return battle.network
func local_role() -> String: return n().session.local_peer.player_id
func identity() -> String: return secret().hex_encode().sha256_text()
func retire() -> void:
	if not id.is_empty() and not retired.has(id): retired.append(id)
	if retired.size()>64: retired.pop_front()
func tell(text: String) -> void:
	status=text;battle.tell(text)
	if is_instance_valid(label): label.text=text
func fingerprint() -> String:
	return str(Fingerprint.calculate(battle.reset.start.usable(),m().match_controller.loader.load_records()).get("fingerprint",""))
func secret() -> PackedByteArray:
	return Capsule.key(m().match_controller.loader.storage.directory.path_join("online_save_private.key"))
func reason(host_only: bool=true) -> String:
	for card: Control in m().cards:
		if card.state.current_zone=="review":return "PLAYTEST: resolve your Review Tray before online Save/Load."
	if m().temporary_images!=null and not m().temporary_images.objects.is_empty():return "PLAYTEST: remove temporary images before online Save/Load; local saves can retain them."
	if not battle.connected(): return "Connect both players and load the original decks first."
	if host_only and not r().is_host(): return "The original host requests Load Match; the other player approves."
	if not n().peer is StreamPeerTCP and not n().relay_save_capable: return "Match Save requires an updated CardLink server."
	if not n().save_capable or not n().peer_save_capable(): return "Both players must be running CardLink V0.8.5.1 or newer with Match Save support."
	if m().custom_table.enabled: return "Online Match Save is currently available for standard tables only."
	if r().recovery.suspended or battle.reset.guarded or not battle.reset.phase.is_empty(): return "Finish reconnecting or resetting before saving or loading."
	if r().transactions.has_unfinished() or r().card_sync.running or r().card_sync.requested: return "Finish Card Sync or pending card transfers first."
	if fingerprint().is_empty(): return "Load your original deck before saving or restoring."
	if secret().size()!=64: return "Your local Match Save identity is unavailable."
	return ""
func send(kind: String,data: Dictionary={}) -> bool:
	data=data.duplicate(true);data["id"]=id;data["epoch"]=transaction_epoch
	return battle.send("state_"+kind,data)
func begin(next: String) -> void:
	transaction_epoch=n().match_epoch;id=Crypto.new().generate_random_bytes(16).hex_encode();phase=next;deadline=Time.get_ticks_msec()+60000;committed=false
func freeze() -> void:
	r().scan();n().quiesced=true;r().hidden.close_incoming(false);r().hidden.close_outgoing(false)
	backup=m().persistence.capture_match();m().set_active(false)
func thaw() -> void:
	retire();n().quiesced=false;m().set_active(true);backup.clear();phase="";staged.clear()
	if is_instance_valid(prompt): prompt.hide()
func cancel(message: String,notify_peer: bool=true,code: String="invalid") -> void:
	if notify_peer and battle.connected(): send("cancel",{"reason":code})
	writes.abort(storage)
	if committed:
		battle.reset.guard();phase="";tell("Restore interrupted. Reconnect and approve Reset Match before continuing.");return
	thaw();tell(message);refresh()
func show_prompt(title: String,text: String,yes: Callable,no: Callable) -> void:
	if is_instance_valid(prompt): prompt.queue_free()
	prompt=ConfirmationDialog.new();prompt.title=title;prompt.dialog_text=text;prompt.ok_button_text="ACCEPT";prompt.cancel_button_text="DECLINE"
	prompt.confirmed.connect(yes);prompt.canceled.connect(no);add_child(prompt);prompt.popup_centered(Vector2i(500,200))
func save(value: String) -> void:
	var error: String=reason(false)
	if not phase.is_empty(): error="A Save or Load Match request is already pending."
	if error.is_empty() and not r().enabled: error="Start the match before saving."
	if not Data.safe_text(value,80): error="Enter a save name of 1 to 80 characters."
	if not error.is_empty(): tell(error);return
	caption=value.strip_edges();last_path="";begin("save_wait_reply")
	if not send("save_offer",{"name":caption}): cancel("Save Match request could not be sent.");return
	tell("Waiting for the other player to accept Save Match.")
func accept_save() -> void:
	if phase!="save_offer": return
	if not reason(false).is_empty(): cancel(reason(false));return
	prompt.hide()
	if not send("save_accept"): cancel("Save Match approval could not be sent.");return
	checkpoint()
func decline_save() -> void:
	if phase!="save_offer": return
	send("save_decline");thaw();tell("Save Match request declined.")
func checkpoint() -> void:
	phase="save_wait_ready" if r().is_host() else "save_drain";deadline=Time.get_ticks_msec()+60000
	if not r().is_host(): r().scan()
	tell("Saving Match...")
func make_shared(peer: Dictionary) -> Dictionary:
	return {"save_state_id":id,"save_name":caption,"timestamp":Time.get_datetime_string_from_system(true),"app_version":preload("res://scripts/frontend/app_info.gd").LABEL,"table":"standard","names":{"player_1":n().session.local_peer.display_name,"player_2":n().session.remote_peer.display_name},"fingerprints":{"player_1":fingerprint(),"player_2":peer.fingerprint},"roles":{"player_1":identity(),"player_2":peer.identity},"public_hash":Data.hash_value(public)}
func stage_save(shared: Dictionary) -> bool:
	var own: Dictionary=Data.capture(m())
	if own.has("error"): return false
	var sealed: Dictionary=Capsule.seal(own,secret())
	if sealed.has("error"): return false
	var record: Dictionary={"format":"cardlink_paired_state","version":2,"shared":shared,"public":public,"local_role":local_role(),"private_capsule":sealed}
	return Data.validate(record).is_empty() and writes.stage(storage,record,caption)
func save_failure() -> void: cancel("Match could not be saved on both players' computers.",true,"write_failed")
func saved() -> void:
	last_path=writes.finish();thaw();tell("Match Saved");refresh()
func load_file(path: String) -> void:
	var error: String=reason()
	if not phase.is_empty(): error="A Save or Load Match request is already pending."
	if not error.is_empty(): tell(error);return
	var read: Dictionary=storage.read_record(path)
	if read.has("error"): tell(read.error);return
	file=read.record.data;error=prepare_local()
	if not error.is_empty(): tell(error);return
	begin("probe")
	if not send("probe",pair_reference()): cancel("Could not check the matching save.");return
	tell("Checking the matching save and original decks...")
func pair_reference() -> Dictionary:
	return {"save_state_id":file.shared.save_state_id,"shared_hash":Data.hash_value(file.shared)}
func prepare_local() -> String:
	var error: String=Data.validate(file)
	if not error.is_empty(): return error
	if file.local_role!=local_role() or file.shared.roles[local_role()]!=identity(): return "This saved match requires the original Host/Guest roles and installations. Reconnect using the original roles."
	var opened: Dictionary=Capsule.open(file.private_capsule,secret())
	if opened.has("error"): return opened.error
	var bound: Dictionary=Data.bind(opened.data,m())
	if bound.has("error"): return bound.error
	staged=bound.data;public=file.public;return ""
func find_pair(save_id: String) -> Dictionary:
	for row: Dictionary in storage.list_records():
		var data: Dictionary=row.get("record",{}).get("data",{})
		if data.get("shared") is Dictionary and data.shared.get("save_state_id","")==save_id: return data
	return {}
func accept() -> void:
	if phase!="load_offer": return
	prompt.hide()
	if not reason(false).is_empty() or fingerprint()!=file.shared.fingerprints[local_role()]: cancel("Deck changed or connection is not ready.");return
	freeze();phase="load_ready";deadline=Time.get_ticks_msec()+30000
	if not send("accept"): cancel("Load approval could not be sent.")
func decline() -> void:
	if phase!="load_offer": return
	send("decline");thaw();tell("Load Match declined. Current match unchanged.")
func apply_staged() -> bool:
	r().local_id=n().session.local_peer.player_id;r().remote_id=n().session.remote_peer.player_id
	m().match_controller.public_sync=r()
	var result: Dictionary=Data.Snapshot.restore(m(),staged)
	if result.has("error"):
		if not backup.is_empty(): Data.Snapshot.restore(m(),backup)
		return false
	# Reuse bilateral reset's generation/journal/private-transfer invalidation.
	battle.reset.id=id;battle.reset.commit(public)
	battle.reset.checkpoint=true;n().reset_pending=true
	committed=true
	return true
func finish() -> void:
	battle.reset.finish();phase="stable";deadline=Time.get_ticks_msec()+30000
	tell("Saved match restored. Both players retain their own private state.")
func stable() -> void:
	retire()
	battle.reset.checkpoint=false;n().reset_pending=false;committed=false;phase="";backup.clear();staged.clear()
func receive(kind: String,d: Dictionary) -> void:
	if not battle.connected() or not n().save_capable or not n().peer_save_capable(): return
	if not n().peer is StreamPeerTCP and not n().relay_save_capable: return
	if not Protocol.valid(kind,d) or retired.has(d.id) or not Protocol.sender_allowed(kind,not r().is_host()): return
	if phase.is_empty():
		if d.epoch!=n().match_epoch: return
		transaction_epoch=d.epoch
	elif d.epoch!=transaction_epoch: return
	kind=kind.trim_prefix("state_")
	if kind=="save_offer":
		if not phase.is_empty(): return
		id=d.id;caption=d.name;phase="save_offer";deadline=Time.get_ticks_msec()+60000;committed=false
		if not reason(false).is_empty() or not r().enabled: cancel("Start a compatible match before saving.");return
		show_prompt("SAVE MATCH REQUEST",n().session.remote_peer.display_name+" wants to save the current match as:\n\n"+caption+"\n\nA matching save state will be stored on both players' computers.",accept_save,decline_save);return
	if kind=="probe":
		if r().is_host() or not phase.is_empty(): return
		id=d.id;phase="paired_probe";deadline=Time.get_ticks_msec()+60000;committed=false;file=find_pair(d.save_state_id)
		if file.is_empty(): cancel("The other player does not have the matching save state.",true,"missing_pair");return
		var error: String=prepare_local()
		if not error.is_empty(): cancel(error,true,"invalid");return
		if Data.hash_value(file.shared)!=d.shared_hash: cancel("The paired save records do not match.",true,"pair_mismatch");return
		send("info",{"fingerprint":fingerprint() if reason(false).is_empty() else ""});return
	if d.id!=id or phase.is_empty(): return
	match kind:
		"save_accept":
			if phase=="save_wait_reply": checkpoint()
		"save_decline":
			if phase=="save_wait_reply": thaw();tell("Save Match request declined.")
		"save_ready":
			if not r().is_host() or phase!="save_wait_ready": return
			freeze();public=r().serializer.capture();var shared: Dictionary=make_shared(d)
			if not stage_save(shared): save_failure();return
			phase="save_capture"
			if not send("capture",{"state":public,"revision":r().committed,"shared":shared}): save_failure()
		"capture":
			if r().is_host() or phase!="save_frozen": return
			if d.shared.save_state_id!=id or d.shared.save_name!=caption or d.shared.roles.player_2!=identity() or d.shared.fingerprints.player_2!=fingerprint() or d.shared.public_hash!=Data.hash_value(d.state): cancel("Save checkpoint does not match.");return
			r().resync.apply(d.state,int(d.revision));public=d.state
			if not stage_save(d.shared): save_failure();return
			phase="save_staged";send("save_staged")
		"save_staged":
			if not r().is_host() or phase!="save_capture": return
			if not writes.commit(storage): save_failure();return
			phase="save_commit";send("save_commit")
		"save_commit":
			if r().is_host() or phase!="save_staged": return
			if not writes.commit(storage): save_failure();return
			phase="save_committed";send("save_committed")
		"save_committed":
			if not r().is_host() or phase!="save_commit": return
			if not send("save_done"): save_failure();return
			saved()
		"save_done":
			if not r().is_host() and phase=="save_committed": saved()
		"info":
			if not r().is_host() or phase!="probe": return
			var error: String=Data.mismatch(fingerprint()==file.shared.fingerprints.player_1,d.fingerprint==file.shared.fingerprints.player_2)
			if not error.is_empty(): cancel(error);return
			phase="load_wait"
			if not send("load",pair_reference()): cancel("Load Match request could not be sent.")
		"load":
			if r().is_host() or phase!="paired_probe": return
			if d.save_state_id!=file.shared.save_state_id or d.shared_hash!=Data.hash_value(file.shared): cancel("The paired save records do not match.",true,"pair_mismatch");return
			if fingerprint()!=file.shared.fingerprints.player_2: cancel("This save state requires a different Player 2 deck.");return
			phase="load_offer";show_prompt("LOAD MATCH REQUEST","Restore the saved match:\n\n"+file.shared.save_name,accept,decline)
		"accept":
			if not r().is_host() or phase!="load_wait": return
			if fingerprint()!=file.shared.fingerprints.player_1: cancel("Player 1 deck changed; restore canceled.");return
			freeze()
			if not apply_staged(): cancel("Local restore failed.");return
			phase="load_commit";deadline=Time.get_ticks_msec()+30000
			if not send("commit"): cancel("Restore commit could not be sent.")
		"commit":
			if r().is_host() or phase!="load_ready": return
			if not apply_staged(): cancel("Local restore failed.");return
			phase="load_commit"
			if not send("committed"): cancel("Restore acknowledgement failed.")
		"committed":
			if not r().is_host() or phase!="load_commit": return
			finish()
			if not send("go"): cancel("Restore completion could not be sent.")
		"go":
			if r().is_host() or phase!="load_commit": return
			finish();send("ack")
		"ack":
			if r().is_host() and phase=="stable": send("stable");stable()
		"stable":
			if not r().is_host() and phase=="stable": stable()
		"decline":
			if r().is_host() and phase=="load_wait": thaw();tell("Load Match declined. Current match unchanged.")
		"cancel":
			var messages: Dictionary={"write_failed":"Match could not be saved on both players' computers.","missing_pair":"The other player does not have the matching save state.","pair_mismatch":"The paired save records do not match.","invalid":"Save/Load canceled. Check the other player's message."}
			cancel(messages[d.reason],false)
func _process(_delta: float) -> void:
	if phase.is_empty(): return
	if not battle.connected() or Time.get_ticks_msec()>deadline: cancel("Save/Load expired or disconnected. No shared completion was confirmed.",battle.connected());return
	if phase=="save_drain" and r().journal.pending.is_empty():
		freeze();phase="save_frozen"
		if not send("save_ready",{"fingerprint":fingerprint(),"identity":identity()}): save_failure()
func open(load_mode: bool=false) -> void:
	if not is_instance_valid(window):
		window=Window.new();window.title="Online Save / Load Match State";window.visible=false;window.close_requested.connect(window.hide);add_child(window)
		var rows:=VBoxContainer.new();window.add_child(rows);rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);rows.offset_left=16;rows.offset_right=-16;rows.offset_top=16;rows.offset_bottom=-16
		name_edit=LineEdit.new();name_edit.placeholder_text="Save-state name";rows.add_child(name_edit)
		picker=OptionButton.new();rows.add_child(picker)
		m().controls.button(rows,"Save Match",func() -> void: save(name_edit.text))
		m().controls.button(rows,"Load Match...",func() -> void:
			if picker.selected>=0: load_file(str(picker.get_selected_metadata())))
		label=Label.new();label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rows.add_child(label)
		m().controls.button(rows,"Close",window.hide)
	refresh();tell("Either player can request Save Match. Both players must agree. To restore, load the original decks and keep the original Host/Guest roles.")
	window.popup_centered(Vector2i(550,310))
	if load_mode: picker.grab_focus()
func refresh() -> void:
	if not is_instance_valid(picker): return
	picker.clear()
	for record: Dictionary in storage.list_records():
		var candidate: Variant=record.get("record",{}).get("data",{}).get("shared",{})
		var shared: Dictionary=candidate if candidate is Dictionary else {}
		var names: Dictionary=shared.get("names",{}) if shared.get("names",{}) is Dictionary else {}
		picker.add_item(record.name+" | "+str(shared.get("timestamp","Older save"))+" | "+str(names.get("player_1",""))+" vs "+str(names.get("player_2","")))
		picker.set_item_metadata(picker.item_count-1,record.path)
