extends Node
## Presentation only. No timers run while the title is hidden or unfocused.
var title: Control
var elapsed: float = 0.0
var focused: bool = true
var reduced: bool = false
var ring: Control
var preferences: RefCounted
func _ready() -> void:
	preferences = title.get_parent().get("table_preferences")
	ring = preload("res://scripts/frontend/tech_ring.gd").new()
	ring.position = Vector2(836,180)
	title.composition.add_child(ring)
	title.composition.move_child(ring,0)
	title.visibility_changed.connect(refresh)
	get_window().focus_entered.connect(func() -> void: set_focused(true))
	get_window().focus_exited.connect(func() -> void: set_focused(false))
	if preferences != null: preferences.changed.connect(refresh)
	refresh()
func set_focused(value: bool) -> void:
	focused = value
	refresh()
func refresh() -> void:
	reduced = preferences != null and bool(preferences.value("reduce_motion",false))
	set_process(title.is_visible_in_tree() and focused and not reduced)
	if reduced:
		ring.rotation = 0
		title.title_art.self_modulate = Color.WHITE
		title.background.position = Vector2.ZERO
		title.background.scale = Vector2.ONE
		for button: Button in title.buttons:
			if button.motion != null: button.motion.kill()
			button.hover_amount = 0
			button.queue_redraw()
func _process(delta: float) -> void:
	elapsed += minf(delta,0.1)
	ring.rotation = fmod(elapsed*TAU/26.0,TAU)
	var light: float = 1.0+0.055*sin(elapsed*TAU/7.0)
	title.title_art.self_modulate = Color(light,light,light,1)
	title.background.scale = Vector2(1.025,1.025)
	title.background.position = -title.size*0.0125+Vector2(sin(elapsed/13.0)*4,cos(elapsed/17.0)*3)
