extends "res://scripts/tests/milestone_74_test.gd"
func run() -> void:
    var base: String = OS.get_cmdline_user_args()[0]
    var app: Control = new_app(base)
    await process_frame
    var info = preload("res://scripts/frontend/app_info.gd")
    check(info.LABEL == "CardLink " + info.VERSION + " Beta","Central Beta identity")
    check(info.NETWORK_COMPATIBILITY == "7.7","Wire compatibility unchanged")
    check(info.PROJECT_URL.is_empty(),"No invented project URL")
    var panel: Window = preload("res://scripts/frontend/about_cardlink.gd").open(app)
    await process_frame
    check(panel.visible and panel.title.contains(info.LABEL),"About opens with central version")
    check(panel.feedback.disabled,"Unconfigured feedback safely disabled")
    panel.close_requested.emit()
    await process_frame
    check(not is_instance_valid(panel),"About closes cleanly")
    app.queue_free()
    await process_frame
    print("Beta presentation failures: ", failures)
    quit(1 if failures else 0)
