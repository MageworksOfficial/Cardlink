extends Node
var appearance: Node
var picker: Window
var scope: Window
var scope_choice: OptionButton
var target: String=""
var pending: Dictionary={}
var offered: Dictionary={}
var approval: ConfirmationDialog
var request: Dictionary={}
func manager() -> Node: return appearance.manager
func _ready() -> void:
	picker=preload("res://scripts/battle/deck_back_picker.gd").new();picker.apply_caption="Continue → Apply scope";add_child(picker);picker.chosen.connect(choose_scope)
	scope=Window.new();scope.title="Apply Deck Back";scope.visible=false;scope.close_requested.connect(scope.hide);add_child(scope)
	var rows:=VBoxContainer.new();scope.add_child(rows);rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope_choice=OptionButton.new();scope_choice.add_item("This Match Only");scope_choice.add_item("Save With Deck");rows.add_child(scope_choice)
	picker.button(rows,"Apply",func() -> void:
		if apply_back(target,pending,scope_choice.selected==1): scope.hide())
	picker.button(rows,"Cancel",scope.hide)
	approval=ConfirmationDialog.new();approval.title="Deck Sleeve Request";approval.ok_button_text="Accept";approval.cancel_button_text="Decline";add_child(approval)
	approval.confirmed.connect(func() -> void:
		if not request.is_empty(): apply_back(request.target,request.back,false,true)
		request={})
	approval.canceled.connect(func() -> void: request={})
func targets() -> Array:
	var result: Array=[]
	if not manager().custom_table.enabled:
		for player: String in ["local","opponent"]: result.append({"id":player,"name":manager().match_controller.model.players[player].display_name+" library"})
	else:
		for row: Dictionary in manager().custom_table.document.components:
			if row.kind in ["deck","shared_deck"]: result.append({"id":row.id,"name":row.name})
	return result
func open(id: String="") -> void:
	manager().controls.close_panels()
	if id.is_empty():
		var options: Array=targets()
		if options.size()==1: open(options[0].id);return
		var chooser:=Window.new();chooser.title="Choose Deck / Pile";chooser.size=Vector2i(410,350);add_child(chooser);chooser.close_requested.connect(chooser.queue_free)
		var scroll:=ScrollContainer.new();chooser.add_child(scroll);scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rows:=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
		for item: Dictionary in options: picker.button(rows,item.name,func() -> void: chooser.queue_free();open(item.id))
		picker.button(rows,"Cancel",chooser.queue_free);chooser.popup_centered_clamped(Vector2i(410,350),0.9);return
	target=id
	var value: Dictionary=manager().deck_backs.library_config(id) if id in ["local","opponent"] else manager().deck_backs.pile_config(id)
	picker.open(value)
func remote(id: String) -> bool:
	if not manager().match_controller.online(): return false
	return id=="opponent" if id in ["local","opponent"] else not manager().custom_table.pile_sync.owns(manager().custom_table.row(id))
func choose_scope(config: Dictionary) -> void:
	pending=config;scope_choice.select(0);scope_choice.set_item_disabled(1,remote(target));scope.popup_centered_clamped(Vector2i(390,180),0.9)
func recipes(id: String) -> Array:
	return manager().battle.reset.start.sources.filter(func(row: Dictionary) -> bool: return row.kind==("standard" if id in ["local","opponent"] else "pile") and row.target==id)
func apply_back(id: String, config: Dictionary, save: bool=false, approved: bool=false) -> bool:
	if not preload("res://scripts/battle/deck_back.gd").valid(config): return false
	if remote(id):
		if approved: return false
		if offered.size()>=8: offered.clear()
		if config.type=="image": offered[config.asset]=true
		var wire_target: String="local" if id=="opponent" else id
		var ok: bool=manager().battle.send("sleeve_request",{"target":wire_target,"back":config})
		appearance.tell("Deck sleeve request sent." if ok else "Unable to send sleeve request.");return ok
	if not id in ["local","opponent"] and manager().custom_table.row(id).is_empty(): return false
	var sources: Array=recipes(id)
	if save:
		if sources.size()!=1: appearance.tell("Save With Deck needs exactly one loaded saved deck in this pile.");return false
		var matches: Array=[]
		for record: Dictionary in manager().controls.deck_storage.list_decks():
			if str(record.get("error","")).is_empty() and record.data.deck_id==sources[0].deck.deck_id: matches.append(record)
		if matches.size()!=1: appearance.tell("Saved deck is missing or ambiguous. Use This Match Only.");return false
		var value: Dictionary=matches[0].data.duplicate(true);value.deck_back=config.duplicate(true)
		var result: Dictionary=manager().controls.deck_storage.save_deck(value,matches[0].path)
		if result.has("error"): appearance.tell(result.error);return false
	for row: Dictionary in sources: row.deck.deck_back=config.duplicate(true)
	if id in ["local","opponent"]: manager().match_controller.model.players[id].deck_back=config.duplicate(true)
	else: manager().deck_backs.piles[id]=config.duplicate(true)
	for card: Control in manager().cards:
		var matches: bool=manager().match_controller.model.players[id].loaded_ids.has(card.state.match_instance_id) if id in ["local","opponent"] else (card.state.custom_metadata.get("sleeve_source","")==id or manager().custom_table.orders.get(id,[]).has(card.state.match_instance_id))
		if matches: card.state.custom_metadata["deck_back"]=config.duplicate(true)
	manager().match_controller.refresh();appearance.tell("Deck back saved." if save else "Deck back changed.");return true
func receive(data: Dictionary) -> void:
	if remote(data.target) or (not data.target in ["local","opponent"] and manager().custom_table.row(data.target).is_empty()): return
	if approval.visible: return
	request=data.duplicate(true)
	approval.dialog_text=manager().match_controller.model.players.opponent.display_name+" wants to change your deck sleeve to "+str(data.back.get("preset",data.back.type))+". Applies to this match only."
	approval.popup_centered_clamped(Vector2i(460,210),0.9)
