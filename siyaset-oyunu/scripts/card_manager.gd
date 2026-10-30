extends Node
## Autoload. Kart envanteri, oynama sırası, PARA ve hamleler, tur/seçim döngüsü,
## seçim sonuçları, İLLERİN SEÇMEN PROFİLİ, AKTİVİTE (il puanı
## + il başkanlığı), oyuncuya
## özel istihbarat (anket/gözcü) ve oyun sonu. Host yetkili: host-olmayan
## istemcinin isteği önce host'a "any_peer" RPC ile gider, host doğrulayıp
## uygular ve herkese yayınlar.
##
## TUR AKIŞI (bir oyuncunun sırası):
##   a) KART OYNA: elden saklanabilir bir kart oyna (kartların bedeli yok).
##   b) YASA TASARLA (GameRules.LAW_FUNDS_COST): meclise yasa sun; meclis yoksa
##      oylamasız SEÇİM VAADİ olur.
##   c) TEŞKİLATLANMA (GameRules.ORG_FUNDS_COST): bir ilde teşkilat kur / geliştir
##      (oy bonusu + seviyeye göre anket).
##   d) PAS: hamle yapmadan geç, +GameRules.FUNDS_PASS_BONUS para.
##   KART: sıra başında KART ÇEK (bkz. TUR AKIŞI); kart oynamak sınırsız. Her seçimden sonra herkese 1 kart hediye.
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
## SUNUM: her olay (host'ta ve istemcide) uygulandıktan SONRA bir kez; sürüm
## numarası olayın kimliğidir (EventFx aynı olayı iki kez oynatmaz).
signal event_presented(event: Dictionary, version: int)
## Kongre gösterisi başlıyor (herkes): data = CardManager._compute_congress sonucu.
signal congress_started(data: Dictionary)
## EKONOMİ OLAYI (herkeste): {"kind": "tax", "from", "to"} vergi değişti,
## {"kind": "invest", "peer_id", "province", "cost", "before", "after"} hazineden
## yatırım, {"kind": "round", "revenue"} tur sonu geliri. Arayüz bununla
## hazine/gösterge animasyonlarını oynatır (değerler zaten durumda).
signal economy_event(data: Dictionary)

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
const WEIGHT_STEAL_WEAK := 15.0
const WEIGHT_FUNDS_BONUS := 12.0
const WEIGHT_FUNDS_BONUS_STRONG := 6.0
## Olumsuz / esnek şans kartları (0.0.232).
const WEIGHT_PENALTY := 8.0
const WEIGHT_SELF_TURMOIL := 6.0
const WEIGHT_FLEX := 8.0
const WEIGHT_POLL := 8.0
const WEIGHT_CARD_THEFT := 6.0
const WEIGHT_POPULISM := 12.0
const WEIGHT_STEAL_STRONG := 9.0
const WEIGHT_EARLY_ELECTION := 6.0
const WEIGHT_REPUTATION := 3.0
const WEIGHT_REBELLION := 18.0

## Meclis: haritadaki bölgelerin vekilleri (ProvinceLayout.PROVINCE_SEATS)
## + ulusal liste. Harita yüklenince yeniden hesaplanır.
var TOTAL_SEATS := 500

## Seçim ittifakları (lobi ayarı, varsayılan açık; anayasa ile değişebilir).
## id -> {name, color, leader: party id, members: party ids}. Bkz. alliance_of.
var alliances_enabled: bool = true
var alliances: Dictionary = {}
## Açık başvurular: id -> {alliance, party, kind: "invite"|"request", round,
## accepted (davet edilen kabul etti mi), voters: party ids, votes: party -> bool}.
var alliance_requests: Dictionary = {}
var _next_alliance_request: int = 0
## Son seçimdeki ittifak ortakları: party -> Array[party] (botların dostluğu).
var former_allies: Dictionary = {}
## Son seçime giren ittifaklar (seçim gecesi ve sonuçlar için; seçimle dağılırlar).
var last_election_alliances: Dictionary = {}

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
## 0.0.185: yasa hakları AYRI: grup yasası (law_rounds), vergi yasası ve
## anayasa değişikliği her biri dönemde bir; aynı turda üçü de sunulabilir.
var tax_rounds: Dictionary = {}
var constitution_rounds: Dictionary = {}
## Popülizm bonusu: peer_id -> bittiği tur (o turdan önceki son tura kadar sürer).
var populism: Dictionary = {}
## KARIŞIKLIK (GİZLİ, sadece host; oyunculara hiç gösterilmez): peer_id -> puan.
## Kaset ve iç karışıklık kartları büyütür; olumlu hamleler ve zaman söndürür.
## PublicOpinion.SPLIT_TURMOIL'i aşan parti BÖLÜNÜR (bkz. _check_splits).
var turmoil: Dictionary = {}
## BÖLÜNEN PARTİLER: ayrılan (yapay zekâ) partinin peer_id -> {"parent": ana parti,
## "elections": ayrıldıktan sonra atlattığı seçim, "since": ayrıldığı tur}.
var splinters: Dictionary = {}
## ERKEN SEÇİM önergesi bedelsiz (0.0.182): parti başına bir seçim aralığında
## (GameRules.ELECTION_INTERVAL tur) bir önerge. parti -> önerge turu.
var early_requests: Dictionary = {}
## Parti -> kongre yapıldığı son dönem (dönemde bir kongre).
var congress_rounds: Dictionary = {}
## Bir önceki seçimin oy oranları (kongrede "oy kaybı" ölçüsü).
var previous_vote_shares: Dictionary = {}
## MİTİNG YORGUNLUĞU (azalan getiri): parti -> {grup -> birikmiş kazanç}.
## Her tur sonunda PublicOpinion.MITING_FATIGUE_DECAY ile söner.
var miting_fatigue: Dictionary = {}
## Son seçim anındaki grup yakınlıkları: parti -> {grup -> değer} (arayüzde
## "son seçimden beri" değişimi göstermek için).
var election_groups: Dictionary = {}
## SİYASİ KRİZ (0.0.259; eskiden "gündem"): {"type": "kriz_<grup>", "until":
## bittiği tur} (boş = kriz yok). Eski kayıtlardaki "gundem_<grup>" de okunur.
var agenda: Dictionary = {}
## KRİZ: {"type": "kriz_<grup>", "until": tur}. Gündemle birlikte açılır.
var crisis: Dictionary = {}
## ANKET KARTI (0.0.272): peer -> {"round", "parties": {pid: {"percent", "seats"}}}.
## Çekildiği anın görüntüsü (değişmez); seçimde sıfırlanır. Yalnız sahibi görür.
var polls: Dictionary = {}
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
## Erken seçimden sonra takvim TAMAMEN kayar: kalan seçim sayısı korunur, son
## seçim de aralık kadar ileri gider (oyun uzar). 0 = lobi ayarındaki uzunluk.
var max_rounds_override: int = 0
## Son seçimin girdileri (sadece host/yerel; denge analizi için, senkronlanmaz).
var last_election_inputs: Dictionary = {}

## GÜÇ (bkz. PublicOpinion)
# peer_id -> float
var _secret_news: Array = []
# province_id -> { peer_id -> float }  — sönen il puanı (aktivitenin bir parçası)
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
## AFET (bkz. Disaster): {"active": {} ya da {"id", "kind", "provinces",
## "round", "aid": {parti: toplam milyon ¤}}, "term_count": bu seçim
## döneminde çıkan afet, "owed": önceki dönemde hiç çıkmadı (garanti),
## "next_id"}.
var disaster: Dictionary = {}
## HÜKÜMET ONAYI (bkz. PublicOpinion.APPROVAL_*): {"value", "delta", "history",
## "pending": [{"text", "amount"}]}. Hükümet kurulunca start_approval başlatır.
var approval: Dictionary = {}
## YATIRIM İSTEKLERİ: province_id -> {"amount": milyon ¤, "done": bool}. Tur
## sonunda karşılanmayanlar cezalandırılır, sonra yeni tur için yenileri seçilir.
var invest_requests: Dictionary = {}
## Tur başında çıkan afetin gazete bilgisi (sonraki _push_state olaya ekler).
var _pending_disaster_fx: Dictionary = {}
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
## OYUN GÜNLÜĞÜ (0.0.227): bütün olaylar (gizli türler dahil) ve seçim sonuçları;
## ESC menüsündeki "LOG İNDİR" bunu dosyaya yazar (bkz. GameLog).
var full_log: PackedStringArray = PackedStringArray()
## Testler için: 0 değilse init_game her seferinde bu tohumla aynı haritayı kurar.
var fixed_map_seed: int = 0

# Seçim hesabına giren iller ve koltuk sayıları (yetkili kaynak GameMap).
var _province_ids: Array = []
var _province_seat_counts: Dictionary = {}

var _turn_time_left: float = GameRules.TURN_TIMEOUT
var _turn_deadline_ms: int = 0
## Son durumla gelen kalan süre (oylama gibi engellerde sayaç bunda durur).
var _turn_time_synced: float = GameRules.TURN_TIMEOUT
var _round_end_pending: bool = false
## Son turun seçimi yapıldı: hükümet kurulunca (ya da kurulamayınca) oyun biter.
var final_election_pending: bool = false
var _heartbeat_timer: float = 0.0
## Son hamlenin herkese duyurulacak mesajı.
var _event_message: String = ""
## Bölünme/birleşme gibi ek log kayıtları: bir sonraki state olayına iliştirilir.
var _pending_log: Array = []
var _rng := RandomNumberGenerator.new()

# --- TUR AKIŞI (0.0.231) ----------------------------------------------------------
## Sıranın başı: KART ÇEK (sırada tek sefer) → varsa AFET YARDIM kararı →
## serbest tur (haritadaki il paneli, MECLİS akışı, ittifak, Turu Bitir).
## Durum host'ta tutulur ve yayılır (istemci kendi kararını bundan okur):
##   turn_flow = {"serial", "peer", "drawn", "draws": [{card, result}],
##     "intro_left": çekim beklenirken kalan sunum süresi (tur sayacı durur),
##     "aid_for": bu sırada karar verilen afet id'si, "parl_closed": kapanan
##     meclis aşamaları, "mitings", "invests": bu sıradaki başarılı hamleler}.
## MECLİS SEKMELERİ (0.0.246) PARL_STAGES: sıra yok, oyuncu istediği sekmeden
## başlar. Bir sekmenin hamlesi yapılınca (gensoru verildi,
## yasa / anayasa / erken seçim sunuldu) o sekme bu sıra kapanır, yeniden
## açılmaz. Botlar bir sekmeyi "geç" ile de kapatabilir (_apply_parl_pass).
## enforce_turn_flow: testler eski serbest akışa dönebilsin (çekim zorunluluğu
## ve meclis sırası uygulanmaz); miting / yatırım sınırı her zaman geçerli.
const PARL_STAGES := ["censure", "law"]
## Çekim bekleyen oyuncunun sunum süresi: bu sürede tur sayacı işlemez; dolunca
## kart kendiliğinden çekilir (AFK açığı yok).
const INTRO_TIMEOUT := 15.0
## Kart açılış ve afet sahnesi animasyonları karar süresinden yemesin.
const DRAW_GRACE_SECONDS := 4.0
## Sıra başına miting / yatırım sınırı lobi ayarıdır (world_settings
## "action_limit", 3..7, varsayılan 5); ESNEK HAREKET kartı o sıra iki katına çıkarır.
## MİTİNG BÜTÇESİ: küçük / orta (eski 15 milyon miting) / büyük. Küçük para
## başına en verimli, büyük tek hamlede en güçlü (3 hak sınırı varken değerli).
const MITING_TIERS := [{"cost": 10.0, "mult": 0.7}, {"cost": 15.0, "mult": 1.0}, {"cost": 25.0, "mult": 1.4}]
## YATIRIM BÜTÇESİ: 50 / 100 (eski yatırım) / 150 milyon; etki tutarla orantılı
## (il puanı tavanı büyük yatırımın getirisini sınırlar).
const INVEST_TIERS := [{"cost": 50.0}, {"cost": 100.0}, {"cost": 150.0}]
const DEFAULT_TIER := 1
var enforce_turn_flow := true
## Son seçimin hediye kartları (host; testler ve günlük için): peer -> çekimler.
var last_gift_draws: Dictionary = {}

## Çekimlerdeki anında para kartlarının bu oyuncunun kasasına net etkisi (testler).
func instant_funds_of(peer_id: int, draws: Array) -> float:
	var total := 0.0
	for entry in draws:
		if String(entry.get("result", "")) == "instant":
			match String(entry.get("card", "")):
				CardPresets.FUNDS_BONUS_CARD_TYPE:
					total += funds_bonus_amount(peer_id, false)
				CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE:
					total += funds_bonus_amount(peer_id, true)
				CardPresets.PENALTY_CARD_TYPE:
					total -= float(entry.get("amount", 0.0))
	return total
var turn_flow: Dictionary = {}
var _turn_serial := 0
var _skip_stage_gate := false

## Çekildiği anda uygulanan kartlar (ele girmez, oynama bedeli yok).
static func is_instant_card(card_type: String) -> bool:
	return card_type in [CardPresets.POPULISM_CARD_TYPE, CardPresets.FUNDS_BONUS_CARD_TYPE,
		CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE, CardPresets.PENALTY_CARD_TYPE,
		CardPresets.SELF_TURMOIL_CARD_TYPE, CardPresets.FLEX_CARD_TYPE]

## Olumsuz şans kartı mı? (Sunumda kırmızı.)
static func is_negative_card(card_type: String) -> bool:
	return card_type in [CardPresets.PENALTY_CARD_TYPE, CardPresets.SELF_TURMOIL_CARD_TYPE]

static func miting_tier_cost(tier: int) -> float:
	return float(MITING_TIERS[clampi(tier, 0, MITING_TIERS.size() - 1)]["cost"])

static func miting_tier_mult(tier: int) -> float:
	return float(MITING_TIERS[clampi(tier, 0, MITING_TIERS.size() - 1)]["mult"])

static func invest_tier_cost(tier: int) -> float:
	return float(INVEST_TIERS[clampi(tier, 0, INVEST_TIERS.size() - 1)]["cost"])

static func valid_tier(tier: int) -> bool:
	return tier >= 0 and tier < MITING_TIERS.size()

## Yeni sıra başladı (host): akış sıfırlanır. Kart almayan üye çekim yapmaz.
func _start_turn_flow(peer_id: int) -> void:
	_turn_serial += 1
	turn_flow = {"serial": _turn_serial, "peer": peer_id, "drawn": peer_id == -1 or is_party_member(peer_id),
		"draws": [], "intro_left": INTRO_TIMEOUT, "aid_for": -1, "parl_closed": [], "mitings": 0, "invests": 0}

## Bu oyuncunun sırasının akışı (yoksa oluşturur). Sıra başında kurulmamış
## akış (eski kayıt, test) çekim hakkını kullanılmış sayar: çift kart olmaz.
func _flow_for(peer_id: int) -> Dictionary:
	if int(turn_flow.get("peer", -1)) != peer_id:
		_turn_serial += 1
		turn_flow = {"serial": _turn_serial, "peer": peer_id, "drawn": true, "draws": [], "intro_left": 0.0,
			"aid_for": -1, "parl_closed": [], "mitings": 0, "invests": 0}
	return turn_flow

func _flow_value(peer_id: int, key: String, default: Variant) -> Variant:
	if int(turn_flow.get("peer", -1)) != peer_id:
		return default
	return turn_flow.get(key, default)

## Sırası gelen oyuncu henüz kart çekmedi mi? (KART ÇEK düğmesi.)
func needs_turn_draw(peer_id: int) -> bool:
	return enforce_turn_flow and peer_id == current_turn_peer_id() and not game_finished and not is_turn_blocked() \
		and int(turn_flow.get("peer", -1)) == peer_id and not bool(turn_flow.get("drawn", true))

func turn_draws(peer_id: int) -> Array:
	return _flow_value(peer_id, "draws", [])

## Bu oyuncunun bu sıradaki miting (ve ayrıca yatırım) sınırı.
func action_limit(peer_id: int) -> int:
	var base := int(MultiplayerManager.world_settings.get("action_limit", MultiplayerManager.WORLD_DEFAULTS["action_limit"]))
	return base * (2 if bool(_flow_value(peer_id, "flex", false)) else 1)

func miting_count(peer_id: int) -> int:
	return int(_flow_value(peer_id, "mitings", 0))

func invest_count(peer_id: int) -> int:
	return int(_flow_value(peer_id, "invests", 0))

func draw_turn_card() -> void:
	var me := multiplayer.get_unique_id()
	if not needs_turn_draw(me):
		return
	if _is_authority():
		_apply_draw(me)
	else:
		_request_draw.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_draw() -> void:
	if MultiplayerManager.is_host:
		_apply_draw(multiplayer.get_remote_sender_id())

## ATLA: oyuncu bu sıra kart çekmekten vazgeçer (çekim hakkı kullanılmış sayılır).
func skip_turn_draw() -> void:
	var me := multiplayer.get_unique_id()
	if not needs_turn_draw(me):
		return
	if _is_authority():
		_apply_skip_draw(me)
	else:
		_request_skip_draw.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_skip_draw() -> void:
	if MultiplayerManager.is_host:
		_apply_skip_draw(multiplayer.get_remote_sender_id())

func _apply_skip_draw(peer_id: int) -> void:
	if not needs_turn_draw(peer_id):
		return
	turn_flow["drawn"] = true
	turn_flow["draws"] = []
	_push_state({"type": "draw", "peer_id": peer_id, "draws": []})

## KART ÇEKİMİ (host): sırada tek sefer. Anında kart hemen uygulanır, saklanabilir
## kart ele girer. El doluysa (eski kural) kart çekilmez. automatic: süre doldu
## ya da tur çekmeden bitti (sunum payı eklenmez).
func _apply_draw(peer_id: int, automatic: bool = false) -> void:
	if not needs_turn_draw(peer_id):
		return
	turn_flow["drawn"] = true
	var draws: Array = []
	var messages: PackedStringArray = []
	if (inventories.get(peer_id, []) as Array).size() >= MAX_HAND_SIZE:
		draws.append({"card": "", "result": "full"})
	else:
		_resolve_draw(peer_id, CardPresets.weighted_pick(_draw_weights(peer_id), _rng), draws, messages)
	turn_flow["draws"] = draws
	if not automatic:
		_turn_time_left += DRAW_GRACE_SECONDS + (2.0 if aid_pending(peer_id) else 0.0)
	var event := {"type": "draw", "peer_id": peer_id, "draws": draws}
	if not messages.is_empty():
		event["message"] = " ".join(messages)
	_push_state(event)

## EK ŞANS KARTI (0.0.301): ücretsiz çekimden (ya da ATLA'dan) sonra sırada
## bir kez daha, EXTRA_DRAW_COST karşılığında kart çekilebilir.
const EXTRA_DRAW_COST := 20.0

func can_extra_draw(peer_id: int) -> bool:
	return extra_draw_block_reason(peer_id) == ""

## Ek çekim neden yapılamıyor ("" = yapılabilir).
func extra_draw_block_reason(peer_id: int) -> String:
	if peer_id != current_turn_peer_id() or is_turn_blocked() or game_finished:
		return L.t("Sıra sende değil.")
	if is_party_member(peer_id):
		return L.t("Kartları partinin genel başkanı çeker.")
	if needs_turn_draw(peer_id):
		return L.t("Önce bu sıranın kartını çek.")
	if bool(_flow_value(peer_id, "extra_draw", false)):
		return L.t("Bu sıra ek kartını çektin.")
	if (inventories.get(peer_id, []) as Array).size() >= MAX_HAND_SIZE:
		return L.t("Elin dolu.")
	if funds_of(peer_id) < EXTRA_DRAW_COST:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(EXTRA_DRAW_COST)
	return ""

func extra_draw() -> void:
	var me := multiplayer.get_unique_id()
	if not can_extra_draw(me):
		return
	if _is_authority():
		_apply_extra_draw(me)
	else:
		_request_extra_draw.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_extra_draw() -> void:
	if MultiplayerManager.is_host:
		_apply_extra_draw(multiplayer.get_remote_sender_id())

func _apply_extra_draw(peer_id: int) -> void:
	if not can_extra_draw(peer_id):
		return
	_note_main_action(peer_id)
	funds[peer_id] = funds_of(peer_id) - EXTRA_DRAW_COST
	_flow_for(peer_id)["extra_draw"] = true
	var draws: Array = []
	var messages: PackedStringArray = []
	_resolve_draw(peer_id, CardPresets.weighted_pick(_draw_weights(peer_id), _rng), draws, messages)
	_turn_time_left += DRAW_GRACE_SECONDS
	var event := {"type": "draw", "peer_id": peer_id, "draws": draws, "extra": true}
	if not messages.is_empty():
		event["message"] = " ".join(messages)
	_push_state(event)

## Çekilen kartı sınıfına göre işler: anında kart uygulanır, saklanabilir kart ele girer.
func _resolve_draw(peer_id: int, card_type: String, draws: Array, messages: PackedStringArray) -> void:
	if not is_instant_card(card_type):
		if not inventories.has(peer_id):
			inventories[peer_id] = []
		if (inventories[peer_id] as Array).size() >= MAX_HAND_SIZE:
			draws.append({"card": "", "result": "full"})
			return
		inventories[peer_id].insert(inventories[peer_id].size() / 2, card_type)
		draws.append({"card": card_type, "result": "hand"})
		return
	var entry := {"card": card_type, "result": "instant"}
	var text := _apply_instant(peer_id, card_type, entry)
	draws.append(entry)
	if text != "":
		messages.append(text)

## Anında kartın etkisi (bir kez). entry'ye sunum ayrıntısı (ör. ceza tutarı)
## yazılır. Dönüş: herkese duyurulan mesaj.
func _apply_instant(peer_id: int, card_type: String, entry: Dictionary = {}) -> String:
	match card_type:
		CardPresets.POPULISM_CARD_TYPE:
			populism[party_of(peer_id)] = round_number + GameRules.POPULISM_ROUNDS
			return L.t("%s popülizme başladı: bu dönem hamleleri daha etkili.") % _party_name(peer_id)
		CardPresets.PENALTY_CARD_TYPE:
			stat_add(peer_id, "bad")
			var fine := maxf(0.0, funds_of(peer_id)) * CardPresets.PENALTY_SHARE
			funds[peer_id] = funds_of(peer_id) - fine
			entry["amount"] = fine
			return L.t("%s para cezasına çarptırıldı (−%s).") % [_party_name(peer_id), GameRules.cost_text(fine)]
		CardPresets.SELF_TURMOIL_CARD_TYPE:
			stat_add(peer_id, "bad")
			# İÇ KARIŞIKLIK kartının etkisi, oyuncunun kendi partisinde.
			_add_national(peer_id, -PublicOpinion.REBELLION_NATIONAL_DAMAGE)
			_add_turmoil(peer_id, PublicOpinion.TURMOIL_REBELLION)
			return L.t("%s'da iç karışıklık çıktı: parti sarsıldı, ulusal desteği düştü.") % _party_name(peer_id)
		CardPresets.FLEX_CARD_TYPE:
			if int(turn_flow.get("peer", -1)) == peer_id:
				turn_flow["flex"] = true
			return L.t("%s esnek hareket kartı çekti: bu sıra miting ve yatırım sınırı iki katı.") % _party_name(peer_id)
		CardPresets.FUNDS_BONUS_CARD_TYPE:
			var weak_gain := funds_bonus_amount(peer_id, false)
			funds[peer_id] = funds_of(peer_id) + weak_gain
			return L.t("%s bağış kampanyası yaptı (+%s).") % [_party_name(peer_id), GameRules.cost_text(weak_gain)]
		CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE:
			var strong_gain := funds_bonus_amount(peer_id, true)
			funds[peer_id] = funds_of(peer_id) + strong_gain
			return L.t("%s büyük bir bağış kampanyası yaptı (+%s).") % [_party_name(peer_id), GameRules.cost_text(strong_gain)]
	return ""

## ANKET KARTININ VERİSİ: şu an seçim olsa ülke geneli oy oranı ve vekil
## sayısı, hafif gürültülü (her il POLL_ERROR_HIGH kadar). pid -> {"percent", "seats"}.
func national_poll_snapshot(peer_id: int) -> Dictionary:
	var eligible := projected_eligible()
	var votes := {}
	var seats := {}
	var total := 0.0
	for province_id in _province_ids:
		var shares := expected_province_shares(province_id)
		var noisy := {}
		for pid in shares.keys():
			noisy[pid] = {"percent": float(shares[pid])}
		noisy = _noisy_poll(noisy, GameRules.POLL_ERROR_HIGH, "anket:%s:%d:%d" % [province_id, party_of(peer_id), round_number],
			province_seat_count(province_id), eligible)
		# Seçmen sayısı ilin vekil sayısıyla orantılı (bkz. VOTERS_PER_SEAT).
		var weight := float(province_seat_count(province_id))
		for pid in noisy.keys():
			votes[pid] = float(votes.get(pid, 0.0)) + float(noisy[pid]["percent"]) * weight
			seats[pid] = int(seats.get(pid, 0)) + int(noisy[pid]["seats"])
		total += weight
	var result := {}
	for pid in party_ids():
		result[pid] = {"percent": float(votes.get(pid, 0.0)) / maxf(total, 0.0001), "seats": int(seats.get(pid, 0))}
	return result

## Bu oyuncunun son anketi (yoksa boş): {"round", "parties"}.
func my_poll(peer_id: int) -> Dictionary:
	return polls.get(peer_id, {})

## İL KARTI ANKETİ (0.0.272): her ilde görünür; teşkilat isabeti artırır
## (teşkilatsız: kaba tahmin, POLL_ERROR_ROUGH).
func province_card_poll(peer_id: int, province_id: String) -> Dictionary:
	var poll := province_poll(peer_id, province_id)
	if not poll.is_empty():
		return poll
	return _noisy_poll(province_projection(province_id), GameRules.POLL_ERROR_ROUGH,
		"%s:%d:%d:kaba" % [province_id, party_of(peer_id), round_number], province_seat_count(province_id), projected_eligible())

## AFET SAHNESİ bekleniyor mu? (Kart çekildikten sonra bir kez açılır; yardım
## ya da "şimdilik atla" ile kapanır. Sonra YARDIM hamlesi tur boyunca açık.)
func aid_pending(peer_id: int) -> bool:
	return has_disaster() and not needs_turn_draw(peer_id) and not aid_decided(peer_id) and can_aid(peer_id)

## Bu sırada afet sahnesi geçildi mi (yardım yapıldı ya da "şimdilik atla")?
func aid_decided(peer_id: int) -> bool:
	return has_disaster() and int(_flow_value(peer_id, "aid_for", -1)) == int(active_disaster().get("id", 0))

func skip_aid() -> void:
	var me := multiplayer.get_unique_id()
	if not has_disaster() or me != current_turn_peer_id() or aid_decided(me):
		return
	if _is_authority():
		_apply_skip_aid(me)
	else:
		_request_skip_aid.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_skip_aid() -> void:
	if MultiplayerManager.is_host:
		_apply_skip_aid(multiplayer.get_remote_sender_id())

func _apply_skip_aid(peer_id: int) -> void:
	if not has_disaster() or peer_id != current_turn_peer_id() or is_turn_blocked() or aid_decided(peer_id):
		return
	_flow_for(peer_id)["aid_for"] = int(active_disaster().get("id", 0))
	_push_state({"type": "aid_skip", "peer_id": peer_id})

## Oyuncu yardım kararı vermeden başka bir hamle yaptı: sahne geçilmiş sayılır
## (eski istemci / doğrudan çağrı kararı delemesin).
func _note_main_action(peer_id: int) -> void:
	if enforce_turn_flow and has_disaster() and peer_id == current_turn_peer_id():
		_flow_for(peer_id)["aid_for"] = int(active_disaster().get("id", 0))

## MECLİS AKIŞI: şu an açık aşama ("" = yapılacak aşama yok / akış bitti).
## Oylama ya da hükümet kurma sürerken ilk kapanmamış aşamada bekler.
func parliament_stage(peer_id: int) -> String:
	if not enforce_turn_flow or peer_id != current_turn_peer_id() or game_finished:
		return ""
	var closed: Array = _flow_value(peer_id, "parl_closed", [])
	var blocked := is_turn_blocked()
	var previous := _skip_stage_gate
	_skip_stage_gate = true
	var result := ""
	for stage in PARL_STAGES:
		if closed.has(stage):
			continue
		if blocked or _parl_stage_available(peer_id, String(stage)):
			result = String(stage)
			break
	_skip_stage_gate = previous
	return result

func _parl_stage_available(peer_id: int, stage: String) -> bool:
	match stage:
		"censure":
			return can_censure(peer_id)
		"law":
			return can_propose_law(peer_id) or can_propose_constitution(peer_id) or can_early_election(peer_id)
	return false

## Meclis hamlesi bu aşamada mı yapılabilir? (Akış kapalıyken her zaman.)
func _parl_stage_ok(peer_id: int, stage: String) -> bool:
	if not enforce_turn_flow or _skip_stage_gate:
		return true
	if not PARL_STAGES.has(stage) or peer_id != current_turn_peer_id() or game_finished:
		return false
	return not (_flow_value(peer_id, "parl_closed", []) as Array).has(stage)

## Bu sekme şu an kullanılabilir mi (kapanmamış ve hamlesi mümkün)?
func parliament_stage_available(peer_id: int, stage: String) -> bool:
	if not _parl_stage_ok(peer_id, stage):
		return false
	var previous := _skip_stage_gate
	_skip_stage_gate = true
	var ok := _parl_stage_available(peer_id, stage)
	_skip_stage_gate = previous
	return ok

## Bu sırada meclis akışında hiç aşama açıldı mı / kapandı mı?
func parliament_closed_stages(peer_id: int) -> Array:
	return _flow_value(peer_id, "parl_closed", [])

## Yalnız bu sekme bu sıra kapanır (diğerleri açık kalır).
func _parl_close(peer_id: int, stage: String) -> void:
	if peer_id != current_turn_peer_id():
		return
	var closed: Array = _flow_for(peer_id)["parl_closed"]
	if not closed.has(stage):
		closed.append(stage)

## "BU TUR GEÇ" / yasa alanında "BİTİR": aşama bu sıra kapanır.
func pass_parliament_stage(stage: String) -> void:
	var me := multiplayer.get_unique_id()
	if not _parl_stage_ok(me, stage) or is_turn_blocked():
		return
	if _is_authority():
		_apply_parl_pass(me, stage)
	else:
		_request_parl_pass.rpc_id(1, stage)

@rpc("any_peer", "reliable")
func _request_parl_pass(stage: String) -> void:
	if MultiplayerManager.is_host:
		_apply_parl_pass(multiplayer.get_remote_sender_id(), stage)

func _apply_parl_pass(peer_id: int, stage: String) -> void:
	if not PARL_STAGES.has(stage) or is_turn_blocked() or not _parl_stage_ok(peer_id, stage):
		return
	_note_main_action(peer_id)
	_parl_close(peer_id, stage)
	_push_state({"type": "parl_pass", "peer_id": peer_id, "stage": stage})

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

func _election_rng(at_round: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_rng.seed, at_round, "election"])
	return rng

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
		var current := current_turn_peer_id()
		if needs_turn_draw(current):
			# Kart çekme sunumu karar süresini yemez; uzarsa kart kendiliğinden çekilir.
			turn_flow["intro_left"] = float(turn_flow.get("intro_left", INTRO_TIMEOUT)) - delta
			if float(turn_flow["intro_left"]) <= 0.0:
				_apply_draw(current, true)
		else:
			_turn_time_left -= delta
			if _turn_time_left <= 0.0:
				_apply_pass(current, false)
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
## destek, teşkilat, vekil, seçmen grubu yakınlığı, yasa hakkı PARTİYE aittir. Parti
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

## --- SEÇİM İTTİFAKLARI (0.0.225) ------------------------------------------------
## Kurmak bedava; ittifakın LİDERİ kurucusudur. Katılmanın iki yolu var, ikisi de
## OYBİRLİĞİ ister (bkz. alliance_requests):
##   davet  : yalnız lider davet eder (sınırsız); davet edilen kabul etmeli ve
##            liderin dışındaki bütün üyeler onaylamalı.
##   istek  : ittifakı olmayan parti katılmak ister; bütün üyeler onaylamalı.
## Yanıtlar sıra beklemeden verilir. ALLIANCE_REQUEST_ROUNDS tur içinde yanıt
## vermeyen RET sayılır. Oylayanlar başvuru açıldığı anki üyelerdir.
## AYRILMA serbest; yalnız SEÇİM TURUNDA ayrılan parti ulusal puan cezası alır.
## Lider ayrılırsa liderlik en çok vekili olan üyeye geçer; tek üye kalırsa
## ittifak biter. Seçim sonuçları çıkınca bütün ittifaklar dağılır (eski ortaklar
## former_allies'ta bir dönem durur: botlar onlara daha dostça davranır).
const ALLIANCE_REQUEST_ROUNDS := 2
const ALLIANCE_LEAVE_ELECTION_PENALTY := 3.0
const ALLIANCE_NAME_MAX := 28

func alliance_of(peer_or_party_id: int) -> int:
	var pid := party_of(peer_or_party_id)
	for alliance_id in alliances:
		if (alliances[alliance_id].get("members", []) as Array).has(pid):
			return int(alliance_id)
	return -1

func alliance_leader(alliance_id: int) -> int:
	return int(alliances.get(alliance_id, {}).get("leader", -1))

func is_alliance_leader(peer_id: int) -> bool:
	var alliance_id := alliance_of(peer_id)
	return alliance_id >= 0 and alliance_leader(alliance_id) == party_of(peer_id)

## Bu iki parti şu an aynı ittifakta mı?
func are_allies(a: int, b: int) -> bool:
	var alliance_id := alliance_of(a)
	return alliance_id >= 0 and alliance_id == alliance_of(b) and party_of(a) != party_of(b)

## Son seçimdeki ittifak üyeliği: party -> ittifak kimliği.
func election_alliance_membership() -> Dictionary:
	var membership := {}
	for alliance_id in last_election_alliances:
		for pid in last_election_alliances[alliance_id].get("members", []):
			membership[int(pid)] = int(alliance_id)
	return membership

## Son seçimde aynı ittifaktaydılar mı?
func were_allies(a: int, b: int) -> bool:
	return (former_allies.get(party_of(a), []) as Array).has(party_of(b))

## Kendi sırasında ittifak hamlesi (kur, davet et, iste, ayrıl) yapabilir mi?
func can_manage_alliance(peer_id: int) -> bool:
	return alliances_enabled and can_choose_main_action(peer_id) and not is_party_member(peer_id) \
		and not PartyManager.is_independent(peer_id)

## Başvuruya yanıt (onay, kabul, ret) sıra beklemeden verilir; genel başkan verir.
func can_answer_alliance(peer_id: int) -> bool:
	return alliances_enabled and not is_party_member(peer_id) and PartyManager.parties.has(party_of(peer_id))

## Bu partinin yanıt vermesi beklenen başvurular: [request_id].
func alliance_requests_for(peer_id: int) -> Array:
	var pid := party_of(peer_id)
	var result: Array = []
	for rid in alliance_requests:
		var req: Dictionary = alliance_requests[rid]
		if _request_waits_for(req, pid):
			result.append(int(rid))
	return result

func _request_waits_for(req: Dictionary, pid: int) -> bool:
	if String(req.get("kind", "")) == "invite" and int(req.get("party", -1)) == pid:
		return not bool(req.get("accepted", false))
	return (req.get("voters", []) as Array).has(pid) and not (req.get("votes", {}) as Dictionary).has(pid)

## Bu parti ile bu ittifak arasında açık başvuru var mı?
func pending_alliance_request(alliance_id: int, party_id: int) -> int:
	for rid in alliance_requests:
		var req: Dictionary = alliance_requests[rid]
		if int(req.get("alliance", -1)) == alliance_id and int(req.get("party", -1)) == party_of(party_id):
			return int(rid)
	return -1

func create_alliance(peer_id: int, alliance_name: String, color: Color) -> void:
	if _is_authority():
		_apply_create_alliance(peer_id, alliance_name, color)
	else:
		_request_create_alliance.rpc_id(1, alliance_name, color)

func invite_alliance_party(peer_id: int, alliance_id: int, party_id: int) -> void:
	if _is_authority():
		_apply_invite_alliance_party(peer_id, alliance_id, party_id)
	else:
		_request_invite_alliance_party.rpc_id(1, alliance_id, party_id)

func request_alliance(peer_id: int, alliance_id: int) -> void:
	if _is_authority():
		_apply_request_alliance(peer_id, alliance_id)
	else:
		_request_request_alliance.rpc_id(1, alliance_id)

func answer_alliance_request(peer_id: int, request_id: int, yes: bool) -> void:
	if _is_authority():
		_apply_answer_alliance(peer_id, request_id, yes)
	else:
		_request_answer_alliance.rpc_id(1, request_id, yes)

func leave_alliance(peer_id: int) -> void:
	if _is_authority():
		_apply_leave_alliance(peer_id)
	else:
		_request_leave_alliance.rpc_id(1)

func _apply_create_alliance(peer_id: int, alliance_name: String, color: Color) -> void:
	var name := alliance_name.strip_edges().substr(0, ALLIANCE_NAME_MAX)
	if not can_manage_alliance(peer_id) or name == "" or alliance_of(peer_id) >= 0:
		return
	if not PartyPresets.COLORS.has(color):
		return
	for existing in alliances.values():
		if Color(existing.get("color", Color.WHITE)).is_equal_approx(color):
			return
	var next_id := 1
	for key in alliances:
		next_id = maxi(next_id, int(key) + 1)
	var pid := party_of(peer_id)
	alliances[next_id] = {"name": name, "color": color, "leader": pid, "members": [pid]}
	_drop_requests_of_party(pid)
	var message := L.t("%s kuruldu; lideri %s oldu.") % [name, _party_name(peer_id)]
	_push_state({"type": "alliance_created", "peer_id": peer_id, "alliance_id": next_id, "message": message})

func _apply_invite_alliance_party(peer_id: int, alliance_id: int, party_id: int) -> void:
	if not can_manage_alliance(peer_id) or not alliances.has(alliance_id) or alliance_leader(alliance_id) != party_of(peer_id):
		return
	if not party_ids().has(party_id) or alliance_of(party_id) >= 0 or PartyManager.is_independent(party_id) \
			or pending_alliance_request(alliance_id, party_id) >= 0:
		return
	var voters: Array = (alliances[alliance_id]["members"] as Array).duplicate()
	voters.erase(party_of(peer_id))
	var rid := _open_alliance_request(alliance_id, party_id, "invite", voters)
	_push_state({"type": "alliance_invited", "peer_id": peer_id, "alliance_id": alliance_id, "target": party_id, "request": rid,
		"message": L.t("%s, “%s” grubuna davet edildi.") % [_party_name(party_id), String(alliances[alliance_id]["name"])]})

func _apply_request_alliance(peer_id: int, alliance_id: int) -> void:
	if not can_manage_alliance(peer_id) or not alliances.has(alliance_id) or alliance_of(peer_id) >= 0 \
			or pending_alliance_request(alliance_id, peer_id) >= 0:
		return
	var pid := party_of(peer_id)
	var rid := _open_alliance_request(alliance_id, pid, "request", (alliances[alliance_id]["members"] as Array).duplicate())
	alliance_requests[rid]["accepted"] = true
	_push_state({"type": "alliance_requested", "peer_id": peer_id, "alliance_id": alliance_id, "request": rid,
		"message": L.t("%s, “%s” grubuna katılmak istiyor; bütün üyelerin onayı bekleniyor.") % [_party_name(peer_id), String(alliances[alliance_id]["name"])]})

func _open_alliance_request(alliance_id: int, party_id: int, kind: String, voters: Array) -> int:
	_next_alliance_request += 1
	alliance_requests[_next_alliance_request] = {"alliance": alliance_id, "party": party_of(party_id), "kind": kind,
		"round": round_number, "accepted": false, "voters": voters, "votes": {}}
	return _next_alliance_request

## Onay / ret. Davet edilen parti için yes = daveti kabul; üye için yes = onay.
func _apply_answer_alliance(peer_id: int, request_id: int, yes: bool) -> void:
	if not can_answer_alliance(peer_id) or not alliance_requests.has(request_id):
		return
	var pid := party_of(peer_id)
	var req: Dictionary = alliance_requests[request_id]
	if not _request_waits_for(req, pid):
		return
	if String(req["kind"]) == "invite" and int(req["party"]) == pid:
		req["accepted"] = yes
	else:
		var votes: Dictionary = (req.get("votes", {}) as Dictionary).duplicate()
		votes[pid] = yes
		req["votes"] = votes
	alliance_requests[request_id] = req
	_resolve_alliance_request(request_id, pid if not yes else -1)

## Başvuruyu sonuçlandırır: ret varsa düşer; herkes onaylamışsa parti katılır.
## Sonuç yoksa (hâlâ bekleniyor) sadece durum yayınlanır.
func _resolve_alliance_request(request_id: int, refused_by: int = -1) -> void:
	var req: Dictionary = alliance_requests.get(request_id, {})
	if req.is_empty():
		return
	var alliance_id := int(req["alliance"])
	var pid := int(req["party"])
	var alliance_name := String(alliances.get(alliance_id, {}).get("name", "?"))
	if not alliances.has(alliance_id) or alliance_of(pid) >= 0 or not PartyManager.parties.has(pid):
		alliance_requests.erase(request_id)
		_push_state({"type": "alliance_request_closed"})
		return
	var members: Array = alliances[alliance_id]["members"]
	var voters: Array = []
	for voter in req.get("voters", []):
		if members.has(int(voter)):
			voters.append(int(voter))
	var votes: Dictionary = req.get("votes", {})
	var refused := refused_by != -1
	for voter in voters:
		if votes.has(voter) and not bool(votes[voter]):
			refused = true
	if refused:
		alliance_requests.erase(request_id)
		# Ret hatırlanır: botlar aynı partiye hemen yeniden başvurmaz (bkz. recently_refused).
		var refusals: Dictionary = (alliances[alliance_id].get("refused", {}) as Dictionary).duplicate()
		refusals[pid] = round_number
		alliances[alliance_id]["refused"] = refusals
		var who := refused_by if refused_by != -1 else pid
		_push_state({"type": "alliance_refused", "peer_id": who, "alliance_id": alliance_id, "target": pid,
			"message": L.t("%s ile %s arasındaki başvuru reddedildi (%s).") % [_party_name(pid), alliance_name, _party_name(who)]})
		return
	var all_voted := true
	for voter in voters:
		if not votes.has(voter):
			all_voted = false
	if not bool(req.get("accepted", false)) or not all_voted:
		_push_state({"type": "alliance_vote"})
		return
	alliance_requests.erase(request_id)
	var updated: Array = members.duplicate()
	updated.append(pid)
	alliances[alliance_id]["members"] = updated
	_drop_requests_of_party(pid)
	_push_state({"type": "alliance_joined", "peer_id": pid, "alliance_id": alliance_id,
		"message": L.t("%s, “%s” grubuna katıldı.") % [_party_name(pid), alliance_name]})

func _drop_requests_of_party(pid: int) -> void:
	for rid in alliance_requests.keys():
		if int(alliance_requests[rid].get("party", -1)) == pid:
			alliance_requests.erase(rid)

## Tur başında: süresi dolan başvurular (yanıt vermeyen = ret) düşer.
func _expire_alliance_requests() -> void:
	for rid in alliance_requests.keys():
		var req: Dictionary = alliance_requests[rid]
		if round_number - int(req.get("round", round_number)) >= ALLIANCE_REQUEST_ROUNDS:
			alliance_requests.erase(rid)
			_pending_log.append({"text": L.t("%s ile %s arasındaki başvuru yanıtsız kaldığı için düştü.") % [
				_party_name(int(req["party"])), String(alliances.get(int(req["alliance"]), {}).get("name", "?"))],
				"peer_id": int(req["party"]), "province": "", "kind": "alliance"})

func _apply_leave_alliance(peer_id: int) -> void:
	var alliance_id := alliance_of(peer_id)
	if not can_manage_alliance(peer_id) or alliance_id < 0:
		return
	var pid := party_of(peer_id)
	var alliance: Dictionary = alliances[alliance_id]
	var alliance_name := String(alliance["name"])
	var members: Array = (alliance["members"] as Array).duplicate()
	members.erase(pid)
	alliance["members"] = members
	alliances[alliance_id] = alliance
	var message := L.t("%s, “%s” grubundan ayrıldı.") % [_party_name(peer_id), alliance_name]
	if members.size() <= 1:
		alliances.erase(alliance_id)
		message += " " + L.t("Tek parti kaldı; ittifak sona erdi.")
	if election_this_round():
		_add_national(pid, -ALLIANCE_LEAVE_ELECTION_PENALTY)
		message = L.t("%s seçim arifesinde “%s” grubundan ayrıldı; seçmen bunu affetmedi.") % [_party_name(peer_id), alliance_name]
	_push_state({"type": "alliance_left", "peer_id": peer_id, "alliance_id": alliance_id, "message": message})

## GERGİNLİK (0.0.227): ortağının meclis önergesine HAYIR diyen parti ittifakta
## küskünlük yaratır: önergenin sahibinin "grievance" sayacı artar. Botlar
## küskünlük birikince ittifaktan ayrılmayı düşünür (bkz. BotBrain).
const ALLIANCE_GRIEVANCE_LEAVE := 2

func note_alliance_vote(voter: int, proposer: int, vote_no: bool) -> void:
	if not vote_no or not are_allies(voter, proposer):
		return
	var alliance_id := alliance_of(voter)
	var alliance: Dictionary = alliances[alliance_id]
	var grievance: Dictionary = (alliance.get("grievance", {}) as Dictionary).duplicate()
	var victim := party_of(proposer)
	grievance[victim] = int(grievance.get(victim, 0)) + 1
	alliance["grievance"] = grievance
	alliances[alliance_id] = alliance
	_pending_log.append({"text": L.t("%s, ortağı %s tarafından verilen önergeye HAYIR dedi; “%s” grubunda gerginlik var.") % [
		_party_name(voter), _party_name(proposer), String(alliance.get("name", ""))], "peer_id": voter, "province": "", "kind": "alliance"})

## Bu parti ile bu ittifak arasındaki başvuru son 2 turda reddedildi mi?
func recently_refused(alliance_id: int, party_id: int) -> bool:
	var refusals: Dictionary = alliances.get(alliance_id, {}).get("refused", {})
	return refusals.has(party_of(party_id)) and round_number - int(refusals[party_of(party_id)]) < ALLIANCE_REQUEST_ROUNDS

func alliance_grievance(party_id: int) -> int:
	var alliance_id := alliance_of(party_id)
	if alliance_id < 0:
		return 0
	return int((alliances[alliance_id].get("grievance", {}) as Dictionary).get(party_of(party_id), 0))

## Seçim sonuçları çıkınca (ya da anayasa kapatınca) bütün ittifaklar dağılır.
## remember=true: üyelikler former_allies'a yazılır (bir sonraki dağılmaya kadar).
func dissolve_all_alliances(remember: bool) -> void:
	if remember:
		last_election_alliances = alliances.duplicate(true) if alliances_enabled else {}
		former_allies = {}
		for alliance in alliances.values():
			var members: Array = alliance.get("members", [])
			for pid in members:
				var others: Array = members.duplicate()
				others.erase(pid)
				former_allies[int(pid)] = others
	alliances = {}
	alliance_requests = {}

@rpc("any_peer", "reliable")
func _request_create_alliance(alliance_name: String, color: Color) -> void:
	if MultiplayerManager.is_host:
		_apply_create_alliance(multiplayer.get_remote_sender_id(), alliance_name, color)

@rpc("any_peer", "reliable")
func _request_invite_alliance_party(alliance_id: int, party_id: int) -> void:
	if MultiplayerManager.is_host:
		_apply_invite_alliance_party(multiplayer.get_remote_sender_id(), alliance_id, party_id)

@rpc("any_peer", "reliable")
func _request_request_alliance(alliance_id: int) -> void:
	if MultiplayerManager.is_host:
		_apply_request_alliance(multiplayer.get_remote_sender_id(), alliance_id)

@rpc("any_peer", "reliable")
func _request_answer_alliance(request_id: int, yes: bool) -> void:
	if MultiplayerManager.is_host:
		_apply_answer_alliance(multiplayer.get_remote_sender_id(), request_id, yes)

@rpc("any_peer", "reliable")
func _request_leave_alliance() -> void:
	if MultiplayerManager.is_host:
		_apply_leave_alliance(multiplayer.get_remote_sender_id())

## Partideki oyuncu sayısı (para ve puan bölüşümü için).
func member_count(peer_id: int) -> int:
	return PartyManager.member_count(party_of(peer_id))

## Hükümet kurulurken, mecliste bir teklif oylanırken ya da oyun bittiyse
## TUR DURUR: kimse kart çekemez, oynayamaz, pas geçemez.
## Oylamadan dönünce sıra sahibine en az bu kadar süre kalır.
const VOTE_RETURN_MIN_SECONDS := 8.0

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

## PARA ONDALIKLI: para cezası ve finansman paylaşımı yarım basamak üretir.
func funds_of(peer_id: int) -> float:
	return float(funds.get(peer_id, 0.0))

## Para yazısı: tam sayıysa "3", değilse "2,5".
static func funds_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 1).replace(".", ",")

## Sıradaki oyuncunun kalan süresi (saniye).
func turn_seconds_left() -> float:
	if is_turn_blocked() or needs_turn_draw(current_turn_peer_id()):
		# Engel (oylama, kongre...) ve kart çekme sunumu sırasında sayaç DURUR.
		return maxf(0.0, _turn_time_left if _is_authority() else _turn_time_synced)
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
	if not _parl_stage_ok(peer_id, "law"):
		return false
	# Gündem şartı yok (0.0.182): her grup için yasa sunulabilir; gündem ödüllendirir.
	if has_proposed_law_this_round(peer_id, "group"):
		return false
	if law_type != "" and not CardPresets.is_law_card(law_type):
		return false
	# İlk seçime kadar meclis yok: yasa yapılamaz (saf propaganda dönemi).
	return not last_seats.is_empty() and GovernmentManager.can_submit_law()

## VERGİ YASASI: 0.0.300'den beri HERKES sunar; gündem şartı yok ama
## partinin dönemlik yasa hakkını kullanır ve meclis oylamasından geçer.
## level verilirse (≥ 0) o kademe şu ankinden farklı olmalı.
func can_propose_tax_law(peer_id: int, level: int = -1) -> bool:
	return tax_law_block_reason(peer_id, level) == ""

## Vergi yasası neden sunulamıyor ("" = sunulabilir). Arayüz bunu gösterir.
func tax_law_block_reason(peer_id: int, level: int = -1) -> String:
	if last_seats.is_empty():
		return L.t("İlk seçime kadar meclis yok: vergi değiştirilemez.")
	if is_party_member(peer_id):
		return L.t("Yasayı partinin genel başkanı sunar.")
	if not has_seats(peer_id):
		return L.t("Mecliste vekilin yok.")
	if has_proposed_law_this_round(peer_id, "tax"):
		return L.t("Partin bu dönem zaten bir vergi yasası sundu.")
	if not GovernmentManager.can_submit_law():
		return L.t("Mecliste başka bir oylama sürüyor.")
	if not can_choose_main_action(peer_id):
		return L.t("Sıra sende değil.")
	if not _parl_stage_ok(peer_id, "law"):
		return L.t("Vergi yasası meclis akışının yasa aşamasında sunulur.")
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
	if has_proposed_law_this_round(peer_id, "constitution"):
		return false
	if not _parl_stage_ok(peer_id, "law"):
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
	_note_main_action(peer_id)
	if not GovernmentManager.submit_constitution(peer_id, payload):
		return
	constitution_rounds[party_of(peer_id)] = round_number
	_push_state({"type": "law", "peer_id": peer_id, "law": "anayasa"})

@rpc("any_peer", "reliable")
func _request_constitution(payload: Dictionary) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_constitution_proposal(multiplayer.get_remote_sender_id(), payload)

## Yasa hakkı PARTİYE aittir (partinin iki üyesinden biri sunar). Her tür
## dönemde bir: kind "group" (seçmen grubu yasası), "tax", "constitution";
## "" = herhangi biri sunuldu mu.
func has_proposed_law_this_round(peer_id: int, kind: String = "") -> bool:
	var pid := party_of(peer_id)
	match kind:
		"group":
			return int(law_rounds.get(pid, 0)) == round_number
		"tax":
			return int(tax_rounds.get(pid, 0)) == round_number
		"constitution":
			return int(constitution_rounds.get(pid, 0)) == round_number
	return int(law_rounds.get(pid, 0)) == round_number or int(tax_rounds.get(pid, 0)) == round_number 		or int(constitution_rounds.get(pid, 0)) == round_number

# --- Afet ve YARDIM GÖTÜR (bkz. Disaster) -------------------------------------

# --- HÜKÜMET ONAYI ----------------------------------------------------------------

func has_approval() -> bool:
	return GovernmentManager.has_government() and approval.has("value")

func approval_value() -> float:
	return float(approval.get("value", PublicOpinion.APPROVAL_NEUTRAL))

## Son tur sonu güncellemesinin farkı (göstergedeki artış/azalış etiketi).
func approval_delta() -> float:
	return float(approval.get("delta", 0.0))

## Onayın bu hükümet partisine her tur sonunda yazdığı ülke geneli seçmen
## etkisi (puan): %50'den uzaklık × APPROVAL_NATIONAL_MAX, bakanlık payına göre.
func approval_national(pid: int) -> float:
	if not has_approval():
		return 0.0
	return PublicOpinion.APPROVAL_NATIONAL_MAX * (approval_value() - PublicOpinion.APPROVAL_NEUTRAL) \
		/ PublicOpinion.APPROVAL_NEUTRAL * quota_share(pid)

## Hükümet güvenoyu aldı: her ortağın oy oranı × bakanlık payı toplanır
## (%50 oyla tek başına iktidar %50'den başlar).
func start_approval() -> void:
	if not _is_authority():
		return
	var value := 0.0
	for pid in GovernmentManager.government_party_ids():
		value += float(last_vote_shares.get(pid, 0.0)) * quota_share(int(pid))
	value = clampf(snappedf(value, 0.1), 0.0, 100.0)
	approval = {"value": value, "delta": 0.0, "history": [value], "pending": []}
	_pending_log.append({"text": L.t("Hükümet onayı %%%s ile başladı.") % L.dec(value, 0), "peer_id": -1, "province": "", "kind": "government"})
	invest_requests = {}
	_ensure_invest_requests()

# --- YATIRIM İSTEKLERİ ------------------------------------------------------------

func invest_request(province_id: String) -> Dictionary:
	return invest_requests.get(province_id, {})

## İsteğin süresi: oynama sırasında kalan sıra sayısı (bu sıra dahil) / tur
## başındaki sıra sayısı. Haritadaki pasta bu kadar dilimden oluşur.
func request_turns() -> Vector2i:
	var total := maxi(1, turn_order.size())
	return Vector2i(clampi(total - current_turn_index, 1, total), total)

## Yeni tur: hükümet varken il sayısı / REQUEST_PROVINCES_PER (en az REQUEST_MIN)
## il, vekil sayısına göre küçük ya da büyük yatırım ister.
func _roll_invest_requests() -> void:
	invest_requests = {}
	if not has_approval() or _province_ids.is_empty():
		return
	var count := maxi(PublicOpinion.REQUEST_MIN, int(roundf(float(_province_ids.size()) / float(PublicOpinion.REQUEST_PROVINCES_PER))))
	var pool: Array = _province_ids.duplicate()
	for province_id in active_disaster().get("provinces", []):
		pool.erase(province_id)
	_shuffle(pool)
	var average := average_province_seats()
	for province_id in pool.slice(0, mini(count, pool.size())):
		var tier := 1 if province_seat_count(String(province_id)) > average else 0
		invest_requests[String(province_id)] = {"amount": invest_tier_cost(tier), "done": false}

## Hükümet kurulunca bu turun istekleri hemen seçilir (tur başını beklemez).
func _ensure_invest_requests() -> void:
	if invest_requests.is_empty():
		_roll_invest_requests()

func _fulfil_invest_request(province_id: String, amount: float) -> void:
	var req: Dictionary = invest_requests.get(province_id, {})
	if req.is_empty() or bool(req.get("done", false)) or amount + 0.001 < float(req["amount"]):
		return
	req["done"] = true
	_approval_add(L.t("%s yatırım isteği karşılandı") % _province_name(province_id), PublicOpinion.APPROVAL_REQUEST_DONE)
	_pending_log.append({"text": L.t("%s yatırım isteği karşılandı: hükümet onayı tur sonunda artacak.") % _province_name(province_id),
		"peer_id": -1, "province": province_id, "kind": "invest"})

## Tur bitti: karşılanmayan her istek onayı düşürür; hükümet ortakları o ilde
## bakanlık paylarına göre il puanı kaybeder.
func _settle_invest_requests() -> void:
	if not has_approval():
		invest_requests = {}
		return
	var missed: PackedStringArray = []
	for province_id in invest_requests.keys():
		if bool(invest_requests[province_id].get("done", false)) or not has_province(String(province_id)):
			continue
		missed.append(_province_name(String(province_id)))
		_approval_add(L.t("%s yatırım isteği karşılanmadı") % _province_name(String(province_id)), PublicOpinion.APPROVAL_REQUEST_MISSED)
		for pid in GovernmentManager.government_party_ids():
			_add_local(String(province_id), int(pid), PublicOpinion.REQUEST_MISSED_LOCAL * quota_share(int(pid)))
	if not missed.is_empty():
		_pending_log.append({"text": L.t("Karşılanmayan yatırım istekleri: %s. Hükümet bu illerde oy kaybetti.") % ", ".join(missed),
			"peer_id": -1, "province": "", "kind": "invest"})

## Tur içindeki bir olayın onaya etkisi: tur sonunda topluca uygulanır.
func _approval_add(text: String, amount: float) -> void:
	if not has_approval() or is_zero_approx(amount):
		return
	var pending: Array = approval.get("pending", [])
	pending.append({"text": text, "amount": amount})
	approval["pending"] = pending

func _settle_approval() -> void:
	if not has_approval():
		return
	var before := approval_value()
	var total := 0.0
	var parts: PackedStringArray = []
	for item in approval.get("pending", []):
		total += float(item["amount"])
		parts.append("%s %s" % [String(item["text"]), _signed_points(float(item["amount"]))])
	var value := clampf(snappedf(before + total, 0.1), 0.0, 100.0)
	var history: Array = approval.get("history", [])
	history.append(value)
	while history.size() > PublicOpinion.APPROVAL_HISTORY:
		history.pop_front()
	approval = {"value": value, "delta": value - before, "history": history, "pending": []}
	# Onay %50'nin üstündeyse hükümet ortakları ülke genelinde seçmen kazanır, altındaysa kaybeder.
	for pid in GovernmentManager.government_party_ids():
		_add_national(int(pid), approval_national(int(pid)))
	if not parts.is_empty():
		_pending_log.append({"text": L.t("Hükümet onayı %%%s (%s): %s.") % [L.dec(value, 0), _signed_points(value - before), ", ".join(parts)],
			"peer_id": -1, "province": "", "kind": "government"})

static func _signed_points(amount: float) -> String:
	return ("+" if amount >= 0.0 else "−") + L.dec(absf(amount), 0)

## Krizli grubun yasası: geçerse onay artar; HAYIR diyen hükümet partisi
## bakanlık payı oranında ağır kaybettirir; hükümetin HAYIR'ıyla düşerse ek eksi.
func _crisis_law_approval(votes: Dictionary, passed: bool, gov_ids: Array) -> void:
	if not has_approval():
		return
	if passed:
		_approval_add(L.t("Kriz yasası geçti"), PublicOpinion.APPROVAL_CRISIS_LAW_PASSED)
	var said_no := false
	for voter in votes.keys():
		var pid := party_of(int(voter))
		if int(voter) != pid or not gov_ids.has(pid):
			continue
		if GovernmentManager.normalize_vote(votes[voter]) == GovernmentManager.VOTE_NO:
			said_no = true
			_approval_add(L.t("%s kriz yasasına HAYIR dedi") % _party_name(pid), PublicOpinion.APPROVAL_CRISIS_LAW_NO * quota_share(pid))
	if said_no and not passed:
		_approval_add(L.t("Kriz yasası hükümet oylarıyla düştü"), PublicOpinion.APPROVAL_CRISIS_LAW_FAILED)

func active_disaster() -> Dictionary:
	return disaster.get("active", {})

func has_disaster() -> bool:
	return not active_disaster().is_empty()

## Bu oyuncunun partisinin bu afete şimdiye kadar yaptığı yardım (milyon ¤).
func disaster_aid_of(peer_id: int) -> float:
	return float((active_disaster().get("aid", {}) as Dictionary).get(party_of(peer_id), 0.0))

## Yardım tutarlarının üst sınırları: {"party_max", "state_max", "state_allowed"}
## (AID_STEP'e yuvarlanmış). Devlet payı hükümet partisinin hazine kotasıyla sınırlı.
func aid_limits(peer_id: int) -> Dictionary:
	# 0.0.238: devlet hazinesi yalnız yatırım içindir; afet yardımı parti kasasından.
	return {"party_max": Disaster.snap_amount(funds_of(peer_id)), "state_max": 0.0, "state_allowed": false}

## Yardım neden yapılamıyor ("" = yapılabilir). Tutarlar verilmezse (< 0)
## sadece "en az AID_MIN ödenebiliyor mu" bakılır.
func aid_block_reason(peer_id: int, party_m: float = -1.0, state_m: float = -1.0) -> String:
	if not has_disaster():
		return L.t("Şu an yardım bekleyen bir afet yok.")
	if not can_choose_main_action(peer_id):
		return L.t("Sıra sende değil.")
	var lim := aid_limits(peer_id)
	if party_m < 0.0 or state_m < 0.0:
		if float(lim["party_max"]) + float(lim["state_max"]) < Disaster.AID_MIN:
			return L.t("Yardım için en az %s gerekir.") % Economy.money_full(Disaster.AID_MIN)
		return ""
	if party_m + state_m < Disaster.AID_MIN - 0.001:
		return L.t("Yardım için en az %s gerekir.") % Economy.money_full(Disaster.AID_MIN)
	if not is_equal_approx(Disaster.snap_amount(party_m + 0.001), party_m) or not is_equal_approx(Disaster.snap_amount(state_m + 0.001), state_m):
		return L.t("Tutar %s adımlarla seçilir.") % Economy.money_full(Disaster.AID_STEP)
	if state_m > 0.0 and not bool(lim["state_allowed"]):
		return L.t("Afet yardımı parti kasasından yapılır; devlet hazinesi yalnız yatırım içindir.")
	if state_m > state_treasury() + 0.001:
		return L.t("Devlet hazinesi yetmiyor (%s var).") % Economy.money_full(state_treasury())
	if state_m > state_quota(peer_id) + 0.001:
		return L.t("Bu dönemki hazine kotan yetmiyor (%s kaldı).") % Economy.money_full(state_quota(peer_id))
	if party_m > funds_of(peer_id) + 0.001:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(party_m)
	return ""

func can_aid(peer_id: int, party_m: float = -1.0, state_m: float = -1.0) -> bool:
	return aid_block_reason(peer_id, party_m, state_m) == ""

## YARDIM GÖTÜR: party_m parti kasasından, state_m devlet hazinesinden (milyon ¤).
func aid(party_m: float, state_m: float) -> void:
	if not can_aid(multiplayer.get_unique_id(), party_m, state_m):
		return
	if _is_authority():
		_apply_aid_move(multiplayer.get_unique_id(), party_m, state_m)
	else:
		_request_aid.rpc_id(1, party_m, state_m)

@rpc("any_peer", "reliable")
func _request_aid(party_m: float, state_m: float) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_aid_move(multiplayer.get_remote_sender_id(), party_m, state_m)

func _apply_aid_move(peer_id: int, party_m: float, state_m: float) -> void:
	if not can_aid(peer_id, party_m, state_m):
		return
	var active := active_disaster()
	if peer_id == current_turn_peer_id():
		_flow_for(peer_id)["aid_for"] = int(active.get("id", 0))
	var provinces: Array = active.get("provinces", [])
	var total := party_m + state_m
	funds[peer_id] = funds_of(peer_id) - party_m
	var before := state_treasury()
	if state_m > 0.0:
		_spend_quota(peer_id, state_m)
		economy["treasury"] = before - state_m
	var pid := party_of(peer_id)
	stat_add(peer_id, "aid", total)
	var aid_map: Dictionary = active.get("aid", {})
	var prev := float(aid_map.get(pid, 0.0))
	aid_map[pid] = prev + total
	active["aid"] = aid_map
	var gain := Disaster.local_gain(prev, prev + total, provinces.size())
	for province_id in provinces:
		_add_local(String(province_id), peer_id, gain)
		_log_province(String(province_id), L.t("%s yardımı — %s getirdi (%s)") % [
			Disaster.title(String(active["kind"])), _party_name(peer_id), Economy.money_full(total)])
	_add_national(peer_id, Disaster.national_gain(prev, prev + total))
	var message := L.t("%s, afet bölgesi %s iline %s yardım götürdü.") % [_party_name(peer_id), _province_name(String(provinces[0])), Economy.money_full(total)] 		if provinces.size() == 1 else L.t("%s, afetteki %d ile %s yardım götürdü.") % [_party_name(peer_id), provinces.size(), Economy.money_full(total)]
	var event := {"type": "aid", "peer_id": peer_id, "province": String(provinces[0]), "message": message}
	if state_m > 0.0:
		event["econ"] = {"kind": "invest", "peer_id": peer_id, "province": String(provinces[0]), "cost": state_m,
			"party_cost": party_m, "before": before, "after": state_treasury()}
	_push_state(event)

## Tur başı (host): afet zarı. Dönemde en fazla TERM_MAX; önceki dönem hiç
## çıkmadıysa bu dönemin son turunda hâlâ yoksa kesin çıkar.
func _roll_disaster() -> void:
	if last_election_round <= 0:
		return
	var count := int(disaster.get("term_count", 0))
	if count >= Disaster.TERM_MAX:
		return
	var forced: bool = bool(disaster.get("owed", false)) and count == 0 and GameRules.is_election_round(round_number)
	if not forced and _rng.randf() >= Disaster.round_chance():
		return
	start_disaster(Disaster.pick_kind(_rng))

## Afeti başlatır (testler de doğrudan çağırır). Dönüş: etkilenen iller.
func start_disaster(kind: String, provinces: Array = []) -> Array:
	if last_election_round <= 0:
		return []
	if provinces.is_empty():
		provinces = Disaster.pick_region(kind, _rng, GameMap.province_ids())
	if provinces.is_empty():
		return []
	var id := int(disaster.get("next_id", 1))
	disaster["next_id"] = id + 1
	disaster["term_count"] = int(disaster.get("term_count", 0)) + 1
	disaster["owed"] = false
	disaster["active"] = {"id": id, "kind": kind, "provinces": provinces, "round": round_number, "aid": {}}
	var names: Array = []
	for province_id in provinces:
		names.append(_province_name(String(province_id)))
		_log_province(String(province_id), L.t("%s afeti") % Disaster.title(kind))
	_pending_log.append({"text": L.t("AFET: %s — %s. Bu tur boyunca YARDIM hamlesiyle bölgeye istendiği kadar yardım edilebilir.") % [
		Disaster.title(kind), ", ".join(PackedStringArray(names))], "peer_id": -1, "province": String(provinces[0]), "kind": "disaster"})
	_pending_disaster_fx = {"id": id, "kind": kind, "provinces": provinces}
	return provinces

## Tur bitti: afet sona erer, kimin ne kadar yardım ettiği loga düşer.
func _end_disaster() -> void:
	var active := active_disaster()
	if active.is_empty():
		return
	var aid_map: Dictionary = active.get("aid", {})
	var text := ""
	if aid_map.is_empty():
		text = L.t("%s afeti sona erdi: bölgeye hiçbir parti yardım götürmedi.") % Disaster.title(String(active["kind"]))
	else:
		var parts: Array = []
		var ids: Array = aid_map.keys()
		ids.sort_custom(func(a, b): return float(aid_map[a]) > float(aid_map[b]))
		for pid in ids:
			parts.append("%s %s" % [_party_name(int(pid)), Economy.money_full(float(aid_map[pid]))])
		text = L.t("%s afeti sona erdi. Yardımlar: %s.") % [Disaster.title(String(active["kind"])), ", ".join(PackedStringArray(parts))]
	_pending_log.append({"text": text, "peer_id": -1, "province": String((active.get("provinces", [""]) as Array)[0]), "kind": "disaster"})
	disaster["active"] = {}
	# Hükümet ortaklarının toplam yardımı muhalefetinkinden fazlaysa onay artar, değilse düşer.
	if has_approval():
		var gov_ids := GovernmentManager.government_party_ids()
		var gov_aid := 0.0
		var opp_aid := 0.0
		for pid in aid_map.keys():
			if gov_ids.has(int(pid)):
				gov_aid += float(aid_map[pid])
			else:
				opp_aid += float(aid_map[pid])
		if gov_aid > opp_aid:
			_approval_add(L.t("Afet yardımı"), PublicOpinion.APPROVAL_DISASTER_MORE)
		elif gov_aid < opp_aid or gov_aid <= 0.0:
			_approval_add(L.t("Afet yardımı yetersiz"), PublicOpinion.APPROVAL_DISASTER_LESS)

## Yeni seçim dönemi: sayaç sıfırlanır; biten dönemde hiç afet çıkmadıysa
## yenisinde en az bir tane garanti.
func _disaster_new_term() -> void:
	disaster["owed"] = int(disaster.get("term_count", 0)) == 0
	disaster["term_count"] = 0

## Yatırım hamlesi: sadece hükümet partileri; tamamı DEVLET HAZİNESİNDEN
## (partinin bu dönemki hazine kotası yetmezse yapılamaz).
## state: devletin payı (0..1); -1 = uygun bir paylaşım var mı.
func can_invest(peer_id: int, province_id: String = "", state: float = -1.0, tier: int = DEFAULT_TIER) -> bool:
	if not (can_choose_main_action(peer_id) and is_government_party(peer_id) and not is_party_member(peer_id)
			and (province_id == "" or has_province(province_id))):
		return false
	if not valid_tier(tier) or invest_count(peer_id) >= action_limit(peer_id):
		return false
	return _funding_ok(funding_range(peer_id, "invest", invest_tier_cost(tier)), state)

# --- Finansman paylaşımı ------------------------------------------------------

## Hamlenin finansmanı (0.0.238 sadeleştirme): MİTİNG her zaman parti
## kasasından, YATIRIM her zaman devlet hazinesinden (partinin hazine kotası,
## bakanlık payına göre); paylaşım seçimi yok. {"kind", "total", "min", "max"
## (devlet payı; ikisi eşit), "default", "state_allowed"}. min > max ise
## ödenemez.
func funding_range(peer_id: int, kind: String, total: float = -1.0) -> Dictionary:
	if total <= 0.0:
		total = Economy.INVEST_COST if kind == "invest" else float(GameRules.MITING_FUNDS_COST)
	if kind == "invest":
		var state_allowed := is_government_party(peer_id) and not is_party_member(peer_id) and not PartyManager.is_independent(peer_id)
		var ok := state_allowed and state_quota(peer_id) >= total - 0.001
		return {"kind": kind, "total": total, "min": 1.0, "max": 1.0 if ok else 0.0, "default": 1.0, "state_allowed": state_allowed}
	var affordable := funds_of(peer_id) >= total - 0.001
	return {"kind": kind, "total": total, "min": 0.0 if affordable else 1.0, "max": 0.0, "default": 0.0, "state_allowed": false}

static func _funding_ok(r: Dictionary, state: float) -> bool:
	if float(r["min"]) > float(r["max"]) + 0.0001:
		return false
	if state < 0.0:
		return true
	var s := Economy.snap_share(state)
	return s >= float(r["min"]) - 0.0001 and s <= float(r["max"]) + 0.0001

## Paylaşım neden ödenemiyor ("" = ödenebilir).
func funding_block_reason(peer_id: int, kind: String, state: float, total: float = -1.0) -> String:
	var r := funding_range(peer_id, kind, total)
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

## Mecliste en az bir vekili var mı? (Vekilsiz parti oy veremez, yasa ve
## gensoru veremez, vekil çalamaz.)
func has_seats(peer_id: int) -> bool:
	return int(last_seats.get(party_of(peer_id), 0)) > 0

## Gensoru hamlesi: muhalefet, hükümet görevde ve salt çoğunluğu yokken.
func can_censure(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and not is_party_member(peer_id) and funds_of(peer_id) >= GameRules.CENSURE_FUNDS_COST and has_seats(peer_id) \
		and GovernmentManager.phase == GovernmentManager.Phase.GOVERNING and GovernmentManager.has_government() \
		and not GovernmentManager.has_majority() and not is_government_party(peer_id) and _parl_stage_ok(peer_id, "censure")

## ERKEN SEÇİM hamlesi: meclis gerekir, oylama açık olmamalı, zaten erken
## seçim kararı yoksa.
func can_early_election(peer_id: int) -> bool:
	return can_choose_main_action(peer_id) and not is_party_member(peer_id) and funds_of(peer_id) >= GameRules.EARLY_ELECTION_FUNDS_COST \
		and has_seats(peer_id) and not early_election_pending and GovernmentManager.can_submit_law() 		and not early_request_used(peer_id) and not election_this_round() and _parl_stage_ok(peer_id, "law")

## Seçim zaten BU turun sonunda mı? (Son turda erken seçim önergesi anlamsız.)
func election_this_round() -> bool:
	return GameRules.is_election_round(round_number) or round_number >= GameRules.MAX_ROUNDS

## Partisi bu seçim aralığında erken seçim önergesi verdi mi?
func early_request_used(peer_id: int) -> bool:
	var last := int(early_requests.get(party_of(peer_id), -999))
	return round_number - last < GameRules.ELECTION_INTERVAL

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
	_note_main_action(peer_id)
	funds[peer_id] = funds_of(peer_id) - GameRules.EARLY_ELECTION_FUNDS_COST
	early_requests[party_of(peer_id)] = round_number
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
## state: devlet payı; 0.0.238'den beri miting hep parti kasasından (yalnız
## 0 geçerli); -1 = ödenebilir mi.
func can_miting(peer_id: int, province_id: String = "", state: float = -1.0, tier: int = DEFAULT_TIER, smear_target: int = -1) -> bool:
	if not can_choose_main_action(peer_id) or not valid_tier(tier) or miting_count(peer_id) >= action_limit(peer_id):
		return false
	if smear_target != -1 and (province_id == "" or not can_smear(peer_id, smear_target, province_id)):
		return false
	if not _funding_ok(funding_range(peer_id, "miting", miting_tier_cost(tier)), state):
		return false
	# BAĞIMSIZ siyasetçinin teşkilatı yoktur: her ilde miting yapabilir.
	if PartyManager.is_independent(peer_id):
		return province_id == "" or has_province(province_id)
	# 0.0.269: miting için ilde TEŞKİLAT şart (eskiden teşkilatsız miting az getiriyordu).
	return province_id == "" or (has_province(province_id) and organization_level(province_id, peer_id) > 0)

## MİTİNG HEDEFİ (0.0.282): seçmen grubu seçmek ZORUNLU ve teşkilattan
## bağımsız. İllerin vekil sayısı ortalaması en yakın tam sayıya yuvarlanır;
## ortalamanın altında vekil çıkaran ilde 1, ortalama ve üstünde 2 grup hedeflenir.
func miting_focus_slots(_peer_id: int, province_id: String) -> int:
	return 2 if province_seat_count(province_id) >= average_province_seats() else 1

func average_province_seats() -> int:
	if _province_seat_counts.is_empty():
		return 0
	var total := 0
	for province_id in _province_seat_counts:
		total += int(_province_seat_counts[province_id])
	return int(roundf(float(total) / float(_province_seat_counts.size())))

## Hedef grupları tam mı (mitingi düzenlemek için şart).
func miting_focus_complete(peer_id: int, province_id: String, focus: Array) -> bool:
	return _clean_focus(peer_id, province_id, focus).size() == miting_focus_slots(peer_id, province_id)

func _complete_focus(peer_id: int, province_id: String, focus: Array) -> Array:
	var result := _clean_focus(peer_id, province_id, focus)
	var slots := miting_focus_slots(peer_id, province_id)
	for group in BotBrain.miting_focus(peer_id, province_id, slots + result.size()):
		if result.size() >= slots:
			break
		if not result.has(group):
			result.append(group)
	return result

## Odak listesini temizler: geçerli, tekrarsız, en çok hedef sayısı kadar.
func _clean_focus(peer_id: int, province_id: String, focus: Array) -> Array:
	var result: Array = []
	for group in focus:
		if VoterGroups.is_group(String(group)) and not result.has(String(group)) \
				and result.size() < miting_focus_slots(peer_id, province_id):
			result.append(String(group))
	return result

## Ülkedeki grup seçmen sayıları.
func national_group_counts() -> Dictionary:
	return VoterGroups.national_counts(province_voters())

## Mitingin bu ildeki grup kazançları (ham; yorgunluk dahil, azalan getiri hariç).
func miting_group_gains(peer_id: int, province_id: String, focus: Array = [], tier_mult: float = 1.0) -> Array:
	var pid := party_of(peer_id)
	var fatigue: Dictionary = miting_fatigue.get(pid, {})
	var result: Array = []
	for effect in PublicOpinion.miting_gains(province_profile(province_id), national_group_counts(),
			_miting_mult(peer_id, province_id) * tier_mult, focus):
		var group := String(effect["group"])
		result.append({"group": group, "gain": float(effect["gain"]) * PublicOpinion.miting_fatigue_mult(float(fatigue.get(group, 0.0)))})
	return result

func _miting_mult(peer_id: int, province_id: String) -> float:
	var mult := PublicOpinion.miting_org_mult(organization_level(province_id, peer_id))
	return mult * PoliticianPresets.effect(peer_id, "miting")

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
	if is_party_member(peer_id):
		return false
	if card_type == CardPresets.EARLY_ELECTION_CARD_TYPE:
		return false  # artık hamle (bkz. can_early_election)
	# İTTİFAK (0.0.227): ortağa saldırı kartı oynanamaz.
	if target_peer_id != -1 and are_allies(peer_id, target_peer_id):
		return false
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
		# 0.0.237: karalama yine tek başına oynanır (karta dokun / sürükle → il → parti).
		return can_smear(peer_id, target_peer_id, target_province)
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

## KARALAMA (mitingin içinde): kart elde, hedef başka (ittifak dışı) parti,
## ilde teşkilat (bağımsızın teşkilatı yoktur, her ilde yapabilir).
func can_smear(peer_id: int, target_peer_id: int, province_id: String) -> bool:
	if not (inventories.get(peer_id, []) as Array).has(CardPresets.PROPAGANDA_CARD_TYPE) or is_party_member(peer_id):
		return false
	if target_peer_id == -1 or not party_ids().has(party_of(target_peer_id)) or PartyManager.same_party(target_peer_id, peer_id) \
			or are_allies(peer_id, target_peer_id):
		return false
	return has_province(province_id) and (organization_level(province_id, peer_id) > 0 or PartyManager.is_independent(peer_id))

## Bu ilde karalama yapılabilecek partiler (kart eldeyse).
func smear_targets(peer_id: int, province_id: String) -> Array:
	var result: Array = []
	for pid in party_ids():
		if can_smear(peer_id, int(pid), province_id):
			result.append(int(pid))
	return result

# --- Güç sorguları ------------------------------------------------------------

## GİDİŞAT: şimdi seçim olsa beklenen ulusal oy − son seçimdeki oy (yüzde
## puanı). Seçim yoksa beklenen oy − 0. Botlar erken seçim kararında kullanır.
func vote_trend(peer_id: int) -> float:
	var pid := party_of(peer_id)
	if last_vote_shares.is_empty():
		return 0.0
	return float(_expected_national().get(pid, 0.0)) * 100.0 - float(last_vote_shares.get(pid, 0.0))

func _release_secret_news() -> void:
	if _secret_news.is_empty():
		return
	var news := _secret_news.duplicate(true)
	_secret_news.clear()
	# Sunum sırası oyun RNG'sini ve oyun kurallarını etkilemez.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(news.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var item = news[i]
		news[i] = news[j]
		news[j] = item
	_push_state({"type": "secret_news", "news": news})


## İllerin seçmen profilleri (oyun başında üretilir). Oyun kurulmamışsa
## (testler, editör) örnek profillere düşer.
func province_voters() -> Dictionary:
	if province_profiles.is_empty():
		return ElectionModel.load_province_voters()
	return province_profiles

func province_profile(province_id: String) -> Dictionary:
	return province_voters().get(province_id, {})

## Partinin seçimde kullanılan grup yakınlıkları (ittifakta karışım).
func effective_groups(peer_id: int) -> Dictionary:
	var pid := party_of(peer_id)
	var groups := PartyManager.groups_of(pid)
	var alliance_id := alliance_of(pid)
	if alliances_enabled and alliance_id >= 0:
		groups = VoterGroups.alliance_blend(groups, _alliance_blend_members(alliances[alliance_id].get("members", [])))
	return groups

## İdeoloji karışımının üyeleri: taban hitap + ağırlık (son oy payı; seçim
## olmadıysa eşit). Hesap döngüye girmesin diye beklenen oy kullanılmaz.
func _alliance_blend_members(members: Array) -> Array:
	var result: Array = []
	for pid in members:
		result.append({"groups": PartyManager.groups_of(int(pid)), "weight": float(last_vote_shares.get(int(pid), 10.0))})
	return result

## Katılım önizlemesi: party_id bu ittifaka girerse etkin hitabı nasıl değişir?
## [[grup, önce, sonra], ...] en büyük değişimden küçüğe.
func alliance_preview(party_id: int, alliance_id: int) -> Array:
	var pid := party_of(party_id)
	if not alliances.has(alliance_id):
		return []
	var members: Array = (alliances[alliance_id].get("members", []) as Array).duplicate()
	if not members.has(pid):
		members.append(pid)
	var before := PartyManager.groups_of(pid)
	var after := VoterGroups.alliance_blend(before, _alliance_blend_members(members))
	var rows: Array = []
	for group in VoterGroups.GROUP_IDS:
		rows.append([group, float(before.get(group, 0.0)), float(after.get(group, 0.0))])
	rows.sort_custom(func(a, b): return absf(a[2] - a[1]) > absf(b[2] - b[1]))
	return rows

## Partinin bu ittifaktan etkilenen bütün değerleri tek satırda ("Emekliler 90 → 80").
func alliance_preview_text(party_id: int, alliance_id: int, count: int = 3) -> String:
	var parts: Array[String] = []
	for row in alliance_preview(party_id, alliance_id):
		if parts.size() >= count or absf(float(row[2]) - float(row[1])) < 0.5:
			break
		parts.append("%s %d » %d" % [VoterGroups.title(String(row[0])), roundi(float(row[1])), roundi(float(row[2]))])
	return ", ".join(PackedStringArray(parts))

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

## Bu tur sonunda hazineye girecek vergi geliri.
func expected_revenue(level: int = -1) -> float:
	return Economy.revenue(tax_level() if level < 0 else level)

## VERGİ ÇARPANI (0.0.259): seçim döngüsünde bu tur kaçıncı tur (1..aralık).
## Seçime yaklaştıkça vergi seçmene daha çok yansır.
func tax_cycle_mult() -> int:
	var interval := maxi(1, GameRules.ELECTION_INTERVAL)
	var left := maxi(0, next_election_round() - round_number)
	return clampi(interval - left, 1, interval)

## Bu turda bir sırada hükümete yazılan toplam vergi etkisi (ulusal puan).
func tax_turn_effect(level: int = -1) -> float:
	return Economy.tax_turn_effect(tax_level() if level < 0 else level, tax_cycle_mult())

## Bu partinin bir sıradaki vergi payı (hükümette değilse 0): bakanlık puanı
## payı × meslek çarpanı.
func tax_turn_effect_of(peer_id: int, level: int = -1) -> float:
	var pid := party_of(peer_id)
	if not GovernmentManager.has_government() or not GovernmentManager.government_party_ids().has(pid):
		return 0.0
	return tax_turn_effect(level) * quota_share(pid) * PoliticianPresets.party_effect(pid, "tax_mood")

## Her sıranın başında (host): vergi hükümet partilerine yazılır.
func _apply_tax_tick() -> void:
	if not GovernmentManager.has_government():
		return
	for pid in GovernmentManager.government_party_ids():
		var amount := tax_turn_effect_of(int(pid))
		if amount != 0.0:
			_add_national(int(pid), amount)

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
	var eligible := projected_eligible()
	var shares := expected_province_shares(province_id)
	var projection := {}
	for pid in party_ids():
		projection[pid] = {"percent": float(shares.get(pid, 0.0))}
	return _noisy_poll(projection, error, "%s:%d:%d" % [province_id, party_of(peer_id), round_number], province_seat_count(province_id),
		eligible)

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
func projected_eligible() -> Array:
	var national := {}
	var total := 0.0
	for province_id in _province_ids:
		var seats := float(province_seat_count(province_id))
		var shares := expected_province_shares(province_id)
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

## Gürültüsüz beklenen il payları (peer -> yüzde): bağlı seçmen + kararsızların
## sandığa giden kısmı eşit bölünür (bkz. ElectionModel.voter_shares).
func expected_province_shares(province_id: String) -> Dictionary:
	_vb_ensure()
	var parties := _vb_parties()
	var shares := ElectionModel.voter_shares(_vb_province_state(province_id, parties), parties, {})
	for pid in shares.keys():
		shares[pid] = float(shares[pid]) * 100.0
	return shares

## Gürültüsüz beklenen ulusal paylar (toplam 1). Aynı kare içinde önbellekli:
## bir harita çizimi 67 kez sormasın.
var _national_cache_frame := -1
var _national_cache: Dictionary = {}
func _expected_national() -> Dictionary:
	if _national_cache_frame == Engine.get_process_frames() and not _national_cache.is_empty():
		return _national_cache
	var profiles := {}
	var seats := {}
	for province_id in _province_ids:
		profiles[province_id] = province_profile(province_id)
		seats[province_id] = province_seat_count(province_id)
	var national := {}
	var total := 0.0
	for province_id in _province_ids:
		var n := float(province_profile(province_id).get("_electorate", province_seat_count(province_id)))
		var shares := expected_province_shares(province_id)
		for peer_id in shares.keys():
			national[peer_id] = float(national.get(peer_id, 0.0)) + float(shares[peer_id]) / 100.0 * n
		total += n
	if total > 0.0:
		for peer_id in national.keys():
			national[peer_id] = float(national[peer_id]) / total
	_national_cache = national
	_national_cache_frame = Engine.get_process_frames()
	return _national_cache

## Şimdi seçim olsa bu ilde: peer_id -> {"percent", "seats"} (gürültüsüz beklenen
## oylar, ildeki vekiller D'Hondt ile; baraj yok sayılır). Gözcü raporu için.
func province_projection(province_id: String) -> Dictionary:
	var shares := expected_province_shares(province_id)
	var alloc := ElectionModel.allocate(shares, projected_eligible(), province_seat_count(province_id))
	var result := {}
	for peer_id in party_ids():
		result[peer_id] = {"percent": float(shares.get(peer_id, 0.0)), "seats": int(alloc.get(peer_id, 0))}
	return result

## Güç haritası: bu partinin ANKETİ olan illerde (teşkilat 2+) anlık seçim
## tahmini: province_id -> {peer_id -> {"percent", "seats", "quotient"},
## "seat_count"}. quotient: ildeki son kazanan D'Hondt bölümü (bir vekile ne
## kadar yakın olunduğunu ölçmek için). peer_id = -1: tüm iller, gürültüsüz.
func projection_all(viewer: int = -1) -> Dictionary:
	var eligible := projected_eligible()
	var result := {}
	for province_id in _province_ids:
		var error := poll_error(viewer, province_id) if viewer != -1 else 0.0
		if error < 0.0:
			continue
		var seat_count := province_seat_count(province_id)
		var shares := expected_province_shares(province_id)
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

## Ülke genelinde yarışan partilerin seçimdeki grup yakınlıkları.
## BAĞIMSIZLAR dahil değil: sadece memleketlerinde aday olurlar
## (bkz. _add_independent_seats).
func _group_profiles() -> Dictionary:
	var result := {}
	for peer_id in party_ids():
		if PartyManager.is_independent(peer_id):
			continue
		result[peer_id] = effective_groups(peer_id)
	return result

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
## Oyundan kaldırılan kartlar: eski kayıttaki ellerden düşer (0.0.232: bonus kart).
const REMOVED_CARD_TYPES := ["bonus_kart"]
const PLAYER_HIDDEN_LOG_KINDS := ["bagis_kampanyasi", "bagis_kampanyasi_guclu"]

func log_event(text: String, peer_id: int = -1, province: String = "", kind: String = "system") -> void:
	if text.strip_edges() == "":
		return
	# ANA (geliştirici) LOG: her şey konsola ve indirilebilir oyun günlüğüne yazılır.
	print("[LOG r%d] %s" % [round_number, text])
	full_log.append("[%s] %s" % [GameRules.period_label(maxi(1, round_number)), text])
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
	_broadcast_snapshot.clear()
	_received_snapshot.clear()
	inventories.clear()
	alliances = {}
	alliance_requests = {}
	former_allies = {}
	alliances_enabled = bool(MultiplayerManager.world_settings.get("alliances", true))
	event_log.clear()
	BotBrain.reset_skills()
	funds = {}
	approval = {}
	invest_requests = {}
	for peer_id in MultiplayerManager.players.keys():
		inventories[peer_id] = []
		funds[peer_id] = GameRules.FUNDS_START
	turn_order = MultiplayerManager.players.keys().duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	_grant_turn_income()
	law_rounds = {}
	tax_rounds = {}
	constitution_rounds = {}
	early_requests = {}
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
	miting_fatigue = {}
	election_groups = {}
	former_parties = {}
	axis_history = {}
	game_stats = {}
	economy = Economy.start_state()
	disaster = {}
	_pending_disaster_fx = {}
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
	# Erken seçimle uzamış oyun: lobideki uzunluğa dön.
	max_rounds_override = 0
	GameRules.set_max_rounds_override(0)
	_secret_news.clear()
	province_events = {}
	# Her oyunda üretilen ülke herkese tam durumla gönderilir.
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
	province_profiles = VoterGroups.generate_profiles(_rng, _province_ids, _province_seat_counts, GameMap.electorate_counts())
	organizations = {}
	_apply_politician_starts()
	# SEÇMEN TABANI: başlangıç hitabından (çekirdek gruplar, geçmiş) kurulur.
	voter_base = {}
	_vb_ready = false
	_vb_ensure()
	_grant_start_voters()
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
## iş insanı ek para, belediye başkanı rastgele illerde teşkilat alır.
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
		if PoliticianPresets.has_background(peer_id, "is_insani"):
			funds[peer_id] = funds_of(peer_id) + PoliticianPresets.BUSINESS_START_FUNDS
		if PoliticianPresets.has_background(peer_id, "belediye_baskani"):
			_grant_mayor_orgs(peer_id, home)
		if home == "":
			continue
		organizations[home] = organizations.get(home, {})
		organizations[home][peer_id] = PoliticianPresets.HOMETOWN_ORG_LEVEL

## Oyun başı: memleket ve başlangıç teşkilatları (memleket, belediye başkanı)
## o illerde seçmen olarak yazılır (teşkilat kurmakla aynı kural, bkz. _apply_organization).
func _grant_start_voters() -> void:
	for province_id in organizations.keys():
		for pid in organizations[province_id].keys():
			_add_local(String(province_id), int(pid), PublicOpinion.org_activity(int(organizations[province_id][pid])) 				* PoliticianPresets.party_effect(int(pid), "org"))
	for pid in party_ids():
		var home := PoliticianPresets.hometown_of(int(pid))
		if home != "" and _province_ids.has(home):
			_add_local(home, int(pid), PoliticianPresets.HOMETOWN_ACTIVITY)

## Belediye başkanı: il sayısının MAYOR_ORG_SHARE'i kadar (en az 1) rastgele
## ilde 1. seviye teşkilat (memleket ve teşkilatlı iller hariç).
func _grant_mayor_orgs(peer_id: int, home: String) -> void:
	var pool: Array = []
	for province_id in _province_ids:
		if String(province_id) != home and organization_level(String(province_id), peer_id) <= 0:
			pool.append(String(province_id))
	var count := mini(pool.size(), maxi(1, int(round(_province_ids.size() * PoliticianPresets.MAYOR_ORG_SHARE))))
	for i in count:
		var province_id := String(pool.pop_at(_rng.randi() % pool.size()))
		organizations[province_id] = organizations.get(province_id, {})
		organizations[province_id][peer_id] = PoliticianPresets.MAYOR_ORG_LEVEL

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
	max_rounds_override = 0
	GameRules.set_max_rounds_override(0)
	_secret_news.clear()
	province_events = {}
	province_profiles = {}
	miting_fatigue = {}
	election_groups = {}
	former_parties = {}
	economy = Economy.start_state()
	organizations = {}
	turmoil = {}
	splinters = {}
	credibility = {}
	funds = {}
	game_finished = false
	final_ranking = []
	game_end_reason = ""
	_round_end_pending = false

# --- Oyuncu eylemleri -------------------------------------------------------

## Bu oyuncu için desteden çekilebilecek kartlar ve ağırlıkları.
##   - karalama her zaman,
##   - popülizm ve bağış kampanyası her zaman,
##   - vekil çalma ve kart çalma ilk seçimden (meclis oluştuktan) sonra.
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
	# Popülizm sürerken yeni popülizm çıkmaz.
	if peer_id == -1 or populism_rounds_left(peer_id) <= 0:
		weights[CardPresets.POPULISM_CARD_TYPE] = WEIGHT_POPULISM
	weights[CardPresets.FUNDS_BONUS_CARD_TYPE] = WEIGHT_FUNDS_BONUS
	weights[CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE] = WEIGHT_FUNDS_BONUS_STRONG
	weights[CardPresets.PENALTY_CARD_TYPE] = WEIGHT_PENALTY
	weights[CardPresets.SELF_TURMOIL_CARD_TYPE] = WEIGHT_SELF_TURMOIL
	weights[CardPresets.FLEX_CARD_TYPE] = WEIGHT_FLEX
	# Anket oyunun ilk turunda ve seçimden sonraki ilk turda gelmez.
	if round_number > 1 and round_number != last_election_round + 1:
		weights[CardPresets.POLL_CARD_TYPE] = WEIGHT_POLL
	# Kart çalma da ilk seçimden önce desteye girmez (0.0.191).
	if not last_seats.is_empty():
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
func invest(province_id: String, state: float = 1.0, tier: int = DEFAULT_TIER) -> void:
	if not can_invest(multiplayer.get_unique_id(), province_id, state, tier):
		return
	if _is_authority():
		_apply_invest_move(multiplayer.get_unique_id(), province_id, state, tier)
	else:
		_request_invest.rpc_id(1, province_id, state, tier)

## Gensoru hamlesi (CENSURE_FUNDS_COST): meclis oylaması açılır.
func censure() -> void:
	if not can_censure(multiplayer.get_unique_id()):
		return
	if _is_authority():
		_apply_censure_move(multiplayer.get_unique_id())
	else:
		_request_censure.rpc_id(1)

## Miting hamlesi: seçilen ilde miting (MITING_FUNDS_COST). focus: odak gruplar
## (en çok ildeki teşkilat seviyesi kadar).
func miting(province_id: String, state: float = 0.0, focus: Array = [], tier: int = DEFAULT_TIER, smear_target: int = -1) -> void:
	if not can_miting(multiplayer.get_unique_id(), province_id, state, tier, smear_target):
		return
	if _is_authority():
		_apply_miting_move(multiplayer.get_unique_id(), province_id, state, focus, tier, smear_target)
	else:
		_request_miting.rpc_id(1, province_id, state, focus, tier, smear_target)

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
	_note_main_action(peer_id)
	var anonymous := is_anonymous_card(card_type)
	if not anonymous:
		card_played.emit(peer_id, card_type)
	hand.remove_at(hand_index)
	_event_message = ""
	var seats_changed_now := _apply_card_effect(peer_id, card_type, target_peer_id, target_province)
	var event := {"type": "played", "peer_id": peer_id, "card": card_type,
		"target": target_peer_id, "province": target_province, "seats_changed": seats_changed_now}
	if _event_message != "":
		event["message"] = _event_message
	if anonymous:
		event["peer_id"] = target_peer_id
		event["actor_hidden"] = true
		_secret_news.append(event)
		# Herkese giden olayda kart, hedef ve mesaj bulunmaz.
		event = {"type": "sync"}
		if peer_id == multiplayer.get_unique_id():
			card_played.emit(peer_id, card_type)
		elif peer_id > 0 and not _is_local_only():
			_secret_play_confirmed.rpc_id(peer_id, card_type)
	# Hiçbir kart sırayı devretmez; tur sadece "Turu Bitir" ya da süreyle biter.
	_push_state(event, seats_changed_now)
	
## Turu bitir (voluntary=false: süre doldu). Bağış kampanyası yok.
func _apply_pass(peer_id: int, voluntary: bool = true) -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id():
		return
	# Kartını çekmeden biten sıra: kart yine verilir (eski otomatik dağıtım gibi).
	if needs_turn_draw(peer_id):
		_apply_draw(peer_id, true)
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
	_note_main_action(peer_id)
	if not GovernmentManager.submit_law(peer_id, law_type):
		return
	# 0.0.300: yasa sekmesi kapanmaz; her yasa türü (grup, vergi, anayasa,
	# erken seçim) turda birer kez sunulur.
	funds[peer_id] = funds_of(peer_id) - law_funds_cost(peer_id, law_type)
	if CardPresets.is_tax_law(law_type):
		tax_rounds[party_of(peer_id)] = round_number
	else:
		law_rounds[party_of(peer_id)] = round_number
	var event := {"type": "law", "peer_id": peer_id, "law": law_type}
	if _event_message != "":
		event["message"] = _event_message
	_push_state(event)

func _apply_organization(peer_id: int, province_id: String) -> void:
	if not can_build_organization(peer_id, province_id):
		return
	_note_main_action(peer_id)
	funds[peer_id] = funds_of(peer_id) - org_cost_for(peer_id, province_id)
	var entry: Dictionary = organizations.get(province_id, {})
	var level := int(entry.get(party_of(peer_id), 0)) + 1
	entry[party_of(peer_id)] = level
	organizations[province_id] = entry
	var verb := L.t("kurdu") if level == 1 else L.t("geliştirdi")
	_log_province(province_id, L.t("%s teşkilat %s (seviye %d)") % [_party_name(peer_id), verb, level])
	# TEŞKİLAT SEÇMENİ: kurulunca / geliştirilince ilde seçmen kazanılır
	# (seviye farkı kadar puan, meslek çarpanıyla; popülizm büyütür).
	var org_gain := (PublicOpinion.org_activity(level) - PublicOpinion.org_activity(level - 1)) 		* PoliticianPresets.party_effect(peer_id, "org")
	_add_local(province_id, peer_id, org_gain, true)
	# Teşkilat parti içini toparlar.
	_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_ORG)
	_push_state({"type": "organization", "peer_id": peer_id, "province": province_id,
		"message": L.t("%s, %s'da teşkilat %s (seviye %d).") % [_actor_name(peer_id), _province_name(province_id), verb, level]})

## state: devletin payı (varsayılan tamamı devletten, eski kural). Bedel
## TEK SEFER düşer: devlet payı hazineden, parti payı (+ sabit hamle bedeli)
## parti kasasından; gerçek paylaşım kayda geçer.
func _apply_invest_move(peer_id: int, province_id: String, state: float = 1.0, tier: int = DEFAULT_TIER) -> void:
	if not can_invest(peer_id, province_id, state, tier):
		return
	var amount := invest_tier_cost(tier)
	_note_main_action(peer_id)
	var flow := _flow_for(peer_id)
	flow["invests"] = int(flow.get("invests", 0)) + 1
	var split := Economy.split_cost(amount, state)
	funds[peer_id] = funds_of(peer_id) - float(split["party"])
	_spend_quota(peer_id, float(split["state"]))
	var before := state_treasury()
	economy["treasury"] = before - float(split["state"])
	_event_message = ""
	_apply_investment(peer_id, province_id, amount)
	_fulfil_invest_request(province_id, amount)
	_push_state({"type": "invest", "peer_id": peer_id, "province": province_id, "message": _event_message,
		"econ": {"kind": "invest", "peer_id": peer_id, "province": province_id, "cost": float(split["state"]),
			"party_cost": float(split["party"]), "before": before, "after": state_treasury()}})

func _apply_censure_move(peer_id: int) -> void:
	if not can_censure(peer_id):
		return
	stat_add(peer_id, "censures")
	_note_main_action(peer_id)
	_parl_close(peer_id, "censure")
	funds[peer_id] = funds_of(peer_id) - GameRules.CENSURE_FUNDS_COST
	_push_state({"type": "censure", "peer_id": peer_id,
		"message": L.t("%s hükümete gensoru verdi: meclis oylaması başladı.") % _party_name(peer_id)})
	GovernmentManager.submit_censure(peer_id)

## tier: bütçe kademesi (MITING_TIERS); smear_target: mitingte karalanacak
## parti (-1 = yok). Karalama ayrı hak tüketmez; kart ancak miting
## gerçekleşince düşer (kartların bedeli yok).
func _apply_miting_move(peer_id: int, province_id: String, state: float = 0.0, focus: Array = [],
		tier: int = DEFAULT_TIER, smear_target: int = -1) -> void:
	if not can_miting(peer_id, province_id, state, tier, smear_target):
		return
	# Arayüz hedef seçimini zorunlu tutar; eksik gelirse (eski istemci, test)
	# kalan yerler partinin en uygun gruplarıyla dolar: her miting hedeflidir.
	focus = _complete_focus(peer_id, province_id, focus)
	_note_main_action(peer_id)
	var flow := _flow_for(peer_id)
	flow["mitings"] = int(flow.get("mitings", 0)) + 1
	var total := miting_tier_cost(tier)
	var split := Economy.split_cost(total, state)
	funds[peer_id] = funds_of(peer_id) - float(split["party"])
	_spend_quota(peer_id, float(split["state"]))
	var before := state_treasury()
	economy["treasury"] = before - float(split["state"])
	if float(split["state"]) > 0.0:
		economy_event.emit({"kind": "invest", "cost": float(split["state"]), "before": before, "after": state_treasury()})
	_event_message = ""
	_apply_miting(peer_id, province_id, focus, miting_tier_mult(tier))
	var miting_message := _event_message
	if smear_target != -1:
		var hand: Array = inventories.get(peer_id, [])
		hand.erase(CardPresets.PROPAGANDA_CARD_TYPE)
		_event_message = ""
		_apply_propaganda(peer_id, smear_target, province_id)
		miting_message += " " + L.t("Kürsüden %s'a yüklendi.") % _party_name(smear_target)
		_event_message = miting_message
	# Bağımsızın ve üyenin mitingi kendi güvenilirliğini de artırır.
	if PartyManager.is_independent(peer_id) or is_party_member(peer_id):
		credibility_add(peer_id, MITING_CREDIBILITY)
	_push_state({"type": "miting", "peer_id": peer_id, "province": province_id, "message": _event_message,
		"tier": tier, "smear": smear_target})

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
			stat_add(target_peer_id, "bad")
			_stat_deed("isyan", peer_id, target_peer_id)
			# İÇ KARIŞIKLIK: ulusal destek düşer, partide (gizli) karışıklık büyür.
			_add_national(target_peer_id, -PublicOpinion.REBELLION_NATIONAL_DAMAGE)
			_add_turmoil(target_peer_id, PublicOpinion.TURMOIL_REBELLION)
			# ANONİM: iç karışıklığı kimin kışkırttığı hiçbir yerde gösterilmez.
			_event_message = L.t("%s'da iç karışıklık çıktı: parti sarsıldı, ulusal desteği düştü.") % _party_name(target_peer_id)
		CardPresets.CARD_THEFT_CARD_TYPE:
			_apply_card_theft(peer_id, target_peer_id)
		CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE:
			var strong_gain := funds_bonus_amount(peer_id, true)
			funds[peer_id] = funds_of(peer_id) + strong_gain
			_event_message = L.t("%s büyük bir bağış kampanyası yaptı (+%s).") % [_party_name(peer_id), GameRules.cost_text(strong_gain)]
		CardPresets.EARLY_ELECTION_CARD_TYPE:
			GovernmentManager.submit_early_election(peer_id)
			_event_message = L.t("%s erken seçim önergesi verdi.") % _party_name(peer_id)
		CardPresets.POPULISM_CARD_TYPE:
			populism[party_of(peer_id)] = round_number + GameRules.POPULISM_ROUNDS
			_event_message = L.t("%s popülizme başladı: bu dönem hamleleri daha etkili.") % _party_name(peer_id)
		CardPresets.FUNDS_BONUS_CARD_TYPE:
			var weak_gain := funds_bonus_amount(peer_id, false)
			funds[peer_id] = funds_of(peer_id) + weak_gain
			_event_message = L.t("%s bağış kampanyası yaptı (+%s).") % [_party_name(peer_id), GameRules.cost_text(weak_gain)]
		CardPresets.PROPAGANDA_CARD_TYPE:
			_apply_propaganda(peer_id, target_peer_id, target_province)
		CardPresets.POLL_CARD_TYPE:
			# 0.0.300: anket elde bekler, oyuncu istediği an kullanır.
			polls[peer_id] = {"round": round_number, "parties": national_poll_snapshot(peer_id)}
			_event_message = L.t("%s ülke geneli bir anket yaptırdı.") % _party_name(peer_id)
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

## Miting: ildeki grupların bir kısmı seçmen olarak kazanılır (nüfusla
## orantılı, kalıcı). 0.0.285: provokasyon riski kalktı, miting hep işler.
func _apply_miting(peer_id: int, province_id: String, focus: Array = [], tier_mult: float = 1.0) -> void:
	stat_add(peer_id, "mitings")
	var moved := _apply_miting_positioning(peer_id, province_id, focus, tier_mult)
	_log_province(province_id, L.t("%s miting yaptı") % _party_name(peer_id))
	_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_MITING)
	_event_message = L.t("%s, %s'da miting yaptı.") % [_actor_name(peer_id), _province_name(province_id)]
	if moved != "":
		_event_message += L.t(" Hitabı %s.") % moved

## MİTİNGİN SİYASİ HİTABI: ildeki her grubun nüfusla orantılı bir kısmı
## kazanılır (odak gruplarda daha çok), diğer partilerden ve kararsızlardan
## alınır. Yorgunluk (aynı gruba art arda miting), azalan getiri ve çekirdek
## çarpanı uygulanır. Popülizm kazancı büyütür.
## Dönüş: kısa özet ("odak: Emekliler") ya da "".
func _apply_miting_positioning(peer_id: int, province_id: String, focus: Array = [], tier_mult: float = 1.0) -> String:
	var pid := party_of(peer_id)
	if PartyManager.is_independent(pid):
		return _apply_miting_positioning_legacy(peer_id, province_id, focus, tier_mult)
	var fatigue: Dictionary = miting_fatigue.get(pid, {})
	# SEÇMEN TABANI (0.0.228): ildeki seçmenin bir kısmı çekilir (bkz. _vb_miting).
	var gains := _vb_miting(pid, province_id, focus, _miting_mult(peer_id, province_id) * tier_mult * _own_effect(pid, 1.0))
	var national := national_group_counts()
	for group in gains.keys():
		var points := float(gains[group]) / maxf(1.0, float(national.get(group, 1.0))) * 100.0
		if points > 0.0:
			fatigue[group] = float(fatigue.get(group, 0.0)) + points
	if not fatigue.is_empty():
		miting_fatigue[pid] = fatigue
	if focus.is_empty():
		return ""
	var names: PackedStringArray = []
	for group in focus:
		names.append(VoterGroups.title(String(group)))
	return L.t("odak: %s") % ", ".join(names)

## Bağımsız siyasetçi seçmen tabanına girmez: eski hitap hesabı.
func _apply_miting_positioning_legacy(peer_id: int, province_id: String, focus: Array = [], tier_mult: float = 1.0) -> String:
	var pid := party_of(peer_id)
	var changes: Array = []
	for effect in miting_group_gains(peer_id, province_id, focus, tier_mult):
		changes.append({"peer": pid, "group": String(effect["group"]), "amount": _own_effect(pid, float(effect["gain"]))})
	PartyManager.apply_group_deltas(changes)
	return ""

## "1,8" gibi kısa sayı.
static func _num(value: float) -> String:
	return String.num(snappedf(value, 0.1), 1).replace(".", ",")

## Yatırım: getiren parti daha çok, hükümet ortakları daha az kazanır.
## İldeki bütün gruplardan seçmen; grup yakınlığına (ideolojiye) dokunmaz.
## Popülizm yatırımı büyütmez. Etkinin INVEST_IMMEDIATE'i hemen, kalanı
## sonraki INVEST_DELAY_ROUNDS tur sonunda dilim dilim gelir (bekleyen
## dilimler economy["investments"]'ta; seçimde sadece gelmiş olan sayılır).
## Yatırımın parti başına payı (toplam 1): INVEST_OWN_SHARE getirene, kalanı
## hükümet partilerine makam puanlarıyla orantılı. Makam puanı yoksa hepsi getirene.
func investment_shares(investor: int) -> Dictionary:
	var total := 1.0
	var shares := {investor: total * PublicOpinion.INVEST_OWN_SHARE}
	var rest := total - float(shares[investor])
	var points := {}
	var sum := 0
	for pid in GovernmentManager.government_party_ids():
		var p := GovernmentManager.round_points_of(int(pid))
		if p > 0:
			points[int(pid)] = p
			sum += p
	if sum <= 0:
		shares[investor] = total
		return shares
	for pid in points:
		shares[pid] = float(shares.get(pid, 0.0)) + rest * float(points[pid]) / float(sum)
	return shares

func _apply_investment(peer_id: int, province_id: String, amount: float = Economy.INVEST_COST) -> void:
	stat_add(peer_id, "invest", amount)
	var investor := party_of(peer_id)
	var scale := Economy.invest_scale(amount)
	var shares := investment_shares(investor)
	# SEÇMEN: yatırım ideolojiye bakmaz; ildeki BÜTÜN gruplardan seçmeni
	# getirene ve makam sahiplerine çeker. INVEST_IMMEDIATE kadarı hemen, kalanı
	# (varsa) sonraki dönemlerde eşit dilimlerle gelir (later: parti -> dilim ölçeği).
	var parts := {}
	var share_total := 0.0
	for pid in shares.keys():
		share_total += float(shares[pid])
	var later := {}
	for pid in shares.keys():
		parts[int(pid)] = float(shares[pid]) / maxf(0.0001, share_total)
		later[pid] = float(parts[int(pid)]) * scale * (1.0 - Economy.INVEST_IMMEDIATE) / float(Economy.INVEST_DELAY_ROUNDS)
	_vb_invest(province_id, parts, scale * Economy.INVEST_IMMEDIATE)
	if Economy.INVEST_IMMEDIATE < 1.0:
		var pending: Array = economy.get("investments", [])
		pending.append({"province": province_id, "party": investor, "round": round_number,
			"rounds_left": Economy.INVEST_DELAY_ROUNDS, "amounts": later})
		economy["investments"] = pending
	_ease_turmoil(peer_id, PublicOpinion.TURMOIL_EASE_INVEST * minf(1.0, scale))
	_log_province(province_id, L.t("Hükümet yatırımı — %s getirdi (%s)") % [_party_name(peer_id), Economy.money_full(amount)])
	_event_message = L.t("%s, %s'a hükümet yatırımı getirdi: %s.") % [_party_name(peer_id),
		_province_name(province_id), Economy.money_full(amount)]

## Yatırımın ildeki grup kazançları (ham): [{"group", "gain"}], tutarla orantılı.
func investment_group_gains(province_id: String, amount: float = Economy.INVEST_COST) -> Array:
	var result: Array = []
	var national := national_group_counts()
	var profile := province_profile(province_id)
	for group in VoterGroups.GROUP_IDS:
		var here := VoterGroups.group_count(profile, group)
		var total := float(national.get(group, 0.0))
		if here <= 0.0 or total <= 0.0:
			continue
		result.append({"group": group, "gain": PublicOpinion.INVEST_CONVERT * amount / Economy.INVEST_COST * here / total * VoterGroups.AFFINITY_MAX})
	return result

## Partinin her gruptaki TAHMİNİ OY PAYI (0..100): ildeki her grubun oyu
## partiler arasında hitap + kararsızların eşit payı × kamuoyu (ulusal + il)
## çarpanıyla paylaşılır, iller grup seçmeni ağırlığıyla toplanır. Grupların
## (büyüklükleriyle ağırlıklı) ortalaması ülke geneli oy oranına yaklaşır.
func group_vote_estimates(peer_id: int) -> Dictionary:
	# 0.0.228: kararsızlar gösterilmez; grubun partiye bağlı yüzdesi.
	if not PartyManager.is_independent(party_of(peer_id)):
		var result_vb := {}
		var levels := group_level_shares(peer_id)
		for group in levels.keys():
			var l: Array = levels[group]
			result_vb[group] = float(l[0]) + float(l[1]) + float(l[2])
		return result_vb
	var pid := party_of(peer_id)
	var parties := _group_profiles()
	var result := {}
	if not parties.has(pid):
		return result
	var profiles := province_voters()
	for group in VoterGroups.GROUP_IDS:
		var votes := 0.0
		var total := 0.0
		for province_id in profiles.keys():
			var count := VoterGroups.group_count(profiles[province_id], group)
			if count <= 0.0:
				continue
			votes += count * float(ElectionModel.shares_in_group(parties, group).get(pid, 0.0))
			total += count
		result[group] = votes / total * 100.0 if total > 0.0 else 0.0
	return result

## TUR SONU (host, tur başına TEK SEFER, seçimden önce): vergi geliri
## hazineye, bekleyen yatırım dilimleri illere gelir. Dönüş: log satırı.
func _advance_economy() -> String:
	Economy.advance(economy)
	var still: Array = []
	for entry in economy.get("investments", []):
		var province_id := String(entry["province"])
		var amounts: Dictionary = entry.get("amounts", {})
		for pid in amounts.keys():
			if PartyManager.parties.has(int(pid)):
				_vb_invest(province_id, {int(pid): 1.0}, float(amounts[pid]))
		entry["rounds_left"] = int(entry["rounds_left"]) - 1
		if int(entry["rounds_left"]) > 0:
			still.append(entry)
		else:
			_log_province(province_id, L.t("%s yatırımı tamamlandı") % _party_name(int(entry.get("party", -1))))
	economy["investments"] = still
	return L.t("Hazineye %s vergi geliri girdi (vergi %s). Hazine: %s.") % [Economy.money_full(float(economy["revenue"])),
		Economy.tax_title(tax_level()), Economy.money_full(state_treasury())]

## KARALAMA: hedefin bu ildeki seçmeninin PROPAGANDA_DEMOTE kadarı bir seviye
## düşer (en zayıf bağlılar kararsızlaşır); karalayan ilde PROPAGANDA_GAIN kadar
## seçmen kazanır. Meslek ve teşkilat çarpanları uygulanır.
func _apply_propaganda(peer_id: int, target_peer_id: int, province_id: String) -> void:
	stat_add(target_peer_id, "bad")
	# Meslek: atanın karalama gücü × hedefin karalamaya direnci.
	var profile_mult := PoliticianPresets.effect(peer_id, "propaganda_out") \
		* PoliticianPresets.party_effect(target_peer_id, "propaganda_in")
	var org_mult := PublicOpinion.org_action_mult(organization_level(province_id, peer_id))
	var demote := clampf(PublicOpinion.PROPAGANDA_DEMOTE * profile_mult * org_mult \
		* (PublicOpinion.POPULISM_GOOD_MULT if populism_rounds_left(peer_id) > 0 else 1.0), 0.0, 1.0)
	var before := float(vb_province_state(province_id)["attached"].get(party_of(target_peer_id), 0.0))
	_vb_scandal(target_peer_id, province_id, demote)
	var lost := before - float(vb_province_state(province_id)["attached"].get(party_of(target_peer_id), 0.0))
	_add_local(province_id, peer_id, PublicOpinion.PROPAGANDA_GAIN * org_mult, true)
	_log_province(province_id, L.t("%s, %s karşıtı kampanya yaptı (%s ildeki seçmeninin %%%s'ini kaybetti)") % [
		_party_name(peer_id), _party_name(target_peer_id), _party_name(target_peer_id), L.dec(lost / maxf(before, 0.0001) * 100.0, 0)])
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
	if passed:
		stat_add(proposer, "laws")
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
	var law_mult := PoliticianPresets.effect(proposer, "law")
	var gain := (PublicOpinion.LAW_GROUP_GAIN_PASSED if passed else PublicOpinion.LAW_GROUP_GAIN_REJECTED) * law_mult
	# GÜNDEM: gündemdeki gruba yasa sunana daha güçlü yazar (karşıt kayıp da büyür).
	if crisis_group() == group:
		gain *= PublicOpinion.AGENDA_LAW_MULT
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
	if crisis_group() == group:
		_crisis_law_approval(votes, passed, gov_ids)
	# KRİZE YANIT: krizin istediği gruba yasa sunan ya da EVET diyen kısmi ulusal destek kazanır.
	if not crisis_parties.is_empty():
		var names: PackedStringArray = []
		for pid in crisis_parties:
			_add_national(int(pid), PublicOpinion.CRISIS_RESPONSE_NATIONAL)
			names.append(_party_name(int(pid)))
		notes += L.t(" Krize yanıt verdi (seçmen kazandı): %s.") % ", ".join(names)
	if passed:
		notes += L.t(" %s +%d puan.") % [_actor_name(proposer), law_pass_score(proposer_in_gov)]
		_ease_turmoil(proposer_party, PublicOpinion.TURMOIL_EASE_LAW)
	_push_state({"type": "opinion", "peer_id": proposer, "message": L.t("%s %s — %s, %s seçmeninde güçlendi%s; %s seçmeninde biraz kaybetti.%s") % [
		law["title"], L.t("KABUL EDİLDİ") if passed else L.t("reddedildi"), _party_name(proposer), law["group_title"],
		"" if passed else L.t(" (vaat olarak, az)"), VoterGroups.title(opposite), notes]})

## VERGİ YASASI sonucu. Kabul: kademe değişir; gelir bir sonraki tur sonundan
## itibaren yeni kademeyle, seçmen etkisi bir sonraki sıradan itibaren
## (_apply_tax_tick: her sırada hükümete, seçime yaklaştıkça artarak).
func _apply_tax_result(proposer: int, level: int, passed: bool) -> void:
	var old := tax_level()
	var title := CardPresets.card_title(CardPresets.tax_law_type(level))
	if not passed or level == old:
		_push_state({"type": "opinion", "peer_id": proposer, "message": L.t("%s reddedildi — vergiler %s kalıyor.") % [
			title, Economy.tax_title(old)]})
		return
	economy["tax_from"] = old
	economy["tax"] = level
	economy["tax_round"] = round_number
	_ease_turmoil(party_of(proposer), PublicOpinion.TURMOIL_EASE_LAW)
	_push_state({"type": "opinion", "peer_id": proposer, "econ": {"kind": "tax", "from": old, "to": level},
		"message": L.t("%s KABUL EDİLDİ — vergiler %s » %s. Dönem geliri %s » %s. %s +%d puan.") % [
		title, Economy.tax_title(old), Economy.tax_title(level), Economy.money_full(expected_revenue(old)),
		Economy.money_full(expected_revenue(level)), _actor_name(proposer), law_pass_score(true)]})

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

## Eski ayrı KRİZ kaldırıldı (0.0.182: gündemle birleşti); hep "".
func crisis_type() -> String:
	return ""

## Süren siyasi krizin seçmen grubu ya da "".
func crisis_group() -> String:
	return String(CardPresets.agenda_data(agenda_type()).get("group", ""))

## Süren siyasi kriz ("kriz_<grup>") ya da "".
func agenda_type() -> String:
	if agenda.is_empty() or round_number >= int(agenda.get("until", 0)):
		return ""
	return String(agenda.get("type", ""))

func agenda_rounds_left() -> int:
	return maxi(0, int(agenda.get("until", 0)) - round_number) if agenda_type() != "" else 0

## Gündemin ödüllendirdiği grup (tek elemanlı; gündem yoksa boş).
func agenda_groups() -> Array:
	var group := crisis_group()
	return [] if group == "" else [group]

## Bu yasa gündemdeki grup için mi?
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
			_push_state({"type": "agenda", "message": L.t("Kriz yatıştı: %d dönem sakin, sonra yeni krizler.") % GameRules.AGENDA_GAP})
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
	var type := "kriz_%s" % groups[_rng.randi() % 2]
	agenda = {"type": type, "until": round_number + 1, "index": pos + 1}
	var data := CardPresets.agenda_data(type)
	crisis = {}
	var message := L.t("SİYASİ KRİZ: %s — %s.") % [data["title"], CardPresets.agenda_effect_text(type)]
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

## Başka bir sistemin (ör. GovernmentManager) ülke geneli seçmen etkisi için.
func add_national_points(peer_id: int, amount: float) -> void:
	_add_national(peer_id, amount)

## ÜLKE GENELİ SEÇMEN ETKİSİ (bkz. _shift_voters). own=true: parti bu etkiyi
## KENDİ hamlesiyle aldı (popülizm uygulanır).
func _add_national(peer_id: int, amount: float, own: bool = false) -> void:
	_shift_voters(peer_id, "", amount, own)

## Partinin bağlı seçmeni (province_id "" = bütün iller). Testler ve botlar için.
func voter_total(peer_id: int, province_id: String = "") -> float:
	_vb_ensure()
	var pid := party_of(peer_id)
	if not voter_base.has(pid):
		return 0.0
	var arr: PackedFloat32Array = voter_base[pid]
	var total := 0.0
	for pi in _province_ids.size():
		if province_id != "" and String(_province_ids[pi]) != province_id:
			continue
		for gi in VB_GROUPS:
			total += _vb_cell(arr, pi, gi)
	return total

## İldeki seçmenin yüzde kaçı bu partiye bağlı (0..100). Partinin kendi
## bildiği değer (anket değil): il panelinde gösterilir.
func attached_share(peer_id: int, province_id: String) -> float:
	_vb_ensure()
	var pi := _province_ids.find(province_id)
	if pi < 0:
		return 0.0
	var total := 0.0
	for gi in VB_GROUPS:
		total += _vb_count(pi, gi)
	return voter_total(peer_id, province_id) / total * 100.0 if total > 0.0 else 0.0

## Bir ildeki bütün gruplarda seçmen etkisi (bkz. _shift_voters).
func _add_local(province_id: String, peer_id: int, amount: float, own: bool = false) -> void:
	_shift_voters(peer_id, province_id, amount, own)

## OY KAZANMA / KAYBETME (0.0.284, tek kural): oy = seçmen. Bütün etkiler
## partinin seçmen tabanını değiştirir; ayrı bir kamuoyu puanı yoktur.
##   puan > 0: her (il, grup) hücresinde grubun seçmeninin puan × VOTER_GAIN
##             kadarı kararsızlardan partiye 1. seviyeden bağlanır (kararsız
##             yetmezse yettiği kadar).
##   puan < 0: partinin her hücredeki seçmeninin |puan| × VOTER_LOSS kadarı
##             kararsızlara döner; önce en zayıf bağlılar (1. seviye) gider.
## province_id "" = bütün iller.
func _shift_voters(peer_id: int, province_id: String, points: float, own: bool = false) -> void:
	if own:
		points = _own_effect(peer_id, points)
	if is_zero_approx(points) or peer_id == -1:
		return
	_vb_ensure()
	var pid := party_of(peer_id)
	if not voter_base.has(pid):
		return
	for pi in _province_ids.size():
		if province_id != "" and String(_province_ids[pi]) != province_id:
			continue
		for gi in VB_GROUPS:
			var arr: PackedFloat32Array = voter_base[pid]
			var i := _vb_i(pi, gi, 0)
			if points > 0.0:
				arr[i] += minf(_vb_count(pi, gi) * points * PublicOpinion.VOTER_GAIN, _vb_undecided(pi, gi))
			else:
				var lose := (arr[i] + arr[i + 1] + arr[i + 2]) * minf(1.0, -points * PublicOpinion.VOTER_LOSS)
				for level in VB_LEVELS:
					var take := minf(arr[i + level], lose)
					arr[i + level] -= take
					lose -= take
			voter_base[pid] = arr
	_vb_sync_groups(pid)

func _log_province(province_id: String, text: String) -> void:
	var events: Array = province_events.get(province_id, [])
	events.append({"round": round_number, "text": text})
	while events.size() > PROVINCE_EVENT_LIMIT:
		events.pop_front()
	province_events[province_id] = events

# --- SEÇMEN TABANI (0.0.228) ----------------------------------------------------
## Her il × seçmen grubu × parti için SADAKAT SEVİYESİNE göre seçmen sayısı:
## 1, 2, 3. seviye partiye bağlı seçmen; partilere bağlı olmayan geri kalan
## seçmen 0. seviye = KARARSIZ (oyuncuya gösterilmez). Seçimde bağlı seçmen
## partisine oy verir; kararsızların UNDECIDED_TURNOUT'u sandığa gider ve
## partilere kamuoyu (ulusal + il puanı) ağırlığıyla dağılır.
##   MİTİNG  : ildeki seçmenin MITING_PULL'u kadarını çeker (teşkilat çarpanı);
##             odak gruplar bileşimi değiştirir, TOPLAM DEĞİŞMEZ. Çekilen
##             seçmenin VB_FROM_UNDECIDED'ı kararsızlardan, kalanı rakiplerden
##             (1. seviye kolay, 2. zor, 3. çok zor çalınır; çalınamayan
##             baskı seviye düşürür). Kendi seçmenini de bir üst seviyeye
##             taşır (odakta daha çok).
##   YATIRIM : ideolojiye bakmaz; daha çok çeker ve 2./3. seviyeyi daha kolay çalar.
##   ZIT GRUP: "5 KAZAN 3 KAYBET" (0.0.300, istisnasız): bir gruba kazanılan
##             her 5 seçmene karşılık AYNI İLDE zıt gruptaki kendi seçmeninden 3
##             kişi kararsızlara döner (önce en zayıf bağlılar). O ilde zıt
##             grupta seçmenin yoksa kayıp da yoktur. Miting, yasa ve yasaya
##             HAYIR (zıt grubun yasası gibi) bu kuralla işler; yatırım bütün
##             gruplardan kazandırır, bu kurala girmez. İki zıt grupta aynı
##             ilde aynı anda 3. seviye tutulamaz (yeni 3. seviye diğerini 2'ye indirir).
##   KASET   : hedef partinin bütün seçmeni bir seviye düşer (ilahiyatçı: yarısı);
##   KARALAMA: aynısı yalnız hedef ilde.
##   YASA    : ülke genelinde grubun seçmeninden çeker ve kendi
##             seçmenini yükseltir.
##   İTTİFAK : ortaklar birbirinin seçmenini çalmaz, seviyesini düşürmez.
## Kendiliğinden seviye kaybı yok: düşüş rakiplerin baskısıyla olur; teşkilat
## kendi seçmeninin seviye düşüşünü yavaşlatır (VB_ORG_SHIELD).
## Saklama: party -> PackedFloat32Array, indeks ((il * 8 + grup) * 3 + seviye-1).
## Partinin eski "hitap" değeri (groups) artık bundan TÜRETİLİR: grubun ülke
## genelindeki bağlı payı (bkz. _vb_sync_groups).
const VB_GROUPS := 8
const VB_LEVELS := 3
const UNDECIDED_TURNOUT := 0.6
const MITING_PULL := 0.04
const MITING_FOCUS_WEIGHT := 3.0
const VB_FROM_UNDECIDED := 0.5
## Mitingin rakip seviyelerine etkisi: çalma [1., 2., 3. seviye], düşürme [2., 3. seviye].
const MITING_STEAL := [1.0, 0.12, 0.03]
const MITING_DEMOTE := [1.5, 1.2]
## Miting kendi seçmenini yükseltir: [1->2, 2->3]; odakta tam, diğer gruplarda üçte bir.
const MITING_PROMOTE := [0.25, 0.1]
const INVEST_PULL := 0.14
const INVEST_STEAL := [1.0, 0.5, 0.15]
const INVEST_DEMOTE := [0.3, 0.2]
## Ülke çapı (yasa): eski hitap puanı başına grubun bu kadar yüzdesi.
const NATIONAL_PULL_MULT := 1.5
const NATIONAL_STEAL := [1.0, 0.1, 0.02]
const NATIONAL_DEMOTE := [0.4, 0.1]
const NATIONAL_PROMOTE := [0.15, 0.05]
## ZIT GRUP KAYBI — "5 KAZAN 3 KAYBET" (0.0.300): bir gruba kazanılan her 5
## seçmen için aynı ildeki zıt gruptaki kendi seçmeninden 3'ü partiyi bırakır
## (kararsızlaşır). İstisna yok: kriz, teşkilat ya da il büyüklüğü oranı
## değiştirmez. (0.0.268–0.0.299: birebir, seçmen yalnız bir seviye düşüyordu.)
const OPPOSITE_LOSS := 3.0 / 5.0
## Teşkilat kendi seçmeninin seviye düşüşünü bu oranda azaltır (seviye 0, 1, 2).
const VB_ORG_SHIELD := [0.0, 0.3, 0.55]
## İL BÜYÜKLÜĞÜ (0.0.232): seviye ATLAMA hızı ilin vekil sayısıyla TERS, seviye
## DÜŞME hızı DOĞRU orantılı (çarpan = il vekili / ortalama il vekili, bu
## aralıkta). Küçük ilde az mitingle 3. seviyeye çıkılır ve seçmen zor düşer;
## kalabalık ilde seçmen kolay kararsızlaşır, oradan da başkasına çekilir.
## Kaset / karalama gibi skandalların "bir seviye düşür" payı değişmez.
const VB_SIZE_MIN := 0.35
const VB_SIZE_MAX := 3.0

var voter_base: Dictionary = {}
var _vb_index: Dictionary = {}
var _vb_counts := PackedFloat32Array()
var _vb_size := PackedFloat32Array()
var _vb_ready := false

func _vb_setup() -> void:
	_vb_index.clear()
	_vb_counts = PackedFloat32Array()
	_vb_counts.resize(_province_ids.size() * VB_GROUPS)
	var voters := province_voters()
	for i in _province_ids.size():
		var id := String(_province_ids[i])
		_vb_index[id] = i
		for g in VB_GROUPS:
			_vb_counts[i * VB_GROUPS + g] = VoterGroups.group_count(voters.get(id, {}), String(VoterGroups.GROUP_IDS[g]))
	# İl büyüklüğü çarpanı: vekil sayısı / ortalama.
	_vb_size = PackedFloat32Array()
	_vb_size.resize(_province_ids.size())
	var mean := 0.0
	for id in _province_ids:
		mean += float(province_seat_count(String(id)))
	mean = maxf(1.0, mean / maxf(1.0, float(_province_ids.size())))
	for i in _province_ids.size():
		_vb_size[i] = clampf(float(province_seat_count(String(_province_ids[i]))) / mean, VB_SIZE_MIN, VB_SIZE_MAX)
	_vb_ready = true

## İlin büyüklük çarpanı (1 = ortalama il).
func vb_size_factor(pi: int) -> float:
	return float(_vb_size[pi]) if pi >= 0 and pi < _vb_size.size() else 1.0

func _vb_check() -> void:
	if not _vb_ready or _vb_counts.size() != _province_ids.size() * VB_GROUPS:
		_vb_setup()

## Seçmen tabanına katılan partiler (bağımsız ve blok hariç).
func _vb_parties() -> Array:
	var result: Array = []
	for pid in party_ids():
		if not PartyManager.is_independent(int(pid)) and int(pid) != PartyManager.BLOC_ID:
			result.append(int(pid))
	return result

func _vb_arr(pid: int) -> PackedFloat32Array:
	var arr: PackedFloat32Array = voter_base.get(pid, PackedFloat32Array())
	if arr.size() != _province_ids.size() * VB_GROUPS * VB_LEVELS:
		arr = PackedFloat32Array()
		arr.resize(_province_ids.size() * VB_GROUPS * VB_LEVELS)
	return arr

static func _vb_i(pi: int, gi: int, level: int) -> int:
	return (pi * VB_GROUPS + gi) * VB_LEVELS + level

func _vb_count(pi: int, gi: int) -> float:
	return _vb_counts[pi * VB_GROUPS + gi]

func _vb_cell(arr: PackedFloat32Array, pi: int, gi: int) -> float:
	var i := _vb_i(pi, gi, 0)
	return arr[i] + arr[i + 1] + arr[i + 2]

func _vb_undecided(pi: int, gi: int) -> float:
	var used := 0.0
	for pid in _vb_parties():
		if voter_base.has(pid):
			used += _vb_cell(voter_base[pid], pi, gi)
	return maxf(0.0, _vb_count(pi, gi) - used)

## Eksik partilerin tabanı açılır (hitabından, yalnız kararsızlardan), oyundan
## çıkan partilerin tabanı silinir (seçmeni kararsızlaşır).
func _vb_ensure() -> void:
	_vb_check()
	var parties := _vb_parties()
	for pid in voter_base.keys():
		if not parties.has(int(pid)):
			voter_base.erase(pid)
	for pid in parties:
		if not voter_base.has(pid) or (voter_base[pid] as PackedFloat32Array).size() != _province_ids.size() * VB_GROUPS * VB_LEVELS:
			_vb_init_party(pid)

## Partinin tabanını eski hitap değerinden kurar: her ilde grubun hitap kadarı
## (kararsızlar yetmezse yettiği kadar). ÇEKİRDEK gruplarının seçmeni 2.
## seviyeden (partili, sadık), diğerleri 1. seviyeden başlar; memleketinde bir
## seviye daha yüksek. (Hepsi 1. seviye olsaydı tek kaset tabanı silerdi.)
func _vb_init_party(pid: int) -> void:
	var arr := PackedFloat32Array()
	arr.resize(_province_ids.size() * VB_GROUPS * VB_LEVELS)
	voter_base[pid] = arr
	var groups := PartyManager.groups_of(pid)
	var core: Array = PartyManager.data_of(pid).get("core", [])
	var home := PoliticianPresets.hometown_of(pid)
	for pi in _province_ids.size():
		for gi in VB_GROUPS:
			var group := String(VoterGroups.GROUP_IDS[gi])
			var want := _vb_count(pi, gi) * clampf(float(groups.get(group, 0.0)) / 100.0, 0.0, 1.0)
			var take := minf(want, _vb_undecided(pi, gi))
			var level := (1 if core.has(group) else 0) + (1 if String(_province_ids[pi]) == home else 0)
			arr[_vb_i(pi, gi, mini(level, VB_LEVELS - 1))] += take
			voter_base[pid] = arr
	_vb_sync_groups(pid)

## Türetilmiş hitap: grubun ülke genelinde partiye bağlı yüzdesi (0..100).
func _vb_sync_groups(pid: int) -> void:
	if not PartyManager.parties.has(pid) or not voter_base.has(pid):
		return
	var arr: PackedFloat32Array = voter_base[pid]
	var groups: Dictionary = (PartyManager.parties[pid].get("groups", {}) as Dictionary).duplicate()
	for gi in VB_GROUPS:
		var mine := 0.0
		var total := 0.0
		for pi in _province_ids.size():
			mine += _vb_cell(arr, pi, gi)
			total += _vb_count(pi, gi)
		groups[VoterGroups.GROUP_IDS[gi]] = mine / total * 100.0 if total > 0.0 else 0.0
	PartyManager.parties[pid]["groups"] = groups

func _vb_sync_all() -> void:
	for pid in voter_base.keys():
		_vb_sync_groups(int(pid))

## Rakiplerin baskısı: çal / düşür. Dönüş: çalınan seçmen.
func _vb_press_rivals(pid: int, pi: int, gi: int, pressure: float, steal: Array, demote: Array) -> float:
	var rivals := {}
	var rival_total := 0.0
	for other in _vb_parties():
		if other == pid or are_allies(pid, other) or not voter_base.has(other):
			continue
		var t := _vb_cell(voter_base[other], pi, gi)
		if t > 0.0:
			rivals[other] = t
			rival_total += t
	if rival_total <= 0.0 or pressure <= 0.0:
		return 0.0
	var stolen := 0.0
	for other in rivals:
		var p: float = pressure * float(rivals[other]) / rival_total
		var arr: PackedFloat32Array = voter_base[other]
		var shield: float = float(VB_ORG_SHIELD[clampi(organization_level(String(_province_ids[pi]), other), 0, 2)])
		var size := vb_size_factor(pi)
		var i := _vb_i(pi, gi, 0)
		var s1 := minf(arr[i], p * float(steal[0]))
		arr[i] -= s1
		var left := maxf(0.0, p - s1)
		var s2 := minf(arr[i + 1], left * float(steal[1]) * (1.0 - shield))
		arr[i + 1] -= s2
		var d2 := minf(arr[i + 1], left * float(demote[0]) * (1.0 - shield) * size)
		arr[i + 1] -= d2
		arr[i] += d2
		var s3 := minf(arr[i + 2], left * float(steal[2]) * (1.0 - shield))
		arr[i + 2] -= s3
		var d3 := minf(arr[i + 2], left * float(demote[1]) * (1.0 - shield) * size)
		arr[i + 2] -= d3
		arr[i + 1] += d3
		voter_base[other] = arr
		stolen += s1 + s2 + s3
	return stolen

## Bir il-grup hücresinden amount seçmen çeker (önce kısmen kararsızlardan,
## sonra rakiplerden; rakipten alınamayan kısım kararsızlardan tamamlanır).
## Gelen seçmen 1. seviyedir. Dönüş: çekilen seçmen.
func _vb_pull(pid: int, pi: int, gi: int, amount: float, steal: Array, demote: Array) -> float:
	if amount <= 0.0:
		return 0.0
	var undecided := _vb_undecided(pi, gi)
	var gained := minf(undecided, amount * VB_FROM_UNDECIDED)
	undecided -= gained
	gained += _vb_press_rivals(pid, pi, gi, amount - gained, steal, demote)
	if gained < amount:
		gained += minf(undecided, amount - gained)
	var arr := _vb_arr(pid)
	arr[_vb_i(pi, gi, 0)] += gained
	voter_base[pid] = arr
	return gained

## Kendi seçmeninden amount kadarı bir seviye düşer (seviyelere orantılı;
## 1. seviyeden düşen kararsızlaşır). Teşkilat düşüşü yavaşlatır.
func _vb_demote_own(pid: int, pi: int, gi: int, amount: float, shielded: bool = true) -> void:
	if amount <= 0.0 or not voter_base.has(pid):
		return
	var arr: PackedFloat32Array = voter_base[pid]
	var i := _vb_i(pi, gi, 0)
	var total := arr[i] + arr[i + 1] + arr[i + 2]
	if total <= 0.0:
		return
	if shielded:
		# Teşkilat yavaşlatır; kalabalık ilde seçmen daha kolay düşer (skandal hariç).
		amount *= (1.0 - float(VB_ORG_SHIELD[clampi(organization_level(String(_province_ids[pi]), pid), 0, 2)])) * vb_size_factor(pi)
	var frac := minf(1.0, amount / total)
	var m1 := arr[i] * frac
	var m2 := arr[i + 1] * frac
	var m3 := arr[i + 2] * frac
	arr[i] += m2 - m1
	arr[i + 1] += m3 - m2
	arr[i + 2] -= m3
	voter_base[pid] = arr

## Bir hücrenin seçmeninin frac kadarı bir seviye düşer (skandal).
func _vb_demote_fraction(pid: int, pi: int, gi: int, frac: float) -> void:
	if not voter_base.has(pid):
		return
	var arr: PackedFloat32Array = voter_base[pid]
	var i := _vb_i(pi, gi, 0)
	_vb_demote_own(pid, pi, gi, (arr[i] + arr[i + 1] + arr[i + 2]) * frac, false)

## Kendi seçmenini yükseltir: r1 kadar 1->2, r2 kadar 2->3. Yeni 3. seviye,
## zıt gruptaki 3. seviyeyi 2'ye indirir (iki zıt grupta aynı anda tutulamaz).
func _vb_promote(pid: int, pi: int, gi: int, r1: float, r2: float) -> void:
	if not voter_base.has(pid):
		return
	var arr: PackedFloat32Array = voter_base[pid]
	var i := _vb_i(pi, gi, 0)
	# Küçük ilde seviye atlamak kolay, kalabalık ilde zor.
	var size := vb_size_factor(pi)
	var up1 := arr[i] * clampf(r1 / size, 0.0, 1.0)
	var up2 := arr[i + 1] * clampf(r2 / size, 0.0, 1.0)
	arr[i] -= up1
	arr[i + 1] += up1 - up2
	arr[i + 2] += up2
	if up2 > 0.0:
		var oi := _vb_i(pi, _vb_opposite(gi), 0)
		arr[oi + 1] += arr[oi + 2]
		arr[oi + 2] = 0.0
	voter_base[pid] = arr

func _vb_opposite(gi: int) -> int:
	return VoterGroups.GROUP_IDS.find(VoterGroups.opposite(String(VoterGroups.GROUP_IDS[gi])))

## 5 KAZAN 3 KAYBET: kazanılan seçmenin OPPOSITE_LOSS'u kadar, AYNI İLDEKİ
## zıt gruptaki kendi seçmeni partiyi bırakır (önce 1. seviye, sonra 2., 3.).
## Zıt grupta o ilde seçmen yoksa kayıp yok. Teşkilat kalkanı ve il büyüklüğü
## uygulanmaz.
func _vb_opposite_loss(pid: int, pi: int, gi: int, gained: float) -> void:
	var oi := _vb_opposite(gi)
	if oi < 0 or gained <= 0.0 or not voter_base.has(pid):
		return
	var arr: PackedFloat32Array = voter_base[pid]
	var i := _vb_i(pi, oi, 0)
	var lose := gained * OPPOSITE_LOSS
	for level in VB_LEVELS:
		var take := minf(arr[i + level], lose)
		arr[i + level] -= take
		lose -= take
	voter_base[pid] = arr

## MİTİNG. mult: teşkilat × geçmiş × popülizm. Dönüş: grup -> çekilen seçmen.
func _vb_miting(pid: int, province_id: String, focus: Array, mult: float) -> Dictionary:
	_vb_ensure()
	var pi: int = _vb_index.get(province_id, -1)
	var result := {}
	if pi < 0 or not voter_base.has(pid):
		return result
	var electorate := 0.0
	var weights := []
	var weight_total := 0.0
	for gi in VB_GROUPS:
		var n := _vb_count(pi, gi)
		electorate += n
		var w := n * (MITING_FOCUS_WEIGHT if focus.has(VoterGroups.GROUP_IDS[gi]) else 1.0)
		weights.append(w)
		weight_total += w
	if weight_total <= 0.0:
		return result
	var total := electorate * MITING_PULL * mult
	var fatigue: Dictionary = miting_fatigue.get(pid, {})
	for gi in VB_GROUPS:
		var group := String(VoterGroups.GROUP_IDS[gi])
		var amount: float = total * float(weights[gi]) / weight_total * PublicOpinion.miting_fatigue_mult(float(fatigue.get(group, 0.0))) \
			* PoliticianPresets.group_appeal(pid, group)
		var got := _vb_pull(pid, pi, gi, amount, MITING_STEAL, MITING_DEMOTE)
		_vb_opposite_loss(pid, pi, gi, got)
		result[group] = got
	var org_level := organization_level(province_id, pid)
	var promo_mult := 1.0 + 0.3 * float(org_level)
	# ODAK TOPLAMI DEĞİŞTİRMEZ (0.0.268): grup seçilse de seçilmese de ildeki
	# yükselen seçmen sayısı aynı; odak yalnızca dağılımı odak gruplara kaydırır.
	var shares := miting_promote_shares(pid, pi, focus)
	for gi in VB_GROUPS:
		_vb_promote(pid, pi, gi, float(MITING_PROMOTE[0]) * float(shares[0][gi]) * promo_mult,
			float(MITING_PROMOTE[1]) * float(shares[1][gi]) * promo_mult)
	_vb_sync_all()
	return result

## Mitingin seviye yükseltme payları [[1->2 payları], [2->3 payları]] (grup
## başına). Odaklı mitingde payların seçmenle ağırlıklı toplamı odaksızla aynı.
func miting_promote_shares(pid: int, pi: int, focus: Array) -> Array:
	var arr: PackedFloat32Array = voter_base[pid]
	var shares := [[], []]
	for level in 2:
		var base := 0.0
		var focused := 0.0
		for gi in VB_GROUPS:
			var n := arr[_vb_i(pi, gi, level)]
			base += n / 3.0
			focused += n * (1.0 if focus.has(VoterGroups.GROUP_IDS[gi]) else 0.15)
		var k := base / focused if focused > 0.0 else 0.0
		for gi in VB_GROUPS:
			(shares[level] as Array).append(1.0 / 3.0 if focus.is_empty() 				else (1.0 if focus.has(VoterGroups.GROUP_IDS[gi]) else 0.15) * k)
	return shares

## YATIRIM: ideolojiden bağımsız, ildeki bütün gruplardan nüfusla orantılı.
## parts: party -> pay (0..1, toplam 1). Dönüş: çekilen toplam seçmen.
func _vb_invest(province_id: String, parts: Dictionary, scale: float) -> float:
	_vb_ensure()
	var pi: int = _vb_index.get(province_id, -1)
	if pi < 0:
		return 0.0
	var gained := 0.0
	for gi in VB_GROUPS:
		var amount := _vb_count(pi, gi) * INVEST_PULL * scale
		for pid in parts.keys():
			if voter_base.has(int(pid)):
				gained += _vb_pull(int(pid), pi, gi, amount * float(parts[pid]), INVEST_STEAL, INVEST_DEMOTE)
	_vb_sync_all()
	return gained

## ÜLKE ÇAPI GRUP ETKİSİ (yasa, geçmiş): eski hitap puanı amount
## grubun seçmeninin yaklaşık amount × NATIONAL_PULL_MULT yüzdesine denk gelir.
## amount < 0: kendi seçmeninden o kadarı bir seviye düşer. promote: [r1, r2].
## Dönüş: grubun ülke geneli payındaki değişim (puan).
func _vb_national_group(pid: int, group: String, amount: float, promote: Array = NATIONAL_PROMOTE, opposite: bool = true) -> float:
	_vb_ensure()
	var gi := VoterGroups.GROUP_IDS.find(group)
	if gi < 0 or not voter_base.has(pid):
		return 0.0
	var before := float(PartyManager.groups_of(pid).get(group, 0.0))
	if amount > 0.0:
		amount *= PoliticianPresets.group_appeal(pid, group)
	for pi in _province_ids.size():
		if amount > 0.0:
			var got := _vb_pull(pid, pi, gi, _vb_count(pi, gi) * amount / 100.0 * NATIONAL_PULL_MULT, NATIONAL_STEAL, NATIONAL_DEMOTE)
			if opposite:
				_vb_opposite_loss(pid, pi, gi, got)
			_vb_promote(pid, pi, gi, float(promote[0]), float(promote[1]))
		elif amount < 0.0:
			_vb_demote_own(pid, pi, gi, _vb_cell(voter_base[pid], pi, gi) * -amount / 100.0 * NATIONAL_PULL_MULT)
	_vb_sync_groups(pid)
	for other in voter_base.keys():
		if int(other) != pid:
			_vb_sync_groups(int(other))
	return float(PartyManager.groups_of(pid).get(group, 0.0)) - before

## SKANDAL: partinin seçmeninin frac'ı bir seviye düşer (province "" = bütün iller).
func _vb_scandal(target: int, province_id: String = "", frac: float = 1.0) -> void:
	_vb_ensure()
	var pid := party_of(target)
	if not voter_base.has(pid):
		return
	for pi in _province_ids.size():
		if province_id != "" and String(_province_ids[pi]) != province_id:
			continue
		for gi in VB_GROUPS:
			_vb_demote_fraction(pid, pi, gi, frac)
	_vb_sync_groups(pid)

## Bölünme / birleşme: from'un tabanının frac'ı to'ya geçer (aynı seviyeyle).
func _vb_transfer(from_pid: int, to_pid: int, frac: float) -> void:
	_vb_check()
	if not voter_base.has(from_pid):
		return
	var src: PackedFloat32Array = voter_base[from_pid]
	var dst := _vb_arr(to_pid)
	for i in src.size():
		var moved := src[i] * frac
		src[i] -= moved
		dst[i] += moved
	voter_base[from_pid] = src
	voter_base[to_pid] = dst
	_vb_sync_groups(from_pid)
	_vb_sync_groups(to_pid)

## İldeki bağlı seçmen (parti -> sayı) ve kararsızlar: seçim modelinin girdisi.
func vb_province_state(province_id: String) -> Dictionary:
	_vb_ensure()
	return _vb_province_state(province_id, _vb_parties())

## Callers scanning the country validate the base once, outside the province loop.
func _vb_province_state(province_id: String, parties: Array) -> Dictionary:
	var pi: int = _vb_index.get(province_id, -1)
	var attached := {}
	var undecided := 0.0
	if pi < 0:
		return {"attached": attached, "undecided": 0.0}
	var used := 0.0
	var electorate := 0.0
	for gi in VB_GROUPS:
		electorate += _vb_count(pi, gi)
	for pid in parties:
		var n := 0.0
		if voter_base.has(pid):
			for gi in VB_GROUPS:
				n += _vb_cell(voter_base[pid], pi, gi)
		attached[pid] = n
		used += n
	undecided = maxf(0.0, electorate - used)
	return {"attached": attached, "undecided": undecided}

func vb_election_state() -> Dictionary:
	_vb_ensure()
	var parties := _vb_parties()
	var state := {}
	for province_id in _province_ids:
		state[province_id] = _vb_province_state(String(province_id), parties)
	return state

## Partinin her gruptaki ülke geneli seçmen payı seviyelere ayrılmış:
## grup -> [1. seviye %, 2. seviye %, 3. seviye %] (grubun bütün seçmenine oranla).
func group_level_shares(peer_id: int) -> Dictionary:
	_vb_ensure()
	var pid := party_of(peer_id)
	var result := {}
	if not voter_base.has(pid):
		return result
	var arr: PackedFloat32Array = voter_base[pid]
	for gi in VB_GROUPS:
		var levels := [0.0, 0.0, 0.0]
		var total := 0.0
		for pi in _province_ids.size():
			total += _vb_count(pi, gi)
			for level in VB_LEVELS:
				levels[level] = float(levels[level]) + arr[_vb_i(pi, gi, level)]
		for level in VB_LEVELS:
			levels[level] = float(levels[level]) / total * 100.0 if total > 0.0 else 0.0
		result[VoterGroups.GROUP_IDS[gi]] = levels
	return result

## Ağ ve kayıt: tabanı (parti -> dizi) paketle.
func _vb_pack() -> Dictionary:
	return voter_base.duplicate()

func _vb_unpack(data) -> void:
	voter_base = {}
	if data is Dictionary:
		for pid in data:
			voter_base[int(pid)] = PackedFloat32Array(data[pid])
	_vb_ready = false

# --- Grup yakınlıkları -------------------------------------------------

## Partilerin grup yakınlıklarını değiştirir (bkz. PartyManager.apply_group_deltas).
## changes: [{"peer", "group", "amount"}]. Dönüş: gerçekleşen [{"peer", "group", "delta"}].
## 0.0.228: partiler için seçmen tabanına yazılır (bkz. _vb_national_group):
## pozitif değer grubun ülke genelindeki seçmeninden çeker (zıt grupta yarısı
## kadar seviye kaybı otomatik); aynı partinin aynı listedeki zıt grup EKSİSİ
## bu yüzden atlanır. Bağımsızlar eski hitap hesabıyla.
func _shift_groups(changes: Array) -> Array:
	var positive := {}
	for change in changes:
		if float(change["amount"]) > 0.0:
			positive["%d|%s" % [party_of(int(change["peer"])), String(change["group"])]] = true
	var result: Array = []
	for change in changes:
		var pid := party_of(int(change["peer"]))
		var group := String(change["group"])
		var amount := float(change["amount"])
		if PartyManager.is_independent(pid) or not PartyManager.parties.has(pid):
			result.append_array(PartyManager.apply_group_deltas([change]))
			continue
		if amount < 0.0 and positive.has("%d|%s" % [pid, VoterGroups.opposite(group)]):
			continue
		result.append({"peer": pid, "group": group, "delta": _vb_national_group(pid, group, amount)})
	return result

## Tur sonu: miting yorgunluğu söner.
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

# --- Karışıklık ve bölünme ------------------------------------------------------------

## HAMLE SIRASI FARK ETMESİN (0.0.187): tur İÇİNDE karışıklık ham toplam
## olarak tutulur (eksiye düşebilir), okunurken 0'ın altı 0 sayılır; 0'a
## kırpma yalnız TUR SONUNDA yapılır. Böylece "miting (−0,3) sonra kaset
## (+1,5)" ile "kaset sonra miting" aynı sonucu (1,2) verir; eskiden önce
## gelen miting 0'da boşa gidiyordu.
func turmoil_of(peer_id: int) -> float:
	return maxf(0.0, float(turmoil.get(party_of(peer_id), 0.0)))

func _add_turmoil(peer_id: int, amount: float) -> void:
	if peer_id == -1 or not _is_authority():
		return
	peer_id = party_of(peer_id)
	if amount > 0.0:
		amount *= PoliticianPresets.party_effect(peer_id, "turmoil_in")
	var value := float(turmoil.get(peer_id, 0.0)) + amount
	if is_zero_approx(value):
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
		PoliticianPresets.random_background(), home, bot_name["gender"], "", AvatarCatalog.random(bot_name["gender"], _rng.randi())))
	turn_order.append(splinter)
	# Ayrılan parti sırada (ve soldaki listede) ana partinin hemen altında.
	var anchor := parent
	for member in PartyManager.members_of(parent):
		if turn_order.find(int(member)) > turn_order.find(anchor):
			anchor = int(member)
	if turn_order.has(anchor):
		_place_after(splinter, anchor)
	inventories[splinter] = []
	funds[splinter] = float(GameRules.FUNDS_PER_ROUND)
	var seats_before := int(last_seats.get(parent, 0))
	var share := _rng.randf_range(PublicOpinion.SPLIT_SEAT_SHARE_MIN, PublicOpinion.SPLIT_SEAT_SHARE_MAX)
	var moved := _move_seats(parent, splinter, maxi(1, int(round(seats_before * share))))
	_vb_transfer(parent, splinter, share)
	election_seats[splinter] = mini(moved, int(election_seats.get(parent, 0)))
	election_seats[parent] = maxi(0, int(election_seats.get(parent, 0)) - int(election_seats[splinter]))
	# Oy oranı son seçimin statik sonucudur: bölünmede paylaştırılmaz, ayrılan
	# parti ilk seçimine kadar oy oranı göstermez.
	if passed_threshold.has(parent):
		passed_threshold.append(splinter)
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
	_vb_transfer(splinter, parent, 1.0)
	voter_base.erase(splinter)
	election_seats[parent] = int(election_seats.get(parent, 0)) + int(election_seats.get(splinter, 0))
	last_vote_shares.erase(splinter)  # birleşmede oy oranı eklenmez (son seçim sonucu statik)
	for province_id in organizations.keys():
		var entry: Dictionary = organizations[province_id]
		var level := int(entry.get(splinter, 0))
		if level > int(entry.get(parent, 0)):
			entry[parent] = level
		entry.erase(splinter)
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
	# Meclis dışı parti yarı verimle çalar; hukukçunun partisinden daha az koparılır.
	wanted = maxi(1, int(round(wanted * steal_efficiency(peer_id)
		* PoliticianPresets.party_effect(target_peer_id, "steal_in"))))
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
	stat_add(target_peer_id, "bad")
	_stat_deed("kaset", peer_id, target_peer_id)
	var damage := PublicOpinion.REPUTATION_NATIONAL_DAMAGE
	if populism_rounds_left(peer_id) > 0:
		damage *= PublicOpinion.POPULISM_GOOD_MULT
	damage *= PoliticianPresets.effect(peer_id, "reputation_out")
	_add_turmoil(target_peer_id, PublicOpinion.TURMOIL_REPUTATION)
	_add_national(target_peer_id, -damage)
	# 0.0.284: kaset bütün illerde seçmenin KASET_DEMOTE kadarını bir seviye
	# düşürür (eskiden hepsini: ikinci kaset tabanı siliyordu).
	_vb_scandal(target_peer_id, "", PublicOpinion.KASET_DEMOTE)
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
	record_turn_snapshot(current_turn_peer_id())
	var size: int = maxi(1, turn_order.size())
	var wrapped: bool = (current_turn_index + 1) >= size
	current_turn_index = (current_turn_index + 1) % size
	_turn_time_left = GameRules.TURN_TIMEOUT
	if not wrapped:
		_retire_due_temporary_parties()
	else:
		# Tur kapandı: yeni turun ilk oyuncusu seçimden sonra (sıralama
		# değişebilir) belli olur; geliri ve kartı _begin_round_turn verir.
		_income_deferred = true
		turn_flow = {}
		return wrapped
	_grant_turn_income()
	_maybe_mandatory_congress()
	return wrapped

## Tur kapanırken ertelenen ilk oyuncu geliri / kartı / zorunlu kongre.
var _income_deferred := false

func _begin_round_turn() -> void:
	if not _income_deferred:
		return
	_income_deferred = false
	_grant_turn_income()
	_maybe_mandatory_congress()

## SIRALAMA (0.0.188): her seçimden sonra oynama sırası partilerin SON OY
## ORANINA göre (büyükten küçüğe) dizilir; iki kişilik partide genel başkan ve
## üye yan yana, eski sıralarıyla kalır. Yeni tur sıranın başından başlar.
func _order_turns_by_votes() -> void:
	var old: Array = turn_order.duplicate()
	var keyed: Array = []
	for i in old.size():
		var peer := int(old[i])
		keyed.append({"peer": peer, "share": float(last_vote_shares.get(party_of(peer), 0.0)), "party": party_of(peer), "i": i})
	# Partinin ilk görüldüğü sıra (üyeler başkanla birlikte kalsın diye).
	var first_seen := {}
	for k in keyed:
		if not first_seen.has(k["party"]):
			first_seen[k["party"]] = k["i"]
	keyed.sort_custom(func(a, b):
		if not is_equal_approx(float(a["share"]), float(b["share"])):
			return float(a["share"]) > float(b["share"])
		if int(first_seen[a["party"]]) != int(first_seen[b["party"]]):
			return int(first_seen[a["party"]]) < int(first_seen[b["party"]])
		return int(a["i"]) < int(b["i"]))
	turn_order = []
	for k in keyed:
		turn_order.append(k["peer"])
	current_turn_index = 0
	_turn_time_left = GameRules.TURN_TIMEOUT

## Sırası gelen oyuncu para gelirini VE bir kart alır.
## KART ÇEKME HAMLESİ KALDIRILDI: deste butonu yerine her elin başında
## otomatik olarak bir kart geliyor. Dağıtılan kart, bu hamleden sonra
## gönderilecek state olayına iliştirilsin diye _pending_dealt'ta beklet.
func _grant_turn_income() -> void:
	var peer_id := current_turn_peer_id()
	_start_turn_flow(peer_id)
	if peer_id == -1:
		return
	_apply_tax_tick()
	funds[peer_id] = funds_of(peer_id) + turn_income(peer_id)
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	# 0.0.231: kart artık otomatik dağıtılmaz; oyuncu sırasının başında KART
	# ÇEK'e basar (bkz. _apply_draw). Akış kapalıysa (testler) eski dağıtım.
	if enforce_turn_flow:
		return
	turn_flow["drawn"] = true
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
	var business := PoliticianPresets.BUSINESS_TURN_INCOME if PoliticianPresets.has_background(peer_id, "is_insani") else 0.0
	return maxf(0.0, base - bot_funds_penalty(peer_id)) + org_income(peer_id) + business

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

## Partinin teşkilatlarının tur başı geliri (1. seviye +2,5, 2. seviye +8 / il; sınırsız).
func org_income(peer_id: int) -> float:
	var pid := party_of(peer_id)
	var total := 0.0
	for province_id in organizations.keys():
		var level := int((organizations[province_id] as Dictionary).get(pid, 0))
		total += float(GameRules.ORG_INCOME[clampi(level, 0, GameRules.ORG_INCOME.size() - 1)])
	return total

## Lobi kuralı: botlar tur başında ve bağış kampanyalarından bu kadar az para alır.
func bot_funds_penalty(peer_id: int) -> float:
	return MultiplayerManager.bot_funds_penalty if MultiplayerManager.is_bot(peer_id) else 0.0

## Bağış kampanyası kartının bu oyuncuya verdiği para (botlara zayıflatma uygulanır).
func funds_bonus_amount(peer_id: int, strong: bool) -> float:
	var base := float(GameRules.FUNDS_BONUS_STRONG if strong else GameRules.FUNDS_BONUS_WEAK)
	return maxf(0.0, base - bot_funds_penalty(peer_id))

# --- Tur sonu / seçim / oyun sonu -------------------------------------------

func _finish_round_if_needed(wrapped: bool) -> void:
	if not wrapped or game_finished:
		return
	if is_turn_blocked():
		# Örn. turun son hamlesi gensoru ya da yasaydı: oylama bitince tur kapanacak.
		_round_end_pending = true
		return
	_finish_round()

## Bu turdan (dahil) oyun sonuna kadar kalan seçim sayısı (mevcut takvimle).
func remaining_elections() -> int:
	var n := 0
	for r in range(maxi(1, round_number), GameRules.MAX_ROUNDS + 1):
		if GameRules.is_election_round(r):
			n += 1
	return n

## Anayasa değişikliği seçim aralığını değiştirdi: takvim SON SEÇİMDEN
## itibaren yeni aralıkla işlesin (yoksa çıpa eski aralığa göre kalır).
## remaining >= 0 verilirse kalan seçim sayısı korunur ve son seçim yeni
## aralığa oturur (eskiden eski bitiş turu kalıp seçimler üst üste gelebiliyordu).
func rebase_election_calendar(remaining: int = -1) -> void:
	election_anchor = maxi(last_election_round, 0)
	if election_anchor <= 0:
		election_anchor = GameRules.FIRST_ELECTION_ROUND
	GameRules.set_election_anchor(election_anchor)
	if remaining > 0:
		var first := election_anchor
		while first < round_number:
			first += GameRules.ELECTION_INTERVAL
		max_rounds_override = first + (remaining - 1) * GameRules.ELECTION_INTERVAL
		GameRules.set_max_rounds_override(max_rounds_override)

## Meclis erken seçimi kabul etti (GovernmentManager çağırır).
func schedule_early_election() -> void:
	early_election_pending = true
	_push_state({"type": "opinion"})

## Sıradaki seçimin turu: erken seçim kararı varsa BU turun sonu.
func next_election_round() -> int:
	if early_election_pending:
		return round_number
	return GameRules.next_election_round(round_number)

## POLİTİK EKSEN GEÇMİŞİ (0.0.304): her tur sonunda partilerin eksendeki
## konumu (bkz. VoterGroups.axis_position). Oyun sonunda jenerik sonrası
## sahnede logolar bu yolda kayar. pid -> {"name", "bg_color", "icon_index",
## "icon_color", "path": [[tur, x, y], ...]}; dağılan partinin yolu kalır.
var axis_history: Dictionary = {}

## OYUN SONU İSTATİSTİKLERİ (0.0.305): ünvanlar, perde arkası ve seçim grafiği
## için oyun boyunca tutulan sayaçlar. Host yazar, durumla birlikte yayılır.
##   parties: pid -> {name, bg_color, icon_index, icon_color, leader,
##     mitings, invest, laws, no_votes, censures, coalitions, bad, aid}
##   deeds: [[tur, "kaset" | "isyan", yapan pid, hedef pid]] (yalnız oyun sonunda gösterilir)
##   shares: pid -> [[tur, oy %]] (tur sonu tahmini; seçim turunda gerçek sonuç)
##   elections: seçim yapılan turlar
var game_stats: Dictionary = {}

func _stats_party(pid: int) -> Dictionary:
	if game_stats.is_empty():
		game_stats = {"parties": {}, "deeds": [], "shares": {}, "elections": []}
	var parties: Dictionary = game_stats["parties"]
	var entry: Dictionary = parties.get(pid, {"mitings": 0, "invest": 0.0, "laws": 0, "no_votes": 0, "censures": 0,
		"coalitions": 0, "bad": 0, "aid": 0.0})
	var party: Dictionary = PartyManager.data_of(pid)
	if not party.is_empty():
		entry["name"] = String(party.get("name", "?"))
		entry["bg_color"] = party.get("bg_color", Color.GRAY)
		entry["icon_index"] = int(party.get("icon_index", 0))
		entry["icon_color"] = party.get("icon_color", Color.WHITE)
		entry["leader"] = PoliticianPresets.display_name(pid)
	parties[pid] = entry
	return entry

## Partinin sayacına ekler (peer_id üye de olabilir: partisine yazılır).
func stat_add(peer_id: int, key: String, amount: float = 1.0) -> void:
	if not _is_authority() or peer_id == -1:
		return
	var pid := party_of(peer_id)
	if PartyManager.is_independent(pid) or not PartyManager.parties.has(pid):
		return
	var entry := _stats_party(pid)
	entry[key] = entry.get(key, 0) + amount

## Kaset / iç karışıklık: oyun sonundaki "perde arkası" için gizlice kaydedilir.
func _stat_deed(kind: String, actor: int, target: int) -> void:
	if not _is_authority():
		return
	_stats_party(party_of(actor))
	_stats_party(party_of(target))
	(game_stats["deeds"] as Array).append([round_number, kind, party_of(actor), party_of(target)])

## Tur sonu: partilerin tahmini oy oranı (seçim turunda gerçek sonuç yazılır).
func _record_vote_shares(round_value: int, shares: Dictionary, election: bool) -> void:
	if not _is_authority():
		return
	if game_stats.is_empty():
		game_stats = {"parties": {}, "deeds": [], "shares": {}, "elections": []}
	var all: Dictionary = game_stats["shares"]
	for pid in shares.keys():
		if not PartyManager.parties.has(int(pid)) or PartyManager.is_independent(int(pid)):
			continue
		_stats_party(int(pid))
		var list: Array = all.get(int(pid), [])
		if not list.is_empty() and int(list[list.size() - 1][0]) == round_value:
			list.pop_back()
		list.append([round_value, snappedf(float(shares[pid]), 0.01)])
		all[int(pid)] = list
	if election and not (game_stats["elections"] as Array).has(round_value):
		(game_stats["elections"] as Array).append(round_value)

## SIRA ANLIK GÖRÜNTÜSÜ (0.0.306): her oyuncunun sırası bitince partilerin oy
## oranı ve eksen konumu kaydedilir (oyun sonu grafiği ve yolculuk sıra sıra
## oynar). game_stats["steps"]: [[adım, tur, sırası biten parti]].
func record_turn_snapshot(actor: int) -> void:
	if not _is_authority():
		return
	if game_stats.is_empty():
		game_stats = {"parties": {}, "deeds": [], "shares": {}, "elections": []}
	var step := int(game_stats.get("step", 0)) + 1
	game_stats["step"] = step
	var steps: Array = game_stats.get("steps", [])
	steps.append([step, round_number, party_of(actor) if actor != -1 else -1])
	game_stats["steps"] = steps
	record_axis_positions(step)
	# Önbellek aynı karede kalır; kayıt her sırada taze değer okusun.
	_national_cache_frame = -1
	var expected := _expected_national()
	var percent := {}
	for pid in expected.keys():
		percent[pid] = float(expected[pid]) * 100.0
	_record_vote_shares(step, percent, false)

func record_axis_positions(step: int = -1) -> void:
	if step < 0:
		step = int(game_stats.get("step", 0))
	for pid in party_ids():
		var party: Dictionary = PartyManager.data_of(int(pid))
		if party.is_empty() or PartyManager.is_independent(int(pid)):
			continue
		var entry: Dictionary = axis_history.get(int(pid), {"path": []})
		entry["name"] = String(party.get("name", "?"))
		entry["bg_color"] = party.get("bg_color", Color.GRAY)
		entry["icon_index"] = int(party.get("icon_index", 0))
		entry["icon_color"] = party.get("icon_color", Color.WHITE)
		var p := VoterGroups.axis_position(party.get("groups", {}))
		var path: Array = entry["path"]
		if not path.is_empty() and int(path[path.size() - 1][0]) == step:
			path.pop_back()
		path.append([step, snappedf(p.x, 0.001), snappedf(p.y, 0.001)])
		entry["path"] = path
		axis_history[int(pid)] = entry

func _finish_round() -> void:
	_round_end_pending = false
	_release_secret_news()
	# Makam puanları TUR SONUNDA DEĞİL, hükümet kurulduğu anda yazılır
	# (bkz. GovernmentManager.award_formation_scores).
	var finished_round := round_number
	round_number += 1
	_expire_alliance_requests()

	# Ayrılan partiler dönebilir, çok karışan parti bölünür; sonra karışıklık söner.
	_check_reunions()
	_check_splits()
	# Tur sonu: ham karışıklık 0'a kırpılır (turmoil_of) ve söner.
	for peer_id in turmoil.keys():
		turmoil[peer_id] = turmoil_of(int(peer_id)) * PublicOpinion.TURMOIL_DECAY
	# EKONOMİ: tur başına tek sefer, SEÇİMDEN ÖNCE (sandık o ana kadar
	# gerçekleşmiş etkileri görür; bekleyen dilimler ve yerleşmemiş vergi
	# etkisi sayılmaz).
	_pending_log.append({"text": _advance_economy(), "peer_id": -1, "province": "", "kind": "economy"})
	_pending_econ = {"kind": "round", "revenue": float(economy["revenue"])}
	# AFET: bitmiş turun afeti sona erer; yeni tur için zar atılır. Bu tur
	# seçimle bitiyorsa yeni afet YENİ seçim dönemine sayılır.
	_end_disaster()
	# HÜKÜMET ONAYI tur sonunda (afet sonucu ve yatırım istekleri dahil)
	# güncellenir; seçim yeni değeri görür. Sonra yeni turun istekleri seçilir.
	_settle_invest_requests()
	_settle_approval()
	_roll_invest_requests()
	var will_elect: bool = finished_round >= GameRules.MAX_ROUNDS or early_election_pending \
		or GameRules.is_election_round(finished_round) \
		or (not last_seats.is_empty() and not GovernmentManager.has_government()
			and GovernmentManager.phase == GovernmentManager.Phase.IDLE)
	if will_elect:
		_disaster_new_term()
	# Seçimden hemen sonraki ilk tur AFETSİZ (0.0.188): seçim gecesi, hükümet
	# kurma ve sonuç gazetesi arasında afet haberi kayboluyordu; o turda yalnız
	# gündem olur. Afet ancak seçimden sonraki ikinci turdan itibaren çıkar.
	if finished_round < GameRules.MAX_ROUNDS and not will_elect:
		_roll_disaster()

	var scheduled := GameRules.is_election_round(finished_round)
	var no_government := not last_seats.is_empty() \
		and not GovernmentManager.has_government() \
		and GovernmentManager.phase == GovernmentManager.Phase.IDLE
	# ERKEN SEÇİM (meclis kararı ya da kurulamayan hükümet) lobideki seçim
	# SAYISINA DAHİLDİR (0.0.239): sıradaki olağan seçimin yerine geçer. Ondan
	# sonra kalan seçim yoksa bu erken seçim oyunun SON seçimidir.
	var early := finished_round < GameRules.MAX_ROUNDS and not scheduled and (early_election_pending or no_government)
	var left_after := 0
	if early:
		for r in range(finished_round + 1, GameRules.MAX_ROUNDS + 1):
			if GameRules.is_election_round(r):
				left_after += 1
		left_after -= 1
		if left_after <= 0:
			max_rounds_override = finished_round
			GameRules.set_max_rounds_override(max_rounds_override)

	if finished_round >= GameRules.MAX_ROUNDS:
		# SON SEÇİM: kurulan hükümet puanlarını alınca oyun biter (bkz. on_block_state_changed).
		early_election_pending = false
		final_election_pending = true
		_hold_election(finished_round, early)
		return

	# Erken seçim: takvim bu tura sabitlenir — kalan seçimler buradan itibaren aralıkla.
	if early:
		early_election_pending = false
		election_anchor = finished_round
		GameRules.set_election_anchor(election_anchor)
		max_rounds_override = finished_round + left_after * GameRules.ELECTION_INTERVAL
		GameRules.set_max_rounds_override(max_rounds_override)
		_hold_election(finished_round, true)
		_schedule_agenda()
		return

	if scheduled:
		early_election_pending = false
		_hold_election(finished_round, false)
	else:
		_decay_opinion()
		_begin_round_turn()
		_push_state({"type": "round"})
	_schedule_agenda()

## SEÇİM (0.0.284): sandıkta yalnız seçmen tabanı sayılır (bkz. ElectionModel):
## bağlı seçmen partisine, kararsızların sandığa gidenleri partilere eşit.
## Ayrı bir kamuoyu / il puanı çarpanı yoktur.
func _hold_election(finished_round: int, early: bool) -> void:
	var groups := _group_profiles().duplicate(true)
	# Denge analizi (tools/balance_sim.gd) için seçimin girdileri; ağda gönderilmez.
	last_election_inputs = {
		"groups": groups, "voters": province_voters(),
		"threshold": MultiplayerManager.election_threshold,
		"alliances": alliance_membership() if alliances_enabled else {},
		"gov_ids": GovernmentManager.government_party_ids(), "organizations": organizations.duplicate(true),
		"seats_before": last_seats.duplicate(),
	}
	var result := ElectionModel.compute(groups, _province_seat_counts, province_voters(),
		MultiplayerManager.election_threshold, _election_rng(finished_round), alliance_membership() if alliances_enabled else {},
		vb_election_state())
	_add_independent_seats(result, groups)
	# Fesihten kalan Bağımsızlar bloğu seçimle dağılır (aşağıda sonuçlar yazılınca).
	if PartyManager.parties.has(PartyManager.BLOC_ID):
		PartyManager.parties.erase(PartyManager.BLOC_ID)
		PartyManager.broadcast()
	_update_credibility(last_vote_shares, result["vote_shares"])
	previous_vote_shares = last_vote_shares.duplicate()
	last_vote_shares = result["vote_shares"]
	# Seçim: gerçek sonuç ayrı tutulur (grafik çizgisi tahmini oranla kesintisiz
	# akar; sonuç seçim etiketinde görünür).
	if _is_authority():
		if game_stats.is_empty():
			game_stats = {"parties": {}, "deeds": [], "shares": {}, "elections": []}
		var step := int(game_stats.get("step", 0))
		if not (game_stats["elections"] as Array).has(step):
			(game_stats["elections"] as Array).append(step)
		var results: Dictionary = game_stats.get("election_results", {})
		results[step] = last_vote_shares.duplicate()
		game_stats["election_results"] = results
	last_seats = result["seats"]
	last_province_results = result["province_results"]
	passed_threshold = result["passed_threshold"]
	national_list = result.get("national_list", {})
	election_seats = last_seats.duplicate()
	election_groups = {}
	for pid in party_ids():
		election_groups[pid] = PartyManager.groups_of(pid).duplicate()
	last_election_round = finished_round
	# Anketler seçimle sıfırlanır: yeni anket yaptırılana kadar boş.
	polls = {}
	# İTTİFAKLAR seçimle biter (0.0.225): ortaklar bir dönem former_allies'ta kalır.
	if not alliances.is_empty():
		_pending_log.append({"text": L.t("Seçim bitti: bütün seçim ittifakları dağıldı."), "peer_id": -1, "province": "", "kind": "alliance"})
	dissolve_all_alliances(true)
	# Geçici partiler: süresi dolan fesheder; sonra
	# belki yeni bir parti katılır. (Hükümet kurma bundan sonra başlar: ayrılan
	# kardeş partiler ayrı ayrı makam alabilir.)
	_retire_temporary_parties()
	_count_congress_elections()
	_maybe_add_temporary_party()
	for splinter in splinters.keys():
		splinters[splinter]["elections"] = int(splinters[splinter].get("elections", 0)) + 1
	last_election_was_early = early
	_order_turns_by_votes()
	_begin_round_turn()
	# Seçim sonrası herkese para ve 1 kart hediye.
	for peer_id in turn_order:
		funds[peer_id] = funds_of(peer_id) + float(GameRules.ELECTION_FUNDS_BONUS)
		# Hediye kart da sınıfına göre: anında kart hemen uygulanır.
		if is_party_member(peer_id):
			continue
		var gift: Array = []
		var gift_messages: PackedStringArray = []
		_resolve_draw(peer_id, CardPresets.weighted_pick(_draw_weights(peer_id), _rng), gift, gift_messages)
		last_gift_draws[peer_id] = gift
		for text in gift_messages:
			_pending_log.append({"text": text, "peer_id": peer_id, "province": "", "kind": "card"})
	# Seçimde kullanıldıktan SONRA söner: seçimden hemen önceki hamleler tam etkili.
	_decay_opinion()
	_pick_music_track()  # seçim gecesinden sonra yeni dönemin müziği
	_push_state({"type": "election"}, true)
	# Yeni meclis: hükümet kurma görevi en çok vekili olan partiye verilir.
	# Seçim gecesi yayını herkesin ekranında oynarken kurma süresi yanmasın.
	GovernmentManager.start_formation(GameRules.ELECTION_NIGHT_SECONDS + GameRules.ELECTION_NIGHT_HOLD + GameRules.ELECTION_NIGHT_PAPER + 2.0)

func alliance_membership() -> Dictionary:
	var membership := {}
	for alliance_id in alliances:
		for pid in alliances[alliance_id].get("members", []):
			membership[int(pid)] = int(alliance_id)
	return membership

## BAĞIMSIZ ADAY: sadece memleketinde yarışır, en fazla 1 sandalye kazanır.
## O ildeki payı (diğer partilerle birlikte hesaplanır) ilin bir vekillik
## kotasının INDEPENDENT_QUOTA_FACTOR'ünü geçerse, ilin en çok vekil çıkaran
## partisinden bir sandalye alır. Az bir miting bile yetebilir (hemşehri desteği).
const INDEPENDENT_QUOTA_FACTOR := 0.6

func _add_independent_seats(result: Dictionary, groups: Dictionary) -> void:
	var province_results: Dictionary = result["province_results"]
	var seats: Dictionary = result["seats"]
	var vote_shares: Dictionary = result["vote_shares"]
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
		field[pid] = effective_groups(pid)
		var shares := ElectionModel.expected_shares(field, province_profile(home))
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
func on_block_state_changed(after_vote: bool = false) -> void:
	if not _is_authority() or turn_order.is_empty() or game_finished or is_turn_blocked():
		return
	if final_election_pending:
		_finish_final_election()
		return
	# Oylama bitince sıra süresi BAŞTAN başlamaz: oylama sırasında durmuştu,
	# kaldığı yerden sürer (bitmek üzereyse kısa bir pay tanınır).
	if after_vote:
		_turn_time_left = maxf(_turn_time_left, VOTE_RETURN_MIN_SECONDS)
	else:
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
	turmoil.erase(peer_id)
	splinters.erase(peer_id)
	for province_id in last_province_results.keys():
		last_province_results[province_id].erase(peer_id)
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
## Bağımsız ya da üye mitingi güvenilirlik kazandırır.
const MITING_CREDIBILITY := 3.0
## Yeni parti: güvenilirliğin her FOUND_ORG_PER_CREDIBILITY puanı için miting
## yapılan en güçlü illerden birinde 1. seviye teşkilat (en fazla FOUND_ORG_MAX).
const FOUND_ORG_PER_CREDIBILITY := 25.0
const FOUND_ORG_MAX := 4
## ESKİ PARTİDEN TEŞKİLAT GEÇİŞİ: partisinden istifa eden ya da partisini
## feshedip bağımsız kalan siyasetçi yeni parti kurunca eski partisinin
## teşkilatlarının bir kısmı (seviyeleriyle) yeni partiye geçer:
##   pay = 0,5 + süre + başarı + güvenilirlik (%10..%90)
##   süre       : +0,2 − 0,05 × ayrılıştan beri geçen tur (en az −0,25)
##   başarı     : siyasetçinin puanı / 100 (en fazla +0,25)
##   güvenilirlik: (güvenilirlik − 50) / 500 (−0,1..+0,1)
## Eski parti sürüyorsa teşkilatlar ondan KOPAR (taşınır); feshedildiyse
## dağılan teşkilatlar yeniden toplanır.
const FORMER_ORG_BASE := 0.5
const FORMER_ORG_FRESH := 0.2
const FORMER_ORG_PER_ROUND := 0.05
const FORMER_ORG_TIME_MIN := -0.25
const FORMER_ORG_SCORE_DIV := 100.0
const FORMER_ORG_SCORE_MAX := 0.25
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
	_add_national(bot, TEMP_PARTY_NATIONAL)
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
	for table in [populism, turmoil, law_rounds, congress_rounds,
			miting_fatigue, election_groups,
			national_list, last_seats, election_seats, last_vote_shares, previous_vote_shares, inventories, funds, credibility]:
		table.erase(pid)
	passed_threshold.erase(pid)
	for nested in [last_province_results, organizations]:
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
	# Seçmeni en çok olan (miting yapılan) illerde teşkilat.
	var count := mini(FOUND_ORG_MAX, int(credibility_of(peer_id) / FOUND_ORG_PER_CREDIBILITY))
	var ranked: Array = []
	for province_id in _province_ids:
		var points := float(vb_province_state(province_id)["attached"].get(peer_id, 0.0))
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

## KONGRE ŞİMDİLİK KAPALI (0.0.260): kodu duruyor, ileride geri açılmak üzere.
## Kapalıyken ne hamle, ne istek, ne zorunlu kongre olur (testler açabilir).
var congress_enabled := false
const CONGRESS_MAX_ELECTIONS := 3
const CONGRESS_COST := 10
const CONGRESS_REQUEST_COST := 20
const CONGRESS_DELEGATES := 1200
## Gösteri süreleri (sonuç gazetesi hariç): oyuncunun partisi seçim gecesinin
## 0,4'ü (~8,8 sn), bot partisi dörtte biri (~5,5 sn).
static func congress_duration(has_human: bool) -> float:
	return (GameRules.ELECTION_NIGHT_SECONDS + GameRules.ELECTION_NIGHT_HOLD) * (0.4 if has_human else 0.25)

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
	return congress_enabled and can_choose_main_action(peer_id) and PartyManager.is_leader(peer_id) and not PartyManager.is_independent(peer_id) \
		and not is_splinter(peer_id) and elections_since_congress(peer_id) >= 1 and funds_of(peer_id) >= CONGRESS_COST

## Üye (eski başkan) kongre isteyebilir mi? Son kongreden beri bir seçim
## geçmiş olmalı VE bot başkanın döneminde partinin oyu DÜŞMÜŞ olmalı.
func can_request_congress(peer_id: int) -> bool:
	if not congress_enabled or not can_choose_main_action(peer_id) or not is_party_member(peer_id):
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
	if not congress_enabled or peer_id == -1 or game_finished or congress_active or not PartyManager.is_leader(peer_id):
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
			String(_province_ids[_rng.randi() % _province_ids.size()]) if not _province_ids.is_empty() else "", person["gender"],
			"", AvatarCatalog.random(person["gender"], _rng.randi()))
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
	# Gösteri herkesin ekranında oynar; o süre boyunca (sonuç gazetesi dahil)
	# tur akışı durur.
	var duration := congress_duration(has_human)
	_congress_time_left = duration + GameRules.ELECTION_NIGHT_PAPER
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
	if int(turn_flow.get("peer", -1)) == old_id:
		turn_flow["peer"] = new_id
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
	if voter_base.has(old_id):
		voter_base[new_id] = voter_base[old_id]
		voter_base.erase(old_id)
	for alliance_id in alliances.keys():
		var alliance: Dictionary = alliances[alliance_id]
		var members: Array = alliance.get("members", []).duplicate()
		var member_index := members.find(old_id)
		if member_index >= 0:
			members[member_index] = new_id
		alliance["members"] = members
		if int(alliance.get("leader", -1)) == old_id:
			alliance["leader"] = new_id
		alliances[alliance_id] = alliance
	for rid in alliance_requests.keys():
		var req: Dictionary = alliance_requests[rid]
		if int(req.get("party", -1)) == old_id:
			req["party"] = new_id
		var voters: Array = (req.get("voters", []) as Array).duplicate()
		if voters.has(old_id):
			voters[voters.find(old_id)] = new_id
		req["voters"] = voters
		var votes: Dictionary = (req.get("votes", {}) as Dictionary).duplicate()
		if votes.has(old_id):
			votes[new_id] = votes[old_id]
			votes.erase(old_id)
		req["votes"] = votes
	if former_allies.has(old_id):
		former_allies[new_id] = former_allies[old_id]
		former_allies.erase(old_id)
	for pid in former_allies.keys():
		var others: Array = former_allies[pid]
		if others.has(old_id):
			others[others.find(old_id)] = new_id
	for table in [populism, turmoil, law_rounds, congress_rounds,
			miting_fatigue, election_groups,
			national_list, last_seats, election_seats, last_vote_shares, previous_vote_shares, party_congress]:
		if table.has(old_id):
			table[new_id] = table[old_id]
			table.erase(old_id)
	var t := passed_threshold.find(old_id)
	if t != -1:
		passed_threshold[t] = new_id
	for nested in [last_province_results, organizations]:
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
		"world_settings": MultiplayerManager.world_settings,
		"alliances_enabled": alliances_enabled,
		"alliances": alliances,
		"alliance_requests": alliance_requests,
		"voter_base": _vb_pack(),
		"alliance_request_next": _next_alliance_request,
		"former_allies": former_allies,
		"last_election_alliances": last_election_alliances,
		"turn_flow": turn_flow,
		"law_rounds": law_rounds,
		"tax_rounds": tax_rounds,
		"constitution_rounds": constitution_rounds,
		"populism": populism,
		"splinters": splinters,
		"early_requests": early_requests,
		"congress_rounds": congress_rounds,
		"previous_vote_shares": previous_vote_shares,
		"party_congress": party_congress,
		"congress_active": congress_active,
		"agenda": agenda,
		"crisis": crisis,
		"polls": polls,
		"axis_history": axis_history,
		"game_stats": game_stats,
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
		"max_rounds_override": max_rounds_override,
		"passed": passed_threshold,
		"events": province_events,
		"organizations": organizations,
		"province_profiles": province_profiles,
		"miting_fatigue": miting_fatigue,
		"election_groups": election_groups,
		"former_parties": former_parties,
		"economy": economy,
		"disaster": disaster,
		"approval": approval,
		"invest_requests": invest_requests,
		"funds": funds,
		"game_finished": game_finished,
		"final_ranking": final_ranking,
		"end_reason": game_end_reason,
	}
	if include_results:
		state["map"] = GameMap.data
		state["province_results"] = last_province_results
	return state

## Kapanan / bağımsızlaşan partiler düşer; lider yoksa liderlik en çok vekili
## olan üyeye geçer; tek üye kalan ittifak biter (cezasız).
func _prune_alliances() -> void:
	for alliance_id in alliances.keys():
		var alliance: Dictionary = alliances[alliance_id]
		var members: Array = []
		for pid in alliance.get("members", []):
			if PartyManager.parties.has(int(pid)) and not PartyManager.is_independent(int(pid)) and not members.has(int(pid)):
				members.append(int(pid))
		if members.size() <= 1 and (alliance.get("members", []) as Array).size() > 1:
			alliances.erase(alliance_id)
			_pending_log.append({"text": L.t("“%s” grubunda tek parti kaldı; ittifak sona erdi.") % String(alliance.get("name", "")),
				"peer_id": -1, "province": "", "kind": "alliance"})
			continue
		if members.is_empty():
			alliances.erase(alliance_id)
			continue
		alliance["members"] = members
		if not members.has(int(alliance.get("leader", -1))):
			var best: int = members[0]
			for pid in members:
				var score := float(last_seats.get(pid, 0)) * 1000.0 + float(last_vote_shares.get(pid, 0.0))
				if score > float(last_seats.get(best, 0)) * 1000.0 + float(last_vote_shares.get(best, 0.0)):
					best = pid
			alliance["leader"] = best
		alliances[alliance_id] = alliance
	for rid in alliance_requests.keys():
		var req: Dictionary = alliance_requests[rid]
		if not alliances.has(int(req.get("alliance", -1))) or not PartyManager.parties.has(int(req.get("party", -1))) 				or alliance_of(int(req.get("party", -1))) >= 0:
			alliance_requests.erase(rid)

func _apply_state(state: Dictionary) -> void:
	state_version = int(state["version"])
	inventories = state["inventories"]
	# 0.0.166 öncesi kart adları ("mana_bonusu" → bağış kampanyası).
	for owner in inventories.keys():
		var hand: Array = inventories[owner]
		for i in hand.size():
			hand[i] = OLD_CARD_TYPES.get(String(hand[i]), hand[i])
		for removed in REMOVED_CARD_TYPES:
			while hand.has(removed):
				hand.erase(removed)
	turn_order = state["turn_order"]
	current_turn_index = int(state["turn_index"])
	var world: Dictionary = state.get("world_settings", MultiplayerManager.world_settings)
	if world != MultiplayerManager.world_settings:
		MultiplayerManager._apply_world_settings(world)
	alliances_enabled = bool(state.get("alliances_enabled", true))
	alliances = state.get("alliances", {})
	alliance_requests = state.get("alliance_requests", {})
	var base: Dictionary = state.get("voter_base", {})
	if base != voter_base:
		_vb_unpack(base)
	_next_alliance_request = int(state.get("alliance_request_next", 0))
	former_allies = state.get("former_allies", {})
	last_election_alliances = state.get("last_election_alliances", {})
	# 0.0.225 öncesi kayıt: lideri olmayan ittifakın lideri ilk üye.
	for alliance_id in alliances:
		var old: Dictionary = alliances[alliance_id]
		if not old.has("leader") and not (old.get("members", []) as Array).is_empty():
			old["leader"] = int(old["members"][0])
		old.erase("invitations")
	turn_flow = state.get("turn_flow", {})
	_turn_serial = maxi(_turn_serial, int(turn_flow.get("serial", 0)))
	law_rounds = state.get("law_rounds", {})
	tax_rounds = state.get("tax_rounds", {})
	constitution_rounds = state.get("constitution_rounds", {})
	populism = state.get("populism", {})
	splinters = state.get("splinters", {})
	early_requests = state.get("early_requests", {})
	congress_rounds = state.get("congress_rounds", {})
	previous_vote_shares = state.get("previous_vote_shares", {})
	party_congress = state.get("party_congress", {})
	congress_active = bool(state.get("congress_active", false))
	agenda = state.get("agenda", {})
	crisis = state.get("crisis", {})
	polls = state.get("polls", {})
	axis_history = state.get("axis_history", {})
	game_stats = state.get("game_stats", {})
	national_list = state.get("national_list", {})
	round_number = int(state["round"])
	_turn_deadline_ms = Time.get_ticks_msec() + int(float(state["turn_time_left"]) * 1000.0)
	_turn_time_synced = float(state["turn_time_left"])
	last_election_round = int(state["last_election_round"])
	last_election_was_early = bool(state["early"])
	last_vote_shares = state["vote_shares"]
	credibility = state.get("credibility", {})
	music_track = String(state.get("music_track", "game"))
	last_seats = state["seats"]
	election_seats = state.get("election_seats", {})
	early_election_pending = bool(state.get("early_election_pending", false))
	election_anchor = int(state.get("election_anchor", 0))
	max_rounds_override = int(state.get("max_rounds_override", 0))
	GameRules.set_max_rounds_override(max_rounds_override)
	# Takvim çıpası her istemcide aynı olmalı (erken seçim sonrası).
	GameRules.set_election_anchor(election_anchor)
	passed_threshold = state["passed"]
	province_events = state["events"]
	organizations = state.get("organizations", {})
	miting_fatigue = state.get("miting_fatigue", {})
	election_groups = state.get("election_groups", {})
	former_parties = state.get("former_parties", {})
	# Eski sürüm durumunda ekonomi yoktur: güvenli başlangıç değerleri.
	economy = Economy.normalized(state.get("economy", {}))
	disaster = state.get("disaster", {})
	approval = state.get("approval", {})
	invest_requests = state.get("invest_requests", {})
	# PARTİ KASASI (milyon ¤). 0.0.166 öncesi durumda alan "mana" adındaydı;
	# para ölçeği eski değerlerle birebir kurulduğu için (bkz. GameRules) değer
	# aynen taşınır. İkisi de yoksa boş başlar (herkes 0).
	funds = state.get("funds", state.get("mana", {}))
	game_finished = bool(state["game_finished"])
	final_ranking = state["final_ranking"]
	game_end_reason = str(state["end_reason"])
	if state.has("map") and int((state["map"] as Dictionary).get("seed", -1)) != GameMap.seed_value():
		GameMap.set_data(state["map"])
		_vb_ready = false
	# Vekil sayıları HER durumda haritadan yeniden okunur: istemci haritayı aynı
	# tohumla kendisi üretince (seed eşit) bu tablo açılıştaki varsayılan
	# haritadan kalıyordu, her oyuncu ilde farklı vekil sayısı görüyordu.
	if state.has("map") or _province_seat_counts.size() != GameMap.province_ids().size():
		_load_province_seat_counts()
	if state.has("province_results"):
		last_province_results = state["province_results"]
	# Eski sürüm (ideoloji eksenli) bir host'un durumu sessizce yeni profillere
	# eşlenmez: geçersiz profiller hiç alınmaz (bkz. VoterGroups.is_valid_profile).
	if state.has("province_profiles") and province_profiles != state["province_profiles"] and _valid_profiles(state["province_profiles"]):
		province_profiles = state["province_profiles"]
		_vb_ready = false

static func _valid_profiles(profiles) -> bool:
	if not profiles is Dictionary:
		return false
	for province_id in profiles.keys():
		if not VoterGroups.is_valid_profile(profiles[province_id]):
			return false
	return true

## Host: durumu (sürümü artırarak) herkese yayınlar ve olayın sinyallerini
## kendi tarafında da doğrudan atar (.rpc() göndericide çalışmaz).
var _broadcast_snapshot: Dictionary = {}
var _received_snapshot: Dictionary = {}

func _push_state(event: Dictionary, include_results: bool = false) -> void:
	_prune_alliances()
	if not _pending_log.is_empty():
		event = event.duplicate()
		event["extra_log"] = _pending_log
		_pending_log = []
	if not _pending_dealt.is_empty():
		event = event.duplicate()
		event["dealt"] = _pending_dealt
		_pending_dealt = {}
	if not _pending_disaster_fx.is_empty():
		event = event.duplicate()
		event["disaster"] = _pending_disaster_fx
		_pending_disaster_fx = {}
	if not _pending_econ.is_empty():
		event = event.duplicate()
		if not event.has("econ"):
			event["econ"] = _pending_econ
		_pending_econ = {}
	state_version += 1
	if not _is_local_only():
		var full: bool = include_results or event.get("type", "") in ["full", "election", "player_left", "player_away", "player_back", "party_split", "party_merge", "party_change"]
		var state := _pack_state(full)
		if full or _broadcast_snapshot.is_empty() or int(_broadcast_snapshot["version"]) != state_version - 1:
			_receive_state.rpc(state, event)
		else:
			_receive_state_delta.rpc(int(_broadcast_snapshot["version"]), _state_delta(state, _broadcast_snapshot), event)
		# Packed arrays use copy-on-write; nested dictionaries need a snapshot.
		_broadcast_snapshot = state.duplicate(true)
	_emit_post_event(event)

func _state_delta(state: Dictionary, previous: Dictionary) -> Dictionary:
	var changes := {}
	for key in state:
		if not previous.has(key) or state[key] != previous[key]:
			changes[key] = state[key]
	return changes

func _emit_post_event(event: Dictionary) -> void:
	var type: String = event.get("type", "")
	# Seçim: ekran ÖNCE donsun (bkz. GameScreen._on_election_completed), sonra
	# paneller güncellensin — yoksa sonuç bir an önceden görünüyordu.
	if type == "election":
		GameLog.note_election()
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
	if event.has("message"):
		opinion_event.emit(str(event["message"]))
		log_event(str(event["message"]), int(event.get("peer_id", -1)), String(event.get("province", "")), _log_kind(event))
	for extra in event.get("extra_log", []):
		log_event(String(extra["text"]), int(extra["peer_id"]), String(extra["province"]), String(extra["kind"]))
	if type == "secret_news":
		for i in event.get("news", []).size():
			var news: Dictionary = event["news"][i]
			if news.has("message"):
				opinion_event.emit(str(news["message"]))
				log_event(str(news["message"]), int(news.get("peer_id", -1)), "", _log_kind(news))
			# Batch içindeki her gazete ayrı kimlik alır.
			news = news.duplicate()
			news["news_id"] = "%d|%d" % [state_version, i]
			event_presented.emit(news, state_version)
	else:
		event_presented.emit(event, state_version)
	match type:
		"round":
			log_event(L.t("%s başladı.") % GameRules.period_label(round_number), -1, "", "round")
		"election":
			log_event((L.t("%s erken seçimi yapıldı.") if last_election_was_early else L.t("%s genel seçimi yapıldı.")) % GameRules.election_label(last_election_round), -1, "", "election")
			var mine := party_of(multiplayer.get_unique_id())
			var trend := election_trend(mine)
			if trend != "":
				log_event(trend, mine, "", "election")

@rpc("authority", "reliable")
func _secret_play_confirmed(card_type: String) -> void:
	card_played.emit(multiplayer.get_unique_id(), card_type)

@rpc("authority", "reliable")
func _receive_state(state: Dictionary, event: Dictionary) -> void:
	_received_snapshot = state.duplicate(true)
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

## Same event and application path as a full snapshot; only transport is smaller.
@rpc("authority", "reliable")
func _receive_state_delta(base_version: int, changes: Dictionary, event: Dictionary) -> void:
	if state_version != base_version or int(_received_snapshot.get("version", -1)) != base_version:
		request_full_sync()
		return
	var state := _received_snapshot.duplicate()
	state.merge(changes, true)
	_receive_state(state, event)

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
func _request_invest(province_id: String, state: float = 1.0, tier: int = DEFAULT_TIER) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_invest_move(multiplayer.get_remote_sender_id(), province_id, state, tier)

@rpc("any_peer", "reliable")
func _request_censure() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_censure_move(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _request_miting(province_id: String, state: float = 0.0, focus: Array = [], tier: int = DEFAULT_TIER, smear_target: int = -1) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_miting_move(multiplayer.get_remote_sender_id(), province_id, state, focus, tier, smear_target)

@rpc("any_peer", "reliable")
func _request_pass() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_pass(multiplayer.get_remote_sender_id(), true)
