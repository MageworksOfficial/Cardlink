extends SceneTree
var app: Control
var m: Node
var base: String
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i: int in 8: await process_frame
func shot(name_text: String) -> void:
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(base.path_join(name_text+".png"))
func select(items: Array) -> void:
	m.selection.clear()
	for item: Control in items: m.selection.ids.append(item.state.match_instance_id)
	m.selection.paint()
func record(name_text: String, color: Color) -> Dictionary:
	var image:=Image.create(750,1050,false,Image.FORMAT_RGB8);image.fill(Color("ebdfc9"))
	image.fill_rect(Rect2i(25,25,700,1000),color)
	image.fill_rect(Rect2i(50,55,650,110),Color("efe6d8"))
	image.fill_rect(Rect2i(50,195,650,435),color.lightened(0.2))
	image.fill_rect(Rect2i(100,260,550,290),color.darkened(0.2))
	image.fill_rect(Rect2i(50,665,650,335),Color("efe6d8"))
	var path: String=base.path_join(name_text+".png");image.save_png(path)
	return {"name":name_text,"image_path":path,"metadata":{"card_id":name_text.to_lower().replace(" ","_")},"thumbnail":ImageTexture.create_from_image(image)}
func run() -> void:
	base=OS.get_cmdline_user_args()[0];root.size=Vector2i(1920,1080);root.content_scale_size=root.size;root.gui_embed_subwindows=true
	app=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app);await settle();app.shared_settings.welcome.hide()
	await app.enter_mode(app.Mode.OFFLINE_PLAYTEST);await settle();m=app.table_scene.tabletop
	var lands: Array=[];var creatures: Array=[];var tokens: Array=[]
	var land: Dictionary=record("Land sample",Color("729763"));var creature: Dictionary=record("Creature sample",Color("659cba"))
	for i: int in 8:
		var card: Control=m.spawn_definition(land,false).card;card.position=Vector2(360+i*115,860);card.state.position=card.position;lands.append(card)
	for i: int in 6:
		var card: Control=m.spawn_definition(creature,false).card;card.position=Vector2(430+i*135,580);card.state.position=card.position;creatures.append(card)
	for i: int in 5:
		var token: Control=m.create_token("Wolf %d" % (i+1),"local","local","","2","2").card;token.position=Vector2(1750,260+i*152);token.state.position=token.position;tokens.append(token)
	m.view.zoom=0.7;m.view.pan=Vector2(130,55);m.view.apply_view()
	select(lands);m.selection.arrange.apply(0);await shot("01-stack")
	m.selection.arrange.apply(1);await shot("02-fan")
	select(creatures);m.selection.arrange.apply(2);await shot("03-horizontal-row")
	select(tokens);m.selection.arrange.apply(3);await shot("04-vertical-column")
	select(creatures)
	for i: int in creatures.size(): creatures[i].position=Vector2(400+[0,40,190,260,550,950][i],500)
	m.selection.arrange.apply(4);await shot("05-distributed")
	select(lands);m.selection.arrange.apply(0);m.selection.arrange.apply(5);await shot("06-spread")
	for extent: Vector2i in [Vector2i(1920,1080),Vector2i(1152,648),Vector2i(960,540)]:
		root.size=extent;root.content_scale_size=extent;await settle();m.view.zoom=0.4;m.view.pan=Vector2.ZERO;m.view.apply_view()
		m.selection.open_bulk(lands[0],Vector2(20,20));await settle()
		var menu: PopupMenu=m.selection.arrange.menu
		menu.position=m.selection.bulk.position+Vector2i(m.selection.bulk.size.x,0);menu.popup();await shot("07-menu-"+str(extent.x));menu.hide();m.selection.bulk.hide()
	app.function_search.open();app.function_search.query.text="arrange";app.function_search.filter_entries();await shot("08-function-search")
	app.function_search.window.hide();app.dispose_table();app.queue_free();await process_frame;quit()
