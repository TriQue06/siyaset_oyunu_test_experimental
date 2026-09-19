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
##     Kart çekmek bedava, turda DRAWS_PER_TURN kez; kart OYNAMAK sınırsız
##     (kartların kendi bedeli var).
##     Kartları oynamanın bedeli CardPresets.CARD_MANA_COSTS.
##   - Hükümet kurulamazsa (tüm görev hakları biterse) o turun sonunda ERKEN
##     SEÇİM yapılır.
##   - MAX_ROUNDS'uncu turun sonunda SON SEÇİM yapılır; kurulan hükümet
##     makam puanlarını bir kez daha alır ve puan tablosu kesinleşir. Hükümet
##     kurulamazsa bu puan yazılmaz. En çok puanı olan kazanır (eşitlikte
##     milletvekili sayısı).

const ELECTION_INTERVAL := 5
const FIRST_ELECTION_ROUND := 5

const MANA_START := 0
const MANA_PER_ROUND := 3
const LAW_MANA_COST := 1
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
const CENSURE_MANA_COST := 1
## Popülizm bonusu kartı bu kadar tur sürer; mana bonusu kartı bu kadar mana verir.
const POPULISM_ROUNDS := 4
const MANA_BONUS_AMOUNT := 5
const ELECTION_MANA_BONUS := 1
## GÜNDEM: bir eksenin bir ucuyla ilgili sıcak konu AGENDA_ROUNDS tur sürer
## (başladığı tur dahil). Gündem yokken her tur sonunda AGENDA_RANDOM_CHANCE
## olasılıkla rastgele bir gündem başlar; gündem kartıyla da başlatılabilir.
const AGENDA_ROUNDS := 2
const AGENDA_RANDOM_CHANCE := 0.3
## Kabul edilen yasa, getiren partiye puan tablosunda bu kadar puan yazar
## (hükümet partisinin yasası daha çok).
const LAW_PASS_SCORE := 4
const LAW_PASS_SCORE_GOV := 6
const GOVERNMENT_MANA_BONUS := 1
const ORG_MANA_COST := 2
const ORG_MAX_LEVEL := 3
## Seçimler 5 turda bir: son seçim de takvime denk gelsin diye 30 tur.
const MAX_ROUNDS := 30

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
