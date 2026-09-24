extends PanelContainer
## Presentation boundary accepts only explicitly public art; hidden slots carry no identity.
var label: Label
var cards_row: Control
var back_count: int = -1
var public_textures: Array = []
var public_names: Array = []
var back_texture: Texture2D
var layout_mode_id: String = "row"
func _ready() -> void:
	position = Vector2(18, 38)
	size = Vector2(590, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.063,0.137,0.188,0.5)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	add_child(column)
	label = Label.new()
	column.add_child(label)
	cards_row = Control.new()
	cards_row.custom_minimum_size = Vector2(0, 56)
	cards_row.resized.connect(arrange)
	column.add_child(cards_row)
func present(count: int, back: Texture2D, faces: Array = [], names: Array = []) -> void:
	label.text = "Opponent hand: %d" % count
	if count == back_count and back == back_texture and faces == public_textures and names == public_names:
		return
	public_textures = faces.duplicate()
	public_names = names.duplicate()
	back_count = count
	back_texture = back
	for item: Node in cards_row.get_children():
		cards_row.remove_child(item)
		item.queue_free()
	for i: int in count:
		var item := TextureRect.new()
		var face: Texture2D = faces[i] if i < faces.size() else null
		item.texture = face if face != null else back
		item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item.size = Vector2(40, 56)
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.tooltip_text = "Revealed card" if face != null else "Hidden card"
		cards_row.add_child(item)
		var known_name: String = str(names[i]) if i < names.size() and names[i] != null else ""
		if face != null or not known_name.is_empty():
			var eye := Label.new()
			eye.text = "◉"
			eye.position = Vector2(23,0)
			eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
			item.add_child(eye)
			item.tooltip_text = (known_name + " — revealed") if face != null else known_name + " — Missing card asset. Use Card Sync before starting the match."
	arrange()
func arrange() -> void:
	# One layout function can later be replaced by fan/stack arrangers.
	var target: float = 44 if layout_mode_id == "Straight" else 24 if layout_mode_id == "Overlap" else 10
	var spacing: float = minf(target, maxf(0, cards_row.size.x - 40) / maxf(1, back_count - 1))
	for i: int in cards_row.get_child_count():
		cards_row.get_child(i).position = Vector2(i * spacing, 0)
