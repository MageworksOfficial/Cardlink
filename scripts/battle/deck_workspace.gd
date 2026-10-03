extends Control
signal closed
var deck_builder: Control
var library: Control
var archive_importer: Window
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var importer: Window=preload("res://ui/card_importer.tscn").instantiate();add_child(importer)
	library=preload("res://scenes/card_library.tscn").instantiate();add_child(library);library.hide()
	deck_builder=preload("res://scenes/deck_builder.tscn").instantiate();deck_builder.standalone=true;add_child(deck_builder)
	archive_importer=preload("res://scripts/archive_importer.gd").new();add_child(archive_importer)
	deck_builder.import_requested.connect(func() -> void: preload("res://scripts/collection_workflow.gd").custom(deck_builder))
	library.import_requested.connect(func() -> void: preload("res://scripts/collection_workflow.gd").custom(library))
	deck_builder.archive_requested.connect(archive_importer.open_importer)
	library.archive_requested.connect(archive_importer.open_importer)
	archive_importer.imported.connect(func(_result: Dictionary) -> void: deck_builder.refresh_saved())
	deck_builder.back_requested.connect(func() -> void: closed.emit())
	deck_builder.open_builder()

func _exit_tree() -> void:
	var hub: Node=get_tree().root.get_node_or_null("OptionalCardCatalog")
	if hub!=null and hub.context_owner!=null and hub.context_owner.get_ref()==deck_builder:
		hub.cancel();hub.context_owner=null
		if hub.window!=null: hub.window.hide()
