extends RefCounted
## Pure parser; accepts text only and never performs I/O.
const SECTIONS = {"deck":"deck","main deck":"deck","maindeck":"deck","mainboard":"deck","commander":"commander","commanders":"commander","leader":"commander","leaders":"commander","sideboard":"sideboard","companion":"companion","maybeboard":"maybeboard"}
static func parse(text: String) -> Dictionary:
	var rows: Array = []
	var issues: Array = []
	var section: String = "deck"
	var pattern := RegEx.new()
	pattern.compile("^([0-9]+)[xX]?\\s+(.+?)(?:\\s+\\(([A-Za-z0-9]+)\\)\\s+([^\\s]+))?$")
	var line_number: int = 0
	var total: int = 0
	if text.length()>200000: return {"entries":[],"issues":[{"line":0,"text":"List exceeds 200 KB."}],"total":0}
	for raw: String in text.split("\n"):
		line_number += 1
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("//"): continue
		var heading: String = line.trim_suffix(":").to_lower()
		if SECTIONS.has(heading): section = SECTIONS[heading]; continue
		var entry_section: String = section
		if line.begins_with("SB: "): entry_section="sideboard"; line=line.substr(4)
		var found: RegExMatch = pattern.search(line)
		if found==null or int(found.get_string(1))<1 or int(found.get_string(1))>1000 or found.get_string(2).length()>160:
			issues.append({"line":line_number,"text":raw}); continue
		var entry: Dictionary = {"quantity":int(found.get_string(1)),"name":found.get_string(2).strip_edges(),"set_code":found.get_string(3).to_lower(),"collector_number":found.get_string(4),"section":entry_section}
		var matched: bool = false
		for existing: Dictionary in rows:
			if existing.name==entry.name and existing.set_code==entry.set_code and existing.collector_number==entry.collector_number and existing.section==entry.section:
				existing.quantity += entry.quantity; matched=true; break
		if not matched: rows.append(entry)
		total += int(entry.quantity)
	if total>2000 or rows.size()>500 or rows.any(func(e: Dictionary) -> bool:return e.quantity>1000):
		return {"entries":[],"issues":[{"line":0,"text":"Limit: 500 unique entries, 2000 copies, 1000 per row."}],"total":total}
	return {"entries":rows,"issues":issues,"total":total}
