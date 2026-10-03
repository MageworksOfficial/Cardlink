extends SceneTree
var failures: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, caption: String) -> void:
	print(("PASS " if ok else "FAIL ")+caption)
	if not ok: failures+=1
func run() -> void:
	var app: Control=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app.tabletop.set_active(false);app.deck_builder.open_builder()
	var deck: Control=app.deck_builder
	deck.name_input.text="Unsaved live acceptance";deck.dirty=true
	deck.online_search_button.pressed.emit()
	var hub: Node=root.get_node("OptionalCardCatalog")
	hub.client.enabled=true
	var window: Window=hub.window
	window.filters.colors.Red.button_pressed=true
	window.filters.fields.type.select(1);window.filters.fields.min.text="3";window.filters.fields.max.text="6"
	window.filters.update_summary()
	await window.run_search()
	check(not window.cards.is_empty(),"Live Scryfall red creature MV 3–6 search")
	if window.cards.is_empty(): print(window.status.text);app.queue_free();hub.queue_free();await process_frame;quit(1);return
	check(window.results.get_item_icon(0)!=null,"Live selected results have previews")
	window.results.select(0);window.select_result(0)
	await window.add_selected()
	for i: int in 8: await process_frame
	check(not window.imported_id.is_empty() and deck.records.size()==1,"Live import immediately refreshes open Deck Builder")
	check(deck.name_input.text=="Unsaved live acceptance" and deck.dirty,"Live import preserves unsaved deck")
	window.add_to_current_deck()
	check(deck.deck.cards.size()==1 and deck.deck.cards[0].card_id==window.imported_id,"Live Add to Current Deck")
	var id: String=window.imported_id
	window.add_to_current_deck()
	check(deck.deck.cards.size()==1 and deck.deck.cards[0].quantity==2,"Live direct add increments quantity")
	print("Imported one printing into isolated test profile only: ",id)
	check(hub.client.SPACING>=0.65,"Shared provider queue still throttles")
	app.queue_free();hub.queue_free()
	for i: int in 8: await process_frame
	quit(0 if failures==0 else 1)
