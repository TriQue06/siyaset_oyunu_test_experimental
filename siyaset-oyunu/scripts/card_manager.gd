extends Node
## Autoload. Kart envanteri, oynama sırası, MANA ve hamleler, tur/seçim döngüsü,
## seçim sonuçları, İLLERİN GÖRÜŞÜ, AKTİVİTE (il puanı + il başkanlığı), oyuncuya
## özel istihbarat (anket/gözcü) ve oyun sonu. Host yetkili: host-olmayan
## istemcinin isteği önce host'a "any_peer" RPC ile gider, host doğrulayıp
## uygular ve herkese yayınlar.
##
## TUR AKIŞI (bir oyuncunun sırası):
##   0) MECLİS KONUŞMASI (zorunlu, atlanamaz): 6 uçtan birini seçer, partisi o
##      yöne IdeologyAxes.SPEECH_SHIFT kayar; güçlü olduğu iller kısmen takip eder.
##      Konuşmadan önce hiçbir hamle yapılamaz, tur bitirilemez.
##   a) KART OYNA: elden bir kart oyna; kartın mana bedeli düşer
##      (CardPresets.card_cost).
##   b) YASA TASARLA (GameRules.LAW_MANA_COST): meclise yasa sun; meclis yoksa
##      oylamasız SEÇİM VAADİ olur.
##   c) TEŞKİLATLANMA (GameRules.ORG_MANA_COST): bir ilde teşkilat kur / geliştir
##      (oy bonusu + ilin görüşü + 2. seviyeden itibaren anket).
##   d) PAS: hamle yapmadan geç, +GameRules.MANA_PASS_BONUS mana.
##   KART: sıra gelince otomatik 1 kart dağıtılır; kart oynamak sınırsız. Her seçimden sonra herkese 1 kart hediye.
##   Tur otomatik geçmez: oyuncu "Turu Bitir"e basar ya da süre dolar.
##   GameRules.TURN_TIMEOUT dolarsa otomatik pas geçilir (mana bonusu yok).
##   Hükümet kurulurken / meclis oylarken tur DURUR (is_turn_blocked).
##
## TUR SONU (herkes birer kez oynayınca) — bkz. GameRules
##   - (mana geliri tur sonunda değil, her oyuncunun sırası geldiğinde verilir),
##   - eksen keskinliği artar (makam puanları hükümet kurulurken yazılır),
##   - il/ulusal puanlar sıfıra doğru söner (il başkanlığı sönmez),
##   - son tursa oyun biter; seçim turuysa (ya da hükümet kurulamadıysa
##     ERKEN SEÇİM) seçim yapılır ve hükümet kurma aşaması başlar,
##   - tur sonu bir oylamanın ortasına denk gelirse oylama bitene kadar ertelenir.
##
## GİZLİ BİLGİ: illerin görüşü ve anket/gözcü sonuçları ağ üzerinden herkese
## gönderilen durumun içindedir; sadece ARAYÜZ ilgili oyuncuya gösterir.
##
## AĞ SENKRONU
##   Host her yetkili değişiklikte TÜM durumu bir "olay" ile birlikte yayınlar
##   (_receive_state) ve state_version'ı artırır. İl bazlı seçim sonuçları büyük
##   olduğu için sadece değiştiklerinde pakete eklenir. Host ayrıca
##   HEARTBEAT_INTERVAL'de bir sadece sürüm numaralarını yollar; sürümü farklı
##   olan istemci (bir mesajı kaçırmışsa) tam durumu kendisi ister.

signal inventories_updated
signal turn_order_updated
signal turn_changed(peer_id: int)
## Sadece animasyon için: state güncellenmeden HEMEN ÖNCE yayınlanır
## (my_inventory() hâlâ ESKİ eli verir).
signal card_drawn(peer_id: int, card_type: String)
## HERKESİN ekranında animasyon için: state güncellenmeden HEMEN ÖNCE yayınlanır.
signal card_played(peer_id: int, card_type: String)
## Seçimsiz bir tur bitti (hükümet puanlarını aldı, keskinlik arttı).
signal round_advanced
## Seçim yapıldı (last_vote_shares / last_seats / last_province_results güncel).
signal election_completed
## Milletvekili dağılımı seçim DIŞI bir sebeple değişti (vekil çalma, ayrılan oyuncu).
signal seats_changed
## Güç puanları değişti (miting, yatırım, yasa, karalama, sönme...).
signal opinion_changed
## Herkesin görmesi gereken bir olay oldu.
signal opinion_event(text: String)
## Oyun bitti (bkz. final_ranking, game_end_reason).
signal game_over
## OLAY LOGU: yeni bir kayıt eklendi (bkz. event_log). Oyun ekranının sol
## panelindeki log bunu dinler.
signal event_logged(entry: Dictionary)

const MAX_HAND_SIZE := 9
## Olay logunda tutulan en fazla kayıt.
const EVENT_LOG_LIMIT := 80
const HEARTBEAT_INTERVAL := 5.0
## İl başına saklanan son olay sayısı (il detay panelinde gösterilir).
const PROVINCE_EVENT_LIMIT := 6

## KART NADİRLİĞİ (bkz. _draw_weights). Değerler mutlak değil, oransal: bir
## kartın gelme olasılığı ağırlığının havuzdaki toplama bölümüdür. İlk seçimden
## önce isyan ve vekil çalma havuza girmez, kalanların payı kendiliğinden artar.
const WEIGHT_PROPAGANDA := 12.0
const WEIGHT_STEAL_WEAK := 12.0
const WEIGHT_MANA_BONUS := 12.0
const WEIGHT_MANA_BONUS_STRONG := 6.0
const WEIGHT_BONUS_CARD := 9.0
const WEIGHT_CARD_THEFT := 6.0
const WEIGHT_POPULISM := 12.0
const WEIGHT_STEAL_STRONG := 6.0
const WEIGHT_EARLY_ELECTION := 6.0
const WEIGHT_REPUTATION := 6.0
const WEIGHT_REBELLION := 9.0

## Meclis: haritadaki bölgelerin vekilleri (HexGridGenerator.PROVINCE_SEATS)
## + ulusal liste. Harita yüklenince yeniden hesaplanır.
var TOTAL_SEATS := 500

# peer_id -> Array[String] (her biri CardPresets.CARD_TYPES'tan biri)
var inventories: Dictionary = {}
# Array[int]: oynama sırasına göre peer_id'ler.
var turn_order: Array = []
# turn_order içindeki index; sırası gelen oyuncu turn_order[current_turn_index].
var current_turn_index: int = 0
## Elin başında dağıtılan kart, bir sonraki state olayına iliştirilmek üzere
## burada bekler: {"peer_id": int, "card": String}. İstemciler bunu görüp
## kart dağıtma animasyonunu oynatır.
var _pending_dealt: Dictionary = {}
## Oyuncunun en son yasa sunduğu tur: peer_id -> round_number (turda 1 yasa).
var law_rounds: Dictionary = {}
## Popülizm bonusu: peer_id -> bittiği tur (o turdan önceki son tura kadar sürer).
var populism: Dictionary = {}
## KARIŞIKLIK (GİZLİ, sadece host; oyunculara hiç gösterilmez): peer_id -> puan.
## Kaset ve iç karışıklık kartları büyütür; olumlu hamleler ve zaman söndürür.
## PublicOpinion.SPLIT_TURMOIL'i aşan parti BÖLÜNÜR (bkz. _check_splits).
var turmoil: Dictionary = {}
## BÖLÜNEN PARTİLER: ayrılan (yapay zekâ) partinin peer_id -> {"parent": ana parti,
## "elections": ayrıldıktan sonra atlattığı seçim, "since": ayrıldığı tur}.
var splinters: Dictionary = {}
## MECLİS KONUŞMASI: sırası gelen oyuncu bu sırada konuşmasını yaptı mı?
var speech_done: bool = false
## Testler için: false ise konuşma şartı aranmaz.
var speech_required: bool = true
## GÜNDEM: {"type": gündem türü, "until": bittiği tur} (boş = gündem yok).
var agenda: Dictionary = {}
## Sadece host: bu üçlemenin eksen sırası (her üçlemede karıştırılır).
var _agenda_axes: Array = []
var _last_agenda_axis: String = ""
## peer_id -> int: son seçimde ulusal listeden kazanılan vekil.
var national_list: Dictionary = {}
## Eksen keskinliği: il bazlı seçim sonuçlarının ne kadar keskin çıkacağını
## belirleyen üs (bkz. ElectionModel). HER TUR SONUNDA artar.
var current_axis_sharpness: float = 0.5

## Şu an oynanan tur (1'den başlar).
var round_number: int = 1
## Son seçimin yapıldığı tur (0 = henüz seçim yok) ve erken seçim olup olmadığı.
var last_election_round: int = 0
var last_election_was_early: bool = false
# peer_id -> float (yüzde, toplamı 100). Son seçimin sonucu.
var last_vote_shares: Dictionary = {}
# peer_id -> int. Son seçimden bu yana (vekil çalma dahil) milletvekili dağılımı.
var last_seats: Dictionary = {}
# province_id -> { peer_id -> {"percent": float, "seats": int} }
var last_province_results: Dictionary = {}
# Son seçimde barajı geçen peer_id'ler.
var passed_threshold: Array = []
## peer_id -> int: son seçimde kazanılan vekil (vekil momentumu bununla ölçülür).
var election_seats: Dictionary = {}
## Meclis erken seçim önergesini kabul etti: bu dönemin sonunda sandık kurulur.
var early_election_pending: bool = false
## Seçim takviminin çıpası (erken seçimden sonra kayar; 0 = varsayılan).
var election_anchor: int = 0
## Son seçimin girdileri (sadece host/yerel; denge analizi için, senkronlanmaz).
var last_election_inputs: Dictionary = {}

## GÜÇ (bkz. PublicOpinion)
# peer_id -> float
var national_support: Dictionary = {}
# province_id -> { peer_id -> float }  — sönen il puanı (aktivitenin bir parçası)
var local_support: Dictionary = {}
# province_id -> Array[{"round": int, "text": String}] (en yeni sonda)
var province_events: Dictionary = {}
## province_id -> {"economic": int, "social": int, "administrative": int}
var province_ideology: Dictionary = {}
## province_id -> { peer_id -> seviye (1..GameRules.ORG_MAX_LEVEL) }
var organizations: Dictionary = {}
## SİYASİ KALE: province_id -> peer_id (bkz. PublicOpinion.STRONGHOLD_*).
var strongholds: Dictionary = {}
## KALE EMEĞİ: province_id -> {peer_id -> puan}. O ilde yapılan her miting ve
## yatırım +1. Teşkilatı tam olan, emeği STRONGHOLD_EFFORT'a ulaşan ve seçmeni
## kendine yakın parti ili KALE yapar.
var kale_effort: Dictionary = {}
## KUŞATMA: province_id -> {peer_id -> puan}. Kale ilinde RAKİP mitingleri ve
## karalamaları biriktirir; toplam SIEGE_BREAK'e ulaşınca kale düşer.
var siege: Dictionary = {}
## REFERANDUM (boş = yok). Meclis anayasa değişikliğine salt çoğunlukla ama
## 2/3'ün altında EVET dediyse karar halka gider:
##   {"proposer", "payload" (anayasa paketi), "sides": peer -> VOTE_*,
##    "start_round", "end_round" (bu turun SONUNDA sonuçlanır: tam 2 tur),
##    "national": peer -> kampanya puanı, "local": il -> {peer -> puan},
##    "postponed": bool (seçim ertelendi), "postponed_final": bool}
## Bu 2 turda sadece MİTİNG ve KARTLAR kullanılır; seçim varsa ertelenir.
var referendum: Dictionary = {}
## Sadece host: illerin oyun başındaki DOĞAL görüşü (geri dönüş hedefi).
var _province_origin: Dictionary = {}
## peer_id -> int
var mana: Dictionary = {}

var game_finished: bool = false
## [{peer_id, name, leader, color, score, seats}], kazanan başta.
var final_ranking: Array = []
var game_end_reason: String = ""

var state_version: int = 0
## OLAY LOGU (her cihaz kendi tutar, ağda gitmez; sahne değişse de kalır):
## Array[{"text", "peer_id", "province", "kind", "round"}]. En yeni sonda.
var event_log: Array = []
## Testler için: 0 değilse init_game her seferinde bu tohumla aynı haritayı kurar.
var fixed_map_seed: int = 0

# Seçim hesabına giren iller ve koltuk sayıları (yetkili kaynak GameMap).
var _province_ids: Array = []
var _province_seat_counts: Dictionary = {}

var _turn_time_left: float = GameRules.TURN_TIMEOUT
var _turn_deadline_ms: int = 0
var _round_end_pending: bool = false
## Son turun seçimi yapıldı: hükümet kurulunca (ya da kurulamayınca) oyun biter.
var final_election_pending: bool = false
var _heartbeat_timer: float = 0.0
## Son hamlenin herkese duyurulacak mesajı.
var _event_message: String = ""
## Kale kazanma/kaybetme gibi ek log kayıtları: bir sonraki state olayına iliştirilir.
var _pending_log: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	call_deferred("_connect_log_sources")
	_rng.randomize()
	_load_province_seat_counts()

func _process(delta: float) -> void:
	# ÇEVRİM DIŞI OYUNDA DA İŞLEMELİ: eskiden room_code == "" kontrolü vardı,
	# çevrim dışında oda kodu boş olduğu için tur süresi hiç ilerlemiyordu.
	# Sadece gerçek bir oyun yokken (sahne önizlemesi) duruyor.
	if MultiplayerManager.is_standalone_preview() or not MultiplayerManager.is_host:
		return
	tick(delta)

func _is_local_only() -> bool:
	return MultiplayerManager.room_code == ""

func _is_authority() -> bool:
	return _is_local_only() or MultiplayerManager.is_host

## Testlerde rastgeleliği sabitlemek için.
func set_rng_seed(value: int) -> void:
	_rng.seed = value

## Host'un zamanlayıcıları (tur süresi, heartbeat). _process çağırır; testler
## doğrudan çağırabilir.
func tick(delta: float) -> void:
	if not _is_authority():
		return
	if not turn_order.is_empty() and not game_finished and not is_turn_blocked():
		_turn_time_left -= delta
		if _turn_time_left <= 0.0:
			_apply_pass(current_turn_peer_id(), false)
	if not _is_local_only():
		_heartbeat_timer += delta
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_heartbeat.rpc(state_version, GovernmentManager.state_version, PartyManager.state_version)

## Seçim bölgeleri ve vekil sayıları haritadan (GameMap) okunur.
func _load_province_seat_counts() -> void:
	_province_seat_counts = GameMap.seat_counts()
	_province_ids = GameMap.province_ids()
	var sum := 0
	for province_id in _province_ids:
		sum += int(_province_seat_counts[province_id])
	if sum > 0:
		TOTAL_SEATS = sum + ElectionModel.NATIONAL_LIST_SEATS

# --- Sorgular ---------------------------------------------------------------

func current_turn_peer_id() -> int:
	if turn_order.is_empty():
		return -1
	return turn_order[current_turn_index % turn_order.size()]

## Hükümet kurulurken, mecliste bir teklif oylanırken ya da oyun bittiyse
## TUR DURUR: kimse kart çekemez, oynayamaz, pas geçemez.
func is_turn_blocked() -> bool:
	return game_finished \
		or GovernmentManager.phase == GovernmentManager.Phase.FORMING \
		or GovernmentManager.phase == GovernmentManager.Phase.VOTING

func is_my_turn() -> bool:
	return current_turn_peer_id() == multiplayer.get_unique_id()

## Sıra bende VE tur akışı engellenmemiş mi? (UI bunu kullanmalı.)
func can_act() -> bool:
	return is_my_turn() and not is_turn_blocked() and not needs_speech(multiplayer.get_unique_id())

func my_inventory() -> Array:
	return inventories.get(multiplayer.get_unique_id(), [])

## MANA ONDALIKLI: çöpe atılan kart bedelinin YARISINI geri verdiği için
## yarım basamaklar oluşur (bkz. discard_card).
func mana_of(peer_id: int) -> float:
	return float(mana.get(peer_id, 0.0))

## Mana yazısı: tam sayıysa "3", değilse "2,5".
static func mana_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 1).replace(".", ",")

## Sıradaki oyuncunun kalan süresi (saniye).
func turn_seconds_left() -> float:
	if is_turn_blocked():
		return GameRules.TURN_TIMEOUT
	if _is_authority():
		return maxf(0.0, _turn_time_left)
	return maxf(0.0, float(_turn_deadline_ms - Time.get_ticks_msec()) / 1000.0)

func has_province(province_id: String) -> bool:
	return _province_seat_counts.has(province_id)

func province_seat_count(province_id: String) -> int:
	return int(_province_seat_counts.get(province_id, 0))

func is_government_party(peer_id: int) -> bool:
	return GovernmentManager.government_party_ids().has(peer_id)

## Sıra bu oyuncuda ve tur akışı engellenmemiş mi? (Her hamlenin ön şartı;
## hamle sayısı sınırsız, mana belirler.)
func can_choose_main_action(peer_id: int) -> bool:
	return peer_id == current_turn_peer_id() and not is_turn_blocked() and not needs_speech(peer_id)

## Bu oyuncu şu an MECLİS KONUŞMASI yapmak zorunda mı? (Sırası gelmiş, henüz
## konuşmamış.) Konuşmadan önce hiçbir hamle yapılamaz.
func needs_speech(peer_id: int) -> bool:
	return speech_required and not turn_order.is_empty() and peer_id == current_turn_peer_id() and not speech_done

## Bu oyuncu şu an bir yasa sunabilir mi? (law_type verilirse o yasa geçerli mi.)
func can_propose_law(peer_id: int, law_type: String = "") -> bool:
	if not can_choose_main_action(peer_id) or mana_of(peer_id) < law_mana_cost(peer_id, law_type):
		return false
	if is_referendum_active():
		return false  # referandumda sadece miting ve kartlar
	if not has_seats(peer_id):
		return false  # meclis dışı parti yasa teklif edemez
	# Yasa sadece gündemdeki eksende sunulabilir.
	var current := agenda_type()
	if current == "":
		return false
	if law_type != "" and CardPresets.law_data(law_type).get("axis", "") != CardPresets.agenda_data(current)["axis"]:
		return false
	if has_proposed_law_this_round(peer_id):
		return false
	if law_type != "" and not CardPresets.is_law_card(law_type):
		return false
	# İlk seçime kadar meclis yok: yasa yapılamaz (saf propaganda dönemi).
	return not last_seats.is_empty() and GovernmentManager.can_submit_law()

## Yasanın bu partiye bedeli: partinin yerleşik görüşüne ZIT yasa ek mana ister
## (bkz. GameRules.LAW_AGAINST_*). law_type boşsa taban bedel.
func law_mana_cost(peer_id: int, law_type: String = "") -> int:
	var law := CardPresets.law_data(law_type)
	if law.is_empty():
		return GameRules.LAW_MANA_COST
	var value := float(PartyManager.parties.get(peer_id, {}).get("ideology", {}).get(law["axis"], 0.0))
	if signf(value) == float(-int(law["dir"])):
		if absf(value) >= GameRules.LAW_AGAINST_LEVEL_2:
			return GameRules.LAW_MANA_COST + 2
		if absf(value) >= GameRules.LAW_AGAINST_LEVEL_1:
			return GameRules.LAW_MANA_COST + 1
	return GameRules.LAW_MANA_COST

## ANAYASA DEĞİŞİKLİĞİ sunulabilir mi? Yasadan farkı: GÜNDEM ŞARTI YOK
## (anayasa her dönem gündeme bakılmaksızın önerilebilir). Yasa hakkını
## kullanır: aynı dönemde ikisinden sadece biri sunulabilir.
func can_propose_constitution(peer_id: int) -> bool:
	if not can_choose_main_action(peer_id) or is_referendum_active():
		return false
	if not has_seats(peer_id):
		return false
	if has_proposed_law_this_round(peer_id):
		return false
	return not last_seats.is_empty() and GovernmentManager.can_submit_law()

## Anayasa paketi: {"threshold": %, "interval": kaç yılda bir seçim}
func propose_constitution(payload: Dictionary) -> void:
	if not can_propose_constitution(multiplayer.get_unique_id()):
		return
	if _is_authority():
		_apply_constitution_proposal(multiplayer.get_unique_id(), payload)
	else:
		_request_constitution.rpc_id(1, payload)

func _apply_constitution_proposal(peer_id: int, payload: Dictionary) -> void:
	if not can_propose_constitution(peer_id):
		return
	if payload.has("seat_method") and not ElectionModel.SEAT_METHODS.has(String(payload["seat_method"])):
		return
	_event_message = ""
	if not GovernmentManager.submit_constitution(peer_id, payload):
		return
	law_rounds[peer_id] = round_number
	_push_state({"type": "law", "peer_id": peer_id, "law": "anayasa"})

@rpc("any_peer", "reliable")
func _request_constitution(payload: Dictionary) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_constitution_proposal(multiplayer.get_remote_sender_id(), payload)

func has_proposed_law_this_round(peer_id: int) -> bool:
	return int(law_rounds.get(peer_id, 0)) == round_number

## Yatırım hamlesi: sadece hükümet partileri.
func can_invest(peer_id: int, province_id: String = "") -> bool:
	return can_choose_main_action(peer_id) and not is_referendum_active() and is_government_party(peer_id) \
		and mana_of(peer_id) >= GameRules.INVEST_MANA_COST and (province_id == "" or has_province(province_id))

## Mecliste en az bir vekili var mı? (Vekilsiz parti oy veremez, yasa ve
## gensoru veremez, vekil çalamaz.)
func has_seats(peer_id: int) -> bool:
	return int(last_seats.get(peer_id, 0)) > 0

## Gensoru hamlesi: muhalefet, hükümet görevde ve salt çoğunluğu yokken.
func can_censure(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and not is_referendum_active() and mana_of(peer_id) >= GameRules.CENSURE_MANA_COST and has_seats(peer_id) \
		and GovernmentManager.phase == GovernmentManager.Phase.GOVERNING and GovernmentManager.has_government() \
		and not GovernmentManager.has_majority() and not is_government_party(peer_id)

## Popülizm bonusunun kalan turu (kullanıldığı turda POPULISM_ROUNDS, yoksa 0).
func populism_rounds_left(peer_id: int) -> int:
	return maxi(0, int(populism.get(peer_id, 0)) - round_number)

## Miting hamlesi: seçilen ilde güç (provokasyon riskiyle).
func can_miting(peer_id: int, province_id: String = "") -> bool:
	if not can_choose_main_action(peer_id) or mana_of(peer_id) < GameRules.MITING_MANA_COST:
		return false
	if is_referendum_active():
		# Referandum kampanyası: her ilde miting yapılabilir (teşkilat şartı yok).
		return province_id == "" or has_province(province_id)
	if province_id == "":
		return has_organization_anywhere(peer_id)
	# Miting artik teskilat ister: once ilde orgutlenmis olmak gerekir.
	return has_province(province_id) and organization_level(province_id, peer_id) > 0

## Partinin herhangi bir ilde teskilati var mi? (miting/karalama on sarti)
func has_organization_anywhere(peer_id: int) -> bool:
	for province_id in organizations.keys():
		if organization_level(String(province_id), peer_id) > 0:
			return true
	return false

func can_build_organization(peer_id: int, province_id: String) -> bool:
	return can_choose_main_action(peer_id) and not is_referendum_active() and mana_of(peer_id) >= GameRules.ORG_MANA_COST \
		and has_province(province_id) and organization_level(province_id, peer_id) < GameRules.ORG_MAX_LEVEL

## Bir partiden vekil çalınabilir mi? Kendinden çalınamaz, meclis dışı partiden
## çalınamaz ve hedefin en az 2 vekili olmalı (1'in altına DÜŞÜRÜLEMEZ).
func is_valid_steal_target(peer_id: int, target_peer_id: int) -> bool:
	if target_peer_id == -1 or target_peer_id == peer_id:
		return false
	# Meclis dışı parti de vekil çalabilir (ilk seçimden sonra), ama etkisi
	# YARI YARIYA (bkz. steal_efficiency) ve bu ceza sonraki seçime kadar sürer.
	if last_seats.is_empty():
		return false
	# Hedefin vekili çalınacak sayıdan azsa hepsi gidebilir (0'a iner).
	return has_seats(target_peer_id)

## SEÇİMDE BARAJ ALTINDA KALAN parti çaldığı vekillerin yarısını alır. Kart
## sayesinde meclise girse bile ceza sonraki seçime kadar devam eder — ölçüt
## son SEÇİMDEKİ sonuç (election_seats), o anki vekil sayısı değil.
func steal_efficiency(peer_id: int) -> float:
	if int(election_seats.get(peer_id, 0)) > 0:
		return 1.0
	return PublicOpinion.STEAL_OUTSIDER_EFFICIENCY

## Bu parti son seçimde meclis dışında mı kaldı?
func is_outside_parliament(peer_id: int) -> bool:
	return int(election_seats.get(peer_id, 0)) <= 0

## Bu kart şu an bu hedeflerle oynanabilir mi? (Host doğrulaması ve UI.)
func can_play_card(peer_id: int, card_type: String, target_peer_id: int = -1, target_province: String = "") -> bool:
	if mana_of(peer_id) < CardPresets.card_cost(card_type) or needs_speech(peer_id):
		return false
	if card_type == CardPresets.EARLY_ELECTION_CARD_TYPE:
		# Meclis gerekir, oylama açık olmamalı, zaten erken seçim kararı yoksa.
		return has_seats(peer_id) and not early_election_pending and not is_referendum_active() \
			and GovernmentManager.can_submit_law()
	if CardPresets.needs_target(card_type):
		return is_valid_steal_target(peer_id, target_peer_id)
	if card_type == CardPresets.REPUTATION_CARD_TYPE or card_type == CardPresets.CARD_THEFT_CARD_TYPE:
		return turn_order.has(target_peer_id) and target_peer_id != peer_id
	if card_type == CardPresets.REBELLION_CARD_TYPE:
		return turn_order.has(target_peer_id) and target_peer_id != peer_id and has_seats(target_peer_id)
	if card_type == CardPresets.PROPAGANDA_CARD_TYPE:
		# Karalama da teskilat ister: ilde orgutlu olmayan parti kampanya yapamaz.
		return has_province(target_province) and turn_order.has(target_peer_id) \
			and target_peer_id != peer_id and (is_referendum_active() or organization_level(target_province, peer_id) > 0)
	if card_type == CardPresets.SCOUT_CARD_TYPE:
		return false  # gözcü artık teşkilatın parçası
	if CardPresets.needs_province_target(card_type):
		if not has_province(target_province):
			return false
		if card_type == CardPresets.MITING_CARD_TYPE:
			# Miting kartı da teşkilat ister.
			return organization_level(target_province, peer_id) > 0
		return true
	if card_type == CardPresets.INVEST_CARD_TYPE or CardPresets.is_censure_card(card_type):
		return false  # artık hamle (bkz. invest / censure)
	return true

# --- Güç sorguları ------------------------------------------------------------

func national_of(peer_id: int) -> float:
	return float(national_support.get(peer_id, 0.0))

func local_of(province_id: String, peer_id: int) -> float:
	return float(local_support.get(province_id, {}).get(peer_id, 0.0))

## İllerin görüşü (oyun başında üretilir). Oyun kurulmamışsa (testler, editör)
## dosyadaki örnek görüşlere düşer.
func province_voters() -> Dictionary:
	if province_ideology.is_empty():
		return ElectionModel.load_province_voters()
	return province_ideology

func province_center(province_id: String) -> Dictionary:
	return province_voters().get(province_id, {})

func organization_level(province_id: String, peer_id: int) -> int:
	return int(organizations.get(province_id, {}).get(peer_id, 0))

## AKTİVİTE yakınlığı: sönen il puanı + teşkilatın kalıcı katkısı.
func activity_of(province_id: String, peer_id: int) -> float:
	return local_of(province_id, peer_id) + org_bonus(province_id, peer_id)

## Teşkilatın oy bonusu (popülizm sürerken büyür) + KALE bonusu.
func org_bonus(province_id: String, peer_id: int) -> float:
	var bonus := PublicOpinion.org_activity(organization_level(province_id, peer_id))
	if stronghold_of(province_id) == peer_id:
		bonus += PublicOpinion.STRONGHOLD_ACTIVITY
	if populism_rounds_left(peer_id) > 0:
		bonus *= PublicOpinion.POPULISM_GOOD_MULT
	return bonus

## Bir ilde partilerin aktivitesi: peer_id -> puan.
func activity_entry(province_id: String) -> Dictionary:
	var entry: Dictionary = local_support.get(province_id, {}).duplicate()
	var orgs: Dictionary = organizations.get(province_id, {})
	for peer_id in orgs.keys():
		entry[peer_id] = float(entry.get(peer_id, 0.0)) + org_bonus(province_id, int(peer_id))
	return entry

## Tüm iller: province_id -> {peer_id -> aktivite}.
func activity_map() -> Dictionary:
	var result := {}
	for province_id in _province_ids:
		var entry := activity_entry(province_id)
		if not entry.is_empty():
			result[province_id] = entry
	return result

## Bir partinin bir ildeki gücü (ideolojik + aktivite).
func party_strength(province_id: String, peer_id: int) -> float:
	var ideology: Dictionary = PartyManager.parties.get(peer_id, {}).get("ideology", IdeologyAxes.default_values())
	return PublicOpinion.party_strength(ideology, province_center(province_id), activity_of(province_id, peer_id))

## Teşkilat bilgisi (sadece o partinin arayüzü gösterir):
##   1. seviye: ilin görüşü + YAKLAŞIK oy (±%35),
##   2. seviye: %90 doğrulukla oy (±%10).
func knows_leaning(peer_id: int, province_id: String) -> bool:
	return organization_level(province_id, peer_id) >= 1

## Anket sapması (−1: anket yok).
func poll_error(peer_id: int, province_id: String) -> float:
	match organization_level(province_id, peer_id):
		1:
			return GameRules.POLL_ERROR_LOW
		2:
			return GameRules.POLL_ERROR_HIGH
	return -1.0

## Teşkilat anketi: gerçek tahmin, seviyeye göre gürültülü. Aynı turda aynı
## sonucu verir (her bakışta değişmez). Anket yoksa boş sözlük.
func province_poll(peer_id: int, province_id: String) -> Dictionary:
	var error := poll_error(peer_id, province_id)
	if error < 0.0:
		return {}
	var projection := province_projection(province_id)
	return _noisy_poll(projection, error, "%s:%d:%d" % [province_id, peer_id, round_number], province_seat_count(province_id),
		projected_eligible())

func _noisy_poll(projection: Dictionary, error: float, seed_text: String, seat_count: int, eligible: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var shares := {}
	var total := 0.0
	var ids: Array = projection.keys()
	ids.sort()
	for peer_id in ids:
		var value: float = float(projection[peer_id]["percent"]) * (1.0 + rng.randf_range(-error, error))
		shares[peer_id] = value
		total += value
	if total > 0.0:
		for peer_id in ids:
			shares[peer_id] = float(shares[peer_id]) / total * 100.0
	var alloc := ElectionModel.allocate(shares, eligible, seat_count)
	var result := {}
	for peer_id in ids:
		result[peer_id] = {"percent": float(shares[peer_id]), "seats": int(alloc.get(peer_id, 0))}
	return result

## Tahminlerde (güç haritası, anket) barajı geçmesi beklenen partiler: gürültüsüz
## beklenen ulusal oyu baraj ve üstü olanlar (seçimle aynı kural; kimse
## geçemezse herkes).
func projected_eligible(mods: Dictionary = {}) -> Array:
	if mods.is_empty():
		mods = election_modifiers()
	var local_mods: Dictionary = mods["local"]
	var ideologies := _ideologies()
	var national := {}
	var total := 0.0
	for province_id in _province_ids:
		var seats := float(province_seat_count(province_id))
		var shares := ElectionModel.expected_shares(ideologies, province_center(province_id), current_axis_sharpness,
			mods["national"], local_mods.get(province_id, {}), _expected_national(mods))
		for peer_id in shares.keys():
			national[peer_id] = float(national.get(peer_id, 0.0)) + float(shares[peer_id]) * seats
		total += seats
	var eligible: Array = []
	for peer_id in turn_order:
		if total > 0.0 and float(national.get(peer_id, 0.0)) / total >= MultiplayerManager.election_threshold:
			eligible.append(peer_id)
	if eligible.is_empty():
		eligible = turn_order.duplicate()
	return eligible

## Gürültüsüz beklenen ulusal paylar (il payları bununla karışır). Aynı
## modifier sözlüğü için önbellekli: bir harita çizimi 67 kez sormasın.
var _national_cache_key: Dictionary = {}
var _national_cache: Dictionary = {}
func _expected_national(mods: Dictionary) -> Dictionary:
	if is_same(mods, _national_cache_key):
		return _national_cache
	var centers := {}
	var seats := {}
	for province_id in _province_ids:
		centers[province_id] = province_center(province_id)
		seats[province_id] = province_seat_count(province_id)
	_national_cache = ElectionModel.expected_national(_ideologies(), centers, seats, current_axis_sharpness,
		mods["national"], mods["local"])
	_national_cache_key = mods
	return _national_cache

## Şimdi seçim olsa bu ilde: peer_id -> {"percent", "seats"} (gürültüsüz beklenen
## oylar, ildeki vekiller D'Hondt ile; baraj yok sayılır). Gözcü raporu için.
func province_projection(province_id: String) -> Dictionary:
	var mods := election_modifiers()
	var local_mods: Dictionary = mods["local"]
	var shares := ElectionModel.expected_shares(_ideologies(), province_center(province_id), current_axis_sharpness,
		mods["national"], local_mods.get(province_id, {}), _expected_national(mods))
	var alloc := ElectionModel.allocate(shares, projected_eligible(mods), province_seat_count(province_id))
	var result := {}
	for peer_id in turn_order:
		result[peer_id] = {"percent": float(shares.get(peer_id, 0.0)), "seats": int(alloc.get(peer_id, 0))}
	return result

## Güç haritası: bu partinin ANKETİ olan illerde (teşkilat 2+) anlık seçim
## tahmini: province_id -> {peer_id -> {"percent", "seats", "quotient"},
## "seat_count"}. quotient: ildeki son kazanan D'Hondt bölümü (bir vekile ne
## kadar yakın olunduğunu ölçmek için). peer_id = -1: tüm iller, gürültüsüz.
func projection_all(viewer: int = -1) -> Dictionary:
	var mods := election_modifiers()
	var local_mods: Dictionary = mods["local"]
	var ideologies := _ideologies()
	var eligible := projected_eligible(mods)
	var result := {}
	for province_id in _province_ids:
		var error := poll_error(viewer, province_id) if viewer != -1 else 0.0
		if error < 0.0:
			continue
		var seat_count := province_seat_count(province_id)
		var shares := ElectionModel.expected_shares(ideologies, province_center(province_id), current_axis_sharpness,
			mods["national"], local_mods.get(province_id, {}), _expected_national(mods))
		if viewer != -1:
			var noisy := {}
			for peer_id in shares.keys():
				noisy[peer_id] = {"percent": float(shares[peer_id])}
			noisy = _noisy_poll(noisy, error, "%s:%d:%d" % [province_id, viewer, round_number], seat_count, eligible)
			for peer_id in noisy.keys():
				shares[peer_id] = float(noisy[peer_id]["percent"])
		var alloc := ElectionModel.allocate(shares, eligible, seat_count)
		var last_quotient := INF
		for peer_id in turn_order:
			var won := int(alloc.get(peer_id, 0))
			if won > 0:
				last_quotient = minf(last_quotient, float(shares.get(peer_id, 0.0)) / float(won))
		var entry := {}
		for peer_id in turn_order:
			entry[peer_id] = {"percent": float(shares.get(peer_id, 0.0)), "seats": int(alloc.get(peer_id, 0)),
				"quotient": last_quotient}
		entry["seat_count"] = seat_count
		result[province_id] = entry
	return result

func _ideologies() -> Dictionary:
	var result := {}
	for peer_id in turn_order:
		result[peer_id] = PartyManager.parties.get(peer_id, {}).get("ideology", IdeologyAxes.default_values())
	return result

## İlin mevcut siyasi dengesi (il görüşü + güçlü partilerin çekişi).
func province_balance(province_id: String) -> Dictionary:
	var shares := {}
	var results: Dictionary = last_province_results.get(province_id, {})
	for peer_id in results.keys():
		shares[peer_id] = float(results[peer_id].get("percent", 0.0))
	return PublicOpinion.balance_center(province_center(province_id), shares, activity_entry(province_id), _ideologies())

## Bu parti bu ilde miting yaparsa provokasyon olasılığı (0..0.5).
func miting_risk(peer_id: int, province_id: String) -> float:
	var ideology: Dictionary = PartyManager.parties.get(peer_id, {}).get("ideology", IdeologyAxes.default_values())
	return PublicOpinion.provocation_risk(ideology, province_balance(province_id), organization_level(province_id, peer_id))

# --- Olay logu -----------------------------------------------------------------

## Loga kayıt ekler. peer_id: hamleyi yapan parti (-1: sistem), province:
## olayın geçtiği il ("" = yok), kind: olay türü (odak simgesi seçilir).
func log_event(text: String, peer_id: int = -1, province: String = "", kind: String = "system") -> void:
	if text.strip_edges() == "":
		return
	var entry := {"text": text, "peer_id": peer_id, "province": province, "kind": kind, "round": round_number}
	event_log.append(entry)
	while event_log.size() > EVENT_LOG_LIMIT:
		event_log.pop_front()
	event_logged.emit(entry)

func clear_event_log() -> void:
	event_log.clear()

## Meclis sonuçları ve koalisyon olayları da loga düşer (GovernmentManager
## CardManager'dan sonra yüklendiği için bağlantı ertelenir).
func _connect_log_sources() -> void:
	GovernmentManager.proposal_resolved.connect(func(_accepted: bool, kind: String, proposer: int):
		log_event(GovernmentManager.last_resolution_reason, proposer, "", "vote_" + kind))
	GovernmentManager.coalition_changed.connect(func(text: String):
		log_event(text, -1, "", "coalition"))

## Olay türünden log türü: kart oynandıysa kartın türü.
static func _log_kind(event: Dictionary) -> String:
	var type := String(event.get("type", ""))
	if type == "played":
		return String(event.get("card", "played"))
	return type

# --- Oyun başlangıcı --------------------------------------------------------

## Sadece host çağırır (Parti Kurulum bitip GameScreen'e geçilirken): tüm oyun
## durumunu sıfırlar, illerin görüşünü üretir, oynama sırasını rastgele
## belirler, herkese yayınlar.
func init_game() -> void:
	if not _is_authority():
		return
	inventories.clear()
	event_log.clear()
	mana = {}
	for peer_id in MultiplayerManager.players.keys():
		inventories[peer_id] = []
		mana[peer_id] = GameRules.MANA_START
	turn_order = MultiplayerManager.players.keys().duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	_grant_turn_income()
	law_rounds = {}
	populism = {}
	turmoil = {}
	splinters = {}
	agenda = {}
	_agenda_axes = []
	national_list = {}
	current_axis_sharpness = minf(MultiplayerManager.axis_sharpness_start, MultiplayerManager.axis_sharpness_max_value if MultiplayerManager.axis_sharpness_max_enabled else MultiplayerManager.AXIS_SHARPNESS_HARD_MAX)
	round_number = 1
	last_election_round = 0
	last_election_was_early = false
	last_vote_shares = {}
	last_seats = {}
	last_province_results = {}
	passed_threshold = []
	election_seats = {}
	early_election_pending = false
	election_anchor = 0
	GameRules.set_election_anchor(0)
	national_support = {}
	local_support = {}
	province_events = {}
	# YENİ ÜLKE: her oyunda rastgele altıgen harita (herkese tam durumla gider).
	# Lobide tohum girildiyse o ülke, yoksa rastgele (1..999 999 999) bir tohum.
	var map_seed := fixed_map_seed
	if map_seed == 0 and MultiplayerManager.map_seed != "":
		map_seed = int(MultiplayerManager.map_seed)
	if map_seed == 0:
		map_seed = _rng.randi_range(1, 999999999)
	GameMap.generate_new(map_seed)
	_load_province_seat_counts()
	province_ideology = ProvinceIdeology.generate(_rng, _province_ids)
	_province_origin = province_ideology.duplicate(true)
	organizations = {}
	strongholds = {}
	kale_effort = {}
	siege = {}
	referendum = {}
	game_finished = false
	final_ranking = []
	game_end_reason = ""
	_turn_time_left = GameRules.TURN_TIMEOUT
	_round_end_pending = false
	final_election_pending = false
	GovernmentManager.reset()
	# Yeni oyun: sayım yöntemi D'Hondt'a döner.
	MultiplayerManager.reset_seat_method()
	if not _is_local_only():
		MultiplayerManager._sync_seat_method.rpc(MultiplayerManager.seat_method)
	_push_state({"type": "full"}, true)

## Oyundan ayrılınca YEREL oyun durumunu temizler (ağ yayını yok).
func abandon_game() -> void:
	inventories = {}
	event_log = []
	turn_order = []
	current_turn_index = 0
	round_number = 1
	last_election_round = 0
	last_election_was_early = false
	last_vote_shares = {}
	last_seats = {}
	last_province_results = {}
	passed_threshold = []
	election_seats = {}
	early_election_pending = false
	election_anchor = 0
	GameRules.set_election_anchor(0)
	national_support = {}
	local_support = {}
	province_events = {}
	province_ideology = {}
	organizations = {}
	strongholds = {}
	kale_effort = {}
	siege = {}
	turmoil = {}
	splinters = {}
	speech_done = false
	referendum = {}
	mana = {}
	game_finished = false
	final_ranking = []
	game_end_reason = ""
	_round_end_pending = false

# --- Oyuncu eylemleri -------------------------------------------------------

## Bu oyuncu için desteden çekilebilecek kartlar ve ağırlıkları.
##   - karalama her zaman,
##   - popülizm ve mana bonusu her zaman,
##   - vekil çalma ilk seçimden (meclis oluştuktan) sonra.
func _draw_weights(peer_id: int = -1) -> Dictionary:
	var weights := {}
	weights[CardPresets.PROPAGANDA_CARD_TYPE] = WEIGHT_PROPAGANDA
	weights[CardPresets.REPUTATION_CARD_TYPE] = WEIGHT_REPUTATION
	# İsyan kartı ancak meclis (ve yasa oylaması) varken anlamlı.
	if not last_seats.is_empty():
		weights[CardPresets.REBELLION_CARD_TYPE] = WEIGHT_REBELLION
	if not last_seats.is_empty():
		weights[CardPresets.STEAL_WEAK_CARD_TYPE] = WEIGHT_STEAL_WEAK
		weights[CardPresets.STEAL_STRONG_CARD_TYPE] = WEIGHT_STEAL_STRONG
	# Erken seçim ancak meclis varken anlamlı.
	if not last_seats.is_empty():
		weights[CardPresets.EARLY_ELECTION_CARD_TYPE] = WEIGHT_EARLY_ELECTION
	weights[CardPresets.POPULISM_CARD_TYPE] = WEIGHT_POPULISM
	weights[CardPresets.MANA_BONUS_CARD_TYPE] = WEIGHT_MANA_BONUS
	weights[CardPresets.MANA_BONUS_STRONG_CARD_TYPE] = WEIGHT_MANA_BONUS_STRONG
	weights[CardPresets.BONUS_CARD_TYPE] = WEIGHT_BONUS_CARD
	weights[CardPresets.CARD_THEFT_CARD_TYPE] = WEIGHT_CARD_THEFT
	return weights

## Geriye uyumluluk / testler: desteye girebilecek kart türleri.
func _draw_pool(peer_id: int = -1) -> Array:
	return _draw_weights(peer_id).keys()

## Sırası gelen oyuncu elindeki bir kartı oynar (hand_index: my_inventory()
## içindeki sırası).
##   target_peer_id  : vekil çalma ve karalamada hedef parti.
##   target_province : il kartlarında ZORUNLU.
func play_card(hand_index: int, target_peer_id: int = -1, target_province: String = "") -> void:
	if _is_local_only() and turn_order.is_empty():
		var id := multiplayer.get_unique_id()
		var hand: Array = inventories.get(id, [])
		if hand_index < 0 or hand_index >= hand.size():
			return
		var card_type: String = hand[hand_index]
		card_played.emit(id, card_type)
		hand.remove_at(hand_index)
		_apply_card_effect(id, card_type, target_peer_id, target_province)
		inventories_updated.emit()
		return
	if not can_act():
		return
	if _is_authority():
		_apply_play(multiplayer.get_unique_id(), hand_index, target_peer_id, target_province)
	else:
		_request_play.rpc_id(1, hand_index, target_peer_id, target_province)

## ÇÖP: istemediğin kartı at, bedelinin YARISINI mana olarak geri al.
## (Kart oynamak gibi sırayı devretmez; sıradaki oyuncu yapar.)
func discard_card(hand_index: int) -> void:
	if _is_local_only() and turn_order.is_empty():
		_apply_discard(multiplayer.get_unique_id(), hand_index)
		return
	if not can_act():
		return
	if _is_authority():
		_apply_discard(multiplayer.get_unique_id(), hand_index)
	else:
		_request_discard.rpc_id(1, hand_index)

func _apply_discard(peer_id: int, hand_index: int) -> void:
	if not _is_local_only() and (is_turn_blocked() or peer_id != current_turn_peer_id()):
		return
	if needs_speech(peer_id):
		return
	var hand: Array = inventories.get(peer_id, [])
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_type: String = hand[hand_index]
	hand.remove_at(hand_index)
	var refund := discard_refund(card_type)
	mana[peer_id] = mana_of(peer_id) + refund
	_event_message = "%s bir kartı çöpe attı (+%s mana)." % [_party_name(peer_id), mana_text(refund)]
	inventories_updated.emit()
	if _is_local_only() and turn_order.is_empty():
		return
	_push_state({"type": "discard", "peer_id": peer_id, "card": card_type})

## Çöpe atılan kartın geri verdiği mana: bedelinin yarısı.
static func discard_refund(card_type: String) -> float:
	return CardPresets.card_cost(card_type) * 0.5

@rpc("any_peer", "reliable")
func _request_discard(hand_index: int) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_discard(multiplayer.get_remote_sender_id(), hand_index)

## Yasa tasarla: law_type = CardPresets.law_type(eksen, yön).
func propose_law(law_type: String) -> void:
	if not can_propose_law(multiplayer.get_unique_id(), law_type):
		return
	if _is_authority():
		_apply_law(multiplayer.get_unique_id(), law_type)
	else:
		_request_law.rpc_id(1, law_type)

## Seçilen ilde il başkanlığı kur / geliştir.
func build_organization(province_id: String) -> void:
	if not can_build_organization(multiplayer.get_unique_id(), province_id):
		return
	if _is_authority():
		_apply_organization(multiplayer.get_unique_id(), province_id)
	else:
		_request_organization.rpc_id(1, province_id)

## Yatırım hamlesi: seçilen ile hükümet yatırımı (INVEST_MANA_COST).
func invest(province_id: String) -> void:
	if not can_invest(multiplayer.get_unique_id(), province_id):
		return
	if _is_authority():
		_apply_invest_move(multiplayer.get_unique_id(), province_id)
	else:
		_request_invest.rpc_id(1, province_id)

## Gensoru hamlesi (CENSURE_MANA_COST): meclis oylaması açılır.
func censure() -> void:
	if not can_censure(multiplayer.get_unique_id()):
		return
	if _is_authority():
		_apply_censure_move(multiplayer.get_unique_id())
	else:
		_request_censure.rpc_id(1)

## Miting hamlesi: seçilen ilde miting (MITING_MANA_COST).
func miting(province_id: String) -> void:
	if not can_miting(multiplayer.get_unique_id(), province_id):
		return
	if _is_authority():
		_apply_miting_move(multiplayer.get_unique_id(), province_id)
	else:
		_request_miting.rpc_id(1, province_id)

## "Turu Bitir": sırayı bir sonraki oyuncuya devreder.
func pass_turn() -> void:
	if turn_order.is_empty() or not can_act():
		return
	if _is_authority():
		_apply_pass(multiplayer.get_unique_id(), true)
	else:
		_request_pass.rpc_id(1)

## İstemci: tam durumu host'tan ister (heartbeat sürüm uyuşmazlığında).
func request_full_sync() -> void:
	if _is_authority():
		return
	_request_full_sync.rpc_id(1)

# --- Host tarafı: uygulama --------------------------------------------------

func _apply_play(peer_id: int, hand_index: int, target_peer_id: int = -1, target_province: String = "") -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id():
		return
	var hand: Array = inventories.get(peer_id, [])
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_type: String = hand[hand_index]
	# Geçersiz hedefle / şartsız oynanan kart elde kalır, boşa harcanmaz.
	if not can_play_card(peer_id, card_type, target_peer_id, target_province):
		return
	card_played.emit(peer_id, card_type)
	hand.remove_at(hand_index)
	mana[peer_id] = mana_of(peer_id) - CardPresets.card_cost(card_type)
	_event_message = ""
	var seats_changed_now := _apply_card_effect(peer_id, card_type, target_peer_id, target_province)
	var event := {"type": "played", "peer_id": peer_id, "card": card_type,
		"target": target_peer_id, "province": target_province, "seats_changed": seats_changed_now}
	if _event_message != "":
		event["message"] = _event_message
	# Hiçbir kart sırayı devretmez; tur sadece "Turu Bitir" ya da süreyle biter.
	_push_state(event, seats_changed_now)
	
## Turu bitir (voluntary=false: süre doldu). Mana bonusu yok.
func _apply_pass(peer_id: int, voluntary: bool = true) -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id():
		return
	# Konuşmadan tur bitirilemez (süre dolarsa sıra yine de devreder).
	if voluntary and needs_speech(peer_id):
		return
	var wrapped := _advance_turn()
	_push_state({"type": "passed", "peer_id": peer_id})
	_finish_round_if_needed(wrapped)

func _apply_law(peer_id: int, law_type: String) -> void:
	if not can_propose_law(peer_id, law_type):
		return
	_event_message = ""
	if not GovernmentManager.submit_law(peer_id, law_type):
		return
	mana[peer_id] = mana_of(peer_id) - law_mana_cost(peer_id, law_type)
	law_rounds[peer_id] = round_number
	var event := {"type": "law", "peer_id": peer_id, "law": law_type}
	if _event_message != "":
		event["message"] = _event_message
	_push_state(event)

func _apply_organization(peer_id: int, province_id: String) -> void:
	if not can_build_organization(peer_id, province_id):
		return
	mana[peer_id] = mana_of(peer_id) - GameRules.ORG_MANA_COST
	var entry: Dictionary = organizations.get(province_id, {})
	var level := int(entry.get(peer_id, 0)) + 1
	entry[peer_id] = level
	organizations[province_id] = entry
	var verb := "kurdu" if level == 1 else "geliştirdi"
	_log_province(province_id, "%s teşkilat %s (seviye %d)" % [_party_name(peer_id), verb, level])
	# Teşkilat seçmeni de partiye yaklaştırır (ve parti içini toparlar).
	_pull_province(province_id, peer_id, PublicOpinion.ORG_PULL)
	_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_ORG)
	_push_state({"type": "organization", "peer_id": peer_id, "province": province_id,
		"message": "%s, %s'da teşkilat %s (seviye %d)." % [_party_name(peer_id), _province_name(province_id), verb, level]})

func _apply_invest_move(peer_id: int, province_id: String) -> void:
	if not can_invest(peer_id, province_id):
		return
	mana[peer_id] = mana_of(peer_id) - GameRules.INVEST_MANA_COST
	_event_message = ""
	_apply_investment(peer_id, province_id)
	_push_state({"type": "invest", "peer_id": peer_id, "province": province_id, "message": _event_message})

func _apply_censure_move(peer_id: int) -> void:
	if not can_censure(peer_id):
		return
	mana[peer_id] = mana_of(peer_id) - GameRules.CENSURE_MANA_COST
	_push_state({"type": "censure", "peer_id": peer_id,
		"message": "%s hükümete gensoru verdi: meclis oylaması başladı." % _party_name(peer_id)})
	GovernmentManager.submit_censure(peer_id)

func _apply_miting_move(peer_id: int, province_id: String) -> void:
	if not can_miting(peer_id, province_id):
		return
	mana[peer_id] = mana_of(peer_id) - GameRules.MITING_MANA_COST
	_event_message = ""
	_apply_miting(peer_id, province_id)
	_push_state({"type": "miting", "peer_id": peer_id, "province": province_id, "message": _event_message})

## Kartın etkisini uygular. Milletvekili dağılımı değiştiyse true döner.
## Herkese duyurulacak bir sonuç varsa _event_message'a yazar.
func _apply_card_effect(peer_id: int, card_type: String, target_peer_id: int = -1, target_province: String = "") -> bool:
	if CardPresets.needs_target(card_type):
		return _apply_steal(peer_id, target_peer_id, card_type)
	match card_type:
		CardPresets.REPUTATION_CARD_TYPE:
			_apply_reputation(peer_id, target_peer_id)
		CardPresets.REBELLION_CARD_TYPE:
			# İÇ KARIŞIKLIK: ulusal destek düşer, partide (gizli) karışıklık büyür.
			_add_national(target_peer_id, -PublicOpinion.REBELLION_NATIONAL_DAMAGE)
			_add_turmoil(target_peer_id, PublicOpinion.TURMOIL_REBELLION)
			_event_message = "%s'da iç karışıklık çıktı: parti sarsıldı, ulusal desteği düştü. (%s)" % [
				_party_name(target_peer_id), _party_name(peer_id)]
		CardPresets.CARD_THEFT_CARD_TYPE:
			_apply_card_theft(peer_id, target_peer_id)
		CardPresets.BONUS_CARD_TYPE:
			var drawn := 0
			for i in GameRules.BONUS_CARD_DRAW:
				if _deal_turn_card(peer_id) != "":
					drawn += 1
			_event_message = "%s bonus kart kullandı (+%d kart)." % [_party_name(peer_id), drawn]
		CardPresets.MANA_BONUS_STRONG_CARD_TYPE:
			mana[peer_id] = mana_of(peer_id) + GameRules.MANA_BONUS_STRONG
			_event_message = "%s güçlü mana bonusu kullandı (+%d mana)." % [_party_name(peer_id), GameRules.MANA_BONUS_STRONG]
		CardPresets.EARLY_ELECTION_CARD_TYPE:
			GovernmentManager.submit_early_election(peer_id)
			_event_message = "%s erken seçim önergesi verdi." % _party_name(peer_id)
		CardPresets.POPULISM_CARD_TYPE:
			populism[peer_id] = round_number + GameRules.POPULISM_ROUNDS
			_event_message = "%s popülizme başladı: %d dönem boyunca hamleleri daha etkili." % [_party_name(peer_id), GameRules.POPULISM_ROUNDS]
		CardPresets.MANA_BONUS_CARD_TYPE:
			mana[peer_id] = mana_of(peer_id) + GameRules.MANA_BONUS_WEAK
			_event_message = "%s mana bonusu kullandı (+%d mana)." % [_party_name(peer_id), GameRules.MANA_BONUS_WEAK]
		CardPresets.PROPAGANDA_CARD_TYPE:
			_apply_propaganda(peer_id, target_peer_id, target_province)
	return false

func _party_name(peer_id: int) -> String:
	return PartyManager.parties.get(peer_id, {}).get("name", "?")

## KART ÇALMA: hedefin elinden rastgele bir kart alınır (el doluysa kart yanar).
## Hangi kartın çalındığı herkese duyurulmaz.
func _apply_card_theft(peer_id: int, target_peer_id: int) -> void:
	var hand: Array = inventories.get(target_peer_id, [])
	if hand.is_empty():
		_event_message = "%s, %s'ın elinden kart çalmaya kalktı ama elinde hiç kart yoktu." % [
			_party_name(peer_id), _party_name(target_peer_id)]
		return
	var card: String = hand[_rng.randi_range(0, hand.size() - 1)]
	hand.erase(card)
	var mine: Array = inventories.get(peer_id, [])
	if mine.size() < MAX_HAND_SIZE:
		mine.append(card)
		inventories[peer_id] = mine
	_event_message = "%s, %s'ın elinden bir kart çaldı." % [_party_name(peer_id), _party_name(target_peer_id)]

func _province_name(province_id: String) -> String:
	return GameMap.name_of(province_id)

## Miting: riski ilin mevcut siyasi dengesine göre hesaplanır, zar atılır.
func _apply_miting(peer_id: int, province_id: String) -> void:
	var risk := miting_risk(peer_id, province_id)
	if is_referendum_active():
		_apply_referendum_miting(peer_id, province_id, risk)
		return
	if _rng.randf() < risk:
		_add_local(province_id, peer_id, PublicOpinion.PROVOCATION_LOCAL, true)
		_add_national(peer_id, PublicOpinion.PROVOCATION_NATIONAL, true)
		_log_province(province_id, "%s mitinginde PROVOKASYON (il %.1f, ulusal %.1f)" % [
			_party_name(peer_id), PublicOpinion.PROVOCATION_LOCAL, PublicOpinion.PROVOCATION_NATIONAL])
		_event_message = "%s'da %s mitinginde provokasyon çıktı! (risk %%%d)" % [
			_province_name(province_id), _party_name(peer_id), int(round(risk * 100.0))]
	else:
		var org_mult := PublicOpinion.org_action_mult(organization_level(province_id, peer_id))
		_add_local(province_id, peer_id, PublicOpinion.MITING_LOCAL * org_mult, true)
		_add_national(peer_id, PublicOpinion.MITING_NATIONAL * org_mult, true)
		_log_province(province_id, "%s miting yaptı (+%.1f)" % [_party_name(peer_id), PublicOpinion.MITING_LOCAL * org_mult])
		_pull_province(province_id, peer_id, PublicOpinion.MITING_PULL)
		_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_MITING)
		_campaign_in(province_id, peer_id, 1.0)
		_event_message = "%s, %s'da miting yaptı." % [_party_name(peer_id), _province_name(province_id)]

## Yatırım: getiren parti daha çok, hükümet ortakları daha az kazanır.
## Popülizm yatırımı büyütmez (popülist iktidar için miting daha etkili).
func _apply_investment(peer_id: int, province_id: String) -> void:
	_add_local(province_id, peer_id, PublicOpinion.INVEST_LOCAL)
	_add_national(peer_id, PublicOpinion.INVEST_NATIONAL)
	for partner in GovernmentManager.government_party_ids():
		if partner != peer_id:
			_add_local(province_id, partner, PublicOpinion.INVEST_PARTNER_LOCAL)
	_pull_province(province_id, peer_id, PublicOpinion.INVEST_PULL)
	_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_INVEST)
	_add_kale_effort(province_id, peer_id, 1.0)
	_log_province(province_id, "Hükümet yatırımı — %s getirdi (+%.1f, ortaklar +%.1f)" % [
		_party_name(peer_id), PublicOpinion.INVEST_LOCAL, PublicOpinion.INVEST_PARTNER_LOCAL])
	_event_message = "%s, %s'a hükümet yatırımı getirdi." % [_party_name(peer_id), _province_name(province_id)]

## Karalama: hedefe eksi, karalayana artı; ikisi de o ildeki güçleriyle ölçeklenir.
func _apply_propaganda(peer_id: int, target_peer_id: int, province_id: String) -> void:
	if is_referendum_active():
		_apply_referendum_propaganda(peer_id, target_peer_id, province_id)
		return
	var damage := PublicOpinion.propaganda_damage(party_strength(province_id, target_peer_id))
	if populism_rounds_left(peer_id) > 0:
		damage *= PublicOpinion.POPULISM_GOOD_MULT
	var org_mult := PublicOpinion.org_action_mult(organization_level(province_id, peer_id))
	damage *= org_mult
	# KALE: kalesinde karalanan partiye hasar az işler; karalama kuşatmaya sayılır.
	if stronghold_of(province_id) == target_peer_id:
		damage *= PublicOpinion.STRONGHOLD_DAMAGE_MULT
		_add_siege(province_id, peer_id, PublicOpinion.SIEGE_PROPAGANDA)
	var gain := PublicOpinion.propaganda_gain(party_strength(province_id, peer_id)) * org_mult
	# Taban: karalama il puanını PROPAGANDA_FLOOR'un altına itemez.
	var current := local_of(province_id, target_peer_id)
	damage = clampf(damage, 0.0, maxf(0.0, current - PublicOpinion.PROPAGANDA_FLOOR))
	_add_local(province_id, target_peer_id, -damage)
	_add_local(province_id, peer_id, gain, true)
	_log_province(province_id, "%s, %s karşıtı kampanya yaptı (%s −%.1f, %s +%.1f)" % [
		_party_name(peer_id), _party_name(target_peer_id), _party_name(target_peer_id), damage, _party_name(peer_id), gain])
	_event_message = "%s, %s'da %s karşıtı karalama kampanyası yaptı." % [
		_party_name(peer_id), _province_name(province_id), _party_name(target_peer_id)]

## GovernmentManager, bir yasa oylaması sonuçlanınca (host) çağırır. Etkiler
## PARTİ PUANINA değil, İL İL aktiviteye yazılır (bkz. PublicOpinion yasa kuralları).
##   votes  : peer_id -> GovernmentManager.VOTE_*
##   gov_ids: yasa meclise geldiği andaki hükümet partileri
func apply_law_result(proposer: int, law_type: String, votes: Dictionary, passed: bool, gov_ids: Array) -> void:
	if not _is_authority():
		return
	var law := CardPresets.law_data(law_type)
	if law.is_empty():
		return
	var axis: String = law["axis"]
	var dir: int = int(law["dir"])
	var proposer_in_gov := gov_ids.has(proposer)
	var agenda_mult := agenda_law_mult(law_type)
	for province_id in _province_ids:
		var alignment := PublicOpinion.law_alignment(province_center(province_id), axis, dir)
		_add_local(province_id, proposer, PublicOpinion.law_proposer_delta(alignment, passed) * agenda_mult, true)
		for voter in votes.keys():
			if int(voter) == proposer:
				continue
			var choice := GovernmentManager.normalize_vote(votes[voter])
			_add_local(province_id, int(voter), PublicOpinion.law_vote_delta(alignment, choice, gov_ids.has(voter), proposer_in_gov) * agenda_mult, true)
	# KOALİSYON UYUMU: başbakanın partisinin yasasına hükümet ortağının oyu
	# ulusal puana yansır (kısmi).
	var pm_party := GovernmentManager.main_gov_peer_id
	if proposer == pm_party and pm_party != -1:
		for voter in votes.keys():
			var partner := int(voter)
			if partner == proposer or not gov_ids.has(partner):
				continue
			var partner_choice := GovernmentManager.normalize_vote(votes[voter])
			if partner_choice == GovernmentManager.VOTE_YES:
				_add_national(partner, PublicOpinion.LAW_PARTNER_YES_NATIONAL)
			elif partner_choice == GovernmentManager.VOTE_NO:
				_add_national(partner, PublicOpinion.LAW_PARTNER_NO_NATIONAL)
				_add_national(pm_party, PublicOpinion.LAW_PM_PARTNER_NO_NATIONAL)
	# Görüş kayması: sunan yasanın yönünde 1 adım, EVET yasanın yönünde,
	# HAYIR ters yönde yarım adım; çekimser kaymaz.
	var shifts: Array = [{"peer": proposer, "axis": axis, "delta": IdeologyAxes.LAW_PROPOSE_SHIFT * dir}]
	for voter in votes.keys():
		if int(voter) == proposer:
			continue
		var choice := GovernmentManager.normalize_vote(votes[voter])
		if choice != GovernmentManager.VOTE_ABSTAIN:
			shifts.append({"peer": int(voter), "axis": axis, "delta": IdeologyAxes.LAW_VOTE_SHIFT * dir * choice})
	var before := {}
	for change in shifts:
		before[change["peer"]] = float(PartyManager.parties.get(change["peer"], {}).get("ideology", {}).get(axis, 0.0))
	_shift_ideologies(shifts)
	var notes := ""
	# TABAN GÜVENİ: radikalleşen ya da yerleşik görüşünden dönen parti ulusal
	# destek kaybeder (bkz. PublicOpinion.ideology_shift_national).
	var shaken: Array = []
	for peer in before.keys():
		var after := float(PartyManager.parties.get(peer, {}).get("ideology", {}).get(axis, 0.0))
		var penalty := PublicOpinion.ideology_shift_national(float(before[peer]), after)
		if penalty < 0.0:
			_add_national(int(peer), penalty, true)
			shaken.append(_party_name(int(peer)))
	if not shaken.is_empty():
		notes += " Görüş değişimi tabanı sarstı: %s." % ", ".join(PackedStringArray(shaken))
	# Yasa, illerin seçmenini kendi ekseninde sunanın görüşüne doğru çeker.
	var proposer_ideology: Dictionary = PartyManager.parties.get(proposer, {}).get("ideology", {})
	for province_id in _province_ids:
		_pull_province(province_id, proposer, PublicOpinion.LAW_PULL_PASSED if passed else PublicOpinion.LAW_PULL_REJECTED,
			axis, proposer_ideology, false)
	_refresh_all_strongholds()
	if passed:
		notes += " %s +%d puan." % [_party_name(proposer), law_pass_score(proposer_in_gov)]
		_ease_turmoil(proposer, PublicOpinion.TURMOIL_EASE_LAW)
	_push_state({"type": "opinion", "peer_id": proposer, "message": "%s %s — %s bu görüşe yakın illerde güçlendi%s. Partisi %s yönüne kaydı.%s" % [
		law["title"], "KABUL EDİLDİ" if passed else "reddedildi", _party_name(proposer),
		" (2 kat)" if passed else "", law["side"], notes]})

## Kabul edilen yasanın getiren partiye yazdığı puan.
static func law_pass_score(proposer_in_gov: bool) -> int:
	return GameRules.LAW_PASS_SCORE_GOV if proposer_in_gov else GameRules.LAW_PASS_SCORE

# --- Gündem ------------------------------------------------------------------------

## Şu an gündemdeki konu (gündem kartı türü) ya da "".
func agenda_type() -> String:
	if agenda.is_empty() or round_number >= int(agenda.get("until", 0)):
		return ""
	return String(agenda.get("type", ""))

func agenda_rounds_left() -> int:
	return maxi(0, int(agenda.get("until", 0)) - round_number) if agenda_type() != "" else 0

## Bu yasa gündemdeki eksende mi? (Sadece gündemdeki eksende yasa sunulabilir.)
func law_on_agenda(law_type: String) -> bool:
	var current := agenda_type()
	if current == "":
		return false
	var law := CardPresets.law_data(law_type)
	var data := CardPresets.agenda_data(current)
	return not law.is_empty() and not data.is_empty() and law["axis"] == data["axis"]

## Gündem çarpanı artık hep 1: gündem etkileri büyütmez (bkz. PublicOpinion).
func agenda_law_mult(law_type: String) -> float:
	var current := agenda_type()
	if current == "":
		return 1.0
	var law := CardPresets.law_data(law_type)
	var data := CardPresets.agenda_data(current)
	if law.is_empty() or data.is_empty() or law["axis"] != data["axis"]:
		return 1.0
	return PublicOpinion.AGENDA_MATCH_MULT if int(law["dir"]) == int(data["dir"]) else PublicOpinion.AGENDA_AXIS_MULT

## Yeni turun gündemi takvimden: ilk seçimden sonraki turdan itibaren
## AGENDA_ROUNDS tur gündem (her tur farklı eksen), AGENDA_GAP tur ara.
func _schedule_agenda() -> void:
	var k := round_number - (GameRules.FIRST_ELECTION_ROUND + 1)
	if k < 0 or last_seats.is_empty():
		agenda = {}
		return
	var pos := k % (GameRules.AGENDA_ROUNDS + GameRules.AGENDA_GAP)
	if pos >= GameRules.AGENDA_ROUNDS:
		var was_active := not agenda.is_empty()
		agenda = {}
		if was_active and pos == GameRules.AGENDA_ROUNDS:
			_push_state({"type": "agenda", "message": "Gündem arası: %d dönem yasa yok, sonra yeni gündemler." % GameRules.AGENDA_GAP})
		return
	# Eksenler karıştırılmış bir sıradan tüketilir: arka arkaya gelen iki gündem
	# (aynı dönemde ya da iki dönem arasında) hep farklı eksenden olur.
	if _agenda_axes.is_empty():
		_agenda_axes = IdeologyAxes.AXES.duplicate()
		for i in range(_agenda_axes.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp = _agenda_axes[i]
			_agenda_axes[i] = _agenda_axes[j]
			_agenda_axes[j] = tmp
		if _agenda_axes.size() > 1 and String(_agenda_axes[0]) == _last_agenda_axis:
			_agenda_axes.push_back(_agenda_axes.pop_front())
	var axis: String = String(_agenda_axes.pop_front())
	_last_agenda_axis = axis
	var type := "gundem_%s_%s" % [axis, "p" if _rng.randf() < 0.5 else "n"]
	agenda = {"type": type, "until": round_number + 1, "index": pos + 1}
	var data := CardPresets.agenda_data(type)
	_push_state({"type": "agenda", "message": "GÜNDEM (%d/%d): %s — bu dönem %s." % [pos + 1, GameRules.AGENDA_ROUNDS,
		data["title"], CardPresets.agenda_effect_text(type)]})

## GovernmentManager, reddedilen gensorudan sonra (host) çağırır: getiren parti
## ulusal destek kaybeder. Durum GovernmentManager'ın yayınıyla birlikte gider.
func apply_censure_rejected(peer_id: int) -> void:
	if not _is_authority():
		return
	_add_national(peer_id, PublicOpinion.CENSURE_REJECTED_NATIONAL, true)
	_push_state({"type": "opinion"})

## Popülizm süren partinin kendi hamlesinin etkisi: iyisi büyür, kötüsü küçülür.
func _own_effect(peer_id: int, amount: float) -> float:
	if populism_rounds_left(peer_id) <= 0:
		return amount
	return amount * (PublicOpinion.POPULISM_GOOD_MULT if amount > 0.0 else PublicOpinion.POPULISM_BAD_MULT)

## Başka bir sistemin (ör. GovernmentManager) ulusal puan uygulaması için.
func add_national_points(peer_id: int, amount: float) -> void:
	_add_national(peer_id, amount)

## own=true: parti bu etkiyi KENDİ hamlesiyle aldı (popülizm uygulanır).
func _add_national(peer_id: int, amount: float, own: bool = false) -> void:
	if own:
		amount = _own_effect(peer_id, amount)
	if amount == 0.0 or peer_id == -1:
		return
	national_support[peer_id] = PublicOpinion.clamp_points(national_of(peer_id) + amount)

func _add_local(province_id: String, peer_id: int, amount: float, own: bool = false) -> void:
	if own:
		amount = _own_effect(peer_id, amount)
	if amount == 0.0 or peer_id == -1:
		return
	var entry: Dictionary = local_support.get(province_id, {})
	entry[peer_id] = PublicOpinion.clamp_points(float(entry.get(peer_id, 0.0)) + amount)
	local_support[province_id] = entry

func _log_province(province_id: String, text: String) -> void:
	var events: Array = province_events.get(province_id, [])
	events.append({"round": round_number, "text": text})
	while events.size() > PROVINCE_EVENT_LIMIT:
		events.pop_front()
	province_events[province_id] = events

# --- Referandum ----------------------------------------------------------------------

func is_referendum_active() -> bool:
	return not referendum.is_empty()

## Kaç tur kaldı (içinde bulunulan tur dahil).
func referendum_rounds_left() -> int:
	if referendum.is_empty():
		return 0
	return maxi(1, int(referendum["end_round"]) - round_number + 1)

## Partinin referandumdaki kararı: VOTE_YES / VOTE_NO / VOTE_ABSTAIN.
func referendum_side(peer_id: int) -> int:
	return int(referendum.get("sides", {}).get(peer_id, GovernmentManager.VOTE_ABSTAIN))

func referendum_side_text(peer_id: int) -> String:
	match referendum_side(peer_id):
		GovernmentManager.VOTE_YES:
			return "EVET"
		GovernmentManager.VOTE_NO:
			return "HAYIR"
	return "çekimser"

## GovernmentManager: anayasa değişikliği salt çoğunluğu aştı ama 2/3'te kaldı.
## Referandum bu andan itibaren TAM 2 TUR sürer (bir sonraki turun sonunda sonuç).
func start_referendum(proposer: int, payload: Dictionary, votes: Dictionary) -> void:
	if not _is_authority():
		return
	var sides := {}
	for peer_id in turn_order:
		sides[peer_id] = GovernmentManager.normalize_vote(votes.get(peer_id, GovernmentManager.VOTE_ABSTAIN)) \
			if votes.has(peer_id) else GovernmentManager.VOTE_ABSTAIN
	referendum = {"proposer": proposer, "payload": payload.duplicate(), "sides": sides,
		"start_round": round_number, "end_round": round_number + 1,
		"national": {}, "local": {}, "postponed": false, "postponed_final": false}
	_push_state({"type": "referendum_start"})

func _ref_add_national(peer_id: int, amount: float, own: bool = false) -> void:
	if own:
		amount = _own_effect(peer_id, amount)
	var national: Dictionary = referendum.get("national", {})
	national[peer_id] = PublicOpinion.clamp_points(float(national.get(peer_id, 0.0)) + amount)
	referendum["national"] = national

func _ref_add_local(province_id: String, peer_id: int, amount: float, own: bool = false) -> void:
	if own:
		amount = _own_effect(peer_id, amount)
	var local: Dictionary = referendum.get("local", {})
	var entry: Dictionary = local.get(province_id, {})
	entry[peer_id] = PublicOpinion.clamp_points(float(entry.get(peer_id, 0.0)) + amount)
	local[province_id] = entry
	referendum["local"] = local

func ref_local_of(province_id: String, peer_id: int) -> float:
	return float(referendum.get("local", {}).get(province_id, {}).get(peer_id, 0.0))

func ref_national_of(peer_id: int) -> float:
	return float(referendum.get("national", {}).get(peer_id, 0.0))

## Referandum mitingi: partinin KARARINI halka benimsetir (genel seçime etkisi yok).
func _apply_referendum_miting(peer_id: int, province_id: String, risk: float) -> void:
	var side := referendum_side_text(peer_id)
	if _rng.randf() < risk:
		_ref_add_local(province_id, peer_id, PublicOpinion.PROVOCATION_LOCAL, true)
		_ref_add_national(peer_id, PublicOpinion.PROVOCATION_NATIONAL, true)
		_log_province(province_id, "%s referandum mitinginde PROVOKASYON" % _party_name(peer_id))
		_event_message = "%s'da %s'ın \"%s\" mitinginde provokasyon çıktı! (risk %%%d)" % [
			_province_name(province_id), _party_name(peer_id), side, int(round(risk * 100.0))]
		return
	_ref_add_local(province_id, peer_id, PublicOpinion.MITING_LOCAL, true)
	_ref_add_national(peer_id, PublicOpinion.MITING_NATIONAL, true)
	_log_province(province_id, "%s referandum mitingi: \"%s\"" % [_party_name(peer_id), side])
	_event_message = "%s, %s'da \"%s\" mitingi yaptı (referandum)." % [_party_name(peer_id), _province_name(province_id), side]

## Referandum karalaması: hedefin (ve kararının) o ildeki inandırıcılığı düşer,
## karalayanınki artar. Genel seçime etkisi yok.
func _apply_referendum_propaganda(peer_id: int, target_peer_id: int, province_id: String) -> void:
	var damage := PublicOpinion.propaganda_damage(party_strength(province_id, target_peer_id))
	if populism_rounds_left(peer_id) > 0:
		damage *= PublicOpinion.POPULISM_GOOD_MULT
	var gain := PublicOpinion.propaganda_gain(party_strength(province_id, peer_id))
	damage = clampf(damage, 0.0, maxf(0.0, ref_local_of(province_id, target_peer_id) - PublicOpinion.PROPAGANDA_FLOOR))
	_ref_add_local(province_id, target_peer_id, -damage)
	_ref_add_local(province_id, peer_id, gain, true)
	_log_province(province_id, "%s, %s'ın \"%s\" kampanyasını karaladı" % [
		_party_name(peer_id), _party_name(target_peer_id), referendum_side_text(target_peer_id)])
	_event_message = "%s, %s'da %s'ın \"%s\" kampanyasına karşı karalama yaptı (referandum)." % [
		_party_name(peer_id), _province_name(province_id), _party_name(target_peer_id), referendum_side_text(target_peer_id)]

## HALKOYU TAHMİNİ (rastgelesiz). Her ilde partilerin beklenen oy payları
## (seçim modeli) × kampanya gücü; partinin seçmeni partinin kararına oy verir,
## çekimser partinin seçmeni ikiye bölünür. Ülke sonucu il vekil sayısıyla
## ağırlıklı ortalama. Dönüş: {"yes": %, "no": %, "provinces": il -> EVET %}.
func referendum_projection() -> Dictionary:
	if referendum.is_empty():
		return {}
	var mods := election_modifiers()
	var local_mods: Dictionary = mods["local"]
	var ideologies := _ideologies()
	var national_expected := _expected_national(mods)
	var provinces := {}
	var yes_total := 0.0
	var weight_total := 0.0
	for province_id in _province_ids:
		var shares := ElectionModel.expected_shares(ideologies, province_center(province_id), current_axis_sharpness,
			mods["national"], local_mods.get(province_id, {}), national_expected)
		var yes := 0.0
		var no := 0.0
		for peer_id in shares.keys():
			var w := float(shares[peer_id]) * PublicOpinion.referendum_multiplier(ref_national_of(int(peer_id)),
				ref_local_of(province_id, int(peer_id)))
			match referendum_side(int(peer_id)):
				GovernmentManager.VOTE_YES:
					yes += w
				GovernmentManager.VOTE_NO:
					no += w
				_:
					yes += w * 0.5
					no += w * 0.5
		var pct := yes / maxf(0.0001, yes + no) * 100.0
		provinces[province_id] = pct
		var seats := float(province_seat_count(province_id))
		yes_total += pct * seats
		weight_total += seats
	var national_yes := yes_total / maxf(1.0, weight_total)
	return {"yes": national_yes, "no": 100.0 - national_yes, "provinces": provinces}

## Tur sonu referandum işleri. true dönerse _finish_round burada biter.
func _referendum_round_end(finished_round: int) -> bool:
	var no_government := not last_seats.is_empty() and not GovernmentManager.has_government() \
		and GovernmentManager.phase == GovernmentManager.Phase.IDLE
	var is_final := finished_round >= GameRules.MAX_ROUNDS
	var wants_election := is_final or early_election_pending or GameRules.is_election_round(finished_round) or no_government
	if finished_round < int(referendum["end_round"]):
		# Kampanya sürüyor: seçim varsa referandum sonrasına ERTELENİR.
		var message := ""
		if wants_election and not bool(referendum["postponed"]):
			message = "Seçim, referandum sonuçlanana kadar ertelendi."
		if wants_election:
			referendum["postponed"] = true
			referendum["postponed_final"] = bool(referendum["postponed_final"]) or is_final
			early_election_pending = false
		_decay_opinion()
		var event := {"type": "round"}
		if message != "":
			event["message"] = message
		_push_state(event)
		_schedule_agenda()
		return true
	# Referandum bitti: halk karar verir.
	var postponed: bool = bool(referendum["postponed"]) or wants_election
	var postponed_final: bool = bool(referendum["postponed_final"]) or is_final
	early_election_pending = false
	_resolve_referendum()
	if postponed_final:
		final_election_pending = true
		_hold_election(finished_round, false)
		return true
	if postponed:
		# Ertelenen seçim şimdi; takvim buradan itibaren yeniden işler.
		election_anchor = finished_round
		GameRules.set_election_anchor(election_anchor)
		_hold_election(finished_round, false)
		_schedule_agenda()
		return true
	return false

func _resolve_referendum() -> void:
	var projection := referendum_projection()
	var yes := clampf(float(projection.get("yes", 50.0)) + _rng.randf_range(-PublicOpinion.REFERENDUM_NOISE, PublicOpinion.REFERENDUM_NOISE), 0.0, 100.0)
	var passed := yes > 50.0
	var payload: Dictionary = referendum["payload"]
	var proposer := int(referendum["proposer"])
	referendum = {}
	var text := "REFERANDUM SONUCU: EVET %%%s – HAYIR %%%s. Anayasa değişikliği halk tarafından %s." % [
		String.num(yes, 1), String.num(100.0 - yes, 1), "KABUL EDİLDİ" if passed else "REDDEDİLDİ"]
	if passed:
		MultiplayerManager.apply_constitution(payload)
		rebase_election_calendar()
		text += " Yeni baraj %%%s, seçimler %d yılda bir, sayım: %s." % [
			String.num(MultiplayerManager.election_threshold, 1), MultiplayerManager.election_interval,
			ElectionModel.method_title(MultiplayerManager.seat_method)]
	_push_state({"type": "referendum_end", "peer_id": proposer, "message": text})

# --- Siyasi kale -------------------------------------------------------------------

## İlin seçmen merkezini partinin görüşüne doğru çeker (kaledeyse rakip yavaş).
func _pull_province(province_id: String, peer_id: int, rate: float, axis_only: String = "",
		target: Dictionary = {}, update: bool = true) -> void:
	if not province_ideology.has(province_id):
		return
	if target.is_empty():
		target = PartyManager.parties.get(peer_id, {}).get("ideology", {})
	var owner := int(strongholds.get(province_id, -1))
	var shielded := owner != -1 and owner != peer_id
	province_ideology[province_id] = PublicOpinion.pull_center(province_ideology[province_id], target, rate, shielded, axis_only)
	if update:
		_update_stronghold(province_id)

func stronghold_of(province_id: String) -> int:
	return int(strongholds.get(province_id, -1))

func stronghold_closeness(province_id: String, peer_id: int) -> float:
	var ideology: Dictionary = PartyManager.parties.get(peer_id, {}).get("ideology", {})
	return PublicOpinion.stronghold_closeness(ideology, province_center(province_id))

func kale_effort_of(province_id: String, peer_id: int) -> float:
	return float(kale_effort.get(province_id, {}).get(peer_id, 0.0))

## Kale şartları: teşkilat TAM, kale emeği (miting/yatırım) yeterli ve seçmen
## partiye yakın.
func can_hold_stronghold(province_id: String, peer_id: int) -> bool:
	return organization_level(province_id, peer_id) >= GameRules.ORG_MAX_LEVEL \
		and kale_effort_of(province_id, peer_id) >= PublicOpinion.STRONGHOLD_EFFORT \
		and stronghold_closeness(province_id, peer_id) >= PublicOpinion.STRONGHOLD_THRESHOLD

## Kalenin kuşatma toplamı (0..SIEGE_BREAK).
func siege_total(province_id: String) -> float:
	var total := 0.0
	for value in siege.get(province_id, {}).values():
		total += float(value)
	return total

func _add_kale_effort(province_id: String, peer_id: int, amount: float) -> void:
	var entry: Dictionary = kale_effort.get(province_id, {})
	entry[peer_id] = float(entry.get(peer_id, 0.0)) + amount
	kale_effort[province_id] = entry
	_update_stronghold(province_id)

## İlde miting: kale emeği birikir. Başkasının kalesindeyse KUŞATMA, kendi
## kalesindeyse SAVUNMA (kuşatma geriler).
func _campaign_in(province_id: String, peer_id: int, amount: float) -> void:
	var owner := stronghold_of(province_id)
	if owner == peer_id:
		_defend_stronghold(province_id, PublicOpinion.SIEGE_DEFENSE * amount)
	elif owner != -1:
		_add_siege(province_id, peer_id, amount)
	_add_kale_effort(province_id, peer_id, amount)

## Rakibin kuşatma puanı: benzer görüşteki rakip daha çok puan ve daha yüksek
## tavan alır (kalenin seçmenini daha kolay ikna eder). Tek parti tavanı
## SIEGE_BREAK'in altında: kaleyi düşürmek en az 2-3 partinin işidir.
func _add_siege(province_id: String, attacker: int, amount: float) -> void:
	var owner := stronghold_of(province_id)
	if owner == -1 or attacker == owner:
		return
	var similarity := PublicOpinion.siege_similarity(
		PartyManager.parties.get(attacker, {}).get("ideology", {}), PartyManager.parties.get(owner, {}).get("ideology", {}))
	var entry: Dictionary = siege.get(province_id, {})
	var cap := PublicOpinion.SIEGE_PARTY_CAP + PublicOpinion.SIEGE_SIMILAR_CAP * similarity
	entry[attacker] = minf(float(entry.get(attacker, 0.0)) + amount * (1.0 + similarity), cap)
	siege[province_id] = entry
	if siege_total(province_id) >= PublicOpinion.SIEGE_BREAK - 0.001:
		_break_stronghold(province_id)

func _defend_stronghold(province_id: String, amount: float) -> void:
	var total := siege_total(province_id)
	if total <= 0.0:
		return
	var keep := maxf(0.0, total - amount) / total
	var entry: Dictionary = siege.get(province_id, {})
	for peer_id in entry.keys():
		entry[peer_id] = float(entry[peer_id]) * keep
	siege[province_id] = entry

## Kuşatma başarılı: kale düşer, sahibinin kale emeği sıfırlanır.
func _break_stronghold(province_id: String) -> void:
	var owner := stronghold_of(province_id)
	if owner == -1:
		return
	var attackers: Array = []
	for peer_id in siege.get(province_id, {}).keys():
		attackers.append(_party_name(int(peer_id)))
	strongholds.erase(province_id)
	siege.erase(province_id)
	var effort: Dictionary = kale_effort.get(province_id, {})
	effort.erase(owner)
	kale_effort[province_id] = effort
	_add_local(province_id, owner, PublicOpinion.STRONGHOLD_FALL_LOCAL)
	_log_province(province_id, "%s'nın kalesi kuşatmayla düştü (%s)" % [_party_name(owner), ", ".join(PackedStringArray(attackers))])
	_pending_log.append({"text": "%s'daki %s kalesi düştü! Kuşatanlar: %s." % [_province_name(province_id), _party_name(owner),
		", ".join(PackedStringArray(attackers))], "peer_id": owner, "province": province_id, "kind": "stronghold_lost"})
	_update_stronghold(province_id)

## Kale kurulur: şartları (can_hold_stronghold) sağlayan, kale emeği en yüksek
## parti. Kale kolay yıkılmaz: sahibi ancak KUŞATMAYLA (bkz. _add_siege), oyundan
## çıkarak ya da görüşünü ilden çok uzaklaştırarak (STRONGHOLD_LOSS_THRESHOLD) kaybeder.
func _update_stronghold(province_id: String) -> void:
	var owner := stronghold_of(province_id)
	var new_owner := owner
	if owner != -1 and (not turn_order.has(owner) \
			or stronghold_closeness(province_id, owner) < PublicOpinion.STRONGHOLD_LOSS_THRESHOLD \
			or kale_effort_of(province_id, owner) < PublicOpinion.STRONGHOLD_KEEP_EFFORT):
		new_owner = -1
	if new_owner == -1:
		var best_effort := 0.0
		for peer_id in turn_order:
			if not can_hold_stronghold(province_id, int(peer_id)):
				continue
			var effort := kale_effort_of(province_id, int(peer_id))
			if effort > best_effort:
				best_effort = effort
				new_owner = int(peer_id)
	if new_owner == owner:
		return
	siege.erase(province_id)
	if owner != -1:
		_log_province(province_id, "%s bu ildeki siyasi kalesini kaybetti" % _party_name(owner))
		_pending_log.append({"text": "%s, %s'daki siyasi kalesini kaybetti." % [_party_name(owner), _province_name(province_id)],
			"peer_id": owner, "province": province_id, "kind": "stronghold_lost"})
	if new_owner == -1:
		strongholds.erase(province_id)
	else:
		strongholds[province_id] = new_owner
		_log_province(province_id, "%s bu ili SİYASİ KALESİ yaptı" % _party_name(new_owner))
		_pending_log.append({"text": "%s, %s bölgesini siyasi kalesi yaptı." % [_party_name(new_owner), _province_name(province_id)],
			"peer_id": new_owner, "province": province_id, "kind": "stronghold"})

## Tur sonu: her il doğal görüşüne biraz geri döner (bkz. PROVINCE_REVERSION).
func _revert_provinces() -> void:
	for province_id in province_ideology.keys():
		var origin: Dictionary = _province_origin.get(province_id, {})
		if origin.is_empty():
			continue
		province_ideology[province_id] = PublicOpinion.pull_center(province_ideology[province_id], origin,
			PublicOpinion.PROVINCE_REVERSION, false)
	_refresh_all_strongholds()

## Tur sonu: teşkilatlar bulundukları ilin seçmenini her tur biraz daha
## partilerine çeker (seviye başına ORG_ROUND_PULL).
func _org_pressure() -> void:
	for province_id in organizations.keys():
		if not province_ideology.has(province_id):
			continue
		var orgs: Dictionary = organizations[province_id]
		for peer_id in orgs.keys():
			var level := int(orgs[peer_id])
			if level > 0 and turn_order.has(int(peer_id)):
				_pull_province(String(province_id), int(peer_id), PublicOpinion.ORG_ROUND_PULL * level, "", {}, false)

## Tur sonu KALE BAKIMI: kale emeği azalır (ihmal edilen kale düşer) ve ilde
## beklenen oyda sahibini geçen bir parti varsa kale düşer.
func _check_stronghold_upkeep() -> void:
	for province_id in kale_effort.keys():
		var entry: Dictionary = kale_effort[province_id]
		for peer_id in entry.keys():
			var value := float(entry[peer_id]) - PublicOpinion.STRONGHOLD_EFFORT_DECAY
			if value <= 0.0:
				entry.erase(peer_id)
			else:
				entry[peer_id] = value
	if strongholds.is_empty():
		return
	var shares := _province_share_map()
	for province_id in strongholds.keys():
		var owner := stronghold_of(String(province_id))
		var here: Dictionary = shares.get(province_id, {})
		var mine := float(here.get(owner, 0.0))
		var overtaken := -1
		for peer_id in here.keys():
			if int(peer_id) != owner and float(here[peer_id]) > mine:
				overtaken = int(peer_id)
		if overtaken != -1:
			strongholds.erase(province_id)
			siege.erase(province_id)
			# Emek sıfırlanır: kale aynı anda geri verilmesin, yeniden kurulması gereksin.
			(kale_effort.get(province_id, {}) as Dictionary).erase(owner)
			_log_province(String(province_id), "%s oyda %s'nın gerisine düştü, kale elden gitti" % [
				_party_name(owner), _party_name(overtaken)])
			_pending_log.append({"text": "%s, %s'daki kalesini kaybetti: %s oyda öne geçti." % [_party_name(owner),
				_province_name(String(province_id)), _party_name(overtaken)], "peer_id": owner,
				"province": String(province_id), "kind": "stronghold_lost"})
	_refresh_all_strongholds()

## Tur sonu: kuşatmalar zamanla dağılır.
func _decay_siege() -> void:
	for province_id in siege.keys():
		var entry: Dictionary = siege[province_id]
		for peer_id in entry.keys():
			var value := float(entry[peer_id]) * PublicOpinion.SIEGE_DECAY
			if value < 0.05:
				entry.erase(peer_id)
			else:
				entry[peer_id] = value
		if entry.is_empty():
			siege.erase(province_id)

func _refresh_all_strongholds() -> void:
	for province_id in _province_ids:
		_update_stronghold(province_id)

# --- İllerin partiyi takibi -------------------------------------------------------

## İl -> {peer_id -> beklenen oy yüzdesi} (gürültüsüz, şimdiki durum).
func _province_share_map() -> Dictionary:
	var mods := election_modifiers()
	var local_mods: Dictionary = mods["local"]
	var ideologies := _ideologies()
	var national := _expected_national(mods)
	var result := {}
	for province_id in _province_ids:
		result[province_id] = ElectionModel.expected_shares(ideologies, province_center(province_id), current_axis_sharpness,
			mods["national"], local_mods.get(province_id, {}), national)
	return result

## Partilerin görüşünü kaydırır. Partinin GÜÇLÜ olduğu iller onu kısmen TAKİP
## eder: il, partinin oradaki oy payı × PROVINCE_FOLLOW kadar aynı yöne kayar
## (kalesiyse daha çok). Baskın parti görüş değiştirmekten korkmamalı; ilde
## farklı görüşte birden çok güçlü parti varsa il ikisinin arasında kalır.
## Dönüş: gerçekleşen kaymalar [{"peer", "axis", "delta"}].
func _shift_ideologies(changes: Array) -> Array:
	var shares := _province_share_map() if not province_ideology.is_empty() else {}
	var before := {}
	for change in changes:
		var peer := int(change["peer"])
		if not before.has(peer):
			before[peer] = (PartyManager.parties.get(peer, {}).get("ideology", {}) as Dictionary).duplicate()
	PartyManager.apply_ideology_deltas(changes)
	var actual: Array = []
	for peer in before.keys():
		var after: Dictionary = PartyManager.parties.get(peer, {}).get("ideology", {})
		for axis in IdeologyAxes.AXES:
			var delta := float(after.get(axis, 0.0)) - float(before[peer].get(axis, 0.0))
			if not is_zero_approx(delta):
				actual.append({"peer": int(peer), "axis": axis, "delta": delta})
	if actual.is_empty() or shares.is_empty():
		return actual
	for province_id in _province_ids:
		if not province_ideology.has(province_id):
			continue
		var center: Dictionary = (province_ideology[province_id] as Dictionary).duplicate()
		var here: Dictionary = shares.get(province_id, {})
		for change in actual:
			var peer := int(change["peer"])
			var follow := float(here.get(peer, 0.0)) / 100.0 * PublicOpinion.PROVINCE_FOLLOW
			if stronghold_of(province_id) == peer:
				follow *= PublicOpinion.STRONGHOLD_FOLLOW_MULT
			var axis := String(change["axis"])
			center[axis] = clampf(float(center.get(axis, 0.0)) + float(change["delta"]) * minf(follow, 0.9), -3.0, 3.0)
		province_ideology[province_id] = center
	_refresh_all_strongholds()
	return actual

# --- Meclis konuşması ---------------------------------------------------------------

## Sıra gelen oyuncunun ZORUNLU konuşması: axis ekseninde dir (+1/−1) ucunu savunur.
func make_speech(axis: String, dir: int) -> void:
	var me := multiplayer.get_unique_id()
	if not needs_speech(me) or is_turn_blocked():
		return
	if _is_authority():
		_apply_speech(me, axis, dir)
	else:
		_request_speech.rpc_id(1, axis, dir)

func _apply_speech(peer_id: int, axis: String, dir: int) -> void:
	if not needs_speech(peer_id) or is_turn_blocked() or not IdeologyAxes.AXES.has(axis):
		return
	var d := 1 if dir > 0 else -1
	speech_done = true
	var moved := _shift_ideologies([{"peer": peer_id, "axis": axis, "delta": IdeologyAxes.SPEECH_SHIFT * d}])
	var text := "%s, Meclis kürsüsünde \"%s\" konuşması yaptı (%s)." % [_party_name(peer_id),
		IdeologyAxes.speech_title(axis, d), IdeologyAxes.AXIS_SIDES[axis]["pos" if d > 0 else "neg"]]
	if moved.is_empty():
		text += " Partisi bu konuda zaten en uçta."
	_push_state({"type": "speech", "peer_id": peer_id, "message": text})

@rpc("any_peer", "reliable")
func _request_speech(axis: String, dir: int) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_speech(multiplayer.get_remote_sender_id(), axis, dir)

# --- Karışıklık ve bölünme ------------------------------------------------------------

func turmoil_of(peer_id: int) -> float:
	return float(turmoil.get(peer_id, 0.0))

func _add_turmoil(peer_id: int, amount: float) -> void:
	if peer_id == -1 or not _is_authority():
		return
	var value := maxf(0.0, turmoil_of(peer_id) + amount)
	if value <= 0.0:
		turmoil.erase(peer_id)
	else:
		turmoil[peer_id] = value

## Olumlu bir hamle parti içini toparlar.
func _ease_turmoil(peer_id: int, amount: float) -> void:
	_add_turmoil(peer_id, -amount)

func is_splinter(peer_id: int) -> bool:
	return splinters.has(peer_id)

## Bu partiden ayrılmış (henüz geri dönmemiş) parti; yoksa -1.
func splinter_of(parent: int) -> int:
	for splinter in splinters.keys():
		if int(splinters[splinter].get("parent", -1)) == parent:
			return int(splinter)
	return -1

## Tur sonu: karışıklık söner; çok karışan parti bölünür. Ayrılmış bir parti
## bir daha bölünemez, ana partinin de aynı anda tek ayrılanı olabilir.
func _check_splits() -> void:
	for peer_id in turn_order.duplicate():
		var parent := int(peer_id)
		if turmoil_of(parent) < PublicOpinion.SPLIT_TURMOIL or is_splinter(parent) or splinter_of(parent) != -1:
			continue
		if int(last_seats.get(parent, 0)) < PublicOpinion.SPLIT_MIN_SEATS:
			continue
		_split_party(parent)
		return  # turda en fazla bir bölünme

## Ayrılan partinin adı: "Yeni X" (sığmazsa kısaltılır), benzersiz.
func _splinter_name(parent_name: String) -> String:
	var used: Array = []
	for party in PartyManager.parties.values():
		used.append(String(party.get("name", "")))
	for prefix in ["Yeni ", "Öz ", "Gerçek ", "Hür "]:
		var candidate := (String(prefix) + parent_name).left(PartyManager.NAME_MAX_LENGTH).strip_edges()
		if not used.has(candidate):
			return candidate
	return ("Y" + parent_name).left(PartyManager.NAME_MAX_LENGTH)

## BÖLÜNME: ana partiyle BİREBİR aynı görüşte, benzer renkte yeni bir parti
## doğar ve yapay zekâ yönetir. Ana partinin vekillerinin ciddi bir bölümü ve
## bazı il teşkilatları ona geçer.
func _split_party(parent: int) -> void:
	var parent_name := _party_name(parent)
	var splinter := MultiplayerManager.add_splinter_bot("Muhalif Kanat")
	PartyManager.add_splinter_party(splinter, parent, _splinter_name(parent_name))
	turn_order.append(splinter)
	inventories[splinter] = []
	mana[splinter] = float(GameRules.MANA_PER_ROUND)
	var seats_before := int(last_seats.get(parent, 0))
	var share := _rng.randf_range(PublicOpinion.SPLIT_SEAT_SHARE_MIN, PublicOpinion.SPLIT_SEAT_SHARE_MAX)
	var moved := _move_seats(parent, splinter, maxi(1, int(round(seats_before * share))))
	election_seats[splinter] = mini(moved, int(election_seats.get(parent, 0)))
	election_seats[parent] = maxi(0, int(election_seats.get(parent, 0)) - int(election_seats[splinter]))
	var vote := float(last_vote_shares.get(parent, 0.0))
	if vote > 0.0:
		last_vote_shares[splinter] = vote * share
		last_vote_shares[parent] = vote * (1.0 - share)
	if passed_threshold.has(parent):
		passed_threshold.append(splinter)
	national_support[splinter] = national_of(parent)
	_add_national(parent, PublicOpinion.SPLIT_NATIONAL_DAMAGE)
	for province_id in organizations.keys():
		var entry: Dictionary = organizations[province_id]
		if int(entry.get(parent, 0)) > 0 and _rng.randf() < PublicOpinion.SPLIT_ORG_CHANCE:
			entry[splinter] = 1
	turmoil[parent] = PublicOpinion.SPLIT_AFTER_TURMOIL
	splinters[splinter] = {"parent": parent, "elections": 0, "since": round_number}
	_push_state({"type": "party_split", "peer_id": parent, "message":
		"%s BÖLÜNDÜ! Parti içi karışıklık sonunda %d milletvekili ayrılıp %s'yi kurdu." % [
		parent_name, moved, _party_name(splinter)]}, true)

## Tur sonu: ayrılan parti en erken 1, en geç 4 seçim atlattıktan sonra ana
## partisine BÜTÜN vekilleri ve teşkilatlarıyla geri döner. Erken dönüş için
## ana partinin karışıklığı yatışmış olmalı.
func _check_reunions() -> void:
	for splinter in splinters.keys().duplicate():
		var info: Dictionary = splinters[splinter]
		var parent := int(info.get("parent", -1))
		if not turn_order.has(parent):
			splinters.erase(splinter)  # ana parti oyundan çıktı: bağımsız kalır
			continue
		var elections := int(info.get("elections", 0))
		if elections >= PublicOpinion.SPLIT_MAX_ELECTIONS \
				or (elections >= PublicOpinion.SPLIT_MIN_ELECTIONS and turmoil_of(parent) <= PublicOpinion.REUNION_TURMOIL):
			_merge_splinter(int(splinter))

func _merge_splinter(splinter: int) -> void:
	var parent := int(splinters[splinter]["parent"])
	var splinter_name := _party_name(splinter)
	var moved := _move_seats(splinter, parent, int(last_seats.get(splinter, 0)))
	election_seats[parent] = int(election_seats.get(parent, 0)) + int(election_seats.get(splinter, 0))
	last_vote_shares[parent] = float(last_vote_shares.get(parent, 0.0)) + float(last_vote_shares.get(splinter, 0.0))
	for province_id in organizations.keys():
		var entry: Dictionary = organizations[province_id]
		var level := int(entry.get(splinter, 0))
		if level > int(entry.get(parent, 0)):
			entry[parent] = level
		entry.erase(splinter)
	for province_id in local_support.keys():
		var entry: Dictionary = local_support[province_id]
		if entry.has(splinter):
			entry[parent] = PublicOpinion.clamp_points(float(entry.get(parent, 0.0)) + float(entry[splinter]))
			entry.erase(splinter)
	for province_id in kale_effort.keys():
		var entry: Dictionary = kale_effort[province_id]
		if entry.has(splinter):
			entry[parent] = float(entry.get(parent, 0.0)) + float(entry[splinter])
			entry.erase(splinter)
	for province_id in strongholds.keys():
		if int(strongholds[province_id]) == splinter:
			strongholds[province_id] = parent
	for province_id in siege.keys():
		siege[province_id].erase(splinter)
	_add_national(parent, maxf(0.0, national_of(splinter)) * 0.5)
	national_support.erase(splinter)
	var hand: Array = inventories.get(parent, [])
	for card in inventories.get(splinter, []):
		if hand.size() < MAX_HAND_SIZE:
			hand.append(card)
	inventories[parent] = hand
	for table in [inventories, mana, populism, law_rounds, national_list, last_seats, election_seats, last_vote_shares, turmoil]:
		table.erase(splinter)
	passed_threshold.erase(splinter)
	for province_id in last_province_results.keys():
		last_province_results[province_id].erase(splinter)
	if not referendum.is_empty():
		referendum.get("sides", {}).erase(splinter)
	var idx := turn_order.find(splinter)
	if idx != -1:
		turn_order.remove_at(idx)
		if idx < current_turn_index:
			current_turn_index -= 1
		current_turn_index = clampi(current_turn_index, 0, maxi(0, turn_order.size() - 1))
	splinters.erase(splinter)
	turmoil.erase(parent)
	GovernmentManager.merge_party(splinter, parent)
	_push_state({"type": "party_merge", "peer_id": parent, "message":
		"%s, ana partisi %s'ya geri döndü: %d milletvekili ve bütün teşkilatlarıyla." % [
		splinter_name, _party_name(parent), moved]}, true)
	PartyManager.remove_party(splinter)
	MultiplayerManager.remove_splinter_bot(splinter)

## Tur sonu: puanlar sıfıra doğru söner; neredeyse sıfır olanlar silinir.
## (İl başkanlıkları sönmez.)
func _decay_opinion() -> void:
	_org_pressure()
	_revert_provinces()
	_decay_siege()
	_check_stronghold_upkeep()
	for peer_id in national_support.keys():
		var value: float = national_of(peer_id) * PublicOpinion.NATIONAL_DECAY
		if absf(value) < 0.05:
			national_support.erase(peer_id)
		else:
			national_support[peer_id] = value
	for province_id in local_support.keys():
		var entry: Dictionary = local_support[province_id]
		for peer_id in entry.keys():
			var value: float = float(entry[peer_id]) * PublicOpinion.LOCAL_DECAY
			if absf(value) < 0.05:
				entry.erase(peer_id)
			else:
				entry[peer_id] = value
		if entry.is_empty():
			local_support.erase(province_id)

## from_peer'un vekillerinden amount kadarını (rastgele seçim çevrelerinden ve
## ulusal listeden) to_peer'a taşır; il bazlı ve ulusal toplamlar birlikte
## değişir. Taşınan vekil sayısını döner.
func _move_seats(from_peer: int, to_peer: int, amount: int) -> int:
	amount = mini(amount, int(last_seats.get(from_peer, 0)))
	if amount <= 0:
		return 0
	var bag: Array = []
	for province_id in last_province_results.keys():
		var here: int = int(last_province_results[province_id].get(from_peer, {}).get("seats", 0))
		for i in here:
			bag.append(province_id)
	# Ulusal listeden de vekil taşınabilir ("" = ulusal liste).
	for i in int(national_list.get(from_peer, 0)):
		bag.append("")
	bag.shuffle()
	var moved := 0
	for province_id in bag:
		if moved >= amount:
			break
		if province_id == "":
			if int(national_list.get(from_peer, 0)) <= 0:
				continue
			national_list[from_peer] = int(national_list[from_peer]) - 1
			national_list[to_peer] = int(national_list.get(to_peer, 0)) + 1
			moved += 1
			continue
		var entry: Dictionary = last_province_results[province_id]
		var from_entry: Dictionary = entry.get(from_peer, {})
		if int(from_entry.get("seats", 0)) <= 0:
			continue
		from_entry["seats"] = int(from_entry["seats"]) - 1
		entry[from_peer] = from_entry
		var to_entry: Dictionary = entry.get(to_peer, {"percent": 0.0, "seats": 0})
		to_entry["seats"] = int(to_entry.get("seats", 0)) + 1
		entry[to_peer] = to_entry
		moved += 1
	last_seats[from_peer] = int(last_seats[from_peer]) - moved
	last_seats[to_peer] = int(last_seats.get(to_peer, 0)) + moved
	return moved

## Hedef partiden rastgele sayıda milletvekilini çalıp kartı oynayana aktarır.
## Vekiller RASTGELE SEÇİM ÇEVRELERİNDEN alınır; il bazlı ve ulusal toplamlar
## HER ZAMAN birlikte değişir.
func _apply_steal(peer_id: int, target_peer_id: int, card_type: String) -> bool:
	if not is_valid_steal_target(peer_id, target_peer_id):
		return false
	var range_info := steal_range(peer_id, target_peer_id, card_type)
	if range_info.is_empty():
		return false
	var wanted: int = _rng.randi_range(int(range_info["min"]), int(range_info["max"]))
	if populism_rounds_left(peer_id) > 0:
		wanted = int(round(wanted * PublicOpinion.POPULISM_STEAL_MULT))
	# Meclis dışı parti yarı verimle çalar.
	wanted = maxi(1, int(round(wanted * steal_efficiency(peer_id))))
	var amount: int = mini(wanted, int(last_seats[target_peer_id]))
	if amount <= 0:
		return false

	var moved := _move_seats(target_peer_id, peer_id, amount)
	if moved == 0:
		return false
	# Transfer meşru görünmez: çalan küçük bir ulusal destek kaybeder, çalınan
	# parti mağduriyetten küçük bir destek kazanır (ikisi de kısmi).
	# NORMAL vekil çalmanın ulusal bedeli YOK; sadece güçlü varyant bedel öder.
	if card_type == CardPresets.STEAL_STRONG_CARD_TYPE:
		_add_national(peer_id, PublicOpinion.steal_thief_national(moved))
	_add_national(target_peer_id, PublicOpinion.steal_victim_national(moved))
	_event_message = "%s, %s'dan %d milletvekili transfer etti." % [_party_name(peer_id), _party_name(target_peer_id), moved]
	return true

## Kaset / itibar suikastı: hedefin ULUSAL desteği doğrudan düşer. Popülizm
## süren saldırgan için hasar daha büyüktür (kendi hamlesinin iyi sonucu).
func _apply_reputation(peer_id: int, target_peer_id: int) -> void:
	var damage := PublicOpinion.REPUTATION_NATIONAL_DAMAGE
	if populism_rounds_left(peer_id) > 0:
		damage *= PublicOpinion.POPULISM_GOOD_MULT
	_add_turmoil(target_peer_id, PublicOpinion.TURMOIL_REPUTATION)
	if is_referendum_active():
		# İFTİRA: referandumda kaset partinin ve kararının inandırıcılığını vurur.
		_ref_add_national(target_peer_id, -damage)
		_event_message = "%s hakkında kaset sızdı: referandumda \"%s\" kampanyası sarsıldı. (%s)" % [
			_party_name(target_peer_id), referendum_side_text(target_peer_id), _party_name(peer_id)]
		return
	_add_national(target_peer_id, -damage)
	_event_message = "%s hakkında kaset sızdı: ulusal desteği %.1f puan düştü. (%s)" % [
		_party_name(target_peer_id), damage, _party_name(peer_id)]

## GovernmentManager, hükümet güvenoyu alınca çağırır: hükümet partilerine mana.
func grant_government_mana(peer_ids: Array) -> void:
	if not _is_authority():
		return
	for peer_id in peer_ids:
		if mana.has(peer_id):
			mana[peer_id] = mana_of(peer_id) + GameRules.GOVERNMENT_MANA_BONUS
		# Hükümete girmek parti içini toparlar.
		_ease_turmoil(int(peer_id), PublicOpinion.TURMOIL_EASE_GOVERNMENT)
	_push_state({"type": "mana"})

## İki partinin ideolojik yakınlığı: 1 aynı görüş, 0 zıt radikal uçlar.
func ideological_closeness(a: int, b: int) -> float:
	var ia: Dictionary = PartyManager.parties.get(a, {}).get("ideology", IdeologyAxes.default_values())
	var ib: Dictionary = PartyManager.parties.get(b, {}).get("ideology", IdeologyAxes.default_values())
	return clampf(1.0 - IdeologyAxes.distance(ia, ib) / IdeologyAxes.max_distance(), 0.0, 1.0)

## Bu partinin hedeften bu kartla çalabileceği vekil aralığı (yakınlığa göre).
## Kartın vereceği vekil aralığı. Meclis dışı partide yarıya iner (arayüzde de
## bu aralık gösterilir, sürpriz olmasın).
func steal_range(peer_id: int, target_peer_id: int, card_type: String) -> Dictionary:
	var base := CardPresets.steal_range(card_type, ideological_closeness(peer_id, target_peer_id))
	var efficiency := steal_efficiency(peer_id)
	if is_equal_approx(efficiency, 1.0):
		return base
	return {"min": maxi(1, int(round(int(base["min"]) * efficiency))),
		"max": maxi(1, int(round(int(base["max"]) * efficiency)))}

## Sırayı bir sonrakine devreder; index başa sardıysa (tur bitti) true döner.
func _advance_turn() -> bool:
	var size: int = maxi(1, turn_order.size())
	var wrapped: bool = (current_turn_index + 1) >= size
	current_turn_index = (current_turn_index + 1) % size
	_turn_time_left = GameRules.TURN_TIMEOUT
	_grant_turn_income()
	return wrapped

## Sırası gelen oyuncu mana gelirini VE bir kart alır.
## KART ÇEKME HAMLESİ KALDIRILDI: deste butonu yerine her elin başında
## otomatik olarak bir kart geliyor. Dağıtılan kart, bu hamleden sonra
## gönderilecek state olayına iliştirilsin diye _pending_dealt'ta beklet.
func _grant_turn_income() -> void:
	speech_done = false
	var peer_id := current_turn_peer_id()
	if peer_id == -1:
		return
	mana[peer_id] = mana_of(peer_id) + turn_income(peer_id)
	# Kart, ele girmeden ÖNCE duyurulur: animasyon eski el boyutunu kullanır.
	var card_type := _peek_turn_card(peer_id)
	if card_type == "":
		return
	card_drawn.emit(peer_id, card_type)
	inventories[peer_id].insert(inventories[peer_id].size() / 2, card_type)
	_pending_dealt = {"peer_id": peer_id, "card": card_type}

## Elin başında verilecek kartı seçer (ele koymaz). El doluysa "" döner.
func _peek_turn_card(peer_id: int) -> String:
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	if inventories[peer_id].size() >= MAX_HAND_SIZE:
		return ""
	return CardPresets.weighted_pick(_draw_weights(peer_id), _rng)

## Tur geliri: hükümette görevi olan partiler bir fazla mana alır.
func turn_income(peer_id: int) -> int:
	if GovernmentManager.government_party_ids().has(peer_id):
		return GameRules.MANA_PER_ROUND_GOVERNMENT
	return GameRules.MANA_PER_ROUND

## Desteden bir kartı doğrudan ele verir. El doluysa verilmez.
## Dönen değer: verilen kartın türü ("" = verilmedi).
func _deal_turn_card(peer_id: int) -> String:
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	if inventories[peer_id].size() >= MAX_HAND_SIZE:
		return ""
	var card_type := CardPresets.weighted_pick(_draw_weights(peer_id), _rng)
	inventories[peer_id].insert(inventories[peer_id].size() / 2, card_type)
	return card_type

# --- Tur sonu / seçim / oyun sonu -------------------------------------------

func _finish_round_if_needed(wrapped: bool) -> void:
	if not wrapped or game_finished:
		return
	if is_turn_blocked():
		# Örn. turun son hamlesi gensoru ya da yasaydı: oylama bitince tur kapanacak.
		_round_end_pending = true
		return
	_finish_round()

## Anayasa değişikliği seçim aralığını değiştirdi: takvim SON SEÇİMDEN
## itibaren yeni aralıkla işlesin (yoksa çıpa eski aralığa göre kalır).
func rebase_election_calendar() -> void:
	election_anchor = maxi(last_election_round, 0)
	if election_anchor <= 0:
		election_anchor = GameRules.FIRST_ELECTION_ROUND
	GameRules.set_election_anchor(election_anchor)

## Meclis erken seçimi kabul etti (GovernmentManager çağırır).
func schedule_early_election() -> void:
	early_election_pending = true

func _finish_round() -> void:
	_round_end_pending = false
	# Makam puanları TUR SONUNDA DEĞİL, hükümet kurulduğu anda yazılır
	# (bkz. GovernmentManager.award_formation_scores).
	var finished_round := round_number
	round_number += 1
	current_axis_sharpness = minf(current_axis_sharpness + MultiplayerManager.axis_sharpness_increment,
		MultiplayerManager.AXIS_SHARPNESS_HARD_MAX)
	if MultiplayerManager.axis_sharpness_max_enabled:
		current_axis_sharpness = minf(current_axis_sharpness, MultiplayerManager.axis_sharpness_max_value)

	# Ayrılan partiler dönebilir, çok karışan parti bölünür; sonra karışıklık söner.
	_check_reunions()
	_check_splits()
	for peer_id in turmoil.keys():
		turmoil[peer_id] = turmoil_of(int(peer_id)) * PublicOpinion.TURMOIL_DECAY

	if not referendum.is_empty():
		if _referendum_round_end(finished_round):
			return

	if finished_round >= GameRules.MAX_ROUNDS:
		# SON SEÇİM: kurulan hükümet puanlarını alınca oyun biter (bkz. on_block_state_changed).
		final_election_pending = true
		_hold_election(finished_round, false)
		return

	# ERKEN SEÇİM: meclis karar verdiyse bu dönemin sonunda sandık kurulur ve
	# takvim bu tura sabitlenir — sonraki seçimler buradan itibaren sayılır.
	if early_election_pending:
		early_election_pending = false
		election_anchor = finished_round
		GameRules.set_election_anchor(election_anchor)
		_hold_election(finished_round, false)
		_schedule_agenda()
		return

	var scheduled := GameRules.is_election_round(finished_round)
	var no_government := not last_seats.is_empty() \
		and not GovernmentManager.has_government() \
		and GovernmentManager.phase == GovernmentManager.Phase.IDLE
	if scheduled or no_government:
		_hold_election(finished_round, no_government and not scheduled)
	else:
		_decay_opinion()
		_push_state({"type": "round"})
	_schedule_agenda()

## Seçimde kullanılacak güç çarpanları:
##   ulusal : ulusal puan + İKTİDAR DENGESİ + POPÜLİZM + VEKİL MOMENTUMU (seçimden bu
##            yana vekil çalarak büyüyen parti artıyla girer)
##   il     : aktivite (il puanı + il başkanlığı)
func election_modifiers() -> Dictionary:
	var national := national_support.duplicate()
	for peer_id in GovernmentManager.government_party_ids():
		national[peer_id] = float(national.get(peer_id, 0.0)) + PublicOpinion.GOVERNMENT_FATIGUE
	# Popülizm sürerken seçim: seçmen vaatleri hatırlar.
	for peer_id in turn_order:
		if populism_rounds_left(peer_id) > 0:
			national[peer_id] = float(national.get(peer_id, 0.0)) + PublicOpinion.POPULISM_ELECTION_NATIONAL
	return {"national": national, "local": activity_map()}

func _hold_election(finished_round: int, early: bool) -> void:
	var mods := election_modifiers()
	var ideologies := _ideologies().duplicate(true)
	# Denge analizi (tools/balance_sim.gd) için seçimin girdileri; ağda gönderilmez.
	last_election_inputs = {
		"mods": mods, "ideologies": ideologies, "voters": province_voters(),
		"sharpness": current_axis_sharpness, "threshold": MultiplayerManager.election_threshold,
		"gov_ids": GovernmentManager.government_party_ids(), "organizations": organizations.duplicate(true),
		"seats_before": last_seats.duplicate(),
	}
	var result := ElectionModel.compute(ideologies, _province_seat_counts, province_voters(),
		MultiplayerManager.election_threshold, current_axis_sharpness, _rng, mods)
	last_vote_shares = result["vote_shares"]
	last_seats = result["seats"]
	last_province_results = result["province_results"]
	passed_threshold = result["passed_threshold"]
	national_list = result.get("national_list", {})
	election_seats = last_seats.duplicate()
	last_election_round = finished_round
	for splinter in splinters.keys():
		splinters[splinter]["elections"] = int(splinters[splinter].get("elections", 0)) + 1
	last_election_was_early = early
	# Seçim sonrası herkese mana ve 1 kart hediye.
	for peer_id in turn_order:
		mana[peer_id] = mana_of(peer_id) + GameRules.ELECTION_MANA_BONUS
		_deal_turn_card(peer_id)
	# Seçimde kullanıldıktan SONRA söner: seçimden hemen önceki hamleler tam etkili.
	_decay_opinion()
	_push_state({"type": "election"}, true)
	# Yeni meclis: hükümet kurma görevi en çok vekili olan partiye verilir.
	# Seçim gecesi yayını herkesin ekranında oynarken kurma süresi yanmasın.
	GovernmentManager.start_formation(GameRules.ELECTION_NIGHT_SECONDS + GameRules.ELECTION_NIGHT_HOLD + 2.0)

## Son seçimin ardından hükümet kurma bitti: puan tablosu kesinleşir. Makam
## puanları hükümet kurulurken zaten yazıldı, burada tekrar yazılmaz.
func _finish_final_election() -> void:
	final_election_pending = false
	if GovernmentManager.has_government():
		_end_game("%d dönem tamamlandı. Son hükümeti %s kurdu." % [
			GameRules.MAX_ROUNDS, _party_name(GovernmentManager.main_gov_peer_id)])
	else:
		_end_game("%d dönem tamamlandı. Son seçimden sonra hükümet kurulamadı." % GameRules.MAX_ROUNDS)

func _end_game(reason: String) -> void:
	game_finished = true
	game_end_reason = reason
	final_ranking = []
	var ids: Array = []
	for peer_id in turn_order:
		if not is_splinter(peer_id):
			ids.append(peer_id)
	ids.sort_custom(func(a, b):
		var sa := ranking_score(a)
		var sb := ranking_score(b)
		if sa != sb:
			return sa > sb
		var va := int(last_seats.get(a, 0))
		var vb := int(last_seats.get(b, 0))
		if va != vb:
			return va > vb
		return a < b
	)
	for peer_id in ids:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		final_ranking.append({
			"peer_id": peer_id,
			"name": party.get("name", "?"),
			"leader": MultiplayerManager.players.get(peer_id, {}).get("name", "?"),
			"color": party.get("bg_color", Color(0.5, 0.5, 0.5)),
			"score": ranking_score(peer_id),
			"seats": int(last_seats.get(peer_id, 0)),
		})
	GovernmentManager.end_game()
	_push_state({"type": "game_over"})

## Sıralama puanı: ayrılmış (henüz dönmemiş) partinin puanı ana partiye sayılır.
func ranking_score(peer_id: int) -> int:
	var score := GovernmentManager.score_of(peer_id)
	for splinter in splinters.keys():
		if int(splinters[splinter].get("parent", -1)) == peer_id:
			score += GovernmentManager.score_of(int(splinter))
	return score

## GovernmentManager, tur akışını engelleyen bir aşamadan (kurma/oylama)
## çıkıldığında çağırır: sıradaki oyuncunun süresi baştan başlar ve ertelenmiş
## bir tur sonu varsa şimdi işlenir.
func on_block_state_changed() -> void:
	if not _is_authority() or turn_order.is_empty() or game_finished or is_turn_blocked():
		return
	if final_election_pending:
		_finish_final_election()
		return
	_turn_time_left = GameRules.TURN_TIMEOUT
	if _round_end_pending:
		_finish_round()
	else:
		_push_state({"type": "timer"})
	# Yasa/gensoru son manayla verildiyse oylama bitince sıra devreder.

## Host: oyun sırasında ayrılan oyuncuyu sıradan, envanterden, meclisten ve
## hükümet süreçlerinden çıkarır. Onsuz sırası gelen/oy bekleyen oyun kilitlenirdi.
func remove_player(peer_id: int) -> void:
	if not _is_authority():
		return
	var idx := turn_order.find(peer_id)
	if idx == -1:
		return
	var was_current := idx == current_turn_index
	turn_order.remove_at(idx)
	inventories.erase(peer_id)
	mana.erase(peer_id)
	last_seats.erase(peer_id)
	election_seats.erase(peer_id)
	national_list.erase(peer_id)
	last_vote_shares.erase(peer_id)
	passed_threshold.erase(peer_id)
	national_support.erase(peer_id)
	turmoil.erase(peer_id)
	splinters.erase(peer_id)
	for province_id in last_province_results.keys():
		last_province_results[province_id].erase(peer_id)
	for province_id in local_support.keys():
		local_support[province_id].erase(peer_id)
	for province_id in organizations.keys():
		organizations[province_id].erase(peer_id)

	var wrapped := false
	if idx < current_turn_index:
		current_turn_index -= 1
	elif was_current:
		_turn_time_left = GameRules.TURN_TIMEOUT
		if current_turn_index >= turn_order.size():
			current_turn_index = 0
			wrapped = true

	if game_finished:
		_push_state({"type": "player_left", "peer_id": peer_id}, true)
		return
	GovernmentManager.remove_player(peer_id)
	_push_state({"type": "player_left", "peer_id": peer_id}, true)
	if turn_order.size() < GameRules.MIN_PLAYERS_TO_CONTINUE:
		_end_game("Yeterli oyuncu kalmadı.")
		return
	_finish_round_if_needed(wrapped)

# --- Senkronizasyon ---------------------------------------------------------

func _pack_state(include_results: bool) -> Dictionary:
	var state := {
		"version": state_version,
		"inventories": inventories,
		"turn_order": turn_order,
		"turn_index": current_turn_index,
		"law_rounds": law_rounds,
		"populism": populism,
		"splinters": splinters,
		"speech_done": speech_done,
		"kale_effort": kale_effort,
		"siege": siege,
		"agenda": agenda,
		"national_list": national_list,
		"sharpness": current_axis_sharpness,
		"round": round_number,
		"turn_time_left": _turn_time_left,
		"last_election_round": last_election_round,
		"early": last_election_was_early,
		"vote_shares": last_vote_shares,
		"seats": last_seats,
		"election_seats": election_seats,
		"early_election_pending": early_election_pending,
		"election_anchor": election_anchor,
		"passed": passed_threshold,
		"national": national_support,
		"local": local_support,
		"events": province_events,
		"organizations": organizations,
		"strongholds": strongholds,
		"referendum": referendum,
		"province_ideology": province_ideology,
		"mana": mana,
		"game_finished": game_finished,
		"final_ranking": final_ranking,
		"end_reason": game_end_reason,
	}
	if include_results:
		state["map"] = GameMap.data
		state["province_results"] = last_province_results
	return state

func _apply_state(state: Dictionary) -> void:
	state_version = int(state["version"])
	inventories = state["inventories"]
	turn_order = state["turn_order"]
	current_turn_index = int(state["turn_index"])
	law_rounds = state.get("law_rounds", {})
	populism = state.get("populism", {})
	splinters = state.get("splinters", {})
	speech_done = bool(state.get("speech_done", false))
	kale_effort = state.get("kale_effort", {})
	siege = state.get("siege", {})
	agenda = state.get("agenda", {})
	national_list = state.get("national_list", {})
	current_axis_sharpness = float(state["sharpness"])
	round_number = int(state["round"])
	_turn_deadline_ms = Time.get_ticks_msec() + int(float(state["turn_time_left"]) * 1000.0)
	last_election_round = int(state["last_election_round"])
	last_election_was_early = bool(state["early"])
	last_vote_shares = state["vote_shares"]
	last_seats = state["seats"]
	election_seats = state.get("election_seats", {})
	early_election_pending = bool(state.get("early_election_pending", false))
	election_anchor = int(state.get("election_anchor", 0))
	# Takvim çıpası her istemcide aynı olmalı (erken seçim sonrası).
	GameRules.set_election_anchor(election_anchor)
	passed_threshold = state["passed"]
	national_support = state["national"]
	local_support = state["local"]
	province_events = state["events"]
	organizations = state.get("organizations", {})
	strongholds = state.get("strongholds", {})
	referendum = state.get("referendum", {})
	mana = state.get("mana", {})
	game_finished = bool(state["game_finished"])
	final_ranking = state["final_ranking"]
	game_end_reason = str(state["end_reason"])
	if state.has("map") and int((state["map"] as Dictionary).get("seed", -1)) != GameMap.seed_value():
		GameMap.set_data(state["map"])
		_load_province_seat_counts()
	if state.has("province_results"):
		last_province_results = state["province_results"]
	if state.has("province_ideology"):
		province_ideology = state["province_ideology"]

## Host: durumu (sürümü artırarak) herkese yayınlar ve olayın sinyallerini
## kendi tarafında da doğrudan atar (.rpc() göndericide çalışmaz).
func _push_state(event: Dictionary, include_results: bool = false) -> void:
	if not _pending_log.is_empty():
		event = event.duplicate()
		event["extra_log"] = _pending_log
		_pending_log = []
	if not _pending_dealt.is_empty():
		event = event.duplicate()
		event["dealt"] = _pending_dealt
		_pending_dealt = {}
	state_version += 1
	if not _is_local_only():
		_receive_state.rpc(_pack_state(include_results or event.get("type", "") in ["full", "election", "player_left", "party_split", "party_merge"]), event)
	_emit_post_event(event)

func _emit_post_event(event: Dictionary) -> void:
	var type: String = event.get("type", "")
	inventories_updated.emit()
	if type in ["full", "player_left", "party_split", "party_merge"]:
		turn_order_updated.emit()
	turn_changed.emit(current_turn_peer_id())
	opinion_changed.emit()
	match type:
		"election":
			election_completed.emit()
		"round":
			round_advanced.emit()
		"game_over":
			game_over.emit()
		"full", "player_left", "party_split", "party_merge":
			seats_changed.emit()
		"played":
			if bool(event.get("seats_changed", false)):
				seats_changed.emit()
	if type == "full" and round_number == 1 and last_election_round == 0:
		event_log.clear()  # yeni oyun (istemci tarafı)
	if event.has("message"):
		opinion_event.emit(str(event["message"]))
		log_event(str(event["message"]), int(event.get("peer_id", -1)), String(event.get("province", "")), _log_kind(event))
	for extra in event.get("extra_log", []):
		log_event(String(extra["text"]), int(extra["peer_id"]), String(extra["province"]), String(extra["kind"]))
	match type:
		"round":
			log_event("%s başladı." % GameRules.period_label(round_number), -1, "", "round")
		"election":
			log_event("%d genel seçimi yapıldı." % GameRules.election_year(last_election_round), -1, "", "election")

@rpc("authority", "reliable")
func _receive_state(state: Dictionary, event: Dictionary) -> void:
	# Animasyon sinyalleri ESKİ state üzerinden kurulsun diye önce bunlar.
	if event.has("dealt"):
		var dealt: Dictionary = event["dealt"]
		card_drawn.emit(int(dealt["peer_id"]), str(dealt["card"]))
	match str(event.get("type", "")):
		"played":
			card_played.emit(int(event["peer_id"]), str(event["card"]))
	_apply_state(state)
	_emit_post_event(event)

@rpc("authority", "reliable")
func _heartbeat(card_version: int, gov_version: int, party_version: int) -> void:
	if card_version != state_version:
		request_full_sync()
	if gov_version != GovernmentManager.state_version:
		GovernmentManager.request_full_sync()
	if party_version != PartyManager.state_version:
		PartyManager.request_full_sync()

@rpc("any_peer", "reliable")
func _request_full_sync() -> void:
	if not MultiplayerManager.is_host:
		return
	_receive_state.rpc_id(multiplayer.get_remote_sender_id(), _pack_state(true), {"type": "full"})

@rpc("any_peer", "reliable")
func _request_play(hand_index: int, target_peer_id: int = -1, target_province: String = "") -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_play(multiplayer.get_remote_sender_id(), hand_index, target_peer_id, target_province)

@rpc("any_peer", "reliable")
func _request_law(law_type: String) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_law(multiplayer.get_remote_sender_id(), law_type)

@rpc("any_peer", "reliable")
func _request_organization(province_id: String) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_organization(multiplayer.get_remote_sender_id(), province_id)

@rpc("any_peer", "reliable")
func _request_invest(province_id: String) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_invest_move(multiplayer.get_remote_sender_id(), province_id)

@rpc("any_peer", "reliable")
func _request_censure() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_censure_move(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _request_miting(province_id: String) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_miting_move(multiplayer.get_remote_sender_id(), province_id)

@rpc("any_peer", "reliable")
func _request_pass() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_pass(multiplayer.get_remote_sender_id(), true)
