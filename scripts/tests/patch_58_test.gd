extends SceneTree
const Service = preload("res://scripts/archive_import_service.gd")
const Catalog = preload("res://scripts/archive_catalog.gd")
const Processor = preload("res://scripts/card_image_processor.gd")
const Decks = preload("res://scripts/deck_storage.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(condition: bool, message: String) -> void:
	checks += 1
	print("PASS: " if condition else "FAIL: ", message)
	if not condition:
		failures += 1
func zip(path: String, entries: Dictionary) -> void:
	var pack := ZIPPacker.new()
	pack.open(path)
	for name: String in entries:
		pack.start_file(name)
		pack.write_file(entries[name])
		pack.close_file()
	pack.close()
func png(color: Color, extent: Vector2i = Vector2i(50, 70)) -> PackedByteArray:
	var image := Image.create(extent.x, extent.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image.save_png_to_buffer()
func count_files(folder: String, extension: String) -> int:
	var count: int = 0
	if DirAccess.dir_exists_absolute(folder):
		for name: String in DirAccess.get_files_at(folder):
			if name.get_extension() == extension:
				count += 1
	return count
func find_row(rows: Array, name: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.name == name:
			return row
	return {}
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(base)
	var cards_dir: String = base.path_join("cards")
	var decks_dir: String = base.path_join("decks")
	var archive: String = base.path_join("Lucky_Casino.zip")
	var service := Service.new(cards_dir, decks_dir)
	var blue := Image.create(50, 70, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var jpg: PackedByteArray = blue.save_jpg_to_buffer()
	blue.fill(Color.CYAN)
	var webp: PackedByteArray = blue.save_webp_to_buffer(false)
	var entries: Dictionary = {"lands/Forest.png": png(Color.GREEN), "lands/Forest (2).png": png(Color.GREEN), "extra/Forest_2.png": png(Color.GREEN), "Island.jpg": jpg, "Gate.jpeg": jpg, "day/Sun.png": png(Color.ORANGE), "night/Sun.png": png(Color.PURPLE), "Relic.webp": webp, "variants/Forest_2.png": png(Color.RED), "Part_2.png": png(Color.BLACK), "readme.txt": "ignored".to_utf8_buffer()}
	zip(archive, entries)
	service.reset_job()
	var preview: Dictionary = service.preview(archive)
	check(not preview.has("error"), "ZIP with nested PNG JPG JPEG WebP scans successfully")
	if preview.has("error"):
		print(preview)
		quit(1)
		return
	check(preview.deck_name == "Lucky Casino" and preview.images_found == 10, "Archive naming and image count")
	check(preview.unsupported.size() == 1 and preview.failed.is_empty(), "Unsupported files ignored and reported")
	check(not DirAccess.dir_exists_absolute(cards_dir) and not DirAccess.dir_exists_absolute(decks_dir), "Preview writes no collection or deck files")
	check(find_row(preview.rows, "Forest").quantity == 3, "Safe filename suffixes become three copies")
	check(find_row(preview.rows, "Forest_2").quantity == 1 and find_row(preview.rows, "Part_2").quantity == 1, "Different artwork and unproven numeric suffixes retain names")
	check(preview.rows.filter(func(row: Dictionary) -> bool: return row.name == "Sun").size() == 2, "Same filenames in different folders retain distinct art")
	var dimensions_ok: bool = true
	for row: Dictionary in preview.rows:
		var normalized := Image.new()
		normalized.load_png_from_buffer(row.png)
		dimensions_ok = dimensions_ok and normalized.get_size() == Vector2i(750, 1050)
	check(dimensions_ok, "Every gameplay image normalizes to 750 by 1050")
	var initial: Dictionary = service.commit(preview)
	check(not initial.has("error") and FileAccess.file_exists(initial.path), "ZIP automatically creates a saved deck")
	if initial.has("error"):
		print(initial)
		quit(1)
		return
	check(Decks.validate(initial.deck).is_empty() and initial.deck.cards.size() == 8, "Deck stores valid definition ID references and quantities")
	var definitions: int = count_files(cards_dir.path_join("definitions"), "json")
	var assets: int = count_files(cards_dir, "png")
	check(definitions == 8 and assets == 7, "Different names sharing normalized art reuse a single SHA-256 asset")
	service.reset_job()
	var repeated: Dictionary = service.preview(archive)
	check(repeated.stats.new == 0 and repeated.stats.existing == 8 and repeated.candidates.size() == 1, "Repeated archive finds existing cards and matching deck")
	check(repeated.candidates[0].diff.added.is_empty() and repeated.candidates[0].diff.removed.is_empty() and repeated.candidates[0].diff.artwork.is_empty(), "Identical archive comparison is unchanged")
	var repeated_result: Dictionary = service.commit(repeated, 0, false)
	check(not repeated_result.has("error") and repeated_result.deck.deck_id == initial.deck.deck_id, "Repeated import updates the same deck identity")
	check(count_files(cards_dir.path_join("definitions"), "json") == definitions and count_files(cards_dir, "png") == assets, "Repeated import does not grow definitions or image assets")
	var relic_id: String = find_row(initial.deck.archive_import.rows, "Relic").id
	var custom: Dictionary = repeated_result.deck.duplicate(true)
	custom.deck_name = "My Casino"
	custom.format_id = "custom_commander"
	custom.leaders = [relic_id]
	service.decks.save_deck(custom, initial.path)
	entries.erase("Island.jpg")
	entries.erase("extra/Forest_2.png")
	entries["Dragon.png"] = png(Color.YELLOW)
	entries.erase("Relic.webp")
	entries["Relic.png"] = png(Color.PINK)
	zip(archive, entries)
	service.reset_job()
	var changed: Dictionary = service.preview(archive)
	var diff: Dictionary = changed.candidates[0].diff
	check(diff.added.any(func(value: String) -> bool: return value.contains("Dragon")), "Changed archive detects added cards")
	check(diff.removed.any(func(value: String) -> bool: return value.contains("Island")), "Changed archive detects removed cards")
	check(diff.quantities.any(func(value: String) -> bool: return value.contains("Forest: 3 → 2")), "Changed archive detects copy quantity changes")
	check(diff.artwork.has("Relic") and changed.stats.changed == 1, "Same-name changed artwork is flagged")
	check(not diff.unchanged.is_empty(), "Comparison reports unchanged cards")
	var old_relic: Dictionary = Catalog.scan(cards_dir).by_id[relic_id]
	var old_asset: String = cards_dir.path_join(old_relic.hash + ".png")
	var updated: Dictionary = service.commit(changed, 0, false)
	check(not updated.has("error") and updated.deck.deck_id == initial.deck.deck_id and updated.deck.deck_name == "My Casino", "Update preserves existing deck ID and renamed title")
	check(updated.deck.format_id == "custom_commander" and updated.deck.leaders.size() == 1 and updated.deck.leaders[0] != relic_id, "Unambiguous changed-art leader transfers to replacement definition")
	check(FileAccess.file_exists(old_relic.path) and FileAccess.file_exists(old_asset), "Changed art preserves old definitions and assets")
	check(find_row(updated.deck.archive_import.rows, "Gate").id == find_row(initial.deck.archive_import.rows, "Gate").id, "Unchanged cards keep definition IDs")
	service.reset_job()
	var again: Dictionary = service.preview(archive)
	var definition_count: int = count_files(cards_dir.path_join("definitions"), "json")
	var separate: Dictionary = service.commit(again, 0, true, "Casino Copy")
	check(not separate.has("error") and separate.deck.deck_id != updated.deck.deck_id and count_files(decks_dir, "json") == 2, "Import as New Deck creates a separate saved deck")
	check(count_files(cards_dir.path_join("definitions"), "json") == definition_count, "Separate deck reuses definitions and assets")
	service.reset_job()
	var ambiguous: Dictionary = service.preview(archive)
	check(ambiguous.candidates.size() == 2, "Multiple imported decks are offered as explicit choices")
	check(service.commit(ambiguous, -1, false).has("error"), "No arbitrary deck chosen for ambiguous update")
	var stale: Dictionary = ambiguous.candidates[0].deck.duplicate(true)
	stale.deck_name = "Edited after preview"
	service.decks.save_deck(stale, ambiguous.candidates[0].path)
	check(service.commit(ambiguous, 0, false).has("error"), "Stale deck preview cannot overwrite a later edit")
	var odd_archive: String = base.path_join("Odd.zip")
	zip(odd_archive, {"Wide.png": png(Color.ORANGE, Vector2i(140, 35)), "broken.png": "invalid image".to_utf8_buffer(), "other.bin": PackedByteArray([1, 2])})
	service.reset_job()
	var odd: Dictionary = service.preview(odd_archive)
	check(odd.warnings.size() == 1 and odd.failed.size() == 1 and odd.unsupported.size() == 1, "Unusual ratios and corrupt images flagged before committing")
	var filled := Image.new()
	filled.load_png_from_buffer(odd.rows[0].png)
	service.reset_job()
	var fitted: Dictionary = service.preview(odd_archive, true)
	var fit_image := Image.new()
	fit_image.load_png_from_buffer(fitted.rows[0].png)
	check(absf(fit_image.get_pixel(0, 0).r - Processor.BACKGROUND.r) < 1.0 / 255.0 and filled.get_pixel(0, 0).r > 0.9, "Global Fit pads and Fill center-crops consistently")
	var before_cancel: int = count_files(cards_dir.path_join("definitions"), "json")
	service.reset_job()
	service.cancel()
	check(service.preview(odd_archive).get("cancelled", false), "Batch scan can be cancelled without writes")
	check(service.commit(odd).get("cancelled", false) and count_files(cards_dir.path_join("definitions"), "json") == before_cancel, "Commit cancellation leaves existing collection unchanged")
	var invalid: String = base.path_join("Corrupt.zip")
	FileAccess.open(invalid, FileAccess.WRITE).store_string("not a ZIP")
	service.reset_job()
	check(service.preview(invalid).has("error"), "Corrupt ZIP fails safely")
	zip(invalid, {})
	check(service.preview(invalid).has("error"), "Empty ZIP fails safely")
	zip(invalid, {"readme.txt": "no images".to_utf8_buffer()})
	check(service.preview(invalid).has("error"), "ZIP with no images produces a clear failure")
	check(service.preview(base.path_join("Cards.rar")).error.contains("RAR"), "RAR limitation is explicit")
	var duplicate_path: String = base.path_join("duplicate_path.zip")
	var duplicate_zip := ZIPPacker.new()
	duplicate_zip.open(duplicate_path)
	for i: int in 2:
		duplicate_zip.start_file("Card.png")
		duplicate_zip.write_file(png(Color.RED))
		duplicate_zip.close_file()
	duplicate_zip.close()
	check(service.preview(duplicate_path).has("error"), "Duplicate exact archive paths are rejected as ambiguous")
	var oversized: String = base.path_join("oversized.zip")
	zip(oversized, {"Huge.png": png(Color.RED)})
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(oversized)
	for i: int in range(raw.size() - 46):
		if raw.decode_u32(i) == 0x02014b50:
			raw.encode_u32(i + 24, 129 * 1024 * 1024)
			break
	FileAccess.open(oversized, FileAccess.WRITE).store_buffer(raw)
	check(service.preview(oversized).has("error"), "Oversized expanded entry rejected before decompression")
	var bad_decks: String = base.path_join("not_a_directory")
	FileAccess.open(bad_decks, FileAccess.WRITE).store_string("occupied")
	var failing := Service.new(base.path_join("failure_cards"), bad_decks)
	failing.reset_job()
	var failure_plan: Dictionary = failing.preview(odd_archive)
	check(failing.commit(failure_plan).has("error") and count_files(base.path_join("failure_cards/definitions"), "json") == 0, "Failed deck save rolls back new definitions without a partial deck")
	var main: Control = preload("res://scripts/tests/table_fixture.gd").create_main()
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	main.tabletop.match_controller.loader = preload("res://scripts/library_loader.gd").new(cards_dir)
	check(not main.tabletop.match_controller.load_deck(updated.deck, true).has("error"), "Imported deck loads normally onto tabletop")
	check(main.tabletop.match_controller.model.players.local.leaders.size() == 1, "Imported leader behaves normally")
	var ui: Window = main.archive_importer
	ui.service = service
	ui.open_importer()
	check(ui.visible and ui.new_button.disabled, "Archive importer opens with commit disabled before preview")
	ui.archive_path = odd_archive
	ui.start_preview()
	while ui.worker != null:
		await process_frame
	check(ui.acknowledge.visible and ui.new_button.disabled, "UI requires acknowledgement for unusual crops and skipped images")
	ui.acknowledge.button_pressed = true
	check(not ui.new_button.disabled, "Reviewed warnings enable explicit commit")
	ui.cancel_import()
	check(not ui.visible and count_files(cards_dir.path_join("definitions"), "json") == before_cancel, "Cancel preview closes without adding cards")
	ui.open_importer()
	ui.archive_path = archive
	ui.start_preview()
	while ui.worker != null:
		await process_frame
	check(ui.target.item_count == 2 and ui.target.selected == -1 and ui.update_button.disabled, "UI requires a target choice when multiple decks match")
	ui.target.select(0)
	ui.target.item_selected.emit(0)
	check(not ui.update_button.disabled and ui.summary.text.contains("Compared with"), "Selected deck displays comparison and enables update")
	if OS.get_cmdline_user_args().size() > 1:
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("patch58_preview.png"))
	ui.start_commit(false)
	while ui.worker != null:
		await process_frame
	check(ui.summary.text.contains("Imported") and ui.plan.is_empty(), "UI commits successfully and clears stale preview")
	ui.cancel_import()
	print("PATCH 5.8: %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
