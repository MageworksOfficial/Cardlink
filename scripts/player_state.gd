extends RefCounted
const Pile = preload("res://scripts/library_pile.gd")
var player_id: String
var display_name: String
var life: int = 40
var library = Pile.new()
var hand: Array[String] = []
var graveyard: Array[String] = []
var exile: Array[String] = []
var leaders: Array[String] = []
var battlefield: Array[String] = []
var loaded_ids: Array[String] = []
var deck_manifest: Array = []
var deck_name: String = "No deck loaded"
func _init(id: String = "local", caption: String = "Local player") -> void:
	player_id = id
	display_name = caption
func to_data() -> Dictionary:
	return {"player_id": player_id, "display_name": display_name, "life": life,
		"library_order": library.order.duplicate(), "hand": hand.duplicate(),
		"graveyard": graveyard.duplicate(), "exile": exile.duplicate(),
		"leaders": leaders.duplicate(), "battlefield": battlefield.duplicate(),
		"loaded_ids": loaded_ids.duplicate(), "deck_name": deck_name, "deck_manifest": deck_manifest.duplicate(true)}
