extends Node
const Doc = preload("res://scripts/custom_table/table_document.gd")
signal structure_changed
var manager: Node
var enabled: bool = false
var document: Dictionary = Doc.fresh()
var orders: Dictionary = {}
var views: Dictionary = {}
var assets = preload("res://scripts/custom_table/table_assets.gd").new()
var storage = preload("res://scripts/custom_table/template_storage.gd").new()
var panel: Window
var pile_sync: Node
var editor: Node
func _ready() -> void:
	pile_sync = preload("res://scripts/custom_table/pile_sync.gd").new()
	pile_sync.builder = self
	add_child(pile_sync)
	storage.assets = assets
	panel = preload("res://scripts/custom_table/component_panel.gd").new()
	panel.builder = self
	add_child(panel)
	var sync := preload("res://scripts/custom_table/table_sync.gd").new()
	sync.builder = self
	add_child(sync)
	editor = preload("res://scripts/custom_table/builder_editor.gd").new()
	editor.builder = self
	add_child(editor)
func local_player(global_id: String) -> String:
	return "local" if global_id == (pile_sync.local_id() if pile_sync.connected() else "player_1") else "opponent"
func global_player(local_id: String) -> String:
	var own: String = pile_sync.local_id() if pile_sync.connected() else "player_1"
	return own if local_id == "local" else ("player_2" if own == "player_1" else "player_1")
func row(id: String) -> Dictionary: return Doc.find(document,id)
func start_blank() -> void:
	enabled = true
	document = Doc.fresh()
	orders.clear()
	for card: Control in manager.cards.duplicate(): manager.match_controller.remove_card(card)
	for zone: Control in manager.zones:
		zone.get_parent().remove_child(zone)
		zone.queue_free()
	manager.zones.clear()
	manager.layout.set_edit_mode(true)
	rebuild()
	manager.match_controller.refresh()
	editor.mark_saved()
	editor.refresh()
func apply_template(data: Dictionary) -> String:
	var error: String = Doc.validate(data)
	if not error.is_empty(): return error
	# Layout changes do not discard existing cards. Return pile contents to the table.
	for card: Control in manager.cards:
		if card.state.custom_metadata.has("table_component"):
			card.state.custom_metadata.erase("table_component")
			card.state.current_zone = "battlefield"
	enabled = true
	document = data.duplicate(true)
	if manager.appearance!=null: manager.appearance.apply(document.get("background",preload("res://scripts/appearance/background_config.gd").defaults()))
	var existing_defaults: Array = template_defaults()
	for item: Dictionary in data.get("defaults",[]):
		var found: int = existing_defaults.find(item)
		if found >= 0:
			existing_defaults.remove_at(found)
			continue
		if item.kind == "counter": manager.extras.create_counter(Vector2(item.position[0],item.position[1]),int(item.value),item.name)
		else:
			var result: Dictionary = manager.create_token(item.name,local_player(item.owner),local_player(item.controller),"",item.power,item.toughness)
			if result.has("card"):
				result.card.position = Vector2(item.position[0],item.position[1])
				result.card.state.position = result.card.position
	orders.clear()
	rebuild()
	manager.match_controller.refresh()
	structure_changed.emit()
	return ""
func add_component(kind: String, owner: String = "table") -> Dictionary:
	var item: Dictionary = Doc.component(kind,owner)
	if kind == "hand" and owner == "table": item.owner = "player_1"
	item.position = [300+(document.components.size()%4)*460,250+(document.components.size()/4)*300]
	var next: Dictionary = document.duplicate(true)
	next.components.append(item)
	var error: String = Doc.validate(next)
	if not error.is_empty(): return {"error":error}
	document = next
	rebuild()
	structure_changed.emit()
	return item
func update_component(id: String, changes: Dictionary) -> bool:
	var next: Dictionary = document.duplicate(true)
	var target: Dictionary = Doc.find(next,id)
	if target.is_empty(): return false
	if pile_sync.connected() and changes.has("owner") and changes.owner != target.owner and (not orders.get(id,[]).is_empty() or pile_sync.remote_counts.get(id,0)>0): return false
	for key: String in changes: target[key] = changes[key]
	if not Doc.validate(next).is_empty(): return false
	document = next
	rebuild()
	structure_changed.emit()
	return true
func remove_component(id: String, confirmed: bool = false) -> bool:
	if not orders.get(id,[]).is_empty() and not confirmed: return false
	for card: Control in manager.cards:
		if card.state.custom_metadata.get("table_component","") == id:
			card.state.custom_metadata.erase("table_component")
			card.state.current_zone = "battlefield"
	orders.erase(id)
	for i: int in range(document.components.size()-1,-1,-1):
		if document.components[i].id == id: document.components.remove_at(i)
	for other: Dictionary in document.components:
		if other.linked_pile == id: other.linked_pile = ""
	rebuild()
	manager.match_controller.refresh()
	structure_changed.emit()
	return true
func rebuild() -> void:
	manager.world.size = Vector2(document.dimensions[0],document.dimensions[1]) if enabled else manager.world.LOGICAL_SIZE
	manager.world.queue_redraw()
	var keep: Dictionary = {}
	for item: Dictionary in document.components:
		keep[item.id] = true
		if not views.has(item.id):
			var view: Control = preload("res://scripts/custom_table/component_view.gd").new()
			view.builder = self
			view.id = item.id
			views[item.id] = view
			manager.world.add_child(view)
		views[item.id].refresh()
	for id: String in views.keys():
		if not keep.has(id):
			views[id].get_parent().remove_child(views[id])
			views[id].queue_free()
			views.erase(id)
	refresh_presentation()
func refresh_presentation() -> void:
	if not enabled: return
	var c: Node = manager.match_controller
	pile_sync.apply_members()
	c.pile_view.hide()
	c.opponent_pile.hide()
	for zone: Control in manager.zones: zone.hide()
	var near: String = c.active_hand_player()
	var far: String = "opponent" if near == "local" else "local"
	c.hand.visible = manager.active and c.hand_open and not c.hands_hidden and hand_available(near)
	c.opponent_hand.visible = manager.active and not c.hands_hidden and hand_available(far)
	if c.hand_window != null and c.hand_window.detached:
		c.hand_window.window.visible = c.hand.visible
	for card: Control in manager.cards:
		var id: String = card.state.custom_metadata.get("table_component","")
		if not id.is_empty():
			var item: Dictionary = row(id)
			if item.is_empty(): continue
			card.visible = manager.active and not item.hidden and not item.kind in ["deck","shared_deck"]
	for view: Control in views.values(): view.refresh()
func hand_available(player: String) -> bool:
	# A layout marker is optional; real drawn cards must never become inaccessible.
	# An explicitly hidden marker still expresses an intentional visibility choice.
	var owner: String = global_player(player)
	var configured: bool = false
	for item: Dictionary in document.components:
		if item.kind == "hand" and item.owner == owner:
			configured = true
			if not item.hidden: return true
	return not configured and manager.match_controller.hidden_count(player,"hand") > 0
func detach(card: Control) -> void:
	for id: String in orders:
		if orders[id].has(card.state.match_instance_id):
			orders[id].erase(card.state.match_instance_id)
			if pile_sync != null: pile_sync.publish_members(id)
	card.state.custom_metadata.erase("table_component")
	if pile_sync != null: pile_sync.counts()
func put_card(card: Control, id: String) -> bool:
	var item: Dictionary = row(id)
	if item.is_empty() or not is_instance_valid(card) or not item.kind in ["deck","shared_deck","hand","discard","zone","leader","shared_area"]: return false
	if pile_sync.connected() and not pile_sync.owns(item):
		if not manager.match_controller.online() or not manager.match_controller.public_sync.state.cards.has(card.state.match_instance_id):
			manager.controls.status.text = "Play or reveal the card before moving it to the other side's pile."
			return false
		return pile_sync.send("place",{"id":id,"card":card.state.match_instance_id})
	if card.state.is_token and item.kind in ["deck","shared_deck","hand","discard"]:
		manager.match_controller.destroy_token(card)
		manager.match_controller.refresh()
		return true
	detach(card)
	if item.kind == "hand": return manager.match_controller.move_card(card,"hand",true,local_player(item.owner))
	for player: RefCounted in manager.match_controller.model.players.values(): player.library.order.erase(card.state.match_instance_id)
	manager.match_controller.transitioning = true
	manager.assign_zone(card,null)
	manager.match_controller.transitioning = false
	card.state.custom_metadata["table_component"] = id
	card.state.current_zone = "custom_pile" if item.kind in ["deck","shared_deck"] else "battlefield"
	card.state.visibility = "owner_private" if item.visibility == "private" else "public"
	card.state.face_down = item.visibility == "private" and not card.state.custom_metadata.get("public_reveal",false)
	card.position = Vector2(item.position[0]+20,item.position[1]+40)
	card.state.position = card.position
	if not orders.has(id): orders[id] = []
	orders[id].append(card.state.match_instance_id)
	card.state.zone_player_id = "local" if pile_sync.connected() else card.state.zone_player_id
	pile_sync.counts()
	pile_sync.publish_members(id)
	manager.match_controller.refresh()
	return true
func draw(id: String, player: String) -> bool:
	if pile_sync.connected(): return pile_sync.draw(id,player)
	if orders.get(id,[]).is_empty(): return false
	var card: Control = manager.match_controller.card_by_id(orders[id][0])
	if card == null: return false
	if manager.match_controller.playtest.network_busy(): return false
	detach(card)
	return manager.match_controller.move_card(card,"hand",true,"local" if player == "player_1" else "opponent")
func shuffle(id: String) -> void:
	if pile_sync.connected() and not pile_sync.owns(row(id)):
		pile_sync.send("shuffle",{"id":id})
		return
	if not orders.has(id): return
	orders[id].shuffle()
	for card_id: String in orders[id]:
		var card: Control = manager.match_controller.card_by_id(card_id)
		if card != null: manager.match_controller.visibility.set_public_reveal(card.state,false)
	manager.match_controller.record_event("shuffle","Shuffled "+str(row(id).get("name","pile")))
	manager.match_controller.refresh()
func load_deck(id: String, deck: Dictionary) -> String:
	var deck_error: String = preload("res://scripts/deck_storage.gd").validate(deck)
	if not deck_error.is_empty(): return deck_error
	if pile_sync.connected() and not pile_sync.owns(row(id)): return "The player holding this pile loads its cards. The host holds shared piles."
	var item: Dictionary = row(id)
	if item.is_empty() or not item.kind in ["deck","shared_deck"]: return "Choose a deck/pile."
	var catalog: Dictionary = {}
	for record: Dictionary in manager.match_controller.loader.load_records(): catalog[str(record.metadata.get("card_id",""))] = record
	for entry: Dictionary in deck.get("cards",[]):
		if not catalog.has(entry.card_id): return "A card in this deck is missing from the collection."
	if deck.has("deck_back"): manager.deck_backs.piles[id]=deck.deck_back.duplicate(true)
	else: manager.deck_backs.piles.erase(id)
	for entry: Dictionary in deck.get("cards",[]):
		for _i: int in int(entry.quantity):
			var result: Dictionary = manager.spawn_definition(catalog[entry.card_id],false)
			if result.has("error"): return result.error
			if deck.has("deck_back"): result.card.state.custom_metadata["deck_back"]=deck.deck_back.duplicate(true)
			result.card.state.custom_metadata["sleeve_source"]=id
			result.card.state.owner_player_id = local_player(item.owner) if item.owner != "table" else "local"
			result.card.state.controller_player_id = result.card.state.owner_player_id
			put_card(result.card,id)
			manager.match_controller.model.players.local.loaded_ids.append(result.card.state.match_instance_id)
		var descriptor: Dictionary = preload("res://scripts/network/card_sync_catalog.gd").descriptor(catalog[entry.card_id].metadata)
		if not manager.match_controller.model.players.local.deck_manifest.has(descriptor): manager.match_controller.model.players.local.deck_manifest.append(descriptor)
	manager.match_controller.model.players.local.deck_name = "Custom table piles"
	pile_sync.counts()
	if manager.battle!=null: manager.battle.reset.start.remember("pile",id,deck,false)
	return ""
func capture_template_defaults() -> void:
	document["defaults"] = template_defaults()
func template_defaults() -> Array:
	var defaults: Array = []
	for item: Control in manager.extras.counters:
		defaults.append({"kind":"counter","name":item.caption,"position":[item.position.x,item.position.y],"value":item.value,"power":"","toughness":"","owner":"player_1","controller":"player_1"})
	for card: Control in manager.cards:
		if card.state.is_token:
			defaults.append({"kind":"token","name":card.state.display_name,"position":[card.position.x,card.position.y],"value":0,"power":str(card.state.custom_metadata.get("power","")),"toughness":str(card.state.custom_metadata.get("toughness","")),"owner":global_player(card.state.owner_player_id),"controller":global_player(card.state.controller_player_id)})
	return defaults
func capture() -> Dictionary:
	return {"enabled":enabled,"table":document.duplicate(true),"orders":orders.duplicate(true)}
static func validate_saved(data: Variant) -> String:
	if not data is Dictionary or data.size() != 3 or not data.get("enabled") is bool or not data.get("orders") is Dictionary: return "Invalid custom table save."
	var error: String = Doc.validate(data.get("table"))
	if not error.is_empty(): return error
	var seen: Dictionary = {}
	for id: Variant in data.orders:
		if not id is String or Doc.find(data.table,id).is_empty() or not data.orders[id] is Array or data.orders[id].size() > 5000: return "Invalid custom pile."
		for card_id: Variant in data.orders[id]:
			if not card_id is String or card_id.length() > 100 or seen.has(card_id): return "Invalid custom pile member."
			seen[card_id] = true
	return ""
func restore(data: Dictionary) -> void:
	enabled = data.get("enabled",false)
	document = data.get("table",Doc.fresh()).duplicate(true)
	orders = data.get("orders",{}).duplicate(true)
	rebuild()
func _unhandled_key_input(event: InputEvent) -> void:
	if not enabled or not manager.active: return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_F:
		if manager.get_parent().app_shell!=null: manager.get_parent().app_shell.function_search.open()
		else: editor.focus_search()
		get_viewport().set_input_as_handled()

# Primary designation uses the existing validated pile link: a draw pile links to itself.
func primary_for(player: String) -> String:
	var owned: Array[String] = []
	var primary: Array[String] = []
	var shared: Array[String] = []
	for item: Dictionary in document.components:
		if not item.kind in ["deck","shared_deck"]: continue
		if item.owner == player:
			owned.append(item.id)
			if item.linked_pile == item.id: primary.append(item.id)
		if item.owner == "table" and item.linked_pile == item.id: shared.append(item.id)
	if not primary.is_empty(): return primary[0] if primary.size() == 1 else ""
	if not shared.is_empty(): return shared[0] if shared.size() == 1 else ""
	return owned[0] if owned.size() == 1 else ""
func missing_source(action: String, player: String) -> String:
	for item: Dictionary in document.components:
		if item.kind in ["deck","shared_deck"] and item.owner in [player,"table"]:
			return "Choose a pile to "+action+". Right-click it → Set as Primary Draw Pile / Use as Shared Draw Source."
	return "No draw pile is assigned for "+player.replace("player_","Player ")+"."
func shuffle_active() -> bool:
	var player: String = global_player(manager.match_controller.model.active_player)
	var source: String = primary_for(player)
	if source.is_empty():
		manager.controls.status.text = missing_source("shuffle",player)
		return false
	shuffle(source)
	manager.controls.status.text = player.replace("player_","Player ")+" shuffled "+str(row(source).name)+"."
	return true
func set_primary(id: String) -> bool:
	var item: Dictionary = row(id)
	if item.is_empty() or not item.kind in ["deck","shared_deck"]: return false
	var next: Dictionary = document.duplicate(true)
	for other: Dictionary in next.components:
		if other.kind in ["deck","shared_deck"] and (item.owner == "table" or other.owner in [item.owner,"table"]):
			other.linked_pile = other.id if other.id == id else ""
	if not Doc.validate(next).is_empty(): return false
	document = next
	rebuild()
	structure_changed.emit()
	return true
func draw_active() -> bool:
	var player: String = global_player(manager.match_controller.model.active_player)
	var source: String = primary_for(player)
	if source.is_empty():
		manager.controls.status.text = missing_source("draw",player)
		return false
	var success: bool = draw(source,player)
	manager.controls.status.text = ("Draw → "+player.replace("player_","Player ")) if success else "Primary draw pile is empty or unavailable."
	return success
