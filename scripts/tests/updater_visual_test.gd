extends SceneTree
var base: String
func _initialize() -> void: run.call_deferred()
func shot(name_text: String) -> void:
	for i: int in 8: await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(base.path_join(name_text+".png"))
func run() -> void:
	base=OS.get_cmdline_user_args()[0];root.gui_embed_subwindows=true;root.size=Vector2i(1152,648);root.content_scale_size=root.size
	var app: Control=load("res://scenes/application_shell.tscn").instantiate();root.add_child(app)
	for i: int in 8: await process_frame
	app.shared_settings.welcome.hide();app.update_service.request.cancel_request()
	var fixture: Dictionary={"latest_version":"0.8.5.1-beta","minimum_online_version":"0.0.0","update_level":"recommended","release_url":"https://github.com/MageworksOfficial/Cardlink/releases/tag/test-only","assets":{"windows-x86_64":{"url":"https://github.com/MageworksOfficial/Cardlink/releases/download/test-only/fixture.zip","sha256":"a".repeat(64),"size":75000000}}}
	app.update_service.receive(0,200,PackedStringArray(),JSON.stringify(fixture).to_utf8_buffer());await shot("01-current")
	fixture.latest_version="0.8.6";app.update_service.receive(0,200,PackedStringArray(),JSON.stringify(fixture).to_utf8_buffer());await shot("02-available")
	app.updater.open();await shot("03-update-dialog");app.updater.dialog.hide()
	app.table_preferences.put("reduce_motion",true);await shot("04-reduce-motion")
	fixture.minimum_online_version="0.8.6";app.update_service.receive(0,200,PackedStringArray(),JSON.stringify(fixture).to_utf8_buffer());app.updater.open();await shot("05-required-dialog");app.updater.dialog.hide()
	for extent: Vector2i in [Vector2i(960,540),Vector2i(1920,1080)]:
		root.size=extent;root.content_scale_size=extent;await shot("06-required-"+str(extent.x))
		app.updater.open();await shot("07-dialog-"+str(extent.x));app.updater.dialog.hide()
	app.update_service.checked_at=0;app.update_service.failed("Update status unavailable.");await shot("08-unavailable")
	app.queue_free();await process_frame;quit()
