extends RefCounted
const MAX_BYTES = 65536
static func version(value: Variant) -> Array:
	if not value is String or value.length()>40: return []
	var parts: PackedStringArray=value.trim_prefix("V").trim_prefix("v").trim_suffix("-beta").split(".")
	if parts.size()<3 or parts.size()>4: return []
	var result: Array=[]
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int() or part.begins_with("+") or part.begins_with("-") or part.length()>6 or part.strip_edges()!=part: return []
		result.append(int(part))
	while result.size()<4: result.append(0)
	# Stable sorts after the explicit beta channel of the same numeric version.
	result.append(0 if value.ends_with("-beta") else 1)
	return result
static func compare(a: String,b: String) -> int:
	var av: Array=version(a);var bv: Array=version(b)
	if av.is_empty() or bv.is_empty(): return 0
	for i: int in 5:
		if av[i]!=bv[i]: return 1 if av[i]>bv[i] else -1
	return 0
static func https_url(value: Variant) -> bool:
	if not value is String or value.length()>2048 or not value.begins_with("https://"): return false
	var authority: String=value.trim_prefix("https://").split("/")[0]
	return not authority.is_empty() and not value.contains("@") and not value.contains("\\") and not value.contains(" ") and not value.contains("\n") and not value.contains("\r") and not value.contains("\t")
static func release_url(value: Variant,repository: String,asset: bool=false) -> bool:
	if not https_url(value) or repository.count("/")!=1: return false
	var prefix: String="https://github.com/"+repository+"/releases/"+("download/" if asset else "")
	return value.begins_with(prefix) and not value.contains("..") and not value.contains("%") and not value.contains("?") and not value.contains("#") and (asset or value.begins_with(prefix+"tag/") or value==prefix+"latest")
static func validate(data: Variant,repository: String) -> String:
	if not data is Dictionary: return "Manifest must be an object."
	for key: String in ["latest_version","minimum_online_version"]:
		if version(data.get(key)).is_empty(): return "Invalid "+key+"."
	if compare(data.minimum_online_version,data.latest_version)>0: return "Minimum online version exceeds latest version."
	if data.get("update_level") not in ["optional","recommended","required"]: return "Invalid update level."
	if not release_url(data.get("release_url"),repository): return "Release must belong to the configured GitHub project."
	if data.has("server_directory_url") and data.server_directory_url!="" and not https_url(data.server_directory_url): return "Invalid optional directory URL."
	if not data.get("assets") is Dictionary or data.assets.size()>8: return "Invalid assets."
	for platform: Variant in data.assets:
		if not platform is String or platform.length()>40: return "Invalid platform."
		var asset: Variant=data.assets[platform]
		if not asset is Dictionary or not release_url(asset.get("url"),repository,true): return "Invalid GitHub asset URL."
		var hash_value: Variant=asset.get("sha256")
		if not hash_value is String or hash_value.length()!=64 or not hash_value.is_valid_hex_number(false): return "Invalid SHA-256."
		var bytes: Variant=asset.get("size")
		if not (bytes is int or bytes is float) or not is_finite(float(bytes)) or bytes!=floor(bytes) or bytes<1 or bytes>10737418240: return "Invalid asset size."
	return ""
static func public_fields(data: Dictionary) -> Dictionary:
	# Cache only recognized metadata; never retain arbitrary response fields.
	var result: Dictionary={}
	for key: String in ["latest_version","minimum_online_version","update_level","release_url","assets"]: result[key]=data[key].duplicate(true) if data[key] is Dictionary else data[key]
	for platform: String in result.assets:
		var asset: Dictionary=result.assets[platform]
		result.assets[platform]={"url":asset.url,"sha256":asset.sha256,"size":asset.size}
	return result
