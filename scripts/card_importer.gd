extends Window
signal card_imported(metadata: Dictionary, reused: bool)
const Processor = preload("res://scripts/card_image_processor.gd")
const Storage = preload("res://scripts/card_storage.gd")
const CropPreview = preload("res://scripts/crop_preview.gd")
var storage: Storage = Storage.new()
var last_definition: Dictionary = {}
var adding_face: bool = false
var add_face_button: Button
var source: Image
var busy: bool = false
var context_owner: WeakRef
var followup: Button
@onready var crop: CropPreview = %CropPreview
@onready var picker: FileDialog = $FileDialog
@onready var name_edit: LineEdit = %CardName
@onready var status: Label = %Status
@onready var warning: Label = %Warning
@onready var confirm_button: Button = %Confirm

func _ready() -> void:
	add_face_button = Button.new()
	add_face_button.text = "Add Another Face"
	add_face_button.disabled = true
	%Confirm.get_parent().add_child(add_face_button)
	add_face_button.pressed.connect(func() -> void:
		if not busy: adding_face = true; choose_file())
	followup = Button.new()
	followup.hide()
	%Confirm.get_parent().add_child(followup)
	followup.pressed.connect(use_imported_card)
	%Close.text = "Done"
	close_requested.connect(close_importer)
	%Close.pressed.connect(close_importer)
	%Choose.pressed.connect(func() -> void: adding_face = false; choose_file())
	picker.file_selected.connect(select_file)
	picker.canceled.connect(cancel_selection)
	%Fit.pressed.connect(crop.fit)
	%Fill.pressed.connect(crop.fill)
	%Reset.pressed.connect(crop.reset)
	%ZoomIn.pressed.connect(crop.zoom.bind(1.25))
	%ZoomOut.pressed.connect(crop.zoom.bind(0.8))
	confirm_button.pressed.connect(confirm_crop)
	crop.crop_changed.connect(update_warning)

func open_importer(context: Node = null) -> void:
	context_owner = weakref(context) if context != null else null
	followup.hide()
	popup_centered_clamped(Vector2i(900, 600), 0.9)

func close_importer() -> void:
	if not busy:
		adding_face = false
		crop.dragging = false
		hide()

func choose_file() -> void:
	picker.popup_centered_clamped(Vector2i(760, 520), 0.9)

func cancel_selection() -> void:
	adding_face = false
	status.text = "File selection canceled. Your current crop is unchanged."

func select_file(path: String) -> void:
	var loaded: Dictionary = Processor.load_source(path)
	if loaded.has("error"):
		status.text = str(loaded["error"])
		return
	followup.hide()
	source = loaded["image"] as Image
	name_edit.text = path.get_file().get_basename()
	crop.set_image(source)
	confirm_button.disabled = false
	status.text = "Image loaded. Drag to pan; use the wheel or buttons to zoom."

func update_warning() -> void:
	if source == null:
		warning.text = ""
		return
	var resolution: String = "%d × %d source • 750 × 1050 output" % [source.get_width(), source.get_height()]
	warning.text = resolution
	if Processor.low_resolution(source, crop.crop_rect()):
		warning.text += "\nLow resolution: this source or crop needs enlargement and may look soft."
	var bounds := Rect2(Vector2.ZERO, Vector2(source.get_size()))
	if not bounds.encloses(crop.crop_rect()):
		warning.text += "\nUncovered areas will use dark padding."

func confirm_crop() -> void:
	if source == null or busy:
		return
	busy = true
	add_face_button.disabled = true
	confirm_button.disabled = true
	%Choose.disabled = true
	status.text = "Saving card…"
	await get_tree().process_frame
	var output: Image = Processor.normalize(source, crop.crop_rect())
	var result: Dictionary
	if output == null:
		result = {"error": "Cannot export this crop."}
	else:
		if adding_face and not last_definition.is_empty():
			var asset: Dictionary = storage.save_asset(output.save_png_to_buffer())
			result = asset
			if not asset.has("error"):
				var faces: Array = preload("res://scripts/card_faces.gd").list(last_definition)
				faces.append({"face_id":"face_"+str(faces.size()),"face_index":faces.size(),"name":name_edit.text.strip_edges(),"image_path":asset.image_path,"image_hash":asset.image_hash})
				result = preload("res://scripts/card_faces.gd").save(storage.directory,str(last_definition.name),faces,last_definition)
		else:
			result = storage.save_card(output.save_png_to_buffer(), name_edit.text, source.get_size())
	# The shared collection event is deferred so archive workers can use it too.
	# Keep completion behind that refresh, including for callers awaiting busy.
	await get_tree().process_frame
	busy = false
	add_face_button.disabled = last_definition.is_empty()
	confirm_button.disabled = false
	%Choose.disabled = false
	if result.has("error"):
		status.text = str(result["error"])
		return
	last_definition = result.metadata
	adding_face = false
	add_face_button.disabled = false
	var metadata: Dictionary = result["metadata"]
	var reused: bool = result["reused"]
	status.text = "Card added to your library: "+str(metadata.name)
	if reused: status.text += " · Existing image reused."
	followup.text = "Add to Current Deck" if preload("res://scripts/collection_workflow.gd").valid_deck(context_owner) != null else "View Card"
	followup.visible = context_owner != null
	card_imported.emit(metadata, reused)



func use_imported_card() -> void:
	var deck: Node = preload("res://scripts/collection_workflow.gd").valid_deck(context_owner)
	if deck != null:
		if deck.add_imported_card(str(last_definition.card_id)): status.text = "Card added to current deck."
	else:
		preload("res://scripts/collection_workflow.gd").view_card(context_owner,str(last_definition.card_id))
		close_importer()
