extends RefCounted
# Scryfall-specific options stay in the optional provider layer.
const TYPES = ["Any", "Creature", "Instant", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Land"]
const FORMATS = ["Any", "Commander", "Standard", "Modern", "Pioneer", "Legacy", "Vintage", "Pauper"]
const RARITIES = ["Any", "Common", "Uncommon", "Rare", "Mythic"]
const SORTS = ["name", "cmc", "released", "set", "rarity", "color"]
const COLORS = {"White":"w", "Blue":"u", "Black":"b", "Red":"r", "Green":"g", "Colorless":"c", "Multicolor":"m"}
static func quoted(value: String) -> String:
	return '"'+value.replace("\\","\\\\").replace('"','\\"')+'"'
static func build(name: String, options: Dictionary, exact: bool = false) -> Dictionary:
	var terms: Array[String] = []
	var summary: Array[String] = []
	if not name.strip_edges().is_empty(): terms.append("!"+quoted(name.strip_edges()) if exact else "("+name.strip_edges()+")")
	var colors: Array[String] = []
	for color: String in options.get("colors",[]):
		if COLORS.has(color): colors.append("c:"+COLORS[color]); summary.append(color)
	if not colors.is_empty(): terms.append("("+" or ".join(colors)+")")
	for field: String in ["type","format","rarity"]:
		var value: String = str(options.get(field,"Any"))
		var choices: Array = TYPES if field=="type" else FORMATS if field=="format" else RARITIES
		if not value in choices: return {"error":"Unknown "+field+" filter."}
		if value!="Any": terms.append({"type":"t:","format":"f:","rarity":"r:"}[field]+value.to_lower()); summary.append(value)
	var bounds: Dictionary = {}
	for field: String in ["min","max"]:
		var value: String = str(options.get(field,"")).strip_edges()
		if value.is_empty(): continue
		if not value.is_valid_float() or not is_finite(value.to_float()) or value.to_float()<0 or value.to_float()>1000:
			return {"error":"Mana value must be a number between 0 and 1000, or blank."}
		bounds[field]=value.to_float()
		terms.append("cmc"+(">=" if field=="min" else "<=")+str(value.to_float()))
		summary.append("MV "+("≥" if field=="min" else "≤")+value)
	if bounds.has("min") and bounds.has("max") and bounds.min>bounds.max: return {"error":"Minimum mana value cannot exceed maximum."}
	for field: String in ["set","oracle","artist","number"]:
		var value: String = str(options.get(field,"")).strip_edges()
		if not value.is_empty():
			terms.append({"set":"set:","oracle":"o:","artist":"a:","number":"cn:"}[field]+quoted(value))
			summary.append(field.capitalize()+": "+value)
	var identity: String = str(options.get("identity","")).strip_edges().to_lower()
	if not identity.is_empty():
		for character: String in identity:
			if not character in "wubrgc": return {"error":"Commander identity uses W U B R G, or C for colorless (no spaces)."}
		if "c" in identity and identity!="c": return {"error":"Use C alone for a colorless commander identity."}
		terms.append("id<="+identity); summary.append("Identity: "+identity.to_upper())
	var order: String = str(options.get("order","name"))
	if not order in SORTS: return {"error":"Unknown sort order."}
	if order!="name": summary.append("Sort: "+order)
	return {"query":" ".join(terms),"order":order,"summary":" • ".join(summary),"filtered":not summary.is_empty()}
