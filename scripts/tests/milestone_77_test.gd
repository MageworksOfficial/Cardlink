extends "res://scripts/tests/milestone_74_test.gd"
const Faces = preload("res://scripts/card_faces.gd")
const FaceAction = preload("res://scripts/usability/face_actions.gd")
func run() -> void:
	var base: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1152,760)
	root.gui_embed_subwindows = true
	var app: Control = new_app(base)
	app.entry.start(app.Mode.OFFLINE_PLAYTEST)
	await wait_for(func() -> bool: return not app.entering and app.table_scene != null)
	var table: Node = app.table_scene.tabletop
	var c: Node = table.match_controller
	var directory: String = base.path_join("cards")
	var storage = preload("res://scripts/card_storage.gd").new(directory)
	var definitions: Array = []
	for i: int in 3:
		var image := Image.create(750,1050,false,Image.FORMAT_RGBA8)
		image.fill([Color.BLUE,Color.RED,Color.GREEN][i])
		definitions.append(storage.save_card(image.save_png_to_buffer(),"Face "+str(i+1),image.get_size()).metadata)
	var faces: Array = []
	for i: int in 3:
		var face: Dictionary = Faces.list(definitions[i])[0]
		face.face_id = "face_"+str(i)
		face.face_index = i
		faces.append(face)
	var created: Dictionary = Faces.save(directory,"Three-sided piece",faces)
	check(not created.has("error"),"Create generic three-face definition")
	check(DirAccess.get_files_at(directory).size() == 3,"Multi-face definition reuses three existing assets")
	c.loader = preload("res://scripts/library_loader.gd").new(directory)
	var rows: Array = c.loader.load_records()
	check(rows.size() == 4,"One new definition; originals retained")
	var row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r.metadata.card_id == created.metadata.card_id)[0]
	var card: Control = table.spawn_definition(row).card
	check(card.state.faces.size() == 3 and card.state.display_name == "Face 1","Default front face displays")
	var id: String = card.state.match_instance_id
	card.position = Vector2(700,500)
	card.state.position = card.position
	card.set_tapped(true)
	card.state.counters = {"charge":3}
	card.update_counters()
	await process_frame
	var sibling: int = card.get_index()
	check(FaceAction.change(table,card),"Change to next face")
	check(card.state.active_face_index == 1 and card.state.display_name == "Face 2","Alternate name/index updated")
	check(card.state.match_instance_id == id and c.card_by_id(id) == card,"Same physical object and instance ID")
	check(card.state.tapped and is_equal_approx(card.card_image.rotation_degrees,90),"Tap rotation preserved")
	check(card.state.counters == {"charge":3},"Counters preserved")
	check(card.state.owner_player_id == "local" and card.state.controller_player_id == "local","Owner/controller preserved")
	check(card.state.current_zone == "battlefield" and card.position == Vector2(700,500),"Zone/position preserved")
	check(card.get_index() == sibling and table.selected_card == card,"Selection/z-order preserved")
	await process_frame
	check(table.undo.available() and not table.undo.entries.is_empty(),"Offline face change is undoable")
	table.undo.undo()
	card = c.card_by_id(id)
	check(card.state.active_face_index == 0 and card.state.display_name == "Face 1","Undo restores previous face")
	FaceAction.change(table,card,2)
	await process_frame
	var saved: Dictionary = preload("res://scripts/match_snapshot.gd").capture(table)
	check(preload("res://scripts/match_snapshot.gd").validate(saved).is_empty(),"Multi-face snapshot validates")
	FaceAction.change(table,card,0)
	check(not table.persistence.restore_match(saved).has("error"),"Snapshot restores")
	card = c.card_by_id(id)
	check(card.state.active_face_index == 2 and card.state.image_path == faces[2].image_path,"Save/load restores active face artwork")
	table.perspective.switch_to("opponent",false)
	check(card.state.active_face_index == 2 and is_equal_approx(card.get_global_transform().get_rotation(),0),"Offline seat preserves active face and upright root")
	app.bindings.assign("card_face",KEY_J)
	table.select_card(card)
	table.shortcuts.dispatcher.execute("card_face")
	check(card.state.active_face_index == 0,"Assigned face hotkey cycles faces")
	check(app.bindings.keys.perspective == KEY_V and app.bindings.keys.tap == KEY_Q,"V perspective and Q tap unchanged")
	card.set_face_down(true)
	FaceAction.change(table,card,1)
	check(card.state.face_down and card.state.active_face_index == 1,"Face-down flag remains independent of printed face")
	card.set_face_down(false)
	app.table_preferences.put("reduce_motion",true)
	FaceAction.change(table,card,2)
	check(card.card_image.modulate.a == 1,"Instant face swap respects Reduce Motion")
	var library: Control = preload("res://scripts/card_library.gd").new()
	library.loader = c.loader
	root.add_child(library)
	library.refresh()
	library.select_record(row.path)
	check(library.face_tools.picker.item_count == 3,"Library alternate-face choices")
	library.face_tools.show_face(1)
	check(library.preview.texture.get_image().get_pixel(0,0).r > 0.9,"Library preview displays alternate red art")
	var cleanup: Dictionary = c.loader.storage.cleanup_candidates()
	check(cleanup.paths.is_empty(),"Cleanup protects every referenced face")
	var single: Control = table.spawn_definition(rows.filter(func(r: Dictionary) -> bool: return r.metadata.card_id == definitions[0].card_id)[0]).card
	check(single.state.faces.size() == 1 and not FaceAction.change(table,single),"Old single-face definition stays valid")
	var descriptor: Dictionary = preload("res://scripts/network/card_sync_catalog.gd").descriptor(created.metadata)
	check(preload("res://scripts/network/card_sync_protocol.gd").definition(descriptor),"Multi-face Card Sync descriptor validates")
	check(not JSON.stringify(descriptor).contains("image_path") and not descriptor.has("active_face_index"),"Asset descriptor contains no paths or live face state")
	table.select_card(card)
	table.controls.open_card_actions()
	var change_button: Button = table.controls.card_actions.filter(func(button: Button) -> bool: return button.text.begins_with("Change Face"))[0]
	change_button.pressed.emit()
	check(card.state.active_face_index==0,"Right-click Card Actions face control cycles without stealing double-click")
	table.controls.close_panels()
	FaceAction.change(table,card,1)
	await process_frame
	app.recovery.save_recovery()
	var recovered: Dictionary = app.recovery.storage.read_record(app.recovery.saved_path)
	check(not recovered.has("error"),"Autosave writes multi-face recovery")
	check(recovered.record.data.cards.filter(func(row: Dictionary) -> bool: return row.match_instance_id==id)[0].active_face_index==1,"Recovery record retains active face")
	FaceAction.change(table,card,0)
	table.persistence.restore_match(recovered.record.data)
	check(c.card_by_id(id).state.active_face_index==1,"Recovery snapshot restores alternate face")
	var invalid: Dictionary = recovered.record.data.duplicate(true)
	invalid.cards[0].active_face_index=99
	check(not preload("res://scripts/match_snapshot.gd").validate(invalid).is_empty(),"Invalid saved face index rejected safely")
	library.queue_free()
	app.queue_free()
	await process_frame
	print("CARDLINK 7.7: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
