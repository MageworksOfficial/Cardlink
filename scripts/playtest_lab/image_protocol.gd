extends RefCounted
const Doc=preload("res://scripts/custom_table/table_document.gd")
static func row(value: Variant) -> bool:
 if not value is Dictionary or value.size()!=7:return false
 for key: String in ["id","hash","position","size","rotation","opacity","locked"]:
  if not value.has(key):return false
 return Doc.hash_id(value.id,32) and Doc.hash_id(value.hash,64) and Doc.pair(value.position,-20000,20000) and Doc.pair(value.size,40,4000) and Doc.number(value.rotation,-360,360) and Doc.number(value.opacity,0.05,1) and value.locked is bool
static func valid(frame: Dictionary) -> bool:
 if frame.size()!=5 or frame.get("type")!="playtest_image" or frame.get("protocol")!=1 or not Doc.hash_id(frame.get("session_id"),32) or not frame.get("data") is Dictionary:return false
 var data: Dictionary=frame.data
 match frame.get("kind"):
  "object":return row(data)
  "delete":return data.size()==1 and Doc.hash_id(data.get("id"),32)
  "need":return data.size()==1 and Doc.hash_id(data.get("hash"),64)
  "chunk":return data.size()==4 and Doc.hash_id(data.get("hash"),64) and Doc.number(data.get("offset"),0,8388608) and data.offset==floor(data.offset) and Doc.number(data.get("total"),24,8388608) and data.total==floor(data.total) and data.get("bytes") is String and data.bytes.length()<=43692
 return false
