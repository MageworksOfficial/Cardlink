extends RefCounted
signal changed
const ACTIONS = {
	"reset_match":["Reset Match",KEY_R | KEY_MASK_CTRL | KEY_MASK_ALT | KEY_MASK_SHIFT,"Gameplay"],
	"background_edit":["Background Edit Mode",KEY_B | KEY_MASK_CTRL,"View"],
	"play_top":["Top card to battlefield",KEY_D | KEY_MASK_CTRL,"Gameplay"],
	"draw":["Draw",KEY_D,"Gameplay"], "discard":["Discard selected hand card",KEY_F,"Gameplay"],
	"shuffle":["Shuffle",KEY_S,"Gameplay"], "token":["Create / Duplicate Token",KEY_T,"Gameplay"],
	"counter":["Counter Action",KEY_C,"Gameplay"], "graveyard":["Open / Move to Graveyard",KEY_G,"Gameplay"],
	"exile":["Open / Move to Exile",KEY_E,"Gameplay"], "end_turn":["End Turn",KEY_N,"Gameplay"],
	"delete":["Delete Selected",KEY_DELETE,"Gameplay"], "undo":["Undo",KEY_Z | KEY_MASK_CTRL,"Gameplay"],
	"hands":["Show / Hide Hands",KEY_X,"View"], "layout":["Layout Mode",KEY_L,"View"],
	"reset_view":["Reset View",KEY_R,"View"], "center_view":["Center on Local Side",KEY_SPACE,"View"],
	"pan_left":["Pan Left",KEY_LEFT,"View"], "pan_right":["Pan Right",KEY_RIGHT,"View"],
	"pan_up":["Pan Up",KEY_UP,"View"], "pan_down":["Pan Down",KEY_DOWN,"View"],
	"hand":["Open Hand",KEY_H,"Interface"], "library":["Open Library",KEY_B,"Interface"],
	"history":["Match History",KEY_M,"Interface"], "save":["Save Match",KEY_S | KEY_MASK_CTRL,"Interface"],
	"table_builder":["Toggle Table Builder",0,"Interface"],
	"mode":["Online / Playtest",KEY_P,"Interface"],
	"tap":["Tap / Untap Selected",KEY_Q,"Gameplay"], "perspective":["Switch Offline Perspective",KEY_V,"View"], "card_face":["Change Card Face",0,"Gameplay"]}
var path: String
var keys: Dictionary = {}
func _init(file: String = "user://input_bindings.cfg") -> void:
	path = file
	for id: String in ACTIONS: keys[id] = ACTIONS[id][1]
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for id: String in ACTIONS:
			var value: Variant = config.get_value("keys",id,keys[id])
			if value is int and value >= 0: keys[id] = value
	# Upgrade the previous default while retaining other custom bindings.
	if keys.reset_match == (KEY_R | KEY_MASK_CTRL | KEY_MASK_ALT):
		keys.reset_match = ACTIONS.reset_match[1]
	# A corrupted preference cannot create ambiguous shortcuts.
	var used: Dictionary = {}
	for id: String in keys:
		if keys[id] != 0 and used.has(keys[id]): keys[id] = 0
		elif keys[id] != 0: used[keys[id]] = id
func caption(id: String) -> String:
	return "Unbound" if keys.get(id,0) == 0 else OS.get_keycode_string(keys[id])
func conflict(id: String, key: int) -> String:
	for other: String in keys:
		if other != id and key != 0 and keys[other] == key: return other
	return ""
func assign(id: String, key: int, replace: bool = false) -> bool:
	if not ACTIONS.has(id): return false
	var other: String = conflict(id,key)
	if not other.is_empty() and not replace: return false
	if not other.is_empty(): keys[other] = 0
	keys[id] = key
	save()
	changed.emit()
	return true
func reset_all() -> void:
	for id: String in ACTIONS: keys[id] = ACTIONS[id][1]
	save()
	changed.emit()
func save() -> Error:
	var config := ConfigFile.new()
	for id: String in keys: config.set_value("keys",id,keys[id])
	return preload("res://scripts/card_storage.gd").write_atomic(path,config.encode_to_text().to_utf8_buffer())
func action_for(event: InputEventKey) -> String:
	var code: int = event.get_keycode_with_modifiers()
	for id: String in keys:
		if keys[id] != 0 and keys[id] == code: return id
	# Shift speeds up a pan binding unless the combination was explicitly rebound.
	if event.shift_pressed:
		for id: String in keys:
			if id.begins_with("pan_") and keys[id] != 0 and keys[id] == (code & ~KEY_MASK_SHIFT): return id
	return ""
func help_text() -> String:
	var result: String = "Ctrl+F — Find cards and functions (offline or online)\n\nMouse\nLeft drag — Move · Empty drag — Multi-select\nCtrl/Shift-click — Add/remove battlefield or hand objects\nRight click — Actions · Double click battlefield card — Tap / Untap\nWheel — Zoom · Middle drag — Pan\nMulti-select battlefield objects → Right-click → Arrange\nStack · Fan · Horizontal · Vertical · Distribute · Spread\n"
	for group: String in ["Gameplay","View","Interface"]:
		result += "\n"+group+"\n"
		for id: String in ACTIONS:
			if ACTIONS[id][2] == group: result += caption(id)+" — "+str(ACTIONS[id][0])+"\n"
	return result+"\nShift + pan key — Faster pan\nShortcuts pause while typing or in modal windows."
