extends "res://scripts/tests/milestone_6b_test.gd"
func run() -> void:
    var base: String = OS.get_cmdline_user_args()[0]
    root.gui_embed_subwindows = true
    var a: Control = await create_client(base.path_join("a"),"A",Color.BLUE)
    var b: Control = await create_client(base.path_join("b"),"B",Color.GREEN)
    var ca: Node = a.tabletop.match_controller
    var cb: Node = b.tabletop.match_controller
    var store = preload("res://scripts/card_storage.gd").new(base.path_join("a"))
    var deck: Dictionary = preload("res://scripts/deck_storage.gd").new_deck()
    deck.cards = []
    for i: int in 105:
        var im := Image.create(750,1050,false,Image.FORMAT_RGBA8)
        im.fill(Color.from_hsv(float(i)/106.0,0.8,0.8))
        var noise := Image.create_from_data(750,24,false,Image.FORMAT_RGBA8,Crypto.new().generate_random_bytes(750*24*4))
        im.blit_rect(noise,Rect2i(0,0,750,24),Vector2i.ZERO)
        var row: Dictionary = store.save_card(im.save_png_to_buffer(),"Generic "+str(i),im.get_size())
        deck.cards.append({"card_id":row.metadata.card_id,"quantity":2})
    ca.load_deck(deck,false)
    var ua: Node = a.get_node("Network")
    var ub: Node = b.get_node("Network")
    ua.preparation.auto_setup = true; ub.preparation.auto_setup = true
    var port: int = randi_range(33000,43000)
    ua.network.host_game(port,"Host","127.0.0.1");ub.network.join_game("127.0.0.1",port,"Guest")
    check(await wait_for(func() -> bool: return ua.preparation.can_start() and ub.preparation.can_start(),15),"Large decks ready without art")
    ua.preparation.start_match()
    check(await wait_for(func() -> bool: return ua.gameplay.enabled and ub.gameplay.enabled),"Large match starts immediately")
    ca.draw_card(); cb.draw_card()
    var card: Control = ca.card_by_id(ca.model.players.local.hand[0])
    var guest_card: Control = cb.card_by_id(cb.model.players.local.hand[0])
    ca.move_card(card,"battlefield");cb.move_card(guest_card,"battlefield")
    await settle()
    ua.preparation.start_sync()
    await wait_for(func() -> bool: return ua.gameplay.card_sync.running)
    var start: int = Time.get_ticks_msec()
    var last: int = start
    var worst: int = 0
    var tick: int = 0
    var prev: float = 0
    var monotonic: bool = true
    while Time.get_ticks_msec()-start<90000 and not ub.gameplay.card_sync.work.finished:
        var now: int = Time.get_ticks_msec()
        worst = maxi(worst,now-last);last=now
        var percent: float = ub.gameplay.card_sync.work.percent()
        monotonic = monotonic and percent>=prev;prev=percent
        if tick % 20 == 0:
            card.position.x += 1;guest_card.position.x += 1
            card.set_tapped(not card.tapped);guest_card.set_tapped(not guest_card.tapped)
            ca.change_life("local",1);cb.change_life("local",1)
        if tick == 40:
            ca.draw_card();cb.draw_card()
            a.tabletop.create_token("During sync","local","local","","1","1")
        tick+=1
        await process_frame
    check(ub.gameplay.card_sync.work.finished,"105 unique images complete during gameplay")
    check(ub.gameplay.card_sync.inspect_required().missing==0,"All 105 definitions present")
    check(ub.gameplay.card_sync.reports.get("2",{}).get("images",0)==105,"Quantities deduplicated to 105 image transfers")
    check(monotonic and ub.gameplay.card_sync.work.percent()==100,"Large progress monotonic and complete")
    check(worst<1000,"No one-second frame stall during large transfer")
    await settle()
    check(cb.model.players.opponent.life==ca.model.players.local.life and ca.model.players.opponent.life==cb.model.players.local.life,"Both players' life updates arrive during sync")
    check(ca.model.players.local.hand.size()==1 and cb.model.players.local.hand.size()==1,"Both draw during sync")
    check(cb.card_by_id(card.state.match_instance_id).card_image.texture!=null,"Large transfer replaces played placeholder")
    print("PERFORMANCE ms=",Time.get_ticks_msec()-start," max_frame_ms=",worst," gameplay_updates=",tick/20)
    ua.network.disconnect_session();ub.network.disconnect_session();a.queue_free();b.queue_free()
    await process_frame
    print("BACKGROUND LARGE: %d checks, %d failures" % [checks,failures])
    quit(1 if failures else 0)
