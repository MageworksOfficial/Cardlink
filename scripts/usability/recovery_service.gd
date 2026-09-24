extends Node
## Dedicated atomic local recovery record. Never overwrites a named match.
var shell: Control
var storage = preload("res://scripts/match_save_storage.gd").new("user://recovery")
var saved_path: String = ""
var preserve_failed: bool = false
var source_mode: String = ""
var timer: Timer
var debounce: Timer
var prompt: ConfirmationDialog
func _ready() -> void:
	timer = Timer.new()
	timer.wait_time = 45
	timer.timeout.connect(save_recovery)
	add_child(timer)
	timer.start()
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 2
	debounce.timeout.connect(save_recovery)
	add_child(debounce)
	prompt = ConfirmationDialog.new()
	prompt.title = "Recover previous match?"
	prompt.dialog_text = "CardLink found a recovery copy. Open it offline? Named saves are unchanged; online peers will not reconnect automatically."
	prompt.ok_button_text = "Recover"
	prompt.cancel_button_text = "Discard"
	prompt.confirmed.connect(recover)
	prompt.canceled.connect(discard)
	add_child(prompt)
func inspect() -> void:
	var records: Array = storage.list_records()
	if records.is_empty(): return
	saved_path = records[0].path
	prompt.popup_centered(Vector2i(560,180))
func schedule() -> void:
	if debounce.is_stopped(): debounce.start()
func attach() -> void:
	shell.table_scene.tabletop.undo.committed.connect(schedule)
	schedule()
func save_recovery() -> void:
	if preserve_failed or shell.table_scene == null or shell.entering: return
	var c: Node = shell.table_scene.tabletop.match_controller
	# Never capture an in-flight transfer, temporary inspection, or dragging card.
	if c.contents.visible or c.review.visible: schedule(); return
	if c.public_sync != null and c.public_sync.transactions.has_unfinished(): schedule(); return
	for card: Control in shell.table_scene.tabletop.cards:
		if card.dragging: schedule(); return
	var snapshot: Dictionary = shell.table_scene.tabletop.persistence.capture_match()
	if not preload("res://scripts/match_snapshot.gd").validate(snapshot).is_empty(): return
	snapshot["recovery_metadata"] = {"source_opponent_mode":source_mode if not source_mode.is_empty() else snapshot.local_tabletop.get("opponent_mode","online")}
	var result: Dictionary = storage.save_record(snapshot,"Recovery",saved_path)
	if not result.has("error"): saved_path = result.path
func discard() -> void:
	debounce.stop()
	for row: Dictionary in storage.list_records(): storage.delete_record(row.path)
	saved_path = ""
	preserve_failed = false
	source_mode = ""
	prompt.hide()
func recover() -> void:
	var read: Dictionary = storage.read_record(saved_path)
	if read.has("error") or not preload("res://scripts/match_snapshot.gd").validate(read.get("record",{}).get("data",{})).is_empty():
		prompt.dialog_text = "The recovery copy could not be read. Your named saves are unchanged. Choose Discard to continue."
		prompt.popup_centered()
		return
	shell.shared_settings.welcome.hide()
	source_mode = str(read.record.data.get("recovery_metadata",{}).get("source_opponent_mode",read.record.data.get("local_tabletop",{}).get("opponent_mode","online")))
	shell.entry.recovery_data = read.record.data.duplicate(true)
	shell.entry.start(shell.Mode.OFFLINE_PLAYTEST)
