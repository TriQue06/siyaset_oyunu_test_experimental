extends Node
## Autoload. Kart envanteri, oynama sırası, MANA ve hamleler, tur/seçim döngüsü,
## seçim sonuçları, İLLERİN GÖRÜŞÜ, AKTİVİTE (il puanı + il başkanlığı), oyuncuya
## özel istihbarat (anket/gözcü) ve oyun sonu. Host yetkili: host-olmayan
## istemcinin isteği önce host'a "any_peer" RPC ile gider, host doğrulayıp
## uygular ve herkese yayınlar.
##
## TUR AKIŞI (bir oyuncunun sırası) — TEK ANA HAMLE:
##   a) KART OYNA: elden bir kart oyna; kartın mana bedeli düşer
##      (CardPresets.card_cost).
##   b) YASA TASARLA (GameRules.LAW_MANA_COST): meclise yasa sun; meclis yoksa
##      oylamasız SEÇİM VAADİ olur.
##   c) TEŞKİLATLANMA (GameRules.ORG_MANA_COST): bir ilde teşkilat kur / geliştir
##      (oy bonusu + ilin görüşü + 2. seviyeden itibaren anket).
##   d) PAS: hamle yapmadan geç, +GameRules.MANA_PASS_BONUS mana.
##   KART ÇEKMEK: bedava, turda bir kez; kart oynamak sınırsız. Her seçimden sonra herkese 1 kart hediye.
##   Tur otomatik geçmez: oyuncu "Turu Bitir"e basar ya da süre dolar.
##   GameRules.TURN_TIMEOUT dolarsa otomatik pas geçilir (mana bonusu yok).
##   Hükümet kurulurken / meclis oylarken tur DURUR (is_turn_blocked).
##
## TUR SONU (herkes birer kez oynayınca) — bkz. GameRules
##   - (mana geliri tur sonunda değil, her oyuncunun sırası geldiğinde verilir),
##   - görevdeki hükümet makam puanlarını alır, eksen keskinliği artar,
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

const MAX_HAND_SIZE := 9
const HEARTBEAT_INTERVAL := 5.0
const PROVINCE_SEATS_PATH := "res://data/province_seats.json"
## İl başına saklanan son olay sayısı (il detay panelinde gösterilir).
const PROVINCE_EVENT_LIMIT := 6

## KART NADİRLİĞİ (bkz. _draw_weights). Değerler mutlak değil, oransal: bir
## kartın gelme olasılığı ağırlığının havuzdaki toplama bölümüdür. İlk seçimden
## önce isyan ve vekil çalma havuza girmez, kalanların payı kendiliğinden artar.
const WEIGHT_PROPAGANDA := 15.0
const WEIGHT_MANA_BONUS := 12.0
const WEIGHT_POPULISM := 12.0
const WEIGHT_STEAL_WEAK := 12.0
const WEIGHT_REPUTATION := 9.0
const WEIGHT_REBELLION := 9.0
const WEIGHT_STEAL_STRONG := 9.0

## Koltuk SAYILARI GERÇEK: TBMM'nin il bazlı milletvekili dağılımı (bkz.
## data/province_seats.json). Bu değer dosyadaki sayıların toplamıdır.
var TOTAL_SEATS := 390

# peer_id -> Array[String] (her biri CardPresets.CARD_TYPES'tan biri)
var inventories: Dictionary = {}
# Array[int]: oynama sırasına göre peer_id'ler.
var turn_order: Array = []
# turn_order içindeki index; sırası gelen oyuncu turn_order[current_turn_index].
var current_turn_index: int = 0
# Sırası gelen oyuncu bu turda kart çekti mi (turda bir çekiş).
var has_drawn_this_turn: bool = false
## Oyuncunun en son yasa sunduğu tur: peer_id -> round_number (turda 1 yasa).
var law_rounds: Dictionary = {}
## Popülizm bonusu: peer_id -> bittiği tur (o turdan önceki son tura kadar sürer).
var populism: Dictionary = {}
## peer_id -> true: partide isyan var, sıradaki ilk yasa oylamasında çekimser.
var rebellion: Dictionary = {}
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
## peer_id -> int
var mana: Dictionary = {}

var game_finished: bool = false
## [{peer_id, name, leader, color, score, seats}], kazanan başta.
var final_ranking: Array = []
var game_end_reason: String = ""

var state_version: int = 0

# Seçim hesabına giren iller ve koltuk sayıları (yetkili kaynak province_seats.json).
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
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_load_province_seat_counts()

func _process(delta: float) -> void:
	if MultiplayerManager.room_code == "" or not MultiplayerManager.is_host:
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

## Gerçek il bazlı milletvekili sayılarını yükler.
func _load_province_seat_counts() -> void:
	_province_seat_counts.clear()
	_province_ids.clear()
	if not FileAccess.file_exists(PROVINCE_SEATS_PATH):
		push_warning("data/province_seats.json bulunamadı — il bazlı seçim sonucu üretilemeyecek.")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PROVINCE_SEATS_PATH))
	if not (parsed is Dictionary):
		push_warning("data/province_seats.json okunamadı — il bazlı seçim sonucu üretilemeyecek.")
		return
	var sum := 0
	for province_id in parsed.keys():
		var seats := int(parsed[province_id])
		if seats <= 0:
			continue
		_province_seat_counts[province_id] = seats
		_province_ids.append(province_id)
		sum += seats
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

func can_draw() -> bool:
	return can_draw_for(multiplayer.get_unique_id())

## Kart çekmek bedava, turda bir kez.
func can_draw_for(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and not has_drawn_this_turn and mana_of(peer_id) >= GameRules.DRAW_MANA_COST \
		and inventories.get(peer_id, []).size() < MAX_HAND_SIZE

## Sıra bende VE tur akışı engellenmemiş mi? (UI bunu kullanmalı.)
func can_act() -> bool:
	return is_my_turn() and not is_turn_blocked()

func my_inventory() -> Array:
	return inventories.get(multiplayer.get_unique_id(), [])

func mana_of(peer_id: int) -> int:
	return int(mana.get(peer_id, 0))

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
	return peer_id == current_turn_peer_id() and not is_turn_blocked()

## Bu oyuncu şu an bir yasa sunabilir mi? (law_type verilirse o yasa geçerli mi.)
func can_propose_law(peer_id: int, law_type: String = "") -> bool:
	if not can_choose_main_action(peer_id) or mana_of(peer_id) < GameRules.LAW_MANA_COST:
		return false
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

func has_proposed_law_this_round(peer_id: int) -> bool:
	return int(law_rounds.get(peer_id, 0)) == round_number

## Yatırım hamlesi: sadece hükümet partileri.
func can_invest(peer_id: int, province_id: String = "") -> bool:
	return can_choose_main_action(peer_id) and is_government_party(peer_id) \
		and mana_of(peer_id) >= GameRules.INVEST_MANA_COST and (province_id == "" or has_province(province_id))

## Mecliste en az bir vekili var mı? (Vekilsiz parti oy veremez, yasa ve
## gensoru veremez, vekil çalamaz.)
func has_seats(peer_id: int) -> bool:
	return int(last_seats.get(peer_id, 0)) > 0

## Gensoru hamlesi: muhalefet, hükümet görevde ve salt çoğunluğu yokken.
func can_censure(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and mana_of(peer_id) >= GameRules.CENSURE_MANA_COST and has_seats(peer_id) \
		and GovernmentManager.phase == GovernmentManager.Phase.GOVERNING and GovernmentManager.has_government() \
		and not GovernmentManager.has_majority() and not is_government_party(peer_id)

## Popülizm bonusunun kalan turu (kullanıldığı turda POPULISM_ROUNDS, yoksa 0).
func populism_rounds_left(peer_id: int) -> int:
	return maxi(0, int(populism.get(peer_id, 0)) - round_number)

## Miting hamlesi: seçilen ilde güç (provokasyon riskiyle).
func can_miting(peer_id: int, province_id: String = "") -> bool:
	return can_choose_main_action(peer_id) and mana_of(peer_id) >= GameRules.MITING_MANA_COST \
		and (province_id == "" or has_province(province_id))

func can_build_organization(peer_id: int, province_id: String) -> bool:
	return can_choose_main_action(peer_id) and mana_of(peer_id) >= GameRules.ORG_MANA_COST \
		and has_province(province_id) and organization_level(province_id, peer_id) < GameRules.ORG_MAX_LEVEL

## Bir partiden vekil çalınabilir mi? Kendinden çalınamaz, meclis dışı partiden
## çalınamaz ve hedefin en az 2 vekili olmalı (1'in altına DÜŞÜRÜLEMEZ).
func is_valid_steal_target(peer_id: int, target_peer_id: int) -> bool:
	if target_peer_id == -1 or target_peer_id == peer_id:
		return false
	# Vekilsiz (meclis dışı / barajı geçemeyen) parti vekil çalamaz: yoksa baraj delinir.
	if not has_seats(peer_id):
		return false
	# Hedefin vekili çalınacak sayıdan azsa hepsi gidebilir (0'a iner).
	return has_seats(target_peer_id)

## Bu kart şu an bu hedeflerle oynanabilir mi? (Host doğrulaması ve UI.)
func can_play_card(peer_id: int, card_type: String, target_peer_id: int = -1, target_province: String = "") -> bool:
	if mana_of(peer_id) < CardPresets.card_cost(card_type):
		return false
	if CardPresets.needs_target(card_type):
		return is_valid_steal_target(peer_id, target_peer_id)
	if card_type == CardPresets.REPUTATION_CARD_TYPE:
		return turn_order.has(target_peer_id) and target_peer_id != peer_id
	if card_type == CardPresets.REBELLION_CARD_TYPE:
		return turn_order.has(target_peer_id) and target_peer_id != peer_id and has_seats(target_peer_id)
	if card_type == CardPresets.PROPAGANDA_CARD_TYPE:
		return has_province(target_province) and turn_order.has(target_peer_id) and target_peer_id != peer_id
	if card_type == CardPresets.SCOUT_CARD_TYPE:
		return false  # gözcü artık teşkilatın parçası
	if CardPresets.needs_province_target(card_type):
		if not has_province(target_province):
			return false
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

## Teşkilatın oy bonusu (popülizm sürerken büyür).
func org_bonus(province_id: String, peer_id: int) -> float:
	var bonus := PublicOpinion.org_activity(organization_level(province_id, peer_id))
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
##   1. seviye: ilin görüşü (her eksende hangi uç), 2: + orta isabetli anket,
##   3: + yüksek isabetli anket.
func knows_leaning(peer_id: int, province_id: String) -> bool:
	return organization_level(province_id, peer_id) >= 1

## Anket sapması (−1: anket yok).
func poll_error(peer_id: int, province_id: String) -> float:
	match organization_level(province_id, peer_id):
		2:
			return GameRules.POLL_ERROR_MEDIUM
		3:
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
	var alloc := ElectionModel.dhondt(shares, eligible, seat_count)
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
	var alloc := ElectionModel.dhondt(shares, projected_eligible(mods), province_seat_count(province_id))
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
		var alloc := ElectionModel.dhondt(shares, eligible, seat_count)
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

# --- Oyun başlangıcı --------------------------------------------------------

## Sadece host çağırır (Parti Kurulum bitip GameScreen'e geçilirken): tüm oyun
## durumunu sıfırlar, illerin görüşünü üretir, oynama sırasını rastgele
## belirler, herkese yayınlar.
func init_game() -> void:
	if not _is_authority():
		return
	inventories.clear()
	mana = {}
	for peer_id in MultiplayerManager.players.keys():
		inventories[peer_id] = []
		mana[peer_id] = GameRules.MANA_START
	turn_order = MultiplayerManager.players.keys().duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	_grant_turn_income()
	has_drawn_this_turn = false
	law_rounds = {}
	populism = {}
	rebellion = {}
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
	national_support = {}
	local_support = {}
	province_events = {}
	province_ideology = ProvinceIdeology.generate(_rng, _province_ids)
	organizations = {}
	game_finished = false
	final_ranking = []
	game_end_reason = ""
	_turn_time_left = GameRules.TURN_TIMEOUT
	_round_end_pending = false
	final_election_pending = false
	GovernmentManager.reset()
	_push_state({"type": "full"}, true)

## Oyundan ayrılınca YEREL oyun durumunu temizler (ağ yayını yok).
func abandon_game() -> void:
	inventories = {}
	turn_order = []
	current_turn_index = 0
	has_drawn_this_turn = false
	round_number = 1
	last_election_round = 0
	last_election_was_early = false
	last_vote_shares = {}
	last_seats = {}
	last_province_results = {}
	passed_threshold = []
	election_seats = {}
	national_support = {}
	local_support = {}
	province_events = {}
	province_ideology = {}
	organizations = {}
	mana = {}
	game_finished = false
	final_ranking = []
	game_end_reason = ""
	_round_end_pending = false

# --- Oyuncu eylemleri -------------------------------------------------------

## Sırası gelen oyuncu, deste butonuna basınca çağırır.
func draw_card() -> void:
	if _is_local_only() and turn_order.is_empty():
		# Aktif oyun yok (örn. sahne editörde tek başına test) — yerel önizleme.
		var id := multiplayer.get_unique_id()
		if not inventories.has(id):
			inventories[id] = []
		if inventories[id].size() >= MAX_HAND_SIZE:
			return
		var card_type := CardPresets.weighted_pick(_draw_weights(id), _rng)
		card_drawn.emit(id, card_type)
		inventories[id].insert(inventories[id].size() / 2, card_type)
		inventories_updated.emit()
		return
	if not can_draw():
		return
	if _is_authority():
		_apply_draw(multiplayer.get_unique_id())
	else:
		_request_draw.rpc_id(1)

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
	weights[CardPresets.POPULISM_CARD_TYPE] = WEIGHT_POPULISM
	weights[CardPresets.MANA_BONUS_CARD_TYPE] = WEIGHT_MANA_BONUS
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

func _apply_draw(peer_id: int) -> void:
	if not can_draw_for(peer_id):
		return
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	mana[peer_id] = mana_of(peer_id) - GameRules.DRAW_MANA_COST
	var card_type := CardPresets.weighted_pick(_draw_weights(peer_id), _rng)
	card_drawn.emit(peer_id, card_type)
	# Yeni kart elin ORTASINA yerleşir.
	inventories[peer_id].insert(inventories[peer_id].size() / 2, card_type)
	has_drawn_this_turn = true
	_push_state({"type": "drawn", "peer_id": peer_id, "card": card_type})

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
func _apply_pass(peer_id: int, _voluntary: bool = true) -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id():
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
	mana[peer_id] = mana_of(peer_id) - GameRules.LAW_MANA_COST
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
			rebellion[target_peer_id] = true
			_event_message = "%s'da parti içi isyan çıktı: sıradaki yasa oylamasında çekimser kalacak." % _party_name(target_peer_id)
		CardPresets.POPULISM_CARD_TYPE:
			populism[peer_id] = round_number + GameRules.POPULISM_ROUNDS
			_event_message = "%s popülizme başladı: %d tur boyunca hamleleri daha etkili." % [_party_name(peer_id), GameRules.POPULISM_ROUNDS]
		CardPresets.MANA_BONUS_CARD_TYPE:
			mana[peer_id] = mana_of(peer_id) + GameRules.MANA_BONUS_AMOUNT
			_event_message = "%s mana bonusu kullandı (+%d mana)." % [_party_name(peer_id), GameRules.MANA_BONUS_AMOUNT]
		CardPresets.PROPAGANDA_CARD_TYPE:
			_apply_propaganda(peer_id, target_peer_id, target_province)
	return false

func _party_name(peer_id: int) -> String:
	return PartyManager.parties.get(peer_id, {}).get("name", "?")

func _province_name(province_id: String) -> String:
	return ElectionNightSim.province_name(province_id)

## Miting: riski ilin mevcut siyasi dengesine göre hesaplanır, zar atılır.
func _apply_miting(peer_id: int, province_id: String) -> void:
	var risk := miting_risk(peer_id, province_id)
	if _rng.randf() < risk:
		_add_local(province_id, peer_id, PublicOpinion.PROVOCATION_LOCAL, true)
		_add_national(peer_id, PublicOpinion.PROVOCATION_NATIONAL, true)
		_log_province(province_id, "%s mitinginde PROVOKASYON (il %.1f, ulusal %.1f)" % [
			_party_name(peer_id), PublicOpinion.PROVOCATION_LOCAL, PublicOpinion.PROVOCATION_NATIONAL])
		_event_message = "%s'da %s mitinginde provokasyon çıktı! (risk %%%d)" % [
			_province_name(province_id), _party_name(peer_id), int(round(risk * 100.0))]
	else:
		_add_local(province_id, peer_id, PublicOpinion.MITING_LOCAL, true)
		_add_national(peer_id, PublicOpinion.MITING_NATIONAL, true)
		_log_province(province_id, "%s miting yaptı (+%.1f)" % [_party_name(peer_id), PublicOpinion.MITING_LOCAL])
		_event_message = "%s, %s'da miting yaptı." % [_party_name(peer_id), _province_name(province_id)]

## Yatırım: getiren parti daha çok, hükümet ortakları daha az kazanır.
## Popülizm yatırımı büyütmez (popülist iktidar için miting daha etkili).
func _apply_investment(peer_id: int, province_id: String) -> void:
	_add_local(province_id, peer_id, PublicOpinion.INVEST_LOCAL)
	_add_national(peer_id, PublicOpinion.INVEST_NATIONAL)
	for partner in GovernmentManager.government_party_ids():
		if partner != peer_id:
			_add_local(province_id, partner, PublicOpinion.INVEST_PARTNER_LOCAL)
	_log_province(province_id, "Hükümet yatırımı — %s getirdi (+%.1f, ortaklar +%.1f)" % [
		_party_name(peer_id), PublicOpinion.INVEST_LOCAL, PublicOpinion.INVEST_PARTNER_LOCAL])
	_event_message = "%s, %s'a hükümet yatırımı getirdi." % [_party_name(peer_id), _province_name(province_id)]

## Karalama: hedefe eksi, karalayana artı; ikisi de o ildeki güçleriyle ölçeklenir.
func _apply_propaganda(peer_id: int, target_peer_id: int, province_id: String) -> void:
	var damage := PublicOpinion.propaganda_damage(party_strength(province_id, target_peer_id))
	if populism_rounds_left(peer_id) > 0:
		damage *= PublicOpinion.POPULISM_GOOD_MULT
	var gain := PublicOpinion.propaganda_gain(party_strength(province_id, peer_id))
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
	PartyManager.apply_ideology_deltas(shifts)
	var notes := ""
	if passed:
		notes += " %s +%d puan." % [_party_name(proposer), law_pass_score(proposer_in_gov)]
	_push_state({"type": "opinion", "message": "%s %s — %s bu görüşe yakın illerde güçlendi%s. Partisi %s yönüne kaydı.%s" % [
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
			_push_state({"type": "agenda", "message": "Gündem arası: %d tur yasa yok, sonra yeni gündemler." % GameRules.AGENDA_GAP})
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
	_push_state({"type": "agenda", "message": "GÜNDEM (%d/%d): %s — bu tur %s." % [pos + 1, GameRules.AGENDA_ROUNDS,
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

## Tur sonu: puanlar sıfıra doğru söner; neredeyse sıfır olanlar silinir.
## (İl başkanlıkları sönmez.)
func _decay_opinion() -> void:
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
	var amount: int = mini(wanted, int(last_seats[target_peer_id]))
	if amount <= 0:
		return false

	var bag: Array = []
	for province_id in last_province_results.keys():
		var here: int = int(last_province_results[province_id].get(target_peer_id, {}).get("seats", 0))
		for i in here:
			bag.append(province_id)
	# Ulusal listeden de vekil çalınabilir ("" = ulusal liste).
	for i in int(national_list.get(target_peer_id, 0)):
		bag.append("")
	bag.shuffle()

	var moved := 0
	for province_id in bag:
		if moved >= amount:
			break
		if province_id == "":
			if int(national_list.get(target_peer_id, 0)) <= 0:
				continue
			national_list[target_peer_id] = int(national_list[target_peer_id]) - 1
			national_list[peer_id] = int(national_list.get(peer_id, 0)) + 1
			moved += 1
			continue
		var entry: Dictionary = last_province_results[province_id]
		var target_entry: Dictionary = entry.get(target_peer_id, {})
		if int(target_entry.get("seats", 0)) <= 0:
			continue
		target_entry["seats"] = int(target_entry["seats"]) - 1
		entry[target_peer_id] = target_entry
		var thief_entry: Dictionary = entry.get(peer_id, {"percent": 0.0, "seats": 0})
		thief_entry["seats"] = int(thief_entry.get("seats", 0)) + 1
		entry[peer_id] = thief_entry
		moved += 1

	if moved == 0:
		return false
	last_seats[target_peer_id] = int(last_seats[target_peer_id]) - moved
	last_seats[peer_id] = int(last_seats.get(peer_id, 0)) + moved
	# Transfer meşru görünmez: çalan küçük bir ulusal destek kaybeder, çalınan
	# parti mağduriyetten küçük bir destek kazanır (ikisi de kısmi).
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
	_add_national(target_peer_id, -damage)
	_event_message = "%s hakkında kaset sızdı: ulusal desteği %.1f puan düştü. (%s)" % [
		_party_name(target_peer_id), damage, _party_name(peer_id)]

## Parti içi isyan sürüyor mu? (sıradaki ilk yasa oylamasında çekimser)
func has_rebellion(peer_id: int) -> bool:
	return bool(rebellion.get(peer_id, false))

## İsyan kullanıldı: bayrak düşer (host yetkili; yasa oylaması başlarken).
func consume_rebellion(peer_id: int) -> bool:
	if not has_rebellion(peer_id):
		return false
	rebellion.erase(peer_id)
	return true

## GovernmentManager, hükümet güvenoyu alınca çağırır: hükümet partilerine mana.
func grant_government_mana(peer_ids: Array) -> void:
	if not _is_authority():
		return
	for peer_id in peer_ids:
		if mana.has(peer_id):
			mana[peer_id] = mana_of(peer_id) + GameRules.GOVERNMENT_MANA_BONUS
	_push_state({"type": "mana"})

## İki partinin ideolojik yakınlığı: 1 aynı görüş, 0 zıt radikal uçlar.
func ideological_closeness(a: int, b: int) -> float:
	var ia: Dictionary = PartyManager.parties.get(a, {}).get("ideology", IdeologyAxes.default_values())
	var ib: Dictionary = PartyManager.parties.get(b, {}).get("ideology", IdeologyAxes.default_values())
	return clampf(1.0 - IdeologyAxes.distance(ia, ib) / IdeologyAxes.max_distance(), 0.0, 1.0)

## Bu partinin hedeften bu kartla çalabileceği vekil aralığı (yakınlığa göre).
func steal_range(peer_id: int, target_peer_id: int, card_type: String) -> Dictionary:
	return CardPresets.steal_range(card_type, ideological_closeness(peer_id, target_peer_id))

## Sırayı bir sonrakine devreder; index başa sardıysa (tur bitti) true döner.
func _advance_turn() -> bool:
	var size: int = maxi(1, turn_order.size())
	var wrapped: bool = (current_turn_index + 1) >= size
	current_turn_index = (current_turn_index + 1) % size
	has_drawn_this_turn = false
	_turn_time_left = GameRules.TURN_TIMEOUT
	_grant_turn_income()
	return wrapped

## Sırası gelen oyuncu mana gelirini alır.
func _grant_turn_income() -> void:
	var peer_id := current_turn_peer_id()
	if peer_id != -1:
		mana[peer_id] = mana_of(peer_id) + turn_income(peer_id)

## Tur geliri: hükümette görevi olan partiler bir fazla mana alır.
func turn_income(peer_id: int) -> int:
	if GovernmentManager.government_party_ids().has(peer_id):
		return GameRules.MANA_PER_ROUND_GOVERNMENT
	return GameRules.MANA_PER_ROUND

## Desteden bir kartı doğrudan ele verir (seçim hediyesi). El doluysa verilmez.
func _deal_turn_card(peer_id: int) -> void:
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	if inventories[peer_id].size() >= MAX_HAND_SIZE:
		return
	var card_type := CardPresets.weighted_pick(_draw_weights(peer_id), _rng)
	inventories[peer_id].insert(inventories[peer_id].size() / 2, card_type)

# --- Tur sonu / seçim / oyun sonu -------------------------------------------

func _finish_round_if_needed(wrapped: bool) -> void:
	if not wrapped or game_finished:
		return
	if is_turn_blocked():
		# Örn. turun son hamlesi gensoru ya da yasaydı: oylama bitince tur kapanacak.
		_round_end_pending = true
		return
	_finish_round()

func _finish_round() -> void:
	_round_end_pending = false
	# Biten turda görevde olan hükümet görev puanlarını KAZANIR (birikimli).
	GovernmentManager.award_round_scores()
	var finished_round := round_number
	round_number += 1
	current_axis_sharpness = minf(current_axis_sharpness + MultiplayerManager.axis_sharpness_increment,
		MultiplayerManager.AXIS_SHARPNESS_HARD_MAX)
	if MultiplayerManager.axis_sharpness_max_enabled:
		current_axis_sharpness = minf(current_axis_sharpness, MultiplayerManager.axis_sharpness_max_value)

	if finished_round >= GameRules.MAX_ROUNDS:
		# SON SEÇİM: kurulan hükümet puanlarını alınca oyun biter (bkz. on_block_state_changed).
		final_election_pending = true
		_hold_election(finished_round, false)
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

## Son seçimin ardından hükümet kurma bitti: kurulduysa hükümet partileri makam
## puanlarını son kez alır, puan tablosu kesinleşir.
func _finish_final_election() -> void:
	final_election_pending = false
	if GovernmentManager.has_government():
		GovernmentManager.award_round_scores()
		_end_game("%d tur tamamlandı. Son seçimle kurulan %s hükümeti makam puanlarını aldı." % [
			GameRules.MAX_ROUNDS, _party_name(GovernmentManager.main_gov_peer_id)])
	else:
		_end_game("%d tur tamamlandı. Son seçimden sonra hükümet kurulamadı." % GameRules.MAX_ROUNDS)

func _end_game(reason: String) -> void:
	game_finished = true
	game_end_reason = reason
	final_ranking = []
	var ids: Array = turn_order.duplicate()
	ids.sort_custom(func(a, b):
		var sa := GovernmentManager.score_of(a)
		var sb := GovernmentManager.score_of(b)
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
			"score": GovernmentManager.score_of(peer_id),
			"seats": int(last_seats.get(peer_id, 0)),
		})
	GovernmentManager.end_game()
	_push_state({"type": "game_over"})

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
		has_drawn_this_turn = false
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
		"has_drawn": has_drawn_this_turn,
		"law_rounds": law_rounds,
		"populism": populism,
		"rebellion": rebellion,
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
		"passed": passed_threshold,
		"national": national_support,
		"local": local_support,
		"events": province_events,
		"organizations": organizations,
		"mana": mana,
		"game_finished": game_finished,
		"final_ranking": final_ranking,
		"end_reason": game_end_reason,
	}
	if include_results:
		state["province_results"] = last_province_results
		state["province_ideology"] = province_ideology
	return state

func _apply_state(state: Dictionary) -> void:
	state_version = int(state["version"])
	inventories = state["inventories"]
	turn_order = state["turn_order"]
	current_turn_index = int(state["turn_index"])
	has_drawn_this_turn = bool(state["has_drawn"])
	law_rounds = state.get("law_rounds", {})
	populism = state.get("populism", {})
	rebellion = state.get("rebellion", {})
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
	passed_threshold = state["passed"]
	national_support = state["national"]
	local_support = state["local"]
	province_events = state["events"]
	organizations = state.get("organizations", {})
	mana = state.get("mana", {})
	game_finished = bool(state["game_finished"])
	final_ranking = state["final_ranking"]
	game_end_reason = str(state["end_reason"])
	if state.has("province_results"):
		last_province_results = state["province_results"]
	if state.has("province_ideology"):
		province_ideology = state["province_ideology"]

## Host: durumu (sürümü artırarak) herkese yayınlar ve olayın sinyallerini
## kendi tarafında da doğrudan atar (.rpc() göndericide çalışmaz).
func _push_state(event: Dictionary, include_results: bool = false) -> void:
	state_version += 1
	if not _is_local_only():
		_receive_state.rpc(_pack_state(include_results or event.get("type", "") in ["full", "election", "player_left"]), event)
	_emit_post_event(event)

func _emit_post_event(event: Dictionary) -> void:
	var type: String = event.get("type", "")
	inventories_updated.emit()
	if type in ["full", "player_left"]:
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
		"full", "player_left":
			seats_changed.emit()
		"played":
			if bool(event.get("seats_changed", false)):
				seats_changed.emit()
	if event.has("message"):
		opinion_event.emit(str(event["message"]))

@rpc("authority", "reliable")
func _receive_state(state: Dictionary, event: Dictionary) -> void:
	# Animasyon sinyalleri ESKİ state üzerinden kurulsun diye önce bunlar.
	match str(event.get("type", "")):
		"drawn":
			card_drawn.emit(int(event["peer_id"]), str(event["card"]))
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
func _request_draw() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_draw(multiplayer.get_remote_sender_id())

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
