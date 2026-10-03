extends RefCounted
## Encrypt-then-MAC. Each installation's persistent local key stays on that installation.
const LIMIT=262144
static func key(path: String) -> PackedByteArray:
	if FileAccess.file_exists(path): return FileAccess.get_file_as_bytes(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var value: PackedByteArray=Crypto.new().generate_random_bytes(64)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return PackedByteArray()
	file.store_buffer(value);file.close();return value
static func seal(data: Dictionary, secret: PackedByteArray) -> Dictionary:
	if secret.size()!=64: return {"error":"Private save key unavailable."}
	var plain: PackedByteArray=JSON.stringify(data).to_utf8_buffer()
	if plain.size()>LIMIT-16: return {"error":"Private save state exceeds the 256 KiB safety limit."}
	var padding: int=16-plain.size()%16
	for i: int in padding: plain.append(padding)
	var iv: PackedByteArray=Crypto.new().generate_random_bytes(16)
	var aes:=AESContext.new();aes.start(AESContext.MODE_CBC_ENCRYPT,secret.slice(0,32),iv)
	var encrypted: PackedByteArray=aes.update(plain);aes.finish()
	var mac: PackedByteArray=Crypto.new().hmac_digest(HashingContext.HASH_SHA256,secret.slice(32),iv+encrypted)
	return {"iv":iv.hex_encode(),"cipher":Marshalls.raw_to_base64(encrypted),"mac":mac.hex_encode()}
static func open(data: Dictionary, secret: PackedByteArray) -> Dictionary:
	if secret.size()!=64 or not valid(data): return {"error":"Private save data or local key unavailable."}
	var iv: PackedByteArray=data.iv.hex_decode();var encrypted: PackedByteArray=Marshalls.base64_to_raw(data.cipher)
	var mac: PackedByteArray=Crypto.new().hmac_digest(HashingContext.HASH_SHA256,secret.slice(32),iv+encrypted)
	if not Crypto.new().constant_time_compare(mac,data.mac.hex_decode()): return {"error":"This save requires this installation's original private save key, or is damaged."}
	var aes:=AESContext.new();aes.start(AESContext.MODE_CBC_DECRYPT,secret.slice(0,32),iv)
	var plain: PackedByteArray=aes.update(encrypted);aes.finish()
	var padding: int=plain[-1]
	if padding<1 or padding>16: return {"error":"Invalid private save padding."}
	for i: int in padding:
		if plain[plain.size()-1-i]!=padding: return {"error":"Invalid private save padding."}
	var parsed: Variant=JSON.parse_string(plain.slice(0,plain.size()-padding).get_string_from_utf8())
	return {"data":parsed} if parsed is Dictionary else {"error":"Damaged private save state."}
static func valid(d: Variant) -> bool:
	if not d is Dictionary or d.size()!=3 or not d.get("iv") is String or not d.get("mac") is String or not d.get("cipher") is String: return false
	if d.iv.length()!=32 or not d.iv.is_valid_hex_number(false) or d.mac.length()!=64 or not d.mac.is_valid_hex_number(false) or d.cipher.is_empty() or d.cipher.length()>349528: return false
	var regex:=RegEx.new();regex.compile("^[A-Za-z0-9+/]*={0,2}$")
	if d.cipher.length()%4!=0 or regex.search(d.cipher)==null: return false
	var b: PackedByteArray=Marshalls.base64_to_raw(d.cipher)
	return b.size()>0 and b.size()<=LIMIT and b.size()%16==0
