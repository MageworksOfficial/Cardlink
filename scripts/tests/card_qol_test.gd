extends SceneTree
const Q = preload("res://scripts/integrations/scryfall_query.gd")
const Events = preload("res://scripts/collection_events.gd")
const Existing = preload("res://scripts/tests/milestone_78_test.gd")
var failures: int = 0
var changes: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, caption: String) -> void:
	print(("PASS " if ok else "FAIL ")+caption)
	if not ok: failures+=1
func settle() -> void:
	for i: int in 8: await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or OS.get_cmdline_user_args().is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1152,760); root.gui_embed_subwindows=true
	if OS.get_cmdline_user_args().has("compact"): root.size=Vector2i(1152,648)
	var app: Control=load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await settle()
	app.tabletop.set_active(false)
	var deck: Control=app.deck_builder
	var library: Control=app.library
	library.open_library()
	check(library.empty_help.visible,"Empty library explains both import options")
	await capture("empty-library")
	library.custom_import_button.pressed.emit()
	var importer: Window=app.get_node("CardImporter")
	check(importer.visible and importer.context_owner.get_ref()==library,"Library opens existing custom importer")
	importer.hide(); library.hide(); deck.open_builder()
	deck.name_input.text="Unsaved classroom deck"; deck.format_input.text="custom format"; deck.dirty=true
	deck.custom_import_button.pressed.emit()
	check(importer.visible and importer.context_owner.get_ref()==deck,"Deck Builder opens the same importer")
	Events.shared.collection_changed.connect(func(_directory: String) -> void: changes+=1)
	var image := Image.create(750,1050,false,Image.FORMAT_RGB8); image.fill(Color("287c91"))
	image.save_png("user://Generic Test Card.png")
	importer.select_file("user://Generic Test Card.png")
	await settle(); await importer.confirm_crop(); await settle()
	var id: String=importer.last_definition.card_id
	check(changes>0 and deck.records.size()==1 and library.records.size()==1,"Custom import notifies both views without reopening")
	check(deck.dirty and deck.name_input.text=="Unsaved classroom deck" and deck.format_input.text=="custom format","Import preserves unsaved deck fields")
	check(importer.followup.visible and importer.followup.text=="Add to Current Deck","Custom success offers Add to Current Deck")
	await capture("custom-import-success")
	importer.followup.pressed.emit(); importer.followup.pressed.emit()
	check(deck.deck.cards.size()==1 and deck.deck.cards[0].quantity==2,"Add to Current Deck uses normal quantities, not duplicate rows")
	deck.deck.leaders.append(id); deck.refresh_entries()
	deck.save_current()
	var another: Dictionary=deck.storage.new_deck();another.deck_name="Another saved deck";another.cards=[{"card_id":id,"quantity":1}]
	deck.storage.save_deck(another);deck.refresh_saved();deck.deck_picker.select(deck.saved.size()-1)
	var selected_path: String=deck.saved[deck.deck_picker.selected].path
	deck.name_input.text="Still editing unsaved name";deck.format_input.text="unsaved format";deck.dirty=true
	var old_deck: Dictionary=deck.deck.duplicate(true)
	var path: String=deck.record_for(id).path
	var editor=preload("res://scripts/library_storage.gd").new()
	editor.update_metadata(path,"Renamed Fixture",["test"]); await settle()
	check(deck.deck==old_deck and deck.dirty and deck.records[0].name=="Renamed Fixture","Rename refresh preserves quantities and leaders")
	check(deck.saved[deck.deck_picker.selected].path==selected_path and deck.name_input.text=="Still editing unsaved name" and deck.format_input.text=="unsaved format","Refresh preserves saved-deck selection and unsaved field text")
	importer.adding_face=true; image.fill(Color.CORAL); image.save_png("user://back.png")
	importer.select_file("user://back.png"); await importer.confirm_crop(); await settle()
	check(deck.record_for(id).metadata.faces.size()==2,"Adding face refreshes the existing definition")
	importer.hide(); await settle(); await capture("deck-after-custom-import")
	var alien=preload("res://scripts/card_storage.gd").new("user://other_cards")
	alien.save_card(image.save_png_to_buffer(),"Other collection",image.get_size()); await settle()
	check(deck.records.size()==1,"Collection notification does not mix unrelated storage roots")
	var hub=preload("res://scripts/integrations/integration_hub.gd").new(); hub.name="OptionalCardCatalog";root.add_child(hub)
	hub.context_owner=weakref(deck); hub.open_window()
	var window: Window=hub.window
	var filter: VBoxContainer=window.filters
	check(not filter.build("Dragon").filtered,"Plain name search has no filters")
	filter.colors.Red.button_pressed=true; filter.fields.type.select(1);filter.fields.min.text="3";filter.fields.max.text="6"
	var built: Dictionary=filter.build("")
	check(built.query.contains("c:r") and built.query.contains("t:creature") and built.query.contains("cmc>=3") and built.query.contains("cmc<=6"),"Combined red creature MV 3–6 query")
	filter.fields.format.select(1);filter.fields.set.text="tst";filter.fields.rarity.select(3)
	built=filter.build("Dragon")
	check(built.query.contains("f:commander") and built.query.contains('set:"tst"') and built.query.contains("r:rare"),"Format set and rarity query")
	filter.fields.identity.text="rg"; filter.fields.oracle.text="draw a card";filter.fields.artist.text="An Artist";filter.fields.number.text="12";filter.fields.order.select(1)
	built=filter.build("")
	check(built.query.contains("id<=rg") and built.query.contains('o:"draw a card"') and built.query.contains('a:"An Artist"') and built.query.contains('cn:"12"') and built.order=="cmc","Advanced provider filters and sort")
	check(hub.client.request_count==0,"Changing filters makes no network requests")
	filter.fields.min.text="oops"; await window.run_search()
	check(window.status.text.contains("Mana value") and hub.client.request_count==0,"Invalid MV rejected before network")
	filter.fields.min.text="8";filter.fields.max.text="2"
	check(filter.build("").has("error"),"Inverted MV range rejected")
	filter.clear_filters()
	check(not filter.build("Dragon").filtered and not filter.advanced.visible and deck.deck==old_deck,"Clear Filters resets search without touching deck")
	check(Q.build("",{"colors":["Colorless","Multicolor"]}).query=="(c:c or c:m)","Colorless and multicolor provider syntax")
	filter.colors.Red.button_pressed=true;filter.fields.type.select(1);filter.fields.min.text="3";filter.fields.max.text="6"
	filter.update_summary();window.status.text="Configure filters, then press Search."
	await settle();await capture("online-basic-filters")
	filter.advanced_button.pressed.emit();await settle();await capture("online-advanced-filters")
	check(filter.get_parent().scroll_vertical>0,"Advanced fields scroll into view when opened")
	check(window.position.y>=0 and window.position.y+window.size.y<=root.size.y,"Search window stays within screen bounds with advanced filters open")
	var fake=Existing.FakeProvider.new();root.add_child(fake)
	fake.images["https://cards.scryfall.io/front.png"]=image.save_png_to_buffer()
	image.fill(Color.PURPLE);fake.images["https://cards.scryfall.io/back.png"]=image.save_png_to_buffer()
	hub.importer.client=fake
	var fixture_builder=Existing.new()
	var raw: Dictionary=fixture_builder.fixture("qol-single","Online Fixture")
	var record: Dictionary=preload("res://scripts/integrations/scryfall_record.gd").compact(raw)
	window.cards=[record];window.page=0;window.results.clear();window.results.add_item("Online Fixture");window.results.select(0)
	await window.add_selected();await settle()
	check(deck.records.size()==2 and library.records.size()==2 and deck.deck==old_deck,"Online Add to Library refreshes both views with unsaved deck intact")
	check(window.deck_button.visible,"Online success offers Add to Current Deck")
	window.deck_button.pressed.emit()
	check(deck.deck.cards.size()==2 and deck.deck.cards[1].card_id==window.imported_id,"Online direct add references imported definition")
	var multi: Dictionary=fixture_builder.fixture("qol-double","Two Face Fixture",true)
	var result: Dictionary=await hub.importer.import_card(preload("res://scripts/integrations/scryfall_record.gd").compact(multi));await settle()
	check(not result.has("error") and result.metadata.faces.size()==2 and deck.records.size()==3,"Online multi-face refresh regression")
	var deck_raw: Dictionary=fixture_builder.fixture("qol-decklist","Decklist Fixture")
	fake.data={"Decklist Fixture":deck_raw}
	var plan: Array=await hub.importer.resolve(preload("res://scripts/integrations/decklist_parser.gd").parse("2 Decklist Fixture").entries)
	result=await hub.importer.commit(plan,"Imported Fixture Deck");await settle()
	check(not result.has("error") and deck.records.size()==4 and library.records.size()==4,"Decklist commit refreshes both views")
	var zipper := ZIPPacker.new();zipper.open("user://QoL.zip");zipper.start_file("nested/ZIP Fixture.png");zipper.write_file(image.save_png_to_buffer());zipper.close_file();zipper.close()
	var archive=preload("res://scripts/archive_import_service.gd").new()
	archive.reset_job();var preview: Dictionary=archive.preview("user://QoL.zip")
	var worker := Thread.new();worker.start(archive.commit.bind(preview))
	while worker.is_alive(): await process_frame
	result=worker.wait_to_finish();await settle()
	check(not result.has("error") and deck.records.size()==5 and library.records.size()==5,"ZIP worker commit refreshes both views on main thread")
	editor.delete_definition(path);await settle()
	check(deck.records.size()==4 and library.records.size()==4 and deck.deck.cards[0].quantity==2,"Delete refresh preserves deck references and quantities")
	for i: int in 40: importer.storage.save_card(image.save_png_to_buffer(),"Scroll Fixture %02d" % i,image.get_size())
	await settle()
	deck.catalog.select(20);deck.catalog.get_v_scroll_bar().value=150;await settle()
	var scroll_before: float=deck.catalog.get_v_scroll_bar().value
	var selected_id: String=deck.catalog.get_item_metadata(20)
	importer.storage.save_card(image.save_png_to_buffer(),"A new first row",image.get_size());await settle()
	check(deck.catalog.get_v_scroll_bar().value==scroll_before and str(deck.catalog.get_item_metadata(deck.catalog.get_selected_items()[0]))==selected_id,"Collection refresh preserves scroll and selected card across sorted insertion")
	hub.window.hide();app.queue_free();hub.queue_free();fake.queue_free();fixture_builder.free();await settle()
	print("CARD QOL FAILURES: ",failures);quit(0 if failures==0 else 1)
