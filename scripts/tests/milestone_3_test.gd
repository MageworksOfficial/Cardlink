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
func motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func button(point: Vector2, key: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if key == MOUSE_BUTTON_RIGHT and not pressed:
		var controls: Node = root.find_child("TabletopControls",true,false)
		if controls != null and controls.panels.Card.visible:
			for action: Button in controls.card_actions:
				if action.text == "Tap / Untap": action.pressed.emit()
			controls.close_panels()

func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://cache/tabletop_tests/" + Crypto.new().generate_random_bytes(8).hex_encode()
	var directory: String = base.path_join("cards")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1152, 760)
	root.gui_embed_subwindows = true
	var main := preload("res://scripts/tests/table_fixture.gd").create_main()
	root.add_child(main)
	await process_frame
	await process_frame
	var table = main.tabletop
	check(table.controls.visible and table.cards.size() == 1, "tabletop opens with existing card")
	var fixture := Image.create(750, 1050, false, Image.FORMAT_RGB8)
	fixture.fill(Color.CORNFLOWER_BLUE)
	var store := Storage.new(directory)
	store.save_card(fixture.save_png_to_buffer(), "Azure Guardian", Vector2i(750, 1050))
	main.library.loader = Loader.new(directory)
	main.library.open_library()
	main.library.select_record(main.library.records[0]["path"])
	main.library.place_button.pressed.emit()
	await process_frame
	check(table.cards.size() == 2 and not main.library.visible, "library places selected definition on tabletop")
	var first: Control = table.cards[1]
	var record: Dictionary = main.library.records[0]
	var second: Control = table.spawn_definition(record)["card"]
	await process_frame
	check(first.state.card_definition_id == second.state.card_definition_id and first.state.match_instance_id != second.state.match_instance_id, "copies share definition and have unique match IDs")
	check(first.state != second.state, "copies have independent state")
	main.tabletop.world.get_node("Card").position = Vector2(850, 100)
	first.position = Vector2(80, 110)
	second.position = Vector2(390, 110)
	var center: Vector2 = first.position + first.size / 2
	motion(center)
	check(first.hover_preview.visible and not second.hover_preview.visible, "hover belongs to pointed card")
	button(center, MOUSE_BUTTON_RIGHT, true)
	button(center, MOUSE_BUTTON_RIGHT, false)
	await process_frame
	check(first.tapped and not second.tapped and first.state.tapped, "tap is independent and state synchronized")
	button(center, MOUSE_BUTTON_RIGHT, true)
	button(center, MOUSE_BUTTON_RIGHT, false)
	motion(center)
	button(center, MOUSE_BUTTON_LEFT, true)
	motion(center + Vector2(35, 20), true)
	button(center + Vector2(35, 20), MOUSE_BUTTON_LEFT, false)
	check(first.position.is_equal_approx(Vector2(115, 130)) and second.position.is_equal_approx(Vector2(390, 110)), "drag moves only one copy")
	check(not first.dragging and first.state.position == first.position, "drag release synchronizes position")
	first.position = Vector2(80, 110)
	second.position = first.position
	table.select_card(first)
	await process_frame
	check(first.get_index() > second.get_index() and first.is_selected and not second.is_selected, "selection raises card through GUI sibling order")
	table.send_to_back()
	check(first.get_index() < second.get_index(), "send back changes overlap order")
	center = second.position + second.size / 2
	motion(center)
	button(center, MOUSE_BUTTON_RIGHT, true)
	button(center, MOUSE_BUTTON_RIGHT, false)
	await process_frame
	check(second.tapped and not first.tapped and table.selected_card == second, "overlap pointer selects visible front card")
	table.bring_to_front(first)
	check(first.get_index() > second.get_index(), "bring front changes overlap order")
	var commander: Control = table.add_zone({"display_name": "Leader", "zone_type": "commander", "capacity": 1, "position": Vector2(400, 100)})
	var custom: Control = table.add_zone({"display_name": "Quest", "zone_type": "custom", "position": Vector2(720, 155)})
	check(commander.zone_id != custom.zone_id and custom.display_name == "Quest" and commander.capacity == 1, "zones have independent ID name type position and capacity")
	check(table.assign_zone(first, commander) and first.state.zone_id == commander.zone_id and commander.members.has(first.state.match_instance_id), "move card into commander zone")
	var old_position: Vector2 = second.position
	check(not table.assign_zone(second, commander) and second.state.zone_id.is_empty() and second.position == old_position, "full capacity rejects move without changing state")
	table.select_card(second)
	await process_frame
	for i: int in table.controls.destination.item_count:
		if table.controls.destination.get_item_metadata(i) == custom.zone_id: table.controls.destination.select(i)
	table.move_selected_to_zone()
	check(second.state.zone_id == custom.zone_id, "selected card moves into custom zone through action")
	var before: Vector2 = second.position
	table.layout.set_edit_mode(true)
	var header_point: Vector2 = custom.position + Vector2(10, 10)
	motion(header_point)
	button(header_point, MOUSE_BUTTON_LEFT, true)
	motion(header_point + Vector2(15, 25), true)
	button(header_point + Vector2(15, 25), MOUSE_BUTTON_LEFT, false)
	check(second.position == before + Vector2(15, 25) and second.state.position == second.position, "zone movement carries member cards")
	second.position = Vector2(20, 110)
	table.finish_drag(second)
	check(second.state.zone_id.is_empty() and custom.members.is_empty(), "free drag out clears zone membership")
	second.position = commander.position + Vector2(20, 44)
	table.drag_origins[second.state.match_instance_id] = Vector2(20, 110)
	table.finish_drag(second)
	check(second.position == Vector2(20, 110) and second.state.zone_id.is_empty(), "drag into full zone restores previous location")
	first.position = custom.position + Vector2(20, 44)
	table.finish_drag(first)
	check(first.state.zone_id == custom.zone_id and commander.members.is_empty(), "drag into different zone transfers membership")
	table.change_life(1)
	check(table.life == 41, "life increment")
	table.change_life(-2)
	check(table.life == 39 and table.controls.life_label.text == "Life: 39", "life decrement updates display")
	table.select_card(first)
	table.controls.counter_name.text = "Shield"
	table.change_counter(1)
	table.change_counter(1)
	check(first.state.counters.get("Shield") == 2 and second.state.counters.is_empty() and first.counter_label.text.contains("Shield: 2"), "named counters belong to selected instance and display")
	table.change_counter(-1)
	table.change_counter(-1)
	table.change_counter(-1)
	check(first.state.counters.is_empty(), "counter removal stops at zero")
	table.set_active(false)
	check(not first.visible and not table.controls.visible and not table.zone_layer.visible, "library navigation hides tabletop surfaces")
	table.set_active(true)
	check(first.visible and table.controls.visible and first.state.zone_id == custom.zone_id, "tabletop return retains state")
	check(table.spawn_definition({}).has("error"), "invalid definition cannot spawn")
	if OS.get_cmdline_user_args().size() > 1:
		root.size = Vector2i(1152, 648)
		main.tabletop.world.get_node("Card").hide()
		table.assign_zone(first, null)
		first.position = Vector2(75, 110)
		table.controls.counter_name.text = "Shield"
		table.change_counter(2)
		table.assign_zone(second, commander)
		second.set_tapped(false)
		first.hover_preview.hide()
		second.hover_preview.hide()
		custom.position = Vector2(750, 110)
		commander.position = Vector2(410, 110)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(base.path_join("tabletop.png"))
	print("TABLETOP TESTS COMPLETE: failures=", failures)
	quit(1 if failures else 0)








