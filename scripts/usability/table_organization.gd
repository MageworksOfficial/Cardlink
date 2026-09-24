extends RefCounted
var manager: Node
var snap_grid: bool = false
var snap_edge: bool = false
const GRID = 20.0
func _init(table: Node) -> void: manager = table
func snap(point: Vector2, extent: Vector2, fixed_ui: bool = false) -> Vector2:
	if not manager.layout.edit_mode: return point
	var result: Vector2 = point.snapped(Vector2.ONE*GRID) if snap_grid else point
	if snap_edge:
		var canvas: Vector2 = manager.get_viewport().get_visible_rect().size if fixed_ui else manager.world.LOGICAL_SIZE
		for axis: int in 2:
			var near: float = 20
			var far: float = canvas[axis]-extent[axis]-20
			if absf(result[axis]-near) < 90: result[axis] = near
			elif absf(result[axis]-far) < 90: result[axis] = far
	return result
func reset_layout() -> void:
	var c: Node = manager.match_controller
	for player: String in ["local","opponent"]:
		var y: float = 820 if player == "local" else 256
		var pile: Control = c.pile_view if player == "local" else c.opponent_pile
		pile.position = Vector2(1450,y)
		for i: int in 3:
			var zone: Control = c.zone_for(["graveyard","exile","commander"][i],player)
			zone.custom_minimum_size = Vector2(180,170)
			zone.size = zone.custom_minimum_size
			zone.position = Vector2(1590+i*210,820 if player == "local" else 226)
	# Reset anchors only: preserve every match card's position and zone membership.
	var view: Vector2 = manager.get_viewport().get_visible_rect().size
	var height: float = hand_height()
	var hand_position: Vector2 = Vector2(10,view.y-height-32)
	var hand_size: Vector2 = Vector2(view.x-20,height)
	if c.hand_window.detached: c.hand_window.main_layout = {"position":hand_position,"size":hand_size}
	else:
		c.hand.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		c.hand.position = hand_position
		c.hand.size = hand_size
	c.opponent_hand.position = Vector2(12,48)
	c.opponent_hand.size = Vector2(440,72)
	for player: String in c.hearts.hearts:
		var row: Control = c.hearts.hearts[player].get_parent()
		row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		row.position = Vector2(12,view.y-height-74 if player == "local" else 8)
	if manager.perspective != null: manager.perspective.capture_heart_anchors()
	manager.view.reset_view()
	manager.controls.status.text = "Table layout reset. Cards and decks kept."
func build_controls(rows: Node) -> void:
	manager.controls.button(rows,"Reset Table Layout",reset_layout)
	for entry: Array in [["Snap to Grid","snap_grid"],["Snap to Edge","snap_edge"]]:
		var toggle := CheckBox.new()
		toggle.text = entry[0]
		toggle.toggled.connect(func(value: bool) -> void: set(entry[1],value))
		rows.add_child(toggle)

func hand_height() -> float:
	return 118*clampf(float(manager.table_preferences.value("hand_scale",1.0)),0.65,1.4)+36+(18 if manager.table_preferences.value("hand_layout","Straight") == "Fan" else 0)
