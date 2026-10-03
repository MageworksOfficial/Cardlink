extends Control
var builder: Node
var id: String
var picture: TextureRect
var caption: Label
var dragging: bool = false
func _ready() -> void:
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption = Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_outline_size",3)
	add_child(caption)
	caption.position = Vector2(8,6)
	resized.connect(func() -> void: caption.size.x = maxf(40,size.x-16))
	refresh()
func refresh() -> void:
	var item: Dictionary = builder.row(id)
	if item.is_empty(): return
	if builder.editor != null and builder.editor.gesture.get("id","") == id: return
	position = Vector2(item.position[0],item.position[1])
	size = Vector2(item.size[0],item.size[1])
	rotation_degrees = item.rotation
	# Keep labels/borders readable; opacity applies to zone fill and board art.
	picture.modulate.a = item.opacity
	visible = not item.hidden and builder.manager.active
	var count: int = builder.orders.get(id,[]).size()
	if item.kind in ["deck","shared_deck"] and builder.pile_sync.connected() and not builder.pile_sync.owns(item): count = builder.pile_sync.remote_counts.get(id,0)
	caption.add_theme_font_size_override("font_size",int(13.0/maxf(0.4,builder.manager.view.zoom)))
	caption.add_theme_color_override("font_color",preload("res://scripts/custom_table/builder_editor.gd").accent(item.owner))
	caption.text = preload("res://scripts/custom_table/builder_editor.gd").badge(item.owner)+("\n" if item.kind in ["deck","shared_deck","discard"] else " · ")+item.name
	if item.kind in ["deck","shared_deck"] and id in [builder.primary_for("player_1"),builder.primary_for("player_2")]: caption.text += "\n[ SHARED DRAW ]" if item.owner == "table" else "\n[ DRAW ]"
	if item.kind in ["deck","shared_deck","discard"]: caption.text += "\n%d cards" % count
	if item.kind == "text": caption.text += "\n"+item.text
	if item.locked and builder.manager.layout.edit_mode: caption.text += "  [LOCK]"
	caption.size.x = maxf(40,size.x-16)
	picture.texture = builder.assets.texture(item.asset) if item.kind == "board" else null
	if item.kind in ["deck","shared_deck"]:
		picture.texture = builder.manager.deck_backs.pile_texture(id)
		if not builder.manager.deck_backs.piles.has(id) and not builder.manager.deck_backs.remote.piles.has(id):
			var legacy: Texture2D=builder.assets.texture(item.back)
			if legacy!=null: picture.texture=legacy
		if not builder.orders.get(id,[]).is_empty():
			var top: Control = builder.manager.match_controller.card_by_id(builder.orders[id][0])
			if top != null and (item.visibility == "public" or top.state.custom_metadata.get("public_reveal",false)): picture.texture = top.card_image.texture
	if item.kind in ["board","zone","shared_area","hand","leader"]:
		z_index = 0
		get_parent().move_child(self,0)
	caption.visible = item.kind != "board" or picture.texture == null or builder.manager.layout.edit_mode
	mouse_filter = Control.MOUSE_FILTER_STOP if builder.manager.layout.edit_mode else (Control.MOUSE_FILTER_PASS if item.kind in ["deck","shared_deck","discard"] else Control.MOUSE_FILTER_IGNORE)
	queue_redraw()
func resize_supported() -> bool:
	var item: Dictionary = builder.row(id)
	return item.kind in ["zone","shared_area","board","hand","leader"] and is_zero_approx(float(item.rotation)) and not item.locked
func handles() -> Array[Vector2]: return [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]
func corner(handle: Vector2) -> Vector2: return Vector2(0 if handle.x < 0 else size.x,0 if handle.y < 0 else size.y)
func _draw() -> void:
	var item: Dictionary = builder.row(id)
	if item.is_empty(): return
	var accent: Color = preload("res://scripts/custom_table/builder_editor.gd").accent(item.owner)
	var selected: bool = builder.editor != null and builder.editor.selected == id and builder.manager.layout.edit_mode
	if item.kind != "board":
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.04,0.18,0.25,0.10*item.opacity))
		draw_rect(Rect2(Vector2.ZERO,Vector2(size.x,minf(size.y,42))),Color(0.02,0.09,0.15,0.4))
		draw_rect(Rect2(Vector2.ZERO,size),accent*Color(1,1,1,0.6),false,2)
	if selected:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.2,0.95,1,0.22),false,10)
		draw_rect(Rect2(Vector2.ZERO,size),Color.CYAN,false,3)
		if resize_supported():
			var width: float = 16/maxf(0.4,builder.manager.view.zoom)
			for handle: Vector2 in handles(): draw_rect(Rect2(corner(handle)-Vector2.ONE*width/2,Vector2.ONE*width),Color("b6faff"))
		if not item.locked: draw_line(Vector2(size.x/2-12,18),Vector2(size.x/2+12,18),Color.CYAN,4)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			builder.editor.context_menu(id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if builder.manager.layout.edit_mode:
				var handle := Vector2.ZERO
				if resize_supported() and builder.editor.selected == id:
					for candidate: Vector2 in handles():
						if event.position.distance_to(corner(candidate)) < 24/maxf(builder.manager.view.zoom,0.4): handle = candidate; break
				builder.editor.begin_transform(id,builder.manager.world.get_local_mouse_position(),handle)
				accept_event()
			elif event.double_click:
				builder.editor.context_menu(id)
				accept_event()
