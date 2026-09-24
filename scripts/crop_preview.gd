extends Control
## The crop is stored in source pixels; resizing the UI preserves the edit.
signal crop_changed
const Processor = preload("res://scripts/card_image_processor.gd")
var source: Image
var texture: ImageTexture
var center: Vector2 = Vector2.ZERO
var crop_width: float = 1.0
var dragging: bool = false

func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)
	mouse_default_cursor_shape = Control.CURSOR_DRAG

func set_image(image: Image) -> void:
	source = image
	texture = ImageTexture.create_from_image(image)
	reset()

func frame_rect() -> Rect2:
	var available: Vector2 = (size - Vector2(40, 40)).max(Vector2(5, 7))
	var height: float = minf(available.y, available.x * 7.0 / 5.0)
	var frame_size := Vector2(height * 5.0 / 7.0, height)
	return Rect2((size - frame_size) / 2.0, frame_size)

func crop_rect() -> Rect2:
	var crop_size := Vector2(crop_width, crop_width * 7.0 / 5.0)
	return Rect2(center - crop_size / 2.0, crop_size)

func fit() -> void:
	if source == null:
		return
	center = Vector2(source.get_size()) / 2.0
	crop_width = maxf(source.get_width(), source.get_height() * 5.0 / 7.0)
	changed()

func fill() -> void:
	if source == null:
		return
	center = Vector2(source.get_size()) / 2.0
	crop_width = minf(source.get_width(), source.get_height() * 5.0 / 7.0)
	changed()

func reset() -> void:
	dragging = false
	fill()

func zoom(factor: float) -> void:
	if source == null or factor <= 0.0:
		return
	var fit_width: float = maxf(source.get_width(), source.get_height() * 5.0 / 7.0)
	crop_width = clampf(crop_width / factor, maxf(1.0, fit_width / 32.0), fit_width * 2.0)
	changed()

func pan(delta: Vector2) -> void:
	if source == null:
		return
	center -= delta * crop_width / frame_rect().size.x
	# Keep at least part of the image within the frame.
	var half := Vector2(crop_width, crop_width * 7.0 / 5.0) * 0.49
	center = center.clamp(-half, Vector2(source.get_size()) + half)
	changed()

func changed() -> void:
	queue_redraw()
	crop_changed.emit()

func _gui_input(event: InputEvent) -> void:
	if source == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.1)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.0 / 1.1)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		pan(event.relative)
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.045, 0.055, 0.075))
	var frame: Rect2 = frame_rect()
	draw_rect(frame, Processor.BACKGROUND)
	if texture != null:
		var scale_factor: float = frame.size.x / crop_width
		var image_rect := Rect2(frame.get_center() - center * scale_factor, Vector2(source.get_size()) * scale_factor)
		# Draw only the part inside the locked crop frame.
		var intersection: Rect2 = image_rect.intersection(frame)
		if intersection.has_area():
			var region := Rect2((intersection.position - image_rect.position) / scale_factor, intersection.size / scale_factor)
			draw_texture_rect_region(texture, intersection, region)
	draw_rect(frame, Color(0.45, 0.8, 1.0), false, 2.0)
