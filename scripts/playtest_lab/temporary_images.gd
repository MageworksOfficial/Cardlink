extends Node
## PLAYTEST generic visuals, separate from card/token definitions. Direct LAN only.
const Wire=preload("res://scripts/playtest_lab/image_protocol.gd")
var manager: Node
var assets=preload("res://scripts/custom_table/table_assets.gd").new()
var objects: Dictionary={}
var views: Dictionary={}
var local_ids: Dictionary={}
var network: Node
var session: String=""
var requests: Dictionary={}
var incoming: Dictionary={}
var queue: Array=[]
var picker: FileDialog
var editor: Window
var fields: Dictionary={}
var editing: String=""
func _ready() -> void:
 assets.directory="user://playtest_images"
 picker=FileDialog.new();picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM;picker.filters=PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image files"]);picker.file_selected.connect(spawn);add_child(picker)
 editor=Window.new();editor.title="PLAYTEST Temporary Image";editor.size=Vector2i(400,440);editor.hide();add_child(editor);editor.close_requested.connect(editor.hide)
 var rows:=VBoxContainer.new();rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);editor.add_child(rows)
 for key: String in ["Width","Height","Rotation","Opacity"]:
  var label:=Label.new();label.text=key;rows.add_child(label)
  var field:=SpinBox.new();field.min_value=-360 if key=="Rotation" else (0.05 if key=="Opacity" else 40);field.max_value=360 if key=="Rotation" else (1 if key=="Opacity" else 4000);field.step=0.05 if key=="Opacity" else 1;rows.add_child(field);fields[key]=field
 var lock:=CheckButton.new();lock.text="Lock position";rows.add_child(lock);fields.Lock=lock
 for entry: Array in [["Apply",apply_edit],["Duplicate",func() -> void: duplicate_image(editing)],["Delete",func() -> void: remove(editing);editor.hide()],["Close",editor.hide]]:
  var button:=Button.new();button.text=entry[0];button.pressed.connect(entry[1]);rows.add_child(button)
func connected() -> bool:return network!=null and network.session.state=="connected"
func supported() -> bool:return not connected() or network.room_session==null or not network.room_session.active
func choose() -> void:
 if not supported():manager.controls.status.text="PLAYTEST temporary images require two playtest clients using Advanced LAN/IP. Public relay is unchanged.";return
 picker.popup_centered_ratio(0.7)
func spawn(path: String) -> Dictionary:
 if not supported():return {"error":"Temporary images are LAN-only in this playtest."}
 if objects.size()>=32:return {"error":"Maximum 32 temporary images."}
 var result: Dictionary=assets.ingest(path)
 if result.has("error"):manager.controls.status.text=result.error;return result
 var texture: Texture2D=assets.texture(result.hash);var dimension: Vector2=texture.get_size();dimension*=minf(1,400/maxf(dimension.x,dimension.y));dimension=dimension.max(Vector2(40,40))
 var row: Dictionary={"id":Crypto.new().generate_random_bytes(16).hex_encode(),"hash":result.hash,"position":[500,350],"size":[dimension.x,dimension.y],"rotation":0,"opacity":1.0,"locked":false}
 local_ids[row.id]=true;put(row);return row
func put(row: Dictionary,publish: bool=true) -> bool:
 if not Wire.row(row) or (not objects.has(row.id) and objects.size()>=32):return false
 objects[row.id]=row.duplicate(true)
 if not views.has(row.id):
  var view:=preload("res://scripts/playtest_lab/image_object.gd").new();view.service=self;view.id=row.id;manager.world.add_child(view);views[row.id]=view
 views[row.id].update(row)
 if publish:send("object",row)
 request_images();return true
func change(id: String,changes: Dictionary) -> bool:
 if not objects.has(id) or not supported():return false
 var row: Dictionary=objects[id].duplicate(true)
 for key: String in changes:row[key]=changes[key]
 return put(row)
func duplicate_image(id: String) -> String:
 if not objects.has(id) or not supported():return ""
 var row: Dictionary=objects[id].duplicate(true);row.id=Crypto.new().generate_random_bytes(16).hex_encode();row.position=[row.position[0]+24,row.position[1]+24]
 local_ids[row.id]=true;return row.id if put(row) else ""
func remove(id: String,publish: bool=true) -> void:
 if not objects.has(id):return
 objects.erase(id);local_ids.erase(id)
 if views.has(id):views[id].queue_free();views.erase(id)
 if publish:send("delete",{"id":id})
func edit(id: String) -> void:
 if not objects.has(id):return
 editing=id;var row: Dictionary=objects[id]
 fields.Width.value=row.size[0];fields.Height.value=row.size[1];fields.Rotation.value=row.rotation;fields.Opacity.value=row.opacity;fields.Lock.button_pressed=row.locked;editor.popup_centered()
func apply_edit() -> void:
 change(editing,{"size":[fields.Width.value,fields.Height.value],"rotation":fields.Rotation.value,"opacity":fields.Opacity.value,"locked":fields.Lock.button_pressed})
func send(kind: String,data: Dictionary) -> bool:
 return connected() and supported() and not network.quiesced and network.send_message({"type":"playtest_image","protocol":1,"session_id":network.session.session_id,"kind":kind,"data":data})
func needed(hash: String) -> bool:
 return objects.values().any(func(row: Dictionary) -> bool:return row.hash==hash)
func request_images() -> void:
 if not connected() or not supported():return
 for row: Dictionary in objects.values():
  if requests.size()>=4:break
  if assets.texture(row.hash)==null and not requests.has(row.hash) and send("need",{"hash":row.hash}):requests[row.hash]=Time.get_ticks_msec()
func receive(frame: Dictionary) -> void:
 if not supported() or frame.session_id!=network.session.session_id:return
 var data: Dictionary=frame.data
 match frame.kind:
  "object":
   if put(data,false) and network.session.local_peer.role=="host":send("object",data)
  "delete":
   remove(data.id,false)
   if network.session.local_peer.role=="host":send("delete",data)
  "need":
   if not needed(data.hash) or queue.size()>=4 or assets.texture(data.hash)==null:return
   if queue.any(func(row: Dictionary) -> bool:return row.hash==data.hash):return
   var bytes: PackedByteArray=FileAccess.get_file_as_bytes(assets.path(data.hash))
   if bytes.size()>8388608:return
   queue.append({"hash":data.hash,"bytes":bytes,"offset":0})
  "chunk":
   if not requests.has(data.hash) or not needed(data.hash):return
   if not incoming.has(data.hash):
    if data.offset!=0 or incoming.size()>=4:return
    incoming[data.hash]={"bytes":PackedByteArray(),"total":data.total}
   var entry: Dictionary=incoming[data.hash];var bytes: PackedByteArray=Marshalls.base64_to_raw(data.bytes)
   if entry.bytes.size()!=data.offset or entry.total!=data.total or bytes.is_empty() or bytes.size()>32768 or entry.bytes.size()+bytes.size()>entry.total:incoming.erase(data.hash);requests.erase(data.hash);return
   entry.bytes.append_array(bytes)
   if entry.bytes.size()==entry.total:
    var valid_png: bool=preload("res://scripts/network/card_sync_catalog.gd").png_complete(entry.bytes)
    var result: Dictionary=assets.store(entry.bytes,data.hash) if valid_png else {"error":"Malformed image stream."};incoming.erase(data.hash);requests.erase(data.hash)
    if not result.has("error"):
     for row: Dictionary in objects.values():
      if row.hash==data.hash:views[row.id].update(row)
func _process(_delta: float) -> void:
 var panel: Node=manager.get_parent().get_node_or_null("Network")
 if panel!=null and panel.network!=network:network=panel.network;network.playtest_image_received.connect(receive)
 for view: Control in views.values():view.visible=manager.active and supported()
 if not connected():session="";requests.clear();incoming.clear();queue.clear();return
 if not supported():return
 if session!=network.session.session_id:
  session=network.session.session_id
  for row: Dictionary in objects.values():
   if network.session.local_peer.role=="host" or local_ids.has(row.id):send("object",row)
 for hash: String in requests.keys():
  if Time.get_ticks_msec()-int(requests[hash])>30000:requests.erase(hash);incoming.erase(hash)
 request_images()
 if not queue.is_empty() and network.outgoing.size()<65536:
  var job: Dictionary=queue[0];var count: int=mini(32768,job.bytes.size()-job.offset)
  if send("chunk",{"hash":job.hash,"offset":job.offset,"total":job.bytes.size(),"bytes":Marshalls.raw_to_base64(job.bytes.slice(job.offset,job.offset+count))}):
   job.offset+=count
   if job.offset==job.bytes.size():queue.pop_front()
func capture() -> Array:return objects.values().duplicate(true)
func restore(rows: Array) -> void:
 for id: String in objects.keys():remove(id,false)
 for row: Dictionary in rows:
  local_ids[row.id]=true;put(row,false)
