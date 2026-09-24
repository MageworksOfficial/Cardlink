extends SceneTree
const Processor = preload("res://scripts/card_image_processor.gd")
const Storage = preload("res://scripts/card_storage.gd")
var failures: int = 0
var directory: String
var imported: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	print("PASS: " if condition else "FAIL: ", description)
	if not condition:
		failures += 1

func motion(point: Vector2, relative: Vector2 = Vector2.ZERO, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func button(point: Vector2, which: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = which
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if which == MOUSE_BUTTON_RIGHT and not pressed:
		var controls: Node = root.find_child("TabletopControls",true,false)
		if controls != null and controls.panels.Card.visible:
			for action: Button in controls.card_actions:
				if action.text == "Tap / Untap": action.pressed.emit()
			controls.close_panels()


func run() -> void:
	directory = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://cache/importer_tests/" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var main := preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var card := main.tabletop.world.get_node("Card") as Control
	var art := card.get_node("CardImage") as TextureRect
	var hover := card.get_node("HoverPreview") as TextureRect
	var center: Vector2 = art.get_global_rect().get_center()
	motion(center)
	check(hover.visible, "card hover shows preview")
	button(center, MOUSE_BUTTON_RIGHT, true)
	button(center, MOUSE_BUTTON_RIGHT, false)
	check(card.get("tapped") and is_equal_approx(art.rotation_degrees, 90.0), "tap rotates only CardImage")
	check(is_zero_approx(card.rotation), "Card root remains unrotated")
	var outside_rotated := card.position + Vector2(10, 10)
	motion(outside_rotated)
	button(outside_rotated, MOUSE_BUTTON_RIGHT, true)
	button(outside_rotated, MOUSE_BUTTON_RIGHT, false)
	check(card.get("tapped") and not hover.visible, "tapped card excludes upright-only corner")
	check(main.tabletop.extras.field_menu.visible, "Empty corner now opens tabletop context menu")
	main.tabletop.extras.field_menu.hide()
	var rotated_edge := card.position + Vector2(-10, card.size.y / 2)
	motion(rotated_edge)
	check(hover.visible, "tapped overhang accepts hover outside root layout rectangle")
	button(rotated_edge, MOUSE_BUTTON_RIGHT, true)
	button(rotated_edge, MOUSE_BUTTON_RIGHT, false)
	check(not card.get("tapped"), "tapped overhang accepts untap")
	motion(center)
	var before: Vector2 = card.position
	button(center, MOUSE_BUTTON_LEFT, true)
	motion(center + Vector2(70, 45), Vector2(70, 45), true)
	check(card.position.is_equal_approx(before + Vector2(70, 45)), "left drag moves card")
	check(not hover.visible, "drag hides preview")
	button(center + Vector2(70, 45), MOUSE_BUTTON_LEFT, false)
	check(not card.get("dragging"), "release ends drag")
	motion(Vector2(1050, 700))
	button(Vector2(1050, 700), MOUSE_BUTTON_RIGHT, true)
	button(Vector2(1050, 700), MOUSE_BUTTON_RIGHT, false)
	check(not card.get("tapped") and not hover.visible, "empty tabletop does not mutate card or reveal hover")
	check(main.tabletop.extras.field_menu.visible, "Empty field opens context menu")
	main.tabletop.extras.field_menu.hide()

	var importer: Window = main.get_node("CardImporter")
	importer.storage = Storage.new(directory.path_join("cards"))
	importer.card_imported.connect(func(metadata: Dictionary, _reused: bool) -> void: imported.append(metadata))
	main.get_node("ImportCard").pressed.emit()
	await process_frame
	check(importer.visible, "Import Card button opens importer")
	check(importer.confirm_button.disabled, "no-image confirm disabled")
	importer.choose_file()
	await process_frame
	importer.picker.get_cancel_button().pressed.emit()
	await process_frame
	check(importer.source == null and importer.confirm_button.disabled, "cancel without source is safe")

	var fixture := Image.create(1500, 1500, false, Image.FORMAT_RGBA8)
	fixture.fill(Color(0.2, 0.4, 0.6))
	fixture.fill_rect(Rect2i(600, 600, 300, 300), Color.WHITE)
	for extension: String in ["png", "jpg", "jpeg", "webp"]:
		var path: String = directory.path_join("source." + extension)
		if extension == "png":
			fixture.save_png(path)
		elif extension == "webp":
			fixture.save_webp(path, false)
		else:
			fixture.save_jpg(path)
		importer.picker.file_selected.emit(path)
		check(importer.source != null and importer.source.get_size() == Vector2i(1500, 1500), extension + " selection decodes")
		check(not importer.confirm_button.disabled, extension + " enables import")
	var source_path: String = directory.path_join("source.png")
	importer.choose_file()
	await process_frame
	importer.picker.current_path = source_path
	importer.picker.get_ok_button().pressed.emit()
	await process_frame
	check(not importer.picker.visible and importer.source != null, "file dialog Open accepts selected valid image")
	importer.picker.file_selected.emit(source_path)
	var crop: Control = importer.crop
	var initial: Rect2 = crop.crop_rect()
	check(is_equal_approx(initial.size.x / initial.size.y, 5.0 / 7.0), "locked crop ratio")
	check(not Processor.low_resolution(importer.source, initial), "adequate source has no low-resolution warning")
	importer.get_node("Margin/Layout/Controls/ZoomIn").pressed.emit()
	check(crop.crop_width < initial.size.x, "Zoom +")
	importer.get_node("Margin/Layout/Controls/ZoomOut").pressed.emit()
	check(is_equal_approx(crop.crop_width, initial.size.x), "Zoom −")
	var prior_center: Vector2 = crop.center
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	crop._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(40, 20)
	crop._gui_input(drag)
	check(not crop.center.is_equal_approx(prior_center), "crop left-drag pans")
	press.pressed = false
	crop._gui_input(press)
	check(not crop.dragging, "crop release stops pan")
	importer.get_node("Margin/Layout/Controls/Fit").pressed.emit()
	check(crop.crop_rect().encloses(Rect2(Vector2.ZERO, Vector2(1500, 1500))), "Fit contains entire source")
	check(importer.warning.text.contains("padding"), "Fit explains padding")
	var fitted: Image = Processor.normalize(importer.source, crop.crop_rect())
	check(absf(fitted.get_pixel(0, 0).r - Processor.BACKGROUND.r) < 1.0 / 255.0 and absf(fitted.get_pixel(0, 0).g - Processor.BACKGROUND.g) < 1.0 / 255.0 and absf(fitted.get_pixel(0, 0).b - Processor.BACKGROUND.b) < 1.0 / 255.0, "Fit output padding matches preview background")
	importer.get_node("Margin/Layout/Controls/Fill").pressed.emit()
	check(crop.crop_rect().is_equal_approx(initial), "Fill restores centered coverage")
	crop.pan(Vector2(100, 70))
	crop.zoom(2.0)
	importer.get_node("Margin/Layout/Controls/Reset").pressed.emit()
	check(crop.crop_rect().is_equal_approx(initial), "Reset restores centered Fill")
	var state_before_cancel: Rect2 = crop.crop_rect()
	importer.choose_file()
	await process_frame
	importer.picker.get_cancel_button().pressed.emit()
	await process_frame
	check(crop.crop_rect().is_equal_approx(state_before_cancel), "cancel preserves current edit")
	importer.picker.file_selected.emit(directory.path_join("missing.png"))
	check(importer.status.text.contains("Cannot open"), "missing image handled")
	check(crop.crop_rect().is_equal_approx(state_before_cancel), "failed selection preserves crop")
	check(Processor.load_source("not-supported.gif").has("error"), "unsupported format handled")

	importer.picker.file_selected.emit(source_path)
	importer.confirm_button.pressed.emit()
	while importer.busy:
		await process_frame
	check(imported.size() == 1, "confirm crop creates definition")
	var first: Dictionary = imported[0]
	var output := Image.load_from_file(first["image_path"])
	check(output.get_size() == Vector2i(750, 1050), "output exactly 750 × 1050")
	check(first["image_hash"] == FileAccess.get_sha256(first["image_path"]), "SHA-256 matches saved PNG bytes")
	var metadata_path: String = directory.path_join("cards/definitions").path_join(str(first["card_id"]) + ".json")
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	check(metadata is Dictionary and metadata["card_id"] == first["card_id"] and metadata["tags"] == [], "persistent JSON metadata valid")
	# A 300 × 300 square remains square after uniform crop scaling.
	var white_width: int = 0
	var white_height: int = 0
	for x: int in range(750):
		if output.get_pixel(x, 525).r > 0.9:
			white_width += 1
	for y: int in range(1050):
		if output.get_pixel(375, y).r > 0.9:
			white_height += 1
	check(absi(white_width - white_height) <= 1, "export preserves image proportions")
	importer.picker.file_selected.emit(source_path)
	importer.confirm_button.pressed.emit()
	while importer.busy:
		await process_frame
	check(imported.size() == 2 and imported[1]["card_id"] != first["card_id"], "repeat import generates unique definition ID")
	check(imported[1]["image_path"] == first["image_path"] and importer.status.text.contains("reused"), "repeat import reuses exact asset")
	var asset_count: int = 0
	for file: String in DirAccess.get_files_at(directory.path_join("cards")):
		if file.ends_with(".png"):
			asset_count += 1
	check(asset_count == 1, "duplicate import stores only one image file")
	# Reopen storage to verify dedup does not depend on session memory.
	var reopened = Storage.new(directory.path_join("cards"))
	var result: Dictionary = reopened.save_card(output.save_png_to_buffer(), "Restart duplicate", Vector2i(1500, 1500))
	check(result.get("reused", false), "duplicate detection survives storage restart")

	var small := Image.create(100, 140, false, Image.FORMAT_RGBA8)
	small.fill(Color(0.9, 0.3, 0.1))
	small.save_png(directory.path_join("small.png"))
	importer.picker.file_selected.emit(directory.path_join("small.png"))
	check(importer.warning.text.contains("Low resolution"), "small source displays warning")
	importer.confirm_button.pressed.emit()
	while importer.busy:
		await process_frame
	check(imported.size() == 3 and Image.load_from_file(imported[2]["image_path"]).get_size() == Vector2i(750, 1050), "small image imports successfully")

	var large := Image.create(6000, 4000, false, Image.FORMAT_RGBA8)
	large.fill(Color(0.1, 0.8, 0.3))
	large.save_png(directory.path_join("large.png"))
	large = null
	importer.picker.file_selected.emit(directory.path_join("large.png"))
	check(importer.source.get_size() == Vector2i(6000, 4000), "24 megapixel image loads")
	importer.confirm_button.pressed.emit()
	while importer.busy:
		await process_frame
	check(imported.size() == 4 and Image.load_from_file(imported[3]["image_path"]).get_size() == Vector2i(750, 1050), "large image exports successfully")
	check(not importer.warning.text.contains("Low resolution"), "large source has no low-resolution warning")
	importer.picker.file_selected.emit(source_path)
	crop.zoom(4.0)
	check(importer.warning.text.contains("Low resolution"), "deep zoom warns about effective crop resolution")
	var extreme := Image.create(4000, 40, false, Image.FORMAT_RGBA8)
	extreme.fill(Color.CYAN)
	crop.set_image(extreme)
	crop.fit()
	var panorama: Image = Processor.normalize(extreme, crop.crop_rect())
	check(panorama.get_size() == Vector2i(750, 1050), "extreme panorama Fit exports safely")
	importer.picker.file_selected.emit(source_path)
	importer.close_importer()
	check(not importer.visible, "Close hides importer")
	var oversized := Image.create(17000, 1, false, Image.FORMAT_RGBA8)
	oversized.save_png(directory.path_join("too-wide.png"))
	check(Processor.load_source(directory.path_join("too-wide.png")).has("error"), "oversized texture dimension is rejected safely")
	print("USER CARD DIRECTORY: ", ProjectSettings.globalize_path("user://cards"))
	print("TESTS COMPLETE: failures=", failures)
	quit(1 if failures else 0)





