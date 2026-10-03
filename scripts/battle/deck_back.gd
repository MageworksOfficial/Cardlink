extends RefCounted
const PRESETS = {"Black":"#151820","White":"#e6e6e2","Gray":"#777c83","Red":"#ae343d","Orange":"#d97526","Yellow":"#dfc549","Green":"#287849","Blue":"#2468b4","Purple":"#7645ac","Brown":"#79503a"}
const DIRECTORY = "user://deck_backs"
const MAX_BYTES = 2*1024*1024
static var textures: Dictionary = {}
static func defaults() -> Dictionary: return {"type":"default","color":"#2468b4","preset":"","asset":""}
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=4: return false
	for key: String in ["type","color","preset","asset"]:
		if not value.get(key) is String: return false
	if not value.type in ["default","preset","color","image"] or value.color.length()!=7 or not value.color.begins_with("#") or not value.color.substr(1).is_valid_hex_number(false): return false
	if value.type=="preset" and not PRESETS.has(value.preset): return false
	if value.preset.length()>16: return false
	return value.asset.is_empty() or (value.type=="image" and value.asset.length()==64 and value.asset==value.asset.to_lower() and value.asset.is_valid_hex_number(false))
static func path(hash_value: String) -> String:
	return DIRECTORY.path_join(hash_value+".png") if hash_value.length()==64 and hash_value.is_valid_hex_number(false) else ""
static func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
static func store(bytes: PackedByteArray, expected: String = "") -> Dictionary:
	if bytes.is_empty() or bytes.size()>MAX_BYTES: return {"error":"Card back exceeds 2 MB."}
	var hash_value: String=digest(bytes)
	if not expected.is_empty() and hash_value!=expected: return {"error":"Card-back hash mismatch."}
	# Check PNG dimensions before allocating an image from an untrusted buffer.
	if bytes.size()<24 or bytes.slice(0,8).hex_encode()!="89504e470d0a1a0a": return {"error":"Invalid card-back PNG."}
	var width: int=0;var height: int=0
	for i: int in range(16,20): width=(width<<8)+bytes[i]
	for i: int in range(20,24): height=(height<<8)+bytes[i]
	if width!=500 or height!=700: return {"error":"Card back must be 500 × 700."}
	var image := Image.new()
	if image.load_png_from_buffer(bytes)!=OK: return {"error":"Invalid card-back image."}
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if preload("res://scripts/card_storage.gd").write_atomic(path(hash_value),bytes)!=OK: return {"error":"Cannot store card back."}
	textures.erase(hash_value)
	return {"hash":hash_value}
static func import_image(file: String) -> Dictionary:
	var response: Dictionary=preload("res://scripts/card_image_processor.gd").load_source(file)
	if response.has("error"): return response
	var source: Image=response.image
	var image: Image=preload("res://scripts/card_image_processor.gd").normalize(source,preload("res://scripts/card_image_processor.gd").batch_crop(source,true))
	image.resize(500,700,Image.INTERPOLATE_LANCZOS)
	return store(image.save_png_to_buffer())
static func color_texture(color: String) -> Texture2D:
	var key: String="color:"+color
	if textures.has(key): return textures[key]
	var image := Image.new()
	var svg: String='<svg xmlns="http://www.w3.org/2000/svg" width="500" height="700"><rect width="500" height="700" rx="28" fill="#111a2a"/><rect x="20" y="20" width="460" height="660" rx="20" fill="'+color+'" stroke="#e4dfc7" stroke-width="5"/><rect x="40" y="40" width="420" height="620" rx="12" fill="none" stroke="#142337" stroke-width="4"/><path d="M150 260 L270 350 L150 440 L90 350 Z M350 260 L410 350 L350 440 L230 350 Z" fill="none" stroke="#e4dfc7" stroke-width="18"/><path d="M200 350 H300" stroke="#142337" stroke-width="14"/></svg>'
	image.load_svg_from_string(svg);textures[key]=ImageTexture.create_from_image(image);return textures[key]
static func texture(config: Dictionary) -> Texture2D:
	if not valid(config) or config.type=="default": return preload("res://assets/cardlink_back.svg")
	if config.type=="image" and not config.asset.is_empty():
		if textures.has(config.asset): return textures[config.asset]
		var file: String=path(config.asset)
		if FileAccess.file_exists(file) and FileAccess.get_sha256(file)==config.asset:
			var image := Image.new()
			if image.load(file)==OK and image.get_size()==Vector2i(500,700): textures[config.asset]=ImageTexture.create_from_image(image);return textures[config.asset]
	return color_texture(PRESETS[config.preset] if config.type=="preset" else config.color)
static func for_card(card: Control, backs: RefCounted) -> Texture2D:
	return texture(card.state.custom_metadata.deck_back) if card.state.custom_metadata.has("deck_back") and card.state.custom_metadata.deck_back is Dictionary else backs.texture(str(card.state.custom_metadata.get("card_back_id","")))
