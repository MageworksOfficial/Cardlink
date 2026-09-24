extends Node
signal progress(message: String)
const Record = preload("res://scripts/integrations/scryfall_record.gd")
const Faces = preload("res://scripts/card_faces.gd")
const Processor = preload("res://scripts/card_image_processor.gd")
var client: Node
var catalog: Node
var cards = preload("res://scripts/card_storage.gd").new()
var decks = preload("res://scripts/deck_storage.gd").new()
var cancelled: bool = false
var worker: Thread
func definitions() -> Array:
	var result: Array = []
	var folder: String = cards.directory.path_join("definitions")
	if not DirAccess.dir_exists_absolute(folder): return result
	for name: String in DirAccess.get_files_at(folder):
		if name.get_extension()!="json": continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(name)))
		if data is Dictionary and data.get("source")=="scryfall" and data.get("scryfall_id") is String and valid_assets(data): result.append(data)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return str(a.card_id)<str(b.card_id))
	return result
func valid_assets(data: Dictionary) -> bool:
	var faces: Array = Faces.list(data)
	if not Faces.validate(faces).is_empty(): return false
	for face: Dictionary in faces:
		if face.image_path!=cards.directory.path_join(face.image_hash+".png") or not FileAccess.file_exists(face.image_path) or FileAccess.get_sha256(face.image_path)!=face.image_hash: return false
	return true
func existing_id(id: String) -> Dictionary:
	for item: Dictionary in definitions():
		if item.scryfall_id==id: return item
	return {}
func local_for(entry: Dictionary) -> Dictionary:
	for item: Dictionary in definitions():
		if not Record.same_name(item,entry.name): continue
		if not str(entry.get("set_code","")).is_empty() and (item.get("set_code")!=str(entry.set_code).to_lower() or item.get("collector_number")!=entry.collector_number): continue
		return item
	return {}
func resolve(entries: Array) -> Array:
	var plan: Array = []
	var lookups: int = 0
	cancelled=false
	for i: int in entries.size():
		if cancelled: break
		progress.emit("Resolving cards… %d / %d" % [i+1,entries.size()])
		var entry: Dictionary = entries[i].duplicate(true)
		entry["local"] = local_for(entry)
		entry["card"] = {}; entry["skip"]=false; entry["error"]=""
		if entry.local.is_empty():
			var matches: Array = catalog.search_local(entry.name,true) if str(entry.set_code).is_empty() else []
			if matches.size()==1: entry.card=matches[0]
			elif entries.size()>20 and catalog.rows.is_empty(): entry.error="Update Metadata Catalog first for large decklists, or choose this entry manually."
			elif lookups>=20: entry.error="Online lookup budget reached. Review this entry manually or use the local metadata catalog."
			else:
				lookups+=1
				var response: Dictionary = await client.resolve_card(entry)
				if response.has("error"): entry.error=response.error
				else:
					var card: Dictionary = Record.compact(response.data)
					var wrong_print: bool = not str(entry.set_code).is_empty() and (card.get("set")!=entry.set_code or card.get("collector_number")!=entry.collector_number)
					if card.is_empty() or wrong_print or not Record.same_name(card,entry.name): entry.error="Printing/name mismatch. Choose a result or skip."
					else: entry.card=card
		plan.append(entry)
		await get_tree().process_frame
	return [] if cancelled else plan
func normalize(bytes: PackedByteArray, extension: String) -> Dictionary:
	var source: Dictionary = Processor.load_buffer(bytes,extension)
	if source.has("error"): return source
	var output: Image = Processor.normalize(source.image,Processor.batch_crop(source.image,true))
	return {"png":output.save_png_to_buffer()}
func import_card(card: Dictionary) -> Dictionary:
	var existing: Dictionary = existing_id(str(card.get("id","")))
	if not existing.is_empty(): return {"metadata":existing,"reused":true}
	if not card.get("faces") is Array or card.faces.is_empty(): return {"error":"No printable card faces."}
	var normalized: Array = []
	for face: Dictionary in card.faces:
		if cancelled: return {"error":"Cancelled.","cancelled":true}
		progress.emit("Downloading image: "+str(face.name))
		var response: Dictionary = await client.fetch_image(face.image)
		if response.has("error"): return response
		worker=Thread.new()
		var ext: String = str(face.image).split("?")[0].get_extension().to_lower()
		if worker.start(normalize.bind(response.bytes,ext))!=OK: worker=null; return {"error":"Cannot start image processing."}
		while worker.is_alive(): await get_tree().process_frame
		response=worker.wait_to_finish(); worker=null
		if response.has("error"): return response
		normalized.append(response.png)
	if cancelled: return {"error":"Cancelled.","cancelled":true}
	var faces: Array = []
	for i: int in normalized.size():
		var asset: Dictionary = cards.save_asset(normalized[i])
		if asset.has("error"): return asset
		faces.append({"face_id":"face_"+str(i),"face_index":i,"name":card.faces[i].name,"image_path":asset.image_path,"image_hash":asset.image_hash})
	# Reuse a matching ordinary local definition too; never overwrite its metadata.
	var folder: String = cards.directory.path_join("definitions")
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension()!="json": continue
		var found: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file)))
		if found is Dictionary and found.get("name")==card.name and Faces.signature(Faces.list(found))==Faces.signature(faces):
			if found.get("scryfall_id",card.id)==card.id:
				annotate(found,card)
				return Faces.save(cards.directory,card.name,faces,found)
	var metadata: Dictionary = preload("res://scripts/card_metadata.gd").create(card.name,faces[0].image_hash,faces[0].image_path,Vector2i(750,1050))
	annotate(metadata,card)
	return Faces.save(cards.directory,card.name,faces,metadata)
func annotate(metadata: Dictionary, card: Dictionary) -> void:
	metadata.merge({"source":"scryfall","scryfall_id":card.id,"oracle_id":card.get("oracle_id",""),"set_code":card.set,"collector_number":card.collector_number,"printing_name":card.set_name,"language":card.lang,"source_reference":card.scryfall_uri,"source_images":card.faces.map(func(f: Dictionary) -> String:return f.image)},true)
func commit(plan: Array, name: String) -> Dictionary:
	cancelled=false
	var deck: Dictionary = decks.new_deck()
	deck.deck_name=name.strip_edges() if not name.strip_edges().is_empty() else "Imported deck"
	deck["import_sections"]={}; deck["import_source"]="pasted_text"
	var index: int = 0
	for entry: Dictionary in plan:
		if entry.skip: continue
		if not str(entry.error).is_empty(): return {"error":"Review or skip unresolved entries before importing."}
	for entry: Dictionary in plan:
		if entry.skip: continue
		if cancelled: return {"error":"Cancelled. Completed library cards kept; no partial deck saved."}
		index+=1; progress.emit("Importing chosen cards… %d / %d" % [index,plan.size()])
		var result: Dictionary = {"metadata":entry.local} if not entry.local.is_empty() else await import_card(entry.card)
		if result.has("error"): return result
		var id: String = result.metadata.card_id
		if not deck.import_sections.has(entry.section): deck.import_sections[entry.section]=[]
		deck.import_sections[entry.section].append({"card_id":id,"quantity":entry.quantity,"name":entry.name})
		if entry.section in ["deck","commander"]:
			var added: bool = false
			for row: Dictionary in deck.cards:
				if row.card_id==id: row.quantity+=entry.quantity; added=true; break
			if not added: deck.cards.append({"card_id":id,"quantity":entry.quantity})
			if entry.section=="commander" and not deck.leaders.has(id): deck.leaders.append(id)
	if cancelled: return {"error":"Cancelled. No deck saved."}
	if deck.cards.is_empty(): return {"error":"No main-deck or leader cards chosen. No deck saved."}
	progress.emit("Building deck…")
	var saved: Dictionary = decks.save_deck(deck)
	if not saved.has("error"): saved["deck"]=deck
	return saved
func _exit_tree() -> void:
	cancelled=true
	if worker!=null: worker.wait_to_finish()
