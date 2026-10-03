extends RefCounted
const Back = preload("res://scripts/battle/deck_back.gd")
var session: Node
const SESSION_BUDGET = 64*1024*1024
var sent_bytes: int = 0
var received_bytes: int = 0
var sending: Array = []
var requests: Dictionary = {}
var receiving: Dictionary = {}
var sent_signature: String = ""
func _init(owner: Node) -> void: session=owner
func hashes(config: Dictionary) -> Dictionary:
	var result: Dictionary={}
	var values: Array=[config.get("library",{})]+config.get("hand",[])+config.get("piles",{}).values()
	for value: Dictionary in values:
		if value.get("type")=="image" and not value.asset.is_empty(): result[value.asset]=true
	return result
func update() -> void:
	var own: Dictionary=session.manager.deck_backs.public_config()
	var signature: String=JSON.stringify(own)
	if signature!=sent_signature and session.send("backs",own): sent_signature=signature
	var need: Dictionary=hashes(session.manager.deck_backs.remote)
	need.merge(hashes(own))
	for card: Control in session.manager.cards:
		var back: Dictionary=card.state.custom_metadata.get("deck_back",{})
		if back.get("type")=="image": need[back.asset]=true
	for key: String in requests.keys():
		if FileAccess.file_exists(Back.path(key)) or not need.has(key): requests.erase(key);receiving.erase(key)
	for hash_value: String in need:
		if FileAccess.file_exists(Back.path(hash_value)): continue
		if requests.has(hash_value) and Time.get_ticks_msec()-requests[hash_value]<15000: continue
		if requests.size()>=32 or received_bytes>=SESSION_BUDGET: break
		if session.send("back_need",{"hash":hash_value}):
			requests[hash_value]=Time.get_ticks_msec();receiving.erase(hash_value)
	if not sending.is_empty() and sent_bytes<SESSION_BUDGET and session.network.outgoing.size()<65536:
		var transfer: Dictionary=sending[0]
		var count: int=mini(32768,transfer.bytes.size()-transfer.offset)
		if session.send("back_chunk",{"hash":transfer.hash,"total":transfer.bytes.size(),"offset":transfer.offset,"bytes":Marshalls.raw_to_base64(transfer.bytes.slice(transfer.offset,transfer.offset+count))}):
			transfer.offset+=count;sent_bytes+=count
			if transfer.offset==transfer.bytes.size(): sending.pop_front()
func receive(kind: String, data: Dictionary) -> void:
	if kind=="backs": session.manager.deck_backs.receive(data);return
	if kind=="back_need":
		var permitted: Dictionary=hashes(session.manager.deck_backs.public_config())
		if session.manager.appearance!=null: permitted.merge(session.manager.appearance.sleeves.offered)
		for card: Control in session.manager.cards:
			var value: Dictionary=card.state.custom_metadata.get("deck_back",{})
			if value.get("type")=="image": permitted[value.asset]=true
		if not permitted.has(data.hash) or sending.size()>=4: return
		var file := FileAccess.open(Back.path(data.hash),FileAccess.READ)
		if file==null or file.get_length()>Back.MAX_BYTES: return
		var bytes: PackedByteArray=file.get_buffer(file.get_length())
		if Back.digest(bytes)!=data.hash: return
		for transfer: Dictionary in sending:
			if transfer.hash==data.hash: return
		sending.append({"hash":data.hash,"bytes":bytes,"offset":0})
	elif kind=="back_chunk":
		if not requests.has(data.hash) or received_bytes>=SESSION_BUDGET: return
		var chunk: PackedByteArray=Marshalls.base64_to_raw(data.bytes)
		if chunk.is_empty() or chunk.size()>32768: return
		received_bytes+=chunk.size()
		if not receiving.has(data.hash):
			if data.offset!=0 or receiving.size()>=4: return
			receiving[data.hash]={"bytes":PackedByteArray(),"total":int(data.total)}
		var row: Dictionary=receiving[data.hash]
		if row.total!=int(data.total) or row.bytes.size()!=int(data.offset) or row.bytes.size()+chunk.size()>row.total:
			receiving.erase(data.hash);requests.erase(data.hash);return
		row.bytes.append_array(chunk)
		if row.bytes.size()==row.total:
			var result: Dictionary=Back.store(row.bytes,data.hash)
			receiving.erase(data.hash);requests.erase(data.hash)
			if not result.has("error"): session.manager.match_controller.refresh()
func clear() -> void:
	sending.clear();requests.clear();receiving.clear();sent_signature=""
