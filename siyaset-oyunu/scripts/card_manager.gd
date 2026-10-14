extends Node
## Autoload. Kart envanteri, oynama sırası, PARA ve hamleler, tur/seçim döngüsü,
## seçim sonuçları, İLLERİN SEÇMEN PROFİLİ, GRUP TOPLANTILARI, AKTİVİTE (il puanı
## + il başkanlığı), oyuncuya
## özel istihbarat (anket/gözcü) ve oyun sonu. Host yetkili: host-olmayan
## istemcinin isteği önce host'a "any_peer" RPC ile gider, host doğrulayıp
## uygular ve herkese yayınlar.
##
## TUR AKIŞI (bir oyuncunun sırası):
##   0) GRUP TOPLANTISI (isteğe bağlı, dönemde partide bir kez): 8 seçmen
##      grubundan birini seçer; o grupta GEÇİCİ destek (PublicOpinion.MEETING_BONUS:
##      bu tur +10, sonraki +3, sonraki +1). Toplantı yapmamanın cezası yok.
##   a) KART OYNA: elden bir kart oyna; kartın para bedeli düşer
##      (CardPresets.card_cost).
##   b) YASA TASARLA (GameRules.LAW_FUNDS_COST): meclise yasa sun; meclis yoksa
##      oylamasız SEÇİM VAADİ olur.
##   c) TEŞKİLATLANMA (GameRules.ORG_FUNDS_COST): bir ilde teşkilat kur / geliştir
##      (oy bonusu + seviyeye göre anket).
##   d) PAS: hamle yapmadan geç, +GameRules.FUNDS_PASS_BONUS para.
##   KART: sıra gelince otomatik 1 kart dağıtılır; kart oynamak sınırsız. Her seçimden sonra herkese 1 kart hediye.
##   Tur otomatik geçmez: oyuncu "Turu Bitir"e basar ya da süre dolar.
##   GameRules.TURN_TIMEOUT dolarsa otomatik pas geçilir (bağış kampanyası yok).
##   Hükümet kurulurken / meclis oylarken tur DURUR (is_turn_blocked).
##
## TUR SONU (herkes birer kez oynayınca) — bkz. GameRules
##   - (para geliri tur sonunda değil, her oyuncunun sırası geldiğinde verilir),
##   - (makam puanları hükümet kurulurken yazılır),
##   - il/ulusal puanlar sıfıra doğru söner (il başkanlığı sönmez),
##   - son tursa oyun biter; seçim turuysa (ya da hükümet kurulamadıysa
##     ERKEN SEÇİM) seçim yapılır ve hükümet kurma aşaması başlar,
##   - tur sonu bir oylamanın ortasına denk gelirse oylama bitene kadar ertelenir.
##
## AÇIK BİLGİ: illerin seçmen grubu dağılımı herkese açıktır. GİZLİ BİLGİ:
## anket sonuçları ağ üzerinden herkese gönderilen durumun içindedir; sadece
## ARAYÜZ ilgili oyuncuya gösterir.
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
## Seçimsiz bir tur bitti.
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
## Kongre gösterisi başlıyor (herkes): data = CardManager._compute_congress sonucu.
signal congress_started(data: Dictionary)
## EKONOMİ OLAYI (herkeste): {"kind": "tax", "from", "to"} vergi değişti,
## {"kind": "invest", "peer_id", "province", "cost", "before", "after"} hazineden
## yatırım, {"kind": "round", "revenue"} tur sonu geliri. Arayüz bununla
## hazine/gösterge animasyonlarını oynatır (değerler zaten durumda).
signal economy_event(data: Dictionary)
## FİNANSMAN SORUŞTURMASI sonuçlandı (herkeste): {"peer_id", "target", "result"
## ("clean" / "scandal" / "none"), "examined", "party_million", "public_million",
## "improper_million", "gain", "damage"}.
signal inquiry_resolved(data: Dictionary)

const MAX_HAND_SIZE := 9
## Bağımsız siyasetçinin (teşkilatsız) mitinginde provokasyon riski çarpanı.
const INDEPENDENT_MITING_RISK_MULT := 1.5
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
const WEIGHT_FUNDS_BONUS := 12.0
const WEIGHT_FUNDS_BONUS_STRONG := 6.0
const WEIGHT_BONUS_CARD := 15.0
const WEIGHT_CARD_THEFT := 6.0
const WEIGHT_POPULISM := 12.0
const WEIGHT_STEAL_STRONG := 6.0
const WEIGHT_EARLY_ELECTION := 6.0
const WEIGHT_REPUTATION := 3.0
const WEIGHT_REBELLION := 18.0

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
## GRUP TOPLANTISI: sırası gelen oyuncunun PARTİSİ bu dönem toplantı yaptı mı?
## (Grup toplantısı partiye aittir: iki kişilik partide biri yaptıysa
## diğeri o dönem yapamaz; bkz. speech_rounds.)
var speech_done: bool = false
## Parti -> grup toplantısı yaptığı son dönem.
var speech_rounds: Dictionary = {}
## Parti -> kongre yapıldığı son dönem (dönemde bir kongre).
var congress_rounds: Dictionary = {}
## Bir önceki seçimin oy oranları (kongrede "oy kaybı" ölçüsü).
var previous_vote_shares: Dictionary = {}
## Testler için: false ise toplantı hakkı hiç açılmaz.
var speech_required: bool = true
## GEÇİCİ GRUP DESTEĞİ: parti -> {grup -> toplantının yapıldığı tur}. Bonus
## toplantı turundan itibaren PublicOpinion.MEETING_BONUS ile azalır; aynı gruba
## yeni toplantı eskisinin yerini alır (toplanmaz).
var group_meetings: Dictionary = {}
## MİTİNG YORGUNLUĞU (azalan getiri): parti -> {grup -> birikmiş kazanç}.
## Her tur sonunda PublicOpinion.MITING_FATIGUE_DECAY ile söner.
var miting_fatigue: Dictionary = {}
## Son seçim anındaki grup yakınlıkları: parti -> {grup -> değer} (arayüzde
## "son seçimden beri" değişimi göstermek için).
var election_groups: Dictionary = {}
## GÜNDEM: {"type": gündem türü, "until": bittiği tur} (boş = gündem yok).
var agenda: Dictionary = {}
## KRİZ: {"type": "kriz_<grup>", "until": tur}. Gündemle birlikte açılır.
var crisis: Dictionary = {}
var _crisis_rng := RandomNumberGenerator.new()
## Sadece host: gündem çiftlerinin sırası (her turda karıştırılır).
var _agenda_pairs: Array = []
var _last_agenda_pair: String = ""
## peer_id -> int: son seçimde ulusal listeden kazanılan vekil.
var national_list: Dictionary = {}

## Şu an oynanan tur (1'den başlar).
var round_number: int = 1
## Son seçimin yapıldığı tur (0 = henüz seçim yok) ve erken seçim olup olmadığı.
var last_election_round: int = 0
var last_election_was_early: bool = false
# peer_id -> float (yüzde, toplamı 100). Son seçimin sonucu.
var last_vote_shares: Dictionary = {}
## GENEL BAŞKAN GÜVENİLİRLİĞİ: peer_id -> 0..CREDIBILITY_MAX. Parti bir önceki
## seçime göre oy kaybederse düşer. ŞİMDİLİK HİÇBİR ETKİSİ YOK; ileride genel
## başkan değişimi gibi olaylar buna bağlanacak.
var credibility: Dictionary = {}
## Bu dönemin oyun müziği (AudioManager.GAME_TRACKS); oyun başında ve her
## seçimden sonra rastgele seçilir, herkes aynısını duyar.
var music_track: String = "game"
const CREDIBILITY_MAX := 100.0
const CREDIBILITY_START := 100.0
## Oy kaybında düşüş: sabit + kaybedilen her yüzde puanı başına.
const CREDIBILITY_DROP_BASE := 5.0
const CREDIBILITY_DROP_PER_POINT := 2.0
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
## İL SEÇMEN PROFİLLERİ (oyun başında üretilir, DEĞİŞMEZ):
## province_id -> {çift_id: ilk grubun yüzdesi (tam sayı)} (bkz. VoterGroups).
var province_profiles: Dictionary = {}
## province_id -> { peer_id -> seviye (1..GameRules.ORG_MAX_LEVEL) }
var organizations: Dictionary = {}
## peer_id -> int
var funds: Dictionary = {}
## EKONOMİ (bkz. Economy): vergi kademesi, hissedilen vergi baskısı, ekonomi
## endeksi, yatırım ivmesi, DEVLET HAZİNESİ, bekleyen yatırım dilimleri.
var economy: Dictionary = Economy.start_state()
## Tur sonu ekonomi olayı: bir sonraki durum yayınına iliştirilir.
var _pending_econ: Dictionary = {}

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
## Bölünme/birleşme gibi ek log kayıtları: bir sonraki state olayına iliştirilir.
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
	_crisis_rng.seed = value + 7919

## Host'un zamanlayıcıları (tur süresi, heartbeat). _process çağırır; testler
## doğrudan çağırabilir.
func tick(delta: float) -> void:
	if not _is_authority():
		return
	if congress_active:
		_congress_time_left -= delta
		if _congress_time_left <= 0.0:
			_finish_congress_show()
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

## OYUNCU / PARTİ: sıra, para, el, puan ve güvenilirlik OYUNCUYA (peer_id);
## destek, teşkilat, vekil, seçmen grubu yakınlığı, yasa/toplantı hakkı PARTİYE aittir. Parti
## anahtarı genel başkanın peer_id'sidir (bkz. PartyManager.party_of). Parti
## düzeyindeki sorgular ve yazmalar argümanı her zaman party_of'tan geçirir:
## yardımcı da kendi peer_id'siyle sorsa partisinin verisini görür.
func party_of(peer_id: int) -> int:
	return PartyManager.party_of(peer_id)

## Seçime giren partiler (bağımsızlar dahil, Bağımsızlar bloğu hariç), sıra düzeninde.
func party_ids() -> Array:
	var ids: Array = []
	for peer_id in turn_order:
		var pid := party_of(int(peer_id))
		if not ids.has(pid):
			ids.append(pid)
	return ids

## Partideki oyuncu sayısı (para ve puan bölüşümü için).
func member_count(peer_id: int) -> int:
	return PartyManager.member_count(party_of(peer_id))

## Hükümet kurulurken, mecliste bir teklif oylanırken ya da oyun bittiyse
## TUR DURUR: kimse kart çekemez, oynayamaz, pas geçemez.
func is_turn_blocked() -> bool:
	return game_finished or congress_active \
		or GovernmentManager.phase == GovernmentManager.Phase.FORMING \
		or GovernmentManager.phase == GovernmentManager.Phase.VOTING

func is_my_turn() -> bool:
	return current_turn_peer_id() == multiplayer.get_unique_id()

## Sıra bende VE tur akışı engellenmemiş mi? (UI bunu kullanmalı.)
func can_act() -> bool:
	return is_my_turn() and not is_turn_blocked()

func my_inventory() -> Array:
	return inventories.get(multiplayer.get_unique_id(), [])

## PARA ONDALIKLI: çöpe atılan kart bedelinin YARISINI geri verdiği için
## yarım basamaklar oluşur (bkz. discard_card).
func funds_of(peer_id: int) -> float:
	return float(funds.get(peer_id, 0.0))

## Para yazısı: tam sayıysa "3", değilse "2,5".
static func funds_text(value: float) -> String:
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
	return GovernmentManager.government_party_ids().has(party_of(peer_id))

## Sıra bu oyuncuda ve tur akışı engellenmemiş mi? (Her hamlenin ön şartı;
## hamle sayısı sınırsız, para belirler.)
func can_choose_main_action(peer_id: int) -> bool:
	return peer_id == current_turn_peer_id() and not is_turn_blocked()

## Bu oyuncu bu sırada grup toplantısı yapabilir mi? (Toplantı isteğe bağlıdır;
## yapmamanın cezası yok.) Toplantı hakkı DÖNEMLİKTİR ve partiye aittir: o
## dönem partisi toplandıysa toplanamaz; kasası yetmiyorsa da hakkı yok. (Önbellekteki speech_done'a güvenilmez: turun ilk oyuncusunun
## sırası tur numarası artmadan başlar, eski dönemin bilgisi taşınıyordu.)
func needs_speech(peer_id: int) -> bool:
	return speech_required and not turn_order.is_empty() and peer_id == current_turn_peer_id() and not is_party_member(peer_id) \
		and int(speech_rounds.get(party_of(peer_id), 0)) != round_number and funds_of(peer_id) >= GameRules.SPEECH_FUNDS_COST

## Bu oyuncu şu an bir yasa sunabilir mi? (law_type verilirse o yasa geçerli mi.)
## law_type boşsa: grup yasası YA DA vergi yasası sunabiliyorsa true.
func can_propose_law(peer_id: int, law_type: String = "") -> bool:
	if CardPresets.is_tax_law(law_type):
		return can_propose_tax_law(peer_id, CardPresets.tax_law_level(law_type))
	if law_type == "" and can_propose_tax_law(peer_id):
		return true
	if not can_choose_main_action(peer_id) or is_party_member(peer_id) or funds_of(peer_id) < law_funds_cost(peer_id, law_type):
		return false
	if not has_seats(peer_id):
		return false  # meclis dışı parti yasa teklif edemez
	# Yasa sadece gündemdeki çiftin gruplarından biri için sunulabilir.
	if agenda_type() == "":
		return false
	if law_type != "" and not law_on_agenda(law_type):
		return false
	if has_proposed_law_this_round(peer_id):
		return false
	if law_type != "" and not CardPresets.is_law_card(law_type):
		return false
	# İlk seçime kadar meclis yok: yasa yapılamaz (saf propaganda dönemi).
	return not last_seats.is_empty() and GovernmentManager.can_submit_law()

## VERGİ YASASI: sadece HÜKÜMET partileri sunar; gündem şartı yok ama
## partinin dönemlik yasa hakkını kullanır ve meclis oylamasından geçer.
## level verilirse (≥ 0) o kademe şu ankinden farklı olmalı.
func can_propose_tax_law(peer_id: int, level: int = -1) -> bool:
	return tax_law_block_reason(peer_id, level) == ""

## Vergi yasası neden sunulamıyor ("" = sunulabilir). Arayüz bunu gösterir.
func tax_law_block_reason(peer_id: int, level: int = -1) -> String:
	if last_seats.is_empty():
		return L.t("İlk seçime kadar meclis yok: vergi değiştirilemez.")
	if not is_government_party(peer_id):
		return L.t("Vergi yasasını sadece hükümet partileri sunabilir.")
	if is_party_member(peer_id):
		return L.t("Yasayı partinin genel başkanı sunar.")
	if not has_seats(peer_id):
		return L.t("Mecliste vekilin yok.")
	if has_proposed_law_this_round(peer_id):
		return L.t("Partin bu dönem yasa hakkını kullandı.")
	if not GovernmentManager.can_submit_law():
		return L.t("Mecliste başka bir oylama sürüyor.")
	if not can_choose_main_action(peer_id):
		return L.t("Sıra sende değil.")
	if funds_of(peer_id) < GameRules.LAW_FUNDS_COST:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(GameRules.LAW_FUNDS_COST)
	if level >= 0 and (level == tax_level() or not Economy.TAX_LEVELS.has(level)):
		return L.t("Vergi zaten %s.") % Economy.tax_title(tax_level())
	return ""

## Yasanın bu partiye bedeli (her grup için aynı).
func law_funds_cost(_peer_id: int, _law_type: String = "") -> int:
	return GameRules.LAW_FUNDS_COST

## ANAYASA DEĞİŞİKLİĞİ sunulabilir mi? Yasadan farkı: GÜNDEM ŞARTI YOK
## (anayasa her dönem gündeme bakılmaksızın önerilebilir). Yasa hakkını
## kullanır: aynı dönemde ikisinden sadece biri sunulabilir.
func can_propose_constitution(peer_id: int) -> bool:
	if not can_choose_main_action(peer_id):
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
	law_rounds[party_of(peer_id)] = round_number
	_push_state({"type": "law", "peer_id": peer_id, "law": "anayasa"})

@rpc("any_peer", "reliable")
func _request_constitution(payload: Dictionary) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_constitution_proposal(multiplayer.get_remote_sender_id(), payload)

## Yasa hakkı PARTİYE aittir: dönemde bir yasa (partinin iki üyesinden biri sunar).
func has_proposed_law_this_round(peer_id: int) -> bool:
	return int(law_rounds.get(party_of(peer_id), 0)) == round_number

## Yatırım hamlesi: sadece hükümet partileri; DEVLET HAZİNESİNDEN ödenir
## (Economy.INVEST_COST; hazine yetmezse kalanı parti kasasından).
## state: devletin payı (0..1); -1 = uygun bir paylaşım var mı.
func can_invest(peer_id: int, province_id: String = "", state: float = -1.0) -> bool:
	if not (can_choose_main_action(peer_id) and is_government_party(peer_id) and not is_party_member(peer_id)
			and (province_id == "" or has_province(province_id))):
		return false
	return _funding_ok(funding_range(peer_id, "invest"), state)

# --- Finansman paylaşımı ------------------------------------------------------

## Hamlenin finansman seçenekleri: {"kind", "total" (milyon ₺), "min", "max"
## (devlet payının izinli aralığı), "default", "state_allowed"}. min > max ise
## hiçbir paylaşım ödenemez.
func funding_range(peer_id: int, kind: String) -> Dictionary:
	var total := Economy.INVEST_COST if kind == "invest" else float(GameRules.MITING_FUNDS_COST)
	var state_allowed := is_government_party(peer_id) and not is_party_member(peer_id) and not PartyManager.is_independent(peer_id)
	var party_cap := maxf(0.0, funds_of(peer_id))
	var lo := clampf(1.0 - party_cap / total, 0.0, 1.0)
	# Devlet payı partinin HAZİNE KOTASIYLA sınırlı (bkz. state_quota).
	var hi := clampf(state_quota(peer_id) / total, 0.0, 1.0) if state_allowed else 0.0
	# %5 adımlara oturt: alt sınır yukarı, üst sınır aşağı yuvarlanır (aşım olmaz).
	lo = ceilf(lo / Economy.FUND_STEP - 0.0001) * Economy.FUND_STEP
	hi = floorf(hi / Economy.FUND_STEP + 0.0001) * Economy.FUND_STEP
	var preferred := 1.0 if kind == "invest" else 0.0
	return {"kind": kind, "total": total, "min": lo, "max": hi,
		"default": clampf(preferred, lo, hi), "state_allowed": state_allowed}

static func _funding_ok(r: Dictionary, state: float) -> bool:
	if float(r["min"]) > float(r["max"]) + 0.0001:
		return false
	if state < 0.0:
		return true
	var s := Economy.snap_share(state)
	return s >= float(r["min"]) - 0.0001 and s <= float(r["max"]) + 0.0001

## Paylaşım neden ödenemiyor ("" = ödenebilir).
func funding_block_reason(peer_id: int, kind: String, state: float) -> String:
	var r := funding_range(peer_id, kind)
	var split := Economy.split_cost(float(r["total"]), state)
	if float(split["state"]) > state_treasury() + 0.001:
		return L.t("Devlet hazinesi yetmiyor (%s var).") % Economy.money_full(state_treasury())
	if float(split["state"]) > state_quota(peer_id) + 0.001:
		return L.t("Bu dönemki hazine kotan yetmiyor (%s kaldı).") % Economy.money_full(state_quota(peer_id))
	if float(split["state"]) > 0.0 and not bool(r["state_allowed"]):
		return L.t("Devlet hazinesini sadece hükümet partileri kullanabilir.")
	if float(split["party"]) > funds_of(peer_id) + 0.001:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(float(split["party"]))
	return ""

## Gerçek finansmanı kaydeder (soruşturmanın tek kaynağı).
func _record_funding(peer_id: int, kind: String, province_id: String, split: Dictionary, total: float) -> void:
	var ledger: Array = economy.get("ledger", [])
	var id := int(economy.get("next_id", 1))
	economy["next_id"] = id + 1
	ledger.append({"id": id, "round": round_number, "party": party_of(peer_id), "kind": kind, "province": province_id,
		"total": total, "party_million": float(split["party"]),
		"state_million": float(split["state"]), "investigated": false})
	economy["ledger"] = Economy.prune_ledger(ledger, round_number)

## Partinin henüz incelenmemiş, kapsam içindeki işlemleri (sadece SAYI ve tür
## herkese açıktır; tutarlar soruşturmada açıklanır).
func inquiry_records(target: int) -> Array:
	var pid := party_of(target)
	var result: Array = []
	for entry in economy.get("ledger", []):
		if int(entry["party"]) == pid and not bool(entry.get("investigated", false)) \
				and round_number - int(entry["round"]) <= Economy.INQUIRY_SCOPE_ROUNDS:
			result.append(entry)
	return result

## FİNANSMAN SORUŞTURMASI açılabilir mi? Meclis kurulmuş, soruşturan partinin
## vekili var, sırası ve kasası var, partisi bu dönem soruşturma açmamış.
## Hükümet de muhalefet de açabilir; hedef herhangi bir parti (kendi dahil).
func inquiry_block_reason(peer_id: int, target: int = -1) -> String:
	if last_seats.is_empty():
		return L.t("İlk seçime kadar meclis yok: soruşturma açılamaz.")
	if is_party_member(peer_id):
		return L.t("Soruşturmayı partinin genel başkanı açar.")
	if not has_seats(peer_id):
		return L.t("Mecliste vekilin yok.")
	if int(economy.get("inquiries", {}).get(party_of(peer_id), -1)) == round_number:
		return L.t("Partin bu dönem bir soruşturma açtı.")
	if not can_choose_main_action(peer_id):
		return L.t("Sıra sende değil.")
	if funds_of(peer_id) < Economy.INQUIRY_FUNDS_COST:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(Economy.INQUIRY_FUNDS_COST)
	if target != -1 and (not party_ids().has(party_of(target)) or PartyManager.is_independent(target)):
		return L.t("Bu parti soruşturulamaz.")
	return ""

func can_open_inquiry(peer_id: int, target: int = -1) -> bool:
	return inquiry_block_reason(peer_id, target) == ""

func open_inquiry(target: int) -> void:
	if not can_open_inquiry(multiplayer.get_unique_id(), target):
		return
	if _is_authority():
		_apply_inquiry(multiplayer.get_unique_id(), target)
	else:
		_request_inquiry.rpc_id(1, target)

@rpc("any_peer", "reliable")
func _request_inquiry(target: int) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_inquiry(multiplayer.get_remote_sender_id(), target)

## Soruşturma: hedefin kapsamdaki incelenmemiş işlemleri GERÇEK kayıtlarla
## sınıflanır ve hepsi "incelendi" olur (aynı işlem ikinci kez ödül ya da
## skandal üretmez):
##   parti kasasından ödenen  → şeffaflık (hedefe sınırlı ulusal destek)
##   devletten ödenen yatırım → meşru kamu harcaması (etki yok)
##   devletten ödenen miting  → usulsüzlük (kaset benzeri skandal)
## Kanıt yoksa kimse ödül ya da ceza almaz.
func _apply_inquiry(peer_id: int, target: int) -> void:
	if not can_open_inquiry(peer_id, target):
		return
	var tpid := party_of(target)
	funds[peer_id] = funds_of(peer_id) - Economy.INQUIRY_FUNDS_COST
	var inquiries: Dictionary = economy.get("inquiries", {})
	inquiries[party_of(peer_id)] = round_number
	economy["inquiries"] = inquiries
	var records := inquiry_records(tpid)
	var party_million := 0.0
	var eligible := 0.0
	var public_million := 0.0
	var improper_million := 0.0
	for entry in records:
		entry["investigated"] = true
		party_million += float(entry["party_million"])
		eligible += Economy.transparency_amount(entry)
		if Economy.is_partisan(String(entry["kind"])):
			improper_million += float(entry["state_million"])
		else:
			public_million += float(entry["state_million"])
	var gain := Economy.transparency_gain(eligible) * (Economy.SELF_AUDIT_FACTOR if party_of(peer_id) == tpid else 1.0)
	var damage := Economy.scandal_damage(improper_million)
	if gain > 0.0:
		_add_national(tpid, gain)
	if damage > 0.0:
		_add_national(tpid, -damage)
		_add_turmoil(tpid, PublicOpinion.TURMOIL_REPUTATION)
		if party_of(peer_id) != tpid:
			credibility_add(peer_id, Economy.INQUIRY_CREDIBILITY)
	var result := "scandal" if damage > 0.0 else ("clean" if gain > 0.0 else "none")
	var who := _party_name(tpid)
	var text := ""
	match result:
		"scandal":
			text = L.t("USULSÜZLÜK — Finansman soruşturması: %s partizan faaliyetler için devlet hazinesinden %s kullandı. Skandal partiyi %s baskı altına sokuyor.") % [
				who, Economy.money_full(improper_million), L.t("ağır") if EffectWords.level(damage) >= 3 else "ciddi"]
			if party_million > 0.0:
				text += L.t(" Kendi kasasından ödediği %s ise doğrulandı.") % Economy.money_full(party_million)
		"clean":
			text = L.t("ŞEFFAF — Finansman soruşturması: %s %s harcamayı kendi kasasından yaptığı doğrulandı. %s") % [
				who, Economy.money_full(party_million), L.t("Parti itibar kazanıyor.") if gain > 0.0 else L.t("Belirgin bir siyasi etkisi yok.")]
		_:
			text = L.t("KANIT YOK — Finansman soruşturması %s hakkında %s.") % [who,
				L.t("incelenecek yeni bir işlem bulamadı") if records.is_empty() else L.t("nitelikli bir kanıt bulamadı")]
	if public_million > 0.0:
		text += L.t(" %s devlet yatırımı meşru kamu harcaması sayıldı.") % Economy.money_full(public_million)
	var data := {"peer_id": peer_id, "target": tpid, "result": result, "examined": records.size(),
		"party_million": party_million, "public_million": public_million, "improper_million": improper_million,
		"gain": gain, "damage": damage}
	_push_state({"type": "inquiry", "peer_id": peer_id, "message": text, "inquiry": data})

## Mecliste en az bir vekili var mı? (Vekilsiz parti oy veremez, yasa ve
## gensoru veremez, vekil çalamaz.)
func has_seats(peer_id: int) -> bool:
	return int(last_seats.get(party_of(peer_id), 0)) > 0

## Gensoru hamlesi: muhalefet, hükümet görevde ve salt çoğunluğu yokken.
func can_censure(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and not is_party_member(peer_id) and funds_of(peer_id) >= GameRules.CENSURE_FUNDS_COST and has_seats(peer_id) \
		and GovernmentManager.phase == GovernmentManager.Phase.GOVERNING and GovernmentManager.has_government() \
		and not GovernmentManager.has_majority() and not is_government_party(peer_id)

## ERKEN SEÇİM hamlesi: meclis gerekir, oylama açık olmamalı, zaten erken
## seçim kararı yoksa.
func can_early_election(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and not is_party_member(peer_id) and funds_of(peer_id) >= GameRules.EARLY_ELECTION_FUNDS_COST \
		and has_seats(peer_id) and not early_election_pending and GovernmentManager.can_submit_law()

func early_election() -> void:
	if not can_early_election(multiplayer.get_unique_id()):
		return
	if _is_authority():
		_apply_early_election_move(multiplayer.get_unique_id())
	else:
		_request_early_election.rpc_id(1)

func _apply_early_election_move(peer_id: int) -> void:
	if not can_early_election(peer_id):
		return
	funds[peer_id] = funds_of(peer_id) - GameRules.EARLY_ELECTION_FUNDS_COST
	_push_state({"type": "early_election", "peer_id": peer_id,
		"message": L.t("%s erken seçim önergesi verdi: meclis oylaması başladı.") % _party_name(peer_id)})
	GovernmentManager.submit_early_election(peer_id)

@rpc("any_peer", "reliable")
func _request_early_election() -> void:
	if MultiplayerManager.is_host:
		_apply_early_election_move(multiplayer.get_remote_sender_id())

## Popülizm bonusunun kalan turu (kullanıldığı turda POPULISM_ROUNDS, yoksa 0).
func populism_rounds_left(peer_id: int) -> int:
	return maxi(0, int(populism.get(party_of(peer_id), 0)) - round_number)

## Miting hamlesi: seçilen ilde güç (provokasyon riskiyle).
## state: mitingin devletten ödenen payı (0..1; sadece hükümet partisi
## seçebilir ve PARTİZAN HARCAMA sayılır); -1 = uygun bir paylaşım var mı.
func can_miting(peer_id: int, province_id: String = "", state: float = -1.0) -> bool:
	if not can_choose_main_action(peer_id) or not _funding_ok(funding_range(peer_id, "miting"), state):
		return false
	# BAĞIMSIZ siyasetçinin teşkilatı yoktur: her ilde miting yapabilir.
	if PartyManager.is_independent(peer_id):
		return province_id == "" or has_province(province_id)
	if province_id == "":
		return has_organization_anywhere(peer_id)
	# Miting artik teskilat ister: once ilde orgutlenmis olmak gerekir.
	return has_province(province_id) and organization_level(province_id, peer_id) > 0

## Partinin herhangi bir ilde teskilati var mi? (miting/karalama on sarti)
func has_organization_anywhere(peer_id: int) -> bool:
	peer_id = party_of(peer_id)
	for province_id in organizations.keys():
		if organization_level(String(province_id), peer_id) > 0:
			return true
	return false

func can_build_organization(peer_id: int, province_id: String) -> bool:
	if PartyManager.is_independent(peer_id) or is_party_member(peer_id):
		return false  # bağımsızın teşkilatı olmaz; üye teşkilat kuramaz
	return can_choose_main_action(peer_id) and funds_of(peer_id) >= org_cost_for(peer_id, province_id) \
		and has_province(province_id) and organization_level(province_id, peer_id) < GameRules.ORG_MAX_LEVEL

## Bir partiden vekil çalınabilir mi? Kendinden çalınamaz, meclis dışı partiden
## çalınamaz ve hedefin en az 2 vekili olmalı (1'in altına DÜŞÜRÜLEMEZ).
func is_valid_steal_target(peer_id: int, target_peer_id: int) -> bool:
	if target_peer_id == -1 or party_of(target_peer_id) == party_of(peer_id):
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
	if int(election_seats.get(party_of(peer_id), 0)) > 0:
		return 1.0
	return PublicOpinion.STEAL_OUTSIDER_EFFICIENCY

## Bu parti son seçimde meclis dışında mı kaldı?
func is_outside_parliament(peer_id: int) -> bool:
	return int(election_seats.get(party_of(peer_id), 0)) <= 0

## Bu kart şu an bu hedeflerle oynanabilir mi? (Host doğrulaması ve UI.)
func can_play_card(peer_id: int, card_type: String, target_peer_id: int = -1, target_province: String = "") -> bool:
	if is_party_member(peer_id) or funds_of(peer_id) < CardPresets.card_cost(card_type):
		return false
	if card_type == CardPresets.EARLY_ELECTION_CARD_TYPE:
		return false  # artık hamle (bkz. can_early_election)
	if CardPresets.needs_target(card_type):
		return is_valid_steal_target(peer_id, target_peer_id)
	# Hedef PARTİ (ya da kart çalmada o partinin oyuncusu): kendi partin olamaz.
	var other_party := target_peer_id != -1 and party_ids().has(party_of(target_peer_id)) \
		and not PartyManager.same_party(target_peer_id, peer_id)
	if card_type == CardPresets.REPUTATION_CARD_TYPE:
		return other_party
	if card_type == CardPresets.CARD_THEFT_CARD_TYPE:
		return other_party and turn_order.has(target_peer_id)
	if card_type == CardPresets.REBELLION_CARD_TYPE:
		return other_party and has_seats(target_peer_id)
	if card_type == CardPresets.PROPAGANDA_CARD_TYPE:
		# Karalama teşkilat ister (ilde örgütlü olmayan parti kampanya yapamaz);
		# BAĞIMSIZ siyasetçinin teşkilatı yoktur, her ilde yapabilir.
		return has_province(target_province) and other_party \
			and (organization_level(target_province, peer_id) > 0 or PartyManager.is_independent(peer_id))
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
	return float(national_support.get(party_of(peer_id), 0.0))

func local_of(province_id: String, peer_id: int) -> float:
	return float(local_support.get(province_id, {}).get(party_of(peer_id), 0.0))

## İllerin seçmen profilleri (oyun başında üretilir). Oyun kurulmamışsa
## (testler, editör) örnek profillere düşer.
func province_voters() -> Dictionary:
	if province_profiles.is_empty():
		return ElectionModel.load_province_voters()
	return province_profiles

func province_profile(province_id: String) -> Dictionary:
	return province_voters().get(province_id, {})

## Partinin seçimde kullanılan grup yakınlıkları: kalıcı ulusal yakınlık +
## geçici toplantı bonusu. at_round: bonusun hesaplandığı tur (-1: şimdiki).
## EKONOMİ: hükümet partilerine vergi/ekonomi memnuniyeti de eklenir (tek
## kanal; kalıcı yakınlığa yazılmaz, ulusal puana ayrıca eklenmez).
func effective_groups(peer_id: int, at_round: int = -1) -> Dictionary:
	var pid := party_of(peer_id)
	var bonus := meeting_bonuses(pid, at_round)
	var mood := economy_mood(pid)
	for group in mood.keys():
		bonus[group] = float(bonus.get(group, 0.0)) + float(mood[group])
	return VoterGroups.with_bonus(PartyManager.groups_of(pid), bonus)

## Partinin şu an geçerli toplantı bonusları: grup -> bonus.
func meeting_bonuses(peer_id: int, at_round: int = -1) -> Dictionary:
	if at_round < 0:
		at_round = round_number
	var result := {}
	var entry: Dictionary = group_meetings.get(party_of(peer_id), {})
	for group in entry.keys():
		var bonus := PublicOpinion.meeting_bonus(at_round - int(entry[group]))
		if bonus > 0.0:
			result[group] = bonus
	return result

## Partinin bu ildeki GRUP UYUMU (0..100, 50 nötr).
func appeal_of(province_id: String, peer_id: int) -> float:
	return VoterGroups.appeal(effective_groups(peer_id), province_profile(province_id))

# --- Ekonomi sorguları ---------------------------------------------------------

func tax_level() -> int:
	return int(economy.get("tax", Economy.START_TAX))

func state_treasury() -> float:
	return float(economy.get("treasury", 0.0))

## HAZİNE KOTASI: hükümet partileri devlet hazinesini BAKANLIK PUANLARIYLA
## ORANTILI paylaşır. Her parti bir dönemde, dönem başındaki hazinenin
## (puanı / hükümetteki toplam puan) kadarını harcayabilir; aşanını kendi
## kasasından öder. Sırada önce oynayan ortak hazineyi tek başına bitiremez.
## Harcanmayan kota dönem sonunda yanar (hazine olduğu gibi devreder).
func state_quota(peer_id: int) -> float:
	if not is_government_party(peer_id) or is_party_member(peer_id) or PartyManager.is_independent(peer_id):
		return 0.0
	var pid := party_of(peer_id)
	var left := quota_base() * quota_share(pid) - float(_quota_spent().get(pid, 0.0))
	return clampf(left, 0.0, state_treasury())

## Partinin hazinedeki payı: bakanlık puanı / hükümet partilerinin toplam puanı.
func quota_share(pid: int) -> float:
	var ids := GovernmentManager.government_party_ids()
	if not ids.has(pid):
		return 0.0
	var total := 0
	for gid in ids:
		total += GovernmentManager.round_points_of(int(gid))
	if total <= 0:
		return 1.0 / float(ids.size())
	return float(GovernmentManager.round_points_of(pid)) / float(total)

## Kotanın hesaplandığı hazine: bu dönem ilk harcamadan önceki tutar.
func quota_base() -> float:
	if int(economy.get("quota_round", -1)) == round_number:
		return float(economy.get("quota_base", 0.0))
	return state_treasury()

func _quota_spent() -> Dictionary:
	if int(economy.get("quota_round", -1)) == round_number:
		return economy.get("quota_spent", {})
	return {}

## Devlet hazinesinden harcamayı partinin kotasına yazar (hazineden düşmeden ÖNCE).
func _spend_quota(peer_id: int, amount: float) -> void:
	if amount <= 0.0:
		return
	if int(economy.get("quota_round", -1)) != round_number:
		economy["quota_round"] = round_number
		economy["quota_base"] = state_treasury()
		economy["quota_spent"] = {}
	var spent: Dictionary = economy["quota_spent"]
	var pid := party_of(peer_id)
	spent[pid] = float(spent.get(pid, 0.0)) + amount

func economy_index() -> float:
	return float(economy.get("index", Economy.START_INDEX))

func inflation() -> float:
	return Economy.inflation(economy)

func unemployment() -> float:
	return Economy.unemployment(economy)

## Bu tur sonunda hazineye girecek vergi geliri (şu anki kademe ve ekonomiyle).
func expected_revenue(level: int = -1) -> float:
	return Economy.revenue(tax_level() if level < 0 else level, economy_index())

## Partinin ekonomik memnuniyet payı: başbakanın partisi 1, ortak
## PARTNER_SHARE, hükümette değilse 0.
func economy_share(peer_id: int) -> float:
	var pid := party_of(peer_id)
	if not GovernmentManager.has_government() or not GovernmentManager.government_party_ids().has(pid):
		return 0.0
	return 1.0 if pid == GovernmentManager.main_gov_peer_id else Economy.PARTNER_SHARE

## Hükümet partisinin ekonomiden gelen GEÇİCİ grup yakınlığı değişimi.
func economy_mood(peer_id: int) -> Dictionary:
	return Economy.group_mood(economy, economy_share(peer_id))

## Partinin bekleyen (henüz gerçekleşmemiş) yatırım dilimleri: [{province,
## amount, rounds_left}] — sadece kendi payı.
func pending_investments(peer_id: int) -> Array:
	var pid := party_of(peer_id)
	var result: Array = []
	for entry in economy.get("investments", []):
		var amounts: Dictionary = entry.get("amounts", {})
		if amounts.has(pid):
			result.append({"province": String(entry["province"]), "amount": float(amounts[pid]),
				"rounds_left": int(entry["rounds_left"]), "investor": int(entry.get("party", -1))})
	return result

## İki partinin seçmen grubu yakınlığı: 1 aynı profil, 0 çok farklı.
func group_closeness(a: int, b: int) -> float:
	return VoterGroups.party_closeness(PartyManager.groups_of(party_of(a)), PartyManager.groups_of(party_of(b)))

func organization_level(province_id: String, peer_id: int) -> int:
	return int(organizations.get(province_id, {}).get(party_of(peer_id), 0))

## AKTİVİTE yakınlığı: sönen il puanı + teşkilatın kalıcı katkısı.
func activity_of(province_id: String, peer_id: int) -> float:
	return local_of(province_id, peer_id) + org_bonus(province_id, peer_id) 		+ PoliticianPresets.hometown_activity(province_id, peer_id)

## Teşkilatın oy bonusu (popülizm sürerken büyür).
func org_bonus(province_id: String, peer_id: int) -> float:
	var bonus := PublicOpinion.org_activity(organization_level(province_id, peer_id))
	if PoliticianPresets.party_has_background(peer_id, "belediye_baskani"):
		bonus *= PoliticianPresets.MAYOR_ORG_MULT
	if populism_rounds_left(peer_id) > 0:
		bonus *= PublicOpinion.POPULISM_GOOD_MULT
	return bonus

## Bir ilde partilerin aktivitesi: peer_id -> puan.
func activity_entry(province_id: String) -> Dictionary:
	var entry: Dictionary = local_support.get(province_id, {}).duplicate()
	var orgs: Dictionary = organizations.get(province_id, {})
	for peer_id in orgs.keys():
		entry[peer_id] = float(entry.get(peer_id, 0.0)) + org_bonus(province_id, int(peer_id))
	# Hemşehri desteği (üyelerin memleketi).
	for peer_id in party_ids():
		var home_bonus := PoliticianPresets.hometown_activity(province_id, int(peer_id))
		if home_bonus > 0.0:
			entry[peer_id] = float(entry.get(peer_id, 0.0)) + home_bonus
	return entry

## Tüm iller: province_id -> {peer_id -> aktivite}.
func activity_map() -> Dictionary:
	var result := {}
	for province_id in _province_ids:
		var entry := activity_entry(province_id)
		if not entry.is_empty():
			result[province_id] = entry
	return result

## Bir partinin bir ildeki gücü (grup uyumu + aktivite).
func party_strength(province_id: String, peer_id: int) -> float:
	return PublicOpinion.party_strength(appeal_of(province_id, peer_id), activity_of(province_id, peer_id))

## Teşkilat anketi (sadece o partinin arayüzü gösterir):
##   1. seviye: YAKLAŞIK oy (±%35), 2. seviye: %90 doğrulukla oy (±%10).

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
	return _noisy_poll(projection, error, "%s:%d:%d" % [province_id, party_of(peer_id), round_number], province_seat_count(province_id),
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
	var groups := _group_profiles()
	var national := {}
	var total := 0.0
	for province_id in _province_ids:
		var seats := float(province_seat_count(province_id))
		var shares := ElectionModel.expected_shares(groups, province_profile(province_id),
			mods["national"], local_mods.get(province_id, {}), _expected_national(mods))
		for peer_id in shares.keys():
			national[peer_id] = float(national.get(peer_id, 0.0)) + float(shares[peer_id]) * seats
		total += seats
	var eligible: Array = []
	for peer_id in party_ids():
		if total > 0.0 and float(national.get(peer_id, 0.0)) / total >= MultiplayerManager.election_threshold:
			eligible.append(peer_id)
	if eligible.is_empty():
		eligible = party_ids()
	return eligible

## Gürültüsüz beklenen ulusal paylar (il payları bununla karışır). Aynı
## modifier sözlüğü için önbellekli: bir harita çizimi 67 kez sormasın.
var _national_cache_key: Dictionary = {}
var _national_cache: Dictionary = {}
func _expected_national(mods: Dictionary) -> Dictionary:
	if is_same(mods, _national_cache_key):
		return _national_cache
	var profiles := {}
	var seats := {}
	for province_id in _province_ids:
		profiles[province_id] = province_profile(province_id)
		seats[province_id] = province_seat_count(province_id)
	_national_cache = ElectionModel.expected_national(_group_profiles(), profiles, seats,
		mods["national"], mods["local"])
	_national_cache_key = mods
	return _national_cache

## Şimdi seçim olsa bu ilde: peer_id -> {"percent", "seats"} (gürültüsüz beklenen
## oylar, ildeki vekiller D'Hondt ile; baraj yok sayılır). Gözcü raporu için.
func province_projection(province_id: String) -> Dictionary:
	var mods := election_modifiers()
	var local_mods: Dictionary = mods["local"]
	var shares := ElectionModel.expected_shares(_group_profiles(), province_profile(province_id),
		mods["national"], local_mods.get(province_id, {}), _expected_national(mods))
	var alloc := ElectionModel.allocate(shares, projected_eligible(mods), province_seat_count(province_id))
	var result := {}
	for peer_id in party_ids():
		result[peer_id] = {"percent": float(shares.get(peer_id, 0.0)), "seats": int(alloc.get(peer_id, 0))}
	return result

## Güç haritası: bu partinin ANKETİ olan illerde (teşkilat 2+) anlık seçim
## tahmini: province_id -> {peer_id -> {"percent", "seats", "quotient"},
## "seat_count"}. quotient: ildeki son kazanan D'Hondt bölümü (bir vekile ne
## kadar yakın olunduğunu ölçmek için). peer_id = -1: tüm iller, gürültüsüz.
func projection_all(viewer: int = -1) -> Dictionary:
	var mods := election_modifiers()
	var local_mods: Dictionary = mods["local"]
	var groups := _group_profiles()
	var eligible := projected_eligible(mods)
	var result := {}
	for province_id in _province_ids:
		var error := poll_error(viewer, province_id) if viewer != -1 else 0.0
		if error < 0.0:
			continue
		var seat_count := province_seat_count(province_id)
		var shares := ElectionModel.expected_shares(groups, province_profile(province_id),
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
		var parties_now := party_ids()
		for peer_id in parties_now:
			var won := int(alloc.get(peer_id, 0))
			if won > 0:
				last_quotient = minf(last_quotient, float(shares.get(peer_id, 0.0)) / float(won))
		var entry := {}
		for peer_id in parties_now:
			entry[peer_id] = {"percent": float(shares.get(peer_id, 0.0)), "seats": int(alloc.get(peer_id, 0)),
				"quotient": last_quotient}
		entry["seat_count"] = seat_count
		result[province_id] = entry
	return result

## Ülke genelinde yarışan partilerin seçimdeki grup yakınlıkları (toplantı
## bonusu dahil). BAĞIMSIZLAR dahil değil: sadece memleketlerinde aday olurlar
## (bkz. _add_independent_seats). at_round: bonusların turu (-1: şimdiki).
func _group_profiles(at_round: int = -1) -> Dictionary:
	var result := {}
	for peer_id in party_ids():
		if PartyManager.is_independent(peer_id):
			continue
		result[peer_id] = effective_groups(peer_id, at_round)
	return result

## Bu parti bu ilde miting yaparsa provokasyon olasılığı (0..0.5): ilin seçmen
## profili partinin hitap ettiği gruplardan ne kadar uzaksa o kadar yüksek.
func miting_risk(peer_id: int, province_id: String) -> float:
	var risk := PublicOpinion.provocation_risk(appeal_of(province_id, peer_id), organization_level(province_id, peer_id))
	# Bağımsız teşkilatsız miting yapar: provokasyon riski daha yüksek.
	if PartyManager.is_independent(peer_id):
		risk = minf(PublicOpinion.PROVOCATION_MAX_RISK, risk * INDEPENDENT_MITING_RISK_MULT)
	return risk

# --- Olay logu -----------------------------------------------------------------

## Loga kayıt ekler. peer_id: hamleyi yapan parti (-1: sistem), province:
## olayın geçtiği il ("" = yok), kind: olay türü (odak simgesi seçilir).
## Oyuncuların gördüğü logda gösterilmeyen olay türleri (konsolda görünür).
## SEÇİMİN SİYASİ ANLAMI (bir parti için, tek cümle): oy oranının bir önceki
## seçime göre değişimi ve birinci çıktığı il sayısı GERÇEK sonuçlardan
## okunur, sözcüğe çevrilir. İlk seçimde karşılaştırma yoktur.
func election_trend(pid: int) -> String:
	if not last_vote_shares.has(pid) or PartyManager.is_independent(pid):
		return ""
	var name := _party_name(pid)
	var now := float(last_vote_shares.get(pid, 0.0))
	var wins := 0
	for province_id in last_province_results.keys():
		var results: Dictionary = last_province_results[province_id]
		var best := -1
		var best_share := -1.0
		for other in results.keys():
			var share := float((results[other] as Dictionary).get("percent", 0.0))
			if share > best_share:
				best_share = share
				best = int(other)
		if best == pid:
			wins += 1
	var where := ""
	if wins >= 10:
		where = L.t(" ve birçok ilde birinci")
	elif wins > 0:
		where = L.t(" ve %d ilde birinci") % wins
	if not previous_vote_shares.has(pid):
		return L.t("%s ilk seçiminde %%%s oy aldı%s.") % [name, String.num(now, 1).replace(".", ","), where]
	var diff := now - float(previous_vote_shares[pid])
	if absf(diff) < 1.0:
		return L.t("%s oy oranını korudu%s.") % [name, where]
	if diff > 0.0:
		return "%s %s%s." % [name, L.t("güçlü bir yükseliş yakaladı") if diff >= 5.0 else L.t("halk desteğini artırdı"), where]
	return "%s %s%s." % [name, L.t("ağır bir kan kaybı yaşadı") if diff <= -5.0 else "geriledi", where]

## Eski sürüm kayıtlarındaki kart adları ve yeni karşılıkları.
const OLD_CARD_TYPES := {"mana_bonusu": "bagis_kampanyasi", "mana_bonusu_guclu": "bagis_kampanyasi_guclu"}
const PLAYER_HIDDEN_LOG_KINDS := ["bagis_kampanyasi", "bagis_kampanyasi_guclu"]

func log_event(text: String, peer_id: int = -1, province: String = "", kind: String = "system") -> void:
	if text.strip_edges() == "":
		return
	# ANA (geliştirici) LOG: her şey konsola yazılır.
	print("[LOG r%d] %s" % [round_number, text])
	# Oyuncu logunda gereksiz olanlar (bağış kampanyası) gösterilmez.
	if kind in PLAYER_HIDDEN_LOG_KINDS:
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
## durumunu sıfırlar, illerin seçmen profillerini üretir, oynama sırasını rastgele
## belirler, herkese yayınlar.
func init_game() -> void:
	if not _is_authority():
		return
	inventories.clear()
	event_log.clear()
	BotBrain.reset_skills()
	funds = {}
	for peer_id in MultiplayerManager.players.keys():
		inventories[peer_id] = []
		funds[peer_id] = GameRules.FUNDS_START
	turn_order = MultiplayerManager.players.keys().duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	_grant_turn_income()
	law_rounds = {}
	speech_rounds = {}
	congress_rounds = {}
	previous_vote_shares = {}
	party_congress = {}
	congress_active = false
	_congress_time_left = 0.0
	populism = {}
	turmoil = {}
	splinters = {}
	agenda = {}
	crisis = {}
	_agenda_pairs = []
	group_meetings = {}
	miting_fatigue = {}
	election_groups = {}
	former_parties = {}
	economy = Economy.start_state()
	national_list = {}
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
	# Oyun başlarken (siyasetçi profilinden önce) kesinleşen harita.
	if map_seed == 0:
		map_seed = MultiplayerManager.game_map_seed
	if map_seed == 0 and MultiplayerManager.map_seed != "":
		map_seed = int(MultiplayerManager.map_seed)
	if map_seed == 0:
		map_seed = _rng.randi_range(1, 999999999)
	GameMap.generate_new(map_seed)
	_load_province_seat_counts()
	province_profiles = VoterGroups.generate_profiles(_rng, _province_ids, _province_seat_counts)
	organizations = {}
	_apply_politician_starts()
	credibility = {}
	for peer_id in MultiplayerManager.players.keys():
		credibility[peer_id] = CREDIBILITY_START
	_pick_music_track()
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

## SİYASETÇİ PROFİLİ (bkz. PoliticianPresets): memlekette bedava teşkilat,
## geçmişin seçmen grubunda ek yakınlık, iş insanı ek para alır.
## Memleketi bu haritada olmayan (ör. test tohumu farklı) siyasetçiye rastgele
## bir il verilir.
func _apply_politician_starts() -> void:
	for peer_id in MultiplayerManager.players.keys():
		var data: Dictionary = PoliticianPresets.of(peer_id)
		if data.is_empty():
			continue
		var home := String(data.get("hometown", ""))
		if not _province_ids.has(home) and not _province_ids.is_empty():
			home = String(_province_ids[_rng.randi() % _province_ids.size()])
			var fixed := data.duplicate()
			fixed["hometown"] = home
			PartyManager.set_politician_host(peer_id, fixed)
		# Geçmiş, partiyi kendi seçmen grubuna biraz yaklaştırır.
		var background_group := PoliticianPresets.group_of(String(data.get("background", "")))
		if background_group != "" and PartyManager.parties.has(peer_id):
			PartyManager.apply_group_deltas([{"peer": peer_id, "group": background_group,
				"amount": PoliticianPresets.BACKGROUND_GROUP_BONUS}])
		if home == "":
			continue
		organizations[home] = organizations.get(home, {})
		organizations[home][peer_id] = PoliticianPresets.HOMETOWN_ORG_LEVEL
		if PoliticianPresets.has_background(peer_id, "is_insani"):
			funds[peer_id] = funds_of(peer_id) + PoliticianPresets.BUSINESS_START_FUNDS

func _pick_music_track() -> void:
	var tracks: Array = AudioManager.GAME_TRACKS
	music_track = String(tracks[_rng.randi() % tracks.size()])

func credibility_of(peer_id: int) -> float:
	return float(credibility.get(peer_id, CREDIBILITY_START))

## Bir önceki seçime göre oy kaybeden partinin genel başkanı güven kaybeder
## (ilk seçimde kıyas yok). Oy yüzdeleri puan cinsinden (ör. 23.4).
static func credibility_drop(old_share: float, new_share: float) -> float:
	var loss := old_share - new_share
	if loss <= 0.0:
		return 0.0
	return CREDIBILITY_DROP_BASE + CREDIBILITY_DROP_PER_POINT * loss

func _update_credibility(old_shares: Dictionary, new_shares: Dictionary) -> void:
	for peer_id in new_shares.keys():
		if not old_shares.has(peer_id):
			continue
		var drop := credibility_drop(float(old_shares[peer_id]), float(new_shares[peer_id]))
		if drop > 0.0:
			credibility[peer_id] = clampf(credibility_of(int(peer_id)) - drop, 0.0, CREDIBILITY_MAX)

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
	province_profiles = {}
	group_meetings = {}
	miting_fatigue = {}
	election_groups = {}
	former_parties = {}
	economy = Economy.start_state()
	organizations = {}
	turmoil = {}
	splinters = {}
	credibility = {}
	speech_done = false
	funds = {}
	game_finished = false
	final_ranking = []
	game_end_reason = ""
	_round_end_pending = false

# --- Oyuncu eylemleri -------------------------------------------------------

## Bu oyuncu için desteden çekilebilecek kartlar ve ağırlıkları.
##   - karalama her zaman,
##   - popülizm ve bağış kampanyası her zaman,
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
	weights[CardPresets.FUNDS_BONUS_CARD_TYPE] = WEIGHT_FUNDS_BONUS
	weights[CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE] = WEIGHT_FUNDS_BONUS_STRONG
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
		card_played.emit(-1 if is_anonymous_card(card_type) and id != multiplayer.get_unique_id() else id, card_type)
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

## ÇÖP: istemediğin kartı at, bedelinin YARISINI para olarak geri al.
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
	var hand: Array = inventories.get(peer_id, [])
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_type: String = hand[hand_index]
	hand.remove_at(hand_index)
	var refund := discard_refund(card_type)
	funds[peer_id] = funds_of(peer_id) + refund
	_event_message = L.t("%s bir kartı bozdurdu (+%s).") % [_party_name(peer_id), GameRules.cost_text(refund)]
	inventories_updated.emit()
	if _is_local_only() and turn_order.is_empty():
		return
	_push_state({"type": "discard", "peer_id": peer_id, "card": card_type})

## Çöpe atılan kartın geri verdiği para: bedelinin yarısı.
static func discard_refund(card_type: String) -> float:
	return CardPresets.card_cost(card_type) * 0.5

@rpc("any_peer", "reliable")
func _request_discard(hand_index: int) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_discard(multiplayer.get_remote_sender_id(), hand_index)

## Yasa tasarla: law_type = CardPresets.law_type(seçmen grubu).
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

## Yatırım hamlesi: seçilen ile hükümet yatırımı (INVEST_FUNDS_COST).
func invest(province_id: String, state: float = 1.0) -> void:
	if not can_invest(multiplayer.get_unique_id(), province_id, state):
		return
	if _is_authority():
		_apply_invest_move(multiplayer.get_unique_id(), province_id, state)
	else:
		_request_invest.rpc_id(1, province_id, state)

## Gensoru hamlesi (CENSURE_FUNDS_COST): meclis oylaması açılır.
func censure() -> void:
	if not can_censure(multiplayer.get_unique_id()):
		return
	if _is_authority():
		_apply_censure_move(multiplayer.get_unique_id())
	else:
		_request_censure.rpc_id(1)

## Miting hamlesi: seçilen ilde miting (MITING_FUNDS_COST).
func miting(province_id: String, state: float = 0.0) -> void:
	if not can_miting(multiplayer.get_unique_id(), province_id, state):
		return
	if _is_authority():
		_apply_miting_move(multiplayer.get_unique_id(), province_id, state)
	else:
		_request_miting.rpc_id(1, province_id, state)

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
	card_played.emit(-1 if is_anonymous_card(card_type) and peer_id != multiplayer.get_unique_id() else peer_id, card_type)
	hand.remove_at(hand_index)
	funds[peer_id] = funds_of(peer_id) - CardPresets.card_cost(card_type)
	_event_message = ""
	var seats_changed_now := _apply_card_effect(peer_id, card_type, target_peer_id, target_province)
	var event := {"type": "played", "peer_id": peer_id, "card": card_type,
		"target": target_peer_id, "province": target_province, "seats_changed": seats_changed_now}
	if _event_message != "":
		event["message"] = _event_message
	if is_anonymous_card(card_type):
		# Kaset ve iç karışıklık anonim: logda hedefin simgesi görünür, atanın değil.
		event["peer_id"] = target_peer_id
		event["actor_hidden"] = peer_id
	# Hiçbir kart sırayı devretmez; tur sadece "Turu Bitir" ya da süreyle biter.
	_push_state(event, seats_changed_now)
	
## Turu bitir (voluntary=false: süre doldu). Bağış kampanyası yok.
func _apply_pass(peer_id: int, voluntary: bool = true) -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id():
		return
	# Grup toplantısı isteğe bağlıdır: yapmamanın cezası yok (rakibe kısa
	# vadeli fırsat bırakmış olursun).
	var wrapped := _advance_turn()
	_push_state({"type": "passed", "peer_id": peer_id})
	_finish_round_if_needed(wrapped)

## Bu oyuncunun partisinden bu dönem sırası henüz gelmemiş bir üye var mı?
func _party_member_later_this_round(peer_id: int) -> bool:
	for i in range(current_turn_index + 1, turn_order.size()):
		var other := int(turn_order[i])
		if other != peer_id and PartyManager.same_party(other, peer_id):
			return true
	return false

func _apply_law(peer_id: int, law_type: String) -> void:
	if not can_propose_law(peer_id, law_type):
		return
	_event_message = ""
	if not GovernmentManager.submit_law(peer_id, law_type):
		return
	funds[peer_id] = funds_of(peer_id) - law_funds_cost(peer_id, law_type)
	law_rounds[party_of(peer_id)] = round_number
	var event := {"type": "law", "peer_id": peer_id, "law": law_type}
	if _event_message != "":
		event["message"] = _event_message
	_push_state(event)

func _apply_organization(peer_id: int, province_id: String) -> void:
	if not can_build_organization(peer_id, province_id):
		return
	funds[peer_id] = funds_of(peer_id) - org_cost_for(peer_id, province_id)
	var entry: Dictionary = organizations.get(province_id, {})
	var level := int(entry.get(party_of(peer_id), 0)) + 1
	entry[party_of(peer_id)] = level
	organizations[province_id] = entry
	var verb := L.t("kurdu") if level == 1 else L.t("geliştirdi")
	_log_province(province_id, L.t("%s teşkilat %s (seviye %d)") % [_party_name(peer_id), verb, level])
	# Teşkilat parti içini toparlar (oy bonusu activity_of'ta, kalıcı).
	_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_ORG)
	_push_state({"type": "organization", "peer_id": peer_id, "province": province_id,
		"message": L.t("%s, %s'da teşkilat %s (seviye %d).") % [_actor_name(peer_id), _province_name(province_id), verb, level]})

## state: devletin payı (varsayılan tamamı devletten, eski kural). Bedel
## TEK SEFER düşer: devlet payı hazineden, parti payı (+ sabit hamle bedeli)
## parti kasasından; gerçek paylaşım kayda geçer.
func _apply_invest_move(peer_id: int, province_id: String, state: float = 1.0) -> void:
	if not can_invest(peer_id, province_id, state):
		return
	var split := Economy.split_cost(Economy.INVEST_COST, state)
	funds[peer_id] = funds_of(peer_id) - float(split["party"])
	_spend_quota(peer_id, float(split["state"]))
	var before := state_treasury()
	economy["treasury"] = before - float(split["state"])
	_record_funding(peer_id, "invest", province_id, split, Economy.INVEST_COST)
	_event_message = ""
	_apply_investment(peer_id, province_id)
	_push_state({"type": "invest", "peer_id": peer_id, "province": province_id, "message": _event_message,
		"econ": {"kind": "invest", "peer_id": peer_id, "province": province_id, "cost": float(split["state"]),
			"party_cost": float(split["party"]), "before": before, "after": state_treasury()}})

func _apply_censure_move(peer_id: int) -> void:
	if not can_censure(peer_id):
		return
	funds[peer_id] = funds_of(peer_id) - GameRules.CENSURE_FUNDS_COST
	_push_state({"type": "censure", "peer_id": peer_id,
		"message": L.t("%s hükümete gensoru verdi: meclis oylaması başladı.") % _party_name(peer_id)})
	GovernmentManager.submit_censure(peer_id)

func _apply_miting_move(peer_id: int, province_id: String, state: float = 0.0) -> void:
	if not can_miting(peer_id, province_id, state):
		return
	var total := float(GameRules.MITING_FUNDS_COST)
	var split := Economy.split_cost(total, state)
	funds[peer_id] = funds_of(peer_id) - float(split["party"])
	_spend_quota(peer_id, float(split["state"]))
	var before := state_treasury()
	economy["treasury"] = before - float(split["state"])
	_record_funding(peer_id, "miting", province_id, split, total)
	if float(split["state"]) > 0.0:
		economy_event.emit({"kind": "invest", "cost": float(split["state"]), "before": before, "after": state_treasury()})
	_event_message = ""
	_apply_miting(peer_id, province_id)
	# Bağımsızın ve üyenin mitingi kendi güvenilirliğini de artırır.
	if PartyManager.is_independent(peer_id) or is_party_member(peer_id):
		credibility_add(peer_id, MITING_CREDIBILITY)
	_push_state({"type": "miting", "peer_id": peer_id, "province": province_id, "message": _event_message})

## ANONİM KARTLAR: kaset ve iç karışıklık. Oynayanın adı mesajda, log
## simgesinde ve kart animasyonunda gizlidir (hedef görünür).
static func is_anonymous_card(card_type: String) -> bool:
	return card_type in [CardPresets.REPUTATION_CARD_TYPE, CardPresets.REBELLION_CARD_TYPE]

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
			# ANONİM: iç karışıklığı kimin kışkırttığı hiçbir yerde gösterilmez.
			_event_message = L.t("%s'da iç karışıklık çıktı: parti sarsıldı, ulusal desteği düştü.") % _party_name(target_peer_id)
		CardPresets.CARD_THEFT_CARD_TYPE:
			_apply_card_theft(peer_id, target_peer_id)
		CardPresets.BONUS_CARD_TYPE:
			var drawn := 0
			for i in GameRules.BONUS_CARD_DRAW:
				if _deal_turn_card(peer_id, [CardPresets.BONUS_CARD_TYPE]) != "":
					drawn += 1
			_event_message = L.t("%s bonus kart kullandı (+%d kart).") % [_party_name(peer_id), drawn]
		CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE:
			var strong_gain := funds_bonus_amount(peer_id, true)
			funds[peer_id] = funds_of(peer_id) + strong_gain
			_event_message = L.t("%s büyük bir bağış kampanyası yaptı (+%s).") % [_party_name(peer_id), GameRules.cost_text(strong_gain)]
		CardPresets.EARLY_ELECTION_CARD_TYPE:
			GovernmentManager.submit_early_election(peer_id)
			_event_message = L.t("%s erken seçim önergesi verdi.") % _party_name(peer_id)
		CardPresets.POPULISM_CARD_TYPE:
			populism[party_of(peer_id)] = round_number + GameRules.POPULISM_ROUNDS
			_event_message = L.t("%s popülizme başladı: %d dönem boyunca hamleleri daha etkili.") % [_party_name(peer_id), GameRules.POPULISM_ROUNDS]
		CardPresets.FUNDS_BONUS_CARD_TYPE:
			var weak_gain := funds_bonus_amount(peer_id, false)
			funds[peer_id] = funds_of(peer_id) + weak_gain
			_event_message = L.t("%s bağış kampanyası yaptı (+%s).") % [_party_name(peer_id), GameRules.cost_text(weak_gain)]
		CardPresets.PROPAGANDA_CARD_TYPE:
			_apply_propaganda(peer_id, target_peer_id, target_province)
	return false

func _party_name(peer_id: int) -> String:
	return PartyManager.data_of(peer_id).get("name", "?")

## KART ÇALMA: hedefin elinden rastgele bir kart alınır (el doluysa kart yanar).
## Hangi kartın çalındığı herkese duyurulmaz.
func _apply_card_theft(peer_id: int, target_peer_id: int) -> void:
	var hand: Array = inventories.get(target_peer_id, [])
	if hand.is_empty():
		_event_message = L.t("%s, %s'ın elinden kart çalmaya kalktı ama elinde hiç kart yoktu.") % [
			_party_name(peer_id), _party_name(target_peer_id)]
		return
	var card: String = hand[_rng.randi_range(0, hand.size() - 1)]
	hand.erase(card)
	var mine: Array = inventories.get(peer_id, [])
	if mine.size() < MAX_HAND_SIZE:
		mine.append(card)
		inventories[peer_id] = mine
	_event_message = L.t("%s, %s'ın elinden bir kart çaldı.") % [_party_name(peer_id), _party_name(target_peer_id)]

## Olay metinlerinde hamleyi yapan: "Soyad (Parti)"; siyasetçi yoksa parti adı.
func _actor_name(peer_id: int) -> String:
	var surname := PoliticianPresets.surname_of(peer_id)
	if surname == "":
		return _party_name(peer_id)
	return "%s (%s)" % [surname, _party_name(peer_id)]

func _province_name(province_id: String) -> String:
	return GameMap.name_of(province_id)

## Miting: riski ilin mevcut siyasi dengesine göre hesaplanır, zar atılır.
func _apply_miting(peer_id: int, province_id: String) -> void:
	var risk := miting_risk(peer_id, province_id)
	if _rng.randf() < risk:
		_add_local(province_id, peer_id, PublicOpinion.PROVOCATION_LOCAL, true)
		_add_national(peer_id, PublicOpinion.PROVOCATION_NATIONAL, true)
		_log_province(province_id, L.t("%s mitinginde PROVOKASYON: ilde ve ülkede destek kaybı") % _party_name(peer_id))
		_event_message = L.t("%s'da %s mitinginde provokasyon çıktı: parti ilde ve ülke genelinde destek kaybetti.") % [
			_province_name(province_id), _party_name(peer_id)]
	else:
		var org_mult := PublicOpinion.org_action_mult(organization_level(province_id, peer_id))
		if PoliticianPresets.has_background(peer_id, "sendikaci"):
			org_mult *= PoliticianPresets.UNION_MITING_MULT
		# YEREL: ildeki aktivite (söner).
		_add_local(province_id, peer_id, PublicOpinion.MITING_LOCAL * org_mult, true)
		# ULUSAL YANSIMA: hitap ilin baskın gruplarına kayar (kalıcı, azalan getiri).
		var moved := _apply_miting_positioning(peer_id, province_id, org_mult)
		_log_province(province_id, L.t("%s miting yaptı") % _party_name(peer_id))
		_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_MITING)
		_event_message = L.t("%s, %s'da miting yaptı.") % [_actor_name(peer_id), _province_name(province_id)]
		if moved != "":
			_event_message += L.t(" Hitabı %s.") % moved

## MİTİNGİN SİYASİ HİTABI: ilin her çiftindeki baskın gruba ulusal yakınlık,
## karşıt gruba daha küçük kayıp. Yorgunluk (aynı gruba art arda miting) ve
## VoterGroups'un azalan getirisi uygulanır. Popülizm kazancı büyütür.
## Dönüş: kısa özet ("ilin kalabalık gruplarına kaydı (İşçiler ve Sendikalar, ...)") ya da "".
func _apply_miting_positioning(peer_id: int, province_id: String, mult: float) -> String:
	var pid := party_of(peer_id)
	var fatigue: Dictionary = miting_fatigue.get(pid, {})
	var changes: Array = []
	for effect in PublicOpinion.miting_positioning(province_profile(province_id), mult):
		var group := String(effect["group"])
		var damp := PublicOpinion.miting_fatigue_mult(float(fatigue.get(group, 0.0)))
		var gain := _own_effect(pid, float(effect["gain"]) * damp)
		changes.append({"peer": pid, "group": group, "amount": gain})
		changes.append({"peer": pid, "group": String(effect["loss_group"]),
			"amount": _own_effect(pid, -float(effect["loss"]) * damp)})
	var actual := _shift_groups(changes)
	var parts: PackedStringArray = []
	for change in actual:
		var group := String(change["group"])
		var delta := float(change["delta"])
		if delta > 0.0:
			fatigue[group] = float(fatigue.get(group, 0.0)) + delta
			parts.append(VoterGroups.title(group))
	if not fatigue.is_empty():
		miting_fatigue[pid] = fatigue
	if parts.is_empty():
		return ""
	return L.t("ilin kalabalık gruplarına kaydı (%s)") % ", ".join(parts)

## "1,8" gibi kısa sayı.
static func _num(value: float) -> String:
	return String.num(snappedf(value, 0.1), 1).replace(".", ",")

## Yatırım: getiren parti daha çok, hükümet ortakları daha az kazanır.
## YEREL MEMNUNİYET: sadece il aktivitesi; grup yakınlığına dokunmaz.
## Popülizm yatırımı büyütmez. Etkinin INVEST_IMMEDIATE'i hemen, kalanı
## sonraki INVEST_DELAY_ROUNDS tur sonunda dilim dilim gelir (bekleyen
## dilimler economy["investments"]'ta; seçimde sadece gelmiş olan sayılır).
## Ekonomik yansıması ayrı bir ulusal puan değil: ekonomi ivmesi (bkz. Economy).
func _apply_investment(peer_id: int, province_id: String) -> void:
	var investor := party_of(peer_id)
	var shares := {investor: PublicOpinion.INVEST_LOCAL}
	for partner in GovernmentManager.government_party_ids():
		if partner != investor:
			shares[partner] = PublicOpinion.INVEST_PARTNER_LOCAL
	var later := {}
	for pid in shares.keys():
		_add_local(province_id, int(pid), float(shares[pid]) * Economy.INVEST_IMMEDIATE)
		later[pid] = float(shares[pid]) * (1.0 - Economy.INVEST_IMMEDIATE) / float(Economy.INVEST_DELAY_ROUNDS)
	var pending: Array = economy.get("investments", [])
	pending.append({"province": province_id, "party": investor, "round": round_number,
		"rounds_left": Economy.INVEST_DELAY_ROUNDS, "amounts": later})
	economy["investments"] = pending
	economy["boost"] = minf(Economy.BOOST_MAX, float(economy.get("boost", 0.0)) + Economy.INVEST_ECONOMY)
	_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_INVEST)
	_log_province(province_id, L.t("Hükümet yatırımı — %s getirdi (%s; etkisi %d dönemde tamamlanır)") % [
		_party_name(peer_id), Economy.money_full(Economy.INVEST_COST), Economy.INVEST_DELAY_ROUNDS])
	_event_message = L.t("%s, %s'a hükümet yatırımı getirdi: devlet hazinesinden %s.") % [_party_name(peer_id),
		_province_name(province_id), Economy.money_full(Economy.INVEST_COST)]

## TUR SONU EKONOMİSİ (host, tur başına TEK SEFER, seçimden önce): vergi
## geliri hazineye, vergi baskısı ve ekonomi bir adım yerleşir, bekleyen
## yatırım dilimleri ile illere gelir. Dönüş: log satırı.
func _advance_economy() -> String:
	Economy.advance(economy)
	var still: Array = []
	for entry in economy.get("investments", []):
		var province_id := String(entry["province"])
		var amounts: Dictionary = entry.get("amounts", {})
		for pid in amounts.keys():
			if PartyManager.parties.has(int(pid)):
				_add_local(province_id, int(pid), float(amounts[pid]))
		entry["rounds_left"] = int(entry["rounds_left"]) - 1
		if int(entry["rounds_left"]) > 0:
			still.append(entry)
		else:
			_log_province(province_id, L.t("%s yatırımı tamamlandı") % _party_name(int(entry.get("party", -1))))
	economy["investments"] = still
	return L.t("Hazineye %s vergi geliri girdi (vergi %s). Hazine: %s.") % [Economy.money_full(float(economy["revenue"])),
		Economy.tax_title(tax_level()), Economy.money_full(state_treasury())]

## Karalama: hedefe eksi, karalayana artı; ikisi de o ildeki güçleriyle ölçeklenir.
func _apply_propaganda(peer_id: int, target_peer_id: int, province_id: String) -> void:
	var damage := PublicOpinion.propaganda_damage(party_strength(province_id, target_peer_id))
	if PoliticianPresets.party_has_background(target_peer_id, "ilahiyatci"):
		damage *= PoliticianPresets.CLERIC_DAMAGE_MULT
	if populism_rounds_left(peer_id) > 0:
		damage *= PublicOpinion.POPULISM_GOOD_MULT
	var org_mult := PublicOpinion.org_action_mult(organization_level(province_id, peer_id))
	damage *= org_mult
	var gain := PublicOpinion.propaganda_gain(party_strength(province_id, peer_id)) * org_mult
	# Taban: karalama il puanını PROPAGANDA_FLOOR'un altına itemez.
	var current := local_of(province_id, target_peer_id)
	damage = clampf(damage, 0.0, maxf(0.0, current - PublicOpinion.PROPAGANDA_FLOOR))
	_add_local(province_id, target_peer_id, -damage)
	_add_local(province_id, peer_id, gain, true)
	_log_province(province_id, L.t("%s, %s karşıtı kampanya yaptı (%s, %s)") % [
		_party_name(peer_id), _party_name(target_peer_id), EffectWords.change(-damage, "local", L.t("yerel güç")), L.t("karşılığında kazanç") if gain > 0.0 else L.t("kazanç yok")])
	_event_message = L.t("%s, %s'da %s karşıtı karalama kampanyası yaptı.") % [
		_actor_name(peer_id), _province_name(province_id), _party_name(target_peer_id)]

## GovernmentManager, bir yasa oylaması sonuçlanınca (host) çağırır. Etkiler
## ULUSAL GRUP YAKINLIĞINA yazılır (bkz. PublicOpinion yasa kuralları):
##   sunan  : hedef grup +GAIN (kabul / ret), karşıt grup −GAIN × backlash,
##   oy veren genel başkanlar: EVET hedefe, HAYIR karşıt gruba yaklaşır.
##   votes  : peer_id -> GovernmentManager.VOTE_*
##   gov_ids: yasa meclise geldiği andaki hükümet partileri
func apply_law_result(proposer: int, law_type: String, votes: Dictionary, passed: bool, gov_ids: Array) -> void:
	if not _is_authority():
		return
	if CardPresets.is_tax_law(law_type):
		_apply_tax_result(proposer, CardPresets.tax_law_level(law_type), passed)
		return
	var law := CardPresets.law_data(law_type)
	if law.is_empty():
		return
	var group: String = law["group"]
	var opposite: String = law["opposite"]
	var backlash := float(VoterGroups.data(group).get("law_backlash", 0.4))
	# Yasayı OYUNCU sunar, etkiler PARTİSİNE yazılır.
	var proposer_party := party_of(proposer)
	var proposer_in_gov := gov_ids.has(proposer_party)
	var party_votes := _party_vote_shares(votes)
	var law_mult := PoliticianPresets.ACADEMIC_LAW_MULT if PoliticianPresets.has_background(proposer, "akademisyen") else 1.0
	var gain := (PublicOpinion.LAW_GROUP_GAIN_PASSED if passed else PublicOpinion.LAW_GROUP_GAIN_REJECTED) * law_mult
	var changes: Array = [
		{"peer": proposer_party, "group": group, "amount": _own_effect(proposer_party, gain)},
		{"peer": proposer_party, "group": opposite, "amount": _own_effect(proposer_party, -gain * backlash)},
	]
	var crisis_parties: Array = []
	if crisis_group() == group:
		crisis_parties.append(proposer_party)
	# Oy veren partiler (genel başkanın oyu parti çizgisidir).
	for voter in votes.keys():
		var voter_party := party_of(int(voter))
		if voter_party == proposer_party or int(voter) != voter_party:
			continue
		match GovernmentManager.normalize_vote(votes[voter]):
			GovernmentManager.VOTE_YES:
				changes.append({"peer": voter_party, "group": group, "amount": _own_effect(voter_party, PublicOpinion.LAW_VOTE_YES_GAIN)})
				changes.append({"peer": voter_party, "group": opposite, "amount": _own_effect(voter_party, -PublicOpinion.LAW_VOTE_YES_GAIN * backlash)})
				if crisis_group() == group and not crisis_parties.has(voter_party):
					crisis_parties.append(voter_party)
				# İktidar partisi muhalefetin yasasına EVET: gündemi kaptırdı.
				if gov_ids.has(voter_party) and not proposer_in_gov:
					_add_national(voter_party, PublicOpinion.LAW_GOV_YES_ON_OPPOSITION, true)
			GovernmentManager.VOTE_NO:
				changes.append({"peer": voter_party, "group": opposite, "amount": _own_effect(voter_party, PublicOpinion.LAW_VOTE_NO_GAIN)})
				changes.append({"peer": voter_party, "group": group, "amount": _own_effect(voter_party, -PublicOpinion.LAW_VOTE_NO_GAIN * backlash)})
	_shift_groups(changes)
	# KOALİSYON UYUMU: başbakanın partisinin yasasına hükümet ortağının oyu
	# ulusal puana yansır (kısmi).
	var pm_party := GovernmentManager.main_gov_peer_id
	if proposer_party == pm_party and pm_party != -1:
		for pid in party_votes.keys():
			var partner := int(pid)
			if partner == proposer_party or not gov_ids.has(partner):
				continue
			for entry in party_votes[pid]:
				var weight := float(entry["weight"])
				match int(entry["choice"]):
					GovernmentManager.VOTE_YES:
						_add_national(partner, PublicOpinion.LAW_PARTNER_YES_NATIONAL * weight)
					GovernmentManager.VOTE_NO:
						_add_national(partner, PublicOpinion.LAW_PARTNER_NO_NATIONAL * weight)
						_add_national(pm_party, PublicOpinion.LAW_PM_PARTNER_NO_NATIONAL * weight)
	var notes := ""
	# KRİZE YANIT: krizin istediği gruba yasa sunan ya da EVET diyen kısmi ulusal destek kazanır.
	if not crisis_parties.is_empty():
		var names: PackedStringArray = []
		for pid in crisis_parties:
			_add_national(int(pid), PublicOpinion.CRISIS_RESPONSE_NATIONAL)
			names.append(_party_name(int(pid)))
		notes += L.t(" Krize yanıt verdi (ulusal destek): %s.") % ", ".join(names)
	if passed:
		notes += L.t(" %s +%d puan.") % [_actor_name(proposer), law_pass_score(proposer_in_gov)]
		_ease_turmoil(proposer_party, PublicOpinion.TURMOIL_EASE_LAW)
	_push_state({"type": "opinion", "peer_id": proposer, "message": L.t("%s %s — %s, %s seçmeninde güçlendi%s; %s seçmeninde biraz kaybetti.%s") % [
		law["title"], L.t("KABUL EDİLDİ") if passed else L.t("reddedildi"), _party_name(proposer), law["group_title"],
		"" if passed else L.t(" (vaat olarak, az)"), VoterGroups.title(opposite), notes]})

## VERGİ YASASI sonucu. Kabul: kademe değişir, gelir bir sonraki tur sonundan
## itibaren yeni kademeyle; seçmenin hissettiği baskı TAX_IMMEDIATE kadar
## hemen, kalanı turlar içinde yerleşir. Grup yakınlığına ayrıca YAZILMAZ
## (etki Economy.group_mood'dan gelir: çift sayım yok).
func _apply_tax_result(proposer: int, level: int, passed: bool) -> void:
	var old := tax_level()
	var title := CardPresets.card_title(CardPresets.tax_law_type(level))
	if not passed or level == old:
		_push_state({"type": "opinion", "peer_id": proposer, "message": L.t("%s reddedildi — vergiler %s kalıyor.") % [
			title, Economy.tax_title(old)]})
		return
	economy["tax_from"] = old
	economy["pressure_from"] = float(economy["pressure"])
	economy["tax"] = level
	economy["tax_round"] = round_number
	economy["pressure"] = Economy.pressure_after_change(float(economy["pressure"]), level)
	_ease_turmoil(party_of(proposer), PublicOpinion.TURMOIL_EASE_LAW)
	var rounds := Economy.rounds_to_settle(economy)
	_push_state({"type": "opinion", "peer_id": proposer, "econ": {"kind": "tax", "from": old, "to": level},
		"message": L.t("%s KABUL EDİLDİ — vergiler %s → %s. Dönem geliri %s → %s. Seçmen bunu kademeli hissedecek (yaklaşık %d dönem). %s +%d puan.") % [
		title, Economy.tax_title(old), Economy.tax_title(level), Economy.money_full(expected_revenue(old)),
		Economy.money_full(expected_revenue(level)), rounds, _actor_name(proposer), law_pass_score(true)]})

## Oylar (oyuncu -> oy) partiye göre: parti -> [{"choice", "weight"}]; weight,
## oyuncunun partinin vekillerinden yönettiği pay (tek kişilik partide 1).
func _party_vote_shares(votes: Dictionary) -> Dictionary:
	var result := {}
	for voter in votes.keys():
		var pid := party_of(int(voter))
		var seats := GovernmentManager.seats_of(pid)
		var weight := 1.0 if seats <= 0 or member_count(pid) < 2 else float(GovernmentManager.vote_weight(int(voter))) / seats
		var list: Array = result.get(pid, [])
		list.append({"choice": GovernmentManager.normalize_vote(votes[voter]), "weight": weight})
		result[pid] = list
	return result

## Kabul edilen yasanın getiren partiye yazdığı puan.
static func law_pass_score(proposer_in_gov: bool) -> int:
	return GameRules.LAW_PASS_SCORE_GOV if proposer_in_gov else GameRules.LAW_PASS_SCORE

# --- Gündem ------------------------------------------------------------------------

## Şu anki kriz türü ("kriz_<grup>") ya da "".
func crisis_type() -> String:
	if crisis.is_empty() or round_number >= int(crisis.get("until", 0)):
		return ""
	return String(crisis.get("type", ""))

## Krizin istediği seçmen grubu ya da "".
func crisis_group() -> String:
	var data := CardPresets.crisis_data(crisis_type())
	return String(data.get("group", ""))

## Şu an gündemdeki konu ("gundem_<grup>") ya da "".
func agenda_type() -> String:
	if agenda.is_empty() or round_number >= int(agenda.get("until", 0)):
		return ""
	return String(agenda.get("type", ""))

func agenda_rounds_left() -> int:
	return maxi(0, int(agenda.get("until", 0)) - round_number) if agenda_type() != "" else 0

## Gündemde yasa sunulabilen iki grup (gündem yoksa boş).
func agenda_groups() -> Array:
	return CardPresets.agenda_groups(agenda_type())

## Bu yasa gündemdeki çiftin bir grubu için mi?
func law_on_agenda(law_type: String) -> bool:
	var law := CardPresets.law_data(law_type)
	return not law.is_empty() and agenda_groups().has(String(law["group"]))

## Yeni turun gündemi takvimden: ilk seçimden sonraki turdan itibaren
## AGENDA_ROUNDS tur gündem (her tur farklı çift), AGENDA_GAP tur ara.
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
			_push_state({"type": "agenda", "message": L.t("Gündem arası: %d dönem yasa yok, sonra yeni gündemler.") % GameRules.AGENDA_GAP})
		return
	# Çiftler karıştırılmış bir sıradan tüketilir: arka arkaya gelen iki gündem
	# hep farklı çiftten olur.
	if _agenda_pairs.is_empty():
		_agenda_pairs = VoterGroups.PAIR_IDS.duplicate()
		for i in range(_agenda_pairs.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp = _agenda_pairs[i]
			_agenda_pairs[i] = _agenda_pairs[j]
			_agenda_pairs[j] = tmp
		if _agenda_pairs.size() > 1 and String(_agenda_pairs[0]) == _last_agenda_pair:
			_agenda_pairs.push_back(_agenda_pairs.pop_front())
	var pair: String = String(_agenda_pairs.pop_front())
	_last_agenda_pair = pair
	var groups: Array = VoterGroups.PAIRS[pair]
	var type := "gundem_%s" % groups[_rng.randi() % 2]
	agenda = {"type": type, "until": round_number + 1, "index": pos + 1}
	var data := CardPresets.agenda_data(type)
	crisis = {}
	var message := L.t("GÜNDEM (%d/%d): %s — bu dönem %s.") % [pos + 1, GameRules.AGENDA_ROUNDS,
		data["title"], CardPresets.agenda_effect_text(type)]
	if _crisis_rng.randf() < GameRules.CRISIS_CHANCE:
		var crisis_kind := "kriz_%s" % groups[_crisis_rng.randi() % 2]
		crisis = {"type": crisis_kind, "until": round_number + 1}
		var info := CardPresets.crisis_data(crisis_kind)
		message += L.t(" KRİZ: %s — %s için yasa sunan, EVET diyen ya da toplantı yapan partiler ulusal destek kazanır.") % [
			info["title"], info["group_title"]]
	_push_state({"type": "agenda", "message": message})

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
	peer_id = party_of(peer_id)
	national_support[peer_id] = PublicOpinion.clamp_points(national_of(peer_id) + amount)

func _add_local(province_id: String, peer_id: int, amount: float, own: bool = false) -> void:
	if own:
		amount = _own_effect(peer_id, amount)
	if amount == 0.0 or peer_id == -1:
		return
	peer_id = party_of(peer_id)
	var entry: Dictionary = local_support.get(province_id, {})
	entry[peer_id] = PublicOpinion.clamp_points(float(entry.get(peer_id, 0.0)) + amount)
	local_support[province_id] = entry

func _log_province(province_id: String, text: String) -> void:
	var events: Array = province_events.get(province_id, [])
	events.append({"round": round_number, "text": text})
	while events.size() > PROVINCE_EVENT_LIMIT:
		events.pop_front()
	province_events[province_id] = events

# --- Grup yakınlıkları ve toplantı -------------------------------------------------

## Partilerin grup yakınlıklarını değiştirir (bkz. PartyManager.apply_group_deltas).
## changes: [{"peer", "group", "amount"}]. Dönüş: gerçekleşen [{"peer", "group", "delta"}].
func _shift_groups(changes: Array) -> Array:
	return PartyManager.apply_group_deltas(changes)

## Sıra gelen oyuncunun GRUP TOPLANTISI: bir seçmen grubunun sorunlarını konuşur.
func make_speech(group: String) -> void:
	var me := multiplayer.get_unique_id()
	if not needs_speech(me) or is_turn_blocked():
		return
	if _is_authority():
		_apply_speech(me, group)
	else:
		_request_speech.rpc_id(1, group)

func _apply_speech(peer_id: int, group: String) -> void:
	if not needs_speech(peer_id) or is_turn_blocked() or not VoterGroups.is_group(group):
		return
	funds[peer_id] = funds_of(peer_id) - GameRules.SPEECH_FUNDS_COST
	speech_done = true
	var pid := party_of(peer_id)
	speech_rounds[pid] = round_number
	var entry: Dictionary = group_meetings.get(pid, {})
	entry[group] = round_number
	group_meetings[pid] = entry
	var text := L.t("%s, %s ile grup toplantısı yaptı (%s): o grupta geçici, %s.") % [
		_party_name(peer_id), VoterGroups.title(group), String(VoterGroups.data(group).get("meeting", "")),
		EffectWords.change(PublicOpinion.MEETING_BONUS[0], "group")]
	if crisis_group() == group:
		_add_national(pid, PublicOpinion.CRISIS_RESPONSE_NATIONAL)
		text += L.t(" Krize yanıt verdi (ulusal destek).")
	_push_state({"type": "speech", "peer_id": peer_id, "message": text})

@rpc("any_peer", "reliable")
func _request_speech(group: String) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_speech(multiplayer.get_remote_sender_id(), group)

## Tur sonu: miting yorgunluğu söner, süresi dolan toplantı kayıtları silinir.
func _decay_group_effects(next_round: int) -> void:
	for pid in miting_fatigue.keys():
		var entry: Dictionary = miting_fatigue[pid]
		for group in entry.keys():
			var value := float(entry[group]) * PublicOpinion.MITING_FATIGUE_DECAY
			if value < 0.05:
				entry.erase(group)
			else:
				entry[group] = value
		if entry.is_empty():
			miting_fatigue.erase(pid)
	for pid in group_meetings.keys():
		var entry: Dictionary = group_meetings[pid]
		for group in entry.keys():
			if next_round - int(entry[group]) >= PublicOpinion.MEETING_BONUS.size():
				entry.erase(group)
		if entry.is_empty():
			group_meetings.erase(pid)

# --- Karışıklık ve bölünme ------------------------------------------------------------

func turmoil_of(peer_id: int) -> float:
	return float(turmoil.get(party_of(peer_id), 0.0))

func _add_turmoil(peer_id: int, amount: float) -> void:
	if peer_id == -1 or not _is_authority():
		return
	peer_id = party_of(peer_id)
	if amount > 0.0 and PoliticianPresets.party_has_background(peer_id, "emekli_subay"):
		amount *= PoliticianPresets.OFFICER_TURMOIL_MULT
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

## Sonradan katılan geçici bot partisi mi? (Sıralamaya girmez.)
func is_temporary(peer_id: int) -> bool:
	return bool(PartyManager.data_of(peer_id).get("temporary", false)) and MultiplayerManager.is_bot(peer_id)

## Bu partiden ayrılmış (henüz geri dönmemiş) parti; yoksa -1.
func splinter_of(parent: int) -> int:
	for splinter in splinters.keys():
		if int(splinters[splinter].get("parent", -1)) == parent:
			return int(splinter)
	return -1

## Tur sonu: karışıklık söner; çok karışan parti bölünür. Ayrılmış bir parti
## bir daha bölünemez, ana partinin de aynı anda tek ayrılanı olabilir.
func _check_splits() -> void:
	for peer_id in party_ids():
		var parent := int(peer_id)
		if PartyManager.is_independent(parent) or turmoil_of(parent) < PublicOpinion.SPLIT_TURMOIL or is_splinter(parent) or splinter_of(parent) != -1:
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
	for prefix in ["Yeni ", L.t("Öz "), L.t("Gerçek "), L.t("Hür ")]:
		var candidate := (String(prefix) + parent_name).left(PartyManager.NAME_MAX_LENGTH).strip_edges()
		if not used.has(candidate):
			return candidate
	return ("Y" + parent_name).left(PartyManager.NAME_MAX_LENGTH)

## BÖLÜNME: ana partiyle BİREBİR aynı grup yakınlıklarıyla, benzer renkte yeni bir parti
## doğar ve yapay zekâ yönetir. Ana partinin vekillerinin ciddi bir bölümü ve
## bazı il teşkilatları ona geçer.
func _split_party(parent: int) -> void:
	var parent_name := _party_name(parent)
	# Ayrılanların başında YENİ bir siyasetçi var (ana partinin adamı değil).
	var bot_name := PoliticianPresets.random_name(PoliticianPresets.used_surnames())
	var splinter := MultiplayerManager.add_splinter_bot("%s %s" % [bot_name["first_name"], bot_name["surname"]])
	PartyManager.add_splinter_party(splinter, parent, _splinter_name(parent_name))
	var home := String(_province_ids[_rng.randi() % _province_ids.size()]) if not _province_ids.is_empty() else ""
	PartyManager.set_politician_host(splinter, PoliticianPresets.make(bot_name["first_name"], bot_name["surname"],
		PoliticianPresets.random_background(), home, bot_name["gender"]))
	turn_order.append(splinter)
	inventories[splinter] = []
	funds[splinter] = float(GameRules.FUNDS_PER_ROUND)
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
		L.t("%s BÖLÜNDÜ! Parti içi karışıklık sonunda %d milletvekili %s önderliğinde ayrılıp %s'yi kurdu.") % [
		parent_name, moved, PoliticianPresets.display_name(splinter), _party_name(splinter)]}, true)

## Tur sonu: ayrılan parti en erken 1, en geç 4 seçim atlattıktan sonra ana
## partisine BÜTÜN vekilleri ve teşkilatlarıyla geri döner. Erken dönüş için
## ana partinin karışıklığı yatışmış olmalı.
func _check_reunions() -> void:
	for splinter in splinters.keys().duplicate():
		var info: Dictionary = splinters[splinter]
		var parent := int(info.get("parent", -1))
		if not party_ids().has(parent) or PartyManager.is_independent(parent):
			splinters.erase(splinter)  # ana parti oyundan çıktı / feshedildi: bağımsız kalır
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
	_add_national(parent, maxf(0.0, national_of(splinter)) * 0.5)
	national_support.erase(splinter)
	var hand: Array = inventories.get(parent, [])
	for card in inventories.get(splinter, []):
		if hand.size() < MAX_HAND_SIZE:
			hand.append(card)
	inventories[parent] = hand
	for table in [inventories, funds, populism, law_rounds, national_list, last_seats, election_seats, last_vote_shares, turmoil, credibility]:
		table.erase(splinter)
	passed_threshold.erase(splinter)
	for province_id in last_province_results.keys():
		last_province_results[province_id].erase(splinter)
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
		L.t("%s, ana partisi %s'ya geri döndü: %d milletvekili ve bütün teşkilatlarıyla.") % [
		splinter_name, _party_name(parent), moved]}, true)
	PartyManager.remove_party(splinter)
	MultiplayerManager.remove_splinter_bot(splinter)

## Tur sonu: puanlar sıfıra doğru söner; neredeyse sıfır olanlar silinir.
## (İl başkanlıkları sönmez.)
func _decay_opinion() -> void:
	_decay_group_effects(round_number)
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
	var amount: int = mini(wanted, int(last_seats.get(party_of(target_peer_id), 0)))
	if amount <= 0:
		return false

	var moved := _move_seats(party_of(target_peer_id), party_of(peer_id), amount)
	if moved == 0:
		return false
	# Transfer meşru görünmez: çalan küçük bir ulusal destek kaybeder, çalınan
	# parti mağduriyetten küçük bir destek kazanır (ikisi de kısmi).
	# NORMAL vekil çalmanın ulusal bedeli YOK; sadece güçlü varyant bedel öder.
	if card_type == CardPresets.STEAL_STRONG_CARD_TYPE:
		_add_national(peer_id, PublicOpinion.steal_thief_national(moved))
	_add_national(target_peer_id, PublicOpinion.steal_victim_national(moved))
	_event_message = L.t("%s, %s'dan %d milletvekili transfer etti.") % [_party_name(peer_id), _party_name(target_peer_id), moved]
	return true

## Kaset / itibar suikastı: hedefin ULUSAL desteği doğrudan düşer. Popülizm
## süren saldırgan için hasar daha büyüktür (kendi hamlesinin iyi sonucu).
func _apply_reputation(peer_id: int, target_peer_id: int) -> void:
	var damage := PublicOpinion.REPUTATION_NATIONAL_DAMAGE
	if populism_rounds_left(peer_id) > 0:
		damage *= PublicOpinion.POPULISM_GOOD_MULT
	if PoliticianPresets.party_has_background(target_peer_id, "ilahiyatci"):
		damage *= PoliticianPresets.CLERIC_DAMAGE_MULT
	_add_turmoil(target_peer_id, PublicOpinion.TURMOIL_REPUTATION)
	_add_national(target_peer_id, -damage)
	# ANONİM: kaseti kimin sızdırdığı hiçbir yerde gösterilmez.
	_event_message = L.t("%s hakkında kaset sızdı: %s, parti içinde karışıklık.") % [
		_party_name(target_peer_id), EffectWords.change(-damage)]

## GovernmentManager, hükümet güvenoyu alınca çağırır: hükümet partilerine para.
func grant_government_funds(peer_ids: Array) -> void:
	if not _is_authority():
		return
	for peer_id in peer_ids:
		# İki kişilik partide iki oyuncu da hükümet kasasını alır.
		var members: Array = PartyManager.members_of(party_of(int(peer_id)))
		for member in members:
			if funds.has(member):
				funds[member] = funds_of(member) + float(GameRules.GOVERNMENT_FUNDS_BONUS)
		# Hükümete girmek parti içini toparlar.
		_ease_turmoil(int(peer_id), PublicOpinion.TURMOIL_EASE_GOVERNMENT)
	_push_state({"type": "funds"})

## Bu partinin hedeften bu kartla çalabileceği vekil aralığı (yakınlığa göre).
## Kartın vereceği vekil aralığı. Meclis dışı partide yarıya iner (arayüzde de
## bu aralık gösterilir, sürpriz olmasın).
func steal_range(peer_id: int, target_peer_id: int, card_type: String) -> Dictionary:
	var base := CardPresets.steal_range(card_type, group_closeness(peer_id, target_peer_id))
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
	if not wrapped:
		_retire_due_temporary_parties()
	_grant_turn_income()
	_maybe_mandatory_congress()
	return wrapped

## Sırası gelen oyuncu para gelirini VE bir kart alır.
## KART ÇEKME HAMLESİ KALDIRILDI: deste butonu yerine her elin başında
## otomatik olarak bir kart geliyor. Dağıtılan kart, bu hamleden sonra
## gönderilecek state olayına iliştirilsin diye _pending_dealt'ta beklet.
func _grant_turn_income() -> void:
	var peer_id := current_turn_peer_id()
	# Grup toplantısı PARTİYE aittir: partinin diğer üyesi bu dönem toplandıysa
	# bu oyuncu toplanamaz.
	speech_done = peer_id != -1 and int(speech_rounds.get(party_of(peer_id), 0)) == round_number
	if peer_id == -1:
		return
	funds[peer_id] = funds_of(peer_id) + turn_income(peer_id)
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
	if inventories[peer_id].size() >= MAX_HAND_SIZE or is_party_member(peer_id):
		return ""  # üye kart oynayamaz: kart da almaz
	return CardPresets.weighted_pick(_draw_weights(peer_id), _rng)

## Tur geliri: hükümette görevi olan partiler bir fazla para alır.
func turn_income(peer_id: int) -> float:
	var base := float(GameRules.FUNDS_PER_ROUND_GOVERNMENT if is_government_party(peer_id) else GameRules.FUNDS_PER_ROUND)
	return maxf(0.0, base - bot_funds_penalty(peer_id)) + float(org_income(peer_id))

## Partinin teşkilatlı il sayısı.
func org_count(peer_id: int) -> int:
	var pid := party_of(peer_id)
	var n := 0
	for province_id in organizations.keys():
		if int((organizations[province_id] as Dictionary).get(pid, 0)) > 0:
			n += 1
	return n

## Bu oyuncunun bu ilde (il yoksa yeni bir ilde) teşkilat hamlesinin bedeli.
func org_cost_for(peer_id: int, province_id: String = "") -> float:
	var level := organization_level(province_id, peer_id) if province_id != "" else 0
	return GameRules.org_cost(level, org_count(peer_id))

## Partinin teşkilatlarının tur başı geliri (1. seviye +5, 2. seviye +10 / il,
## toplamı en fazla GameRules.ORG_INCOME_CAP).
func org_income(peer_id: int) -> int:
	var pid := party_of(peer_id)
	var total := 0
	for province_id in organizations.keys():
		var level := int((organizations[province_id] as Dictionary).get(pid, 0))
		total += int(GameRules.ORG_INCOME[clampi(level, 0, GameRules.ORG_INCOME.size() - 1)])
	return mini(total, GameRules.ORG_INCOME_CAP)

## Lobi kuralı: botlar tur başında ve bağış kampanyalarından bu kadar az para alır.
func bot_funds_penalty(peer_id: int) -> float:
	return MultiplayerManager.bot_funds_penalty if MultiplayerManager.is_bot(peer_id) else 0.0

## Bağış kampanyası kartının bu oyuncuya verdiği para (botlara zayıflatma uygulanır).
func funds_bonus_amount(peer_id: int, strong: bool) -> float:
	var base := float(GameRules.FUNDS_BONUS_STRONG if strong else GameRules.FUNDS_BONUS_WEAK)
	return maxf(0.0, base - bot_funds_penalty(peer_id))

## Desteden bir kartı doğrudan ele verir. El doluysa verilmez.
## Dönen değer: verilen kartın türü ("" = verilmedi).
## exclude: bu kart türleri çekilmez (bonus karttan bonus kart çıkmaz).
func _deal_turn_card(peer_id: int, exclude: Array = []) -> String:
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	if inventories[peer_id].size() >= MAX_HAND_SIZE:
		return ""
	var weights := _draw_weights(peer_id)
	for card_type in exclude:
		weights.erase(card_type)
	var card_type := CardPresets.weighted_pick(weights, _rng)
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
	# Yeni dönem: sıradaki oyuncunun toplantı bilgisi yeni döneme göre.
	var current := current_turn_peer_id()
	speech_done = current != -1 and int(speech_rounds.get(party_of(current), 0)) == round_number

	# Ayrılan partiler dönebilir, çok karışan parti bölünür; sonra karışıklık söner.
	_check_reunions()
	_check_splits()
	for peer_id in turmoil.keys():
		turmoil[peer_id] = turmoil_of(int(peer_id)) * PublicOpinion.TURMOIL_DECAY
	# EKONOMİ: tur başına tek sefer, SEÇİMDEN ÖNCE (sandık o ana kadar
	# gerçekleşmiş etkileri görür; bekleyen dilimler ve yerleşmemiş vergi
	# etkisi sayılmaz).
	_pending_log.append({"text": _advance_economy(), "peer_id": -1, "province": "", "kind": "economy"})
	_pending_econ = {"kind": "round", "revenue": float(economy["revenue"])}

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
	for peer_id in party_ids():
		if populism_rounds_left(peer_id) > 0:
			national[peer_id] = float(national.get(peer_id, 0.0)) + PublicOpinion.POPULISM_ELECTION_NATIONAL
	return {"national": national, "local": activity_map()}

func _hold_election(finished_round: int, early: bool) -> void:
	var mods := election_modifiers()
	# Toplantı bonusları seçimin yapıldığı (biten) tura göre: son tur toplantısı tam etkili.
	var groups := _group_profiles(finished_round).duplicate(true)
	# Denge analizi (tools/balance_sim.gd) için seçimin girdileri; ağda gönderilmez.
	last_election_inputs = {
		"mods": mods, "groups": groups, "voters": province_voters(),
		"threshold": MultiplayerManager.election_threshold,
		"gov_ids": GovernmentManager.government_party_ids(), "organizations": organizations.duplicate(true),
		"seats_before": last_seats.duplicate(),
	}
	var result := ElectionModel.compute(groups, _province_seat_counts, province_voters(),
		MultiplayerManager.election_threshold, _rng, mods)
	_add_independent_seats(result, groups, mods, finished_round)
	# Fesihten kalan Bağımsızlar bloğu seçimle dağılır (aşağıda sonuçlar yazılınca).
	if PartyManager.parties.has(PartyManager.BLOC_ID):
		PartyManager.parties.erase(PartyManager.BLOC_ID)
		PartyManager.broadcast()
	_update_credibility(last_vote_shares, result["vote_shares"])
	previous_vote_shares = last_vote_shares.duplicate()
	last_vote_shares = result["vote_shares"]
	last_seats = result["seats"]
	last_province_results = result["province_results"]
	passed_threshold = result["passed_threshold"]
	national_list = result.get("national_list", {})
	election_seats = last_seats.duplicate()
	election_groups = {}
	for pid in party_ids():
		election_groups[pid] = PartyManager.groups_of(pid).duplicate()
	last_election_round = finished_round
	# Geçici partiler: süresi dolan fesheder; botlar ittifak kurar/bozar; sonra
	# belki yeni bir parti katılır. (Hükümet kurma bundan sonra başlar: ayrılan
	# kardeş partiler ayrı ayrı makam alabilir.)
	_retire_temporary_parties()
	_count_congress_elections()
	_maybe_add_temporary_party()
	for splinter in splinters.keys():
		splinters[splinter]["elections"] = int(splinters[splinter].get("elections", 0)) + 1
	last_election_was_early = early
	# Seçim sonrası herkese para ve 1 kart hediye.
	for peer_id in turn_order:
		funds[peer_id] = funds_of(peer_id) + float(GameRules.ELECTION_FUNDS_BONUS)
		_deal_turn_card(peer_id)
	# Seçimde kullanıldıktan SONRA söner: seçimden hemen önceki hamleler tam etkili.
	_decay_opinion()
	_pick_music_track()  # seçim gecesinden sonra yeni dönemin müziği
	_push_state({"type": "election"}, true)
	# Yeni meclis: hükümet kurma görevi en çok vekili olan partiye verilir.
	# Seçim gecesi yayını herkesin ekranında oynarken kurma süresi yanmasın.
	GovernmentManager.start_formation(GameRules.ELECTION_NIGHT_SECONDS + GameRules.ELECTION_NIGHT_HOLD + 2.0)

## BAĞIMSIZ ADAY: sadece memleketinde yarışır, en fazla 1 sandalye kazanır.
## O ildeki payı (diğer partilerle birlikte hesaplanır) ilin bir vekillik
## kotasının INDEPENDENT_QUOTA_FACTOR'ünü geçerse, ilin en çok vekil çıkaran
## partisinden bir sandalye alır. Az bir miting bile yetebilir (hemşehri desteği).
const INDEPENDENT_QUOTA_FACTOR := 0.6

func _add_independent_seats(result: Dictionary, groups: Dictionary, mods: Dictionary, at_round: int = -1) -> void:
	var province_results: Dictionary = result["province_results"]
	var seats: Dictionary = result["seats"]
	var vote_shares: Dictionary = result["vote_shares"]
	var local_mods: Dictionary = mods["local"]
	var total_seats := 0
	for province_id in _province_ids:
		total_seats += province_seat_count(province_id)
	for pid in party_ids():
		if not PartyManager.is_independent(pid):
			continue
		var home := PoliticianPresets.hometown_of(pid)
		if not province_results.has(home):
			continue
		var field := groups.duplicate()
		field[pid] = effective_groups(pid, at_round)
		var shares := ElectionModel.expected_shares(field, province_profile(home), mods["national"], local_mods.get(home, {}))
		var share := float(shares.get(pid, 0.0))
		var seats_here := province_seat_count(home)
		var entry: Dictionary = province_results[home]
		var won := 0
		if seats_here > 0 and share >= 100.0 / float(seats_here + 1) * INDEPENDENT_QUOTA_FACTOR:
			var victim := -1
			for other in entry.keys():
				if int(entry[other].get("seats", 0)) > 0 and (victim == -1 or int(entry[other]["seats"]) > int(entry[victim]["seats"])):
					victim = int(other)
			if victim != -1:
				entry[victim]["seats"] = int(entry[victim]["seats"]) - 1
				seats[victim] = int(seats.get(victim, 0)) - 1
				won = 1
		entry[pid] = {"percent": share, "seats": won}
		seats[pid] = won
		vote_shares[pid] = share * seats_here / maxf(1.0, float(total_seats))

## Son seçimin ardından hükümet kurma bitti: puan tablosu kesinleşir. Makam
## puanları hükümet kurulurken zaten yazıldı, burada tekrar yazılmaz.
func _finish_final_election() -> void:
	final_election_pending = false
	if GovernmentManager.has_government():
		_end_game(L.t("%d dönem tamamlandı. Son hükümeti %s kurdu.") % [
			GameRules.MAX_ROUNDS, _party_name(GovernmentManager.main_gov_peer_id)])
	else:
		_end_game(L.t("%d dönem tamamlandı. Son seçimden sonra hükümet kurulamadı.") % GameRules.MAX_ROUNDS)

func _end_game(reason: String) -> void:
	game_finished = true
	game_end_reason = reason
	final_ranking = []
	# SİYASETÇİ TABANLI sıralama: her oyuncu ayrı satır; bölünen ve geçici
	# (sonradan katılan) bot partileri sıralamaya girmez.
	var ids: Array = []
	for peer_id in turn_order:
		if not is_splinter(party_of(int(peer_id))) and not is_temporary(int(peer_id)):
			ids.append(peer_id)
	ids.sort_custom(func(a, b):
		var sa := ranking_score(a)
		var sb := ranking_score(b)
		if sa != sb:
			return sa > sb
		var va := int(last_seats.get(party_of(int(a)), 0))
		var vb := int(last_seats.get(party_of(int(b)), 0))
		if va != vb:
			return va > vb
		return a < b
	)
	for peer_id in ids:
		var party: Dictionary = PartyManager.data_of(int(peer_id))
		final_ranking.append({
			"peer_id": peer_id,
			"name": party.get("name", "?"),
			"leader": PoliticianPresets.display_name(int(peer_id)),
			"color": party.get("bg_color", Color(0.5, 0.5, 0.5)),
			"score": ranking_score(peer_id),
			"seats": int(last_seats.get(party_of(int(peer_id)), 0)),
			"independent": PartyManager.is_independent(int(peer_id)),
		})
	GovernmentManager.end_game()
	_push_state({"type": "game_over"})

## Sıralama puanı: ayrılmış (henüz dönmemiş) partinin puanı ana partiye sayılır.
func ranking_score(peer_id: int) -> int:
	var score := GovernmentManager.score_of(peer_id)
	if not PartyManager.is_leader(peer_id):
		return score
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
	# Yasa/gensoru son parayla verildiyse oylama bitince sıra devreder.

## Host: oyun sırasında ayrılan oyuncuyu sıradan, envanterden, meclisten ve
## hükümet süreçlerinden çıkarır. Onsuz sırası gelen/oy bekleyen oyun kilitlenirdi.
func remove_player(peer_id: int) -> void:
	if not _is_authority():
		return
	var idx := turn_order.find(peer_id)
	if idx == -1:
		return
	# PARTİ ÜYESİ AYRILDI: parti yaşamaya devam eder. Yardımcı giderse sadece
	# üyelikten düşer; genel başkan giderse parti yardımcıya geçer.
	var pid := party_of(peer_id)
	var keep_party := false
	if pid != peer_id:
		PartyManager.parties[pid].erase("deputy")
		keep_party = true
	elif PartyManager.deputy_of(pid) != -1:
		_rekey_party(pid, PartyManager.deputy_of(pid), -1)
		keep_party = true
	PartyManager.politicians.erase(peer_id)
	if keep_party:
		PartyManager.broadcast()
		_remove_from_turn_order(idx)
		inventories.erase(peer_id)
		funds.erase(peer_id)
		credibility.erase(peer_id)
		GovernmentManager.votes.erase(peer_id)
		_push_state({"type": "player_left", "peer_id": peer_id}, true)
		if turn_order.size() < GameRules.MIN_PLAYERS_TO_CONTINUE:
			_end_game(L.t("Yeterli oyuncu kalmadı."))
		return
	var was_current := idx == current_turn_index
	turn_order.remove_at(idx)
	inventories.erase(peer_id)
	funds.erase(peer_id)
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
		_end_game(L.t("Yeterli oyuncu kalmadı."))
		return
	_finish_round_if_needed(wrapped)

# --- Parti siyaseti ------------------------------------------------------------------
## HER PARTİNİN TEK GENEL BAŞKANI VAR (beraber oynama yok). Oyuncu ya bir
## partinin genel başkanı, ya bir bot başkanın partisinde ÜYE (kongreyi
## kaybetmiş eski başkan; teknik olarak parti kaydındaki "deputy" alanı), ya da
## bağımsızdır.
##   FESİH (genel başkan): vekillerin yarısı Bağımsızlar bloğuna, yarısı seçmen grupları
##     en yakın partilere dağılır; siyasetçi BAĞIMSIZ olur.
##   İSTİFA (üye): partiden ayrılır, BAĞIMSIZ olur.
##   YENİ PARTİ (bağımsız): FOUND_PARTY_COST para. Bağımsızken toplanan ulusal
##     destek partiye geçer; miting yaptığı en güçlü illerde 1. seviye teşkilatla
##     başlar (güvenilirliği ne kadar yüksekse o kadar çok il).
##   ÜYE: sadece MİTİNG yapar (partisine ve kendi güvenilirliğine yazar) ya da
##     kongre ister / istifa eder. Parti hükümetteyse makam puanını başkanla
##     aynı miktarda alır.
##
## KONGRE (bkz. "Kongre" bölümü): genel başkan en geç CONGRESS_MAX_ELECTIONS
## seçimde bir kongreye gider; gitmezse sırası gelince kongre kendiliğinden
## olur. Başkan isterse (en az bir seçim geçtiyse) kendi sırasında kongreye
## gidebilir. Adaylar ve sonuç önceden hesaplanır, herkesin ekranında seçim
## gecesi tarzında oynatılır.
const FOUND_PARTY_COST := 80
const DISSOLVE_CREDIBILITY := 8.0
const DISSOLVE_BLOC_SHARE := 0.5
## Fesihte partinin ulusal puanının siyasetçiye (kişisel popülerlik) kalan payı.
const DISSOLVE_NATIONAL_KEEP := 0.5
## Bağımsız ya da üye mitingi güvenilirlik kazandırır.
const MITING_CREDIBILITY := 3.0
## Yeni parti: güvenilirliğin her FOUND_ORG_PER_CREDIBILITY puanı için miting
## yapılan en güçlü illerden birinde 1. seviye teşkilat (en fazla FOUND_ORG_MAX).
const FOUND_ORG_PER_CREDIBILITY := 25.0
const FOUND_ORG_MAX := 4
## ESKİ PARTİDEN TEŞKİLAT GEÇİŞİ: partisinden istifa eden ya da partisini
## feshedip bağımsız kalan siyasetçi yeni parti kurunca eski partisinin
## teşkilatlarının bir kısmı (seviyeleriyle) yeni partiye geçer:
##   pay = 0,5 + süre + başarı + ulusal destek + güvenilirlik (%10..%90)
##   süre       : +0,2 − 0,05 × ayrılıştan beri geçen tur (en az −0,25)
##   başarı     : siyasetçinin puanı / 100 (en fazla +0,25)
##   ulusal     : ulusal destek × 0,04 (−0,2..+0,2)
##   güvenilirlik: (güvenilirlik − 50) / 500 (−0,1..+0,1)
## Eski parti sürüyorsa teşkilatlar ondan KOPAR (taşınır); feshedildiyse
## dağılan teşkilatlar yeniden toplanır.
const FORMER_ORG_BASE := 0.5
const FORMER_ORG_FRESH := 0.2
const FORMER_ORG_PER_ROUND := 0.05
const FORMER_ORG_TIME_MIN := -0.25
const FORMER_ORG_SCORE_DIV := 100.0
const FORMER_ORG_SCORE_MAX := 0.25
const FORMER_ORG_NATIONAL := 0.04
const FORMER_ORG_NATIONAL_MAX := 0.2
const FORMER_ORG_MIN := 0.1
const FORMER_ORG_MAX := 0.9
## Bağımsız siyasetçi -> {"party": eski parti, "name": adı, "round": ayrıldığı
## tur, "orgs": {il: seviye} (sadece parti feshedildiyse: dağılan teşkilatlar)}.
var former_parties: Dictionary = {}

# Sorgular (arayüz ve host doğrulaması) -------------------------------------------

func is_party_member(peer_id: int) -> bool:
	return PartyManager.is_deputy(peer_id)

func can_dissolve(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and PartyManager.is_leader(peer_id) and not PartyManager.is_independent(peer_id) \
		and PartyManager.deputy_of(peer_id) == -1

func can_resign(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and is_party_member(peer_id)

func can_found_party(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and PartyManager.is_independent(peer_id) and funds_of(peer_id) >= FOUND_PARTY_COST

## Yeni parti kurulursa eski partiden geçecek teşkilat payı (0 = eski parti yok).
func former_org_share(peer_id: int) -> float:
	var info: Dictionary = former_parties.get(peer_id, {})
	if info.is_empty() or former_org_source(peer_id).is_empty():
		return 0.0
	var rounds := maxi(0, round_number - int(info.get("round", round_number)))
	var share := FORMER_ORG_BASE
	share += maxf(FORMER_ORG_TIME_MIN, FORMER_ORG_FRESH - FORMER_ORG_PER_ROUND * rounds)
	share += clampf(float(GovernmentManager.score_of(peer_id)) / FORMER_ORG_SCORE_DIV, 0.0, FORMER_ORG_SCORE_MAX)
	share += clampf(national_of(peer_id) * FORMER_ORG_NATIONAL, -FORMER_ORG_NATIONAL_MAX, FORMER_ORG_NATIONAL_MAX)
	share += clampf((credibility_of(peer_id) - 50.0) / 500.0, -0.1, 0.1)
	return clampf(share, FORMER_ORG_MIN, FORMER_ORG_MAX)

## Eski partinin şu an devralınabilecek teşkilatları: il -> seviye.
func former_org_source(peer_id: int) -> Dictionary:
	var info: Dictionary = former_parties.get(peer_id, {})
	if info.is_empty():
		return {}
	if info.has("orgs"):
		return info["orgs"]
	var pid := int(info.get("party", -1))
	if not PartyManager.parties.has(pid) or PartyManager.is_independent(pid):
		return {}
	var result := {}
	for province_id in organizations.keys():
		var level := int(organizations[province_id].get(pid, 0))
		if level > 0:
			result[province_id] = level
	return result

## Yeni parti kurulunca geçecek teşkilat sayısı (arayüz önizlemesi için).
func former_org_count(peer_id: int) -> int:
	var total := former_org_source(peer_id).size()
	if total == 0:
		return 0
	return clampi(int(round(former_org_share(peer_id) * total)), 1, total)

## Ayrılan siyasetçinin eski partisini kaydeder. dissolved_orgs: fesihte
## dağılan teşkilatlar (parti sürüyorsa boş).
func _remember_former_party(peer_id: int, pid: int, dissolved_orgs: Dictionary = {}) -> void:
	var info := {"party": pid, "name": _party_name(pid), "round": round_number}
	if not dissolved_orgs.is_empty() or pid == peer_id:
		info["orgs"] = dissolved_orgs
	former_parties[peer_id] = info

## Eski partinin teşkilatlarından payı kadarını yeni partiye taşır.
## Dönüş: [geçen sayı, toplam, pay].
func _transfer_former_orgs(peer_id: int) -> Array:
	var source := former_org_source(peer_id)
	var share := former_org_share(peer_id)
	var count := former_org_count(peer_id)
	var info: Dictionary = former_parties.get(peer_id, {})
	var old_pid := int(info.get("party", -1))
	var dissolved := info.has("orgs")
	var ids: Array = source.keys()
	ids.sort()
	_shuffle(ids)
	for i in count:
		var province_id := String(ids[i])
		if not organizations.has(province_id):
			organizations[province_id] = {}
		organizations[province_id][peer_id] = maxi(int(organizations[province_id].get(peer_id, 0)), int(source[province_id]))
		if not dissolved:
			organizations[province_id].erase(old_pid)
	return [count, source.size(), share]

func credibility_add(peer_id: int, amount: float) -> void:
	credibility[peer_id] = clampf(credibility_of(peer_id) + amount, 0.0, CREDIBILITY_MAX)

# İstemci istekleri ------------------------------------------------------------------

func dissolve_party() -> void:
	var me := multiplayer.get_unique_id()
	if not can_dissolve(me):
		return
	if _is_authority():
		_apply_dissolve(me)
	else:
		_request_dissolve.rpc_id(1)

func resign_from_party() -> void:
	var me := multiplayer.get_unique_id()
	if not can_resign(me):
		return
	if _is_authority():
		_apply_resign(me)
	else:
		_request_resign.rpc_id(1)

## data: {"name", "icon_index", "bg_color"}
func found_party(data: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	if not can_found_party(me):
		return
	if _is_authority():
		_apply_found(me, data)
	else:
		_request_found.rpc_id(1, data)

func request_congress() -> void:
	var me := multiplayer.get_unique_id()
	if not can_call_congress(me):
		return
	if _is_authority():
		_apply_congress(me)
	else:
		_request_congress.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_dissolve() -> void:
	if MultiplayerManager.is_host:
		_apply_dissolve(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _request_resign() -> void:
	if MultiplayerManager.is_host:
		_apply_resign(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _request_found(data: Dictionary) -> void:
	if MultiplayerManager.is_host:
		_apply_found(multiplayer.get_remote_sender_id(), data)

@rpc("any_peer", "reliable")
func _request_congress() -> void:
	if MultiplayerManager.is_host:
		_apply_congress(multiplayer.get_remote_sender_id())

# Host: uygulama ------------------------------------------------------------------------

func _apply_dissolve(peer_id: int) -> void:
	if not can_dissolve(peer_id):
		return
	var pid := peer_id
	var party_name := _party_name(pid)
	var groups := PartyManager.groups_of(pid).duplicate()
	credibility_add(peer_id, -DISSOLVE_CREDIBILITY)
	# FESİH: vekillerin yarısı Bağımsızlar bloğuna, yarısı yakın partilere.
	var scattered := _scatter_seats(pid)
	var to_bloc := int(scattered[0])
	var rest := int(scattered[1])
	election_seats[pid] = 0
	last_vote_shares.erase(pid)
	previous_vote_shares.erase(pid)
	passed_threshold.erase(pid)
	var dissolved_orgs := {}
	for province_id in organizations.keys():
		if int(organizations[province_id].get(pid, 0)) > 0:
			dissolved_orgs[province_id] = int(organizations[province_id][pid])
		organizations[province_id].erase(pid)
	_remember_former_party(peer_id, pid, dissolved_orgs)
	for province_id in local_support.keys():
		local_support[province_id].erase(pid)
	national_support[pid] = national_of(pid) * DISSOLVE_NATIONAL_KEEP
	populism.erase(pid)
	turmoil.erase(pid)
	party_congress.erase(pid)
	for splinter in splinters.keys():
		if int(splinters[splinter].get("parent", -1)) == pid:
			splinters.erase(splinter)
	_make_independent(peer_id, groups)
	PartyManager.broadcast()
	var gov_note := GovernmentManager.party_dissolved(pid)
	_push_state({"type": "party_change", "peer_id": peer_id, "message":
		L.t("%s, %s'yi FESHETTİ ve bağımsız kaldı. %d vekil Bağımsızlar'a, %d vekil yakın partilere geçti.%s") % [
		PoliticianPresets.display_name(peer_id), party_name, to_bloc, rest, gov_note]}, true)

## Üye partisinden istifa eder: bağımsız olur (parti bot başkanla sürer).
func _apply_resign(peer_id: int) -> void:
	if not can_resign(peer_id):
		return
	var pid := party_of(peer_id)
	var party_name := _party_name(pid)
	var groups := PartyManager.groups_of(pid).duplicate()
	_remember_former_party(peer_id, pid)
	PartyManager.parties[pid].erase("deputy")
	_make_independent(peer_id, groups)
	national_support[peer_id] = 0.0
	PartyManager.broadcast()
	_push_state({"type": "party_change", "peer_id": peer_id, "message":
		L.t("%s, %s'den istifa etti ve bağımsız devam ediyor.") % [PoliticianPresets.display_name(peer_id), party_name]}, true)

## Feshedilen partinin vekilleri: yarısı Bağımsızlar bloğuna, yarısı seçmen
## grupları en yakın partilere (grup yakınlığı ağırlıklı D'Hondt).
## Dönüş: [bloğa giden, partilere giden].
func _scatter_seats(pid: int) -> Array:
	var seats := int(last_seats.get(pid, 0))
	var to_bloc := int(round(seats * DISSOLVE_BLOC_SHARE))
	var others: Array = []
	for other in party_ids():
		if int(other) != pid and not PartyManager.is_independent(int(other)):
			others.append(int(other))
	if others.is_empty():
		to_bloc = seats
	if to_bloc > 0:
		_ensure_bloc()
		_move_seats(pid, PartyManager.BLOC_ID, to_bloc)
	var rest := int(last_seats.get(pid, 0))
	if rest > 0 and not others.is_empty():
		var weights := {}
		for other in others:
			weights[other] = group_closeness(pid, other) + 0.01
		var alloc := ElectionModel.dhondt(weights, others, rest)
		for other in others:
			if int(alloc.get(other, 0)) > 0:
				_move_seats(pid, int(other), int(alloc[other]))
	return [to_bloc, rest]

## Botun yeni partisi için rastgele ad, logo ve boşta bir renk.
func _random_party_info(peer_id: int) -> Dictionary:
	var used: Array = []
	var colors: Array = []
	for party in PartyManager.parties.values():
		used.append(String(party.get("name", "")))
		colors.append(Color(party.get("bg_color", Color.TRANSPARENT)))
	return {
		"name": PartyManager._bot_party_name(used),
		"icon_index": PartyPresets.random_icon_index(),
		"icon_color": Color.WHITE,
		"bg_color": PartyManager._pick_distinct_color(colors),
		"ready": true,
		"founded_round": round_number,
	}

# Geçici (rastgele katılan) partiler ---------------------------------------------------
## Lobide açıksa (MultiplayerManager.random_parties) her seçimden sonra
## TEMP_PARTY_CHANCE olasılıkla yeni bir bot partisi kurulur: sandalyesiz,
## biraz ulusal destekle başlar, oyun sonu sıralamasına girmez. Kendini
## feshetmek üzere kurulur: ilk seçimde barajı geçemezse ya da
## TEMP_PARTY_ELECTIONS seçim atlattıktan sonra feshedip oyundan çıkar.
const TEMP_PARTY_CHANCE := 0.3
const TEMP_PARTY_ELECTIONS := 2
const TEMP_PARTY_NATIONAL := 2.0

## Testler kapatır (rastgele katılan parti test beklentilerini bozmasın).
var allow_temporary_parties: bool = true

func _maybe_add_temporary_party() -> void:
	if not allow_temporary_parties or not MultiplayerManager.random_parties or game_finished:
		return
	if MultiplayerManager.players.size() >= MultiplayerManager.MAX_PLAYERS:
		return
	if _rng.randf() >= TEMP_PARTY_CHANCE:
		return
	var bot := MultiplayerManager.add_splinter_bot(L.t("Yeni Parti"))
	PartyManager.add_bot_party(bot)
	PartyManager.parties[bot]["temporary"] = true
	PartyManager.parties[bot]["temp_elections"] = 0
	var home := PoliticianPresets.hometown_of(bot)
	if not _province_ids.has(home) and not _province_ids.is_empty():
		var fixed := PoliticianPresets.of(bot).duplicate()
		fixed["hometown"] = String(_province_ids[_rng.randi() % _province_ids.size()])
		PartyManager.set_politician_host(bot, fixed)
	PartyManager.broadcast()
	turn_order.append(bot)
	inventories[bot] = []
	funds[bot] = float(GameRules.FUNDS_PER_ROUND)
	credibility[bot] = CREDIBILITY_START
	national_support[bot] = TEMP_PARTY_NATIONAL
	_pending_log.append({"text": L.t("YENİ PARTİ: %s, %s'yi kurdu.") % [PoliticianPresets.display_name(bot), _party_name(bot)],
		"peer_id": bot, "province": "", "kind": "party_change"})

## Seçimden sonra: geçici partiler seçim sayar; süresi dolan ya da barajı
## geçemeyen fesheder ve oyundan çıkar.
func _retire_temporary_parties() -> void:
	for bot in turn_order.duplicate():
		var pid := int(bot)
		if not PartyManager.is_leader(pid) or not bool(PartyManager.parties[pid].get("temporary", false)):
			continue
		var elections := int(PartyManager.parties[pid].get("temp_elections", 0)) + 1
		PartyManager.parties[pid]["temp_elections"] = elections
		if elections < TEMP_PARTY_ELECTIONS and passed_threshold.has(pid):
			continue
		# Hemen değil: yeni turun ORTASINDA (ne başında ne sonunda) fesheder.
		var size := turn_order.size()
		PartyManager.parties[pid]["retire_at"] = _rng.randi_range(1, maxi(1, size - 2))

## Feshi bekleyen geçici partiler, sıra hedef konuma gelince dağılır.
func _retire_due_temporary_parties() -> void:
	for bot in turn_order.duplicate():
		var pid := int(bot)
		if not PartyManager.parties.has(pid) or not PartyManager.parties[pid].has("retire_at"):
			continue
		if current_turn_index < int(PartyManager.parties[pid]["retire_at"]):
			continue
		_dissolve_temporary_party(pid)

func _dissolve_temporary_party(pid: int) -> void:
	var party_name := _party_name(pid)
	var scattered := _scatter_seats(pid)
	var deputy := PartyManager.deputy_of(pid)
	if deputy != -1:
		# Yardımcısı (bir oyuncu) varsa parti feshedilince o bağımsız kalır.
		var temp_orgs := {}
		for province_id in organizations.keys():
			if int(organizations[province_id].get(pid, 0)) > 0:
				temp_orgs[province_id] = int(organizations[province_id][pid])
		_remember_former_party(deputy, pid, temp_orgs)
		_make_independent(deputy, PartyManager.groups_of(pid).duplicate())
	for table in [national_support, populism, turmoil, law_rounds, speech_rounds, congress_rounds,
			group_meetings, miting_fatigue, election_groups,
			national_list, last_seats, election_seats, last_vote_shares, previous_vote_shares, inventories, funds, credibility]:
		table.erase(pid)
	passed_threshold.erase(pid)
	for nested in [last_province_results, local_support, organizations]:
		for province_id in nested.keys():
			nested[province_id].erase(pid)
	var idx := turn_order.find(pid)
	if idx != -1:
		_remove_from_turn_order(idx)
	PartyManager.parties.erase(pid)
	PartyManager.politicians.erase(pid)
	MultiplayerManager.remove_splinter_bot(pid)
	PartyManager.broadcast()
	_pending_log.append({"text": L.t("%s kendini feshetti (%d vekil dağıldı).") % [party_name, int(scattered[0]) + int(scattered[1])],
		"peer_id": -1, "province": "", "kind": "party_change"})

## Siyasetçiyi bağımsız kayda çevirir (gri, kullanıcı simgeli, adıyla).
func _make_independent(peer_id: int, groups: Dictionary) -> void:
	PartyManager.parties[peer_id] = {
		"name": PoliticianPresets.display_name(peer_id).left(PartyManager.NAME_MAX_LENGTH + 10),
		"icon_index": PartyPresets.USER_ICON_INDEX,
		"icon_color": Color.WHITE,
		"bg_color": PartyPresets.INDEPENDENT_COLOR,
		"groups": groups,
		"independent": true,
		"ready": true,
	}

## Bağımsızlar bloğu kaydı (fesihte sahipsiz kalan vekiller).
func _ensure_bloc() -> void:
	if PartyManager.parties.has(PartyManager.BLOC_ID):
		return
	PartyManager.parties[PartyManager.BLOC_ID] = {
		"name": L.t("Bağımsızlar"),
		"icon_index": PartyPresets.USER_ICON_INDEX,
		"icon_color": Color.WHITE,
		"bg_color": PartyPresets.INDEPENDENT_COLOR.darkened(0.25),
		"groups": VoterGroups.neutral_affinities(),
		"bloc": true,
	}

## Parti verisi geçerli mi? (ad, ikon, renk; başka partide olmayan renk.)
func _valid_party_data(peer_id: int, data: Dictionary) -> bool:
	var party_name := String(data.get("name", "")).strip_edges()
	if not PartyManager.is_valid_name(party_name):
		return false
	for other in PartyManager.parties.keys():
		if int(other) != peer_id and String(PartyManager.parties[other].get("name", "")) == party_name:
			return false
	var icon := int(data.get("icon_index", -1))
	if icon < 0 or icon >= PartyPresets.icon_count():
		return false
	var color: Color = data.get("bg_color", Color.WHITE)
	if color.is_equal_approx(Color.WHITE) or not PartyPresets.COLORS.has(color):
		return false
	return PartyManager.color_owner(color, peer_id) == -1

## YENİ PARTİ: bağımsız kurar (FOUND_PARTY_COST). Bağımsızken toplanan ulusal
## destek partiye geçer; güvenilirliğe göre miting yaptığı en güçlü illerde
## 1. seviye teşkilatla başlar.
func _apply_found(peer_id: int, data: Dictionary) -> void:
	if not can_found_party(peer_id) or not _valid_party_data(peer_id, data):
		return
	var info := {
		"name": String(data["name"]).strip_edges(),
		"icon_index": int(data["icon_index"]),
		"icon_color": Color.WHITE,
		"bg_color": Color(data["bg_color"]),
		"ready": true,
		"founded_round": round_number,
	}
	funds[peer_id] = funds_of(peer_id) - FOUND_PARTY_COST
	info["groups"] = PartyManager.groups_of(peer_id).duplicate()
	PartyManager.parties[peer_id] = info
	party_congress[peer_id] = {"elections": 0, "share": float(last_vote_shares.get(peer_id, 0.0))}
	# Miting yapılan (yerel desteği en yüksek) illerde teşkilat.
	var count := mini(FOUND_ORG_MAX, int(credibility_of(peer_id) / FOUND_ORG_PER_CREDIBILITY))
	var ranked: Array = []
	for province_id in _province_ids:
		var points := float(local_support.get(province_id, {}).get(peer_id, 0.0))
		if points > 0.0:
			ranked.append([points, province_id])
	ranked.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var opened: Array = []
	for i in mini(count, ranked.size()):
		var province_id := String(ranked[i][1])
		if not organizations.has(province_id):
			organizations[province_id] = {}
		if int(organizations[province_id].get(peer_id, 0)) < 1:
			organizations[province_id][peer_id] = 1
			opened.append(_province_name(province_id))
	# Eski partinin teşkilatlarından bir kısmı yeni partiye geçer.
	var former: Dictionary = former_parties.get(peer_id, {})
	var moved := _transfer_former_orgs(peer_id) if not former.is_empty() else [0, 0, 0.0]
	former_parties.erase(peer_id)
	PartyManager.broadcast()
	var text := L.t("%s, %s'yi kurdu. Bağımsızken kazandığı destek yeni partisine geçti.") % [
		PoliticianPresets.display_name(peer_id), info["name"]]
	if int(moved[0]) > 0:
		text += L.t(" %s'nin %d teşkilatından %d tanesi (%%%d) yeni partiye geçti.") % [String(former.get("name", L.t("eski parti"))),
			int(moved[1]), int(moved[0]), int(round(float(moved[2]) * 100.0))]
	if not opened.is_empty():
		text += L.t(" Miting yaptığı illerde teşkilatla başlıyor: %s.") % ", ".join(PackedStringArray(opened))
	_push_state({"type": "party_change", "peer_id": peer_id, "message": text}, true)

func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp

# --- Kongre --------------------------------------------------------------------------
## Parti -> {"elections": son kongreden beri seçim sayısı, "share": son kongredeki
## (ya da bot başkanın göreve geldiği andaki) oy oranı, "member_share": bot başkan
## eski başkandan (oyuncudan) devraldığında partinin oy oranı}.
var party_congress: Dictionary = {}
## Sadece host: süren kongre gösterisinin kalan süresi (bu sürede tur akışı durur).
var _congress_time_left: float = 0.0
## Herkes: kongre gösterisi sürüyor mu (tur akışı durur).
var congress_active: bool = false

const CONGRESS_MAX_ELECTIONS := 3
const CONGRESS_COST := 10
const CONGRESS_REQUEST_COST := 20
const CONGRESS_DELEGATES := 1200
## Gösteri süreleri: oyuncunun partisi seçim gecesinin yarısı, bot partisi dörtte biri.
static func congress_duration(has_human: bool) -> float:
	return (GameRules.ELECTION_NIGHT_SECONDS + GameRules.ELECTION_NIGHT_HOLD) * (0.5 if has_human else 0.25)

func _congress_info(pid: int) -> Dictionary:
	if not party_congress.has(pid):
		party_congress[pid] = {"elections": 0, "share": float(last_vote_shares.get(pid, 0.0))}
	return party_congress[pid]

## Bot, son seçimden olumlu çıktı: sırası gelince kongreye gidecek.
func bot_congress_due(pid: int) -> bool:
	return bool(party_congress.get(pid, {}).get("bot_due", false))

func elections_since_congress(pid: int) -> int:
	return int(party_congress.get(pid, {}).get("elections", 0))

## Genel başkan isteğe bağlı kongreye gidebilir mi? (Son kongreden beri en az
## bir seçim geçmiş olmalı.)
func can_hold_congress(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and PartyManager.is_leader(peer_id) and not PartyManager.is_independent(peer_id) \
		and not is_splinter(peer_id) and elections_since_congress(peer_id) >= 1 and funds_of(peer_id) >= CONGRESS_COST

## Üye (eski başkan) kongre isteyebilir mi? Son kongreden beri bir seçim
## geçmiş olmalı VE bot başkanın döneminde partinin oyu DÜŞMÜŞ olmalı.
func can_request_congress(peer_id: int) -> bool:
	if not can_choose_main_action(peer_id) or not is_party_member(peer_id):
		return false
	var pid := party_of(peer_id)
	return elections_since_congress(pid) >= 1 and funds_of(peer_id) >= CONGRESS_REQUEST_COST and member_vote_drop(pid) > 0.0

## Bot başkanın döneminde partinin oy kaybı (puan; 0 = kayıp yok).
func member_vote_drop(pid: int) -> float:
	var info: Dictionary = party_congress.get(pid, {})
	if not info.has("member_share") or not last_vote_shares.has(pid):
		return 0.0
	return maxf(0.0, float(info["member_share"]) - float(last_vote_shares[pid]))

func can_call_congress(peer_id: int) -> bool:
	return can_hold_congress(peer_id) or can_request_congress(peer_id)

## Neden kongre yapılamıyor? (arayüz)
func congress_block_reason(peer_id: int) -> String:
	var pid := party_of(peer_id)
	if is_party_member(peer_id):
		if elections_since_congress(pid) < 1:
			return L.t("Son kongreden beri seçim olmadı: bir sonraki seçimden sonra isteyebilirsin.")
		if member_vote_drop(pid) <= 0.0:
			return L.t("%s döneminde parti oy kaybetmedi: kongreyi kazanmanın yolu yok.") % PoliticianPresets.display_name(pid)
		if funds_of(peer_id) < CONGRESS_REQUEST_COST:
			return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(CONGRESS_REQUEST_COST)
	elif elections_since_congress(pid) < 1:
		return L.t("Son kongreden beri seçim olmadı.")
	elif funds_of(peer_id) < CONGRESS_COST:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(CONGRESS_COST)
	if not can_choose_main_action(peer_id):
		return L.t("Sıran değil.")
	return ""

## GENEL BAŞKANIN GÜCÜ (0..100): kongrede alacağı delege payının merkezi.
##   50 + son kongreden beri oy değişimi (artışta puan başına +3, en fazla +18;
##   düşüşte puan başına −4) + hükümette +10 (başbakanlık +5) − karışıklık
##   (en fazla −15) + güvenilirlik (−5..+10) − barajın altında 15.
func congress_strength(pid: int) -> float:
	var info := _congress_info(pid)
	var strength := 50.0
	if last_vote_shares.has(pid):
		var change := float(last_vote_shares[pid]) - float(info.get("share", last_vote_shares[pid]))
		strength += minf(18.0, change * 3.0) if change > 0.0 else change * 4.0
		if not passed_threshold.has(pid):
			strength -= 15.0
	if is_government_party(pid):
		strength += 10.0
		if GovernmentManager.main_gov_peer_id == pid:
			strength += 5.0
	strength -= clampf(turmoil_of(pid) * 3.0, 0.0, 15.0)
	strength += lerpf(-5.0, 10.0, credibility_of(pid) / CREDIBILITY_MAX)
	return clampf(strength, 5.0, 95.0)

## Gücüne göre rakip aday sayısı (en fazla 3; başkanla en fazla 4 aday).
func _challenger_count(strength: float) -> int:
	if strength >= 75.0:
		return _rng.randi_range(0, 1)
	if strength >= 55.0:
		return _rng.randi_range(1, 2)
	if strength >= 40.0:
		return _rng.randi_range(2, 3)
	return 3

## KONGRE SONUCU (host önceden hesaplar, herkes animasyonla izler):
## {"pid", "party", "color", "kind", "candidates": [{"name", "background",
##  "peer" (oyuncu/başkan peer'i, yeni bot için -1), "incumbent", "human"}],
##  "round1": [delege], "round2": [] ya da [aday1, aday2, delege1, delege2],
##  "winner": aday indeksi, "strength"}
func _compute_congress(pid: int, kind: String, requester: int = -1) -> Dictionary:
	var strength := congress_strength(pid)
	var candidates: Array = [{"name": PoliticianPresets.display_name(pid), "peer": pid, "incumbent": true,
		"human": not MultiplayerManager.is_bot(pid),
		"background": PoliticianPresets.title(String(PoliticianPresets.of(pid).get("background", "")))}]
	var weights: Array = []
	if requester != -1:
		candidates.append({"name": PoliticianPresets.display_name(requester), "peer": requester, "incumbent": false,
			"human": true, "background": PoliticianPresets.title(String(PoliticianPresets.of(requester).get("background", "")))})
		# Oy düşüşü ne kadar büyükse eski başkanın şansı o kadar yüksek.
		weights.append(2.0 + member_vote_drop(pid) * 0.6 + credibility_of(requester) / CREDIBILITY_MAX)
	var used: Array = PoliticianPresets.used_surnames()
	var extra := _challenger_count(strength) - (1 if requester != -1 else 0)
	for i in maxi(0, extra):
		var person := PoliticianPresets.random_name(used, _rng)
		used.append(String(person["surname"]))
		var background := PoliticianPresets.random_background(_rng)
		candidates.append({"name": "%s %s" % [person["first_name"], person["surname"]], "peer": -1, "incumbent": false,
			"human": false, "background": PoliticianPresets.title(background), "_person": person, "_background": background})
		weights.append(_rng.randf_range(0.6, 1.4))
	var round1: Array = []
	var incumbent_share := clampf(strength + _rng.randf_range(-8.0, 8.0), 5.0, 92.0) if candidates.size() > 1 else 100.0
	round1.append(incumbent_share)
	var total_weight := 0.0
	for w in weights:
		total_weight += float(w)
	for w in weights:
		round1.append((100.0 - incumbent_share) * float(w) / maxf(0.001, total_weight))
	var delegates := _to_delegates(round1)
	var result := {"pid": pid, "party": _party_name(pid), "color": PartyManager.data_of(pid).get("bg_color", Color.GRAY),
		"kind": kind, "candidates": candidates, "round1": delegates, "round2": [], "strength": strength}
	var order: Array = range(candidates.size())
	order.sort_custom(func(a, b): return int(delegates[a]) > int(delegates[b]))
	if int(delegates[order[0]]) * 2 > CONGRESS_DELEGATES:
		result["winner"] = int(order[0])
		return result
	# 2. TUR: ilk iki aday. Elenenlerin delegeleri bölünür; başkan güç
	# oranında pay alır.
	var a := int(order[0])
	var b := int(order[1])
	var freed := 0
	for i in candidates.size():
		if i != a and i != b:
			freed += int(delegates[i])
	var a_take := strength / 100.0 if a == 0 else (1.0 - strength / 100.0 if b == 0 else 0.5)
	a_take = clampf(a_take + _rng.randf_range(-0.1, 0.1), 0.05, 0.95)
	var da := int(delegates[a]) + int(round(freed * a_take))
	var db := CONGRESS_DELEGATES - da
	if da == db:
		da += 1 if a == 0 else -1
		db = CONGRESS_DELEGATES - da
	result["round2"] = [a, b, da, db]
	result["winner"] = a if da > db else b
	return result

func _to_delegates(percents: Array) -> Array:
	var out: Array = []
	var sum := 0
	for p in percents:
		var n := int(round(float(p) / 100.0 * CONGRESS_DELEGATES))
		out.append(n)
		sum += n
	if not out.is_empty():
		out[0] = int(out[0]) + CONGRESS_DELEGATES - sum
	return out

## Kongre: hamle (başkan ya da üye ister) ya da zorunlu (otomatik).
func _apply_congress(peer_id: int) -> void:
	if can_hold_congress(peer_id):
		funds[peer_id] = funds_of(peer_id) - CONGRESS_COST
		_run_congress(peer_id, "voluntary")
	elif can_request_congress(peer_id):
		funds[peer_id] = funds_of(peer_id) - CONGRESS_REQUEST_COST
		_run_congress(party_of(peer_id), "request", peer_id)

## Sırası gelen partinin başkanı CONGRESS_MAX_ELECTIONS seçimdir kongreye
## gitmediyse kongre kendiliğinden başlar.
func _maybe_mandatory_congress() -> void:
	var peer_id := current_turn_peer_id()
	if peer_id == -1 or game_finished or congress_active or not PartyManager.is_leader(peer_id):
		return
	if PartyManager.is_independent(peer_id) or is_splinter(peer_id) or bool(PartyManager.data_of(peer_id).get("temporary", false)):
		return
	if elections_since_congress(peer_id) >= CONGRESS_MAX_ELECTIONS:
		_run_congress(peer_id, "mandatory")

func _run_congress(pid: int, kind: String, requester: int = -1) -> void:
	var result := _compute_congress(pid, kind, requester)
	var candidates: Array = result["candidates"]
	var winner: Dictionary = candidates[int(result["winner"])]
	var party_name := String(result["party"])
	var old_leader := pid
	var member := PartyManager.deputy_of(pid)
	var has_human := not MultiplayerManager.is_bot(pid) or member != -1
	var text := ""
	if bool(winner.get("incumbent", false)):
		text = L.t("%s KONGRESİ: %s genel başkanlığını korudu.") % [party_name, PoliticianPresets.display_name(pid)]
		_congress_info(pid)["elections"] = 0
		_congress_info(pid).erase("bot_due")
		_congress_info(pid)["share"] = float(last_vote_shares.get(pid, 0.0))
		if requester != -1:
			text += L.t(" Kongre isteyen %s kaybetti.") % PoliticianPresets.display_name(requester)
	elif int(winner.get("peer", -1)) == requester and requester != -1:
		# Eski başkan (oyuncu) geri döndü: bot başkan siyasetten çekilir.
		_rekey_party(old_leader, requester, -1)
		_remove_bot_leader(old_leader)
		_congress_info(requester)["elections"] = 0
		_congress_info(requester)["share"] = float(last_vote_shares.get(requester, 0.0))
		_congress_info(requester).erase("member_share")
		text = L.t("%s KONGRESİ: %s genel başkanlığa geri döndü!") % [party_name, PoliticianPresets.display_name(requester)]
	else:
		var person: Dictionary = winner["_person"]
		var new_politician := PoliticianPresets.make(person["first_name"], person["surname"], String(winner["_background"]),
			String(_province_ids[_rng.randi() % _province_ids.size()]) if not _province_ids.is_empty() else "", person["gender"])
		if MultiplayerManager.is_bot(old_leader):
			# Bot başkan değişti: aynı bot yeni bir siyasetçi olur.
			PartyManager.set_politician_host(old_leader, new_politician)
			GovernmentManager.scores[old_leader] = 0
			credibility[old_leader] = CREDIBILITY_START
			_congress_info(old_leader)["elections"] = 0
			_congress_info(old_leader)["share"] = float(last_vote_shares.get(old_leader, 0.0))
			text = L.t("%s KONGRESİ: %s yeni genel başkan seçildi.") % [party_name, PoliticianPresets.display_name(old_leader)]
		else:
			# Oyuncu başkanlığı kaybetti: yeni bot başkan gelir, oyuncu ÜYE olur.
			var bot := MultiplayerManager.add_splinter_bot(String(winner["name"]))
			PartyManager.set_politician_host(bot, new_politician)
			turn_order.append(bot)
			_place_after(bot, old_leader)
			inventories[bot] = []
			funds[bot] = float(GameRules.FUNDS_PER_ROUND)
			credibility[bot] = CREDIBILITY_START
			var share := float(last_vote_shares.get(old_leader, 0.0))
			_rekey_party(old_leader, bot, old_leader)
			_congress_info(bot)["elections"] = 0
			_congress_info(bot)["share"] = share
			_congress_info(bot)["member_share"] = share
			text = L.t("%s KONGRESİ: %s genel başkanlığı kaybetti! Yeni genel başkan %s. %s partide üye olarak kalıyor.") % [
				party_name, PoliticianPresets.display_name(old_leader), PoliticianPresets.display_name(bot),
				PoliticianPresets.display_name(old_leader)]
	for key in party_congress.keys():
		if int(key) == pid or int(key) == party_of(pid):
			party_congress[key].erase("bot_due")
	# Gösteri herkesin ekranında oynar; o süre boyunca tur akışı durur.
	var duration := congress_duration(has_human)
	_congress_time_left = duration
	congress_active = true
	var show := result.duplicate(true)
	for c in show["candidates"]:
		c.erase("_person")
		c.erase("_background")
	show["duration"] = duration
	PartyManager.broadcast()
	_push_state({"type": "congress", "peer_id": int(result["pid"]) if PartyManager.parties.has(int(result["pid"])) else -1,
		"congress": show, "message": text}, true)

## YENİDEN KATILMA: oyuncunun bütün kayıtları eski peer id'den yenisine taşınır.
func rekey_player(old_id: int, new_id: int) -> void:
	if PartyManager.parties.has(old_id):
		_rekey_party(old_id, new_id, PartyManager.deputy_of(old_id))
	else:
		for pid in PartyManager.parties.keys():
			if int(PartyManager.parties[pid].get("deputy", -1)) == old_id:
				PartyManager.parties[pid]["deputy"] = new_id
	if PartyManager.politicians.has(old_id):
		PartyManager.politicians[new_id] = PartyManager.politicians[old_id]
		PartyManager.politicians.erase(old_id)
	var idx := turn_order.find(old_id)
	if idx != -1:
		turn_order[idx] = new_id
	for table in [funds, inventories, credibility]:
		if table.has(old_id):
			table[new_id] = table[old_id]
			table.erase(old_id)
	for table in [GovernmentManager.scores, GovernmentManager.votes]:
		if table.has(old_id):
			table[new_id] = table[old_id]
			table.erase(old_id)

## Host: tek bir istemciye tam oyun durumu (yeniden katılan oyuncu).
func send_full_state(peer_id: int) -> void:
	if MultiplayerManager.is_host and not _is_local_only():
		_receive_state.rpc_id(peer_id, _pack_state(true), {"type": "full"})

## Kongreyi kaybeden bot başkan oyundan çıkar (parti oyuncuya döndü).
func _remove_bot_leader(bot: int) -> void:
	for table in [inventories, funds, credibility]:
		table.erase(bot)
	var idx := turn_order.find(bot)
	if idx != -1:
		_remove_from_turn_order(idx)
	PartyManager.politicians.erase(bot)
	MultiplayerManager.remove_splinter_bot(bot)

## Seçimden sonra: her partinin son kongreden beri geçen seçim sayısı artar.
func _count_congress_elections() -> void:
	for pid in party_ids():
		if PartyManager.is_independent(int(pid)):
			continue
		var info := _congress_info(int(pid))
		info["elections"] = int(info.get("elections", 0)) + 1
		# BOT, SEÇİMDEN OLUMLU ÇIKTIYSA (oyu arttıysa) sırası gelince kongreye
		# gider: başarının ardından iktidarını tazeler.
		var gained := float(last_vote_shares.get(pid, 0.0)) > float(previous_vote_shares.get(pid, INF))
		info["bot_due"] = MultiplayerManager.is_bot(int(pid)) and gained

## Kongre gösterisi bitti: tur akışı yeniden başlar.
func _finish_congress_show() -> void:
	_congress_time_left = 0.0
	congress_active = false
	_push_state({"type": "congress_end"})

## Sıradaki yerini değiştirir: peer, anchor'un hemen ardından oynar.
func _place_after(peer_id: int, anchor: int) -> void:
	var current := current_turn_peer_id()
	var idx := turn_order.find(peer_id)
	if idx == -1:
		return
	turn_order.remove_at(idx)
	turn_order.insert(turn_order.find(anchor) + 1, peer_id)
	var now := turn_order.find(current)
	if now != -1:
		current_turn_index = now

func _remove_from_turn_order(idx: int) -> void:
	var was_current := idx == current_turn_index
	turn_order.remove_at(idx)
	if idx < current_turn_index:
		current_turn_index -= 1
	elif was_current:
		_turn_time_left = GameRules.TURN_TIMEOUT
		if current_turn_index >= turn_order.size():
			current_turn_index = 0

## PARTİ ANAHTARI DEĞİŞİR (genel başkan değişti): partiye ait bütün kayıtlar
## old_id'den new_id'ye taşınır. new_member: partide kalan üye (-1: yok).
func _rekey_party(old_id: int, new_id: int, new_member: int) -> void:
	var data: Dictionary = PartyManager.parties.get(old_id, {}).duplicate()
	data.erase("deputy")
	if new_member != -1:
		data["deputy"] = new_member
	PartyManager.parties.erase(old_id)
	PartyManager.parties[new_id] = data
	for table in [national_support, populism, turmoil, law_rounds, speech_rounds, congress_rounds,
			group_meetings, miting_fatigue, election_groups,
			national_list, last_seats, election_seats, last_vote_shares, previous_vote_shares, party_congress]:
		if table.has(old_id):
			table[new_id] = table[old_id]
			table.erase(old_id)
	var t := passed_threshold.find(old_id)
	if t != -1:
		passed_threshold[t] = new_id
	for nested in [last_province_results, local_support, organizations]:
		for province_id in nested.keys():
			var entry: Dictionary = nested[province_id]
			if entry.has(old_id):
				entry[new_id] = entry[old_id]
				entry.erase(old_id)
	if splinters.has(old_id):
		splinters[new_id] = splinters[old_id]
		splinters.erase(old_id)
	for politician in former_parties.keys():
		if int(former_parties[politician].get("party", -1)) == old_id:
			former_parties[politician]["party"] = new_id
	for entry in economy.get("ledger", []):
		if int(entry.get("party", -1)) == old_id:
			entry["party"] = new_id
	var inquiries: Dictionary = economy.get("inquiries", {})
	if inquiries.has(old_id):
		inquiries[new_id] = inquiries[old_id]
		inquiries.erase(old_id)
	for entry in economy.get("investments", []):
		if int(entry.get("party", -1)) == old_id:
			entry["party"] = new_id
		var amounts: Dictionary = entry.get("amounts", {})
		if amounts.has(old_id):
			amounts[new_id] = amounts[old_id]
			amounts.erase(old_id)
	for splinter in splinters.keys():
		if int(splinters[splinter].get("parent", -1)) == old_id:
			splinters[splinter]["parent"] = new_id
	GovernmentManager.rekey_party(old_id, new_id)

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
		"speech_rounds": speech_rounds,
		"congress_rounds": congress_rounds,
		"previous_vote_shares": previous_vote_shares,
		"party_congress": party_congress,
		"congress_active": congress_active,
		"agenda": agenda,
		"crisis": crisis,
		"national_list": national_list,
		"round": round_number,
		"turn_time_left": _turn_time_left,
		"last_election_round": last_election_round,
		"early": last_election_was_early,
		"vote_shares": last_vote_shares,
		"credibility": credibility,
		"music_track": music_track,
		"seats": last_seats,
		"election_seats": election_seats,
		"early_election_pending": early_election_pending,
		"election_anchor": election_anchor,
		"passed": passed_threshold,
		"national": national_support,
		"local": local_support,
		"events": province_events,
		"organizations": organizations,
		"province_profiles": province_profiles,
		"group_meetings": group_meetings,
		"miting_fatigue": miting_fatigue,
		"election_groups": election_groups,
		"former_parties": former_parties,
		"economy": economy,
		"funds": funds,
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
	# 0.0.166 öncesi kart adları ("mana_bonusu" → bağış kampanyası).
	for owner in inventories.keys():
		var hand: Array = inventories[owner]
		for i in hand.size():
			hand[i] = OLD_CARD_TYPES.get(String(hand[i]), hand[i])
	turn_order = state["turn_order"]
	current_turn_index = int(state["turn_index"])
	law_rounds = state.get("law_rounds", {})
	populism = state.get("populism", {})
	splinters = state.get("splinters", {})
	speech_done = bool(state.get("speech_done", false))
	speech_rounds = state.get("speech_rounds", {})
	congress_rounds = state.get("congress_rounds", {})
	previous_vote_shares = state.get("previous_vote_shares", {})
	party_congress = state.get("party_congress", {})
	congress_active = bool(state.get("congress_active", false))
	agenda = state.get("agenda", {})
	crisis = state.get("crisis", {})
	national_list = state.get("national_list", {})
	round_number = int(state["round"])
	_turn_deadline_ms = Time.get_ticks_msec() + int(float(state["turn_time_left"]) * 1000.0)
	last_election_round = int(state["last_election_round"])
	last_election_was_early = bool(state["early"])
	last_vote_shares = state["vote_shares"]
	credibility = state.get("credibility", {})
	music_track = String(state.get("music_track", "game"))
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
	group_meetings = state.get("group_meetings", {})
	miting_fatigue = state.get("miting_fatigue", {})
	election_groups = state.get("election_groups", {})
	former_parties = state.get("former_parties", {})
	# Eski sürüm durumunda ekonomi yoktur: güvenli başlangıç değerleri.
	economy = Economy.normalized(state.get("economy", {}))
	# PARTİ KASASI (milyon ₺). 0.0.166 öncesi durumda alan "mana" adındaydı;
	# para ölçeği eski değerlerle birebir kurulduğu için (bkz. GameRules) değer
	# aynen taşınır. İkisi de yoksa boş başlar (herkes 0).
	funds = state.get("funds", state.get("mana", {}))
	game_finished = bool(state["game_finished"])
	final_ranking = state["final_ranking"]
	game_end_reason = str(state["end_reason"])
	if state.has("map") and int((state["map"] as Dictionary).get("seed", -1)) != GameMap.seed_value():
		GameMap.set_data(state["map"])
	# Vekil sayıları HER durumda haritadan yeniden okunur: istemci haritayı aynı
	# tohumla kendisi üretince (seed eşit) bu tablo açılıştaki varsayılan
	# haritadan kalıyordu, her oyuncu ilde farklı vekil sayısı görüyordu.
	if state.has("map") or _province_seat_counts.size() != GameMap.province_ids().size():
		_load_province_seat_counts()
	if state.has("province_results"):
		last_province_results = state["province_results"]
	# Eski sürüm (ideoloji eksenli) bir host'un durumu sessizce yeni profillere
	# eşlenmez: geçersiz profiller hiç alınmaz (bkz. VoterGroups.is_valid_profile).
	if state.has("province_profiles") and _valid_profiles(state["province_profiles"]):
		province_profiles = state["province_profiles"]

static func _valid_profiles(profiles) -> bool:
	if not profiles is Dictionary:
		return false
	for province_id in profiles.keys():
		if not VoterGroups.is_valid_profile(profiles[province_id]):
			return false
	return true

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
	if not _pending_econ.is_empty():
		event = event.duplicate()
		if not event.has("econ"):
			event["econ"] = _pending_econ
		_pending_econ = {}
	state_version += 1
	if not _is_local_only():
		_receive_state.rpc(_pack_state(include_results or event.get("type", "") in ["full", "election", "player_left", "player_away", "player_back", "party_split", "party_merge", "party_change"]), event)
	_emit_post_event(event)

func _emit_post_event(event: Dictionary) -> void:
	var type: String = event.get("type", "")
	# Seçim: ekran ÖNCE donsun (bkz. GameScreen._on_election_completed), sonra
	# paneller güncellensin — yoksa sonuç bir an önceden görünüyordu.
	if type == "election":
		election_completed.emit()
	if type == "congress":
		congress_started.emit(event.get("congress", {}))
	inventories_updated.emit()
	if type in ["full", "player_left", "player_away", "player_back", "party_split", "party_merge", "party_change"]:
		turn_order_updated.emit()
	turn_changed.emit(current_turn_peer_id())
	opinion_changed.emit()
	match type:
		"round":
			round_advanced.emit()
		"game_over":
			game_over.emit()
		"full", "player_left", "party_split", "party_merge", "party_change":
			seats_changed.emit()
		"played":
			if bool(event.get("seats_changed", false)):
				seats_changed.emit()
	if type == "full" and round_number == 1 and last_election_round == 0:
		event_log.clear()  # yeni oyun (istemci tarafı)
	if event.has("econ"):
		economy_event.emit(event["econ"])
	if event.has("inquiry"):
		inquiry_resolved.emit(event["inquiry"])
	if event.has("message"):
		opinion_event.emit(str(event["message"]))
		log_event(str(event["message"]), int(event.get("peer_id", -1)), String(event.get("province", "")), _log_kind(event))
	for extra in event.get("extra_log", []):
		log_event(String(extra["text"]), int(extra["peer_id"]), String(extra["province"]), String(extra["kind"]))
	match type:
		"round":
			log_event(L.t("%s başladı.") % GameRules.period_label(round_number), -1, "", "round")
		"election":
			log_event(L.t("%d genel seçimi yapıldı.") % GameRules.election_year(last_election_round), -1, "", "election")
			var mine := party_of(multiplayer.get_unique_id())
			var trend := election_trend(mine)
			if trend != "":
				log_event(trend, mine, "", "election")

@rpc("authority", "reliable")
func _receive_state(state: Dictionary, event: Dictionary) -> void:
	# Animasyon sinyalleri ESKİ state üzerinden kurulsun diye önce bunlar.
	if event.has("dealt"):
		var dealt: Dictionary = event["dealt"]
		card_drawn.emit(int(dealt["peer_id"]), str(dealt["card"]))
	match str(event.get("type", "")):
		"played":
			var shown := -1 if event.has("actor_hidden") else int(event["peer_id"])
			card_played.emit(shown, str(event["card"]))
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
func _request_invest(province_id: String, state: float = 1.0) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_invest_move(multiplayer.get_remote_sender_id(), province_id, state)

@rpc("any_peer", "reliable")
func _request_censure() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_censure_move(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _request_miting(province_id: String, state: float = 0.0) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_miting_move(multiplayer.get_remote_sender_id(), province_id, state)

@rpc("any_peer", "reliable")
func _request_pass() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_pass(multiplayer.get_remote_sender_id(), true)
