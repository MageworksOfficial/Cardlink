extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
    var base: String = OS.get_cmdline_user_args()[0]
    root.gui_embed_subwindows = true
    var a: Control = await create_client(base.path_join("a"),"Host art",Color.BLUE)
    var b: Control = await create_client(base.path_join("b"),"Guest art",Color.GREEN)
    var ua: Node = a.get_node("Network")
    var ub: Node = b.get_node("Network")
    ua.preparation.auto_setup = true;ub.preparation.auto_setup = true
    var port: int = randi_range(33000,43000)
    ua.network.host_game(port,"Host","127.0.0.1");ub.network.join_game("127.0.0.1",port,"Guest")
    check(await wait_for(func() -> bool: return ua.preparation.can_start() and ub.preparation.can_start(),12),"Deck setup completes automatically")
    check(ua.gameplay.card_sync.inspect_required().missing>0 and ub.gameplay.card_sync.inspect_required().missing>0,"Both peers have missing deck assets")
    check(not ua.start_match_button.disabled and not ub.start_match_button.disabled,"Missing artwork does not gate Start")
    ua.start_match_button.pressed.emit()
    check(await wait_for(func() -> bool: return ua.gameplay.enabled and ub.gameplay.enabled),"One Start opens the shared table without transfers")
    var ca: Node = a.tabletop.match_controller
    var cb: Node = b.tabletop.match_controller
    ca.draw_card()
    var card: Control = ca.card_by_id(ca.model.players.local.hand[0])
    ca.move_card(card,"battlefield")
    check(await wait_for(func() -> bool: return cb.card_by_id(card.state.match_instance_id)!=null),"Unsynced card can be played")
    var remote: Control = cb.card_by_id(card.state.match_instance_id)
    check(remote.card_image.texture == null,"Unsynced card uses placeholder")
    remote.position.x += 60;remote.set_tapped(true)
    remote.state.counters = {"charge":3};remote.update_counters()
    await settle()
    var position: Vector2 = remote.position
    var id: String = remote.state.match_instance_id
    ca.draw_card(); ca.draw_card()
    var revealed: Control = ca.card_by_id(ca.model.players.local.hand[0])
    ca.toggle_hand_reveal(revealed)
    ca.draw_card()
    var known_top: Control = ca.card_by_id(ca.model.players.local.hand[-1])
    ca.visibility.set_public_reveal(known_top.state,true)
    ca.move_card(known_top,"library",true,"local")
    await settle()
    wire.clear()
    ub.preparation.start_sync()
    check(await wait_for(func() -> bool: return ua.gameplay.card_sync.running or ub.gameplay.card_sync.running),"Either peer initiates without any permission dialog")
    ca.change_life("local",-3);cb.draw_card();a.tabletop.create_token("Token","local","local","","1","1")
    var previous: float = 0
    var monotonic: bool = true
    var end: int = Time.get_ticks_msec()+15000
    while Time.get_ticks_msec()<end and not (ua.gameplay.card_sync.work.finished and ub.gameplay.card_sync.work.finished):
        var value: float = ub.gameplay.card_sync.work.percent()
        if value < previous: monotonic = false
        previous = value
        await process_frame
    check(ua.gameplay.card_sync.work.finished and ub.gameplay.card_sync.work.finished,"Background transfer finishes in both directions")
    if not ua.gameplay.card_sync.work.finished:print(ua.gameplay.card_sync.status," | ",ub.gameplay.card_sync.status)
    check(monotonic and ub.gameplay.card_sync.work.percent()==100,"Real verified-work progress is monotonic to 100%")
    check(await wait_for(func() -> bool: return remote.card_image.texture != null),"Placeholder gains art without reload")
    check(remote.state.match_instance_id==id and remote.position.distance_to(position)<0.1 and remote.state.tapped and remote.state.counters.get("charge")==3,"Live replacement preserves instance, position, tap and counters")
    check(cb.model.players.opponent.life==37 and cb.model.players.local.hand.size()==1,"Life and drawing continue during transfer")
    check(ua.gameplay.card_sync.inspect_required().missing==0 and ub.gameplay.card_sync.inspect_required().missing==0,"Only required missing cards are resolved")
    var hand_view: Dictionary = ub.gameplay.serializer.projection.remote_hand()
    check(hand_view.faces.size()==2 and hand_view.faces[0]!=null and hand_view.faces[1]==null,"Revealed hand gains art while hidden sibling stays private")
    check(cb.opponent_pile.back_image.texture!=b.tabletop.backs.texture(),"Known library top gains art without replaying state")
    if failures:
        print("HOST ",ua.gameplay.card_sync.status," ",ua.gameplay.card_sync.inspect_required()," ",ua.gameplay.card_sync.events)
        print("GUEST ",ub.gameplay.card_sync.status," ",ub.gameplay.card_sync.inspect_required()," ",ub.gameplay.card_sync.events)
        print("REMOTE ",ub.gameplay.state.cards.get(id,{})," image ",remote.state.image_path)
    check(not JSON.stringify(wire).contains(ca.pile.order[0]),"No hidden library instance/order in transfer")
    ua.network.disconnect_session();ub.network.disconnect_session();a.queue_free();b.queue_free()
    await process_frame
    print("BACKGROUND BASIC: %d checks, %d failures" % [checks,failures])
    quit(1 if failures else 0)
