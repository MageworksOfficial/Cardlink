extends RefCounted
## Adapts a verified TLS stream to the existing manager's TCP-shaped interface.
var tcp: StreamPeerTCP
var tls: StreamPeerTLS
func poll() -> void:
	tcp.poll()
	if tls != null:
		tls.poll()
func get_status() -> int:
	if tls == null:
		return tcp.get_status()
	var value: int = tls.get_status()
	return StreamPeerTCP.STATUS_CONNECTED if value == StreamPeerTLS.STATUS_CONNECTED else (StreamPeerTCP.STATUS_CONNECTING if value == StreamPeerTLS.STATUS_HANDSHAKING else StreamPeerTCP.STATUS_ERROR)
func stream() -> StreamPeer:
	return tls if tls != null else tcp
func get_available_bytes() -> int:
	return stream().get_available_bytes()
func get_partial_data(count: int) -> Array:
	return stream().get_partial_data(count)
func put_partial_data(data: PackedByteArray) -> Array:
	return stream().put_partial_data(data)
func disconnect_from_host() -> void:
	if tls != null:
		tls.disconnect_from_stream()
	tcp.disconnect_from_host()
