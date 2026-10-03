extends RefCounted
## Deployment configuration only. Never reads gameplay endpoint settings.
var update_service_url: String = ""
var github_repository: String = ""
var server_directory_url: String = ""
func _init(path: String = "res://config/update.cfg") -> void:
	var config:=ConfigFile.new()
	if config.load(path)==OK:
		update_service_url=str(config.get_value("updates","update_service_url",""))
		github_repository=str(config.get_value("updates","github_repository",""))
		server_directory_url=str(config.get_value("directory","server_directory_url",""))
	# Operator/test override is independent of any selected gameplay server.
	if OS.has_environment("CARDLINK_UPDATE_SERVICE_URL"):
		update_service_url=OS.get_environment("CARDLINK_UPDATE_SERVICE_URL")
func releases_url() -> String:
	return "https://github.com/"+github_repository+"/releases" if github_repository.count("/")==1 and not github_repository.contains("..") else ""
