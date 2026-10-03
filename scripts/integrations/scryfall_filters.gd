extends VBoxContainer
const Query = preload("res://scripts/integrations/scryfall_query.gd")
var catalog_rows: Array = []
var fields: Dictionary = {}
var colors: Dictionary = {}
var summary: Label
var advanced: GridContainer
var advanced_button: Button
func field(parent: Node, key: String, caption: String, choices: Array = []) -> void:
	var label := Label.new(); label.text=caption; parent.add_child(label)
	if choices.is_empty():
		var input := LineEdit.new(); input.placeholder_text=caption; input.max_length=160; input.custom_minimum_size.x=120; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		parent.add_child(input); fields[key]=input; input.text_changed.connect(func(_text: String) -> void: update_summary())
	else:
		var input := OptionButton.new(); input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for choice: String in choices: input.add_item(choice)
		parent.add_child(input); fields[key]=input; input.item_selected.connect(func(_index: int) -> void: update_summary())
func _ready() -> void:
	var color_row := HFlowContainer.new(); add_child(color_row)
	for color: String in Query.COLORS:
		var box := CheckBox.new(); box.text=color; box.tooltip_text="Match any of the checked colors."; color_row.add_child(box); colors[color]=box
		box.toggled.connect(func(_on: bool) -> void: update_summary())
	var scroller := ScrollContainer.new(); scroller.custom_minimum_size.y=84; scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroller)
	var grid := GridContainer.new(); grid.columns=6; grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroller.add_child(grid)
	field(grid,"type","Card Type",Query.TYPES); field(grid,"min","MV Min"); field(grid,"max","MV Max")
	field(grid,"format","Format",Query.FORMATS); field(grid,"set","Set code (blank = Any)"); field(grid,"rarity","Rarity",Query.RARITIES)
	var known := MenuButton.new(); known.text="Known Sets"; known.tooltip_text="Sets from your downloaded local metadata, if available."
	var sets: Dictionary = {}
	for row: Dictionary in catalog_rows:
		if not str(row.get("set","")).is_empty(): sets[str(row.set)]=str(row.get("set_name",row.set))
	known.get_popup().add_item("Any Set")
	known.get_popup().set_item_metadata(0,"")
	var keys: Array = sets.keys(); keys.sort()
	for key: String in keys:
		known.get_popup().add_item(key.to_upper()+" · "+sets[key]); known.get_popup().set_item_metadata(known.get_popup().item_count-1,key)
	known.get_popup().id_pressed.connect(func(id: int) -> void: fields.set.text=str(known.get_popup().get_item_metadata(id)); update_summary())
	var row := HBoxContainer.new(); add_child(row)
	advanced_button=Button.new(); advanced_button.text="Advanced Filters ▾"; row.add_child(advanced_button)
	var clear := Button.new(); clear.text="Clear Filters"; clear.pressed.connect(clear_filters); row.add_child(clear)
	row.add_child(known)
	advanced=GridContainer.new(); advanced.columns=4; add_child(advanced)
	field(advanced,"identity","Commander identity (WUBRG/C)"); field(advanced,"oracle","Oracle Text Contains")
	field(advanced,"artist","Artist"); field(advanced,"number","Collector Number"); field(advanced,"order","Sort Order",Query.SORTS)
	advanced.hide(); advanced_button.pressed.connect(toggle_advanced)
	summary=Label.new(); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(summary); update_summary()
func toggle_advanced() -> void:
	advanced.visible=not advanced.visible
	advanced_button.text="Advanced Filters ▴" if advanced.visible else "Advanced Filters ▾"
	# Containers finish their new layout after the visibility change.
	await get_tree().process_frame
	await get_tree().process_frame
	if advanced.visible and get_parent() is ScrollContainer:
		get_parent().scroll_vertical=int(get_parent().get_v_scroll_bar().max_value)
func options() -> Dictionary:
	var result: Dictionary = {"colors":[]}
	for key: String in fields:
		var control: Control = fields[key]
		result[key]=control.get_item_text(control.selected) if control is OptionButton else control.text
	for key: String in colors:
		if colors[key].button_pressed: result.colors.append(key)
	return result
func build(name: String, exact: bool = false) -> Dictionary: return Query.build(name,options(),exact)
func update_summary() -> void:
	if summary==null: return
	var result: Dictionary = build("")
	summary.text=result.get("error",result.get("summary",""))
	summary.visible=not summary.text.is_empty()
func clear_filters() -> void:
	for control: Control in fields.values():
		if control is OptionButton: control.select(0)
		else: control.text=""
	for control: CheckBox in colors.values(): control.set_pressed_no_signal(false)
	advanced.hide(); advanced_button.text="Advanced Filters ▾"; update_summary()
