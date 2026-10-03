extends RefCounted
const D = preload("res://scripts/network/network_action.gd")
static func defaults() -> Dictionary:
	return {"type":"default","color":"#152d40","asset":"","position":[0,0],"size":[2304,1296],"rotation":0.0,"opacity":1.0,"locked":true}
static func valid(v: Variant) -> bool:
	if not v is Dictionary or v.size()!=8: return false
	for key: String in defaults():
		if not v.has(key): return false
	return v.type in ["default","color","image"] and v.color is String and v.color.length()==7 and v.color.begins_with("#") and v.color.substr(1).is_valid_hex_number(false) and (v.asset is String and (v.asset.is_empty() or (v.asset.length()==64 and v.asset.is_valid_hex_number(false) and v.asset==v.asset.to_lower()))) and (v.type!="image" or not v.asset.is_empty()) and pair(v.position,-20000,20000) and pair(v.size,40,20000) and D.number(v.rotation,-360,360) and D.number(v.opacity,0,1) and v.locked is bool

static func pair(value: Variant, low: float, high: float) -> bool:
	return value is Array and value.size()==2 and D.number(value[0],low,high) and D.number(value[1],low,high)
