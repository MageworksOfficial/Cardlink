extends "res://scripts/integrations/catalog_provider.gd"
## One queue per application; never routes through the CardLink server.
class Ticket extends RefCounted:
	signal finished(result: Dictionary)
	var url: String
	var kind: String
	var target: String
const API = "https://api.scryfall.com"
const SPACING = 0.65
const HEADERS = ["User-Agent: CardLink/7.8 (optional open-source tabletop catalog)","Accept: application/json;q=0.9,*/*;q=0.8"]
var enabled: bool = false
var cache = preload("res://scripts/integrations/catalog_cache.gd").new()
var queue: Array = []
var active: Ticket
var http: HTTPRequest
var next_start: float = 0
var cooldown: float = 0
var request_count: int = 0
var starts: Array[float] = []
func _ready() -> void:
	http = HTTPRequest.new()
	http.use_threads = true
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(completed)
static func allowed(url: String, kind: String) -> bool:
	if kind=="json": return url.begins_with(API+"/cards/") or url.begins_with(API+"/bulk-data")
	if kind=="bulk": return url.begins_with("https://data.scryfall.io/") and url.ends_with(".jsonl.gz")
	return url.begins_with("https://cards.scryfall.io/")
func request(url: String, kind: String = "json", target: String = "", fresh: bool = false) -> Dictionary:
	if not enabled: return {"error":"Online MTG Catalog is disabled. Enable it in Integrations."}
	if not allowed(url,kind): return {"error":"Provider returned an unsupported address."}
	if not fresh and kind in ["json","thumb"]:
		var bytes: PackedByteArray = cache.get_bytes(url)
		if not bytes.is_empty(): return decode(bytes,kind)
	if Time.get_ticks_msec()/1000.0<cooldown: return {"error":"Too many requests. Please wait before trying again.","status":429}
	if queue.size()>=128: return {"error":"Request queue full. Please wait."}
	var ticket := Ticket.new()
	ticket.url = url; ticket.kind = kind; ticket.target = target
	queue.append(ticket)
	return await ticket.finished
func _process(_delta: float) -> void:
	if active!=null or queue.is_empty(): return
	if Time.get_ticks_msec()/1000.0<maxf(next_start,cooldown): return
	active = queue.pop_front()
	http.download_file = active.target
	http.timeout = 180 if active.kind=="bulk" else 30
	http.body_size_limit = 96*1024*1024 if active.kind=="bulk" else 8*1024*1024
	next_start = Time.get_ticks_msec()/1000.0+SPACING
	starts.append(Time.get_ticks_msec()/1000.0)
	if starts.size()>32: starts.pop_front()
	request_count += 1
	var error: Error = http.request(active.url,PackedStringArray(HEADERS))
	if error!=OK: finish({"error":"Scryfall request could not start."})
static func decode(bytes: PackedByteArray, kind: String) -> Dictionary:
	if kind!="json": return {"bytes":bytes}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK: return {"error":"Invalid provider response."}
	return {"data":parser.data} if parser.data is Dictionary else {"error":"Invalid provider response."}
func completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if active==null: return
	if code==429:
		var delay: float = 30
		for line: String in headers:
			if line.to_lower().begins_with("retry-after:"):
				var value: String = line.substr(12).strip_edges()
				if value.is_valid_float(): delay = maxf(delay,value.to_float())
				else: delay=maxf(delay,http_date_delay(value))
		cooldown = Time.get_ticks_msec()/1000.0+delay
		finish({"error":"Too many requests. Please wait at least %d seconds; no automatic retry." % int(delay),"status":429})
		cancel_pending()
		return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		finish({"error":"No exact match or printing found. Review or skip this entry." if code==404 else "Scryfall is unavailable or the download failed. Try again later.","status":code})
		return
	if active.kind=="bulk": finish({"path":active.target}); return
	var answer: Dictionary = decode(body,active.kind)
	if not answer.has("error") and active.kind in ["json","thumb"]: cache.put_bytes(active.url,body)
	finish(answer)
static func http_date_delay(value: String) -> float:
	var parts: PackedStringArray = value.split(" ",false)
	var months: Array = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
	if parts.size()!=6 or not parts[2] in months: return 30
	var date: String="%s-%02d-%02dT%s" % [parts[3],months.find(parts[2])+1,int(parts[1]),parts[4]]
	return maxf(30,Time.get_unix_time_from_datetime_string(date)-Time.get_unix_time_from_system())
func finish(result: Dictionary) -> void:
	var ticket: Ticket = active
	active = null
	if ticket!=null: ticket.finished.emit(result)
func cancel_pending() -> void:
	var old: Array = queue.duplicate()
	queue.clear()
	for ticket: Ticket in old: ticket.finished.emit({"error":"Cancelled.","cancelled":true})
func cancel() -> void:
	cancel_pending()
	if active!=null:
		http.cancel_request()
		finish({"error":"Cancelled.","cancelled":true})
func search(query: String, page: int = 1) -> Dictionary:
	if query.strip_edges().is_empty(): return {"error":"Enter a card name."}
	return await request(API+"/cards/search?q="+query.uri_encode()+"&unique=cards&order=name&page="+str(clampi(page,1,100)))
func search_sorted(query: String, page: int = 1, order: String = "name") -> Dictionary:
	if not order in preload("res://scripts/integrations/scryfall_query.gd").SORTS: return {"error":"Unsupported sort order."}
	if query.strip_edges().is_empty(): return {"error":"Enter a name or choose filters."}
	return await request(API+"/cards/search?q="+query.uri_encode()+"&unique=cards&order="+order+"&page="+str(clampi(page,1,100)))
func resolve_card(entry: Dictionary) -> Dictionary:
	if not str(entry.get("set_code","")).is_empty() and not str(entry.get("collector_number","")).is_empty():
		return await request(API+"/cards/"+str(entry.set_code).to_lower().uri_encode()+"/"+str(entry.collector_number).uri_encode())
	return await request(API+"/cards/named?exact="+str(entry.name).uri_encode())
func get_printings(card: Dictionary, page: int = 1) -> Dictionary:
	return await request(API+"/cards/search?q="+("oracleid:"+str(card.get("oracle_id",""))).uri_encode()+"&unique=prints&order=released&dir=desc&page="+str(clampi(page,1,100)))
func fetch_metadata(id: String) -> Dictionary: return await request(API+"/cards/"+id.uri_encode())
func fetch_image(url: String, thumbnail: bool = false) -> Dictionary: return await request(url,"thumb" if thumbnail else "image")
