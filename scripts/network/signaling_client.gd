extends Node
## Rendezvous metadata only; no match reference or gameplay serializer.
signal request_sent(action: String, data: Dictionary)
var service_url: String = ""
var timeout_seconds: float = 6.0
const FIELDS = {"health": [], "lookup": ["code"], "create": ["session_id", "protocol", "app_version", "addresses", "port"], "join": ["code", "protocol", "app_version"], "heartbeat": ["code", "token", "connected"], "resume": ["code", "token"], "relay": ["code", "token"], "close": ["code", "token"]}
func configured() -> bool:
	var endpoint := RegEx.new()
	endpoint.compile("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$|^http://(127\\.0\\.0\\.1|localhost):[0-9]{1,5}/?$")
	return endpoint.search(service_url) != null
func valid_payload(action: String, data: Dictionary) -> bool:
	if not FIELDS.has(action) or data.size() != FIELDS[action].size():
		return false
	for key: String in data:
		if not FIELDS[action].has(key):
			return false
		var value: Variant = data[key]
		match key:
			"session_id", "token":
				if not value is String or value.length() != 32 or not value.is_valid_hex_number(false):
					return false
			"code":
				var expression := RegEx.new()
				expression.compile("^[A-Z]{4}-[0-9]{4}$")
				if not value is String or expression.search(value) == null:
					return false
			"protocol", "port":
				if not value is int or value < (1024 if key == "port" else 1) or value > 65535:
					return false
			"connected":
				if not value is bool:
					return false
			"app_version":
				if not preload("res://scripts/network/network_codec.gd").safe_text(value, 24):
					return false
			"addresses":
				if not value is Array or value.size() > 8:
					return false
				for address: Variant in value:
					if not address is String or not address.is_valid_ip_address():
						return false
	return true
func call_service(action: String, data: Dictionary) -> Dictionary:
	if not configured():
		return {"error": "not_configured"}
	if not valid_payload(action, data):
		return {"error": "invalid_request"}
	for key: String in data:
		if not FIELDS[action].has(key):
			return {"error": "invalid_request"}
	var body: String = JSON.stringify(data)
	if body.length() > 4096:
		return {"error": "invalid_request"}
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	http.body_size_limit = 8192
	http.max_redirects = 0
	add_child(http)
	request_sent.emit(action, data.duplicate(true))
	var error: Error = http.request(service_url.trim_suffix("/") + "/v1/" + action, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		return {"error": "service_unavailable"}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return {"error": "service_unavailable"}
	if not preload("res://scripts/network/network_codec.gd").valid_utf8(result[3]):
		return {"error": "invalid_response"}
	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"error": "invalid_response"}
	return json.data
