extends Window
signal chosen(config: Dictionary)
const Back = preload("res://scripts/battle/deck_back.gd")
var apply_caption: String="Use for this deck"
var config: Dictionary=Back.defaults()
var preview: TextureRect
var color: ColorPickerButton
var picker: FileDialog
var status: Label
func _ready() -> void:
	title="Deck Back";visible=false;close_requested.connect(hide)
	var scroll:=ScrollContainer.new();add_child(scroll);scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rows := VBoxContainer.new();scroll.add_child(rows);rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preview=TextureRect.new();preview.custom_minimum_size=Vector2(140,196);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;rows.add_child(preview)
	button(rows,"CardLink Default",func() -> void: config=Back.defaults();refresh())
	var presets := OptionButton.new();presets.add_item("Colors…")
	for key: String in Back.PRESETS: presets.add_item(key)
	rows.add_child(presets)
	presets.item_selected.connect(func(index: int) -> void:
		if index>0: config={"type":"preset","color":Back.PRESETS[presets.get_item_text(index)],"preset":presets.get_item_text(index),"asset":""};refresh())
	var color_label := Label.new();color_label.text="Custom Color · click the swatch";rows.add_child(color_label)
	color=ColorPickerButton.new();color.text="Custom Color";color.edit_alpha=false;rows.add_child(color)
	color.color_changed.connect(func(value: Color) -> void: config={"type":"color","color":"#"+value.to_html(false),"preset":"","asset":""};refresh())
	picker=FileDialog.new();picker.access=FileDialog.ACCESS_FILESYSTEM;picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.filters=PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Card back image"]);add_child(picker)
	picker.file_selected.connect(func(file: String) -> void:
		var result: Dictionary=Back.import_image(file)
		if result.has("error"): status.text=result.error;return
		config={"type":"image","color":config.color,"preset":"","asset":result.hash};status.text="Custom image stored locally.";refresh())
	button(rows,"Custom Image…",func() -> void: picker.popup_centered_ratio(0.8))
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rows.add_child(status)
	button(rows,apply_caption,func() -> void: chosen.emit(config.duplicate(true));hide())
	button(rows,"Cancel",hide)
func button(parent: Node, caption: String, action: Callable) -> void:
	var item := Button.new();item.text=caption;item.pressed.connect(action);parent.add_child(item)
func open(value: Dictionary) -> void:
	config=value.duplicate(true) if Back.valid(value) else Back.defaults();refresh();popup_centered_clamped(Vector2i(390,500),0.9)
func refresh() -> void:
	preview.texture=Back.texture(config);color.color=Color(config.color)
