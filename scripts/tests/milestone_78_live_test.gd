extends "res://scripts/tests/milestone_74_test.gd"
func capture(path: String) -> void:
	if not OS.get_cmdline_user_args().has("capture"): return
	for _i: int in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var base: String=OS.get_cmdline_user_args()[0]
	root.size=Vector2i(1152,820);root.gui_embed_subwindows=true
	var hub=preload("res://scripts/integrations/integration_hub.gd").new()
	hub.settings_path=base.path_join("settings.cfg")
	root.add_child(hub)
	hub.client.cache.directory=base.path_join("cache")
	hub.catalog.directory=base.path_join("catalog");hub.catalog.rows.clear()
	hub.importer.cards.directory=base.path_join("cards");hub.importer.decks.directory=base.path_join("decks")
	hub.open_window(2)
	check(hub.client.request_count==0 and not hub.client.enabled,"Opening optional UI does not request provider data")
	hub.window.enabled_box.button_pressed=true
	check(hub.client.enabled and hub.client.request_count==0,"Enable is explicit and starts no downloads")
	hub.open_window(0)
	hub.window.query.text="Lightning Bolt";hub.window.exact.button_pressed=true
	await hub.window.run_search()
	check(hub.window.cards.size()==1 and hub.window.cards[0].name=="Lightning Bolt","Live exact-name search succeeds")
	if hub.window.cards.is_empty(): print(hub.window.status.text);quit(1);return
	check(hub.window.results.get_item_icon(0)!=null,"Live result thumbnail displays")
	hub.window.results.select(0);hub.window.select_result(0)
	await capture(base.path_join("online-search.png"))
	var card: Dictionary=hub.window.cards[0]
	await hub.window.add_selected()
	check(not hub.importer.existing_id(card.id).is_empty(),"Live single card imported into normal storage")
	var count: int=hub.client.request_count
	await hub.window.add_selected()
	check(hub.client.request_count==count and hub.window.add_button.text=="Already in Library","Live duplicate add reuses asset without provider request")
	var response: Dictionary=await hub.client.get_printings(card)
	check(not response.has("error") and response.data.data.size()>1,"Choose Printing returns multiple actual printings")
	var exact_print: Dictionary=response.data.data[0] if not response.has("error") else {}
	if not exact_print.is_empty():
		response=await hub.client.resolve_card({"name":exact_print.name,"set_code":exact_print.set,"collector_number":exact_print.collector_number})
		check(not response.has("error") and response.data.id==exact_print.id,"Exact set/collector request resolves requested printing")
	response=await hub.client.search("delver")
	check(not response.has("error") and not response.data.data.is_empty(),"Live partial-name search succeeds")
	response=await hub.client.resolve_card({"name":"Delver of Secrets"})
	if response.has("error"): print(response);quit(1);return
	var multi: Dictionary=preload("res://scripts/integrations/scryfall_record.gd").compact(response.data)
	response=await hub.importer.import_card(multi)
	check(not response.has("error") and response.metadata.faces.size()==2,"Live double-sided printing imports both faces as one definition")
	var plan: Array=await hub.importer.resolve(preload("res://scripts/integrations/decklist_parser.gd").parse("Deck\n4 Lightning Bolt\n1 Delver of Secrets").entries)
	response=await hub.importer.commit(plan,"Live import validation")
	check(not response.has("error") and response.deck.cards.size()==2,"Live decklist creates normal saved deck")
	check(hub.client.starts.size()>1 and spaced(hub.client.starts),"Actual provider requests respect the centralized spacing")
	hub.open_window(1)
	hub.window.deck_ui.input.text="Deck\n4 Lightning Bolt\n1 Delver of Secrets\nSideboard\n1 Unknown example card"
	await hub.window.deck_ui.resolve()
	check(hub.window.deck_ui.plan.size()==3 and not hub.window.deck_ui.plan[2].error.is_empty(),"Live unresolved entry appears for review")
	hub.window.deck_ui.review.select(2);hub.window.deck_ui.skip_selected()
	check(hub.window.deck_ui.plan[2].skip,"Review UI explicitly skips invalid card")
	await capture(base.path_join("decklist-review.png"))
	if OS.get_cmdline_user_args().has("bulk"):
		hub.open_window(2)
		await hub.window.update_catalog()
		check(hub.catalog.rows.size()>1000,"Live current JSONL bulk metadata update succeeds")
		check(not hub.catalog.search_local("Lightning Bolt",true).is_empty(),"Live bulk enables offline exact lookup")
		await capture(base.path_join("catalog-settings.png"))
	hub.set_enabled(false)
	count=hub.client.request_count
	response=await hub.importer.import_card(card)
	check(not response.has("error") and hub.client.request_count==count,"Imported official card reuses fully offline")
	hub.window.close();hub.queue_free()
	await process_frame
	print("CARDLINK 7.8 LIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func spaced(values: Array) -> bool:
	for i: int in range(1,values.size()):
		if float(values[i])-float(values[i-1])<0.64: return false
	return true
