extends Node
## Optional provider boundary. No match, peer, or hand state is accepted here.
func search(_query: String, _page: int = 1) -> Dictionary: return {"error":"Provider unavailable."}
func resolve_card(_entry: Dictionary) -> Dictionary: return {"error":"Provider unavailable."}
func get_printings(_card: Dictionary, _page: int = 1) -> Dictionary: return {"error":"Provider unavailable."}
func fetch_metadata(_id: String) -> Dictionary: return {"error":"Provider unavailable."}
func fetch_image(_url: String, _thumbnail: bool = false) -> Dictionary: return {"error":"Provider unavailable."}
