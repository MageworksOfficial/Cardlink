extends Button
var record_path: String
func configure(record: Dictionary, selected: bool) -> void:
	record_path = record["path"]
	toggle_mode = true
	button_pressed = selected
	custom_minimum_size = Vector2(154, 246)
	tooltip_text = str(record["name"]) + "\n" + "\n".join(record["errors"])
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 8
	layout.offset_top = 8
	layout.offset_right = -8
	layout.offset_bottom = -8
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(130, 182)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = record["thumbnail"]
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(picture)
	if picture.texture == null:
		var placeholder := Label.new()
		placeholder.text = "Image unavailable"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(placeholder)
	var title := Label.new()
	title.text = record["name"]
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(title)
	var detail := Label.new()
	detail.text = "Needs attention" if not record["errors"].is_empty() else ", ".join(record["tags"])
	var face_count: int = preload("res://scripts/card_faces.gd").list(record.metadata).size()
	if face_count>1: detail.text = "%d Faces · " % face_count+detail.text
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(detail)
