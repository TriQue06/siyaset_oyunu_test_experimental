class_name GameRules
extends RefCounted
## Oyunun zaman/döngü kuralları tek yerde. Dengeyi değiştirmek için sadece
## buradaki sabitleri düzenlemek yeterli.
##
## DÖNGÜ
##   - Bir TUR: turn_order'daki herkesin sırayla bir kez oynaması.
##   - İlk FIRST_ELECTION_ROUND tur KAMPANYA DÖNEMİDİR (meclis yok: il
##     başkanlıkları, mitingler, gözcü, seçim vaatleri). İlk seçim o turun
##     sonunda, sonra her ELECTION_INTERVAL turda bir (3, 6, 9 ...). Arada
##     kalan turlarda kurulu hükümet görevde kalır ve makam puanlarını toplar.
##   - MANA: herkes MANA_START ile başlar, her tur sonunda +MANA_PER_ROUND,
##     pas geçince +MANA_PASS_BONUS. Sınır yok. Yasa LAW_MANA_COST, il
##     başkanlığı ORG_MANA_COST, kartların bedeli CardPresets.CARD_MANA_COSTS.
##     Kart çekmek bedavadır ve hamle sayılmaz.
##   - Hükümet kurulamazsa (tüm görev hakları biterse) o turun sonunda ERKEN
##     SEÇİM yapılır.
##   - MAX_ROUNDS'uncu turun sonunda oyun biter; en çok puanı olan kazanır
##     (eşitlikte milletvekili sayısı).

const ELECTION_INTERVAL := 3
const FIRST_ELECTION_ROUND := 3

const MANA_START := 1
const MANA_PER_ROUND := 1
const MANA_PASS_BONUS := 1
const LAW_MANA_COST := 1
const ORG_MANA_COST := 2
const ORG_MAX_LEVEL := 3
## GEÇİCİ olarak iki katına çıkarıldı (12 -> 24) ki oyun geç bitsin.
const MAX_ROUNDS := 24

## Süre sınırları (saniye). AFK kalan tek bir oyuncu oyunu kilitleyemesin diye.
## Tur süresi dolarsa otomatik pas; hükümet kurma süresi dolarsa o teklif
## hakkı yanar; oylama süresi dolarsa oy vermeyenler ÇEKİMSER sayılır.
const TURN_TIMEOUT := 60.0
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
	# Son turun sonunda seçim yapılmaz: oyun biter.
	return round_number >= FIRST_ELECTION_ROUND and round_number < MAX_ROUNDS \
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
