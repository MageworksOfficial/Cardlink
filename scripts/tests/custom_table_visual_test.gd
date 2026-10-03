extends SceneTree
func _initialize() -> void: run.call_deferred()
func capture(name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name+".png"))
func run() -> void:
	root.size = Vector2i(1280,800)
	root.gui_embed_subwindows = true
	var app: Control = load("res://scenes/application_shell.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.4).timeout
	app.shared_settings.welcome.hide()
	app.choose_table(app.Mode.OFFLINE_PLAYTEST)
	await capture("choose-table")
	app.table_chosen(true)
	await create_timer(0.7).timeout
	var b: Node = app.table_scene.tabletop.custom_table
	b.panel.open_palette()
	await capture("components")
	b.panel.hide()
	var board: Dictionary = b.add_component("board")
	var image := Image.create(800,500,false,Image.FORMAT_RGB8)
	image.fill(Color("315856"))
	for x: int in range(0,800,100):
		for y: int in range(0,500,100):
			if (x/100+y/100)%2 == 0: image.fill_rect(Rect2i(x,y,100,100),Color("497e78"))
	var stored: Dictionary = b.assets.store(image.save_png_to_buffer())
	b.update_component(board.id,{"asset":stored.hash,"position":[100,150],"size":[1600,1000]})
	var pile: Dictionary = b.add_component("shared_deck")
	b.update_component(pile.id,{"position":[500,400]})
	b.add_component("hand","player_1")
	b.add_component("hand","player_2")
	b.add_component("discard")
	b.manager.layout.set_edit_mode(false)
	await capture("custom-table")
	b.panel.open_component(pile.id)
	await capture("pile-properties")
	app.dispose_table()
	app.queue_free()
	await process_frame
	quit()
