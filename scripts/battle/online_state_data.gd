extends RefCounted
const Snapshot=preload("res://scripts/match_snapshot.gd")
const Fingerprint=preload("res://scripts/battle/deck_fingerprint.gd")
const Capsule=preload("res://scripts/battle/save_state_capsule.gd")
static func capture(manager: Node) -> Dictionary:
	var data: Dictionary=Snapshot.capture(manager)
	var records: Dictionary={}
	for row: Dictionary in manager.match_controller.loader.load_records(): records[row.metadata.card_id]=row.metadata
	data.local_tabletop.reset_start={}
	for player: Dictionary in data.players: player.deck_manifest=[]
	for card: Dictionary in data.cards:
		if card.is_token or card.card_definition_id.is_empty(): continue
		if not records.has(card.card_definition_id): return {"error":"Sync all required card definitions before saving."}
		card["content_key"]=Fingerprint.definition(records[card.card_definition_id])
		card.image_path="";card.definition_path="";card.faces=[]
		# Face ordinal is restored after binding the existing definition.
		card["saved_face"]=card.active_face_index;card.active_face_index=0
	return data
static func bind(data: Dictionary,manager: Node) -> Dictionary:
	if not Snapshot.validate(data).is_empty(): return {"error":"Invalid saved local state: "+Snapshot.validate(data)}
	if not data.get("local_tabletop",{}).get("reset_start",{}).is_empty(): return {"error":"Online save must not contain source deck recipes."}
	var result: Dictionary=data.duplicate(true);var records: Dictionary={}
	for row: Dictionary in manager.match_controller.loader.load_records(): records[Fingerprint.definition(row.metadata)]=row
	for player: Dictionary in result.players:
		if not player.get("deck_manifest",[]).is_empty(): return {"error":"Online save must not contain a source deck manifest."}
		player.deck_manifest=manager.match_controller.model.players[player.player_id].deck_manifest.duplicate(true)
	for card: Dictionary in result.cards:
		if card.is_token or card.card_definition_id.is_empty(): continue
		if not card.get("content_key") is String or not records.has(card.content_key): return {"error":"A saved card definition is unavailable. Load both decks and complete Card Sync."}
		var row: Dictionary=records[card.content_key]
		if row.thumbnail==null: return {"error":"A required card image is missing. Complete Card Sync first."}
		card.card_definition_id=row.metadata.card_id;card.definition_path=row.path
		card.faces=row.metadata.get("faces",[]).duplicate(true);card.active_face_index=int(card.get("saved_face",0));card.image_path=row.image_path
		if not card.faces.is_empty():
			if card.active_face_index<0 or card.active_face_index>=card.faces.size(): return {"error":"Invalid saved face index."}
			card.image_path=card.faces[card.active_face_index].image_path
	result.local_tabletop.reset_start=manager.battle.reset.start.capture()
	return {"data":result} if Snapshot.validate(result).is_empty() else {"error":"Saved instance/zone validation failed."}
static func hash_value(value: Variant) -> String:
	# Canonicalize integer/float Variants through the same JSON representation used on wire/disk.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)),"",true).sha256_text()
static func safe_text(value: Variant,limit: int) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length()>limit: return false
	for c: int in value.length():
		if value.unicode_at(c)<32 or value.unicode_at(c)==127: return false
	return true
static func shared_valid(d: Variant) -> bool:
	var A=preload("res://scripts/network/network_action.gd")
	if not d is Dictionary or not A.keys(d,["save_state_id","save_name","timestamp","app_version","names","fingerprints","roles","public_hash","table"]): return false
	if not d.save_state_id is String or d.save_state_id.length()!=32 or not d.save_state_id.is_valid_hex_number(false): return false
	if not safe_text(d.save_name,80) or not safe_text(d.timestamp,32) or not safe_text(d.app_version,96) or d.table!="standard": return false
	for field: String in ["names","fingerprints","roles"]:
		if not d[field] is Dictionary or not A.keys(d[field],["player_1","player_2"]): return false
		for role: String in ["player_1","player_2"]:
			var value: Variant=d[field][role]
			if not value is String: return false
			if field=="names":
				if not safe_text(value,48): return false
			elif value.length()!=64 or not value.is_valid_hex_number(false): return false
	return d.public_hash is String and d.public_hash.length()==64 and d.public_hash.is_valid_hex_number(false)
static func validate(file: Dictionary) -> String:
	if file.get("format")!="cardlink_paired_state" or file.get("version")!=2: return "This save was created by an older development version of Match Save and cannot be restored."
	if not shared_valid(file.get("shared")): return "Invalid paired save metadata."
	if file.get("local_role") not in ["player_1","player_2"]: return "Invalid saved player role."
	if not Capsule.valid(file.get("private_capsule")): return "Invalid local private save."
	if not preload("res://scripts/network/network_action.gd").snapshot(file.get("public")) or hash_value(file.public)!=file.shared.public_hash: return "Saved public checkpoint is damaged."
	return ""
static func mismatch(a: bool,b: bool) -> String:
	if not a and not b: return "Both original decks must be loaded before this match can be restored."
	if not a: return "This save state requires a different Player 1 deck."
	if not b: return "This save state requires a different Player 2 deck."
	return ""
