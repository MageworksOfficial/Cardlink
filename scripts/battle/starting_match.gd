extends RefCounted
## Local-only deck recipes. No private order is ever a rematch source.
var reset: RefCounted
var sources: Array = []
var life: Dictionary = {"local":40,"opponent":40}
func _init(owner: RefCounted) -> void: reset=owner
func capture() -> Dictionary: return {"sources":sources.duplicate(true),"life":life.duplicate(true)}
static func valid(d: Variant) -> bool:
	if not d is Dictionary: return false
	if d.is_empty(): return true
	if not d.get("sources") is Array or d.sources.size()>128 or not d.get("life") is Dictionary: return false
	for p: String in ["local","opponent"]:
		if not preload("res://scripts/layout_service.gd").number(d.life.get(p)) or absf(d.life[p])>1000000: return false
	for row: Variant in d.sources:
		if not row is Dictionary or row.get("kind") not in ["standard","pile"] or not row.get("target") is String or row.target.length()>80 or not row.get("leaders") is bool: return false
		if row.kind=="standard" and row.target not in ["local","opponent"]: return false
		if not row.get("deck") is Dictionary or not preload("res://scripts/deck_storage.gd").validate(row.deck).is_empty(): return false
	return true
func restore(data: Dictionary) -> void:
	sources=data.get("sources",[]).duplicate(true);life=data.get("life",{"local":40,"opponent":40}).duplicate(true)
func remember(kind: String,target: String,deck: Dictionary,leaders: bool) -> void:
	if reset.rebuilding: return
	if sources.is_empty():
		for p: String in ["local","opponent"]: life[p]=reset.session.manager.match_controller.model.players[p].life
	if kind=="standard": sources=sources.filter(func(row: Dictionary) -> bool: return row.kind!="standard" or row.target!=target)
	sources.append({"kind":kind,"target":target,"deck":deck.duplicate(true),"leaders":leaders})
func usable() -> Array:
	var result: Array=[]
	var b: Node=reset.session.manager.custom_table
	for row: Dictionary in sources:
		if row.kind=="pile" and b.row(row.target).is_empty(): continue
		if reset.session.connected() and ((row.kind=="standard" and row.target!="local") or (row.kind=="pile" and not b.pile_sync.owns(b.row(row.target)))): continue
		result.append(row)
	return result
func preflight() -> String:
	var m: Node=reset.session.manager
	if m.match_controller.preparing_match: return "Finish Card Sync before resetting."
	if reset.session.router!=null and reset.session.router.transactions.has_unfinished(): return "Resolve the pending card transfer before resetting."
	var records: Dictionary={}
	var repeated: Dictionary={}
	for record: Dictionary in m.match_controller.loader.load_records():
		var id: String=str(record.metadata.get("card_id",""))
		if records.has(id): repeated[id]=true
		records[id]=record
	for row: Dictionary in usable():
		for entry: Dictionary in row.deck.cards:
			if not records.has(entry.card_id) or repeated.has(entry.card_id) or records[entry.card_id].thumbnail==null: return "A starting deck card or image is missing. Restore it before resetting."
	return ""
func rebuild() -> String:
	var error: String=preflight()
	if not error.is_empty(): return error
	var m: Node=reset.session.manager
	var c: Node=m.match_controller
	var recipes: Array=usable()
	reset.rebuilding=true
	c.search_player="";c.close_inspection();c.review.cancel()
	c.visibility.end(c.model.instances)
	m.undo.invalidate("New match started.")
	c.batching=true
	for card: Control in m.cards.duplicate(): c.remove_card(card)
	m.extras.restore_counters([])
	m.custom_table.orders.clear()
	m.custom_table.pile_sync.grants.clear()
	m.custom_table.pile_sync.remote_counts.clear()
	m.custom_table.pile_sync.public_members.clear()
	for p: String in ["local","opponent"]:
		var player: RefCounted=c.model.players[p]
		player.library.order.clear();player.loaded_ids.clear();player.deck_manifest.clear()
		player.life=int(life[p])
	c.remote_library_knowledge.clear();c.remote_library_count=-1;c.remote_hand_count=-1
	c.model.turn_number=1;c.model.active_player="opponent" if reset.session.connected() and not reset.session.router.is_host() else "local"
	c.model.match_id=Crypto.new().generate_random_bytes(16).hex_encode()
	c.model.history.clear();c.batching=false
	for row: Dictionary in recipes:
		if row.kind=="standard":
			var result: Dictionary=c.load_deck(row.deck,row.leaders,row.target)
			if result.has("error"): error=result.error;break
		else:
			error=m.custom_table.load_deck(row.target,row.deck)
			if not error.is_empty(): break
	for id: String in m.custom_table.orders: m.custom_table.orders[id].shuffle()
	c.model.history.clear();m.life=c.model.players.local.life
	m.controls.life_label.text="Life: %d" % m.life
	m.extras.refresh_history();c.refresh();reset.rebuilding=false
	return error
