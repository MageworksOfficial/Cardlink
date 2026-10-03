extends SceneTree
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i: int in 8: await process_frame
func shot(path: String) -> void:
	await settle();await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(path)
func run() -> void:
	root.gui_embed_subwindows=true
	var base: String=OS.get_cmdline_user_args()[0]
	var app: Control=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app);await settle();app.shared_settings.welcome.hide()
	await app.enter_mode(app.Mode.OFFLINE_PLAYTEST);await settle()
	var m: Node=app.table_scene.tabletop
	var image:=Image.create(1000,700,false,Image.FORMAT_RGB8);image.fill(Color("284c3e"))
	image.fill_rect(Rect2i(100,100,800,500),Color("356451"));image.fill_rect(Rect2i(120,120,760,460),Color("234438"))
	var stored: Dictionary=m.appearance.assets.store(image.save_png_to_buffer())
	var value: Dictionary=m.appearance.Config.defaults();value.type="image";value.asset=stored.hash;value.locked=false;m.appearance.apply(value)
	m.layout.set_edit_mode(true);m.appearance.toggle_edit()
	for extent: Vector2i in [Vector2i(1920,1080),Vector2i(1152,648),Vector2i(960,540)]:
		root.size=extent;root.content_scale_size=extent;await settle();m.view.reset_view()
		m.appearance.open();await shot(base.path_join("background-"+str(extent.x)+".png"));m.appearance.editor.hide()
		m.appearance.sleeves.open("local");await shot(base.path_join("sleeve-"+str(extent.x)+".png"));m.appearance.sleeves.picker.hide()
		await shot(base.path_join("table-"+str(extent.x)+".png"))
	app.function_search.open();app.function_search.query.text="playmat";app.function_search.filter_entries();await shot(base.path_join("function-search.png"));app.function_search.window.hide()
	app.queue_free();await process_frame;quit()
