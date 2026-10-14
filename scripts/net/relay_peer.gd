class_name RelayPeer
extends MultiplayerPeerExtension
## A multiplayer connection through the relay server (relay/ in this repo)
## instead of directly between computers. It's a WebSocket, so it works from
## a browser and needs no port forwarding: the host opens a room and gets a
## short code, the other player joins with the code, and the relay passes the
## game's packets between them. To the rest of the game it looks like any
## other MultiplayerPeer (the host is peer 1).
##
## The relay's protocol is described at the top of relay/src/room.js.

## The relay gave the host its room code.
signal room_opened(code: String)
## The relay turned us away or closed the room; [param reason] says why.
signal refused(reason: String)

const HEADER_SIZE := 6
const BUFFER_SIZE := 4 << 20

var room_code := ""
## Why the relay closed the connection, if it said.
var close_reason := ""

var _socket := WebSocketPeer.new()
var _hosting := false
var _id := 0
var _status := CONNECTION_DISCONNECTED
## Peers we can reach: every guest for the host, only the host for a guest.
var _peers := {}
var _incoming: Array[Dictionary] = []
var _target := 0
var _channel := 0
var _mode := TRANSFER_MODE_RELIABLE
var _refusing := false


## Opens a room on the relay at [param url] (ws:// or wss://).
func host(url: String) -> Error:
	_hosting = true
	return _open(url.trim_suffix("/") + "/host")


## Joins the room [param code] on the relay at [param url].
func join(url: String, code: String) -> Error:
	_hosting = false
	return _open(url.trim_suffix("/") + "/join/" + code.strip_edges().to_upper())


func _open(url: String) -> Error:
	_socket.inbound_buffer_size = BUFFER_SIZE
	_socket.outbound_buffer_size = BUFFER_SIZE
	_socket.max_queued_packets = 8192
	var error := _socket.connect_to_url(url)
	if error == OK:
		_status = CONNECTION_CONNECTING
	return error


func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	_socket.poll()
	while _socket.get_available_packet_count() > 0:
		var data := _socket.get_packet()
		if _socket.was_string_packet():
			_control(data.get_string_from_utf8())
		elif data.size() >= HEADER_SIZE:
			var source := data.decode_s32(0)
			if _peers.has(source):
				_incoming.append({"peer": source, "channel": data[4], "mode": data[5], "data": data.slice(HEADER_SIZE)})
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_lost()


func _control(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if typeof(message) != TYPE_DICTIONARY:
		return
	match message.get("type", ""):
		"welcome":
			_id = int(message.id)
			room_code = str(message.code)
			_status = CONNECTION_CONNECTED
			for peer: Variant in message.get("peers", []):
				_add(int(peer))
			if _hosting:
				room_opened.emit(room_code)
		"peer_joined":
			if _refusing:
				_kick(int(message.id))
			else:
				_add(int(message.id))
		"peer_left":
			_remove(int(message.id))
		"error":
			close_reason = str(message.get("message", ""))


func _add(peer: int) -> void:
	if peer == _id or _peers.has(peer):
		return
	_peers[peer] = true
	peer_connected.emit(peer)


func _remove(peer: int) -> void:
	if _peers.erase(peer):
		peer_disconnected.emit(peer)


## The socket closed: tell the game everyone is gone.
func _lost() -> void:
	var was := _status
	_status = CONNECTION_DISCONNECTED
	if close_reason == "" and _socket.get_close_reason() != "":
		close_reason = _socket.get_close_reason()
	for peer: int in _peers.keys():
		_remove(peer)
	if was == CONNECTION_CONNECTING or close_reason != "":
		refused.emit(close_reason if close_reason != "" else "Couldn't reach the relay server")


func _kick(peer: int) -> void:
	_socket.send_text(JSON.stringify({"type": "kick", "id": peer}))


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var target := _target
	if not _hosting:
		target = 1  # Guests only ever talk to the host.
	var packet := PackedByteArray()
	packet.resize(HEADER_SIZE)
	packet.encode_s32(0, target)
	packet[4] = _channel
	packet[5] = _mode
	packet.append_array(buffer)
	return _socket.send(packet)


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	return _incoming.pop_front().data if not _incoming.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return _incoming[0].peer if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return _incoming[0].channel if not _incoming.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _incoming[0].mode if not _incoming.is_empty() else TRANSFER_MODE_RELIABLE


func _get_max_packet_size() -> int:
	return (1 << 20) - HEADER_SIZE


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _get_unique_id() -> int:
	return 1 if _hosting else _id


func _is_server() -> bool:
	return _hosting


func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> ConnectionStatus:
	return _status


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _hosting and _peers.has(peer):
		_kick(peer)
		_remove(peer)


func _close() -> void:
	if _status != CONNECTION_DISCONNECTED:
		_socket.close()
	_status = CONNECTION_DISCONNECTED
	_peers.clear()
	_incoming.clear()
