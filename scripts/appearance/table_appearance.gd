extends Node
const Config=preload("res://scripts/appearance/background_config.gd")
var manager: Node
var background: Dictionary=Config.defaults()
var assets=preload("res://scripts/custom_table/table_assets.gd").new()
var layer: Control
var editor: Window
var sleeves: Node
var sync: Node
var editing: bool=false
var gesture: String=""
var start: Vector2
var before: Dictionary={}
var resize_corner: Vector2
func _ready() -> void:
	layer=preload("res://scripts/appearance/background_layer.gd").new();layer.appearance=self;manager.world.add_child(layer);manager.world.move_child(layer,0)
	editor=preload("res://scripts/appearance/background_editor.gd").new();editor.appearance=self;add_child(editor)
	sleeves=preload("res://scripts/appearance/match_sleeves.gd").new();sleeves.appearance=self;add_child(sleeves)
	sync=preload("res://scripts/appearance/appearance_sync.gd").new();sync.appearance=self;add_child(sync)
	refresh()
func tell(message: String) -> void: manager.controls.status.text=message
func apply(value: Dictionary, broadcast: bool=true) -> bool:
	if not Config.valid(value): return false
	background=value.duplicate(true);refresh()
	if manager.custom_table!=null and manager.custom_table.enabled: manager.custom_table.document["background"]=background.duplicate(true)
	if broadcast and sync!=null: sync.publish()
	return true
func refresh() -> void:
	layer.position=Vector2(background.position[0],background.position[1]);layer.size=Vector2(background.size[0],background.size[1]);layer.rotation=deg_to_rad(background.rotation);layer.modulate=Color.WHITE;layer.queue_redraw()
func open() -> void:
	manager.controls.close_panels();editor.open()
func toggle_edit() -> void:
	if not manager.layout.edit_mode:
		tell("Enable Layout Mode to edit the battlefield background.");return
	editing=not editing;gesture="";refresh();tell("Background Edit: ON" if editing else "Background Edit: OFF")
func reset_background() -> void:
	apply(Config.defaults());tell("Background reset.")
func fit(fill: bool=false) -> void:
	if background.locked: tell("Unlock background first.");return
	var texture: Texture2D=assets.texture(background.asset)
	var base: Vector2=texture.get_size() if texture!=null else manager.world.size
	var ratios: Vector2=manager.world.size/base
	var size: Vector2=base*(maxf(ratios.x,ratios.y) if fill else minf(ratios.x,ratios.y))
	var next: Dictionary=background.duplicate(true);next.size=[size.x,size.y];next.position=[(manager.world.size.x-size.x)/2,(manager.world.size.y-size.y)/2];next.rotation=0.0
	apply(next)
func reset_transform() -> void:
	if background.locked: tell("Unlock background first.");return
	var next: Dictionary=background.duplicate(true);next.position=[0,0];next.size=[manager.world.size.x,manager.world.size.y];next.rotation=0.0;next.opacity=1.0;apply(next)
func _process(_delta: float) -> void:
	if has_meta("edit_toggle"):
		var toggle: CheckButton=get_meta("edit_toggle");toggle.set_pressed_no_signal(editing);toggle.text="Background Edit: "+("ON" if editing else "OFF")+" [Ctrl+B]"
	if editing and (not manager.active or not manager.layout.edit_mode):
		editing=false;gesture="";refresh()
func input(event: InputEvent) -> bool:
	if not editing or not manager.layout.edit_mode or background.locked: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var local: Vector2=layer.get_transform().affine_inverse()*event.position
			if not Rect2(Vector2.ZERO,layer.size).grow(14/manager.view.zoom).has_point(local): return false
			gesture="move";before=background.duplicate(true);start=event.position
			for corner: Vector2 in [Vector2.ZERO,Vector2(layer.size.x,0),layer.size,Vector2(0,layer.size.y)]:
				if local.distance_to(corner)<18/manager.view.zoom: gesture="resize";resize_corner=corner;break
		else:
			if gesture.is_empty(): return false
			gesture="";apply(background);editor.refresh_fields()
		return true
	if event is InputEventMouseMotion and not gesture.is_empty():
		if gesture=="move": background.position=[before.position[0]+event.position.x-start.x,before.position[1]+event.position.y-start.y]
		else:
			var delta: Vector2=(event.position-start).rotated(-deg_to_rad(background.rotation))
			var old:=Vector2(before.size[0],before.size[1])
			var sign_x: float=1.0 if resize_corner.x>0 else -1.0
			var factor: float=clampf((old.x+delta.x*sign_x)/old.x,40.0/minf(old.x,old.y),20000.0/maxf(old.x,old.y))
			var size: Vector2=old*factor
			var offset:=Vector2(old.x-size.x if resize_corner.x==0 else 0,old.y-size.y if resize_corner.y==0 else 0).rotated(deg_to_rad(background.rotation))
			background.size=[size.x,size.y];background.position=[before.position[0]+offset.x,before.position[1]+offset.y]
		refresh();return true
	return false
