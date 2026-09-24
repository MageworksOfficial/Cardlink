extends RefCounted
var internet: String = "Not checked"
var service: String = "Not checked"
var room_service: String = "Not checked"
var direct: String = "Not tested"
var relay: String = "Not checked"
var ready: String = "Not connected"
func text() -> String:
	return "Internet: %s\nCardLink Service: %s\nRoom Service: %s\nDirect Peer Connection: %s\nRelay Fallback: %s\nReady: %s" % [internet, service, room_service, direct, relay, ready]
static func error_text(code: String) -> String:
	return {
		"not_configured": "CardLink's internet service is not configured in this build. Use Advanced LAN, or configure the development service.",
		"service_unavailable": "CardLink online service is currently unavailable. The service could not be reached. Retry, Advanced LAN Connection, or Cancel.",
		"room_not_found": "Room not found. Check the room code or ask the host to create a new room.",
		"host_offline": "Host is no longer online. Ask the host to create a new room.",
		"room_closed": "This room has closed. Ask the host for a new code.",
		"room_full": "This room already has two players.",
		"relay_unavailable": "Relay service unavailable. Try again later or use Advanced LAN connection.",
		"service_busy": "CardLink's connection service is busy. Please try again shortly.",
		"invalid_response": "The connection service returned an invalid response. Connection stopped safely.",
	}.get(code, "Connection could not be completed safely. Create a new room or try Advanced LAN.")
