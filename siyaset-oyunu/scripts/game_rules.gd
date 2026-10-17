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
##   - HAMLE SINIRI YOK: sırası gelen oyuncu PARTİ KASASI yettiğince hamle
##     yapar, "Turu Bitir" ile sırayı devreder. Kasa birikir, üst sınır yok.
##   - PARTİ KASASI (milyon ¤): herkes FUNDS_START ile başlar; SIRASI
##     GELDİĞİNDE bağış ve aidat geliri +FUNDS_PER_ROUND (hükümette görevi
##     olan partiler +FUNDS_PER_ROUND_GOVERNMENT) ve teşkilat geliri (en fazla
##     ORG_INCOME_CAP) girer. Her seçimden sonra herkes +ELECTION_FUNDS_BONUS
##     (devlet hazine yardımı), göreve başlayan hükümetin partileri
##     +GOVERNMENT_FUNDS_BONUS alır. DEVLET HAZİNESİ ayrıdır (economy.gd).
##   - YASA ilk seçimden önce yapılamaz: meclis yok, saf propaganda dönemi.
##     Yasa oyuncu başına turda LAWS_PER_ROUND kez.
##   - TEŞKİLATLANMA (eski il başkanlığı + gözcü) il başına 2 seviye; her
##     seviye ORG_FUNDS_COST. 1: az oy bonusu + kaba anket, 2: yüksek bonus +
##     isabetli anket. (İllerin seçmen grubu dağılımı herkese açıktır.)
##     KART ÇEKME HAMLESİ YOK: sıra gelince otomatik olarak 1 kart dağıtılır
##     (el doluysa verilmez); kart oynamak sınırsız (kartların kendi bedeli
##     var). Her seçimden sonra da herkese 1 kart hediye.
##     Kartların oynama bedeli yok (0.0.232).
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
## VARSAYILAN: seçimler 2 YILDA BİR, yani 4 dönemde bir (tur = 6 ay).
const DEFAULT_ELECTION_INTERVAL := 2
const DEFAULT_ELECTION_COUNT := 5
const ELECTION_INTERVAL_MIN := 1
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

## Oyun içinde kaymış takvim (erken seçim / anayasa). configure() bunları
## SİLMEZ (0.0.218): oyun ortasındaki ayar senkronu takvimi bozuyordu.
static var _anchor_override: int = 0
static var _max_rounds_override: int = 0
static var _election_count: int = DEFAULT_ELECTION_COUNT

static func configure(interval_years: int, count: int) -> void:
	ELECTION_INTERVAL_YEARS = clampi(interval_years, ELECTION_INTERVAL_MIN, ELECTION_INTERVAL_MAX)
	ELECTION_INTERVAL = ELECTION_INTERVAL_YEARS * ROUNDS_PER_YEAR
	FIRST_ELECTION_ROUND = ELECTION_INTERVAL
	_election_count = clampi(count, ELECTION_COUNT_MIN, ELECTION_COUNT_MAX)
	ELECTION_ANCHOR = _anchor_override if _anchor_override > 0 else FIRST_ELECTION_ROUND
	MAX_ROUNDS = _max_rounds_override if _max_rounds_override > 0 else ELECTION_INTERVAL * _election_count

## Erken seçim yapıldı: takvim bu tura sabitlenir, sonraki seçimler buradan
## itibaren aynı aralıkla gelir. 0 = varsayılan takvim.
static func set_election_anchor(round_number: int) -> void:
	_anchor_override = maxi(0, round_number)
	ELECTION_ANCHOR = FIRST_ELECTION_ROUND if round_number <= 0 else round_number

## Oyunun son seçim turu kaydıysa (erken seçim / anayasa); 0 = lobi uzunluğu.
static func set_max_rounds_override(last_round: int) -> void:
	_max_rounds_override = maxi(0, last_round)
	MAX_ROUNDS = _max_rounds_override if _max_rounds_override > 0 else ELECTION_INTERVAL * _election_count

## PARA ÖLÇEĞİ: bütün parti bedelleri ve gelirleri MİLYON ¤. Bir partinin
## dönemlik geliri (30–40) devletin dönemlik vergi gelirinin (70–140) üçte
## biri kadardır; tek bir kamu yatırımı (100) bir partinin üç dönemlik
## gelirine denk gelir. Eski "mana" değerleri bu ölçeğe birebir taşındı
## (kayıt göçü için bkz. CardManager._apply_state); yatırımın ayrı hamle
## bedeli kaldırıldı, mitingin toplam bedeli MITING_FUNDS_COST oldu.
const FUNDS_START := 0
const FUNDS_PER_ROUND := 30
## Hükümette görevi olan partiler dönemde 10 milyon ¤ fazla alır (iktidar avantajı).
const FUNDS_PER_ROUND_GOVERNMENT := 40
## BEDEL YAZISI: ücretsiz hamleler her yerde "bedelsiz" diye geçer ("bedava"
## ya da "0 milyon ¤" değil). Para cezası ve finansman paylaşımı yüzünden
## ondalık da gerekirse basılır.
static func cost_text(cost: float) -> String:
	if cost <= 0.0:
		return L.t("bedelsiz")
	return L.t("%s milyon ¤") % money_text(cost)

## Tutar yazısı (milyon ¤, birimsiz): tam sayıysa "15", değilse "2,5".
static func money_text(value: float) -> String:
	return L.dec(value, 1)

## MECLİS HAMLELERİ BEDELSİZ (0.0.182): yasa, gensoru, erken seçim önergesi,
## anayasa. Meclis oyunun merkezi, para engel olmasın; sınır dönemde 1 yasa.
const LAW_FUNDS_COST := 0
const LAWS_PER_ROUND := 1
## Teşkilat anketinin sapması (her partinin oyu en fazla bu oranda sapar):
## 1. seviye YAKLAŞIK oy (±%35), 2. seviye %90 doğruluk (±%10).
const POLL_ERROR_LOW := 0.35
const POLL_ERROR_HIGH := 0.10
const MITING_FUNDS_COST := 15
## Yatırım (sadece hükümet partileri) ve gensoru (sadece muhalefet, hükümet
## azınlıktayken) hamleleri. Yatırımın asıl bedeli DEVLET HAZİNESİNDEN
## ödenir (Economy.INVEST_COST); ayrı bir hamle bedeli YOK: sınır devlet
## hazinesidir (dönemlik vergi geliri ≈ bir yatırım).
const INVEST_FUNDS_COST := 0
## Gensoru BEDELSİZ: muhalefetin elindeki tek gerçek silah engellenmemeli.
const CENSURE_FUNDS_COST := 0
## ERKEN SEÇİM hamlesi (eskiden kart): meclise önerge getirir.
const EARLY_ELECTION_FUNDS_COST := 0
## Popülizm bonusu kartı bu kadar tur sürer. BAĞIŞ KAMPANYASI kartının iki
## çeşidi var: zayıf +FUNDS_BONUS_WEAK, güçlü +FUNDS_BONUS_STRONG milyon ¤. Popülizm 0.0.232'den beri bir dönem sürer.
const POPULISM_ROUNDS := 1
const FUNDS_BONUS_WEAK := 30
const FUNDS_BONUS_STRONG := 60
const FUNDS_BONUS_AMOUNT := FUNDS_BONUS_WEAK
const ELECTION_FUNDS_BONUS := 10
## GÜNDEM (0.0.182'de kriz ile birleşti): ilk seçimden sonraki her tur bir
## SEÇMEN GRUBUNUN sıcak konusudur; art arda gelen gündemler farklı çiftlerden
## (işçi/işveren, genç/emekli, dindar/ilerici, özerkçi/milliyetçi) olur.
## YASA her zaman HER grup için sunulabilir; gündem sadece o gruba eğilimi
## ÖDÜLLENDİRİR: o gruba yasa daha güçlü (PublicOpinion.AGENDA_LAW_MULT), o
## gruba yasa sunan, EVET diyen ya da onunla toplanan parti ulusal destek
## kazanır (PublicOpinion.CRISIS_RESPONSE_NATIONAL).
const AGENDA_ROUNDS := 1
const AGENDA_GAP := 0
## Kabul edilen yasa, getiren partiye puan tablosunda bu kadar puan yazar
## (hükümet partisinin yasası daha çok).
## Kabul edilen gensoru, getiren partiye puan tablosunda bu kadar puan yazar.
const CENSURE_PASS_SCORE := 5
## Meclisten yasa geçirmek +5 puan (hükümet ya da muhalefet fark etmez).
const LAW_PASS_SCORE := 5
const LAW_PASS_SCORE_GOV := 5
const GOVERNMENT_FUNDS_BONUS := 10
## Teşkilat (0.0.227): kurmak (1. seviye) SABİT ORG_FUNDS_COST, geliştirmek
## (2. seviye) ORG_UPGRADE_FUNDS_COST. Kademeli artan fiyat kaldırıldı.
const ORG_FUNDS_COST := 10
## TEŞKİLAT GELİRİ: her ildeki teşkilat tur başında yerel bağış getirir
## (1. seviye +2,5, 2. seviye +8 milyon ¤). Üst sınır yok (0.0.227).
const ORG_INCOME := [0.0, 2.5, 8.0]
## GRUP TOPLANTISI bedeli (sırada bir kez; bir seçmen grubuyla, geçici destek).
const SPEECH_FUNDS_COST := 0
const ORG_UPGRADE_FUNDS_COST := 30

## Bu ildeki teşkilatı bir seviye ilerletmenin bedeli (current_level: şu anki
## seviye, owned: partinin teşkilatlı il sayısı). Tek doğru kaynak budur;
## oyuncu için CardManager.org_cost_for kullanılır.
## (0.0.227: fiyat sabit, owned kullanılmıyor.)
static func org_cost(current_level: int, _owned: int = 0) -> float:
	return float(ORG_FUNDS_COST if current_level <= 0 else ORG_UPGRADE_FUNDS_COST)
## En fazla 2 seviye: 1 = kaba anket + az bonus, 2 = isabetli anket + yüksek bonus.
const ORG_MAX_LEVEL := 2

## Süre sınırları (saniye). AFK kalan tek bir oyuncu oyunu kilitleyemesin diye.
## Tur süresi dolarsa sıra otomatik devredilir; hükümet kurma süresi dolarsa o teklif
## hakkı yanar; oylama süresi dolarsa oy vermeyenler ÇEKİMSER sayılır.
static var TURN_TIMEOUT := 75.0
const FORMATION_TIMEOUT := 120.0
const VOTE_TIMEOUT := 30.0
## Seçim gecesi canlı sayım yayınının süresi ve bittikten sonra kesin sonucun
## ekranda kaldığı süre (bkz. election_results.gd); ardından seçim ekranında
## sonuç gazetesi (~2,8 sn, ELECTION_NIGHT_PAPER) oynar. Host, hükümet kurma
## süresine bunları ekler.
const ELECTION_NIGHT_SECONDS := 19.5
const ELECTION_NIGHT_HOLD := 2.5
const ELECTION_NIGHT_PAPER := 3.0

## Oyun ortasında oyuncular ayrılıp bu sayının altına düşülürse oyun biter.
const MIN_PLAYERS_TO_CONTINUE := 2

## TAKVİM: bir tur ALTI AYDIR. Oyun START_YEAR'ın ilk yarısında başlar.
## Tur sonunda sandıktan çıkan meclis bir sonraki dönemin meclisidir; bu yüzden
## seçim, biten turun DEĞİL onu izleyen yılın adıyla anılır (varsayılan 4 yıllık
## aralıkla 2004, 2008, 2012 ...).
const START_YEAR := 2000

## Bu turun takvim yılı.
static func year_of_round(round_number: int) -> int:
	return START_YEAR + (maxi(1, round_number) - 1) / ROUNDS_PER_YEAR

## Yılın hangi yarısı: 0 = Ocak-Haziran, 1 = Temmuz-Aralık.
static func half_of_round(round_number: int) -> int:
	return (maxi(1, round_number) - 1) % ROUNDS_PER_YEAR

## "2000 · 1. yarı" gibi okunur dönem etiketi.
static func period_label(round_number: int) -> String:
	return "%d %s" % [year_of_round(round_number),
		L.t("1. yarı") if half_of_round(round_number) == 0 else L.t("2. yarı")]

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
