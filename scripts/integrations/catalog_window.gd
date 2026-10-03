extends Window
const Record = preload("res://scripts/integrations/scryfall_record.gd")
var hub: Node
var tabs: TabContainer
var status: Label
var query: LineEdit
var exact: CheckBox
var local_only: CheckBox
var results: ItemList
var add_button: Button
var deck_button: Button
var imported_id: String = ""
var import_context: WeakRef
var filters: VBoxContainer
var search_options: Dictionary = {}
var cards: Array = []
var page: int = 0
var api_page: int = 1
var more_api: bool = false
var printing: Dictionary = {}
var busy: bool = false
var generation: int = 0
var deck_ui: Node
var enabled_box: CheckBox
var date_label: Label
func button(rows: Node, text: String, callback: Callable) -> Button:
	var item := Button.new(); item.text=text; item.pressed.connect(callback); rows.add_child(item); return item
func label(rows: Node, text: String) -> Label:
	var item := Label.new(); item.text=text; item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; rows.add_child(item); return item
func _ready() -> void:
	title="Online Card Search · Optional Scryfall"
	visible=false
	close_requested.connect(close)
	var rows := VBoxContainer.new(); add_child(rows)
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left=16; rows.offset_top=16; rows.offset_right=-16; rows.offset_bottom=-16
	label(rows,"Magic: The Gathering · Data and images from Scryfall")
	label(rows,"Third-party card data/images belong to their respective rights holders. CardLink is an unofficial, free, open-source tabletop sandbox, not affiliated with or endorsed by Wizards of the Coast or Scryfall.")
	tabs=TabContainer.new(); tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; rows.add_child(tabs)
	var search_rows := VBoxContainer.new(); search_rows.name="Card Search"; tabs.add_child(search_rows)
	var search_bar := HBoxContainer.new(); search_rows.add_child(search_bar)
	query=LineEdit.new(); query.placeholder_text="Card name or Scryfall query"; query.size_flags_horizontal=Control.SIZE_EXPAND_FILL; query.max_length=200; search_bar.add_child(query)
	query.text_submitted.connect(func(_value: String) -> void: run_search())
	exact=CheckBox.new(); exact.text="Exact"; search_bar.add_child(exact)
	local_only=CheckBox.new(); local_only.text="Local metadata"; search_bar.add_child(local_only)
	button(search_bar,"Search",run_search)
	filters=preload("res://scripts/integrations/scryfall_filters.gd").new()
	filters.catalog_rows=hub.catalog.rows
	var filter_scroll := ScrollContainer.new()
	filter_scroll.custom_minimum_size.y=160
	filter_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	search_rows.add_child(filter_scroll)
	filters.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	filter_scroll.add_child(filters)
	# Keep the active summary visible even when the advanced fields scroll.
	filters.remove_child(filters.summary)
	search_rows.add_child(filters.summary)
	label(search_rows,"Search loads small previews for the visible results only. Add to Library downloads the selected printing's full faces.")
	results=ItemList.new(); results.size_flags_vertical=Control.SIZE_EXPAND_FILL; results.max_columns=4; results.fixed_column_width=218; results.fixed_icon_size=Vector2i(105,147); results.icon_mode=ItemList.ICON_MODE_TOP; results.same_column_width=true
	results.max_text_lines=4
	search_rows.add_child(results)
	results.item_selected.connect(select_result)
	var actions := HFlowContainer.new(); search_rows.add_child(actions)
	button(actions,"Previous",func() -> void: if not busy and page>0: page-=1; render())
	button(actions,"Next",next_page)
	button(actions,"Choose Printing",choose_printing)
	add_button=button(actions,"Add to Library",add_selected)
	button(actions,"Use for Selected Deck Entry",use_for_deck)
	deck_button=button(actions,"Add to Current Deck",add_to_current_deck)
	deck_button.hide()
	deck_ui=preload("res://scripts/integrations/decklist_panel.gd").new(); deck_ui.host=self; tabs.add_child(deck_ui)
	var settings := VBoxContainer.new(); settings.name="Integrations"; tabs.add_child(settings)
	enabled_box=CheckBox.new(); enabled_box.text="Enable Online MTG Catalog"; enabled_box.button_pressed=hub.client.enabled; settings.add_child(enabled_box)
	enabled_box.toggled.connect(func(value: bool) -> void:
		status.text="Preference saved." if hub.set_enabled(value)==OK else "Could not save preference."
		if not value: generation+=1)
	label(settings,"Optional direct HTTPS access to Scryfall. Only requested card queries are sent; no match history, hand state or opponent information. Nothing downloads just by enabling this option.")
	date_label=label(settings,"Metadata catalog: "+hub.catalog.updated)
	label(settings,"Update downloads compressed Oracle metadata (typically tens of MB), not images. It provides one representative printing per name for offline lookup. Other printings remain available through online Choose Printing. Update only when you want newer releases.")
	button(settings,"Check / Update Metadata Catalog",update_catalog)
	button(settings,"Clear Metadata Catalog",func() -> void:
		if not busy: hub.catalog.clear(); date_label.text="Metadata catalog: Not downloaded")
	button(settings,"Clear Search / Preview Cache",func() -> void:
		if not busy: hub.client.cache.clear(); status.text="Search and preview cache cleared. Imported cards are kept.")
	label(settings,"Search/preview cache: up to 256 entries / 32 MB, refreshed after 24 hours. Imported card assets stay in your normal local collection and work offline.")
	status=label(rows,"Enable the optional provider in Integrations, or search an existing local metadata catalog.")
	var footer := HBoxContainer.new(); rows.add_child(footer)
	button(footer,"Cancel Operation",cancel)
	button(footer,"Close",close)
	hub.importer.progress.connect(func(message: String) -> void: status.text=message)
	hub.catalog.progress.connect(func(message: String) -> void: status.text=message)
	preload("res://scripts/frontend/frontend_theme.gd").skin_window(self)
func cancel() -> void:
	generation+=1; hub.cancel(); status.text="Cancelling. Completed library cards are kept; unfinished decks are not saved."
func close() -> void: cancel(); hide()
func run_search() -> void:
	if busy: return
	search_options = filters.build(query.text,exact.button_pressed)
	if search_options.has("error"): status.text=search_options.error; return
	if local_only.button_pressed and search_options.filtered:
		status.text="Local metadata supports name search only. Clear Filters or turn off Local metadata."; return
	search_options["name"]=query.text
	search_options["exact"]=exact.button_pressed
	printing={}; api_page=1; page=0
	await fetch_results()
func fetch_results() -> void:
	busy=true; status.text="Searching…"; generation+=1
	var token: int = generation
	if local_only.button_pressed:
		cards=hub.catalog.search_local(query.text,exact.button_pressed); more_api=false
	else:
		var response: Dictionary
		if not printing.is_empty(): response=await hub.client.get_printings(printing,api_page)
		elif search_options.get("filtered",false): response=await hub.client.search_sorted(search_options.query,api_page,search_options.order)
		elif search_options.get("exact",exact.button_pressed): response=await hub.client.resolve_card({"name":search_options.get("name",query.text)})
		else: response=await hub.client.search(search_options.get("name",query.text),api_page)
		if token!=generation: busy=false; return
		if response.has("error"): status.text=response.error; busy=false; return
		cards.clear()
		var incoming: Variant = response.data.get("data",[response.data])
		if not incoming is Array: status.text="Invalid search response."; busy=false; return
		var raw: Array = incoming
		for item: Variant in raw:
			var record: Dictionary = Record.compact(item)
			if not record.is_empty(): cards.append(record)
		more_api=bool(response.data.get("has_more",false))
	busy=false
	await render()
func render() -> void:
	generation+=1; var token: int = generation
	results.clear(); add_button.disabled=true; deck_button.hide()
	var shown: Array = cards.slice(page*12,mini(cards.size(),page*12+12))
	for card: Dictionary in shown:
		results.add_item("%s\n%s · #%s · %s" % [card.name,card.set.to_upper(),card.collector_number,card.lang])
	status.text="%d results on this provider page · preview page %d" % [cards.size(),page+1]
	for i: int in shown.size():
		if token!=generation or not visible: return
		if not hub.client.enabled: continue
		var response: Dictionary = await hub.client.fetch_image(shown[i].faces[0].thumbnail,true)
		if token!=generation or not is_instance_valid(results): return
		if response.has("error"): continue
		var image := Image.new()
		if image.load_jpg_from_buffer(response.bytes)==OK: results.set_item_icon(i,ImageTexture.create_from_image(image))
func selected() -> Dictionary:
	var indices: PackedInt32Array = results.get_selected_items()
	return cards[page*12+indices[0]] if not indices.is_empty() and page*12+indices[0]<cards.size() else {}
func select_result(_index: int) -> void:
	var card: Dictionary = selected()
	if card.is_empty(): return
	imported_id = str(hub.importer.existing_id(card.id).get("card_id",""))
	import_context = hub.context_owner
	var exists: bool = not imported_id.is_empty()
	deck_button.visible = exists and preload("res://scripts/collection_workflow.gd").valid_deck(import_context) != null
	add_button.text="Already in Library" if exists else "Add to Library"
	add_button.disabled=exists
	status.text="%s · %s · #%s · %s" % [card.name,card.set_name,card.collector_number,card.lang]
func next_page() -> void:
	if busy: return
	if (page+1)*12<cards.size(): page+=1; await render()
	elif more_api: api_page+=1; page=0; await fetch_results()
func choose_printing() -> void:
	if busy or selected().is_empty(): return
	printing=selected(); api_page=1; page=0; local_only.button_pressed=false
	await fetch_results()
func add_selected() -> void:
	if busy or selected().is_empty(): return
	busy=true; hub.importer.cancelled=false
	var context: WeakRef = hub.context_owner
	var card: Dictionary = selected()
	var response: Dictionary = await hub.importer.import_card(card)
	busy=false
	if response.has("error"): status.text=response.error; return
	imported_id = str(response.metadata.card_id)
	import_context = context
	add_button.text="Already in Library"; add_button.disabled=true
	deck_button.visible = preload("res://scripts/collection_workflow.gd").valid_deck(import_context) != null
	status.text="Card added to your library: "+str(card.name)
func use_for_deck() -> void:
	if busy or selected().is_empty(): return
	deck_ui.choose(selected()); tabs.current_tab=1
func update_catalog() -> void:
	if busy: return
	busy=true
	var response: Dictionary = await hub.catalog.update_catalog()
	date_label.text="Metadata catalog: "+hub.catalog.updated
	status.text=response.error if response.has("error") else "Metadata catalog ready. No images downloaded."
	busy=false

func add_to_current_deck() -> void:
	var deck: Node = preload("res://scripts/collection_workflow.gd").valid_deck(import_context)
	if deck != null and not imported_id.is_empty() and deck.add_imported_card(imported_id):
		status.text="Card added to current deck."
