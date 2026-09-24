extends Control
var app_shell: Control
var archive_importer: Window
var library: Control
var tabletop: Node
var deck_builder: Control
var replace_deck: ConfirmationDialog
var pending_deck: Dictionary
var pending_leaders: bool
func _ready() -> void:
	$ImportStatus.text = "Drag to move · Right-click to tap · Hover to preview · Middle-drag to pan"
	$ImportCard.hide()
	$ImportStatus.hide()
	$ImportCard.pressed.connect($CardImporter.open_importer)
	$CardImporter.card_imported.connect(_on_card_imported)
	library = (preload("res://scenes/card_library.tscn") as PackedScene).instantiate()
	add_child(library)
	library.back_requested.connect(func() -> void:
		library.hide()
		tabletop.set_active(true))
	library.import_requested.connect($CardImporter.open_importer)
	library.place_requested.connect(_place_card)
	var browse := Button.new()
	browse.text = "Card Library"
	browse.position = Vector2(24, 62)
	browse.size = Vector2(136, 32)
	browse.pressed.connect(func() -> void:
		tabletop.set_active(false)
		library.open_library())
	add_child(browse)
	browse.hide()
	move_child(browse, library.get_index())
	tabletop = (preload("res://scenes/tabletop.tscn") as PackedScene).instantiate()
	add_child(tabletop)
	deck_builder = preload("res://scenes/deck_builder.tscn").instantiate()
	add_child(deck_builder)
	deck_builder.back_requested.connect(func() -> void:
		deck_builder.hide()
		tabletop.set_active(true))
	deck_builder.play_requested.connect(_request_play)
	var decks := Button.new()
	decks.text = "Deck Builder"
	decks.position = Vector2(24, 100)
	decks.size = Vector2(136, 32)
	decks.pressed.connect(func() -> void:
		tabletop.set_active(false)
		move_child(deck_builder, get_child_count() - 1)
		deck_builder.open_builder())
	add_child(decks)
	decks.hide()
	move_child(decks, library.get_index())
	replace_deck = ConfirmationDialog.new()
	replace_deck.dialog_text = "Replace the currently loaded deck's match copies? Imported library definitions and unrelated tabletop cards will remain."
	add_child(replace_deck)
	replace_deck.confirmed.connect(_play_pending)
	archive_importer = preload("res://scripts/archive_importer.gd").new()
	add_child(archive_importer)
	library.archive_requested.connect(open_archive_importer)
	deck_builder.archive_requested.connect(open_archive_importer)
	archive_importer.imported.connect(func(result: Dictionary) -> void:
		if library.visible:
			library.refresh()
		if deck_builder.visible or deck_builder.saved_path == result.path:
			deck_builder.records = deck_builder.loader.load_records()
			deck_builder.refresh_catalog()
		deck_builder.refresh_saved()
		if deck_builder.saved_path == result.path and not deck_builder.dirty:
			deck_builder.load_selected()
		tabletop.controls.refresh_decks())
func _request_play(deck: Dictionary, leaders_out: bool) -> void:
	pending_deck = deck
	pending_leaders = leaders_out
	if not tabletop.match_controller.loaded_ids.is_empty():
		replace_deck.popup_centered()
	else:
		_play_pending()
func _play_pending() -> void:
	var result: Dictionary = tabletop.match_controller.load_deck(pending_deck, pending_leaders)
	if result.has("error"):
		deck_builder.status.text = result.error
		return
	deck_builder.hide()
	tabletop.set_active(true)
func _place_card(record: Dictionary) -> void:
	var result: Dictionary = tabletop.spawn_definition(record)
	if result.has("error"):
		library.status.text = result["error"]
		return
	library.hide()
	tabletop.set_active(true)
func _on_card_imported(metadata: Dictionary, reused: bool) -> void:
	$ImportStatus.text = "Saved: %s%s" % [metadata["name"], " (image reused)" if reused else ""]
	if library.visible:
		library.refresh()

func open_library() -> void:
	tabletop.set_active(false)
	move_child(library, get_child_count() - 1)
	library.open_library()
func open_deck_builder() -> void:
	tabletop.set_active(false)
	move_child(deck_builder, get_child_count() - 1)
	deck_builder.open_builder()

func open_archive_importer() -> void:
	tabletop.controls.close_panels()
	deck_builder.guard(archive_importer.open_importer)

func ensure_network() -> Node:
	var panel: Node = get_node_or_null("Network")
	if panel == null:
		panel = preload("res://scripts/network/network_panel.gd").new()
		panel.name = "Network"
		add_child(panel)
	return panel
func open_network_panel() -> void:
	if tabletop.match_controller.playtest.local_playtest():
		tabletop.controls.status.text = "Choose Online [P] before connecting. Offline playtest never needs a server."
		return
	ensure_network().open_panel()
func return_to_title() -> void:
	if app_shell != null: app_shell.request_return()
