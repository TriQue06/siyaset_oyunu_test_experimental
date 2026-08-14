extends Node
## Autoload (singleton). Oda kurma/katılma, oyuncu listesi senkronizasyonu,
## lobi sahipliği devri, lobi ayarları (seçim barajı, parti kurma süresi) ve
## oyunu başlatma (herkesi Parti Kurulum sahnesine geçirme) mantığını yönetir.
##
## KURALLAR:
## - Oda kodu: 5 haneli, sadece büyük İngilizce harf (A-Z), rakam yok.
## - Lobi sahipliği başka bir oyuncuya devredilebilir; kod bundan etkilenmez,
##   aynı kalır.
## - O ANKİ lobi sahibi odadan ayrılırsa (bağlantısı kesilirse) oda TAMAMEN
##   kapanır ve içindeki herkes (host dahil) odadan çıkarılır.
## - "is_host" = bu instance'ın ENet SUNUCUSU olması (her zaman ilk kurucu,
##   peer id 1). "owner_id" = LOBİ SAHİBİ rolü — devredilebilir, host'tan
##   BAĞIMSIZ bir kavramdır (devredilirse host olmayan bir istemci sahip
##   olabilir). Sadece host, ağ üzerinden gerçek yayın (authority RPC)
##   yapabildiği için, host-olmayan bir sahibin ayar değiştirmesi/sahiplik
##   devretmesi/oyunu başlatması gibi işlemler önce host'a "any_peer" RPC ile
##   İSTEK olarak gider, host isteği sahiplik kontrolünden geçirip uygular ve
##   sonra authority RPC ile herkese yayınlar.
##
## Bağlantı, CGNAT / statik IP olmayan oyuncular için de çalışsın diye ham
## ENet yerine internete açık bir WebSocket RÖLE sunucusu (relay-server/)
## üzerinden kuruluyor (bkz. scripts/relay_multiplayer_peer.gd). Host ve
## katılan herkes bu ortak röle adresine bağlanır; oda kodu eşleştirmeyi
## sunucu tarafında yapar, IP bilmeye gerek kalmaz.

signal room_created(code: String)
signal join_failed(reason: String)
signal connection_error(reason: String)
signal join_succeeded
signal player_list_updated
signal room_closed(reason: String)
signal settings_updated
signal game_started
signal party_setup_finished

## Röle sunucusunun adresi. relay-server/ deploy edildikten sonra buradaki
## adresi gerçek deploy URL'i ile değiştir (örn. "wss://<servis-adin>.onrender.com").
const RELAY_URL := "wss://siyaset-oyunu-test-experimental.onrender.com"

const RelayMultiplayerPeerScript := preload("res://scripts/relay_multiplayer_peer.gd")

const MAX_PLAYERS := 8
## TEST AMAÇLI 2'ye düşürüldü (tasarım gereği asıl değer 3). Tek başına
## birden fazla instance açıp hızlı deneme yapabilmek için — yayına
## alınmadan önce tekrar 3 yapılmalı.
const MIN_PLAYERS_TO_START := 2

const THRESHOLD_MIN := 0.0
const THRESHOLD_MAX := 10.0
const THRESHOLD_STEP := 0.5
const THRESHOLD_DEFAULT := 0.0

# Parti kurulum süresi seçenekleri (saniye). 0 = SINIRSIZ (süre yok, sadece
# herkes hazır verince başlar). Sadece bu değerler geçerlidir.
const PARTY_DURATION_OPTIONS: Array[int] = [0, 30, 60, 90, 120]
const PARTY_DURATION_UNLIMITED := 0
const PARTY_DURATION_DEFAULT := PARTY_DURATION_UNLIMITED

# --- Eksen keskinliği: her kart oynanışında ideoloji kayması, giderek büyüyen
# bir çarpanla ölçeklenir (bkz. CardManager.current_axis_sharpness). Oyun
# başında AXIS_SHARPNESS_START_DEFAULT'tan başlar, her kartta
# AXIS_SHARPNESS_INCREMENT_DEFAULT kadar artar; "sınırlı" seçildiyse
# AXIS_SHARPNESS_CAP_OPTIONS'taki bir tavanda durur.
const AXIS_SHARPNESS_START_MIN := 0.5
const AXIS_SHARPNESS_START_MAX := 5.0
const AXIS_SHARPNESS_START_DEFAULT := 0.5
const AXIS_SHARPNESS_INCREMENT_MIN := 0.0
const AXIS_SHARPNESS_INCREMENT_MAX := 1.0
const AXIS_SHARPNESS_INCREMENT_DEFAULT := 0.25
const AXIS_SHARPNESS_CAP_OPTIONS: Array[float] = [5.0, 10.0, 15.0, 20.0, 25.0]
const AXIS_SHARPNESS_MAX_ENABLED_DEFAULT := false
const AXIS_SHARPNESS_MAX_VALUE_DEFAULT := 10.0

var room_code: String = ""
var is_host: bool = false
var owner_id: int = 1
var local_player_name: String = "Oyuncu"
# peer_id -> {"name": String}
var players: Dictionary = {}

# --- Lobi ayarları (lobi sahibi yetkili, tüm oyunculara senkronize) ---
var election_threshold: float = THRESHOLD_DEFAULT
var party_setup_duration: int = PARTY_DURATION_DEFAULT
var axis_sharpness_start: float = AXIS_SHARPNESS_START_DEFAULT
var axis_sharpness_increment: float = AXIS_SHARPNESS_INCREMENT_DEFAULT
var axis_sharpness_max_enabled: bool = AXIS_SHARPNESS_MAX_ENABLED_DEFAULT
var axis_sharpness_max_value: float = AXIS_SHARPNESS_MAX_VALUE_DEFAULT

var _pending_code: String = ""
var _has_synced_once: bool = false
var _closing: bool = false

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

static func snap_threshold(value: float) -> float:
	value = clampf(value, THRESHOLD_MIN, THRESHOLD_MAX)
	return round(value / THRESHOLD_STEP) * THRESHOLD_STEP

static func snap_party_duration(value: int) -> int:
	var closest: int = PARTY_DURATION_OPTIONS[0]
	for option in PARTY_DURATION_OPTIONS:
		if abs(option - value) < abs(closest - value):
			closest = option
	return closest

static func snap_axis_sharpness_start(value: float) -> float:
	return clampf(value, AXIS_SHARPNESS_START_MIN, AXIS_SHARPNESS_START_MAX)

static func snap_axis_sharpness_increment(value: float) -> float:
	return clampf(value, AXIS_SHARPNESS_INCREMENT_MIN, AXIS_SHARPNESS_INCREMENT_MAX)

static func snap_axis_sharpness_max_value(value: float) -> float:
	var closest: float = AXIS_SHARPNESS_CAP_OPTIONS[0]
	for option in AXIS_SHARPNESS_CAP_OPTIONS:
		if absf(option - value) < absf(closest - value):
			closest = option
	return closest

## Röle sunucusu üzerinden bir oda kurar (bu oyuncu host + lobi sahibi olur).
## Sonuç asenkrondur: başarılı olursa room_created(code), olmazsa
## connection_error(reason) sinyali yayınlanır.
func create_room(player_name: String) -> void:
	local_player_name = player_name if player_name != "" else "Host"
	is_host = true
	room_code = ""
	_closing = false
	election_threshold = THRESHOLD_DEFAULT
	party_setup_duration = PARTY_DURATION_DEFAULT
	axis_sharpness_start = AXIS_SHARPNESS_START_DEFAULT
	axis_sharpness_increment = AXIS_SHARPNESS_INCREMENT_DEFAULT
	axis_sharpness_max_enabled = AXIS_SHARPNESS_MAX_ENABLED_DEFAULT
	axis_sharpness_max_value = AXIS_SHARPNESS_MAX_VALUE_DEFAULT
	players.clear()
	var peer := RelayMultiplayerPeerScript.new()
	peer.room_created.connect(_on_relay_room_created)
	peer.room_error.connect(_on_relay_error)
	# SceneMultiplayer, atama anında peer'in en azindan "connecting" durumunda
	# olmasini zorunlu tutuyor; o yuzden once baglanmayi baslatip (durumu
	# CONNECTING'e cekip) sonra multiplayer_peer'a atiyoruz.
	peer.start_create_room(RELAY_URL, local_player_name)
	multiplayer.multiplayer_peer = peer

func _on_relay_room_created(code: String) -> void:
	if not is_host or room_code != "":
		return
	room_code = code
	owner_id = multiplayer.get_unique_id()
	players[owner_id] = {"name": local_player_name}
	room_created.emit(room_code)
	player_list_updated.emit()

func _on_relay_error(reason: String) -> void:
	if is_host and room_code == "":
		multiplayer.multiplayer_peer = null
		is_host = false
		connection_error.emit(reason)
	elif not is_host and not _has_synced_once:
		multiplayer.multiplayer_peer = null
		join_failed.emit(reason)

## Röle sunucusu üzerinden, verilen 5 haneli oda koduna katılmayı dener.
func join_room(code: String, player_name: String) -> void:
	local_player_name = player_name if player_name != "" else "Oyuncu"
	_pending_code = code.to_upper()
	room_code = _pending_code
	_has_synced_once = false
	_closing = false
	is_host = false
	var peer := RelayMultiplayerPeerScript.new()
	peer.room_error.connect(_on_relay_error)
	peer.start_join_room(RELAY_URL, _pending_code, local_player_name)
	multiplayer.multiplayer_peer = peer

## Oyuncu kendi isteğiyle odadan ayrılır. Ayrılan kişi lobi sahibiyse
## (host tarafında bu durum peer_disconnected ile algılanıp odanın tamamen
## kapatılmasına yol açar; bu fonksiyon sadece kendi bağlantımızı kapatır).
func leave_room() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	_reset_state()

## Lobi sahipliği rolü — ağ host'u olup olmamasından BAĞIMSIZDIR.
func is_local_owner() -> bool:
	return multiplayer.get_unique_id() == owner_id

## Lobi sahipliğini başka bir oyuncuya devreder. Sadece mevcut sahip çağırabilir.
## Oda kodu bu işlemden ETKİLENMEZ, aynı kalır.
func transfer_ownership(new_owner_id: int) -> void:
	if not is_local_owner():
		return
	if not players.has(new_owner_id):
		return
	if is_host:
		owner_id = new_owner_id
		_sync_player_list.rpc(players, owner_id, election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		player_list_updated.emit()
	else:
		_request_transfer_ownership.rpc_id(1, new_owner_id)

## Seçim barajını (%) ayarlar. Sadece mevcut lobi sahibi çağırabilir.
## value 0-10 arasına ve 0.5'in katlarına yuvarlanır.
func set_election_threshold(value: float) -> void:
	if not is_local_owner():
		return
	var snapped := snap_threshold(value)
	if is_host:
		election_threshold = snapped
		_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_threshold.rpc_id(1, snapped)

## Parti kurulum süresini (saniye) ayarlar. Sadece mevcut lobi sahibi çağırabilir.
## Değer PARTY_DURATION_OPTIONS içindeki en yakın seçeneğe yuvarlanır.
func set_party_setup_duration(value: int) -> void:
	if not is_local_owner():
		return
	var snapped := snap_party_duration(value)
	if is_host:
		party_setup_duration = snapped
		_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_party_duration.rpc_id(1, snapped)

## Eksen keskinliğinin başlangıç değerini ayarlar (0.5-5.0). Sadece mevcut
## lobi sahibi çağırabilir.
func set_axis_sharpness_start(value: float) -> void:
	if not is_local_owner():
		return
	var snapped := snap_axis_sharpness_start(value)
	if is_host:
		axis_sharpness_start = snapped
		_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_axis_sharpness_start.rpc_id(1, snapped)

## Eksen keskinliğinin her kartta artış miktarını ayarlar (0.0-1.0). Sadece
## mevcut lobi sahibi çağırabilir.
func set_axis_sharpness_increment(value: float) -> void:
	if not is_local_owner():
		return
	var snapped := snap_axis_sharpness_increment(value)
	if is_host:
		axis_sharpness_increment = snapped
		_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_axis_sharpness_increment.rpc_id(1, snapped)

## Eksen keskinliğinin bir tavanı olup olmayacağını (sınırlı/sınırsız) ayarlar.
## Sadece mevcut lobi sahibi çağırabilir.
func set_axis_sharpness_max_enabled(enabled: bool) -> void:
	if not is_local_owner():
		return
	if is_host:
		axis_sharpness_max_enabled = enabled
		_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_axis_sharpness_max_enabled.rpc_id(1, enabled)

## Eksen keskinliği "sınırlı" iken kullanılacak tavan değerini ayarlar
## (5/10/15/20/25). Sadece mevcut lobi sahibi çağırabilir.
func set_axis_sharpness_max_value(value: float) -> void:
	if not is_local_owner():
		return
	var snapped := snap_axis_sharpness_max_value(value)
	if is_host:
		axis_sharpness_max_value = snapped
		_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_axis_sharpness_max_value.rpc_id(1, snapped)

## Oyunu başlatır: herkesi Parti Kurulum ekranına geçirir. Sadece mevcut lobi
## sahibi çağırabilir; en az MIN_PLAYERS_TO_START oyuncu gerekir.
func start_game() -> void:
	if not is_local_owner():
		return
	if players.size() < MIN_PLAYERS_TO_START:
		return
	if is_host:
		_broadcast_game_start()
	else:
		_request_start_game.rpc_id(1)

func _reset_state() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	room_code = ""
	is_host = false
	owner_id = 1
	election_threshold = THRESHOLD_DEFAULT
	party_setup_duration = PARTY_DURATION_DEFAULT
	axis_sharpness_start = AXIS_SHARPNESS_START_DEFAULT
	axis_sharpness_increment = AXIS_SHARPNESS_INCREMENT_DEFAULT
	axis_sharpness_max_enabled = AXIS_SHARPNESS_MAX_ENABLED_DEFAULT
	axis_sharpness_max_value = AXIS_SHARPNESS_MAX_VALUE_DEFAULT
	_has_synced_once = false
	_closing = false

# --- Bağlantı olayları -------------------------------------------------

func _on_connected_to_server() -> void:
	_request_join.rpc_id(1, _pending_code, local_player_name)

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit("Sunucuya ulaşılamadı.")

func _on_server_disconnected() -> void:
	_reset_state()
	room_closed.emit("Sunucu (oda sahibi) bağlantıyı kapattı.")

func _on_peer_disconnected(id: int) -> void:
	if not is_host or _closing:
		return
	if id == owner_id:
		# Lobi sahibi ayrıldı: oda herkes için tamamen kapanır.
		_close_room("Oda sahibi ayrıldı, oda kapatıldı.")
		return
	if players.has(id):
		players.erase(id)
	_sync_player_list.rpc(players, owner_id, election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	player_list_updated.emit()

## Sadece host çağırır: tüm istemcileri bilgilendirip sunucuyu kapatır.
func _close_room(reason: String) -> void:
	if _closing:
		return
	_closing = true
	_notify_room_closed.rpc(reason)
	# RPC'nin ağa gitmesi için bir kaç frame bekleyip sonra sunucuyu kapatıyoruz.
	await get_tree().process_frame
	await get_tree().process_frame
	_reset_state()
	room_closed.emit(reason)

## Sadece host çağırır: parti verilerini sıfırlayıp herkesi oyuna başlatır.
func _broadcast_game_start() -> void:
	PartyManager.reset()
	_notify_game_start.rpc()
	game_started.emit()

## Sadece host çağırır (Parti Kurulum ekranındaki geri sayım host'ta bitince):
## herkesi Oyun Ekranı'na geçirir.
func finish_party_setup() -> void:
	if not is_host:
		return
	CardManager.init_game()
	_notify_party_setup_finished.rpc()
	party_setup_finished.emit()

@rpc("authority", "reliable")
func _notify_party_setup_finished() -> void:
	if is_host:
		return
	party_setup_finished.emit()

# --- RPC'ler -------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_join(code: String, player_name: String) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if code != room_code:
		_join_rejected.rpc_id(sender_id, "Kod hatalı.")
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if players.size() >= MAX_PLAYERS:
		_join_rejected.rpc_id(sender_id, "Oda dolu.")
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	players[sender_id] = {"name": player_name}
	_sync_player_list.rpc(players, owner_id, election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	player_list_updated.emit()

@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit(reason)

@rpc("authority", "reliable")
func _sync_player_list(new_players: Dictionary, new_owner: int, threshold: float, duration: int, axis_start: float, axis_increment: float, axis_max_enabled: bool, axis_max_value: float) -> void:
	players = new_players
	owner_id = new_owner
	election_threshold = threshold
	party_setup_duration = duration
	axis_sharpness_start = axis_start
	axis_sharpness_increment = axis_increment
	axis_sharpness_max_enabled = axis_max_enabled
	axis_sharpness_max_value = axis_max_value
	if not is_host and not _has_synced_once:
		_has_synced_once = true
		join_succeeded.emit()
	player_list_updated.emit()

## Host-olmayan mevcut sahip, sahipliği devretmek istediğinde host'a istek yollar.
@rpc("any_peer", "reliable")
func _request_transfer_ownership(new_owner_id: int) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_id or not players.has(new_owner_id):
		return
	owner_id = new_owner_id
	_sync_player_list.rpc(players, owner_id, election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	player_list_updated.emit()

## Host-olmayan mevcut sahip, baraj değiştirmek istediğinde host'a istek yollar.
@rpc("any_peer", "reliable")
func _request_set_threshold(value: float) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_id:
		return
	election_threshold = snap_threshold(value)
	_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

## Host-olmayan mevcut sahip, parti kurulum süresini değiştirmek istediğinde
## host'a istek yollar.
@rpc("any_peer", "reliable")
func _request_set_party_duration(value: int) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_id:
		return
	party_setup_duration = snap_party_duration(value)
	_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

## Host-olmayan mevcut sahip, eksen keskinliği ayarlarından birini değiştirmek
## istediğinde host'a istek yollar.
@rpc("any_peer", "reliable")
func _request_set_axis_sharpness_start(value: float) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	axis_sharpness_start = snap_axis_sharpness_start(value)
	_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_axis_sharpness_increment(value: float) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	axis_sharpness_increment = snap_axis_sharpness_increment(value)
	_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_axis_sharpness_max_enabled(enabled: bool) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	axis_sharpness_max_enabled = enabled
	_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_axis_sharpness_max_value(value: float) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	axis_sharpness_max_value = snap_axis_sharpness_max_value(value)
	_sync_settings.rpc(election_threshold, party_setup_duration, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("authority", "reliable")
func _sync_settings(threshold: float, duration: int, axis_start: float, axis_increment: float, axis_max_enabled: bool, axis_max_value: float) -> void:
	election_threshold = threshold
	party_setup_duration = duration
	axis_sharpness_start = axis_start
	axis_sharpness_increment = axis_increment
	axis_sharpness_max_enabled = axis_max_enabled
	axis_sharpness_max_value = axis_max_value
	settings_updated.emit()

## Host-olmayan mevcut sahip, oyunu başlatmak istediğinde host'a istek yollar.
@rpc("any_peer", "reliable")
func _request_start_game() -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_id:
		return
	if players.size() < MIN_PLAYERS_TO_START:
		return
	_broadcast_game_start()

## Host'tan istemcilere: oyun başlıyor, Parti Kurulum ekranına geç.
@rpc("authority", "reliable")
func _notify_game_start() -> void:
	if is_host:
		return
	game_started.emit()

## Host'tan istemcilere: oda kapatılıyor, herkes lobiden çıkmalı.
@rpc("authority", "reliable")
func _notify_room_closed(reason: String) -> void:
	if is_host:
		return
	_reset_state()
	room_closed.emit(reason)
