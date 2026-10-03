extends Node
## UI adapter for version status only; no gameplay-server health indicators.
var shell: Control
var service: Node
var button: Button
var dialog: Window
var summary: Label
var update_button: Button
var notes_button: Button
var check_button: Button
var close_button: Button
var pulse: Tween
var last_highlight: String = ""
const LABELS = {"checking":"● Checking for updates…","current":"● Up to Date","available":"! Update Available","required":"! Update Required","unavailable":"? Update Status Unavailable"}
func _ready() -> void:
	button=Button.new();button.name="VersionUpdateStatus";button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size=Vector2(320,58);button.add_theme_font_size_override("font_size",14)
	var style:=StyleBoxFlat.new();style.bg_color=Color("12293dee");style.border_color=Color("74bdda");style.set_border_width_all(1);style.set_corner_radius_all(8)
	for side: String in ["left","right","top","bottom"]: style.set("content_margin_"+side,10)
	button.add_theme_stylebox_override("normal",style)
	shell.title_screen.add_child(button);button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left=-336;button.offset_right=-16;button.offset_top=-78;button.offset_bottom=-16
	button.pressed.connect(open)
	dialog=Window.new();dialog.title="CARDLINK UPDATE";dialog.visible=false;dialog.exclusive=true
	dialog.close_requested.connect(dialog.hide);add_child(dialog)
	dialog.window_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"): dialog.hide())
	var rows:=VBoxContainer.new();dialog.add_child(rows);rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left=18;rows.offset_right=-18;rows.offset_top=18;rows.offset_bottom=-18;rows.add_theme_constant_override("separation",10)
	var scroll:=ScrollContainer.new();rows.add_child(scroll);scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	summary=Label.new();summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL;summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;scroll.add_child(summary)
	update_button=make_button(rows,"UPDATE NOW",download)
	notes_button=make_button(rows,"RELEASE NOTES",notes)
	check_button=make_button(rows,"CHECK AGAIN",service.check_now)
	close_button=make_button(rows,"CLOSE",dialog.hide)
	service.changed.connect(refresh);shell.table_preferences.changed.connect(refresh);refresh()
func make_button(parent: Node,caption: String,action: Callable) -> Button:
	var item:=Button.new();item.text=caption;item.pressed.connect(action);parent.add_child(item);return item
func refresh() -> void:
	button.text=preload("res://scripts/frontend/app_info.gd").LABEL+"\n"+LABELS[service.state]
	button.tooltip_text="Check for Updates · "+service.detail
	var highlight: String=service.state+str(shell.table_preferences.value("reduce_motion",false))
	if highlight!=last_highlight:
		last_highlight=highlight
		if pulse!=null: pulse.kill();pulse=null
		button.modulate=Color.WHITE
		if service.state in ["available","required"]:
			button.add_theme_color_override("font_color",Color("ffe0a3"))
			if not bool(shell.table_preferences.value("reduce_motion",false)):
				pulse=create_tween().set_loops()
				pulse.tween_property(button,"modulate",Color(1,0.88,0.7),1.6)
				pulse.tween_property(button,"modulate",Color.WHITE,1.6)
		else: button.add_theme_color_override("font_color",Color("e4f3fc"))
	var latest: String=service.manifest.get("latest_version","Unknown")
	summary.text="Installed: V"+service.installed_version+"\nLatest: "+("V"+latest if latest!="Unknown" else latest)+"\nStatus: "+LABELS[service.state]+"\n\n"
	if service.state=="required": summary.text+="This version has retired from online service.\nUpdate CardLink to continue playing online.\nOffline Mode remains available.\n\n"
	elif service.state=="current": summary.text+="You're running the latest version or a newer local build.\n\n"
	elif service.state=="available": summary.text+=str(service.manifest.get("update_level","recommended")).capitalize()+" Update\n\n"
	summary.text+=service.detail
	if service.cached: summary.text+="\nLast valid check: "+Time.get_datetime_string_from_unix_time(int(service.checked_at),true)+" UTC."
	var asset: Dictionary=service.asset()
	update_button.visible=service.state in ["available","required"]
	update_button.disabled=asset.is_empty() or not service.fresh()
	if update_button.visible:
		if asset.is_empty(): summary.text+="\nNo package for this platform has been announced. Check releases later."
		else: summary.text+="\nDownload: %.1f MB\nOpens GitHub in your browser; download/install manually." % (float(asset.size)/1048576)
	update_button.tooltip_text="Expected SHA-256: "+str(asset.get("sha256",""))
	check_button.disabled=service.busy
	check_button.visible=service.state not in ["available","required"]
	notes_button.text="RELEASE NOTES" if service.state in ["available","required"] else "VIEW RELEASES"
	notes_button.disabled=service.config.releases_url().is_empty()
	close_button.text="LATER" if service.state in ["available","required"] else "CLOSE"
func open() -> void:
	refresh();dialog.popup_centered_clamped(Vector2i(520,440),0.9)
func download() -> void:
	if not service.fresh() or service.state not in ["available","required"]: return
	var asset: Dictionary=service.asset()
	if not asset.is_empty(): OS.shell_open(asset.url)
func notes() -> void:
	var url: String=service.manifest.get("release_url",service.config.releases_url()) if service.state in ["available","required"] else service.config.releases_url()
	if not url.is_empty(): OS.shell_open(url)
func allow_online() -> bool:
	var allowed: bool=await service.online_allowed()
	if not allowed: open()
	return allowed
