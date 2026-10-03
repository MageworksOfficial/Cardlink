extends "res://scripts/tests/milestone_6b_test.gd"
const Layout = preload("res://scripts/usability/arrange_layout.gd")
func rects_at(count: int) -> Array:
	var result: Array = []
	for i: int in count: result.append(Rect2(Vector2(400+i*2,400+i*3),Vector2(100,140)))
	return result
func identity(card: Control) -> Dictionary:
	var data: Dictionary=card.state.to_data();data.erase("position");return data
func click(point: Vector2, pressed: bool=true) -> InputEventMouseButton:
	var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;return e
func run() -> void:
	var table:=Rect2(0,0,2304,1296)
	for count: int in [2,5,10,24]:
		var rects: Array=rects_at(count)
		for mode: int in 6:
			var points: Array=Layout.positions(rects,mode,table)
			check(points.size()==count and points==Layout.positions(rects,mode,table),"Deterministic %s with %d" % [Layout.MODES[mode],count])
			if mode==0: check(points[1].x>points[0].x and points[1].x-points[0].x<10 and points[1].y>points[0].y,"Stack has subtle visible diagonal edges")
			if mode==1: check(points[0].y==points[-1].y and points[1].x-points[0].x<100 and points[1].x-points[0].x>10,"Fan straight horizontal overlap; no arc")
			if mode in [2,5]: check(points[1].x-points[0].x>=118 and points[0].y==points[-1].y,"Readable horizontal spacing")
			if mode==3: check(points[1].y-points[0].y>=158 and points[0].x==points[-1].x,"Readable vertical spacing")
	var varied: Array=[Rect2(0,100,60,80),Rect2(120,100,200,100),Rect2(600,100,100,140)]
	var horizontal: Array=Layout.positions(varied,2,table)
	check(horizontal[1].x-horizontal[0].x==78 and horizontal[2].x-horizontal[1].x==218,"Horizontal uses actual different widths")
	var vertical: Array=Layout.positions(varied,3,table)
	check(vertical[1].y-vertical[0].y==98 and vertical[2].y-vertical[1].y==118,"Vertical uses actual different heights")
	var row: Array=[Rect2(200,200,100,140),Rect2(230,220,100,140),Rect2(800,200,100,140)]
	var distributed: Array=Layout.positions(row,4,table)
	check(distributed[0]==row[0].position and distributed[2]==row[2].position and distributed[1]==Vector2(500,220),"Horizontal distribution preserves endpoints and perpendicular position")
	row=[Rect2(200,200,100,140),Rect2(210,230,100,140),Rect2(200,800,100,140)]
	distributed=Layout.positions(row,4,table)
	check(distributed[1]==Vector2(210,500) and distributed[2]==row[2].position,"Vertical distribution uses dominant center span")
	row=[Rect2(200,200,100,140),Rect2(210,220,100,140),Rect2(600,600,100,140)]
	check(Layout.positions(row,4,table)[1]==Vector2(400,220),"Ambiguous distribution defaults horizontal")
	check(Layout.positions(row.slice(0,2),4,table)==[row[0].position,row[1].position],"Two-object distribution retains endpoints")
	var center_rects: Array=rects_at(5)
	var center_points: Array=Layout.positions(center_rects,1,table)
	var fan_rects: Array=[]
	for i: int in center_points.size(): fan_rects.append(Rect2(center_points[i],center_rects[i].size))
	check(Layout.union_rect(center_rects).get_center().is_equal_approx(Layout.union_rect(fan_rects).get_center()),"Stable selection center anchors arrangements")
	var started: int=Time.get_ticks_usec()
	for i: int in 100: Layout.positions(rects_at(200),i%6,table)
	print("200-object layout average microseconds: ",(Time.get_ticks_usec()-started)/100)
	var edge: Array=[Rect2(2250,1230,100,140),Rect2(2260,1240,100,140)]
	var points: Array=Layout.positions(edge,2,table)
	check(points[0].x>=0 and points[-1].x+100<=2304 and points[-1].y+140<=1296,"Whole formation shifted inside table edges")
	points=Layout.positions(rects_at(24),2,table)
	check(points[0].x==0 and points[-1].x+100>2304,"Oversized row extends naturally without shrinking")
	var base: String=OS.get_cmdline_user_args()[0]
	root.size=Vector2i(1152,760);root.gui_embed_subwindows=true
	var app: Control=await create_client(base.path_join("cards"),"Arrange sample",Color.CORAL)
	var m: Node=app.tabletop;var c: Node=m.match_controller;var s: Control=m.selection
	var items: Array[Control]=[]
	for id: String in c.pile.order.duplicate().slice(0,5):
		var card: Control=c.card_by_id(id);c.move_card(card,"battlefield");items.append(card)
	items[0].set_tapped(true);items[1].set_face_down(true)
	items[2].state.set_counter("charge",3);items[2].update_counters();c.change_controller(items[3],"opponent")
	var token: Control=m.create_token("Wolf","local","opponent","","2","2").card;items.append(token)
	var counter: Control=m.extras.create_counter(Vector2(700,400),7,"Test");items.append(counter)
	await process_frame
	for i: int in items.size(): items[i].position=Vector2(400+i*20,400+i*10)
	m.undo.finish();s.ids.clear()
	var prior: Dictionary={};var order: Array=[]
	for item: Control in items:
		s.ids.append(s.object_id(item));order.append(item.get_index())
		if item in m.cards: prior[s.object_id(item)]=identity(item)
	var selected: Array=s.ids.duplicate();s.ids.reverse()
	s.arrange.apply(0)
	check(s.ids.size()==7 and counter.value==7,"Mixed cards, token and standalone counter arrange")
	var ranked: Array=items.duplicate()
	ranked.sort_custom(func(a: Control,b: Control) -> bool: return a.get_index()<b.get_index() if a.z_index==b.z_index else a.z_index<b.z_index)
	var ordered_edges: bool=true
	for i: int in ranked.size()-1: ordered_edges=ordered_edges and s.bounds(ranked[i]).position.x<s.bounds(ranked[i+1]).position.x
	for i: int in items.size(): ordered_edges=ordered_edges and items[i].get_index()==order[i]
	check(ordered_edges,"Stack uses scene order, not selection order; top stays top")
	for mode: int in 6:
		s.arrange.apply(mode)
		var intact: bool=true
		for item: Control in items:
			if item in m.cards: intact=intact and identity(item)==prior[s.object_id(item)]
		check(intact and items[0].tapped and items[1].state.face_down,"All instance/owner/controller/tap/face/counter fields unchanged: "+Layout.MODES[mode])
		check(s.ids.size()==selected.size() and items[0].is_selected,"Selection and highlight preserved: "+Layout.MODES[mode])
		check(items[0].card_image.rotation!=0 and items[1].rotation==0,"No arrangement rotates or untaps objects: "+Layout.MODES[mode])
	var positions: Array=[]
	for item: Control in items: positions.append(item.position)
	s.object_input(items[0],click(Vector2(10,10)))
	s.move_group(Vector2(90,30))
	var relative: bool=true
	for i: int in items.size(): relative=relative and items[i].position.is_equal_approx(positions[i]+Vector2(90,30));items[i].dragging=false
	s.moving=false;s.origins.clear();m.drag_origins.clear()
	check(relative,"Group drag retains arranged offsets for cards/tokens/counters")
	s.clear();s.set_single(items[0]);items[0].position+=Vector2(50,0)
	check(items[1].position==positions[1]+Vector2(90,30),"Individual object moves independently after deselection")
	s.ids.assign(selected);var before: Vector2=items[0].position
	var hand: Control=c.card_by_id(c.pile.order[0]);c.move_card(hand,"hand");s.ids.append(hand.state.match_instance_id)
	s.arrange.update_menu();s.arrange.apply(0)
	check(s.bulk.is_item_disabled(s.bulk.get_item_index(100)) and items[0].position==before and c.model.players.local.hand.has(hand.state.match_instance_id),"Mixed hand selection disables whole operation without moving anything")
	s.ids.assign(selected);s.ids.append("missing")
	s.arrange.apply(0);check(items[0].position==before,"Stale or unsupported selected ID fails safely")
	s.ids.assign(selected);c.move_card(items[0],"graveyard");s.arrange.apply(0)
	check(m.controls.status.text.contains("battlefield objects only"),"Graveyard selection rejected clearly")
	c.move_card(items[0],"battlefield");s.ids.assign(selected)
	var background: Dictionary=m.appearance.background.duplicate(true)
	m.custom_table.enabled=true;s.arrange.apply(1)
	check(m.appearance.background==background and token.state.is_token,"Build Your Own uses same arrangement; background untouched")
	m.custom_table.enabled=false
	m.undo.finish();var saved: Dictionary=m.persistence.capture_match();var old_positions: Array=[]
	for item: Control in items: old_positions.append(item.position)
	s.arrange.apply(3);var undo_count: int=m.undo.entries.size();m.undo.undo()
	check(undo_count>0 and m.match_controller.card_by_id(selected[0]).position.is_equal_approx(old_positions[0]),"Offline Arrange undo restores the whole operation")
	var restored: Dictionary=m.persistence.restore_match(saved)
	check(not restored.has("error") and m.match_controller.card_by_id(selected[1]).position.is_equal_approx(old_positions[1]),"Arranged positions survive save/load")
	var restored_token: Control=m.match_controller.card_by_id(selected[5])
	m.match_controller.move_card(restored_token,"graveyard")
	check(m.match_controller.card_by_id(selected[5])==null,"Arranged token still follows destruction lifecycle")
	var independent: Control=m.match_controller.card_by_id(selected[0]);independent.set_tapped(false)
	check(not independent.tapped and m.match_controller.card_by_id(selected[1]).state.face_down,"Independent tap and face actions remain separate")
	app.queue_free();await process_frame;await process_frame
	var shell: Control=load("res://scenes/application_shell.tscn").instantiate();root.add_child(shell)
	for i: int in 8: await process_frame
	shell.shared_settings.welcome.hide();await shell.enter_mode(shell.Mode.OFFLINE_PLAYTEST)
	for i: int in 8: await process_frame
	var finder: Node=shell.function_search;finder.build_entries()
	for alias: String in ["arrange","organize","stack","fan","line up","spread","distribute"]:
		finder.query.text=alias;finder.filter_entries()
		check(finder.visible_entries.any(func(row: Dictionary) -> bool: return row.caption=="Arrange Selected"),"Ctrl+F alias: "+alias)
	var sm: Node=shell.table_scene.tabletop
	sm.selection.arrange.open();check(sm.controls.status.text=="Select multiple battlefield objects first.","Ctrl+F empty selection gives useful guidance")
	for i: int in 2:
		var created: Control=sm.create_token("Sample","local","local").card;sm.selection.ids.append(created.state.match_instance_id)
	sm.selection.arrange.open();await process_frame
	check(sm.selection.arrange.menu.visible and sm.selection.arrange.menu.item_count==6,"Ctrl+F opens the six-choice popup")
	sm.selection.arrange.menu.hide()
	sm.selection.open_bulk(sm.selection.resolve(sm.selection.ids[0]),Vector2(5,5));await process_frame
	check(sm.selection.bulk.get_item_submenu(sm.selection.bulk.get_item_index(100))=="Arrange" and sm.selection.bulk.get_parent()==sm.controls,"Arrange submenu uses screen-fixed bulk menu")
	shell.dispose_table();shell.queue_free();await process_frame
	print("ARRANGE: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
