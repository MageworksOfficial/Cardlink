extends Container
## Pure presentation: state, visibility and drag payloads remain in HandCard.
var mode: String = "Straight"
var card_scale: float = 1.0
func _get_minimum_size() -> Vector2:
	var count: int = get_child_count()
	var step: float = 74.0 if mode == "Straight" else 44.0
	return Vector2(maxf(70,(count-1)*step+76)*card_scale,118*card_scale + (18 if mode == "Fan" else 0))
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var count: int = get_child_count()
		var step: float = (74.0 if mode == "Straight" else 44.0)*card_scale
		for i: int in count:
			var card: Control = get_child(i)
			card.custom_minimum_size = Vector2(70,98)*card_scale
			card.size = card.custom_minimum_size
			card.pivot_offset = Vector2(card.size.x/2,card.size.y)
			var t: float = (i-float(count-1)/2)/maxf(1,float(count-1)/2)
			card.rotation = t*0.16 if mode == "Fan" else 0
			card.position = Vector2(i*step+4,8+absf(t)*14 if mode == "Fan" else 0)
			card.z_index = mini(i,4095)
func configure(style: String, factor: float) -> void:
	mode = style
	card_scale = clampf(factor,0.65,1.4)
	update_minimum_size()
	queue_sort()
