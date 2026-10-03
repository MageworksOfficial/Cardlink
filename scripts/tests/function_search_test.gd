extends SceneTree
var failures: int=0
func _initialize() -> void: run.call_deferred()
func check(v: bool,caption: String) -> void:
	print(("PASS " if v else "FAIL ")+caption)
	if not v: failures+=1
func settle() -> void:
	for i: int in 8: await process_frame
func key() -> InputEventKey:
	var e:=InputEventKey.new();e.keycode=KEY_F;e.ctrl_pressed=true;e.pressed=true;return e
func run() -> void:
	root.size=Vector2i(1152,760);root.gui_embed_subwindows=true
	var app: Control=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app);await settle();app.shared_settings.welcome.hide()
	var search: Node=app.function_search
	search._input(key());check(search.window.visible,"Ctrl+F on title opens function finder");search.window.hide()
	await app.enter_mode(app.Mode.OFFLINE_PLAYTEST);await settle()
	var m: Node=app.table_scene.tabletop
	var c: Node=m.match_controller
	Input.parse_input_event(key());await settle();check(search.window.visible and search.query.has_focus(),"offline Ctrl+F opens focused search")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("function-search.png"))
	search.query.text="search library —";search.query.text_changed.emit(search.query.text);check(search.results.item_count==2,"find both offline player libraries")
	check(c.model.history.is_empty(),"filtering does not execute a command")
	search.activate(0);await settle();check(c.contents.visible and c.inspection_zone=="library" and not c.knowledge_view,"search opens actual library inspection, not known-only view")
	search._input(key());check(c.contents_query.has_focus() and not search.window.visible,"Ctrl+F in inspection focuses its search")
	await create_timer(0.25).timeout;c.contents_list.grab_focus();c.contents.window_input.emit(key());check(c.contents_query.has_focus(),"Ctrl+F received by inspection subwindow focuses search")
	c.close_inspection();await settle()
	search.open();search.query.text="not a real function";search.query.text_changed.emit(search.query.text);check(search.results.item_count==0,"no results handled safely");search.activate();check(search.window.visible,"empty results do nothing")
	var esc:=InputEventKey.new();esc.keycode=KEY_ESCAPE;esc.pressed=true;search.palette_input(esc);check(not search.window.visible,"Escape closes finder")
	search.open();search.query.text="reset match";search.query.text_changed.emit(search.query.text);search.activate();await settle();check(m.battle.reset.prompt.visible,"Reset Match still asks for confirmation");search._input(key());check(not search.window.visible,"Ctrl+F cannot bypass confirmation");m.battle.reset.prompt.hide()
	app.table_scene.open_library();await settle();search._input(key());check(app.table_scene.library.query.has_focus() and not search.window.visible,"collection Ctrl+F focuses card query")
	app.table_scene.library.hide();app.table_scene.open_deck_builder();await settle();search._input(key());check(app.table_scene.deck_builder.query.has_focus(),"deck builder Ctrl+F focuses card query")
	app.table_scene.deck_builder.hide();m.set_active(true);m.custom_table.start_blank();await settle()
	search._input(key());search.query.text="search table components";search.query.text_changed.emit(search.query.text);search.activate();await settle();check(m.custom_table.editor.drawer.search.has_focus(),"custom component search remains accessible")
	search.open();search.query.text="dice";search.query.text_changed.emit(search.query.text);check(search.results.item_count>=1,"tools searchable offline");search.window.hide()
	app.dispose_table();app.mode=app.Mode.TITLE;await settle();await app.enter_mode(app.Mode.ONLINE);await settle();app.table_scene.get_node("Network").window.hide()
	search.open();search.query.text="search hand";search.query.text_changed.emit(search.query.text);check(search.results.item_count==2,"online hidden-zone search uses existing inspection entrypoints")
	search.window.hide();app.dispose_table();app.queue_free();await settle()
	print("FUNCTION SEARCH FAILURES ",failures);quit(0 if failures==0 else 1)
