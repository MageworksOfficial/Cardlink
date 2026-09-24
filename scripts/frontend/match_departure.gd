extends Node
## Detect meaningful match changes, excluding camera and hand-window presentation.
var shell: Control
var baseline: String = ""
var path: String = ""
var caption: String = "My Match"
var content: VBoxContainer
var explanation: Label
var save_name: LineEdit
var action: String = "return"
func fingerprint() -> String:
	if shell.table_scene == null: return ""
	var data: Dictionary = shell.table_scene.tabletop.persistence.capture_match()
	data.erase("layout")
	data.erase("match_id")
	for key: String in ["hand_detached","hand_position","hand_player"]: data.local_tabletop.erase(key)
	for player: Dictionary in data.players: player.erase("display_name")
	return JSON.stringify(data)
func mark_saved(saved_path: String = "") -> void:
	baseline = fingerprint()
	if not saved_path.is_empty():
		path = saved_path
		var read: Dictionary = shell.entry.saves.read_record(path)
		caption = str(read.get("record",{}).get("name","My Match"))
func dirty() -> bool: return baseline != fingerprint()
func request(next: String) -> void:
	action = next
	if not dirty(): finish(); return
	var dialog: ConfirmationDialog = shell.return_dialog if action == "return" else shell.exit_dialog
	content.reparent(dialog)
	explanation.text = "Keep your progress before leaving?\nMatch name"
	save_name.text = caption
	dialog.popup_centered(Vector2i(560,210))
func save_and_finish() -> void:
	var result: Dictionary = shell.table_scene.tabletop.persistence.save_match(save_name.text,path)
	if result.has("error"):
		var dialog: ConfirmationDialog = shell.return_dialog if action == "return" else shell.exit_dialog
		explanation.text = "Could not save. Your match is still open.\nChoose a name and try again."
		dialog.popup_centered(Vector2i(560,210))
		return
	mark_saved(str(result.path))
	finish()
func finish() -> void:
	shell.return_dialog.hide()
	shell.exit_dialog.hide()
	if action == "return": shell.return_to_title()
	else: shell.exit_now()
func build() -> void:
	for dialog: ConfirmationDialog in [shell.return_dialog,shell.exit_dialog]:
		dialog.title = "Save your match?"
		dialog.dialog_text = ""
		dialog.ok_button_text = "Save & Return" if dialog == shell.return_dialog else "Save & Exit"
		dialog.confirmed.connect(save_and_finish)
		dialog.add_button("Return Without Saving" if dialog == shell.return_dialog else "Exit Without Saving",true,"discard")
		dialog.custom_action.connect(func(_id: StringName) -> void: finish())
	content = VBoxContainer.new()
	shell.return_dialog.add_child(content)
	explanation = Label.new()
	explanation.text = "Keep your progress before leaving?\nMatch name"
	content.add_child(explanation)
	save_name = LineEdit.new()
	save_name.placeholder_text = "Match name"
	save_name.max_length = 100
	content.add_child(save_name)
