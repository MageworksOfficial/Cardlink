extends RefCounted
var path: String = "user://player_settings.cfg"
var config := ConfigFile.new()
func _init(file: String = "user://player_settings.cfg") -> void:
	path = file
	config.load(path)
static func clean_name(value: String) -> String:
	var result: String = ""
	for character: String in value.strip_edges():
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127: result += character
	result = result.left(48).strip_edges()
	return "CardLink Player" if result.is_empty() else result
func player_name() -> String:
	config.load(path)
	return clean_name(str(config.get_value("player","name","CardLink Player")))
func get_flag(key: String, fallback: bool = false) -> bool: return bool(config.get_value("preferences",key,fallback))
func save_name(value: String) -> Error:
	config.load(path)
	config.set_value("player","name",clean_name(value))
	return config.save(path)
func set_flag(key: String, value: bool) -> Error:
	config.load(path)
	config.set_value("preferences",key,value)
	return config.save(path)
