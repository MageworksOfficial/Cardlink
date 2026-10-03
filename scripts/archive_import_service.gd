extends RefCounted
const Catalog = preload("res://scripts/archive_catalog.gd")
const Processor = preload("res://scripts/card_image_processor.gd")
const Cards = preload("res://scripts/card_storage.gd")
const Decks = preload("res://scripts/deck_storage.gd")
var cards: RefCounted
var decks: RefCounted
var mutex := Mutex.new()
var cancelled: bool = false
var progress: String = ""
func _init(card_directory: String = "user://cards", deck_directory: String = "user://decks") -> void:
	cards = Cards.new(card_directory)
	decks = Decks.new(deck_directory)
func reset_job() -> void:
	mutex.lock()
	cancelled = false
	progress = "Preparing…"
	mutex.unlock()
func cancel() -> void:
	mutex.lock()
	cancelled = true
	mutex.unlock()
func stopped() -> bool:
	mutex.lock()
	var value: bool = cancelled
	mutex.unlock()
	return value
func report(message: String) -> void:
	mutex.lock()
	progress = message
	mutex.unlock()
func progress_text() -> String:
	mutex.lock()
	var value: String = progress
	mutex.unlock()
	return value
func preview(path: String, fit: bool = false) -> Dictionary:
	var guarded: Dictionary = preload("res://scripts/archive_zip_guard.gd").inspect(path)
	if guarded.has("error"):
		return guarded
	var archive_hash: String = FileAccess.get_sha256(path)
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {"error": "The ZIP archive is corrupt or unreadable."}
	var files: PackedStringArray = reader.get_files()
	if files.size() != guarded.entries.size():
		reader.close()
		return {"error": "ZIP directory could not be read consistently."}
	var warnings: Array[String] = []
	var ignored: Array[String] = []
	var failed: Array[String] = []
	var incoming: Array = []
	var cache: Dictionary = {}
	var seen_hashes: Dictionary = {}
	var bytes_kept: int = 0
	var images_found: int = 0
	for entry: Dictionary in guarded.entries:
		if entry.supported:
			images_found += 1
	if images_found > 2000:
		reader.close()
		return {"error": "More than 2,000 images. Split the archive into smaller decks."}
	var done: int = 0
	for entry: Dictionary in guarded.entries:
		if stopped():
			reader.close()
			return {"cancelled": true}
		var filename: String = entry.path
		if filename.ends_with("/"):
			continue
		if not entry.supported:
			ignored.append(filename)
			continue
		done += 1
		report("Normalizing %d / %d: %s" % [done, images_found, filename.get_file()])
		if not files.has(filename):
			reader.close()
			return {"error": "ZIP filename encoding is not supported: " + filename}
		var buffer: PackedByteArray = reader.read_file(filename, true)
		if buffer.size() != entry.size:
			failed.append(filename + " — unreadable ZIP entry")
			continue
		var extension: String = filename.get_extension().to_lower()
		var raw_hash: String = ("jpg" if extension == "jpeg" else extension) + ":" + Catalog.digest(buffer)
		var normalized: Dictionary = cache.get(raw_hash, {})
		if normalized.is_empty():
			var loaded: Dictionary = Processor.load_buffer(buffer, filename.get_extension().to_lower())
			if loaded.has("error"):
				failed.append(filename + " — " + str(loaded.error))
				continue
			var source: Image = loaded.image
			var image: Image = Processor.normalize(source, Processor.batch_crop(source, fit))
			if image == null:
				failed.append(filename + " — normalization failed")
				continue
			var png: PackedByteArray = image.save_png_to_buffer()
			var normalized_hash: String = Catalog.digest(png)
			if not seen_hashes.has(normalized_hash):
				seen_hashes[normalized_hash] = png
				bytes_kept += png.size()
			normalized = {"png": seen_hashes[normalized_hash], "hash": normalized_hash, "source_size": source.get_size()}
			cache[raw_hash] = normalized
			if bytes_kept > 256 * 1024 * 1024:
				reader.close()
				return {"error": "Normalized preview exceeds 256 MB. Please use a smaller archive."}
		var ratio: float = float(normalized.source_size.x) / normalized.source_size.y
		if ratio < 0.5 or ratio > 0.95:
			warnings.append("%s — %d × %d; %s" % [filename, normalized.source_size.x, normalized.source_size.y, "Fit adds padding" if fit else "Fill crops the edges"])
		var row: Dictionary = normalized.duplicate()
		row["file"] = filename
		row["name"] = filename.replace("\\", "/").get_file().get_basename().strip_edges()
		if row.name.is_empty():
			row.name = "Untitled Card"
		incoming.append(row)
	reader.close()
	if incoming.is_empty():
		return {"error": "No usable supported images found. PNG, JPG, JPEG and WebP are supported.", "unsupported": ignored, "failed": failed, "images_found": images_found}
	if FileAccess.get_sha256(path) != archive_hash:
		return {"error": "Archive changed while scanning. Please scan it again."}
	var grouped: Array[Dictionary] = Catalog.group(incoming)
	for row: Dictionary in grouped:
		if row.quantity > 1000:
			return {"error": "A card exceeds the existing deck limit of 1,000 copies: " + row.name}
	report("Comparing with your collection and saved decks…")
	var catalog: Dictionary = Catalog.scan(cards.directory)
	var stats: Dictionary = {"new": 0, "existing": 0, "changed": 0}
	var fingerprint_rows: Array[String] = []
	for row: Dictionary in grouped:
		var identity: String = Catalog.key(row.name, row.hash)
		row["existing_id"] = str(catalog.by_key.get(identity, {}).get("id", ""))
		if row.existing_id.is_empty():
			stats.new += 1
			if catalog.by_name.has(Catalog.normalized_name(row.name)):
				stats.changed += 1
		else:
			stats.existing += 1
		fingerprint_rows.append(identity + ":" + str(row.quantity))
	fingerprint_rows.sort()
	var fingerprint: String = Catalog.digest(JSON.stringify(fingerprint_rows).to_utf8_buffer())
	var name: String = path.get_file().get_basename().replace("_", " ").strip_edges()
	var source_key: String = Catalog.normalized_name(name)
	var candidates: Array[Dictionary] = []
	for saved: Dictionary in decks.list_decks():
		if not str(saved.error).is_empty():
			continue
		var hint: Variant = saved.data.get("archive_import", {})
		if not hint is Dictionary or hint.is_empty():
			continue
		if hint.get("source_key") == source_key or hint.get("fingerprint") == fingerprint:
			var previous: Array = Catalog.deck_rows(saved.data, catalog)
			candidates.append({"path": saved.path, "deck": saved.data, "file_hash": FileAccess.get_sha256(saved.path), "previous": previous, "diff": Catalog.compare(grouped, previous)})
	return {"archive": path, "archive_hash": archive_hash, "deck_name": name, "source_key": source_key, "fingerprint": fingerprint, "fit": fit, "rows": grouped, "images_found": images_found, "valid_images": incoming.size(), "unsupported": ignored, "failed": failed, "warnings": warnings, "stats": stats, "candidates": candidates, "catalog_signature": catalog.signature}
func commit(plan: Dictionary, candidate_index: int = -1, as_new: bool = true, deck_name: String = "") -> Dictionary:
	if not plan.has("rows") or plan.rows.is_empty():
		return {"error": "Scan an archive before importing."}
	if FileAccess.get_sha256(plan.archive) != plan.archive_hash:
		return {"error": "Archive changed since preview. Please scan again."}
	var catalog: Dictionary = Catalog.scan(cards.directory)
	if catalog.signature != plan.catalog_signature:
		return {"error": "Your collection changed since preview. Please scan again."}
	var candidate: Dictionary = {}
	if candidate_index >= 0 and candidate_index < plan.candidates.size():
		candidate = plan.candidates[candidate_index]
	if not as_new and candidate.is_empty():
		return {"error": "Choose the existing deck to update."}
	if not as_new and FileAccess.get_sha256(candidate.path) != candidate.file_hash:
		return {"error": "That deck changed since preview. Please scan again."}
	var result_deck: Dictionary = Decks.new_deck() if candidate.is_empty() else candidate.deck.duplicate(true)
	if as_new:
		result_deck.deck_id = Decks.new_deck().deck_id
	result_deck.deck_name = deck_name.strip_edges() if not deck_name.strip_edges().is_empty() else (plan.deck_name if as_new else candidate.deck.deck_name)
	result_deck.cards = []
	var created: Array[Dictionary] = []
	var manifest: Array[Dictionary] = []
	var old_leaders: Array = result_deck.leaders.duplicate()
	var by_name: Dictionary = {}
	var included: Dictionary = {}
	var index: int = 0
	for row: Dictionary in plan.rows:
		if stopped():
			rollback(created)
			return {"cancelled": true}
		index += 1
		report("Importing %d / %d: %s" % [index, plan.rows.size(), row.name])
		if Catalog.digest(row.png) != row.hash:
			rollback(created)
			return {"error": "Preview image changed. Please scan again."}
		var id: String = row.existing_id
		if id.is_empty():
			var saved: Dictionary = preload("res://scripts/archive_face_pairs.gd").save_row(cards,row)
			if saved.has("error"):
				rollback(created)
				return saved
			id = saved.metadata.card_id
			created.append({"path": saved.metadata_path, "id": id, "hash": FileAccess.get_sha256(saved.metadata_path)})
		result_deck.cards.append({"card_id": id, "quantity": row.quantity})
		manifest.append({"id": id, "name": row.name, "hash": row.hash, "art_signature":row.get("art_signature",row.hash), "quantity": row.quantity})
		included[id] = true
		var name_key: String = Catalog.normalized_name(row.name)
		if not by_name.has(name_key):
			by_name[name_key] = []
		by_name[name_key].append(id)
	result_deck.leaders = []
	for id: String in old_leaders:
		if included.has(id):
			result_deck.leaders.append(id)
		elif not candidate.is_empty():
			for old: Dictionary in candidate.previous:
				var name_key: String = Catalog.normalized_name(old.name)
				if old.id == id and by_name.has(name_key) and by_name[name_key].size() == 1 and not result_deck.leaders.has(by_name[name_key][0]):
					result_deck.leaders.append(by_name[name_key][0])
	result_deck["archive_import"] = {"version": 1, "source_key": plan.source_key, "fingerprint": plan.fingerprint, "archive_name": str(plan.archive).get_file(), "mode": "fit" if plan.fit else "fill", "rows": manifest}
	if stopped():
		rollback(created)
		return {"cancelled": true}
	# Definitions/assets are complete before the deck is atomically published, last.
	if not as_new and FileAccess.get_sha256(candidate.path) != candidate.file_hash:
		rollback(created)
		return {"error": "That deck changed during import. No deck was overwritten. Please preview again."}
	var saved_deck: Dictionary = decks.save_deck(result_deck, "" if as_new else candidate.path)
	if saved_deck.has("error"):
		rollback(created)
		return saved_deck
	var copies: int = 0
	for row: Dictionary in result_deck.cards: copies += int(row.quantity)
	return {"deck": result_deck, "path": saved_deck.path, "created_definitions": created.size(), "copies": copies}
func rollback(created: Array[Dictionary]) -> void:
	# Only definitions created by this operation, unchanged and unused by saved decks.
	# Keep content-addressed images for safe retry/reuse; never remove shared art.
	var used: Dictionary = {}
	for saved: Dictionary in decks.list_decks():
		if not str(saved.error).is_empty():
			return
		for row: Dictionary in saved.data.cards:
			used[row.card_id] = true
	for row: Dictionary in created:
		if not used.has(row.id) and FileAccess.get_sha256(row.path) == row.hash:
			DirAccess.remove_absolute(row.path)
			preload("res://scripts/collection_events.gd").publish(cards.directory)
