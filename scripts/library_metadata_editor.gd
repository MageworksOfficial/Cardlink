extends VBoxContainer
signal save_requested(card_name: String, tags: Array[String])
var name_edit: LineEdit
var tags_edit: LineEdit
var save_button: Button
func _ready() -> void:
	var title := Label.new()
	title.text = "Card name"
	add_child(title)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Card name"
	add_child(name_edit)
	var caption := Label.new()
	caption.text = "Tags (comma separated)"
	add_child(caption)
	tags_edit = LineEdit.new()
	tags_edit.placeholder_text = "Creature, Forest, Custom set"
	add_child(tags_edit)
	save_button = Button.new()
	save_button.text = "Save name & tags"
	save_button.pressed.connect(func() -> void: save_requested.emit(name_edit.text, parse_tags(tags_edit.text)))
	add_child(save_button)
func show_record(record: Dictionary) -> void:
	name_edit.text = str(record.get("metadata", {}).get("name", ""))
	tags_edit.text = ", ".join(record.get("tags", []))
	var editable: bool = record.get("editable", false)
	name_edit.editable = editable
	tags_edit.editable = editable
	save_button.disabled = not editable
static func parse_tags(value: String) -> Array[String]:
	var tags: Array[String] = []
	for part: String in value.split(","):
		var tag: String = part.strip_edges()
		if not tag.is_empty() and not tags.has(tag):
			tags.append(tag)
	return tags
