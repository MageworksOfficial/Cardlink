extends Node
const Back = preload("res://scripts/battle/deck_back.gd")
var manager: Node
var piles: Dictionary = {}
var remote: Dictionary = {"library":{},"hand":[],"piles":{}}
func library_config(player: String) -> Dictionary:
	var c: Node=manager.match_controller
	if player=="opponent" and c.online(): return remote.library
	var order: Array=c.model.players[player].library.order
	if not order.is_empty():
		var card: Control=c.card_by_id(order[0])
		if card!=null and card.state.custom_metadata.get("deck_back") is Dictionary: return card.state.custom_metadata.deck_back
	return c.model.players[player].deck_back
func library_texture(player: String) -> Texture2D:
	var value: Dictionary=library_config(player)
	return Back.texture(value) if not value.is_empty() else manager.backs.texture()
func hand_textures(player: String) -> Array:
	var c: Node=manager.match_controller
	var result: Array=[]
	if player=="opponent" and c.online():
		for value: Dictionary in remote.hand: result.append(Back.texture(value) if not value.is_empty() else manager.backs.texture())
	else:
		for id: String in c.model.players[player].hand:
			var card: Control=c.card_by_id(id)
			result.append(Back.for_card(card,manager.backs) if card!=null else manager.backs.texture())
	return result
func pile_config(id: String) -> Dictionary:
	var order: Array=manager.custom_table.orders.get(id,[])
	if not order.is_empty():
		var card: Control=manager.match_controller.card_by_id(order[0])
		if card!=null and card.state.custom_metadata.get("deck_back") is Dictionary: return card.state.custom_metadata.deck_back
	return piles.get(id,{})
func pile_texture(id: String) -> Texture2D:
	var b: Node=manager.custom_table
	var value: Dictionary=remote.piles.get(id,{}) if b.pile_sync.connected() and not b.pile_sync.owns(b.row(id)) else pile_config(id)
	return Back.texture(value) if not value.is_empty() else manager.backs.texture()
func public_config() -> Dictionary:
	var result: Dictionary={"library":library_config("local").duplicate(true),"hand":[],"piles":{}}
	var c: Node=manager.match_controller
	for id: String in c.model.players.local.hand:
		var card: Control=c.card_by_id(id)
		result.hand.append(card.state.custom_metadata.get("deck_back",{}).duplicate(true) if card!=null else {})
	for id: String in piles:
		var row: Dictionary=manager.custom_table.row(id)
		if not row.is_empty() and (not manager.custom_table.pile_sync.connected() or manager.custom_table.pile_sync.owns(row)): result.piles[id]=pile_config(id).duplicate(true)
	return result
func receive(value: Dictionary) -> void:
	remote=value.duplicate(true);manager.match_controller.refresh()
