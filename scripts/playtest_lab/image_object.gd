extends Control
var service: Node
var id: String
var texture: Texture2D
var dragging: bool=false
var start: Vector2
var origin: Vector2
func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_STOP;mouse_default_cursor_shape=Control.CURSOR_MOVE
 tooltip_text="PLAYTEST temporary image - drag; double/right-click for properties"
func update(row: Dictionary) -> void:
 position=Vector2(row.position[0],row.position[1]);size=Vector2(row.size[0],row.size[1]);pivot_offset=size/2;rotation_degrees=row.rotation;modulate.a=row.opacity
 texture=service.assets.texture(row.hash);queue_redraw()
func _draw() -> void:
 if texture!=null:draw_texture_rect(texture,Rect2(Vector2.ZERO,size),false)
 else:draw_rect(Rect2(Vector2.ZERO,size),Color(0.2,0.3,0.4,0.8))
 draw_rect(Rect2(Vector2.ZERO,size),Color(0.4,0.8,1,0.5),false,1)
func _gui_input(e: InputEvent) -> void:
 if e is InputEventMouseButton:
  if e.pressed and (e.button_index==MOUSE_BUTTON_RIGHT or e.double_click):service.edit(id);accept_event();return
  if e.button_index==MOUSE_BUTTON_LEFT:
   if e.pressed and not service.objects[id].locked:dragging=true;start=get_global_mouse_position();origin=position
   elif dragging:
    dragging=false;service.change(id,{"position":[position.x,position.y]})
   accept_event()
 elif e is InputEventMouseMotion and dragging:
  position=origin+get_parent().get_global_transform().basis_xform_inv(get_global_mouse_position()-start);accept_event()
