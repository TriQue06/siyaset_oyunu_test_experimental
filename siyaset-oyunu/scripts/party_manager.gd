extends Node
## Autoload. Parti kurulum ekranındaki her oyuncunun kendi parti verisini
## (isim, ikon index'i, ikon rengi, arka plan rengi, çekirdek seçmen grupları,
## hazır mı) tutar
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

const NAME_MIN_LENGTH := 1
const NAME_MAX_LENGTH := 15

# peer_id -> {
#   "name": String, "icon_index": int, "icon_color": Color, "bg_color": Color,
#   "core": Array[String] (kuruluşta seçilen 2 çekirdek seçmen grubu),
#   "groups": {grup_id: 0..100} (8 seçmen grubundaki ULUSAL yakınlık; bkz. VoterGroups),
#   "ready": bool,
# }
var parties: Dictionary = {}
## SİYASETÇİLER (oyuncu başına, partiden bağımsız): peer_id -> PoliticianPresets
## sözlüğü. Oyuncu başka partiye katılsa da, partisini feshetse de siyasetçisi
## burada kalır (bkz. PoliticianPresets.of).
var politicians: Dictionary = {}
## Bu cihazdaki oyuncunun siyasetçisi (profil ekranında seçilir).
var my_politician: Dictionary = {}
## Her yayında artar; istemci heartbeat'te farklı görürse tam durumu ister
## (bkz. CardManager._heartbeat).
var state_version: int = 0

## Bu renk (arka plan) başka bir partide mi? Varsa sahibinin peer_id'si, yoksa -1.
func color_owner(color: Color, except_peer: int = 0) -> int:
	for peer_id in parties.keys():
		if int(peer_id) == except_peer:
			continue
		if Color(parties[peer_id].get("bg_color", Color.TRANSPARENT)).is_equal_approx(color):
			return int(peer_id)
	return -1

## Renk başkasındaysa kullanılamaz. İstisna: sahibi bot ise bot başka boş bir
## renge geçer (botlar oyuncularla aynı rengi alamaz, oyuncu önceliklidir).
func _claim_color(peer_id: int, color: Color) -> bool:
	var owner := color_owner(color, peer_id)
	if owner == -1:
		return true
	if not MultiplayerManager.is_bot(owner) or MultiplayerManager.is_bot(peer_id):
		return false
	parties[owner]["bg_color"] = _free_color(color, owner)
	return true

## Rengini oyuncuya kaptıran botun yeni rengi: alınan renge ve diğer bütün
## partilerin renklerine yakın olmayan rastgele bir palet rengi.
func _free_color(also_avoid: Color, bot_id: int) -> Color:
	var avoid: Array = [also_avoid]
	for peer_id in parties.keys():
		if int(peer_id) != bot_id and parties[peer_id].has("bg_color"):
			avoid.append(Color(parties[peer_id]["bg_color"]))
	return _pick_distinct_color(avoid)

# --- PARTİ ÜYELİĞİ -------------------------------------------------------------------
## Bir PARTİ, genel başkanının peer_id'siyle tutulur (anahtar = genel başkan).
## Partide en fazla bir YARDIMCI daha olabilir: parties[pid]["deputy"] = peer_id.
## BAĞIMSIZ siyasetçi de tek kişilik bir kayıttır: parties[pid]["independent"].
## Fesihte sahipsiz kalan vekiller BLOC_ID anahtarlı "Bağımsızlar" kaydında
## durur (oyuncusu yok, seçime girmez; bir sonraki seçimde kaybolur).
const BLOC_ID := -2
const MAX_MEMBERS := 2

## Bu oyuncunun (ya da parti anahtarının) partisi. Kaydı olmayan peer kendisi
## sayılır (testler ve eski kayıtlar parti tablosu olmadan çalışır).
func party_of(peer_id: int) -> int:
	# -1 ("kimse": sistem mesajı vb.) hiçbir partiye ait değildir. Yardımcısı
	# olmayan parti için "deputy" anahtarı yoktur; -1 ile eşleşmemeli.
	if peer_id < 0 or parties.has(peer_id):
		return peer_id
	for pid in parties.keys():
		if parties[pid].has("deputy") and int(parties[pid]["deputy"]) == peer_id:
			return int(pid)
	return peer_id

## Oyuncunun ya da partinin parti verisi (yardımcı için genel başkanın partisi).
func data_of(peer_id: int) -> Dictionary:
	return parties.get(party_of(peer_id), {})

## Partinin üyeleri: [genel başkan, (yardımcı)]. Bağımsızlar bloğunun üyesi yok.
func members_of(pid: int) -> Array:
	if pid == BLOC_ID or not parties.has(pid):
		return [] if pid == BLOC_ID else [pid]
	var deputy := int(parties[pid].get("deputy", -1))
	return [pid] if deputy == -1 else [pid, deputy]

func member_count(pid: int) -> int:
	return maxi(1, members_of(pid).size())

func deputy_of(pid: int) -> int:
	return int(parties.get(pid, {}).get("deputy", -1))

func is_leader(peer_id: int) -> bool:
	return parties.has(peer_id) and peer_id != BLOC_ID

func is_deputy(peer_id: int) -> bool:
	return party_of(peer_id) != peer_id

func is_independent(pid: int) -> bool:
	return bool(parties.get(party_of(pid), {}).get("independent", false))

func is_bloc(pid: int) -> bool:
	return pid == BLOC_ID

## Aynı partide mi? (Bir oyuncu kendisiyle de aynı partidedir.)
func same_party(a: int, b: int) -> bool:
	return party_of(a) == party_of(b)

## Host: parti kayıtlarını yayınlar (CardManager'daki parti işlemleri sonrası).
func broadcast() -> void:
	if MultiplayerManager.room_code != "" and MultiplayerManager.is_host:
		_broadcast_parties()
	parties_updated.emit()

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

## Bu oyuncunun parti verisini ayarlar (isim/ikon/renk/çekirdek grup seçimi
## değiştikçe çağrılır). core: VoterGroups.is_valid_core()'u geçmeli (farklı
## çiftlerden 2 grup).
func set_my_party(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, core: Array) -> void:
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not VoterGroups.is_valid_core(core):
		return
	if MultiplayerManager.is_standalone_preview():
		# Aktif bir oyun yok (örn. sahne editörde tek başına çalıştırılıyor)
		# — RPC atmadan sadece yerel önizlemeye izin ver.
		_apply_party_local_only(party_name, icon_index, icon_color, bg_color, core)
		return
	var my_id := multiplayer.get_unique_id()
	if MultiplayerManager.is_host:
		_apply_party(my_id, party_name, icon_index, icon_color, bg_color, core)
	else:
		_request_set_party.rpc_id(1, party_name, icon_index, icon_color, bg_color, core)

## Parti verisini ve hazır durumunu AYNI ANDA, TEK bir RPC ile ayarlar.
## "Kilitle ve Hazır Ver"e basınca kullanılmalı — set_my_party() sonra ayrı
## bir set_ready(true) çağrısı YAPMA: iki ayrı RPC arasında (özellikle
## hızlıca art arda basılırsa) host'un "hazır" bayrağını partinin SON
## değişikliği ulaşmadan uygulayıp oyunu erken başlatma riski olurdu — bu
## fonksiyon ikisini TEK mesajda birleştirerek bunu imkansız kılar.
func set_party_and_ready(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, core: Array, is_ready_value: bool) -> void:
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not VoterGroups.is_valid_core(core):
		return
	# ÇEVRİM DIŞI OYUN BURAYA GİRMEZ: girdiğinde "hazır" bayrağı sadece
	# yerelde işaretlenip finish_party_setup() hiç çağrılmıyordu, yani
	# hazır verince oyun başlamıyordu.
	if MultiplayerManager.is_standalone_preview():
		_apply_party_local_only(party_name, icon_index, icon_color, bg_color, core)
		var id := multiplayer.get_unique_id()
		if parties.has(id):
			parties[id]["ready"] = is_ready_value
		parties_updated.emit()
		return
	var my_id := multiplayer.get_unique_id()
	if MultiplayerManager.is_host:
		_apply_party_and_ready(my_id, party_name, icon_index, icon_color, bg_color, core, is_ready_value)
	else:
		_request_set_party_and_ready.rpc_id(1, party_name, icon_index, icon_color, bg_color, core, is_ready_value)

## Bu oyuncunun hazır durumunu ayarlar ("Kilitle ve Hazır Ver" / iptal).
func set_ready(is_ready_value: bool) -> void:
	if MultiplayerManager.is_standalone_preview():
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
	politicians.clear()
	_broadcast_parties()
	parties_updated.emit()

## BOT PARTİ ADLARI: "XP" biçiminde; X %75 iki harf, %25 tek harf ("AKP", "MP").
const BOT_NAME_LETTERS := "ABCDEFGHKLMNORSTUVY"
const BOT_NAME_TWO_LETTER_CHANCE := 0.75
## Bot YENİ renk seçerken (oluşturulurken ya da oyuncu rengini alınca) diğer
## partilere bundan yakın renk seçmez (0..1 algısal mesafe). 0.0.193: botlar
## yakın renk yüzünden kendiliğinden renk DEĞİŞTİRMEZ.
const BOT_COLOR_MIN_DISTANCE := 0.2

static func _bot_party_name(used: Array) -> String:
	for attempt in 60:
		var count := 2 if randf() < BOT_NAME_TWO_LETTER_CHANCE else 1
		var letters := ""
		for i in count:
			letters += BOT_NAME_LETTERS[randi_range(0, BOT_NAME_LETTERS.length() - 1)]
		var candidate := letters + "P"
		if not used.has(candidate):
			return candidate
	return "P%d" % randi_range(10, 99)

## İki rengin algısal mesafesi (0 aynı .. ~1 çok farklı; "redmean" yaklaşımı).
static func color_distance(a: Color, b: Color) -> float:
	var rm := (a.r + b.r) * 0.5
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return sqrt((2.0 + rm) * dr * dr + 4.0 * dg * dg + (3.0 - rm) * db * db) / 3.0

## Paletten, avoid'deki renklerin hepsine yeterince uzak bir renk (yoksa en uzak).
func _pick_distinct_color(avoid: Array) -> Color:
	var good: Array = []
	var best := PartyPresets.COLORS[0]
	var best_distance := -1.0
	for color in PartyPresets.COLORS:
		if color.is_equal_approx(Color.WHITE):
			continue
		var nearest := INF
		for other in avoid:
			nearest = minf(nearest, color_distance(color, other))
		if nearest >= BOT_COLOR_MIN_DISTANCE:
			good.append(color)
		if nearest > best_distance:
			best_distance = nearest
			best = color
	return good[randi_range(0, good.size() - 1)] if not good.is_empty() else best

## Host: yeni botun ilk rengi, diğer partilere yakın olmayan bir palet rengi.
func _assign_new_bot_color(bot_id: int) -> void:
	var avoid: Array = []
	for peer_id in parties.keys():
		var c := Color(parties[peer_id].get("bg_color", Color.TRANSPARENT))
		if int(peer_id) != bot_id and c.a > 0.0:
			avoid.append(c)
	parties[bot_id]["bg_color"] = _pick_distinct_color(avoid)

## Host: parti kurulumunda düşen oyuncu: partisi eksikse rastgele tamamlanır
## ve hazır sayılır (oyun onu beklemesin).
func auto_ready_away(peer_id: int) -> void:
	var party: Dictionary = parties.get(peer_id, {})
	var used_names: Array = []
	for other in parties.values():
		used_names.append(other.get("name", ""))
	if not is_valid_name(String(party.get("name", ""))):
		party["name"] = _bot_party_name(used_names)
	if not party.has("icon_index"):
		party["icon_index"] = PartyPresets.random_icon_index()
	party["icon_color"] = Color.WHITE
	if not party.has("bg_color") or Color(party["bg_color"]).a <= 0.0:
		var colors: Array = []
		for other in parties.values():
			colors.append(Color(other.get("bg_color", Color.TRANSPARENT)))
		party["bg_color"] = _pick_distinct_color(colors)
	if not VoterGroups.is_valid_core(party.get("core", [])):
		party["core"] = VoterGroups.random_core()
		party["groups"] = VoterGroups.start_affinities(party["core"])
	party["ready"] = true
	parties[peer_id] = party
	if not politicians.has(peer_id):
		var homes := GameMap.province_ids()
		var person := PoliticianPresets.random_name(PoliticianPresets.used_surnames(peer_id))
		politicians[peer_id] = PoliticianPresets.make(person["first_name"], person["surname"],
			PoliticianPresets.random_background(), String(homes[randi() % homes.size()]) if not homes.is_empty() else "", person["gender"])
	_broadcast_parties()
	parties_updated.emit()

## Host: bir bot için hazır (kilitli) rastgele bir parti oluşturur.
func add_bot_party(peer_id: int) -> void:
	if MultiplayerManager.room_code != "" and not MultiplayerManager.is_host:
		return
	var used_names: Array = []
	for party in parties.values():
		used_names.append(party.get("name", ""))
	parties[peer_id] = {
		"name": _bot_party_name(used_names),
		"icon_index": PartyPresets.random_icon_index(),
		"icon_color": Color.WHITE,
		"bg_color": Color.TRANSPARENT,
		"ready": true,
	}
	var bot_core := VoterGroups.random_core()
	parties[peer_id]["core"] = bot_core
	parties[peer_id]["groups"] = VoterGroups.start_affinities(bot_core)
	var background := PoliticianPresets.random_background()
	var homes := GameMap.province_ids()
	var bot_name := PoliticianPresets.random_name(PoliticianPresets.used_surnames(peer_id))
	politicians[peer_id] = PoliticianPresets.make(bot_name["first_name"], bot_name["surname"],
		background, String(homes[randi() % homes.size()]) if not homes.is_empty() else "", bot_name["gender"])
	_assign_new_bot_color(peer_id)
	if MultiplayerManager.room_code != "":
		_broadcast_parties()
	parties_updated.emit()

## BÖLÜNEN PARTİ: ana partiyle BİREBİR aynı grup yakınlıkları ve logo, BENZER (aynı değil)
## renk. Host çağırır (bkz. CardManager._split_party).
func add_splinter_party(peer_id: int, parent_id: int, party_name: String) -> void:
	var parent: Dictionary = parties.get(parent_id, {})
	parties[peer_id] = {
		"name": party_name,
		"icon_index": int(parent.get("icon_index", 0)),
		"icon_color": Color.WHITE,
		"bg_color": similar_color(Color(parent.get("bg_color", Color(0.5, 0.5, 0.5)))),
		"core": (parent.get("core", []) as Array).duplicate(),
		"groups": (parent.get("groups", VoterGroups.neutral_affinities()) as Dictionary).duplicate(),
		"ready": true,
		"splinter_of": parent_id,
	}
	if MultiplayerManager.room_code != "":
		_broadcast_parties()
	parties_updated.emit()

## Ana rengin "akrabası": tonu biraz kayık, açıklığı belirgin farklı.
static func similar_color(base: Color) -> Color:
	var value := base.v * 0.62 if base.get_luminance() > 0.45 else minf(1.0, base.v * 1.25 + 0.15)
	return Color.from_hsv(fposmod(base.h + 0.04, 1.0), clampf(base.s * 0.85, 0.25, 1.0), clampf(value, 0.25, 1.0))

## Host: oyundan çıkan (ana partisine dönen) partiyi siler.
func remove_party(peer_id: int) -> void:
	if not parties.has(peer_id):
		return
	parties.erase(peer_id)
	if MultiplayerManager.room_code != "":
		_broadcast_parties()
	parties_updated.emit()

## Partinin 8 seçmen grubundaki ulusal yakınlığı (yoksa nötr).
func groups_of(peer_id: int) -> Dictionary:
	return data_of(peer_id).get("groups", VoterGroups.neutral_affinities())

## Oyun sırasında (yasa, miting...) partilerin GRUP YAKINLIKLARINI değiştirir.
## Sadece host çağırır. Azalan getiri ve çift dengesi VoterGroups.apply_delta'da.
## changes: [{"peer": int, "group": String, "amount": float}]
## Dönüş: gerçekleşen değişimler [{"peer", "group", "delta"}].
func apply_group_deltas(changes: Array) -> Array:
	var actual: Array = []
	# room_code == "" : aktif oda yok (örn. sahne editörde tek başına test) —
	# yerel önizleme için host kontrolünü atla.
	if MultiplayerManager.room_code != "" and not MultiplayerManager.is_host:
		return actual
	for change in changes:
		var peer_id := int(change["peer"])
		var group := String(change["group"])
		if not parties.has(peer_id) or is_zero_approx(float(change["amount"])) or not VoterGroups.is_group(group):
			continue
		var groups: Dictionary = (parties[peer_id].get("groups", VoterGroups.neutral_affinities()) as Dictionary).duplicate()
		var before := float(groups.get(group, VoterGroups.AFFINITY_NEUTRAL))
		var delta := VoterGroups.apply_delta(groups, group, float(change["amount"]), parties[peer_id].get("core", []))
		parties[peer_id]["groups"] = groups
		if delta > 0.0:
			_take_group_share(peer_id, group, delta, before)
		if not is_zero_approx(delta):
			actual.append({"peer": peer_id, "group": group, "delta": delta})
	if actual.is_empty():
		return actual
	if MultiplayerManager.room_code == "":
		parties_updated.emit()
		return actual
	_broadcast_parties()
	parties_updated.emit()
	return actual

## SEÇMEN ÇALMA: bir parti bir grupta `gained` kadar hitap kazanınca bu pay
## kararsızlardan ve diğer partilerden, sahip oldukları payla orantılı alınır
## (kazanan için evren: 100 − önceki hitabı). Hitap toplamı 100'ü aşamaz.
func _take_group_share(peer_id: int, group: String, gained: float, before: float) -> void:
	var universe := VoterGroups.AFFINITY_MAX - before
	if universe <= 0.0:
		return
	for other in parties.keys():
		if int(other) == peer_id or int(other) == BLOC_ID or not parties[other].has("groups"):
			continue
		var groups: Dictionary = (parties[other]["groups"] as Dictionary).duplicate()
		var value := float(groups.get(group, VoterGroups.AFFINITY_NEUTRAL))
		if value <= 0.0:
			continue
		groups[group] = maxf(0.0, value - gained * value / universe)
		parties[other]["groups"] = groups

func _apply_party_local_only(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, core: Array) -> void:
	var id := multiplayer.get_unique_id()
	if not _claim_color(id, bg_color):
		parties_updated.emit()
		return
	var was_ready: bool = parties.get(id, {}).get("ready", false)
	parties[id] = {
		"name": party_name,
		"icon_index": icon_index,
		"icon_color": icon_color,
		"bg_color": bg_color,
		"core": core.duplicate(),
		"groups": VoterGroups.start_affinities(core),
		"ready": was_ready,
	}
	parties_updated.emit()

func _apply_party(peer_id: int, party_name: String, icon_index: int, icon_color: Color, bg_color: Color, core: Array) -> void:
	if not _claim_color(peer_id, bg_color):
		_broadcast_parties()  # reddedildi: istemci güncel renkleri görsün
		parties_updated.emit()
		return
	var was_ready: bool = parties.get(peer_id, {}).get("ready", false)
	parties[peer_id] = {
		"name": party_name,
		"icon_index": icon_index,
		"icon_color": icon_color,
		"bg_color": bg_color,
		"core": core.duplicate(),
		"groups": VoterGroups.start_affinities(core),
		"ready": was_ready,
	}
	_broadcast_parties()
	parties_updated.emit()

func _apply_party_and_ready(peer_id: int, party_name: String, icon_index: int, icon_color: Color, bg_color: Color, core: Array, is_ready_value: bool) -> void:
	if not _claim_color(peer_id, bg_color):
		_broadcast_parties()
		parties_updated.emit()
		return
	parties[peer_id] = {
		"name": party_name,
		"icon_index": icon_index,
		"icon_color": icon_color,
		"bg_color": bg_color,
		"core": core.duplicate(),
		"groups": VoterGroups.start_affinities(core),
		"ready": is_ready_value,
	}
	_broadcast_parties()
	parties_updated.emit()
	if is_ready_value and all_ready():
		MultiplayerManager.finish_party_setup()

func _apply_ready(peer_id: int, is_ready_value: bool) -> void:
	if not parties.has(peer_id):
		parties[peer_id] = {}
	parties[peer_id]["ready"] = is_ready_value
	_broadcast_parties()
	parties_updated.emit()
	if all_ready():
		MultiplayerManager.finish_party_setup()

## Parti adı henüz boşken de seçilen renk host'a gider: botlar rengini hemen
## değiştirir (oyuncu önceliklidir).
func set_my_color(bg_color: Color) -> void:
	if MultiplayerManager.is_standalone_preview() or MultiplayerManager.is_host:
		_apply_color(multiplayer.get_unique_id(), bg_color)
	else:
		_request_set_color.rpc_id(1, bg_color)

@rpc("any_peer", "reliable")
func _request_set_color(bg_color: Color) -> void:
	if MultiplayerManager.is_host:
		_apply_color(multiplayer.get_remote_sender_id(), bg_color)

func _apply_color(peer_id: int, bg_color: Color) -> void:
	if bg_color.is_equal_approx(Color.WHITE) or not _claim_color(peer_id, bg_color):
		if MultiplayerManager.room_code != "":
			_broadcast_parties()
		parties_updated.emit()
		return
	if not parties.has(peer_id):
		parties[peer_id] = {"ready": false}
	parties[peer_id]["bg_color"] = bg_color
	if MultiplayerManager.room_code != "":
		_broadcast_parties()
	parties_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_party(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, core: Array) -> void:
	if not MultiplayerManager.is_host:
		return
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not VoterGroups.is_valid_core(core):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_party(sender_id, party_name, icon_index, icon_color, bg_color, core)

@rpc("any_peer", "reliable")
func _request_set_ready(is_ready_value: bool) -> void:
	if not MultiplayerManager.is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_ready(sender_id, is_ready_value)

@rpc("any_peer", "reliable")
func _request_set_party_and_ready(party_name: String, icon_index: int, icon_color: Color, bg_color: Color, core: Array, is_ready_value: bool) -> void:
	if not MultiplayerManager.is_host:
		return
	if not is_valid_name(party_name):
		return
	if not is_valid_colors(icon_color, bg_color):
		return
	if not VoterGroups.is_valid_core(core):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_party_and_ready(sender_id, party_name, icon_index, icon_color, bg_color, core, is_ready_value)

# --- Siyasetçi profili (bkz. PoliticianPresets) ---------------------------------------

## Bu oyuncunun siyasetçisini ayarlar (profil ekranında "Devam"a basınca).
func set_my_politician(data: Dictionary) -> void:
	if not PoliticianPresets.is_valid(data):
		return
	# Yerel kopya: host'un yayını gelmeden parti kurulumu geçmişi bilsin.
	my_politician = data.duplicate()
	if MultiplayerManager.is_standalone_preview() or MultiplayerManager.room_code == "":
		_apply_politician(multiplayer.get_unique_id(), data)
	elif MultiplayerManager.is_host:
		_apply_politician(multiplayer.get_unique_id(), data)
	else:
		_request_set_politician.rpc_id(1, data)

## Oda sahibi: botun siyasetçisini tamamen rastgele yeniden üretir (cinsiyet,
## ad, soyad, geçmiş, memleket). Host değilse istek host'a gider.
func randomize_bot_politician(bot_id: int) -> void:
	if not MultiplayerManager.is_local_owner() or not MultiplayerManager.is_bot(bot_id):
		return
	if MultiplayerManager.room_code == "" or MultiplayerManager.is_host:
		_randomize_bot_politician(bot_id)
	else:
		_request_randomize_bot_politician.rpc_id(1, bot_id)

func _randomize_bot_politician(bot_id: int) -> void:
	if not parties.has(bot_id) and not politicians.has(bot_id):
		return
	var bot_name := PoliticianPresets.random_name(PoliticianPresets.used_surnames(bot_id))
	var homes := GameMap.province_ids()
	var home := String(homes[randi() % homes.size()]) if not homes.is_empty() else ""
	_apply_politician(bot_id, PoliticianPresets.make(bot_name["first_name"], bot_name["surname"],
		PoliticianPresets.random_background(), home, bot_name["gender"]))

## Oda sahibi: botun siyasetçisinin adını ve soyadını değiştirir (geçmiş,
## memleket ve cinsiyet korunur). Ad oyuncu profilindeki kurallarla temizlenir.
func set_bot_politician_name(bot_id: int, first_name: String, surname: String) -> void:
	if not MultiplayerManager.is_local_owner() or not MultiplayerManager.is_bot(bot_id):
		return
	if MultiplayerManager.room_code == "" or MultiplayerManager.is_host:
		_set_bot_politician_name(bot_id, first_name, surname)
	else:
		_request_set_bot_politician_name.rpc_id(1, bot_id, first_name, surname)

func _set_bot_politician_name(bot_id: int, first_name: String, surname: String) -> void:
	if not politicians.has(bot_id):
		return
	var data: Dictionary = (politicians[bot_id] as Dictionary).duplicate()
	data["first_name"] = PoliticianPresets.normalize_name(first_name)
	data["surname"] = PoliticianPresets.normalize_name(surname)
	if not PoliticianPresets.is_valid(data):
		parties_updated.emit()
		return
	_apply_politician(bot_id, data)

@rpc("any_peer", "reliable")
func _request_set_bot_politician_name(bot_id: int, first_name: String, surname: String) -> void:
	if not MultiplayerManager.is_host or multiplayer.get_remote_sender_id() != MultiplayerManager.owner_id \
			or not MultiplayerManager.is_bot(bot_id):
		return
	_set_bot_politician_name(bot_id, first_name, surname)

@rpc("any_peer", "reliable")
func _request_randomize_bot_politician(bot_id: int) -> void:
	if not MultiplayerManager.is_host or multiplayer.get_remote_sender_id() != MultiplayerManager.owner_id \
			or not MultiplayerManager.is_bot(bot_id):
		return
	_randomize_bot_politician(bot_id)

## Host: bir partinin siyasetçisini yazar ve yayar (botların memleketi de buradan düzeltilir).
func set_politician_host(peer_id: int, data: Dictionary) -> void:
	_apply_politician(peer_id, data)

func _apply_politician(peer_id: int, data: Dictionary) -> void:
	politicians[peer_id] = PoliticianPresets.make(String(data.get("first_name", "")),
		String(data.get("surname", "")), String(data.get("background", "")), String(data.get("hometown", "")),
		String(data.get("gender", "m")))
	if MultiplayerManager.room_code != "" and MultiplayerManager.is_host:
		_broadcast_parties()
	parties_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_politician(data: Dictionary) -> void:
	if not MultiplayerManager.is_host or not PoliticianPresets.is_valid(data):
		return
	_apply_politician(multiplayer.get_remote_sender_id(), data)

# --- Oda sahibi: bot partilerini düzenleme ------------------------------------------

## Oda sahibi bir botun partisinin adını, logosunu ve rengini değiştirir
## (çekirdek grupları ve hazır durumu korunur). Renk başka bir partideyse reddedilir.
## core boş verilirse botun çekirdek grupları değişmez.
func set_bot_party(bot_id: int, party_name: String, icon_index: int, bg_color: Color, core: Array = []) -> void:
	if not MultiplayerManager.is_local_owner() or not MultiplayerManager.is_bot(bot_id):
		return
	if not is_valid_name(party_name) or not is_valid_colors(Color.WHITE, bg_color):
		return
	if not core.is_empty() and not VoterGroups.is_valid_core(core):
		return
	if MultiplayerManager.room_code == "" or MultiplayerManager.is_host:
		_apply_bot_party(bot_id, party_name, icon_index, bg_color, core)
	else:
		_request_set_bot_party.rpc_id(1, bot_id, party_name, icon_index, bg_color, core)

func _apply_bot_party(bot_id: int, party_name: String, icon_index: int, bg_color: Color, core: Array = []) -> void:
	if not parties.has(bot_id) or icon_index < 0 or icon_index >= PartyPresets.icon_count():
		return
	if color_owner(bg_color, bot_id) != -1:
		if MultiplayerManager.room_code != "":
			_broadcast_parties()  # reddedildi: sahip güncel renkleri görsün
		parties_updated.emit()
		return
	parties[bot_id]["name"] = party_name
	parties[bot_id]["icon_index"] = icon_index
	if not Color(parties[bot_id].get("bg_color", Color.TRANSPARENT)).is_equal_approx(bg_color):
		parties[bot_id]["color_locked"] = true
	parties[bot_id]["bg_color"] = bg_color
	if not core.is_empty():
		parties[bot_id]["core"] = core.duplicate()
		parties[bot_id]["groups"] = VoterGroups.start_affinities(core)
	if MultiplayerManager.room_code != "":
		_broadcast_parties()
	parties_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_bot_party(bot_id: int, party_name: String, icon_index: int, bg_color: Color, core: Array = []) -> void:
	if not MultiplayerManager.is_host:
		return
	if multiplayer.get_remote_sender_id() != MultiplayerManager.owner_id or not MultiplayerManager.is_bot(bot_id):
		return
	if not is_valid_name(party_name) or not is_valid_colors(Color.WHITE, bg_color):
		return
	if not core.is_empty() and not VoterGroups.is_valid_core(core):
		return
	_apply_bot_party(bot_id, party_name, icon_index, bg_color, core)

func _broadcast_parties() -> void:
	state_version += 1
	_sync_parties.rpc(parties, politicians, state_version)

## İstemci: tam durumu host'tan ister (heartbeat sürüm uyuşmazlığında).
func request_full_sync() -> void:
	if MultiplayerManager.room_code == "" or MultiplayerManager.is_host:
		return
	_request_full_sync.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_full_sync() -> void:
	if not MultiplayerManager.is_host:
		return
	_sync_parties.rpc_id(multiplayer.get_remote_sender_id(), parties, politicians, state_version)

@rpc("authority", "reliable")
func _sync_parties(new_parties: Dictionary, new_politicians: Dictionary, version: int) -> void:
	parties = new_parties
	politicians = new_politicians
	state_version = version
	parties_updated.emit()
