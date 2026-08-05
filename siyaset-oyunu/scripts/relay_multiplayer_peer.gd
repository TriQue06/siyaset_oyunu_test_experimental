class_name RelayMultiplayerPeer
extends MultiplayerPeerExtension
## CGNAT / statik IP olmayan oyuncular arasinda oda kodu ile eslestirme
## yapan, internete acik bir WebSocket role sunucusu (relay-server/server.js)
## uzerinden calisan ozel MultiplayerPeer implementasyonu. Godot'un yuksek
## seviye multiplayer API'siyle (RPC, MultiplayerSpawner vb.) normal bir
## ENetMultiplayerPeer gibi kullanilabilir; tek fark tasima katmani.

enum FrameType {
	CREATE_ROOM = 0,
	JOIN_ROOM = 1,
	ROOM_OK = 2,
	ROOM_ERR = 3,
	PEER_CONNECTED = 4,
	PEER_DISCONNECTED = 5,
	DATA = 6,
	ROOM_CLOSED = 7,
}

signal room_created(code: String)
signal room_error(reason: String)
signal room_closed_by_relay(reason: String)

var _ws: WebSocketPeer = WebSocketPeer.new()
var _status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var _unique_id: int = 0
var _target_peer: int = 0
var _transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refusing_new_connections: bool = false

var _incoming: Array = [] # her biri: {"sender": int, "data": PackedByteArray}

var _pending_mode: int = -1 # 0=create, 1=join
var _pending_name: String = ""
var _pending_code: String = ""
var _sent_hello: bool = false

func start_create_room(relay_url: String, player_name: String) -> void:
	_pending_mode = FrameType.CREATE_ROOM
	_pending_name = player_name
	_connect(relay_url)

func start_join_room(relay_url: String, code: String, player_name: String) -> void:
	_pending_mode = FrameType.JOIN_ROOM
	_pending_code = code.to_upper()
	_pending_name = player_name
	_connect(relay_url)

func _connect(relay_url: String) -> void:
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	_sent_hello = false
	var err := _ws.connect_to_url(relay_url)
	if err != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		room_error.emit("Sunucuya baglanilamadi.")

func _send_hello() -> void:
	var body := PackedByteArray()
	if _pending_mode == FrameType.CREATE_ROOM:
		body.append(FrameType.CREATE_ROOM)
		body.append_array(_pending_name.to_utf8_buffer())
	else:
		body.append(FrameType.JOIN_ROOM)
		body.append_array(_pending_code.to_ascii_buffer())
		body.append_array(_pending_name.to_utf8_buffer())
	_ws.send(body)
	_sent_hello = true

# ---- MultiplayerPeerExtension zorunlu overrideleri ----

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	var state := _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not _sent_hello:
		_send_hello()

	if state == WebSocketPeer.STATE_CLOSED:
		# connection_succeeded/connection_failed/server_disconnected sinyalleri
		# MultiplayerPeer'da degil, ust seviye MultiplayerAPI'de yasar; o da bu
		# durumu _get_connection_status()'u her frame yoklayarak kendisi anlar.
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return

	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		_handle_frame(pkt)

func _handle_frame(pkt: PackedByteArray) -> void:
	if pkt.size() < 1:
		return
	var frame_type := pkt[0]
	match frame_type:
		FrameType.ROOM_OK:
			if pkt.size() < 1 + 5 + 4 + 1:
				return
			var code := pkt.slice(1, 6).get_string_from_ascii()
			var peer_id := pkt.decode_s32(6)
			_unique_id = peer_id
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			room_created.emit(code)
		FrameType.ROOM_ERR:
			var reason := pkt.slice(1).get_string_from_utf8()
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			room_error.emit(reason)
		FrameType.PEER_CONNECTED:
			if pkt.size() < 5:
				return
			var pid := pkt.decode_s32(1)
			emit_signal("peer_connected", pid)
		FrameType.PEER_DISCONNECTED:
			if pkt.size() < 5:
				return
			var pid2 := pkt.decode_s32(1)
			emit_signal("peer_disconnected", pid2)
		FrameType.DATA:
			if pkt.size() < 5:
				return
			var sender := pkt.decode_s32(1)
			var game_data := pkt.slice(5)
			_incoming.append({"sender": sender, "data": game_data})
		FrameType.ROOM_CLOSED:
			var close_reason := pkt.slice(1).get_string_from_utf8()
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			room_closed_by_relay.emit(close_reason)

func _get_available_packet_count() -> int:
	return _incoming.size()

func _get_max_packet_size() -> int:
	return 1 << 16

func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var entry: Dictionary = _incoming.pop_front()
	return entry["data"]

func _put_packet_script(p_buffer: PackedByteArray) -> int:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	var frame := PackedByteArray()
	frame.append(FrameType.DATA)
	var target_bytes := PackedByteArray()
	target_bytes.resize(4)
	target_bytes.encode_s32(0, _target_peer)
	frame.append_array(target_bytes)
	frame.append_array(p_buffer)
	return _ws.send(frame)

func _get_packet_channel() -> int:
	return 0

func _get_packet_mode() -> int:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE

func _get_transfer_channel() -> int:
	return _transfer_channel

func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = p_channel

func _get_transfer_mode() -> int:
	return _transfer_mode

func _set_transfer_mode(p_mode: int) -> void:
	_transfer_mode = p_mode

func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer

func _get_packet_peer() -> int:
	# ÖNEMLİ: bunu _get_packet_script()'ten BAĞIMSIZ, kuyruğun BAŞINDAKİ
	# paketten (henüz pop ETMEDEN, sadece bakarak) okuyoruz. Önceden
	# _get_packet_script() çağrılana kadar güncellenmeyen ayrı bir "son
	# gönderen" değişkeni tutuyorduk — Godot bu iki fonksiyonu her paket
	# için hangi sırayla çağırdığına bağlı olarak, gönderen bilgisi bir
	# paket GERİDEN gelebiliyordu (ör. B'nin isteği yanlışlıkla A'nın
	# göndericisi sanılabiliyordu). Artık ikisi tamamen bağımsız ve her
	# zaman kuyruğun aynı (ilk) elemanına bakıyor, sıra sorunu imkansız.
	if _incoming.is_empty():
		return 0
	return _incoming[0]["sender"]

func _is_server() -> bool:
	return _unique_id == 1

func _poll_ok() -> bool:
	return true

func _close() -> void:
	_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED

func _disconnect_peer(p_peer: int, p_force: bool) -> void:
	# Role sunucusu uzerinden tekil oyuncuyu atma su an desteklenmiyor;
	# host, oyuncuyu oyun mantigi seviyesinde (parti/lobi listesinden) cikarir.
	pass

func _get_unique_id() -> int:
	return _unique_id

func _set_refuse_new_connections(p_enable: bool) -> void:
	_refusing_new_connections = p_enable

func _is_refusing_new_connections() -> bool:
	return _refusing_new_connections

func _is_server_relay_supported() -> bool:
	return true

func _get_connection_status() -> int:
	return _status
