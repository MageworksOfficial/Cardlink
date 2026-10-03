extends Node
## Discover existing commands; never scans private card identities itself.
var shell: Control
var window: Window
var query: LineEdit
var results: ItemList
var hint: Label
var watch_elapsed: float = 0
var entries: Array = []
var visible_entries: Array = []
func _ready() -> void:
	window=Window.new();window.title="Find Cards & Functions · Ctrl+F";window.visible=false;window.exclusive=true
	window.close_requested.connect(window.hide);add_child(window)
	var rows := VBoxContainer.new();window.add_child(rows);rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left=16;rows.offset_right=-16;rows.offset_top=16;rows.offset_bottom=-16
	query=LineEdit.new();query.placeholder_text="Find a function: search library, hand, token, dice, save…";rows.add_child(query)
	query.text_changed.connect(func(_text: String) -> void: filter_entries())
	query.text_submitted.connect(func(_text: String) -> void: activate())
	results=ItemList.new();results.size_flags_vertical=Control.SIZE_EXPAND_FILL;rows.add_child(results)
	results.item_activated.connect(func(index: int) -> void: activate(index))
	hint=Label.new();hint.text="Enter to open · ↑/↓ to choose · Esc to close";rows.add_child(hint)
	var close := Button.new();close.text="Close";close.pressed.connect(window.hide);rows.add_child(close)
	window.window_input.connect(palette_input)
func add(caption: String, words: String, action: Callable) -> void:
	for row: Dictionary in entries:
		if row.caption==caption: return
	entries.append({"caption":caption,"words":(caption+" "+words).to_lower(),"action":action})
func build_entries() -> void:
	entries.clear()
	add("Settings","nickname controls shortcuts",shell.shared_settings.open)
	if shell.table_scene==null:
		add("Deck Builder","cards collection import deck back",shell.open_deck_workspace)
		return
	var main: Control=shell.table_scene
	var m: Node=main.tabletop
	var c: Node=m.match_controller
	add("Search Card Collection","find cards import library",func() -> void: main.open_library();focus(main.library.query))
	add("Deck Builder","deck cards quantities import",main.open_deck_builder)
	add("Online Card Search (Scryfall)","find cards internet optional provider",func() -> void: preload("res://scripts/integrations/integration_hub.gd").open(main.library))
	for player: String in ["local","opponent"]:
		var label: String=c.model.players[player].display_name
		add("Search Library — "+label,"deck find inspect shuffle",m.controls.inspect.bind(player,"library"))
		add("Search Hand — "+label,"find inspect cards",m.controls.inspect.bind(player,"hand"))
	for caption: String in m.extras.FUNCTIONS:
		if caption=="Multiplayer / Network" and c.playtest.local_playtest(): continue
		if caption=="Table Components" and not m.custom_table.enabled: continue
		if caption.begins_with("Search /"): continue
		add(caption,"",m.extras.choose.bind(caption))
	for action: String in m.shortcuts.bindings.ACTIONS:
		if action.begins_with("pan_") or action in ["mode","table_builder"]: continue
		add(str(m.shortcuts.bindings.ACTIONS[action][0]),action.replace("_"," "),m.shortcuts.dispatcher.execute.bind(action))
	for panel: String in ["Card","Hand","Library","Zones","Counter","Life","Layout"]:
		add(panel+" Actions", "mill scry reveal top bottom" if panel=="Library" else "",m.controls.open_panel.bind(panel))
	add("Change Deck Back","card back sleeve deck sleeve back cover",m.appearance.sleeves.open)
	add("Change Battlefield Background","background battlefield table background playmat board floor image",m.appearance.open)
	add("Edit Battlefield Background","background transform",m.appearance.toggle_edit)
	add("Reset Battlefield Background","default playmat",m.appearance.reset_background)
	add("Arrange Selected","arrange organize stack fan line up spread distribute",m.selection.arrange.open)
	add("Create Token","name art power toughness",m.extras.choose.bind("Token"))
	add("Loyalty Counter","add remove plus minus card",func() -> void: preload("res://scripts/battle/loyalty.gd").open(m))
	add("Reset Match / Rematch…","restart game",m.battle.reset.open)
	add("Dice / Coin / Calculator","tools d6 d20 roll",m.extras.choose.bind("Tools"))
	if m.custom_table.enabled:
		add("Search Table Components","build zones objects",m.custom_table.editor.focus_search)
		for row: Dictionary in m.custom_table.document.components:
			add("Component: "+row.name,row.kind,m.custom_table.panel.open_component.bind(row.id))
func focus(field: LineEdit) -> void:
	field.grab_focus();field.select_all()
func filter_entries() -> void:
	results.clear();visible_entries.clear()
	var terms: PackedStringArray=query.text.to_lower().split(" ",false)
	for row: Dictionary in entries:
		var matches: bool=true
		for term: String in terms:
			if not row.words.contains(term): matches=false;break
		if matches: visible_entries.append(row);results.add_item(row.caption)
	if results.item_count>0: results.select(0)
	hint.text="No matching function. Try library, hand, token, tools or save." if results.item_count==0 else "Enter to open · ↑/↓ to choose · Esc to close"
func activate(index: int=-1) -> void:
	if index<0:
		var chosen: PackedInt32Array=results.get_selected_items()
		if chosen.is_empty(): return
		index=chosen[0]
	if index>=visible_entries.size(): return
	var action: Callable=visible_entries[index].action
	window.hide()
	if shell.table_scene!=null and not shell.table_scene.tabletop.active: return
	if action.is_valid(): action.call_deferred()
func other_window(node: Node) -> bool:
	for child: Node in node.get_children():
		if child==window: continue
		if child is Window and child.visible and child.name!="PrivateHandWindow": return true
		if other_window(child): return true
	return false
func open() -> void:
	if shell.entering: return
	if window.visible: focus(query);return
	# Existing searches retain their context and do not open a second overlay.
	var hub: Node=get_tree().root.get_node_or_null("OptionalCardCatalog")
	if hub!=null and hub.window!=null and hub.window.visible: focus(hub.window.query);return
	if shell.table_scene!=null:
		var main: Control=shell.table_scene
		if main.tabletop.match_controller.contents.visible: focus(main.tabletop.match_controller.contents_query);return
	if other_window(shell): return # Never bypass a confirmation, import, or private-access dialog.
	if is_instance_valid(shell.deck_workspace): focus(shell.deck_workspace.deck_builder.query);return
	if shell.table_scene!=null:
		var main: Control=shell.table_scene
		if main.deck_builder.visible: focus(main.deck_builder.query);return
		if main.library.visible: focus(main.library.query);return
		if not main.tabletop.active: return
	build_entries();query.text="";filter_entries()
	window.popup_centered_clamped(Vector2i(660,480),0.9);focus(query)
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and event.keycode==KEY_F:
		get_viewport().set_input_as_handled();open()
func palette_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	if event.keycode==KEY_ESCAPE: window.hide();window.set_input_as_handled()
	elif event.ctrl_pressed and event.keycode==KEY_F: focus(query);window.set_input_as_handled()
	elif event.keycode in [KEY_UP,KEY_DOWN] and query.has_focus() and results.item_count>0:
		var chosen: PackedInt32Array=results.get_selected_items()
		var index: int=chosen[0] if not chosen.is_empty() else 0
		results.select(clampi(index+(-1 if event.keycode==KEY_UP else 1),0,results.item_count-1));results.ensure_current_is_visible();window.set_input_as_handled()

func _process(delta: float) -> void:
	watch_elapsed+=delta
	if watch_elapsed<0.2: return
	watch_elapsed=0
	if shell.table_scene!=null:
		var c: Node=shell.table_scene.tabletop.match_controller
		if c!=null:
			watch(c.contents)
			if c.hand_window!=null: watch(c.hand_window.window)
	var hub: Node=get_tree().root.get_node_or_null("OptionalCardCatalog")
	if hub!=null and hub.window!=null: watch(hub.window)
func watch(target: Window) -> void:
	var handler: Callable=subwindow_input.bind(target)
	if target!=null and not target.window_input.is_connected(handler): target.window_input.connect(handler)
func subwindow_input(event: InputEvent,target: Window) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and event.keycode==KEY_F:
		open();target.set_input_as_handled()
