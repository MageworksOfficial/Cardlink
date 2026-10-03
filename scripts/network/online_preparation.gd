extends Node
## Connection/deck setup is independent from optional background asset transfer.
var panel: Node
var auto_setup: bool = true
var active: bool = false
var cancelled: bool = false
var match_ready: bool = false
var role: String = ""
var session: String = ""
var selected: String = ""
var primary: Button
var choose: Button
var progress: Label
var bar: ProgressBar
var cancel_button: Button
var hud: PanelContainer
var hud_text: Label
var hud_bar: ProgressBar
var hud_button: Button
var hud_cancel: Button
var timer: float = 0
var was_syncing: bool = false
var resume_needed: bool = false
var need: Dictionary = {}
var inspection_key: String = ""
func sync() -> Node: return panel.gameplay.card_sync
func connected() -> bool: return panel.network.session.state == "connected"
func _ready() -> void:
    sync().changed.connect(func() -> void:
        if sync().running or sync().requested: was_syncing = true
        inspection_key = "")
func build_ui(parent: Node) -> void:
    primary = panel.button(parent,"SYNC MISSING CARDS",start_sync)
    progress = panel.label(parent,"Choose a deck and connect to play.")
    bar = ProgressBar.new()
    parent.add_child(bar)
    bar.hide()
    cancel_button = panel.button(parent,"Cancel Sync",cancel)
    cancel_button.hide()
    hud = PanelContainer.new()
    panel.get_parent().add_child.call_deferred(hud)
    hud.z_index = 200
    hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    hud.offset_left = -350; hud.offset_right = -16
    hud.offset_top = -175; hud.offset_bottom = -70
    var rows := VBoxContainer.new()
    hud.add_child(rows)
    hud_text = panel.label(rows,"")
    hud_bar = ProgressBar.new()
    rows.add_child(hud_bar)
    var buttons := HBoxContainer.new()
    rows.add_child(buttons)
    hud_button = panel.button(buttons,"SYNC MISSING CARDS",start_sync)
    hud_cancel = panel.button(buttons,"Cancel Sync",cancel)
    hud.hide()
func can_start() -> bool:
    var s: Node = sync()
    return connected() and not panel.gameplay.recovery.suspended and s.pending and s.have_remote and (not s.own.is_empty() and not s.remote.is_empty())
func start_match() -> void:
    if not can_start(): return
    if panel.gameplay.enabled:
        panel.window.hide()
        return
    if panel.gameplay.opted_in: return
    panel.apply_starting_life()
    panel.gameplay.start_public()
    panel.window.hide()
func start_sync() -> void:
    if not auto_setup: sync().decide("sync"); return
    if not can_start() or not sync().checked or sync().running or sync().requested: return
    cancelled = false
    sync().last_failure = ""
    was_syncing = true
    sync().decide("sync")
func retry() -> void: start_sync()
func start() -> void: start_sync()
func placeholders() -> void:
    if auto_setup: start_match()
    else: sync().decide("placeholders")
func cancel() -> void:
    cancelled = true
    resume_needed = false; was_syncing = false
    if sync().pending: sync().cancel_match()
    # Cancels the transfer only. Public gameplay and hidden-zone services keep running.
func _process(delta: float) -> void:
    if not auto_setup or panel.gameplay.table == null or progress == null: return
    var s: Node = sync()
    if not connected():
        if was_syncing: resume_needed = true
        was_syncing = false; match_ready = false
        hud.hide()
        progress.text = "Connection lost. Completed card images are kept."
        return
    if panel.gameplay.recovery.suspended: return
    timer += delta
    if timer < 0.2: return
    timer = 0
    var manifest: Array = panel.gameplay.table.match_controller.model.players.local.deck_manifest
    var fingerprint: String = JSON.stringify(manifest).sha256_text()
    if fingerprint != selected or session != panel.network.session.session_id or not s.pending:
        if s.validation != null: return
        if s.pending: s.cancel_match()
        if fingerprint != selected: s.work.reset(); resume_needed = false
        selected = fingerprint
        session = panel.network.session.session_id
        role = panel.network.session.local_peer.role
        s.background_mode = true
        s.guided_consent_required = false
        s.preparation_authorized = false
        s.begin()
    match_ready = can_start()
    if match_ready and panel.gameplay.remote_ready and not panel.gameplay.opted_in: panel.gameplay.start_public()
    if s.catalog == null: return
    var key: String = str(s.run_id)+str(s.running)+str(s.checked)+str(s.work.finished)+session+selected+s.background_remote_signature
    if key != inspection_key or need.is_empty():
        need = s.inspect_required()
        inspection_key = key
    var peer_missing: int = int(s.remote_availability.get("missing",0))
    if s.running or s.requested:
        was_syncing = true
    elif s.work.finished or not s.last_failure.is_empty(): was_syncing = false
    if resume_needed and match_ready and s.checked:
        resume_needed = false
        start_sync()
    var busy: bool = s.running or s.requested
    var missing: bool = need.missing > 0 or peer_missing > 0
    primary.visible = missing and not busy
    primary.disabled = not match_ready or not s.checked
    primary.text = "Retry Missing" if s.work.finished and missing else "SYNC MISSING CARDS"
    cancel_button.visible = busy
    bar.visible = busy or (s.work.started and missing)
    if s.work.started: bar.value = s.work.percent()
    if busy: progress.text = "Syncing card images... %d%%\n%d / %d items verified. Keep playing." % [int(bar.value),s.work.completed(),s.work.total()]
    elif cancelled and missing: progress.text = "Sync cancelled. %d cards missing locally. You can keep playing." % need.missing
    elif not s.last_failure.is_empty(): progress.text = "Sync paused. Retry Missing when ready. You can keep playing."
    elif not s.checked: progress.text = "Checking remote card definitions and artwork..."
    elif missing: progress.text = "%d cards missing locally (%d definitions, %d images).\nOpponent needs %d cards. Start Match uses placeholders until Card Sync finishes." % [need.missing,need.definitions.size(),need.images.size(),peer_missing]
    else: progress.text = "Cards ready"
    if not match_ready: progress.text = "Choose a deck. Waiting for opponent's deck..."
    hud.visible = panel.gameplay.enabled and (busy or missing) and not panel.window.visible
    hud_text.text = progress.text
    hud_bar.visible = bar.visible; hud_bar.value = bar.value
    hud_button.visible = primary.visible; hud_button.disabled = primary.disabled; hud_button.text = primary.text
    hud_cancel.visible = busy
    panel.refresh_sync_buttons()
func _exit_tree() -> void:
    if is_instance_valid(hud): hud.queue_free()
