extends RefCounted
var path: String
var recent: Array = []
var favorites: Array = []
func _init(file: String = "user://deck_preferences.cfg") -> void:
	path = file
	reload()
func reload() -> void:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		recent = clean(config.get_value("decks","recent",[])).slice(0,8)
		favorites = clean(config.get_value("decks","favorites",[])).slice(0,100)
func clean(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for id: Variant in value:
			if id is String and id.length() <= 120 and not result.has(id): result.append(id)
	return result
func used(id: String) -> void:
	reload()
	recent.erase(id)
	recent.push_front(id)
	recent = recent.slice(0,8)
	save()
func toggle(id: String) -> void:
	reload()
	if favorites.has(id): favorites.erase(id)
	elif favorites.size() < 100: favorites.append(id)
	save()
func save() -> void:
	var config := ConfigFile.new()
	config.set_value("decks","recent",recent)
	config.set_value("decks","favorites",favorites)
	preload("res://scripts/card_storage.gd").write_atomic(path,config.encode_to_text().to_utf8_buffer())
func rank(id: String) -> int:
	return -100 if favorites.has(id) else (recent.find(id) if recent.has(id) else 100)
func caption(deck: Dictionary) -> String:
	return ("★ " if favorites.has(deck.deck_id) else "↶ " if recent.has(deck.deck_id) else "")+str(deck.deck_name)
