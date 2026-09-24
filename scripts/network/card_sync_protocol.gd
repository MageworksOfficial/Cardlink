extends RefCounted
## Asset messages contain deck definitions, never match instances or hidden-zone arrays.
const MAX_IMAGE = 8 * 1024 * 1024
const CHUNK = 32768
const MAX_CARDS = 500
const MAX_SESSION_BYTES = 256 * 1024 * 1024
static func identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 80: return false
	for i: int in value.length():
		var ch: String = value[i]
		if not ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true
static func hash_ok(value: Variant) -> bool:
	return value is String and value.length() == 64 and value == value.to_lower() and value.is_valid_hex_number(false)
static func definition(value: Variant) -> bool:
	var a = preload("res://scripts/network/network_action.gd")
	if not a.keys(value,["id","name","hash","tags","faces"],false): return false
	if not ["id","name","hash","tags"].all(func(key: String) -> bool: return value.has(key)): return false
	if not identifier(value.id) or not hash_ok(value.hash) or not a.text(value.name,160) or value.name.strip_edges().is_empty(): return false
	if not value.tags is Array or value.tags.size() > 24: return false
	for tag: Variant in value.tags:
		if not a.text(tag,48): return false
	if value.has("faces"):
		if not value.faces is Array or value.faces.size()<2 or value.faces.size()>16: return false
		for face: Variant in value.faces:
			if not a.keys(face,["name","hash"]) or not a.text(face.name,160) or face.name.strip_edges().is_empty() or not hash_ok(face.hash): return false
		if value.faces[0].hash != value.hash: return false
	return true
static func manifest(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_CARDS: return false
	var ids: Dictionary = {}
	for row: Variant in value:
		if not definition(row) or ids.has(row.id): return false
		ids[row.id] = true
	return true
static func strings(value: Variant, hashes: bool = false) -> bool:
	if not value is Array or value.size() > MAX_CARDS * 16: return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not (hash_ok(id) if hashes else identifier(id)) or seen.has(id): return false
		seen[id] = true
	return true
static func valid(frame: Dictionary) -> bool:
	var a = preload("res://scripts/network/network_action.gd")
	if not a.keys(frame,["type","protocol","session_id","run","kind","data"]) or frame.type != "card_sync" or not a.number(frame.protocol,1,65535) or not identifier(frame.run) or not a.text(frame.session_id,32): return false
	var d: Variant = frame.data
	match frame.kind:
		"availability": return a.keys(d,["available","missing","definitions","images"]) and a.number(d.available,0,MAX_CARDS*16) and a.number(d.missing,0,MAX_CARDS*16) and a.number(d.definitions,0,MAX_CARDS*16) and a.number(d.images,0,MAX_CARDS*16)
		"manifest": return manifest(d)
		"decision": return a.keys(d,["choice"]) and d.choice in ["sync","placeholders","cancel","start"]
		"begin", "launch": return a.keys(d,[])
		"need": return a.keys(d,["step","definitions","images"]) and a.number(d.step,1,2) and d.step == floor(d.step) and strings(d.definitions) and strings(d.images,true)
		"definition": return a.keys(d,["step","row"]) and a.number(d.step,1,2) and d.step == floor(d.step) and definition(d.row)
		"image_begin": return a.keys(d,["step","hash","bytes"]) and a.number(d.step,1,2) and d.step == floor(d.step) and hash_ok(d.hash) and a.number(d.bytes,1,MAX_IMAGE) and d.bytes == floor(d.bytes)
		"chunk": return a.keys(d,["step","hash","offset","base64"]) and a.number(d.step,1,2) and d.step == floor(d.step) and hash_ok(d.hash) and a.number(d.offset,0,MAX_IMAGE) and d.offset == floor(d.offset) and a.text(d.base64,43692)
		"ack": return a.keys(d,["offset"]) and a.number(d.offset,0,MAX_IMAGE)
		"sent": return a.keys(d,["step"]) and a.number(d.step,1,2) and d.step == floor(d.step)
		"report": return a.keys(d,["step","missing","available","definitions","images","reused"]) and a.number(d.step,1,2) and d.step == floor(d.step) and a.number(d.missing,0,MAX_CARDS*16) and a.number(d.available,0,MAX_CARDS*16) and a.number(d.definitions,0,MAX_CARDS*16) and a.number(d.images,0,MAX_CARDS*16) and a.number(d.reused,0,MAX_CARDS*16)
		"error": return a.keys(d,["message"]) and a.text(d.message,200)
	return false
