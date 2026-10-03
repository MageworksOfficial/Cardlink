extends RefCounted
## Opens the existing importer without replacing the current deck editing session.
static func custom(owner: Node) -> void:
	var table: Node = owner.get_parent()
	var importer: Window = table.get_node_or_null("CardImporter")
	if importer == null: return
	importer.open_importer(owner)
static func valid_deck(context: WeakRef) -> Node:
	if context == null: return null
	var node: Node = context.get_ref()
	return node if is_instance_valid(node) and node.has_method("add_imported_card") and node.is_visible_in_tree() else null
static func view_card(context: WeakRef, id: String) -> void:
	if context == null: return
	var library: Node = context.get_ref()
	if not is_instance_valid(library) or not library.has_method("select_record"): return
	library.query.text = ""
	library.tag_filter.select(0)
	library.refresh()
	for record: Dictionary in library.records:
		if record.metadata.get("card_id") == id: library.select_record(record.path); return
