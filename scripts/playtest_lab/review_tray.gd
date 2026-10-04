extends Node
## Temporary private/public workspace. Original cards retain their match IDs.
var manager: Node
var window: Window
var preview: TextureRect
var list: ItemList
var info: Label
var n: SpinBox
var player: String = "local"
var hit: String = ""
var revealing: bool = false
var session_ids: Array[String] = []
var original: Array[String] = []
var committed: bool = false
func c() -> Node: return manager.match_controller
func _ready() -> void:
 window=Window.new();window.title="PLAYTEST - Review Tray";window.size=Vector2i(790,510);window.hide();add_child(window);window.close_requested.connect(window.hide)
 var rows:=VBoxContainer.new();rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);window.add_child(rows)
 info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rows.add_child(info)
 var body:=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;rows.add_child(body)
 list=ItemList.new();list.select_mode=ItemList.SELECT_MULTI;list.icon_mode=ItemList.ICON_MODE_TOP;list.fixed_icon_size=Vector2i(70,98);list.fixed_column_width=110;list.max_columns=0;list.size_flags_vertical=Control.SIZE_EXPAND_FILL;list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(list)
 preview=TextureRect.new();preview.custom_minimum_size=Vector2(210,294);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;body.add_child(preview)
 list.multi_selected.connect(func(index: int,_selected: bool) -> void:preview.texture=list.get_item_icon(index))
 list.gui_input.connect(func(e: InputEvent) -> void:
  if e is InputEventMouseButton and e.pressed and e.button_index==MOUSE_BUTTON_RIGHT: menu(selected())
  elif e is InputEventMouseMotion:
   var index: int=list.get_item_at_position(e.position,true)
   if index>=0:preview.texture=list.get_item_icon(index))
 var tools:=HBoxContainer.new();rows.add_child(tools)
 for entry: Array in [["Select All",select_all],["Select Hit",select_hit],["Select Others",select_others],["Earlier",reorder.bind(-1)],["Later",reorder.bind(1)],["Destinations...",func() -> void: menu(selected())]]: button(tools,entry[0],entry[1])
 var flow:=HBoxContainer.new();rows.add_child(flow)
 button(flow,"REVEAL NEXT",next_card);button(flow,"STOP HERE",stop_here);button(flow,"Reveal selected",reveal_selected)
 button(flow,"Cancel (private only)",cancel);button(flow,"Close / Keep cards",window.hide)
 var position_label:=Label.new();position_label.text="Library insertion position (1 = top):";rows.add_child(position_label)
 n=SpinBox.new();n.min_value=1;n.max_value=5000;n.value=1;rows.add_child(n);n.tooltip_text="One-based Nth position from top"
func button(parent: Node,caption: String,fn: Callable) -> void:
 var b:=Button.new();b.text=caption;b.pressed.connect(fn);parent.add_child(b)
func ids() -> Array[String]:
 var found: Array[Control]=[]
 for card: Control in manager.cards:
  if card.state.current_zone=="review" and card.state.zone_player_id==player: found.append(card)
 found.sort_custom(func(a: Control,b: Control) -> bool: return int(a.state.custom_metadata.get("review_rank",0))<int(b.state.custom_metadata.get("review_rank",0)))
 var result: Array[String]=[]
 for card: Control in found: result.append(card.state.match_instance_id)
 return result
func zone() -> Control:
 for z: Control in manager.zones:
  if z.display_name=="PLAYTEST REVIEW" and z.player_id==player: return z
 var z: Control=manager.add_zone({"display_name":"PLAYTEST REVIEW","zone_type":"custom","player_id":player,"position":(c().library_actions.beside_library(player)+Vector2(-700,-190)).max(Vector2(40,80))})
 z.custom_minimum_size=Vector2(590,180);z.size=z.custom_minimum_size;return z
func begin(player_id: String,count: int,public: bool,until: bool=false) -> bool:
 if c().online() and player_id!="local":
  manager.controls.status.text="Ask the player holding that private library to start its review.";return false
 player=player_id
 if not ids().is_empty(): open();info.text="Resolve the existing review before starting another.";return false
 c().close_inspection();manager.controls.close_panels();original=c().model.players[player].library.order.duplicate();session_ids.clear();hit="";committed=false;revealing=until
 manager.undo.invalidate("Looking at cards is not undoable; use Cancel before committing.")
 take(1 if until else clampi(count,1,50),public);open();return true
func take(count: int,public: bool) -> void:
 var room: int=maxi(0,50-ids().size())
 if public and c().online():room=mini(room,maxi(0,480-c().public_sync.state.cards.size()))
 count=mini(count,room)
 if count<=0:info.text="PLAYTEST review limit reached. Resolve cards before revealing more.";return
 var z: Control=zone()
 c().batching=true
 for id: String in c().model.players[player].library.peek(count):
  var card: Control=c().card_by_id(id)
  if card==null: continue
  c().transitioning=true;manager.assign_zone(card,z);c().transitioning=false
  c().model.players[player].library.order.erase(id)
  card.state.custom_metadata["review_prior"]={"visibility":card.state.visibility,"face_down":card.state.face_down,"public":bool(card.state.custom_metadata.get("public_reveal",false))}
  card.state.custom_metadata["review_rank"]=session_ids.size();session_ids.append(id)
  card.state.current_zone="review";card.state.zone_player_id=player;card.set_face_down(false);card.state.visibility="public" if public else "owner_private"
  if public: c().visibility.set_public_reveal(card.state,true);committed=true
  card.position=z.position+Vector2(10+(session_ids.size()-1)%5*112,38+(session_ids.size()-1)/5*150);card.state.position=card.position
 c().batching=false;c().refresh();refresh()
func next_card() -> void:
 if not revealing: return
 if c().model.players[player].library.order.is_empty(): info.text="Library empty. Stop Here selects the last revealed card.";return
 take(1,true)
func stop_here() -> void:
 revealing=false
 var current: Array[String]=ids();hit=session_ids.back() if not session_ids.is_empty() and session_ids.back() in current else "";select_hit();info.text="Hit selected. Send it somewhere, then Select Others to resolve the rest."
func open() -> void:
 refresh();window.popup_centered_clamped(Vector2i(790,510),0.95)
func refresh() -> void:
 if list==null: return
 list.clear();preview.texture=null
 for id: String in ids():
  var card: Control=c().card_by_id(id);list.add_item(("HIT: " if id==hit else "")+card.state.display_name,card.card_image.texture);list.set_item_metadata(list.item_count-1,id)
 info.text="PLAYTEST REVIEW - %d unresolved. Ctrl/Shift select; right-click for destinations. Close preserves cards." % list.item_count
func selected() -> Array[String]:
 var result: Array[String]=[]
 for i: int in list.get_selected_items(): result.append(str(list.get_item_metadata(i)))
 return result
func select_all() -> void:
 for i: int in list.item_count: list.select(i,false)
func select_hit() -> void:
 list.deselect_all()
 for i: int in list.item_count:
  if list.get_item_metadata(i)==hit: list.select(i,false)
func select_others() -> void:
 list.deselect_all()
 for i: int in list.item_count:
  if list.get_item_metadata(i)!=hit: list.select(i,false)
func reorder(delta: int) -> void:
 var order: Array[String]=ids();var chosen: Array[String]=selected();var indices: Array=[]
 for id: String in chosen: indices.append(order.find(id))
 if delta>0: indices.reverse()
 for index: int in indices:
  var target: int=index+delta
  if target>=0 and target<order.size() and not order[target] in chosen:
   var id: String=order[index];order.remove_at(index);order.insert(target,id)
 for i: int in order.size():
  var card: Control=c().card_by_id(order[i]);card.state.custom_metadata.review_rank=i
  card.position=zone().position+Vector2(10+(i%5)*112,38+(i/5)*150);card.state.position=card.position
 refresh()
 for i: int in list.item_count:
  if list.get_item_metadata(i) in chosen:list.select(i,false)
func menu(chosen: Array) -> void:
 var popup:=PopupMenu.new();window.add_child(popup);popup.add_theme_font_size_override("font_size",18);popup.min_size=Vector2i(340,0)
 var actions: Array=["hand","battlefield","graveyard","exile","top","bottom","nth","random_top","random_bottom","leave"]
 for caption: String in ["Move to Hand","Move to Battlefield","Move to Graveyard","Move to Exile","Library: Top","Library: Bottom","Library: Nth from top","Library: Randomized Top","Library: Randomized Bottom","Leave in Review Tray"]: popup.add_item(caption)
 popup.id_pressed.connect(func(i: int) -> void: destination(chosen,actions[i],int(n.value)))
 popup.popup_hide.connect(popup.queue_free);popup.position=Vector2i(window.get_mouse_position());popup.popup()
func destination(chosen: Array,action: String,position_n: int=1) -> Array[String]:
 var group: Array[String]=[]
 for id: String in ids():
  if id in chosen: group.append(id)
 if group.is_empty() or action=="leave": return group
 if not action in ["hand","battlefield","graveyard","exile","top","bottom","nth","random_top","random_bottom"]: return []
 if action.begins_with("random_"): group.shuffle() # Only this selected group; never the remaining library.
 var library: bool=action in ["top","bottom","nth","random_top","random_bottom"]
 var remaining: Array[String]=c().model.players[player].library.order.duplicate()
 c().batching=true
 var moved: Array[String]=[]
 for id: String in group:
  var card: Control=c().card_by_id(id)
  if c().move_card(card,"library" if library else action,false,player):
   card.state.custom_metadata.erase("review_prior");card.state.custom_metadata.erase("review_rank");moved.append(id)
   if action=="battlefield":card.position=c().library_actions.beside_library(player)+Vector2((moved.size()-1)*110,0);card.state.position=card.position
 if library:
  var index: int=remaining.size() if action in ["bottom","random_bottom"] else (clampi(position_n-1,0,remaining.size()) if action=="nth" else 0)
  for i: int in moved.size(): remaining.insert(index+i,moved[i])
  c().model.players[player].library.order=remaining
  for id: String in moved:
   var card: Control=c().card_by_id(id)
   if card.state.custom_metadata.get("public_reveal",false): c().Knowledge.learn(card.state,"opponent")
 c().batching=false;committed=true;c().refresh();refresh()
 c().record_event("review","Resolved %d reviewed cards: %s" % [moved.size(),action],{})
 return moved
func reveal_selected() -> void:
 for id: String in selected(): c().visibility.set_public_reveal(c().card_by_id(id).state,true)
 committed=true;c().refresh()
func cancel() -> bool:
 var current: Array[String]=ids();current.sort();var expected_ids: Array[String]=session_ids.duplicate();expected_ids.sort()
 if committed or original.is_empty() or current!=expected_ids:
  info.text="Public/committed or restored review cannot be undone. Choose destinations for unresolved cards.";return false
 var expected: Array[String]=original.duplicate()
 for id: String in session_ids:expected.erase(id)
 if c().model.players[player].library.order!=expected:
  info.text="Library changed during review. Resolve cards manually to avoid losing changes.";return false
 c().batching=true
 for id: String in session_ids:
  var card: Control=c().card_by_id(id);var prior: Dictionary=card.state.custom_metadata.review_prior.duplicate()
  c().move_card(card,"library",false,player);card.state.visibility=prior.visibility;card.set_face_down(prior.face_down)
  if not prior.public:card.state.custom_metadata.erase("public_reveal")
  card.state.custom_metadata.erase("review_prior");card.state.custom_metadata.erase("review_rank")
 c().model.players[player].library.order=original.duplicate();c().batching=false;c().refresh();refresh();window.hide();return true
func untap_all() -> int:
 var count: int=0
 var player_id: String=c().active_hand_player()
 for card: Control in manager.cards:
  if card.state.current_zone=="battlefield" and card.state.controller_player_id==player_id and card.tapped: card.set_tapped(false);count+=1
 c().record_event("untap","Untapped %d controlled battlefield objects." % count,{});return count
