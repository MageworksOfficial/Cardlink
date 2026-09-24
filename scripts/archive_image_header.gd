extends RefCounted
## Read dimensions before decoding compressed images into full pixel buffers.
static func be16(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) * 256 + bytes[offset + 1]
static func be32(bytes: PackedByteArray, offset: int) -> int:
	return be16(bytes, offset) * 65536 + be16(bytes, offset + 2)
static func dimensions(bytes: PackedByteArray, extension: String) -> Vector2i:
	if extension == "png":
		if bytes.size() < 33 or bytes.slice(0, 8).hex_encode() != "89504e470d0a1a0a" or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
			return Vector2i.ZERO
		return Vector2i(be32(bytes, 16), be32(bytes, 20))
	if extension in ["jpg", "jpeg"]:
		if bytes.size() < 4 or be16(bytes, 0) != 0xffd8:
			return Vector2i.ZERO
		var i: int = 2
		while i + 4 < bytes.size():
			if bytes[i] != 0xff:
				return Vector2i.ZERO
			while i < bytes.size() and bytes[i] == 0xff:
				i += 1
			if i + 3 >= bytes.size():
				break
			var marker: int = bytes[i]
			i += 1
			if marker == 0xda or marker == 0xd9:
				break
			var length: int = be16(bytes, i)
			if length < 2 or i + length > bytes.size():
				break
			if marker in [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf] and length >= 8:
				return Vector2i(be16(bytes, i + 5), be16(bytes, i + 3))
			i += length
	if extension == "webp":
		if bytes.size() < 30 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WEBP":
			return Vector2i.ZERO
		var kind: String = bytes.slice(12, 16).get_string_from_ascii()
		if kind == "VP8X":
			return Vector2i(1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16), 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16))
		if kind == "VP8 " and bytes[23] == 0x9d and bytes[24] == 1 and bytes[25] == 0x2a:
			return Vector2i(bytes.decode_u16(26) & 0x3fff, bytes.decode_u16(28) & 0x3fff)
		if kind == "VP8L" and bytes[20] == 0x2f:
			var bits: int = bytes.decode_u32(21)
			return Vector2i((bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1)
	return Vector2i.ZERO
