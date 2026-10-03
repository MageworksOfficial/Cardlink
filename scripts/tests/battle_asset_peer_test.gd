extends "res://scripts/tests/milestone_6b_test.gd"
const Back = preload("res://scripts/battle/deck_back.gd")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var host: bool=args[1]=="host"
	var app: Control=await create_client(args[0].path_join("cards"),"Private fixture",Color.SEA_GREEN)
	var m: Node=app.tabletop;var c: Node=m.match_controller
	var n: Node=app.get_node("Network").network;var r: Node=app.get_node("Network").gameplay
	var deck: Dictionary=m.battle.reset.start.sources[0].deck.duplicate(true)
	var hash_value: String=""
	if host:
		var image := Image.create(500,700,false,Image.FORMAT_RGBA8);image.fill(Color.CORAL)
		var noise := Image.create_from_data(500,100,false,Image.FORMAT_RGBA8,Crypto.new().generate_random_bytes(500*100*4));image.blit_rect(noise,Rect2i(0,0,500,100),Vector2i.ZERO)
		hash_value=Back.store(image.save_png_to_buffer()).hash
		deck["deck_back"]={"type":"image","color":"#dc8844","preset":"","asset":hash_value};c.load_deck(deck,false)
		n.host_game(int(args[2]),"Image Host","127.0.0.1")
	else:
		await create_timer(1).timeout;n.join_game("127.0.0.1",int(args[2]),"Image Guest")
	check(await wait_for(func() -> bool: return n.session.state=="connected",10),"independent profile connected")
	r.start_public();check(await wait_for(func() -> bool: return r.enabled,10),"independent profile shared")
	if host:
		check(await wait_for(func() -> bool: return n.session.remote_peer.display_name=="Back received",20),"remote verified transferred back")
	else:
		check(await wait_for(func() -> bool: return not m.deck_backs.remote.library.get("asset","").is_empty(),10),"custom back descriptor arrived")
		hash_value=m.deck_backs.remote.library.get("asset","")
		check(await wait_for(func() -> bool: return FileAccess.file_exists(Back.path(hash_value)),15),"missing custom image transferred")
		check(FileAccess.get_sha256(Back.path(hash_value))==hash_value,"received PNG hash verified")
		check(Image.load_from_file(Back.path(hash_value)).get_size()==Vector2i(500,700),"received image dimensions bounded")
		check(not JSON.stringify(wire).contains("Private fixture"),"cosmetic transfer exposes no private card names")
		m.battle.nickname("Back received");await create_timer(1).timeout
	n.disconnect_session();await settle();app.queue_free();await settle();print("BATTLE ASSET FAILURES ",failures);quit(0 if failures==0 else 1)
