extends RefCounted
signal changed
const THEMES = {"CardLink Blue":Color("152d40"),"Dark":Color("171d23"),"Neutral Gray":Color("35383c"),"Green Felt":Color("173c2f"),"Black":Color("090b0d")}
var path: String
var config := ConfigFile.new()
func _init(file: String = "user://table_preferences.cfg") -> void:
	path = file
	config.load(path)
func value(key: String, fallback: Variant) -> Variant: return config.get_value("table",key,fallback)
func put(key: String, data: Variant) -> void:
	config.set_value("table",key,data)
	preload("res://scripts/card_storage.gd").write_atomic(path,config.encode_to_text().to_utf8_buffer())
	changed.emit()
func build(rows: Node, make_button: Callable) -> void:
	for entry: Array in [["Hand layout","hand_layout",["Straight","Overlap","Fan"]],["Opponent hand","opponent_layout",["Straight","Overlap","Compact"]],["Table theme","theme",THEMES.keys()]]:
		var label := Label.new()
		label.text = entry[0]
		rows.add_child(label)
		var picker := OptionButton.new()
		for caption: String in entry[2]: picker.add_item(caption)
		picker.select(maxi(0,entry[2].find(value(entry[1],entry[2][0]))))
		picker.item_selected.connect(func(index: int) -> void: put(entry[1],picker.get_item_text(index)))
		rows.add_child(picker)
	var gameplay := Label.new()
	gameplay.text = "Gameplay · Offline Playtest"
	rows.add_child(gameplay)
	for option: Array in [["Auto-switch perspective on End Turn","auto_perspective",true]]:
		var toggle := CheckBox.new()
		toggle.text = option[0]
		toggle.button_pressed = bool(value(option[1],option[2]))
		toggle.toggled.connect(func(enabled: bool) -> void: put(option[1],enabled))
		rows.add_child(toggle)
	var display := Label.new()
	display.text = "Display"
	rows.add_child(display)
	var reduce := CheckBox.new()
	reduce.text = "Reduce Motion"
	reduce.button_pressed = bool(value("reduce_motion",false))
	reduce.toggled.connect(func(enabled: bool) -> void: put("reduce_motion",enabled))
	rows.add_child(reduce)
	var opacity_label := Label.new()
	opacity_label.text = "Hand Background Opacity · %d%%" % roundi(float(value("hand_opacity",0.5))*100)
	rows.add_child(opacity_label)
	var opacity := HSlider.new()
	opacity.min_value = 0.2
	opacity.max_value = 1.0
	opacity.step = 0.05
	opacity.value = float(value("hand_opacity",0.5))
	opacity.value_changed.connect(func(amount: float) -> void:
		put("hand_opacity",amount)
		opacity_label.text = "Hand Background Opacity · %d%%" % roundi(amount*100))
	rows.add_child(opacity)
	var label := Label.new()
	label.text = "Hand card scale"
	rows.add_child(label)
	var scale := HSlider.new()
	scale.min_value = 0.65
	scale.max_value = 1.4
	scale.step = 0.05
	scale.value = float(value("hand_scale",1.0))
	scale.value_changed.connect(func(amount: float) -> void: put("hand_scale",amount))
	rows.add_child(scale)
