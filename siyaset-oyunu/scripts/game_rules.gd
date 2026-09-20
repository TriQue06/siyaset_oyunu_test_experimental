class_name GameRules
extends RefCounted
## Oyunun zaman/döngü kuralları tek yerde. Dengeyi değiştirmek için sadece
## buradaki sabitleri düzenlemek yeterli.
##
## DÖNGÜ
##   - Bir TUR: turn_order'daki herkesin sırayla bir kez oynaması. Bir tur
##     oyunun takviminde BİR YILDIR (bkz. START_YEAR / year_of_round).
##   - İlk FIRST_ELECTION_ROUND tur KAMPANYA DÖNEMİDİR (meclis yok: il
##     başkanlıkları, mitingler, gözcü, seçim vaatleri). İlk seçim o turun
##     sonunda, sonra her ELECTION_INTERVAL turda bir (5, 10, 15 ... 30). Arada
##     kalan turlarda kurulu hükümet görevde kalır. MAKAM PUANLARI hükümet
##     KURULDUĞU ANDA tek sefer yazılır, her tur tekrarlanmaz.
##   - HAMLE SINIRI YOK: sırası gelen oyuncu manası yettiğince hamle yapar,
##     "Turu Bitir" ile sırayı devreder. Mana birikir, üst sınır yok. Manası
##     biten (ve elinde bedava kart olmayan) oyuncunun sırası kendiliğinden devreder.
##   - Her seçimden sonra herkes +ELECTION_MANA_BONUS, göreve başlayan hükümetin
##     partileri +GOVERNMENT_MANA_BONUS mana alır (gensoruyla düşen hükümetin
##     yerine kurulan hükümet dahil).
##   - MANA: herkes MANA_START ile başlar; SIRASI GELDİĞİNDE +MANA_PER_ROUND alır
##     (tur sonunda değil: harcadığın mana turu bitirince geri dolmuş görünmez).
##     Hükümette görevi olan partiler bunun yerine +MANA_PER_ROUND_GOVERNMENT.
##   - YASA ilk seçimden önce yapılamaz: meclis yok, saf propaganda dönemi.
##     HAMLELER: miting MITING_MANA_COST, il başkanlığı ORG_MANA_COST, gözcü
##     yasa oyuncu başına turda LAWS_PER_ROUND kez.
##   - TEŞKİLATLANMA (eski il başkanlığı + gözcü) il başına 3 seviye; her
##     seviye ORG_MANA_COST. 1: az oy bonusu + ilin görüşü (her eksende hangi uç),
##     2: orta bonus + orta isabetli anket, 3: yüksek bonus + yüksek isabetli anket.
##     KART ÇEKMEK bedava, turda DRAWS_PER_TURN kez; kart oynamak sınırsız
##     (kartların kendi bedeli var). Her seçimden sonra herkese 1 kart hediye.
##     Kartları oynamanın bedeli CardPresets.CARD_MANA_COSTS.
##   - Hükümet kurulamazsa (tüm görev hakları biterse) o turun sonunda ERKEN
##     SEÇİM yapılır.
##   - MAX_ROUNDS'uncu turun sonunda SON SEÇİM yapılır; kurulan hükümet makam
##     puanlarını kurulurken alır ve puan tablosu kesinleşir. En çok puanı olan
##     kazanır (eşitlikte milletvekili sayısı).

## TAKVİM: BİR TUR ALTI AYDIR. Lobideki "seçimler kaç yılda bir" ayarı YIL
## cinsindendir; tur cinsinden karşılığı ELECTION_INTERVAL = yıl × 2'dir.
## Oyun MAX_ROUNDS = aralık × seçim sayısı tur (yani aralık_yıl × sayı × 2 tur)
## sürer. Değerler configure() ile (her cihazda, ayar senkronlanınca) güncellenir.
const ROUNDS_PER_YEAR := 2
const DEFAULT_ELECTION_INTERVAL := 4
const DEFAULT_ELECTION_COUNT := 8
const ELECTION_INTERVAL_MIN := 2
const ELECTION_INTERVAL_MAX := 8
const ELECTION_COUNT_MIN := 2
const ELECTION_COUNT_MAX := 12
## Seçim aralığı YIL cinsinden (lobi ayarı).
static var ELECTION_INTERVAL_YEARS: int = DEFAULT_ELECTION_INTERVAL
## Aynı aralığın TUR cinsinden karşılığı (oyun içi hesaplar bunu kullanır).
static var ELECTION_INTERVAL: int = DEFAULT_ELECTION_INTERVAL * ROUNDS_PER_YEAR
static var FIRST_ELECTION_ROUND: int = DEFAULT_ELECTION_INTERVAL * ROUNDS_PER_YEAR
static var MAX_ROUNDS: int = DEFAULT_ELECTION_INTERVAL * ROUNDS_PER_YEAR * DEFAULT_ELECTION_COUNT

## Seçim takviminin ÇIPASI: seçimler bu turdan itibaren ELECTION_INTERVAL'de
## bir yapılır. Normalde ilk seçim turudur; ERKEN SEÇİM kabul edilince o tura
## kayar ve takvim oradan devam eder.
static var ELECTION_ANCHOR: int = DEFAULT_ELECTION_INTERVAL * ROUNDS_PER_YEAR

static func configure(interval_years: int, count: int) -> void:
	ELECTION_INTERVAL_YEARS = clampi(interval_years, ELECTION_INTERVAL_MIN, ELECTION_INTERVAL_MAX)
	ELECTION_INTERVAL = ELECTION_INTERVAL_YEARS * ROUNDS_PER_YEAR
	FIRST_ELECTION_ROUND = ELECTION_INTERVAL
	ELECTION_ANCHOR = FIRST_ELECTION_ROUND
	MAX_ROUNDS = ELECTION_INTERVAL * clampi(count, ELECTION_COUNT_MIN, ELECTION_COUNT_MAX)

## Erken seçim yapıldı: takvim bu tura sabitlenir, sonraki seçimler buradan
## itibaren aynı aralıkla gelir. 0 = varsayılan takvim.
static func set_election_anchor(round_number: int) -> void:
	ELECTION_ANCHOR = FIRST_ELECTION_ROUND if round_number <= 0 else round_number

const MANA_START := 0
const MANA_PER_ROUND := 3
## Hükümette görevi olan partiler tur başına 1 fazla mana alır (iktidar avantajı).
const MANA_PER_ROUND_GOVERNMENT := 4
## Yasa sunmak BEDAVA (turda 1): meclis oyunun merkezi, mana engel olmasın.
const LAW_MANA_COST := 0
const LAWS_PER_ROUND := 1
const DRAW_MANA_COST := 0
const DRAWS_PER_TURN := 1
## Teşkilat anketinin sapması (her partinin oyu en fazla bu oranda sapar):
## 2. seviye orta isabet, 3. seviye yüksek isabet.
const POLL_ERROR_MEDIUM := 0.3
const POLL_ERROR_HIGH := 0.08
const MITING_MANA_COST := 2
## Yatırım (sadece hükümet partileri) ve gensoru (sadece muhalefet, hükümet
## azınlıktayken) hamleleri.
const INVEST_MANA_COST := 2
## Gensoru BEDAVA: muhalefetin elindeki tek gerçek silah engellenmemeli.
const CENSURE_MANA_COST := 0
## Popülizm bonusu kartı bu kadar tur sürer; mana bonusu kartı bu kadar mana verir.
const POPULISM_ROUNDS := 3
const MANA_BONUS_AMOUNT := 5
const ELECTION_MANA_BONUS := 1
## GÜNDEM TAKVİMİ: ilk seçimden hemen sonraki turdan itibaren AGENDA_ROUNDS tur
## (6 ay) gündem, AGENDA_GAP tur (12 ay) ara, yine gündem... Gündemli her tur
## tek bir eksenin bir ucudur; bir gündem dönemindeki turlar farklı eksenlerdir
## (eksenler her dönemde rastgele). YASA sadece gündemdeki eksende sunulabilir.
const AGENDA_ROUNDS := 1
const AGENDA_GAP := 2
## Kabul edilen yasa, getiren partiye puan tablosunda bu kadar puan yazar
## (hükümet partisinin yasası daha çok).
## Kabul edilen gensoru, getiren partiye puan tablosunda bu kadar puan yazar.
const CENSURE_PASS_SCORE := 5
## Yasa geçirmek artık sembolik bir puan: asıl puan iktidarda olmaktan gelir.
const LAW_PASS_SCORE := 2
const LAW_PASS_SCORE_GOV := 3
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

## TAKVİM: bir tur ALTI AYDIR. Oyun START_YEAR'ın ilk yarısında başlar.
## Tur sonunda sandıktan çıkan meclis bir sonraki dönemin meclisidir; bu yüzden
## seçim, biten turun DEĞİL onu izleyen yılın adıyla anılır (varsayılan 4 yıllık
## aralıkla 1954, 1958, 1962 ...).
const START_YEAR := 1950

## Bu turun takvim yılı.
static func year_of_round(round_number: int) -> int:
	return START_YEAR + (maxi(1, round_number) - 1) / ROUNDS_PER_YEAR

## Yılın hangi yarısı: 0 = Ocak-Haziran, 1 = Temmuz-Aralık.
static func half_of_round(round_number: int) -> int:
	return (maxi(1, round_number) - 1) % ROUNDS_PER_YEAR

## "1950 · Oca-Haz" gibi okunur dönem etiketi.
static func period_label(round_number: int) -> String:
	return "%d %s" % [year_of_round(round_number),
		"Oca-Haz" if half_of_round(round_number) == 0 else "Tem-Ara"]

## round_number'uncu turun sonunda yapılan seçimin adı olan yıl.
static func election_year(round_number: int) -> int:
	return START_YEAR + maxi(1, round_number) / ROUNDS_PER_YEAR


static func is_election_round(round_number: int) -> bool:
	# Son turun sonunda da seçim yapılır (son seçim); oyun hükümet kurulunca biter.
	if round_number > MAX_ROUNDS:
		return false
	if round_number == MAX_ROUNDS:
		return true
	# Takvim ELECTION_ANCHOR turundan itibaren işler (erken seçim çıpayı kaydırır).
	return round_number >= ELECTION_ANCHOR \
		and (round_number - ELECTION_ANCHOR) % ELECTION_INTERVAL == 0

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
