extends Node
## Independent HTTP metadata client; no gameplay, relay or match references.
signal changed
signal completed
const Manifest = preload("res://scripts/updater/update_manifest.gd")
const FRESH_SECONDS: float = 14400.0
var config = preload("res://scripts/updater/update_config.gd").new()
var installed_version: String = preload("res://scripts/frontend/app_info.gd").UPDATE_VERSION
var cache_path: String = "user://updates/manifest.json"
var manifest: Dictionary = {}
var checked_at: float = 0
var state: String = "unavailable"
var detail: String = "Update status unavailable."
var cached: bool = false
var busy: bool = false
var last_attempt: float = 0
var request: HTTPRequest
var allow_loopback_for_tests: bool = false
func _ready() -> void:
	request=HTTPRequest.new();request.timeout=8;request.body_size_limit=Manifest.MAX_BYTES;request.max_redirects=0
	add_child(request);request.request_completed.connect(receive)
	load_cache()
	check_now.call_deferred()
func now() -> float: return Time.get_unix_time_from_system()
func fresh() -> bool:
	var age: float=now()-checked_at
	return not manifest.is_empty() and age>=-300 and age<FRESH_SECONDS
func load_cache() -> void:
	if not FileAccess.file_exists(cache_path): return
	var file:=FileAccess.open(cache_path,FileAccess.READ)
	if file==null or file.get_length()>Manifest.MAX_BYTES: return
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK: return
	var value: Variant=parser.data
	if not value is Dictionary or value.get("endpoint")!=config.update_service_url: return
	if not value.get("checked_at") is float and not value.get("checked_at") is int: return
	if not Manifest.validate(value.get("manifest"),config.github_repository).is_empty(): return
	checked_at=float(value.checked_at)
	if not is_finite(checked_at) or checked_at>now()+300: checked_at=0;return
	manifest=Manifest.public_fields(value.manifest);cached=true
func classify() -> String:
	if Manifest.compare(installed_version,manifest.minimum_online_version)<0: return "required"
	return "available" if Manifest.compare(installed_version,manifest.latest_version)<0 else "current"
func check_now() -> void:
	if busy: return
	last_attempt=now();busy=true;state="checking";detail="Checking for updates…";changed.emit()
	var url: String=config.update_service_url
	var local_test: bool=allow_loopback_for_tests and url.begins_with("http://127.0.0.1:")
	if not Manifest.https_url(url) and not local_test:
		failed("Update service is not configured with a valid HTTPS endpoint.");return
	# Default HTTPRequest TLS verifies both hostname and trust chain. No bypass.
	if request.request(url,PackedStringArray(["Accept: application/json"]))!=OK: failed("Unable to start the update check.")
func failed(message: String) -> void:
	busy=false
	if fresh(): state=classify();cached=true;detail=message+" Using a recent cached check."
	else: state="unavailable";detail=message+" Online and offline startup remain available."
	changed.emit();completed.emit()
func receive(result: int,code: int,_headers: PackedStringArray,body: PackedByteArray) -> void:
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200: failed("Update status unavailable.");return
	if body.size()>Manifest.MAX_BYTES: failed("Update manifest is too large.");return
	var parser:=JSON.new()
	if parser.parse(body.get_string_from_utf8())!=OK: failed("Update manifest contains invalid JSON.");return
	var data: Variant=parser.data
	var error: String=Manifest.validate(data,config.github_repository)
	if not error.is_empty(): failed("Update manifest could not be validated. "+error);return
	manifest=Manifest.public_fields(data);checked_at=now();cached=false;busy=false;state=classify();detail="Checked with the independent Update Service."
	var value: Dictionary={"endpoint":config.update_service_url,"checked_at":checked_at,"manifest":manifest}
	preload("res://scripts/card_storage.gd").write_atomic(cache_path,JSON.stringify(value).to_utf8_buffer())
	changed.emit();completed.emit()
func online_allowed() -> bool:
	if busy: await completed
	elif not fresh() and now()-last_attempt>=30:
		check_now()
		if busy: await completed
	# Old required responses cannot indefinitely retire clients while offline.
	return not (fresh() and classify()=="required")
func asset() -> Dictionary:
	var platform: String="macos-universal" if OS.get_name()=="macOS" else ("windows-x86_64" if OS.get_name()=="Windows" else "linux-x86_64")
	return manifest.get("assets",{}).get(platform,{})
