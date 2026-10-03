extends Node
var client: Node
var catalog: Node
var importer: Node
var window: Window
var context_owner: WeakRef
var settings_path: String = "user://integrations/scryfall/settings.cfg"
static func open(owner: Node, tab: int = 0) -> void:
	var root: Window = owner.get_tree().root
	var hub: Node = root.get_node_or_null("OptionalCardCatalog")
	if hub==null:
		hub=load("res://scripts/integrations/integration_hub.gd").new()
		hub.name="OptionalCardCatalog"
		root.add_child(hub)
	hub.context_owner = weakref(owner)
	hub.open_window(tab)
func _ready() -> void:
	client=preload("res://scripts/integrations/scryfall_client.gd").new()
	add_child(client)
	catalog=preload("res://scripts/integrations/scryfall_catalog.gd").new()
	catalog.client=client; add_child(catalog); catalog.load_local()
	importer=preload("res://scripts/integrations/scryfall_importer.gd").new()
	importer.client=client; importer.catalog=catalog; add_child(importer)
	var settings := ConfigFile.new()
	settings.load(settings_path)
	client.enabled=bool(settings.get_value("scryfall","enabled",false))
func set_enabled(value: bool) -> Error:
	client.enabled=value
	if not value: cancel()
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	var settings := ConfigFile.new()
	settings.set_value("scryfall","enabled",value)
	return settings.save(settings_path)
func cancel() -> void:
	importer.cancelled=true; catalog.cancelled=true; client.cancel()
func open_window(tab: int = 0) -> void:
	if window==null:
		window=preload("res://scripts/integrations/catalog_window.gd").new()
		window.hub=self
		add_child(window)
	window.tabs.current_tab=tab
	window.popup_centered_clamped(Vector2i(1040,680),0.90)
