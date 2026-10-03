extends Node
var manager: Node
var network: Node
var router: Node
var reset: RefCounted
var saves: Node
var backs: RefCounted
var transport: String = ""
var tick: float = 0
func _ready() -> void:
	reset=preload("res://scripts/battle/match_reset.gd").new(self)
	saves=preload("res://scripts/battle/online_save_states.gd").new();saves.battle=self;add_child(saves)
	backs=preload("res://scripts/battle/back_transfer.gd").new(self)
func bind_network() -> void:
	var panel: Node=manager.get_parent().get_node_or_null("Network")
	if panel==null or panel.gameplay==null: return
	router=panel.gameplay;network=panel.network
	network.battle_received.connect(receive)
func connected() -> bool: return network!=null and network.session.state=="connected"
func send(kind: String,data: Dictionary) -> bool:
	return connected() and network.remote_battle and network.send_message({"type":"battle","protocol":1,"session_id":network.session.session_id,"kind":kind,"data":data})
func tell(text: String) -> void: manager.controls.status.text=text
func _process(delta: float) -> void:
	if network==null: bind_network()
	reset.poll()
	if not connected():
		if not transport.is_empty(): transport="";backs.clear()
		return
	if transport!=network.session.session_id:
		transport=network.session.session_id;backs.clear();backs.sent_bytes=0;backs.received_bytes=0
		if network.remote_reset_pending: reset.guard()
	tick+=delta
	if tick>=0.15:
		tick=0
		if router.enabled and not network.quiesced: backs.update()
func receive(frame: Dictionary) -> void:
	if frame.session_id!=network.session.session_id: return
	if frame.kind.begins_with("state_"): saves.receive(frame.kind,frame.data);return
	if frame.kind.begins_with("reset_"): reset.receive(frame.kind,frame.data);return
	if network.quiesced or (router.recovery.suspended and not router.recovery.authenticated): return
	if frame.kind=="nickname":
		network.session.remote_peer.display_name=frame.data.name
		manager.match_controller.model.players.opponent.display_name=frame.data.name
		manager.match_controller.refresh();return
	if frame.kind in ["background","background_edit","background_need","background_chunk","sleeve_request"]:
		manager.appearance.sync.receive(frame.kind,frame.data);return
	backs.receive(frame.kind,frame.data)
func nickname(value: String) -> void:
	if not connected(): return
	network.session.local_peer.display_name=value
	manager.match_controller.model.players.local.display_name=value
	if not router.recovery.context.is_empty(): router.recovery.context.name=value
	send("nickname",{"name":value});manager.match_controller.refresh()
func queue_event(kind: String,payload: Dictionary) -> void:
	if network==null or network.quiesced: return
	deliver_event.call_deferred(kind,payload.duplicate(true),network.match_epoch)
func deliver_event(kind: String,payload: Dictionary,epoch: String) -> void:
	if network!=null and not network.quiesced and network.match_epoch==epoch: router.capture_event(kind,payload)

func _exit_tree() -> void:
	if reset!=null: reset.start.reset=null;reset.session=null
	if backs!=null: backs.session=null
