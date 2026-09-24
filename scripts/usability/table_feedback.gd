extends Node
var manager: Node
var selected: Label
var elapsed: float = 0
var last_message: String = ""
func _ready() -> void:
	selected = Label.new()
	selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected.position = Vector2(12,122)
	selected.z_index = 200
	manager.get_parent().add_child(selected)
func _process(_delta: float) -> void:
	selected.visible = manager.active
	selected.text = "%d selected" % manager.selection.ids.size() if manager.selection.ids.size()>1 else ""
