class_name GameRules
extends RefCounted
## Oyunun zaman/döngü kuralları tek yerde. Dengeyi değiştirmek için sadece
## buradaki sabitleri düzenlemek yeterli.
##
## DÖNGÜ
##   - Bir TUR: turn_order'daki herkesin sırayla bir kez oynaması.
##   - İlk FIRST_ELECTION_ROUND tur KAMPANYA DÖNEMİDİR (meclis yok: il
##     başkanlıkları, mitingler, gözcü, seçim vaatleri). İlk seçim o turun
##     sonunda, sonra her ELECTION_INTERVAL turda bir (5, 10, 15 ... 30). Arada
##     kalan turlarda kurulu hükümet görevde kalır ve makam puanlarını toplar.
##   - HAMLE SINIRI YOK: sırası gelen oyuncu manası yettiğince hamle yapar,
##     "Turu Bitir" ile sırayı devreder. Mana birikir, üst sınır yok. Manası
##     biten (ve elinde bedava kart olmayan) oyuncunun sırası kendiliğinden devreder.
##   - Her seçimden sonra herkes +ELECTION_MANA_BONUS, göreve başlayan hükümetin
##     partileri +GOVERNMENT_MANA_BONUS mana alır (gensoruyla düşen hükümetin
##     yerine kurulan hükümet dahil).
##   - MANA: herkes MANA_START ile başlar; SIRASI GELDİĞİNDE +MANA_PER_ROUND alır
##     (tur sonunda değil: harcadığın mana turu bitirince geri dolmuş görünmez).
##   - YASA ilk seçimden önce yapılamaz: meclis yok, saf propaganda dönemi.
##     HAMLELER: miting MITING_MANA_COST, il başkanlığı ORG_MANA_COST, gözcü
##     yasa oyuncu başına turda LAWS_PER_ROUND kez.
##   - TEŞKİLATLANMA (eski il başkanlığı + gözcü) il başına 3 seviye; her
##     seviye ORG_MANA_COST. 1: az oy bonusu + ilin görüşü (her eksende hangi uç),
##     2: orta bonus + orta isabetli anket, 3: yüksek bonus + yüksek isabetli anket.
##     KART: sırası gelen oyuncuya oyun bir kart verir (el doluysa vermez);
##     kart oynamak sınırsız (kartların kendi bedeli var).
##     Kartları oynamanın bedeli CardPresets.CARD_MANA_COSTS.
##   - Hükümet kurulamazsa (tüm görev hakları biterse) o turun sonunda ERKEN
##     SEÇİM yapılır.
##   - MAX_ROUNDS'uncu turun sonunda SON SEÇİM yapılır; kurulan hükümet
##     makam puanlarını bir kez daha alır ve puan tablosu kesinleşir. Hükümet
##     kurulamazsa bu puan yazılmaz. En çok puanı olan kazanır (eşitlikte
##     milletvekili sayısı).

## Oyun süresi LOBİ AYARIDIR (bkz. MultiplayerManager.election_interval /
## election_count): seçimler ELECTION_INTERVAL turda bir, toplam ELECTION_COUNT
## seçim; oyun MAX_ROUNDS = aralık × sayı tur sürer. Değerler configure() ile
## (her cihazda, ayar senkronlanınca) güncellenir.
const DEFAULT_ELECTION_INTERVAL := 4
const DEFAULT_ELECTION_COUNT := 7
const ELECTION_INTERVAL_MIN := 2
const ELECTION_INTERVAL_MAX := 8
const ELECTION_COUNT_MIN := 2
const ELECTION_COUNT_MAX := 12
static var ELECTION_INTERVAL: int = DEFAULT_ELECTION_INTERVAL
static var FIRST_ELECTION_ROUND: int = DEFAULT_ELECTION_INTERVAL
static var MAX_ROUNDS: int = DEFAULT_ELECTION_INTERVAL * DEFAULT_ELECTION_COUNT

static func configure(interval: int, count: int) -> void:
	ELECTION_INTERVAL = clampi(interval, ELECTION_INTERVAL_MIN, ELECTION_INTERVAL_MAX)
	FIRST_ELECTION_ROUND = ELECTION_INTERVAL
	MAX_ROUNDS = ELECTION_INTERVAL * clampi(count, ELECTION_COUNT_MIN, ELECTION_COUNT_MAX)

const MANA_START := 0
const MANA_PER_ROUND := 3
const LAW_MANA_COST := 1
const LAWS_PER_ROUND := 1
## Teşkilat anketinin sapması (her partinin oyu en fazla bu oranda sapar):
## 2. seviye orta isabet, 3. seviye yüksek isabet.
const POLL_ERROR_MEDIUM := 0.3
const POLL_ERROR_HIGH := 0.08
const MITING_MANA_COST := 2
## Yatırım (sadece hükümet partileri) ve gensoru (sadece muhalefet, hükümet
## azınlıktayken) hamleleri.
const INVEST_MANA_COST := 2
const CENSURE_MANA_COST := 1
## Popülizm bonusu kartı bu kadar tur sürer; mana bonusu kartı bu kadar mana verir.
const POPULISM_ROUNDS := 4
const MANA_BONUS_AMOUNT := 5
const ELECTION_MANA_BONUS := 1
## GÜNDEM TAKVİMİ: ilk seçimden hemen sonraki turdan itibaren AGENDA_ROUNDS tur
## gündem, AGENDA_GAP tur ara, yine AGENDA_ROUNDS tur gündem... Gündemli her tur
## tek bir eksenin bir ucudur; bir üçlemedeki üç tur üç farklı eksendir (sıra
## her üçlemede rastgele). YASA sadece gündemdeki eksende sunulabilir.
const AGENDA_ROUNDS := 3
const AGENDA_GAP := 2
## Kabul edilen yasa, getiren partiye puan tablosunda bu kadar puan yazar
## (hükümet partisinin yasası daha çok).
const LAW_PASS_SCORE := 4
const LAW_PASS_SCORE_GOV := 6
const GOVERNMENT_MANA_BONUS := 1
const ORG_MANA_COST := 2
const ORG_MAX_LEVEL := 3

## Süre sınırları (saniye). AFK kalan tek bir oyuncu oyunu kilitleyemesin diye.
## Tur süresi dolarsa sıra otomatik devredilir; hükümet kurma süresi dolarsa o teklif
## hakkı yanar; oylama süresi dolarsa oy vermeyenler ÇEKİMSER sayılır.
const TURN_TIMEOUT := 90.0
const FORMATION_TIMEOUT := 120.0
const VOTE_TIMEOUT := 45.0
## Seçim gecesi canlı sayım yayınının süresi ve bittikten sonra kesin sonucun
## ekranda kaldığı süre (bkz. election_results.gd). Host, hükümet kurma
## süresine bunları ekler.
const ELECTION_NIGHT_SECONDS := 22.5
const ELECTION_NIGHT_HOLD := 5.0

## Oyun ortasında oyuncular ayrılıp bu sayının altına düşülürse oyun biter.
const MIN_PLAYERS_TO_CONTINUE := 2

static func is_election_round(round_number: int) -> bool:
	# Son turun sonunda da seçim yapılır (son seçim); oyun hükümet kurulunca biter.
	return round_number >= FIRST_ELECTION_ROUND and round_number <= MAX_ROUNDS \
		and (round_number - FIRST_ELECTION_ROUND) % ELECTION_INTERVAL == 0

## round_number'dan (dahil) itibaren seçimin yapılacağı ilk tur; oyun
## bitmeden seçim kalmadıysa -1.
static func next_election_round(round_number: int) -> int:
	for r in range(maxi(1, round_number), MAX_ROUNDS + 1):
		if is_election_round(r):
			return r
	return -1

static func format_seconds(seconds: float) -> String:
	var s: int = int(ceil(maxf(0.0, seconds)))
	return "%d:%02d" % [s / 60, s % 60]
