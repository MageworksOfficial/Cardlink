extends PanelContainer
var editor: Node
var search: LineEdit
var rows: VBoxContainer
var content: VBoxContainer
var tools: VBoxContainer
var confirm: ConfirmationDialog
var destination: OptionButton
var remove_id: String = ""
const HINTS = {"deck":"An ordered pile of cards owned by one player.","shared_deck":"One central deck used by multiple players.","hand":"A private card area for one player.","zone":"A named area for organizing the table.","board":"Place an image underneath the table.","shared_area":"A public area shared by all players.","discard":"A public discard pile, shared or player-owned."}
func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102b40")
	style.border_color = Color("368aa5")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel",style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := Label.new()
	title.text = "TABLE BUILDER"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	editor.add_button(header,"×",func() -> void: hide(); editor.refresh()).tooltip_text = "Collapse Table Builder"
	search = LineEdit.new()
	search.placeholder_text = "Search components..."
	search.tooltip_text = "Search component types here · Ctrl+F finds cards and functions"
	rows.add_child(search)
	search.text_changed.connect(func(_value: String) -> void: refresh_content())
	tools = VBoxContainer.new()
	rows.add_child(tools)
	content = VBoxContainer.new()
	rows.add_child(content)
	confirm = ConfirmationDialog.new()
	confirm.title = "Remove component safely"
	confirm.ok_button_text = "Return to Battlefield"
	confirm.add_button("Move to Another Pile",false,"move")
	destination = OptionButton.new()
	confirm.add_child(destination)
	destination.position = Vector2(16,85)
	destination.custom_minimum_size = Vector2(330,35)
	confirm.confirmed.connect(func() -> void: editor.builder.remove_component(remove_id,true); editor.notify("Cards returned to the battlefield."))
	confirm.custom_action.connect(func(action: StringName) -> void:
		if action != "move" or destination.selected < 0: return
		var target: String = destination.get_selected_metadata()
		if relocate(remove_id,target): confirm.hide())
	add_child(confirm)
func clear(parent: Node) -> void:
	for child: Node in parent.get_children(): parent.remove_child(child); child.queue_free()
func heading(text: String, parent: Node) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color",Color("82cada"))
	parent.add_child(label)
func button(parent: Node, text: String, action: Callable) -> Button:
	var b: Button = editor.add_button(parent,text,action)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b
func refresh() -> void:
	if content == null: return
	refresh_tools()
	refresh_content()
func refresh_tools() -> void:
	clear(tools)
	var b: Node = editor.builder
	var item: Dictionary = b.row(editor.selected)
	if item.is_empty(): return
	heading("SELECTED · "+editor.badge(item.owner),tools)
	var name_input := LineEdit.new()
	name_input.text = item.name
	name_input.max_length = 80
	name_input.tooltip_text = "Rename: press Enter to apply"
	tools.add_child(name_input)
	name_input.text_submitted.connect(func(value: String) -> void: b.update_component(item.id,{"name":value}); editor.notify("Component renamed."))
	var owner := OptionButton.new()
	for id: String in (["table"] if item.kind == "shared_deck" else (["player_1","player_2"] if item.kind == "hand" else b.Doc.OWNERS)):
		owner.add_item(editor.badge(id))
		owner.set_item_metadata(owner.item_count-1,id)
		if id == item.owner: owner.select(owner.item_count-1)
	owner.tooltip_text = "Owner · occupied online piles cannot change owner"
	owner.item_selected.connect(func(index: int) -> void:
		if not b.update_component(item.id,{"owner":owner.get_item_metadata(index)}): editor.notify("Empty the online pile before changing its owner."); refresh())
	tools.add_child(owner)
	var actions := GridContainer.new()
	actions.columns = 2
	tools.add_child(actions)
	button(actions,"Unlock" if item.locked else "Lock",func() -> void: b.update_component(item.id,{"locked":not item.locked}); editor.notify("Component unlocked." if item.locked else "Component locked."))
	button(actions,"Show" if item.hidden else "Hide",func() -> void: b.update_component(item.id,{"hidden":not item.hidden}))
	button(actions,"Duplicate",func() -> void: editor.duplicate_component(item.id))
	button(actions,"Other Player",func() -> void: editor.duplicate_component(item.id,true)).disabled = item.owner == "table"
	button(actions,"Remove",remove_selected)
	button(actions,"More / Resize…",func() -> void: b.panel.open_component(item.id))
	if item.kind in ["deck","shared_deck"]:
		button(tools,"✓ Primary Draw" if item.linked_pile == item.id else ("Use as Shared Draw" if item.owner == "table" else "Set Primary Draw"),func() -> void: b.set_primary(item.id); editor.notify("Primary Draw set to "+item.name+"."))
		button(tools,"Load Saved Deck",func() -> void: b.panel.deck_list(item.id); b.panel.show_panel())
	if item.kind == "board": button(tools,"Choose Board Image",func() -> void: b.panel.open_component(item.id); b.panel.choose_file("board"))
func refresh_content() -> void:
	clear(content)
	var b: Node = editor.builder
	var query: String = search.text.strip_edges().to_lower()
	heading("QUICK ADD",content)
	var grid := GridContainer.new()
	grid.columns = 2
	content.add_child(grid)
	for kind: String in b.Doc.TYPES + ["counter","token"]:
		var caption: String = {"deck":"Deck / Pile","hand":"Hand","zone":"Custom Zone","shared_deck":"Shared Deck","discard":"Shared Discard","board":"Board Image","counter":"Counter","token":"Token","text":"Text Label","leader":"Leader Zone","shared_area":"Shared Area"}[kind]
		if not b.Doc.matches({"name":caption,"kind":kind},query): continue
		button(grid,"+ "+caption,func() -> void: editor.begin_placement(kind)).tooltip_text = HINTS.get(kind,"Place a "+caption.to_lower()+" on the table.")
	heading("ON TABLE",content)
	for item: Dictionary in b.document.components:
		var line := HBoxContainer.new()
		content.add_child(line)
		var eye := CheckBox.new()
		eye.button_pressed = not item.hidden
		eye.tooltip_text = "Show / Hide · object stays in this list"
		eye.toggled.connect(func(value: bool) -> void: b.update_component(item.id,{"hidden":not value}))
		line.add_child(eye)
		var caption: String = editor.badge(item.owner)+" · "+item.name+(" [LOCK]" if item.locked else "")
		if item.kind in ["deck","shared_deck"] and item.id in [b.primary_for("player_1"),b.primary_for("player_2")]: caption += " [DRAW]"
		button(line,caption,func() -> void: editor.select_component(item.id)).modulate = editor.accent(item.owner)
	if b.document.components.is_empty(): heading("No components yet. Choose Quick Add.",content)
	button(content,"+ Add Component",func() -> void: search.grab_focus())
	button(content,"Lock All Components",func() -> void: editor.lock_all(true))
	button(content,"Unlock All Components",func() -> void: editor.lock_all(false))
	button(content,"Save Table",func() -> void: b.panel.template_form(false))
	button(content,"My Tables",func() -> void: editor.templates.open_manager())
func remove_selected() -> void:
	var b: Node = editor.builder
	remove_id = editor.selected
	var count: int = b.orders.get(remove_id,[]).size()
	if b.pile_sync.connected() and b.pile_sync.remote_counts.get(remove_id,0)>0 and not b.pile_sync.owns(b.row(remove_id)):
		editor.notify("The player holding this pile must empty or remove it.")
		return
	if count == 0: b.remove_component(remove_id); editor.notify("Component removed."); return
	destination.clear()
	for item: Dictionary in b.document.components:
		if item.id != remove_id and item.kind in ["deck","shared_deck"] and (not b.pile_sync.connected() or b.pile_sync.owns(item)):
			destination.add_item(item.name)
			destination.set_item_metadata(destination.item_count-1,item.id)
	confirm.dialog_text = "This component contains %d cards.\nWhere should they go?\n\n\n" % count
	confirm.popup_centered(Vector2i(400,210))
func relocate(id: String, target: String) -> bool:
	var b: Node = editor.builder
	if b.row(target).is_empty() or id == target: return false
	for card_id: String in b.orders.get(id,[]).duplicate():
		if not b.put_card(b.manager.match_controller.card_by_id(card_id),target): editor.notify("Some cards could not move; component retained."); return false
	var ok: bool = b.remove_component(id)
	if ok: editor.notify("Cards moved; empty component removed.")
	return ok
