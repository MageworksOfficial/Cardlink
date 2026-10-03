extends RefCounted
## Strict, bounded JSON messages. No Variant/object decoding or match snapshots.
const PROTOCOL = 1
const APP_VERSION = preload("res://scripts/frontend/app_info.gd").NETWORK_COMPATIBILITY
const MAX_BYTES = 2048
const MAX_FRAME = 524288
const FIELDS = {
	"welcome": ["type", "protocol", "app_version", "player_id", "role", "display_name", "session_id"],
	"hello": ["type", "protocol", "app_version", "player_id", "role", "display_name", "session_id"],
	"ready": ["type", "protocol", "session_id"],
	"reject": ["type", "protocol", "reason"],
	"bye": ["type", "protocol"],
	"ping": ["type", "protocol"],
	"pong": ["type", "protocol"]}
static func safe_text(value: Variant, limit: int) -> bool:
	if not value is String or value.is_empty() or value.length() > limit:
		return false
	for c: int in value.length():
		if value.unicode_at(c) < 32 or value.unicode_at(c) == 127:
			return false
	return true
const EPOCH_TYPES = ["game","hidden_zone","transfer_tx","table_structure","card_sync"]
static func valid(message: Dictionary) -> bool:
	if message.has("match_epoch"):
		if not message.get("type") in EPOCH_TYPES and not (message.get("type")=="recovery" and message.get("kind") not in ["hello","challenge","proof"]): return false
		if not preload("res://scripts/battle/battle_protocol.gd").identifier(message.match_epoch): return false
		message=message.duplicate(true);message.erase("match_epoch")
	if message.get("type")=="ready" and message.has("save_state_version"):
		if message.save_state_version!=3: return false
		message=message.duplicate(true);message.erase("save_state_version")
	if message.get("type") == "battle": return preload("res://scripts/battle/battle_protocol.gd").valid(message)
	if message.get("type") in ["hello","welcome"] and message.has("battle_version"):
		if message.battle_version!=1 or not message.get("reset_pending") is bool: return false
		message=message.duplicate(true);message.erase("battle_version");message.erase("reset_pending")
	if message.get("type") == "table_structure": return preload("res://scripts/custom_table/table_protocol.gd").valid(message)
	if message.get("type") == "recovery":
		return preload("res://scripts/network/recovery_protocol.gd").valid(message)
	if message.get("type") == "transfer_tx":
		return preload("res://scripts/network/transfer_protocol.gd").valid(message)
	if message.get("type") == "hidden_zone":
		return preload("res://scripts/network/hidden_zone_protocol.gd").valid(message)
	if message.get("type") == "card_sync":
		return preload("res://scripts/network/card_sync_protocol.gd").valid(message)
	if message.get("type") == "game":
		return preload("res://scripts/network/network_action.gd").frame(message)
	var kind: Variant = message.get("type")
	if not kind is String or not FIELDS.has(kind) or message.size() != FIELDS[kind].size() + (1 if kind == "hello" and message.has("join_key") else 0):
		return false
	for field: String in FIELDS[kind]:
		if not message.has(field):
			return false
	if message.has("join_key") and (not message.join_key is String or message.join_key.length() != 32 or not message.join_key.is_valid_hex_number(false)):
		return false
	var version: Variant = message.get("protocol")
	if not (version is int or version is float) or not is_finite(float(version)) or version != floor(version) or version < 1 or version > 65535:
		return false
	if kind in ["welcome", "hello"]:
		if not safe_text(message.display_name, 48) or not safe_text(message.app_version, 24):
			return false
		if message.player_id != ("player_1" if kind == "welcome" else "player_2") or message.role != ("host" if kind == "welcome" else "guest"):
			return false
	if message.has("session_id"):
		if not message.session_id is String or message.session_id.length() != 32 or not message.session_id.is_valid_hex_number(false):
			return false
	if kind == "reject" and not message.reason in ["protocol_mismatch", "invalid_message"]:
		return false
	return true
static func encode(message: Dictionary) -> PackedByteArray:
	if not valid(message):
		return PackedByteArray()
	var bytes: PackedByteArray = JSON.stringify(message).to_utf8_buffer()
	if bytes.size() > (MAX_FRAME if message.get("type") in ["game", "card_sync", "hidden_zone", "recovery", "transfer_tx", "table_structure", "battle"] else MAX_BYTES):
		return PackedByteArray()
	bytes.append(10)
	return bytes
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_FRAME or not valid_utf8(bytes):
		return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary or not valid(json.data):
		return {}
	if bytes.size() > MAX_BYTES and not json.data.get("type") in ["game","card_sync","hidden_zone", "recovery", "transfer_tx", "table_structure", "battle"]:
		return {}
	return json.data
static func valid_utf8(bytes: PackedByteArray) -> bool:
	# Reject invalid encoding before Godot's decoder can emit engine errors.
	var i: int = 0
	while i < bytes.size():
		var first: int = bytes[i]
		if first < 128:
			i += 1
			continue
		var count: int = 2 if first >= 194 and first <= 223 else (3 if first >= 224 and first <= 239 else (4 if first >= 240 and first <= 244 else 0))
		if count == 0 or i + count > bytes.size():
			return false
		for j: int in range(1, count):
			if bytes[i + j] < 128 or bytes[i + j] > 191:
				return false
		var second: int = bytes[i + 1]
		if (first == 224 and second < 160) or (first == 237 and second >= 160) or (first == 240 and second < 144) or (first == 244 and second >= 144):
			return false
		i += count
	return true
