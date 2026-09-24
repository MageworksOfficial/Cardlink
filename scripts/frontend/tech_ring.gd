extends Control
## The supplied logo has a baked-in ring. Independent faint vector arcs add
## motion behind it without rotating or editing the supplied lettering.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	for i: int in 8:
		var start: float = i*TAU/8.0
		draw_arc(Vector2.ZERO,166,start,start+0.48,18,Color(0.2,0.75,1,0.23),1.2,true)
		draw_line(Vector2.from_angle(start)*171,Vector2.from_angle(start)*176,Color(0.3,0.8,1,0.3),1.2,true)
