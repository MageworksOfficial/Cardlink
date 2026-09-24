extends Node
signal progress(message: String)
const Record = preload("res://scripts/integrations/scryfall_record.gd")
var client: Node
var directory: String = "user://integrations/scryfall"
var rows: Array = []
var updated: String = "Not downloaded"
var cancelled: bool = false
var busy: bool = false
var worker: Thread
func catalog_path() -> String: return directory.path_join("catalog.jsonl")
func load_local() -> void:
	rows.clear(); updated="Not downloaded"
	if not FileAccess.file_exists(catalog_path()): return
	var file := FileAccess.open(catalog_path(),FileAccess.READ)
	if file==null: return
	var header: Variant = JSON.parse_string(file.get_line())
	if not header is Dictionary or header.get("schema")!=1: return
	updated = str(header.get("updated","Unknown"))
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges().is_empty(): continue
		var parser := JSON.new()
		if parser.parse(line)!=OK: continue
		var data: Variant = parser.data
		if data is Dictionary and data.get("faces") is Array: rows.append(data)
func search_local(query: String, exact: bool = false) -> Array:
	var result: Array = []
	for row: Dictionary in rows:
		if Record.same_name(row,query) if exact else str(row.name).to_lower().contains(query.to_lower()):
			result.append(row)
			if result.size()>=100: break
	return result
func update_catalog() -> Dictionary:
	if busy: return {"error":"Catalog update already running."}
	busy=true; cancelled=false
	progress.emit("Checking Scryfall bulk metadata…")
	var response: Dictionary = await client.request(client.API+"/bulk-data/oracle_cards","json","",true)
	if response.has("error"): busy=false; return response
	var descriptor: Dictionary = response.data
	if descriptor.get("type")!="oracle_cards" or not descriptor.get("jsonl_download_uri") is String or int(descriptor.get("compressed_size",0))>96*1024*1024:
		busy=false; return {"error":"Unsupported bulk format or size. Existing catalog kept."}
	if descriptor.get("updated_at")==updated: busy=false; return {"unchanged":true}
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("download.jsonl.gz")
	progress.emit("Downloading metadata only (%d MB). No card images…" % ceili(float(descriptor.get("compressed_size",0))/1048576.0))
	response = await client.request(descriptor.jsonl_download_uri,"bulk",path,true)
	if response.has("error") or cancelled:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		busy=false; return {"error":response.get("error","Cancelled. Existing catalog kept.")}
	progress.emit("Processing catalog locally…")
	worker = Thread.new()
	var error: Error = worker.start(process_bulk.bind(path,str(descriptor.updated_at)))
	if error!=OK: busy=false; worker=null; return {"error":"Cannot start catalog processing."}
	while worker.is_alive(): await get_tree().process_frame
	response = worker.wait_to_finish(); worker=null
	DirAccess.remove_absolute(path)
	if not response.has("error"):
		rows=response.records
		updated=str(descriptor.updated_at)
		response.erase("records")
	busy=false
	return response
func process_bulk(path: String, date: String) -> Dictionary:
	var packed: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if packed.size()<18 or packed[0]!=31 or packed[1]!=139 or packed[2]!=8: return {"error":"Invalid compressed metadata. Existing catalog kept."}
	var bytes: PackedByteArray = packed.decompress_dynamic(512*1024*1024,FileAccess.COMPRESSION_GZIP)
	if bytes.is_empty(): return {"error":"Bulk archive damaged or too large. Existing catalog kept."}
	var text: String = bytes.get_string_from_utf8()
	bytes.clear(); packed.clear()
	var temporary: String = catalog_path()+".pending"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return {"error":"Cannot write catalog. Existing catalog kept."}
	file.store_line(JSON.stringify({"schema":1,"updated":date}))
	var count: int = 0
	var records: Array = []
	var malformed: bool = false
	for line: String in text.split("\n",false):
		if cancelled: break
		var parser := JSON.new()
		if parser.parse(line)!=OK: malformed=true; break
		var parsed: Variant = parser.data
		if not parsed is Dictionary: malformed=true; break
		var row: Dictionary = Record.compact(parsed)
		if row.is_empty(): continue # Image-less records are not importable.
		file.store_line(JSON.stringify(row)); count+=1
		records.append(row)
		if count>200000: malformed=true; break
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if cancelled or malformed or count==0 or write_error!=OK:
		DirAccess.remove_absolute(temporary)
		return {"error":"Catalog update cancelled or invalid. Existing catalog kept."}
	if DirAccess.rename_absolute(temporary,catalog_path())!=OK: return {"error":"Cannot finish catalog update. Existing catalog kept."}
	return {"count":count,"records":records}
func clear() -> void:
	if busy: return
	if FileAccess.file_exists(catalog_path()): DirAccess.remove_absolute(catalog_path())
	rows.clear(); updated="Not downloaded"
func _exit_tree() -> void:
	cancelled=true
	if worker!=null: worker.wait_to_finish()
