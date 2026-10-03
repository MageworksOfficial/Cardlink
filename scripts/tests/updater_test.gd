extends "res://scripts/tests/milestone_6b_test.gd"
const Manifest=preload("res://scripts/updater/update_manifest.gd")
const Service=preload("res://scripts/updater/update_service.gd")
var endpoint: String
var base: String
func make_service(path: String,cache: String="") -> Node:
	var service:=Service.new();service.config.update_service_url=endpoint+path;service.allow_loopback_for_tests=true
	service.cache_path=base.path_join(cache if not cache.is_empty() else path.trim_prefix("/")+".json")
	root.add_child(service);return service
func fetch(service: Node,path: String) -> void:
	service.config.update_service_url=endpoint+path;service.check_now()
	await wait_for(func() -> bool: return not service.busy)
func write_json(path: String,data: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func run() -> void:
	base=OS.get_cmdline_user_args()[0];endpoint=OS.get_cmdline_user_args()[1]
	root.size=Vector2i(1152,648);root.content_scale_size=root.size;root.gui_embed_subwindows=true
	var app: Control=load("res://scenes/application_shell.tscn").instantiate()
	app.update_service=Service.new();app.update_service.config.update_service_url=endpoint+"/slow";app.update_service.allow_loopback_for_tests=true;app.update_service.cache_path=base.path_join("app.json")
	root.add_child(app);await process_frame;await process_frame;app.shared_settings.welcome.hide()
	var service: Node=app.update_service
	check(service.busy and app.title_screen.visible and app.updater.button.text.contains("Checking"),"Startup requests manifest while title remains visible")
	app.choose_table(app.Mode.ONLINE)
	app.choose_table(app.Mode.OFFLINE_PLAYTEST)
	check(app.table_selection.visible and service.busy,"Offline selection responds during slow startup check")
	app.table_selection.hide();app.title_screen.show()
	check(await wait_for(func() -> bool: return not service.busy),"Bounded startup HTTP completes")
	check(service.state=="current" and service.manifest.latest_version=="0.8.5.1-beta","Up-to-date manifest classification")
	check(app.pending_table_mode==app.Mode.OFFLINE_PLAYTEST,"Completed update check does not replace a newer offline choice")
	var attempted: float=service.last_attempt
	await create_timer(0.3).timeout
	check(service.last_attempt==attempted and not service.busy,"No constant polling after startup")
	app.updater.check_button.pressed.emit();check(service.busy,"Manual Check Again starts a new request")
	await wait_for(func() -> bool: return not service.busy)
	app.updater.button.pressed.emit();check(app.updater.dialog.visible and not app.updater.update_button.visible,"Click status opens current-version dialog")
	app.updater.dialog.hide()
	check(Manifest.compare("0.8.5.1","0.8.5")>0 and Manifest.compare("0.8.10","0.8.9")>0 and Manifest.compare("0.8.5.1","0.8.6")<0,"Numeric 3/4-part release comparison")
	check(Manifest.compare("0.8.5.1-beta","0.8.5")>0 and Manifest.compare("0.8.5.1-beta","0.8.5.1")<0 and Manifest.version("0.8.5.1-evil").is_empty(),"Beta channel comparison and invalid suffix rejection")
	await fetch(service,"/available")
	check(service.state=="available" and not app.updater.update_button.disabled,"Recommended update shows safe GitHub action")
	check(app.updater.pulse!=null,"Available indicator pulses gently by default")
	app.table_preferences.put("reduce_motion",true)
	check(app.updater.pulse==null and app.updater.button.text.contains("Update Available"),"Reduce Motion uses static text-highlighted status")
	app.table_preferences.put("reduce_motion",false);check(app.updater.pulse!=null,"Re-enabling motion restores gentle pulse")
	check(FileAccess.file_exists(service.cache_path),"Last valid manifest persists atomically")
	var cache: Variant=JSON.parse_string(FileAccess.get_file_as_string(service.cache_path))
	check(cache.has("checked_at") and cache.manifest.has("minimum_online_version") and not cache.manifest.has("server_directory_url") and not cache.manifest.has("private_extra"),"Cache includes policy/time but ignores optional directory and unknown fields")
	check(await service.online_allowed(),"Recommended update does not retire online mode")
	await fetch(service,"/required")
	check(service.state=="required" and not await service.online_allowed(),"Below minimum online version requires update")
	await app.enter_mode(app.Mode.ONLINE)
	check(app.mode==app.Mode.TITLE and app.updater.dialog.visible and app.updater.summary.text.contains("retired"),"Required policy blocks online entry with explanation")
	app.updater.dialog.hide()
	await app.enter_mode(app.Mode.OFFLINE_PLAYTEST)
	app.table_scene.tabletop.shortcuts.toggle_playtest()
	await process_frame
	check(app.mode==app.Mode.OFFLINE_PLAYTEST and app.updater.dialog.visible,"Playtest-to-online shortcut respects retirement policy")
	app.updater.dialog.hide()
	check(app.mode==app.Mode.OFFLINE_PLAYTEST and app.table_scene!=null,"Offline launch remains available under required policy")
	app.dispose_table();app.mode=app.Mode.TITLE;app.title_screen.show()
	service.checked_at-=Service.FRESH_SECONDS+1;service.last_attempt=0
	service.config.update_service_url=endpoint+"/error"
	check(await service.online_allowed(),"Stale required cache refreshes and fails open when service unavailable")
	check(service.state=="unavailable" and not service.fresh(),"Unavailable indicator does not treat stale retirement policy as current")
	service.manifest.clear();service.checked_at=0
	for path: String in ["/bad","/oversized","/redirect","/foreign","/invalid-floor"]:
		await fetch(service,path);check(service.state=="unavailable","Reject unsafe/invalid response: "+path)
	service.allow_loopback_for_tests=false;await fetch(service,"/current")
	check(service.state=="unavailable" and service.detail.contains("HTTPS"),"Production configuration refuses plaintext update endpoint")
	service.allow_loopback_for_tests=true;await fetch(service,"/available")
	var recent: Dictionary={"endpoint":endpoint+"/error","checked_at":service.now(),"manifest":service.manifest.duplicate(true)}
	write_json(base.path_join("recent.json"),recent)
	var cached_service: Node=make_service("/error","recent.json");await process_frame
	await wait_for(func() -> bool: return not cached_service.busy)
	check(cached_service.state=="available" and cached_service.cached,"Unavailable service uses recent valid cached manifest")
	check(await cached_service.online_allowed(),"Cached recommendation keeps online available")
	recent.checked_at-=Service.FRESH_SECONDS+1;recent.manifest.minimum_online_version="0.8.6";recent.manifest.latest_version="0.8.6"
	write_json(base.path_join("stale.json"),recent)
	var stale: Node=make_service("/error","stale.json");await process_frame;await wait_for(func() -> bool: return not stale.busy)
	check(stale.state=="unavailable" and await stale.online_allowed(),"Old cached required policy cannot permanently block online")
	var config=preload("res://scripts/updater/update_config.gd").new()
	check(not config.get_script().source_code.contains("network.cfg") or config.get_script().source_code.count("network.cfg")==1,"Updater configuration contains no gameplay-config dependency")
	# Use an actually failed, independent network connection while updates still work.
	await app.enter_mode(app.Mode.ONLINE)
	var panel: Node=app.table_scene.get_node("Network")
	var saved_endpoint: String=service.config.update_service_url
	panel.rooms.config.set_value("internet","service_url","https://other-gameplay.invalid")
	panel.rooms.config.set_value("internet","relay_host","other-gameplay.invalid")
	panel.rooms.signaling.service_url="https://other-gameplay.invalid"
	check(service.config.update_service_url==saved_endpoint,"Changing gameplay relay configuration leaves update endpoint untouched")
	var net: Node=panel.network
	net.join_game("127.0.0.1",1,"Unavailable gameplay server")
	await fetch(service,"/current")
	check(service.state=="current","Gameplay connection failure does not prevent successful update check")
	check(app.mode==app.Mode.ONLINE,"Update availability does not depend on room or relay state")
	app.table_scene.get_node("Network").network.disconnect_session()
	await fetch(service,"/required")
	var refused: Array=[]
	panel.connect_if_online(func() -> void: refused.append(true))
	await process_frame
	check(refused.is_empty() and app.updater.dialog.visible,"Host/Join action guard enforces required update")
	app.updater.dialog.hide()
	service.manifest.clear();service.checked_at=0;await fetch(service,"/error")
	var executed: Array=[]
	app.table_scene.get_node("Network").connect_if_online(func() -> void: executed.append(true))
	await process_frame
	check(not executed.is_empty(),"Failed update service does not prevent allowed connection action")
	cached_service.queue_free();stale.queue_free();app.dispose_table();app.queue_free();await process_frame
	print("UPDATER: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
