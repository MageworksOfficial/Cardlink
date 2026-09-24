extends Control
signal online_requested
signal offline_requested
signal exit_requested
const BASE = Vector2(1672,941)
const ASSETS = "res://assets/title_screen/"
var animation: Node
var composition: Control
var background: TextureRect
var title_art: TextureRect
var buttons: Array[Button] = []
var settings: Window
var picker: FileDialog
var back_preview: TextureRect
var settings_status: Label
var backs = preload("res://scripts/card_back_service.gd").new()
func _ready() -> void:
	background = TextureRect.new()
	background.name = "Environment"
	background.texture = load(ASSETS+"background/background_tabletop_reconstructed.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	composition = Control.new()
	composition.name = "Composition"
	composition.size = BASE
	composition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(composition)
	title_art = TextureRect.new()
	title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_art.texture = load(ASSETS+"ui/cardlink_title.png")
	title_art.position = Vector2(354,12)
	title_art.size = Vector2(964,340)
	title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_art.size = Vector2(964,340)
	title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	composition.add_child(title_art)
	title_art.set_size.call_deferred(Vector2(964,340))
	add_art("Online", "online_mode_panel",Rect2(309,363,510,286),Rect2(175,150,1300,670),"Play with another person using CardLink room codes.",func() -> void: online_requested.emit())
	add_art("Offline", "offline_mode_panel",Rect2(853,363,511,286),Rect2(220,145,1335,615),"Local playtest: control both players. No internet required.",func() -> void: offline_requested.emit())
	add_art("Settings", "settings_button",Rect2(550,684,268,64),Rect2(420,210,1315,300),"Choose your card back.",open_settings)
	add_art("Exit", "exit_button",Rect2(853,684,267,64),Rect2(190,190,1750,360),"Exit CardLink.",func() -> void: exit_requested.emit())
	for i: int in buttons.size():
		buttons[i].focus_next = buttons[i].get_path_to(buttons[(i+1)%4])
		buttons[i].focus_previous = buttons[i].get_path_to(buttons[(i+3)%4])
		buttons[i].focus_neighbor_left = buttons[i].get_path_to(buttons[i^1])
		buttons[i].focus_neighbor_right = buttons[i].get_path_to(buttons[i^1])
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i+2)%4])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i+2)%4])
	build_settings()
	resized.connect(arrange)
	arrange()
	animation = preload("res://scripts/frontend/title_motion.gd").new()
	animation.title = self
	add_child(animation)
	focus_preferred.call_deferred()
func add_art(label: String, file: String, area: Rect2, visible_frame: Rect2, hint: String, action: Callable) -> void:
	var item: Button = preload("res://scripts/title_art_button.gd").new()
	item.name = label
	item.artwork = load(ASSETS+"ui/"+file+".png")
	item.frame = visible_frame
	item.position = area.position
	item.size = area.size
	item.tooltip_text = hint
	item.pressed.connect(action)
	composition.add_child(item)
	buttons.append(item)
func arrange() -> void:
	var factor: float = minf(size.x/BASE.x,size.y/BASE.y)
	composition.scale = Vector2.ONE*factor
	composition.position = (size-BASE*factor)/2
func build_settings() -> void:
	settings = Window.new()
	settings.title = "Settings · Card backs"
	settings.visible = false
	settings.size = Vector2i(440,400)
	settings.close_requested.connect(close_settings)
	settings.window_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel") and not picker.visible: close_settings())
	add_child(settings)
	var rows := VBoxContainer.new()
	rows.position = Vector2(18,18)
	rows.size = Vector2(404,364)
	settings.add_child(rows)
	settings_status = Label.new()
	settings_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_status.text = "Card backs use your existing CardLink settings."
	rows.add_child(settings_status)
	back_preview = TextureRect.new()
	back_preview.custom_minimum_size = Vector2(100,160)
	back_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rows.add_child(back_preview)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Card back image"])
	picker.file_selected.connect(func(path: String) -> void:
		var error: String = backs.import_custom(path)
		settings_status.text = "Card back saved." if error.is_empty() else error
		back_preview.texture = backs.texture())
	settings.add_child(picker)
	for entry: Array in [["Choose custom card back…",func() -> void: picker.popup_centered_ratio(0.8)],["Use default CardLink back",func() -> void:
		var error: String = backs.use_default()
		settings_status.text = "Default card back saved." if error.is_empty() else error
		back_preview.texture = backs.texture()],["Close",close_settings]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		rows.add_child(button)
func open_settings() -> void:
	if get_parent().get("shared_settings") != null:
		get_parent().shared_settings.open()
		return
	backs.reload()
	back_preview.texture = backs.texture()
	settings.popup_centered_clamped(Vector2i(440,400),0.9)
	settings.get_child(0).get_child(2).grab_focus()
func close_settings() -> void:
	settings.hide()
	buttons[2].grab_focus()
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel") and settings.visible:
		close_settings()
		get_viewport().set_input_as_handled()

func focus_preferred() -> void:
	var shell: Node = get_parent()
	var offline: bool = shell.get("preferences") != null and shell.preferences.get_flag("last_offline",false)
	buttons[1 if offline else 0].grab_focus()
