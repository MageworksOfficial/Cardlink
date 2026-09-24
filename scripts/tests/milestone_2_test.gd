extends SceneTree
const Storage = preload("res://scripts/card_storage.gd")
const Loader = preload("res://scripts/library_loader.gd")
var failures: int = 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if not value:
		failures += 1
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://cache/library_tests/" + Crypto.new().generate_random_bytes(8).hex_encode()
	var directory: String = base.path_join("cards")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var main := preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	var library = main.library
	library.loader = Loader.new(directory)
	library.open_library()
	check(library.records.is_empty() and library.status.text.contains("empty"), "empty library opens")
	var image := Image.create(750, 1050, false, Image.FORMAT_RGB8)
	image.fill(Color.CORNFLOWER_BLUE)
	var store := Storage.new(directory)
	var first: Dictionary = store.save_card(image.save_png_to_buffer(), "Zebra", Vector2i(750, 1050))
	var second: Dictionary = store.save_card(image.save_png_to_buffer(), "Alpha", Vector2i(750, 1050))
	var first_path: String = first["metadata_path"]
	var second_path: String = second["metadata_path"]
	var data: Dictionary = first["metadata"]
	data["created_at"] = "2027-01-01T00:00:00"
	data["custom_field"] = {"preserve": true}
	Storage.write_atomic(first_path, JSON.stringify(data).to_utf8_buffer())
	data = second["metadata"]
	data["created_at"] = "2026-01-01T00:00:00"
	Storage.write_atomic(second_path, JSON.stringify(data).to_utf8_buffer())
	library.refresh()
	check(library.records.size() == 2 and library.grid.get_child_count() == 2, "refresh reads definitions and creates thumbnail grid")
	check(library.displayed[0]["name"] == "Alpha", "name sorting")
	library.grid.get_child(0).pressed.emit()
	check(library.selected_path == second_path and library.preview.texture != null, "thumbnail selects large preview")
	library.query.text = "zEb"
	library.query.text_changed.emit(library.query.text)
	check(library.displayed.size() == 1 and library.displayed[0]["name"] == "Zebra", "case insensitive name search")
	library.query.text = ""
	library.sort_order.select(1)
	library.sort_order.item_selected.emit(1)
	check(library.displayed[0]["name"] == "Zebra", "newest sorting uses creation date")
	library.select_record(first_path)
	library.editor.name_edit.text = "Renamed"
	library.editor.tags_edit.text = " Forest, , Rare, Forest "
	library.editor.save_button.pressed.emit()
	var saved: Dictionary = library.loader.storage.read_definition(first_path)["metadata"]
	check(saved["name"] == "Renamed" and saved["tags"] == ["Forest", "Rare"], "rename and cleaned tag editing persist")
	check(saved["custom_field"]["preserve"], "unknown metadata preserved")
	library.tag_filter.select(1)
	library.tag_filter.item_selected.emit(1)
	check(library.displayed.size() == 1, "tag filtering")
	library.tag_filter.select(0)
	library.rebuild_grid()
	library.select_record(first_path)
	library.request_delete()
	check(library.delete_dialog.visible and FileAccess.file_exists(first_path), "delete requires confirmation")
	library.delete_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check(FileAccess.file_exists(first_path) and not library.delete_dialog.visible, "cancel deletion preserves definition")
	library.request_delete()
	library.delete_dialog.hide()
	library.confirm_delete()
	check(not FileAccess.file_exists(first_path) and FileAccess.file_exists(second["metadata"]["image_path"]), "definition deletion retains shared image")
	check(library.loader.storage.cleanup_candidates()["paths"].is_empty(), "shared image not cleanup eligible")
	library.loader.storage.delete_definition(second_path)
	check(library.loader.storage.cleanup_candidates()["paths"].size() == 1, "unreferenced image cleanup eligible")
	# A reference created after the preview must be retained at confirmation.
	Storage.write_atomic(second_path, JSON.stringify(second["metadata"]).to_utf8_buffer())
	check(library.loader.storage.cleanup_unused()["removed"] == 0, "cleanup rescans references")
	var broken: String = directory.path_join("definitions/broken.json")
	Storage.write_atomic(broken, "{bad".to_utf8_buffer())
	library.refresh()
	check(library.records.size() == 2, "malformed record does not stop loading")
	check(library.loader.storage.cleanup_unused().has("error"), "malformed JSON blocks cleanup")
	library.select_record(broken)
	check(library.preview.texture == null and library.editor.save_button.disabled and not library.details.text.is_empty(), "broken record placeholder and error")
	library.loader.storage.delete_definition(broken)
	var duplicate: Dictionary = second["metadata"].duplicate(true)
	duplicate.erase("name")
	duplicate["image_path"] = directory.path_join("missing.png")
	duplicate["tags"] = ["", "  "]
	duplicate["created_at"] = "2026-99-99 garbage!!"
	Storage.write_atomic(first_path, JSON.stringify(duplicate).to_utf8_buffer())
	library.refresh()
	check(library.records.size() == 2, "missing name image and bad date load safely")
	check(library.records[0]["errors"].has("Duplicate card ID; this entry is identified by its JSON filename."), "duplicate IDs flagged")
	check(not library.loader.storage.definition_path_allowed(directory.path_join("definitions/../outside.json")), "traversal rejected")
	library.loader.storage.delete_definition(first_path)
	library.loader.storage.delete_definition(second_path)
	check(library.loader.storage.cleanup_unused()["removed"] == 1, "orphan cleanup deletes unused hash image")
	main.get_node("CardImporter").storage = Storage.new(directory)
	library.import_requested.emit()
	await process_frame
	check(main.get_node("CardImporter").visible, "library opens existing importer")
	var source_path: String = base.path_join("new-import.png")
	image.save_png(source_path)
	main.get_node("CardImporter").select_file(source_path)
	main.get_node("CardImporter").confirm_crop()
	while main.get_node("CardImporter").busy:
		await process_frame
	check(library.records.size() == 1 and library.grid.get_child_count() == 1, "import from library refreshes records immediately")
	main.get_node("CardImporter").close_importer()
	library.back_requested.emit()
	check(not library.visible and main.tabletop.world.get_node("Card").visible, "return to tabletop")
	if OS.get_cmdline_user_args().size() > 1:
		store.save_card(image.save_png_to_buffer(), "Azure Guardian", Vector2i(750, 1050))
		image.fill(Color.INDIAN_RED)
		store.save_card(image.save_png_to_buffer(), "Ember Sentinel", Vector2i(750, 1050))
		library.open_library()
		library.select_record(library.records[0]["path"])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("library.png"))
	print("LIBRARY TESTS COMPLETE: failures=", failures)
	quit(1 if failures else 0)



