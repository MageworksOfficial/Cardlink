extends RefCounted
## Inspect sizes before ZIPReader allocates entry buffers. Nothing is extracted to disk.
const MAX_ARCHIVE: int = 512 * 1024 * 1024
const MAX_ENTRY: int = 128 * 1024 * 1024
const MAX_TOTAL: int = 512 * 1024 * 1024
static func inspect(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "zip":
		return {"error": "Please choose a ZIP archive. RAR is not supported; convert it to ZIP first."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open this archive."}
	var length: int = file.get_length()
	if length < 22 or length > MAX_ARCHIVE:
		return {"error": "Invalid ZIP or archive exceeds the 512 MB limit."}
	var tail_start: int = maxi(0, length - 65557)
	file.seek(tail_start)
	var tail: PackedByteArray = file.get_buffer(length - tail_start)
	var end: int = -1
	for i: int in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(i) == 0x06054b50 and i + 22 + tail.decode_u16(i + 20) == tail.size():
			end = i
			break
	if end < 0:
		return {"error": "Corrupt ZIP: missing end-of-directory record."}
	if tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0:
		return {"error": "Split/multi-volume ZIP archives are not supported."}
	var count: int = tail.decode_u16(end + 10)
	var size: int = tail.decode_u32(end + 12)
	var offset: int = tail.decode_u32(end + 16)
	if count == 65535 or size == 0xffffffff or offset == 0xffffffff:
		var locator: int = tail_start + end - 20
		if locator < 0:
			return {"error": "Invalid ZIP64 locator."}
		file.seek(locator)
		var loc: PackedByteArray = file.get_buffer(20)
		if loc.decode_u32(0) != 0x07064b50 or loc.decode_u32(4) != 0 or loc.decode_u32(16) != 1:
			return {"error": "Invalid or split ZIP64 archive."}
		var wide_offset: int = loc.decode_u64(8)
		if wide_offset < 0 or wide_offset + 56 > length:
			return {"error": "Invalid ZIP64 directory."}
		file.seek(wide_offset)
		var wide: PackedByteArray = file.get_buffer(56)
		if wide.decode_u32(0) != 0x06064b50 or wide.decode_u32(16) != 0 or wide.decode_u32(20) != 0:
			return {"error": "Invalid ZIP64 directory."}
		count = wide.decode_u64(32)
		size = wide.decode_u64(40)
		offset = wide.decode_u64(48)
	if count < 0 or count > 10000 or offset < 0 or size < 0 or offset + size > tail_start + end:
		return {"error": "Invalid directory or more than 10,000 archive entries."}
	var rows: Array[Dictionary] = []
	var names: Dictionary = {}
	var total: int = 0
	file.seek(offset)
	for i: int in count:
		if file.get_position() + 46 > offset + size:
			return {"error": "Truncated ZIP directory."}
		var header: PackedByteArray = file.get_buffer(46)
		if header.decode_u32(0) != 0x02014b50:
			return {"error": "Invalid ZIP directory entry."}
		var name_size: int = header.decode_u16(28)
		var extra_size: int = header.decode_u16(30)
		var comment_size: int = header.decode_u16(32)
		if name_size < 1 or name_size > 4096 or file.get_position() + name_size + extra_size + comment_size > offset + size:
			return {"error": "Invalid archive filename or entry length."}
		var name: String = file.get_buffer(name_size).get_string_from_utf8()
		var extra: PackedByteArray = file.get_buffer(extra_size)
		file.seek(file.get_position() + comment_size)
		var unpacked: int = header.decode_u32(24)
		var packed: int = header.decode_u32(20)
		var local_offset: int = header.decode_u32(42)
		var position: int = 0
		while position + 4 <= extra.size():
			var tag: int = extra.decode_u16(position)
			var field_size: int = extra.decode_u16(position + 2)
			position += 4
			if position + field_size > extra.size():
				return {"error": "Invalid ZIP extra field."}
			if tag == 1:
				var cursor: int = position
				for field: String in ["unpacked", "packed", "offset"]:
					var needed: bool = (unpacked == 0xffffffff if field == "unpacked" else (packed == 0xffffffff if field == "packed" else local_offset == 0xffffffff))
					if needed:
						if cursor + 8 > position + field_size:
							return {"error": "Truncated ZIP64 entry."}
						var value: int = extra.decode_u64(cursor)
						cursor += 8
						match field:
							"unpacked": unpacked = value
							"packed": packed = value
							"offset": local_offset = value
			position += field_size
		if names.has(name):
			return {"error": "ZIP contains the same full entry path twice: " + name}
		names[name] = true
		var supported: bool = name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]
		if supported:
			if (header.decode_u16(8) & 1) != 0 or not header.decode_u16(10) in [0, 8]:
				return {"error": "Encrypted images or unsupported ZIP compression. Use an unencrypted standard ZIP."}
			if unpacked < 0 or unpacked > MAX_ENTRY or packed < 0 or local_offset < 0 or local_offset + 30 + packed > offset:
				return {"error": "Invalid or oversized ZIP image entry."}
			total += unpacked
			if total > MAX_TOTAL:
				return {"error": "Expanded images exceed 512 MB; split the deck into smaller archives."}
		rows.append({"path": name, "size": unpacked, "supported": supported})
	file.close()
	return {"entries": rows}
