extends Node
## Public appearance only. Host sequences concurrent cosmetic edits, not gameplay.
var appearance: Node
var pending: bool=false
var elapsed: float=0
var chunk_elapsed: float=0
var session_id: String=""
var sending: Array=[]
var receiving: Dictionary={}
var requested: String=""
var request_time: int=0
var sent_bytes: int=0
var received_bytes: int=0
const BUDGET=64*1024*1024
func battle() -> Node: return appearance.manager.battle
func active() -> bool: return battle().connected() and battle().router.enabled and not battle().network.quiesced and not (battle().router.recovery.suspended and not battle().router.recovery.authenticated)
func host() -> bool: return battle().network.session.local_peer.role=="host"
func publish() -> void: pending=true
func _process(delta: float) -> void:
	if not active():
		if not session_id.is_empty(): session_id="";sending.clear();receiving.clear();requested="";appearance.sleeves.request={};appearance.sleeves.approval.hide()
		return
	if session_id!=battle().network.session.session_id:
		session_id=battle().network.session.session_id;sent_bytes=0;received_bytes=0;pending=host()
	elapsed+=delta;chunk_elapsed+=delta
	if pending or (host() and elapsed>=3):
		if battle().send("background" if host() else "background_edit",appearance.background): pending=false;elapsed=0
	var hash: String=appearance.background.asset if appearance.background.type=="image" else ""
	if not hash.is_empty() and not FileAccess.file_exists(appearance.assets.path(hash)) and received_bytes<BUDGET:
		if requested!=hash or Time.get_ticks_msec()-request_time>15000:
			requested=hash;request_time=Time.get_ticks_msec();receiving.clear();battle().send("background_need",{"hash":hash});appearance.tell("Syncing table background...")
	elif requested!="": requested="";receiving.clear()
	if chunk_elapsed>=0.05 and not sending.is_empty() and sent_bytes<BUDGET and battle().network.outgoing.size()<65536:
		chunk_elapsed=0
		var row: Dictionary=sending[0];var n: int=mini(32768,row.bytes.size()-row.offset)
		if battle().send("background_chunk",{"hash":row.hash,"total":row.bytes.size(),"offset":row.offset,"bytes":Marshalls.raw_to_base64(row.bytes.slice(row.offset,row.offset+n))}):
			row.offset+=n;sent_bytes+=n
			if row.offset==row.bytes.size(): sending.pop_front()
func receive(kind: String,data: Dictionary) -> void:
	if not active(): return
	match kind:
		"sleeve_request": appearance.sleeves.receive(data)
		"background","background_edit":
			if (kind=="background" and host()) or (kind=="background_edit" and not host()): return
			appearance.apply(data,false)
			if host(): pending=true
		"background_need":
			if appearance.background.type!="image" or data.hash!=appearance.background.asset or sending.size()>=2 or sent_bytes>=BUDGET: return
			for row: Dictionary in sending:
				if row.hash==data.hash: return
			var file:=FileAccess.open(appearance.assets.path(data.hash),FileAccess.READ)
			if file==null or file.get_length()>appearance.assets.MAX_BYTES: return
			sending.append({"hash":data.hash,"bytes":file.get_buffer(file.get_length()),"offset":0})
		"background_chunk":
			if data.hash!=requested or data.hash!=appearance.background.asset or received_bytes>=BUDGET: return
			var bytes: PackedByteArray=Marshalls.base64_to_raw(data.bytes);received_bytes+=bytes.size()
			if receiving.is_empty():
				if data.offset!=0: return
				receiving={"bytes":PackedByteArray(),"total":int(data.total)}
			if int(data.offset)!=receiving.bytes.size() or int(data.total)!=receiving.total or receiving.bytes.size()+bytes.size()>receiving.total: receiving.clear();requested="";return
			receiving.bytes.append_array(bytes)
			if receiving.bytes.size()==receiving.total:
				var result: Dictionary=appearance.assets.store(receiving.bytes,data.hash);receiving.clear();requested=""
				if not result.has("error"): appearance.refresh();appearance.tell("Background changed.")
