extends Button
## Full original texture; visible frame defines input geometry, not transparent padding.
var hover_amount: float = 0.0
var motion: Tween
var artwork: Texture2D
var frame: Rect2
var art_rect: Rect2
func _ready() -> void:
	for state: String in ["normal","hover","pressed","focus"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for event: Signal in [mouse_entered,mouse_exited,focus_entered,focus_exited,button_down,button_up]: event.connect(update_feedback)
	resized.connect(queue_redraw)
func _draw() -> void:
	if artwork == null: return
	var factor: float = minf(size.x/frame.size.x,size.y/frame.size.y)
	var inset: Vector2 = (size-frame.size*factor)/2
	art_rect = Rect2(inset-frame.position*factor,artwork.get_size()*factor)
	var growth: float = 1.0+hover_amount*0.012
	draw_set_transform(size/2+Vector2(0,-2*hover_amount),0,Vector2.ONE*growth)
	art_rect.position -= size/2
	draw_texture_rect(artwork,art_rect,false,Color(0.82,0.92,1) if is_pressed() else (Color(1.15,1.15,1.15) if is_hovered() or has_focus() else Color.WHITE))
	if has_focus() or is_hovered(): draw_rect(Rect2(inset-size/2,frame.size*factor).grow(5),Color("8beaff"),false,2)

func update_feedback() -> void:
	var target: float = 1.0 if is_hovered() or has_focus() else 0.0
	if is_pressed(): target = -0.3
	var shell: Node = get_parent().get_parent().get_parent()
	if motion != null: motion.kill()
	if shell.get("table_preferences") != null and bool(shell.table_preferences.value("reduce_motion",false)):
		hover_amount = 0
		queue_redraw()
		return
	motion = create_tween()
	motion.tween_method(func(value: float) -> void: hover_amount = value; queue_redraw(),hover_amount,target,0.14)
