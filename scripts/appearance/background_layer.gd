extends Control
## A single noninteractive bottom layer; editor gestures are routed by the world.
var appearance: Node
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=0
func _draw() -> void:
	var value: Dictionary=appearance.background
	if value.type=="default": return
	var tint:=Color(value.color);tint.a=value.opacity
	if value.type=="color": draw_rect(Rect2(Vector2.ZERO,size),tint)
	else:
		var texture: Texture2D=appearance.assets.texture(value.asset)
		if texture!=null: draw_texture_rect(texture,Rect2(Vector2.ZERO,size),false,Color(1,1,1,value.opacity))
		else: draw_rect(Rect2(Vector2.ZERO,size),tint)
	if appearance.editing and not value.locked:
		draw_rect(Rect2(Vector2.ZERO,size),Color.CYAN,false,2/appearance.manager.view.zoom)
		for point: Vector2 in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]: draw_rect(Rect2(point-Vector2.ONE*7,Vector2.ONE*14),Color.CYAN)
