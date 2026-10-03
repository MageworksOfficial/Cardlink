extends Window
var appearance: Node
var fields: Dictionary={}
var refreshing: bool=false
var color: ColorPickerButton
var lock: CheckButton
var status: Label
var picker: FileDialog
func button(parent: Node, text: String, fn: Callable) -> Button:
	var b:=Button.new();b.text=text;b.pressed.connect(fn);parent.add_child(b);return b
func _ready() -> void:
	title="Battlefield Background";visible=false;close_requested.connect(hide)
	var scroll:=ScrollContainer.new();add_child(scroll);scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rows:=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	button(rows,"Reset to CardLink Default",func() -> void: appearance.reset_background();refresh_fields())
	var presets:=OptionButton.new();presets.add_item("Solid color…")
	for name: String in preload("res://scripts/battle/deck_back.gd").PRESETS: presets.add_item(name)
	rows.add_child(presets);presets.item_selected.connect(func(index: int) -> void:
		if index==0: return
		var value: Dictionary=appearance.background.duplicate(true);value.type="color";value.color=preload("res://scripts/battle/deck_back.gd").PRESETS[presets.get_item_text(index)];appearance.apply(value);refresh_fields())
	color=ColorPickerButton.new();color.text="Custom Color / Preview";color.edit_alpha=false;rows.add_child(color)
	color.color_changed.connect(func(value: Color) -> void:
		if refreshing: return
		status.text="Custom color preview — click Apply Custom Color to use it.")
	button(rows,"Apply Custom Color",func() -> void:
		var next: Dictionary=appearance.background.duplicate(true);next.type="color";next.color="#"+color.color.to_html(false);appearance.apply(next);appearance.tell("Background changed."))
	picker=FileDialog.new();picker.access=FileDialog.ACCESS_FILESYSTEM;picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.filters=PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Background image"]);add_child(picker)
	picker.file_selected.connect(func(path: String) -> void:
		var result: Dictionary=appearance.assets.ingest(path)
		if result.has("error"): status.text=result.error;return
		var next: Dictionary=appearance.Config.defaults();next.type="image";next.asset=result.hash;next.locked=false;appearance.apply(next);appearance.fit();refresh_fields();appearance.tell("Background changed."))
	button(rows,"Choose Background Image…",func() -> void: picker.popup_centered_ratio(0.8))
	button(rows,"Background Edit ON / OFF [Ctrl+B]",func() -> void: appearance.toggle_edit();refresh_fields())
	lock=CheckButton.new();lock.text="Lock Background";rows.add_child(lock)
	lock.toggled.connect(func(locked: bool) -> void:
		if refreshing: return
		var next: Dictionary=appearance.background.duplicate(true);next.locked=locked;appearance.apply(next);appearance.tell("Background locked." if locked else "Background unlocked.");refresh_fields())
	for key: String in ["X","Y","Width","Height","Rotation","Opacity %"]:
		var row:=HBoxContainer.new();rows.add_child(row);var label:=Label.new();label.text=key;label.custom_minimum_size.x=125;row.add_child(label)
		var number:=SpinBox.new();number.min_value=-20000 if key in ["X","Y"] else (-360 if key=="Rotation" else (0 if key=="Opacity %" else 40));number.max_value=360 if key=="Rotation" else (100 if key=="Opacity %" else 20000);number.step=1;number.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(number);fields[key]=number
		number.value_changed.connect(update_value.bind(key))
	var aspect:=Label.new();aspect.text="Resize preserves aspect ratio. Transforms require Layout + Background Edit.";aspect.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rows.add_child(aspect)
	for item: String in ["Fit","Fill","Reset Transform"]:
		button(rows,item,func() -> void:
			if not appearance.editing or not appearance.manager.layout.edit_mode: appearance.tell("Enable Layout and Background Edit first.");return
			if item=="Reset Transform": appearance.reset_transform()
			else: appearance.fit(item=="Fill")
			refresh_fields())
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rows.add_child(status)
	button(rows,"Close",hide)
func open() -> void:
	refresh_fields();popup_centered_clamped(Vector2i(480,620),0.9)
func refresh_fields() -> void:
	if fields.is_empty(): return
	refreshing=true
	var v: Dictionary=appearance.background;color.color=Color(v.color);lock.button_pressed=v.locked
	var values: Array=[v.position[0],v.position[1],v.size[0],v.size[1],v.rotation,v.opacity*100]
	var i: int=0
	for key: String in fields:
		fields[key].value=values[i];fields[key].editable=appearance.editing and appearance.manager.layout.edit_mode and (not v.locked or key=="Opacity %");i+=1
	status.text="Background Edit: "+("ON" if appearance.editing else "OFF")+" · "+("Locked" if v.locked else "Unlocked")
	refreshing=false
func update_value(value: float,key: String) -> void:
	if refreshing: return
	if not appearance.editing or not appearance.manager.layout.edit_mode or (appearance.background.locked and key!="Opacity %"): refresh_fields();return
	var next: Dictionary=appearance.background.duplicate(true)
	match key:
		"X": next.position[0]=value
		"Y": next.position[1]=value
		"Width": next.size=[value,clampf(next.size[1]*value/next.size[0],40,20000)]
		"Height": next.size=[clampf(next.size[0]*value/next.size[1],40,20000),value]
		"Rotation": next.rotation=value
		"Opacity %": next.opacity=value/100
	appearance.apply(next);refresh_fields()
