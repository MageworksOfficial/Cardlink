extends SceneTree
var folder: String
var role: String
var mode: String
var app: Node
var panel: Node
var results: Dictionary = {}
var wire: Array = []
func _initialize() -> void: run.call_deferred()
func wait_for(test: Callable, seconds: float=15) -> bool:
 var end: int=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  if test.call(): return true
  await process_frame
 return false
func mark(name: String, value: String="ready") -> void:
 var f:=FileAccess.open(folder.path_join(role+"_"+name),FileAccess.WRITE);f.store_string(value);f.close()
func other(name: String) -> String: return folder.path_join(("guest" if role=="host" else "host")+"_"+name)
func barrier(stage: String) -> void:
 mark(stage)
 await wait_for(func() -> bool:return FileAccess.file_exists(other(stage)))
func check(name: String, value: bool) -> void:
 results[name]=value;print(name," ",value)
func finish() -> void:
 results["log"]=panel.gameplay.log;results["sync_log"]=panel.gameplay.card_sync.events;results["network_log"]=panel.network.debug_log
 results["state"]=panel.gameplay.state
 mark("result.json",JSON.stringify(results,"  "));mark("done")
 await wait_for(func() -> bool:return FileAccess.file_exists(other("done")),5)
 app.queue_free();await process_frame;quit(0 if not results.values().has(false) else 1)
func run() -> void:
 var args:=OS.get_cmdline_user_args();folder=args[0];role=args[1];mode=args[2]
 root.size=Vector2i(1152,760);root.gui_embed_subwindows=true
 if mode=="visual": await visual();return
 app=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app)
 await process_frame;await process_frame;app.shared_settings.welcome.hide()
 await app.enter_mode(app.Mode.ONLINE)
 panel=app.table_scene.get_node("Network")
 panel.network.message_sent.connect(func(d: Dictionary) -> void: wire.append(d))
 if mode=="lan":
  panel.port.value=int(args[3]);panel.address.text="127.0.0.1"
  if role=="host": panel.host_button.pressed.emit();mark("hosting")
  else:
   await wait_for(func() -> bool:return FileAccess.file_exists(other("hosting")))
   panel.join_button.pressed.emit()
 else:
  if role=="host":
   await panel.rooms.host_room("Hotfix Test Host")
   if panel.network.server!=null: panel.network.server.stop();panel.network.server=null
   mark("hosting",panel.rooms.code)
  else:
   await wait_for(func() -> bool:return FileAccess.file_exists(other("hosting")),30)
   await panel.rooms.join_room(FileAccess.get_file_as_string(other("hosting")),"Hotfix Test Guest")
 check("connected",await wait_for(func() -> bool:return panel.network.session.state=="connected",35))
 if not results.connected: await finish();return
 if role=="guest": await create_timer(3).timeout
 var c: Node=app.table_scene.tabletop.match_controller
 var store=load("res://scripts/card_storage.gd").new()
 var deck: Dictionary=load("res://scripts/deck_storage.gd").new_deck();deck.deck_name="Fixture "+role
 for i: int in 3:
  var im:=Image.create(750,1050,false,Image.FORMAT_RGBA8);im.fill(Color.from_hsv((0.1 if role=="host" else 0.55)+i*0.08,0.8,0.8))
  var saved: Dictionary=store.save_card(im.save_png_to_buffer(),role+" Custom "+str(i),im.get_size())
  if i==0:
   im.fill(Color.GOLD if role=="host" else Color.PURPLE)
   var back_face: Dictionary=store.save_card(im.save_png_to_buffer(),role+" Alternate Face",im.get_size())
   var faces: Array=[{"face_id":"front","face_index":0,"name":saved.metadata.name,"image_path":saved.metadata.image_path,"image_hash":saved.metadata.image_hash},{"face_id":"other","face_index":1,"name":back_face.metadata.name,"image_path":back_face.metadata.image_path,"image_hash":back_face.metadata.image_hash}]
   saved=load("res://scripts/card_faces.gd").save(store.directory,saved.metadata.name,faces,saved.metadata)
   deck.leaders.append(saved.metadata.card_id)
  if i==2:
   var alias: String=store.directory.path_join(role+"-legacy-art.png")
   DirAccess.rename_absolute(saved.metadata.image_path,alias)
   saved.metadata.image_path=alias
   store.write_atomic(saved.metadata_path,JSON.stringify(saved.metadata).to_utf8_buffer())
  deck.cards.append({"card_id":saved.metadata.card_id,"quantity":i+2})
 var sleeve:=Image.create(500,700,false,Image.FORMAT_RGBA8);sleeve.fill(Color.DARK_BLUE if role=="host" else Color.DARK_RED)
 var back: Dictionary=load("res://scripts/battle/deck_back.gd").store(sleeve.save_png_to_buffer())
 deck["deck_back"]={"type":"image","color":"#2468b4","preset":"","asset":back.hash}
 # Exercise the actual Deck Builder play callback, not a router launch shortcut.
 app.table_scene.open_deck_builder()
 app.table_scene._request_play(deck,true)
 check("deck_loaded",c.pile.order.size()==8)
 check("both_decks_ready",await wait_for(func() -> bool:return panel.preparation.can_start()))
 check("discovery_checked",await wait_for(func() -> bool:return panel.gameplay.card_sync.checked))
 if panel.gameplay.card_sync.catalog!=null: check("three_missing",panel.gameplay.card_sync.inspect_required().missing==3)
 mark("discovered")
 await wait_for(func() -> bool:return FileAccess.file_exists(other("discovered")))
 panel.preparation.start_sync()
 check("synced",await wait_for(func() -> bool:return panel.gameplay.card_sync.checked and panel.gameplay.card_sync.inspect_required().missing==0,40))
 app.table_scene.tabletop.shortcuts.start_match_button.pressed.emit()
 check("active",await wait_for(func() -> bool:return panel.gameplay.enabled))
 check("opponent_library",await wait_for(func() -> bool:return c.hidden_count("opponent","library")==8))
 mark("counts_ready")
 await wait_for(func() -> bool:return FileAccess.file_exists(other("counts_ready")))
 check("leader_public",await wait_for(func() -> bool:return panel.gameplay.state.cards.size()==2))
 check("remote_back",await wait_for(func() -> bool:return not app.table_scene.tabletop.deck_backs.remote.is_empty() and app.table_scene.tabletop.deck_backs.remote.get("library",{}).get("type")=="image"))
 for id: String in c.pile.order.duplicate():
  if c.card_by_id(id).state.faces.size()>1: c.pile.put(id,true);break
 c.draw_card()
 var local_card: Control=c.card_by_id(c.model.players.local.hand[0])
 c.move_card(local_card,"battlefield")
 check("both_public",await wait_for(func() -> bool:return panel.gameplay.state.cards.size()==4))
 local_card.position=panel.gameplay.serializer.decode_position([0.25 if role=="host" else 0.65,0.55]);local_card.set_tapped(true)
 c.change_life("local",-3)
 check("life_mirrored",await wait_for(func() -> bool:return c.model.players.opponent.life==37))
 await create_timer(1).timeout
 check("public_art",app.table_scene.tabletop.cards.any(func(card: Control) -> bool:return card.state.owner_player_id=="opponent" and card.state.current_zone=="battlefield" and card.card_image.texture!=null))
 await barrier("public_done")
 var opposite_id: String=""
 for id: String in panel.gameplay.state.cards:
  if panel.gameplay.state.cards[id].owner==panel.gameplay.remote_id and panel.gameplay.state.cards[id].zone=="battlefield":opposite_id=id
 check("tap_mirrored",await wait_for(func() -> bool:return panel.gameplay.state.cards.get(opposite_id,{}).get("tapped",false)))
 check("movement_mirrored",await wait_for(func() -> bool:return absf(panel.gameplay.state.cards.get(opposite_id,{}).get("position",[-1,-1])[0]-(0.65 if role=="host" else 0.25))<0.0001))
 load("res://scripts/card_faces.gd").apply(local_card.state,1);app.table_scene.tabletop.apply_card_art(local_card)
 check("face_mirrored",await wait_for(func() -> bool:return panel.gameplay.state.cards.get(opposite_id,{}).get("face_index",0)==1))
 await barrier("faces_done")
 local_card.set_face_down(true)
 check("facedown_private",await wait_for(func() -> bool:return panel.gameplay.state.cards.get(opposite_id,{}).get("face_down",false) and panel.gameplay.state.cards.get(opposite_id,{}).get("art","x")=="" and panel.gameplay.state.cards.get(opposite_id,{}).get("definition","x")==""))
 await barrier("hidden_done")
 local_card.set_face_down(false)
 for zone: String in ["graveyard","exile","commander","battlefield"]:
  c.move_card(local_card,zone,true,"local")
  check(zone+"_mirrored",await wait_for(func() -> bool:return panel.gameplay.state.cards.get(opposite_id,{}).get("zone")==zone))
  await barrier(zone+"_done")
 var token: Control=app.table_scene.tabletop.create_token(role+" Token","local","local","","2","3").card
 check("tokens_mirrored",await wait_for(func() -> bool:return panel.gameplay.state.cards.values().filter(func(d:Dictionary)->bool:return d.token).size()==2))
 await barrier("tokens_done")
 local_card.state.set_counter("Loyalty",4);local_card.update_counters()
 app.table_scene.tabletop.extras.create_counter(Vector2(400,700),7,role+" counter")
 check("counters_mirrored",await wait_for(func() -> bool:return panel.gameplay.state.counters.size()==2 and panel.gameplay.state.cards[opposite_id].counters.get("Loyalty")==4))
 await barrier("counters_done")
 await capture_ui(role+"-shared-table")
 if role=="host": c.end_turn()
 check("host_turn",await wait_for(func() -> bool:return panel.gameplay.state.turn.number==2))
 await barrier("host_turn_done")
 if role=="guest": c.end_turn()
 check("guest_turn",await wait_for(func() -> bool:return panel.gameplay.state.turn.number==3))
 var private_id: String=c.pile.order[0]
 check("private_library_id_absent",not JSON.stringify(wire).contains(private_id))
 check("online_undo_disabled",not app.table_scene.tabletop.undo.available())
 mark("before_fault")
 await wait_for(func() -> bool:return FileAccess.file_exists(other("before_fault")))
 if role=="guest":
  panel.gameplay.submit([{ "kind":"counter_set", "data":{"id":"fault","position":[0,0],"value":1000001,"label":"Bound check"}}])
  c.change_life("local",-1)
 check("valid_action_after_rejection",await wait_for(func() -> bool:return panel.gameplay.state.players.player_2.life==36))
 mark("played")
 await wait_for(func() -> bool:return FileAccess.file_exists(other("played")))
 if role=="host":
  deck.cards[0].quantity=3
  c.load_deck(deck,false)
 await create_timer(3).timeout
 check("discovery_after_reload",panel.preparation.can_start() and panel.gameplay.card_sync.checked)
 results["transport"]=panel.rooms.method if mode!="lan" else "LAN"
 results["epoch"]=panel.network.match_epoch
 await finish()





func capture_ui(name: String) -> void:
 if DisplayServer.get_name()=="headless":return
 for i: int in 12: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func audit_text(node: Node) -> void:
 for property: String in ["text","tooltip_text","title"]:
  for item: Dictionary in node.get_property_list():
   if item.name!=property:continue
   var value: Variant=node.get(property)
   if value is String and (value.contains("â") or value.contains("Â") or value.contains("�")):
    print("BAD_UI_TEXT ",node.get_path()," ",property);results["encoding"]=false
 for child: Node in node.get_children():audit_text(child)
func visual() -> void:
 app=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app)
 for i: int in 10:await process_frame
 app.shared_settings.welcome.hide()
 await capture_ui("01-title")
 app.shared_settings.open()
 await capture_ui("02-settings-top")
 app.shared_settings.settings_content.scroll_vertical=300
 await capture_ui("03-settings-middle")
 app.shared_settings.settings_content.scroll_vertical=9999
 await capture_ui("04-settings-bottom")
 app.title_screen.settings.hide()
 app.shared_settings.key_bindings.popup_centered_clamped(Vector2i(640,560),0.95)
 await capture_ui("05-key-bindings")
 app.shared_settings.key_bindings.rows.get_parent().scroll_vertical=9999
 await capture_ui("05b-key-bindings-bottom")
 app.shared_settings.key_bindings.hide()
 app.shared_settings.open_help()
 await capture_ui("06-controls")
 app.shared_settings.helper.hide()
 load("res://scripts/integrations/integration_hub.gd").open(app,2)
 await capture_ui("07-integrations")
 root.get_node("OptionalCardCatalog").window.hide()
 await app.enter_mode(app.Mode.ONLINE)
 await capture_ui("08-online")
 panel=app.table_scene.get_node("Network");panel.window.hide()
 await capture_ui("09-tabletop")
 app.table_scene.open_deck_builder()
 await capture_ui("10-deck-builder")
 var builder: Node=app.table_scene.deck_builder
 builder.back_picker.open({})
 await capture_ui("11-deck-back")
 builder.back_picker.hide();builder.hide()
 app.table_scene.open_library()
 await capture_ui("12-card-library")
 app.table_scene.library.hide();app.table_scene.tabletop.set_active(true)
 app.table_scene.tabletop.controls.open_panel("Match")
 await capture_ui("13-match")
 app.table_scene.tabletop.controls.close_panels()
 app.table_scene.tabletop.controls.open_panel("Layout")
 await capture_ui("14-layout")
 app.table_scene.tabletop.controls.close_panels()
 app.table_scene.tabletop.appearance.open()
 await capture_ui("15-background")
 app.table_scene.tabletop.appearance.editor.hide()
 app.table_scene.tabletop.battle.saves.open()
 await capture_ui("16-save-load")
 results.encoding=true;audit_text(root)
 mark("visual.json",JSON.stringify(results));print("VISUAL_COMPLETE ",results)
 app.queue_free();await process_frame;quit()
