extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
    var base: String = OS.get_cmdline_user_args()[0]
    root.gui_embed_subwindows = true
    var a: Control = await create_client(base.path_join("a"),"A",Color.BLUE,true)
    var b: Control = await create_client(base.path_join("b"),"B",Color.GREEN,true)
    var ua: Node = a.get_node("Network")
    var ub: Node = b.get_node("Network")
    var ca: Node = a.tabletop.match_controller
    var cb: Node = b.tabletop.match_controller
    ua.preparation.auto_setup = true;ub.preparation.auto_setup = true
    var port: int = randi_range(33000,43000)
    ua.network.host_game(port,"Host","127.0.0.1");ub.network.join_game("127.0.0.1",port,"Guest")
    check(await wait_for(func() -> bool: return ua.preparation.can_start() and ub.preparation.can_start(),15),"Failure fixture decks ready")
    ua.preparation.start_match()
    await wait_for(func() -> bool: return ua.gameplay.enabled and ub.gameplay.enabled)
    var sa: Node = ua.gameplay.card_sync
    var sb: Node = ub.gameplay.card_sync
    var path: String = sa.catalog.asset_path(sa.own[0].hash)
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
    var f := FileAccess.open(path,FileAccess.WRITE);f.store_buffer(PackedByteArray([0]));f.close()
    ua.preparation.start_sync()
    check(await wait_for(func() -> bool: return sa.work.finished and sb.work.finished,20),"Unavailable individual image does not abort batch")
    check(sa.inspect_required().missing==0 and sb.inspect_required().missing==1,"Healthy opposite transfer succeeds despite failed image")
    check(sb.work.percent()<100,"Failed image not counted as verified progress")
    check(ua.gameplay.enabled and ub.gameplay.enabled,"Gameplay remains active after individual failure")
    f=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(bytes);f.close()
    wire.clear()
    ub.preparation.start_sync()
    await wait_for(func() -> bool: return sa.running or sb.running)
    check(await wait_for(func() -> bool: return sa.work.finished and sb.work.finished,20),"Retry completes remaining assets")
    check(sa.reports["1"].images==0 and sb.reports["2"].images==1,"Retry transfers only missing image")
    check(sb.inspect_required().missing==0,"Retry restores missing card")
    wire.clear();ua.preparation.start_sync()
    await wait_for(func() -> bool: return sa.running or sb.running)
    check(await wait_for(func() -> bool: return sa.work.finished and sb.work.finished),"Already-cached exchange finishes")
    check(sa.reports["1"].images==0 and sb.reports["2"].images==0,"Both cached sends zero images")
    # Remove only this isolated test's received asset to create an interrupted download.
    var received: String = sb.catalog.asset_path(sa.own[0].hash)
    DirAccess.remove_absolute(received)
    sa.check_ready();sb.check_ready()
    await settle()
    ua.preparation.start_sync()
    check(await wait_for(func() -> bool: return not sb.incoming_hash.is_empty(),10),"Partial incoming image observed")
    var completed_path: String = sa.catalog.asset_path(sb.own[0].hash)
    ua.network.disconnect_session()
    check(await wait_for(func() -> bool: return ua.network.available() and ub.network.available()),"Interrupted peers disconnect cleanly")
    check(FileAccess.file_exists(completed_path) and not FileAccess.file_exists(received),"Validated assets retained, partial asset not committed")
    check(sb.incoming.is_empty(),"Partial receive buffer discarded")
    ua.gameplay.recovery.reconnect();ub.gameplay.recovery.reconnect()
    check(await wait_for(func() -> bool: return ua.gameplay.enabled and ub.gameplay.enabled and not ua.gameplay.recovery.suspended and not ub.gameplay.recovery.suspended,25),"Gameplay reconnect independent of missing art")
    check(await wait_for(func() -> bool: return sa.work.finished and sb.work.finished and sb.inspect_required().missing==0,25),"Interrupted sync automatically resumes only missing")
    check(sa.reports.get("1",{}).get("images",-1)==0 and sb.reports.get("2",{}).get("images",-1)==1,"Resume does not resend completed opposite image")
    sa.running = true;sa.step = 2;sa.need_received = false
    sa.receive({"session_id":ua.network.session.session_id,"run":sa.run_id,"kind":"need","data":{"step":2,"definitions":[],"images":[sb.own[0].hash]}})
    check(not sa.running and sa.last_failure.contains("outside the loaded deck"),"Sender rejects unrelated cached asset outside its selected deck")
    check(ua.gameplay.enabled and ub.gameplay.enabled,"Rejected asset request does not end public gameplay")
    ua.network.disconnect_session();ub.network.disconnect_session();a.queue_free();b.queue_free()
    await process_frame
    print("BACKGROUND RETRY: %d checks, %d failures" % [checks,failures])
    quit(1 if failures else 0)
