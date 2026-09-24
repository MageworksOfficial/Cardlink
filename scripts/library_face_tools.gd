extends RefCounted
var library: Control
var picker: OptionButton
var current: Dictionary = {}
var combine: AcceptDialog
var second: OptionButton
func _init(owner: Control, rows: Node) -> void:
	library = owner
	picker = OptionButton.new()
	rows.add_child(picker)
	picker.item_selected.connect(show_face)
	library.action(rows,"Combine with another definition as faces…",open_combine)
	combine = AcceptDialog.new()
	combine.title = "Create a new multi-face definition"
	combine.ok_button_text = "Combine · Keep originals"
	library.add_child(combine)
	second = OptionButton.new()
	combine.add_child(second)
	combine.confirmed.connect(commit_combine)
func select(record: Dictionary) -> void:
	current = record
	picker.clear()
	if record.is_empty(): picker.hide(); return
	var faces: Array = preload("res://scripts/card_faces.gd").list(record.metadata)
	for i: int in faces.size(): picker.add_item("Face %d / %d · %s" % [i+1,faces.size(),faces[i].name])
	picker.visible = faces.size()>1
	if not faces.is_empty(): show_face(0)
func show_face(index: int) -> void:
	var faces: Array = preload("res://scripts/card_faces.gd").list(current.get("metadata",{}))
	if index < 0 or index >= faces.size(): return
	var path: String = str(faces[index].get("image_path",""))
	library.preview.texture = null
	if path.get_base_dir().simplify_path() == library.loader.storage.directory.simplify_path() and not path.contains("..") and FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK: library.preview.texture = ImageTexture.create_from_image(image)
	library.preview_placeholder.visible = library.preview.texture == null
	library.preview_placeholder.text = "Face image unavailable"
func open_combine() -> void:
	if current.is_empty(): library.status.text = "Select the first definition."; return
	second.clear()
	for record: Dictionary in library.records:
		if record.path == current.path: continue
		second.add_item(record.name)
		second.set_item_metadata(second.item_count-1,record)
	if second.item_count == 0: library.status.text = "Import another face image first."; return
	combine.popup_centered(Vector2i(500,130))
func commit_combine() -> void:
	if current.is_empty() or second.selected<0: return
	var other: Dictionary = second.get_selected_metadata()
	var faces: Array = preload("res://scripts/card_faces.gd").list(current.metadata)+preload("res://scripts/card_faces.gd").list(other.metadata)
	for i: int in faces.size(): faces[i].face_index = i; faces[i].face_id = "face_"+str(i)
	var result: Dictionary = preload("res://scripts/card_faces.gd").save(library.loader.storage.directory,current.name,faces)
	if result.has("error"): library.status.text = result.error; return
	library.refresh()
	library.select_record(result.metadata_path)
	library.status.text = "Created one multi-face definition. Original definitions and image assets retained."
