extends Node
## Autoload. Parti kurulum ekranındaki her oyuncunun kendi parti verisini
## (isim, ikon index'i, ikon rengi, arka plan rengi, ideoloji, hazır mı) tutar
## ve senkronize eder.
##
## Herkes SADECE KENDİ verisini değiştirebilir. MultiplayerManager'daki
## desenle aynı: host olmayan biri değişiklik isterse host'a "any_peer" RPC
## ile istek gönderir, host kendi göndereni doğrulayıp uygular ve herkese
## authority RPC ile yayınlar.
##
## Bir oyuncu "Kilitle ve Hazır Ver" dediğinde set_ready(true) çağrılır.
## HERKES hazır olduğunda (süre dolmamış olsa bile) host otomatik olarak
## MultiplayerManager.finish_party_setup() çağırıp oyunu başlatır.

signal parties_updated

const NAME_MIN_LENGTH := 2
const NAME_MAX_LENGTH := 11

# peer_id -> {
#   "name": String, "icon_index": int, "icon_color": Color, "bg_color": Color,
#   "ideology": {"economic": int, "social": int, "administrative": int},
#   "ready": bool,
# }
var parties: Dictionary = {}

func my_party() -> Dictionary:
	return parties.get(multiplayer.get_unique_id(), {})

func is_ready(peer_id: int) -> bool:
	return parties.get(peer_id, {}).get("ready", false)

## Odadaki HERKES (MultiplayerManager.players) hazır mı? Oda boşsa false döner.
func all_ready() -> bool:
	if MultiplayerManager.players.is_empty():
		return false
	for peer_id in MultiplayerManager.players.keys():
		if not is_ready(peer_id):
			return false
	return true

static func is_valid_name(party_name: String) -> bool:
	var length := party_name.length()
	return length >= NAME_MIN_LENGTH and length <= NAME_MAX_LENGTH

## İkon rengi ile arka plan rengi ASLA aynı olamaz — istemci tarafı bunu UI
## seviyesinde (taken renk butonları) engelliyor ama bir istemci tarafı gecikmesi/
## bug'ı yüzünden çakışan bir çift yine de gönderilirse, HOST burada son
## savunma hattı olarak reddeder (aksi hâlde ikon, arka planla aynı renkte
## görünmez olurdu — "arka plan rengi kabul olmuyor" gibi algılanabilir).
static func is_valid_colors(icon_color: Color, bg_color: Color) -> bool:
	return not icon_color.is_equal_approx(bg_color)

## Bu oyuncunun parti verisini ayarlar (isim/ikon/renk/ideoloji seçimi
## değiştikçe çağrılır). ideology: IdeologyAxes.is_valid_start_ideology()'yi
## geçmeli (kuruluşta uç/nötr yasak).
func set_my_party(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, ideology: Dictionary) -> void:
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not IdeologyAxes.is_valid_start_ideology(ideology):
		return
	if MultiplayerManager.room_code == "":
		# Aktif bir oda/bağlantı yok (örn. sahne editörde tek başına
		# çalıştırılıyor) — RPC atmadan sadece yerel önizlemeye izin ver.
		_apply_party_local_only(party_name, icon_index, icon_color, bg_color, ideology)
		return
	var my_id := multiplayer.get_unique_id()
	if MultiplayerManager.is_host:
		_apply_party(my_id, party_name, icon_index, icon_color, bg_color, ideology)
	else:
		_request_set_party.rpc_id(1, party_name, icon_index, icon_color, bg_color, ideology)

## Parti verisini ve hazır durumunu AYNI ANDA, TEK bir RPC ile ayarlar.
## "Kilitle ve Hazır Ver"e basınca kullanılmalı — set_my_party() sonra ayrı
## bir set_ready(true) çağrısı YAPMA: iki ayrı RPC arasında (özellikle
## hızlıca art arda basılırsa) host'un "hazır" bayrağını partinin SON
## değişikliği ulaşmadan uygulayıp oyunu erken başlatma riski olurdu — bu
## fonksiyon ikisini TEK mesajda birleştirerek bunu imkansız kılar.
func set_party_and_ready(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, ideology: Dictionary, is_ready_value: bool) -> void:
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not IdeologyAxes.is_valid_start_ideology(ideology):
		return
	if MultiplayerManager.room_code == "":
		_apply_party_local_only(party_name, icon_index, icon_color, bg_color, ideology)
		var id := multiplayer.get_unique_id()
		parties[id]["ready"] = is_ready_value
		parties_updated.emit()
		return
	var my_id := multiplayer.get_unique_id()
	if MultiplayerManager.is_host:
		_apply_party_and_ready(my_id, party_name, icon_index, icon_color, bg_color, ideology, is_ready_value)
	else:
		_request_set_party_and_ready.rpc_id(1, party_name, icon_index, icon_color, bg_color, ideology, is_ready_value)

## Bu oyuncunun hazır durumunu ayarlar ("Kilitle ve Hazır Ver" / iptal).
func set_ready(is_ready_value: bool) -> void:
	if MultiplayerManager.room_code == "":
		var id := multiplayer.get_unique_id()
		if not parties.has(id):
			parties[id] = {}
		parties[id]["ready"] = is_ready_value
		parties_updated.emit()
		return
	if MultiplayerManager.is_host:
		_apply_ready(multiplayer.get_unique_id(), is_ready_value)
	else:
		_request_set_ready.rpc_id(1, is_ready_value)

## Yeni bir parti kurulum turuna girerken (oyun başlarken) host çağırır.
func reset() -> void:
	if not MultiplayerManager.is_host:
		return
	parties.clear()
	_sync_parties.rpc(parties)
	parties_updated.emit()

## Oyun sırasında (kart oynanınca vb.) bir partinin ideoloji eksenini kaydırır.
## Sadece host çağırır (bkz. CardManager._apply_play). Oyun ortasında uç/nötr
## yasağı YOKTUR, sadece [-3, 3] aralığına sıkıştırılır.
func apply_ideology_delta(peer_id: int, axis: String, delta: int) -> void:
	# room_code == "" : aktif oda yok (örn. sahne editörde tek başına test) —
	# yerel önizleme için host kontrolünü atla.
	if MultiplayerManager.room_code != "" and not MultiplayerManager.is_host:
		return
	if not parties.has(peer_id):
		return
	var ideology: Dictionary = parties[peer_id].get("ideology", IdeologyAxes.default_values())
	var new_value: int = IdeologyAxes.clamp_value(int(ideology.get(axis, 0)) + delta)
	ideology[axis] = new_value
	parties[peer_id]["ideology"] = ideology
	if MultiplayerManager.room_code == "":
		parties_updated.emit()
		return
	_sync_parties.rpc(parties)
	parties_updated.emit()

func _apply_party_local_only(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, ideology: Dictionary) -> void:
	var id := multiplayer.get_unique_id()
	var was_ready: bool = parties.get(id, {}).get("ready", false)
	parties[id] = {
		"name": party_name,
		"icon_index": icon_index,
		"icon_color": icon_color,
		"bg_color": bg_color,
		"ideology": ideology,
		"ready": was_ready,
	}
	parties_updated.emit()

func _apply_party(peer_id: int, party_name: String, icon_index: int, icon_color: Color, bg_color: Color, ideology: Dictionary) -> void:
	var was_ready: bool = parties.get(peer_id, {}).get("ready", false)
	parties[peer_id] = {
		"name": party_name,
		"icon_index": icon_index,
		"icon_color": icon_color,
		"bg_color": bg_color,
		"ideology": ideology,
		"ready": was_ready,
	}
	_sync_parties.rpc(parties)
	parties_updated.emit()

func _apply_party_and_ready(peer_id: int, party_name: String, icon_index: int, icon_color: Color, bg_color: Color, ideology: Dictionary, is_ready_value: bool) -> void:
	parties[peer_id] = {
		"name": party_name,
		"icon_index": icon_index,
		"icon_color": icon_color,
		"bg_color": bg_color,
		"ideology": ideology,
		"ready": is_ready_value,
	}
	_sync_parties.rpc(parties)
	parties_updated.emit()
	if is_ready_value and all_ready():
		MultiplayerManager.finish_party_setup()

func _apply_ready(peer_id: int, is_ready_value: bool) -> void:
	if not parties.has(peer_id):
		parties[peer_id] = {}
	parties[peer_id]["ready"] = is_ready_value
	_sync_parties.rpc(parties)
	parties_updated.emit()
	if all_ready():
		MultiplayerManager.finish_party_setup()

@rpc("any_peer", "reliable")
func _request_set_party(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, ideology: Dictionary) -> void:
	if not MultiplayerManager.is_host:
		return
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not IdeologyAxes.is_valid_start_ideology(ideology):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_party(sender_id, party_name, icon_index, icon_color, bg_color, ideology)

@rpc("any_peer", "reliable")
func _request_set_ready(is_ready_value: bool) -> void:
	if not MultiplayerManager.is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_ready(sender_id, is_ready_value)

@rpc("any_peer", "reliable")
func _request_set_party_and_ready(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, ideology: Dictionary, is_ready_value: bool) -> void:
	if not MultiplayerManager.is_host:
		return
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not IdeologyAxes.is_valid_start_ideology(ideology):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_party_and_ready(sender_id, party_name, icon_index, icon_color, bg_color, ideology, is_ready_value)

@rpc("authority", "reliable")
func _sync_parties(new_parties: Dictionary) -> void:
	parties = new_parties
	parties_updated.emit()
