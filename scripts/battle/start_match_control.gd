extends Button
## Presentation only: uses the existing OnlinePreparation start authority.
var manager: Node
var elapsed: float = 0.0
var gold: bool = false
var pulsing: bool = false
static func presentation(local_ready: bool, remote_ready: bool, active: bool, starting: bool) -> Dictionary:
	if active: return {"text":"MATCH ACTIVE","ready":false,"hint":"Match active. Use Reset Match for a bilateral rematch."}
	if starting: return {"text":"STARTING…","ready":false,"hint":"Waiting for the shared match to initialize."}
	var hint: String = "Both players must load a deck."
	if local_ready and not remote_ready: hint="Waiting for opponent deck."
	elif remote_ready and not local_ready: hint="Load your deck to continue."
	elif local_ready and remote_ready: hint="Start the shared match."
	return {"text":"START MATCH","ready":local_ready and remote_ready,"hint":hint}
func _ready() -> void:
	focus_mode=Control.FOCUS_NONE;custom_minimum_size=Vector2(132,36)
	pressed.connect(start)
func start() -> void:
	var panel: Node=manager.get_parent().get_node_or_null("Network")
	if panel!=null: panel.preparation.start_match()
func _process(delta: float) -> void:
	visible=not manager.match_controller.playtest.local_playtest()
	var panel: Node=manager.get_parent().get_node_or_null("Network")
	var row: Dictionary=presentation(false,false,false,false)
	if panel!=null and panel.gameplay!=null:
		var r: Node=panel.gameplay
		var connected: bool=panel.network.session.state=="connected" and not r.recovery.suspended
		row=presentation(connected and not r.card_sync.own.is_empty(),connected and r.card_sync.have_remote and not r.card_sync.remote.is_empty(),r.enabled or (r.recovery.suspended and not r.recovery.context.is_empty()),r.opted_in and not r.enabled)
		if panel.network.quiesced or not manager.battle.reset.phase.is_empty(): row.ready=false
		if not connected and row.text!="MATCH ACTIVE": row.hint="Connect and load both decks to continue.";row.ready=false
	text=row.text;tooltip_text=row.hint;disabled=not row.ready;gold=row.ready
	var reduced: bool=bool(manager.table_preferences.value("reduce_motion",false))
	pulsing=gold and not reduced;elapsed+=delta
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("9e731c") if gold else Color("223544")
	style.border_color=Color("ffdb75") if gold else Color("557080")
	style.set_border_width_all(2);style.set_corner_radius_all(5)
	style.shadow_color=Color(1.0,0.75,0.2,0.12+0.09*(sin(elapsed*2.0)+1.0)) if pulsing else Color(0,0,0,0)
	style.shadow_size=5 if pulsing else 0
	add_theme_stylebox_override("normal",style);add_theme_stylebox_override("hover",style);add_theme_stylebox_override("disabled",style)
