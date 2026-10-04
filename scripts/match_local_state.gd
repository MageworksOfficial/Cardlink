extends RefCounted
## Optional extension on schema 1 saves: old matches receive safe defaults.
const Layout = preload("res://scripts/layout_service.gd")
static func capture(manager: Node) -> Dictionary:
	var model: RefCounted = manager.match_controller.model
	return {"playtest_images":manager.temporary_images.capture() if manager.temporary_images!=null else [],"background":manager.appearance.background.duplicate(true) if manager.appearance!=null else preload("res://scripts/appearance/background_config.gd").defaults(),"reset_start":manager.battle.reset.start.capture() if manager.battle!=null else {},"deck_backs":manager.deck_backs.piles.duplicate(true),"custom_table":manager.custom_table.capture() if manager.custom_table != null else {"enabled":false,"table":preload("res://scripts/custom_table/table_document.gd").fresh(),"orders":{}},"viewed_player": manager.perspective.viewed_player if manager.perspective != null and manager.perspective.offline() else "local", "turn_number": model.turn_number, "active_player": model.active_player, "history": model.history.duplicate(true), "counters": manager.extras.capture_counters(), "opponent_mode":manager.match_controller.playtest.mode, "hand_player":manager.match_controller.active_hand_player(), "hand_detached":manager.match_controller.hand_window.detached, "hand_position":[manager.match_controller.hand_window.window.position.x,manager.match_controller.hand_window.window.position.y], "remote_library_knowledge":manager.match_controller.remote_library_knowledge.duplicate(true), "remote_library_count":manager.match_controller.remote_library_count}
static func validate(data: Variant) -> String:
	if not data is Dictionary:
		return "Invalid local tabletop state."
	var lab_images: Variant=data.get("playtest_images",[])
	if not lab_images is Array or lab_images.size()>32:return "Invalid playtest images."
	var image_ids: Dictionary={}
	for row: Variant in lab_images:
		if not preload("res://scripts/playtest_lab/image_protocol.gd").row(row):return "Invalid playtest image."
		if image_ids.has(row.id):return "Duplicate playtest image."
		image_ids[row.id]=true
	if not data.get("opponent_mode","online") in ["online","local_playtest"] or not data.get("hand_player","local") in ["local","opponent"] or not data.get("hand_detached",false) is bool or not Layout.vector_valid(data.get("hand_position",[100,100])):
		return "Invalid hand window or playtest state."
	if not data.get("viewed_player","local") in ["local","opponent"]: return "Invalid viewed player."
	if data.has("background") and not preload("res://scripts/appearance/background_config.gd").valid(data.background): return "Invalid battlefield background."
	if data.has("reset_start") and not preload("res://scripts/battle/starting_match.gd").valid(data.reset_start): return "Invalid rematch starting configuration."
	if data.has("deck_backs"):
		if not data.deck_backs is Dictionary or data.deck_backs.size()>128: return "Invalid saved pile backs."
		for config: Variant in data.deck_backs.values():
			if not preload("res://scripts/battle/deck_back.gd").valid(config): return "Invalid saved pile back."
	if data.has("custom_table"):
		var table_error: String = preload("res://scripts/custom_table/table_builder.gd").validate_saved(data.custom_table)
		if not table_error.is_empty(): return table_error
	var memories: Variant = data.get("remote_library_knowledge",{})
	if not memories is Dictionary or memories.size()>500: return "Invalid library knowledge."
	for slot: Variant in memories:
		if not slot is String or not slot.is_valid_int() or int(slot)<0 or int(slot)>4999 or not preload("res://scripts/network/network_action.gd").card(memories[slot]): return "Invalid known library slot."
	var library_count: Variant = data.get("remote_library_count",-1)
	if not Layout.number(library_count) or library_count != floor(library_count) or library_count < -1 or library_count > 5000: return "Invalid remote library count."
	var turn: Variant = data.get("turn_number", 1)
	if not Layout.number(turn) or turn < 1 or turn > 1000000000 or turn != floor(turn) or not data.get("active_player", "local") in ["local", "opponent"]:
		return "Invalid turn state."
	var history: Variant = data.get("history", [])
	if not history is Array or history.size() > 1000:
		return "Invalid match history."
	for event: Variant in history:
		if not event is Dictionary or not event.get("text") is String or event.text.length() > 4000 or not event.get("kind") is String or not event.get("actor") in ["local", "opponent"] or not Layout.number(event.get("turn")) or event.turn < 1 or event.turn != floor(event.turn) or not event.get("payload", {}) is Dictionary:
			return "Invalid history event."
	var counters: Variant = data.get("counters", [])
	if not counters is Array or counters.size() > 500:
		return "Invalid standalone counters."
	var seen: Dictionary = {}
	for row: Variant in counters:
		if not row is Dictionary or not row.get("instance_id") is String or row.instance_id.is_empty() or seen.has(row.instance_id) or not row.get("label") is String or row.label.length() > 80 or not Layout.vector_valid(row.get("position")) or not Layout.number(row.get("value")) or absf(row.value) > 1000000 or row.value != floor(row.value):
			return "Invalid standalone counter."
		seen[row.instance_id] = true
	return ""
static func restore(manager: Node, data: Dictionary) -> void:
	if manager.temporary_images!=null:manager.temporary_images.restore(data.get("playtest_images",[]))
	if manager.battle!=null: manager.battle.reset.start.restore(data.get("reset_start",{}))
	var model: RefCounted = manager.match_controller.model
	model.turn_number = int(data.get("turn_number", 1))
	model.active_player = data.get("active_player", "local")
	model.history.assign(data.get("history", []))
	manager.extras.restore_counters(data.get("counters", []))
	manager.extras.refresh_history()
	manager.deck_backs.piles=data.get("deck_backs",{}).duplicate(true)
	var c: Node = manager.match_controller
	c.playtest.mode = data.get("opponent_mode","online")
	c.playtest.hand_player = data.get("hand_player","local") if c.playtest.local_playtest() else "local"
	c.playtest.refresh()
	if manager.perspective != null: manager.perspective.switch_to(data.get("viewed_player",model.active_player if c.playtest.local_playtest() else "local"),false,false)
	c.remote_library_knowledge = data.get("remote_library_knowledge",{}).duplicate(true)
	c.remote_library_count = int(data.get("remote_library_count",-1))
	c.hand_window.restore_hand()
	var point: Array = data.get("hand_position",[100,100])
	c.hand_window.last_position = Vector2i(point[0],point[1])
	if data.get("hand_detached",false): c.hand_window.open_hand()
	if manager.custom_table != null:
		manager.custom_table.restore(data.get("custom_table",{}))
	if manager.appearance!=null: manager.appearance.apply(data.get("background",preload("res://scripts/appearance/background_config.gd").defaults()),false)
