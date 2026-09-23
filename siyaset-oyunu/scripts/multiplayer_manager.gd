extends Node
## Autoload (singleton). Oda kurma/katılma, oyuncu listesi senkronizasyonu,
## lobi sahipliği devri, lobi ayarları (seçim barajı, parti kurma süresi) ve
## oyunu başlatma (herkesi Parti Kurulum sahnesine geçirme) mantığını yönetir.
##
## KURALLAR:
## - Oda kodu: 5 haneli, sadece büyük İngilizce harf (A-Z), rakam yok.
## - Lobi sahipliği başka bir oyuncuya devredilebilir; kod bundan etkilenmez,
##   aynı kalır.
## - Host OLMAYAN bir lobi sahibi ayrılırsa oda kapanmaz, sahiplik host'a
##   geçer. HOST ayrılırsa oda kapanır: tüm oyun durumu host'ta yaşadığı ve
##   röle sunucusu oyunu çalıştırmadığı için devralınamaz; herkes oda
##   ekranına sebebiyle birlikte döner.
## - Oyun başladıktan sonra odaya katılınamaz. Oyun sırasında ayrılan oyuncu
##   sıradan/meclisten/hükümet süreçlerinden çıkarılır (CardManager.remove_player).
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
## Bağlantı sürerken kullanıcıya gösterilecek ara bilgi (örn. sunucu uyanıyor).
signal connection_status(text: String)

## Varsayılan röle sunucusu. Kodu değiştirmeden başka bir sunucu kullanmak
## için (öncelik sırasıyla):
##   1. komut satırı:   godot -- --relay=wss://ornek.com
##   2. ortam değişkeni: SIYASET_RELAY_URL=wss://ornek.com
##   3. proje ayarı:     siyaset/network/relay_url
const DEFAULT_RELAY_URL := "wss://siyaset-oyunu-test-experimental.onrender.com"
const RELAY_KEEP_ALIVE_SEC := 240.0
const RELAY_URL_SETTING := "siyaset/network/relay_url"

enum Stage { LOBBY, PARTY_SETUP, IN_GAME }

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

# --- Eksen keskinliği: her kart oynanışında ideoloji kayması, giderek büyüyen
# bir çarpanla ölçeklenir (bkz. CardManager.current_axis_sharpness). Oyun
# başında AXIS_SHARPNESS_START_DEFAULT'tan başlar, her kartta
# AXIS_SHARPNESS_INCREMENT_DEFAULT kadar artar; "sınırlı" seçildiyse
# AXIS_SHARPNESS_CAP_OPTIONS'taki bir tavanda durur.
const AXIS_SHARPNESS_START_MIN := 0.5
const AXIS_SHARPNESS_START_MAX := 2.0
const AXIS_SHARPNESS_START_DEFAULT := 0.5
const AXIS_SHARPNESS_INCREMENT_MIN := 0.0
const AXIS_SHARPNESS_INCREMENT_MAX := 1.0
const AXIS_SHARPNESS_INCREMENT_DEFAULT := 0.125
## Keskinlik hiçbir ayarda 2'yi aşamaz (iller tek partiye kilitlenmesin).
const AXIS_SHARPNESS_HARD_MAX := 2.0
const AXIS_SHARPNESS_CAP_OPTIONS: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]
const AXIS_SHARPNESS_MAX_ENABLED_DEFAULT := true
const AXIS_SHARPNESS_MAX_VALUE_DEFAULT := 2.0

var room_code: String = ""
var is_host: bool = false
## ÇEVRİM DIŞI: ağ yok, oda kodu yok, sadece bu cihaz ve botlar.
var offline_mode: bool = false
var owner_id: int = 1
var local_player_name: String = "Oyuncu"
# peer_id -> {"name": String}
var players: Dictionary = {}

# --- Lobi ayarları (lobi sahibi yetkili, tüm oyunculara senkronize) ---
var election_threshold: float = THRESHOLD_DEFAULT
## Oyun süresi: seçimler kaç turda bir ve kaç seçim olacak (bkz. GameRules.configure).
var election_interval: int = GameRules.DEFAULT_ELECTION_INTERVAL
var election_count: int = GameRules.DEFAULT_ELECTION_COUNT
var axis_sharpness_start: float = AXIS_SHARPNESS_START_DEFAULT
var axis_sharpness_increment: float = AXIS_SHARPNESS_INCREMENT_DEFAULT
var axis_sharpness_max_enabled: bool = AXIS_SHARPNESS_MAX_ENABLED_DEFAULT
var axis_sharpness_max_value: float = AXIS_SHARPNESS_MAX_VALUE_DEFAULT

var _pending_code: String = ""
var _has_synced_once: bool = false
var _closing: bool = false
var _connect_error_reported: bool = false

## Sadece host'ta anlamlı: oda şu an hangi aşamada.
var stage: int = Stage.LOBBY
## Oda kapanınca sebebi; oda ekranı açılınca gösterilir.
var last_close_reason: String = ""

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	room_closed.connect(_on_room_closed_any)
	_wake_relay()
	# Ücretsiz sunucu ~15 dk boyunca yeni HTTP isteği gelmezse uykuya geçiyor;
	# WebSocket trafiği bunu engellemiyor ve oyun ortasında (~15. tur) bağlantı
	# kopuyordu. Odadayken birkaç dakikada bir HTTP isteğiyle uyanık tutulur.
	if DisplayServer.get_name() != "headless":
		var keep_alive := Timer.new()
		keep_alive.wait_time = RELAY_KEEP_ALIVE_SEC
		keep_alive.autostart = true
		keep_alive.timeout.connect(func():
			if room_code != "":
				_wake_relay())
		add_child(keep_alive)

## Oyun açılır açılmaz röle sunucusuna basit bir HTTP isteği atar. Ücretsiz
## sunucu kullanılmayınca uyuyor ve uyanması 30-60 sn sürüyor; oyuncu menüde
## adını girip "Oda Kur"a basana kadar sunucu büyük ölçüde uyanmış olur.
## Sonuç önemsiz (hata da olsa sessizce yok sayılır). Headless testlerde atlanır.
func _wake_relay() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var url := relay_url().replace("wss://", "https://").replace("ws://", "http://")
	var request := HTTPRequest.new()
	request.timeout = 90.0
	add_child(request)
	request.request_completed.connect(func(_result, _code, _headers, _body): request.queue_free())
	if request.request(url) != OK:
		request.queue_free()

static func relay_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--relay="):
			return arg.substr("--relay=".length())
	var env := OS.get_environment("SIYASET_RELAY_URL")
	if env != "":
		return env
	return str(ProjectSettings.get_setting(RELAY_URL_SETTING, DEFAULT_RELAY_URL))

## Oda nerede kapanırsa kapansın (oyun ekranı, parti kurulum, hükümet kurma…)
## oyuncu oda ekranına döner; eskiden sadece oda lobisi bunu dinlediği için
## oyun ortasında host ayrılınca diğerleri ölü bir ekranda kalıyordu.
func _on_room_closed_any(reason: String) -> void:
	last_close_reason = reason
	var scene := get_tree().current_scene
	var path: String = scene.scene_file_path if scene != null else ""
	if path in ["res://scenes/RoomLobby.tscn", "res://scenes/Lobby.tscn"]:
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/Lobby.tscn")

func _on_relay_connecting_slow() -> void:
	connection_status.emit("Sunucu uyanıyor olabilir (ücretsiz sunucu uykudan kalkarken ~1 dk sürebilir)…")

static func snap_threshold(value: float) -> float:
	value = clampf(value, THRESHOLD_MIN, THRESHOLD_MAX)
	return round(value / THRESHOLD_STEP) * THRESHOLD_STEP

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

## ÇEVRİM DIŞI MOD: röle sunucusu, oda kodu ve katılma yok. Ağ peer'i hiç
## kurulmaz; oyun tamamen bu cihazda döner (CardManager._is_local_only()
## zaten room_code == "" olduğunda yerel çalışır). Sadece bot eklenebilir.
func start_offline(player_name: String) -> void:
	_reset_state()
	offline_mode = true
	local_player_name = player_name if player_name != "" else "Oyuncu"
	# OfflineMultiplayerPeer: ağ yok ama bu instance "sunucu" sayılır, unique_id
	# 1 olur ve RPC'ler kimseye gitmez. Böylece host tarafındaki tüm yerel
	# mantık (bot ekleme, oyunu başlatma, CardManager) olduğu gibi çalışır.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = true
	room_code = ""
	election_threshold = THRESHOLD_DEFAULT
	election_interval = GameRules.DEFAULT_ELECTION_INTERVAL
	election_count = GameRules.DEFAULT_ELECTION_COUNT
	GameRules.configure(election_interval, election_count)
	axis_sharpness_start = AXIS_SHARPNESS_START_DEFAULT
	axis_sharpness_increment = AXIS_SHARPNESS_INCREMENT_DEFAULT
	axis_sharpness_max_enabled = AXIS_SHARPNESS_MAX_ENABLED_DEFAULT
	axis_sharpness_max_value = AXIS_SHARPNESS_MAX_VALUE_DEFAULT
	players.clear()
	owner_id = multiplayer.get_unique_id()
	players[owner_id] = {"name": local_player_name}
	player_list_updated.emit()
	room_created.emit("")

## Röle sunucusu üzerinden bir oda kurar (bu oyuncu host + lobi sahibi olur).
## Sonuç asenkrondur: başarılı olursa room_created(code), olmazsa
## connection_error(reason) sinyali yayınlanır.
func create_room(player_name: String) -> void:
	offline_mode = false
	local_player_name = player_name if player_name != "" else "Host"
	is_host = true
	room_code = ""
	_closing = false
	election_threshold = THRESHOLD_DEFAULT
	election_interval = GameRules.DEFAULT_ELECTION_INTERVAL
	election_count = GameRules.DEFAULT_ELECTION_COUNT
	GameRules.configure(election_interval, election_count)
	axis_sharpness_start = AXIS_SHARPNESS_START_DEFAULT
	axis_sharpness_increment = AXIS_SHARPNESS_INCREMENT_DEFAULT
	axis_sharpness_max_enabled = AXIS_SHARPNESS_MAX_ENABLED_DEFAULT
	axis_sharpness_max_value = AXIS_SHARPNESS_MAX_VALUE_DEFAULT
	players.clear()
	var peer := RelayMultiplayerPeerScript.new()
	_connect_error_reported = false
	peer.room_created.connect(_on_relay_room_created)
	peer.room_error.connect(_on_relay_error)
	peer.connecting_slow.connect(_on_relay_connecting_slow)
	# SceneMultiplayer, atama anında peer'in en azindan "connecting" durumunda
	# olmasini zorunlu tutuyor; o yuzden once baglanmayi baslatip (durumu
	# CONNECTING'e cekip) sonra multiplayer_peer'a atiyoruz.
	peer.start_create_room(relay_url(), local_player_name)
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
	if _connect_error_reported:
		return
	if is_host and room_code == "":
		_connect_error_reported = true
		multiplayer.multiplayer_peer = null
		is_host = false
		connection_error.emit(reason)
	elif not is_host and not _has_synced_once:
		_connect_error_reported = true
		multiplayer.multiplayer_peer = null
		join_failed.emit(reason)

## Röle sunucusu üzerinden, verilen 5 haneli oda koduna katılmayı dener.
func join_room(code: String, player_name: String) -> void:
	offline_mode = false
	local_player_name = player_name if player_name != "" else "Oyuncu"
	_pending_code = code.to_upper()
	room_code = _pending_code
	_has_synced_once = false
	_closing = false
	is_host = false
	var peer := RelayMultiplayerPeerScript.new()
	_connect_error_reported = false
	peer.room_error.connect(_on_relay_error)
	peer.connecting_slow.connect(_on_relay_connecting_slow)
	peer.start_join_room(relay_url(), _pending_code, local_player_name)
	multiplayer.multiplayer_peer = peer

## Oyuncu kendi isteğiyle odadan ayrılır. Ayrılan kişi lobi sahibiyse
## (host tarafında bu durum peer_disconnected ile algılanıp odanın tamamen
## kapatılmasına yol açar; bu fonksiyon sadece kendi bağlantımızı kapatır).
func leave_room() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	_reset_state()

## ESC menüsündeki "Oyundan Ayrıl": oyuncu odadan düzgünce çıkar ve ana menüye
## döner. Host OLMAYAN oyuncu ayrılınca host bunu peer_disconnected ile görür
## ve oyunu ona uyarlar (sıradan/meclisten/oylamadan/hükümetten çıkarır, bkz.
## CardManager.remove_player). HOST ayrılırsa oyun durumu onda yaşadığı için
## oda kapanır; diğerlerine önce sebep bildirilir.
func leave_game() -> void:
	if room_code != "" and is_host and multiplayer.multiplayer_peer != null:
		_closing = true
		_notify_room_closed.rpc("Oda sahibi oyundan ayrıldı, oda kapatıldı.")
		# RPC'nin ağa çıkması için birkaç kare bekle.
		for i in 3:
			await get_tree().process_frame
	leave_room()
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	# Eski oyun ekranı gittikten sonra yerel oyun durumunu temizle.
	await get_tree().process_frame
	await get_tree().process_frame
	CardManager.abandon_game()
	GovernmentManager.reset()
	PartyManager.parties = {}

# --- Botlar (sadece lobide, sahip ekler/çıkarır; host oynatır: BotManager) ---

## Gerçek peer id'leriyle çakışmasın diye çok büyük sayılardan geriye doğru.
const BOT_ID_BASE := 2000000000

func is_bot(peer_id: int) -> bool:
	return bool(players.get(peer_id, {}).get("bot", false))

func bot_ids() -> Array:
	var ids: Array = []
	for peer_id in players.keys():
		if is_bot(peer_id):
			ids.append(peer_id)
	return ids

## Lobi kartlarının sırası: önce insanlar (katılma sırasıyla), sonra botlar.
## Botlar varken bir oyuncu katılırsa botlar otomatik olarak bir sonraki
## karta kayar.
func lobby_order() -> Array:
	var humans: Array = []
	var bots: Array = []
	for peer_id in players.keys():
		if is_bot(peer_id):
			bots.append(peer_id)
		else:
			humans.append(peer_id)
	return humans + bots

func add_bot() -> void:
	if not is_local_owner():
		return
	if is_host or room_code == "":
		_apply_add_bot()
	else:
		_request_add_bot.rpc_id(1)

func remove_bot(peer_id: int) -> void:
	if not is_local_owner():
		return
	if is_host or room_code == "":
		_apply_remove_bot(peer_id)
	else:
		_request_remove_bot.rpc_id(1, peer_id)

func _apply_add_bot() -> void:
	if players.size() >= MAX_PLAYERS or stage != Stage.LOBBY:
		return
	players[_free_bot_id()] = {"name": "", "bot": true}
	_renumber_bots()
	_broadcast_player_list()

func _apply_remove_bot(peer_id: int) -> void:
	if not is_bot(peer_id) or stage != Stage.LOBBY:
		return
	players.erase(peer_id)
	_renumber_bots()
	_broadcast_player_list()

## Kullanılmayan en küçük bot id'si. Id'ler sabit kalır; görünen AD adaptiftir.
func _free_bot_id() -> int:
	var index := 1
	while players.has(BOT_ID_BASE - index):
		index += 1
	return BOT_ID_BASE - index

## BOT ADLARI ADAPTİF: botlar her zaman 1..N diye numaralanır. Bot 5 varken
## Bot 3 ve Bot 4 silinirse Bot 5, Bot 3 olur — arada boşluk kalmaz.
## Kullanıcının elle verdiği ad (parti kurma ekranı) varsa dokunulmaz.
func _renumber_bots() -> void:
	var index := 0
	for peer_id in players.keys():
		if not is_bot(peer_id):
			continue
		index += 1
		var entry: Dictionary = players[peer_id]
		var current := String(entry.get("name", ""))
		if current == "" or current.begins_with("Bot "):
			entry["name"] = "Bot %d" % index
			players[peer_id] = entry

## Lobiden oyuncu atma: sadece lobi sahibi, sadece LOBİ aşamasında ve kendisi
## dışında birini atabilir. Bot ise sadece listeden silinir; insan oyuncuya
## önce sebep bildirilir, sonra ağ bağlantısı kesilir.
func kick_player(peer_id: int) -> void:
	if not is_local_owner() or peer_id == owner_id or stage != Stage.LOBBY:
		return
	if is_bot(peer_id):
		remove_bot(peer_id)
		return
	if is_host:
		_apply_kick(peer_id)
	else:
		_request_kick.rpc_id(1, peer_id)

func _apply_kick(peer_id: int) -> void:
	if stage != Stage.LOBBY or peer_id == owner_id or not players.has(peer_id):
		return
	if is_bot(peer_id):
		_apply_remove_bot(peer_id)
		return
	players.erase(peer_id)
	_broadcast_player_list()
	if multiplayer.multiplayer_peer == null:
		return
	_notify_kicked.rpc_id(peer_id)
	# Bildirimin ağa çıkması için birkaç kare bekleyip bağlantıyı kesiyoruz.
	for i in 3:
		await get_tree().process_frame
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

@rpc("any_peer", "reliable")
func _request_kick(peer_id: int) -> void:
	if is_host and multiplayer.get_remote_sender_id() == owner_id:
		_apply_kick(peer_id)

@rpc("authority", "reliable")
func _notify_kicked() -> void:
	_reset_state()
	room_closed.emit("Oda sahibi seni lobiden çıkardı.")

func _broadcast_player_list() -> void:
	if room_code != "" and multiplayer.multiplayer_peer != null:
		_sync_player_list.rpc(players, owner_id, election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	player_list_updated.emit()

@rpc("any_peer", "reliable")
func _request_add_bot() -> void:
	if is_host and multiplayer.get_remote_sender_id() == owner_id:
		_apply_add_bot()

@rpc("any_peer", "reliable")
func _request_remove_bot(peer_id: int) -> void:
	if is_host and multiplayer.get_remote_sender_id() == owner_id:
		_apply_remove_bot(peer_id)

## Lobi sahipliği rolü — ağ host'u olup olmamasından BAĞIMSIZDIR.
func is_local_owner() -> bool:
	return multiplayer.get_unique_id() == owner_id

## Lobi sahipliğini başka bir oyuncuya devreder. Sadece mevcut sahip çağırabilir.
## Oda kodu bu işlemden ETKİLENMEZ, aynı kalır.
func transfer_ownership(new_owner_id: int) -> void:
	if not is_local_owner():
		return
	if not players.has(new_owner_id) or is_bot(new_owner_id):
		return
	if is_host:
		owner_id = new_owner_id
		_sync_player_list.rpc(players, owner_id, election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		player_list_updated.emit()
	else:
		_request_transfer_ownership.rpc_id(1, new_owner_id)

## ANAYASA DEĞİŞİKLİĞİ: meclis 2/3 çoğunlukla kabul ettiyse oyunun kuralları
## değişir. Lobi ayarından farkı: oyun İÇİNDE, oylamayla ve sahiplik aranmadan
## uygulanır (host yazar, herkese senkronlanır).
func apply_constitution(threshold: float, interval_years: int) -> void:
	var local_only := room_code == ""
	if not is_host and not local_only:
		return
	election_threshold = snap_threshold(threshold)
	election_interval = clampi(interval_years, GameRules.ELECTION_INTERVAL_MIN, GameRules.ELECTION_INTERVAL_MAX)
	GameRules.configure(election_interval, election_count)
	if not local_only:
		_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

## Seçim barajını (%) ayarlar. Sadece mevcut lobi sahibi çağırabilir.
## value 0-10 arasına ve 0.5'in katlarına yuvarlanır.
func set_election_threshold(value: float) -> void:
	if not is_local_owner():
		return
	var snapped := snap_threshold(value)
	if is_host:
		election_threshold = snapped
		_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_threshold.rpc_id(1, snapped)

## Oyun süresini ayarlar: seçimler kaç turda bir ve kaç seçim olacak. Sadece
## mevcut lobi sahibi çağırabilir.
func set_game_length(interval: int, count: int) -> void:
	if not is_local_owner():
		return
	interval = clampi(interval, GameRules.ELECTION_INTERVAL_MIN, GameRules.ELECTION_INTERVAL_MAX)
	count = clampi(count, GameRules.ELECTION_COUNT_MIN, GameRules.ELECTION_COUNT_MAX)
	if is_host:
		election_interval = interval
		election_count = count
		GameRules.configure(election_interval, election_count)
		_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
		settings_updated.emit()
	else:
		_request_set_game_length.rpc_id(1, interval, count)

## Eksen keskinliğinin başlangıç değerini ayarlar (0.5-5.0). Sadece mevcut
## lobi sahibi çağırabilir.
func set_axis_sharpness_start(value: float) -> void:
	if not is_local_owner():
		return
	var snapped := snap_axis_sharpness_start(value)
	if is_host:
		axis_sharpness_start = snapped
		_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
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
		_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
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
		_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
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
		_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
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
	offline_mode = false
	owner_id = 1
	election_threshold = THRESHOLD_DEFAULT
	election_interval = GameRules.DEFAULT_ELECTION_INTERVAL
	election_count = GameRules.DEFAULT_ELECTION_COUNT
	GameRules.configure(election_interval, election_count)
	axis_sharpness_start = AXIS_SHARPNESS_START_DEFAULT
	axis_sharpness_increment = AXIS_SHARPNESS_INCREMENT_DEFAULT
	axis_sharpness_max_enabled = AXIS_SHARPNESS_MAX_ENABLED_DEFAULT
	axis_sharpness_max_value = AXIS_SHARPNESS_MAX_VALUE_DEFAULT
	_has_synced_once = false
	_closing = false
	stage = Stage.LOBBY

# --- Bağlantı olayları -------------------------------------------------

func _on_connected_to_server() -> void:
	_request_join.rpc_id(1, _pending_code, local_player_name, network_signature())

## Ağ sürüm imzası = oyun sürümü. Godot RPC'leri SIRA NUMARASIYLA eşler; iki
## cihazda farklı sürüm varsa istemcinin istekleri sunucuda yanlış fonksiyona
## gider ya da sessizce düşer. Katılırken karşılaştırılır; her derlemede sürüm
## artırıldığı için farklı derlemeler asla eşleşmez.
func network_signature() -> String:
	return game_version()

## Oyun sürümü (project.godot: application/config/version). Her yeni derlemede
## son rakam 1 artırılır (0.0.1, 0.0.2, ...); Android version/name ile aynı tutulur.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## Röle peer'ı aynı hatayı room_error ile de bildirebilir; kullanıcıya tek
## mesaj gitsin, ve oda KURARKEN düşen bağlantı "katılma" hatası sanılmasın.
func _on_connection_failed() -> void:
	if _connect_error_reported:
		return
	_connect_error_reported = true
	var hosting := is_host
	multiplayer.multiplayer_peer = null
	if hosting:
		is_host = false
		connection_error.emit("Sunucuya ulaşılamadı.")
	else:
		join_failed.emit("Sunucuya ulaşılamadı.")

func _on_server_disconnected() -> void:
	_reset_state()
	room_closed.emit("Sunucu (oda sahibi) bağlantıyı kapattı.")

func _on_peer_disconnected(id: int) -> void:
	if not is_host or _closing:
		return
	var was_player := players.has(id)
	players.erase(id)
	if id == owner_id:
		# Host olmayan lobi sahibi ayrıldı: oda kapanmaz, sahiplik host'a geçer.
		owner_id = multiplayer.get_unique_id()
	_sync_player_list.rpc(players, owner_id, election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	player_list_updated.emit()
	if not was_player:
		return
	match stage:
		Stage.PARTY_SETUP:
			# Ayrılan kişi "hazır" bekleniyordu; kalanların hepsi hazırsa başla.
			if PartyManager.all_ready():
				finish_party_setup()
		Stage.IN_GAME:
			CardManager.remove_player(id)

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
	stage = Stage.PARTY_SETUP
	PartyManager.reset()
	for bot in bot_ids():
		PartyManager.add_bot_party(bot)
	_notify_game_start.rpc()
	game_started.emit()

## Sadece host çağırır (Parti Kurulum ekranındaki geri sayım host'ta bitince):
## herkesi Oyun Ekranı'na geçirir.
func finish_party_setup() -> void:
	# Aşama kontrolü: süre dolması, son "hazır" ve bir oyuncunun ayrılması aynı
	# anda olursa oyun iki kez başlatılmasın.
	if not is_host or stage != Stage.PARTY_SETUP:
		return
	stage = Stage.IN_GAME
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
func _request_join(code: String, player_name: String, signature: String) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if signature != network_signature():
		_join_rejected.rpc_id(sender_id, "Oyun sürümleri farklı (sen %s, oda %s). İki cihazda da aynı güncel sürümü kullanın." % [
			signature, game_version()])
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if code != room_code:
		_join_rejected.rpc_id(sender_id, "Kod hatalı.")
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if players.size() >= MAX_PLAYERS and (bot_ids().is_empty() or stage != Stage.LOBBY):
		_join_rejected.rpc_id(sender_id, "Oda dolu.")
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if stage != Stage.LOBBY:
		_join_rejected.rpc_id(sender_id, "Bu odada oyun zaten başladı.")
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	# Oda botlarla doluysa en son eklenen bot insan oyuncuya yer açar.
	if players.size() >= MAX_PLAYERS:
		players.erase(bot_ids().back())
	players[sender_id] = {"name": player_name}
	_sync_player_list.rpc(players, owner_id, election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	player_list_updated.emit()

@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit(reason)

@rpc("authority", "reliable")
func _sync_player_list(new_players: Dictionary, new_owner: int, threshold: float, interval: int, count: int, axis_start: float, axis_increment: float, axis_max_enabled: bool, axis_max_value: float) -> void:
	players = new_players
	owner_id = new_owner
	election_threshold = threshold
	election_interval = interval
	election_count = count
	GameRules.configure(election_interval, election_count)
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
	if sender_id != owner_id or not players.has(new_owner_id) or is_bot(new_owner_id):
		return
	owner_id = new_owner_id
	_sync_player_list.rpc(players, owner_id, election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
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
	_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

## Host-olmayan mevcut sahip, oyun süresini değiştirmek istediğinde host'a istek yollar.
@rpc("any_peer", "reliable")
func _request_set_game_length(interval: int, count: int) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	election_interval = clampi(interval, GameRules.ELECTION_INTERVAL_MIN, GameRules.ELECTION_INTERVAL_MAX)
	election_count = clampi(count, GameRules.ELECTION_COUNT_MIN, GameRules.ELECTION_COUNT_MAX)
	GameRules.configure(election_interval, election_count)
	_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
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
	_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_axis_sharpness_increment(value: float) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	axis_sharpness_increment = snap_axis_sharpness_increment(value)
	_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_axis_sharpness_max_enabled(enabled: bool) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	axis_sharpness_max_enabled = enabled
	_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_axis_sharpness_max_value(value: float) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	axis_sharpness_max_value = snap_axis_sharpness_max_value(value)
	_sync_settings.rpc(election_threshold, election_interval, election_count, axis_sharpness_start, axis_sharpness_increment, axis_sharpness_max_enabled, axis_sharpness_max_value)
	settings_updated.emit()

@rpc("authority", "reliable")
func _sync_settings(threshold: float, interval: int, count: int, axis_start: float, axis_increment: float, axis_max_enabled: bool, axis_max_value: float) -> void:
	election_threshold = threshold
	election_interval = interval
	election_count = count
	GameRules.configure(election_interval, election_count)
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
