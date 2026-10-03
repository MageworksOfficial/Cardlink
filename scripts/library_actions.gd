extends RefCounted
## Sandbox operations share one zone-move path and one ordered pile API.
var controller: Node
func _init(owner: Node) -> void:
	controller = owner
func put_nth(card: Control, player: String, n: int, from_bottom: bool = false) -> bool:
	if card == null or n < 1 or not controller.model.players.has(player):
		return false
	if controller.online():
		player = "local" if card.state.zone_player_id == "local" and card.state.current_zone in ["hand","library"] else card.state.owner_player_id
		if player != "local":
			controller.manager.controls.status.text = "Use Top/Bottom for a remote owner; private indexed placement comes later."
			return false
	if not controller.move_card(card, "library", true, player):
		return false
	if not controller.manager.cards.has(card):
		return true
	controller.model.players[player].library.insert_nth(card.state.match_instance_id, n, from_bottom)
	controller.refresh()
	return true
func draw_n(player: String, n: int) -> int:
	return move_top_n(player, n, "hand")
func mill_n(player: String, n: int) -> int:
	return move_top_n(player, n, "graveyard")
func move_top_n(player: String, n: int, kind: String) -> int:
	if not controller.model.players.has(player) or n < 1:
		return 0
	if controller.online() and player != "local": return 0
	var ids: Array[String] = controller.model.players[player].library.peek(n)
	var moved: int = 0
	controller.batching = true
	for id: String in ids:
		if not controller.move_card(controller.card_by_id(id), kind, true, player):
			break
		moved += 1
	controller.batching = false
	controller.refresh()
	controller.manager.controls.status.text = "%d card(s) moved to %s %s." % [moved, player, kind]
	return moved
func duplicate_token(source: Control) -> Dictionary:
	if source == null:
		return {"error": "Select a card first."}
	# A deliberate copy action may preserve hidden identity internally, never expose it.
	var result: Dictionary = controller.manager.create_token(source.state.display_name, source.state.owner_player_id, source.state.controller_player_id, source.state.image_path)
	if result.has("card"):
		var token: Control = result.card
		token.state.custom_metadata = source.state.custom_metadata.duplicate(true)
		token.state.counters = source.state.counters.duplicate(true)
		token.set_tapped(source.state.tapped)
		token.update_counters()
		token.position = source.position + Vector2(24, 24)
		token.state.position = token.position
		token.set_face_down(source.state.face_down or not controller.visibility.can_present(source.state, "local"))
		controller.refresh()
	return result

func mill_bottom(player: String, n: int) -> int:
	if not controller.model.players.has(player) or n<1: return 0
	if controller.online() and player!="local":
		controller.manager.controls.status.text="The player holding that private library performs this action."
		return 0
	var order: Array = controller.model.players[player].library.order
	# Take the final N in existing top-to-bottom order: ABCDE -> D, then E.
	var ids: Array = order.slice(maxi(0,order.size()-mini(n,5000)))
	var moved: int=0
	controller.batching=true
	for id: String in ids:
		var card: Control=controller.card_by_id(id)
		if card==null or not controller.move_card(card,"graveyard",true,player): break
		# Keep both model and public scene ordering deterministic for the appended cards.
		controller.manager.cards.erase(card);controller.manager.cards.append(card)
		controller.manager.world.move_child(card,controller.manager.world.get_child_count()-1)
		moved+=1
	controller.batching=false;controller.refresh()
	controller.record_event("mill_bottom",controller.model.players[player].display_name+" milled %d cards from bottom." % moved,{"count":moved})
	controller.manager.controls.status.text="Milled %d cards from bottom." % moved
	return moved

# Local placement preference; private identities stay private until the final move.
var enter_face_down: bool = false
func hand_drag_ids(id: String) -> Array[String]:
	var result: Array[String] = []
	var selected: Array = controller.manager.selection.ids
	for candidate: String in (selected if selected.has(id) else [id]):
		var card: Control=controller.card_by_id(candidate)
		if card!=null and card.state.current_zone=="hand" and card.state.zone_player_id==controller.active_hand_player(): result.append(candidate)
	return result
func beside_library(player: String) -> Vector2:
	var pile: Control=controller.pile_view if player=="local" else controller.opponent_pile
	return controller.manager.world.get_global_transform().affine_inverse()*(pile.get_global_transform()*Vector2(pile.size.x+24,0))
func place_cards(ids: Array, point: Vector2, hidden: bool = false) -> int:
	var moved: int=0
	for id: String in ids.duplicate():
		var card: Control=controller.card_by_id(id)
		if card==null: continue
		var player: String=card.state.zone_player_id
		if controller.online() and card.state.current_zone in ["hand","library"] and player!="local": continue
		var preserve_tap: bool=card.state.current_zone=="hand" and card.state.tapped
		if controller.move_card(card,"battlefield",true,player,false,hidden):
			if preserve_tap: card.set_tapped(true)
			card.position=point+Vector2((moved%8)*120,(moved/8)*175)
			card.state.position=card.position
			moved+=1
	controller.refresh()
	return moved
func play_top(player: String, count: int = 1) -> int:
	if controller.online() and player!="local": return 0
	return place_cards(controller.model.players[player].library.peek(count),beside_library(player),enter_face_down)
func play_active() -> int:
	var table: Node=controller.manager.custom_table
	if table!=null and table.enabled:
		var source: String=table.primary_for(table.global_player(controller.model.active_player))
		if source.is_empty():
			controller.manager.controls.status.text=table.missing_source("play",table.global_player(controller.model.active_player));return 0
		if table.pile_sync.connected() and not table.pile_sync.owns(table.row(source)):
			controller.manager.controls.status.text="The player holding this pile must place its top card.";return 0
		var ids: Array=table.orders.get(source,[])
		if ids.is_empty(): return 0
		var view: Control=table.views[source]
		return place_cards([ids[0]],view.position+Vector2(view.size.x+24,0),enter_face_down)
	return play_top(controller.active_hand_player())
func placement_toggle(parent: Node) -> void:
	var toggle:=CheckButton.new()
	toggle.text="Enter battlefield face down (hand drops / library)"
	toggle.button_pressed=enter_face_down
	toggle.toggled.connect(func(value: bool) -> void: enter_face_down=value)
	toggle.visibility_changed.connect(func() -> void: toggle.set_pressed_no_signal(enter_face_down))
	parent.add_child(toggle)
