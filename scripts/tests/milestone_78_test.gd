extends "res://scripts/tests/milestone_74_test.gd"
const Record = preload("res://scripts/integrations/scryfall_record.gd")
const Parser = preload("res://scripts/integrations/decklist_parser.gd")
class FakeProvider extends Node:
	const API="https://api.scryfall.com"
	var enabled: bool=true
	var calls: Array=[]
	var data: Dictionary={}
	var images: Dictionary={}
	var failed: bool=false
	var bulk: PackedByteArray
	func resolve_card(entry: Dictionary) -> Dictionary:
		calls.append(entry.duplicate(true))
		return {"data":data[entry.name]} if data.has(entry.name) else {"error":"No exact match."}
	func fetch_image(url: String, _thumb: bool=false) -> Dictionary:
		calls.append(url)
		return {"bytes":images[url]} if images.has(url) and not failed else {"error":"Image download failed."}
	func request(_url: String,kind: String="json",target: String="",_fresh: bool=false) -> Dictionary:
		if failed: return {"error":"Provider unavailable."}
		if kind=="bulk":
			var file:=FileAccess.open(target,FileAccess.WRITE);file.store_buffer(bulk);file.close();return {"path":target}
		return {"data":{"type":"oracle_cards","jsonl_download_uri":"https://data.scryfall.io/test.jsonl.gz","compressed_size":bulk.size(),"updated_at":"2026-09-21T00:00:00Z"}}
func fixture(id: String,name: String,multi: bool=false) -> Dictionary:
	var data: Dictionary={"object":"card","id":id,"oracle_id":"oracle-"+id,"name":name,"set":"tst","set_name":"Synthetic test cards","collector_number":"1","lang":"en","scryfall_uri":"https://scryfall.com/card/tst/1","image_uris":{"png":"https://cards.scryfall.io/front.png","small":"https://cards.scryfall.io/front.jpg"}}
	if multi:
		data.erase("image_uris")
		data["card_faces"]=[{"name":name,"image_uris":{"png":"https://cards.scryfall.io/front.png","small":"https://cards.scryfall.io/front.jpg"}},{"name":"Back test","image_uris":{"png":"https://cards.scryfall.io/back.png","small":"https://cards.scryfall.io/back.jpg"}}]
	return data
func run() -> void:
	var base: String=OS.get_cmdline_user_args()[0]
	root.size=Vector2i(1152,760);root.gui_embed_subwindows=true
	var client=preload("res://scripts/integrations/scryfall_client.gd").new();root.add_child(client)
	client.cache.directory=base.path_join("cache")
	var result: Dictionary=await client.search("test")
	check(result.has("error") and client.request_count==0,"Disabled provider makes no requests")
	check(not client.allowed("http://api.scryfall.com/cards/named","json") and not client.allowed("https://api.scryfall.com.evil/cards/named","json"),"HTTPS provider allowlist rejects insecure/foreign hosts")
	check(client.SPACING>0.5 and str(client.HEADERS).contains("User-Agent: CardLink/7.8") and str(client.HEADERS).contains("Accept:"),"Conservative queue spacing and explicit headers")
	check(client.decode("not json".to_utf8_buffer(),"json").has("error"),"Malformed provider response fails quietly")
	check(client.http_date_delay("Wed, 21 Oct 2037 07:28:00 GMT")>30,"Retry-After HTTP dates are honored")
	client.active=client.Ticket.new()
	var response_holder: Array=[]
	client.active.finished.connect(func(value: Dictionary) -> void:response_holder.append(value))
	client.completed(HTTPRequest.RESULT_SUCCESS,429,PackedStringArray(["Retry-After: 45"]),PackedByteArray())
	check(response_holder[0].status==429 and client.cooldown-Time.get_ticks_msec()/1000.0>44,"429 stops requests and respects Retry-After")
	client.enabled=true
	result=await client.search("test")
	check(result.get("status")==429 and client.request_count==0,"Cooldown does not retry provider")
	client.cache.put_bytes("test",'{"object":"card"}'.to_utf8_buffer())
	check(not client.cache.get_bytes("test").is_empty(),"Metadata cache roundtrip")
	for i: int in 260:
		var cache_file := FileAccess.open(client.cache.path_for(str(i)),FileAccess.WRITE)
		cache_file.store_string("test"); cache_file.close()
	client.cache.prune()
	check(DirAccess.get_files_at(client.cache.directory).size()<=256,"Cache entry bound enforced")
	client.cache.clear();check(DirAccess.get_files_at(client.cache.directory).is_empty(),"Cache clearing stays local")
	var queued=client.Ticket.new();var cancelled_result: Array=[]
	queued.finished.connect(func(value: Dictionary) -> void:cancelled_result.append(value));client.queue.append(queued);client.cancel()
	check(cancelled_result[0].cancelled and client.queue.is_empty(),"Cancelling safely releases queued requests")
	var parsed: Dictionary=Parser.parse("Deck\n4 Test Card\n2x Another Card (TST) 7a\nCommander\n1 Leader\nSideboard\n3 Extra\nCompanion\n1 Companion\nMaybeboard\n1 Later\nnot a valid line")
	check(parsed.entries.size()==6 and parsed.total==12,"Basic names and quantities parse")
	check(parsed.entries[1].set_code=="tst" and parsed.entries[1].collector_number=="7a","Arena printing fields parse")
	check(parsed.entries.map(func(e: Dictionary) -> String:return e.section)==["deck","deck","commander","sideboard","companion","maybeboard"],"All supported section headers parse")
	check(parsed.issues.size()==1,"Malformed line requires attention")
	check(Parser.parse("0 Bad\n-1 Nope\n1001 Too many").entries.is_empty(),"Invalid quantities rejected")
	check(Parser.parse("2 Forest\n3 Forest").entries[0].quantity==5,"Repeated same entries aggregate quantities")
	var fake:=FakeProvider.new();root.add_child(fake)
	var front:=Image.create(75,105,false,Image.FORMAT_RGBA8);front.fill(Color.BLUE)
	fake.images["https://cards.scryfall.io/front.png"]=front.save_png_to_buffer()
	front.fill(Color.RED);fake.images["https://cards.scryfall.io/back.png"]=front.save_png_to_buffer()
	var catalog=preload("res://scripts/integrations/scryfall_catalog.gd").new();catalog.directory=base.path_join("catalog");catalog.client=fake;root.add_child(catalog)
	var importer=preload("res://scripts/integrations/scryfall_importer.gd").new();importer.client=fake;importer.catalog=catalog;importer.cards.directory=base.path_join("cards");importer.decks.directory=base.path_join("decks");root.add_child(importer)
	var normal: Dictionary=fixture("single","Test Card")
	var multi: Dictionary=fixture("double","Two Faces",true)
	fake.data={"Test Card":normal,"Two Faces":multi}
	result=await importer.import_card(Record.compact(normal))
	check(not result.has("error") and result.metadata.name=="Test Card","Single card imports with exact provider name")
	check(result.metadata.source=="scryfall" and result.metadata.scryfall_id=="single" and result.metadata.set_code=="tst","External source metadata stored")
	check(Image.load_from_file(result.metadata.image_path).get_size()==Vector2i(750,1050),"Imported art normalized to local 750x1050 asset")
	var calls: int=fake.calls.size()
	var id: String=result.metadata.card_id
	result=await importer.import_card(Record.compact(normal))
	check(result.reused and result.metadata.card_id==id and fake.calls.size()==calls,"Duplicate printing does not redownload or redefine")
	result=await importer.import_card(Record.compact(multi))
	check(not result.has("error") and result.metadata.faces.size()==2,"Double-sided card creates one two-face definition")
	check(DirAccess.get_files_at(importer.cards.directory.path_join("definitions")).size()==2,"Back face is not an unrelated definition")
	check(DirAccess.get_files_at(importer.cards.directory).size()==2,"Matching front image asset is reused")
	var descriptor: Dictionary=preload("res://scripts/network/card_sync_catalog.gd").descriptor(result.metadata)
	check(preload("res://scripts/network/card_sync_protocol.gd").definition(descriptor),"Imported multi-face metadata uses ordinary Card Sync schema")
	var plan: Array=await importer.resolve(Parser.parse("Deck\n4 Test Card\nCommander\n1 Two Faces\nSideboard\n2 Test Card\n1 Unknown").entries)
	check(plan[0].local.card_id==id,"Name-only resolution prefers existing local printing")
	check(not plan.back().error.is_empty(),"Unknown name is never silently resolved")
	var explicit: Array=await importer.resolve(Parser.parse("1 Test Card (other) 99").entries)
	check(explicit[0].local.is_empty() and not explicit[0].error.is_empty(),"Unavailable exact printing does not reuse different artwork")
	plan.back().skip=true
	result=await importer.commit(plan,"My synthetic deck")
	check(not result.has("error") and result.deck.cards[0].quantity==4,"Deck creation uses existing deck storage and quantities")
	check(result.deck.leaders.size()==1 and result.deck.cards.size()==2,"Leader section maps to one primary definition")
	check(result.deck.import_sections.sideboard[0].quantity==2,"Extra sections retained outside playable deck")
	var deck: Dictionary=result.deck
	result=await importer.commit(plan,"Repeat synthetic deck")
	check(not result.has("error") and DirAccess.get_files_at(importer.cards.directory.path_join("definitions")).size()==2,"Repeated deck import does not grow collection")
	check(importer.decks.list_decks().size()==2,"Repeated import makes a separate deck without overwriting")
	fake.failed=true
	var failure: Dictionary=Record.compact(fixture("fail","New Missing"))
	result=await importer.import_card(failure)
	check(result.has("error") and importer.existing_id("fail").is_empty(),"Image failure leaves no half-written definition")
	importer.cancelled=true;result=await importer.import_card(failure)
	check(result.get("cancelled",false),"Cancelled import starts no image work")
	fake.failed=false;importer.cancelled=false
	fake.bulk=(JSON.stringify(normal)+"\n"+JSON.stringify(multi)+"\n").to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	result=await catalog.update_catalog()
	check(result.get("count")==2 and catalog.rows.size()==2,"Compressed JSONL bulk metadata update works")
	check(catalog.search_local("two").size()==1 and catalog.search_local("Test Card",true).size()==1,"Local metadata supports partial and exact search")
	var before: String=FileAccess.get_sha256(catalog.catalog_path())
	fake.failed=true;result=await catalog.update_catalog()
	check(result.has("error") and before==FileAccess.get_sha256(catalog.catalog_path()),"Failed bulk request keeps previous catalog")
	fake.failed=false;fake.bulk="bad gzip".to_utf8_buffer();catalog.updated="old"
	result=await catalog.update_catalog()
	check(result.has("error") and before==FileAccess.get_sha256(catalog.catalog_path()),"Corrupt bulk does not replace catalog")
	var split: Dictionary=normal.duplicate(true);split["card_faces"]=[{"name":"Part one"},{"name":"Part two"}]
	check(Record.compact(split).faces.size()==1,"Split/adventure metadata with one printed image stays single-face")
	var app: Control=new_app(base.path_join("app"));app.entry.start(app.Mode.OFFLINE_PLAYTEST)
	await wait_for(func() -> bool:return not app.entering and app.table_scene!=null)
	var table: Node=app.table_scene.tabletop;var c: Node=table.match_controller
	c.loader=preload("res://scripts/library_loader.gd").new(importer.cards.directory)
	result=c.load_deck(deck,true,"local")
	check(not result.has("error") and c.model.players.local.library.order.size()==4,"Imported deck loads entirely offline")
	var rows: Array=c.loader.load_records()
	var row: Dictionary=rows.filter(func(x: Dictionary) -> bool:return x.metadata.scryfall_id=="double")[0]
	var card: Control=table.spawn_definition(row).card
	check(preload("res://scripts/usability/face_actions.gd").change(table,card) and card.state.active_face_index==1,"Imported two-face card changes face offline")
	app.dispose_table();app.queue_free()
	client.queue_free();importer.queue_free();catalog.queue_free();fake.queue_free()
	await process_frame
	print("CARDLINK 7.8: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
