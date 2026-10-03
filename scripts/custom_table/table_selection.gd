extends Control
signal chosen(custom: bool)
signal back_requested
signal settings_requested
signal exit_requested
var canvas: Control
var first: Button
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := TextureRect.new()
	background.texture = preload("res://assets/title_screen/background/background_tabletop_reconstructed.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	canvas.size = Vector2(1672,941)
	add_child(canvas)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/title_screen/ui/cardlink_title.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(354,0)
	logo.size = Vector2(964,285)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(logo)
	var title := Label.new()
	title.text = "CHOOSE YOUR TABLE"
	title.add_theme_font_size_override("font_size",34)
	title.position = Vector2(0,260)
	title.size.x = 1672
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(title)
	for i: int in 2:
		var tile := Button.new()
		tile.name = "BuildYourOwn" if i else "CardLinkStandard"
		tile.text = "BUILD YOUR OWN\n\nStart with a blank table.\nAdd decks, zones, boards and objects.\nSave, export and share your own template." if i else "CARDLINK STANDARD\n\nTraditional card-table layout.\nReady to play."
		tile.position = Vector2(230+i*635,345)
		tile.size = Vector2(580,310)
		tile.add_theme_font_size_override("font_size",24)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("102c42")
		style.border_color = Color("43c4ee")
		style.set_border_width_all(3)
		style.set_corner_radius_all(18)
		style.shadow_color = Color(0.1,0.65,1,0.25)
		style.shadow_size = 12
		tile.add_theme_stylebox_override("normal",style)
		var focused: StyleBoxFlat = style.duplicate()
		focused.border_color = Color.WHITE
		focused.bg_color = Color("194763")
		tile.add_theme_stylebox_override("hover",focused)
		tile.add_theme_stylebox_override("focus",focused)
		tile.pressed.connect(func() -> void: chosen.emit(i == 1))
		canvas.add_child(tile)
		if i == 0: first = tile
	for i: int in 3:
		var b := TextureButton.new()
		b.texture_normal = load("res://assets/table_selection/"+["back_exact.png","settings_exact.png","exit_exact.png"][i])
		b.position = Vector2(425+i*270,765)
		b.custom_minimum_size = Vector2(225,72)
		b.size = Vector2(225,72)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.tooltip_text = ["Back","Settings","Exit"][i]
		b.pressed.connect(func() -> void:
			if i == 0: back_requested.emit()
			elif i == 1: settings_requested.emit()
			else: exit_requested.emit()
		)
		canvas.add_child(b)
	resized.connect(arrange)
	arrange()
func arrange() -> void:
	var factor: float = minf(size.x/1672.0,size.y/941.0)
	canvas.scale = Vector2.ONE*factor
	canvas.position = (size-Vector2(1672,941)*factor)/2
