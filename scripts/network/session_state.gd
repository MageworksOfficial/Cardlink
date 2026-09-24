extends RefCounted
const Identity = preload("res://scripts/network/peer_identity.gd")
var state: String = "disconnected"
var status: String = "Disconnected. Local play is available."
var session_id: String = ""
var local_peer = Identity.new()
var remote_peer = Identity.new()
func reset() -> void:
	session_id = ""
	local_peer = Identity.new()
	remote_peer = Identity.new()
