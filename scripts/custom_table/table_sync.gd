extends Node
## Table structure and board assets only. Never serializes private pile membership.
var builder: Node
var network: Node
var last_session: String = ""
var applying: bool = false
var send_images: Array = []
var requests: Dictionary = {}
var receiving: Dictionary = {}
var timer: float = 0
func _ready() -> void: builder.structure_changed.connect(local_edit)
func _process(delta: float) -> void:
	timer += delta
	if timer < 0.05: return
	timer = 0
	for request: String in builder.pile_sync.grants.keys():
		if Time.get_ticks_msec() > builder.pile_sync.grants[request]: builder.pile_sync.grants.erase(request)
	var panel: Node = builder.manager.get_parent().get_node_or_null("Network")
	if panel == null: return
	if network != panel.network:
		network = panel.network
		network.table_received.connect(receive)
		builder.pile_sync.network = network
		network.table_received.connect(builder.pile_sync.receive)
	if network.session.state != "connected":
		last_session = ""
		send_images.clear()
		requests.clear()
		receiving.clear()
		return
	if last_session != network.session.session_id:
		last_session = network.session.session_id
		if host() and builder.enabled: send("table",{"table":builder.document})
		builder.pile_sync.counts()
	if not send_images.is_empty() and network.outgoing.size() < 65536:
		var transfer: Dictionary = send_images[0]
		if transfer.bytes.is_empty():
			var file := FileAccess.open(transfer.path,FileAccess.READ)
			if file == null or file.get_length() > 8388608:
				send_images.pop_front()
				return
			transfer.bytes = file.get_buffer(file.get_length())
		var count: int = mini(32768,transfer.bytes.size()-transfer.offset)
		if send("image",{"hash":transfer.hash,"total":transfer.bytes.size(),"offset":transfer.offset,"bytes":Marshalls.raw_to_base64(transfer.bytes.slice(transfer.offset,transfer.offset+count))}):
			transfer.offset += count
			if transfer.offset == transfer.bytes.size(): send_images.pop_front()
func host() -> bool: return network.session.local_peer.role == "host"
func send(kind: String, data: Dictionary) -> bool:
	return network != null and network.session.state == "connected" and network.send_message({"type":"table_structure","protocol":1,"session_id":network.session.session_id,"kind":kind,"data":data})
func local_edit() -> void:
	if applying or not is_instance_valid(network) or network.session.state != "connected" or not builder.enabled: return
	send("table" if host() else "edit",{"table":builder.document})
func needed() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in builder.document.components:
		for key: String in ["asset","back"]:
			if not row[key].is_empty(): result[row[key]] = true
	return result
func receive(message: Dictionary) -> void:
	if message.session_id != network.session.session_id: return
	var data: Dictionary = message.data
	match message.kind:
		"table", "edit":
			if (message.kind == "table" and host()) or (message.kind == "edit" and not host()): return
			applying = true
			# Keep card instances and private ordered lists local when layout changes.
			for old_id: String in builder.orders.keys():
				if builder.Doc.find(data.table,old_id).is_empty(): builder.remove_component(old_id,true)
			builder.enabled = true
			builder.document = data.table.duplicate(true)
			builder.rebuild()
			if builder.manager.appearance!=null and data.table.has("background"): builder.manager.appearance.apply(data.table.background,false)
			applying = false
			if host(): send("table",{"table":builder.document})
			for hash: String in needed():
				if not FileAccess.file_exists(builder.assets.path(hash)) and not requests.has(hash):
					requests[hash] = true
					send("need",{"hash":hash})
		"need":
			if not needed().has(data.hash) or send_images.size() >= 128: return
			for transfer: Dictionary in send_images:
				if transfer.hash == data.hash: return
			var path: String = builder.assets.path(data.hash)
			if FileAccess.file_exists(path):
				var file := FileAccess.open(path,FileAccess.READ)
				if file != null and file.get_length() <= 8388608: send_images.append({"hash":data.hash,"path":path,"bytes":PackedByteArray(),"offset":0})
		"image":
			if not requests.has(data.hash) or not needed().has(data.hash): return
			if not receiving.has(data.hash):
				if data.offset != 0 or receiving.size() >= 4: return
				receiving[data.hash] = {"bytes":PackedByteArray(),"total":data.total}
			var entry: Dictionary = receiving[data.hash]
			var bytes: PackedByteArray = Marshalls.base64_to_raw(data.bytes)
			if entry.bytes.size() != data.offset or entry.total != data.total or bytes.is_empty() or bytes.size() > 32768 or entry.bytes.size()+bytes.size() > entry.total:
				receiving.erase(data.hash)
				requests.erase(data.hash)
				return
			entry.bytes.append_array(bytes)
			if entry.bytes.size() == entry.total:
				var result: Dictionary = builder.assets.store(entry.bytes,data.hash)
				receiving.erase(data.hash)
				requests.erase(data.hash)
				if not result.has("error"): builder.rebuild()
